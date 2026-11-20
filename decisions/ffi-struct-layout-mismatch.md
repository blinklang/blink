[< All Decisions](../DECISIONS.md)

# A Struct Mirror That Does Not Match Its C Struct — Design Rationale

**Gap:** §9.1.3 said that for every `@ffi.struct` the build checks the size and the offsets, and that a mismatch makes the build fail and report the struct and the field. It gave no code and no exit. The compiler reported a mismatch as `GeneratedCDidNotCompile` (I0017, exit 101), the code for a compiler bug. A mirror that differs from its C struct is an error in the user's source, and the cause is known.

```blink
@ffi.struct(header: "time.h", name: "timespec")
type Ts { tv_sec: I64, tv_nsec: I32 }    // C `tv_nsec` is 8 bytes on x86_64-linux-gnu
```

Before this decision, `blink build` stopped with I0017 and exit 101 and said "this is a compiler bug". After it, `blink build` stops with `ForeignStructMismatch` (E0862) at the `@ffi.struct` line and exits 1.

This decision relates to [What a Clean `blink check` Promises](check-build-promise.md) and to [A `Ptr` at an `@ffi` Call](ffi-pointer-prototype.md). The first said that I0017 is a compiler bug. The second added the prototype test (E0861) with the same rule: the test reads only pass or fail.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q0 | Does the spec need a change? | Yes. | 6-0 |
| Q1 | Which code and exit? | `ForeignStructMismatch` (E0862), a row of §6.7.3, exit 1, from `blink build` and `blink test` only. `blink check` reports nothing. No unit compiles. I0017 keeps only a stop that no test explains. | 6-0 |
| Q2 | One code or several? | One code for five kinds: NoName, NoField, Offset, FieldSize, StructSize. The kind is in the message and in the JSON. One report for each mirror (the first failing check, in order); every bad mirror in one run. | 6-0 |
| Q3 | Per target or not? | Per target. The message names the target triple. | 6-0 |
| V2 | Test order | Header test (E0859), then layout test (E0862), then prototype test (E0861). | 6-0 |
| V1 | Where the primary span points for NoField, Offset and FieldSize | `V1-D`: the `@ffi.struct` line, with a secondary label on the Blink field. | 5-1 (AI/ML dissents for `V1-F`: the field line) |
| V3 | How the test reaches its verdict | `V3-P`: the test reads only pass or fail. The kind and the field are the same under gcc 13 or later, clang and `zig cc`. `tcc` is outside the promise, as for E0861. The mechanism is not spec text. | 6-0 |

The owner approved the tally. Phase D did not run: no question was left open after Phase C.

### Dissent

**AI/ML, V1** voted `V1-F` (the primary span on the Blink field line). The vote, verbatim:

> Reasoning: An agent edits the line that the primary span names. Many tools and agent loops read only the JSON `span` and drop secondary labels. If the field is the primary span, the fix is one step. If the declaration line is the primary span, the agent must find the field name in the message text and then search for its line, and that is where wrong edits come from. NoName and StructSize stay at the declaration line under both options, so V1-F adds no new rule to learn: the span is the line to edit.
>
> Concern: If V1-D wins, the field label must be in the JSON (in a field that tools read, not only in the human text). If it is not, agents lose the field location.

The panel chose `V1-D`. Systems and DevOps gave this concern in their votes: with `V1-D` the message names the field in words, so a tool that shows only the primary span still shows the field. AI/ML's own concern is met in the spec: the JSON form carries the field as a `related` location.

Writer notes from the Phase C votes, and where the spec meets them:

- The message names the field, not only the label (every seat). §9.1.3 says so.
- The JSON carries the field as a related location (AI/ML, DevOps). §9.1.3 and §8.10.5 say so.
- The layout test proves size and offset only, not sign, float or integer kind, or pointee (Systems, PLT, Web/Scripting). §9.1.3 says so and shows PLT's `tv_nsec: Float` case, which builds.
- A size message names the Blink-side size, for example "`I32` is 4 bytes" (Web/Scripting). §9.1.3 and the E0862 row show it.
- The help says that a C field that the mirror lacks shows as an Offset or StructSize kind (Systems). §9.1.3 says so.
- The NoName help says to check `name:`, and that a C type with no visible fields is an `@ffi.opaque` (AI/ML, DevOps). §9.1.3 says so.
- Every text that put a layout mismatch under I0017 now names E0862: §6.7.3, the §8.10.5 note, and the catalog rows for I0017 and the E08xx family.

## Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal, debate and vote rounds. Each panelist's text below is a verbatim copy of the panelist's own reply. A ticket ID or a scratch file path that the reply contains shows as `[ticket]` or `[scratch path]`.

### Phase A — Independent proposals

- **Systems:**

> # [ticket] Phase A: Systems seat (sys)
>
> ## Answers in short
>
> - Q0: Yes, the spec needs a change. Exit 101 means "compiler bug" (check-build-promise). A mirror that differs from its C struct is a user error that the build finds with a known cause. The note "This is a compiler bug" is false here.
> - Q1: Its own code, a §6.7.3 row, at the `@ffi.struct` line, exit 1, build and test only. Working name `ForeignStructMismatch` (E08xx). This is the same pattern as E0855, E0859 and E0861.
> - Q2: One code for all five kinds. The message and the JSON `kind` field say which one.
> - Q3: The verdict is per target. The code is the same on every target, and the message names the triple. `blink check` never reports it.
>
> ## Proposal S1: one code, one probe, I0017 stays the backstop
>
> ### Behavior
>
> The build already runs one C compile for the spelling probe before any unit compiles. The layout lines go in the same file (src/ffi_layout_probe.bl), so the check costs no extra C compiler run. The units keep their `_Static_assert` lines. They have no run-time cost.
>
> Proposed order in `blink build` and `blink test` (I did not confirm the order main uses today): header test (E0859), then spelling and layout probe (new code), then prototype test (E0861), then the unit compile. A mismatch stops the build before the unit compile, exit 1.
>
> For each mirror, report one mismatch, the first in this order: NoName, NoField, Offset or FieldSize (in field order), StructSize. Field order matters: a wrong size on field k moves the offset of field k+1. The first failed field is the cause, the later offsets are only effects.
>
> If the probe gives no verdict (a cc error that is on no check line, an error limit, a C compiler whose error format the probe cannot map, such as `tcc`), the build goes on. The unit asserts then fail, and the stop is I0017 as today. Its note names the program's `@ffi.struct` mirrors as a possible cause. This keeps the rule "no parsing of cc text" as true as E0855 keeps it: the probe reads only which line of its own file failed, not the message.
>
> ### Examples (probes run on main, x86_64-linux host)
>
> Field C lacks:
> ```blink
> @ffi.struct(header: "time.h", name: "timespec")
> type Ts { tv_sec: I64, tv_nsec: I64, extra: I64 }
>
> fn main() {
>     io.println("ok")
> }
> ```
> - check: ok, exit 0.
> - build, test: `error[ForeignStructMismatch]` at line 1 (the `@ffi.struct` line): "`Ts` does not match C struct `timespec` on x86_64-linux-gnu: C struct `timespec` has no field `extra`, or `extra` is a bit-field". Exit 1. Today: I0017, exit 101.
>
> Field of the wrong size:
> ```blink
> @ffi.struct(header: "time.h", name: "timespec")
> type Ts { tv_sec: I64, tv_nsec: I32 }
> ```
> - check: ok. build, test: new code, line 1, "field `tv_nsec` has a different size", exit 1. (Probe today: I0017 with this text, exit 101.)
>
> Name that is no tag or typedef:
> ```blink
> @ffi.struct(header: "time.h", name: "timespek")
> type Ts { tv_sec: I64, tv_nsec: I64 }
> ```
> - check: ok. build, test: new code, line 1, "`time.h` declares no complete struct tag and no complete typedef name `timespek`", help names `@ffi.opaque` for a type with no visible fields. Exit 1.
>
> Matches on one target, differs on another:
> ```blink
> @ffi.struct(header: "netinet/in.h", name: "sockaddr_in")
> type SockIn { sin_family: U16, sin_port: U16, sin_addr: U32, sin_zero: U64 }
>
> fn main() {
>     io.println("ok")
> }
> ```
> - check: ok on every target (it reads no header).
> - `build` (linux): builds, exit 0.
> - `build --target macos-arm64`: new code, line 1, "on aarch64-macos: field `sin_family` is at a different offset", exit 1. BSD and macOS put `uint8_t sin_len` first. (Probe today: I0017, exit 101.)
>
> Missing field (the mirror lacks a C field): the probe cannot list C's members, so this shows as Offset on the next field, or StructSize if the missing field is last. Same code. The help should say "a field may be missing before this one" for Offset and StructSize.
>
> ### Why one code (Q2)
>
> All five kinds have one cause: the mirror's claim about C memory is false on this target. All five have one fix: copy the C struct as it is on that target. E0861 also uses one code for every prototype mismatch. NoName is the one with a different fix (spelling, or `@ffi.opaque`), but the message and help already split it. A second code adds a catalog row and an explain page for a case that the `kind` field covers. Tools that want to branch read `kind` in the JSON: `no_name`, `no_field`, `offset`, `field_size`, `struct_size`.
>
> ### Systems tradeoffs
>
> - Cost: zero at run time; zero extra C compiler runs at build time (one shared probe file). The per-target cost is one probe per target that a build uses, which the build already pays.
> - Why at build, not at check: only the target's C compiler knows `offsetof` on that target. Padding, `time_t` width, `long` width and BSD `sin_len` are target facts. A check that guessed them from Blink tables would be a second copy of every libc layout, and it would drift.
> - Why not keep I0017: exit 101 tells CI and users "file a compiler bug". A wrong mirror is the most common FFI mistake. It must exit 1 with the field named, like E0855.
> - Precision limit: a layout check proves size and offset only. It does not prove sign (`U32` against `int32_t`) or a pointer's pointee. Signed/unsigned of equal size passes. That is the same limit as bindgen tests; the spec should state it so nobody reads E08xx as "types checked".
> - Bool fields: the probe does not compare their size today (`size_checked`). Their offset is still checked.
>
> ### Cross-language note
>
> - Rust bindgen emits layout tests (size, align, `offset_of!`) per target; a failure is a raw const-eval or test failure with no source span on the user's type. Hand-written `#[repr(C)]` mirrors get no check at all. Blink can do better: a span and the field.
> - Zig `@cImport` and Go cgo (`C.struct_timespec`) translate the C struct, so the user writes no mirror and no mismatch exists. Blink chose hand mirrors, so it owes the user the check with a real error.

