[< All Decisions](../DECISIONS.md)

# std.time Calendar API (Date, Weekday, Instant Calendar Methods) — Design Rationale

sections/03_types.md named `std.time.DateTime` and `DateTime.from(instant)` but gave no API, and lib/std/time.bl had none. Programs could not group log lines by date, count the days between two dates or get the day of the week without hand-written calendar math. The panel chose the type set, the parse grammar, the range of the module and the error texts.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds, then a re-vote on Q3 and a focused round on the exact edges of the range.

Panelist text below is quoted verbatim, each reply whole. Only the heading levels are shifted to fit this file, and the scratchpad paths in the lead's broadcasts are replaced by a pointer to the section that quotes the file. Option labels are in the ballots.

Two notes for readers of the record:

- The panel wrote `line.slice(0, n)` for cutting a timestamp out of a log line. `Str` has no `slice`; the spec writes `line.substring(0, n)`, which is the same cut for ASCII stamps.
- Q6 line 8 gave the range as "~1677-09-21..2262-04-11". The edge round (EQ1, E1c) replaced it with 1677-09-22T00:00:00Z ..= 2262-04-11T23:47:16.854775807Z for Instant and 1677-09-22 ..= 2262-04-11 for Date. Systems proposed E2 in the edge round and withdrew it in the debate in favor of E1c.

### Tally

| Question | Result | Vote |
|---|---|---|
| Q1 Type set | T1: Date + Weekday, calendar methods and parse on Instant, no DateTime in v1 | 6-0 |
| Q2 Weekday Int bridge | A: built-in tag only; Monday = 0 … Sunday = 6 stated outright | 6-0 (PLT moved from B2) |
| Q3 `Instant.parse` separator | B: `T` or exactly one U+0020, closed grammar | 6-0 in Phase D after 4-2 in Phase C (Systems, Minimalism moved from A) |
| Q4 `day_of_year` | A: out of v1 | 6-0 |
| Q5 Future zone names | A: "no zone support in v1", no name reserved | 6-0 |
| Q6 Core bundle (15 lines) | APPROVE | 6-0 |
| EQ1 Instant-side lower edge | E1c: one std.time range from 1677-09-22T00:00:00Z; every Instant constructor checks it | 5-1 (Web/Scripting dissents for E1b) |
| EQ2 Range-error text | R1: names the range, no byte offset | 6-0 (PLT moved from offset 0) |

**Dissent (EQ1, Web/Scripting, from the edge debate):** "it changes the closed `Instant` contract (Int64 nanos, an approved earlier decision) and adds a range check on every `Instant.add` to guard a day no one reads."

#### Phase A — Independent proposals


======================================================================
##### MINIMALISM (min)
======================================================================
MINIMALISM panelist, Phase A proposal for pmpmyc (std.time.DateTime).

##### Starting point

`Instant` is already a UTC date-time: it holds nanoseconds since the epoch, and `lib/std/time.bl` already runs Hinnant's `civil_from_days` to print `2026-02-14T12:00:00Z`. A UTC-only `DateTime` would be a second way to store the same value. That breaks "one way to do it", and the open audit tickets already target exactly this kind of duplicate. The real gap is narrower. It has two parts: there is no **calendar date** value, and `Instant` cannot **parse** its own Display text. Close those two holes and stop.

##### Proposal M1 (preferred): `Date` + `Instant.parse`, no `DateTime`, no timezones

**Surface (12 items in total):**

