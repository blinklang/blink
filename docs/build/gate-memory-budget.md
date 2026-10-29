# Gate memory and process budget

Status: the Taskfile applies the "one gate scope" rows (see "Applied: one gate scope"
below), the per-child rows (see "Applied: one cap per child") and the worker budget (see
"Knobs and how they multiply"). `scripts/install-gate-slice.sh` installs the slice rows
(see "Applied: the slice").

## Why

On 2026-10-25 a gate run filled the RAM (61 GB) and the swap (16 GB). The kernel then
killed seven Claude sessions, plasmashell and other programs that did not cause the
problem. Gate work must die first, and alone.

## How we measured

Each task ran alone, on commit 441a9802, in a new worktree with only `build/gen0` seeded,
in this scope:

```
systemd-run --user --scope --slice=blink-gates.slice -p TasksMax=8192 -q bash -c '<task>'
```

After the task, we read `memory.peak` and `pids.peak` of the scope cgroup. A loop read
`anon + shmem` from `memory.stat` each 0.5 s, because `memory.peak` also counts the page
cache. The page cache is the build files the task writes; the kernel can reclaim it. No
run hit `memory.high`, `memory.max` or `pids.max`.

Under the slice, `nproc` gives 12, because coreutils reads the slice CPU quota (1200%).
Thus `scripts/default_jobs.sh` gives 12 inside the slice, and 24 / 2 = 12 outside. The
default knobs and `CORPUS_JOBS=12` are the same, so the two `ci` and `corpus` rows show the
spread between two equal runs. `CORPUS_JOBS` changes only `scripts/corpus.sh`.

## Results

| Task | Wall | memory.peak | anon + shmem | pids.peak | Result |
|---|---|---|---|---|---|
| `task gen1` | 11 s | 0.75 GiB | - | 78 | pass |
| `task ci` (cold, default) | 225 s | 2.87 GiB | - | 265 | pass |
| `task ci` (cold, CORPUS_JOBS=12) | 223 s | 3.59 GiB | - | 224 | pass |
| `task corpus` (default) | 192 s | 3.59 GiB | - | 212 | pass |
| `task corpus` (CORPUS_JOBS=12) | 190 s | 3.58 GiB | - | 209 | pass |
| `task build-cli` | 39 s | 0.52 GiB | 0.49 GiB | 46 | pass |
| `task test` (`blink test tests/ --parallel 12`) | 1646 s | 12.71 GiB | 2.03 GiB | 315 | 1 build error, see below |
| `task test-fmt` (golden, idempotent, semantic) | 797 s | 4.31 GiB | 4.12 GiB | 243 | pass |
| `task regen` | 36 s | 0.49 GiB | 0.45 GiB | 47 | pass |
| `task ci-release` | 3175 s | 12.17 GiB | 4.20 GiB | 255 | pass |

`task test` is the `blink test --parallel` mode, so it has no row of its own. Its one
build error is a compiler bug that this work found: a per-module build stops when a
multi-byte character in a C unit crosses byte 4096. It is not a memory problem.

`pids.peak` counts threads as well as processes.

The largest single process in a corpus run was `cc1` at about 500 MB RSS. Next were a
`blink daemon` test (400 MB) and `blink build src/cli.bl` (300 MB).

## The cause on 2026-10-25

The kernel log lists 1907 `test_fmt_expr_u` processes with sequential PIDs, each about
0.5 MB RSS. The kernel stacks (770 MB) show about 48,000 tasks in total. The name is
`tests/test_fmt_expr_unknown_kind_aborts.bl`, cut to 15 characters.

That test ran its own binary as a child to reach `main`. The change "Only a test build
keeps test blocks" (committed later that night) made a test binary run its tests and
never `main`. Before that commit fixed the four tests that did this, each child ran the
test again and started one more child. Each process waits for its child, so the chain
never ends by itself. The fix in the tree is `compile_test_helpers.main_binary_of`, which
makes a plain build for the child. No test in the tree now runs its own binary.

The defect is fixed, so we did not file a bug. The class of fault stays: any test can
start itself or a loop of children. This repro shows how fast it grows:

```
test "a test that runs its own binary as a child" {
    let r = process.run(env.args().get(0).unwrap(), [])?
    assert(r.success())
}
```