- **Web/Scripting:**

> # web seat, [ticket] Phase A
>
> ## Probe (main today, x86_64-linux-gnu)
>
> `tv_nsec: I32` mirror and a `name: "timespek"` mirror: `blink check` exit 0; `blink build` exit 101 with two `internal compiler error[GeneratedCDidNotCompile]` reports, each ending "note: this source passes `blink check`; the cause is a bug of the compiler" and "This is a compiler bug. Please report it". The size report says only "field `tv_nsec` has a different size".
>
> The first line a user reads tells them the compiler is broken, and the last line tells them to file a bug. A typo in `name:` is not a compiler bug. Each of these reports will become a GitHub issue. That is the DX cost of doing nothing.
>
> ## Proposal W1: one new code, `ForeignStructMismatch` (next free, E0862), exit 1
>
> **Q0:** Yes, change the spec. I0017 is wrong for this case even if the note names the struct and field. The "compiler bug" text is false, and the I0017 explain page says the notes hold cc output, which is also false. §9.1.3 says "the build fails and reports the struct and the field". That reads as a user error.
>
> **Q1:** A §6.7.3 row with its own code at the `@ffi.struct` line, exit 1, from `blink build` and `blink test` only. This matches E0855 (bad `@ffi let`), E0859 (no header) and E0861 (wrong prototype). Today we have three @ffi build-time user errors with their own codes, and the fourth is an ICE. A JS or Python dev learns one rule: "@ffi problems that need the header show up at build, as a normal error with a code". No exceptions to memorize. I0017 stays the backstop for a mismatch the probe cannot map to a check line (the units' `_Static_assert`s), the same split as E0861.
>
> **Q2:** One code for all five kinds. The message line changes by kind; the code and the `blink explain` page do not. Reason: the user's fix is the same in every case ("make the mirror match the C struct on this target"), and the user does not care which check failed first. E0855 sets the pattern: a misspelled C name and a value that does not fit share one code. Five codes means five explain pages and five search terms for one mistake.
>
> The no-tag-or-typedef case gets its own help (spelling, or use `@ffi.opaque`), as today. Same code.
>
> Ask: the size and offset messages should name the Blink side ("`tv_nsec: I32` is 4 bytes; the C field has a different size"). The probe reads pass/fail per line, so it cannot give the C number; the Blink number is free and halves the guesswork.
>
> **Q3:** `--target` changes no answer. The check runs per target, the verdict is per target, and the message names the triple. Same code and exit on every target.
>
> ## Examples
>
> ```blink
> @ffi.struct(header: "time.h", name: "timespec")
> type Ts { tv_sec: I64, tv_nsec: I64, extra: I64 }
> ```
> - check: ok, exit 0.
> - build / test: `error[ForeignStructMismatch] (E0862)` at line 1 (the `@ffi.struct` line): "`Ts` does not match C struct `timespec` on x86_64-linux-gnu: C struct `timespec` has no field `extra`". Exit 1. The unit compile does not start.
>
> ```blink
> @ffi.struct(header: "time.h", name: "timespec")
> type Ts { tv_sec: I64, tv_nsec: I32 }
> ```
> - check: exit 0. build / test: E0862 at line 1, "field `tv_nsec` has a different size (`I32` is 4 bytes)". Exit 1.
>
> ```blink
> @ffi.struct(header: "time.h", name: "timespek")
> type Ts { tv_sec: I64, tv_nsec: I64 }
> ```
> - check: exit 0. build / test: E0862 at line 1, "`time.h` declares no struct tag and no typedef `timespek` on x86_64-linux-gnu"; help names spelling and `@ffi.opaque`. Exit 1.
>
> A mirror that matches one target and differs on another (`struct stat` on Linux: `st_nlink` is 8 bytes after `st_ino` on x86_64, but 4 bytes after `st_mode` on aarch64):
> ```blink
> @ffi.struct(header: "sys/stat.h", name: "stat")
> type Stat { st_dev: U64, st_ino: U64, st_nlink: U64 }
>
> fn main() {
>     io.println("ok")
> }
> ```
> - check: exit 0 (no header, any target).
> - `blink build`: E0862 at line 1 for the first field that differs, if any (here StructSize: the mirror is not all of `stat`).
> - `blink build --target aarch64-linux-gnu`: E0862 at line 1, "... on aarch64-linux-gnu: field `st_nlink` has a different offset". Exit 1. The triple in the message is what tells the user the mirror is target-specific.
>
> ## Tradeoffs
>
> - For: the report tells the truth. "error" not "internal compiler error"; no "please report it". Fewer false bug reports; one code to google; the same shape as E0855/E0859/E0861.
> - For: exit 1 vs 101 matters to CI scripts and to AI agents that treat 101 as "not my fault, stop".
> - Against: one more catalog code. Small price; it already has its own message text and help.
> - Against: check still says ok. That is decided (check reads no header). The build is where the user learns it, same as E0859/E0861.
>
> ## Cross-language
>
> - Rust bindgen: layout tests are generated `#[test]`s with `assert_eq!(size_of::<T>(), N)`; a failure is a plain test failure naming the struct and field, never a "rustc bug". Users understand it.
> - Go cgo: you cannot hand-write a mirror; cgo reads the C struct (`C.struct_timespec`), so the mismatch cannot exist. Zig `@cImport` is the same. Blink chose hand mirrors, so it owes a clear user error.
> - Python ctypes: no check at all; a wrong mirror is silent memory corruption. Blink's check is better than ctypes, so do not make it look like a crash.
>
> ## Side note for the moderator (not a vote)
>
> There is no per-target way to write a mirror (no C-sized ints, no target conditional). So for the `stat` case, E0862 tells the user the truth but gives no fix in Blink except "do not mirror that struct". That gap is outside this ticket; it may deserve a friction ticket.

- **PLT:**

> # [ticket] Phase A: PLT seat
>
> ## Position
>
> Q0: the spec must change. Q1: own code, exit 1. Q2: one code. Q3: the verdict is a function of (source, target); --target changes the result, not the rule.
>
> ## Why I0017 is wrong here (the rule)
>
> decisions/check-build-promise.md fixes the meaning of exit 101: a compiler bug. Today's report contradicts itself. It says "the cause is a bug of the compiler" and then tells the user to change their own type. A code must have one meaning; I0017 now has two. The mismatch is a decided judgment, not raw cc text: the probe gives a kind, a field and a span. Each other decided judgment of the C side already has its own exit-1 code, at the declaration: E0855 (the claim of an `@ffi let`), E0859 (the header), E0861 (the claim of an `@ffi fn`). An `@ffi.struct` is the third form of an `@ffi` claim. The same rule gives the same answer: **a false `@ffi` claim that a build test finds is a Blink error at the claim, exit 1; I0017 keeps only what no test finds.** Then I0017 stays sound: it fires only when no test explains the stop.
>
> ## Proposal P1: `ForeignStructMismatch` (E0862)
>
> - Found by `blink build` and `blink test`, never by `blink check` (check runs no C compiler).
> - Span: the `@ffi.struct` line. Exit 1. No unit compile starts.
> - Message names the mirror, the C name and the target triple (as E0855 does). Help as today, without the ICE note and without "this source passes blink check".
> - One diagnostic per mirror: the first check that fails, in a fixed order (name, then fields in mirror order, then struct size). Every bad mirror reports in one run.
> - Order of the build tests: header test (E0859), then layout test (E0862), then prototype test (E0861). The layout test must come before E0861: a `Ptr[Ts]` where `Ts` names no C type would also fail the prototype probe and blame the wrong `@ffi fn` line. Root cause first, once.
> - If the probe itself fails for a cause it cannot name, that stays I0017 (no change to the one-I0017 rule; we never parse cc text).
>
> ### Examples (host x86_64-linux-gnu; all verified on main with the probe)
>
> ```blink
> @ffi.struct(header: "time.h", name: "timespec")
> type Ts2 { tv_sec: I64, tv_nsec: I64, extra: I64 }
> ```
> check: ok, exit 0. build/test: `error[ForeignStructMismatch] (E0862)` at line 1: `` `Ts2` does not match C struct `timespec` on x86_64-linux-gnu: C struct `timespec` has no field `extra`, or `extra` is a bit-field ``, exit 1. Test: file `build_failed` with this one diagnostic, span kept.
>
> ```blink
> @ffi.struct(header: "time.h", name: "timespec")
> type Ts { tv_sec: I64, tv_nsec: I32 }
> ```
> check: exit 0. build/test: E0862 at line 1, `field `tv_nsec` has a different size`, exit 1.
>
> ```blink
> @ffi.struct(header: "time.h", name: "timespec")
> type Ts1 { tv_sec: I64 }
> ```
> (a missing field) check: exit 0. build/test: E0862, `the struct has a different size`, exit 1.
>
> ```blink
> @ffi.struct(header: "time.h", name: "no_such_ts")
> type Nope { a: I64 }
> ```
> check: exit 0. build/test: E0862 at line 1, `` names `no_such_ts`, but `time.h` declares no complete struct tag and no complete typedef name `no_such_ts` on x86_64-linux-gnu ``; help points to `@ffi.opaque` for a type with no visible fields. Exit 1.
>
> ```blink
> @ffi.struct(header: "time.h", name: "timespec")
> type Ts { tv_sec: I64, tv_nsec: I64 }
>
> fn main() {
>     io.println("ok")
> }
> ```
> `blink build`: exit 0. `blink build --target x86-linux-gnu` and `--target arm-linux-gnueabihf`: E0862 at line 1, `` field `tv_sec` has a different size `` (32-bit `time_t`), exit 1. check: exit 0 for every target.
>
> ## Q2: one code, not five
>
> All five kinds are one predicate: "the C layout of the mirror is not the layout of the named C type on this target". NoName is the empty case of that predicate (no layout to match), the same way E0855 folds "the headers do not define the name" into the same code as "not a constant" and "does not fit". Distinct fixes go in the help and a fixed message text per kind (the E0860 pattern), so a tool can tell kinds apart without five codes. Splitting would make a code per probe step, which ties the catalog to the implementation, not to the claim. Bit-field stays in NoField: `offsetof` on a bit-field is not defined, so the probe cannot tell "absent" from "bit-field", and the message must not claim more than the test decides.
>
> ## Q3: --target
>
> The test runs per target with that target's C compiler, so the result is per target, and the message names the triple. No rule changes. The check-build promise is untouched: check ok, build exit 1 is a user error, not a broken promise (101 is the only exit the promise forbids).
>
> ## Boundary the spec must state (soundness)
>
> The test checks **size and offset only**, as §9.1.3 says. A field of the right size and wrong kind passes. Verified: `type Ts { tv_sec: I64, tv_nsec: Float }` against `timespec` builds, exit 0, and reads `long` bits as a double. E0862 must not be described as "the mirror matches C". It means "the layout matches". The spec text (and `blink audit`) should say the field kinds are the author's claim. Widening the test to kinds is a separate question; I do not ask for it here.
>
> Second gap, for friction, not this ticket: Blink has no C-sized integer (`long`, `time_t`), so the last example has no portable mirror. E0862 reports it correctly; the language gives no fix.
>
> ## Tradeoffs
>
> - Pro: exit 101 keeps one meaning; I0017 regains soundness ("only what no test explains"). Same rule as E0855/E0859/E0861, so the four `@ffi` checks compose into one story.
> - Pro: one code per claim form keeps the catalog small and stable.
> - Con: one more E08xx code. Con: a tool that wants the kind must match message text (accepted for E0860).
> - Rejected "do nothing": a user error that prints "This is a compiler bug. Please report it" is a false statement, not a style issue.
>
> ## Cross-language
>
> Rust bindgen emits layout tests (`size_of`, `offset_of` asserts) that fail as ordinary test failures at the struct, a user error, never an ICE; and like this test, they check layout, not field kinds. Zig `@cImport` and Go cgo avoid the question by reading the C type from the header; a hand mirror (Blink's choice) needs this check, and the check must be a first-class diagnostic.

- **DevOps:**

> # [ticket] — devops seat, Phase A
>
> ## What I ran (main, build/blink, probe/devops/)
>
> | Mirror | `blink build` today |
> |---|---|
> | `tv_nsec: I32` on `timespec` | `internal compiler error[GeneratedCDidNotCompile]` ... `field tv_nsec has a different size`, span 1:1, exit 101 |
> | `name: "timespek"` | same code: `names timespek, but time.h declares no complete struct tag and no complete typedef name`, exit 101 |
> | `{ tv_sec: I64, tv_nsec: I64 }` | host x86_64: `built`, exit 0. `--target arm-linux-gnueabihf`: I0017 `field tv_sec has a different size`, exit 101 |
>
> The probe already finds the mirror, the field, the kind and the triple before any unit compiles. Only the label is wrong.
>
> ## Q0: yes, the spec must change
>
> I0017 is the wrong surface for a user error, for four reasons a tool sees:
>
> 1. Exit 101 means "compiler bug" (decided, check-build-promise). CI dashboards, `blink test` triage and bug-report bots key on 101. A typo in `name:` pages the compiler team.
> 2. The text ends "This is a compiler bug. Please report it" and "the cause is a bug of the compiler". Both are false. Users will file false issues; LLM agents will stop and "report the bug" in place of fixing the field.
> 3. `blink explain I0017` says its notes hold the C compiler output. Here there is none.
> 4. Under `blink test`, I0017 is defined as "no span". This report has a real span. Keeping I0017 means the spec contradicts the output.
>
> So "reports the struct and the field" in §9.1.3 is not met by I0017 in the sense that counts: a tool cannot act on it.
>
> ## Proposal A (recommended): one new code, `ForeignStructMismatch` (next free E08xx), a §6.7.3 row, exit 1
>
> Behavior:
> - Found by `blink build` and `blink test`, never `blink check`. Runs after the header test (E0859), in the same per-target probe, before the unit compile. The unit compile does not start.
> - One code for all five kinds: NoName, NoField, Offset, FieldSize, StructSize. The kind is in the message by a fixed prefix (as E0860 does), and in `--json` as a `kind` field: `no_name | no_field | offset | field_size | struct_size`. E0855 is the model: one code covers "misspelled", "not constant", "does not fit".
> - Span: the field line for NoField, Offset, FieldSize; the `@ffi.struct` line for NoName and StructSize. A secondary label points at the `@ffi.struct` line in the field case. The editor jumps to the line the user must edit.
> - Message names the triple, always (host triple from `cc -dumpmachine` for a native build).
> - One report per mirror (the first kind by rank; a wrong field shifts every later offset, so later ones are noise). All mirrors in one run, not one per build.
> - No note about `blink check`, no "compiler bug" note.
> - I0017 stays the backstop: if the probe errors do not all map to check lines, no verdict, and the unit compile's `_Static_assert` gives I0017 with its `@ffi` note.
>
> Examples (each: `blink check` exit 0, no diagnostic):
>
> ```blink
> @ffi.struct(header: "time.h", name: "timespec")
> type Ts { tv_sec: I64, tv_nsec: I64, extra: I64 }
> // build/test: error[ForeignStructMismatch] at `extra` (line 2), exit 1
> //   `@ffi.struct` `Ts` does not match C struct `timespec` on x86_64-linux-gnu:
> //   C struct `timespec` has no field `extra`, or `extra` is a bit-field
> ```
>
> ```blink
> @ffi.struct(header: "time.h", name: "timespec")
> type Ts { tv_sec: I64, tv_nsec: I32 }
> // build/test: error[ForeignStructMismatch] at `tv_nsec`, exit 1
> //   ... on x86_64-linux-gnu: field `tv_nsec` has a different size
> ```
>
> ```blink
> @ffi.struct(header: "time.h", name: "timespek")
> type Ts { tv_sec: I64, tv_nsec: I64 }
> // build/test: error[ForeignStructMismatch] at the @ffi.struct line, exit 1
> //   `Ts` names `timespek`, but `time.h` declares no complete struct tag and no
> //   complete typedef name `timespek` on x86_64-linux-gnu
> //   help: check the spelling of `name:`; a C type with no visible fields is an `@ffi.opaque`
> ```
>
> ```blink
> @ffi.struct(header: "time.h", name: "timespec")
> type Ts { tv_sec: I64, tv_nsec: I64 }
> // build (host x86_64-linux-gnu): ok, exit 0
> // build --target arm-linux-gnueabihf: error[ForeignStructMismatch] at `tv_sec`, exit 1
> //   ... on arm-linux-gnueabihf: field `tv_sec` has a different size
> ```
>
> Under `blink test`: the file is `build_failed` with this one diagnostic, with its span, exit 1.
>
> **Q3 (`--target`).** No answer changes. The check is per target, so the verdict is per target, and the triple in the message says which. A build with several targets reports each failing target once; exit 1 if any fails. A CI matrix sees exit 1 on the arm job only, with the triple in the text. This is the right shape: the promise covers any supported target (Q7), and a mirror that fits only the host is a user claim that is wrong on arm, not a compiler bug on arm.
>
> ## Proposal B (not recommended): split NoName into its own code
>
> NoName is about the `name:` argument, not the layout; its help differs (`@ffi.opaque`). A separate code lets `blink explain` give a tighter page. Against: E0855 already puts "not defined by the headers" under one code with "wrong value", the `kind` field and the fixed prefix already let a script tell them apart, and each code costs a catalog row, an explain page and a test. I vote A unless another seat shows a tool that needs to branch on code alone.
>
> ## Proposal C (rejected): keep I0017, drop only the "compiler bug" note
>
> Fixes the text but not exit 101, not the "notes hold cc output" page, not the no-span rule under `blink test`. A code whose meaning depends on a hidden sub-kind is what `kind` fields exist to avoid.
>
> ## Tradeoffs (tooling)
>
> - **Pro:** exit 1 vs 101 is the one bit CI reads; this fixes it. Span on the field gives problem matchers (VS Code, GitHub annotations) a clickable line. Fits the E0855/E0859/E0861 family: build-only, per-target, at the declaration, exit 1.
> - **Con:** still build-only, so the LSP never shows it while typing. Accept: check reads no header (decided). A later `blink check --probe-c` could add it; not in scope.
> - **Risk:** the probe maps failed lines from cc output (`file:line`). That is reading cc text, which the decision forbids for I0017. E0855 already does the same, and only the line number is read; a compile whose errors do not all map gives no verdict and falls back to I0017. The spec should say that rule plainly so the code never lies.
>
> ## Cross-language
>
> Rust bindgen emits `assert_eq!(size_of::<T>(), N)` layout tests; a mismatch is a test failure at the struct, never an ICE. Zig `@cImport` avoids the issue by translating the struct itself. Go cgo reads the C type directly, so there is no mirror to mismatch. Blink chose hand mirrors, so it owes a user-error code like bindgen's test, not a compiler-bug code.

- **AI/ML:**

> # aiml — [ticket] Phase A
>
> ## Q0: the spec must change
>
> Today's report tells the author three false things: "the cause is a bug of the compiler", "Please report it", and (through `blink explain I0017`) "the notes hold the C compiler output". An AI agent acts on that text. It reads "compiler bug", stops changing its own code, and files an issue or tries a workaround. The fix is one line in the user's code, and the report already names it in the help. The ICE notes then contradict that help. A report that contradicts itself is the worst case for self-correction.
>
> It also breaks a decided rule: exit 101 means a compiler bug (check-build-promise). A mirror that does not match its C struct is a user error, and the compiler knows that for sure: its own probe found it. So "I0017 with a better note" is not enough. The code and the exit are wrong, not only the note.
>
> ## Proposal A (my vote): one new code, `ForeignStructMismatch` (E08xx, next free number)
>
> Q1: a §6.7.3 row. It is the same pattern as E0859, E0861 and E0855: "`blink build` tests an `@ffi` claim against the header; a claim that fails is an E08xx at the `@ffi` line, exit 1, and no unit compiles." An AI learns one rule for the whole family, not four special cases.
>
> - `blink check`: nothing (exit 0). Check reads no header (decided).
> - `blink build` and `blink test`: E08xx, exit 1, after the header test, before any unit compile.
> - Primary span: the `@ffi.struct` line. Secondary label: the Blink field line, when the kind names a field.
> - I0017 keeps only a mismatch that the layout test does not find, the same split as E0861.
> - No ICE notes. `blink explain` gives the fix steps below.
>
> Q2: one code for all five kinds. The message names the kind, the field and the triple; the JSON form has `"kind"`, `"field"`, `"target"` so a tool can branch without a second code. Reasons: E0855 already uses one code for "misspelled name", "not constant" and "does not fit"; fewer codes means fewer facts to learn; the fix is always "make the mirror match the header". A field the mirror lacks is not its own kind. The compiler cannot tell "missing field" from "wrong type"; it shows as an offset or struct-size difference at the first field that moves. One report per mirror, at its first failing check (name, then fields in order, then struct size), because later offsets cascade from the first error.
>
> Q3: no change to the answers. The check runs per target, and the message names the triple. A mirror can pass a host build and fail under `--target`. The triple in the text is what tells an agent that the cause is target-specific.
>
> ### Examples
>
> ```blink
> @ffi.struct(header: "time.h", name: "timespec")
> type Ts { tv_sec: I64, tv_nsec: I64, extra: I64 }
> ```
> check: exit 0. build/test: `error[ForeignStructMismatch]`, exit 1, at 1:1, label on `extra`: "C struct `timespec` has no field `extra`, or `extra` is a bit-field, on x86_64-linux-gnu".
>
> ```blink
> @ffi.struct(header: "time.h", name: "timespec")
> type Ts { tv_sec: I64, tv_nsec: I32 }
> ```
> check: exit 0. build/test: E08xx, exit 1, at 1:1, label on `tv_nsec`: "field `tv_nsec` has a different size". (Probed today: I0017 at 1:1, exit 101.)
>
> ```blink
> @ffi.struct(header: "time.h", name: "timespek")
> type Tk { a: I64 }
> ```
> check: exit 0. build/test: E08xx, exit 1, at 1:1, no field label: "`time.h` declares no complete struct tag and no complete typedef `timespek` on x86_64-linux-gnu". Help: check `name:`; a C type with no visible fields is an `@ffi.opaque`. (Probed today: I0017, exit 101.)
>
> ```blink
> // The x86_64 glibc layout: st_nlink is 8 bytes, after st_ino.
> @ffi.struct(header: "sys/stat.h", name: "stat")
> type Stat { st_dev: U64, st_ino: U64, st_nlink: U64, st_mode: U32, /* ...rest of the x86_64 fields */ }
> ```
> `blink build`: exit 0. `blink build --target linux-arm64`: E08xx, exit 1, label on `st_nlink`: "field `st_nlink` is at a different offset on aarch64-linux-gnu" (aarch64 puts `st_mode` first, and `st_nlink` is 4 bytes there). check: exit 0 for both.
>
> ## Proposal B (fallback): two codes
>
> `ForeignStructNotFound` for NoName, `ForeignStructMismatch` for the four layout kinds. The case for B: the fix differs (change `name:` or use `@ffi.opaque`, not the fields), and it mirrors E0859 ("not there") versus E0861 ("there, but wrong"). I rank B below A: the `kind` field and the help already split the fix, and E0855 sets the precedent of one code per declaration form. I would not oppose B.
>
> ## Rejected: do nothing
>
> "I0017 with a note naming the struct and field" meets the letter of §9.1.3, but the code tells the reader the opposite of the truth. An LLM trusts the code and the "report it" line more than a help line that comes before them.
>
> ## Tradeoffs (AI/ML)
>
> - Learnability: A adds one code that fits a pattern the agent already knows (E0855/E0859/E0861). Cost: one more row in §6.7.3.
> - Self-correction: exit 1 + a field span + the triple gives a one-step fix. Today's text leads the agent away from the fix.
> - Debuggability: one report per mirror, not a cascade of offsets, so the agent fixes the real field first.
> - Limit: check stays blind. An agent that gates on `blink check` alone still finds the error late. That is decided, and `blink test` catches it.
>
> ## Cross-language
>
> Rust bindgen emits layout tests as `const` asserts; a mismatch is a raw "attempt to compute ... overflow" or assert text at the generated line, not at the user's type. That is the I0017 shape. Zig `@cImport` and Go cgo read the struct from the header, so there is no mirror to get wrong. Blink chose hand-written mirrors, so it owes the user a precise error at the mirror.

- **Minimalism:**

> # min (Minimalism), Phase A, [ticket]
>
> ## Where we stand
>
> The work is done. Main already runs the layout probe before any unit compile, and finds the mirror, the field and the kind (`src/ffi_layout_probe.bl`, `report_ffi_struct_mismatches` in `src/cli.bl`). The only thing wrong is the label: it calls `diag_ice_at(... GENERATED_C_DID_NOT_COMPILE ...)` and returns 101. My own re-runs on main (x86_64-linux-gnu):
>
> - `tv_nsec: I32` -> `internal compiler error[GeneratedCDidNotCompile] ... field tv_nsec has a different size`, exit 101
> - `name: "timespek"` -> `internal compiler error[GeneratedCDidNotCompile] ... declares no complete struct tag and no complete typedef name`, exit 101
>
> So this ticket adds no check and no pass. It only picks the code. That is the smallest kind of spec change, and I support it.
>
> ## Q0: yes, the spec must change
>
> "Do nothing" fails a decided rule: exit 101 means a compiler bug (check-build-promise). A mirror that differs from its header is the user's error. I0017 here prints "This is a compiler bug. Please report it" and points users at the issue tracker for their own typo. `blink explain I0017` also says its notes hold cc output, and this report has none. A chore that only drops the ICE note still leaves exit 101, so it does not fix the lie.
>
> ## Proposal M1 (recommended): one code, `ForeignStructMismatch` (E08xx), the third build test
>
> Behavior:
> - `blink check`: no report, exit 0 (check reads no header; decided).
> - `blink build`, `blink test`: `error[ForeignStructMismatch]` at the `@ffi.struct` line, exit 1. The unit compile does not start. It is a row of the closed §6.7.3 list, next to E0855, E0859 and E0861.
> - Order: after the header test (E0859). A missing header is E0859, never this.
> - One diagnostic for each mirror that differs, so one build shows all of them. Each names the mirror, the C name, the target triple, and the first difference.
> - I0017 keeps only a layout fault the test does not find, as E0861 does for prototypes.
>
> **Q2: one code for all five kinds.** NoName, NoField, Offset, FieldSize and StructSize share one claim ("this type has the layout of that C struct") and one fix ("make the mirror match the header"). The kind goes in the message and the help, not in the code. Five codes would give five `blink explain` pages with the same advice. Splitting NoName out (like E0855 for a bad const name) buys nothing: no fix differs.
>
> **Q3: --target changes no answer, only the verdict.** The test runs per target, like E0855 and E0861. Same code, same exit; the message names the triple. With two `--target`s, each failing target gives its own diagnostic.
>
> ### Examples
>
> ```blink
> // 1. A field C lacks
> @ffi.struct(header: "time.h", name: "timespec")
> type Ts { tv_sec: I64, tv_nsec: I64, extra: I64 }
> // check: ok, exit 0
> // build/test: error[ForeignStructMismatch] at line 1, exit 1:
> //   `Ts` does not match C struct `timespec` on x86_64-linux-gnu: C struct `timespec` has no field `extra`
> ```
>
> ```blink
> // 2. A field of the wrong size
> @ffi.struct(header: "time.h", name: "timespec")
> type Ts { tv_sec: I64, tv_nsec: I32 }
> // check: ok, exit 0
> // build/test: error[ForeignStructMismatch] at line 1, exit 1: field `tv_nsec` has a different size
> ```
>
> ```blink
> // 3. A name that is no tag or typedef
> @ffi.struct(header: "time.h", name: "timespek")
> type Ts { tv_sec: I64, tv_nsec: I64 }
> // check: ok, exit 0
> // build/test: error[ForeignStructMismatch] at line 1, exit 1:
> //   `time.h` declares no struct tag and no typedef name `timespek` on x86_64-linux-gnu
> ```
>
> ```blink
> // 4. Matches on one target, differs on another.
> // glibc packs struct epoll_event on x86_64 (size 12, data at 4), not on aarch64 (size 16, data at 8).
> @ffi.struct(header: "sys/epoll.h", name: "epoll_event")
> type EpollEvent { events: U32, data: U64 }
> // check: ok, exit 0, with any --target
> // build --target aarch64-linux-gnu: builds
> // build --target x86_64-linux-gnu: error[ForeignStructMismatch] at line 3, exit 1:
> //   field `data` has a different offset (on x86_64-linux-gnu)
> // build with both targets: one diagnostic, for x86_64-linux-gnu; exit 1
> ```
>
> Example 4 is the honest limit: no Blink spelling matches both layouts, so the user needs one mirror per target. That is a fact of C, not a defect of this rule. Check stays clean, as the promise says for any header fact.
>
> ## One point the panel must not miss: the report reads cc text
>
> `layout_mismatches(layout, sp, run.err_out, ...)` maps the failed `_Static_assert` lines from the cc error output back to a mirror and field. The decided rule (check-build-promise Q3) and both siblings (E0859, E0861) read only pass or fail. If the new code is a user error at exit 1, its verdict must be the same under gcc, clang and zig cc, so it must not hang on how each one prints errors. Behavior I ask for: the same mirror gives the same report (kind and field) under every supported cc. How (one compile per check on a fail, or bisection) is an implementation chore, not spec. I flag it because a new spec row would bless today's mechanism by accident.
>
> ## Rejected options
>
> - **M0, do nothing / chore only:** fails the 101 rule (see Q0).
> - **M2, widen E0861 to "any `@ffi` claim the build test refutes":** one fewer code, but E0861 was named and decided today, its help (`Ptr[Void]`) fits no layout fault, and a code whose fix depends on a sub-kind is two codes in one. Second choice only.
>
> ## Tradeoffs
>
> - Cost: one code, one §6.7.3 row, one sentence in §9.1.3 that names it. The check exists already; this is a relabel plus the pass/fail fix above.
> - Gain: exit 101 means compiler bug again for every mirror fault the test finds. Three build tests (header, prototype, layout) now share one shape. A model learns one pattern, not three.
>
> ## Cross-language
>
> Rust bindgen emits layout tests as `#[test]` asserts: you learn at `cargo test`, as a test failure, never as a compiler bug. Zig `@cImport` has no mirrors to check: it imports the C layout, which is the "do nothing because nothing can differ" end. Go cgo has the same: `C.struct_x` is read from the header. Blink chose hand-written mirrors, so it owes the user a named error, and bindgen shows the error belongs to the user, not to the tool.

### Phase B — Debate (round 1)

- **Systems:**

> # [ticket] B1: sys
>
> **V1 (span): the `@ffi.struct` line is the primary span. I accept aiml's secondary label on the field.** I do not support devops's version.
> An Offset fail on field k usually has its cause before k. Either field k-1 has the wrong size, or a C field that the mirror lacks sits before k (the sockaddr_in probe on macOS: the mirror has no `sin_len`, so `sin_family` gets the blame). A primary span on field k sends the user to a line that is correct. The claim the build tests is the annotation, and E0855 and E0861 also point at the claim. The secondary label gives the editor a click target and does not claim to be the cause. For FieldSize the field line is the cause, and the label shows it there.
>
> **V2 (order): header test, then layout test, then prototype test.** plt gives the reason. A `Ptr[Ts]` param where `Ts` names no C type fails the prototype probe as well, and that error blames the `@ffi fn`. Test the type before the functions that use it.
>
> **V3 (no verdict): I change my Phase A position and side with min.** Fact 2 is correct. Today's mapping reads `file:line` from the cc output. A spec row that blesses that breaks the decided "pass or fail only" rule. It also gives different results under different C compilers. The cost of reading pass/fail only is small:
> - Success path (the usual case): one compile, the same as today.
> - Fail path: first compile the probe without the check lines. If that fails, there is no verdict and the build falls back to I0017. If it passes, bisect over the checks, by mirror and then by check, in rank and field order. That is about log2(checks) more compiles, each tens of ms, and only on a build that already failed.
> - Then any cc that has `_Static_assert` gives the same kind and field. That includes tcc 0.9.27+.
>
> Behavior to vote on: the same mirror gives the same E0862 report under every supported cc. The probe reads only pass or fail. I0017 stays only for a probe base that does not compile. The mechanism is a chore. I agree with min that the spec must not bless line mapping. E0855 has the same flaw, and that needs its own ticket, not this one.
>
> **Fact 3:** `tv_nsec: Float` passes. That supports the writer note: the test proves size and offset, not sign, float or int, or pointee.
>
> STABLE

- **Web/Scripting:**

> # web, [ticket] Phase B round 1
>
> **V1 (span): aiml's form.** Primary span on the `@ffi.struct` line, with a secondary label on the field when the kind names a field. I move from "the `@ffi.struct` line only" to this. devops is right that users want to be shown the field. But a field-line primary misleads for Offset: when the mirror lacks a C field, the line to fix is *before* the flagged field (sys's point). A field label on the annotation primary is true in every case and still shows the field. It also keeps the shape of E0855 and E0861 (span on the `@ffi` line), so users learn one rule for all four. GitHub annotations show only the primary span, which is the line that holds the claim. That is fine.
>
> **V2 (order): header, then layout, then prototype.** I agree with plt. A `Ptr[Ts]` where `Ts` names no C type must not show up as E0861 on an `@ffi fn` line far from the real mistake. Report the root cause once, first. The spec should state the order, because users see which error comes first.
>
> **V3 (no verdict): both, scoped.** Falling back to I0017 when the probe cannot map its own lines is fine as a backstop. But I back min's rule for the supported C compilers (gcc 13+, clang, zig cc): the same mirror gives the same E0862 kind and field under each one. If gcc says "user error, line 2" and clang says "compiler bug, please report it" for the same file, that is a Stack Overflow question every week. Name tcc as the known exception, the same way §9.1 already does for E0861. How the build reaches the same verdict is a chore.
>
> **Fact 2 (reading cc text):** I accept it with E0855 as precedent. The probe reads which line of *its own file* failed, not the message. The spec should say exactly that, so the "reads only pass or fail" sentence of the siblings and this one do not contradict each other.
>
> **Fact 3 (`tv_nsec: Float` builds):** I agree with the writer note. The docs must say "layout matches", not "types match". A JS/Python dev will read "ForeignStructMismatch passed" as "my struct is right". One sentence in the explain page stops that.
>
> **My earlier ask** (size messages name the Blink size, "`I32` is 4 bytes") stays a writer note, not a vote.
>
> STABLE

- **PLT:**

> # [ticket] Phase B round 1: plt
>
> ## V1: span. I back aiml: primary on the `@ffi.struct` line, secondary label on the field
>
> One code should have one anchor. The claim that fails is the relation between `name:` (with its header) and the field list, and the annotation is where that claim sits. A field-kind report does not prove the field is the wrong part. In `type Ts { tv_sec: I32, tv_nsec: I64 }` against `timespec`, the user may have named the wrong C struct, and then the edit goes on line 1. StructSize and NoName have no field at all, so devops's rule gives one code two kinds of primary span, picked by kind. A secondary label on the field still gives the editor and problem matchers a line they can click (devops's goal), and it does not fix the anchor to one guess about the cause.
>
> ## V2: order. I keep header, then layout, then prototype
>
> This is a dependency, not a preference. The prototype test compiles `struct timespec *` for a `Ptr[Ts]`. If `Ts` names no C type, that probe fails too, and E0861 blames an `@ffi fn` line for a fault on the `@ffi.struct` line. Each test should run only once its inputs pass, so a program shows the root cause once. The spec should state the order, as it already does for E0859 before E0855.
>
> ## V3: I side with min. The verdict must not depend on how a cc prints errors
>
> This is the soundness point of the ticket. With line mapping (fact 1), the same program and target give E0862, exit 1, under a cc whose error lines the probe can map, and I0017, exit 101 ("compiler bug"), under one it cannot. Then the code depends on the cc's error format, not on (source, target), and exit 101 keeps the double meaning this ticket exists to remove. The behavior I ask for:
> - Every supported C compiler (gcc 13+, clang, zig cc, the E0861 set) gives the same E0862 report: same mirror, kind and field.
> - The test reads only pass or fail, as E0859 and E0861 do. One way to do that: on a failed combined probe, run one probe per check. That costs extra cc runs only when a build already fails, which is cheap. The mechanism is a chore.
> - I0017 stays only for the case where the combined probe fails and no single check fails, which is a true "no test explains it".
>
> Fact 1 also shows that E0855 maps lines today. Under the same rule that is a latent fault. It needs a separate chore, not a reopened decision.
>
> On fact 3 and the writer notes: agreed. The spec must say the test proves size and offset only.
>
> STABLE

