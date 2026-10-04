# Codegen rewrite harness

This page tells you what the rewrite gate does, how to read its output, and
how to add a lint row. The gate is `task ci`. The old full gate is now
`task ci-release`.

## The compilers

- **gen0** is the pinned compiler, built from the tag
  `gen0-rewrite-selfhost-2` into `build/gen0/`. Run
  `task gen0` to build it. It is a fixed binary per pin, so it
  is a reference, never a thing under test.
- **gen1** is the current source compiled by gen0. `task gen1` writes
  `build/gen1/bin/blinkc` and `build/gen1/bin/blink`. It fails when gen0
  exits nonzero or prints an `error[` line, because blinkc exits 0 on a
  type error. **The corpus runs under gen1**: a corpus run against gen0
  would measure gen0 and never move.

Both live in the installed layout (`bin/`, `lib/`, `share/blink/`, plus
top-level symlinks). The layout is load-bearing: `blink` resolves its
install root two directories up from `realpath(argv[0])`, so a flat
`build/gen1/blink` would resolve to `build/` and link whatever archive
sits there.

Do not export `BLINK_ROOT` when you run these binaries by hand. Each one
finds its stdlib and archive from its own path.

`build/gen1/share/blink/` holds gen1's own archive and header: `gen1.sh`
flattens this tree's `bootstrap/runtime_*.h` into `runtime.h`, then runs
gen1's own `blink __build-stdlib-archive` against the current `lib/std`
and repoints `libblink_std.{a,h}`, `skip_modules.txt` and `.archive-id`
at the result. `native/` sidecars still come from gen0 — those are C,
not codegen output. Every gen1 compile therefore mixes gen1-emitted
user C with a gen1-built archive; the link to gen0's archive is cut.

## The tasks

| Task | What it does | Fails when |
| --- | --- | --- |
| `task ci` | The rewrite gate: `gen1`, `ratchet`, `test-ratchet`, `test-lint`, `test-corpus`, `commit-messages`, `test-commit-messages`, `corpus`, `corpus-check`, formatter goldens and idempotency with gen1, `suites-in-corpus`. | Any step fails. |
| `task gen1` | gen0 compiles `src/blinkc_main.bl` and `src/cli.bl`, then links `build/gen1/bin/blinkc` and `build/gen1/bin/blink`. | Nonzero exit, an `error[` line, or a link error. |
| `task corpus` | Compiles and runs every `tests/test_*.bl` on its own under gen1. Writes `build/corpus.json`. Then runs the lint. | Never for a test result. Only when the lint fails. |
| `task corpus-check` | Compares `build/corpus.json` with `scripts/corpus_baseline.json` and with the baseline in the previous commit. | The pass count drops, or a file that passed no longer passes. |
| `task corpus-baseline` | Rewrites `scripts/corpus_baseline.json` from `build/corpus.json`. Run it only after a real gain. | Never. |
| `task ci-fast` | The branch gate: every step of `ci`, with `corpus-sample` in place of `corpus` and `corpus-check`. | Any step fails. |
| `task corpus-sample` | Compiles and runs the files in `scripts/corpus_sample.txt` under gen1 and holds the pass count to the `# floor:` line in that list. Writes `build/corpus_sample.json`. | Fewer files pass than the floor. It names them. |
| `task lint` | Runs `scripts/lint_codegen.sh`, the eleven rows below. | A row rises above its limit, or a row in debt rises above the previous commit or on any commit of the branch. |
| `task commit-messages` | Runs `scripts/lint_commit_messages.sh` over `main..HEAD`, or over `HEAD^..HEAD` when HEAD is on main, so the main gate checks a merge message and every commit it brought. It matches every token that `br` lists as a ticket or project id. Without `br` it checks only the forms `br <id>`, `ticket: <id>` and `#<id>`, and says so. | A message names a br id. |
| `task test-lint` | Runs `scripts/test_lint_codegen.sh`: each row goes red on a fixture. | A row does not catch its construct. |
| `task ratchet` | Debt counts over the whole compiler (see below), then the lint. | A count rises, on the tip or on any commit of the branch, or a zero-gate row is not zero. |
| `task suites-in-corpus` | Reads `build/corpus.json` and requires every file of the typecheck and rewrite suites to be there with status `pass`. The corpus runs each of them under gen1, so `task ci` uses this check in place of the gen0 suite runs; `task ci-fast` still runs the suites. | A suite file is missing or did not pass, a suite selects no file, or the JSON is not from gen1 at this commit and blinkc hash. |
| `task typecheck-suite` | Runs the files in `scripts/typecheck_suite.txt` under gen0. They assert typechecker behaviour by RUNNING, so they need a compiler that can emit; under gen0 the suite measures gen0's typechecker, not this tree's. | Any file does not pass. |
| `task rewrite-suite` | Runs every rewrite unit-test file under gen0: `tests/test_cg_*.bl`, `test_layout_*.bl`, `test_cname_*.bl`, `test_ir_*.bl`, minus `scripts/rewrite_suite_exclude.txt`. Writes `build/rewrite_suite.json`. | Any file does not pass, a prelude root is missing, one of the four prefixes matches no file, the exclude file is gone, or an exclude line names a file that does not exist or that the glob does not select. |
| `task ci-release` | The old full gate: self-host regen, `blink test`, per-module invariants, installed smoke. | Any step fails. |

