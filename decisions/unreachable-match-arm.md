[< All Decisions](../DECISIONS.md)

# Unreachable Match Arm — Design Rationale

§3.5 *Exhaustiveness* and the E0316, E0525 and E0547 rows of ERROR_CATALOG.md said that a bad arm "gets no
unreachable report". No rule or code defined that report. The compiler reported nothing for an arm that no value can
reach. These programs all passed `check` with no warning:

```blink
fn a(x: Option[Int]) -> Int { match x { _ => 0  Some(v) => v } }                    // arm after `_`
fn b(x: Option[Int]) -> Int { match x { None => 0  None => 1  Some(v) => v } }      // `None` twice
fn c(n: Int) -> Int { match n { 1 => 10  1 => 11  _ => 0 } }                        // literal twice
fn d(x: Option[Int]) -> Int { match x { Some(_) => 1  Some(5) => 2  None => 0 } }  // refutable payload under `Some(_)`
fn e(x: Option[Int]) -> Int { match x { Some(1) | Some(1) => 1  Some(_) => 2  None => 0 } }
```

The question was whether the compiler reports such an arm, at what level, with what contract, and which shapes the
spec guarantees.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | The rule | A: coverage-based warning `UnreachableArm` (W0710): an arm, or one OR-alternative, that the earlier unguarded arms cover. It never reports a live arm and may miss a dead one | 6-0 |
| Q2 | Shapes the spec guarantees | C: an arm after an unguarded `_` or bare binding; an arm whose pattern is a variant, `true`, `false` or a literal that an earlier unguarded arm already names, when that variant's payload patterns are all irrefutable | 6-0 in Phase D after 4-1-1 in Phase C |
| Q2b | Is `Some(1) \| Some(1)` guaranteed? | Owner tiebreak: A widened. A pattern identical to an earlier unguarded pattern, in the same arm (an OR-alternative) or an earlier arm, is always reported; the test is equality of the two patterns | 3-3 in Phase D, owner tiebreak |
| Q3 | Labels for a joint cover | A: a label on each earlier arm that is needed | 5-1 (Minimalism dissent: B) |
| Q4 | The §3.5 checker-list sentence | A: the DevOps text, with the Q2 floor and the `Never` clause in the same bullet | 5-1 (PLT dissent: B) |

Points all six seats stated, not balloted: one coverage-based warning; the check never reports a live arm and may miss
a dead one; guards are opaque (a guarded arm above covers nothing; a guarded arm below is reported when the arms
above cover its pattern); ranges, tuple, struct and `Str` shapes may be missed; each dead OR-alternative is reported
at its own span, and the arm gets one report when all alternatives are dead (V4); an arm for a `Never`-payload variant
is never reported (V7); the primary span is the pattern; the help is text, with no fix that `blink fix` applies; the
warning takes `@allow(UnreachableArm)` and a `[lints]` level; the code is not W0700; the bad-arm rule stands (a bad arm
covers nothing and gets no report); "repeated variant" in the floor means a variant whose payload patterns are all
irrefutable.

### Compiler behavior before the decision

