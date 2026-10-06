[< All Decisions](../DECISIONS.md)

# Test File Outcomes and the Test Line Stream — Design Rationale

Resolves two spec gaps together: the NDJSON record, counts and exit code for a test file that does not build (§8.10.5 said the record was not specified), and the record for a test binary killed by a signal (§8.10 said a signal crash had no record). The Minimalism panelist of the earlier [Panicked Status Reporting](panicked-status-reporting.md) and [Parking Removal](parking-removal-and-xfail-ticket.md) panels asked that the two be decided as one.

Facts given to the panel: each test binary wrote one JSON object at exit, and directory mode wrapped all files in one multi-line document, so nothing streamed; the typecheck pre-pass stopped the whole run when any file failed and showed only the last file's diagnostics; a C compile or link failure gave `{"file": f, "error": "build failed"}` with no diagnostics; the process API reported a signal as exit code `128+n`, and a crashed binary's partial output was pasted into the document, which could make it invalid JSON; `diag_print_json` already wrote diagnostic objects with an `ice` severity and a `notes` list.

## Result

| Question | Result | Vote |
|----------|--------|------|
| Q1 Wire framing | A1: three line kinds, `record: "test"` per test as it ends, `record: "file"` per file (no nested `results`), `record: "run"` last | 3-3 (C) → **6-0** (D) |
| Q1b Unknown `record` values | A consumer ignores them; `status`, `cause`, `outcome` stay closed | **6-0** (D) |
| Q2 Core bundle | One `file` line per file, closed `outcome: ran \| build_failed \| aborted`; `diagnostics` on `build_failed`; real wait status; finished test lines kept and counted; `files: {total, ran, build_failed, aborted}`; exit 1 on `failed + panicked + files.build_failed + files.aborted > 0`; pre-pass no longer stops the run; single-file mode the same | **6-0** |
| Q2b Completion marker | A binary that exits before it reports the end of its run is `aborted`, whatever its exit code | **6-0** |
| Q2c Lower bound | `files.aborted > 0` means the test counts are a lower bound | **6-0** |
| Q3 Signal encoding | T1: `"signal": "SIGSEGV"`, fallback `"SIG<n>"`, or `"exit_code": n` | 3-3 (C) → **6-0** (D) |
| Q3 sub-vote | Flat keys on the file line | 3-3 (C) → 3-3 (D) → **user (BDFL) tiebreak: flat** |
| Q4 Running test | D2-open: optional `running`, present only when known; the method is informative | **5-1** (Min dissent, D3) |
| Q5 C compile/link failure | Split: generated C fails to compile → `severity: "ice"`; link or native-dependency step fails → `severity: "error"`; full tool output in `notes` | 3-2-1 (C) → **4-2** (D; Sys, DevOps dissent for F3+notes); output field by **user decision: `notes`** |
| Q6 Empty keys on `build_failed` | Z1: all-zero `summary` | 4-2 (C) → **5-1** (D; Min dissent) |
| Q7 Human word | H1: `ABORTED` | **5-1** (Web dissent, H2 `CRASHED`/`EXITED`) |

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds. Text below is verbatim from each panelist.

#### Phase A — Independent proposals

##### Systems

My lens is what the pipe and the wait status show the driver. Both tickets have the same root cause: today the binary writes the whole file's results as ONE JSON object at exit. A crash truncates that object, so every result in the file is lost, not only the one that crashed. Fix the framing and both records follow cheaply.

###### P1 (rank 1, prerequisite): one record per line, flushed per test

- Under `--json`, the test binary writes each §8.10 test record on its own line as soon as the test ends, then flushes. After the last test it writes one file line. The record shapes do not change; only the framing changes. This also resolves the spec's own conflict: §8.10 shows one object, while §8.10.5/§8.10.6 already say "NDJSON".
- Each line carries `"type"`: `"test"`, `"file"` or `"run"`. (Panel may pick the key name. One discriminator must exist.) Test lines carry `"file"`. The binary knows its source path at compile time, so this costs nothing.
- Cost: one `write(2)` per test, about 1–2 µs. Tests run in milliseconds. No measurable cost, and memory stays flat (no buffered results array).
- Directory mode: the driver passes lines through without parsing them and adds the `file` line and the final `run` line. Lines from parallel files interleave, but each line is whole because one `write` of under `PIPE_BUF` (4096 bytes) is atomic. The driver must write a long line in one `write` call or hold a lock per line.

```
{"type":"test","file":"tests/a.bl","name":"parses","status":"passed","duration_ms":3}
{"type":"file","file":"tests/a.bl","outcome":"ran","summary":{"total":1,"passed":1,"failed":0,"panicked":0,"skipped":0,"duration_ms":3}}
```

###### P2 (rank 2): file that does not build — one `file` line, zero tests

```
{"type":"file","file":"tests/b.bl","outcome":"build_failed",
 "diagnostics":[{"severity":"error","code":"E0301","message":"...","span":{"file":"tests/b.bl","line":4,"col":9}}]}
```

- `diagnostics` holds the same objects that `diag_print_json` writes today. Do not invent a second diagnostic shape. A C compile or link failure after a clean front end is a compiler bug. It is one diagnostic with `"severity":"ice"` and the `cc` output in `message`.
- Counts: a file that does not build has no tests, so it adds 0 to all six keys. The test summary stays a pure count of tests. The `run` line adds file counts:

```
{"type":"run","summary":{"total":40,"passed":38,"failed":1,"panicked":1,"skipped":0,"duration_ms":912},
 "files":6,"files_build_failed":1,"files_aborted":1}
```

- Exit code: `blink test` exits 0 only when `failed + panicked + files_build_failed + files_aborted == 0`. Otherwise it exits 1. Do not add separate exit codes: CI branches on zero vs non-zero, and the `run` line already carries the detail.
- The typecheck pre-pass must stop aborting the whole run. That contradicts §8.10.5 today. Check each file inside its own worker, and keep a separate diagnostic buffer per file. The shared buffer is why only the last file's errors show today.
- Human: `tests/b.bl ... BUILD FAILED`, then the diagnostics in the normal human form. The summary line gets `, 1 file did not build` only when the count is above 0.

###### P3 (rank 3): binary that ends abnormally, signal included

**Rule for the driver:** a file's run is complete only when the binary's `file` line arrives AND the process exited normally. Any other end is abnormal: a signal (SIGSEGV, SIGABRT, OOM-kill SIGKILL), or an early `exit(n)` from user or FFI code, `exit(0)` included. This rule is wider than "signal". It must be: an early `exit(0)` is a silent green today.

- The driver must read the real wait status (`WIFSIGNALED`/`WTERMSIG`). It must not decode `128+n`, because a normal `exit(139)` looks the same. If the process API flattens these two, fix the API.
- **Finding the running test, at zero cost on the happy path.** Tests run one after another in registration order, and that order is fixed at compile time. On an abnormal end only, the driver runs the same binary again with an internal `--test-list` flag (same filter and tags). It prints names in run order, which takes about 1 ms of exec. The first listed name with no record is the test that was running. The flag is internal driver-to-binary protocol, not user surface.
- The driver writes a record for that test:

```
{"type":"test","file":"tests/c.bl","name":"ffi buffer round-trip","status":"panicked",
 "message":"process terminated by signal SIGSEGV (11)","signal":"SIGSEGV"}
```

  For an early exit, use `"message":"process exited with code 3 before the test ended","exit_code":3`. There is no `span` because the location is not known (§8.10 rule). There is no `duration_ms` because the driver cannot time it.
- **Why `panicked`.** The status enum stays closed. `failed` needs a `cause`, and neither cause fits. `skipped` and `passed` would hide the event. "`panicked` means the test itself is broken" fits a test whose process died. The optional `signal`/`exit_code` fields let a tool tell a process death apart from a Blink panic without a new status. The spec sentence changes to: "`panicked`: a Blink panic escaped the test body, or the process ended while the test ran."
- Tests after the crash do not run and get no records. They are not `skipped`: skipped means someone asked for the skip. The `file` line is `{"type":"file","outcome":"aborted","not_run":7,"summary":{...}}`. If no test can be named (death before the first test, or `--test-list` fails), only the `file` line is written. `files_aborted` still forces a non-zero exit.
- Human: `test ffi buffer round-trip ... PANIC`, then `  process terminated by signal SIGSEGV (11)`, then `  7 tests in tests/c.bl did not run`.

###### Rejected

- **Fork per test** to isolate signals: about 100 µs or more per test plus copy-on-write faults. It is right for nextest as an opt-in and wrong as a default.
- **In-binary SIGSEGV handler** that writes the running test's name: it needs `sigaltstack` per thread to survive stack overflow, it can clash with GC signal use, and it is the "catch signals" feature Min rejected. The `--test-list` re-query gets the same name with no signal code.
- **Restart the binary after the crashed test** to run the rest (pytest-xdist style): cheap on the crash path, but YAGNI until someone shows a need. P3 leaves room for it.

###### Cross-language

- **Go 1.24** added `build-output` events and a `FailedBuild` field to `go test -json` because tools had each guessed at build failures from text. That is the stall 57n5xh warns about.
- **cargo test/libtest:** a SIGSEGV kills the binary. The JSON stream ends with no record for the running test. This is the same gap as qv0b68.
- **nextest:** reports SIGSEGV per test because it runs one process per test, and it pays the fork cost for that.
- **pytest-xdist:** names the test that crashed a worker, then restarts the worker. That is P3 plus the restart I rejected for now.

##### Web/Scripting

Bottom line: a JS or Python developer already knows this shape. Jest and vitest print "Test suite failed to run" and count it under **Test Files / Suites failed**, not under tests. Go 1.24 `go test -json` added `build-fail` at the package level. pytest prints "ERROR collecting x.py" and counts it under `errors`, not `failed`. All of them say the same thing: **when a file breaks, the problem is with the file, not with a test.** We should do the same. Do not touch the test status enum.

###### Proposal 1 (rank 1): one file-level `error` object for both cases

Each file gets one record. A file that built and ran gives its results as usual. A file that did not build, or whose binary died, gets an `error` object in its record. There is no new test status and no new `cause`.

Build failure:

```json
{"file": "tests/auth_test.bl",
 "error": {"kind": "build",
           "diagnostics": [{"severity": "error", "code": "E0301", "message": "...",
                            "span": {"file": "tests/auth_test.bl", "line": 12, "col": 5}}]}}
```

`diagnostics` uses the same objects that `blink check --json` already prints (src/diagnostics.bl). One shape for diagnostics everywhere means one parser. If the C compile or link step fails and there are no Blink diagnostics, `diagnostics` is `[]` and the record has `message` with the tool output.

Signal crash:

```json
{"file": "tests/ffi_test.bl",
 "results": [ ...records for tests that finished... ],
 "error": {"kind": "signal", "signal": "SIGSEGV", "test": "decode raw buffer"}}
```

- `results` keeps the tests that finished before the crash. Throwing away 40 green results because test 41 segfaulted is the thing users hate most about crashing runners.
- `test` names the test that was running. Same rule as `span`: present only when the driver knows it, and never a placeholder.
- `signal` is the name (`SIGSEGV`), not `139`. Nobody on Stack Overflow should have to ask "what is exit code 139".

**Counts.** The six-key test `summary` does not change. A test that never ran, or did not finish, is not counted. Tests that finished count as usual. The run-level output adds a separate file count next to it, so the test identity `total = passed + failed + panicked + skipped` stays true:

```json
{"summary": {"total": 40, "passed": 39, "failed": 1, "panicked": 0, "skipped": 0, "duration_ms": 812},
 "files": {"total": 6, "errored": 2}}
```

**Exit code.** The run exits non-zero when `failed + panicked > 0` **or** `files.errored > 0`. Use exit code 1 for all of these. CI only checks zero or non-zero. A second code (pytest uses 2, 3, 4 and 5) causes questions and no real benefit.

**Human output.**

```
running tests/ffi_test.bl
test encode raw buffer ... ok
CRASH decode raw buffer (SIGSEGV)

BUILD FAILED tests/auth_test.bl
error[E0301]: ...
  at tests/auth_test.bl:12:5

39 passed, 1 failed (of 40)
2 files errored: 1 did not build, 1 crashed
```

The second summary line shows only when `files.errored > 0`. This is the same rule as `panicked` and `skipped`.

**Why not a driver-written `panicked` record for the crash?** It is wrong, and people will notice. §8.10 says "`panicked` means the test itself is broken" and "a signal is not a Blink panic". A segfault is usually caused by FFI or the runtime, not the test. Calling it `panicked` makes users look for a panic message that does not exist. It also puts the crash in the per-test count while the tests after it disappear. That gives a total that changes from run to run.

**Why not one per-test record for each test in a file that did not build?** The runner does not know which tests exist in a file that does not parse, and no mainstream runner pretends to.

###### Proposal 2 (rank 2): make the stream real NDJSON

The spec calls the stream NDJSON. Today directory mode prints one multi-line document. That document becomes invalid JSON when a binary crashes, because the driver pastes in the partial output. Fix it:

- Directory mode prints **one line per file** (the record from Proposal 1), then one final line with `summary` and `files`. Each line is a complete JSON object.
- The driver parses each binary's output and writes it again. It never pastes raw bytes. When a binary's output is cut short, the driver keeps the records it can read and adds `error.kind: "signal"`.
- So the runner can keep finished results after a crash, the test binary writes and flushes each test record as the test ends. It does not keep all records until the end. This is also needed for `--rerun-failed`, which the spec already says "re-reads the previous run's NDJSON".

Single-file mode prints the same line shapes, so a tool needs only one parser.

Cross-language: this matches `go test -json` and the vitest/jest JSON reporters, where a suite failure is an event at the file level. `jq -c 'select(.error)'` finds every broken file in one line. That is a good test for whether the design is easy to use.

###### Proposal 3 (rank 3): fix the pre-pass so it follows §8.10.5

Today one file with a type error stops the whole run, and the driver shows only the last file's diagnostics. Both conflict with the decided sentence "runs the other files". Each file that fails the pre-pass gets its own `kind: "build"` record with its own diagnostics. The other files still build and run. This is a conformance bug, not a spec question. I list it here so that nobody accepts the new record shape while the runner still stops at the first broken file.

###### Scope notes

- No signal handlers and no fork-per-test. The driver reads the signal from the exit status it already gets (`128+sig`). Sys's cost concern does not apply.
- A binary that exits non-zero with no failing records (for example a test that calls `exit(3)`) is the same kind of event. I would add `kind: "exit", "code": 3` to the same object instead of leaving it unspecified. If the panel wants the smallest change, I accept `build` and `signal` only.
- To Min: a record **is** needed. Without one, every tool must parse human text from stderr, and each tool will guess differently. That is the slower and less safe path. One optional object on a record that already exists is the smallest surface that answers the question.

##### PLT

**Position.** Both gaps are the same gap. The spec has a closed type for the outcome of a *test*, but no type for the outcome of a *file*. A build failure and a signal crash are file outcomes, not test outcomes. Put them on the right level and no closed enum has to change.

**Answer to Min's "is any record needed?"** Yes. Today a file that does not build, or that dies, just has no records. A consumer cannot tell "this file has zero tests" from "this file did not build" from "this file crashed after 3 tests". When absence carries three meanings, the output is not a total function of the run. One record per file closes that hole. It is the smallest surface that makes the model total.

###### P1 (rank 1): one file record per test file, with a closed `outcome` enum

Every test file in the run yields exactly one file record. Its `outcome` is a closed enum: `ran | build_failed | aborted`.

```
FileOutcome = ran                         -- the binary exited and wrote its full results
            | build_failed(diagnostics)   -- no binary; no tests ran
            | aborted(termination)        -- the binary ended without full results
Termination = signal(n) | exit_code(n)
```

**ran**: today's per-file object, plus the tag:
```json
{"file": "tests/auth.bl", "outcome": "ran", "results": [...],
 "summary": {"total": 4, "passed": 4, "failed": 0, "panicked": 0, "skipped": 0, "duration_ms": 12}}
```

**build_failed**: carries the diagnostics in the *existing* diagnostics schema (src/diagnostics.bl). One schema for diagnostics everywhere; no new error shape.
```json
{"file": "tests/parse.bl", "outcome": "build_failed",
 "diagnostics": [{"severity": "error", "name": "TypeMismatch", "code": "E0201",
                  "message": "expected Int, found Str",
                  "span": {"file": "tests/parse.bl", "line": 9, "col": 14}}]}
```
A back-end failure (C compile or link) after a clean front end is a compiler bug. It gets one diagnostic with `severity: "ice"` and the tool output as `message`.