In a scope with `TasksMax=2000`, the chain reached 2000 processes in 1.8 s with 0.91 GiB,
then fork failed and the run ended. With `TasksMax=64` it ended in 1 s. Without a task cap
it grows at about 1100 processes per second until the RAM is full.

Other memory users made the OOM worse on that day: a game used 22 GB and tmpfs held
14.7 GB. The fmt stage then started its own scope with `MemoryMax=50G` when it was not in
the slice. That cap is more than the free RAM, so the global OOM killer ran before the
cgroup limit could. The gate scope below replaces it. Also, `scripts/run_fmt_semantic.sh`
ran each test binary with no timeout; the per-child caps below now give it one.

## Knobs and how they multiply

A gate has one worker budget, B. `scripts/default_jobs.sh` gives it, and it is the only
gate script that reads the CPU count:

```
C = CPUs the gate may use: nproc when a quota or an affinity mask holds the gate below
    nproc --all (as in the slice), else nproc / 2
M = BLINK_GATE_MEMORY_MAX / BLINK_GATE_WORKER_MEMORY   (12G / 1G = 12)
B = max(1, min(C, M))
```

On this machine B is 12 in the slice (C = 12, M = 12) and outside it (C = 24 / 2). On a
machine with 64 open CPUs, C is 32 and M holds B to 12, so the gate does not run 32
workers into its 12G cap.

Each fan-out takes its workers from B, and `scripts/inner_jobs.sh <workers>` gives each
worker max(1, B / workers) for the processes it starts. So workers x inner is at most B,
or the worker count when a caller sets more workers than B.

| Knob | Where | Value |
|---|---|---|
| Taskfile `JOBS` | `scripts/default_jobs.sh` | B: 12 |
| `CORPUS_JOBS` | `scripts/corpus.sh` | `JOBS`: 12 |
| `BLINK_JOBS` for every corpus row | `scripts/corpus.sh` | `inner_jobs.sh CORPUS_JOBS`: 1 |
| `blink test --parallel` | Taskfile `__test`, `__ci-monolith`, `__ci-profile` | `JOBS`: 12 (CLI default 4) |
| `BLINK_JOBS` for each `blink test` worker | Taskfile `__test`, `__ci-monolith`, `__ci-profile` | `inner_jobs.sh JOBS`: 1 (the CLI alone uses `nproc`) |
| `parallel -j` in the fmt stage | Taskfile `__fmt-goldens`, `__ci-profile` | `JOBS`: 12 |
| `BLINK_JOBS` for each fmt worker | Taskfile `__fmt-goldens`, `__ci-profile` | `inner_jobs.sh JOBS`: 1 |
| `GC_MARKERS` | `corpus.sh`, `__fmt-goldens`, `__test`, `__ci-monolith`, `__ci-profile` | 1 (the CLI alone does not set it, so Boehm starts one marker per CPU) |
| `cc -flto` jobs for each gen1 link | `scripts/gen1.sh` | B; the two links run at once, 2B for about 10 s |
| ratchet commit walk | `scripts/lint_codegen.sh` | B subshells |

A caller's `JOBS`, `CORPUS_JOBS` or `GC_MARKERS` wins over the default. A caller's
`BLINK_JOBS` can make each worker's share smaller but not larger, as a `BLINK_JOBS` left
in a login shell would otherwise multiply every fan-out again. To give each worker more
cc, run fewer workers.

`default_jobs.sh` reads sizes in K, M, G or T. systemd also takes a size such as `4.5G`
or `50%` for the cap; `default_jobs.sh` then says on stderr that B has no memory limit.

Settings:

| Variable | Default | Effect |
|---|---|---|
| `BLINK_GATE_WORKER_MEMORY` | `1G` | memory to allow for each worker: 2 times the largest single process (500 MB, see "Results"). `infinity` drops the memory limit from B |
| `BLINK_GATE_MEMORY_MAX` | `12G` | the gate's cap (see "Applied: one gate scope"); B reads it too |

`BLINK_JOBS` matters for every row, not only a per-module one: many tests run their own
per-module `blink build`, which starts `BLINK_JOBS` cc at once, or one per CPU when it is
not set. Before the budget, a corpus sweep or an fmt semantic pass could run 12 workers x
12 cc in the slice (12 x 24 outside it).

