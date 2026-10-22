[< All Decisions](../DECISIONS.md)

# Keyword Parameters in Trait Impls — Design Rationale

**Resolution:** the trait method's declaration governs every call path. A call on a concrete receiver (`b.k(1)`), a call through a bound (`t.k(1)` with `T: Kw`) and a qualified call (`Kw.k(b, 1)`) read the trait method's `*` marker, keyword names and defaults. An impl repeats the marker position and the keyword names in the trait's order. An impl writes no default on a keyword parameter; it inherits the trait's default on every path. `E0914 TraitContractKeywordMismatch` reports a marker, name or order fault. `E0915 TraitImplWritesDefault` reports a default written in the impl. E0914 comes first when both fire. The §2.13 *Limit of the guard* clause about trait bounds is removed.

**Vote:** Q1 6-0; Q2 6-0; Q3 3-3 in Phase C, 5-1 in Phase D (AI/ML dissents).

## The Gap

The ticket title, verbatim:

> Spec: trait vs impl declaration governs keyword params and defaults of a call through a bound

§2.13 did not say which declaration governs the keyword marker and the defaults of a call through a trait bound, or whether an impl must repeat them. The compiler read the trait declaration for a bounded call and the impl declaration for a concrete receiver. The moderator measured these cases on the compiler at the time (the parser still took `--` as the marker; the table writes `*`):

| Program | Result |
|---|---|
| trait `d: Int = 1`, impl `d: Int = 5`; calls `b.k(1)`, `g(b)` (bound), `Kw.k(b, 1)` | prints `5 1 5` |
| trait `*, a, b`, impl `*, b, a`, both `Int`; call by name | `7` on both paths (binding is by name) |
| trait `*, a, b`, impl `*, x, y`; bound call `t.s(a: 10, b: 3)` | internal compiler error |
| trait `*, a, b`, impl positional `(a, b)` | impl accepted; `t.s(a: 10, b: 3)` and `x.s(10, 3)` both give `7`, so one method has labels on one path and none on the other |
| trait positional `(a, b)`, impl `*, a, b` | impl accepted; `t.s(10, 3)` and `x.s(a: 10, b: 3)` both give `7` |
| trait `*, d: Int`, impl `*, d: Int = 5` | `b.k()` gives `5`; through the bound, `d` is required |
| trait `*, a: Int, b: Str`, impl `*, b: Str, a: Int` | two `TraitContract` (E0902) errors, because the check compares parameters by position |
| trait `(a: Int, b: Int)`, impl `(x: Int, y: Str)` | `TraitContract` error for `y`; positional names already differ freely, and only types are checked |

Facts that the panel took as decided:

- `*` is the keyword marker. Parameters after it are keyword-required. The author decides, and labels are required and order-independent at the call (§2.13; [Keyword Marker Re-audit](keyword-marker-reaudit.md), 6-0).
- Labels are call-site sugar. Function types carry no labels and have full arity (§2.13).
- Defaults are only on keyword parameters and are const expressions.
- The five call-site codes E0510, E0529, E0511, E0527 and E0528 keep their meaning.
- Traits are the only polymorphism mechanism. A trait default method is overridable unless `final`, and an override has the same signature (§3.6 *The `final` Modifier*).
- The Re-audit left this question open and required that the trait-bound clause of the *Limit of the guard* paragraph come out when it is answered.

The moderator also listed two facts the panel used. §3c.4 *No Inherent Methods* says that a method belongs to a trait, so every `x.name(..)` call goes to a trait method. E0912 `TraitImplAddsPrecondition` (§3b.2) says that an impl inherits the trait method's `@requires` and may not write one, even when the predicate is the same.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Quoted text is each panelist's own, verbatim. `[…]` marks a cut. Moderator text is plain and short.

The questions, as the moderator set them for the vote:

- **Q1, defaults.** D1: the impl repeats each trait default with the same const value, and a missing or different default is an error. D2: the impl writes no default on a trait method's keyword parameter, and inherits the trait's default on every path. D3: the impl may omit the default or restate it with the same const value. (D4, no keyword parameters in trait methods, was also proposed.)
- **Q2, order after the marker.** O1: the impl writes the keyword parameters in the trait's order. O2: the order may differ.
- **Q3, codes.** C1: one new code, E0914 `TraitContractKeywordMismatch`, for marker, names, order and a default written in the impl. C2: E0914 for marker, names and order, and E0915 for a default written in the impl.