The moderator ran ten probes with the gen1 compiler. `p01` (the ticket's `Dott` shape) now reports `NoSuchVariant`
(E0547). `p02` to `p10` all gave `ok`, with no diagnostic: an arm after `_`; `None` twice; the literal `1` twice;
`true`, `false`, then `_`; `Some(_)` then `Some(5)`; `None`, `Some(v)`, then `None | Some(_)`; a guarded arm, then
`Some(v)`, `None`, and a binding `y` (only `UnusedVariable` on `y`); `0..=10` then `5`; `Some(1) | Some(1)`.

The sys seat gave this fact in Phase B: the E0004 collector over-counts coverage on purpose (`Shape.Circle(0)` counts
as covering `Circle`), so a check that must never report a live arm needs its own under-approximating coverage
function. All six seats named this as the concern for Q1.

### Reading gaps and open points (writer)

- The Phase A and B files give the moderator's wording "reuse the E0004 coverage engine" in four seats. The ruling does
  not repeat it; the sys fact above replaces it. The spec says nothing about how the check is built.
- The ruling for Q2b says "an earlier unguarded pattern". It does not say what happens to a second alternative of a
  *guarded* arm that repeats the first alternative (`Some(1) | Some(1) if g => ..`). The spec floor keeps the ruling's
  words. The general rule (cover by earlier unguarded arms) does not report it either, so it is a possible miss, not
  a promise.
- The floor says "when that variant's payload patterns are all irrefutable" and does not say whether that holds for
  the earlier arm, the later arm or both. `Some(_)` above `Some(5)` is covered by the general rule and the check may
  report it; the floor does not require it. `Some(5)` above `Some(5)` is required by Q2b, not by the floor.
- The help text ("remove the arm, or move it above `other`"), the golden block and the label texts are the writer's
  wording; the panel did not vote on them.
- A conformance test per floor shape, and for `Some(1) | Some(1)` and `Some(1)` on two arms, is an implementation task.
  The spec text leads the compiler: gen1 reports none of these arms today.

## Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal →
debate → vote rounds. Phase A and B text below is excerpted with attribution ("…" marks a cut). Phase C and D votes
are complete and verbatim.

### Phase A: independent proposals (excerpts)

**sys-1.** "Add a warning `UnreachableArm` at the next free W code (W0709 is taken by the pending `BareSpreadConcat`
ruling). Level: warning, with `@allow(UnreachableArm)` and a `[lints]` level (§4.16.8). It is not an error. A dead arm
is wrong but harmless: the generated C is correct, and the backend drops the arm." … "**Soundness rule: the check may
miss a dead arm. It may never report a live one.**" … "**Guards.** An earlier guarded arm covers nothing (already
decided), so it never makes a later arm dead … A later guarded arm is reported if the unguarded arms above it already
cover its pattern: the guard cannot make it run." … "**OR-patterns.** Report each dead alternative at its own span …
Report the whole arm only when all its alternatives are dead; then give one report for the arm, not one per
alternative."

**web-1.** "The compiler warns on a match arm (or one OR-alternative) that earlier arms always match first." …
"**Soundness contract: never a false report; may miss.** A report must be true for every value." … "A false
'unreachable' makes a dev delete a live arm. That is worse than a missed report." … "**Must catch (the 90% case):** any
arm after an unguarded `_` or binding (p02, p08); a repeated variant: `None` twice (p03) …"

**plt-1.** "An arm (or one OR-alternative) is *unreachable* when the unguarded arms above it already cover every value
that its pattern matches. The compiler reports it as warning `UnreachableArm`. The check is **sound**: it never reports
a reachable arm. It may miss dead arms. It need not be exact." … "Let `C(i)` be the set of values covered by the
unguarded, non-bad arms before arm `i`. Arm `i` is dead iff `values(p_i) ⊆ C(i)`." … "When several arms cover it
together (`None`, then `Some(_)`, then `None | Some(_)`), the compiler labels each contributing arm."

**devops-1.** "**Name, level, code.** `UnreachableArm`, a warning. Code: the next free W07xx after the pending
`BareSpreadConcat` (W0709), so W0710. Do not reuse W0700 `UnreachableCode`: that is 'code after a jump', and its open
ticket wants one meaning." … "I accept missed arms. I reject any false report: a wrong 'unreachable' makes a user
delete a live arm." … "**Fix.** A suggested fix only, class 'suggested', never applied by `blink fix` (as W0707). …
The LSP offers 'remove arm' and 'move arm' as code actions."

**aiml-1.** "Why a warning and not an error: E0004 is an error because a missing arm is a missing behavior. A dead arm
cannot change behavior, because arms run top to bottom. Generated code often leaves one (a model adds `_ => 0` first,
then the real arms). An error makes the model loop on it." … "A false 'unreachable' makes a user delete a live arm, and a
model will obey the warning without question." … "Test: arm B is dead if the set the earlier arm matches is a superset
of B's by a syntactic rule on one earlier arm."

**min-1.** "The compiler reports `UnreachableArm` (warning, code W0710) on a `match` arm when an earlier arm of the same
`match` is an unguarded catch-all: a bare `_` or a bare binding. Nothing else is reported. The check is syntactic. It
never gives a false report. It misses every other kind of dead arm, and the spec says so." … "A second, exact checker
for Int/Str/Char ranges, tuples and nested patterns doubles the pattern-matrix code, and each miss in it becomes a
false report." Fallback min-2: "Add nothing. Remove the sentence at ~3701 and the 'gets no unreachable report' text in
the three catalog rows."