Where stages run at once, their workers add:

- `task ci` first runs gen1 (two links, 2B for about 10 s) beside the ratchet's commit walk
  (B) and the gate self-tests (about 15 processes): about 3B at the peak.
- Then it starts the corpus (B workers) beside the fmt goldens (B workers) and the warning
  gate (two `blink check` processes, each with one Boehm marker per CPU). At most this is
  2B + 2 processes. In practice the two fan-outs do not overlap: the corpus first builds
  its compiler archive on one core, and the goldens end before its workers start.
- Two gates in two worktrees at the same time double all of this. The slice holds the sum
  only when both run in it.

We measured the overlap on 2026-10-27 (commit b96ac30a, `CORPUS_JOBS=12`, no other gate in
the slice), with a sample of the gate scope each 0.1 s. `task ci` took 226 s. The fmt
goldens ran for 9.3 s, 4.6% of the 202 s that the corpus workers ran, and the gate used at
most 0.9 GiB in that time. No sample had both fan-outs live. The gate peak was 3.9 GiB
(anon + shmem 3.5 GiB), at 39 s, in the corpus alone. Thus the corpus and the goldens each
keep B. Split B between them if the goldens come to overlap more than 20% of the corpus
time, or the gate peak during the overlap goes past 8G. Measure again, and change
`BLINK_GATE_WORKER_MEMORY`, if the largest single process grows past 500 MB.

`scripts/test_gate_budget.sh`, in the gate self-tests, runs `default_jobs.sh` and
`inner_jobs.sh` with a fake `nproc` of 1, 4, 12 and 64 CPUs, with and without a quota,
under several memory sizes, and proves that B is min(C, M) and that workers x inner stays
within the budget, that each worker gets exactly max(1, B / workers), and that a caller's
`BLINK_JOBS` only lowers the share. It also fails when another gate script reads the CPU
count, and when a fan-out line in a Taskfile task (`parallel -j`, `--parallel`,
`xargs -P`) sets no `GC_MARKERS` or `BLINK_JOBS`, on the line or by an export earlier in
the task. `scripts/test_corpus.sh` proves that a row's test binary gets the share and one
marker in each corpus mode, also when the caller sets a larger `BLINK_JOBS`.

## Budget

The slice values are for this 64G machine with 24 CPUs; "Applied: the slice" gives the
rule that sizes them for another machine. A machine has these values only after it runs
`scripts/install-gate-slice.sh` and removes the drop-ins that override the unit. On
2026-10-27 this machine still had the older `set-property` drop-ins (`MemoryHigh=20G`,
`MemoryMax=24G`, `CPUQuota=1200%`), and `systemd-oomd` did not run.

| Limit | Value | Reason |
|---|---|---|
| Slice `CPUQuota` | 1200% | Half the CPUs, as a gate outside the slice gets (see "Knobs and how they multiply"). |
| Slice `MemoryHigh` | 15789M (15.4 GiB) | Highest anon + shmem was 4.2 GiB for one gate. This holds three gates at once. Above it, the kernel reclaims the page cache of the gates first. |
| Slice `MemoryMax` | 23683M (23.1 GiB) | 61.7 GiB RAM less about 20 GB for the desktop and sessions, and room for a large app such as the game (22 GB). |
| Slice `MemorySwapMax` | 2G | On 2026-10-25 the swap was full. Gate work that does not fit must fail, not push the sessions to swap. |
| Slice `TasksMax` | 4096 | Highest `pids.peak` for one gate was 315. 4096 holds about four gates at three times that. A self-spawn chain stops at about 1.8 GiB. |
| Slice `ManagedOOMMemoryPressure`, `ManagedOOMSwap` | `kill` | When `systemd-oomd` runs, it kills a gate scope under memory pressure or when the swap fills, before the kernel's OOM killer starts. |
| OOM score of the gate processes | 500 above the caller's (at most 1000), set by `scripts/capped.sh` | The kernel's OOM killer picks gate work before a session (sessions run at 200, so their gates run at 700). |
| One gate scope `MemoryMax` | 12G | 2.9 times the highest anon + shmem (4.2 GiB). The page cache above this is reclaimed, not killed. Replaces the fmt scope `MemoryMax=50G`. |
| One gate scope `TasksMax` | 1024 | 3.3 times the highest `pids.peak` (315). |
| One gate scope `MemorySwapMax` | 2G (applied) | A fresh machine has no slice swap cap, and the plain-scope fallback has no slice. With no swap cap, a runaway gate pages out to a disk swap for minutes before the memory cap kills it, as on 2026-10-25. |
| Per child (one test binary or one corpus row) `MemoryMax` | 2G | 4 times the largest single process (500 MB). One runaway child dies alone. |
| Per child `TasksMax` | 256 | Holds a per-module build at `BLINK_JOBS=24` plus GC marker threads. Stops a self-spawn chain at about 115 MB. |
| Per child run timeout | 600 s | Same as the corpus `CORPUS_RUN_TIMEOUT`. Before the per-child caps, the fmt semantic stage had none. |
| `BLINK_JOBS` for `blink test --parallel N` workers | B / N, at least 1 (applied) | Holds the `cc` count to the worker budget, as `corpus.sh` does. |
| `GC_MARKERS` for test binaries | 1 (applied) | Same as the corpus and fmt stages. |