#### Phase A — Independent proposals

First choices. D1: AI/ML, Minimalism, PLT. D2: DevOps, Web/Scripting. D3: Systems. Minimalism also named D4 as a second choice. Excerpts:

- **AI/ML:** "Zero decision points for the impl writer: copy the trait's signature, add a body." (D1)
- **Minimalism:** "The fix must remove a source of truth, not add a rule that reconciles two of them." (D1). On D4: "Rule: a trait method's parameter list may not contain the `*` marker. […] That conflicts with an already-decided principle, so I do not make it my first choice."
- **PLT:** "The impl's text tells the truth. Under plt-2, an impl writes `*, d: Int` and a reader sees a required keyword param where the call site may omit it." (D1)
- **DevOps:** "The trait is the single source of the call shape. The impl repeats the marker position and the keyword names (E0914) and writes no default (E0915)." (D2)
- **Web/Scripting:** "Whatever we pick, one method must have one call surface. The trait is the interface the caller sees, so the trait governs." (D2)
- **Systems:** "The impl may omit it (it inherits the trait's value) or restate it; a restated default must be the same const value." (D3)

All six seats agreed on the shared part. The trait method's declaration governs every call path. The impl repeats the marker position and the keyword names, and positional names stay free. Function types stay label-free, so this is a check on the declaration. A rule where the impl governs, or where each path reads its own declaration, or where defaults are chosen per impl after monomorphization, was rejected by every seat that wrote about it. The *Limit of the guard* clause comes out. Whether a default may fill a parameter typed by a bare type parameter stays a separate question.

#### Phase B — Debate (one round)

The moderator deduped the six proposals into the three questions above. Each seat then wrote its position. AI/ML, Minimalism, Systems and Web/Scripting ended with "ready to vote". PLT and DevOps ended with "not ready": PLT until the order-free seats answered the mixed-type case, DevOps until the D1 seats answered the caret-upgrade break. Both points are below. The shifts, each quoted from the seat's own text:

**PLT found that the check compares parameters by position.** PLT ran a trait `*, a: Int, b: Str` against an impl `*, b: Str, a: Int`:

- **PLT:** "So the conformance check (E0902) compares parameters by position today, which is correct, because §2.13 says the fn type has full arity with the keyword params in their written positions. "Order may differ" is true today only when the types happen to agree, which is the case F2 tested."

The run gave two errors, `method `s` param has type `Str`, expected `Int`` and `method `s` param has type `Int`, expected `Str``. The moderator confirmed this before Phase C.

**DevOps argued from the caret range (§8.9.4), and the seats moved to D2.** DevOps:

- **DevOps:** "Under D1, a trait author in package `geo` who changes `*, d: Int = 1` to `= 2` in 1.3.0 breaks the build of every downstream package that implements the trait. […] So under D1, **every change to a trait default is a major-version change** for the trait's package."

Four seats moved from a first choice of D1 or D3 to D2:

- **PLT:** "What moved me was the library-evolution argument from devops-1, web-1 and sys-2."
- **AI/ML:** "My Phase A argument "copying the trait signature is always legal" is already false in Blink."
- **Systems:** "D3 was my first choice. No other seat took it, and its only extra over D2 is "the impl may also restate the same value"."
- **Minimalism:** "My Phase A frame was "remove a source of truth, not reconcile two". D2 is that frame. D1 was not; I got it wrong."

**Minimalism withdrew D4, on the strength of §3c.4 *No Inherent Methods*.**

- **Minimalism:** "So every method call `x.name(..)` in Blink goes to a trait method, and a trait with exactly one impl is the normal way to give a type a method. […] Keyword args would stay only on free fns and `fn T.name(..)`. That is a far larger cut than I wrote in Phase A, and it conflicts with "the author decides" (re-audit). I withdraw min-2."

**Four seats moved from "order may differ" to O1 after PLT's finding.**