**aborted**: the binary ran but did not write a complete result. This covers the signal case *and* the case the brief does not name: test code that calls a process exit mid-run. Both are "the process ended without a verdict". One variant, one rule:
```json
{"file": "tests/ffi.bl", "outcome": "aborted",
 "termination": {"signal": 11, "signal_name": "SIGSEGV"},
 "results": [...completed tests only...]}
```
```json
{"file": "tests/cli.bl", "outcome": "aborted", "termination": {"exit_code": 3}, "results": []}
```
The driver must read the signal from the wait status (WIFSIGNALED), not guess it from exit code `128+n`. A binary that calls `exit(139)` did not get SIGSEGV. If the process API cannot tell them apart, it is wrong, and the spec should say so.

**No test record for the test that was running.** A status says how a test *completed*. That test did not complete. `panicked` is defined as "a Blink panic escaped a test body"; a signal is not one. Calling it `panicked` would make the definition false. `failed` would claim "the test found a bug", which nobody knows. The honest value is "no verdict", and the file record already says that. This keeps §8.10's sentence "a signal crash is not a Blink panic" true and gives it a home.

**Counts.** The test summary keeps its six keys and its law, `total = passed + failed + panicked + skipped`. It counts *records*, not declared tests. Build-failed files add 0 (§8.10.5: "not a test"). Aborted files add only the tests that completed. A second, separate partition counts files:
```json
"files": {"total": 7, "ran": 5, "build_failed": 1, "aborted": 1}
```
Law: `files.total = ran + build_failed + aborted`. Two partitions on two levels; neither leaks into the other. `files.aborted > 0` tells the consumer the test counts are a lower bound.

**Exit code.** `blink test` exits non-zero when `failed + panicked + files.build_failed + files.aborted > 0`. One non-zero code, as before: the record says why, not the exit status.

**Single-file mode** emits the same file record. Today it passes the binary's object through raw, so a crash yields no valid JSON. That breaks the schema.

**Behavior fix.** The typecheck pre-pass that stops the whole run when any file fails contradicts §8.10.5 ("runs the other files"). Under P1 it simply writes `build_failed` for those files and goes on. (Impl note, not spec.)

###### P2 (rank 2): make the stream honestly NDJSON

The spec says "NDJSON" in prose, but its example and the runtime write one object per file. That is a contradiction in the spec. And it matters for P1: if the binary writes its results only at the end, a crash loses every completed result, and `aborted.results` is always empty.

Rule: the test binary writes one test record per line as each test ends, and flushes. The driver tags each line with `file` and builds the file record. Cost: one line write per test, which is noise beside the test itself. No fork per test; Sys's cost objection does not apply.

P1 stands without P2. P2 only makes `aborted.results` useful.

###### P3 (rank 3, optional): name the running test

With P2, the binary may also write `{"start": "<test name>"}` before each test. Then `aborted` may carry `"running": "<name>"`. Same rule as `span`: present only when known, never a placeholder. I rank it last: useful, but new surface, and Min's objection has weight here.

###### Rejected

- **Driver writes `panicked` with "process terminated by signal 11"**: makes the `panicked` definition false. Unsound.
- **New status `crashed` or `build_error`**: breaks a closed enum two votes closed, and puts a file fact on the test level.
- **Catch signals in-process**: a handler after SIGSEGV runs on corrupt state; any record it writes is untrustworthy. Agrees with Sys and Min.

###### Cross-language

- Go 1.24 `go test -json` added package-level `build-output`/`build-fail` actions: build failures sit on the package level, not as test events. Same split as P1.
- Jest reports "Test suite failed to run" as a suite-level error, separate from test status.
- JUnit XML: suite-level `<error>` maps to `build_failed`/`aborted`.
- Rust libtest: a crash kills the binary and leaves nothing. That is the state we want to leave.

##### DevOps/Tooling

My test for every choice: what does a CI dashboard, a JUnit converter, or an editor test panel read, and what does it do when the run goes wrong? Today the answer is "it gets invalid JSON". A SIGSEGV in one file truncates that file's single object, the driver pastes the fragment into one multi-line document, and `jq` fails on the whole run. A build failure in the pre-pass gives `{"status":"error","build_errors":N}` with no file name. That is the gap to close. Min asked whether we need a record at all. My answer is yes: a consumer must be able to tell "this file had no tests" from "this file never ran". Without a record, both look the same.

###### P1 (rank 1, prerequisite): make `--json` real NDJSON, one record per line

The spec already says "NDJSON" in §8.10.5, §8.10.6 and §8.10.4. Only the §8.10 example and the code use one large object. Fix the wire format:

- The test binary writes each test record as one line and flushes it when the test ends.
- The driver writes one `file` line per file, then one `summary` line at the end.
- Each line carries `"record": "test" | "file" | "summary"`. Consumers switch on that one key.

```json
{"record":"test","file":"tests/test_auth.bl","name":"login ok","status":"passed","duration_ms":12}
{"record":"file","file":"tests/test_auth.bl","outcome":"ran","duration_ms":340}
{"record":"summary","total":14,"passed":11,"failed":2,"panicked":1,"skipped":0,"duration_ms":910,"files":{"total":3,"ran":1,"build_failed":1,"crashed":1}}
```

Why: when a binary crashes, streaming loses only the test that was running. Lines already written stay valid. This is how `go test -json` (test2json) and cargo nextest work. A single-object format cannot survive a crash. The §8.10.4 `"event":"test_fail"` / `loc` example also conflicts with §8.10 (`status`, `span`). This change should align it to `record` + `span` too.

Tradeoff: the §8.10 example becomes several lines. Old consumers of the one-object form break. Nothing is stable yet, so now is the cheapest time.

###### P2 (rank 2): one `file` record per file, with a closed `outcome` enum

`outcome` is `ran | build_failed | crashed`. I use `outcome`, not `status`, on purpose. The test `status` enum stays closed and stays about tests. A consumer that filters on `status` never mistakes a file for a test. The driver writes a `file` record for every file, including files that pass. Dashboards get per-file duration, and a file with zero tests still shows up.

**Build failure (57n5xh):**

```json
{"record":"file","file":"tests/test_parser.bl","outcome":"build_failed",
 "message":"tests/test_parser.bl did not build",
 "diagnostics":[{"severity":"error","name":"TypeMismatch","code":"E0301","message":"...","span":{"file":"tests/test_parser.bl","line":12,"col":5}}]}
```

- `diagnostics` reuses the exact objects of `diag_print_json` / `blink check --json`. It adds no new schema, so an editor's problem matcher that already handles `blink check` needs no new code.
- If the failure comes after the front end (C compile or link), `diagnostics` holds what the driver has. The driver puts the raw tool output in `output` (a string). Such a failure is usually a compiler or native-dependency bug, and a human needs the raw text.
- The front-end pre-pass must stop failing the whole run. It marks the failing file `build_failed` and runs the others, as §8.10.5 already requires. It must also keep each file's own diagnostics. Today only the last file's diagnostics show.

**Signal crash (qv0b68):**

```json
{"record":"file","file":"tests/test_ffi.bl","outcome":"crashed",
 "signal":11,"signal_name":"SIGSEGV","exit_code":139,
 "test":"reads native buffer",
 "message":"test binary terminated by signal 11 (SIGSEGV)"}
```

- `test` names the test that was running. It is present only when the driver knows it, by the same rule as `span`: no placeholders. The runner runs tests in order, and each record is flushed, so the driver can find the first declared test with no record. The spec should not say how it finds it.
- I do not want a driver-written `panicked` test record. A SIGSEGV is not a Blink panic. It is usually a compiler, runtime or FFI bug, and someone else owns the fix. Mixing the two would hide those bugs in a "panicked" panel. The driver would also be forging a record into the binary's stream, with a fake `message`.
- The same shape covers SIGABRT, an OOM SIGKILL, and a future per-file timeout (signal 9). No new class is needed later.

JUnit converters map `build_failed` and `crashed` to `<testcase><error>` on the file, or on `test` when it is present. That is the converter's job. Our enums stay small.

###### P3 (rank 3): counts and exit code

- A file that did not build has no tests. It adds nothing to `total`. A crashed file's completed tests count as usual. The running test has no record, so it is not counted. `total = passed + failed + panicked + skipped` still holds. The six keys are unchanged.
- `summary` gains one nested object, `files: {total, ran, build_failed, crashed}`, where `total = ran + build_failed + crashed`. The six keys stay at the top level, so current readers still work.
- **Exit code:** `blink test` exits 1 when `failed + panicked > 0`, or `build_failed + crashed > 0`. There is one non-zero code. This matches the panicked-status P3 vote: CI reads the category from NDJSON, not from 8 bits. A run where every built test passes but one file did not build must fail CI. Otherwise a type error that hides a whole file reads as green. That is the worst outcome for a CI owner.
- Single-file mode (`blink test f.bl`) writes the same records: test lines, one `file` line, and the `summary` line. It also uses the same exit rule.

###### P4 (rank 4): human output

```
BUILD FAILED tests/test_parser.bl
error[E0301]: type mismatch
  --> tests/test_parser.bl:12:5

test reads native buffer ... CRASHED
  test binary terminated by signal 11 (SIGSEGV)

11 passed, 2 failed, 1 panicked (of 14); 1 file did not build, 1 file crashed
```

Show the file clause only when its count is above 0, by the same rule as `panicked`/`skipped`. If `test` is not known, print `CRASHED tests/test_ffi.bl` instead.

###### What I reject