These numbers come from one machine and one commit. Measure again when a gate adds a
stage or when its `pids.peak` or anon + shmem doubles.

## Applied: one gate scope

`scripts/capped.sh` applies the three "one gate scope" rows. Each heavy Taskfile task
re-runs itself through it: `bootstrap`, `regen`, `gen0`, `gen1`, `build-cli`, `build`,
`compile-test`, `test`, `test-fmt`, `test-installed`, `test-sqlite-peel`, `fuzz`,
`bench`, `build-binaries`, `ci`, `ci-fast`, `ci-release`, `ci-monolith`,
`ci-per-module-checks`, `ci-profile`, `corpus`, `corpus-per-module`, `corpus-sample`,
`corpus-only`, `warning-gate`, `typecheck-suite` and `rewrite-suite`. The task `<name>`
holds only the re-run; its steps are in the internal task `__<name>`.
`test-bootstrap-cold` has no re-run: its one heavy step is its `build-cli` dep, which caps
itself, and the rest is one `nm`.

The capped run sets `BLINK_GATE_SCOPE`. A task that finds it set calls its body in
place, so `task ci` gets one scope for the whole gate, and its nested tasks do not stack
scopes or run again. The two fmt scopes with `MemoryMax=50G` are gone: the fmt stage runs
in the gate's scope.

The first way that works caps the run:

| Machine | Cap | Notice |
|---|---|---|
| systemd user scope, slice has a unit | scope `blink-gate-<task>-<pid>-<time>.scope` in `blink-gates.slice`, `MemoryMax=12G`, `MemorySwapMax=2G`, `TasksMax=1024` | none |
| systemd user scope, no `blink-gates.slice` unit | the same scope in the default user slice | one line, with the install command |
| systemd user scope, `BLINK_GATE_SLICE` names a unit that cannot hold a scope | the same scope in the default user slice | one line |
| no systemd user scope, `prlimit` | address space 12G per process, user processes = running + 1024 | one line |
| no `prlimit` | `ulimit -v` and `ulimit -u`, the same limits; no `ulimit -v` on Darwin, which does not hold a process to it | one line |
| none of these work | no cap; the task still runs | one line |

The scope sits in the slice even when the caller already does, for example a run that a
person starts with `systemd-run --user --scope --slice=blink-gates.slice task ci`. That
caller's scope has no memory or task cap of its own, so being in the slice does not prove
a cap. The new scope is a second child of the slice, so the slice's CPU and memory limits
still hold over it, and its own caps hold over the gate. The old fmt scope left the slice
only because it had no `--slice`.

`prlimit` and `ulimit` are weaker. The address space cap is per process, not per run.
`RLIMIT_NPROC` counts every process and thread of the user (on BSD and macOS, every
process), so the cap is the count at the start plus 1024. Programs of the same user that
start during the run use up the same margin, and a fork that fails there gets no report.

When the scope's run ends, the script reads the scope's `memory.events` and
`pids.events` and prints one line per cap the run hit, for example:

```
capped.sh: the run hit its memory cap (MemoryMax=12G) and the OOM killer killed 1 of its processes; exit 137
capped.sh: the run hit its process cap (TasksMax=1024): 7 forks failed; exit 254
```