- **DevOps:** "I withdraw "order may differ" from devops-1."
- **Systems:** "In sys-1 I wrote "order may differ"; I withdraw that."
- **Web/Scripting:** "Same order removes the question, and it costs nobody anything: order after `*` has no meaning at the call, so no one has a reason to reorder in the impl."
- **Minimalism:** ""Same order" is the rule with nothing to add, and the author gives up nothing, because order has no meaning at the call."

On codes, DevOps moved from two codes to one in this round, and AI/ML, PLT and Web/Scripting leaned to two under D2. The machine-fix table that DevOps wrote was accepted by all six seats in Phase B and Phase C. It is in the Final Spec below.

#### Phase C — Final vote

Each seat voted alone on a written ballot. The moderator put three facts on the ballot: PLT's mixed-type case is true on the compiler; caret is the default dependency range (§8.9.4); E0912 says an impl may not write a `@requires`, "even when the predicate is the same as the trait's".

##### Q1 — Defaults — **D2** (6-0)

- **AI/ML:** "Blink already says that an impl inherits the caller-facing contract and may not write it, even when it is the same (E0912 for `@requires`)."
- **DevOps:** "D2 keeps one source of truth, matches the E0912 precedent for `@requires`, and makes the copy-paste case cost one machine-applicable `blink fix` that changes no call's value."
- **Minimalism:** "D1 would write every such default twice and add a const-equality rule only to check the copy."
- **PLT:** "The trait owns the value, so a change to a default breaks no implementer, as it already breaks no caller."
- **Systems:** "D1, D2 and D3 emit the same C for every call, so the choice is only where the constant lives."
- **Web/Scripting:** "E0912 already teaches Blink users that an impl inherits the trait's caller-side contract and may not restate it, "even when the predicate is the same", so D2 adds no new mental model."

##### Q2 — Order after the marker — **O1** (6-0)

- **AI/ML:** "A rule like "order may differ" that holds only when the types happen to agree is hard to learn from the spec."
- **DevOps:** "Same order costs nothing in tooling: `blink fmt` never reorders params, and the reorder fix is machine-applicable because the body binds by name."
- **Minimalism:** "O2 would need either a type-dependent exception or a permutation in codegen, and both are extra rules."
- **PLT:** "O1 costs authors nothing, because the call site ignores order."
- **Systems:** "Same order removes the case and costs nothing, because order after `*` has no meaning at the call site."
- **Web/Scripting:** "A Python or TS dev would not guess either rule, but "same as the trait" needs no explanation."

##### Q3 — Codes — **3-3**

C1 (one code): DevOps, Minimalism, Systems. C2 (two codes): AI/ML, PLT, Web/Scripting.

- **DevOps:** "Every case has one repair, "make the impl's keyword header match the trait's", so §3.1 says one code." (C1)
- **Minimalism:** "§3.1 rule 3 says one repair means one code." (C1)
- **Systems:** "A second code for "default written in the impl" is the same error at a different column." (C1)
- **AI/ML:** "Under D2 the two errors have different repairs. One is "make the keyword list match the trait", the other is "delete the default, or move it to the trait"." (C2)
- **PLT:** "Neither belongs in E0902, which reports a type mismatch while here the types are equal." (C2)
- **Web/Scripting:** "Under D2 the two errors have two different repairs, "fix the parameter list" versus "delete the default", and the second carries a value judgement (help only when the values differ)." (C2)

#### Phase D — One focused round (Q3 only)

Q1 and Q2 were decided and not reopened. The moderator found that the fact brief had misquoted §3.1 and corrected the record before the round:

> The fact brief said: "Diagnostics converge on a code when they converge on a repair (§3.1 *Diagnostic Discipline*)." That is not what §3.1 says. §3.1 rule 3, verbatim (sections/03_types.md:27):
>
> > **Diagnostics at one program point must converge.** When more than one diagnostic fires at the same point, at least one prescribed repair, applied, must discharge all of them — and it must be the repair the diagnostic names *first*. Two diagnostics that each demand the opposite of the other leave the user with no terminating edit; a converging repair that is offered second is a guarantee a mechanical fixer never reaches.
>
> No rule in sections/ says "one code per repair". Past panel rulings did choose codes by concept and repair, for example DECISIONS.md:356 (E0303 vs E0910: "one concept, two codes, differing grammar/repair") and DECISIONS.md:391 (E0539: `UnhandledEffectInTest` folded into one code).

