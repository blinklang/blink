[< All Decisions](../DECISIONS.md)

# std.time Date Range — Design Rationale

`Date.from_ymd` and `Date.parse` returned `Err` outside 1677-09-22 ..= 2262-04-11. That range came from the std.time calendar vote ([EQ1](std-time-calendar-date.md), 5-1, Web/Scripting dissenting), which set one range for `Instant` and `Date` because `Instant` is an `Int64` count of nanoseconds. A `Date` is a day count with no time of day. Real data holds dates outside that window: the 9999-12-31 and 0001-01-01 values that mean "no end" and "no start" in contracts and SQL tables, and birth dates before 1677. Python `date`, SQL `DATE` and .NET `DateOnly` cover 0001..9999. A port from those systems failed on valid input.

This decision reopens EQ1 for `Date` only. The `Instant` range does not change. It stays 1677-09-22T00:00:00Z ..= 2262-04-11T23:47:16.854775807Z, and `instant.date()` stays total. The earlier vote kept `Date.to_instant()` total and kept the law `d.to_instant().date() == d`. Both change here: a wider `Date` has days with no `Instant` at midnight.

### Decision

| Question | Result | Vote |
|---|---|---|
| Q1 First day of the Date range | `Date` range is `0001-01-01 ..= 9999-12-31`; `year()` is 1..=9999 | 6-0 in the Phase D re-vote after 4-2 in Phase C (PLT, Minimalism moved from `0000-01-01`) |
| Q2 `Date.to_instant()` outside the Instant range | `fn to_instant(self) -> Result[Instant, ConversionError]`; `Err` exactly when the day's midnight is outside the `Instant` range; the `Err` text is the `Instant` range text for that midnight | 6-0 in Phase C (AI/ML, Minimalism moved from a panic between Phase A and Phase C) |

Every seat agreed on these points:

- `instant.date()` stays total, because every `Instant` lies in the `Date` range.
- `Date.parse` keeps the 4-digit `YYYY-MM-DD` grammar. A 5-digit or negative year is a syntax error, as before. `Display` writes 4 year digits.
- The range texts become `outside 0001-01-01..9999-12-31`, in the `Err` of `from_ymd` and `parse` and in the `add_days` panic.
- Nothing is wider than 9999. There is no `Date.MIN` or `Date.MAX` in this change.
- The rule for the class split (PLT): a panic means arithmetic left the type's own range (`add_days`, `Instant.add`). An `Err` means a valid value has no image in the other type (`to_instant`).
- The guide teaches the `Date`-side comparison, `now.date() <= valid_until`, which never fails, before `to_instant()?`.

Laws after the change:

- `d.to_instant()` is `Ok(i)` with `i.date() == d` exactly when `d` is in the `Instant` range.
- `i.date().to_instant()` is always `Ok`.
- `d.to_instant() <= i` exactly when `d <= i.date()`, whenever `d.to_instant()` is `Ok`.
- `Date.parse("{d}") == Ok(d)` and `d.add_days(n).days_since(d) == n` hold over the new range.

Worked examples that the panel asked for:

```blink
Date.parse("0000-01-01")     // Err: "invalid date: 0000-01-01 outside 0001-01-01..9999-12-31"
Date.parse("0000-02-29")     // Err: same range text; year 0 is a leap year, so the field check passes first
Date.parse("0000-12-31")     // Err: same range text
Date.from_ymd(0, 2, 29)      // Err: same range text
```

The range is not exactly the set of texts that `YYYY-MM-DD` can write: year `0000` is the one exception.

Phase B did not run. Each question had two options, so there was nothing to merge or cut. The record has Phase A (independent proposals), Phase C (silent ballot), and Phase D (a focused round on Q1 only, then a silent re-vote).

Panelist text below is quoted verbatim. Phase A shows excerpts, each with its seat, and "…" marks a cut. Phase C, Phase D and the re-vote show each reply whole, except that a first line that only named the work item is dropped, and the work item ID is cut from PLT's first line in Phase D. Heading levels are shifted to fit this file.

