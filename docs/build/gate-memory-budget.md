# Gate memory and process budget

Status: the Taskfile applies the "one gate scope" rows (see "Applied: one gate scope"
below) and the per-child rows (see "Applied: one cap per child"). The other rows are a
proposal: the tickets that add the slice file and the concurrency bound apply them.

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
    let r = process_run(env.args().get(0).unwrap(), [])
    assert_eq(r.exit_code, 0)
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

| Knob | Where | Value |
|---|---|---|
| Taskfile `JOBS` | `scripts/default_jobs.sh` | half the CPUs, or all CPUs that a quota gives: 12 |
| `CORPUS_JOBS` | `scripts/corpus.sh` | default `JOBS`: 12 |
| `BLINK_JOBS` per corpus row | `scripts/corpus.sh` | `nproc / CORPUS_JOBS`: 1 in the slice |
| `blink test --parallel` | Taskfile `test` | `JOBS`: 12 (CLI default 4) |
| `BLINK_JOBS` per `blink test` worker | Taskfile `__test` | `nproc / JOBS`, at least 1: 1 in the slice (the CLI alone uses `nproc`) |
| `parallel -j` in the fmt stage | Taskfile `__fmt-goldens` | `JOBS`: 12 |
| `GC_MARKERS` | `corpus.sh`, `__fmt-goldens`, `__test` | 1 (the CLI alone does not set it, so Boehm starts one marker per CPU) |

The products:

- `task ci` runs the corpus (12 workers) at the same time as the fmt goldens (12 workers),
  the warning gate, the ratchet and the gate self-tests. That is about 25 workers.
- `blink test --parallel 12` lets each worker run a per-module build with up to `nproc`
  `cc` processes: 12 x 12 = 144 in the slice, 12 x 24 = 288 outside it.
- Each test binary that `blink test` runs gets one GC marker thread per CPU.
- Two gates in two worktrees at the same time double all of this. The slice holds the sum
  only when both run in it.

## Proposed budget

| Limit | Value | Reason |
|---|---|---|
| Slice `MemoryHigh` | 16G | Highest anon + shmem was 4.2 GiB for one gate. 16G holds three gates at once. Above it, the kernel reclaims the page cache of the gates first. Today it is 20G. |
| Slice `MemoryMax` | 24G (no change) | 61 GB RAM less about 20 GB for the desktop and sessions, and room for a large app such as the game (22 GB). |
| Slice `MemorySwapMax` | 2G | On 2026-10-25 the swap was full. Gate work that does not fit must fail, not push the sessions to swap. |
| Slice `TasksMax` | 4096 | Highest `pids.peak` for one gate was 315. 4096 holds about four gates at three times that. A self-spawn chain stops at about 1.8 GiB. |
| Slice OOM score | `OOMScoreAdjust=500` for the gate processes | The kernel kills gate work before a session (sessions run at 200). |
| One gate scope `MemoryMax` | 12G | 2.9 times the highest anon + shmem (4.2 GiB). The page cache above this is reclaimed, not killed. Replaces the fmt scope `MemoryMax=50G`. |
| One gate scope `TasksMax` | 1024 | 3.3 times the highest `pids.peak` (315). |
| One gate scope `MemorySwapMax` | 2G (applied) | A fresh machine has no slice swap cap, and the plain-scope fallback has no slice. With no swap cap, a runaway gate pages out to a disk swap for minutes before the memory cap kills it, as on 2026-10-25. |
| Per child (one test binary or one corpus row) `MemoryMax` | 2G | 4 times the largest single process (500 MB). One runaway child dies alone. |
| Per child `TasksMax` | 256 | Holds a per-module build at `BLINK_JOBS=24` plus GC marker threads. Stops a self-spawn chain at about 115 MB. |
| Per child run timeout | 600 s | Same as the corpus `CORPUS_RUN_TIMEOUT`. Before the per-child caps, the fmt semantic stage had none. |
| `BLINK_JOBS` for `blink test --parallel N` workers | `nproc / N`, at least 1 | Holds the `cc` count near the CPU count, as `corpus.sh` does. |
| `GC_MARKERS` for test binaries | 1 | Same as the corpus and fmt stages. |

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
| systemd user scope, no `blink-gates.slice` unit | the same scope in the default user slice | one line |
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
systemd stops it at the first OOM kill and the report goes with it.

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

The gate's fork count is shared, so a sibling may own those failures; only a child that
failed gets that line. When the child's swap cap cannot be set, a notice says that only
the gate's swap cap holds it.

The time limit sends `SIGTERM`, then `SIGKILL` after `BLINK_CHILD_KILL_AFTER` seconds. Exit
124 or 137 names the time limit only when the time is spent, so a child that exits 124
itself, an OOM kill or a crash does not read as a time limit. A crash with no cap hit
gives no line, and bash adds no "Segmentation fault" job line to the child's stderr. A child that the OOM killer
hits below its own cap gets a line that says the gate or the machine ran out, not the
child. The script then kills each process that the child left in its cgroup and removes
the cgroup.

A `SIGHUP`, `SIGINT` or `SIGTERM` to the script, for example Ctrl-C at a terminal, kills
the child's cgroup (or the child's process group outside a cgroup) at once, removes the
cgroup, and exits 129, 130 or 143. The `timeout` command runs in a process group of its
own, so without this the child would run on to its time limit.

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
`blink test` starts do not go through `scripts/capped.sh`, so they get no per-child caps,
only the gate's.

Settings:

| Variable | Default | Effect |
|---|---|---|
| `BLINK_CHILD_CAP` | `1` | `0` runs each child in place, with no memory or process cap; the time limit stays |
| `BLINK_CHILD_MEMORY_MAX` | `2G` | the child's `memory.max`, or its address space for `prlimit` and `ulimit`; `infinity` sets none |
| `BLINK_CHILD_TASKS_MAX` | `256` | the child's `pids.max`; `infinity` sets none |
| `BLINK_CHILD_SWAP_MAX` | unset | the child's `memory.swap.max`; unset leaves swap to the gate scope (2G) |
| `BLINK_CHILD_TIMEOUT` | `600` | seconds before the time limit kills the child; `0` turns it off; `--timeout` sets it for one call, so it acts on the fmt stages only: a corpus row takes `CORPUS_*_TIMEOUT` |
| `BLINK_CHILD_KILL_AFTER` | `10` | seconds between `SIGTERM` and `SIGKILL` at the time limit |

The corpus stamp (`scripts/ci_corpus_stamp.sh`) includes these variables, except
`BLINK_CHILD_TIMEOUT`, which reaches no corpus row. So a sweep that passed under other
caps does not let `task ci` skip the next sweep.

`scripts/test_capped_child.sh`, in the gate self-tests, proves with caps of 64M, 64 tasks
and 2 s that a memory hog, a fork loop and a sleep each fail with one line that names the
limit, that a crash and a plain failure name no limit, and that a pass still passes. It
also proves the report file, a fork refused at the gate's cap, `infinity`, the signal
stop, and that a child OOM while the gate reclaims page cache names no gate cap.
`scripts/test_corpus.sh` and `scripts/test_fmt_semantic.sh` prove that a corpus row and an
fmt file fail with that line as their reason.

## Benchmarks in the slice

`task bench` and `task ci-profile` run in the slice too, so the slice's CPU quota holds
over them, and a gate that runs at the same time shifts their timings. Time them while no
other gate runs. The capped run does not cap `task bench-edit-loop`: it waits for an empty
slice before it starts, and a gate scope of its own would keep the slice busy. With no
`blink-gates.slice` unit, gate scopes go to the default user slice, and this wait does not
see them.