- **No record (Min's "ask first").** A file that disappears from output is the bug CI owners hate most. Under P1 we need a `file` line anyway, so the extra surface is one enum value plus fields.
- **Fork-per-test to catch signals.** I agree with Sys. It costs too much as a default. P2 needs no signal handler, because the driver already sees `128+sig`.
- **New test `status` values (`crashed`, `build_error`).** These would reopen two closed votes, and the outcome belongs to the file, not to a test.

Cross-language: Go test2json (`Action` per line, package-level `fail` with output), cargo nextest (`SIGSEGV` named on the test, since it uses a process per test), and rust libtest (no record, only "process didn't exit successfully", which is the failure mode we are fixing).

##### AI/ML

###### Answer to Min first: is a record needed?

Yes. Today an agent that reads `blink test --json` gets one of two results for a broken file. It gets nothing it can parse (a build failure is free text), or it gets a document that is not valid JSON (a crashed binary's partial object is pasted in). The first case looks green to an agent that counts records. The second case makes the agent's parser fail, and it then goes back to scraping text. Silence and broken JSON are the two worst outcomes for a machine reader. One small record per file fixes both. The test-level enums stay closed.

###### P1 (rank 1): one record per file, with a closed `outcome` field on the file

**Wire.** `blink test --json` writes NDJSON to stdout: one line per test file, in discovery order, then one run line. Each line is complete JSON. A crash or a build failure never breaks the stream.

File that built and ran to its end:
```json
{"record":"file","file":"tests/test_auth.bl","outcome":"ran","results":[...],"summary":{"total":3,"passed":3,"failed":0,"panicked":0,"skipped":0,"duration_ms":40}}
```

File that does not build:
```json
{"record":"file","file":"tests/test_db.bl","outcome":"build_failed",
 "diagnostics":[{"severity":"error","name":"type_mismatch","code":"E0201","message":"expected Int, found Str","span":{"file":"tests/test_db.bl","line":12,"col":9}}],
 "results":[],"summary":{"total":0,"passed":0,"failed":0,"panicked":0,"skipped":0,"duration_ms":0}}
```
- `diagnostics` uses the object that `blink check --json` and the diagnostics stream already use. That is not a new schema, and models already know it.
- It holds every diagnostic with severity `error` for that file. It is never empty. If the front end passes but the C compile or link fails, it holds one error diagnostic that names the failed step and carries the tool's first error line, with no `span`. Never a placeholder `line: 0`.
- Every file gets its own record, so the type-check pre-pass must stop failing the whole run. That is what §8.10.5 already says ("runs the other files").

File whose binary a signal killed:
```json
{"record":"file","file":"tests/test_ffi.bl","outcome":"crashed","signal":"SIGSEGV","running":"reads mapped page",
 "results":[{"name":"opens file","status":"passed","duration_ms":1}],
 "summary":{"total":1,"passed":1,"failed":0,"panicked":0,"skipped":0,"duration_ms":3}}
```
- `signal` is the signal name (`SIGSEGV`, `SIGABRT`, ...), not a number. The driver gets it from the exit status (128+n). A name costs the same tokens as `139`, and an agent never has to know the 128+n rule.
- `running` names the test that was running, when the driver knows it. It is absent when the driver does not know it. This follows the `span` rule: absent, never a guess.
- `results` holds the records of the tests that finished before the crash. The crashed test and the tests after it have no record and do not count. `total = passed + failed + panicked + skipped` stays true with no exception.
- Informative implementation note: the test binary flushes one line per finished test, so the driver keeps the finished records and knows the next name. Per-test fork stays rejected. The spec covers only what the driver writes.

Run line (always last):
```json
{"record":"run","summary":{"total":14,"passed":11,"failed":1,"panicked":1,"skipped":1,"duration_ms":340},
 "files":{"total":5,"ran":3,"build_failed":1,"crashed":1}}
```
- `summary` is the same six-key object, summed over all files.
- `files` partitions the files the same way `summary` partitions the tests: `total = ran + build_failed + crashed`. An agent learns one rule and uses it twice.

**Exit code.** `blink test` exits non-zero when `failed + panicked > 0` or `build_failed + crashed > 0`. There is no new exit code. A signal does not pass through as 139, so single-file mode and directory mode give the same exit code and the same records.

**Human output.**
```
FILE tests/test_db.bl ... BUILD FAILED
  error[E0201]: expected Int, found Str
  at tests/test_db.bl:12:9
FILE tests/test_ffi.bl ... CRASHED (SIGSEGV) in test "reads mapped page"
11 passed, 1 failed, 1 panicked, 1 skipped (of 14); 1 file failed to build, 1 file crashed
```
The file clause shows only when a count is above 0, the same rule as `panicked` and `skipped`.

**Tradeoffs (AI/ML).**
- One closed enum on a new axis (the file), three values. A model branches on `outcome`. It does not infer the case from which keys exist. That was my reason for `xfail_observed` on the panicked panel, and it applies here too.
- The status and cause enums stay closed. A crash is a fact about the process, not about a test, so it lives on the file record.
- The `record` key costs about 3 tokens per file. It lets an agent tell the run line from a file line without a key-presence rule. It also leaves room for other line kinds without a schema break.
- Cost to Min: three new file fields (`outcome`, `signal`, `running`), one nested reuse (`diagnostics`) and one counts object. No flag, no store, no event class. §8.10.5's sentence "has no store, flag or event class" stays true.
- This also fixes the §8.10 example (one object vs "NDJSON" in prose). The spec gets one wire shape.

**Cross-language.** Go `go test -json` added `build-output`/`build-fail` actions, because tools could not see build failures. A crashed Go test binary gives a package-level `fail` with the signal in its output. pytest counts collection errors apart from test failures (`N errors`). Jest reports "Test suite failed to run" on the suite, not as a test status. All four put the crash or the build failure on the file or package, never on a test status. P1 does the same.

###### P2 (rank 2): same records, no `outcome` field

Leave out `outcome`. The case comes from which keys exist: `diagnostics` means it did not build, `signal` means it crashed. This saves one field and one enum. I rank it lower. "Branch on which keys exist" is a rule a model must learn from the prose and gets wrong more often than a closed value it can match. It also breaks if a later case has both keys.

###### Rejected: a synthetic `panicked` record for a signal crash

This adds no schema, but it gives `panicked` two meanings. The spec says `panicked` means "the test itself is broken". A SIGSEGV is often a compiler, runtime or FFI bug. The agent's next step is different: fix the test at `span`, or reduce the program and report a bug. One status with two meanings teaches models the wrong fix. It also has no `span`, and its message would be made-up text that the runtime never raised. I vote against.

##### Minimalism

###### First question: is any record needed?

Yes, but not a new one. The driver already writes `{"file": f, "error": "build failed"}` for a C build failure. It also already turns a dead binary into a failed file. The defects are elsewhere: one failing file stops the whole run, the build record has no diagnostics, and a crash can paste truncated output into the JSON, which makes the whole document invalid. A tool author cannot "guess a shape" for invalid JSON. So we do not choose between "add a record" and "add nothing". The choice is to codify the one record the driver already writes, so that it covers both tickets.

My test for every field below: does a consumer need it to act, and can it get the fact from somewhere else?

###### P1 (rank 1): One file record for "this file gave no report"

A file record is not a test. It means "this file's tests did not report". There are two reasons, in a closed enum:

- `build`: the file did not build. Front-end errors, or C compile/link errors.
- `died`: the binary ended without a complete report. This covers a signal (SIGSEGV, SIGABRT, SIGKILL from OOM), a timeout, and user code that calls a process exit in a test.

```json
{"file": "tests/test_parse.bl", "error": {"kind": "build",
  "message": "1 error",
  "diagnostics": [{"severity":"error","code":"E0308","message":"...","span":{"file":"tests/test_parse.bl","line":12,"col":5}}]}}

{"file": "tests/test_ffi.bl", "error": {"kind": "died",
  "message": "terminated by signal 11 (SIGSEGV)", "signal": 11}}

{"file": "tests/test_exit.bl", "error": {"kind": "died",
  "message": "exited with code 3 and no report", "exit_code": 3}}
```

Rules:
- `diagnostics` are the existing diagnostic objects (§8.1 / `diag_print_json`), unchanged. When the failure has no structured diagnostic (a C toolchain error), the array is empty and `message` holds the text.
- `died` carries exactly one of `signal` or `exit_code`. No placeholders.
- A file record never names a test. The driver does not know which test was running, and the panicked panel ruled out placeholder fields.
- The record replaces the file's `results`. The spec does not promise partial results from a dead binary. The driver must emit valid JSON and must never paste the binary's partial output into it.
- Single-file mode prints the same record alone.

**Counts.** The six-key test summary does not change. A file record adds no tests, so `total = passed + failed + panicked + skipped` still holds. The cross-file summary gets one key, `file_errors`, the number of file records. That is the only new surface. It earns its place because without it a summary reads `"failed": 0` on a run that exited 1, and a consumer that reads only the summary gets the wrong answer.

**Exit code.** `blink test` exits 1 when `failed + panicked + file_errors > 0`. It does not pass through 139 or 134. One non-zero code, the same as the panicked vote.

**Human output.**
```
tests/test_ffi.bl ... DIED
  terminated by signal 11 (SIGSEGV)
11 passed, 0 failed (of 11); 1 file did not report
```

**Spec edits.** §8.10: replace "This section does not specify a record for it" with "The driver reports it as a `died` file record (§8.10.5)." §8.10.5: keep "A file that does not build is not a test" and "runs the other files". Replace "does not specify an NDJSON record" with P1. My 8.10.5 dissent is resolved: the behavior and its record are now decided together.

**Implementation notes (not spec).** The typecheck pre-pass must stop failing the whole run. Each file's diagnostics must go to its own record, which also fixes the "only the last file's diagnostics show" bug. The driver detects a signal from `ec > 128` on the process API it already has.

**Tradeoffs.** It adds one enum with two values, two optional fields, and one summary key. It adds no status, no cause, no signal handler, no fork-per-test and no new event class. Its cost: the record cannot say which test crashed. A user finds that with `--filter` or from the last `ok` line in human mode, which survives because stdout is line-buffered.

**Cross-language.** Go prints `FAIL pkg [build failed]` and, on a crash, `FAIL pkg` plus the exit status. It does not name a test and does not catch signals. Rust libtest does the same for a dead test binary. `cargo test` reports a build failure as a compile error, not as a test. P1 is that posture with one structured record.

###### P2 (rank 2): P1 plus a "test started" line

The binary prints `{"event":"test_start","name":...}` before each test, so the driver can name the crashed test. **I oppose this for now.** It adds an event class and a flush per test, and it only helps when the crash happens inside a test body and not in GC, FFI teardown or static init. Nobody has shown a need for it that `--filter` does not meet. File it as a follow-up and accept it when a consumer asks.

###### Rejected

- **Signal as `panicked`.** `panicked` means a Blink panic escaped a test body. A signal can come from outside any test body. The record would need a test name the driver does not have, so it would hold a placeholder. That reuses a status by lying about it.
- **New status (`crashed`, `build_error`).** The status enum is closed, and a file is not a test. Putting file outcomes into the per-test enum would mix two levels and break "a test counts once".
- **Catching signals in the runtime / fork per test.** This is a large feature for a rare event. Sys already priced fork-per-test at ~100µs+/test.
- **Do nothing.** Today's crash path can produce invalid JSON, so silence is not neutral. And the record already exists in code, so specifying it costs almost nothing.

###### Flag for the moderator (out of scope, file it)

The wire format is inconsistent. §8.10 shows one object per suite. §8.10.4 shows `{"event":"test_fail",...}` lines. The driver writes one multi-line document, and the prose calls all of this "NDJSON". P1 uses the driver's per-file list because that is what exists. This ticket must not decide streaming. A separate ticket should reconcile the envelope, and P1's record moves with it unchanged.

#### Phase A.5 — Moderator dedupe (mechanical)

Full verbatim proposals: scratchpad/phaseA_{sys,web,plt,devops,aiml,min}.md (same dir as this file). Read the others before replying.

###### Shared points (proposed by all six; listed so you can object, not as a vote)

- S1. No new test `status` value and no new `cause` value.
- S2. Build-failure diagnostics reuse the existing `diag_print_json` / `blink check --json` diagnostic objects unchanged.
- S3. The six-key test `summary` and `total = passed + failed + panicked + skipped` stay. A file that does not build adds 0 tests.
- S4. One non-zero exit code (1). `blink test` exits 1 when any test failed/panicked OR any file did not build OR any binary ended abnormally. No pass-through of 139/134.
- S5. The typecheck pre-pass must stop aborting the whole run; each failing file gets its own record with its own diagnostics (conformance with §8.10.5 "runs the other files").
- S6. Single-file mode writes the same records as directory mode.
- S7. No fork-per-test and no in-process signal handler.
- S8. The driver always writes valid JSON and never pastes a binary's raw partial output.

###### Sub-questions and the options panelists proposed

###### Q-A. Wire framing (is it decided in this ticket?)
- A1. Stream real NDJSON now: the binary writes and flushes one line per TEST as it ends; the driver adds per-file and final run lines. — Sys P1, DevOps P1, PLT P2 (PLT: "P1 stands without P2")
- A2. NDJSON with one line per FILE (results nested), then one run line; binary flushes per test so the driver can keep finished results. — AI/ML P1, Web P2
- A3. Do not decide streaming here; keep the driver's current per-file list document; file a separate ticket to reconcile the envelope. — Min ("This ticket must not decide streaming")
- Variation: line discriminator key: `"type"` (Sys), `"record"` (DevOps, AI/ML), none (Web, PLT, Min).

###### Q-B. File record shape
- B1. Every file gets a file record with a closed `outcome` enum: `ran | build_failed | <abnormal-end value>`. — PLT P1, DevOps P2, AI/ML P1, Sys (P1/P2/P3)
- B2. Only a broken file carries an `error` object `{kind: ...}`; files that ran keep today's shape. — Web P1 (`kind: build | signal`, optional `exit`), Min P1 (`kind: build | died`; record replaces `results`)
- Variation (AI/ML P2, ranked lower by its author): B1 without the `outcome` field, case inferred from which keys exist.

###### Q-C. Which abnormal ends are covered, and the name of the value
- C1. Any end without a complete report: signal OR early process exit (incl. `exit(0)`). Names: `aborted` (PLT, Sys), `died` (Min). Web accepts adding `kind: "exit"`.
- C2. Signal only. Name: `crashed` (DevOps, AI/ML), `signal` (Web rank 1).
- Variation: signal encoding — name `"SIGSEGV"` only (Web, AI/ML); number only (Min); number + name (PLT, DevOps); DevOps also keeps `exit_code: 139`. PLT and Sys require the real wait status (WIFSIGNALED), not decoding 128+n; Web/AI/ML/Min say decode from 128+n.

###### Q-D. The test that was running when the binary died
- D1. Driver writes a test record with `status: "panicked"` + `signal`/`exit_code`, no `span`, found via an internal `--test-list` re-query; §8.10 `panicked` definition widens to "or the process ended while the test ran". Later tests: no records, file line carries `not_run: N`. — Sys P3
- D2. No test record; the file record names it in an optional field when known (`test` — Web, DevOps; `running` — AI/ML, PLT P3 ranked optional/last). Present only when known, never a placeholder. How the driver learns it: unspecified (DevOps), flush-per-test + first declared test with no record (AI/ML), `test_start` line (PLT P3).
- D3. Never name the test; file record only. `test_start` line rejected for now, follow-up ticket. — Min P1 (P2 opposed)

###### Q-E. Results of tests that finished before the crash
- E1. Kept and counted (Web, PLT, AI/ML, DevOps, Sys).
- E2. Not promised; the file record replaces `results` (Min).

###### Q-F. C compile/link failure after a clean front end
- F1. One diagnostic with `severity: "ice"`, tool output in `message` (Sys, PLT).
- F2. `diagnostics: []` plus `message` (Web, Min) / raw text in an `output` string (DevOps).
- F3. One `error` diagnostic naming the failed step, first tool error line, no `span`; `diagnostics` never empty (AI/ML).

###### Q-G. File counts in the run summary
- G1. Nested partition `files: {total, ran, build_failed, <abnormal>}` with `total = ran + build_failed + <abnormal>` (PLT, DevOps, AI/ML).
- G2. Flat keys `files`, `files_build_failed`, `files_aborted` (Sys).
- G3. `files: {total, errored}` (Web).
- G4. One key `file_errors` (Min).

###### Q-H. Human output (all proposed `BUILD FAILED` + diagnostics, a crash line, and a file clause on the summary line shown only when >0). Word for the crash: `CRASH`/`CRASHED` (Web, DevOps, AI/ML), `DIED` (Min), `PANIC` (Sys, follows D1).

###### Moderator facts
- §8.10.4 shows `{"event":"test_fail", ... "loc": ...}` lines (sections/06_tooling.md ~1160) — a third shape, raised by DevOps and Min.
- `--rerun-failed` (§8.10.4, deferred) "re-reads the previous run's NDJSON".

#### Phase B — Debate (round 1; all six then signalled stable)

##### Systems

###### (1) Shared points S1–S8

No objection to S1–S8. One addition to S8: the driver needs a **completion marker** from the binary, which is its last summary line. "Exit 0 with no summary line" must count as an abnormal end. Without the marker, a test that calls `exit(0)` reads as green under every option.

###### (2) Positions

- **Q-A: A1 preferred, A2 accepted.** The property that matters is in both: **the binary flushes one line per test.** Without that, E1 is empty in practice. A1 is better in one case: CI kills the *driver* on a job timeout. Under A1 every line already written stays valid. Under A2 the results of every file still in flight are lost. The driver's memory and latency costs are noise either way. Discriminator: I drop `"type"` for `"record"` (DevOps, AI/ML). **A3 rejected** (see Min below).
- **Q-B: B1.** A closed `outcome` enum, not a rule about which keys exist (AI/ML's argument). B2 makes a consumer test `has("error")`, and B1 costs one field.
- **Q-C: C1, value `aborted`** (or `died`; I do not care which). Not `crashed`, because early `exit(n)`, including `exit(0)`, must be in the same value. Signal encoding: `signal` (number) + `signal_name`, taken from the **real wait status**, or `exit_code` (number). Exactly one of them.
- **Q-D: I concede D1 and move to D2,** with the field named `running`. PLT, Web, DevOps, AI/ML and Min all argue that a driver-written `panicked` makes the definition false, and I accept that. The test name goes on the file record, present only when known. Spec text: "the driver names the test only when it knows it". The mechanism is informative.
- **Q-E: E1.**
- **Q-F: F3, not F1. I withdraw "ice".** DevOps is right that a link failure after a clean front end is often a user's missing native library, not a compiler bug. Use one `severity:"error"` diagnostic that names the failed step, with no `span`, so `diagnostics` is never empty. Put the full tool output in `output` (DevOps), not only the first line. A linker error's first line is often useless.
- **Q-G: G1** `files: {total, ran, build_failed, aborted}`, with `total = ran + build_failed + aborted`. I drop my flat keys. One partition rule on two levels is cleaner.
- **Q-H:** `BUILD FAILED`, and for an abnormal end `ABORTED` (or whatever word the C-label is), plus the signal name and `running` when known.

###### (3) Responses

**Web:** "The driver reads the signal from the exit status it already gets (`128+sig`). Sys's cost concern does not apply." Correct, cost is not the issue. Correctness is: `exit(139)` and SIGSEGV give the same `128+n`. AI/ML and Min say the same. The spec should say "`signal` is present only when a signal ended the process". That makes decoding from `128+n` non-conformant at no cost: `waitpid` already returns the real status, and only our process wrapper flattens it.

**Min:** "The driver does not know which test was running." It can know, at zero cost. Registration order is fixed at compile time, and the driver compiled the file, so it has the names in order and applies the same filter. Once lines are flushed per test, the first name with no record is the running test. No `test_start` event is needed, and I reject PLT P3's `{"start":...}` line for the same reason.

**Min:** a start line "only helps when the crash happens inside a test body and not in GC, FFI teardown or static init." A GC crash during test X is during test X, and `running` is still the true answer. Static init means no name is known, so the field is absent. The `span` rule covers that.

**Min:** "This ticket must not decide streaming." Under S8 the driver must parse the binary's output to produce valid JSON. E1 also needs flush per test. Both already decide the binary's framing, so leaving it unstated just defers the same choice to the implementer. The flush costs one `write(2)`, about 1 µs per test. If the panel picks A2, the per-test flush can be an informative note, and the wire is still one line per file.

**AI/ML / DevOps:** agreed on `outcome`, `record` and the nested `files`. DevOps keeps `exit_code: 139` next to `signal: 11`. Drop it: it is a second encoding of the same fact, and it is the encoding that gets confused with a real `exit(139)`.

**PLT:** "`files.aborted > 0` tells the consumer the test counts are a lower bound." Agreed. Keep that sentence in the spec.

STABLE

##### Web/Scripting

###### (1) Shared points S1–S8

No objections. S4 (one exit code) and S8 (the output is always valid JSON) matter most to me. Without them, nothing else here helps a script author.

###### (2) Positions

**Q-A: A1, with `record` as the line key.** I move from A2. Sys and DevOps are right: when the binary streams one line per test, a crash loses only the test that was running, and the driver does not need to parse the binary's output to save the rest. A1 also gives editor test panels live progress, the way vitest and jest reporters do. Condition: the `file` line carries that file's six-key `summary`, so a consumer that wants per-file data does not have to add up test lines. On the key name, I pick `record` over `type` because `type` is too general and the word shows up everywhere in a language spec. I accept A2 as a fallback. I oppose A3: if we wait on framing, the invalid-JSON crash path stays in the spec.

**Q-B: B1 (closed `outcome` on every file).** I move from B2. AI/ML said: "A model branches on `outcome`. It does not infer the case from which keys exist." That is just as true for a human writing `if (rec.outcome === "build_failed")`. DevOps's point, that a file with zero tests still shows up, also decides it for me.

**Q-C: C1.** Sys said: "an early `exit(0)` is a silent green today." That is a real bug class, and my `kind: "exit"` aside was the same idea. For the name, I accept `aborted`. I would have picked `crashed`, but an `exit(3)` is not a crash. Encoding: signal number plus name (PLT/DevOps). I agree with reading the real wait status. PLT showed that an `exit(139)` is not a SIGSEGV, and I was wrong to decode `128+n`.

**Q-D: D2, field `running`.** I drop my name `test`, because it collides with the `record: "test"` lines under A1. The spec says only "present when the driver knows it, never a placeholder". How the driver finds it (Sys's internal `--test-list`, or the first declared test with no record) is an implementation note.

**Q-E: E1.** Keep and count the tests that finished.

**Q-F: F1 (`severity: "ice"`).** I move from F2. `diagnostics: []` with a text blob is the "unstructured text" this ticket exists to remove. A failed C link after a clean front end is a compiler bug, and `ice` tells the user to report it rather than change their code.

**Q-G: G1** `files: {total, ran, build_failed, aborted}`. I drop G3. Two partitions that follow one rule are easier to learn than a vague `errored`.

**Q-H:** `BUILD FAILED <file>` plus the diagnostics. For a signal, `CRASHED (SIGSEGV)` on the running test's line when it is known, else on the file. For an early exit, `EXITED (code 3)`. The file clause on the summary line shows only when its count is above 0. A user reads "CRASHED" in 0 seconds. "aborted" in human text sounds like the user pressed Ctrl-C.

###### (3) Responses

**Sys D1:** "`panicked`: a Blink panic escaped the test body, or the process ended while the test ran." This rewrites a definition the panel passed weeks ago to fit a case it was written to leave out. The first Stack Overflow question will be "my test PANICKED but there is no panic message, only 'process terminated by signal'". Your `--test-list` method is good. Put its result in `running` on the file record, not in a fake test record.

**Min D3/E2:** "A user finds that with `--filter` or from the last `ok` line in human mode." Making the user bisect a test file by hand to find which test segfaulted is the experience people hate in libtest. The last `ok` line also does not help under `-P 4`, because lines from different files interleave. `running` is one optional field with the `span` rule. It needs no new event class, because the driver already sees which records arrived.

**Min A3:** "This ticket must not decide streaming." Your own P1 needs the driver never to paste partial output. With the single-object binary, that means throwing away every finished result in a crashed file. Framing is how we fix the crash case, not a separate matter.

**DevOps** on the §8.10.4 `event: "test_fail"` / `loc` example: agreed. Align it to `record` and `span` in this change, or the spec shows three wire shapes.

STABLE

##### PLT

###### (1) Shared points

I accept S1–S8, with one note on S1. Sys's D1 adds no new status *word*, but it changes what `panicked` *means*. Changing a value's meaning breaks a closed enum as much as adding a value does. I read S1 as "no new value and no change to what an existing value means". With that reading, D1 conflicts with S1.

###### (2) Positions

**Q-A: A2 (one line per file, results nested, then one run line). I accept A1.** Keep two things apart. One is the *internal* channel from the binary to the driver: it must flush per test, or E1 cannot work. The other is the *public* schema. In A2, a test record is always inside its file's record, so every line is self-contained and no consumer has to group lines by `file`. A1 is also sound, so I will vote for it if A2 loses. I reject A3: it specifies records inside an envelope the spec already contradicts. Discriminator: `record`. `type` reads as a type name. `event` is the §8.10.4 shape, which we should retire.

**Q-B: B1.** `outcome` is an explicit tag on a sum type. In B2, the case comes from whether `error` is present. That is the key-presence rule AI/ML rejects, and I agree with them. A tag is total and can be checked. Key presence is neither.

**Q-C: C1, name `aborted` (I accept `died`).** I will not move on coverage. A signal-only C2 leaves "the process exited early" without a value. Sys puts it plainly: "an early `exit(0)` is a silent green today." An enum that cannot describe a reachable state is not closed over its domain. Encoding: `termination` holds exactly one of `{signal, signal_name}` or `{exit_code}`. The spec states the meaning ("ended by a signal"). It does not prescribe 128+n decoding.

**Q-D: D2. `running` is optional, present only when known, and the spec does not say how the driver learns it.** I accept D3 if Min wants it. An optional field that is never present costs nothing, so I will not fight for it.

**Q-E: E1.** A test that finished has a verdict. That verdict must not depend on what a *later* test did. Under E2, one crash in test 41 erases 40 facts the runner already observed, and the summary shrinks for reasons unrelated to those tests.

**Q-F: I move from F1 to F3, with one change.** Native deps exist, so a link failure can be a missing library on the user's machine. That is not a compiler bug, and `severity: "ice"` would mislabel it. So: one `error` diagnostic that names the failed step, carries the tool's first error line and has no span, and `diagnostics` is never empty. I reject F2: `[]` plus a loose `message` is a second shape for the same case.

**Q-G: G1**, with the C1 name: `files: {total, ran, build_failed, aborted}`. Nesting puts the two partition laws side by side, and AI/ML's point holds: "An agent learns one rule and uses it twice." G3 and G4 merge two variants, so a consumer still has to read the file lines to tell them apart.

**Q-H:** `BUILD FAILED` and `ABORTED (SIGSEGV)` or `ABORTED (exit 3)`. The human word should match the enum value. Not a hill.

###### (3) Responses

- **Sys:** "`panicked` means the test itself is broken … fits a test whose process died." No. A signal can come from the runtime, the GC or the compiler's own codegen, and then the test is not broken. Your widened definition ("or the process ended while the test ran") also makes `panicked` depend on *when* the process died, not on what the test did. And it puts a record in a stream the binary never wrote. Your `--test-list` re-query is sound as a way to *learn* `running`. I would accept it as the implementation of D2.
- **Min:** "The driver detects a signal from `ec > 128`." Then `exit(139)` and SIGSEGV are the same, and a record says "signal 11" when no signal fired. The spec must define the fact, not one way to guess it. I agree with your structure (one record, two kinds, no test naming required) and differ only on E2 and the tag.
- **Min:** "This ticket must not decide streaming." Your own P1 keeps finished results only if the binary flushes. Without that, E2 is forced on you, not chosen. The framing and the records are coupled, so deciding one and leaving the other open gives a half-specified wire.
- **DevOps:** `"signal":11, … "exit_code":139` together. A process killed by a signal has no exit status (WEXITSTATUS is undefined). Carrying both says two contradictory things. Choose one.
- **AI/ML:** "The driver gets it from the exit status (128+n)." Same objection as to Min. Otherwise your P1 is close to mine, and I would co-sign it with `aborted` covering early exit.
- **Web:** "If the panel wants the smallest change, I accept `build` and `signal` only." Please don't. That leaves the early-exit case open, and it is the one that reads as green.

STABLE

##### DevOps/Tooling

###### (1) Shared points

I accept S1–S8. One sharpening of S8: "valid JSON" must mean **each line** is valid JSON on its own. A consumer that tails a live run must never need the end of the stream to parse a line.

###### (2) Positions

**Q-A: A1, and I accept A2.** Both survive a crash, and that is the property I need. A1 is better for editor test panels and long CI runs, because results show live per test. A2 is simpler for the driver, because there are no interleaved lines from parallel files. I will vote A2 if A1 lacks a majority. **I oppose A3.** The bug in this ticket is invalid JSON after a crash. A record shape that sits inside a document that a crash can corrupt does not fix it. The discriminator key can be `type` or `record`; I do not care which. There must be one key, and the §8.10.4 `event`/`loc` lines must move to it in the same edit. Otherwise we ship three shapes.

**Q-B: B1.** A closed `outcome` on every file. B2 makes consumers infer the case from which keys exist. That is the rule AI/ML ranked lower for good reasons, and in a dashboard it means `has(.error)` checks spread through every reporter.

**Q-C: C1. I concede and drop `crashed`.** Sys is right: "an early `exit(0)` is a silent green today." That is a CI false green, the worst bug in my domain. Name: `aborted`. I also drop my `exit_code: 139` field. Per PLT/Sys, the driver reads the real wait status: `termination: {"signal": 11, "signal_name": "SIGSEGV"}` or `{"exit_code": 3}`. Keep both number and name for signals: the name is for people, the number is for tools that map signals across platforms.

**Q-D: D2, with the field named `running`, and Sys's `--test-list` re-query as the informative way to fill it.** That joins Sys's mechanism to D2's honesty: the name costs nothing on the happy path and needs no new event class.

**Q-E: E1.**

**Q-F: F3, not F1. This changes my Phase A position (raw `output`).** Sys and PLT say a C compile or link failure "is a compiler bug", and that is not always true. A sidecar native dependency that is not installed (`cannot find -lfoo`) is a user environment error. If we mark it `ice`, CI routes it to the compiler team and the user files a false bug. AI/ML's F3 is correct: one `error` diagnostic that names the failed step, the first tool error line, and no `span`. `diagnostics` is never empty. A real ICE still reports `ice`, because the compiler knows when it hit one.

**Q-G: G1** — `files: {total, ran, build_failed, aborted}`. It is the same partition law as `summary`.

**Q-H:** Human output: `BUILD FAILED <file>`, then the diagnostics. On abnormal end: `test <running> ... ABORTED`, or `ABORTED <file>` when the name is not known, then the termination text (`terminated by signal 11 (SIGSEGV)` / `exited with code 3 before the report ended`). I accept `CRASHED` for the signal case if others prefer it. I reject `PANIC`.

###### (3) Responses

**Sys:** "The spec sentence changes to: `panicked`: a Blink panic escaped the test body, or the process ended while the test ran." No. Every CI dashboard and editor panel groups by `status`. With this change, a "panicked" bucket mixes a Blink `unwrap` on `None` (fix the test at `span`) with a SIGSEGV in FFI (reduce it and file a runtime bug). The record has no `span` and no runtime message, so the panel shows an entry with no location. Your `--test-list` gives the name. Put it on the file record as `running`, and you get the same information without changing a definition the panicked-status panel just closed.

**Min:** "A user finds that with `--filter` or from the last `ok` line in human mode." In directory mode four files run in parallel, and under `--json` there is no `ok` line. In a CI log the user cannot see which file's last line belongs to the crash. A user who has to bisect with `--filter` will rerun the suite N times on a flaky native crash. `running` is one optional field with the `span` rule and no new event class. Sys's re-query shows it does not need `test_start`.

**Min:** "This ticket must not decide streaming." Then this ticket fixes nothing for qv0b68. Your own rule "the driver must never paste partial output", together with "the spec does not promise partial results", means a crash in test 41 throws away 40 results. Web said it best: "Throwing away 40 green results because test 41 segfaulted is the thing users hate most about crashing runners." A2 is a small framing change, and it keeps them.

**Web:** `files: {total, errored}` hides the split CI wants: "did not build" (someone broke main) versus "aborted" (a flaky native crash). Different on-call owners read those two counts. G1 costs two more keys.

**PLT:** I agree with everything, including "`files.aborted > 0` tells the consumer the test counts are a lower bound." I would make that sentence normative.

STABLE

##### AI/ML

###### (1) Shared points

No objections to S1–S8. One addition to S2: a diagnostic with no known location has no `span`. Today `diag_emit` for an ICE passes line 0, col 0 (src/diagnostics.bl:699). That must not reach the test stream as `line: 0`, by the panicked panel's rule.

###### (2) Sub-questions

**Q-A: A2, and A1 is an acceptable concession. Against A3.**
A2 is the bridge. It is the driver's current per-file list with each element on one line, so Min's "codify what exists" mostly holds. It is also crash-safe, which is Sys's point. A1 repeats `"type":"test","file":"..."` on every test, about 15 tokens per test. That adds up in a 1000-test run that an agent reads in full. But both are valid line-by-line JSON with one parser, so I will vote A1 if it wins the majority. A3 leaves "NDJSON" in prose with no shape behind it, and that is the stall that 57n5xh was filed to stop. Discriminator: one key must exist. I take `type` or `record`. My vote is `record`, because `type` already means something else in Blink.

**Q-B: B1.** Every file gets a record with a closed `outcome`. Under B2, a consumer must branch on whether `error` is present. That is the key-presence rule I ranked last in my own Phase A. A model matches a closed value more reliably than it notices a missing key.

**Q-C: C1, value `aborted`. I concede on C2.** Sys: "an early `exit(0)` is a silent green today." That is the strongest argument in this round. An agent that sees exit 0 and no red records stops looking. `crashed` would leave that hole open. I also concede the wait-status rule to PLT and Sys: `exit(139)` is not SIGSEGV, and a record that says it was is false.
Encoding: `signal` as a name (`"SIGSEGV"`), or `exit_code` as an int. Exactly one is present, flat on the file record. I accept PLT's nested `termination` object, and number plus name, if the panel prefers. A name alone is enough for an agent. A number alone makes every reader carry a lookup table.

**Q-D: D2, field `running`. Against D1 and D3.**
- I accept `test` as the name. `running` is clearer next to a `record:"test"` line.
- Mechanism: the spec should say "present only when the driver knows it". Sys's `--test-list` re-query is a fine internal way to get it, and it costs nothing when no binary crashes.

**Q-E: E1.**

**Q-F: F1. I concede F3.** `severity:"ice"` already exists in the diagnostics schema (src/diagnostics.bl:593). It tells an agent the most useful thing it can know: "this is not your code, do not edit it." My F3 used `error`, and that would send an agent off to "fix" correct test code. Against F2: an empty `diagnostics` array plus a free-text field is a second path every consumer must handle.

**Q-G: G1.** It uses the same partition law as `summary`. An agent learns the rule once and applies it at both levels. G4 (`file_errors`) loses the split between "did not build" and "aborted", and those two need different next steps.

**Q-H:** The human word matches the JSON value: `BUILD FAILED` and `ABORTED (SIGSEGV)` or `ABORTED (exit 3)`, plus `in test "<name>"` when known. When the human word and the enum value differ, an agent has to map one to the other, and it gets that wrong.

###### (3) Responses

**To Sys (D1):** "'`panicked` means the test itself is broken' fits a test whose process died." It does not. A SIGSEGV in a test is most often a codegen, runtime or FFI bug. The agent's next step for a `panicked` record is to edit the test at `span`. For a crash it should reduce the program and report a bug. Widening the definition sends models to the wrong fix, and the training data then teaches it. Your `--test-list` mechanism is good. Put the name it finds in `running` on the file record, not into a forged test record.

**To Min (D3):** "it only helps when the crash happens inside a test body and not in GC, FFI teardown or static init." The "present only when known" rule already covers those cases: the field is absent. When it is present, it saves the agent a bisect over `--filter`, which costs N builds and runs and many tokens. Your human-mode answer, "from the last `ok` line", is the text scraping the JSON stream exists to remove.

**To Min (E2):** "The spec does not promise partial results from a dead binary." If 40 results are dropped because test 41 crashed, the agent reruns the whole file to get facts the binary already wrote. A1 and A2 both flush per test, so keeping them costs nothing.

**To Web (B2):** "`jq -c 'select(.error)'` finds every broken file." Under B1 the same query is `select(.outcome != "ran")`, which is no harder. B1 also gives a dashboard per-file duration and shows files with zero tests.

**To DevOps:** I agree that the §8.10.4 `event`/`loc` lines must be aligned to the same key and `span` in this change. If they are left alone, the spec shows three wire shapes, and a model will copy whichever one it sees first.

STABLE

##### Minimalism

###### (1) Shared points S1–S8

No objection to any of them. S8 alone justifies the ticket: invalid JSON is a defect, not a missing feature.

###### (2) Positions

**Q-A: A2 (I move from A3).** Everyone else wants E1 (keep finished results). E1 needs the binary to flush per test, so I accept that this ticket decides framing. A2 is the smaller of the two framings. The public wire has two line kinds (file and run), and the per-test flush stays inside the binary-to-driver channel. A1 adds a third public line kind, which every consumer must handle and which interleaves across parallel files (Sys needs the `PIPE_BUF` rule to keep it safe). A2 has none of that cost, because the driver writes whole file lines. Discriminator: I accept `"record"` if the panel wants one key. With only two line kinds it is close to free, and AI/ML's "never branch on key presence" argument is the one I accepted on the panicked panel. §8.10.4's `event`/`loc` example must be brought to the same shape. That is an edit to existing text, not new surface.

**Q-B: B1 (I move from B2).** PLT: "When absence carries three meanings, the output is not a total function of the run." Under A2 every file already has a line, so `outcome` costs one key and removes a key-presence rule. My B2 only saved anything under A3.

**Q-C: C1, and I give up `died`.** I take `aborted` (PLT, Sys). Two conditions:
- Sys and PLT are right on wait status: "a normal `exit(139)` looks the same." I withdraw "decode from 128+n". The driver reads WIFSIGNALED. If the process API flattens it, that is a bug to fix, not a spec rule to write around.
- Encoding: `termination: {"signal": "SIGSEGV"}` or `{"exit_code": 3}`, exactly one key. Only the name: the number does not give a consumer any fact it can act on. I reject DevOps's `"exit_code":139` next to `signal`. The process had no exit code, so the field states something false.

C2 (signal only) leaves early `exit(0)` as a silent green. Sys: "an early `exit(0)` is a silent green today." That is a real defect, and C1 fixes it at no extra cost.

**Q-D: D3. I accept D2 only with its mechanism in the spec.**
- D1: no. Sys widens `panicked` to "or the process ended while the test ran". That breaks the definition the last panel voted on 6-0, and three seats here (PLT, DevOps, AI/ML) already reject it.
- D2 as written (DevOps: "The spec should not say how it finds it") puts an optional field in the spec that no conformance test can require. Agents will learn to read it, and one implementation will never fill it. AI/ML's "first declared test with no record" needs the driver to know the declared order, which A2 alone does not give it. So D2 needs a `--test-list` query or a start line. Either one is new protocol for a rare event, and `--filter` already isolates the test. If the panel wants D2, I take Sys's `--test-list` re-query as the mechanism. It runs only after an abnormal end, it costs nothing on the happy path, and it is internal. It must not be a user flag. The field name is `running` (PLT, AI/ML): `test` reads like the record is a test.

**Q-E: E1.** It follows from A2's flush. Web: "Throwing away 40 green results because test 41 segfaulted is the thing users hate most." Agreed, and with the flush it costs nothing.

**Q-F: F1 (I move from F2).** `"ice"` is already a severity in src/diagnostics.bl (`diag_emit("ice", ...)`). F1 adds no new value, keeps `diagnostics` never empty (AI/ML's point), and does not add DevOps's extra `output` field. One rule: no `span` when there is no location. Note: diagnostics.bl:699 emits an ICE with `0, 0`. The JSON writer must omit `span` there, not print `line: 0`.

**Q-G: G1 (I drop G4).** `files: {total, ran, build_failed, aborted}`. It partitions files the same way `summary` partitions tests, and it uses the same law. My single key was smaller, but it could not answer "how many crashed" without a scan. Reject G2: flat keys `files_*` at the top level sit next to the six test keys, and a reader can confuse the two levels.

**Q-H: the word follows the value: `BUILD FAILED`, `ABORTED`.** One word per value, as with `PANIC`. Put the signal or exit code on the next line. Reject `PANIC` (it follows D1).

###### (3) Responses

- **Web:** "To Min: a record **is** needed." Accepted. My Phase A already said this. My point was that the record existed in code, so we codify it rather than invent one.
- **DevOps:** "Under P1 we need a `file` line anyway, so the extra surface is one enum value plus fields." Accepted under A2, and that is why I moved to B1.
- **Sys** on D1: "`panicked` means the test itself is broken fits a test whose process died." No. A SIGSEGV in GC or FFI teardown is not the test's fault. AI/ML: "One status with two meanings teaches models the wrong fix." The `--test-list` idea is good. Its record shape is wrong.
- **AI/ML P1:** your build-failed line carries `"results":[]` and an all-zero `summary`. Drop both. A file that did not build has no tests (§8.10.5), and zero-filled fields state a run that never happened. The `files` count already records it.

###### Net surface

One closed enum on a new level (3 values), one `termination` object, one optional `running` field (only with a specified mechanism), one `files` object, and an existing severity reused. There is no new status, cause, event class, user flag or signal handler. I can vote yes on this.

STABLE

#### Phase C — Final vote

Ballot as given to the panel:

Vote alone. Do not read other panelists' ballot files (ballot_*.md). For EACH question give:
1. **Vote** — the option label.
2. **Reasoning** — 2–4 sentences from your domain.
3. **Concern** — one sentence on what could go wrong with the option you expect to win (or with yours).

Option text comes from the panel's own Phase A/B text (phaseA_*.md, phaseB1_*.md).

###### Q1. Wire framing of `blink test --json`
Common to both options: every line is one complete JSON object; the discriminator key is `record`; the §8.10 example and the §8.10.4 `event`/`loc` lines are rewritten to the chosen shape; the binary flushes one line per finished test on its channel to the driver.
- **A1** — The public stream has three line kinds: `record:"test"` (one per test, carries `file`, written as each test ends), `record:"file"` (one per file, carries that file's `outcome` and six-key `summary`), and `record:"run"` (last).
- **A2** — The public stream has two line kinds: `record:"file"` (one per file, test records nested in `results`, written when the file ends) and `record:"run"` (last). Per-test flushing stays internal between binary and driver.

###### Q2. Core bundle (yes / no)
Every file yields exactly one file record with a closed `outcome: "ran" | "build_failed" | "aborted"`. `build_failed` carries `diagnostics` (existing diagnostic objects). `aborted` = the binary ended by a signal or by any early process exit, including `exit(0)`; the driver uses the real wait status and never decodes 128+n. Records of tests that finished before an abnormal end are kept and counted. Test `summary` unchanged (six keys, `total = passed + failed + panicked + skipped`). The run record adds `files: {total, ran, build_failed, aborted}` with `total = ran + build_failed + aborted`. No new test status, no new cause, no change to what `panicked` means. Exit 1 when `failed + panicked + files.build_failed + files.aborted > 0`. The typecheck pre-pass no longer stops the run; each file gets its own diagnostics. Single-file mode writes the same records.

###### Q2b. Completion marker (yes / no)
Sys B1: "the driver needs a **completion marker** from the binary, which is its last summary line. 'Exit 0 with no summary line' must count as an abnormal end." Yes = a binary that exits without its completion line is `aborted`, whatever its exit code.

###### Q2c. Lower-bound sentence (yes / no)
Normative spec sentence: "`files.aborted > 0` means the test counts are a lower bound."

###### Q3. Encoding of how an `aborted` process ended
Common: exactly one of signal / exit code is present; a process killed by a signal carries no exit code.
- **T1** — signal as name only: `"signal": "SIGSEGV"`, or `"exit_code": 3`.
- **T2** — signal as number plus name: `"signal": 11, "signal_name": "SIGSEGV"`, or `"exit_code": 3`.
- Sub-vote: **nested** under `termination: {...}`, or **flat** on the file record?

###### Q4. Naming the test that was running at an abnormal end
- **D2-spec** — optional `running: "<test name>"` on the aborted file record, present only when known, and the spec states how the driver learns it. Min B1: "If the panel wants D2, I take Sys's `--test-list` re-query as the mechanism. It runs only after an abnormal end, it costs nothing on the happy path, and it is internal. It must not be a user flag." Sys B1: "Once lines are flushed per test, the first name with no record is the running test."
- **D2-open** — optional `running`, present only when known, never a placeholder; the spec does not say how the driver learns it (an informative note at most). Sys B1: "Spec text: 'the driver names the test only when it knows it'. The mechanism is informative."
- **D3** — no `running` field; follow-up ticket if a consumer asks.

###### Q5. A C compile/link failure after a clean front end
Common: outcome `build_failed`; `diagnostics` is never empty; no `span` when there is no location (never `line: 0`).
- **F1** — one diagnostic with `severity: "ice"`, tool output in `message`.
- **F3** — one diagnostic with `severity: "error"` that names the failed step; the tool's first error line in `message`.
- **F3+output** — as F3, plus the full tool output in an `output` string on the file record.

###### Q6. Empty keys on a `build_failed` file record
- **Z1** — yes: a `build_failed` file record carries an all-zero `summary` (and, under A2, `results: []`), so every file record has the same keys.
- **Z2** — no: a file that did not build has no tests, so its record carries no `summary` (and no `results`).

###### Q7. Human-output word for `aborted`
- **H1** — one word per enum value: `ABORTED`, then `signal SIGSEGV` / `exit code 3` (+ the test name when known).
- **H2** — `CRASHED (SIGSEGV)` for a signal, `EXITED (code 3)` for an early exit.

Write your ballot to ballot_<you>.md in the scratchpad dir (/tmp/claude-1000/-home-nhumrich-blinklang-blink/27824fff-1a55-4182-b5e2-e721b1f00bd8/scratchpad/) and return it as your reply.

##### Systems

###### Q1. Wire framing
**Vote:** A1
**Reasoning:** The binary already flushes per test, so A1 sends that line to the public stream unchanged. The driver keeps no buffer, and a consumer sees progress live. If CI kills the driver on a job timeout, every line already written stays valid. Under A2 the results of every file still in flight are lost.
**Concern:** Lines from parallel files interleave. The driver must write each line with one `write` call, or under a lock, or a long record can tear.

###### Q2. Core bundle
**Vote:** yes
**Reasoning:** It puts process facts on the file and test facts on the test, and keeps both enums closed. It reads the real wait status, so `exit(139)` and SIGSEGV are not confused. The exit rule makes sure a file that did not build can never read as green.
**Concern:** The process API today flattens a signal into `128+n`. The implementation must fix that API, not decode the number.

###### Q2b. Completion marker
**Vote:** yes
**Reasoning:** The exit code alone cannot tell "all tests ran" from "a test called `exit(0)` halfway". The summary line is the only proof that the run completed, and it costs nothing because the binary writes it already.
**Concern:** A binary whose stdout write fails (for example EPIPE) after the last test reads as `aborted`. That is the right answer, but it can surprise someone.

###### Q2c. Lower-bound sentence
**Vote:** yes
**Reasoning:** It tells a consumer exactly what an aborted file means for the counts, so nobody compares totals across runs naively. It is one sentence and adds no fields.
**Concern:** A consumer may still ignore it and alert on a "drop" in `total`. The sentence only helps those who read it.

###### Q3. Encoding of the abnormal end
**Vote:** T2, flat
**Reasoning:** The number is what `WTERMSIG` returns and is exact. Names differ across platforms for some signals. The name is for humans and agents. Flat keys are cheaper to filter (`select(.signal)`), and the closed `outcome` already scopes them, so nesting adds nothing.
**Concern:** On a platform where a number has no standard name, `signal_name` must be omitted, not made up.

###### Q4. Naming the running test
**Vote:** D2-open
**Reasoning:** The field and its "present only when known" rule are the contract. The mechanism is the implementer's choice: registration order plus flushed records, or a re-query with `--test-list` on the crash path only. Both cost zero on the happy path. Do not freeze the mechanism in the spec.
**Concern:** If the spec says nothing about how, an implementation might guess the name when it is not sure, so the spec must state "never a guess" in plain words.

###### Q5. Backend build failure
**Vote:** F3+output
**Reasoning:** A link failure is often a user's missing native library, not a compiler bug, so `ice` would be wrong. The first error line is often useless for a linker, so the full output must be kept. One string is cheap.
**Concern:** Tool output can be large (many KB). The single `write` of the line goes over `PIPE_BUF`, so the driver's line lock matters here.

###### Q6. Empty keys on build_failed
**Vote:** Z1
**Reasoning:** Every file record has the same keys, so a consumer sums `summary` over all file records with no special case. An all-zero summary is true: the file contributed zero tests. The cost is a few bytes.
**Concern:** A consumer might read a zero summary as "file ran, no tests". `outcome` exists to prevent that.

###### Q7. Human word
**Vote:** H1
**Reasoning:** One word per enum value means the human output and the JSON are consistent. `grep ABORTED` finds every case. The detail line already tells signal from exit.
**Concern:** `ABORTED` may read like SIGABRT. The detail line (`signal SIGSEGV`) removes the doubt.

##### Web/Scripting

###### Q1. Wire framing: **A1**
Reasoning: Writing one line per test is what an editor test panel and a watch-mode reporter need to show live progress, the way vitest and jest do. A crash loses only the running test, and those results never depend on the driver re-parsing the binary's output. Because the file line carries its own six-key summary, a consumer that only wants per-file data can filter `record == "file"` and skip the test lines.
Concern: under `-P 4`, test lines from different files interleave, so a naive consumer that assumes the lines are grouped by file will be wrong. The spec must say that each test line carries `file`.

###### Q2. Core bundle: **yes**
Reasoning: It has one closed enum per level, the existing diagnostic objects, a single exit code and valid JSON every time. A JS or Python developer can learn it in five minutes, and it matches jest's "suite failed to run" and pytest's collection errors.
Concern: treating `exit(0)` as `aborted` will surprise people who call `exit` in a test on purpose. The human output must state the reason clearly.

###### Q2b. Completion marker: **yes**
Reasoning: Without it, an early `exit(0)` reads as green, and that is the worst kind of CI bug because nobody looks at it. The marker is the binary's last line, which we already write, so it adds no surface.
Concern: if a binary's stdout is closed or redirected by test code, the run reads as `aborted`. That is correct, but it may confuse people.

###### Q2c. Lower-bound sentence: **yes**
Reasoning: Someone who reads only `summary` will see `failed: 0` and assume the run is clean. One sentence stops that misreading and costs nothing.
Concern: people do not read the spec, so the human summary line must also show the aborted-file clause.

###### Q3. Termination encoding: **T2, flat**
Reasoning: `signal_name` is what people read and search for, and the number is useful for tools that map it themselves. Flat keys mean `rec.signal_name` with no extra nesting to null-check. "Exactly one of signal / exit_code" is easy to see on a flat record.
Concern: two signal keys can drift apart if a platform has no name for a number, so the spec should say `signal_name` is absent when unknown.

###### Q4. Naming the running test: **D2-open**
Reasoning: Users need the name. Making them narrow the file down by hand with `--filter` to find the segfault is the libtest experience they hate. How the driver learns the name is an implementation detail, and keeping it out of the spec lets us change it later (re-query, test-start lines) without a spec change.
Concern: if no mechanism is required, an implementation might never fill the field. The implementation ticket should require it.

###### Q5. C compile/link failure: **F3+output**
Reasoning: I change from F1. A link failure is often the user's fault, for example a missing native library or a bad sidecar dependency, not a compiler bug. Calling it `ice` sends them to file a bug report instead of fixing their setup. They need the full linker output to fix it, and the first line alone is rarely enough.
Concern: `output` can be large and noisy in an NDJSON stream. A size cap or truncation rule may be needed later.

###### Q6. Empty keys on `build_failed`: **Z1**
Reasoning: When every file record has the same keys, `rec.summary.total` works without a null check. That removes one TypeError, one Stack Overflow question and one `?.` in every consumer.
Concern: an all-zero summary could be misread as "built, had zero tests", but `outcome` already says it did not build.

###### Q7. Human word: **H2**
Reasoning: People understand "CRASHED (SIGSEGV)" at once. "ABORTED" in human text sounds like the user pressed Ctrl-C or that SIGABRT fired. The JSON keeps the one enum value, so this affects only what people read.
Concern: the human words and the enum names differ, so the spec must map both of them to `aborted`.

##### PLT

###### Q1: A2
**Reasoning.** A2 nests each test record inside its file's record, so each public line stands on its own. A consumer never has to group lines by a `file` key or wait for a later line to learn the outcome. Per-test flushing is a fact about the internal binary-to-driver channel, not about the public schema, and A2 keeps the two apart.
**Concern.** A long file shows nothing until it ends, so a consumer that wants live progress has to ask for A1 later.

###### Q2: yes
**Reasoning.** This is a total, closed sum type on the file level. It covers every reachable end of a test binary and leaves the test-level enums and the meaning of `panicked` alone. There are two partitions, each with its own law, and neither leaks into the other.
**Concern.** If the implementation decodes 128+n despite the text, `aborted` records will name signals that never fired.

###### Q2b: yes
**Reasoning.** A complete run must be shown by something positive, the completion line. Absence of a bad exit code does not show it. Without a marker, `exit(0)` in the middle of a test is indistinguishable from success, and C1 coverage is not total in practice.
**Concern.** A binary that writes its completion line and then dies in teardown counts as `ran`. The spec should say that this is intended.

###### Q2c: yes
**Reasoning.** The summary counts records, not declared tests. That meaning must be normative, or consumers will read `total` as "tests in the suite". One sentence fixes the meaning of an existing number at zero cost.
**Concern.** None of substance. The wording should say "lower bound on tests in those files", not on the run as a whole.

###### Q3: T1, nested
**Reasoning.** Signal numbers are not portable. SIGBUS is 7 on Linux and 10 on macOS, so a consumer that branches on `11` is wrong on other platforms. The name is the portable identity, and a number next to it would be a second, platform-dependent copy of the same fact. Nesting `termination` makes "exactly one of signal or exit code" a single field that is itself a sum, instead of a rule spread across sibling keys.
**Concern.** Some consumers will want the raw number for a platform-specific lookup. They can still derive it from the name.

###### Q4: D2-open
**Reasoning.** The spec should state the contract, not one implementation: when `running` is present it is correct, and it is never a placeholder. Both the `--test-list` re-query and "first name with no flushed record" meet that contract. Fixing one of them in normative text adds no soundness and adds a constraint.
**Concern.** An implementation may infer the name wrongly, for example by ignoring the filter. The informative note should say the inference must use the same filter and order as the run.

###### Q5: F3
**Reasoning.** A link failure can be a missing native library on the user's machine, so `ice` would misclassify a user-environment error as a compiler bug. One `error` diagnostic that names the step keeps a single diagnostic shape. An extra `output` key is a second channel that holds the same fact in a different form.
**Concern.** The first error line may not be enough to debug a link failure. The human stream must still print the full tool output.

###### Q6: Z2
**Reasoning.** Fields belong to the variant that gives them meaning. A `build_failed` file never ran tests, so a zero `summary` on it blurs the line between "ran zero tests" and "did not build", which is the exact ambiguity this ticket exists to remove. Consumers branch on `outcome`, the tag, not on which keys are present.
**Concern.** Naive consumers that sum `summary` over every file record without checking `outcome` will need a guard. The run record's totals already save them that work.

###### Q7: H1
**Reasoning.** The human word should be the enum value, so a reader who sees `ABORTED` in the terminal finds the same word in the JSON and the spec. The detail line carries the signal or exit code.
**Concern.** `CRASHED` is the word more users would search for. The detail line `signal SIGSEGV` has to carry that recognition.

##### DevOps/Tooling

###### Q1. Wire framing — **A1**
Reasoning: Editor test panels and long CI runs need a result per test as it ends. The model is go test -json and the VS Code test API, where a green tick appears for each test. Under A2, nothing reaches a consumer until the whole file ends, so a 5-minute file shows nothing for 5 minutes. A1 also makes `--rerun-failed` simple: it selects `record=="test" and status=="failed"` with no unnesting.
Concern: Parallel files interleave lines, so the driver must write each line whole, in one write or under a lock. Otherwise we get the same invalid JSON we are fixing.

###### Q2. Core bundle — **yes**
Reasoning: It closes both tickets with one record that has a closed `outcome`. It reuses the diagnostic schema, keeps the test enums and the six-key summary closed, and makes CI go red on every way a file can fail to report.
Concern: The pre-pass change (each file gets its own diagnostics) is implementation work. If the spec lands before that work, the runner does not conform for a while.

###### Q2b. Completion marker — **yes**
Reasoning: An early `exit(0)` that skips tests is a silent green, the worst bug a CI owner can have. Only a completion line proves the binary reported everything.
Concern: If a binary's stdout write fails (closed pipe, full disk), the file is marked `aborted` even though its tests ran. That is the correct, fail-closed result, but the message must say why.

###### Q2c. Lower-bound sentence — **yes**
Reasoning: Dashboards plot `total` over time. Without this sentence, a drop in total after a crash looks like deleted tests, not lost results.
Concern: Consumers may still ignore it. The sentence costs nothing, though.

###### Q3. Termination encoding — **T2, nested**
Reasoning: The name is for people and logs. The number is for tools that map signals across platforms, where numbers differ (SIGBUS is 7 on Linux and 10 on macOS), so a tool should not have to parse a name. Nesting under `termination` makes the "exactly one of signal / exit_code" rule visible in the shape and keeps the file record's top-level keys stable. `jq '.termination.signal_name'` is no harder than the flat form.
Concern: Two fields for one fact can disagree if an implementation fills the name from a stale table.

###### Q4. Running test — **D2-open**
Reasoning: The spec contract is the field's meaning and the `span` rule: present only when known, never a placeholder. The `--test-list` re-query is an implementation detail. It should not freeze an internal protocol into the spec, and a later runner (process per test, or a restart after a crash) could learn the name another way.
Concern: An implementation might never fill the field. A conformance test should cover the simple case (a crash in the second of three tests).

###### Q5. C compile/link failure — **F3+output**
Reasoning: `severity: "error"` is right, because a missing `-lfoo` is the user's environment, not an ICE. The first line fits a diagnostic `message`. A link failure often has 30 lines of undefined references, and CI log viewers and agents need the full text without rerunning. A separate `output` string keeps the diagnostic object clean and does not stretch its schema.
Concern: `output` can be large. The spec should say the driver may truncate it, with a marker.

###### Q6. Empty keys on build_failed — **Z1**
Reasoning: Reporters sum `summary` across file records. If every file record has the same keys, they never need a null check, and a zero summary is the truth: this file contributed no tests.
Concern: A consumer might read an all-zero summary as "file had no tests". The `outcome` field says otherwise, but someone will still miss it.

###### Q7. Human word — **H1**
Reasoning: One word per enum value means `grep ABORTED` in a CI log matches `outcome:"aborted"` in the JSON. Each new end case also needs no new human word.
Concern: `ABORTED` next to a signal can read like SIGABRT. The text after it (`signal SIGSEGV`) must always follow on the same line.

##### AI/ML

###### Q1. Wire framing
1. **Vote:** A2
2. **Reasoning:** An agent reads the whole run, often in one context window. A1 repeats `"record":"test","file":"..."` on every test, about 15 tokens per test, which comes to thousands of tokens on a large suite and gives the agent no new fact. A2 groups a file's tests where the agent needs them, next to that file's `outcome`, so it never has to join lines by `file`. Both forms survive a crash, because the binary flushes per test in both.
3. **Concern:** Under A2 a long-running file shows nothing on the public stream until it ends, so a live watcher (an IDE panel, or `--rerun-failed` on a cancelled run) sees no progress.

###### Q2. Core bundle
1. **Vote:** yes
2. **Reasoning:** Each fact sits on one level: tests carry test statuses and files carry file outcomes. Two partitions follow the same rule, so an agent learns it once. `panicked` keeps one meaning, which keeps an agent from "fixing" a test when the real fault is a codegen or FFI crash. Exit 1 on `build_failed` or `aborted` closes the silent-green hole.
3. **Concern:** The fixed pre-pass and the wait-status rule are implementation work. If the runtime ships the record before both are done, it will write `aborted` records that are wrong, so the conformance test must cover both.

###### Q2b. Completion marker
1. **Vote:** yes
2. **Reasoning:** This is the only way to catch an early `exit(0)`, which is the worst case for an agent: exit 0, no red records, and the agent stops. A wait status alone cannot tell "finished" from "left early with code 0".
3. **Concern:** A binary that writes its completion line and then crashes during teardown would read as `ran`. The spec must say what decides in that case (I would say the wait status: a signal is still `aborted`).

###### Q2c. Lower-bound sentence
1. **Vote:** yes
2. **Reasoning:** An agent compares counts between runs. Without this sentence it reads "total went from 40 to 12" as "28 tests were deleted". One normative sentence stops that wrong conclusion, and it costs no wire surface.
3. **Concern:** The wording must say which number is the lower bound (the count of tests in the run, not each status count). Otherwise a model may read `failed` as "at least N failed".

###### Q3. Encoding of an abnormal end
1. **Vote:** T1, **flat**
2. **Reasoning:** `"signal": "SIGSEGV"` is the fact the agent acts on. A number makes every reader carry a lookup table, and two fields for one fact is a second spelling. Flat keeps one path (`rec.signal`), the same as `rec.span`. A nested `termination` object adds a level and gives no new fact.
3. **Concern:** On an OS where the signal name is not known, the driver needs a fallback spelling (for example `"SIG47"`). The spec should name it, so nobody invents a number in that field.

###### Q4. Naming the running test
1. **Vote:** D2-open
2. **Reasoning:** The agent needs the field and its rule ("present only when known, never a placeholder"). It does not need the mechanism. If the spec names a `--test-list` re-query, it puts driver internals in the language spec and freezes one way of doing it. An informative note is enough to show that a cheap way exists.
3. **Concern:** If the mechanism is not specified, an implementation may simply never set `running`, and the field stays empty forever. The conformance test should check that a SIGSEGV in a test body names that test.

###### Q5. C compile/link failure after a clean front end
1. **Vote:** F1
2. **Reasoning:** `severity: "ice"` already exists in the diagnostic schema, and it tells an agent "this is not your code, do not edit it." An `error` severity (F3) sends the agent off to rewrite correct test code. The full tool output in `message` gives a human enough to file a bug.
3. **Concern:** A native-dependency link error (a missing `-l` library) is the user's setup, not a compiler bug. Under F1 it reads as `ice`, so the message must keep the tool's text for the agent to tell the two apart.

###### Q6. Empty keys on a `build_failed` record
1. **Vote:** Z1
2. **Reasoning:** One shape for every file record means `rec.summary.total` never throws and no consumer needs a key-presence branch. `outcome` already says why the counts are zero. Models make fewer errors on records that always have the same keys.
3. **Concern:** A reader that sums `results` length against `summary.total` per file must not mistake an empty, built file for a broken one. `outcome` covers this, but the spec example should show both side by side.

###### Q7. Human-output word
1. **Vote:** H1
2. **Reasoning:** The human word should match the JSON value one to one. An agent that reads both outputs then needs no mapping table. H2 gives one enum value two human words, and that is the drift the closed enum is there to prevent.
3. **Concern:** `ABORTED` sounds less urgent than `CRASHED` to a human scanning a log. The `signal SIGSEGV` text on the same line must stay, so that the cause is not lost.

##### Minimalism

###### Q1. Wire framing: **A2**
- **Reasoning:** A2 gives the public stream two line kinds, not three. Per-test flushing is a channel detail between binary and driver, and it does not need to be a contract every consumer parses. The driver writes whole file lines, so lines from parallel files never mix and no `PIPE_BUF` rule enters the spec. It still keeps finished results after a crash, which was the reason to decide framing here at all.
- **Concern:** under A2 a consumer sees nothing for a file until the file ends, so a long file shows no live progress. If someone shows a need, A1 can be added later without breaking A2's lines.

###### Q2. Core bundle: **yes**
- **Reasoning:** It codifies the per-file record the driver already writes and fixes the invalid-JSON defect. It adds one closed enum on the file level and changes no closed enum on the test level. `panicked` keeps the meaning the last panel voted 6-0. Each part has a consumer who needs it.
- **Concern:** the pre-pass fix and the wait-status read are implementation work. If they lag, the spec will describe behavior the driver does not have, so they must land with the spec text.

###### Q2b. Completion marker: **yes**
- **Reasoning:** Without it, an early `exit(0)` reads as a green file, and C1 exists to close that hole. The binary already writes a final summary, so its last line becomes the marker at no new public cost.
- **Concern:** a user test that writes to stdout could forge the marker. The marker must be parsed as the final complete record, not found by a text match.

###### Q2c. Lower-bound sentence: **yes**
- **Reasoning:** It is one sentence and adds no field. It stops a reader, human or model, from treating `total` as the number of declared tests when a file aborted.
- **Concern:** none of substance. The sentence states a fact the rules above already imply.

###### Q3. Encoding: **T1, nested**
- **Reasoning:** One key carries one fact. The number gives a consumer nothing it can act on beyond the name, and `"signal": 11` next to `"signal_name"` is two keys for one fact. Nest it under `termination` so that "exactly one of signal / exit_code" is a rule about one small object, not about two optional keys mixed in with the file's other fields.
- **Concern:** a signal with no portable name (realtime signals) needs a fallback. The spec should say to use `"SIG<n>"`, not invent a second key.

###### Q4. Running test: **D3** (D2-spec acceptable; D2-open no)
- **Reasoning:** Naming the test needs new protocol (`--test-list` or a start line) for a rare event, and `--filter` already finds it. If the panel wants the field, D2-spec is the honest form: the spec says how the field gets filled, so a conformance test can require it. D2-open puts an optional field in the spec that no test can require. Agents will learn to read it, and some implementation will never fill it.
- **Concern:** I expect D2-open may win. If it does, the "never a placeholder" rule is the only thing that keeps it honest, and the conformance suite must check that the field is absent when the mechanism is absent.

###### Q5. C compile/link failure: **F1**
- **Reasoning:** `"ice"` is already a severity in src/diagnostics.bl. A C failure after a clean front end is a compiler bug, and ICE says exactly that. F3 relabels a compiler bug as a user error, and F3+output adds a second field for text that `message` already holds.
- **Concern:** diagnostics.bl:699 emits an ICE with `0, 0`. The JSON writer must omit `span` there, or F1 breaks the no-`line: 0` rule on day one.

###### Q6. Empty keys: **Z2**
- **Reasoning:** §8.10.5: a file that does not build "is not a test". An all-zero `summary` and `results: []` describe a run that never happened. `outcome` already tells the consumer which keys to expect, so uniform keys buy nothing. This matches the rule from the panicked panel: absent, not placeholder.
- **Concern:** a lazy consumer that reads `summary` from every file line without checking `outcome` will get a missing key. That is the right failure: loud, and on the first try.

###### Q7. Human word: **H1**
- **Reasoning:** One word per enum value, the same rule that gave us `PANIC`. H2 prints one value as two words, so a reader who greps logs has to know both words map to one outcome.
- **Concern:** `ABORTED` is weaker than `CRASHED` for a segfault. The next line (`signal SIGSEGV`) carries that weight, so the next line must always print.

#### Phase D — Round 2 (Q1, Q3, Q5, Q6)

##### Debate

##### Systems

###### Q1. Framing (hold A1; A2 acceptable)

AI/ML: "A1 repeats `"record":"test","file":"..."` on every test, about 15 tokens per test." That is a real cost for a reader that loads the whole run. It is not a cost on the wire: a few bytes per test is noise. PLT: "a consumer never has to group lines by a `file` key". True, but a filter on `record=="test"` with no grouping is the common case: `--rerun-failed`, an editor panel, a CI annotator. Min: "no `PIPE_BUF` rule enters the spec". It does not enter under A1 either. Whole-line writes are a driver duty in both forms, because a parallel driver writes file lines too, and those can be large under F3+output. My point stands: under A1, if CI kills the driver, the lines already written are kept. Under A2, every file in flight is lost. I hold A1, and I accept A2 on one condition, which I ask both sides to adopt: **the spec says a consumer must ignore a `record` value it does not know.** Then Min's "A1 can be added later without breaking A2's lines" is true by rule, and is not a hope.

###### Q3. Encoding (move to T1; flat preferred, nested accepted)

PLT: "Signal numbers are not portable. SIGBUS is 7 on Linux and 10 on macOS." Correct, and it undoes my own reasoning: I wrote that names differ across platforms, and it is the numbers that differ. The name is the portable identity. The number is a platform detail that a tool branching on `11` gets wrong on macOS. I move to **T1**, with the AI/ML/Min fallback written into the spec: when a signal has no standard name, use `"SIG<n>"`, and never omit the field or invent another key. On nesting, `outcome` is already the tag, so flat `signal` / `exit_code` keys are scoped by it, the same way `diagnostics` sits flat on `build_failed`. I prefer flat for that consistency. I accept nested `termination` without objection if that breaks the tie.

###### Q5. Back-end failure (move to a split by step)

Min: "A C failure after a clean front end is a compiler bug, and ICE says exactly that." AI/ML: "`error` sends the agent off to rewrite correct test code." Both are right for one step and wrong for the other. Web, DevOps and my B1 note: "a missing `-lfoo` is the user's environment". The driver knows which step failed, so make the severity follow the step:
- the C compile of **generated** code fails → `severity:"ice"` (a compiler bug, so do not edit your code);
- the **link** or a **native dependency** step fails → `severity:"error"`, naming the step (fix your setup).

On the text: PLT calls `output` "a second channel that holds the same fact". I accept dropping the `output` key **if `message` holds the full tool output**, not only its first line. A linker's first line is usually useless. So my order is: split + full text in `message` > F3+output > F1 > F3. Min's concern applies to every option: diagnostics.bl:699 emits an ICE at `0, 0`, so the JSON writer must omit `span` there.

###### Q6. Empty keys (hold Z1, weakly)

Min: "absent, not placeholder." A zero count is not a placeholder. It is the true number of tests that file added to the run, which is what `summary` measures, and §8.10.5's "not a test" is exactly why that number is 0. PLT: "blurs ran zero tests vs did not build". `outcome` already separates those, and Z2 does not remove the need to read it. The gain from Z1 is that a consumer can sum `summary` over every file line with no branch. That is small, and the run record already gives the total. I hold Z1 but would not block Z2. Under A2, `results: []` on a `build_failed` line is the weaker half of Z1, and I would drop it first.

##### Web/Scripting

###### Q1. Framing — hold A1
AI/ML: "A1 repeats `"record":"test","file":"..."` on every test, about 15 tokens per test." That is true, but an agent that cares about tokens does not read every passing test. It runs `select(.status != "passed")` or reads the `file` lines. A1 makes that filter one line; A2 needs a filter that unnests. PLT: "A consumer never has to group lines by a `file` key." Under A1 a consumer that wants groups reads the `file` line, which carries `outcome` and the summary. Grouping is needed only by consumers that want per-test detail, and the line has `file` for them. The case that decides it for me is Sys's: "If CI kills the driver on a job timeout … under A2 the results of every file still in flight are lost." A CI timeout is common, and losing results then is exactly the bug this ticket fixes for crashes. I hold A1. I would accept A2 only if the spec states that per-test lines may be added later without changing the A2 line shapes (Min: "A1 can be added later without breaking A2's lines").

###### Q3. Termination encoding — move to T1; nesting: either, slight lean nested
PLT: "SIGBUS is 7 on Linux and 10 on macOS, so a consumer that branches on `11` is wrong on other platforms." That convinces me. The number looks precise but is not portable, and two keys for one fact is the kind of drift that leads to "which one do I read?" questions. I move to T1, with Min's and AI/ML's fallback `"SIG<n>"` when the platform has no name. On nesting: Min said "`exactly one of signal / exit_code` is a rule about one small object." At the top level of a file record, `exit_code` can also be misread as `blink test`'s own exit code. `rec.termination.signal` is not harder to read than `rec.signal`. I lean nested and would accept flat.

###### Q5. C compile/link failure — hold F3+output
Min: "F3 relabels a compiler bug as a user error." A missing `-lssl` or a bad native dependency sidecar is not a compiler bug. AI/ML's own concern admits this: "A native-dependency link error … is the user's setup, not a compiler bug. Under F1 it reads as `ice`." An `ice` severity tells an agent and a person to file a compiler bug, which is the wrong next step for the most common link failure. PLT: "An extra `output` key is a second channel that holds the same fact." It is not the same fact. `message` holds one line, and `output` holds 30 lines of undefined references that someone needs to fix the problem. Putting 30 lines in `message` breaks every diagnostic renderer that assumes one line. I hold F3+output, with DevOps's rule that the driver may cut `output` off, with a marker. I would accept plain F3 only if the spec requires the human stream to print the full tool output (PLT's own condition).

###### Q6. Empty keys — hold Z1
Min: "a lazy consumer that reads `summary` from every file line without checking `outcome` will get a missing key. That is the right failure: loud." In JavaScript it is not loud. `total += rec.summary?.total` gives `NaN` with no error, and `rec.summary.total` without `?.` throws on one CI run in fifty, only when a file did not build. That is the quiet, late failure Min wants to avoid. PLT: "a zero `summary` … blurs the line between 'ran zero tests' and 'did not build'." It does not, because `outcome` says which case it is, and PLT agrees that "consumers branch on `outcome`". A zero summary is also true: the file added zero tests (Sys). I hold Z1. Z2 is acceptable only if the run record stays the one place every consumer is told to read totals from.

##### PLT

###### Q1: framing. I move from A2 to A1.

Sys: "If CI kills the driver on a job timeout, every line already written stays valid. Under A2 the results of every file still in flight are lost." I had not weighed this. My A2 argument was that the binary-to-driver channel can lose nothing. But under A2, the *public* stream still loses facts when the *driver* dies, so A2 only moves the problem up one level. Under A1, each test line is a finished verdict, and it is final the moment it is written. That is the property I asked for under E1. My other A2 argument was that each line stands on its own. A1 keeps that: a test line is the §8.10 record plus `file`. Answer to AI/ML ("about 15 tokens per test"): that is a cost, not a soundness problem, and an agent that wants grouped output can filter `record == "file"`. Answer to Min ("no `PIPE_BUF` rule enters the spec"): agreed, and it should not. The spec says only "each line is one complete JSON object". How the driver keeps lines whole is an implementation matter. I accept either option. My vote moves to A1.

###### Q3: encoding. I hold T1. On nesting, I hold nested weakly and accept flat.

DevOps: "numbers differ (SIGBUS is 7 on Linux and 10 on macOS), so a tool should not have to parse a name." That is backwards. *Because* numbers differ, a number in the record means something different on each host. A consumer that branches on `7` is wrong on macOS. The name is the portable identity, so it should be the one key. Sys: "Names differ across platforms for some signals." The POSIX names are fixed. Only the realtime and vendor signals have no portable name, and Min's and AI/ML's fallback `"SIG<n>"` covers them with no second key. I accept T2 only if `signal_name` is absent when unknown (Web's condition), so the record never holds a made-up name.

On nesting, Sys's point holds: "the closed `outcome` already scopes them". The tag already says which keys may appear, so flat does not lose the sum structure. Nested states "exactly one of" in the shape, which I prefer. Flat is sound too, so I will not block it.

###### Q5: back-end failure. I move from F3 to F3+output.

DevOps: "A link failure often has 30 lines of undefined references … A separate `output` string keeps the diagnostic object clean." With that, each field has one meaning. The diagnostic is the classified fact: step, severity, first line. `output` is the raw evidence. Min: "F3+output adds a second field for text that `message` already holds." Under F3, `message` holds only the first line, so the two fields do not repeat each other. Min and AI/ML: "A C failure after a clean front end is a compiler bug." That is false whenever native deps are linked: a missing `-lfoo` is the user's environment. `ice` would then send the user to file a compiler bug, which is the misclassification AI/ML wants to avoid, in the other direction. I accept a truncation rule with a marker (DevOps, Web).

###### Q6: empty keys. I move from Z2 to Z1.

Sys: "An all-zero summary is true: the file contributed zero tests." Under the Q2c rule we passed 6-0, `summary` counts *records*. So `summary` is defined for every variant: the count over that file's records, and for `build_failed` that set is empty. A field defined on every variant is a sound common field, not a placeholder. My Z2 vote treated `summary` as "tests that ran", and Q2c replaced that meaning. Min: "describe a run that never happened". They describe an empty set of records, which is true. `outcome` stays the tag that consumers branch on. Min's `line: 0` analogy fails because `line: 0` claims a location that does not exist, while `total: 0` claims a count that is correct. The spec example should show a `build_failed` file next to a `ran` file with zero tests, as AI/ML asks.

##### DevOps/Tooling

###### Q1 (A1 vs A2): hold A1. I accept A2 if it wins.

Min: "If someone shows a need, A1 can be added later without breaking A2's lines." It cannot. If we add per-test lines later, either each test record appears twice (streamed and nested in `results`), or we remove the nesting and break every A2 consumer. So the choice is made now, not deferred. PLT: "A consumer never has to group lines by a `file` key." Every real consumer groups anyway: a JUnit converter writes one `<testsuite>` per file, and a dashboard writes one row per file. A `group_by(.file)` is one line of jq. Sys's point has no answer on the A2 side: "If CI kills the driver on a job timeout, every line already written stays valid. Under A2 the results of every file still in flight are lost." A job timeout is the most common way a CI test step ends badly, and A2 loses the results of exactly the files that hung. AI/ML: "about 15 tokens per test." This is a real cost, but an agent that wants it smaller can filter `record=="file"` plus the failing test lines. A2 cannot give back data it never streamed.

###### Q3 (encoding): I move to T1. Sub-vote: I move to flat.

PLT: "SIGBUS is 7 on Linux and 10 on macOS, so a consumer that branches on `11` is wrong on other platforms." This defeats my own T2 reason. I said the number serves cross-platform tools, but the name is the portable identity, and the number is the part that changes per platform. T1 with Min's and AI/ML's fallback: `"SIG<n>"` when no name is known, never a made-up name. On nesting: with T1 only two keys remain (`signal` or `exit_code`), and `outcome:"aborted"` already scopes them. That is the same rule we use for `span`: an optional key that the tag governs. Sys: "Flat keys are cheaper to filter (`select(.signal)`)". That is the form CI scripts write. I would still accept nested, but flat breaks the tie on the side with the simpler jq.

###### Q5 (C compile/link failure): hold F3+output. I accept F3 over F1.

Min: "A C failure after a clean front end is a compiler bug." Several are not: a missing `-lfoo` from a sidecar native dependency, `cc` not on PATH, a missing header in a vendored include path, a full disk. Each one is the user's environment. AI/ML: "An `error` severity (F3) sends the agent off to rewrite correct test code." An F3 diagnostic has no `span` and names the step ("link failed: cannot find -lfoo"). The agent gets no source location to edit, and the text points at the environment. `ice` would point the agent, and the human, at a compiler bug report that does not exist. Min and PLT: `output` is "a second field for text that `message` already holds" / "a second channel". It holds different text. A diagnostic `message` is the one-line field that every editor problems panel and GitHub annotation shows. Putting 40 lines of undefined references in it breaks those displays. PLT says "the human stream must still print the full tool output". In CI, the JSON file is often the only artifact kept, so the full text must live in the JSON too. If `output` loses, I vote F3: `error` is right, `ice` is wrong. I support Min's note on diagnostics.bl:699 for any `ice` path: omit `span`, never write `0, 0`.

###### Q6 (empty keys): hold Z1. I accept Z2.

PLT: "a zero `summary` on it blurs the line between 'ran zero tests' and 'did not build'". It does not, because `outcome` is on the same line, and `outcome` is the tag every consumer is told to branch on. Min: "a lazy consumer ... will get a missing key. That is the right failure: loud." It is loud only in some languages. In jq, `[.[] | .summary.total] | add` treats a missing key as `null` and skips it, so the sum is right by luck. In JS, `undefined + 3` is `NaN`, and a dashboard shows NaN, which is neither loud nor right. Under Z1, every consumer that sums gets the correct number with no branch, and the true fact is shown: this file contributed zero tests. "Absent, not placeholder" is about values we do not know, like `span`. A count of zero is not a placeholder. We know it is zero.

##### AI/ML

###### Q1. Wire framing: I move from A2 to A1

Sys: "If CI kills the driver on a job timeout, every line already written stays valid. Under A2 the results of every file still in flight are lost." I had not weighed this. My A2 case was token cost, about 12 extra tokens per test line. Lost results cost more: an agent that gets a killed CI log under A2 must rerun every file that was in flight to learn facts the binary had already reported. There is a second agent point. The A1 shape (one line per test, then a package or file line) is the `go test -json` shape, and models have seen a lot of it. A shape the model already knows gets copied correctly more often. Web's answer to my token point holds too: "a consumer that only wants per-file data can filter `record == "file"`". An agent can do `jq 'select(.record != "test" or .status != "passed")'` and pay only for the red lines. To Min and PLT ("per-test flushing is a channel detail"): under A1 the flushing is part of the contract, but that is the reason to choose it. The guarantee a consumer gets on a crash or a kill is then written down. I accept A2 if it wins.

###### Q3. Encoding: I hold T1, and I move from flat to nested

T1 vs T2. Sys: "The number is what `WTERMSIG` returns and is exact." It is exact on one platform only. PLT: "SIGBUS is 7 on Linux and 10 on macOS, so a consumer that branches on `11` is wrong on other platforms." A model that learns `signal == 11` from Linux training data writes wrong code for macOS users. A name has the same meaning on every platform. DevOps: "a tool should not have to parse a name". Matching the string `"SIGSEGV"` is not parsing, and it is easier than keeping a table for each platform. I hold T1 with Min's fallback `"SIG<n>"` for signals with no name.

Flat vs nested. PLT: "Nesting `termination` makes 'exactly one of signal or exit code' a single field that is itself a sum." I accept this. It also keeps the top-level keys of the file record the same for every `aborted` record, which is the same argument I made for Z1. My `rec.span` path argument was weak: `rec.termination.signal` is just as easy to find. I move to nested, and I accept flat if it wins.

###### Q5. C failure after a clean front end: I move from F1 to F3+output

Web: "A link failure is often the user's fault, for example a missing native library or a bad sidecar dependency, not a compiler bug. Calling it `ice` sends them to file a bug report instead of fixing their setup." My own Phase C concern said this, and three ballots confirm it. For an agent, `ice` means "do not touch, report upstream". On a missing `-lfoo`, that is the wrong next step. The agent should fix `blink.toml` or install the library. DevOps: "A link failure often has 30 lines of undefined references." The first line alone does not tell an agent which symbol is missing. Without the full text it reruns the build, at a high token cost. To Min ("F3+output adds a second field for text that `message` already holds"): under F3, `message` holds only the first line, so the two fields hold different facts. To PLT (F3 alone; "the human stream must still print the full tool output"): an agent that reads `--json` does not see the human stream, so that output must be in the record. I accept a truncation rule with a marker (DevOps). Min's point on diagnostics.bl:699 still applies: no `span`, never `line: 0`.

###### Q6. Empty keys: I hold Z1

PLT: "a zero `summary` on it blurs the line between 'ran zero tests' and 'did not build'." It does not, because `outcome` is the tag, as PLT says in the next sentence: "Consumers branch on `outcome`, the tag, not on which keys are present." If consumers branch on the tag, uniform keys cost nothing. If they do not, Z1 gives them a true answer, and Z2 makes their code throw. Min: "absent, not placeholder". The placeholder rule was for a value the runner does not know, like `line: 0`. Here the value is known: the file added 0 tests to the run, and the run record's sums depend on that. A zero is a true count, not a placeholder. Under A1 the `results: []` half of the question goes away, because test records are not nested, so Z1 is only the six-key `summary`. That is the same object, with the same keys, on every file line. A model learns that shape once.

##### Minimalism

###### Q1. Framing: I move to A1.

Sys: "If CI kills the driver on a job timeout, every line already written stays valid. Under A2 the results of every file still in flight are lost." That is the defect this ticket fixes, one level up. If A2 keeps it, A2 is not the smaller design. A2 also makes the driver parse every test record and write it again. A1 lets the driver pass lines through and add its own. That is less code and less risk of the driver changing a record. My own ballot concern ("A1 can be added later without breaking A2") was wrong. Adding it later means a second mode or a flag, and that is more surface than choosing A1 now. AI/ML's token cost ("about 15 tokens per test") is real but small next to one record per test. PLT's "a consumer never has to group lines by a `file` key" is the strongest point for A2. But grouping is one `group_by(.file)`, while an in-flight file lost on a timeout cannot be recovered. My conditions, which Sys, Web and DevOps already state: each line is written whole (one `write`, or under a lock), every test line carries `file`, and the file line carries no nested `results`.

###### Q3. Encoding: I hold T1. I move to flat.

PLT: "SIGBUS is 7 on Linux and 10 on macOS, so a consumer that branches on `11` is wrong on other platforms." DevOps uses the same fact for T2 ("a tool should not have to parse a name"). But the fact points the other way: the number is the key that is not portable, so a cross-platform tool should branch on the name. Two fields for one fact can disagree (DevOps's own concern). So I hold T1, with the fallback `"SIG<n>"` that AI/ML and I both asked for when a number has no name. On nesting: AI/ML says "A nested `termination` object adds a level and gives no new fact." With `outcome` closed, the flat keys are already scoped to `aborted`, and "exactly one of `signal` / `exit_code`" is one sentence either way. Fewer levels win, so I move to flat. I accept nested if the panel wants it.

###### Q5. Backend failure: I move off F1. I propose F3 with the full output in `notes`.

Sys: "A link failure is often a user's missing native library, not a compiler bug, so `ice` would be wrong." I accept it. Native-library sidecars exist, so a missing `-lfoo` is user setup, and `ice` would send the user to file a compiler bug. So: `severity: "error"`, message names the step plus the tool's first error line (F3). On full output, DevOps is right that the first line is often not enough ("30 lines of undefined references"). PLT is also right that a new `output` key is "a second channel that holds the same fact in a different form". The diagnostic schema already has a channel for it: `notes: List[Str]` (src/diagnostics.bl:385, written to JSON at :839). Put the tool output there, one entry per line. That gives DevOps the full text with no new key on the file record, and it keeps PLT's single diagnostic shape. If the panel rejects `notes`, I take F3+output over F3, because losing the linker text in JSON mode is worse than one string key. Truncation (Sys, DevOps) applies to whichever field holds it.

###### Q6. Empty keys: I hold Z2, but this is low stakes.

Web: "`rec.summary.total` works without a null check." Under A1 the run line already carries the summed totals, so no consumer needs to sum file lines. The `results: []` half of Z1 is gone too, since A1 has no nested results. What is left is one zero `summary` on a `build_failed` line. PLT: it "blurs the line between 'ran zero tests' and 'did not build', which is the exact ambiguity this ticket exists to remove." I keep Z2 for that reason. If Z1 wins I will not reopen it: the zero is at least true (the file added no tests), and `outcome` says why.

##### Re-vote ballot

Vote alone. Do not read other ballotD_*.md files. Same format per question: **Vote**, **Reasoning** (2–4 sentences), **Concern** (one sentence).
All phaseD_*.md replies are open to you. Options below come from the Phase C ballot and the Phase D replies.

###### Q1. Wire framing
- **A1** — three public line kinds: `record:"test"` (one per test, carries `file`, written as each test ends), `record:"file"` (one per file, `outcome` + six-key `summary`, no nested `results`), `record:"run"` (last).
- **A2** — two public line kinds: `record:"file"` (test records nested in `results`, written when the file ends) and `record:"run"`.

###### Q1b. Unknown record kinds (yes / no)
Sys Phase D: "the spec says a consumer must ignore a `record` value it does not know."

###### Q3. Encoding of how an `aborted` process ended
- **T1** — `"signal": "SIGSEGV"` (fallback `"SIG<n>"` when no name is known), or `"exit_code": 3`.
- **T2** — `"signal": 11, "signal_name": "SIGSEGV"` (`signal_name` absent when not known), or `"exit_code": 3`.
- Sub-vote: **nested** under `termination: {...}`, or **flat** on the file record.

###### Q5. A C compile/link failure after a clean front end
Common: outcome `build_failed`; `diagnostics` never empty; no `span` when there is no location (never `line: 0`); a truncation rule with a marker applies to whichever field holds the full tool output.
- **F1** — one diagnostic, `severity: "ice"`, tool output in `message`.
- **F3** — one diagnostic, `severity: "error"`, names the failed step, tool's first error line in `message`.
- **F3+output** — F3, plus the full tool output in an `output` string on the file record.
- **F3+notes** — F3, with the full tool output in the diagnostic's existing `notes` list, one entry per line (Min Phase D).
- **Split** — severity follows the step: C compile of generated code fails → `ice`; link or native-dependency step fails → `error` naming the step; full tool output in `message` (Sys Phase D).

###### Q6. Empty keys on a `build_failed` file record
- **Z1** — it carries an all-zero `summary`.
- **Z2** — it carries no `summary`.

Write to ballotD_<you>.md in /tmp/claude-1000/-home-nhumrich-blinklang-blink/27824fff-1a55-4182-b5e2-e721b1f00bd8/scratchpad/ and return it as your reply.

##### Systems

###### Q1. Wire framing
**Vote:** A1
**Reasoning:** Each test line is final as soon as it is written. A driver killed on a CI job timeout loses nothing it has already written. The driver passes lines through and adds its own, so it does not parse and rewrite records. That is less code and no risk of changing a record on the way.
**Concern:** The driver must write each line whole (one `write`, or under a lock) while parallel files run, or the stream tears in the exact way this ticket fixes.

###### Q1b. Unknown record kinds
**Vote:** yes
**Reasoning:** One sentence lets us add a new line kind later (a timing or coverage line, say) without breaking consumers. Go's test2json relies on the same rule. It costs no wire surface.
**Concern:** A consumer that skips unknown kinds could also skip a future kind that matters for pass/fail. Any new kind must never change what the `file` and `run` lines say about the outcome.

###### Q3. Encoding of the abnormal end
**Vote:** T1, flat
**Reasoning:** PLT is right: the number is the part that is not portable (SIGBUS is 7 on Linux and 10 on macOS), and the name is the identity. The fallback `"SIG<n>"` covers realtime signals with no second key. `outcome:"aborted"` already scopes the flat keys, the same way it scopes `diagnostics` on `build_failed`.
**Concern:** The implementation must build the name from `WTERMSIG` on the real wait status, never from `128+n`.

###### Q5. C compile/link failure after a clean front end
**Vote:** F3+notes
**Reasoning:** I drop my Split. The generated C also includes user-vendored headers, so even a C compile failure can be the user's setup, and the step does not cleanly decide who is at fault. `error` naming the step, with no `span`, is right for all cases. `notes` is an existing list field of the diagnostic schema, so the full tool output fits with no new key and no multi-line `message`. I accept F3+output as second choice.
**Concern:** A long linker output becomes many `notes` entries. The truncation rule with a marker must apply to the list, or one bad link floods an editor's problems panel.

###### Q6. Empty keys on a build_failed file record
**Vote:** Z1
**Reasoning:** Under Q2c, `summary` counts records, and a file that did not build has zero records, so the zero is a true count, not a placeholder. Every file line has the same keys, so summing in JS or jq needs no branch. `outcome` remains the tag.
**Concern:** A careless reader may take a zero summary for "built, no tests". The spec example should show both cases side by side.

##### Web/Scripting

###### Q1. Wire framing
**Vote:** A1
**Reasoning:** When a CI job times out, A2 loses the results of every file still running. That is the same loss this ticket fixes for crashes. A1 gives editor panels and watch-mode reporters live per-test progress, the way vitest and jest work today. A consumer that wants only files can filter `record == "file"` in one line.
**Concern:** Lines from parallel files interleave, so example code in the spec must show consumers grouping by `file`, not by line order.

###### Q1b. Unknown record kinds
**Vote:** yes
**Reasoning:** This is the rule every JS consumer of an event stream already follows: switch on the type and ignore the default case. It lets us add a line kind later (a test-start line, coverage) without breaking any existing parser. It costs one sentence.
**Concern:** Consumers that ignore unknown kinds can also miss a new kind that matters, so a new kind must never carry a fact that affects pass/fail.

###### Q3. Termination encoding
**Vote:** T1, nested
**Reasoning:** Signal numbers differ between platforms (SIGBUS is 7 on Linux and 10 on macOS), so the name is the only portable fact, and one key per fact means nobody asks which key to read. Nesting under `termination` keeps "exactly one of signal / exit_code" in one small object. It also stops a top-level `exit_code` from being misread as `blink test`'s own exit code.
**Concern:** The `"SIG<n>"` fallback must be stated in the spec, or each implementation will make up its own spelling.

###### Q5. C compile/link failure
**Vote:** Split
**Reasoning:** This is the only option whose severity is correct in both cases. If the generated C fails to compile, that is a compiler bug (`ice`, "report it"). If the link or a native dependency fails, that is the user's setup (`error`, "fix your environment"). F1 sends users with a missing `-lssl` to file compiler bugs, and every F3 form tells users to edit correct code when codegen broke. Users need the full tool output, and the truncation rule keeps it bounded.
**Concern:** A multi-line `message` can break renderers that expect one line, so I would prefer the tool output in the existing `notes` list (Min's form) if the moderator can merge that into Split.

###### Q6. Empty keys on `build_failed`
**Vote:** Z1
**Reasoning:** In JavaScript a missing `summary` does not fail loudly. `total += rec.summary?.total` silently gives `NaN`, and `rec.summary.total` throws only on the rare run where a file did not build. An all-zero summary is true (the file added zero tests), and `outcome` already says why.
**Concern:** A reader may take a zero summary to mean "built, had no tests", so the spec example should show a `build_failed` record next to a zero-test `ran` record.

##### PLT

###### Q1: A1
**Reasoning.** Each test line is a finished verdict and becomes final the moment it is written. So the public stream keeps every observed fact even when the driver itself is killed, which A2 cannot promise. Each line still stands on its own: the §8.10 record plus `file`.
**Concern.** Lines from parallel files interleave, so the driver must keep each line whole. That belongs in the implementation, not in the spec.

###### Q1b: yes
**Reasoning.** The `record` kind is the envelope, and the envelope should be open so a later line kind does not break old consumers. The value enums inside a record (`status`, `cause`, `outcome`) stay closed. The spec should say exactly that: kinds are open, values are closed.
**Concern.** A consumer may read "ignore unknown records" as permission to ignore unknown `outcome` values, so the spec must state the difference explicitly.

###### Q3: T1, nested
**Reasoning.** The signal name is the portable identity of a signal. A number means different things on different hosts, and two keys for one fact can disagree. Nesting `termination` puts "exactly one of signal or exit code" in the shape of the data.
**Concern.** The `"SIG<n>"` fallback puts a host-specific number inside a name-shaped string, so consumers must treat it as opaque.

###### Q5: Split
**Reasoning.** The severity should state the true category of the fault, and the driver knows which step failed. A failed C compile of generated code is a compiler bug (`ice`). A failed link or native-dependency step is the user's setup (`error`). Every single-severity option mislabels one of the two cases. Full text in `message` keeps one diagnostic shape, with no extra key.
**Concern.** A native-dependency C source that fails to compile must be classed under the native-dependency step, not as generated code, or it will read as `ice`.

###### Q6: Z1
**Reasoning.** Q2c defines `summary` as the count of a file's records, so it is defined on every `outcome`. For `build_failed` that count is zero, which is true. A field that is defined on every variant is a sound common field, not a placeholder.
**Concern.** A consumer may still read zero as "ran zero tests" unless it checks `outcome`. The spec example should show both cases side by side.

##### DevOps/Tooling

###### Q1. Wire framing — **A1**
Reasoning: Live per-test lines are what editor test panels, CI annotators and `--rerun-failed` read. A CI job timeout that kills the driver keeps every line already written. A2 loses every file still in flight on the most common bad end of a CI step. Adding per-test lines later would mean a second mode or duplicate records, so this cannot be deferred.
Concern: Parallel files interleave lines, so the driver must write each line whole (one `write` or under a lock), and the spec must say every test line carries `file`.

###### Q1b. Unknown record kinds — **yes**
Reasoning: This is the standard forward-compat rule for any event stream (go test -json consumers ignore unknown `Action` values). Without it, every new line kind breaks strict consumers, and we will add kinds later, for example a `test_start` line if `running` needs it.
Concern: Consumers that ignore unknown kinds can silently miss a new failure kind. A new kind must never be the only carrier of a red outcome. The `run` line and the exit code stay the authority.

###### Q3. Encoding — **T1, flat**
Reasoning: PLT showed that signal numbers are the non-portable part, so the name is the identity, with `"SIG<n>"` as the fallback when no name is known. `outcome:"aborted"` already scopes `signal` / `exit_code`, the same way it scopes `diagnostics` on `build_failed`. Flat keys give CI scripts the simple filter `select(.signal)`.
Concern: A Linux-only tool that wants the raw number now has to map the name back. That case is rare and can be done locally.

###### Q5. C compile/link failure — **F3+notes**
Reasoning: `severity:"error"` is right, because link, native-dependency and FFI-header failures are the user's setup. Even a compile of generated C can fail on a user's `@ffi` header mismatch, so Sys's split would mislabel some of those as `ice`. `notes` already exists in the diagnostic schema, so the full tool output lands in the JSON artifact with no new key. `message` stays one line for problem panels and GitHub annotations. That joins my need (full text in CI artifacts) with PLT's (one diagnostic shape).
Concern: A real codegen bug that shows up as a C compile error is reported as `error`, not `ice`, so the step name in `message` must make "generated C failed to compile" plain enough that a user knows to report it.

###### Q6. Empty keys — **Z1** (weak; I accept Z2)
Reasoning: Under A1 the run line already carries the totals, so the summing argument is weaker than before. Uniform keys still mean one schema per `record` kind, and a zero is the true count of tests the file added. It is not a placeholder.
Concern: A reader that ignores `outcome` may take a zero summary as "built, no tests". The spec example should show a `build_failed` line next to a `ran` line with zero tests.

##### AI/ML

###### Q1. Wire framing
**Vote:** A1
**Reasoning:** If CI kills the driver, or a binary crashes, every test line already written stays valid, so an agent never has to rerun a file to learn facts the binary already reported. The shape is the `go test -json` shape (one line per test, then one per package), which models have seen often and copy correctly. Token cost is under the agent's control: it can filter with `jq 'select(.record != "test" or .status != "passed")'` and read only the red lines.
**Concern:** A model may assume that test lines from one file arrive together. The spec example should show lines from two files mixed together, so that no model learns the wrong order.

###### Q1b. Unknown record kinds
**Vote:** yes
**Reasoning:** Models write exhaustive `match` or `switch` over the values they have seen, and they raise an error on anything else. One sentence that says "ignore a `record` value you do not know" lets a later line kind (for example a test-start line) land without breaking every consumer that agents wrote. It costs no wire surface.
**Concern:** The rule covers `record` values only. A model may stretch it to "ignore unknown `outcome` values", and `outcome` must stay a closed enum.

###### Q3. Encoding of an abnormal end
**Vote:** T1, nested
**Reasoning:** A signal name means the same thing on every platform. A number does not (SIGBUS is 7 on Linux and 10 on macOS), so a model that learns `== 11` from Linux examples writes wrong code for macOS users. The `"SIG<n>"` fallback keeps one key and one type. Nesting under `termination` makes "exactly one of signal or exit code" one small sum, and keeps the same top-level keys on every file record.
**Concern:** A consumer that branches on `"SIG<n>"` strings is not portable either, but only realtime or unknown signals reach that path.

###### Q5. C compile/link failure after a clean front end
**Vote:** Split
**Reasoning:** The severity is the field an agent uses to choose its next step, so it must be true for each cause. If the C compile of generated code fails, that is a compiler bug, and `ice` correctly says "do not edit your code, report it". If the link or native-dependency step fails, the cause is the user's setup, and `error` with the step named says "fix `blink.toml` or install the library". The full tool output in `message` gives the agent the missing symbols without a rebuild, with no new key and no second diagnostic shape.
**Concern:** A C compile error caused by a user's vendored header or `@ffi` C declaration will read as `ice`. The message text must make that case visible.

###### Q6. Empty keys on a `build_failed` record
**Vote:** Z1
**Reasoning:** Under A1 this is only the six-key `summary`, and with Z1 it has the same keys on every file line. Then `rec.summary.total` never throws, and a model learns the shape once. Zero is a known, true count (the file added no tests to the run), not a placeholder for an unknown value. `outcome` remains the tag that says why the counts are zero.
**Concern:** A consumer that does not check `outcome` may read the zeros as "the file built and has no tests". The spec example should show a `build_failed` line and a zero-test `ran` line side by side.

##### Minimalism

###### Q1. Wire framing: **A1**
- **Reasoning:** A2 still loses every in-flight file when CI kills the driver on a timeout. That is the defect this ticket fixes, one level up. A1 lets the driver pass lines through instead of parsing and rewriting every record, so it is less driver code. Adding A1 later would cost a second mode or a flag, which is more surface than choosing it now.
- **Concern:** under `-P`, test lines from different files interleave, so the "write each line whole" rule must be normative, or we ship torn JSON again.

###### Q1b. Unknown record kinds: **yes**
- **Reasoning:** One sentence now lets a later record kind ship without a flag, a version key or a second mode. Without it, every new line kind is a breaking change, and that pushes the language toward adding modes. This is the cheapest kind of rule: it prevents future surface.
- **Concern:** it can become an excuse to add record kinds freely. Each new kind still needs its own vote.

###### Q3. Encoding: **T1, flat**
- **Reasoning:** Signal numbers are not portable (SIGBUS 7 vs 10), so the name is the key a tool should branch on, and a second field for the same fact can disagree with the first. `"SIG<n>"` covers a number with no name. `outcome` is closed, so flat keys already belong only to `aborted`, and a nested object adds a level with no new fact.
- **Concern:** a tool that wants the raw number must map the name back, which on an unknown signal means parsing `"SIG<n>"`.

###### Q5. Backend failure: **Split**
- **Reasoning:** Split is the only option that gives each case its true severity. C that the compiler generated and that does not compile is a compiler bug (`ice`). A link or native-dependency failure is the user's setup (`error` naming the step). Both severities already exist, so Split adds nothing. F3+notes, my own proposal, would label a codegen bug as a user error.
- **Concern:** full tool output in `message` makes a long, multi-line message. I ask that the spec text put it in the existing `notes` list, one line per entry, with `message` holding the step and the first error line, as in F3+notes.

###### Q6. Empty keys: **Z2**
- **Reasoning:** A file that did not build has no tests (§8.10.5), and under A1 the run line already carries the summed totals, so no consumer needs to sum file lines. A zero `summary` on a `build_failed` line brings back the "ran zero tests" vs "did not build" ambiguity that `outcome` exists to remove.
- **Concern:** low stakes either way. If Z1 wins, the zero is at least true, and I will not reopen it.

#### User decisions

- **Q3 sub-vote (3-3 after Phase D):** the user (BDFL) broke the tie for **flat** keys.
- **Q5 output field:** Split as balloted put the full tool output in `message`. Four panelists (Systems and DevOps in their F3+notes votes, Minimalism and Web/Scripting in their Split Concerns) asked for the existing `notes` list. The user chose **`notes`**.

### Final Spec

```json
{"record": "test", "file": "tests/test_ffi.bl", "name": "opens mapping", "status": "passed", "duration_ms": 3}
{"record": "file", "file": "tests/test_parse.bl", "outcome": "build_failed", "summary": {"total": 0, "passed": 0, "failed": 0, "panicked": 0, "skipped": 0, "duration_ms": 0}, "diagnostics": [...]}
{"record": "file", "file": "tests/test_ffi.bl", "outcome": "aborted", "signal": "SIGSEGV", "running": "reads mapped page", "summary": {"total": 1, "passed": 1, "failed": 0, "panicked": 0, "skipped": 0, "duration_ms": 9}}
{"record": "run", "summary": {...}, "files": {"total": 2, "ran": 0, "build_failed": 1, "aborted": 1}}
```

- `blink test --json` is NDJSON with a `record` key: `test` (per test, as it ends, carries `file`), `file` (one per file), `run` (last). A consumer ignores an unknown `record` value.
- `outcome` is closed: `ran | build_failed | aborted`. Test `status` and `cause` are unchanged; a signal never becomes `panicked`.
- `aborted` = ended by a signal, or exited before the end-of-run report (`exit(0)` included). Flat `signal` (name, `"SIG<n>"` fallback) or `exit_code`, never both; optional `running`, never a guess.
- `build_failed` carries `diagnostics` (§8.6 shape, never empty, no `span` without a location). A back-end failure gives one diagnostic: `ice` for generated C, `error` for link/native-dependency, first error line in `message`, full output in `notes` (may be cut, with a last entry saying so).
- Every `file` line carries the six-key `summary`; zero for `build_failed`. Test lines of an aborted file stay and count; `files.aborted > 0` makes the counts a lower bound.
- Exit 1 when `failed + panicked + files.build_failed + files.aborted > 0`. A file that does not build never stops the run.
- Human output: `BUILD FAILED` + diagnostics; `ABORTED` + `signal SIGSEGV` / `exit code 3` and the test name when known; file clauses on the summary line only when above 0.

Spec: [§8.10](../sections/06_tooling.md) (stream, summary, exit code) and §8.10.5 (file outcomes).