### Phase A — Independent proposals

- **Systems:** "Widen Date to **0001-01-01 ..= 9999-12-31**. Make `to_instant` return **`Result[Instant, ConversionError]`**. … **Why 0001 and not 0000:** year 0 means 1 BC in proleptic Gregorian. Python, SQL and .NET reject it. … A panic belongs to programmer error, such as `add_days` overflow or `Int` overflow. Here the failing input is **ordinary data**: the 9999-12-31 sentinel is the *reason* this ticket exists. … Rust precedent: chrono deprecated `timestamp_nanos()` (it panics) for `timestamp_nanos_opt()` because a wide date type and an i64-ns instant had this same mismatch."
- **Web/Scripting:** "The current rule makes the common job fail so that the less common job can be total. … Panic**: a sentinel row in production crashes the job. That is the worst outcome for a scripting user: the program worked in testing (all test dates were recent) and dies on real data. … Rust chrono went the same way for the same Int64-ns cause: `timestamp_nanos()` (panics) is deprecated for `timestamp_nanos_opt()`."
- **PLT:** "A type's range must come from its own definition, not from a sibling's representation. … Why 0000 and not 0001: with 0000 included, Date and the `YYYY-MM-DD` texts that pass the field checks are in **bijection**. … Second choice P2: 0001-01-01 ..= 9999-12-31 (Python, SQL Server). … The class split is now principled. A **panic** means arithmetic left the type's own domain (`add_days`, `Instant.add`), the same class as Int overflow. An **Err** means a valid value has no image in the other type, the same class as a parse error."
- **DevOps/Tooling:** "Every Date in this range prints as exactly `YYYY-MM-DD`, and `Date.parse` reads back every one of them. … 0001 and not 0000: Python `date.min`, SQL Server `DATE`, .NET `DateOnly` and most ERP exports start at 0001-01-01. … A crash that depends on the data and that no test finds is the worst kind of failure to diagnose. A `Result` puts the case in the signature. … Rust chrono made the same change for the same Int64-ns limit. `timestamp_nanos()` panicked outside 1677..2262. chrono 0.4.31 deprecated it for `timestamp_nanos_opt() -> Option<i64>`."
- **AI/ML:** "Widen Date to **0001-01-01 ..= 9999-12-31**. Keep `to_instant() -> Instant` with the same signature, and make it **panic** for a Date outside the Instant range … Why panic and not `Result` or `Option`: std.time already has one rule. **Text in gives `Err`; a value computed past the edge panics** (`add_days`, `Instant.add`, `from_epoch_secs`)."
- **Minimalism:** "Widen Date to **0000-01-01 ..= 9999-12-31**, the exact set of days the `YYYY-MM-DD` grammar can spell. Keep `to_instant() -> Instant` with the same signature, and let it panic outside the Instant range with the panic text that already exists. … Why 0000 and not 0001: with 0000 the range is the grammar, so `Date.parse` has **no range error at all**."

Four seats (Systems, Web/Scripting, PLT, DevOps/Tooling) proposed a `Result` for `to_instant`. Two (AI/ML, Minimalism) proposed to keep the signature and panic. Four seats proposed 0001-01-01 as the first day. PLT and Minimalism proposed 0000-01-01 and named 0001-01-01 as their second choice.

### Phase C — Silent ballot

#### Systems

Q1: Q1-0001
Reasoning: The two options cost the same at run time. Each is one year compare (`y >= 1` or `y >= 0`, plus `y <= 9999`), and neither lets `days_from_civil` overflow. So the tie breaks on the job Date does: it carries values to and from SQL DATE, Python `date` and .NET `DateOnly`, which all start at 0001. With 0000, a Blink Date can write a value that those systems reject on the way out, and that failure lands outside Blink, where no Blink check can catch it. The plt/min bijection is a real gain, but it saves one Err branch inside `parse` and moves the failure to a foreign system.
Concern: One text that matches the grammar (`0000-MM-DD`) stays a range Err in `parse`. The spec must list it in the examples so nobody reads the "range = grammar" claim as exact.

