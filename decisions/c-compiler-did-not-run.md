[< All Decisions](../DECISIONS.md)

# A C Compiler That Did Not Run — Design Rationale

**Gap:** §6.7.3 lists the causes outside the Blink source, and the list is closed. It had no row for a host that has no C compiler (`cc`, or `zig` for `--target`), or for a C compiler that a signal ends (for example the out-of-memory killer). By §6.7.1 any stop outside the list is a compiler bug, so such a stop reached `GeneratedCDidNotCompile` (I0017) with the note "the cause is a bug of the compiler", exit `101`. The cause is the host. The panel had to say which code these stops get, what a signal to the build means, and whether `blink check` changes.

**Result:** Q1 5-1 in Phase D after 4-2 in Phase C (AI/ML dissented): one new code, E0860 `CCompilerDidNotRun`, for a C compiler that gave no verdict. Q2 6-0 in Phase D after 4-2 in Phase C: the interrupt test is whether the compiler itself received the signal.

| Q | Question | Result | Tally |
|---|---|---|---|
| Q1 | How many codes for a C compiler that did not run | One code, E0860 `CCompilerDidNotRun`, exit `1`. It covers "could not start" (not found, not executable) and "a signal ended it". The message names the tool as it ran, and the reason or the signal | 5-1 in Phase D (4-2 in Phase C) |
| Q2 | The test for an interrupt | If the compiler itself gets SIGINT or SIGTERM, it stops, prints no diagnostic and exits `1`. If a signal ends only the C compiler, whatever the signal (SIGINT included), the result is E0860 and the message names the signal | 6-0 in Phase D (4-2 in Phase C) |

Agreed by all six seats, with no separate ballot:

- A host build with no `cc`, and a `--target` build with no `zig`, are §6.7.3 causes with exit `1`. A `cc` that starts and is then ended by a signal is E0860, and the message names the signal by number and name.
- A C compiler that runs and exits with a non-zero status, any value, stays `GeneratedCDidNotCompile` (I0017), exit `101`. The compiler decides from "the tool could not start" or "a signal ended it". It never decides from the number of an exit status.
- A missing tool is reported once, at the probe of the C compiler that runs before any unit compiles. A probe that fails in any way is E0860.
- `blink check` does not change: it runs no C compiler.
- `blink test` marks the file `build_failed` with one E0860 diagnostic, `severity: "error"`, no span. It does not use E0856 and it does not use `aborted`.
- E0860 never carries the I0017 note that the cause is a bug of the compiler.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote → focused-round steps. The excerpts below are verbatim. Each cut is marked `…`. Scratch paths and ticket numbers are cut.

#### Phase A — Independent proposals

The seats split on Q1. Systems, PLT and Minimalism proposed one code. Web, AI/ML and DevOps proposed two codes: one for a missing tool, one for a tool that a signal ended.

- **Systems:**
  > Position: a missing or killed C compiler is a host cause. Add it to the §6.7.3 table. Never emit I0017 for it.
  > …
  > A signal that stops cc is also a host cause, under the same E0860 (message differs: "stopped by signal 9"). Reason: the OOM kill does not depend on the source.
  > …
  > Split on this: exited normally non-zero is I0017. Started but never started or finished is E0860. This mirrors E0856 for the test runner (host state, not source). One code, two cause texts, avoids code sprawl.
  > …
  > The cache key probes (`cc --version`, `cc -dumpmachine`) run first, so a missing cc is detected there. Report E0860 once, before any unit compile. Do not run N unit compiles that each fail.

- **Web/Scripting:**
  > Web (Phase A) proposal: two new §6.7.3 host-cause rows, both exit 1. A missing tool and a killed tool are not compiler bugs, so neither gets an I code.
  > …
  > Two codes, not one. The fix a developer makes differs: install a tool versus free memory. A JS/Python dev reads "not found" and runs `apt install`. They read "killed" and look at memory. A single umbrella code would force them to parse the message.
  > …
  > The label I0017 plus "report this bug" on a missing `cc` costs a wasted issue report each time. That is the worst experience for a new user on a bare Docker image, where `cc` is often absent.