sys-2, web-2, devops-2 and aiml-2 each listed "do nothing" and rejected it. All six seats named W0710 (aiml named
W0709, with W0710 if `BareSpreadConcat` takes it) and kept W0700 out of it.

### Phase B: debate (excerpts)

Round 1 gave the six seats the digest of options and variations V1 to V7 (union of earlier arms, ranges, tuple/struct/Str
shapes, OR-alternatives, labels for a joint cover, header and §3.5 sentence, `Never` payloads).

**sys, the repo fact that changed the debate.** "Four seats say the new check 'reuses the E0004 matrix'. There is no
matrix. `tc_exh_collect_pattern` (src/typecheck.bl:28249-28300) collects variant names into a list. Its header says:
'when in doubt this code counts a variant as COVERED ... `Shape.Circle(0)` counts as fully covering `Circle`'. E0004
over-counts coverage on purpose, because a miss there is safe. For an unreachable report the safe direction is the
opposite. If we reuse that code, `Some(5)` above `Some(v)` gets a false report on a live arm. That breaks the one rule
all six of us hold." … "A pattern counts as covering a value set only when it is provably total on that set. A
constructor with any refutable sub-pattern covers nothing."

**plt, against catch-all only.** "I oppose min-1: it is sound, but it ships a rule that cannot see `None`, `None` (p03)
or p06, p07, p10, and the spec would have to list those misses as intended." On a floor: "state the contract (never a
false report), and do not list the shapes. A list turns every miss into a bug. A short floor is acceptable: arms after
an unguarded `_` or binding, and a repeated variant, `bool` or literal."

**devops, the floor.** "The spec lists a guaranteed floor of shapes the check must report: arm after an unguarded
catch-all; repeated enum variant, `true`/`false`, or literal; an OR-alternative covered by an earlier one. Without a
floor, a conformance test cannot pin the behaviour, and a later engine change can silently stop reporting." On labels:
"one secondary label on each contributing earlier arm, with no 'arms at lines' prose. Secondary labels map one-to-one to
LSP related-information; prose does not."

**min, the conditions.** "I withdraw min-2. The spec already promises the report, so 'reject' would need a spec edit
for little gain." Conditions for voting for the coverage warning: "The spec text states one guarantee only: 'never
reports a live arm; may miss a dead one.' It lists no shape that must be caught. A must-catch list is a promise the
compiler then has to keep."

**web.** "The catch-all case is the 60% case, not the 90% case. A Python/JS dev who writes `None` twice, or `Some(_)`
then `Some(5)`, gets silence and wonders why the compiler warns in one place and not the other."

**aiml.** "A model learns one rule from 'an earlier arm covers it', and a narrower rule has exceptions the model must
memorize." On a joint cover: "one pointer for a joint cover would mislead."

**Result of Phase B.** The moderator put the coverage warning (A), catch-all only (B) and nothing (C) to Q1, and
gave Q2 (a floor of guaranteed shapes), Q3 (labels) and Q4 (the §3.5 sentence) their own options. V4 and V7 were
settled with no vote: all six seats held the same text. The Phase C ballot follows.

### Phase C: silent ballot

Each seat voted alone. The text of each Vote, Reasoning and Concern is verbatim from the seat's reply. The "Files read"
line of each reply is left out. Options: Q1 A coverage-based warning, B catch-all only, C do nothing. Q2 A no list, B
the devops floor (arm after an unguarded catch-all; repeated enum variant, `true`/`false` or literal; an
OR-alternative covered by an earlier one), C the plt floor (arms after an unguarded `_` or binding, and a repeated
variant, `bool` or literal). Q3 A a label on each needed earlier arm, B one `note:` at the first covering arm. Q4 A the
devops-1 sentence, B the plt-1 sentence ("The report is sound: the checker never reports a reachable arm.").

#### Q1. The rule: A 6-0

**sys: A.** Reasoning: "A dead arm costs nothing at run time and the C is correct, so a warning is the right level. A
lint that never reports a live arm and may miss a dead one needs one proof only: each report is true. Option B gives a
rule the user cannot predict (`_`, `None` warns; `None`, `None` is silent). Option C leaves the E0316, E0525 and E0547
rows pointing at no code." Concern: "An implementer reuses the E0004 collector, which counts `Circle(0)` as covering
`Circle` on purpose, and the lint then reports a live arm, such as `Some(5)` above `Some(v)`."

