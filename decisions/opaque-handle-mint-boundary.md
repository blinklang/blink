[< All Decisions](../DECISIONS.md)

# Opaque-Handle Mint Boundary — Design Rationale

Resolves br `z4avjn`. Unblocks the implementation ticket br `9jz9vk` (opaque-ffi-handle
audit body scan). Refines the *Construction — sealed to the FFI boundary* clause of the
[`@ffi.opaque` decision](opaque-ffi-handles.md).

**The gap.** The `opaque-ffi-handle` audit needs a body scan that tags handle *mint* and
*round-trip* crossings inside function bodies. The spec gave two conflicting signals about
which regions count as the mint boundary: §07:904 said a handle is produced "inside an
`@ffi`/`@trusted` region," yet the canonical `open()` wrapper (§07:913-920) mints a handle
(`out.deref()`) in a plain `pub fn` with neither annotation — its only boundary marker is a
`with ffi.scope()` block. E0811's own help text (§07:379) likewise offers `ffi.scope` as the
remedy for an outside-FFI pointer. So either `ffi.scope` is a third FFI-region kind (example
correct, rule text stale) or only `@ffi`/`@trusted` count (example ill-formed).

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate rounds. The moderator ran Phase A (independent proposals)
and a single Phase B broadcast covering three questions: **Q-region** (the mint-boundary
predicate), **VAR-1** (prose style — reference vs. re-enumeration), and **VAR-2** (edit scope —
§9.1.4 alone vs. the E0811 rule text). Phase B collected discrete, vote-shaped final positions
with zero dissent; a separate silent Phase C would have reproduced an identical 6-0, so it was
folded into Phase B (a 6-0 result triggers no Phase D). The Phase B position of each panelist
*is* its recorded vote and is quoted verbatim below.

#### Phase A — Independent proposals

- **Systems:** *"PROPOSAL S1 (primary): mint boundary = the existing E0811-legal-Ptr region,
  reused verbatim, not a new predicate. E0811 already defines, purely structurally, every place
  a Ptr[T] is legal: an @ffi fn, an @trusted fn, or the lexical body of `with ffi.scope() as _
  { }`. Since a handle can only ever be minted by dereferencing a Ptr[opaque] (line 904), and Ptr
  can only ever exist inside one of those three regions, the mint-boundary predicate for the
  audit IS the Ptr-legality predicate. The audit walker doesn't need its own definition of 'FFI
  region' — it needs a pre-typecheck structural clone of the same three-way test E0811 already
  computes, single-sourced so the two can't drift apart later. [...] Spec edits needed: reword
  §9.1.4:904 'inside an @ffi/@trusted region' -> '...or the body of a `with ffi.scope() as _ { }`
  block,' and add the same clause to E0811's rule prose. [...] The open() example itself needs NO
  change — it's already correct under this rule."* Rejects "any pub fn" (would tag ordinary code
  that never touches a Ptr) and "any fn that derefs Ptr[opaque]" (redundant with E0811).
  Cross-language: *"same cost model as Rust's `unsafe { }` — a pure lexical-region stack tracked
  during AST descent, no attribute required, no type resolution."*