- `Instant.parse(s: Str) -> Result[Instant, ConversionError]`. It reads RFC 3339 / RFC 9557 text. A numeric offset (`+05:30`) is applied and the result is UTC. Applying an offset is arithmetic, not timezone support. It is the inverse of the Display text that `Instant` already has.
- `pub opaque type Date`, stored as Int days since 1970-01-01. It derives Eq, Ord, Hash, Clone, Debug and Display. Display is ISO `2026-02-14`.
  - Constructors: `Date.from(i: Instant)` (the `From` trait; this keeps the spec's `.from(instant)` wording), `Date.new(y, m, d) -> Result[Date, ConversionError]`, `Date.parse(s) -> Result[Date, ConversionError]`.
  - Accessors: `year()`, `month()` (Int, 1..12), `day()`, `weekday() -> Weekday`.
  - Arithmetic: `add_days(n: Int) -> Date`, `days_since(other: Date) -> Int`, `to_instant() -> Instant` (midnight UTC).
- `type Weekday { Mon, Tue, Wed, Thu, Fri, Sat, Sun }` with Display. It is an enum, not Int: Blink enums are nominal, and an agent cannot misread an enum as 0-based or 1-based.

```blink
import std.time

fn day_report(lines: List[Str]) -> Result[Map[Date, Int], ConversionError] {
    mut counts: Map[Date, Int] = Map.new()
    for line in lines {
        let stamp = Instant.parse(line.split(" ").get(0).unwrap())?
        let d = Date.from(stamp)
        counts.insert(d, counts.get(d).unwrap_or(0) + 1)
    }
    Ok(counts)
}

fn main() ! Time.Read {
    let today = Date.from(time.read())
    let release = Date.new(2026, 12, 25).unwrap()
    print("{release.days_since(today)} days left, release is a {release.weekday()}")

    // Hour of day: composes from what exists, no new API
    let now = time.read()
    let since_midnight = now.since(Date.from(now).to_instant())
    print("hour = {since_midnight.to_seconds() / 3600}")
}
```

**What I left out, and why:**

| Omitted | Reason |
|---|---|
| `DateTime` (UTC) | Duplicates `Instant`. Keep the name free for a zoned type in a later version, where it would carry real meaning. Edit 03_types.md: replace `std.time.DateTime` / `DateTime.from(instant)` with `std.time.Date` / `Date.from(instant)`. |
| Timezones / local time | They need tzdata, DST rules, and an ambient read of `/etc/localtime` or `TZ`, which means new effect rows (FS.Read/Env). They also bring ambiguous and missing local times (DST gaps and folds). This is the C++ `<chrono>` tz trap: the biggest cost for the smallest share of benchmark tasks. Leave them out of v1 entirely. |
| `Date.today()` | Hides the clock read. `Date.from(time.read())` keeps `Time.Read` in the effect row and works with `mock_clock` at no extra cost. |
| `add_months` / `add_years` | What is Jan 31 + 1 month? Clamp, overflow, or error: each choice needs its own panel vote. `add_days` covers the benchmark tasks. |
| strftime / format strings | A mini-language inside a string, with its own syntax and errors. Interpolation plus the accessors, plus the Str pad helpers just specced (eb89f85c), covers it: `"{d.day()}/{d.month()}"`. |
| `hour()/minute()/second()` on Instant | The `since(midnight)` pattern covers them. Add them later only if friction tickets show demand. |
| `Month` enum, ordinal day, ISO week | Not needed by the tasks in the ticket. |
| A new `DateError` type | Use the fixed `ConversionError`, the same as `parse_int` and `Char.from_code_point`. |

**Tradeoffs:**
- (+) The cost to learn is about 12 names, and all of them follow conventions Blink already has (`.parse`, `.from`, named methods, no operators).
- (+) It reuses the civil-calendar code that `time.bl` already has, so the work is small and the risk is low.
- (+) Two types with two different jobs: `Instant` is a point in time, `Date` is a calendar day. Nothing overlaps.
- (−) Hour of day takes 2 lines, not 1. I accept that until friction proves otherwise.
- (−) No local time. A program that must print "9am in Denver" cannot do it in v1. That is deliberate, and the spec should say so.

**Other languages:** Go has a single `time.Time` that holds a zone, which pulled tzdata into the core package. Java 8's `LocalDate` is the model for M1's `Date`. Its `LocalDateTime` became a familiar source of bugs (a date-time with no zone that people treat as an instant), and M1 does not copy that mistake. Rust std has no calendar type at all, so the ecosystem split between `chrono` and `time`. M1 avoids that split with a small, closed set in std.

##### Proposal M0: do nothing, document the formula (rejected)

This would put a `days_from_civil` recipe in `blink llms` and leave the API alone. I reject it. Calendar arithmetic is the classic thing every user writes wrong, the ticket is P0, and the spec already promises a calendar type. This is foundational, so I vote yes on adding something. The open question is only how small it can be.

##### Proposal M2 (fallback if the panel insists on a `DateTime` name)

`DateTime` becomes a plain UTC struct with public fields `{ date: Date, hour, minute, second, nanos }`. It has no methods except `from(Instant)`, `to_instant()` and Display. All arithmetic stays on `Instant` and `Date`. That adds 1 type and 3 functions to M1, and no logic is duplicated. I vote M1 first and accept M2 second. Any zoned type, DST handling or tzdata in v1 gets a no from me.

======================================================================
##### WEB/SCRIPTING (web)
======================================================================
WEB/SCRIPTING Phase A: I propose two UTC-only types, `Date` and `DateTime`, with no timezones in v1.

##### W1 (primary): `Date` + `DateTime`, both UTC-only, no zones in v1

The JS `Date` object and Python's naive/aware `datetime` split produce more Stack Overflow questions than any other stdlib type. Both bugs come from one thing: the type silently uses local time, or it lets you mix values with a zone and without one. TC39 Temporal (PlainDate / ZonedDateTime) is the industry's correction. We can ship that correction on day one at a fraction of the cost: a plain civil date, a UTC date-time, and nothing that reads the host's zone.

```blink
import std.time
import std.time.{Date, DateTime, Weekday}

fn report(lines: List[Str]) -> Result[Void, time.DateError] ! Time.Read {
    let now = DateTime.from(time.read())          // From[Instant], as 03_types.md says
    let today = now.date()

    let mut by_day: Map[Date, Int] = Map.new()
    for line in lines {
        let ts = DateTime.parse(line.slice(0, 20))?   // "2026-02-14T12:00:00Z"
        by_day.update(ts.date(), 0, fn(n) { n + 1 })
    }

    let due = Date.new(2026, 12, 25)?
    print("{today.days_until(due)} days to go, lands on {due.weekday()}")  // "... lands on Friday"
    print("next month: {today.add_months(1)}")                            // "2026-11-17"
    print("{now.year()}/{now.month()} {now.hour()}:{now.minute()}")
    Ok(())
}
```

###### Surface

**`Date`** (opaque, an Int day count since the epoch):
- `Date.new(y, m, d) -> Result[Date, DateError]` and `Date.parse(s) -> Result[Date, DateError]`. `parse` takes ISO `YYYY-MM-DD` only.
- `year()`, `month()` (1-12), `day()`, `weekday() -> Weekday`, `day_of_year()`.
- `add_days(n)`, `add_months(n)` and `add_years(n)` clamp to the last valid day, the Temporal/Java "constrain" default: Jan 31 + 1 month = Feb 28.
- `days_until(other) -> Int`. This is the same shape as `Instant.since`, without the arg-order trap: `a.days_until(b)` reads left to right.
- `and_time(h, m, s) -> Result[DateTime, DateError]`.

**`DateTime`** (opaque, wraps an `Instant`):
- `DateTime.from(instant)`, `DateTime.parse(s)`, `to_instant()`, `date()`.
- `year()` through `second()`, plus `nanosecond()` and `weekday()`.
- `add(Duration)` and `since(other) -> Duration`, the same names as `Instant`. Date-unit steps go through `.date()`.

**`Weekday`**: `type Weekday { Monday, ..., Sunday }`, with `to_iso() -> Int` (1-7) and a Display that writes the full English name.

**Traits:** both types derive Eq, Ord, Hash, Display, Debug and Clone. Hash is not optional: "group log lines by date" is the benchmark's main task, and it needs `Map[Date, _]`.

**Display:**
- `Date` writes `2026-02-14`.
- `DateTime` writes the same text as `Instant`'s Display (RFC 9557 with `Z`). One rule for every reader.

**Parse:**
- `DateTime.parse` accepts RFC 3339 with `Z` or a numeric offset, and normalizes the offset to UTC.
- It rejects text that has no offset, with an error message that names the cause ("no UTC offset; append Z").
- Accepting an offset is the 90% case: logs and APIs emit `+05:30`. Normalizing at the boundary stops a hidden zone getting into the value.

**Errors:** `DateError { InvalidDate(Str), BadFormat(Str) }` with Display, the pattern of a domain error such as `FsError`. `ConversionError` is too generic to say "Feb 30 does not exist."

###### Explicitly out of v1

- **Local time and IANA zones.** Reading `/etc/localtime` or `TZ` is ambient I/O, so it would need FS.Read/Env in every caller's effect row. That is a big learning-curve hit for something most backend code should not do. Reserve the name `ZonedDateTime` for a later decision.
- **strftime-style format strings.** Accessors plus `{}` interpolation cover the benchmark tasks. A pattern mini-language (`%Y` vs `yyyy` vs `YYYY`, the classic Java week-year bug) is its own SO generator and deserves its own panel.
- **Month and day names other than `Weekday`'s English Display.** That is i18n.
- **Leap seconds.** We stay with POSIX time, the same as `Instant`.

###### Tradeoffs

- **Plus: easy to learn in five minutes.** A JS/Python dev reads `d.add_days(7)`, `d.weekday()` and `DateTime.parse(s)?` with no docs. The names match Temporal, Kotlin's kotlinx-datetime and Python's `date`/`datetime` as closely as our conventions allow.
- **Plus: zero zone confusion by construction.** Every value is UTC or zone-free, so the "works on my laptop, off by one day in CI" class does not exist.
- **Plus: method names follow `Instant`.** `add`/`since` match, so one way to do it holds.
- **Minus: two types instead of one.** I take this cost on purpose. A one-type design forces "truncate to midnight" tricks for date keys, and that is exactly where Python users get burned (`datetime` vs `date` equality).
- **Minus: no local time.** "Print the user's local hour" is not possible. For server and CLI scripting, the benchmark's domain, that is the right default. Go's `time.Local` and JS's local-default `Date` are the cautionary tales.
- **Minus: `add_months` clamping has to be documented.** We still ship it, because billing-cycle and "next month" tasks are common and hand-rolling them is worse.

##### W2 (rejected alternative, for the record): `DateTime` only

Here `.date()` would return a `DateTime` at midnight. This makes the type smaller, but `Map[DateTime, _]` keys break the moment one value has a non-zero time, and `days_until` needs a rule for partial days. Python users learned this the hard way. I recommend against it.

##### Cross-language note

- **Temporal (JS):** PlainDate / Instant / ZonedDateTime. W1 is PlainDate plus a UTC-only date-time, with Zoned deferred.
- **Kotlin (kotlinx-datetime):** LocalDate / Instant / TimeZone. Same layering.
- **Go:** one `time.Time` that carries a location. The Location field causes subtle `==` bugs, which is why Go needs `t.Equal`. We avoid that.
- **Python:** `date` / `datetime`, with naive vs aware as the footgun we remove.

Vote preference: W1.

======================================================================
##### SYSTEMS (sys)
======================================================================
##### Proposal S1 (recommended): two integer-backed opaque types, UTC only, decompose on demand

Representation decides cost:
- `Date` = opaque `{ days: Int }` (days since 1970-01-01). One word. Eq/Ord/Hash are integer compare/hash. `add_days` is one add. `days_until` is one subtract.
- `DateTime` = opaque `{ date: Date, nanos_of_day: Int }`. Two words, by value, no heap, no pointer. Ord compares two ints in order. `hour()` is one divide. `minute()` and `second()` are a divide and a mod.
- Calendar fields (`year/month/day`) run Hinnant's civil_from_days on demand: about 15 integer ops, no tables, no loops, no allocation. time.bl already has this code inside Instant's Display, so it moves into one private fn that both call.
- `DateTime.from(instant)` is one floor-div plus one floor-mod by 86_400e9 (floor, not truncate, so pre-epoch values land on the right day). `to_instant()` is a multiply plus an add.

```blink
import std.time.{Date, DateTime, Weekday}

fn report(log_ts: Str) -> Result[Str, ConversionError] ! Time.Read {
    let now = DateTime.from(time.read())
    let today = now.date()
    let xmas = Date.from_ymd(2026, 12, 25)?
    let left = today.days_until(xmas)
    let dt = DateTime.parse(log_ts)?
    let day = dt.date()
    let wd = day.weekday()
    Ok("{day} ({wd}) {dt.hour()}:{dt.minute()} | {left} days to {xmas} | next week {today.add_days(7)}")
}

// Surface (all methods, no operators):
// Date:     from(Instant), from_ymd(y, m, d) -> Result[Date, ConversionError],
//           parse(Str) -> Result[Date, ConversionError]   // "YYYY-MM-DD" only
//           year, month, day, weekday -> Weekday, day_of_year,
//           add_days(Int), days_until(Date) -> Int, at(hour, min, sec) -> Result[DateTime, ConversionError]
// DateTime: from(Instant), parse(Str) -> Result[DateTime, ConversionError]  // RFC 3339
//           date -> Date, hour, minute, second, nanosecond, to_instant -> Instant
// Weekday:  type Weekday { Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday }
//           .to_int() gives ISO 1..7; Display "Monday"
// Display:  Date "2026-10-17"; DateTime as Instant's Display (RFC 9557 Z, same fraction rule)
```

What DateTime does NOT have: `add`, `since`, `add_days`. Do exact-time arithmetic on Instant (`dt.to_instant().add(d)`) and calendar arithmetic on Date. That keeps one way to do each thing, and stops DateTime from turning into a second Instant with a second set of arithmetic methods. Month/year arithmetic (`add_months`, with its Jan-31 clamp question) stays out of v1.

###### Timezones: out of v1, by design
- An IANA zone needs tzdata: about 450 KB compiled, or reads of /usr/share/zoneinfo plus TZ/localtime. That is FS.Read + Env in the effect row of every "local time" call. It is not hermetic, it fails on static musl, wasm, and minimal containers, and the rules change several times a year. Go embeds an optional 450 KB tzdata package; Rust kept zones out of std. We follow Rust.
- `DateTime.parse` accepts `Z` and `+hh:mm`/`-hh:mm` offsets, and normalizes to UTC at parse time. DateTime has no offset field, so it is two words, never three plus a pointer (Go's time.Time is 24 bytes because it carries `*Location`).
- Fixed-offset or IANA types go in a later `std.time.tz` (new type, effectful constructor). Adding them later breaks nothing.

###### Parse/format
- Hand-written fixed-width parsers: no allocation, no regex, strict (reject `2026-2-5`, reject leap second `:60`). Errors use the existing `ConversionError`, which matches parse_int and from_code_point.
- No strftime-style format strings in v1. They are a mini-language interpreted at run time, they cost a parse on every call, and they let agents pick between two ways. Interpolation of the accessors covers the benchmark tasks.

###### Tradeoffs
- (+) Every type is POD that is 1 or 2 words. Mono emits plain int64 math in C, and gcc -O2 folds the divisions by constants into multiplies.
- (+) Group-by-date is a hash of one Int (`Map[Date, List[Str]]`), with no string keys.
- (-) Field accessors recompute civil_from_days on each call. A loop that reads year+month+day pays about 45 ops. That is cheap, but if it shows up, add `Date.ymd() -> (Int, Int, Int)` later. Do not cache the fields in the struct, because that triples its size and makes Eq/Hash compare more.
- (-) Range: Instant is i64 nanos, so years 1677..2262. Date's range is far wider. `DateTime.to_instant()` can overflow, so `from_ymd` must bound the year (I propose 1678..2261 for DateTime and -9999..9999 for Date), or `to_instant` must return a Result. The panel must choose one. I prefer to bound at construction so to_instant stays total.
- Leap seconds are ignored (POSIX days are 86 400 s), as in every mainstream library.

Cross-language: Zig std.time.epoch (EpochSeconds -> EpochDay -> YearAndDay, decomposed on demand) is the nearest model. Java LocalDate/LocalDateTime splits Date from DateTime the same way. Rust chrono NaiveDate packs year+ordinal into an i32, which is faster to read fields from but slower to add to; we prefer cheap arithmetic. C gmtime_r fills a 9-int struct tm on every call.

##### Proposal S2 (minimal fallback): Date only, no DateTime type
Ship `Date` as in S1, and give `Instant` `date() -> Date` and `nanos_of_day() -> Int`. Remove the `DateTime` sentence from 03_types.md. This is the smallest surface and has zero duplication. Its cost: `hour()` lives on Instant, which goes against 03_types' rule that calendar decomposition belongs in its own type, and RFC 3339 offset parsing has no home except `Instant.parse`. I vote S1. S2 is acceptable if the panel weights "one way" above that 03_types rule.

Summary of my votes: Date beside DateTime, yes. Timezones in v1, no. Offsets accepted on parse and normalized to UTC. No format strings. Calendar arithmetic only on Date, exact arithmetic only on Instant.

======================================================================
##### PLT (plt)
======================================================================
PLT Phase A proposal (pmpmyc, std.time calendar surface). Two proposals: P1 is the one I recommend, P2 is the smaller fallback.

##### P1 (recommended): three sorts, one home for each operation, every conversion total

**Types (all `pub opaque type` in std.time, all pure, no effects):**
- `Instant`: a point on the timeline (exists today).
- `Date`: a civil calendar day with no time of day and no zone. Body: Int days since 1970-01-01.
- `DateTime`: a civil date plus time of day with NO zone (Temporal's PlainDateTime, java.time's LocalDateTime). Body: (days: Int, nanos_of_day: Int).
- `Weekday`: a sum type `{ Monday, ..., Sunday }`, kept apart from Int, which matches the enum-not-Int ruling.

**The typing claim that matters:** a zone-free civil label and a timeline point are different sorts. Python's one `datetime` class for both is the classic unsoundness: comparing a naive value with an aware one fails only at run time. So no `Eq`/`Ord` holds across sorts, and each conversion names its interpretation. In v1 the only interpretation is UTC, so both directions are total and pure:

```blink
import std.time.{Instant, Date, DateTime, Weekday}

impl From[Instant] for Date        // UTC projection, total
impl From[Instant] for DateTime    // UTC projection, total

fn Date.from_ymd(y: Int, m: Int, d: Int) -> Result[Date, ConversionError]
fn Date.parse(s: Str) -> Result[Date, ConversionError]          // "2026-02-14" only
fn DateTime.parse(s: Str) -> Result[DateTime, ConversionError]  // "2026-02-14T12:00:00[.fff]"; rejects Z/offset
fn Instant.parse(s: Str) -> Result[Instant, ConversionError]    // RFC 3339; needs Z or ±hh:mm, normalizes to UTC

pub trait Calendar {            // one accessor set, shared by Date and DateTime
    fn year(self) -> Int
    fn month(self) -> Int       // 1..12
    fn day(self) -> Int         // 1..31
    fn weekday(self) -> Weekday
    fn ordinal(self) -> Int     // 1..366
}
impl Calendar for Date
impl Calendar for DateTime

// Date ops: Date is an affine space over Int days
//   d.add_days(n: Int) -> Date
//   d.days_since(other: Date) -> Int
// DateTime ops: hour(), minute(), second(), nanosecond(), date() -> Date,
//   to_instant_utc() -> Instant (total, see the range rule)

fn busiest_day(lines: List[Str]) -> Result[Date, ConversionError] {
    let mut counts: Map[Date, Int] = Map.new()
    let mut best = Date.from_ymd(1970, 1, 1)?
    let mut best_n = 0
    for line in lines {
        let day = Date.from(Instant.parse(line.split(" ").get(0).unwrap_or(""))?)
        let n = counts.get(day).unwrap_or(0) + 1
        counts.insert(day, n)
        if n > best_n { best = day; best_n = n }
    }
    Ok(best)
}
// "today" is just a composition, so the effect stays visible: Date.from(time.read())
```

**Design rules and why they hold:**
1. **One home for each operation.** Exact elapsed time lives on Instant (`add(Duration)`, `since`). Calendar-day arithmetic lives on Date (`add_days`, `days_since`). DateTime has NO arithmetic; it exists to decompose, parse and print. The "one way to do it" rule then holds by construction: `dt.add(Duration)` and `instant.add(Duration)` never both exist.
2. **No month or year arithmetic in v1.** `add_months` is not a group action of Z: Jan 31 + 1 month needs clamping, so (d + 1m) + 1m differs from d + 2m and the result has no inverse. Day addition is a true affine action (associative, invertible), and `d.add_days(n).days_since(d) == n` holds as a law. If months come later, they come under a distinct name that states the clamping (`add_months_clamped`), never `add`.
3. **Partial at the edge, total inside.** Instant's domain is fixed by Int64 nanos (about 1677-09-21 to 2262-04-11). Date and DateTime constructors and parsers reject values outside that domain (Err(ConversionError) "out of range"). Every conversion between the three sorts is then total, with no Result on the hot path. This also fixes the open overflow hole that `Instant.from_epoch_secs` has today.
4. **Round-trip laws in the spec, not prose.** For every value x: `T.parse("{x}") == Ok(x)`. Display: Date `2026-02-14`; DateTime `2026-02-14T12:00:00`, with the fraction rule Instant already uses (drop a zero fraction, no trailing zeros); Weekday `Monday`. Because DateTime's text has no `Z`, its text form encodes the absence of a zone, and Instant's text (which always has `Z`) cannot round-trip into DateTime by accident. Debug may equal Display.
5. **Eq, Ord, Hash, Display, Clone, Debug** on Date, DateTime and Weekday (Ord on Weekday is ISO order, Monday first). `Weekday.to_iso_number() -> Int` (1..7) and its inverse `Weekday.from_iso_number(n) -> Result[Weekday, ConversionError]` are the only Int bridges.
6. **Proleptic Gregorian, no leap seconds.** This is the POSIX/RFC 3339 model Instant already uses (`second()` is 0..59). The parser rejects `:60` instead of smearing it.

**Timezones: out of v1, with a shape reserved so we do not paint ourselves into a corner.** A tz database is mutable external data. A pure `instant.in_zone("America/Denver")` would make the function's result depend on a file it never declared, which breaks referential transparency and capability tracking. The future shape: `Zone` values come only from an effectful load (`time.zone(name) ! FS.Read` or `! Env` for the local zone), and a separate `ZonedDateTime` sort carries the zone. Because Date and DateTime are zone-free by definition, adding zones later adds a type and changes none of the v1 meanings. The one thing v1 must NOT do is make DateTime "UTC-aware". Then DateTime is isomorphic to Instant (a duplicate API), and adding zones later would change its meaning.

**Spec edit:** replace the 03_types.md paragraph. `DateTime.from(instant)` stays valid and means the UTC projection.

**Cross-language:** this is the TC39 Temporal / java.time / Rust `jiff` and `chrono` lineage (Instant, PlainDate, PlainDateTime, then Zoned later). OCaml's Ptime and Haskell's `time` keep the same split (UTCTime vs Day vs LocalTime). Go's single `time.Time` with a Location is the counterexample: it is compact, but the monotonic-reading and zone-identity bugs in it come from fusing the sorts.

##### P2 (smaller fallback): Date only plus accessors on DateTime as a UTC view

If the panel wants fewer types: ship only `Date` (all of P1's Date surface), and make DateTime a non-opaque read-only view, `DateTime.from(instant)` giving fields year..nanosecond with no constructors and no parse. The cost: DateTime then carries an implicit UTC zone and cannot be the zone-free sort later. That is a later breaking change, which is why I rank P2 second.

##### Votes I would cast
- Date beside DateTime: YES.
- Timezones in v1: NO, but reserve the effectful `Zone` + `ZonedDateTime` shape now.
- strftime-style format strings: NO in v1. They are an untyped mini-language; ISO Display + parse covers the benchmark tasks.
- Month and year arithmetic: NO in v1 (not a group action).

======================================================================
##### DEVOPS/TOOLING (devops)
======================================================================
##### DevOps/Tooling Proposal: calendar dates for `std.time`

**Where I stand:** this is a library-only change. It adds no syntax, so the parser, `blink fmt` and the LSP grammar need no work. The real cost is in the diagnostics and in how many types show up in autocomplete. Each extra type that holds the same value as another means more "expected X, found Y" errors and more `.to_x()` calls that people write wrong. So the test is the fewest types and the clearest failure text.

###### Proposal 1 (recommended): add `Date`, put calendar accessors on `Instant`, keep `DateTime` for zones

When the clock is UTC-only, a "UTC DateTime" is the same value as an `Instant`, just stored differently. If we ship both, autocomplete shows two overlapping method lists, and agents will pick the wrong type and then fix it by hand. That breaks "one way to do it". So v1 ships one new type, `Date`, and adds calendar accessors to `Instant`. The name `DateTime` stays reserved for the type that carries a time zone, which is what 03_types.md already says it holds: "year, month, day, timezone".

```blink
import std.time

type Weekday { Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday }

// Instant gains (all pure, UTC):
//   Instant.parse(s: Str) -> Result[Instant, ConversionError]   // RFC 3339 / RFC 9557
//   .date() -> Date
//   .hour() -> Int   .minute() -> Int   .second() -> Int   .nanosecond() -> Int
//
// pub opaque type Date      // days since 1970-01-01; Eq, Ord, Hash, Display, Debug, Clone
//   Date.from_ymd(y: Int, m: Int, d: Int) -> Result[Date, ConversionError]
//   Date.parse(s: Str) -> Result[Date, ConversionError]          // "YYYY-MM-DD" only
//   .year() -> Int  .month() -> Int  .day() -> Int  .weekday() -> Weekday
//   .add_days(n: Int) -> Date
//   .days_since(earlier: Date) -> Int
//   .to_instant() -> Instant                                       // 00:00:00Z that day

fn count_by_day(lines: List[Str]) -> Result[Map[Date, Int], ConversionError] {
    let mut counts: Map[Date, Int] = Map.new()
    for line in lines {
        let ts = Instant.parse(line.split(" ").get(0).unwrap())?
        let d = ts.date()
        counts.insert(d, counts.get(d).unwrap_or(0) + 1)
    }
    Ok(counts)
}

fn main() ! Time.Read {
    let today = time.read().date()
    let launch = Date.from_ymd(2026, 2, 14).unwrap()
    println("{today} is a {today.weekday()}, {today.days_since(launch)} days after launch")
    // 2026-10-17 is a Saturday, 245 days after launch
}
```

**Why each choice:**

- **`Weekday` is an enum, not an Int.** Whether Sunday is 0 or Monday is 1 is a classic off-by-one, for both people and LLMs. An enum turns that into an exhaustive `match`. Its Display is the full English name (`Saturday`), and `.to_int()` gives ISO numbering (Monday = 1). Month stays an `Int` from 1 to 12, because enums are not nominal Ints (`dhggkg`), and `d.month() == 2` should just compile.
- **`Debug` writes the same text as `Display`** (`2026-10-17`), not `Date { days: 20743 }`. That way an `assert_eq` failure in `blink test` shows two dates you can read. I treat this as a requirement, not a nicety.
- **`Hash` is required**, because grouping by date is the benchmark task.
- **Parse errors use the existing `ConversionError`** (constraint 7). The spec must name each cause class and give the byte offset, the way 03_types.md §3c.2 does for `parse_int`:
  - `invalid date: expected '-' at byte 4`
  - `invalid date: month 13 out of range 1..12`
  - `invalid date: day 30 out of range for 2026-02`
  - `invalid timestamp: missing UTC offset`
- **`Instant.parse` accepts `Z` and `±HH:MM` and converts the result to UTC.** That needs no tzdata, so it has no effect. Log lines from other machines carry offsets, and rejecting them would force workaround code. The cost is that Display always writes `Z`, so a parse followed by Display does not give back the same text when the input had an offset. The spec must say so.
- **No `today()` helper.** `time.read().date()` is the one way to get the date, and the `Time.Read` effect is visible at the call site.
- **No strftime in v1.** Format strings are text with no type checking, so a `%Q` typo is a runtime failure that nothing reports. String interpolation of the accessors already covers the benchmark. If we add custom formats later, the format should be a literal that the compiler checks.
- **No `add_months`.** What does 31 Jan plus one month give? Each language answers that differently (Java clamps, JS rolls over). That needs its own ruling, and v1 doesn't need it.

**Diagnostic surface:**

- Mixing the two types gives `E: expected Date, found Instant`. The fix is `.date()`, and the LSP can offer it as a quick-fix, because exactly one conversion exists in each direction.
- A later lint could validate a literal passed to `Date.parse("2026-02-30")` at compile time. That is out of scope for v1.

**How other languages do it:**

- Go puts calendar accessors on `time.Time` and has no separate date type. Programmers miss a date type and fake one with `Truncate(24h)`.
- Rust's chrono and Java's `java.time` give `NaiveDate` / `LocalDate` as a separate type, which is why I want one.
- `java.time` keeps `Instant` and `ZonedDateTime` apart. I copy that split and leave out `LocalDateTime` for now.
- Temporal (TypeScript) does the same with `Temporal.Instant`, `PlainDate` and `ZonedDateTime`.

**Spec change:** rewrite 03_types.md line 952 so that `DateTime` is the type with a time zone, deferred until time zones are in scope, and v1 civil dates are `Date` plus the `Instant` accessors.

###### Proposal 2 (fallback): `Date` plus a UTC-only `DateTime`

Use this if the panel wants to keep the `DateTime.from(instant)` text as written.

```blink
let dt = DateTime.from(time.read())       // From[Instant]
println("{dt.year()}-{dt.month()} {dt.hour()}h, {dt.date().weekday()}")
let back: Instant = dt.to_instant()
```

`DateTime` would wrap an `Instant` and add the hour, minute and second accessors, with `.date()`, `.add(Duration)` and `.since(DateTime) -> Duration`.

The cost is a second type that holds the same value as `Instant`. Every function signature then has to choose `Instant` or `DateTime`, and callers convert at each boundary. There is also a migration trap: when time zones arrive, `DateTime` either changes meaning (a breaking change) or the zoned type needs a third name such as `ZonedDateTime`. I rank this below Proposal 1.

###### Time zones: out of scope for v1 (both proposals)

IANA zones need tzdata, which means one of two options:

- **Read `/usr/share/zoneinfo`.** That needs `FS.Read`, plus `Env` for `TZ`, so every function that touches local time carries those effects. It also behaves differently on each host, which is bad for `mock_clock` tests and for reproducible CI.
- **Embed the tz database.** That adds about 400 KB to every binary that uses it, and the data needs updating several times a year.

Both choices need their own panel. v1 stays UTC-only, and the spec says so in one sentence. Fixed offsets are accepted only on parse, as given above. The type that carries a zone gets the reserved name `DateTime` later, so adding it then breaks no v1 code.

======================================================================
##### AI/ML (aiml)
======================================================================
##### AI/ML panelist: Phase A proposal for `std.time` calendar support (pmpmyc)

###### Proposal 1 (recommended): a `Date` type plus UTC calendar methods on `Instant`. No `DateTime` in v1.

**Types.** Add two types to `std.time`:
- `pub opaque type Date`: a civil date with no time of day. It implements Eq, Ord, Hash, Display, Clone and Debug.
- `type Weekday { Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday }`.

**New methods on `Instant`.** All of them read the instant in UTC.

| Method | Signature |
|---|---|
| `date` | `fn(self) -> Date` |
| `hour` / `minute` / `second` | `fn(self) -> Int` |
| `Instant.parse` | `fn(s: Str) -> Result[Instant, ConversionError]`. It takes RFC 3339 with `Z` or with a numeric offset such as `+02:00`, and changes the result to UTC. |

**`Date` surface:**

| Method | Signature |
|---|---|
| `Date.new` | `fn(year: Int, month: Int, day: Int) -> Result[Date, ConversionError]` |
| `Date.parse` | `fn(s: Str) -> Result[Date, ConversionError]`. It takes `YYYY-MM-DD` only. |
| `year` / `month` / `day` | `fn(self) -> Int`. `month` is 1–12. |
| `weekday` | `fn(self) -> Weekday` |
| `day_of_year` | `fn(self) -> Int` |
| `add_days` | `fn(self, n: Int) -> Date` |
| `days_since` | `fn(self, other: Date) -> Int` |
| `to_instant` | `fn(self) -> Instant`, at UTC midnight |

**Display.**
- `Date` writes `2026-10-17`.
- `Weekday` writes the English name, such as `Saturday`. `.to_int()` gives the ISO number: Monday = 1, Sunday = 7.

**The three benchmark tasks:**

```blink
import std.time.{Instant, Date, Weekday}

fn count_by_day(lines: List[Str]) -> Result[Map[Date, Int], ConversionError] {
    let counts = Map.new[Date, Int]()
    for line in lines {
        let day = Instant.parse(line.split(" ")[0])?.date()
        counts.insert(day, counts.get(day).unwrap_or(0) + 1)
    }
    Ok(counts)
}

fn main() {
    let a = Date.parse("2026-01-01").unwrap()
    let b = Date.new(2026, 10, 17).unwrap()
    println("{b.days_since(a)} days, {b.weekday()}")   // 289 days, Saturday
    println("{b.add_days(30)}")                         // 2026-11-16
}
```

**Why this shape (my domain):**

1. **No choice between two types.** A UTC-only `DateTime` would be the same thing as `Instant`, just stored differently. Every time-related task would then start with "Instant or DateTime?", and models get that choice wrong. Python shows the cost: `datetime` has naive and aware forms, plus `date` and `time`. LLMs often produce naive datetimes, compare a naive with an aware value, or call `utcnow()`. With one point-in-time type (`Instant`) and one calendar-day type (`Date`), there is nothing to choose.

2. **`Date` is the type these tasks need.** "Group by day" needs a key that is Hash + Eq. Without `Date`, models fall back to string slicing such as `ts.to_rfc3339().slice(0, 10)`. That works by accident and spends tokens on a fragile workaround. Also, `days_since` on two `Instant`s gives the wrong answer across a midnight boundary. `Date` makes the correct result the obvious one.

3. **Names follow existing spec patterns, so a model can learn them from the spec alone:**
   - Type-scoped `parse` and `new`, like `UUID.parse`.
   - Errors are `Result[_, ConversionError]`, like `Char.from_code_point`.
   - `days_since` follows `Instant.since`, and the unit is in the name so the `Int` cannot be read as anything else.
   - `add_days` follows the named-method rule, because operators are sealed.

   Each type has one constructor and one parser.

4. **`month()` returns `Int`, not an enum.** Enums are nominally distinct from Int in Blink, so a `Month` enum would force `.to_int()` on every comparison and print. That adds tokens and gives models one more thing to forget. `Weekday` is different: most code prints it, so the enum's English Display does the work for free.

5. **No strftime in v1.** Format-string languages are a big source of LLM errors: `%M` versus `mm`, minute versus month, Go's `2006-01-02` layout. Interpolation with the new `Str` pad helpers covers custom formats with one obvious method.

6. **No timezones in v1.** A timezone needs the tz database (FS.Read) or the `TZ` environment variable (Env). Either one adds an effect to every caller and opens the DST questions (gaps and repeated hours) that need their own panel. Offset parsing in `Instant.parse` needs neither, and it covers most log formats.

**Spec change.** In 03_types.md, replace the `DateTime.from(instant)` sentence with `instant.date()` and the surface above. Keep the name `DateTime` (or `ZonedDateTime`) free for a later panel on time zones.

**Diagnostic, needed for learnability.** Training data pushes models to write `DateTime.from(x)` and `DateTime.now()`. Those calls should fail with a fix-it hint: "std.time has no DateTime; use `instant.date()` / `.hour()`". This prior from training will cost more failed tasks than any part of the surface, and a hint the model can act on fixes it in one retry.

**Cross-language.** This is the same split as java.time (`Instant` + `LocalDate`), Temporal (`Instant` + `PlainDate`) and Rust jiff/chrono (`Timestamp` + `civil::Date`). All of them settled on keeping "point in time" and "calendar day" as separate types. Go uses one `time.Time` that carries a location, and that is the reason Go date bugs are subtle.

###### Proposal 2 (fallback): the spec's `DateTime`, UTC-only, plus `Date`

If the panel wants to keep the name the spec gives:
- `DateTime.from(instant)` and `DateTime.parse(s)`.
- Accessors: `.year()` … `.second()`, `.date() -> Date`, `.to_instant()`.
- `Date` as in Proposal 1.

```blink
let dt = DateTime.from(time.read())
println("{dt.date()} {dt.hour()}h")
```

**Cost:** two point-in-time types and lossless conversions in both directions. That is a second way to do the same thing, and the open audit tickets against duplicate APIs already target that pattern. The one gain is that it matches the training prior for `DateTime`. Even then, models will still expect Python-style `dt.year` field access, not `dt.year()` method calls.

###### What both proposals leave out of v1

- Month and year arithmetic: should Jan 31 + 1 month clamp to the end of February or overflow? That needs its own vote.
- Time zones and DST.
- strftime-style formatting.
- Leap seconds. UTC days are always 86400 s, the same as Unix time.
- A `Time`-of-day type, because `hour()`, `minute()` and `second()` on `Instant` cover the benchmark tasks.

**Vote preference:** Proposal 1, with the fix-it diagnostic as part of the decision rather than an optional extra.


#### Phase B — Debate (round 1): lead broadcast

Phase B, round 1 — pmpmyc (std.time calendar API). Open debate.

All six Phase A proposals, verbatim, are in:
(quoted in full in the section above)
Read the whole file before you reply.

##### Mechanical dedupe of the Phase A proposals (grouping only; labels cite who proposed each)

###### Type-set options
- T1 — Date + Weekday; calendar accessors and parse on Instant; no DateTime type in v1.
  Proposed by: min M1, aiml P1, devops P1. Fallback of: sys S2.
  Variation inside T1: Instant.hour()/minute()/second() — aiml P1 and devops P1 include them (devops adds nanosecond()); min M1 leaves them out (use `now.since(midnight)`); sys S2 gives `nanos_of_day()` instead.
- T2 — Date + a UTC DateTime type (a decomposed view of an Instant).
  Proposed by: web W1 (DateTime has add(Duration) and since), sys S1 (DateTime has NO arithmetic; body {date, nanos_of_day}). Fallback of: devops P2, aiml P2.
- T3 — Date + a zone-free civil DateTime (no Z on Display; DateTime.parse rejects Z/offset), with Instant.parse for offset text; shared `Calendar` trait.
  Proposed by: plt P1.
- T4 — Date + DateTime as a read-only, non-opaque, public-field UTC view.
  Fallback of: min M2, plt P2.

###### Sub-questions where the proposals differ
1. Date constructor name: `Date.new(y, m, d)` (min, web, aiml) vs `Date.from_ymd(y, m, d)` (sys, devops, plt).
2. Day difference: `days_since(other)` (min, aiml, devops, plt) vs `days_until(other)` (web, sys).
3. Error type: `ConversionError` (min, sys, plt, devops, aiml) vs new `DateError { InvalidDate(Str), BadFormat(Str) }` (web).
4. Month/year arithmetic: `add_months`/`add_years` with clamp in v1 (web) vs out of v1 (min, sys, plt, devops, aiml).
5. Range at the Instant bounds (~1677-09-21..2262-04-11): reject at construction/parse (sys preferred, plt) vs `to_instant` returns Result (sys listed as the other choice).
6. Weekday Int bridge: `.to_int()` (sys, devops, aiml) vs `.to_iso()` (web) vs `to_iso_number()` + `from_iso_number(n) -> Result` (plt). min: none named.
7. Weekday variant names: `Mon..Sun` (min) vs `Monday..Sunday` (web, sys, plt, devops, aiml).
8. Debug text: equal to Display — required (devops), allowed (plt); others did not state.
9. Instant → Date: `Date.from(instant)` via From (min, sys, plt; web for DateTime) vs `instant.date()` (aiml, devops, sys S2).
10. `day_of_year` / `ordinal`: included (web, sys, aiml, plt) vs left out (min, devops).
11. `Date.to_instant()` (midnight UTC): included (min, aiml, devops); sys/web/plt put to_instant on DateTime.
12. Constructor from Date to a date-time: `and_time(h,m,s)` (web), `at(h,m,s)` (sys); others none.
13. Diagnostics: fix-it for `DateTime.from(x)` / `DateTime.now()` named as part of the decision (aiml); `expected Date, found Instant` + `.date()` quick-fix, and ConversionError messages naming cause class + byte offset (devops).
14. Parse round-trip: law `T.parse("{x}") == Ok(x)` stated in spec (plt); spec must say offset input does not round-trip text (devops).

###### Points no proposal disagrees on
No timezones in v1; no strftime/format strings in v1; numeric offsets on parse are normalized to UTC; Date Display is ISO `YYYY-MM-DD`; Date has Hash (Map key); no `today()` helper; no leap seconds; Weekday is an enum; month() returns Int 1..12.

##### Codebase facts (facts only)
- sections/03c_protocols.md §3c.4 "No Inherent Methods": Blink does not support `impl Foo { fn bar(self) ... }`. All methods must belong to a trait. `fn T.name` type-scoped functions (§2.12.3) take no receiver.
- Built-in Instant and Duration get their methods from compiler-known sealed traits, the same way StrOps/ListOps serve Str/List.
- sections/03_types.md today says: "Calendar-aware datetime (year, month, day, timezone) lives in `std.time.DateTime`, constructed from an `Instant` via `DateTime.from(instant)`."
- lib/std/time.bl: `Instant_from_epoch_secs(s)` computes `s * 1000000000` with no range check.

##### What to send back (SendMessage to team-lead)
- Your position on the type-set options and on each numbered sub-question where you have one. You may change your Phase A position; say so if you do.
- Responses to other panelists' arguments: name the panelist and quote the line you answer.
- End with exactly one of: `STABLE, READY TO VOTE` or `NOT STABLE: <what is still open>`.


#### Phase B — Debate (round 1): replies

======================================================================
##### MIN — Phase B round 1 (verbatim)
======================================================================
MINIMALISM, Phase B round 1 (pmpmyc). In short: T1, with two changes from my Phase A (Instant gets hour/minute/second; Instant to Date goes through `.date()`, not `From`).

##### Type set
T1 is my first choice. T4 (my M2) is my fallback. T3 is acceptable over T2. T2 gets a no.

The new codebase fact supports T1. §3c.4 says every method must belong to a trait, and Instant's methods already come from a sealed trait. So T1 needs one sealed trait for Date and a few more methods on Instant's sealed trait. It needs no public trait. plt's public `Calendar` trait only makes sense if DateTime exists. Under T1 it would have one implementor, and that is a trait with no reason to exist.

##### Changes from my Phase A
- **I accept `Instant.hour()/minute()/second()`.** aiml and devops are right on cost. My `now.since(Date.from(now).to_instant()).to_seconds() / 3600` is 2 lines, and an agent will get the divide or the mod wrong. A P0 benchmark ticket makes that error rate the real cost. I add 3 methods and leave out `nanosecond()`, because no task in the ticket needs it. I prefer this to sys S2's `nanos_of_day()`, which only moves the division to the caller.
- **I switch to `instant.date()` and drop `From[Instant] for Date`.** Having both gives two ways to do one thing. `.date()` chains (`Instant.parse(s)?.date()`), and it gives devops's quick-fix one target. The 03_types.md sentence gets rewritten anyway.

##### Sub-questions
1. **`Date.from_ymd`.** I switch from `new`. In Blink, `new` is infallible (`Map.new()`). A fallible named constructor follows `Char.from_code_point`, and the name states the argument order, which stops m/d/y mistakes.
2. **`days_since`.** It follows `Instant.since`, where the receiver is the later value: `b.days_since(a)` is b − a.
   - To web: "`a.days_until(b)` reads left to right". That adds a second argument-order convention beside `since`. One convention is better than two.
3. **`ConversionError`.**
   - To web: "ConversionError is too generic to say Feb 30 does not exist". The message carries that, with devops's cause classes such as `day 30 out of range for 2026-02`. A new error type per domain is new surface that `parse_int` and `from_code_point` already showed we do not need.
4. **No `add_months` in v1.**
   - To web: "billing-cycle and next month tasks are common". None of them is in this ticket. plt shows it is not a group action (`(d+1m)+1m ≠ d+2m`), so it needs its own vote on naming and clamping.
5. **One range rule.** Date's range equals Instant's range (about 1677-09-21 to 2262-04-11). `from_ymd` and `parse` reject anything outside it, so `to_instant()` and `.date()` stay total.
   - To sys: "-9999..9999 for Date". That gives two range rules and makes `to_instant` partial. One domain for every type is simpler, and it also closes the overflow hole in `Instant_from_epoch_secs`.
6. **No named Int bridge on Weekday.** This catches an error in three proposals. §3.4 Tag Operations already gives every fieldless enum `to_int()` and `from_int() -> Option`, set by variant order. So `Weekday.Monday.to_int()` is the tag (0 for Monday), not ISO 1..7. sys, devops and aiml say ".to_int() gives ISO 1..7". That is wrong: it conflicts with the built-in, so there would be two meanings for one name. plt's `to_iso_number()` is a second bridge beside the built-in one. The spec should state the tag order once (Monday first, tags 0..6) and add nothing. The tasks print the weekday name; they do not number it.
7. **`Monday..Sunday`.** I concede this. The variant name then equals the Display text.
8. **Debug equals Display.** I agree with devops. A derived Debug of the opaque body (`Date { days: 20743 }`) is useless in an `assert_eq` failure.
9. **`.date()`.** See above.
10. **No `day_of_year` / `ordinal`.** No task in the ticket needs it. Add it later from friction tickets.
11. **Keep `Date.to_instant()` (midnight UTC).** It is the one conversion back to Instant, which keeps the quick-fix symmetric.
12. **No `at` / `and_time`.** Under T1 there is no DateTime for them to return.
13. **Diagnostics: yes to both.** I accept aiml's fix-it for `DateTime.from(x)` / `DateTime.now()` as part of the decision. It is cheap, and the training prior is the biggest cause of failed tasks. devops's cause-class messages: yes.
14. **Round-trip law: yes.** The spec should say `Date.parse("{d}") == Ok(d)` and `Instant.parse("{i}") == Ok(i)`. It must also say that text with an offset gives back the same Instant, not the same text.

##### Other responses
- **To plt:** "The one thing v1 must NOT do is make DateTime UTC-aware". I agree, and T1 gets that result with zero DateTime types, not one. The civil DateTime in T3 has one strong use case: log stamps with no offset, such as `2026-02-14 12:00:00`. In T1, `Date.parse(line.slice(0, 10))` handles grouping by day, but hour-of-day from a stamp with no offset is a gap. I accept that gap in v1 and want the spec to state it. `Instant.parse` must not treat text with no offset as UTC, because that is Python's naive-datetime trap. If friction shows up, a later panel adds T3's DateTime. Nothing in T1 blocks that.
- **To sys S2:** "hour() lives on Instant, which goes against 03_types' rule". That rule says calendar decomposition belongs "in stdlib, not built-in types". `Instant` is already a Tier-2 stdlib type in std.time, so T1 follows the rule.
- **To devops and web, on reserving `DateTime` / `ZonedDateTime`:** the spec should not reserve a name for a feature that does not exist. It should say "no zone support in v1" and stop there. The zone panel picks the name later.
- **To web W1:** "A one-type design forces truncate-to-midnight tricks". T1 is not a one-type design. It has `Date`, so no trick is needed. What web argues against is W2, which nobody proposed.

##### Final T1 surface (14 items)
- `Instant.parse`; `.date()`; `.hour()`, `.minute()`, `.second()`
- `Date.from_ymd`, `Date.parse`; `.year()`, `.month()`, `.day()`, `.weekday()`; `.add_days()`, `.days_since()`, `.to_instant()`
- `Weekday` (Monday..Sunday), using the existing tag operations
- Eq, Ord, Hash, Display, Clone, Debug on Date and Weekday

STABLE, READY TO VOTE

======================================================================
##### WEB — Phase B round 1 (verbatim)
======================================================================
WEB/SCRIPTING, Phase B round 1: I drop W1 and move to T1 (Date + Weekday, calendar accessors and parse on Instant, no DateTime in v1). I take the aiml/devops variant that includes hour()/minute()/second(). I also report one spec conflict, on Weekday.to_int() (see 6).

##### Type set: T1. I change my Phase A position.

plt convinced me: "The one thing v1 must NOT do is make DateTime 'UTC-aware'. Then DateTime is isomorphic to Instant." The same point holds for sys S1. Without arithmetic, S1's DateTime is a second spelling of Instant that holds less, and every signature has to choose between the two. aiml is right that "Instant or DateTime?" is the first question each task would raise, and agents would pick wrong. My DX argument for W1 was that Python's date/datetime split works. The part of that split that works is *date vs point-in-time*, and T1 keeps exactly that. So I rank T1 > T2(S1) > T4 > T3.

**Against T3 (plt P1).** A zone-free civil DateTime is Python's naive datetime and Java's LocalDateTime. min calls that "a familiar source of bugs", and I agree. With no zones in v1 it also has no real input: every log line or API value carries Z or an offset. Worse, under T3 `DateTime.parse("2026-02-14T12:00:00Z")` is an error. Users paste ISO text with Z more often than anything else, so this would be the first Stack Overflow question we generate.

**Against min M1's omission of hour().** min: "Hour of day: composes from what exists, no new API ... `now.since(Date.from(now).to_instant())...to_seconds() / 3600`". That is the hand-rolled calendar arithmetic the ticket says agents fail on. No JS or Python developer finds it in five minutes. `now.hour()` costs three names and closes the gap. Include hour(), minute() and second() on Instant. nanosecond() I lean no on (YAGNI), but I do not hold that firmly.

**On devops reserving the bare name `DateTime` for the zoned type.** Python developers read `datetime` as "the normal one, maybe naive". If a later `DateTime` is the zoned type, it will be misread. Leave the name to the tz panel. v1 spec defines no DateTime, and aiml's fix-it covers the training prior.

##### Sub-questions

1. **`Date.from_ymd(y, m, d)`. I change my position.** The name fixes the argument order, which removes the US m/d/y vs EU d/m/y guess. That guess is a real DX trap that `new(…)` hides. `new` returning a Result also reads oddly next to `Map.new()`.
2. **`days_since(other)`. I change my position.** It matches `Instant.since(earlier)`, and one direction across the module beats my reading-order argument.
3. **`ConversionError`. I concede.** My objection was the message ("Feb 30 does not exist"). devops' cause-plus-offset messages answer it. I require them as part of the decision: `day 30 out of range for 2026-02`, `missing UTC offset`, `expected '-' at byte 4`.
4. **add_months / add_years: out of v1. I concede.** plt's law argument holds. I ask that the spec say so in one sentence, so agents do not guess at a method that does not exist.
5. **Reject at construction and parse,** so `to_instant()` stays total. A Result on `to_instant()` would put `?` on every hot path. Fix `Instant.from_epoch_secs` the same way or file a ticket for it.
6. **Weekday Int bridge: NOT `.to_int()`. This is a correctness issue, not a matter of taste.** §3.4 *Tag Operations* (03_types.md ~1701) gives every fieldless enum a built-in `to_int()` (its tag, in declaration order), `from_int(n) -> Option`, and comparison with Int. The spec does not let you write your own. So `Weekday.to_int()` already exists and gives the tag, not ISO 1..7. sys, devops and aiml all write ".to_int() gives ISO 1..7", which contradicts the language as specced. I found no way to set explicit tag values; if one exists, that changes this point. If not, Monday.to_int() is the tag, almost certainly 0, which is the classic off-by-one. Two choices:
   - (a) A named bridge, `iso_number() -> Int` (1..7), with the spec warning that `to_int()` is the 0-based tag. I take plt's idea and a shorter name. I would not add `from_iso_number` in v1 (YAGNI).
   - (b) No ISO bridge at all.
   I vote (a), because an agent that needs ISO numbers will otherwise write `to_int() + 1`.
7. **Monday..Sunday,** in full. Kotlin DayOfWeek, Java and Python calendar all spell the names out.
8. **Debug = Display: required.** devops is right: `assert_eq` output must be readable.
9. **`instant.date()`, and no From impl.** If both exist, that is two ways. `.date()` wins for DX for three reasons: it chains (`Instant.parse(s)?.date()`), dot-completion on an Instant finds it, and it sits beside `.hour()` on the same type. `Date.from(instant)` is a name you have to already know.
10. **day_of_year: leave it out. I change my position.** It was in W1, and no benchmark task needs it.
11. **`Date.to_instant()` (00:00:00Z): include.** It is the only way back to the timeline, and it lets you build a timestamp: `d.to_instant().add(Duration.hours(9))`.
12. **No and_time / at in v1.** Item 11 covers it.
13. **Diagnostics: yes to both.** aiml's fix-it for `DateTime.from` / `DateTime.now` and devops' "expected Date, found Instant" + `.date()` quick-fix are part of the decision, not optional extras. They are what make T1 learnable against the training prior.
14. **Round-trip laws in the spec:** `Date.parse("{d}") == Ok(d)` and `Instant.parse("{i}") == Ok(i)`. Also the devops note that offset input does not round-trip its text.

**Spec edit:** rewrite 03_types.md:952 to name `std.time.Date` and `instant.date()`, and to say that v1 is UTC-only with no DateTime type and no month arithmetic.

STABLE, READY TO VOTE

======================================================================
##### DEVOPS — Phase B round 1 (verbatim)
======================================================================
DevOps Phase B round 1 (pmpmyc): I hold T1, and I found a spec fact that makes sub-question 6 (Weekday Int bridge) invalid as worded.

##### New fact: Weekday already has a to_int()
sections/03_types.md:1701-1709 ("Tag Operations") says every fieldless enum has a built-in `to_int()` that returns its variant tag, and `from_int(n) -> Option[Enum]`. sections/06_tooling.md:406 says "Variant order sets `to_int()`". So with `Monday..Sunday` in that order, `Weekday.Monday.to_int()` is 0, not 1.
- My Phase A text ("`.to_int()` gives ISO numbering, Monday = 1") was wrong. So were the matching lines from sys and aiml. I withdraw that line.
- A second bridge (`to_iso()` or `to_iso_number()`) would put two Int bridges on one enum, one starting at 0 and one at 1. Autocomplete would show both next to each other, which is the off-by-one trap the enum exists to remove.
- My position on sub-question 6: add no extra bridge. The spec fixes variant order as Monday first and says `to_int()` is 0 for Monday (ISO number = `to_int() + 1`). `from_int` already exists. The ballot should offer only "built-in tag only" or "tag plus a named ISO bridge". "to_int = ISO" is not an option the language allows.

##### Type set: T1, unchanged
- **plt**: "The one thing v1 must NOT do is make DateTime 'UTC-aware'. Then DateTime is isomorphic to Instant." I agree. That rules out T2 and T4.
- T3's zone-free DateTime avoids that, but I still reject it for v1:
  - The benchmark input carries `Z`. An agent who writes `DateTime.parse(log_ts)` compiles fine and then gets `Err` at run time, on real data. That moves a type error out of the compiler, which is a worse diagnostic surface.
  - No v1 task needs a civil date-time with no zone. It only becomes useful once zones exist to resolve it. Ship it with `ZonedDateTime`.
- On naming, I concede to plt that `DateTime` may later mean the civil type (the Temporal/jiff naming). v1 should reserve both `DateTime` and `ZonedDateTime` and decide neither now.
- **sys** (S2): "`hour()` lives on Instant, which goes against 03_types' rule that calendar decomposition belongs in its own type". The rule actually says "belongs in stdlib, not built-in types". Instant is a stdlib Tier 2 type now, so T1 meets the rule.
- **min**: "The `since(midnight)` pattern covers them." That pattern is hand-written `/ 3600` and `% 60` arithmetic, the exact thing the ticket complains about, and no diagnostic catches `/ 360`. So I keep `hour()`, `minute()` and `second()` on Instant.
- I concede `nanosecond()` (YAGNI) and sys's `nanos_of_day()`: both make the caller divide.
- Method home: adding these to Instant's sealed trait is allowed ("A sealed surface may grow", 03c:909). A clash with a user trait is loud (E0522 / W0734), never silent.

##### Sub-questions
1. `Date.from_ymd`. It follows the `from_*` pattern Blink uses for fallible or converting constructors (`from_code_point`, `from_epoch_secs`), and hover shows the argument order. Low stakes: I accept the majority.
2. `days_since`. **web**: "`a.days_until(b)` reads left to right". But `Instant.since` already puts the later value on the receiver. Matching that keeps one rule across both types, and the parameter name `earlier` shows in signature help.
3. `ConversionError`. **web**: "`ConversionError` is too generic to say 'Feb 30 does not exist.'" The message says it: `invalid date: day 30 out of range for 2026-02`. A new `DateError` also breaks `?` in any fn that mixes `parse_int` and `Date.parse` (a type mismatch at `?`, or a From impl the user must write). That is worse.
4. No `add_months` in v1. plt's group-action argument is the strongest reason.
5. Reject out-of-range values at construction and parse, so `to_instant` stays total. The message names the range: `invalid date: year 2300 outside 1677..2262`. `Instant.from_epoch_secs` overflowing with no check is a separate bug and should get its own ticket.
6. See the new fact above.
7. `Monday..Sunday`. LSP completion removes the typing cost, and the variant name is the Display text.
8. Debug = Display: still required on Date (and Instant). `assert_eq` failure output must show `2026-10-17`.
9. Pick ONE of `instant.date()` and `Date.from(instant)`, never both. I prefer `.date()`:
   - Typing `instant.` lists it.
   - It chains: `Instant.parse(s)?.date()`.
   - `Date.from` only appears once you already know the target type.
   - It also leaves the "expected Date, found Instant" quick-fix with one answer.
10. Leave `day_of_year` out (YAGNI). Weak preference.
11. `Date.to_instant()`: yes (midnight UTC).
12. Leave `at` / `and_time` out. `d.to_instant().add(Duration.hours(9))` composes.
13. **aiml**: "the fix-it diagnostic as part of the decision rather than an optional extra". I support this. The unresolved-name diagnostic for `std.time.DateTime` / `DateTime.from` / `DateTime.now` names the replacement (`instant.date()`, `.hour()`). Keep it narrow: a fixed note for reserved names in std.time, not a general hint table.
14. Adopt plt's round-trip law for `Date` and for `Instant` written with `Z`. Also state that offset input normalizes to UTC and does not round-trip as text.

STABLE, READY TO VOTE. The positions are clear. Sub-question 6 just needs its options rewritten to match the built-in to_int rule before the vote.

======================================================================
##### PLT — Phase B round 1 (verbatim)
======================================================================
PLT Phase B round 1 (pmpmyc). I CHANGE my Phase A position: T1 is now first and T3 (my P1) is second.

##### Type set: T1 > T3 > T2 (S1 form only) > T4

Why I move: my P1 rested on one rule, "v1 must NOT make DateTime UTC-aware, because then it is isomorphic to Instant." T1 satisfies that rule better than my own P1. Date is the zone-free civil sort, Instant is the timeline sort, and the UTC fields are named projections of Instant. My zone-free DateTime has no benchmark task that needs it. min is right that in practice it is the type people mistake for an instant. Leave it, and its name, to the later zones panel. Adding it later changes no v1 meaning, so deferring it paints no corner.

- T2: web says "`DateTime` writes the same text as `Instant`'s Display". Same text, same values and lossless conversions both ways is the definition of one type twice. sys S1 (no arithmetic on DateTime) is the better form of T2, but it is still an isomorphic copy of Instant.
- T4 is last. Public fields let `DateTime { month: 13, ... }` exist, so the calendar invariant goes. Opaque is the only sound form.
- sys S2: "`hour()` lives on Instant, which goes against 03_types' rule that calendar decomposition belongs in its own type." The 03_types sentence is about built-in vs stdlib ("belongs in stdlib, not built-in types"). Instant is already std.time Tier 2, so there is no conflict, and this panel rewrites that paragraph anyway.

T1 variant: include `hour()`, `minute()`, `second()` on Instant (aiml/devops). They are total, pure projections. min's `now.since(Date.from(now).to_instant()).to_seconds() / 3600` is the hand-rolled arithmetic the ticket wants gone. Leave `nanosecond()` out (YAGNI).

##### Sub-questions

1. **Constructor:** weak `from_ymd`. The name fixes the argument order. Either is sound.
2. **`days_since`.** Instant already sets the module's direction: `later.since(earlier)`. web: "`a.days_until(b)` reads left to right" means two directions in one module, and that is the trap. Law: `d.add_days(n).days_since(d) == n`.
3. **`ConversionError`.** TryFrom fixes ConversionError, and Date.parse should agree with parse_int and UUID.parse. web's "Feb 30 does not exist" text fits in the message cause classes devops lists. No new DateError.
4. **No month or year arithmetic in v1.** web: "`add_months(n)` ... clamp ... We still ship it". Clamping is not a group action: Jan 31 +1m +1m = Mar 28, but Jan 31 +2m = Mar 31, and `d.add_months(1).add_months(-1) != d` (Mar 31 → Apr 30 → Mar 30). A method named `add` that fails associativity and inverses is a trap. If it ever ships, the name must state the clamp.
5. **Reject at construction and parse.** Date's range = days whose midnight is a valid Instant. `Date.to_instant()` is then total, Display is always 4-digit fixed width, and the parse grammar is fixed width. Instant.parse rejects out-of-range text too. The unchecked `Instant_from_epoch_secs` overflow is a separate type:bug, not a panel item.
6. **Weekday Int bridge: a fact the panel must fix.** sys/devops/aiml say "`.to_int()` gives ISO 1..7". But Weekday is a fieldless enum, so `to_int()`, `from_int()` and comparison with Int are compiler-given tag operations (03_types.md §3.4 *Tag Operations*). std.time cannot redefine them. As far as I can read, the tag is the declaration index, so Monday is 0, and `wd == 1` compiles today and means Tuesday. That is the exact off-by-one the enum was meant to stop. Also, §3.4 does not plainly state where tags start, which is its own spec gap. Fix: a distinct name for ISO numbering, `to_iso() -> Int` (1..7), plus `Weekday.from_iso(n) -> Option[Weekday]` (Option, matching `from_int`). The spec text says outright that `to_int()` is the tag, not the ISO number. I drop my longer `to_iso_number` names.
7. **`Monday..Sunday`.** Declaration order then gives ISO Ord (Monday first) for free.
8. **Debug = Display: REQUIRED** (devops). For an opaque type, Debug printing the body would also leak the hidden representation.
9. **One conversion, not two.** From auto-derives Into (§3c.2), so `impl From[Instant] for Date` already gives two spellings (`Date.from(i)`, `i.into()`), and `instant.date()` beside it would be a third. I prefer `instant.date()` with NO From impl. Instant→Date drops the time of day, and a lossy projection should carry a name: `let d: Date = i.into()` hides the loss, and it sits with its siblings `.hour()` etc. I accept `Date.from` if the panel weighs the spec's spelling more, but never both. devops: "the LSP can offer it as a quick-fix, because exactly one conversion exists in each direction". That argument needs exactly one.
10. **`day_of_year`: weak include.** That name, not `ordinal`.
11. **`Date.to_instant()` (midnight UTC): include.** It is total under point 5. Date + time of day then composes: `d.to_instant().add(Duration.hours(9))`.
12. **No `at`/`and_time`:** there is no DateTime in T1. Point 11 covers it.
13. **Diagnostics:** support the aiml fix-it and devops cause-class messages as tooling. They are not language rules.
14. **State the law on values, not text:** `T.parse("{x}") == Ok(x)` for Date and Instant. This holds even though offset input does not round-trip as text (devops), because offsets change the text, not the value.

STABLE, READY TO VOTE

======================================================================
##### SYS — Phase B round 1 (verbatim)
======================================================================
SYSTEMS, Phase B round 1: I move from S1 to T1 (Date + Weekday, with calendar accessors and parse on Instant, and no DateTime in v1).

##### Why I changed
PLT's line convinced me: "The one thing v1 must NOT do is make DateTime 'UTC-aware'. Then DateTime is isomorphic to Instant." My S1 body `{date, nanos_of_day}` is exactly that isomorphism, and it is worse for the hardware: 16 bytes where Instant is 8, two compares for Ord, two words to hash, and a multiply-add at every boundary for no new meaning. An Instant already carries every bit a UTC DateTime would. `hour()` on an Instant costs the same ops as `hour()` on my S1 DateTime: one floor-mod by 86_400e9, then one divide. So T1 gives the same machine code with one type fewer.

##### Type set
T1 first. T3 (PLT's zone-free civil DateTime) second: it is sound and it is not a duplicate, but no task in the ticket needs a zone-free date-time, and adding it later breaks nothing. Against T2 (W1 and my old S1). Against T4.

Within T1: give Instant `hour()`, `minute()` and `second()`, and drop my `nanos_of_day()`. Leave out `nanosecond()` (YAGNI; `to_unix_ms` covers the cases that need it).

##### Sub-questions
1. **Constructor:** weak preference for `from_ymd`. In the spec, fallible constructors from parts are spelled `from_*` (`from_code_point`, `from_str`, and `from_int -> Option`). This does not block me; I accept `new`.
2. **Day difference:** I switch to `days_since`. `later.days_since(earlier)` has the same argument order as `Instant.since`, so there is one direction rule in std.time.
3. **Errors:** `ConversionError`. Against web's `DateError`. Devops' message classes plus byte offset give the "Feb 30 does not exist" text that web wants, without a second error type.
4. **Month/year arithmetic:** out of v1.
5. **Range:** reject at construction and parse. `Date.from_ymd`, `Date.parse` and `Instant.parse` give `Err` outside 1677-09-21..2262-04-11. Then `Date.to_instant()`, `Date.add_days` within the range, and `instant.date()` stay total. `add_days` past the range must panic on overflow like any Int overflow, not wrap. The spec must state this. Separately, `Instant_from_epoch_secs` multiplies by 1e9 with no check. That is an existing bug outside this vote, and I want a `type:bug` ticket for it.
6. **Weekday Int bridge:** this corrects all of us who wrote `.to_int()` = ISO 1..7 (me, devops, aiml). §3.4 *Tag Operations* makes `to_int()`/`from_int()` built-in tag operations on every fieldless enum. The compiler fixes their value by variant order (§06 line 406: "Variant order sets `to_int()`"). Stdlib cannot redefine them, so `Weekday.Monday.to_int()` is the tag, not ISO 1. I adopt PLT's `to_iso_number() -> Int` (1..7) and `from_iso_number(n) -> Result[Weekday, ConversionError]`. The spec must also say what the built-in `to_int()` gives for Weekday, so that no reader takes it for ISO. Declaring Monday first keeps the free Ord in ISO order.
7. **Variant names:** `Monday..Sunday`.
8. **Debug equals Display:** required, as devops says.
9. **Instant to Date:** `instant.date()`, with no `From[Instant] for Date`. In §3c's conversion table, `From` marks lossless widening (Char→Int: "widening"). Instant→Date throws away the time of day, so it is a lossy projection and should not be a `From` impl. `Instant.parse(s)?.date()` also chains, and autocomplete finds it. Answering min, who said "`Date.from(i: Instant)` (the `From` trait; this keeps the spec's `.from(instant)` wording)": the wording changes either way, because DateTime goes.
10. **`day_of_year`:** out (YAGNI; no task needs it). This does not block me.
11. **`Date.to_instant()` (midnight UTC):** in. It is total under rule 5.
12. **`and_time`/`at`:** out (there is no DateTime).
13. **Diagnostics:** in, as part of the decision. Aiml's fix-it for `DateTime.from`/`DateTime.now` costs one resolver name table entry and no run time. Devops' `.date()` quick-fix and message classes: yes.
14. **Round-trip:** the law `Date.parse("{d}") == Ok(d)` and `Instant.parse("{i}") == Ok(i)` goes in the spec. So `Instant.parse` must accept fractions of 1 to 9 digits, and pre-epoch values must floor. Input with an offset does not round-trip its text; the spec says so.

##### Replies
- **Min:** "The `since(midnight)` pattern covers them." That is three calls plus a hand division by 3600 for the same ops that `hour()` does in one call, and agents will divide by the wrong constant. I want `hour/minute/second` on Instant.
- **Web:** "`add(Duration)` and `since(other) -> Duration`, the same names as `Instant`." Same names on two types that hold the same value is the duplicate that the audit tickets target. Exact-time arithmetic belongs on Instant only.
- **Web:** "`add_months(n)` ... clamp." PLT's point holds: this is not an invertible action, `(d + 1m) + 1m != d + 2m`. It needs its own name and its own vote.
- **Devops:** "`.to_int()` gives ISO numbering." See item 6. The built-in tag operation already owns that name.
- **PLT, rule 3** ("Partial at the edge, total inside"): agreed. It is also the rule that keeps the hot path free of Result branches.
- **Open detail, does not block:** `Instant.parse` must reject text with no offset, and the error must name the cause ("no UTC offset; append Z"). Whether the date-time separator may also be a space (RFC 3339 §5.6 note) is a detail for implementation. I prefer strict `T`.

Implementation note: §3c.4 forbids inherent methods, so the Date and Weekday methods go through sealed ops traits, the same way InstantOps works. That does not change codegen: mono turns each call into a direct call on an int64.

STABLE, READY TO VOTE

======================================================================
##### AIML — Phase B round 1 (verbatim)
======================================================================
AI/ML Phase B round 1 (pmpmyc): I hold T1 and change three sub-answers (1, 6, 10). I also report one fact that conflicts with a Weekday bridge several of us proposed.

##### Type set: T1
I hold T1. Within T1 I keep hour()/minute()/second() on Instant and drop devops's nanosecond(), which no benchmark task needs.

##### A fact that affects sub-question 6
sections/03_types.md §3.4 "Tag Operations": every fieldless enum has a BUILT-IN `to_int()` and `from_int()`, and it compares with Int through its tag. §3.6: Ord is declaration order, and no second order or impl can be written. So a stdlib `Weekday.to_int()` that returns ISO 1..7 cannot exist. It IS the built-in tag. sys, devops and I (Phase A) all proposed it, and that was wrong.
- This is a real trap for models: `d.weekday() == 1` compiles and compares the tag.
- I did not find the spec line that says tags start at 0. Please verify it.
- If tags start at 0, Monday is 0 and Sunday is 6. That is Python's `date.weekday()` convention, which models know well.
- My position: no extra Int bridge in v1. The spec states Weekday's tags outright: Monday = 0 … Sunday = 6. If the panel wants ISO numbering, use a separate name, plt's `to_iso_number()`, never `to_int()`. I drop my `.to_int()` = ISO.

##### Sub-questions
1. **`Date.from_ymd`.** I CHANGE from `new`. The name fixes the argument order (Y-M-D, not M-D-Y), which is an LLM error class. It also matches the existing `from_` pattern of `Instant.from_epoch_secs` and `Char.from_code_point`.
2. **`days_since`.** It has the same operand order as `Instant.since` (self minus other), so one rule covers both.
3. **ConversionError**, with devops's messages (cause class and byte offset).
4. **Month and year arithmetic: out of v1.**
5. **Reject at construction and parse, so `to_instant` stays total.** Use ONE range for the module: the Instant domain, as plt says. sys's two ranges (Date -9999..9999, DateTime 1678..2261) give a model two limits to learn.
6. See above.
7. **Full names, `Monday`…`Sunday`.** The variant name then equals the Display text, so a model sees one spelling.
8. **Debug = Display, required** (devops). An `assert_eq` failure that a model can read is how an agent fixes a test in one retry.
9. **`instant.date()` only, with no `impl From[Instant] for Date`.** Two spellings is a decision point. `.date()` chains after `?` (`Instant.parse(s)?.date()`), and it puts all decomposition on Instant beside `.hour()`. I accept `Date.from` if the panel prefers it, provided exactly one of the two exists.
10. **Leave `day_of_year` out.** I CHANGE to min/devops. No task in the ticket needs it.
11. **`Date.to_instant()`: include it.**
12. **No and_time/at.** `d.to_instant().add(Duration.hours(9))` covers it.
13. **Keep my fix-it** for `DateTime.from`/`DateTime.now`, plus devops's `.date()` quick-fix.
14. **Endorse plt's law `T.parse("{x}") == Ok(x)`** for Date and Instant, and devops's note that offset input does not keep its text.

**New point: `Instant.parse` input.** Accept `T` or a space between date and time; RFC 3339 §5.6 allows the space, and real logs often use it. Reject text with no offset. The error message must say "no UTC offset; append Z if the time is UTC". Without that hint, models hand-roll string patches.

##### Responses
- **min:** "`hour()/minute()/second()` on Instant | The `since(midnight)` pattern covers them."
  - The pattern is `now.since(now.date().to_instant()).to_seconds() / 3600`. That is about 20 tokens, and minute needs `/ 60 % 60`, a modulo models often drop.
  - "Bucket by hour" is the next most common log task after "bucket by day". Three one-line methods cost less than one wrong hand-rolled formula in every program that needs them.
- **web:** "`a.days_until(b)` reads left to right."
  - It reverses `Instant.since`, so the module would have two operand orders. Models apply the one they saw last.
- **web:** "`ConversionError` is too generic to say 'Feb 30 does not exist.'"
  - The message says it: devops's `day 30 out of range for 2026-02`. A second error type means a second `?` conversion in every function that parses an Int and a date.
- **web, `add_months` clamp:** I agree with plt's "(d + 1m) + 1m differs from d + 2m". A method that silently breaks associativity is the bug models copy from training data.
- **sys S2:** "hour() lives on Instant, which goes against 03_types' rule that calendar decomposition belongs in its own type."
  - The rule says decomposition belongs "in stdlib, not built-in types". Instant's methods are in lib/std/time.bl (`Instant_add` etc.), and Date is the separate type. S2 meets the rule.
- **plt:** "The one thing v1 must NOT do is make DateTime 'UTC-aware'."
  - I agree, and that rules out T2 and T4.
  - On T3's civil DateTime: `DateTime.parse` and `Instant.parse` would take near-identical text with opposite rules about `Z`. A model tries one, gets Err, then tries the other: two decision points for the offset-less log line. The no-offset hint above handles that case in v1. Defer the civil DateTime until a friction ticket asks for it.
- **devops:** "Each extra type that holds the same value as another means more 'expected X, found Y' errors." I agree. That is the main case for T1.

STABLE, READY TO VOTE


#### Phase C — Silent vote: ballot

Phase C — silent vote, pmpmyc (std.time calendar API)

All six panelists sent STABLE, READY TO VOTE after round 1. All round-1 replies, verbatim:
(quoted in full in the section above)
Read it before you vote. Vote on your own; do not message other panelists.

##### Fact (asked for in round 1 by aiml, plt, web)
- sections/03_types.md §3.4 *Tag Operations* and sections/06_tooling.md:406 ("Variant order sets `to_int()`") fix tag ORDER. No spec line states the first tag's VALUE.
- The current compiler gives 0 for the first variant: `type W { A, B, C }` prints `W.A.to_int()` = 0, `W.C.to_int()` = 2 (probe run with build/blink).

##### Questions (options are the ones panelists put forward)

**Q1 — Type set**
- T1: Date + Weekday; calendar accessors and parse on Instant; no DateTime type in v1.
- T2: Date + UTC DateTime.
- T3: Date + zone-free civil DateTime.
- T4: Date + public-field read-only DateTime view.

**Q2 — Weekday Int bridge**
- A: Built-in tag only. Spec states Monday is declared first, and `Weekday.Monday.to_int()` is 0 … Sunday is 6. No extra method. (min, devops, aiml)
- B: Built-in tag plus a named ISO 1..7 bridge; the spec says `to_int()` is the tag, not ISO. If you vote B, also pick a shape:
  - B1: `iso_number() -> Int` only (web)
  - B2: `to_iso() -> Int` + `Weekday.from_iso(n) -> Option[Weekday]` (plt)
  - B3: `to_iso_number() -> Int` + `Weekday.from_iso_number(n) -> Result[Weekday, ConversionError]` (sys)

**Q3 — `Instant.parse` date/time separator**
- A: `T` only (sys)
- B: `T` or a space (aiml)

**Q4 — `Date.day_of_year()`**
- A: Out of v1 (sys, web, devops, aiml, min)
- B: In (plt)

**Q5 — Spec text on future zone names**
- A: Say only "no zone support in v1"; reserve no name; the zone panel picks names later (min, web)
- B: Reserve both `DateTime` and `ZonedDateTime` now and decide neither (devops)

**Q6 — Core bundle (no round-1 reply opposed any line).** Vote APPROVE, or APPROVE EXCEPT <line numbers> with a reason for each.
1. Instant gains `hour()`, `minute()`, `second()` (UTC). No `nanosecond()`.
2. `instant.date() -> Date`. No `impl From[Instant] for Date`.
3. `Instant.parse(s) -> Result[Instant, ConversionError]`: RFC 3339; needs `Z` or `±hh:mm`, normalized to UTC; text with no offset is an error whose message names the cause (e.g. "no UTC offset; append Z if the time is UTC").
4. `pub opaque type Date`; `Date.from_ymd(y, m, d) -> Result[Date, ConversionError]`; `Date.parse(s)` accepts `YYYY-MM-DD` only.
5. `year()`, `month()` (Int 1..12), `day()`, `weekday() -> Weekday`.
6. `add_days(n: Int) -> Date`; `days_since(earlier: Date) -> Int` (same receiver order as `Instant.since`). `add_days` past the range panics as Int overflow does (sys).
7. `Date.to_instant() -> Instant` at 00:00:00Z, total.
8. One range for the module: `Date.from_ymd`, `Date.parse`, `Instant.parse` reject values outside the Instant domain (~1677-09-21..2262-04-11).
9. Errors are `ConversionError`; messages name the cause class and byte offset (devops list).
10. No `add_months`/`add_years` in v1; the spec says so in one sentence.
11. `type Weekday { Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday }`; Display is the English name.
12. Date and Weekday: Eq, Ord, Hash, Display, Clone, Debug; Debug text equals Display.
13. Round-trip law on values: `Date.parse("{d}") == Ok(d)`, `Instant.parse("{i}") == Ok(i)`; input with an offset does not round-trip as text, and the spec says so.
14. Diagnostics are part of the decision: a fix-it for `DateTime.from(x)` / `DateTime.now()` naming `instant.date()` / `.hour()`; `expected Date, found Instant` with a `.date()` quick-fix.
15. Out of v1: timezones, format strings, `today()`, leap seconds (`:60` rejected), `and_time`/`at`.

##### Reply format (SendMessage to team-lead, one message)
For each of Q1..Q6:
- **Vote:** option label
- **Reasoning:** 2–4 sentences from your domain
- **Concern:** one sentence on what could go wrong with the option that wins


#### Phase C — Silent vote: votes

======================================================================
##### SYS — Phase C vote (verbatim)
======================================================================
SYSTEMS: Phase C vote for pmpmyc.

**Q1: Type set**
- **Vote:** T1
- **Reasoning:** A UTC DateTime holds the same bits as an Instant, but it is 16 bytes against 8, and it needs two compares for Ord and two words to hash. T1 gives the same machine code with one type fewer: `hour()` on an Instant is one floor-mod plus one divide by a constant, and gcc -O2 turns those into multiplies. Date is one int64, so grouping by date hashes one word.
- **Concern:** If benchmarks show that agents keep writing `DateTime.*`, we will be tempted to add a UTC DateTime alias that duplicates Instant. The fix-it diagnostic must carry that load.

**Q2: Weekday Int bridge**
- **Vote:** A (I change from my round-1 B3)
- **Reasoning:** The tag is already a free, total, zero-cost Int bridge that the compiler fixes. A second named bridge gives two numbers for one fact, and that is the duplication we cut in Q1. Monday=0..Sunday=6 matches Python's `date.weekday()`, the strongest prior in training data. The spec must now state the first tag's value (0) for all fieldless enums, which closes a real gap for everyone.
- **Concern:** Agents trained on JS `getDay()` (Sunday=0) or on ISO (Monday=1) will write off-by-one code that compiles. The Weekday doc line must state 0..6 with Monday=0 in plain words.

**Q3: Instant.parse separator**
- **Vote:** A (`T` only)
- **Reasoning:** One fixed-width grammar keeps the parser a straight-line byte check and keeps the round-trip law exact. A caller who has space-separated logs does one `replace` at the boundary, and that costs nothing next to the I/O.
- **Concern:** Log formats with a space (Postgres, Python logging) will fail at first, and agents will spend a retry on it. The error message for byte 10 must say "expected 'T'".

**Q4: Date.day_of_year()**
- **Vote:** A (out)
- **Reasoning:** No task in the ticket needs it. It is `d.days_since(Date.from_ymd(d.year(), 1, 1)?) + 1` with no extra cost, and it can be added later with no break.
- **Concern:** The workaround needs a `?` on a constructor that cannot fail for a valid year, which adds noise in hot loops.

**Q5: Future zone names**
- **Vote:** A
- **Reasoning:** Reserving names now is a decision made without the zone design: representation, tzdata embedding, and effect rows. The zone panel should pick names when it knows what the type holds. Reserving nothing costs nothing.
- **Concern:** A user or a lib/pkg can take `DateTime` as a type name in the meantime, and a later std name then collides with code that already exists.

**Q6: Core bundle**
- **Vote:** APPROVE
- **Reasoning:** Every line keeps the representation at one int64, keeps the hot paths total (range checked once at the edge in line 8, so lines 2, 5 and 7 need no Result), and gives each operation one home. Line 6's panic on overflow is the right choice: wrapping would create silent wrong dates.
- **Concern:** Lines 1, 2 and 5 must use floor division and floor modulus, not C truncation. If an implementer uses `/` and `%` on int64 directly, pre-epoch instants will give hour -1 and the wrong date. Tests must include an instant before 1970.

======================================================================
##### WEB — Phase C vote (verbatim)
======================================================================
WEB/SCRIPTING, Phase C vote for pmpmyc.

**Q1: Type set**
- **Vote:** T1
- **Reasoning:** One point-in-time type and one calendar-day type: a JS/Python dev never has to ask "Instant or DateTime?". A UTC DateTime would be a second spelling of Instant, and every signature would have to pick one. Date stays separate because "group by day" needs a Hash key with no time of day in it, and that is the split Python got right.
- **Concern:** The `DateTime` training prior is strong, so if the fix-it diagnostic (Q6 line 14) slips, agents will fail on the first line of every time task.

**Q2: Weekday Int bridge**
- **Vote:** A. I change my position from B1.
- **Reasoning:** The fact that the compiler gives Monday = 0 settles it for me. The trap is `wd == 1` compiling and meaning Tuesday, and a second ISO method does not stop that. A clear spec line does. With the spec saying "Monday.to_int() is 0 … Sunday is 6; the ISO number is to_int() + 1", any dev can work it out from one sentence, and the module has one fewer name to learn.
- **Concern:** JS devs carry `getDay()`'s Sunday = 0 in their heads, so the spec and the `blink llms` time topic must show the Monday = 0 line next to the Weekday declaration, not deep in §3.4.

**Q3: `Instant.parse` separator**
- **Vote:** B (`T` or a space)
- **Reasoning:** RFC 3339 §5.6 allows a space. Postgres output and many log formats use one, and Python's `str(datetime)` prints one. Rejecting the space turns the main benchmark task, parsing a log line, into a `.replace(" ", "T")` workaround that agents have to find by failing first. Accepting it costs one byte comparison in the parser.
- **Concern:** If the space wins, Display still writes `T`. The round-trip law (line 13) holds on values, but the spec must say plainly that space input does not round-trip as text, the same as offset input.

**Q4: `Date.day_of_year()`**
- **Vote:** A (out)
- **Reasoning:** No benchmark task and no common scripting task needs it. It is cheap to add later if a friction ticket shows demand.
- **Concern:** None of note. Someone will hand-roll `d.days_since(Date.from_ymd(d.year(), 1, 1)?) + 1`, which is correct.

**Q5: Future zone names**
- **Vote:** A
- **Reasoning:** Reserving a name for a type that does not exist gives readers a word with no meaning. That spec text will get read as "DateTime exists" and produce the questions we want to avoid. The fix-it diagnostic already handles `DateTime` in user code, and the zone panel should pick names with the full design in front of it.
- **Concern:** A later panel could use `DateTime` for the zoned type, which Python devs will misread as the naive one. That panel must weigh this.

**Q6: Core bundle**
- **Vote:** APPROVE
- **Reasoning:** Each line serves the 90% case with names a JS/Python/Kotlin dev can guess: `.date()`, `.hour()`, `Date.parse`, `add_days`, `days_since`, `weekday()`. Lines 9 and 14 are what make the API learnable in five minutes: error text that names the fix, and fix-its that point training-prior code at the real API.
- **Concern:** Leaving out `add_months` (line 10) will be the first friction ticket from billing and "next month" tasks. Watch for that ticket and put month arithmetic on the panel soon after it arrives.



##### devops
**Q1: Type set**
- Vote: T1
- Reasoning: Two types that do different jobs (a point in time and a calendar day) give each mismatch exactly one quick-fix, `.date()` or `.to_instant()`. Autocomplete on `Instant` shows no second, overlapping method list. The other options either add a type that holds the same value as `Instant` (T2, T4), or move a type error to run time when `Z` text reaches `DateTime.parse` (T3).
- Concern: training priors push models to write `DateTime.from(...)`. If the line-14 fix-it ships late or its wording is vague, the first try at each time task will fail to compile.

**Q2: Weekday Int bridge**
- Vote: A
- Reasoning: Each enum gets one bridge to Int, and every enum uses the same rule. Autocomplete then never shows a 0-based and a 1-based method next to each other. The spec must state the value outright: Monday is 0, Sunday is 6.
- Concern: code ported from ISO-week logic will expect 1..7 and be off by one with no compile error. The `to_int()` doc line and the `blink llms` time topic must say "ISO number = to_int() + 1".

**Q3: Instant.parse separator**
- Vote: B
- Reasoning: RFC 3339 §5.6 allows the space, and real logs use it. Rejecting it gets us `s.replace(" ", "T")` workaround code in every benchmark answer, which is the kind of workaround the ticket was filed to remove. It adds no ambiguity: the offset rule still rejects bare local times, and Display still writes `T`.
- Concern: if A wins, the error must say "expected 'T' at byte 10 (found ' ')" so that the fix is obvious from the message alone.

**Q4: Date.day_of_year()**
- Vote: A
- Reasoning: No benchmark task needs it, and every method added grows the sealed surface for good. `d.days_since(Date.from_ymd(d.year(), 1, 1)?) + 1` covers the rare case.
- Concern: that workaround needs `?` or `.unwrap()` on a value that cannot fail, which is noise. If friction tickets show demand, add the method then.

**Q5: Future zone names**
- Vote: A. I change from my round-1 position.
- Reasoning: a "reserved" name has no clear tooling meaning. If it means users cannot declare their own `DateTime`, we invent a new error class for a feature that does not exist. If it means nothing, the text is dead. The line-14 fix-it works without reserving anything: it is a note on an unresolved name in `std.time`.
- Concern: the zone panel may later pick `DateTime` for something users have since declared themselves, so a std name will shadow theirs. The W1010-style shadow warning must cover that case.

**Q6: Core bundle**
- Vote: APPROVE
- Reasoning: each line has an exact diagnostic surface: range errors name the range (line 8); parse errors name the cause class and byte offset (line 9); Debug equals Display, so `assert_eq` failures can be read (line 12); the fix-its are part of the ruling, not optional (line 14). None of it needs parser or `blink fmt` work.
- Concern: line 9's messages will drift unless the spec lists them as fixed text and the tests check them word for word. If not, each implementation pass will rewrite them and the fix-it guidance goes stale.

##### aiml
**Q1** Vote: T1. Reasoning: One point-in-time type and one calendar-day type means a model never has to choose "Instant or DateTime?" at the start of each time task. That choice is where Python-trained models go wrong (naive vs aware, `date` vs `datetime`). T2–T4 each add a type that holds almost the same value as another, with conversions in both directions. That is more names, more "expected X, found Y" retries, and more tokens per task. Concern: The training prior for `DateTime` is strong. If the fix-it in Q6 line 14 ships late or is vague, models will waste a retry on every task.

**Q2** Vote: A. Reasoning: If B wins, autocomplete shows two Int bridges on one enum, one 0-based and one 1-based. That recreates the off-by-one the enum exists to remove. Monday = 0 also matches Python's `date.weekday()`, the convention models have seen most. The benchmark tasks print the name; they do not number it. Concern: The spec must state the first tag's value outright, which it does not do today (see the ballot fact). Otherwise `wd == 1` stays a guess for a reader who learns from the spec alone.

**Q3** Vote: B. Reasoning: Real log lines often write `2026-10-17 12:00:00Z`, and RFC 3339 §5.6 allows the space. With `T` only, the model writes a `.replace(" ", "T")` patch or a slice-and-concat before every parse. That costs tokens and fails in subtle ways. Accepting both costs nothing in decision points, because the caller never chooses. Concern: If A wins, the parse error for a space must name the fix ("expected 'T' at byte 10"), or models will loop on it.

**Q4** Vote: A. Reasoning: No task in the ticket needs it, and each extra name is one more autocomplete entry to rank. It is cheap to add later from a friction ticket. Concern: "Day N of the year" tasks will hand-roll `d.days_since(Date.from_ymd(d.year(), 1, 1)?) + 1` and drop the `+ 1`.

**Q5** Vote: A. Reasoning: A reserved but undefined name in the spec is text a model can misread as an API that exists. The fix-it in Q6 line 14 already handles `DateTime.from` / `DateTime.now` without a reservation clause. The zone panel picks names when it has a design to name. Concern: If a later zone panel takes `DateTime` for a civil type, the v1 fix-it text must change at the same time, or it will send models to the wrong API.

**Q6** Vote: APPROVE. Reasoning: Every line follows a pattern the spec already teaches: type-scoped `from_*` and `parse`; `Result[_, ConversionError]`; named methods, not operators; one operand order shared with `Instant.since`. A model can learn the full surface from the spec section alone. Line 14 makes the diagnostics part of the decision, which matters most for first-try accuracy. Lines 9 and 13 give a model the text it needs to fix its own code in one retry. Concern: If the Date tests of line 13 (round-trip) and line 8 (range) do not cover the edge years 1677 and 2262 and pre-epoch dates, a civil_from_days bug at the edges will ship and get copied into training data.

##### plt
**Q1** Vote: T1. Reasoning: Instant is the only timeline sort and Date is the only civil sort, and every UTC field is a total, pure projection of an Instant. A UTC DateTime (T2/T4) would be isomorphic to Instant, so it is the same type twice. A zone-free DateTime (T3) has no v1 task, and adding it later changes no v1 meaning. Concern: a later zones panel may want to add `hour()` and similar accessors to a zoned type. Two `hour()` methods, UTC on Instant and local on the zoned type, will then need clear names or docs so readers do not mix them up.

**Q2** Vote: A (I CHANGE from B2). Reasoning: The off-by-one I raised came from the spec not saying what `to_int()` gives. Once the spec states Monday = 0 … Sunday = 6 outright, the built-in tag has one fixed meaning and `from_int` is already its inverse. A second Int view of the same enum adds a name and no expressive power, since ISO = `to_int() + 1` is a fixed bijection. Python's `date.weekday()` uses the same 0-based convention, which helps readers. Concern: code ported from ISO-based sources (Java `getValue()`, `date +%u`) will write `wd.to_int() == 1` and expect Monday. The spec line and the doc example must show Monday = 0 near Weekday, not only in §3.4.

**Q3** Vote: B (`T` or one space). Reasoning: RFC 3339 §5.6 explicitly allows a space, and the grammar stays unambiguous and fixed width either way. The round-trip law is on values, and `Instant.parse("{i}") == Ok(i)` still holds because Display always writes `T`. The accepted language must be stated exactly in the spec: `T` or exactly one U+0020, nothing else. Concern: once one leniency ships, there will be pressure to accept more (lowercase `t`/`z`, comma fractions, missing seconds). The spec must list the grammar as closed.

**Q4** Vote: A (I CHANGE; out of v1). Reasoning: No ticket task needs it, and it can be added later as a pure projection without touching any v1 meaning. YAGNI costs nothing here. Concern: someone hand-rolls it as `d.days_since(Date.from_ymd(d.year(), 1, 1)?) + 1`. That is correct, so the risk is low.

**Q5** Vote: A. Reasoning: A reserved name with no meaning attached is a commitment with no content. It cannot be checked or tested, and it biases the later panel's choice of sorts (is the zoned type `DateTime` or `ZonedDateTime`, and is there a civil date-time beside it?). The sound v1 promise is that Date and Instant are zone-free and UTC-based, which keeps every later design open. Concern: a user may declare their own `DateTime` type, and a later stdlib `DateTime` in std.time would then clash with it on import. Selective imports limit that, so the risk is acceptable.

**Q6** Vote: APPROVE. Reasoning: The bundle is consistent. Line 8 makes the domain a single interval, and with it lines 2, 5 and 7 are total and line 13 holds. Line 6's panic at the range edge keeps the Date invariant the same way Int overflow does. Line 2 avoids the From + Into + `.date()` three-spelling problem. Line 10 keeps `add_*` names for true group actions. Concern: line 8's lower bound (1677-09-21) is not a whole day of Instant nanos. The spec must give the exact first and last valid Date, so that `Date.to_instant()` is total on every value `Date.from_ymd` accepts. The bound should be checked as a property test, not prose.

##### min
**Q1** Vote: T1. Reasoning: In UTC-only v1, a DateTime type of any form (T2/T3/T4) is a second way to hold a value that Instant plus Date already hold. Each one adds a type, its traits, and conversions in both directions. T1 covers every benchmark task in the ticket with Date + Weekday and five Instant methods. Nothing in T1 blocks a later panel from adding a civil or zoned type when friction tickets show a need. Concern: If T1 wins, log stamps with no offset (`2026-02-14 12:00:00`) have no parse path for hour-of-day. Agents may then append `Z` by hand and quietly take local text as UTC.

**Q2** Vote: A. Reasoning: The language already gives every fieldless enum `to_int()`/`from_int()`, so a second Int bridge would put two numberings on one enum, one starting at 0 and one at 1. That is exactly the off-by-one the enum exists to stop. The tasks print the weekday name or match on it; they do not number it. A one-line spec sentence (Monday = 0 … Sunday = 6) costs no surface. Separately, §3.4 should state that the first tag is 0 for every enum, because that is a gap in the spec on its own. Concern: If A wins, code that writes `wd.to_int() == 1` from an ISO habit will compile and mean Tuesday. Only the spec sentence and docs guard against that.

**Q3** Vote: A. Reasoning: One accepted grammar, the same text Instant's Display writes, keeps the round-trip law exact and the parser small. A space adds a second form for one value. The byte-offset error from line 9 (`expected 'T' at byte 10`) tells the caller the one-call fix. I accept that B adds no new names, so this is a weak preference. Concern: If A wins, agents will meet Python- or SQL-style `2026-02-14 12:00:00+00:00` stamps often and must remember `.replace(" ", "T")` each time, which costs tokens on each retry.

**Q4** Vote: A. Reasoning: No task in the ticket needs it. It is cheap to add later from a friction ticket and cannot be removed once shipped. Concern: If A wins, someone will compute it as `d.days_since(Date.from_ymd(d.year(), 1, 1).unwrap()) + 1`. That works, but it is wordy.

**Q5** Vote: A. Reasoning: Spec text that reserves a name for a feature that does not exist is a promise with no design behind it, and it narrows what the zone panel can choose. "No zone support in v1" says all a reader needs. Concern: If A wins, a third-party package may claim `DateTime` in the meantime and make the later stdlib name clash.

**Q6** Vote: APPROVE. Reasoning: Every line is either the smallest form of something a task needs, or an exclusion. The single range rule (8) and Debug equal to Display (12) remove whole classes of bugs at no cost to the surface. The diagnostics (14) target the training prior that would otherwise cost the most failed tasks. Concern: If the bundle wins, line 1 (hour/minute/second on Instant) is the most likely to grow. Later requests for `nanosecond()`, `day_of_year()` and similar should each need a friction ticket, not come in by analogy.

##### Tally
Q1 T1 6-0 | Q2 A 6-0 | Q3 B 4-2 (sys, min for A) | Q4 A 6-0 | Q5 A 6-0 | Q6 APPROVE 6-0


#### Phase D — Round 2 on Q3: lead broadcast

Phase D, focused debate, pmpmyc. Q3 only: `Instant.parse` date/time separator.

Phase C result: Q3 split 4-2 (B: web, devops, aiml, plt; A: sys, min). Q1, Q2, Q4, Q5 and Q6 passed 6-0 and are closed. Do not reopen them.

Every Phase C Q3 vote, verbatim:

**sys: A (`T` only)**
- Reasoning: One fixed-width grammar keeps the parser a straight-line byte check and keeps the round-trip law exact. A caller who has space-separated logs does one `replace` at the boundary, and that costs nothing next to the I/O.
- Concern: Log formats with a space (Postgres, Python logging) will fail at first, and agents will spend a retry on it. The error message for byte 10 must say "expected 'T'".

**web: B (`T` or a space)**
- Reasoning: RFC 3339 §5.6 allows a space. Postgres output and many log formats use one, and Python's `str(datetime)` prints one. Rejecting the space turns the main benchmark task, parsing a log line, into a `.replace(" ", "T")` workaround that agents have to find by failing first. Accepting it costs one byte comparison in the parser.
- Concern: If the space wins, Display still writes `T`. The round-trip law (line 13) holds on values, but the spec must say plainly that space input does not round-trip as text, the same as offset input.

**devops: B**
- Reasoning: RFC 3339 §5.6 allows the space, and real logs use it. Rejecting it gets us `s.replace(" ", "T")` workaround code in every benchmark answer, which is the kind of workaround the ticket was filed to remove. It adds no ambiguity: the offset rule still rejects bare local times, and Display still writes `T`.
- Concern: if A wins, the error must say "expected 'T' at byte 10 (found ' ')" so that the fix is obvious from the message alone.

**aiml: B**
- Reasoning: Real log lines often write `2026-10-17 12:00:00Z`, and RFC 3339 §5.6 allows the space. With `T` only, the model writes a `.replace(" ", "T")` patch or a slice-and-concat before every parse. That costs tokens and fails in subtle ways. Accepting both costs nothing in decision points, because the caller never chooses.
- Concern: If A wins, the parse error for a space must name the fix ("expected 'T' at byte 10"), or models will loop on it.

**plt: B (`T` or one space)**
- Reasoning: RFC 3339 §5.6 explicitly allows a space, and the grammar stays unambiguous and fixed width either way. The round-trip law is on values, and `Instant.parse("{i}") == Ok(i)` still holds because Display always writes `T`. The accepted language must be stated exactly in the spec: `T` or exactly one U+0020, nothing else.
- Concern: once one leniency ships, there will be pressure to accept more (lowercase `t`/`z`, comma fractions, missing seconds). The spec must list the grammar as closed.

**min: A**
- Reasoning: One accepted grammar, the same text Instant's Display writes, keeps the round-trip law exact and the parser small. A space adds a second form for one value. The byte-offset error from line 9 (`expected 'T' at byte 10`) tells the caller the one-call fix. I accept that B adds no new names, so this is a weak preference.
- Concern: If A wins, agents will meet Python- or SQL-style `2026-02-14 12:00:00+00:00` stamps often and must remember `.replace(" ", "T")` each time, which costs tokens on each retry.

##### What to send back (SendMessage to team-lead, one message)
- Your response on Q3 only. Name the panelist and quote the line you answer.
- You may change your position; say so if you do.
- End with exactly one of: `STABLE, READY TO VOTE` or `NOT STABLE: <what is still open>`.
This is the only Phase D round. A silent re-vote on Q3 follows.


#### Phase D — Round 2 on Q3: replies


##### sys
SYSTEMS, Phase D Q3: I change my vote from A to B (`T` or exactly one space).

My own line was: "A caller who has space-separated logs does one `replace` at the boundary, and that costs nothing next to the I/O." That is wrong for the hardware. `replace` allocates a new Str and copies every line, and the benchmark's main task runs it in a loop over every line of the log. With B the parser stays straight-line and fixed width. Byte 10 becomes `b == 'T' || b == ' '`, which is one extra compare, no allocation and no copy. The workaround costs more than the leniency it avoids. It is also wrong in a quiet way: `.replace(" ", "T")` on a line that has more than one space changes the rest of the line too. An agent that slices first and then replaces gets it right, and one that does not gets a wrong parse.

Web says: "Accepting it costs one byte comparison in the parser." Confirmed. The width is unchanged, so every later offset in the grammar stays a constant.

Plt says: "The accepted language must be stated exactly in the spec: `T` or exactly one U+0020, nothing else." Agreed, and it is required for my vote. The spec lists the grammar as closed: no lowercase `t`/`z`, no comma fraction, no missing seconds, no two spaces. A closed grammar keeps the parser a fixed byte check, and stops each new leniency from adding a branch.

Web says: "the spec must say plainly that space input does not round-trip as text, the same as offset input." Agreed. The round-trip law still holds on values, because Display always writes `T`.

Min says: "A space adds a second form for one value." The caller never chooses between the two forms, so this is not a second way to do anything. It is one parser that accepts the two spellings RFC 3339 allows.

STABLE, READY TO VOTE

##### min
MINIMALISM, Phase D, Q3 only. I CHANGE my vote from A to B, on one condition: the spec gives the grammar as closed, as plt words it.

- **To devops:** "Rejecting it gets us `s.replace(" ", "T")` workaround code in every benchmark answer, which is the kind of workaround the ticket was filed to remove." This is the argument that moves me. I measure surface in names and choices. B adds no name, and the caller has no choice to make. A, on the other hand, moves a fixed cost into every program that reads a Postgres or Python log. Workaround code repeated in user programs is surface too, and it is the worst kind, because the spec never sees it.
- **To sys:** "keeps the round-trip law exact". With B the law still holds on values: `Instant.parse("{i}") == Ok(i)`, because Display always writes `T`. The text does not round-trip for space input, but line 13 already accepts that for offset input. A space adds no new kind of exception.
- **To plt:** "The spec must list the grammar as closed." I make this my condition for B. The accepted separator is `T` or exactly one U+0020, and nothing else. The spec should also say plainly that lowercase `t`/`z`, comma fractions, missing seconds and other leniencies are out, so a later "just one more" request has to go through a panel. If the grammar is left open, I go back to A.
- **To web:** "the spec must say plainly that space input does not round-trip as text". I agree. Put it in the same sentence as the offset note in line 13.

STABLE, READY TO VOTE

##### web
WEB/SCRIPTING, Phase D on Q3: I keep my position at B (`T` or one space), with plt's closed grammar as part of the vote.

**To sys:** "A caller who has space-separated logs does one `replace` at the boundary, and that costs nothing next to the I/O." The cost is not CPU. The cost is that the workaround is a bug magnet. `line.replace(" ", "T")` on a whole log line rewrites every space in the message. On a slice it fails on any line whose prefix length differs. And `2026-02-14 12:00:00 +00:00` (Postgres puts a space before the offset in some modes) still fails after the replace, because now there is a `T` before the offset. That is three ways to get the workaround wrong, and each one is a Stack Overflow question. B puts the one correct check inside the parser, where it is written once.

**To min:** "A space adds a second form for one value." Line 3 of the bundle already gives one value many text forms: `Z`, `+00:00` and `+05:30` with shifted digits all parse to the same Instant. The round-trip law is on values for exactly that reason. The space adds a form under a rule we already accepted. It does not add a new kind of exception. min also says "this is a weak preference", and the cost min names in the concern (agents remembering `.replace` on each retry) is the real-world cost. I weigh it higher.

**To plt:** "The accepted language must be stated exactly in the spec: `T` or exactly one U+0020, nothing else." Agreed, and I take it as part of my vote. The rule is uppercase `T` or exactly one U+0020, and uppercase `Z`. That means no lowercase `t`/`z` (RFC 3339 §5.6 allows them, but nobody emits them), no comma fraction, no missing seconds, and no space before the offset. The spec lists the grammar as closed, so the next leniency request needs a panel.

**To sys/min on the error text, if A wins anyway:** devops' "expected 'T' at byte 10 (found ' ')" must be the exact message, so the one-call fix is obvious from the error alone.

STABLE, READY TO VOTE

##### aiml
AI/ML Phase D, Q3 (Instant.parse separator): I hold B. I add plt's closed-grammar condition and web's text-round-trip note.

- **To sys:** "keeps the round-trip law exact."
  - Line 13 put the law on values: `Instant.parse("{i}") == Ok(i)`. Display always writes `T`, so the law holds under B with no change.
  - Text round-trip is already lost under the approved bundle: line 3 accepts `+05:30` and Display writes `Z`. A space adds no new kind of loss.
- **To sys:** "A caller who has space-separated logs does one `replace` at the boundary."
  - For a model, the cost is not the call. It is the failed first run that teaches the call: one compile-run-read-error cycle per task, every task.
  - `replace(" ", "T")` on a whole log line also breaks it, because it changes every space. A correct fix needs a slice plus a concat. Models get that wrong and the error is silent: the result parses, with a wrong field.
- **To min:** "A space adds a second form for one value."
  - Two accepted input forms is not two ways to do it. The caller writes `Instant.parse(s)` either way and makes no choice.
  - "One way" governs what the programmer writes, not what bytes a parser accepts. Line 3 already accepts three offset forms (`Z`, `+hh:mm`, `-hh:mm`) for one value.
- **To plt:** "The spec must list the grammar as closed." I agree, and I make it a condition of my B. The spec gives the exact grammar and says nothing else is accepted, which also blocks the pressure plt names:
  - The separator is `T` or exactly one U+0020.
  - No lowercase `t` or `z`, no comma fraction, no missing seconds.
  - A model learns a closed list from the spec. It cannot learn "lenient in unstated ways".
- **To web:** "the spec must say plainly that space input does not round-trip as text." I agree: one sentence covering both the offset case and the space case.

The error rule holds under either outcome: input with any other byte at offset 10 gets "expected 'T' or ' ' at byte 10".

STABLE, READY TO VOTE

##### plt
PLT Phase D, Q3 only. I HOLD B (`T` or exactly one U+0020).

**To sys:** "keeps the round-trip law exact". Line 13 (passed 6-0) states the law on values: `Instant.parse("{i}") == Ok(i)`. B keeps it exact, because Display always writes `T`, and the law never quantifies over input text. Text round-trip already fails under A: `+05:30` input and `.500Z` (Display writes `.5Z`) do not come back as the same text. So the law gives no reason to choose A over B.

**To min:** "A space adds a second form for one value". Parse is already many-to-one under A: `Z`, `+00:00` and `-00:00` all give one value, and so do `.5Z` and `.500Z`. "One way to do it" governs the API surface, the names a caller chooses among. B adds no name and no choice for the caller. It only widens the input language of a function whose job is to read external text.

**To sys and min on the workaround:** "A caller who has space-separated logs does one `replace` at the boundary". That workaround is not correct as written. `line.replace(" ", "T")` rewrites every space in the line, and on a field that is already isolated it still accepts junk such as `2026-02-14  12:00Z` → `TT`, which then fails with a misleading offset error. The correct patch is a slice at byte 10 plus a concat. That is exactly the hand-rolled, fragile code the ticket exists to remove, and it moves a grammar decision out of the spec and into every caller.

**The condition on my vote (answers my own Phase C concern):** the spec states the grammar as a closed production, for example `date-time = full-date ("T" / " ") full-time` with `time-offset = "Z" / ("+" / "-") hh ":" mm`. Uppercase only: no `t`/`z`, no comma fraction, no missing seconds, no second space. Anything outside the production is `ConversionError` with the byte offset (line 9). A later widening is then a spec change that needs a panel, not an implementation choice. I agree with web that the spec should say in one sentence that space input does not round-trip as text, in the same sentence as offset input.

STABLE, READY TO VOTE

##### devops
DevOps Phase D, Q3: I hold B (`T` or exactly one space). I adopt plt's closed grammar as part of my vote.

- **sys**: "A caller who has space-separated logs does one `replace` at the boundary, and that costs nothing next to the I/O."
  - The cost is not CPU. The cost is a bug that compiles fine.
  - In the benchmark shape, the obvious one-liner is `Instant.parse(line.replace(" ", "T"))`. That turns every space in the log line into `T`, so the parse fails at run time on a message that looked right. Doing it correctly takes a slice to the timestamp's width plus a replace on that slice, and the width changes with the fraction length.
  - A wrong one-liner that no diagnostic catches is exactly the surface I vote against.
- **sys**: "keeps the round-trip law exact". **min**: "A space adds a second form for one value."
  - plt answered the first point already: "The round-trip law is on values, and `Instant.parse("{i}") == Ok(i)` still holds because Display always writes `T`."
  - On min's point, line 3 already accepts many text forms for one value: `Z`, `+00:00` and `-05:00` with a shifted clock all parse to the same Instant. A space adds no new kind of non-canonical input.
  - The spec sentence for line 13 just widens: "offset or space input does not round-trip as text".
- **plt**: "The spec must list the grammar as closed." I agree, and it is the right guard against creep:
  - The separator is `T` or exactly one U+0020. Nothing else is accepted: no lowercase `t`/`z`, no comma fraction, no missing seconds, no two spaces.
  - Each rejected form gets its own byte-offset message, for example `invalid timestamp: expected 'T' or ' ' at byte 10 (found 't')`.
  - The tests check that message text word for word, so the closed list is enforced, not just documented.
- **web**: "the spec must say plainly that space input does not round-trip as text". Agreed. It belongs in the same sentence as the offset note.
- **Tooling footnote:** with either option, `line.split(" ").get(0)` on a space-separated log gives back only the date. That is the same under A and B, so it does not affect the vote. The `blink llms` time topic should show `line.slice(0, n)` in its log example.

STABLE, READY TO VOTE


#### Phase D — Re-vote on Q3: ballot

Phase D silent re-vote, pmpmyc, Q3 only. Vote on your own; do not message other panelists.

All six Phase D replies, verbatim:
(quoted in full in the section above)
Read it before you vote.

**Q3 — `Instant.parse` date/time separator**
- A: `T` only
- B: `T` or exactly one U+0020, with the grammar stated as closed in the spec (the condition plt, sys, min, aiml, devops and web attached to B)

Reply format (SendMessage to team-lead, one message):
- **Vote:** A or B
- **Reasoning:** 2–4 sentences from your domain
- **Concern:** one sentence on what could go wrong with the option that wins


#### Phase D — Re-vote on Q3: votes


##### web
- **Vote:** B
- **Reasoning:** Space-separated timestamps are the normal output of Postgres, Python's `str(datetime)` and many log formats, and RFC 3339 §5.6 allows them. With B the parser does the one correct check in one place. With A, every caller writes a `.replace` workaround that is easy to get wrong. Because the closed grammar is attached, B costs one byte comparison and gives no opening for more leniency.
- **Concern:** The spec and `blink llms` must state the closed grammar and the fact that space input does not round-trip as text. Otherwise readers will assume Display writes the form they passed in.

##### sys
- **Vote:** B
- **Reasoning:** Accepting the space adds one byte compare at a fixed offset. The parse stays fixed width and straight-line, with no allocation. The `.replace(" ", "T")` workaround that A forces allocates and copies every log line in the hot loop, and it changes the wrong bytes when a line holds more than one space. A closed grammar keeps the parser at a constant number of branches.
- **Concern:** An implementer may add more leniency later (`t`, `z`, a comma fraction) because "the parser already accepts a space". Tests must reject each form the spec does not list, so the grammar stays closed in code as well as in text.

##### aiml
- **Vote:** B
- **Reasoning:** With B, the obvious one-line call `Instant.parse(ts)` works on the log formats models meet most often: Postgres, Python `str(datetime)` and logging output. No failed first run is needed to discover a workaround. The workaround under A is also a silent-bug trap: `replace(" ", "T")` on a whole line changes every space, and a correct patch needs a slice plus a concat. The closed grammar keeps the input language a short fixed list that a model can learn from the spec alone, with no unstated leniency to guess at.
- **Concern:** devops's footnote applies under either option. On a log line with a space separator, models will write `line.split(" ").get(0)`, which keeps only the date. So the "input ends at byte 10" error must name the cause plainly, and the `blink llms` time example must show `line.slice(0, n)`. Otherwise B's gain is lost to the next trap one step earlier.

##### min
- **Vote:** B
- **Reasoning:** B adds no name and gives the caller no choice, so the language surface stays the same size. Option A would push a `.replace(" ", "T")` or slice-and-concat fix into every program that reads Postgres or Python logs. sys, web and plt showed that this fix is often wrong in ways that still compile: a replace on the whole line rewrites every space, and a `TT` turns into a misleading offset error. A closed grammar in the spec puts the one correct check in one place.
- **Concern:** If the closed grammar is written loosely in the spec, each later "just one more" leniency (lowercase `t`/`z`, comma fractions, missing seconds) will get in as an implementation choice and not go through a panel.

##### devops
- **Vote:** B
- **Reasoning:** Under A, the fix a user writes, `line.replace(" ", "T")`, compiles and then quietly breaks the log line. No diagnostic can catch that. B puts the one correct check in the parser, written once. The closed grammar (uppercase `T` or exactly one U+0020, nothing else) means each rejected form has one exact byte-offset message that a test can check word for word.
- **Concern:** the closed list only holds if the tests pin both the accepted forms and the rejection messages. If they don't, an implementation pass could quietly accept lowercase `t` or two spaces, and the spec would no longer match the compiler.

##### plt
- **Vote:** B
- **Reasoning:** Line 13 states the round-trip law on values, and B keeps it exact, because Display writes only `T`. Parse is already many-to-one under the approved line 3, so a second separator adds no new kind of non-canonical input. With the grammar stated as a closed production, the input language is fixed and checkable. That is sounder than pushing an unchecked `replace`/slice patch into every caller, because that patch is wrong when written naively.
- **Concern:** devops' footnote: once space-separated stamps parse, the natural idiom `line.split(" ").get(0)` returns only the date, which then fails with a correct but surprising error. The `blink llms` time example and the error text must show slicing the fixed-width timestamp, or B's gain is lost to a new idiom bug.

##### Tally
Q3 B 6-0 (R2, after 4-2 R1; sys and min switched)


#### Edge round — exact first and last Date: brief

Focused round, pmpmyc: the exact first and last valid Date. The user approved the tally and sent this one question back to the panel. All other questions are closed. Do not reopen them.

##### Facts (computed with `date -u` on the Int64 nanosecond domain)
- The earliest Instant is 1677-09-21T00:12:43.145224192Z. The latest is 2262-04-11T23:47:16.854775807Z.
- Midnight UTC on 1677-09-21 is BEFORE the earliest Instant. Midnight UTC on 2262-04-11 is inside the domain.
- Approved Q6 line 2: `instant.date() -> Date`. For every Instant from 1677-09-21T00:12:43.145224192Z to 1677-09-21T23:59:59.999999999Z it gives the date 1677-09-21.
- Approved Q6 line 7: `Date.to_instant() -> Instant` at 00:00:00Z, total.
- Approved Q6 line 8: one range for the module; values outside the Instant domain are rejected.
- Lines 2, 7 and 8 cannot all hold for the date 1677-09-21. The upper edge has no such conflict.

##### Your Phase C concern on record (plt, verbatim)
"line 8's lower bound (1677-09-21) is not a whole day of Instant nanos. The spec must give the exact first and last valid Date, so that `Date.to_instant()` is total on every value `Date.from_ymd` accepts. The bound should be checked as a property test, not prose."

##### What to send back (SendMessage to team-lead, one message)
- Your proposal: the exact first and last valid Date, and what each of `instant.date()`, `Date.to_instant()`, `Date.from_ymd`, `Date.parse` and `add_days` does at the lower edge.
- Reasoning from your domain, 2–4 sentences.
- A short Blink example if it helps.
Do not message other panelists. A digest of all six proposals and a silent vote follow.


#### Edge round: proposals


##### web
WEB/SCRIPTING, edge round for pmpmyc: the first valid Date is 1677-09-22 and the last is 2262-04-11, both inclusive. Every Date that a user can build converts to an Instant. Only `instant.date()` can fail, and only for the partial first day of the Instant domain.

**Behaviour at the lower edge:**
- `Date.from_ymd(1677, 9, 21)` gives `Err(ConversionError)`. The message names the range: "date 1677-09-21 out of range 1677-09-22..2262-04-11".
- `Date.parse("1677-09-21")` gives the same Err with the same text, with the byte offset of the year.
- `Date.from_ymd(1677, 9, 22)` gives Ok. Its `to_instant()` is 1677-09-22T00:00:00Z, which is inside the domain. `to_instant()` stays total on every Date that exists (line 7 holds).
- `d.add_days(n)`: when the result would be before 1677-09-22 or after 2262-04-11, it panics, the same as Int overflow. That is the approved line 6 rule, with the edge now stated exactly.
- `instant.date()` panics for any Instant from 1677-09-21T00:12:43.145224192Z to 1677-09-21T23:59:59.999999999Z. The panic message names the range, the same overflow class as `add_days`. For every other Instant it is total. The upper edge has no gap: every Instant on 2262-04-11 gives that Date.

```blink
let first = Date.from_ymd(1677, 9, 22)?          // Ok
let t = first.to_instant()                        // 1677-09-22T00:00:00Z, never panics
let bad = Date.from_ymd(1677, 9, 21)              // Err: out of range 1677-09-22..2262-04-11
// spec property test: for every d that from_ymd accepts,
// d.to_instant().date() == d, and Date.parse("{d}") == Ok(d)
```

**Reasoning:**
- People build Dates from literals and user input all the time (`from_ymd`, `parse`), and the Err there is visible and handled with `?`.
- No one reaches an Instant in the first 24 hours of 1677 except by overflowing arithmetic, and Blink already treats overflow as a panic.
- So the one partial spot goes where real code never goes, and the type a dev uses every day keeps both directions safe. The other way round, admitting 1677-09-21 and letting its `to_instant()` panic, puts the trap on a value that `from_ymd` just told the user was valid. That is the kind of "it said Ok, then it crashed" surprise that produces bug reports.

**Spec text:** state the range once, as an inclusive pair, in the std.time section. State the property test above as the law. Line 8's "one range for the module" then reads as "the Date range is 1677-09-22..=2262-04-11; Instant keeps its own Int64 domain".

##### aiml
AI/ML edge round, pmpmyc: I propose 1677-09-22 as the first valid Date and 2262-04-11 as the last. The range holds only whole days, so line 7 stays total, and the 12-hour piece of day before it is treated like Int overflow.

**The range.** The first valid Date is 1677-09-22. The last valid Date is 2262-04-11. Both ends are included. Every Date in this range has its midnight inside the Instant domain.

**At the lower edge:**
- **`Date.from_ymd(1677, 9, 21)`:** `Err(ConversionError)`. The message is "date 1677-09-21 out of range 1677-09-22..2262-04-11".
- **`Date.parse("1677-09-21")`:** the same Err and message, with the byte offset 0.
- **`Date.to_instant()`:** total on every Date, as line 7 approves. The earliest result is 1677-09-22T00:00:00Z.
- **`add_days`:** a step below 1677-09-22 or above 2262-04-11 panics with the same range text. This is the overflow class that line 6 already approves.
- **`instant.date()`:** panics for an Instant before 1677-09-22T00:00:00Z, with the same range text. This covers the sliver from 1677-09-21T00:12:43.145224192Z to 23:59:59.999999999Z.
- **`Instant.parse`:** under line 8's "one range for the module", it rejects text before 1677-09-22T00:00:00Z with `Err`. So the sliver cannot come from parse. It can only come from `Instant.from_epoch_secs` or from `.add` arithmetic at the very edge of Int64. Both are already overflow cases.

**Reasoning (AI/ML).**
- A model learns one closed range, stated as two dates in Display form. Every out-of-range error prints that same range text, so the error alone teaches the fix.
- Each other choice has to put in a special case. One way is a `to_instant` that lies or fails for one date. Another is a Date range that does not match `to_instant`, so a model reading the spec must remember "all dates except one".
- The only cost is a panic on an input that `time.read()`, `Instant.parse` and benchmark code never produce. That panic is in the same class as `add_days` overflow, which the panel already approved, so no new kind of failure enters the spec.
- I agree with plt that the spec states this as a property test: for every Date `d` in the range, `d.to_instant().date() == d`. Add edge rows for 1677-09-22, 2262-04-11, and both values just outside.

```blink
let first = Date.from_ymd(1677, 9, 22).unwrap()
assert_eq(first.to_instant().date(), first)
assert(Date.from_ymd(1677, 9, 21).is_err())   // "out of range 1677-09-22..2262-04-11"
assert(Instant.parse("1677-09-21T12:00:00Z").is_err())
```

##### min
MINIMALISM, edge round on pmpmyc. In short: the Date range is 1677-09-22 ..= 2262-04-11, there are no new types or Results, and the partial first day goes through the overflow rule that line 6 already approved.

**Proposal: the valid Dates are exactly the days whose UTC midnight is an Instant.**
- First valid Date: **1677-09-22**. Last valid Date: **2262-04-11**.
- The module range in line 8 becomes whole days at the lower edge: **1677-09-22T00:00:00Z ..= 2262-04-11T23:47:16.854775807Z**. Every parser checks against this one range.

At the lower edge:
- **`Date.from_ymd(1677, 9, 21)` / `Date.parse("1677-09-21")`** return `Err(ConversionError)` with the "out of range" cause from line 9. `1677-09-22` is `Ok`.
- **`Instant.parse`** rejects any text before 1677-09-22T00:00:00Z, also with "out of range". The parsers then share one range, as line 8 asks.
- **`Date.to_instant()`** is total on every Date that can exist, so line 7 holds with no change.
- **`add_days`**: going past either end panics, the same as Int overflow (line 6). So `Date.from_ymd(1677, 9, 22)?.add_days(-1)` panics.
- **`instant.date()`** keeps its signature `-> Date`. For an Instant from 1677-09-21T00:12:43.145224192Z up to 1677-09-21T23:59:59.999999999Z, it panics with the same overflow rule as `add_days`. An Instant in that window cannot come from any parser. Only raw arithmetic near the Int64 minimum can make one (`Instant.add`, `from_epoch_secs`).

**Reasoning.** The three options:
- A `Result` on `.date()` or `.to_instant()` would make every caller write `?` or `.unwrap()`. That would serve a window of about 24 hours at one end of a 584-year domain.
- A clamp hides the error.
- A wider internal Date range makes `to_instant()` partial.

My option adds no type, no `Result` and no new rule: the partial day goes through the overflow panic that line 6 already approved. Every value any parser or constructor accepts stays inside one whole-day range, so the spec states one range, not two.

**Property test** (as plt asked):
- For every Date d from 1677-09-22 to 2262-04-11: `d.to_instant().date() == d`.
- `Date.from_ymd(1677, 9, 21)` is `Err` and `Date.from_ymd(1677, 9, 22)` is `Ok`.
- `Date.from_ymd(2262, 4, 12)` is `Err` and `Date.from_ymd(2262, 4, 11)` is `Ok`.
- `Instant.parse("1677-09-21T23:59:59Z")` is `Err`.

```blink
let first = Date.from_ymd(1677, 9, 22).unwrap()
assert_eq(first.to_instant().date(), first)              // total round trip
assert(Date.from_ymd(1677, 9, 21).is_err())              // out of range
assert(Instant.parse("1677-09-21T23:59:59Z").is_err())   // same module range
```

##### sys
SYSTEMS, edge round: the first valid Date is 1677-09-21 and the last is 2262-04-11. `Date.to_instant()` gives the EARLIEST Instant whose `date()` is that Date. That is 00:00:00Z on every date except 1677-09-21, where it is the Instant minimum.

###### Proposal
- **Range:** Date holds day numbers from -106752 (1677-09-21) to 106751 (2262-04-11). These are `floor(i64::MIN / 86_400e9)` and `floor(i64::MAX / 86_400e9)`, so every Instant maps to a Date in range and every Date in range holds at least one Instant.
- **`instant.date()`:** total. Instants from 1677-09-21T00:12:43.145224192Z to the end of that day give 1677-09-21 (approved line 2, unchanged).
- **`Date.to_instant()`:** total. It is defined as "the first Instant on this date": `max(days * 86_400e9, Instant minimum)`. The multiply cannot overflow for any day in range when it is done in i128, or when the check is `if days == -106752` before the multiply. On 1677-09-21 it gives 1677-09-21T00:12:43.145224192Z. On every other date it gives 00:00:00Z, so line 7 stays true wherever a midnight exists.
- **`Date.from_ymd`, `Date.parse`:** accept 1677-09-21..2262-04-11 and give `Err(ConversionError)` with the cause "date out of range 1677-09-21..2262-04-11" outside it.
- **`add_days`:** a result inside the range is fine. Below 1677-09-21 or above 2262-04-11 it panics (approved line 6). Here the panic is an explicit range check, not an i64 overflow, because a day count never overflows i64.

```blink
let first = Date.from_ymd(1677, 9, 21)?              // Ok
let bad = Date.from_ymd(1677, 9, 20)                 // Err: date out of range 1677-09-21..2262-04-11
let i = first.to_instant()                           // 1677-09-21T00:12:43.145224192Z (no midnight exists)
assert_eq(i.date(), first)
let next = first.add_days(1).to_instant()            // 1677-09-22T00:00:00Z
// first.add_days(-1)                                // panics: date out of range
```

###### Laws for the property test (plt's request)
1. For every Date d in range: `d.to_instant().date() == d`. This holds at both edges, and it is the law that the plain "midnight" rule breaks at the lower edge.
2. For every Instant i: `i.date().to_instant() <= i`, and `i.date().add_days(1)`, when in range, has `to_instant() > i`.
3. `Date.from_ymd` accepts exactly the days for which law 1 can be checked, and the tests call it at -106752, -106753, 106751 and 106752.

###### Reasoning
This keeps all three approved lines total with one compare, a branch that is almost never taken and that gcc turns into a cmov. There is no Result on the hot path and no hole in the type. Ruling out 1677-09-21 instead would make `instant.date()` partial for real Instants (`Instant.from_epoch_secs` and `add` reach them), and that moves the problem from a constructor that already returns a Result to an accessor that must never fail. A clamped first day is the honest answer, because the Instant domain starts partway through that day. "The first Instant of the day" is exact on both edges and equal to "midnight" everywhere else.

Spec text: "`Date.to_instant()` gives the first Instant on that date: 00:00:00Z, except on 1677-09-21, where it gives the Instant minimum, 1677-09-21T00:12:43.145224192Z."

##### plt
PLT, pmpmyc edge round: exact first and last valid Date.

###### Proposal
**Date domain = the days whose UTC midnight is an Instant: 1677-09-22 through 2262-04-11.** As days since 1970-01-01 that is exactly [-106751, 106751], a range that is symmetric about the epoch. (MIN nanos floors to day -106752 = 1677-09-21, whose midnight is outside the domain. MAX nanos floors to day 106751 = 2262-04-11, whose midnight is inside.)

At the lower edge:
- `Date.from_ymd(1677, 9, 21)` → `Err(ConversionError)`, cause "out of range". `Date.from_ymd(1677, 9, 22)` → `Ok`.
- `Date.parse("1677-09-21")` → `Err(ConversionError)`, cause "out of range" (byte offset 0, the start of the value).
- `add_days`: a result before 1677-09-22 (or after 2262-04-11) panics, the same class as Int overflow (line 6 unchanged).
- `Date.to_instant()`: total and exact. Every Date maps to its own 00:00:00Z, and the first Date maps to 1677-09-22T00:00:00Z. Line 7 holds with no exception.
- `instant.date()`: panics for an Instant before 1677-09-22T00:00:00Z, the first 23h 47m 16.85…s of the Instant domain, as overflow does. It is total on every other Instant. Its spec line states the precondition. `Instant.parse` keeps the full Instant domain: line 8's "one range" is read as the Date range for Date constructors and the Instant range for Instant constructors.
- Upper edge: no special case. `instant.date()` on any 2262-04-11 Instant gives 2262-04-11, and `add_days(1)` from it panics.

###### Reasoning
There are three ways out, and each breaks one law. I pick the one whose failure is loud and unreachable in practice:
- **Keep 1677-09-21 and clamp `to_instant` to MIN.** This keeps every function total, and the floor law `d.to_instant() <= i ⟺ d <= i.date()` even survives. But "at 00:00:00Z" becomes false for one day, so the approved composition `d.to_instant().add(Duration.hours(9))` silently returns 09:12:43. A silent wrong value is worse than a panic.
- **Keep 1677-09-21 and make `to_instant` return a Result.** This puts a Result on the common path for one unreachable day, and it breaks line 7.
- **Drop 1677-09-21 (my proposal).** Partiality moves to `instant.date()` on 23h47m of Instants that only `from_epoch_secs`, `add` or `parse` of 1677 text can produce, never `time.read()`. It fails as a panic in the same class as `add_days` overflow, which the panel already accepted in line 6.

###### Laws for the property tests (spec lists them; tests check them at the edges and randomly)
```blink
// for every Date d in [1677-09-22, 2262-04-11]:
d.to_instant().date() == d
Date.parse("{d}") == Ok(d)
// for every Instant i >= 1677-09-22T00:00:00Z:
i.date().to_instant() <= i
// and, when i.date() < 2262-04-11:
i < i.date().add_days(1).to_instant()
// edges, exact:
Date.from_ymd(1677, 9, 22).unwrap().to_instant() == Instant.parse("1677-09-22T00:00:00Z").unwrap()
Date.from_ymd(1677, 9, 21).is_err()
Date.from_ymd(2262, 4, 12).is_err()
```
I add no public `Date.MIN`/`Date.MAX` constants: the bundle is closed, and the spec states the two dates in prose plus these tests.

##### devops
DevOps edge proposal, pmpmyc: the first valid Date is 1677-09-22 and the last is 2262-04-11. The module's one range (line 8) starts on a whole day, so it is 1677-09-22T00:00:00Z ..= 2262-04-11T23:47:16.854775807Z for Instant and 1677-09-22 ..= 2262-04-11 for Date. The 23 h 47 m of 1677-09-21 that Int64 can hold are outside the range of std.time.

Behavior at the lower edge:
- `instant.date()`: total, as line 2 says. No in-range Instant falls on 1677-09-21, so it never has to produce that date.
- `Date.to_instant()`: total, as line 7 says. `Date 1677-09-22` gives `1677-09-22T00:00:00Z`, which is the first Instant in the range.
- `Date.from_ymd(1677, 9, 21)`: `Err(ConversionError)` with the message `invalid date: 1677-09-21 outside 1677-09-22..2262-04-11`.
- `Date.parse("1677-09-21")`: the same error and the same text. This is a range error, so it names the range instead of a byte offset.
- `add_days`: going past either edge panics, the same as Int overflow (line 6). The panic message names the same range.
- To keep line 2 total, the Instant constructors apply the same lower edge:
  - `Instant.parse("1677-09-21T12:00:00Z")` gives `Err` with `invalid timestamp: 1677-09-21T12:00:00Z outside 1677-09-22T00:00:00Z..2262-04-11T23:47:16.854775807Z`.
  - `Instant.add` and `Instant.from_epoch_secs` panic outside the range. That closes the unchecked multiply in `from_epoch_secs` that I flagged in round 1.

Reasoning:
- This keeps the rule we voted in sub-question 5: reject at construction, so every conversion stays total. The other ways out each put a hard-to-read failure in a method users call all the time:
  - `instant.date()` would need to return an Option, and that unwrap noise lands on every call.
  - `instant.date()` could panic on a valid Instant.
  - `to_instant()` could clamp, which returns a value that is not the midnight the docs promise.
- The cost is one comparison in `Instant.add` and the loss of about 24 hours in the year 1677, a span no real program reads.
- For tooling, every edge failure gets one message that names one range. The `blink llms` time topic and the hover docs can state that range in one line: "std.time covers 1677-09-22 through 2262-04-11 UTC".

Property tests (plt's concern: tests, not prose):

```blink
test "Date range edges are exact" {
    let first = Date.from_ymd(1677, 9, 22).unwrap()
    let last = Date.from_ymd(2262, 4, 11).unwrap()
    assert_eq(first.to_instant().date(), first)
    assert_eq(last.to_instant().date(), last)
    assert(Date.from_ymd(1677, 9, 21).is_err())
    assert(Date.from_ymd(2262, 4, 12).is_err())
    assert(Date.parse("1677-09-21").is_err())
    assert(Instant.parse("1677-09-21T23:59:59Z").is_err())
    assert_panics(fn() { first.add_days(-1) })
    assert_panics(fn() { last.add_days(1) })
}
```

To that we add a sweep with a fixed seed over random days in the range, checking `d.to_instant().date() == d` and `d.add_days(n).days_since(d) == n`.


#### Edge round: debate digest

Edge round, debate, pmpmyc: the exact first and last valid Date.

All six proposals, verbatim:
(quoted in full in the section above)
Read the whole file before you reply.

##### Mechanical dedupe (grouping only; labels cite who proposed each)
- **E1 — Date range 1677-09-22 ..= 2262-04-11.** `Date.to_instant()` is midnight UTC and total. `from_ymd`/`parse` reject 1677-09-21 with Err; `add_days` panics past either end. Proposed by web, aiml, min, plt, devops. The proposals differ on what happens to Instants on 1677-09-21:
  - **E1a** — Instant keeps the full Int64 domain. `Instant.parse` accepts the whole domain. `instant.date()` panics for an Instant before 1677-09-22T00:00:00Z. (web, plt)
  - **E1b** — `Instant.parse` rejects text before 1677-09-22T00:00:00Z with Err. `instant.date()` panics for an Instant before 1677-09-22T00:00:00Z (reachable only through `from_epoch_secs` / `add`). (aiml, min)
  - **E1c** — The std.time Instant range starts at 1677-09-22T00:00:00Z. `Instant.parse` rejects text before it with Err; `Instant.add` and `Instant.from_epoch_secs` panic outside it. `instant.date()` stays total. (devops)
- **E2 — Date range 1677-09-21 ..= 2262-04-11.** `instant.date()` total. `Date.to_instant()` total, defined as the first Instant on the date: 00:00:00Z on every date except 1677-09-21, where it is 1677-09-21T00:12:43.145224192Z. (sys)

##### What to send back (SendMessage to team-lead, one message)
- Your position. You may change your proposal; say so if you do.
- Responses to other panelists' arguments: name the panelist and quote the line you answer.
- End with exactly one of: `STABLE, READY TO VOTE` or `NOT STABLE: <what is still open>`.
A silent vote follows.


#### Edge round: debate replies


##### sys
SYSTEMS, edge debate: I drop E2 and back E1c (the std.time Instant range starts at 1677-09-22T00:00:00Z). E1b is my second choice and E1a my third.

###### Why I drop E2
Plt says: "'at 00:00:00Z' becomes false for one day, so the approved composition `d.to_instant().add(Duration.hours(9))` silently returns 09:12:43. A silent wrong value is worse than a panic." That is right, and my laws did not catch it. Law 1 (`d.to_instant().date() == d`) holds while the time-of-day result is wrong. A clamp keeps every function total by giving a wrong answer. Min's line, "A clamp hides the error", says the same.

###### Why E1c over E1a/E1b: the check is already paid for
Blink panics on Int overflow, so `Instant.add` and `from_epoch_secs` must already compare against the i64 limits (an overflow-flag branch, or a compare against `i64::MIN / 1e9` for the multiply). E1c only changes the lower constant in a check that exists, so its cost is zero. E1a and E1b add a new branch to `instant.date()`, and that is the accessor the benchmark calls on every log line. With E1c, `date()` stays a branch-free floor-div. In each case one compare sits somewhere, and E1c puts it on the path that already has one.

E1c is also the only option where line 8 means what it says: one range, for Instant and Date alike, checked only at construction ("reject at construction, so every conversion stays total", devops). With E1a and E1b, an Instant can exist that no conversion accepts. That is a hole in a type that E1c closes.

###### Responses
- **Web:** "No one reaches an Instant in the first 24 hours of 1677 except by overflowing arithmetic." Agreed, and that is the case for E1c. If only arithmetic reaches it, the panic belongs in the arithmetic (`add`, `from_epoch_secs`), where an overflow panic already lives, and not in `date()`, which then has to carry a precondition in its spec line.
- **Plt:** "`Instant.parse` keeps the full Instant domain." Then `Instant.parse("1677-09-21T12:00:00Z")?.date()` parses Ok and panics on the next call. That is the "it said Ok, then it crashed" trap that web warns about, moved from Date to Instant. E1b and E1c both close it, and only E1c closes it for `add` too.
- **Devops:** "That closes the unchecked multiply in `from_epoch_secs`." Yes. The bug I flagged in round 1 gets fixed as part of this decision, not as a separate ticket that can be dropped.
- **Constraint check:** E1c narrows the Instant domain by under 24 hours. It changes no representation, Display, method or trait from decided constraint 1. `time.read()` and `mock_clock` cannot produce a 1677 value, so they need no change. `Instant.since` returns a Duration and needs no new check.

Property tests: as devops wrote them, plus `assert_panics(fn() { Instant.from_epoch_secs(<first second before 1677-09-22>) })` and the same for `add` one nanosecond below the edge.

STABLE, READY TO VOTE

##### web
WEB/SCRIPTING, edge debate: I move from E1a to E1b. The Date range stays 1677-09-22 ..= 2262-04-11. `Instant.parse` now rejects text before 1677-09-22T00:00:00Z with Err, and `instant.date()` panics only for Instants that came from raw arithmetic. My ranking is E1b > E1c > E1a > E2.

**Why I changed.** My own argument against E2 was "it said Ok, then it crashed". Under E1a, which I proposed, that same trap sits on the parse path: `Instant.parse("1677-09-21T12:00:00Z")?.date()` gives Ok from the parser and then panics on `.date()`. Parse is where user input comes in, so the error belongs there, as a Result the user handles with `?`. E1b does that. It also matches line 8 ("one range for the module") as written, so every parser checks against one whole-day range.

**To plt:** "`Instant.parse` keeps the full Instant domain: line 8's 'one range' is read as the Date range for Date constructors and the Instant range for Instant constructors." That makes two ranges for a reader to learn, and it leaves the one gap reachable from text. aiml's point stands: a model learns one closed range from one error message. I agree with plt's rejection of the clamp, quoted next.

**To sys:** "A clamped first day is the honest answer." plt answers it: the approved composition `d.to_instant().add(Duration.hours(9))` "silently returns 09:12:43". To a JS/Python dev, a value that is wrong with no error is the worst kind of bug, because it reaches production. sys also says ruling out 1677-09-21 "would make `instant.date()` partial for real Instants (`Instant.from_epoch_secs` and `add` reach them)". Under E1b, only edge-of-Int64 arithmetic reaches them, which is already overflow territory. No program that reads a clock or parses a log does.

**To devops (E1c):** "`Instant.add` and `Instant.from_epoch_secs` panic outside the range." That keeps `.date()` total, and it is a fine second choice. But it changes the closed `Instant` contract (Int64 nanos, an approved earlier decision) and adds a range check on every `Instant.add` to guard a day no one reads. E1b gets the same user-facing result: every value from a parser or a Date constructor works both ways, and `Instant` keeps its arithmetic. devops' error-text format ("outside 1677-09-22..2262-04-11") should be the shared message for all edge failures. That part of E1c I take whole.

**Property tests:** min's and aiml's edge rows plus plt's laws, including `Instant.parse("1677-09-21T23:59:59Z").is_err()`.

STABLE, READY TO VOTE

##### plt
PLT, pmpmyc edge debate. I CHANGE from E1a to E1c (devops). My ranking is E1c > E2 > E1b > E1a.

**Why I move.** My Phase A rule 3 was "Partial at the edge, total inside": failures belong to constructors, and every conversion between sorts is total. E1a, my own edge proposal, broke that rule. It made `instant.date()`, a conversion, partial. E1c is the only option that meets the rule in full. The std.time domain becomes one whole-day interval, [1677-09-22T00:00:00Z, 2262-04-11T23:47:16.854775807Z]. Every constructor (`Instant.parse`, `from_epoch_secs`, `add`, `Date.from_ymd`, `Date.parse`, `add_days`) checks against it. Lines 2 and 7 are then total with no exception, and line 7 keeps its approved meaning (midnight).

**To sys:** "Ruling out 1677-09-21 instead would make `instant.date()` partial for real Instants (`Instant.from_epoch_secs` and `add` reach them)". Correct against E1a and E1b, and I concede it: that is the hole in my proposal. E1c answers it by removing those Instants from the domain, so the accessor stays total.

**To sys:** "A clamped first day is the honest answer". E2 is principled, and I rank it second. "The first Instant on this date" is exactly the left adjoint of `date()` (the least i with i.date() == d). With it, `d.to_instant() <= i ⟺ d <= i.date()` holds everywhere, as does law 1. But it changes approved line 7 from "at 00:00:00Z" to "first Instant on the date". The approved composition `d.to_instant().add(Duration.hours(9))` then returns 09:12:43 on one day with no signal. E1c keeps both the adjunction and the midnight meaning, because on a whole-day domain the least Instant of each date IS its midnight.

**To web:** "Instant keeps its own Int64 domain". That gives the module two ranges and puts the gap inside a conversion, which is the "it said Ok, then it crashed" surprise web warns against, only moved to `.date()`. I withdraw that reading of line 8.

**To aiml and min (E1b):** "So the sliver cannot come from parse. It can only come from `Instant.from_epoch_secs` or from `.add`". This closes the text path but leaves `date()` partial through arithmetic. Once parse checks the range, applying the same check in `add` and `from_epoch_secs` costs one compare, and it removes the last partial case.

**To devops:** E1c needs two things in the spec, or it is incomplete:
1. 03_types.md's Instant paragraph states the domain as that exact closed interval, and states that `Instant.add` and `Instant.from_epoch_secs` panic outside it. This is the same overflow class as Int and as line 6, so it is no new kind of failure. It also fixes the unchecked `s * 1000000000` today.
2. The property tests cover Instant too: `Instant.parse("1677-09-21T23:59:59Z").is_err()`, the min Instant `.date()` == 1677-09-22, and `assert_panics` for `add` one nanosecond below the min.

`since` and Duration are unchanged, since a Duration between two in-range Instants always fits in Int.

STABLE, READY TO VOTE

###### plt correction (separate message)
PLT correction to my edge debate reply. One line in it is wrong: "a Duration between two in-range Instants always fits in Int". The domain spans almost 2^64 nanos, so `max.since(min)` overflows Int. That is the same as today with the full Int64 domain, and it panics as Int overflow does. E1c neither causes this nor fixes it, so my position does not change: E1c > E2 > E1b > E1a, STABLE, READY TO VOTE.

##### aiml
AI/ML edge debate, pmpmyc: I CHANGE from E1b to E1c (devops). E1b is my second choice, then E1a. I vote against E2.

**Why I change.** E1b and E1c agree on every Date. They differ only on the 23h47m of 1677-09-21 Instants:
- E1b leaves those Instants constructible and makes `instant.date()` panic on them.
- E1c makes them unconstructible, so `instant.date()` stays total, as line 2 approved.

For a model learning from the spec, E1c is the only option that fits in one sentence with no exception: "std.time covers 1677-09-22 through 2262-04-11 UTC", as devops wrote it. Every type, constructor and error message then states the same range. With E1b, a model must also learn "`.date()` is total except for Instants that `.add` can still reach". No benchmark task hits that clause, but it is a second rule that every spec reader must hold.

**Responses:**
- **sys:** "Ruling out 1677-09-21 instead would make `instant.date()` partial for real Instants (`Instant.from_epoch_secs` and `add` reach them)."
  - That is right against E1a and E1b, which is why I leave E1b.
  - E1c answers it at the source: `from_epoch_secs` and `add` panic before such an Instant exists. That is the same "reject at construction" rule the panel voted in sub-question 5.
  - On cost: `Instant.add` near the Int64 edge already overflows, so the check only moves that edge by one day. `time.read()` never reaches it.
- **sys, E2:** "`Date.to_instant()` gives the first Instant on that date: 00:00:00Z, except on 1677-09-21."
  - plt names the danger: "`d.to_instant().add(Duration.hours(9))` silently returns 09:12:43."
  - From my domain: models learn the rule "to_instant is midnight" and never the exception, so E2 turns a law with one exception into a silent wrong value in generated code.
- **plt:** "line 8's 'one range' is read as the Date range for Date constructors and the Instant range for Instant constructors."
  - That reading gives the module two ranges that differ by 23h47m, which is what line 8 was approved to prevent. The error texts would then name two different lower edges.
- **web:** "Instant keeps its own Int64 domain."
  - Same answer. web's own reason ("the one partial spot goes where real code never goes") argues just as well for removing the spot as for keeping it and panicking on it. E1c removes it.
- **min:** "My option adds no type, no `Result` and no new rule."
  - E1c also adds none. It only moves min's whole-day parse range onto `from_epoch_secs` and `add`, so the range in min's own line 8 rewrite ("1677-09-22T00:00:00Z ..= 2262-04-11T23:47:16.854775807Z") becomes the domain of Instant, not only the domain of its parser.

**Conditions I keep from my proposal:**
- One message that names the range, used by every Err and every panic.
- The property laws from plt and devops, with edge rows at both ends and the value just outside each end. Add `assert_panics` rows for `Instant.from_epoch_secs` and `Instant.add` just below 1677-09-22T00:00:00Z.

STABLE, READY TO VOTE

##### min
MINIMALISM, edge round debate. I CHANGE my position from E1b to E1c (devops). E1b is my second choice. I vote against E1a and E2.

**Why I changed.** E1c is the only option where std.time has one range and every accessor is total. All the partiality sits on the two operations that can already fail by overflow: `Instant.add` and `Instant.from_epoch_secs`. Those two already panic at the Int64 bounds. E1c moves that bound by 23 h 47 m, so it adds no new kind of failure. Under E1b, `.date()` still has a hidden precondition that the spec must state and that a reader must remember.

**Responses:**
- **To sys:** "Ruling out 1677-09-21 instead would make `instant.date()` partial for real Instants (`Instant.from_epoch_secs` and `add` reach them)." That is right about E1a and E1b, my own Phase-A option included. E1c answers it: those Instants stop being values, because the operations that would make them panic first. sys's E2 keeps all functions total, but only through an exception sentence ("except on 1677-09-21"). That is one more rule in the spec, and as plt shows, it makes `d.to_instant().add(Duration.hours(9))` silently give 09:12:43 on that day. One special-case sentence for one day out of 213,503 is the wrong place to spend spec text.
- **To plt:** "line 8's 'one range' is read as the Date range for Date constructors and the Instant range for Instant constructors." That is two ranges. It reverses line 8, which passed 6-0. It also means `Instant.parse("1677-09-21T12:00:00Z")` gives `Ok` and then a panic on `.date()`, which is web's "it said Ok, then it crashed" surprise moved from Date to Instant.
- **To web:** "the one partial spot goes where real code never goes". I agree on the reachability, but E1a still makes a parser hand out a value that one accessor cannot handle. E1c puts the failure at construction, which is where sub-question 5 put it.
- **To devops:** "The cost is one comparison in `Instant.add`". I accept that cost. `add` needs an overflow check at that point already, so this is the same check with a different constant.
- **To aiml:** E1b, which we shared, is still acceptable. Its only weakness is that `.date()` panics on an Instant that `from_epoch_secs` gave back without error. E1c removes that last trap at the same price.

**What the spec must say under E1c:** "std.time covers 1677-09-22T00:00:00Z through 2262-04-11T23:47:16.854775807Z. `Instant.parse`, `Date.from_ymd` and `Date.parse` return Err outside this range. `Instant.add`, `Instant.from_epoch_secs` and `Date.add_days` panic outside it." That is one range, stated once, plus devops's property test.

STABLE, READY TO VOTE

##### devops
DevOps edge debate, pmpmyc: I hold E1c, with E1b as my second choice. I reject E1a and E2. The question between the E1 variants is where the panic fires. For tooling, it must fire where the bad value is made, not where someone reads it later.

- **To min**: "Only raw arithmetic near the Int64 minimum can make one (`Instant.add`, `from_epoch_secs`)." **To aiml**: "Both are already overflow cases."
  - Under E1b they are not overflow cases. `Instant.add` returns Ok on 1677-09-21T05:00Z, and the panic waits until some later `.date()` call, possibly in another module or another request. The stack trace then points at a date accessor, and the message talks about a date range, while the bug was the `add` or `from_epoch_secs` call.
  - E1c panics at the call that left the range, with the same range text. That is the line the user has to fix.
  - `from_epoch_secs` needs a check anyway: today `s * 1000000000` is unchecked. E1c makes that one check the range check.
- **To sys**: "Ruling out 1677-09-21 instead would make `instant.date()` partial for real Instants (`Instant.from_epoch_secs` and `add` reach them)."
  - Agreed, under E1a and E1b. That is the reason for E1c. Once the constructors close the range, no such Instant exists, and `.date()` stays total as line 2 says.
  - The cost is one compare in `Instant.add`, and that compare replaces the overflow check line 6 already assumes.
- **To sys**: "A clamped first day is the honest answer."
  - plt answered this: "`d.to_instant().add(Duration.hours(9))` silently returns 09:12:43. A silent wrong value is worse than a panic."
  - From the tooling side, a silent wrong value has no diagnostic at all, not even a late one. E2 also puts an "except on 1677-09-21" clause into the `to_instant()` hover doc for every user, to serve a day nobody reads.
- **To plt and web (E1a)**: "`Instant.parse` keeps the full Instant domain".
  - Then `Instant.parse("1677-09-21T12:00:00Z")` returns `Ok`, and `.date()` on that result panics.
  - web's own line argues against this: "That is the kind of 'it said Ok, then it crashed' surprise that produces bug reports." E1a does that to Instant.
  - It also gives the module two ranges to document instead of one. Line 8 says "one range for the module".
- **To web**: "with the byte offset of the year". For a range error I would leave out the byte offset. The whole value is out of range, so the message should name the range, as in `invalid date: 1677-09-21 outside 1677-09-22..2262-04-11`. plt and aiml give offset 0. I can accept offset 0 if the panel wants every ConversionError to carry one, but the range text must be the same in every Err and every panic message.

All five E1 proposals already agree on the Date range (1677-09-22 ..= 2262-04-11), on `to_instant()` being total at midnight, on `from_ymd`/`parse` returning Err, and on `add_days` panicking. Only the Instant-side placement is open, and the ballot can ask that as a three-way choice: E1a, E1b or E1c.

STABLE, READY TO VOTE


#### Edge round: ballot

Edge round, silent vote, pmpmyc. Vote alone. Do not message other panelists. All other questions are closed.

All six debate replies ended STABLE, READY TO VOTE. All five E1 options share: Date range 1677-09-22 ..= 2262-04-11; `Date.to_instant()` total at 00:00:00Z; `Date.from_ymd` / `Date.parse` return Err outside the range; `add_days` panics outside it.

##### EQ1: lower edge on the Instant side
- **E1a** (plt, web in the proposal round): Instant keeps the full Int64 domain; `instant.date()` panics before 1677-09-22T00:00:00Z.
- **E1b** (aiml, min in the proposal round): `Instant.parse` returns Err for text before 1677-09-22T00:00:00Z; `instant.date()` panics for the sliver that `from_epoch_secs` or `add` can still reach.
- **E1c** (devops): the std.time Instant range starts at 1677-09-22T00:00:00Z; `Instant.parse` returns Err outside it; `Instant.add` and `Instant.from_epoch_secs` panic outside it; `instant.date()` stays total.
- **E2** (sys in the proposal round, withdrawn by sys in debate): Date range starts at 1677-09-21; `to_instant()` gives the first Instant on the date (clamped on 1677-09-21).

##### EQ2: form of a range-error message (devops raised this in debate)
- **R1:** names the range, no byte offset, e.g. `invalid date: 1677-09-21 outside 1677-09-22..2262-04-11` (devops).
- **R2:** names the range and carries byte offset 0, so every ConversionError has an offset (plt, aiml in the proposal round; devops accepts it as an alternative).
Either way, the range text is the same in every Err and every panic message.

##### Reply format (SendMessage to team-lead, one message)
For each of EQ1 and EQ2:
1. **Vote**: one label.
2. **Reasoning**: 2–4 sentences from your domain.
3. **Concern**: one sentence on what could go wrong with the winning option.


#### Edge round: votes


##### devops
DevOps edge vote, pmpmyc.

**EQ1: lower edge on the Instant side**
1. Vote: E1c
2. Reasoning: the panic fires at the call that leaves the range (`Instant.add` or `from_epoch_secs`), so the stack trace and the message point at the line the user has to fix. Under E1a and E1b, a later `.date()` call panics, maybe in another module, while the bug sits somewhere else. `from_epoch_secs` needs a check anyway, because its multiply is unchecked today, and E1c makes that check the range check. `.date()` stays total, as line 2 says, and the module has one range to document.
3. Concern: if the test rows check only `.date()` and `Instant.parse`, a later change to `Instant.add` or `from_epoch_secs` can drop its range check unnoticed. The tests must hit both of those at the range edges and just past them.

**EQ2: form of a range-error message**
1. Vote: R1
2. Reasoning: a byte offset tells the user which character to fix. For a range error, the whole value is wrong, so offset 0 points at nothing and suggests the first character is the problem. The range text alone tells the user the fix. Line 9 still applies to every grammar error, which carries a real offset.
3. Concern: tests and LSP code that expect every ConversionError message to include "at byte N" will meet one cause class without it. The spec's list of cause classes must mark range errors as the one class with no offset.

##### web
WEB/SCRIPTING, edge silent vote.

**EQ1**
1. **Vote:** E1b
2. **Reasoning:** User input enters through parse, so that is where the error must show up, as a Result the dev handles with `?`. A parse should never return Ok on a value whose `.date()` then crashes. E1b gives one whole-day range for every parser, as line 8 says, and it leaves the closed Instant arithmetic contract alone. The only gap left is edge-of-Int64 arithmetic, which no clock read or log line ever produces.
3. **Concern:** The panic on `instant.date()` for the sliver must use the same range text as the Err. Otherwise the one person who does hit it (a fuzz test, say) gets a panic that does not explain itself.

**EQ2**
1. **Vote:** R1
2. **Reasoning:** `Date.from_ymd(1677, 9, 21)` has no input text at all, so "byte 0" there is noise that a reader has to work out is meaningless. A range error is about the value, not where it sits in the string. Naming the range tells the dev the fix in one read. Offsets stay where they mean something: format errors such as "expected '-' at byte 4".
3. **Concern:** Tools that expect every ConversionError message to carry an offset will need a rule for range errors, so the spec must list "out of range" as the one cause class with no offset.

##### min
MINIMALISM, edge round silent vote (pmpmyc). Votes: E1c, R1.

**EQ1: lower edge on the Instant side**
1. **Vote:** E1c
2. **Reasoning:** It is the only option with one range for std.time and no hidden precondition on any accessor. `instant.date()` and `Date.to_instant()` both stay total. The only partial operations are `Instant.add` and `Instant.from_epoch_secs`, and they can already fail by overflow, so E1c moves an existing bound by 23 h 47 m and adds no new kind of failure. The spec states the range once, and every Err and panic names it.
3. **Concern:** If E1c wins, the range check must reach every Instant constructor, including any added later (for example a future `from_unix_ms` or `Duration` path), or the sliver comes back through the one constructor that missed it.

**EQ2: form of a range-error message**
1. **Vote:** R1
2. **Reasoning:** A byte offset that is always 0 carries no information. For `Date.from_ymd` there is no input text at all, so the offset would be made up. One rule covers both kinds of error: a position error gives the offset where the parse failed, and a range error gives the range. Both are cause classes under line 9.
3. **Concern:** If R1 wins, tooling that parses ConversionError text for an offset must handle messages that have none. The spec must say which cause classes carry an offset.

##### sys
SYSTEMS: edge round, silent vote.

**EQ1**
1. **Vote:** E1c
2. **Reasoning:** Blink panics on Int overflow, so `Instant.add` and `from_epoch_secs` already need a range check. E1c only moves the lower constant of a check that already exists, so it adds no cost. `instant.date()`, which runs on every log line, stays a branch-free floor-div. It is the only option where no Instant can exist that a conversion then rejects, so line 8's "one range for the module" holds as written.
3. **Concern:** An implementer may put the lower-bound check only in `add` and miss another path that makes an Instant (`from_epoch_secs`, the `mock_clock` start, a future `sub`). The spec must say that every Instant constructor checks the range, and a test must cover each one.

**EQ2**
1. **Vote:** R1
2. **Reasoning:** A range error has no byte that is at fault: the whole value is out of range. Offset 0 would be a made-up number that a tool or agent then jumps to for nothing. `Date.from_ymd` has no input text at all, so "every ConversionError has an offset" cannot hold anyway, and R2's uniformity is false. Naming the range is the part that tells the caller the fix.
3. **Concern:** If ConversionError later gets a structured offset field, R1 needs that field to be optional. That choice should be made once for the type, not separately at each call site.

##### plt
PLT edge silent vote, pmpmyc.

**EQ1**
1. Vote: E1c
2. Reasoning: E1c is the only option where every failure sits in a constructor and every conversion between the sorts is total. The domain is one whole-day interval, so `instant.date()` and `Date.to_instant()` are mutual floor/midnight maps with no exception, and line 7 keeps its approved midnight meaning. The new panics in `Instant.add` and `from_epoch_secs` are the Int-overflow class that line 6 already uses, so the language gains no new kind of failure.
3. Concern: the Instant paragraph in 03_types.md must state the exact closed interval and the panicking constructors. The tests must also cover the Instant edge (a parse just below it is Err, `add` 1 ns below it panics, the min Instant's `.date()` is 1677-09-22), or the "total" claim stays prose.

**EQ2**
1. Vote: R1 (I CHANGE from offset 0)
2. Reasoning: ConversionError carries only a `message`, so a fixed offset 0 buys no uniformity: no field is made total, and the text just carries a number that means nothing. A range error is about the value, not about a position in the text, and an offset that points nowhere specific is false precision. Line 9's "byte offset" then reads as "for errors in the syntax", and range errors name the range instead.
3. Concern: the spec must say plainly which cause classes carry an offset (syntax) and which name the range (value), so tools and tests do not expect an offset on every message.

##### aiml
AI/ML edge silent vote, pmpmyc

**EQ1**
1. **Vote:** E1c
2. **Reasoning:** E1c is the only option a model can learn as one sentence with no exception: "std.time covers 1677-09-22 through 2262-04-11 UTC". Every constructor, every Err and every panic then names that one range, and `instant.date()` stays total as line 2 approved. E1a and E1b each add a second clause that every spec reader must hold ("`.date()` panics on Instants that `add` can still reach"). E2 turns "to_instant is midnight" into a law with one exception, and generated code copies the rule, never the exception.
3. **Concern:** If the range check goes only into `Instant.parse` and not into `Instant.add` and `Instant.from_epoch_secs`, E1c silently decays into E1b. The `assert_panics` rows just below 1677-09-22T00:00:00Z must ship with the change.

**EQ2**
1. **Vote:** R1
2. **Reasoning:** A model repairs its input from what the error points at. "at byte 0" on a well-formed `1677-09-21` points at the year digits and invites a format fix that cannot work. A range error is about the value, not a byte, and R1 says exactly that, so one retry fixes it. Line 9's byte offsets stay on the format errors, where they name the byte to change.
3. **Concern:** If ConversionError carries the offset as a typed field, R1 needs the spec to say the range cause has no offset. Otherwise implementers will fill in 0 anyway and R2 comes back through the back door.

##### Tally
EQ1: E1c 5-1 (web dissents for E1b) | EQ2: R1 6-0


#### User sign-off

The user approved the Q1–Q6 tally and sent the range edge back to the panel. The user then approved the edge result (EQ1 5-1, EQ2 6-0) with the plan that wrote this spec.

### Lead defaults

The approved bundle requires fixed message texts that tests check word for word (Q6 line 9, the Phase D votes, EQ2). The panel gave examples, not the whole list. The lead wrote the closed list in §3.2.3 from those examples, and these details are open to BDFL review:

- The fraction has 1 to 9 digits; a tenth digit is a syntax error. Display writes at most 9, so the round-trip law needs no more.
- Field errors (month, day, hour, minute, second, offset) name the field's range and carry no offset, under the same reading as EQ2 R1.
- A check stops at the first error: syntax, then fields from left to right, then the std.time range after the offset is applied.
- The panic texts are `date out of range: result outside 1677-09-22..2262-04-11` and `instant out of range: result outside 1677-09-22T00:00:00Z..2262-04-11T23:47:16.854775807Z`.

### Final Spec

```blink
// std.time — calendar: proleptic Gregorian, UTC, no leap seconds
// std.time range: 1677-09-22T00:00:00Z ..= 2262-04-11T23:47:16.854775807Z

// Instant (existing type; new members)
fn Instant.parse(s: Str) -> Result[Instant, ConversionError]  // closed grammar below
fn Instant.from_epoch_secs(s: Int) -> Instant                  // panics outside the range
fn add(self, d: Duration) -> Instant                           // panics outside the range
fn date(self) -> Date                                          // total
fn hour(self) -> Int                                           // UTC, 0..=23
fn minute(self) -> Int                                         // UTC, 0..=59
fn second(self) -> Int                                         // UTC, 0..=59

// date-time   = full-date ("T" / " ") full-time
// full-time   = hour ":" minute ":" second ["." 1*9DIGIT] time-offset
// time-offset = "Z" / ("+" / "-") hh ":" mm
// uppercase only; seconds required; :60 rejected; nothing else accepted

pub opaque type Date                                           // 1677-09-22 ..= 2262-04-11
fn Date.from_ymd(y: Int, m: Int, d: Int) -> Result[Date, ConversionError]
fn Date.parse(s: Str) -> Result[Date, ConversionError]        // YYYY-MM-DD only
fn year(self) -> Int
fn month(self) -> Int                                          // 1..=12
fn day(self) -> Int
fn weekday(self) -> Weekday
fn add_days(self, n: Int) -> Date                              // panics outside the range
fn days_since(self, earlier: Date) -> Int
fn to_instant(self) -> Instant                                 // 00:00:00Z, total

pub type Weekday { Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday }
// Monday.to_int() == 0 … Sunday.to_int() == 6; ISO number = to_int() + 1

// Date and Weekday: Eq, Ord, Hash, Display, Clone, Debug; Debug text == Display text
// Date Display: 2026-10-17; Weekday Display: Monday

// Errors: ConversionError. Syntax errors give the byte offset; field and range
// errors name the range and give no offset. Range text:
//   invalid date: 1677-09-21 outside 1677-09-22..2262-04-11

// Laws (on values):
//   Date.parse("{d}") == Ok(d);  Instant.parse("{i}") == Ok(i)
//   d.to_instant().date() == d
//   d.to_instant() <= i  exactly when  d <= i.date()
//   d.add_days(n).days_since(d) == n

// Out of v1: time zones, add_months/add_years, format strings, today(),
// day_of_year, leap seconds, and_time/at. No DateTime name is reserved.
```

§3.4 *Tag Operations* also states that the first variant's tag is 0, which the Q2 votes named as a gap.

### AI-First Review

5/5 pass. The one risk: code written from ISO habit tests `wd.to_int() == 1` for Monday. The spec line "`Weekday.Monday.to_int()` is 0 … the ISO number is `to_int() + 1`" and the matching `blink llms` note cover it.