**web: A.** Reasoning: "A dev who reorders arms and gets a warning for `_` first but silence for `None`, `None` will
ask why. One rule, 'an earlier arm already covers it', is easy to learn. The spec already promises the report, so C
leaves three catalog rows that point at nothing. A warning does not break a refactor in the middle of an edit."
Concern: "If the implementer reuses E0004's over-counting collector (sys B1 fact), the check reports a live arm
(`Some(5)` above `Some(v)`) and a dev deletes working code."

**plt: A.** Reasoning: "The report is a subset test, values(p_i) subset-of C(i), and C must be a proven
under-approximation. Soundness holds when C is too small and fails when C is too large. A catch-all-only rule (B) is
sound but gives two coverage notions in one spec, and it makes `None`, `None` silent while `_`, `None` warns. The spec
at ~3701 already promises the report, so C leaves three catalog rows that point at nothing." Concern: "sys's fact means
the E0004 collector over-counts coverage (`Circle(0)` covers `Circle`). If an implementer reuses it, `Some(5)` above
`Some(v)` gets a false report, and the soundness guarantee in the spec text is then false."

**devops: A.** Reasoning: "The spec at ~3701 and three catalog rows already promise an unreachable report, so Option C
leaves them pointing at nothing. Option B gives a rule users cannot predict: `_`, `None` warns but `None`, `None` is
silent, and the LSP would gray out one dead arm and not the next. p08's `y` gets only `UnusedVariable`, which advises
the wrong repair. A warning that never reports a live arm and may miss a dead one is the safe contract." Concern: "The
implementer may reuse the E0004 collector, which over-counts coverage on purpose (sys B1 fact), and then report live
arms such as `Some(5)` above `Some(v)`."

**aiml: A.** Reasoning: "A model learns one rule from 'an earlier arm covers it'. Catch-all only (B) leaves `None`,
`None` and `Some(_)` then `Some(5)` silent, so the model must memorize exceptions, and silence on a dead arm teaches it
nothing. Removing the promise (C) leaves three catalog rows that point at nothing." Concern: "If the implementer reuses
the E0004 collector, which over-counts coverage on purpose, the check gives false reports on live arms, and a model
deletes live code on the warning's word."

**min: A.** Reasoning: "The spec already promises an unreachable report, and every catalog row for a bad arm points at
it. Naming one warning with one contract (never a live arm, may miss a dead one) is smaller than a catch-all special
case with its own exception list, and it is smaller than removing the promise from four places. The sys fact means the
check needs its own under-approximating coverage function, not the E0004 collector. That is the cost I accept, and the
first slice should keep it small." Concern: "The E0004 collector counts `Shape.Circle(0)` as covering `Circle`, so an
implementer who reuses it gets false reports on live arms. That breaks the one rule the whole panel holds."

#### Q2. Shapes the spec guarantees: 4-1-1 in Phase C (C: sys, web, plt, aiml; B: devops; A: min). Sent to Phase D.

**sys: C.** Reasoning: "A floor lets a conformance test pin the behaviour, and the floor must be small enough that a
coverage function which treats any constructor with a refutable sub-pattern as covering nothing can meet it. The plt
floor (arm after an unguarded `_` or binding; repeated variant, `bool` or literal) needs only a set of variant names,
two bool flags and a literal compare. The devops floor adds 'an OR-alternative covered by an earlier one', which for
p10 (`Some(1) | Some(1)`) needs a refutable payload comparison that the cheap function does not do. Option A leaves a
later change free to stop reporting the ticket's own shape without a test failing." Concern: "A floor turns every miss
below it into a spec question, and 'repeated variant' must be read as a variant whose payload patterns are all
irrefutable, or the floor and the soundness rule conflict."

**web: C.** Reasoning: "A short floor lets a dev and a conformance test rely on the 90% shapes: arm after `_` or a
binding, repeated variant, `bool`, or literal. It promises less than B, so a later engine can grow without a spec
change. V4 already says p10 is reported, so B's extra item adds a promise and no new learning." Concern: "A floor
without a test for each shape lets the check stop reporting one of them with no one noticing."