Q2: Q2-result
Reasoning: Today's `d.days * TIME_NANOS_PER_DAY` silently wraps past day ±106751, so each design needs the same compare pair in `to_instant`. Panic and `Result` cost the same branch, and the Ok path adds only a tag. With equal cost, the type must show the failure. The input that fails is the 9999-12-31 sentinel, which is ordinary data and not overflow, and a panic turns it into a production crash that no test with recent dates finds. chrono hit this exact Int64-ns mismatch and replaced its panicking `timestamp_nanos()` with `timestamp_nanos_opt()`.
Concern: The migration hits `d.to_instant().add(x)` sites with a bare `UnresolvedMethod on Result[...]` error and no help line (devops probed this). Ship the typecheck help line and the updated `.to_instant()` hint at src/typecheck.bl:24352 in the same change.

#### Web/Scripting

Q1: Q1-0001
Reasoning: A JS/Python dev brings Python `date.min`/`date.max` and SQL `DATE`: 0001..9999. Data from those tools never holds year 0, and a Blink Date with year 0 is one they cannot write back to Postgres, SQL Server or Python, so it fails at the export step instead. The PLT/Min point (no range error in `parse`) is real, but it saves one Err case that a user meets almost never. Matching the tools users already know saves more Stack Overflow questions than removing that case.
Concern: The one remaining in-grammar range error, `Date.parse("0000-01-01")`, needs its exact text in the spec and a test, or it drifts from the `from_ymd` text.

Q2: Q2-result
Reasoning: The ticket exists because of the 9999-12-31 sentinel row. With a panic, code that does `valid_until.to_instant()` passes every test that uses recent dates and then crashes in production on the first sentinel row, which is the worst "works on my machine" bug for a scripting user. `Result` puts the case in the signature, the compiler finds every caller, and the cost on the common path is one `?`. The "text gives Err, computed gives panic" split does not fit here: the input is valid data, not arithmetic overflow, and Rust chrono moved from a panicking `timestamp_nanos()` to `timestamp_nanos_opt()` for this exact mismatch.
Concern: Users reach for `d.to_instant().unwrap()` to make the type error go away, which brings the production crash back; the spec example and the guide must show `now.date() <= valid_until` first, so that the total form is the one people copy.

#### PLT

Q1: Q1-0000
Reasoning: With 0000, the Date type and the field-valid `YYYY-MM-DD` texts are in bijection. `Date.parse` is then total on its grammar except for syntax and field errors, and `parse`/`Display` are inverses in both directions, not only one. With 0001, the grammar admits a string (`0000-MM-DD`) that the type rejects for a reason outside the grammar and the calendar. That is the same kind of seam the ticket complains about, only smaller. The interop argument cuts both ways: under 0001 every Blink Date exports to Python/SQL; under 0000 every Python/SQL date imports to Blink. Year 0 is also what the proleptic Gregorian calendar with astronomical years (ISO 8601) and `from_ymd(y: Int)` already give. Both options are sound, and I accept 0001 as second choice.
Concern: if Q1-0001 wins, `Date.parse` keeps a range check that only the year 0000 can reach. It needs its own test rows (`0000-01-01` and `0000-02-29` are Err with the range text, and the field check runs first), or the check will rot unseen.

Q2: Q2-result
Reasoning: Date → Instant is now a partial map, and a partial function must not have a total type. The panic class in std.time is "arithmetic left the type's own domain" (`add_days`, `Instant.add`, the same class as `Int` overflow). `to_instant` on 9999-12-31 is a different case: a valid value that has no image in another type, which is the conversion-error class that `from_ymd` and `parse` already return as `Result`. The aiml rule "text in gives Err, computed gives panic" does not fit here: the failing input is a valid Date, often read straight from data. A panic would bring back the hidden precondition that EQ1 rejected for `instant.date()`, now on the reverse map. With `Result`, the Galois-connection law keeps its shape: it holds wherever the left adjoint is `Ok`, and `i.date().to_instant()` is always `Ok`.
Concern: the `?` at each call site may push users to write `.unwrap()` by reflex, which brings back the panic one level up. The spec and the typecheck hint must teach the total Date-side comparison (`now.date() <= d`) first, and give `to_instant()?` only for a real conversion.