- **PLT:**
  > Rule: 6.7.1 is a function from inputs to outcome. The outcome "cc rejected the C" is a bug only if cc ran and gave a verdict. If cc gave no verdict, the compiler learned nothing about its C. So the split must use what the compiler observes: did cc return a verdict (exit status) or not?
  > …
  > Proposal: ONE new 6.7.3 row, E0860 CCompilerDidNotRun, exit 1. It is the build-side twin of E0856 TestBinaryDidNotRun.
  > …
  > Needed implementation rule (soundness, not style): the decision must not depend on shell exit 127 or 137.

- **DevOps/Tooling:**
  > Position: split by cause, not by tool. Two new E08xx rows in 6.7.3, both exit 1. I0017 stays only for case 4. blink check changes nothing.
  > …
  > Ctrl-C (SIGINT): not a diagnostic. The user stopped the build; exit by the shell convention is outside 6.7.4, so I suggest the compiler prints nothing extra and exits 1. Raise this for the panel.

- **AI/ML:**
  > Position: a missing or killed C compiler is a host cause. Add it to the closed §6.7.3 table. Do not use an I code. Keep exit 1.
  > …
  > an agent that sees I0017 with "the cause is a bug of the compiler" stops and reports a compiler bug, or it rewrites correct source. It cannot self-correct. An agent that sees "no C compiler on PATH" with a help line can run the fix (install cc, or pass zig) with no guess.
  > …
  > A single merged code is a worse fit: the fixes differ (install vs. add memory or retry).

- **Minimalism:**
  > Min, Phase A: add ONE row to 6.7.3, E0860 CCompilerUnavailable, exit 1. It covers "the host cannot run the C compiler" in every form: tool missing (cases 1, 2) and tool killed by a signal (case 3). I0017 stays only for case 4.
  > …
  > Rule (one sentence for the spec): if the C compiler cannot be started, or a signal ends it, the cause is the host (E0860). If it runs and exits non-zero, the C is wrong (I0017).
  > …
  > Signal detail goes in the message text, not in the code.

#### Phase B — Debate (round 1)

The moderator listed three open items: one code or two (Q1), Ctrl-C (V1) and how the compiler detects the cause (V2). All six seats replied and ended with "Stable, ready to vote".

- **Systems:**
  > Q1: Option 1, ONE code (E0860). … Reason: both causes are "host state kept cc from finishing"; a user acts the same way (fix host, rerun). A second code adds a table row with no different behavior.
  > …
  > V2: I move to plt's direct rule. … Hardware view: exit status of a started process is data from that process; do not guess its meaning.

- **Web/Scripting:**
  > Q1: I keep two codes (E0860 not found, E0861 stopped by a signal). The fixes differ: install a tool, or free memory. I do not object to one code if the message names the cause and the help line differs per cause.
  > …
  > V1 (Ctrl-C): I side with devops. SIGINT is the user's own act, not a host fault. … SIGINT delivered to the cc child alone (not to blink) should count as a user stop.
  > …
  > V2: I take plt's direct rule. I withdraw the sh exit 127 detection from my Phase A text.

- **PLT:**
  > Q1: Option 1, one code. Rule: "no verdict from cc = host cause". Two codes add a second row for a distinction that no compiler action depends on; the message already names the signal or the missing tool.
  > …
  > This keeps one decidable test: did the compiler itself receive the signal?
  > …
  > I do not want a fourth code (130).

- **DevOps/Tooling:**
  > Q1: I move to ONE code. I withdraw my E0861 split. CI keys on the code and the "fix the runner" help is the same for both. The signal name goes in the message text, so a log reader still sees SIGKILL vs missing tool.
  > …
  > If the panel wants one simple rule instead, "any signal = E0860" is acceptable to me; a hand-picked signal list is the worse option for a spec.

- **AI/ML:**
  > Q1: I keep two codes (E0860 not found, E0861 stopped by signal). … I will not block one code if the message and help name the cause. This is a preference, not a bar.
  > …
  > V1 (SIGINT): agree with devops. A user interrupt is not a diagnostic: print nothing extra, exit 1. …
  > …
  > V2: I back plt. … Never by shell exit 127 or 137. … I withdraw the 127/126 shell rule from my Phase A.