**plt: C.** Reasoning: "A floor makes the guarantee testable, and a conformance test can pin it. My floor needs only a
total-on-set test: the arm after an unguarded `_` or binding, and a repeated variant, `bool` or literal with
all-irrefutable payloads. The devops floor adds an OR-alternative covered by an earlier one; that is also sound, but it
adds a promise for little gain, and the per-alternative rule (V4) already states that behaviour. With A (no floor), a
later engine change can silently stop all reports and still conform." Concern: "Any floor is a promise the compiler
must keep, and the first slice may be unable to keep the repeated-literal case if the coverage function is new code."

**devops: B.** Reasoning: "Tooling needs a conformance test that can fail. Without a floor, a later engine change can
silently stop reporting and no test notices. My floor lists the arm after an unguarded catch-all, a repeated variant,
`true`/`false` or literal, and an OR-alternative covered by an earlier one. All of these are provable with a strict
under-approximating cover function, so the floor makes no unsound promise. Everything outside the floor stays 'may
miss'." Concern: "If Option A wins, nothing pins the check, and it can regress to catch-all only with no spec change
and no failing test."

**aiml: C.** Reasoning: "A short floor gives conformance tests something to pin and gives a model a rule it can state:
a catch-all, then anything; a repeated variant, `bool` or literal. These shapes are provable with a simple sound check,
so the floor is cheap to keep. plt's floor is smaller than devops' and leaves p10 to the V4 rule that already stands."
Concern: "Every shape on the floor becomes a promise, so a later engine change that drops one is a bug."

**min: A.** Reasoning: "The spec states the contract only. A must-catch floor is a promise the compiler then has to
keep, and it blocks the first slice from shipping only what the proven coverage logic supports. Later slices can add
shapes with no spec change." Concern: "With no floor, a later change can silently stop reporting a common shape, and no
conformance test pins it."

#### Q3. Labels when several earlier arms cover the arm together: A 5-1

**sys: A.** Reasoning: "When the cover is a union (p07: `None`, then `Some(v)`, then `None | Some(_)`), one covering
arm is a false statement and sends the user to the wrong arm. A label on each needed arm costs a few spans, no runtime,
and maps one-to-one to LSP related-information. For a single cover the output is the same as option B." Concern: "The
implementer must find a minimal set of covering arms; if it labels all earlier arms instead, the labels add noise and
hide the arm that matters."

**web: A.** Reasoning: "For a joint cover (p07), one note at the first arm tells the dev a false thing: that arm alone
does not cover it. A label on each needed arm tells the dev what to change. For one covering arm the output is the same
as the single note." Concern: "With many covering arms the message gets long, and the dev may skip it."

**plt: A.** Reasoning: "When the cover is a union (`None`, `Some(_)`, then `None | Some(_)`), the set that covers is
the set of arms needed together. One note at the first arm states something false: that arm alone does not cover the
pattern. For a single covering arm, A gives the same one label as B. Secondary labels map one-to-one to LSP related
information." Concern: "A long union can put many labels on one report, and the output gets noisy."

**devops: A.** Reasoning: "One label on each needed arm maps one-to-one to LSP related-information, and prose such as
'arms at lines 4 and 5' does not. For p07 a note at only the first arm is a false statement, because that arm alone
does not cover the pattern. A single covering arm gives the same one label either way." Concern: "If Option B wins, a
joint-cover diagnostic names one arm and the user may delete or move the wrong one."

**aiml: A.** Reasoning: "A model repairs code from the note. One pointer for a joint cover names an arm that does not
cover the pattern alone, so the repair misleads. Labels on each needed arm are true, and they map one-to-one to LSP
related-information." Concern: "Output grows with long joint covers, and a model may read many labels as noise."

**min: B (dissent).** Reasoning: "One `note:` at the first needed covering arm is enough for the user to find the
cause. Labels on every contributing arm add output and a rule to learn, for no gain in the repair." Concern: "For a
joint cover, a note at one arm says the arm covers it, but one arm alone does not, so the note can mislead."

#### Q4. The §3.5 checker-list sentence: A 5-1

**sys: A.** Reasoning: "'Never reports a live arm. It may miss a dead one.' states the contract in plain words and
promises no shape. Option B says 'sound', which is jargon and says the same thing in more words. The ruling should also
state that the check does not reuse E0004's collector, outside the §3.5 sentence." Concern: "The sentence makes no
mention of `Never` payloads, so the V7 clause must sit in the same bullet or a reader will expect an empty-type check."