#### DevOps/Tooling

Q1: Q1-0001
Reasoning: The error surface that matters is between tools, not inside `Date.parse`. With 0000 in range, Blink accepts and writes `0000-01-01`, then Python `date.fromisoformat`, SQL Server `DATE` and .NET `DateOnly` reject that text later, in another process, with their own message. With 0001 the rejection happens at the Blink boundary, with a message that names the range: `invalid date: 0000-01-01 outside 0001-01-01..9999-12-31`. The parse bijection that min and plt want is real, but it removes one range-error case in exchange for a failure that is harder to trace in a pipeline. `from_ymd` keeps a range error either way, so the error class does not go away.
Concern: the range check must be the plain year check (`y >= 1 && y <= 9999`), and the test rows must cover `0000-12-31` in `parse` and `from_ymd(0, 2, 29)` (field check passes because year 0 is a leap year, then the range check fails). Otherwise the one day past the low edge goes untested.

Q2: Q2-result
Reasoning: A panic in `to_instant` depends on the data. Tests with recent dates pass, and production then crashes on the first 9999-12-31 row, the exact value this ticket exists for. The stack trace points at a line with no bug in it. A `Result` puts the case in the signature: the LSP hover shows it, and the compiler finds every call site during migration. The panic side's rule, "text gives Err, computed gives panic", does not fit: `add_days` panics because its result leaves Date's own domain, but a valid 9999-12-31 Date that has no Instant is a conversion failure, the same class as `Date.parse` returning Err. The Err text is the existing Instant range text, so no new message family.
Concern: today `d.to_instant().add(x)` on a `Result` gives `error[UnresolvedMethod]: unresolved method .add on type Result[Instant, ConversionError]` with no help line (probed with gen1). Each migrated call site hits that error, so the implementation should add `help: Instant has .add; handle the Result first, e.g. with ?`. The typecheck hint that now says "call `.to_instant()`" (src/typecheck.bl, cited by sys) must also change: `i.date()` for comparisons, `.to_instant()?` for conversion.

#### AI/ML

Q1: Q1-0001
Reasoning: Models arrive with 0001-01-01 ..= 9999-12-31 from Python `date.min`/`date.max`, SQL `DATE` and .NET `DateOnly`. That is the range they write sentinels in, and the edge they expect to fail. Q1-0000 drops one parse range error, but `0000-01-01` almost never shows up in real data. And `Date.from_ymd(0, 2, 29)` being `Ok` is a fact a model cannot get from its priors. Matching the prior removes more wrong guesses than the bijection does.
Concern: If Q1-0001 wins, the spec must show `Date.parse("0000-01-01")` as a range Err (not a syntax Err) in an example, or models will guess wrong about which error class it is.

Q2: Q2-result
Reasoning: I change from my Phase A position. The devops, sys and web papers convinced me that for generated code, the cost that counts is when the mistake shows up, not how many tokens it takes. An agent sees a compile error at once and fixes it in the same loop. A panic shows up only when production data hits a sentinel row, which a model's tests (all recent dates) will never hold. A `Result` puts the partiality in the signature that the model reads from `blink query` or hover, and it costs one `?` token on the rare crossing call. PLT's split ("panic = arithmetic left the type's own domain; Err = a valid value has no image in the other type") is a rule as short as my "text vs computed" rule, and it fits more cases. The chrono `timestamp_nanos` -> `_opt` deprecation shows the panic form gets reversed after users hit it.
Concern: Models from training will write `d.to_instant().add(x)` and `d.to_instant() <= now` with no `?`. The fix depends on the UnresolvedMethod-on-Result diagnostic getting a help line ("handle the Result first, e.g. with `?`"; compare with `d <= i.date()`), so file that chore with the change.

#### Minimalism