- **Minimalism:**
  > Q1: one code. Keep option 1. A second code (E0861) adds surface and no new user action: the fix is the same (repair the host, run again), and the message already names the tool and the cause. … Name: CCompilerDidNotRun is better than my CCompilerUnavailable, because it also covers the signal case. I take plt's name.
  > …
  > V1 (Ctrl-C): accept devops. SIGINT to the build is the user's own stop, not a host fault. … Rule: a signal that ends cc is E0860 unless the compiler itself is being interrupted (SIGINT/SIGTERM on the compiler). One clause, no new row.
  > …
  > V2: I withdraw my shell-exit rule and accept plt's direct rule. … A cc that starts and then exits 127 or 137 on its own is "ran and exited non-zero", so I0017.

#### Phase C — Silent ballot

Q1 was 4-2: A (one code) Systems, PLT, Minimalism, DevOps; B (two codes) Web, AI/ML. Q2 was 4-2: A (the test is whether the compiler itself received the signal) Systems, PLT, Minimalism, DevOps; B (the test is SIGINT by number) Web, AI/ML. Web and AI/ML voted B on both. Ballots, verbatim:

- **Systems:** Q1 A, Q2 A.
  > Both causes mean the host kept cc from finishing, and the fix is the same: change the host, rerun. The signal name in the message carries the detail, so a second code adds a table row with no new behavior.
  > Concern: One code lets a script tell "missing" from "killed" only by parsing message text.
  > …
  > Whether blink itself got the signal is a fact the process can read. It gives a fixed rule that does not guess user intent.
  > Concern: A user who runs `kill -INT` on cc by hand sees E0860, which reads as a host fault, not a user stop.

- **PLT:** Q1 A, Q2 A.
  > The rule "cc gave no verdict = host cause" is one predicate, so it needs one row.
  > Concern: Scripts that want to retry only on a signal stop must parse the message text.
  > …
  > The test "did the compiler itself receive the signal" is decidable and does not depend on which signal it was. Test B makes the result of a SIGINT on cc alone differ from every other signal, with no principled reason …

- **Minimalism:** Q1 A, Q2 A.
  > One row covers one user action: repair the host and run again. The message names the tool and the cause, so a second code adds surface and no new information. E0857 and E0858 already group many sub-causes under one code.
  > Concern: Tools that want to tell "install cc" from "raise the memory limit" must parse the message text, not the code.
  > …
  > Under B, the compiler must decide that a SIGINT on the cc child alone is a user stop. It cannot know that, and it adds a signal-specific rule to the spec.

- **DevOps/Tooling:** Q1 A, Q2 A.
  > CI and tooling key on the code, and the help is the same for both causes: fix the runner.
  > Concern: a script that wants to retry only after an OOM kill must parse the message text, since the code does not split the two.
  > …
  > A signal list by number makes a spec rule that depends on which signals people send by hand, and that is fragile.
  > Concern: a CI runner that cancels a job by sending SIGINT or SIGTERM only to the cc child will see E0860, not a quiet exit.

- **Web/Scripting:** Q1 B, Q2 B.
  > The two causes have different fixes. A missing tool needs an install, and a killed tool needs memory or a retry. Two codes let a JS or Python dev, or a CI script, branch on the code without parsing the message.
  > Concern: If the writer gives both codes near-identical help text, the second code adds a table row and no value.
  > …
  > Whoever sends SIGINT, the user meant to stop the build. … The rule is one line: SIGINT is never a host cause.
  > Concern: A SIGINT that something other than the user sends to cc alone (a wrapper script or a CI timeout tool) is hidden as "interrupted" with exit 1 and no host code.

- **AI/ML:** Q1 B, Q2 B.
  > Two causes have two fixes: install the tool, or retry and add memory. With two codes an agent maps the code to the action and does not parse the message.
  > Concern: a later cause (for example a cc that the OS refuses to run) will not fit cleanly into either code, and the spec must say which one takes it.
  > …
  > One rule on the signal number is easier to learn from the spec than a rule on who received it.
  > Concern: a SIGINT that reaches only cc for a real reason (a wrapper script that sends it) would show as a user stop and hide the cause.