The memory line reads the scope's own `memory.events.local`, so a child that dies at its
own cap does not make the run's line. When the run's cap kills processes of the run itself
while children have caps of their own, the line counts only the run's processes, and a
child that the run's OOM killed gets its own line. An OOM kill below the run's cap gives a
line that says the slice or the machine ran out.

It then ends the processes still in the scope. The scope has `OOMPolicy=continue`, else
systemd stops it at the first OOM kill and the report goes with it. The command runs
with an `oom_score_adj` 500 above the script's (at most 1000). At the cap, the kernel can
kill a second process before the memory of the first is free; the higher score makes it
kill a process of the command, not the script that writes the report.

Settings:

| Variable | Default | Effect |
|---|---|---|
| `BLINK_GATE_CAP` | `1` | `0` runs every task in place, uncapped, with one notice. For a machine that caps gates some other way. |
| `BLINK_GATE_MEMORY_MAX` | `12G` | the scope's `MemoryMax` |
| `BLINK_GATE_TASKS_MAX` | `1024` | the scope's `TasksMax` |
| `BLINK_GATE_SWAP_MAX` | `2G` | the scope's `MemorySwapMax`; `infinity` leaves swap to the slice |
| `BLINK_GATE_SLICE` | `blink-gates.slice` | the slice that holds the scope |

`scripts/test_capped.sh`, in `task ci`'s gate self-tests, proves each path with caps of
64M and 64 tasks.

The scope has `Delegate=yes`, so the run can make cgroups below it for the per-child caps.
The run moves itself into the leaf `gate/` of the scope, and each capped child gets a
cgroup in `kids/`. The kernel lets only a cgroup with no processes of its own give its
controllers to child cgroups, so the run cannot stay in the scope's own cgroup.

The dispatcher re-runs the task with `--force`, `--silent`, `--verbose`, `-- <args>`,
the vars `BUILD_DIR`, `BLINKC`, `JOBS` and `VERSION` when they differ from their
`DEFAULT_*`, and the vars `FMT_SEMANTIC`, `CORPUS_LINT` and `CORPUS_PM_SLICE` when they
are set, so `task test JOBS=2` runs with `JOBS=2`. A value equal to the default is not
passed on: the body works it out again in the scope, where `JOBS` can differ because
`scripts/default_jobs.sh` reads the CPUs that the slice gives. Task gives
no list of the CLI vars, so a var that the dispatcher does not name is lost, and `--dry`,
`--summary` and `--status` act on the dispatcher. Put the capped run around the call by
hand, for example `scripts/capped.sh task --dry ci`; the task then finds
`BLINK_GATE_SCOPE` set and goes straight to its body. A new var that a person sets on the
command line goes in the dispatcher's list, and a new global var also gets a `DEFAULT_*`.

The dispatcher needs Task 3.47 or later, which reads the `if:` of a command. An older Task
runs both commands; `scripts/capped.sh` then sees a dispatcher inside its own capped run
and stops with one line, not with a loop of re-runs.

## Applied: one cap per child

`scripts/capped.sh --child [--timeout <seconds>] [--report <file>] <command>` runs one
child of a gate under the per-child caps. These calls use it:

- `scripts/corpus_one.sh`: the build of each row (`CORPUS_BUILD_TIMEOUT`, 900 s) and each
  run of its test binary (`CORPUS_RUN_TIMEOUT`, 600 s).
- `scripts/run_fmt_golden.sh`, `run_fmt_idempotent.sh` and `run_fmt_semantic.sh`: each
  formatter call, each `blinkc` and `cc` call, and each run of a test binary.

A program that a child starts, such as the `blink build` that a test starts through
`compile_test_helpers`, stays in the child's cgroup and under its caps.

The first way that works caps each child:

| Machine | Cap | Notice |
|---|---|---|
| the gate run has a scope with `Delegate=yes` | a cgroup `kids/c-<pid>` with `memory.max=2G` and `pids.max=256`, and the time limit | none |
| the gate run has no such scope, `prlimit` | address space 2G per process, and the time limit | one line from the gate run |
| no `prlimit` | `ulimit -v`, the same limit, and the time limit | one line from the gate run |
| Darwin, or `BLINK_CHILD_MEMORY_MAX=infinity` | the time limit only | one line from the gate run |
| no `timeout` or `gtimeout` command | no time limit | one more line from the gate run |