The formatter step in `task ci` runs the golden and idempotency checks
only. The semantic check compiles and runs every formatted test, and
those binaries call the relative `build/blink`, which only a release
build provides. `task test-fmt` and `task ci-release` run all three.

## The rewrite unit suite

`task rewrite-suite` runs `scripts/rewrite_suite.sh`. These files test the
rewrite layer directly: `cg_*`, `layout`, `cname` and `ir`. They test it by
RUNNING, so they need a compiler that can emit C. This tree cannot, so the
suite runs under gen0 and measures this tree's rewrite sources compiled by
the pin.

The file list is a glob over four prefixes, not a list file: a new test file
joins the suite by existing, and nobody can forget it. To keep a file out,
name it in `scripts/rewrite_suite_exclude.txt` with a reason above the line.
A line there must name a file that exists and that the glob selects, or the
suite stops; an exclusion that names no file hides a file instead of skipping
it. Each prefix must also match at least one file, or a whole group could
leave the suite and the other three would still report ok.

The suite runs through `corpus.sh --only`, so each file gets the same private
sandbox the corpus gives it, and the row fails unless every file passes.

Every one of these files compiles a probe program in process, which needs the
`std.*` prelude. A compiler resolves it from `<dir of argv[0]>/lib/std`, then
`$BLINK_ROOT/lib/std`, then the embedded registry — and a test binary leaves
the registry empty. So a test binary with neither directory compiles nothing,
reports no error the probe reads, and its assertions hold over an empty
program. The suite checks both roots and stops when one is missing: the
compiler's own `lib/`, which `corpus_one.sh` links beside the `blinkc` in each
sandbox, and `build/lib`, which serves the same file run straight from the
checkout root. The script removes the old `.bl` files and copies `lib/std` and
`lib/pkg` into `build/lib` on every run, so neither an edit nor a deleted
module under `lib/` can leave a stale prelude behind; it copies rather than
links because `bootstrap.sh` copies into the same place and a link to `lib/`
would make that a copy onto itself. A `build/lib` that already points at
`lib/` needs no copy and gets none. A `build/lib`, `build/lib/std` or
`build/lib/pkg` that links somewhere else stops the run, because the copy
would write into a tree the run was never asked to touch.

`corpus_one.sh` stops a file the same way when the compiler under test has no
`lib/std`, so `task corpus` and `task typecheck-suite` cannot run a probe over
an empty program either.

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
  "compiler": "build/gen1",
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
`build/corpus_subset.json` and does not touch the baseline. A subset run
exits 1 when any listed file fails and 2 when the run itself failed. A full
run exits 0 with failing files, because corpus-check judges it against the
baseline. `scripts/test_corpus.sh` proves these exit codes.

## The corpus sample

The full corpus is too slow for a branch gate, so `ci-fast` runs a fixed
sample instead: `scripts/corpus_sample.txt`, files that pass on main, grouped
by the feature each one uses (effects, closures, stdlib imports, generics,
match, containers, and programs with none of those). The point is coverage of
producers, not of counts: a slice that breaks a working program loses a whole
program on its own branch instead of on main.

The list carries its own pass floor on a `# floor: N` line, so the files and
the number they must reach move in one commit. Every file in it passes on
main, so the floor is the length of the list.

When a slice makes more of the sample pass, the runner says so and asks for
the floor to move up. Refresh the list from a green main corpus run, keep the
groups balanced, and never drop a file to make a branch green.

## The lint rows

`scripts/lint_codegen.sh` scans `src/layout.bl`, `src/cname.bl`,
`src/mono.bl`, `src/ir.bl`, `src/cg.bl` and `src/cg_*.bl`. The driver
`cg.bl` is named on its own because `cg_*.bl` does not match it, and a
driver outside the scope escapes every row. A file that does not exist
yet counts as empty. Tests and docs are never scanned.