- **DevOps:**

> # [ticket] — devops, Phase B round 1
>
> ## V1: the span. I move to aiml's form.
>
> Primary span: the `@ffi.struct` line. Secondary label: the Blink field line, when the kind names a field (NoField, Offset, FieldSize). In `--json` the field span goes in a related location (LSP `relatedInformation`, a second GitHub annotation).
>
> Why I give up the field as the primary span: E0855, E0859 and E0861 all put the primary span on the `@ffi` line. One anchor for the whole family means one problem matcher rule and one pattern for a model to learn. The secondary label still puts the line the user must edit on screen, so the main tooling gain stays. NoName and StructSize have no field label.
>
> ## V2: the order. I agree with plt and sys.
>
> Header test (E0859), then the layout test (E0862), then the prototype test (E0861), then the unit compile. A `Ptr[Ts]` whose `Ts` names no C type fails both probes. The user must get one report, at the root cause. Two reports for one fault make a CI log harder to read and make an agent fix the wrong line.
>
> ## V3: no verdict. I side with min, and keep the fallback only for what is outside the supported set.
>
> Facts 1 and 2 are the real issue. Today the report reads `file:line` out of cc stderr. That breaks the decided rule ("reads only pass or fail"), and it ties the exit code to how each cc prints errors and to its error limit. A user error that gives exit 1 under gcc and 101 under clang is the worst result for CI: the same commit is a "user bug" on one runner and a "compiler bug" on another.
>
> Behavior I ask for:
> - For one source on one target, the layout test gives the same verdict (code, mirror, kind, field) under every supported C compiler (gcc 13+, clang, `zig cc`).
> - The test reads only pass or fail, like its siblings. The mechanism (a second compile per mirror or per check after a fail) is a chore, not spec.
> - `tcc` is outside the promise, as for E0861. Under it, a mirror fault can fall through to I0017 with its `@ffi` note.
>
> This also means E0855's line mapping (fact 1) is the same debt. That is a chore ticket, not this ballot.
>
> ## Other points
>
> - Writer notes: I support all three. The help sentence "a missing C field shows as Offset or StructSize" matters most, because the user will look for a "missing field" kind and not find one.
> - Fact 3 (`tv_nsec: Float` builds): the spec should say the test proves size and offset only. It is not a reason to change the code.
>
> STABLE