Q1: Q1-0000
Reasoning: With 0000 the range is exactly the set of days the 4-digit grammar can write, so `Date.parse` loses its range error. That is one error class fewer, with no new rule. Year 0 is what proleptic Gregorian with astronomical year numbers gives (ISO 8601, RFC 3339 `4DIGIT`), and `from_ymd` already takes any `Int` year with no "no year zero" rule. Matching Python and SQL at 0001 adds a check and an Err case that exist only to copy them.
Concern: If 0000 wins, a Blink program can write `0000-MM-DD` that Python, SQL Server and .NET then reject. Blink data passed to those tools fails at their parser, not at ours.

Q2: Q2-result
Reasoning: I change my Phase A vote. Both options add zero names, so surface does not break the tie. What breaks it is what comes next. A panicking `to_instant` on data that is valid (the 9999-12-31 sentinel this ticket is about) is the chrono `timestamp_nanos()` path, and that path ended in a second method, `_opt`. That gives two names for one job, which is the extra surface I vote against. A `Result` now costs one `?` on a rare call and needs no later addition. PLT's split is also the simpler rule to state: a panic means arithmetic left the type's own domain; an `Err` means a valid value has no image in the other type.
Concern: The breaking signature change hits the spec's `d.to_instant().add(...)` idiom. The guide and the `UnresolvedMethod`-on-`Result` hint must teach `?` there, or models will write `.unwrap()` everywhere and bring back the panic.

Q1 was 4-2: Q1-0001 (Systems, Web/Scripting, AI/ML, DevOps/Tooling) against Q1-0000 (PLT, Minimalism). Q2 was 6-0 for the `Result`.

**Dissent (Q1, PLT and Minimalism, Phase C):** the range `0000-01-01 ..= 9999-12-31` puts `Date` and the field-valid `YYYY-MM-DD` texts in bijection. PLT: "With 0000, the Date type and the field-valid `YYYY-MM-DD` texts are in bijection." Minimalism: "With 0000 the range is exactly the set of days the 4-digit grammar can write, so `Date.parse` loses its range error." Their stated concern, if 0001 won: PLT, "`Date.parse` keeps a range check that only the year 0000 can reach. It needs its own test rows"; Minimalism, "a Blink program can write `0000-MM-DD` that Python, SQL Server and .NET then reject".

### Phase D — Focused round on Q1

#### Systems

The strongest point against me is plt's: "interop cuts both ways; under 0000 every Python/SQL date
imports to Blink." But the import direction does not separate the options. Python `date`, SQL Server
`DATE` and .NET `DateOnly` start at 0001, so every date they write imports under 0001 too. Only the
export direction differs, and 0001 wins it: 0001..9999 lies inside both sets, and 0000..9999 does
not. The year-0 sources (Java `LocalDate`, JS, Postgres BC dates) also write negative and 5-digit
years, and our grammar rejects those under both options. So 0000 does not make them import cleanly.

The bijection gain is smaller than it looks. `from_ymd` keeps a range error under both options, so
the range-error class and its text stay in the spec and in lib/std/time.bl. Q1-0000 removes one
branch from `parse`, not an error class. The cost is the same: one year compare.

I do not move. I stay on Q1-0001, with the test rows that plt and devops asked for:
`Date.parse("0000-01-01")`, `Date.parse("0000-02-29")` and `Date.from_ymd(0, 2, 29)` all give Err
with the range text.

#### Web/Scripting

Web, Phase D (Q1): I stay at Q1-0001.

The strongest point on the other side is PLT's "interop cuts both ways: under 0000 every Python/SQL date imports to Blink". It does not cut both ways. Python, SQL and .NET produce only 0001..9999, so under 0001 every date they write already imports. Year 0 adds import only from ISO-astronomical sources (Java `LocalDate`, JS `Date`), and those can also write 5-digit and signed years that our grammar rejects anyway, so 0000 does not make those sources whole. The trade is then: 0000 removes one in-grammar range Err that real data almost never reaches, and in return lets Blink write a value that the most common target systems reject later, in another process, with their own message.

