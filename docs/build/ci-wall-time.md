# Where `task ci` spends its wall time

All numbers come from `task ci` under blink-gates.slice (12 cores), with the slice empty and the
1-minute load below 3 at the start. Times are seconds from the start of the run.

## The critical path

Taskfile deps run in parallel, so the wall is the longest chain, not the sum of the steps.

| Step | Before (20d86b8d) | After |
|---|---|---|
| gen0 emits blinkc.c and cli.c | 0 - 1.9 | 0 - 1.9 |
| cc links gen1 (cli.c is 11 MB, one C unit) | 1.9 - 13.3 | 1.9 - 7.7 |
| gen1 builds its own stdlib archive (one core) | 13.3 - 15.7 | 7.7 - 10.3 |
| gate self-tests, beside gen1 | 0 - 10.3 | 0 - 13.7 |
| formatter goldens | 118.8 - 122.9 | 10.3 - 14.8 |
| corpus builds the compiler archive (one cc, one core) | 15.7 - 19.5 | 10.3 - 15.2 |
| corpus sweep (12 workers, about 1120 CPU-seconds) | 19.5 - 118.6 | 15.2 - 113.7 |
| corpus-check, slice check, suites-in-corpus | 118.6 - 118.8 | 113.7 - 113.9 |

The sweep is the largest part, and it keeps all 12 cores busy. A cut in the sweep has to remove
CPU work: 12 CPU-seconds give one second of wall. Before the sweep, one core did the work and the
others were idle, so the cuts went there:

1. gen1 links with link-time optimization at the same `-O1` (scripts/gen1.sh). cc splits the
   one C unit into partitions and optimizes them at the same time. The cli.c link took 10.7 s
   alone and now takes about 3.9 s. The corpus CPU time did not go up, so gen1 is not slower. A
   cc that does not accept the flag links as before.
2. ci starts the corpus when gen1 is built. It does not wait for the gate self-tests, because
   the corpus reads nothing that they write.
3. The formatter goldens run beside the corpus, while one core builds the compiler archive. They
   do not run after the sweep. Under blink-gates.slice they now run in the slice. Before, their
   own `systemd-run --scope` moved them out of the slice and its CPU cap.

A failing self-test or formatter golden still fails ci, and fails it at once: the two ci tasks
that hold the corpus set `failfast`. task then sends INT to scripts/corpus.sh and kills it 2 s
later. corpus.sh runs each heavy step in the background, so its handler runs at once. The
handler stops every process under those steps, and every process whose working dir is in
build/corpus/work (a daemon that a row starts leaves the process tree). Then it kills them. With
a self-test that fails at 25 s, ci exits at 25.2 s, and no corpus process is left.

### Link-time optimization: cores, memory, and who gets it

Each link runs `-flto=<default_jobs>`. scripts/default_jobs.sh gives the slice CPU cap under a
slice (12 here), and half of nproc outside one. The blinkc and cli links run at the same time,
so up to 24 jobs run for about 4 s, and the slice holds their CPU to its 12 cores. Both links
together peak at 640 MiB (memory.peak of their scope); one cc process peaks at 340 MB (cli) and
287 MB (blinkc).

| Links | Wall of both, alone in the slice | gen1 built, in ci |
|---|---|---|
| 12 + 12 jobs | 3.8 s | 7.6 s |
| 4 + 8 jobs (12 in all) | 4.0 s | 9.4 s |
| no link-time optimization | 10.7 s (cli alone) | 13.3 s |

In ci the gate self-tests run on the same cores, so a split count gives the links a smaller
share. The 12 + 12 links make byte-equal binaries to the 4 + 8 links.

Only scripts/gen1.sh links this way, so only build/gen1 changes: the gate compiler of `task ci`,
`task corpus`, `task corpus-per-module` (and so `task ci-release`), the rewrite suite, and the
default binary of scripts/bench_edit_loop.sh. `task regen`, `task build-cli`, `task
build-binaries` and `task release` link with bootstrap/bootstrap.sh and scripts/link_opt.sh, and
do not change. gen1 with and without it emits byte-equal C for src/cli.bl, src/blinkc_main.bl
and 20 corpus files.

## Median of 3, alternating runs

| Commit | Runs | Median |
|---|---|---|
| 20d86b8d (base) | 122.59, 122.77, 122.94 | 122.77 |
| after the cuts | 113.86, 114.03, 114.33, 114.57 | 114.18 |

## What grew since the 117.6 s baseline

At 8b877a81 the sweep took 90 s (2059 files, 156 slice rows, 1013 CPU-seconds). At 20d86b8d it
takes 99 s (2136 files, 184 slice rows, 1125 CPU-seconds). The 77 files and 28 slice rows added
since then account for 129.6 row-seconds, or about 10.8 s at 12 workers. The largest rows are
the daemon tests (test_daemon_builds_cold_for_a_same_size_compiler_with_the_same_mtime 13.5 s,
test_daemon_builds_cold_for_a_client_with_another_environment_or_compiler 7.5 s) and
test_mono_per_module_emit_runs (14.5 s, plus 19.5 s for its per-module slice row).