- **AI/ML:**

> # aiml — [ticket] Phase B round 1
>
> **V1 (span): I switch to devops.** Primary span on the field line for NoField, Offset and FieldSize, with a secondary label on the `@ffi.struct` line. Primary on the `@ffi.struct` line for NoName and StructSize. Reason: an agent edits where the primary span points. The JSON `span` is the one location most tools and agents read; secondary labels often get dropped. If the primary span is line 1, the agent must parse the field name out of the message text to find the line to change. If it is the field line, the fix is one step. This does not break the E0855/E0861 pattern: the field is part of the declaration, and the primary span still points at the line to edit. My A version (struct line primary, field secondary) is my second choice. Both beat line 1 alone.
>
> **V2 (order): agree with sys and plt.** Header test, then the layout test, then the prototype test. If the layout test fails, the prototype test does not run. plt gave the reason: a bad mirror would also fail the prototype probe and blame an `@ffi fn` line. Two reports for one cause, one of them at the wrong line, is the self-correction trap we are removing.
>
> **V3 (no verdict): both, and they agree.** min's rule is the behavior: one mirror gives the same code, kind and field under gcc 13+, clang and zig cc. An agent that retries on another host or in CI must see the same error, or it chases noise. sys's fallback covers the rest: a cc that is not supported (tcc), or a probe with no verdict that maps to a mirror, falls back to I0017 as today. That is the same split §9.1 already makes for E0861 under tcc.
>
> **Fact 2.** Mapping errors by reading `file:line` out of cc text conflicts with check-build-promise Q3 and with the "reads only pass or fail" text of both sibling tests. min's same-under-every-cc rule makes that a mechanism chore (one pass/fail compile per check on a fail, say) and does not reopen Q3. The spec should not describe today's text mapping.
>
> **Fact 3.** `tv_nsec: Float` passes. That is fine for this ticket: the spec should say the test checks size and offset only (writer note from sys and plt). Per-target mirrors are a separate ticket.
>
> **web note.** Yes: give the Blink-side size ("`I32` is 4 bytes; C `long` is 8 on x86_64-linux-gnu"). With both numbers in the message, the agent can pick the right type without reading the header.
>
> STABLE

