# Gate memory and process budget

Status: proposal. The tickets that add the slice file, the default cgroup wrapper, the
per-child caps and the concurrency bound apply these numbers. This page does not change
any limit.

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
14.7 GB. The fmt stage starts its own scope with `MemoryMax=50G` when it is not in the
slice. That cap is more than the free RAM, so the global OOM killer ran before the cgroup
limit could. Also, `scripts/run_fmt_semantic.sh` runs each test binary with no timeout.

## Knobs and how they multiply

| Knob | Where | Value |
|---|---|---|
| Taskfile `JOBS` | `scripts/default_jobs.sh` | half the CPUs, or all CPUs that a quota gives: 12 |
| `CORPUS_JOBS` | `scripts/corpus.sh` | default `JOBS`: 12 |
| `BLINK_JOBS` per corpus row | `scripts/corpus.sh` | `nproc / CORPUS_JOBS`: 1 in the slice |
| `blink test --parallel` | Taskfile `test` | `JOBS`: 12 (CLI default 4) |
| `BLINK_JOBS` per `blink test` worker | `build_fs.cpu_count()` | `nproc`: 12 in the slice, 24 outside |
| `parallel -j` in the fmt stage | Taskfile `__fmt-goldens` | `JOBS`: 12 |
| `GC_MARKERS` | `corpus.sh`, `__fmt-goldens` | 1; `blink test` does not set it, so Boehm starts one marker per CPU |

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
| Per child (one test binary or one corpus row) `MemoryMax` | 2G | 4 times the largest single process (500 MB). One runaway child dies alone. |
| Per child `TasksMax` | 256 | Holds a per-module build at `BLINK_JOBS=24` plus GC marker threads. Stops a self-spawn chain at about 115 MB. |
| Per child run timeout | 600 s | Same as the corpus `CORPUS_RUN_TIMEOUT`. The fmt semantic stage has none today. |
| `BLINK_JOBS` for `blink test --parallel N` workers | `nproc / N`, at least 1 | Holds the `cc` count near the CPU count, as `corpus.sh` does. |
| `GC_MARKERS` for test binaries | 1 | Same as the corpus and fmt stages. |

These numbers come from one machine and one commit. Measure again when a gate adds a
stage or when its `pids.peak` or anon + shmem doubles.