| Row | Name | Limit | Catches |
| --- | --- | --- | --- |
| L1 | `ct_or_string_types` | 0 | `CT_*`, `type_from_name`, the `tp_*` pool, `sv_tp`, `.ctype`, `.sname` |
| L2 | `sentinel_answers` | 0 | `TYPE_UNKNOWN`, the `if x >= 0 { x } else` fallback (`x` may be a field path), a tid coalesced with `??` |
| L3 | `module_let_mut` | 8 | Mutable module globals in the scanned files, pub or not |
| L3 | `pub_let_mut_unlisted` | 0 | A pub mutable global whose name is not in `scripts/lint_pub_let_mut_allow.txt` |
| L4 | `typename_compares` | 0 | A type name compared as a string |
| L5 | `no_infer` | 0 | A call to any `infer_*` function |
| L6 | `layout_outside_layer` | 0 | A C type spelled outside `layout.bl`, `cname.bl` and `cg_print.bl`; a `TyKind` test inside `cg_print.bl` |
| L7 | `single_producer` | 0 | A name producer defined twice anywhere in `src/`, or missing while its owner file exists. The `PRODUCERS` table names the producers of `cname.bl` and `layout.bl` as they are spelled today; a producer of the deleted codegen with no successor is not listed |
| L8 | `import_dag` | 0 | An import that goes the wrong way in the layer order. The `layout.bl` and `cname.bl` edges come from `scripts/lint_import_dag.sh`, the printer's from `scripts/lint_print_imports.sh` when it exists |
| L9 | `fn_length` | 0 | A function longer than 80 lines |
| L10 | `br_ids_in_source` | 0 | A br ticket id in source |
| L11 | `untested_pub_fns` | 0 | A `pub fn` in the reading layer or mono that no test names |

Each row has a threshold, a stored baseline (`scripts/lint_codegen_baseline.txt`)
and a previous-commit count. The gate is: `now` must not be above
`max(threshold, baseline)`, and a row above its threshold must not be
above the previous commit. A row under its threshold may grow up to the
threshold. The previous-commit rule also holds for every commit on the
branch (`main..HEAD`), each against its parents, so a rise that a later
commit pays back still fails. `scripts/ratchet.sh` walks the branch the same
way. A row above its threshold but not rising shows `DEBT`. This is
how `mono.bl`, which exists today with violations, can be gated without
being rewritten first. `OVER` and `UP` mean the run failed; the matching
lines print under the table.

The ratchet keeps these rows over the whole compiler in
`scripts/ratchet.sh`:

- `br_ids_in_source`: zero gate.
- `module_let_mut`: every column-0 `let mut`, pub or not, in `src/`.
- `typecheck_module_let_mut`: the same count in `typecheck.bl` alone.
- `layout_decline_unhandled`: zero gate. A `decline_reason` read outside
  `layout.bl` with no `diag_ice` within the next three lines.
- `cg_name_string_compares`: a method, trait or fn name compared with a
  string or with a named constant, on the codegen surface the lint scans.
- `fallback_idiom`: `if x >= 0 { x } else` in `src/`.
- `typecheck_str_keyed_tables`: module-scope `Map[Str, _]` tables in
  `typecheck.bl`.

The `module_let_mut` row scans all of `src/` on purpose. It used to name the
old codegen files, so deleting them would have driven it to 0 by
construction and it would then have gated nothing. Over the whole surface
it is a real non-increasing cap: the baseline is the honest current count,
and a new mutable module global anywhere in `src/` fails the row. It
counts globals that are not pub, because a global need not be pub to be
shared state. The codegen-surface half of the rule stays in lint rows L3,
which cap the count and hold pub globals to an allowlist.

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

To allow a new pub mutable global, add a line to
`scripts/lint_pub_let_mut_allow.txt`: the name, then its role. The count
row still holds every global, pub or not, and its cap stays 8. The list names globals that EXIST: a stage that has not landed
adds its line in the commit that adds the global, so the file can never
pre-approve a name nobody has had to justify yet.

## When the corpus baseline moves

Run `task corpus`, read the failing list, and confirm the gain is real.
Then run `task corpus-baseline` and commit `scripts/corpus_baseline.json`
in the same commit as the change that earned it. The baseline lives under
`scripts/` because `build/` is ignored as a whole directory and git cannot
re-include a file below it.

## When the corpus baseline resets

A change that removes the ability to compile at all drops the pass count
to zero for a reason no gain can offset. The rewrite's first commit is
one: it deletes the emitters, so every file fails with I0004
`CodegenStageNotBuilt`. The gate does not bend for this on its own.

Add a hand-written `reset` object to `scripts/corpus_baseline.json`, next
to `passed`:

```json
"reset": {
  "reason": "<why the count went to zero>",
  "resets_baseline_git_head": "<git_head of the baseline being left>",
  "previous_passed": <its pass count>
}
```

`corpus-check` then skips the previous-commit half for exactly that one
predecessor and prints the reason and the number of passing files given
up. The baseline half of the gate still runs in full, so the run must
still match the baseline you just wrote.

It is self-disarming: the next commit's predecessor is the reset baseline
itself, whose `git_head` no longer matches. `corpus-check --update` never
writes the object, so a reset is always a deliberate hand edit. Do not
add one to paper over a regression.