- **Minimalism:**

> # min, Phase B round 1, [ticket]
>
> The common ground is my M1, so I take it as written: E0862 `ForeignStructMismatch`, one code, exit 1, build/test only.
>
> ## V1: span. I pick aiml's form
>
> The primary span goes on the `@ffi.struct` line, with a secondary label on the Blink field when the kind names one. Why:
> - One rule for every kind and for all its siblings. E0855, E0859 and E0861 all point at the declaration line. Under devops's form the primary span moves with the kind (field line for three kinds, decl line for two). That is one more rule to learn for no new fact.
> - The secondary label still takes the user to the line they edit, so devops's goal is met.
> - Weak point in devops's form: for NoField the field is in the Blink type but missing in C, so "the line to edit" may be a field that must go away, or one that a missing C field pushed out of place (sys's help note: a missing C field shows as Offset or StructSize). The field the probe names is a clue, not always the cause. A secondary label says this better than a primary span does.
>
> ## V2: order. Agree with sys and plt
>
> Header, then layout, then prototype. plt's reason is right: a `Ptr[Ts]` whose `Ts` names no C type would fail the prototype test and blame the wrong `@ffi fn` line. Order costs nothing and stops a false E0861.
>
> ## V3: fallback. I withdraw my objection
>
> Moderator fact 1 changes my view. The E0855 probe already maps failed lines from the cc output (`probe_verdicts`, src/cli.bl:2196), and the panel accepted that. Asking E0862 for a stricter rule than E0855 would add a second mechanism for no gain. That is not minimal.
>
> So I accept sys's fallback: no mapped verdict means the build goes on, and the unit's own asserts stop it as I0017. This matches the decided rule that I0017 keeps the faults the test misses, as with E0861 under tcc.
>
> One limit I ask the writer to keep: the mapping reads only which probe lines failed (file and line), never the wording of a message. That is the E0855 shape. No row of the error text may decide the kind or the field. The probe's own line layout decides them.
>
> ## Others
>
> - Fact 3 (`tv_nsec: Float` builds): agree with sys and plt that the spec says the test proves size and offset only. Sign, float vs int and pointee stay the `@ffi` author's claim. No new check. YAGNI.
> - web's "`I32` is 4 bytes" in the message: fine, it is wording.
> - Per-target mirrors are out of scope. Keep them out.
>
> STABLE

