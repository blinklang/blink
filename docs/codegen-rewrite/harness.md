# Codegen rewrite harness

This page tells you what the rewrite gate does, how to read its output, and
how to add a lint row. The gate is `task ci`. The old full gate is now
`task ci-release`.

## The compilers

- **gen0** is the pinned compiler, built from the tag
  `last-selfhost-before-codegen-rewrite` into `build/gen0/`. Run
  `task gen0` to build it. Every corpus run uses gen0, so the corpus
  measures the source tree and not the compiler that built it.
- **gen1** is the current source compiled by gen0. `task gen1` writes
  `build/gen1/blinkc`. It fails when gen0 exits nonzero or prints an
  `error[` line, because blinkc exits 0 on a type error.

Do not export `BLINK_ROOT` when you run these binaries by hand. Each one
finds its stdlib and archive from its own path.

## The tasks

| Task | What it does | Fails when |
| --- | --- | --- |
| `task ci` | The rewrite gate: `gen1`, `ratchet`, `test-ratchet`, `test-lint`, `corpus`, `corpus-check`, formatter goldens and idempotency with gen1, `typecheck-suite`. | Any step fails. |
| `task gen1` | gen0 compiles `src/blinkc_main.bl` and `src/cli.bl`, then links `build/gen1/blinkc`. | Nonzero exit, an `error[` line, or a link error. |
| `task corpus` | Compiles and runs every `tests/test_*.bl` on its own under gen0. Writes `build/corpus.json`. Then runs the lint. | Never for a test result. Only when the lint fails. |
| `task corpus-check` | Compares `build/corpus.json` with `scripts/corpus_baseline.json` and with the baseline in the previous commit. | The pass count drops, or a file that passed no longer passes. |
| `task corpus-baseline` | Rewrites `scripts/corpus_baseline.json` from `build/corpus.json`. Run it only after a real gain. | Never. |
| `task lint` | Runs `scripts/lint_codegen.sh`, the eleven rows below. | A row rises above its limit, or a row in debt rises above the previous commit. |
| `task test-lint` | Runs `scripts/test_lint_codegen.sh`: each row goes red on a fixture. | A row does not catch its construct. |
| `task ratchet` | Three debt counts over the whole compiler (see below), then the lint. | A count rises, or a zero-gate row is not zero. |
| `task typecheck-suite` | Runs the files in `scripts/typecheck_suite.txt` under gen0. | Any file does not pass. |
| `task ci-release` | The old full gate: self-host regen, `blink test`, per-module invariants, installed smoke. `mono-diff` and `node-tid-diff` are parked: still tasks, no longer in any gate. | Any step fails. |

`mono-diff` and `node-tid-diff` still exist as tasks. Neither gate runs
them.

The formatter step in `task ci` runs the golden and idempotency checks
only. The semantic check compiles and runs every formatted test, and
those binaries call the relative `build/blink`, which only a release
build provides. `task test-fmt` and `task ci-release` run all three.

## How the corpus runs a file

Each file gets its own work directory under `build/corpus/work/<name>/`.
That directory holds links to `tests/`, `src/`, `lib/`, `bootstrap/` and
`blink.toml`, a private `.tmp/`, and a private `build/` whose `blink` and
`blinkc` point at the compiler under test. This is why the corpus can run
in parallel: no two files share an object cache, and a test that calls
the relative path `build/blink` reaches the compiler under test.

The pass rule is the same as `blink test`: build with `--debug`, then run
the binary. A file with `test` blocks and a `fn main(` runs with `--test`.
A file with no `test` blocks runs as a program. `blink test tests/` skips
such files; the corpus does not.

Logs are in `build/corpus/logs/<name>.build.log` and `<name>.run.log`.

A `test.failing` block is a witness for a known bug. The test binary
reports it `ok` when the witness fails and `FAIL` when it passes, so the
corpus records a file as `pass` only when every `test` block passes and
every `test.failing` block still fails. A bug fix that makes a witness
pass therefore shows as `run_fail` until the block becomes a plain `test`.

## How to read corpus.json

The file has a header and one record per test:

```json
{
  "compiler": "build/gen0",
  "blinkc_sha256_prefix": "249d975c5ad34338",
  "git_head": "9a372b49",
  "generated_utc": "2026-09-10T17:00:00Z",
  "wall_seconds": 110,
  "total": 1192, "passed": 1190, "compile_fail": 2, "run_fail": 0, "timeout": 0,
  "files": [
    {"file": "tests/test_x.bl", "status": "pass", "seconds": 1.20, "first_error_line": ""}
  ]
}
```

