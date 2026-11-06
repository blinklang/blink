[< All Decisions](../DECISIONS.md)

# Rollout of a New Error Before 1.0 — Design Rationale

## 1. The question

§8.16.1 *Rollout of a new error* gave no clear rule for a new error on a program that compiles today. Cases: `fn g[T](x: T) -> Int { h(x) }` with `h[U: Sh]` becomes E0306 (it prints `2` today); a method call on an unbounded `T` becomes E0505 and has no machine-applicable fix; the empty-argument self-call `r([], n - 1)` becomes E0301 under the instance-limit decision; a concrete `S[Bad]` compiles and runs today, and §3.6 has no machine-applicable fix for it. The questions: warning first, or error at once? Does a warning-to-error hop need two codes? ParamAssign (E0612) followed one reading of this rule.

## 2. Owner ruling

The owner ruled on 2026-11-06. The ruling overrides the panel vote in section 3.

> okay, idk why this made it to panel. WE ARE PRE 1.0. WE BREAK THINGS. just move forward. Thats why the changelog is important. its fine.

The rule as written in §8.16.1:

- Before 1.0, a new error that rejects a program that an earlier release built and ran is an error in the first release that has it. There is no warning release.
- The error keeps its machine-applicable fix where one exists that keeps the program's meaning, so `blink fix` still migrates the code. Where no such fix exists, it carries help only.
- The *Breaking Changes* section of the release's CHANGELOG lists each such break, with its fix.
- The warning-first rule stays, for 1.0 and later. Its text does not change except that it is scoped to 1.0 and later.

Effect on the sites that used the warning step:

```blink
fn a() -> Result[(), Str] { Ok() }   // error[VariantArgumentCount] at once; blink fix writes Ok(())

fn dec(n: Int) -> Int {
    n = n - 1                        // error[ParamAssign] at once; blink fix inserts `let mut n = n`
    n
}
```

`Ok()` at the success type `()` and ParamAssign (E0612) were warnings that became errors in the next release. Both are now errors in the first release that has them. The cases of section 3 (`g`, the method call on an unbounded `T`, the empty-argument self-call and `S[Bad]`) are errors at once, with the fix or help that their sections give.

## 3. Panel record (overruled)

The panel ran first. The owner then overruled the result: before 1.0 there is no warning release, so Q2, Q3 and Q4 do not apply before 1.0. They stay as the reading of the rule for 1.0 and later.

| Question | Tally | Result |
|----------|-------|--------|
| Q1 consensus package | 6-0 | Package A |
| Q2 the §8.16.1 test | 6-0 in round 2 (was 4-2) | The last-release test: warning first if the last release built the program and printed what a reader expects; error at once if it rejected it, crashed, hung or miscompiled |
| Q3 `S[Bad]` | 5-1 (PLT dissents) | Warning first, with help only |
| Q4 `E0306` during a warning release | 6-0 | E0306 at the call that makes the instance, never a crash |

Lines from the seats, verbatim. Q2 round 2 (D2):

- **Systems:** "A tool can decide it. Run the last release on the program."
- **Web/Scripting:** "A user can predict what an upgrade does with one `blink run` on the last release, and the panel's own record shows B cannot do the same"
- **PLT:** "My objection was compositionality."
- **DevOps/Tooling:** "One command on the pinned release sorts each program, and a release script, an AI agent or a CI user gets the same answer."
- **AI/ML:** "A model or a person with the last release can apply A from one run, and so far it gives one answer per case."
- **Minimalism:** "A takes one input: run the last release on the program."

Q3 (C):

- **PLT (dissent):** "`type S[T: Tr]` states the bound. `S[Bad]` is not a well-formed type"
- **Web/Scripting:** "0.60.0 printed `1`, so a user may have shipped this."
- **Systems:** "0.60.0 printed `1`, and the bound plays no part in the layout of `S[Bad]`"
- **DevOps/Tooling:** "0.60.0 printed `1`, and no edit keeps the meaning"
- **AI/ML:** "Under either test, a program that ran and broke no sentence a reader could check warns first."
- **Minimalism:** "0.60.0 built it and printed `1`, so under Q2 A it had a meaning."

The owner overruled the result. The CHANGELOG, not a warning release, tells users about a break before 1.0.