### Phase C — Vote

# [ticket] — Phase C ballot (silent vote)

Round 1 replies: b9/[ticket]/<seat>-B1.md. All six seats wrote STABLE.

## Decided (every seat agrees in Phase A and round 1; not on the ballot)
- Q0 yes. Q1: `ForeignStructMismatch` (E0862), a row of the closed §6.7.3 list, exit 1, from
  `blink build` and `blink test` only; `blink check` reports nothing; no unit compiles.
- Q2: one code for all five kinds (NoName, NoField, Offset, FieldSize, StructSize); the message and
  JSON name the kind. One report per mirror (the first failing check in rank and field order); every bad
  mirror in one run.
- Q3: the verdict is per target; the message names the triple.
- Test order (V2, 6-0 in round 1): header test (E0859), then the layout test (E0862), then the
  prototype test (E0861).

## Q-V1 — where the primary span points for NoField, Offset, FieldSize

**V1-D (decl line, field label)** — round 1: sys, web, plt, devops, min.
(aiml, Phase A:)
```blink
@ffi.struct(header: "time.h", name: "timespec")
type Ts { tv_sec: I64, tv_nsec: I32 }
```
"build/test: E08xx, exit 1, at 1:1, label on `tv_nsec`: "field `tv_nsec` has a different size"."