Min's own concern says the same thing. On bijection: it is a nice property for the spec, but users do not see it. They see "my export to Postgres failed", or they do not.

I agree with the PLT, sys and aiml concerns: the spec must show `Date.parse("0000-01-01")` as a range Err (field check first, so `0000-02-29` is also the range Err), with test rows.

#### PLT

PLT, Phase D (Q1): I CHANGE to Q1-0001.

The strongest point is from devops and sys: "with 0000 in range, Blink accepts and writes `0000-01-01`, then Python, SQL Server and .NET reject that text later, in another process", and "`from_ymd` keeps a range error either way, so the error class does not go away".

The second half decides it for me. My bijection argument removes the range error from `parse` only. The range-error class stays in the type (through `from_ymd` and `add_days`), so the language keeps exactly the same set of failure kinds under both options. What is left is one string in the grammar's image that the type does not hold. That is a real cost to the elegance of `parse`, but it is not a soundness cost: `Date.parse("{d}") == Ok(d)` holds for every Date under both options.

Both options are sound, so the tie breaks on where a failure shows. Under 0001, the failure happens at the Blink boundary, with a message that names the range. Under 0000, it happens in a foreign parser with no link back to Blink. A failure with a typed, named cause at our own boundary is the better place.

Condition: the spec states the one in-grammar range Err as a worked example (`Date.parse("0000-01-01")` and `Date.from_ymd(0, 2, 29)` give the range text, and the field check runs first), with test rows for both.

#### DevOps/Tooling

DEVOPS, Phase D (Q1). I stay at Q1-0001.

The strongest point from the other side is plt's "interop cuts both ways: under 0000 every Python/SQL date imports to Blink". It does not cut both ways. Python `date`, SQL Server `DATE` and .NET `DateOnly` all start at 0001, so every date they can send is already inside 0001..9999. Both options import the same set. (Postgres BC dates fit in neither.) The two options differ only on export, and only 0000 adds a failure there: Blink accepts `0000-01-01`, writes it out, and a foreign parser rejects it in another process, with a message Blink does not control. ISO 8601 also allows years before 1583 only "by mutual agreement" between the parties, so year 0 has no general support on the wire.

The bijection is real, but it gets rid of one Err case at the Blink boundary. That Err gives the user a clear message (`invalid date: 0000-01-01 outside 0001-01-01..9999-12-31`) at the point where the bad value comes in. Without it, the failure comes later, in another tool. For diagnostics, the early error is better.

I agree with the concerns about tests: the spec example and the test rows must show `Date.parse("0000-01-01")` and `Date.parse("0000-02-29")` as range errors, with the field check run first.

#### AI/ML

aiml, Phase D (Q1): I stay on Q1-0001.

Strongest other-side point (plt): "interop cuts both ways: under 0001 every Blink Date exports, under 0000 every Python/SQL date imports." The two directions do not weigh the same. Python `date`, SQL Server `DATE` and .NET `DateOnly` cannot hold year 0, so they never send one. Under 0001 Blink already accepts every date those tools can produce, and the import gain from 0000 is zero. The export loss is real: Blink would write `0000-MM-DD` and the other tool's parser would reject it later, in a different process, with a message that does not name Blink's range.

Bijection (plt, min): it removes the range Err from `Date.parse` only. `from_ymd` keeps the range class either way (`-001`, `10000`), so a model still has to learn "range errors exist". What 0000 adds is one fact no model has from training: year 0 is valid and a leap year. That is a new decision point for a day no real data holds.

What would move me: real data sources that write year 0000 dates which Blink must read. None has been shown.

Condition from my seat: the spec shows `Date.parse("0000-01-01")` with its exact range Err text in an example, and tests cover it (as sys, web, devops and plt also asked).

#### Minimalism

The strongest point on the other side is devops's: `from_ymd` keeps a range error either way, so the error class does not go away. That breaks my Phase C reason. I counted "no range error in `parse`" as one fewer error class. It is not. The check, the text `YYYY-MM-DD outside ...`, and its tests all exist under both options. Under 0001, `parse` reaches the same check with one more input (`0000-MM-DD`). That adds zero names, zero texts and zero rules. It only adds a test row.