#### Phase D — Focused round

Each seat read the other side's ballot and voted a last time. **Q1: 5-1** for one code (AI/ML held B). **Q2: 6-0** for A (Web and AI/ML conceded).

- **Systems:**
  > Q1 rebuttal: … The fix is in the message and help; the compiler takes the same action for both (stop, exit 1, report once). … aiml's concern (a future cause that fits neither) hits two codes harder than one. No concession. Final: Q1 A.
  > Q2 rebuttal: B needs the compiler to guess intent for one signal number on a child it did not signal. … Final: Q2 A.

- **PLT:**
  > Q1: A. … the code is a class of cause, not a repair script. E0857 and E0858 already hold several fixes under one code, so a split here would break that pattern. … I concede the cost: scripts parse the message. Machine-readable detail can come later as a structured field in the JSON diagnostic (cause: not_found | signal), which needs no new code.
  > Q2: A. … The compiler cannot tell a user's `kill -INT` on cc from a CI timeout tool's SIGINT; B calls both "user stop" and hides the second …

- **Minimalism:**
  > Q1: A (final). … Concession: if the closed-table reading needs it, the writer can add a stable `reason:` field to the JSON diagnostic (not_found, signal), so scripts do not parse prose. That adds no code.
  > Q2: A (final). … B makes the compiler guess user intent from a signal number.

- **DevOps/Tooling:**
  > Q1 rebuttal: … the retry case needs the signal name anyway: SIGKILL, SIGTERM and SIGSEGV need different handling, so two codes would still send a script to the message text. A split by code is half a split. … No concession. Final vote: Q1 A.
  > Q2 rebuttal: B hides real host faults. … Final vote: Q2 A.

- **Web/Scripting:**
  > Web, Phase D. I concede both questions.
  > Q1: A (final). Concession: Both causes lead to the same user action, which is to fix the host and run again. … I only ask the writer to put the cause as the first words of the message line, so a reader or a script sees it at once.
  > Q2: A (final). Concession: The test "did the compiler itself get the signal" is a fact the process can read, and it needs no signal list in the spec.

- **AI/ML (dissent on Q1):**
  > Q1: B (hold). Rebuttal: all four A seats name the same cost in their own concern: a script must parse message text to tell "missing" from "killed". That is a worse trade than one table row. The fixes are not the same: install vs retry or add memory. … Message text is also not a stable interface for an agent or a CI script, a code is.
  > Q2: A (concede). Concession: the B rule has a hidden case. A SIGINT on cc alone from a wrapper or a CI timeout becomes a silent stop and hides the cause, which was my own concern. Rule A is one test that the process can read, needs no signal list, and the message names the signal, so an agent still has the data to self-correct.
  > Final: Q1 B, Q2 A.

## Result

Q1 is A (5-1; AI/ML dissented). Q2 is A (6-0). The spec text is the closed table and the paragraphs after it in §6.7.3, the exit `1` row of §6.7.4, the `build_failed` list and the paragraph after it in §8.10.5, and the E0860 row and the I0017 row of the error catalog.

The code name is a writer choice. PLT, Minimalism and DevOps chose `CCompilerDidNotRun`; Systems preferred `CCompilerUnavailable`. The text uses `CCompilerDidNotRun`, because the name is true for a tool that started and was then ended.

### Points Left Open

- The panel did not decide the exit code for a stop on SIGINT or SIGTERM beyond `1`. It chose `1` because §6.7.4 allows no other code and a fourth code (130) was not wanted.

### Facts From Other Languages

- Cargo reports "linker `cc` not found" as a plain error with a help line, and Go prints "gcc: executable file not found in $PATH". Neither tool calls a missing C compiler a bug of the tool. Blink takes the same stance.
- The gcc driver reports a signal-killed `cc1` as an internal compiler error that is separate from a rejection of the source, so tools already treat "killed" as different from "rejected".