**V1-F (field line, decl label)** — round 1: aiml.
(devops, Phase A:)
```blink
@ffi.struct(header: "time.h", name: "timespec")
type Ts { tv_sec: I64, tv_nsec: I32 }
// build/test: error[ForeignStructMismatch] at `tv_nsec`, exit 1
//   ... on x86_64-linux-gnu: field `tv_nsec` has a different size
```
"A secondary label points at the `@ffi.struct` line in the field case." NoName and StructSize sit at the
`@ffi.struct` line under both options.

## Q-V3 — how the test reaches its verdict, and what the user sees under different C compilers

**V3-P (pass or fail only)** — round 1: sys, plt, devops, aiml.
(sys:) "Behavior to vote on: the same mirror gives the same E0862 report under every supported cc. The
probe reads only pass or fail. I0017 stays only for a probe base that does not compile. The mechanism is
a chore." (devops:) "`tcc` is outside the promise, as for E0861. Under it, a mirror fault can fall
through to I0017 with its `@ffi` note."
Result: the same mirror gives `error[ForeignStructMismatch]`, the same kind and field, exit 1, under
gcc 13+, clang and zig cc.

**V3-L (own-line mapping, I0017 fallback)** — round 1: min; web (with the same-cc rule, see below).
(min:) "no mapped verdict means the build goes on, and the unit's own asserts stop it as I0017 ...
the mapping reads only which probe lines failed (file and line), never the wording of a message."
(web:) "The probe reads which line of *its own file* failed, not the message. ... I back min's rule for
the supported C compilers (gcc 13+, clang, zig cc): the same mirror gives the same E0862 kind and field
under each one."
Result: E0862 when the failed lines of the probe file map to a check; I0017, exit 101, when they do not.

Facts (repeated): decisions/check-build-promise.md Q3: one I0017 for a C compiler failure, no parsing of
cc text. §9.1 header and prototype tests: "reads only pass or fail". The E0855 probe maps failed lines
today (src/cli.bl:2196).

## Your vote
Write [scratch path] with, for each of Q-V1 and Q-V3:
1. Vote (the option label).
2. Reasoning (2–4 sentences, your domain).
3. Concern (one sentence: what could go wrong with the option that wins).
Then reply to team-lead with "voted" and your two labels. Do not message other seats.

- **Systems:**