Outside a cgroup a child has no process cap of its own: `RLIMIT_NPROC` counts every
process of the user, so a sibling that starts after a child would use up that child's
share. The gate's process cap still holds. A child outside a cgroup also gets no line for a
memory or process cap, because only a cgroup counts those events; a child that the address
space cap stops fails with its own error.

A call with no gate run around it, for example `scripts/corpus.sh` run by hand, takes the
`prlimit` way and gives the notice itself. A `--child` call inside a child runs in place:
it is already under its parent's caps, and a cgroup of its own would take it out of them.

When the child ends, the script reads its cgroup's `memory.events` and `pids.events`,
prints one line per cap the child hit, and keeps the child's exit code. The first line
names the cap that ended the child:

```
capped.sh: the child hit its memory cap (MemoryMax=2G) and the OOM killer killed 1 of its processes; exit 137
capped.sh: the child hit its process cap (TasksMax=256): 12 forks failed; exit 1
capped.sh: the child ran past its time limit (600s) and was killed; exit 124
capped.sh: the child lost 1 processes to the OOM killer below its memory cap (MemoryMax=2G), so the gate or the machine ran out; exit 137
capped.sh: the gate refused 3 forks at its process cap (TasksMax=1024) while this child ran; exit 254
```

The gate's fork count is shared, so a sibling may own those failures: only a child that
failed gets that line, and it is never the child's reason in the `--report` file. Before
Linux 6.13 the kernel counts a refused fork in the cgroup of the process that forked, not
in the cgroup whose cap refused it, so there the child's line names both caps and the gate
line does not show. When the child's swap cap cannot be set, a notice says that only
the gate's swap cap holds it. A kernel with no swap account has no swap cap file: the gate
then prints one notice, not one for each child.

The time limit sends `SIGTERM`, then `SIGKILL` after `BLINK_CHILD_KILL_AFTER` seconds. Exit
124 or 137 names the time limit only when the time is spent, so a child that exits 124
itself, an OOM kill or a crash does not read as a time limit. A crash with no cap hit
gives no line, and bash adds no "Segmentation fault" job line to the child's stderr. A child that the OOM killer
hits below its own cap gets a line that says the gate or the machine ran out, not the
child. The script then kills each process that the child left in its cgroup and removes
the cgroup.

A `SIGHUP`, `SIGINT` or `SIGTERM` to the script, for example Ctrl-C at a terminal, kills
the child's process group and cgroup at once, removes the cgroup, and then kills the
script with the same signal. The `timeout` command runs in a process group of its own, so
without this the child would run on to its time limit. A shell that runs a loop of
children stops at Ctrl-C only when the child died by the signal, so the script does not
just exit 130.

The child runs in a process group of its own, which stops if it reads the terminal. So a
child whose stdin is a terminal reads `/dev/null`; a pipe or a file stays its stdin.

With `--report <file>`, the script writes the first line to the file when the child
failed, and leaves the file empty otherwise: a child that passed hit no cap that matters
to it. The corpus row and the fmt file fail with that line as their reason: the corpus
row's `first_error_line` is the line, and its status is `timeout` for the time limit. The fmt
scripts print `FAIL (<line>) <name>`. A cap that kills one step of the fmt semantic check
fails the file, because the other verdicts of that check are then not valid.

Why a cgroup per child and not a systemd scope per child: a scope is a unit that systemd
must start and stop, for each of about 2600 corpus rows and several thousand fmt calls per
gate. A new scope would also sit beside the gate scope in the slice, not in it, so the
gate's 12G cap would not hold over it. A cgroup below the delegated gate scope costs one
`mkdir` and a few writes, and the gate's caps still hold over it. `prlimit` alone is weaker: its memory cap is per
process, not per child, and `RLIMIT_NPROC` counts all processes of the user.

`task test` sets `BLINK_JOBS` and `GC_MARKERS` for its workers. The children that
`blink test` starts do not go through `scripts/capped.sh`, so they have only the gate's
cap until `blink test` caps its own children.

Settings:

| Variable | Default | Effect |
|---|---|---|
| `BLINK_CHILD_CAP` | `1` | `0` runs each child in place, with no memory or process cap; the time limit stays |
| `BLINK_CHILD_MEMORY_MAX` | `2G` | the child's `memory.max`, or its address space for `prlimit` and `ulimit`; `infinity` sets none |
| `BLINK_CHILD_TASKS_MAX` | `256` | the child's `pids.max`; `infinity` sets none |
| `BLINK_CHILD_SWAP_MAX` | `0` | the child's `memory.swap.max`; `infinity` leaves swap to the gate scope (2G) |
| `BLINK_CHILD_TIMEOUT` | `600` | seconds before the time limit kills the child; `0` turns it off; `--timeout` sets it for one call, so it acts on the fmt stages only: a corpus row takes `CORPUS_*_TIMEOUT` |
| `BLINK_CHILD_KILL_AFTER` | `10` | seconds between `SIGTERM` and `SIGKILL` at the time limit |

The corpus stamp (`scripts/ci_corpus_stamp.sh`) includes these variables, except
`BLINK_CHILD_TIMEOUT`, which reaches no corpus row. So a sweep that passed under other
caps does not let `task ci` skip the next sweep.

Why no swap per child: a child at its memory cap must die at once and name the cap, not
page out for minutes first. And the gate's children share one swap cap of 2G, so one
child that pages out would leave no swap for the others.

`scripts/test_capped_child.sh`, in the gate self-tests, proves with caps of 64M, 64 tasks
and 2 s that a memory hog, a fork loop and a sleep each fail with one line that names the
limit, that a crash and a plain failure name no limit, and that a pass still passes. It
also proves the report file, a fork refused at the gate's cap, `infinity`, the signal
stop, and that a child OOM while the gate reclaims page cache names no gate cap.
`scripts/test_corpus.sh` and `scripts/test_fmt_semantic.sh` prove that a corpus row and an
fmt file fail with that line as their reason.

## Applied: a command in a cgroup of its own

`blink test --memory <size> --processes <count>` caps each test binary in a cgroup of its
own (sections/06_tooling.md §8.10.7). The Blink runtime can do that only from a cgroup that
holds no process but the program and its descendants (§4.4.8). In a gate run, the leaf
`gate/` also holds the gate's shells and `task`, the ancestors of `blink`, so
`process.can_limit` is false there for both limits, and `blink test` stops with exit 2 when
it gets those flags.

`scripts/capped.sh --own-cgroup <command>` solves that. Inside a gate run with a delegated
scope, it makes `kids/o-<pid>`, moves the command into it alone, and exports
`BLINK_OWN_CGROUP=1` to it. The cgroup has no caps of its own, so the gate's caps hold over
it. When the command ends, the script kills what is left and removes the cgroup and the
cgroups that the command made below it. The exit code passes through, and a signal to the
script ends the command as it does for `--child`. No `timeout` wraps the command: a wrapper
process would sit in the cgroup too.