With equal surface, a minimalist breaks the tie on what each option costs outside the spec. Under 0000, a Blink Date can hold a value that Python, SQL and .NET reject later, in another process, with their own message. Under 0001 the edge matches what users and models already expect, and the error names the range at the Blink boundary.

PLT's bijection is clean, and "every Python/SQL date imports" holds under both options, since neither tool makes year 0.

I move to **Q1-0001**.

Condition: the spec shows `Date.parse("0000-01-01")` as a range Err with its exact text, and the tests cover `0000-12-31` and `from_ymd(0, 2, 29)` (the field check passes, then the range check fails).

Two points moved PLT and Minimalism. The first: `from_ymd` and `add_days` keep the range error under both options, so 0000 removes one branch from `parse` and no error class. DevOps/Tooling (Phase C): "`from_ymd` keeps a range error either way, so the error class does not go away." PLT (Phase D): "The second half decides it for me. My bijection argument removes the range error from `parse` only." Minimalism (Phase D): "That adds zero names, zero texts and zero rules. It only adds a test row." The second: the interop point. DevOps/Tooling (Phase D): "Python `date`, SQL Server `DATE` and .NET `DateOnly` all start at 0001, so every date they can send is already inside 0001..9999. Both options import the same set." That leaves only the export direction, and only 0000 adds a failure there.

### Phase D — Silent re-vote on Q1

#### Systems

Q1: Q1-0001
Reasoning: The run-time cost is the same either way: one year compare, and `days_from_civil` cannot overflow. `from_ymd` keeps the range-error class under both options, so 0000 removes only one branch from `parse`. 0001..9999 is the subset that Python, SQL Server and .NET can all hold. So under 0001, every Date Blink accepts can also leave Blink, and a bad value fails at the Blink boundary with a message that names the range, not later in a foreign parser.
Concern: The implementation must make the low edge a plain year check (`y >= 1 && y <= 9999`), not a day-count compare. Test rows must cover `Date.parse("0000-01-01")`, `Date.parse("0000-02-29")` and `Date.from_ymd(0, 2, 29)` (the field check passes, then the range Err comes), plus `add_days(-1)` on 0001-01-01, or the one day past the edge goes untested.

#### Web/Scripting

Q1: Q1-0001
Reasoning: The edge matches Python `date.min`, SQL `DATE` and .NET `DateOnly`, so a JS/Python dev never has to learn a new low edge, and every date those tools write still parses in Blink. A Blink Date can never hold a value that those tools reject later, in another process. The range-error class stays under both options (through `from_ymd` and `add_days`), so 0001 adds one test row and no new rule.
Concern: A reader may take "the range is what `YYYY-MM-DD` can write" as exact; the spec must show `Date.parse("0000-01-01")` and `Date.from_ymd(0, 2, 29)` as range Errs (the field check runs first), with test rows, so that the one in-grammar exception is visible.

#### PLT

Q1: Q1-0001
Reasoning: Both options are sound. `Date.parse("{d}") == Ok(d)` holds for every Date under each one, and the range-error class stays in the type either way, through `from_ymd` and `add_days`. The panel also showed that my "interop cuts both ways" point was wrong. Python, SQL Server and .NET never write year 0, so 0000 adds nothing on import, and only the export direction differs. With failure kinds equal, the right place for a failure is the Blink boundary, where it has a typed cause and a message that names the range. A foreign parser in another process is the wrong place.
Concern: `Date.parse("0000-01-01")` is the one text that matches the grammar but is outside the range. The spec must show it, and `0000-02-29` / `from_ymd(0, 2, 29)` (field check first, then the range Err), as worked examples with test rows. Otherwise readers will take "range = 4-digit grammar" as exact.

#### DevOps/Tooling