> # [ticket] Phase C: sys
>
> ## Q-V1
> 1. Vote: V1-D
> 2. Reasoning: The test checks the claim the annotation makes. When an offset is wrong, the cause is often a field before the one that fails. It is either a short field k-1 or a C field the mirror lacks: on macOS the mirror lacks `sin_len`, so the probe blames `sin_family`. A primary span on the field would send the user to a line that is correct. The field label still gives editors a line to click.
> 3. Concern: Problem matchers that read only the primary span will jump to the decl line, not the field, so the label text must name the field too.
>
> ## Q-V3
> 1. Vote: V3-P
> 2. Reasoning: On success the build runs one compile, as now. On failure it runs about log2(checks) more compiles, each tens of ms, so pass or fail only costs almost nothing. It also matches the decided rule and the E0859 and E0861 tests. It gives the same kind and field under gcc, clang and zig cc, because it does not depend on how each one formats errors. V3-L ties a user-facing verdict to the error format of each cc. When that format changes, the report silently turns into I0017 exit 101, which is the false "compiler bug" this ticket exists to remove.
> 3. Concern: The bisection must rebuild the probe base for each step with the same flags and include paths as the unit compile, or a probe can pass where the units fail. The E0855 line mapping then stays inconsistent until it gets its own ticket.

- **Web/Scripting:**

> # web, [ticket] Phase C vote
>
> ## Q-V1
> 1. Vote: **V1-D**
> 2. Reasoning: The span sits on the `@ffi` line, the same place as E0855, E0859 and E0861, so users learn one rule for every `@ffi` check. The field label still shows the user which field the report names. A field-line primary misleads for Offset when the real fault is a missing field earlier in the mirror. A span on the declaration is never wrong.
> 3. Concern: An editor or GitHub annotation that shows only the primary span puts the mark on the annotation, not the field, so the message text must always name the field.
>
> ## Q-V3
> 1. Vote: **V3-P**
> 2. Reasoning: What I asked for in round 1 was the user-facing result: the same mirror gives the same E0862 kind and field under gcc, clang and zig cc. V3-P promises that outright. V3-L allows I0017 with "please report it" on a supported compiler whenever line mapping fails, and that is the false bug report this ticket exists to stop. V3-P also keeps the "reads only pass or fail" wording of the sibling tests, so the spec tells one story.
> 3. Concern: A pass/fail-only mechanism may cost more C compiler runs on a failing build (one per check, or a bisection), which is slow on a project with many mirrors. That stays a chore, but someone must measure it.

- **PLT:**

> # [ticket] Phase C: plt
>
> ## Q-V1
> 1. Vote: **V1-D**
> 2. Reasoning: One code should have one anchor. The claim that fails is the relation between `name:` (with its header) and the field list, and that claim sits on the `@ffi.struct` line. A field kind does not prove that the field is the part to change: the user may have named the wrong C struct. Under V1-F, the anchor of one code moves with the kind, and the field label already gives a line to click.
> 3. Concern: Some editors and problem matchers show only the primary span, so the user must read the field label to find the line to edit.
>
> ## Q-V3
> 1. Vote: **V3-P**
> 2. Reasoning: A user-error code must be a function of (source, target) only. Under V3-L, a cc whose failed lines the probe cannot map turns the same program into I0017 with exit 101, so "compiler bug" keeps its double meaning. V3-P also fits the decided rule (no parsing of cc text) and its siblings E0859 and E0861 (pass or fail only). Mapping "only the line" is still reading the cc's output format: that format differs by cc and by version, and an error limit can cut it.
> 3. Concern: Per-check probes on the failure path cost extra cc runs on a program with many mirrors, and the chore must keep that cost bounded (for example, split per mirror first, then per check). E0855's line mapping (src/cli.bl:2196) breaks the same rule and needs its own chore.

- **DevOps:**

> # [ticket] — devops, Phase C vote
>
> ## Q-V1
>
> 1. Vote: V1-D
> 2. Reasoning: E0855, E0859 and E0861 put the primary span on the `@ffi` line, so one problem-matcher rule and one pattern for an agent covers all four `@ffi` build tests. The field label still shows the line to edit, and the JSON related location lets an editor or a GitHub annotation jump to it. The primary span is the stable anchor a tool keys on, and the declaration line does not move when the user adds or reorders fields.
> 3. Concern: a tool that shows only the primary span (some CI annotators drop related locations) hides the field. The message must name the field in its text as well as in the label.
>
> ## Q-V3
>
> 1. Vote: V3-P
> 2. Reasoning: CI reads the exit code. If the verdict depends on how each C compiler prints errors, or on its error limit, the same commit can exit 1 on a gcc runner and 101 on a clang runner, which sends a user error to compiler triage. Pass or fail only is the decided rule for the sibling tests (and check-build-promise Q3), so E0862 should follow it, not be a new exception. V3-L with web's same-cc rule makes the same promise, but it rests on a mechanism that cannot keep it when stderr changes.
> 3. Concern: a pass-or-fail mechanism costs one extra compile per mirror (or per check) after a fail. The chore must keep that cost to builds that fail, and E0855's line mapping needs a matching chore so the two probes do not drift.

- **AI/ML:**

> # aiml — [ticket] Phase C vote
>
> ## Q-V1: V1-F
>
> Reasoning: An agent edits the line that the primary span names. Many tools and agent loops read only the JSON `span` and drop secondary labels. If the field is the primary span, the fix is one step. If the declaration line is the primary span, the agent must find the field name in the message text and then search for its line, and that is where wrong edits come from. NoName and StructSize stay at the declaration line under both options, so V1-F adds no new rule to learn: the span is the line to edit.
>
> Concern: If V1-D wins, the field label must be in the JSON (in a field that tools read, not only in the human text). If it is not, agents lose the field location.
>
> ## Q-V3: V3-P
>
> Reasoning: V3-P gives one input one error on every supported C compiler. An agent that retries on another host or in CI then sees the same code, kind and field, and does not chase noise. It also matches the decided rule (no parsing of cc text) and the two sibling tests, so the family has one rule: "reads pass or fail". V3-L can turn a user error back into I0017, "compiler bug, report it", which is the false signal this ticket exists to remove.
>
> Concern: one pass/fail compile per check can make a build with many mirrors slow. The chore must keep the fast path (one probe compile when all mirrors match) so that no one is tempted to go back to mapping lines from cc text.

- **Minimalism:**

> # min, Phase C vote, [ticket]
>
> ## Q-V1
> 1. Vote: **V1-D**
> 2. Reasoning: There is one span rule for every kind of E0862 and for its siblings E0855, E0859 and E0861: the declaration line. The field label still takes the user to the field. The field the probe names is often a symptom (a C field that the mirror lacks shows as a later Offset or StructSize), so a label fits it better than a primary span.
> 3. Concern: An editor that jumps only to the primary span lands one line above the field to edit.
>
> ## Q-V3
> 1. Vote: **V3-P**
> 2. Reasoning: In round 1 I accepted line mapping only because E0855 does it. But V3-P is what I asked for in Phase A: the same report under every supported cc. It also keeps one rule for the build tests ("reads only pass or fail"), which the promise decision and the header and prototype tests already state. V3-L would put a second rule in the spec and keep a path where a user error under a supported cc still exits 101. One rule beats two, and the extra compiles run only after a failure.
> 3. Concern: The E0855 probe still maps lines, so the spec and that code now differ. It needs a chore to bring E0855 under the same pass-or-fail rule, or the mismatch stays.


### Final Spec

```blink
@ffi.struct(header: "time.h", name: "timespec")
type Ts { tv_sec: I64, tv_nsec: I64 }       // passes on x86_64-linux-gnu

@ffi.struct(header: "time.h", name: "timespec")
type TsSmall { tv_sec: I64, tv_nsec: I32 }
// error[ForeignStructMismatch] (E0862) at the @ffi.struct line, exit 1
//   `@ffi.struct` `TsSmall` does not match C struct `timespec` on x86_64-linux-gnu:
//   FieldSize: field `tv_nsec` has another size in C (`I32` is 4 bytes)

@ffi.struct(header: "time.h", name: "timespek")
type TsTypo { tv_sec: I64, tv_nsec: I64 }
// error[ForeignStructMismatch] (E0862) at the @ffi.struct line, exit 1
//   help: check the spelling of `name:`; a C type with no visible fields is an `@ffi.opaque`
```