**web: A.** Reasoning: "The devops-1 sentence is shorter and uses plain words ('It may miss a dead one'). It states the
same contract as plt-1 with no extra claim." Concern: "'Already cover' does not say how much the check can prove, so a
dev may think a missed dead arm is a compiler bug."

**plt: B (dissent).** Reasoning: "'The report is sound: the checker never reports a reachable arm' states the guarantee
in the terms the spec uses elsewhere, and it names the property that a conformance test checks. 'May miss a dead arm'
states the one allowed direction of error. A and B hold the same rule; B states the reason, and the reason tells an
implementer which direction of approximation is safe." Concern: "The word 'sound' may be read as a claim for the whole
spec, but it applies only to this check."

**devops: A.** Reasoning: "It is the shorter text and makes the same two promises: never a live arm, may miss a dead
one. 'The report is sound' in plt's text is jargon that adds no promise. The writer appends the Q2 floor." Concern:
"None beyond Q1: if the sentence omits the floor, 'may miss' is read as permission to catch nothing."

**aiml: A.** Reasoning: "The devops-1 text is shorter and states the two facts a model needs: the warning and the
contract. The word 'sound' in B adds no meaning for a model reader. The writer adds the Q2 floor to it." Concern: "'It
may miss a dead one' without the floor reads as no promise at all, so the Q2 floor must be in the final text."

**min: A.** Reasoning: "devops-1 makes the fewest promises: a warning, never a live arm, may miss. plt-1 adds 'The
report is sound', a claim in type-theory words that says no more than the next sentence." Concern: "The sentence lists
no shape, so a reader cannot tell from §3.5 what the check does catch."

#### Phase C result

Q1 A 6-0. Q3 A 5-1. Q4 A 5-1. Q2 split 4-1-1, so Q2 went to one focused round (Phase D). The Q3 and Q4 dissents stand
as recorded above: min on Q3 (B) and plt on Q4 (B).

### Phase D: focused debate on Q2

The seats read the six Phase C Q2 votes and replied once each (D1), then voted again (D). In D1 five seats held the plt
floor with a payload clause ("repeated variant" means a variant whose payload patterns are all irrefutable); devops and
min moved to it from B and A. sys then raised a new point: V4 gives the unit of a report, not the shapes found, and
p10 (`Some(1) | Some(1)`) needs a comparison of refutable payloads. The ballot split this off as Q2b.

#### D1 replies (excerpts)

**sys.** "V4 states the unit of a report (one alternative, or the whole arm). It does not state which shapes the check
finds. p10 needs a comparison of two refutable payloads. The first slice may not do that, and 'may miss' must be
allowed to cover it. If the panel wants p10 guaranteed, that is B, and it should say so openly. It should not come in
through V4."

**devops.** "I move from B to C. A floor must exist; min's A leaves the check free to regress with no failing test,
which is my reason for voting B." … "sys is right on one point. p10 (`Some(1) | Some(1)`) needs a comparison of
refutable payloads. That is a V4 question, not a floor question. If the first slice cannot report p10, it conflicts
with V4, not with the floor. I do not reopen V4."

**min.** "I move from A to C. The argument that moves me: with A, a later change can regress the check to nothing and
still conform. A contract with no test that can fail is not a contract."

**plt.** Floor text held: "The check reports at least: an arm after an unguarded `_` or bare binding; and an arm whose
pattern is a variant, `true`, `false` or a literal that an earlier unguarded arm already names, when that variant's
payload patterns are all irrefutable." "Everything else is 'may miss'."

**web, aiml.** Both held C with the payload clause. aiml: "Two statements of one rule give a model two texts to
reconcile."

#### Phase D votes (verbatim; "Files read" lines left out)

Q2 options: A no list; B the devops floor; C the plt floor with the payload clause. Q2b options: A p10 is guaranteed
(V4 requires it); B p10 is not guaranteed and may be missed.