`status` is one of `pass`, `compile_fail`, `run_fail`, `timeout`.
`first_error_line` is the first diagnostic or failure line from the log,
cut to 300 characters. Useful queries:

```sh
jq -r '.files[] | select(.status != "pass") | "\(.status) \(.file): \(.first_error_line)"' build/corpus.json
jq -r '.files | sort_by(-.seconds) | .[:10][] | "\(.seconds)s \(.file)"' build/corpus.json
```

To rerun a subset, write the file names to a list and run
`scripts/corpus.sh --only <list>`. The result goes to
`build/corpus_subset.json` and does not touch the baseline.

## The lint rows

`scripts/lint_codegen.sh` scans `src/layout.bl`, `src/cname.bl`,
`src/mono.bl`, `src/ir.bl` and `src/cg_*.bl`. A file that does not exist
yet counts as empty. Tests and docs are never scanned.

| Row | Name | Limit | Catches |
| --- | --- | --- | --- |
| L1 | `ct_or_string_types` | 0 | `CT_*`, `type_from_name`, the `tp_*` pool, `sv_tp`, `.ctype`, `.sname` |
| L2 | `sentinel_answers` | 0 | `TYPE_UNKNOWN`, the `if x >= 0 { x } else` fallback, a tid coalesced with `??` |
| L3 | `pub_let_mut_new` | 8 | Mutable module globals in the scanned files |
| L3 | `pub_let_mut_unlisted` | 0 | A mutable global whose name is not in `scripts/lint_pub_let_mut_allow.txt` |
| L4 | `typename_compares` | 0 | A type name compared as a string |
| L5 | `no_infer` | 0 | A call to any `infer_*` function |
| L6 | `layout_outside_layer` | 0 | A C type spelled outside `layout.bl` and `cg_print.bl`; a `TyKind` test inside `cg_print.bl` |
| L7 | `single_producer` | 0 | A name producer defined twice anywhere in `src/`, or missing while its owner file exists |
| L8 | `import_dag` | 0 | An import that goes the wrong way in the layer order |
| L9 | `fn_length` | 0 | A function longer than 80 lines |
| L10 | `br_ids_in_source` | 0 | A br ticket id in source |
| L11 | `untested_pub_fns` | 0 | A `pub fn` in the reading layer or mono that no test names |

Each row has a threshold, a stored baseline (`scripts/lint_codegen_baseline.txt`)
and a previous-commit count. The gate is: `now` must not be above
`max(threshold, baseline)`, and a row above its threshold must not be
above the previous commit. A row under its threshold may grow up to the
threshold. A row above its threshold but not rising shows `DEBT`. This is
how `mono.bl`, which exists today with violations, can be gated without
being rewritten first. `OVER` and `UP` mean the run failed; the matching
lines print under the table.

The ratchet keeps three rows over the whole compiler in
`scripts/ratchet.sh`: `br_ids_in_source` (zero gate), `pub_let_mut` over
the old codegen and mono, and `layout_decline_unhandled` (zero gate: a
`decline_reason` read outside `layout.bl` with no `diag_ice` within the
next three lines).

## How to add a lint row

1. Add the row to the `ROWS` table at the top of `scripts/lint_codegen.sh`:
   `L<n> <name> <threshold>`.
2. In `compute_rows`, write the matching lines to `"$det/<name>.txt"`. Use
   `scan '<perl regex>' "$@"` for a plain grep, or a loop for anything
   more.
3. Prove the row red: put a violation in a throwaway `src/cg_zzz.bl`, run
   the script, and check that the row shows `OVER`. Remove the file.
4. Run `scripts/lint_codegen.sh --update` to add the row to the baseline.
   The previous-commit check does not apply to a row that commit did not
   define, so a new row with a nonzero count does not fail on its first
   commit.
5. Add the row to the table above.

To allow a new mutable global, add a line to
`scripts/lint_pub_let_mut_allow.txt`: the name, then its role. The cap
stays 8.

## When the corpus baseline moves

Run `task corpus`, read the failing list, and confirm the gain is real.
Then run `task corpus-baseline` and commit `scripts/corpus_baseline.json`
in the same commit as the change that earned it. The baseline lives under
`scripts/` because `build/` is ignored as a whole directory and git cannot
re-include a file below it.