The moderator added one fact: an impl can break both rules at once, for example `fn k(self, *, a: Int, d: Int = 5)` against the trait's `fn k(self, a: Int, *, d: Int = 1)` (marker moved and a default written).

**Result: C2, 5-1.** DevOps, Minimalism and Systems moved from C1 to C2. PLT and Web/Scripting held C2. AI/ML moved from C2 to C1.

**Moved to C2:**

- **DevOps:** "Under D2 (now 6-0), the trait's header is no longer what the impl writes, because the impl drops the defaults. So the "one repair" claim is gone. […] The precedent that is left points to C2: E0912 is its own code for "an impl writes what it inherits", and E0915 is the same concept for a default."
- **Minimalism:** "The correction takes away my reason. […] A shape mismatch says "your contract differs from the trait's". An impl default says "you wrote a thing you inherit"."
- **Systems:** "I have no good answer to this. The correction changes my view: my C1 reasoning stood on a "one code per repair" rule that §3.1 does not contain."

**Held C2:**

- **PLT:** "Codes name concepts, and "the impl does not match the trait's shape" and "the impl restates an inherited default" are two concepts."
- **Web/Scripting:** "A wrong keyword name is a typo that any dev fixes from the printed header. A default in the impl is a deliberate act: the dev wanted `= 5` for their type, and the `--explain` page has to teach a rule they did not expect ("defaults live in the trait; to change one, change the trait or pass the argument")."

**Moved to C1 (dissent):**

- **AI/ML (dissent):** "Under C2 two codes fire at one point, and §3.1 rule 3 then requires E0914's first repair to discharge E0915 as well. That is possible, but it is two messages and two `explain` pages for one header edit. […] A model fixes this error with one action, which is to paste the expected header that the `help:` prints."

### Final Spec

```blink
trait Kw {
    fn k(self, a: Int, *, d: Int = 1) -> Int
}

type Box { v: Int }
type Crate { v: Int }
type Jar { v: Int }
type Tin { v: Int }

impl Kw for Box {
    fn k(self, n: Int, *, d: Int) -> Int { n * d }   // OK: `n` may differ, `d` inherits `= 1`
}

impl Kw for Crate {
    fn k(self, a: Int, *, d: Int = 5) -> Int { a * d }   // E0915 -- `d` inherits `= 1` from `Kw.k`
}

impl Kw for Jar {
    fn k(self, *, a: Int, d: Int) -> Int { a * d }   // E0914 -- the trait puts `*` after `a`
}

impl Kw for Tin {
    fn k(self, a: Int, *, e: Int) -> Int { a * e }   // E0914 -- the trait names the keyword `d`
}

fn g[T: Kw](t: T) -> Int { t.k(1) }

fn main() {
    let b = Box { v: 0 }
    io.println("{b.k(1)} {g(b)} {Kw.k(b, 1)}")   // 1 1 1: the trait's default fills `d` on every path
}
```

Locked points:

- **One call surface.** The trait method's declaration governs every call path: `b.k(1)` on a concrete receiver, `t.k(1)` with `T: Kw`, and `Kw.k(b, 1)`. The marker, the keyword names and the defaults all come from the trait. Function types stay label-free (§2.13); this is a check on the impl's declaration, not on types. All six seats.
- **Marker and names, in the trait's order (Q2, O1, 6-0).** The impl has the same number of positional parameters before `*` as the trait. The keyword parameters after `*` have the same names in the same order. Positional parameter names stay free; only their types are checked (E0902). The reason for the same order: the function type has full arity, so a different order would change it.
- **No default in the impl (Q1, D2, 6-0).** An impl writes no default on a trait method's keyword parameter. It inherits the trait's default on every call path, even when the impl's default has the same value, on the model of E0912. A default that only the impl writes is the same error. To change a default, change the trait or pass the argument at the call.
- **Two codes (Q3, C2, 5-1).** E0914 `TraitContractKeywordMismatch`: the marker is missing, added or moved; a keyword name differs; the keyword order differs. Its `note:` points at the trait declaration and names the first part that differs. Its `help:` prints the expected impl header: the trait's parameter list with no defaults. E0915 `TraitImplWritesDefault`: an impl writes a default on a trait method's keyword parameter. Its `note:` says that the impl inherits the trait's default and names the value. Its `help:` says to delete the default, or to change the trait's default.
- **Order of the two codes.** When both fire on one impl method, E0914 comes first. Its printed header has no defaults, so it discharges both (§3.1 rule 3). Each code owns a different part of the header: never two errors for one fault.
- **Machine fixes.** Marker missing, added or moved: machine-applicable. Keyword order: machine-applicable. Rename: machine-applicable only when the pairing is one-to-one by position and the new name is free in the body; the fix also renames the uses in the body. E0915, deleting a default that is const-equal to the trait's: machine-applicable. A default that differs from the trait's, or that only the impl writes: `help:` only, never machine-applicable (§3.1 rule 1).
- **Tooling.** Hover and `blink query` on an impl method show the inherited defaults.
- **Spec edits.** §3.6 gains *Keyword Parameters in Impls*. The §2.13 *Limit of the guard* paragraph loses its trait-bound clause and points to §3.6. ERROR_CATALOG.md gains E0914 and E0915, and the E0911 `MissingSupertraitImpl` row that the catalog lacked.

### Concerns for implementation

- **E0914 before E0915, and a header without defaults (DevOps, Minimalism, Systems, Web/Scripting).** DevOps: "So E0914 must come first, and its `help:` must print the expected header without the impl's defaults, or a mechanical fixer applies E0914 and keeps the default that E0915 then rejects."
- **Never two errors for one fault (PLT).** "The ruling should state that each code owns a different part of the header."
- **E0915 must teach the rule (AI/ML).** "When the part that differs is a default written in the impl, the message must say that an impl takes its defaults from the trait, as E0912's message does."
- **The impl header reads as if the parameter were required (Systems, Minimalism, PLT, AI/ML).** Systems: "The `note:` and LSP signature help must show the inherited `= 1` on every path." Minimalism: "so the `note:` and hover must always show the trait's default." PLT: "so the spec and the LSP must show the inherited default (in the error `note:`, hover, and `blink query`)" AI/ML: "A model that reads only the impl sees `*, d: Int`, thinks `d` is required, and writes `d:` at each call. […] one D2 example in §3.6 and in `blink llms` reduces it"
- **The reorder fix from day one (Systems).** "an author who copies keyword params in a different order gets an error that looks pedantic, so the machine fix that reorders them must be in place on day one."
- **E0914 names the first part that differs and prints the expected header (DevOps).** "the message must name the first part that differs […] and print the expected header"
- **Fix metadata per instance (Systems).** "The fix metadata must be set per instance, not per code." E0915 is machine-applicable only for a const-equal default.
- **The spec says "same order" plainly (Minimalism).** "the spec text must say "same order" plainly, so the two-`Int` case (F2) does not read as permission to reorder."
- **O1 can relax later (AI/ML).** "O1 is the strict rule, and a later vote can relax it without breaking any program."

### Follow-ups

- Implement the checks in the type checker: E0914, E0915, and one rule that every call path reads the trait method's declaration.
- Fix the internal compiler error that a renamed keyword parameter gives on a call through a bound. E0914 now rejects the impl, so the call is no longer reachable.
- Fix the internal compiler error on a trait method used as a value (`let f = Tr.m`). The panel did not decide the type of a method value, and the same-order rule keeps it simple.
- Add one D2 example to the `blink llms` reference (AI/ML).
- Whether a keyword default may fill a parameter typed by a bare type parameter stays a separate spec question.

### AI-First Review

Learnability: a default follows the rule that `@requires` already follows (the trait states it, the impl inherits it), so a reader learns one rule for both. The cost is that an impl header reads `*, d: Int` and the default is in the trait; the `note:` and hover show it. Consistency: one method has one call surface on every path, and E0915 reads next to E0912. Generability: the common error (copy the trait header with its defaults) has one machine-applicable fix, and the printed header is a paste target. Debuggability: the silent wrong result (`5 1 5`) and the internal compiler error become two errors at the impl, each with a `note:` at the trait. Token efficiency: an impl repeats the marker and the names but not the defaults, and the catalog gains two rows.