- **Web/Scripting:** *"Mint boundary = wherever `Ptr[T]` is already legally allowed to live under
  E0811 — and E0811's own region list must be corrected to name `ffi.scope()` blocks explicitly.
  [...] The actual bug is in the spec prose, not in the open() example. [...] Fix: edit §07:911
  (and wherever E0811's formal rule is defined) to read 'inside an `@ffi`/`@trusted` region, or
  inside a `with ffi.scope(...) as x { }` block' — three named regions, not two. The canonical
  open() wrapper needs zero changes; it was correct all along, the prose just hadn't caught up to
  it."* On requiring `@trusted` instead: *"duplicates the signal [...] is viral — `@trusted` on a
  `pub fn` leaks 'this API is unsafe' onto the public signature of what is, from the caller's
  perspective, a perfectly safe wrapper [...] generates exactly the Stack-Overflow-bait question
  the panel should be trying to prevent."* Cross-language: *"the same shape as Rust's `unsafe { }`
  block vs. an `unsafe fn` signature."*

- **PLT:** *"There must be exactly ONE syntactic predicate `FFI-active(region)`, defined once,
  consumed by both E0811 (where a `Ptr[T]` may appear) and the 9jz9vk audit body scan [...].
  Defining two separate rules is the failure mode to reject outright — it guarantees drift."*
  Gives the inductive judgment: **R-FFI-FN**, **R-TRUSTED**, **R-SCOPE** (*"body of `with
  ffi.scope() as x { ... }` ⟹ FFI-active, regardless of the enclosing fn's annotations"*),
  **R-PROP-BLOCK**, **R-PROP-CLOSURE** (*"if FFI-active(R) and a closure literal occurs lexically
  inside R ⟹ FFI-active(closure body)"*), **R-NO-PROP-FNITEM** (*"a named nested `fn` item inside
  FFI-active R does not inherit"*). Soundness note: *"keep the region predicate 100% syntactic
  [...] and let the orthogonal escape pass own dynamic-extent safety [E0601]. Don't fold escape
  checking into the mint-boundary predicate — that would make it non-syntactic and duplicate
  E0601."* Cross-language: *"exactly Rust's `unsafe { }`: a purely lexical, compile-time-only
  region marker, decoupled from runtime lifetime reasoning [...] propagating into closure literals
  but not into nested `fn` items."*

- **DevOps/Tooling:** Rejects "any pub fn" (*"would drown the audit inventory in noise"*) and
  "any fn that derefs Ptr[opaque]" (*"circular. That's the exact site the scan is trying to
  classify"*). Core principle: *"The audit's region predicate MUST mirror whatever E0811
  (PtrOutsideFFI) actually accepts — never a re-derived-from-prose guess. [...] silent inventory
  gaps: a compiling mint site the scanner doesn't recognize as 'in-region' and therefore doesn't
  tag [...] a reviewer trusts the inventory is exhaustive, and silent gaps break that trust worse
  than noise does."* Preferred proposal: two structural region forms OR'd (`@ffi`/`@trusted`
  FnDecl attr, OR lexically inside a `with ffi.scope` block). CI recommendation: *"add a property
  test tying the audit scanner's region predicate to the typechecker's E0811 acceptance set:
  assert every `Ptr[opaque].deref()` site that compiles successfully is also tagged by the audit
  scanner. This prevents the two from silently drifting apart."* Proposed audit output lines with
  `MINT` / `ROUND-TRIP` records. Fallback (if E0811 were fn-annotation-only): region =
  `@ffi`/`@trusted` attr only, `open()` gains `@trusted`.

- **AI/ML:** *"The mint boundary is a 'trusted FFI context,' which has exactly two syntactic
  spellings — not two different rules"* (fn-level `@ffi`/`@trusted`, or block-level inside `with
  ffi.scope()`). *"This is not a new rule invented for the audit — it is the rule E0811 already
  enforces [...]. Two independent trust-boundary predicates in one codebase is the failure mode to
  avoid."* Domain analysis: *"models learn region rules from paired (prose, example) evidence, not
  from prose alone. Right now the corpus contains one paragraph asserting rule R [...] sitting a
  few lines above a canonical [...] example that violates R. That is a poisoned training pair. [...]
  This is the single most important thing this panel can fix: not 'which rule is more elegant' but
  'which spec text will a model actually copy, and does that copied text pass typecheck.'"* Warns
  against the `@trusted`-retrofit compromise: *"Two checkers with two different definitions of
  'trusted region' in the same compiler is worse for model learnability than either checker alone."*
  Cross-language: Rust `unsafe fn` vs `unsafe { }` — *"one concept with two spellings, and this is
  empirically well-learned by code-generation models."*

- **Minimalism:** *"invent no new region — reuse E0811's existing legality set; fix ONE prose line,
  by reference not enumeration. [...] The wrong line is §911's prose, not the §913-920 example.
  [...] changing it to add `@trusted` would be patching working code to match broken prose,
  backwards."* Prefers **1a** (*"Replace §911's enumeration with a pointer: 'production happens by
  reading a handle out of a `Ptr` cell wherever a `Ptr[T]` may legally appear (see E0811).' No
  duplicate enumeration to drift out of sync ever again — this is the actual root cause (two places
  listing the same rule)."*), 1b as fallback. Rejects "any pub fn" and "any fn that derefs opaque
  Ptr" as *"a second, bigger region"* / *"the two-sources-of-truth pattern that produced this
  ticket."* Cross-language: *"Rust's soundness auditors (`cargo geiger`, clippy's
  `undocumented_unsafe_blocks`) tag exactly the lexical `unsafe { }` region the compiler itself
  already recognizes — they do not maintain a second, separate definition."*

#### Phase B — Final positions (vote-shaped; recorded as the vote)

The moderator surfaced a codebase fact to the panel: E0811's rule text (§163 "per-function
capability gate", §211 "@ffi/@trusted context") never names `ffi.scope`, yet its own help text
(§379) and the canonical example both rely on it. Each panelist answered Q-region (accept
Option A?), VAR-1 (prose style), and VAR-2 (edit scope).

- **Systems:** *"(a) Accept Option A. (b) VAR-1 pick: 1a (point by reference). (c) VAR-2: editing
  the E0811 rule text at §163/211 is required, not just §9.1.4:904. [...] the compiler's actual
  accepted behavior already grants Ptr-legality at block level via ffi.scope() today — Option A
  doesn't create that legality, it documents a gap that already exists between the rule's text
  (fn-attribute-only) and its worked example/help-text (block-level via ffi.scope). Fix: reword
  §163/211 from 'per-function' to 'per-region: an @ffi/@trusted fn body, or a with ffi.scope() as
  _ { } block,' then have §9.1.4:904 reference that single definition per 1a. (d) Ready to vote."*

- **Web/Scripting:** *"(a) Accept Option A. (b) VAR-1: 1a. (c) VAR-2: This requires editing
  E0811's rule text (§163/§211) to name `ffi.scope` as a third granting region — §9.1.4:904 alone
  is not enough. [...] Under that reading, the canonical `open()` [...] should be rejected, and
  isn't only because the implementation is apparently more lenient than the written rule. [...]
  Option A doesn't just clarify wording — it formally EXTENDS E0811 from function-granularity to
  region-granularity [...]. That's a widening change (nothing currently-legal becomes illegal) but
  it's a substantive spec edit to E0811 itself, not a doc-only fix in 9.1.4. (d) Ready to vote."*

- **PLT:** *"(a) ACCEPT Option A. (b) VAR-1: 1a (point by reference). [...] a re-enumeration at
  §9.1.4 is a second copy of the same fact that will drift. (c) VAR-2 — this is the important
  finding, and it changes my answer from Phase A: No, a `with ffi.scope()` block does NOT already
  grant Ptr-legality today. §163/§211's RULE TEXT states the gate is per-function [...]. So Option
  A is not a clarification, it's a genuine extension [...]. That requires editing the RULE TEXT
  itself at §163/§211 [...]. R-PROP-CLOSURE / R-NO-PROP-FNITEM should be made normative, at that
  same §163/§211 edit site — not left as scan-implementation detail. [...] the propagation
  boundary needs to be spec text, not folklore in the 9jz9vk implementation. (d) Ready to vote."*

- **DevOps/Tooling:** *"(a) Accept Option A. (b) VAR-1: 1a. [...] 'see E0811' becomes a safe
  single source. (c) Agree — edit §163 AND §211 (not just §9.1.4:904) to name `ffi.scope` as a
  third granting region. My earlier objection was to widening the gate silently via prose/example
  alone; editing the rule text itself makes it an explicit, deliberate, recorded semantics
  decision, which is exactly what I wanted. That resolves my concern. @trusted-retrofit fallback
  is now off the table. (d) Ready to vote."*

- **AI/ML:** *"(a) Accept Option A. (b) 1a (reference), conditional on (c). (c) Fixing §9.1.4:904
  alone is not enough — must also edit E0811 rule text at §163/§211. E0811's own rule statement is
  the most authoritative 'where can Ptr appear' text in the corpus [...]. Fixing only 904 while
  §163/§211 keep saying '@ffi/@trusted context' makes the poisoned pair worse, not better [...]. A
  model asked 'where can I dereference Ptr[T]' quotes the rule statement, not the help text — it
  would generate the stale, incomplete answer. [...] Option A documents existing behavior; it does
  not grant new legality. (d) Ready to vote, conditioned on §163/§211 being in scope for edit."*

- **Minimalism:** *"(a) ACCEPT Option A. (b) VAR-1: still 1a (reference, not re-enumeration). (c)
  VAR-2: the surfaced fact changes the edit count from 1 to 2, but not the substance. §211's
  'inside an @ffi/@trusted context' restatement is itself the incomplete enumeration [...]. §163's
  'per-function... checked structurally' can stand as-is (it describes analysis granularity, not
  the grant list) — only §211 needs the ffi.scope clause added. True minimum edit set: (i) add the
  block-level `with ffi.scope() as _ {}` grant to E0811's rule text at §211 [...]; (ii) then §9.1.4
  references E0811 by pointer (1a) [...]. Two line-edits, one concept, one source of truth. (d)
  Ready to vote."*

#### Phase C / Phase D

No distinct Phase C silent vote and no Phase D: the Phase B final positions were unanimous
(6-0) and vote-shaped, so a separate silent round would have reproduced an identical tally.

### Final Vote

- **Q-region — mint-boundary predicate:** **6-0 Option A** — the mint boundary *is* E0811's
  legal-`Ptr` region set (three forms: `@ffi` fn body / `@trusted` fn body / `with ffi.scope() as
  _ { }` block), single-sourced. "Any pub fn" and "any fn that derefs `Ptr[opaque]`" rejected 6-0.
- **VAR-1 — prose style:** **6-0 for 1a** — E0811 owns the one region list; §9.1.4 points at it by
  reference, no second enumeration.
- **VAR-2 — edit scope:** **6-0 to edit the E0811 rule text itself** (§07:163/§211), not §9.1.4
  alone. DevOps withdrew its `@trusted`-retrofit fallback once the rule-text edit was in scope. PLT
  asked (and the panel agreed) that the closure/nested-`fn` propagation rules be made normative at
  the same edit site.

AI-First review: **5/5 pass** (one region concept ≈ Rust `unsafe`; reuses E0811 wholesale;
de-poisons the (prose, example) training pair; audit `MINT`/`ROUND-TRIP` inventory lines; zero
new syntax or ceremony).

### Final Spec

The mint boundary is the **FFI region** set that E0811 permits a `Ptr[T]` to appear in, stated
once with *Pointer Operations* (§9.1.1, E0811) and referenced everywhere else:

1. the body of an `@ffi` function;
2. the body of an `@trusted` function;
3. a `with ffi.scope() as _ { }` block.

```blink
// canonical open() — unchanged; legal because its body sits inside an ffi.scope region
pub fn open(path: Str) -> Option[Connection] ! IO {
    with ffi.scope() as scope {
        let out = scope.alloc[Sqlite3]()          // Ptr[Sqlite3] — legal (region 3)
        let cstr = scope.cstr(path)
        let rc = raw_sqlite3_open(cstr, out)
        if rc != 0 { return None }
        Some(Connection { db: out.deref() })      // MINT — tagged, region = ffi.scope
    }
}
```

Locked design points:

- The audit tags a **mint** (`Ptr[opaque].deref()`) and a **round-trip** (handle handed back to a
  raw pointer) **iff** the site is lexically inside an FFI region. One predicate serves both E0811
  and the audit — they cannot drift.
- The region predicate is **purely syntactic**, per-function, decided **pre-typecheck** from
  `let`/param annotations (no tids) — mirrors `collect_byte_pin_sites`.
- **Propagation is normative:** a closure literal inside a region inherits it; a named nested `fn`
  item does not (needs its own annotation/scope); a pointer that escapes its region dynamically is
  the scope-escape diagnostic E0601's concern, not E0811's.
- The canonical `open()` example is unchanged; the spec **rule text** was widened to name
  `ffi.scope`, reconciling §163/§211 with E0811's own help text (§379) and the worked example.
- Implementation (br `9jz9vk`) must add a CI property test asserting every `Ptr[opaque].deref()`
  site that compiles (passes E0811) is also tagged by the audit — binding the scanner's predicate
  to E0811's acceptance set.