**sys.** Q2 **C.** Reasoning: "A floor lets a conformance test fail if a later change drops a common shape. The plt
floor with the payload clause needs a set of variant names, two bool flags and a literal compare, so a cover function
that treats any constructor with a refutable sub-pattern as covering nothing can keep it. Every seat now holds this
floor in its own words. The writer picks the wording, and the payload clause must stay in it, or the floor promises
`Some(5)` after `Some(5)` and conflicts with the soundness rule. One conformance test per floor shape." Concern: "Any
floor is a promise, and a first slice built on a new coverage function may fail to keep the repeated-literal case."
Q2b **B.** Reasoning: "V4 states the unit of a report (one alternative, or the whole arm). It does not state which
shapes the check finds. p10 needs a comparison of two refutable payloads, which the floor's cheap function does not
do. Guaranteeing p10 would put B's extra promise into the spec through V4 after the panel dropped it from the floor.
'May miss' must cover p10 until a slice implements refutable payload comparison. A check that reports p10 stays
allowed and stays sound." Concern: "If B wins, a dev who sees `Some(1) | Some(1)` unreported may think the check is
broken, and no test pins the shape."

**web.** Q2 **C.** Reasoning: "The floor lists the shapes a dev writes by mistake: an arm after `_` or a binding, a
repeated variant, `true`/`false`, a repeated literal. A conformance test can pin each shape, so the check cannot
regress to nothing and still conform. The payload clause keeps the floor and the 'never report a live arm' rule
consistent: `Some(5)` after `Some(5)` is outside the floor. I hold web's D1 text, in the writer's wording." Concern: "A
floor shape with no conformance test can stop being reported with no failing test, so the implementer must write one
test per shape." Q2b **B.** Reasoning: "V4 sets the unit of a report: one alternative, or the whole arm. It does not
set which shapes the check finds. p10 needs a comparison of two refutable payloads, and the first slice may not do
that. My D1 position is that the floor must not promise more than the first slice can keep, so p10 falls under 'may
miss'. A later slice that reports p10 needs no spec change." Concern: "A dev who sees `Some(1) | Some(1)` go
unreported may read it as a bug in a check that the spec says reports each dead alternative."

**plt.** Q2 **C.** Reasoning: "A guarantee that no test can falsify is not a guarantee, so a floor must exist. The C
floor holds only shapes that a total-on-set cover function proves: names, two bool values, literal equality. With the
payload clause ('payload patterns all irrefutable') the floor and the soundness rule do not conflict: the floor never
requires a report on `Some(5)` above `Some(5)`, and it never permits one on `Some(5)` above `Some(v)`. The floor is a
minimum and does not stop a later engine from catching more." Concern: "The first slice may under-deliver the
repeated-literal shape if its cover function is new code, and the floor then makes that a spec breach and not a miss."
Q2b **A.** Reasoning: "V4 was agreed in Phase B: each dead OR-alternative is reported, and p10 is the named example.
sys is right that V4 fixes the unit of a report and not the shapes found, but the Phase B text names p10 as reported,
and I do not reopen it. The check is sound: two structurally equal patterns in one OR-pattern are provably redundant,
and the test needs only structural equality of the second alternative against the first, not a general
refutable-payload cover. A first slice that cannot report p10 conflicts with V4 and should say so in its ticket."
Concern: "If the first slice does not report p10, the spec promises something the compiler does not do, and the writer
must either mark the gap or the implementer must add the structural-equality case."

**devops.** Q2 **C.** Reasoning: "A conformance test needs a floor that can fail, or the check can fall back to
catch-all only with no failing test. The plt floor with the payload clause holds only shapes that a strict
under-approximating cover function proves. It also keeps the floor and the soundness rule consistent: `Some(5)` above
`Some(v)` is not a 'repeated variant'. Each floor shape gets one conformance test, as an implementation task."
Concern: "The floor wording must keep the payload clause, or a reader takes `Some(5)` after `Some(5)` as promised and
the first slice cannot keep that promise." Q2b **A.** Reasoning: "V4, agreed in Phase B, says each dead OR-alternative
is reported and names p10 in all six Phase A files. The floor lists the minimum, not the full set. If the first slice
cannot report p10, that slice conflicts with V4. The fix is to ship the slice later or reopen V4 in its own ballot.
Writing 'p10 may be missed' now would remove a rule the panel agreed without a vote on it." Concern: "If the first
slice cannot compare refutable payloads, the spec promises p10 before the compiler reports it, and the conformance test
for V4 fails until a later slice adds the compare."