Where it cannot give that cgroup, the command runs in place without `BLINK_OWN_CGROUP`
(also when the caller's env has it), and one line on stderr says why:

| Case | Line |
|---|---|
| `BLINK_CHILD_CAP=0` | `capped.sh: <cmd> gets no cgroup of its own: BLINK_CHILD_CAP=0` |
| a call inside a `--child` | `...: it runs inside a child, under the child's caps` |
| no gate run, `BLINK_GATE_CAP=0`, no delegated scope (`prlimit`, `ulimit`, Darwin) | `...: no gate run with a delegated systemd scope holds it` |
| a call that is not in the gate's leaf | `...: it does not run in the gate's own cgroup` |
| the `mkdir` or the move fails | `...: could not make <dir>` or `...: could not move it into <dir>` |

`BLINK_CHILD_CAP=0` turns `--own-cgroup` off too, as it turns off every per-child cap:
then `blink test` gets no memory or process cap for its test binaries, only its timeout.

`scripts/test_capped_child.sh` proves that the command is alone in a cgroup with the
`memory` and `pids` controllers and no caps of its own, that the cgroup tree goes when the
command ends, that the exit code passes through, and each in-place case above but the
last two.

## Applied: the slice

`scripts/systemd/blink-gates.slice` is the unit, and `scripts/install-gate-slice.sh`
installs it in the systemd user unit dir, `${XDG_CONFIG_HOME:-~/.config}/systemd/user`:

```
scripts/install-gate-slice.sh --dry-run   # print the unit, change nothing
scripts/install-gate-slice.sh             # write the unit, reload the user manager
```

The script needs no `sudo`. It reloads the user manager when the unit changed or when the
manager has not loaded it (a reload that failed on an earlier run), so a second run
changes nothing. After the reload, it checks that the manager reads the unit from the
same dir; when the shell and the manager have a different `XDG_CONFIG_HOME`, it says so
and exits 1. With no systemd, as on Darwin, or with no user manager in the session, it
prints one line and exits 0. Until the slice is installed, each capped gate run prints one
line that names the script, and the gate still runs.

The script fills in the values that depend on the machine:

| Value | Rule | 24 CPUs, 61.7 GiB | 8 CPUs, 15.5 GiB |
|---|---|---|---|
| `CPUQuota` | half the CPUs (`nproc --all`), at least one | 1200% | 400% |
| `MemoryHigh` | a quarter of the RAM | 15789M | 3965M |
| `MemoryMax` | three eighths of the RAM | 23683M | 5947M |

The RAM is `MemTotal`, which is a little less than the RAM (61.7 GiB on a 64G machine), so
the caps are always below the RAM. A value is in G when it is a whole number of GiB, else
in M. `MemorySwapMax`, `TasksMax` and the `ManagedOOM` rows are the same on each machine.
`BLINK_SLICE_CPUS` and `BLINK_SLICE_MEMTOTAL_KIB` set the CPU count and the RAM in KiB, to
size the slice for another machine.

On a machine with less than 32G, `MemoryMax` is less than one gate's 12G cap, so the slice
cap fires first. It still holds the gate away from the rest of the machine. On a 16G
machine, `MemoryHigh` (about 3.9 GiB) is less than the 4.2 GiB that one gate needs at its
peak, so the kernel slows the gate down to reclaim its memory. The gate still passes, but
more slowly.

The OOM score is not in the unit: `OOMScoreAdjust` is a setting of a process that systemd
starts (a service), and a slice or a scope has no such setting. systemd says
`Unknown key 'OOMScoreAdjust' in section [Slice], ignoring`. So `scripts/capped.sh` sets
the score on the command that it runs (see "Applied: one gate scope"), and each process of
the gate gets it.

The unit sets no `ManagedOOMPreference`. That setting keeps a unit from being chosen, and
the gates must be chosen. The `ManagedOOM` rows do nothing while `systemd-oomd` does not
run; the kernel's OOM killer then uses the OOM score.

`systemctl --user set-property blink-gates.slice ...` writes drop-ins to
`~/.config/systemd/user.control/blink-gates.slice.d/` (or below `/run` with `--runtime`),
and they override the unit. The script asks the manager for each drop-in of the slice,
names each file, and prints the command that removes them all and keeps the unit:
`systemctl --user revert blink-gates.slice`.

`scripts/test_gate_slice.sh`, in the gate self-tests, proves the dry-run values for 1,
8, 24 and 64 CPUs and 1.9, 15.5, 61.7 and 100 GiB of RAM, that a second install changes
nothing, that a failed reload is done on the next run, the `XDG_CONFIG_HOME` check, the
drop-in warning, the no-systemd and no-manager lines, and the one notice of a capped run
with no slice unit. It installs into a temp dir, with a fake `systemctl`.

## Probe dirs

Probe builds go in `scripts/scratch.sh new <name>` and leave by `scripts/scratch.sh clean <name>` when the branch lands; at its end `task ci` runs `scripts/scratch.sh check`, which warns past `BLINK_SCRATCH_WARN` (4G), says when the root is on tmpfs (RAM), and never fails the gate.

## Benchmarks in the slice

`task bench` and `task ci-profile` run in the slice too, so the slice's CPU quota holds
over them, and a gate that runs at the same time shifts their timings. Time them while no
other gate runs. The capped run does not cap `task bench-edit-loop`: it waits for an empty
slice before it starts, and a gate scope of its own would keep the slice busy. With no
`blink-gates.slice` unit, gate scopes go to the default user slice, and this wait does not
see them.