Q1: Q1-0001
Reasoning: All six seats now agree that the range-error class and its text stay under both options (through `from_ymd` and `add_days`). So 0000 removes one branch from `parse` and keeps every error class. What is left is where the failure shows up. With 0001, `0000-01-01` fails at the Blink boundary with a message that names the range. With 0000, it fails later in Python, SQL Server or .NET, in another process, with a message Blink does not control. The early, named error is the better diagnostic.
Concern: the one range Err that the grammar can reach (`Date.parse("0000-01-01")`, and `0000-02-29`, where the leap-year field check passes and then the range check fails) gets no example in the spec and no test row, and then its text drifts from the `from_ymd` text.

#### AI/ML

Q1: Q1-0001
Reasoning: The edge matches the 0001..9999 that models bring from Python `date`, SQL `DATE` and .NET `DateOnly`, so generated sentinel code and edge checks are right the first time. As plt, min and devops all now agree, `from_ymd` keeps the range error class under both options, so 0000 saves no rule a model must learn. It only adds one fact no model has from training (year 0 is valid and a leap year). Under 0001 the one failure happens at the Blink boundary, with a message that names the range. An agent can fix it from that output alone.
Concern: A model may assume `Date.parse("0000-01-01")` fails as a syntax error or succeeds as in Java, so the spec must show its exact range Err (and `0000-02-29` and `from_ymd(0, 2, 29)`, where the field check passes first) in a worked example, with test rows.

#### Minimalism

Q1: Q1-0001
Reasoning: Both options keep the same failure kinds, because `from_ymd` and `add_days` keep the range error and its text under either one. Q1-0000 removes one branch in `parse`, not a concept, so the surface is equal. The tie breaks on cost outside the spec. Under 0001, Blink takes in every date that Python, SQL and .NET can write, and it never writes a date they reject. Under 0000, a failure moves into a foreign parser in another process, with a message Blink does not control.
Concern: The one range error inside the grammar (`Date.parse("0000-01-01")`, and `0000-02-29`, where the field check passes first) can go untested. It needs a spec example with its exact text and test rows, or the check will drift from the `from_ymd` text.

### Q2 — Cross-language note

Rust's chrono met the same `Int64` nanosecond limit. Systems (Phase C): "chrono hit this exact Int64-ns mismatch and replaced its panicking `timestamp_nanos()` with `timestamp_nanos_opt()`." AI/ML (Phase C): "The chrono `timestamp_nanos` -> `_opt` deprecation shows the panic form gets reversed after users hit it." A panic here would also need a second, checked method later. Minimalism (Phase C): "that path ended in a second method, `_opt`. That gives two names for one job, which is the extra surface I vote against."

### Spec changes

- sections/03_types.md §3.2.3 *Date and Weekday*: the range, the `year` note, the `to_instant` signature, the range error and panic texts, the worked examples for year 0000, the laws, the `Date`-side comparison example, and the rewritten rationale paragraphs.
- DECISIONS.md: the *std.time calendar API (Date, Weekday)* row now states the new Date range and the `Result` from `to_instant`, and links this decision.
- [std-time-calendar-date.md](std-time-calendar-date.md) gets a pointer to this file at EQ1.
- The `Instant` range, the `Instant` range texts, `Instant.parse`, `Instant.add` and `instant.date()` do not change.

### Follow-up for the implementation

- Calls of the form `d.to_instant().add(x)` stop compiling. The compiler error for a method of `Instant` called on a `Result` should name the fix: handle the `Result` first, for example with `?`.
- The type-check hint that now says "call `.to_instant()`" for a `Date`/`Instant` mismatch should say `i.date()` for comparisons and `.to_instant()?` for a conversion.
- Test rows: `Date.parse` and `Date.from_ymd` at 0001-01-01, 9999-12-31, 0000-12-31, 0000-02-29 (field check passes, range check fails) and 10000-01-01; `add_days` one day past each edge; `to_instant` at 1677-09-21 (`Err`), 1677-09-22 (`Ok`), 2262-04-11 (`Ok`) and 2262-04-12 (`Err`), with the exact `Err` text.