**aiml.** Q2 **C.** Reasoning: "A short floor gives a model one rule it can state and a test that can fail: a
catch-all, then anything; a repeated variant (all payload patterns irrefutable), `true`, `false` or literal. The
payload clause is needed. Without it a model reads `Some(5)` after `Some(5)` as covered and learns a rule that gives
false reports. B states the OR-alternative rule a second time, and V4 already holds it." Concern: "Each floor shape is a
promise, so a slice that drops one breaks the spec, and no test will say so unless each shape has its own conformance
test." Q2b **A.** Reasoning: "V4 was agreed in Phase B, with p10 named by all six seats, and it is not reopened. A
model that reads V4 expects p10 to be reported. If B wins, the spec says 'reported' in one place and 'may miss' in
another, and a model has to guess which text wins. If the first slice cannot report p10, that is a slice gap to log,
not a reason to weaken the spec." Concern: "The first slice may lack a refutable-payload compare, so p10 may ship late
and the spec would promise more than the compiler does for a while."

**min.** Q2 **C.** Reasoning: "A contract with no shape that a test can pin lets the check regress to nothing and
still conform. The plt floor (with the payload clause) is the smallest list that closes that hole: it needs a set of
variant names, two bool flags and a literal compare, and the ticket's own shape is on it. It adds nothing a later slice
cannot extend, and every other dead arm stays 'may miss'." Concern: "Every floor shape is a promise, so a first slice
that cannot meet one (for example the repeated literal) must either grow or break the spec." Q2b **B.** Reasoning: "V4
fixes the unit of a report (one alternative, or the whole arm). It does not list the shapes the check finds. p10 needs
a comparison of two refutable payloads, which the floor leaves out on purpose. Guaranteeing p10 adds a promise through
the side door, and the same promise would then bind the first slice that cannot keep it. A later slice may report p10
with no spec change." Concern: "If p10 is not guaranteed, a reader of V4 may expect the report and file a bug when the
check misses it."

#### Phase D result

Q2 C 6-0. Q2b 3-3: A aiml, devops, plt; B sys, web, min.

### Owner tiebreak (Q2b)

The panel tied 3-3, so the owner (BDFL) broke the tie for A, and widened it: "A pattern identical to an earlier
unguarded pattern, in the same arm (an OR-alternative) or an earlier arm, is always reported. Covers `Some(1) |
Some(1)` and `Some(1) => ..` ; `Some(1) => ..`. The check is structural equality, not a refutable-payload cover." The
ruling goes past the vote so that the two-line duplicate and the OR duplicate do not get different treatment. It meets
the B side's cost concern (a dev sees `Some(1) | Some(1)` unreported and files a bug) by limiting the guarantee to
structural equality. The A side's concern stands: the first slice may ship the p10 case late.

### Final Spec

- §3.5 *Exhaustiveness*: a new checker-list bullet holds the Q4 A sentence (the devops-1 text) with the Q2 floor
  reference and the `Never` clause in the same bullet. The bad-arm bullet now says the compiler reports no
  `UnreachableArm` (W0710) for the bad arm. A new block, *Unreachable arms*, holds the rule, the guard, OR-pattern, joint
  cover, `Never` and bad-arm points, the floor with the payload clause, the Q2b identical-pattern rule, Blink examples,
  a golden diagnostic and the lint controls.
- ERROR_CATALOG.md: a new Linting row W0710 `UnreachableArm` (§3.5). The E0316, E0525 and E0547 rows now name
  `UnreachableArm` (W0710).
- `llms-full.md`: the E0547 bad-arm line and a Gotchas bullet name the warning.
- DECISIONS.md: a Resolved Questions row and a Design Rationales link to this file.

Code check: W0710 appears in none of the 54 `spec/*` branches and not on main. W0709 belongs to the bare-spread
branch. The examples in the new spec block pass `blink check` with gen1; gen1 reports no warning, because the spec
leads the compiler.

Implementation ticket (to file after the merge): `UnreachableArm` W0710 in the type checker with its own
under-approximating coverage function. It must not reuse the E0004 collector, which over-counts on purpose. It needs
a span per OR-alternative, labels on a minimal set of covering arms, one conformance test per floor shape, a
structural-equality duplicate check against earlier unguarded patterns (same arm and earlier arms) with tests for
`Some(1) | Some(1)` and for `Some(1)` on two arms, and `@allow(UnreachableArm)`.
