[< All Decisions](../DECISIONS.md)

# Effect Leaf Operations — Design Rationale

**Question.** May a top-level user effect declare operations without a sub-effect? §4.12 showed operations only inside sub-effects, and the parser required that (`expected effect, got fn`). But §4.6 *Unhandled user effects* (`effect Store { fn get(key: Str) -> Int }`), §4.7.1 *Completeness and auto-delegation* (`effect Cache { ... }`) and §7 (`effect Clock { fn now_ms() -> Int }`) used the flat form. During the debate the panel found that §4.4.3 declared the built-in `Env` with `fn exit` beside `effect Read` and `effect Write`, a mixed body.

**Result.** A leaf effect declares its operations directly. Every effect body, built-in or user-declared, holds operations or sub-effects, never both. §4.4.3 moves `exit` into a child `Env.Exit`, which amends the *env.exit() placement* and *Env sub-effect granularity* rows ([Env Effect API](env-effect-api.md) Q3, Q4). All nine questions passed 6-0; Q2 passed 6-0 in Phase D after 4-2 in Phase C.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Each panelist wrote their own text to a file; the sections below copy those files without edits, except that a panelist's headings appear as bold lines.

#### Phase A — Independent proposals

##### Systems

**Proposal 1 (recommended): an effect body holds either operations or sub-effects, never both**

```blink
effect Clock {
    fn now_ms() -> Int
}

effect DB {
    effect Read { fn query(sql: Str) -> List[Row] }
    effect Write { fn exec(sql: Str) -> Int }
}

fn stamp() -> Int ! Clock {
    clock.now_ms()
}

fn main() {
    with handler Clock { fn now_ms() -> Int { raw_clock_ms() } } {
        stamp()
    }
}
```

**Rule**

1. An `effect` body must be one of three kinds:
   - **Empty or absent**: a marker leaf, such as `effect Arena`.
   - **Only `fn` signatures**: a leaf effect with operations.
   - **Only `effect` children**: a parent effect.
2. A body that mixes `fn` and `effect` items is an error. I propose a new code, `MixedEffectBody` (E05xx). The diagnostic should suggest moving the `fn` items into a named child.
3. A leaf's operations belong to the leaf itself. `! Clock` grants `clock.now_ms`, the handle is `clock`, and the ops are spelled `clock.op` (already decided).
4. `Handler[Clock]` is one vtable whose slots are the leaf's ops in the order they are declared. A leaf has no children, so projection does not apply to it. `Handler[Clock.X]` is `UnknownEffect` (E0538).
5. Op names must be unique under one handle. This applies across all of a parent's children (`DB.Read.get` and `DB.Write.get` collide on `db.get`). It already follows from the flat `handle.op` spelling, but the spec should say it outright.
6. The spec states the nesting depth: top-level plus one level of children. That is what the parser does today.

The three flat-form examples (§4.6, §4.7.1, §7) stay as written. The parser and the op-registration walk change to accept them.

**Why ban mixing.** §4.3 defines `! FS` as sugar for `! FS.Read, FS.Write, …`. If a parent can own ops directly, that sugar breaks: the parent holds a capability that no child grants and no `! P.Child` row can name. Projection also gets worse. `Handler[P]` → `Handler[P.Child]` drops the parent-owned slots, so you can never build a narrower handler that carries them. If the body is either all ops or all children, the vtable of a parent is exactly the union of its children's slots. Projection then stays a slot copy with no exceptions to check.

**What it costs at run time.** Nothing new. A leaf with ops builds the same structure a sub-effect builds today: one evidence-vector entry and one vtable struct with N function pointers. An op call is one evidence load plus one indirect call, the same as `db.query`. A one-op leaf such as `Clock` is a single-slot struct, and the compiler can inline it when the handler is statically known. The two-level form gives none of that a speed benefit.

**Why not desugar the flat form into a hidden child.** It adds an unnamed capability to diagnostics, effect rows and `Handler[...]` type names. The vtable layout is identical either way, so the hidden name buys nothing. Treat the leaf as its own capability.

**Compiler change.** In `parse_effect_decl`, branch on the first body token (`fn` or `effect`), parse the rest as that kind, and report E05xx on the other kind. Typecheck and codegen add one case: when the top-level node has `methods`, register `{handle}.{op}` from it. The vtable emitter already lays out a children-with-methods node, and a leaf is that same shape.

**Proposal 2 (rejected): keep the parser and rewrite the examples**

The examples would become `effect Clock { effect Now { fn now_ms() -> Int } }`.

- Every single-capability effect would need a made-up child name, and the extra level gives no extra grant precision. You would only ever write `! Clock.Now`.
- Users could not express what the built-in `Rand` already is: a leaf with ops (`rand.int`, `rand.float`, `rand.bytes`). The spec would allow a shape for the compiler that users cannot write.
- This one costs nothing at run time either, but it is ceremony that blocks nothing.

**Cross-language notes**

- **Koka and Eff**: effects are flat lists of ops, with no hierarchy. Proposal 1 keeps that common case one level deep.
- **Rust traits**: the closest comparison is trait objects, where a vtable holds only the trait's own methods, and supertrait upcasting needed special vtable layout work to land. Banning mixed bodies keeps Blink's projection a plain slot copy.
- **Zig**: interfaces are hand-written vtable structs. A leaf effect here is exactly one such struct, which keeps the C we emit predictable.

**Summary**

Allow leaf effects with operations. Ban bodies that mix `fn` and `effect` items. Fix the parser and the op-registration walk, keep the three examples as they are, and state the depth limit and the unique-op-name rule in the spec.

##### Web/Scripting

**Position: allow the flat form and fix the parser. Do not rewrite the examples.**

The spec authors wrote the flat form three separate times, and the most recent time was in a ratified panel. That is the strongest evidence we have about what people will type. A JS or Python developer who wants a mockable clock writes `effect Clock { fn now_ms() -> Int }`. If we force `effect Clock { effect Now { fn now_ms() -> Int } }`, they must invent a sub-effect name that means nothing, only to satisfy the parser. That costs one Stack Overflow question per new user, and the answer would be "because the grammar says so." The spec also already has leaf effects with operations: `Rand` (`rand.int`) and `Validation` (`validation.contract_violation`, §4.4 / §4.5). Users should be able to declare what the stdlib has.

**Proposal 1 (primary): a body holds either operations or sub-effects, never both**

```blink
effect Clock {
    fn now_ms() -> Int
}

effect Metrics {
    effect Emit {
        fn counter(name: Str, value: Int)
    }
    effect Query {
        fn get(name: Str) -> List[Int]
    }
}

fn stamp() -> Int ! Clock {
    clock.now_ms()
}

fn main() {
    with handler Clock { fn now_ms() -> Int { 42 } } {
        stamp()
    }
}
```

**Rule:**
- An effect body contains either only `fn` operation signatures (a **leaf effect with operations**) or only nested `effect` declarations (a **parent effect**). Mixing the two in one body is a compile error. Suggested message: "effect `X` declares both operations and sub-effects; move the operations into a sub-effect."
- `effect X` with no body stays an op-less marker. `effect X {}` means the same thing, and `blink fmt` rewrites it to the bare form.
- Effect rows: `! Clock` grants all of Clock's operations. A leaf has no children, so `! Clock.Now` is `UnknownEffect` (E0538). Operations are not effects, so `! Clock.now_ms` is also E0538, and the error should hint "`now_ms` is an operation of `Clock`; write `! Clock`."
- Handle and ops: the handle is the lowercase effect name, and calls are `clock.now_ms()`. The `{handle}.{op}` key is unchanged.
- `Handler[Clock]` is a full handler for the leaf. A leaf has no sub-effects, so projection never applies to it. `handler Clock { ... }` may be partial and auto-delegates exactly as today. The panic message names `clock.now_ms`.
- Op names stay unique across the whole tree (already true, since ops share one handle namespace).

**Why ban mixing:** if `Metrics` held `fn flush()` and also had `Emit` and `Query` children, nobody could say without reading the spec whether `! Metrics.Emit` grants `metrics.flush()`. Each answer is a trap for someone. Banning the mix now costs nothing. If a real need shows up later, allowing it does not break anyone's code. Keeping it allowed and banning it later would.

**Tradeoffs:**
- (+) Matches what the spec authors, LLMs, and newcomers write naturally. Fewer names to invent. Three spec examples become correct with no edits.
- (+) Small compiler change. The parser already collects a top-level `methods` list. Typecheck and codegen must register a leaf's ops under `{handle}.{op}`, the same key they use today.
- (−) Two shapes of effect body instead of one. The either/or rule keeps that cost low, and the mixing error points straight at the fix.
- (−) Moving from a leaf to a tree later is a breaking change for callers who wrote `! Clock`. That is acceptable: `! Clock` keeps working after the split, because the parent grants all its children. Only handler declarations need to move.

**Proposal 2 (fallback, which I oppose): keep two levels mandatory**

Rewrite §4.6, §4.7.1 and §7 to use sub-effects, and add a grammar production for that. This needs no compiler work, but it makes every one-op effect pay for a name with no meaning, and it leaves `Rand` and `Validation` as built-ins that user code cannot express. If the panel takes this route, the parse error must at least say "effect operations must be inside a sub-effect, e.g. `effect Clock { effect Read { fn now_ms() ... } }`" instead of "expected effect, got fn".

**Also needed: state the grammar in §2**

Whichever proposal wins, add an explicit `effect` body production to §2. The fact that three examples drifted from the parser shows that prose alone does not hold the line.

**Cross-language note**

Koka (`effect state { fun get() : int }`), OCaml 5 effect declarations, Unison abilities, and TypeScript/Kotlin interfaces all let you put operations directly on the declared name. Nested groups are opt-in structure everywhere else. Making them mandatory would make Blink the odd one out, and it would be the first thing a newcomer hits when writing their first effect.

##### PLT

**Proposal 1 (preferred): every effect-tree node is a leaf XOR an interior node**

```blink
effect Store {
    fn get(key: Str) -> Int
    fn put(key: Str, value: Int)
}

effect Metrics {
    effect Emit { fn counter(name: Str, value: Int) }
    effect Query { fn get(name: Str) -> List[Int] }
}

fn load() -> Int ! Store {
    store.get("count")
}

fn main() {
    let h = handler Store {
        fn get(key: Str) -> Int { 0 }
        fn put(key: Str, value: Int) { }
    }
    with h { load() }
}
```

**Rule.** An effect body contains either operation declarations (`fn`) or child effects (`effect`), never both. Recursively, at every level:

- **Leaf** `L` (body empty or only `fn` items): ops(L) = its declared ops. Covers built-in `Rand` (leaf with ops) and markers like `Arena` (leaf, zero ops).
- **Interior** `P` (only `effect` items): ops(P) = disjoint union of ops(C) over children C.
- **Mixed body** (`fn` and `effect` in one body): compile error, new E05xx `MixedEffectBody`.
- **Op names are unique across one top-level tree** (error otherwise), since calls are flat `handle.op`. The handle namespace is the whole tree. (Already implied by the implementation; the spec must state it.)

**Typing.**
- `! E` grants ops(E). `! L.X` for a leaf L is `UnknownEffect` (E0538).
- `Handler[L]` is the record over ops(L). Projection `Handler[E]` → `Handler[E']` is legal iff E' is a node in E's subtree; it restricts the record to ops(E'). A leaf has no proper subtree, so `Handler[L]` projects only to itself.
- Completeness, auto-delegation and E0539 are unchanged: each is already stated over ops(E).

**Why forbid mixed bodies (soundness of the tree model).** §4.3 says "a parent effect grants all of its children". That makes a parent *extensional*: it IS the union of its children. If `Metrics` also had its own `fn reset()`:
1. ops(Metrics) ≠ ops(Emit) ∪ ops(Query). `! FS` stops being sugar for `! FS.Read, …`.
2. `reset` has no minimal grantable name. It can't be granted alone, which violates "children are independently grantable".
3. Projection stops being restriction to a named node; you'd need a "Metrics minus children" type that doesn't exist.

With the rule, each op has exactly one minimal grantable name (its declaring leaf). The effect lattice stays a free join-semilattice over leaves. Row subsumption, projection and handler completeness all become plain set operations on leaves, and they compose.

**Parser/checker work.** `parse_effect_decl` accepts top-level `fn` items when the body has no `effect` item. Typecheck/codegen walk the tree with one recursive "collect ops of node" function, which also drops the depth-2 special case. (The depth limit is a separate question: state "no limit" or an explicit limit; this rule doesn't depend on it.)

**Spec edits.** §4.12 states the leaf/interior rule. The three flat examples (§4.6, §4.7.1, §7) become correct as written. §2 gets a production:
`EffectDecl ::= 'effect' Name ( '{' (FnSig* | EffectDecl*) '}' )?`

**Tradeoffs.**
- Gain: `effect Clock { fn now_ms() -> Int }` is the most common user effect. Forcing a meaningless child (`effect Clock { effect Now { … } }`) adds a name to every row and handler for zero expressiveness.
- Gain: parity with built-in `Rand`. Today the spec describes a form users cannot write.
- Cost: a user who later splits `Store` into `Store.Read`/`Store.Write` must move ops into children. Rows saying `! Store` keep working (parent = all children), and so do handlers saying `handler Store { … }` (completeness is over ops(E)). The split is source-compatible for callers and handler authors; only the declaration changes.

**Cross-language.** Koka effects are flat op sets with no hierarchy; our leaf is exactly a Koka effect, and our interior node is a named row alias. OCaml 5 effects are individual ops; grouping is user convention. Neither language mixes "own ops" with "sub-capabilities" in one node, which supports the XOR rule.

**Proposal 2 (rejected): rewrite the three examples to a sub-effect**

Sound, but it keeps a built-in form (`Rand`) that users cannot write and forces dummy children on every simple effect.

**Proposal 3 (rejected): mixed bodies, with parent's own ops in an implicit anonymous child**

Parent-level ops become grantable only via the whole parent. That breaks independent grantability (§4.3), and projection then depends on an unnameable node.

**Vote: Proposal 1.**

##### DevOps/Tooling

**DevOps/Tooling panelist: Phase A proposal (z4xxkg)**

Evidence first. The spec authors wrote the flat form three times without noticing it was illegal. One of those was the panel that just ratified the unhandled-operation rule. When the people who wrote the spec reach for a form by instinct, users and LLMs will reach for it too. Blink already has a leaf effect with operations: the built-in `Rand` (`rand.int(...)`). Only users have no syntax to declare one.

---

**Proposal 1 (preferred): a leaf effect may declare operations; an effect body is all ops or all children**

```blink
effect Clock {
    fn now_ms() -> Int
}

effect Store {
    fn get(key: Str) -> Int
    fn put(key: Str, value: Int)
}

fn load() -> Int ! Store {
    store.get("count")
}

fn main() {
    with handler Store {
        fn get(key: Str) -> Int { 0 }
        fn put(key: Str, value: Int) { }
    } {
        print(load())
    }
}
```

**Rule**
1. The body of a top-level `effect` holds either only `fn` signatures (a leaf with ops) or only `effect` children (a tree, as today). If the body is empty or has no braces, the effect is an op-less marker.
2. **Mixing them is an error:** a new code, `MixedEffectBody` (E05xx). Why: today a parent means exactly the union of its children (§4.3). Ops placed directly on a parent that has children would be a capability with no name. `! Store.Read` could not say whether it grants `store.get`. I will not invent a rule for that in v1.
3. A leaf effect's ops are called as `handle.op`, the same as today. Ops register under `{handle}.{op}`, so the typecheck and codegen keys do not change. Only the walker gains a "leaf methods" path.
4. A leaf effect has no children, so `Handler[Store]` has no projection. `! Store.Get` is `UnknownEffect` (E0538), and the diagnostic adds the note "`Store` is a leaf effect; its operations are `get`, `put`".
5. Handlers, auto-delegation, the `<handle>.<op>` panic and E0539 all apply unchanged. A leaf effect is a tree with one node.

**Diagnostics**
```
error[MixedEffectBody]: effect `Store` declares both operations and sub-effects
  --> app.bl:3:5
   |
 3 |     fn get(key: Str) -> Int
   |     ^^^^^^^^^^^^^^^^^^^^^^^ operation declared on parent effect
 5 |     effect Admin { ... }
   |     ------ sub-effect declared here
   = help: move `get` into a sub-effect, e.g. `effect Read { fn get(...) }`
```
Today's error, "expected effect, got fn", is the worst kind of message: it names a token, not the concept. Whichever proposal wins, the parser must stop producing it.

**Tooling**
- LSP completion on `store.` lists the ops directly. Hover on an op shows `Store.get` for a leaf and `Metrics.Emit.counter` for a tree. One hover format covers both shapes.
- "Add missing effect" code actions insert `! Store`, not an invented sub-effect.
- `blink fmt` puts one op per line and rewrites `effect X {}` to `effect X`.
- `blink doc` renders a leaf effect as one table of ops.

**Tradeoffs:** a small parser change, plus one walker branch in typecheck and codegen. The three spec examples become legal as written. One fix is still needed: §4.7.1 separates ops with `;`, and Blink has no semicolons, so that example must change either way.

**Cross-language:** Koka (`effect state { fun get() : int }`), Unison abilities and OCaml 5 effects all declare flat ops. Nobody coming from those languages expects a mandatory middle level.

---

**Proposal 2 (fallback): keep the two-level rule and rewrite the three examples**

```blink
effect Clock {
    effect Read {
        fn now_ms() -> Int
    }
}
fn now() -> Int ! Clock.Read { clock.now_ms() }
```

**Rule:** ops appear only inside a sub-effect. A `fn` directly in an effect body is a parse error, `OpOutsideSubEffect`. Its help text gives the rewrite that wraps the op in a sub-effect, and `blink fix` can apply it mechanically.

**Tradeoff:** less work in the compiler, but every user hits this ceremony on their first effect. It also leaves the user model different from the built-in `Rand`, which is a leaf with ops. We would have to explain that difference forever in docs and in `blink llms`. I vote against this unless the panel finds a real problem with leaf semantics.

---

**Sub-question I raise for the panel:** the spec states no depth limit, and the parser allows exactly two levels. Whichever proposal wins, the spec should state "max depth 2" explicitly. Grandchildren should get a named diagnostic, not "expected fn, got effect".

##### AI/ML

**Proposal 1 (recommended): leaf effects may declare operations; an effect body holds ops XOR sub-effects**

```blink
effect Store {
    fn get(key: Str) -> Int
    fn put(key: Str, value: Int)
}

fn load() -> Int ! Store {
    store.get("count")
}

fn main() {
    let h = handler Store {
        fn get(key: Str) -> Int { 0 }
        fn put(key: Str, value: Int) { }
    }
    with h { load() }
}
```

**Rule.** An effect is a node in the effect tree. Its body takes one of three forms:
1. **No body** (`effect Rand`): marker leaf, no operations.
2. **Operations only** (`effect Store { fn get(...) }`): leaf with operations.
3. **Sub-effects only** (`effect Metrics { effect Emit { ... } }`): interior node.

Operations live on leaves only. A body that mixes `fn` and `effect` is a compile error (`MixedEffectBody`, fix-it: "move these operations into a sub-effect, e.g. `effect Ops { ... }`").

Semantics of the leaf form:
- **Rows:** `! Store` grants all of Store's operations. Store has no children, so `! Store.Get` is `UnknownEffect` (E0538).
- **Handle:** lowercase top-level name, unchanged: `store.get(...)`. A top-level leaf is exactly the built-in `Rand` shape (`rand.int`); the spec's own `Rand` stops being a special case.
- **`Handler[Store]`:** one vtable over all ops. Projection (`Handler[DB]` -> `Handler[DB.Read]`) does not apply — no children. Partial handlers, auto-delegation, `<handle>.<op>` panic, and E0539 apply unchanged.
- **Grammar:** add a production to §2 (none exists today; that absence is why this ticket happened).

**Why forbid mixing.** Ops on a parent would be grantable only by granting the whole parent: an un-nameable capability that breaks §4.3 "children are independent capabilities". It also adds a decision point ("does this op go on the parent or a child?") with no principled answer, which models would resolve inconsistently.

**Proposal 2 (rejected): keep parser, rewrite the three examples**

```blink
effect Store { effect Ops { fn get(key: Str) -> Int } }
fn load() -> Int ! Store.Ops { store.get("count") }
```

**Tradeoffs (AI/ML)**

- **Empirical signal from the spec itself.** Three independent spec authors — including the panel that just ratified E0539 — wrote the flat form unprompted. When Blink-literate writers produce a form, LLMs will too. Rejecting the most natural form makes a first-try parse error in a common pattern.
- **Training-data prior.** Every mainstream effect system declares ops flat: Koka (`effect state { fun get() : int }`), OCaml 5, Unison abilities, Eff, Effekt. Proposal 2 fights all of them.
- **Decision points.** Proposal 2 forces the writer to invent a meaningless sub-effect name (`Ops`? `Main`? `Self`?) — a new choice with no right answer, and code will fragment across names. Proposal 1 adds one rule ("ops on leaves") that generalizes to any depth.
- **Tokens.** For the common single-capability effect, flat saves ~6-8 tokens per declaration and 2 per row (`! Store` vs `! Store.Ops`); rows repeat on every signature, so the row saving dominates.
- **Learnability.** Proposal 1 is one sentence a model can learn from the spec alone, with an error message that names the fix.

**Cross-language note**

Koka/Effekt have no hierarchy, so all their effects are leaves. Blink adds hierarchy for capability grants. Proposal 1 keeps both: flat when there is one capability, tree when there are several.

**Sub-questions flagged**

- **Depth:** the parser caps at two levels; the spec is silent. State "operations live on leaves" depth-independently; defer whether to state a depth limit to DevOps/Systems.
- **Leaf -> tree evolution:** promoting `Store` to have children later breaks every `handler Store { fn get }`; rows survive (`! Store` keeps meaning). Small migration cost; worth one note in the spec.

##### Minimalism

**Minimalism panelist: Phase A proposal (z4xxkg)**

**Recommendation (Proposal A): allow operations directly on a top-level leaf effect. The grammar gets one rule: an effect body holds operations or sub-effects, never both.**

```blink
effect Store {
    fn get(key: Str) -> Int
    fn put(key: Str, value: Int)
}

fn load() -> Int ! Store {
    store.get("count")
}

handler Store {
    fn get(key: Str) -> Int { 0 }
    fn put(key: Str, value: Int) { }
}

fn main() {
    with Store.handler() { load() }   // install form per §4.7, unchanged
}
```

**Rule**

1. `effect E` with no body declares a marker effect. `effect E { }` means the same thing.
2. If an effect body contains `fn` signatures, E is a **leaf with operations**. Its body can contain only `fn` signatures.
3. If an effect body contains `effect` children, E is a **parent**. Its body can contain only `effect` children. Each child follows rules 1 and 2. Depth stays at two levels, which is what the parser does today and what the spec shows.
4. A body that mixes `fn` and `effect` items is a parse error: "an effect body holds operations or sub-effects, not both".
5. Effect rows: `! Store` grants every operation of Store. `Store.X` is `UnknownEffect` (E0538), because a leaf has no children.
6. Handle: `store`, with operations spelled `store.get` and registered under the key `store.get`. This is the same rule as today.
7. `Handler[Store]` covers the full operation set. No projection applies because a leaf has no children. Auto-delegation, the panic on a missing operation, and E0539 apply without change.

**Why this is subtraction, not addition**

- The shape already exists in two places. A sub-effect body is "a leaf with operations": the parser's child loop calls `parse_effect_op_sig`. The spec's built-in `effect Rand` is a top-level leaf with a handle and operations (`rand.int`, `rand.float`). Today that shape is legal one level down and legal for built-ins, but illegal for a user effect at the top. Removing that asymmetry makes the grammar shorter to state. It does not add a feature.
- Rejecting the flat form taxes the most common case. A user who wants one capability with two operations must invent a child name: `effect Store { effect Access { fn get ... } }`, then write `! Store` or `! Store.Access` with no reason to pick one over the other. That is ceremony with no meaning. Go, Lua, and Scheme all let the simplest case be written in its simplest form.
- Three spec examples already use the flat form. The people who wrote the spec reached for it without thinking, which is evidence it is the natural form.

**Why mixed bodies are forbidden (rule 4)**

Allowing `effect Store { fn get(...); effect Admin { fn wipe() } }` raises questions we do not need to answer:
- Does `! Store.Admin` grant `get`?
- Is there an implicit unnamed child for the top-level operations?
- What vtable slots does `Handler[Store.Admin]` project?

That combinatorial cost buys nothing. If you need a split, move `get` into a named child. Forbidding mixed bodies keeps the meaning of "parent = sum of its children" exact (§4.3). We can relax this later without breaking code. Tightening it after we allow it would break code.

**Proposal B (fallback: do nothing to the language)**

Rewrite the three examples in §4.6, §4.7.1 and §7 to use a sub-effect. This has zero compiler cost. I reject it as the main option because:
- it leaves the user-facing language unable to express what `Rand` already is;
- it makes every small effect pay a naming tax forever.

A one-time change to the parser and registration code is cheaper than either of those.

**Cost**

- Parser: in `parse_effect_decl`, if the first body token is `fn`, parse operation signatures into `methods` on the top-level node. Otherwise use the current child loop. Reject a mixed body.
- Typecheck and codegen publish: walk the top-level `methods` the same way they walk a child's `methods`. Each operation still registers under `{handle}.{op}`.
- No new keyword, no new node kind, no new diagnostic class apart from the mixed-body parse error.

**Cross-language note:** Koka, Eff and OCaml 5 effects all declare operations directly on the effect, and none of them has a mandatory grouping level. Blink's hierarchy is a feature for granting capabilities piece by piece. It should be opt-in, not a cost on every declaration.

**Vote intent:** Proposal A, with mixed bodies forbidden.

#### Phase B — Debate

All six put "leaf effects may declare operations; a body holds `fn` items or `effect` items, never both" first. Round 1 debated seven variations (depth, error class, grammar, unique op names, diagnostic notes, `effect X {}`, leaf-to-tree evolution). Web's round-1 reply raised the §4.4.3 `Env` mixed body; round 2 covered only that fact.

##### Round 1

**Systems:**

**A vs B vs C:** A, unchanged. Reject B (ceremony, users cannot write what built-in `Rand` is). Reject C (parent-owned slots that no child row can name; projection stops being a pure slot copy).

**Variations**

1. **Depth.** State the leaf rule depth-independently ("operations live only on leaves"), as plt and aiml say. Separately, the spec states the current limit as two levels, and a grandchild gets a named diagnostic (devops). Lifting the limit is its own ticket. Systems note: depth costs nothing at run time. A tree of any depth still flattens to one vtable, the union of leaf ops in declaration order, and projection to any subtree is a slot copy. So the limit is an implementation and readability choice, not a cost one. Tie this ticket to no particular depth.
2. **Error class.** A new code, `MixedEffectBody` (E05xx), reported by the parser. min's "parse error, no new class" and a named code are not in conflict: every parse error the user sees needs a stable name for `blink llms` and fix-its. One code, not a generic UnexpectedToken.
3. **§2 production.** Yes. Adopt plt's: `EffectDecl ::= 'effect' Name ( '{' ( FnSig* | EffectDecl* ) '}' )?`, with the depth limit stated in prose beside it while it exists.
4. **Op names unique across one top-level tree.** Yes, state it. One handle means one flat op namespace, and one vtable means one slot per name. Without this rule, `db.get` is ambiguous at the call site, and so is the slot.
5. **Diagnostic notes.** Support both web's and devops's notes. They are cheap and point the reader at the right row.
6. **`effect X {}`.** Same as `effect X`: a marker leaf with a zero-slot vtable. `blink fmt` rewrites it to the bare form.
7. **Leaf-to-tree evolution (factual).** plt and web are right, and aiml is wrong. A handler for a parent effect already lists its ops flat, with no child grouping. See the spec at §4.7 (`handler DB { … }`) and `tests/test_resqj9_with_field_operand.bl`, where `handler Metrics { fn counter … }` covers `Metrics.Emit.counter`. When `Store { fn get; fn put }` becomes `Store { effect Read { fn get } effect Write { fn put } }`:
   - `handler Store { fn get … fn put … }` still compiles, because completeness is over ops(Store).
   - The `! Store` rows still compile, as do `store.get` calls and `Handler[Store]` values.
   - Only the declaration changes, and callers may now narrow to `! Store.Read`.

   At the C level, the vtable for `Handler[Store]` keeps the same slots. If the split keeps op order, the layout is the same too. Blink compiles the whole program, so even a reorder breaks no ABI. aiml: please check this against the test above before we vote.

**Response to named panelists**

- **aiml:** see item 7. Given the evidence, I ask aiml to withdraw "breaks every handler".
- **plt:** I agree that a recursive "collect ops of node" walk should replace the depth-2 special case in typecheck and codegen, whatever the stated limit is. A recursive walk lets the limit live in one place (the parser diagnostic), not in three.

STABLE, ready to vote.

**Web/Scripting:**

**NEW FACT: the spec already contains a mixed body (§4.4.3 Env)**

Nobody's Phase A noticed it. sections/04_effects.md §4.4.3 (lines 708-736) declares:

```blink
effect Env {
    effect Read { fn args() -> List[Str] ... fn cwd() -> Str }
    effect Write { fn set_var(name: Str, value: Str) ... }
    fn exit(code: Int) -> Never      // parent-level op
}
```

and its table says `! Env` grants "all of the above plus `env.exit(...)`". Line 747 says "`env.exit()` requires `! Env` (the parent)". So option A's "never both" rule contradicts a normative section as it stands. The ballot must pick one:

- **A + amend §4.4.3 (my pick):** move `exit` into a child: `effect Env { effect Read {...} effect Write {...} effect Exit { fn exit(code: Int) -> Never } }`. `! Env` still grants `env.exit`, and `! Env.Read` still cannot call it, so no existing user code breaks. `handler Env { ... fn exit ... }` (§4.4.3 test, §8.10 `mock_env`) keeps working by the variation-7 rule. Bonus for users: a CLI can now ask for `! Env.Exit` alone (least privilege), and the plt soundness argument holds without exceptions.
- **A' (mixed allowed, Env's rule generalised):** a parent's own ops are granted only by the whole parent. This matches §4.4.3 today, but it gives an op that has no name of its own to grant, which breaks "children independently grantable" (plt's point 2). It also means one more rule for newcomers to learn.

I take A + amend. "Ops live on leaves" is one sentence a JS dev can keep in their head. "Ops can live anywhere, but parent ops need the whole parent" is the kind of rule people learn only from a Stack Overflow answer. The compiler checks this capability in typecheck (src/typecheck.bl ~24517 lists `exit` among Env methods), so the amendment needs a matching compiler change. That belongs in the implementation ticket.

**A vs B vs C**

A, with §4.4.3 amended as above. Reject B and C.

**Variations**

1. **Depth:** state "at most two levels: top-level plus one level of children" for v1. Grandchildren get a named diagnostic. Relaxing the limit later breaks nothing. Deeper trees mean more names to learn, and no one has asked for them (YAGNI). plt's recursive "collect ops" walk is a fine implementation either way.
2. **Mixed-body error:** a named code, `MixedEffectBody` (E05xx), with fix-it text: "move the operations into a sub-effect, e.g. `effect Exit { fn exit(...) }`". Named codes are searchable, and that matters more than whether the parser or the checker reports it.
3. **§2 production:** yes. Use plt's production, but encode the depth limit:
   `EffectDecl ::= 'effect' Name ( '{' ( FnSig* | ChildEffect* ) '}' )?`
   `ChildEffect ::= 'effect' Name ( '{' FnSig* '}' )?`
4. **Unique op names across one top-level tree:** yes, state it in the spec.
5. **Diagnostic notes:** merge devops's note and mine. For `! Store.Get` or `! Store.get`, E0538 adds the note "`Store` is a leaf effect; its operations are `get`, `put`; write `! Store`."
6. **`effect X {}`:** means the same as `effect X`; `blink fmt` rewrites it to the bare form.
7. **Leaf-to-tree evolution:** I concede to plt. §4.4.3 itself shows `handler Env { fn args ... fn set_var ... fn exit ... }`, a handler on a parent that lists child ops, so completeness is over ops(E) and handlers survive a split. I withdraw "only handler declarations need to move". aiml's claim that a split "breaks every `handler Store { fn get }`" is wrong for the same reason. A split is source-compatible for rows, calls and handlers.

**To named panelists**

- **plt:** your soundness argument is the reason I keep "never both", but §4.4.3 is a live counterexample in the spec. Please confirm the Env amendment (move `exit` into a child, `Env.Exit`) satisfies your model.
- **min:** the amendment adds one child to a built-in effect and takes away one special rule ("parent-own ops need the whole parent"). The rule count goes down.

STABLE, ready to vote, provided the ballot includes the §4.4.3 Env item (A + amend, or A').

**PLT:**

**A vs B vs C:** unchanged. A. B is sound but leaves the built-in `Rand` form unwritable by users. C breaks independent grantability (§4.3).

**1. Depth.** I now take a position: state the limit (top-level plus one level of children), and word the leaf/interior rule so it doesn't depend on depth. Soundness doesn't need a limit; the semilattice argument works at any depth. But the parser, typecheck and codegen implement depth 2, no one has shown a use for grandchildren, and lifting a stated limit later is additive. Grandchildren get a named diagnostic. The implementation should still collect ops recursively over the tree, so lifting the limit later is a grammar change only.

**2. Error class for a mixed body.** A named code. Given the production in (3), the parser can detect and report it. I don't care whether it is numbered as a parse error or as E05xx. It must have its own name and a message that says "an effect body holds operations or sub-effects, not both". A generic UnexpectedToken is not enough. This is compatible with min's "parse error" if min accepts that the parse error has a name.

**3. §2 production.** Yes. Revised so the grammar itself encodes depth 2 and the XOR rule:
```
EffectDecl ::= 'effect' Name EffectBody?
EffectBody ::= '{' ( OpSig* | SubEffect* ) '}'
SubEffect  ::= 'effect' Name ( '{' OpSig* '}' )?
```
A mixed body and a grandchild then fall out of the grammar. Each gets its own named diagnostic (2, 1).

**4. Op names unique across one top-level tree, stated in the spec.** Yes, normative. It is *forced*, not stylistic. Calls are `handle.op`, and a handler body is a flat list of ops. The §4.7 `handler DB { fn read … fn write … fn admin … }` example covers ops from three sub-effects with no grouping. Two ops named `get` in one tree would make both the call site and the handler body ambiguous.

**5. Diagnostic notes.** Support both web's and devops's notes as implementation quality. The normative part is only that `! Leaf.X` is E0538. The notes need not be in the spec.

**6. `effect X {}`.** The same as `effect X`: a leaf with zero ops. In my semantics, ops(X) = ∅ in both cases, so they are the same declaration. What `blink fmt` does with it is a tooling choice; no objection.

**7. Leaf-to-tree evolution: aiml is wrong, web is half right.** The spec answers this. In §4.7 *Defining a handler*, `handler DB { fn read … fn write … fn admin … }` writes ops from three different sub-effects as one flat list. A handler body is keyed on ops(E), not on the shape of the tree. So splitting `effect Store { fn get; fn put }` into `effect Store { effect Read { fn get } effect Write { fn put } }` keeps all of these:
- `! Store` rows (parent = all children)
- `Handler[Store]` types
- `handler Store { fn get … fn put … }` bodies (ops(Store) did not change)

The split breaks only if ops are added or renamed, and that breaks a leaf too. So for callers and handler authors, the split is source-compatible. web's "only handler declarations need to move" and aiml's "breaks every `handler Store { fn get }`" both contradict the DB example. aiml's own case `handler Store { fn get }` (missing `put`) is incomplete before the split too. If it is a partial handler, it auto-delegates the same way before and after. If the spec gets a note, it should say the split is compatible.

STABLE, ready to vote.

**DevOps/Tooling:**

**A vs B vs C:** A. B is my fallback only. Reject C: an implicit anonymous child is a capability that the LSP cannot name in hover, completion or E0538 notes.

**Correction accepted:** the `;` in §4.7.1 came from the brief, not the spec. I withdraw that point.

1. **Depth:** take plt's split. The spec states "operations live on leaves", which holds at any depth, and it states an explicit v1 limit of two levels (top-level plus children). A grandchild is a named error, not "expected fn, got effect". Raising the limit later does not break anything; removing a limit once users depend on it being absent is not possible. The compiler should walk the tree with one recursive "ops of node" function so a later raise costs nothing.
2. **Mixed body:** a named diagnostic class, `MixedEffectBody`. min is right that the parser detects it. But the class name is what users search for and what LSP code actions key on, and a bare "parse error" gives neither. The error points at both the first `fn` and the first `effect`. The help text gives the move-into-sub-effect fix. Zero extra node kinds.
3. **§2 production:** yes, plt's form: `EffectDecl ::= 'effect' Name ( '{' (FnSig* | EffectDecl*) '}' )?`. The depth limit goes in prose next to it. Without a production, this gap repeats.
4. **Op names unique across one top-level tree:** yes, state it. It follows from the `{handle}.{op}` key. A duplicate needs its own diagnostic that names both declaring sub-effects (`Metrics.Emit.get` and `Metrics.Query.get`), not a generic redefinition error.
5. **Diagnostic notes:** take both. web's note covers an op written as a sub-effect (`! Clock.now_ms` → "write `! Clock`"). Mine covers an invented child on a leaf (`! Store.Get` → "`Store` is a leaf; ops: get, put"). They are two branches of one E0538 note: test whether the name after the dot is an op of the effect.
6. **`effect X {}`:** same as `effect X`. `blink fmt` rewrites it to the bare form.
7. **Leaf-to-tree evolution:** plt and web are right, and aiml is wrong. The spec already writes `handler DB { ... }` with flat ops over a parent with children (§4.7 line ~1214, §4.7.1 ~1686), and completeness is over ops(E). A split changes only the declaration. Rows survive (`! Store` = all children), handler sources survive, and call sites survive (`store.get`). The spec should state this as one sentence so users know a split is safe.

**To aiml:** your claim on 7 conflicts with existing spec text: `handler DB` lists ops from `DB.Read` and `DB.Write` flat. Unless you have a case I missed, please drop it.

STABLE, ready to vote

**AI/ML:**

**A vs B vs C:** A, unchanged. B and C rejected.

1. **Depth.** I move to sys/devops/min: state the limit explicitly as top-level plus one level of children. Give a grandchild its own named diagnostic. Also state "operations live on leaves" as the general rule, so the text holds if a later panel lifts the limit. A limit stated in the spec is something a model can learn. A limit that is silent in the spec and enforced only by the parser shows up as a confusing parse error. Deeper trees also add a "how deep?" decision with no use case today.
2. **Mixed-body error.** A named code, `MixedEffectBody` (E05xx), with a fix-it: "move these operations into a sub-effect". The phase it fires in does not matter to me (parser is fine). The name and the fix-it do matter, because they are what a model repairs from.
3. **§2 production.** Yes. Use plt's production with the depth limit applied: `EffectDecl ::= 'effect' Name ( '{' (FnSig* | SubEffectDecl*) '}' )?` and `SubEffectDecl ::= 'effect' Name ( '{' FnSig* '}' )?`.
4. **Op names unique across one top-level tree.** Yes, state it. `handle.op` is one flat namespace per top-level effect, so the spec must say so.
5. **Diagnostic notes.** Use both: E0538 on `! Store.Get` / `! Clock.now_ms`, a note listing the leaf's operations, and the hint "write `! Clock`". The two proposals are compatible.
6. **`effect X {}`.** Same as `effect X`. `blink fmt` rewrites it to the bare form. That gives one canonical spelling.
7. **Leaf-to-tree evolution.** I concede to plt and web. §4.7.1 completeness covers all ops of the named effect, and the spec already writes `handler DB { ... }` for a parent (04_effects.md:1214). So after a split, `handler Store { fn get ... }` stays valid. Rows (`! Store`) and calls (`store.get`) stay valid too. Only the declaration changes. I withdraw my "breaks every handler" claim. The split is source-compatible, which makes the leaf form even cheaper to adopt.

**To devops:** with the `;` correction, B's case gets weaker still. All three spec examples already use the canonical one-op-per-line form.

STABLE, ready to vote

**Minimalism:**

**Minimalism: Phase B round 1 (z4xxkg)**

**A vs B vs C:** I hold A. B is my fallback. I reject C: the implicit anonymous child is hidden surface, and nobody needs it.

**1. Depth.** Keep exactly two levels and state that in the spec: top-level, then one level of children. A grandchild is an error. I accept plt's recursive "collect ops of node" as an implementation choice, but the spec should not promise unlimited depth. Nobody has asked for three levels, and no code in stdlib, tests or src uses them. A limit we state now can be relaxed later without breaking code. A "no limit" promise cannot be taken back.

**2. Mixed-body error code.** I accept a named code, `MixedEffectBody` (E05xx). My Phase A wording ("no new diagnostic class apart from the mixed-body parse error") already allowed one. A named code costs nothing in the language and helps tools and LLM repair. For a grandchild, one more named code is fine. I would not mint more than those two.

**3. Grammar in §2.** Yes. Today the form exists only in prose and examples, and that is how this gap appeared. Put the depth rule in the grammar so the prose cannot drift from it again:

```
EffectDecl  ::= 'effect' Name ( '{' ( FnSig* | ChildEffect* ) '}' )?
ChildEffect ::= 'effect' Name ( '{' FnSig* '}' )?
```

This is plt's production, split into two rules so it states depth 2.

**4. Op names unique across one top-level tree.** Yes, state it. It is not a new rule. It follows from "ops are spelled `handle.op` whichever child declares them", and the spec should say so outright.

**5. Diagnostic notes (web's and devops's E0538 hints).** I support both. They are tool text on an existing code, with no language surface. Merge them into one: `! Store.Get` → E0538, note "`Store` is a leaf effect; its operations are `get`, `put`; write `! Store`".

**6. `effect X {}`.** It means the same as `effect X`. `blink fmt` rewrites it to the bare form. It should not be an error: an error here would be one more special case, and the grammar above already accepts the empty body.

**7. Changing a leaf into a tree (factual).** plt and web are right, and aiml is wrong. In the spec (§4.7, "Defining a handler", sections/04_effects.md about line 1214), a handler for a tree names the root and lists the ops flat, for example `handler DB { fn read ... fn write ... fn admin ... }` against `Handler[DB]`. The tests do the same with `handler Metrics { fn counter }` over `Metrics.Emit`. So after `Store` is split into children:
- `handler Store { fn get ... }` still compiles, because completeness is checked over ops(Store);
- `store.get` still resolves;
- `! Store` still grants everything;
- `Handler[Store]` keeps the same meaning.

Only the declaration changes. A handler written for one child (`handler Store.Read`) is new code, not a break.

**To aiml:** this removes your main risk for A. Splitting a leaf into a tree later is source-compatible, so A does not lock anyone in.

STABLE, ready to vote.

##### Round 2 — the §4.4.3 `Env` mixed body

**Systems:**

**Position: A, with §4.4.3 amended to `effect Exit { fn exit(code: Int) -> Never }`**

I agree with web. I get there from the systems model, not from the newcomer argument.

**What a mixed body costs the compiler.** With "never both", an effect row normalizes to a set of leaves. A parent is the OR of its children's leaf bits. Row checks (subsumption, the E0539 discharge check, projection coverage) are then a bitset subset test, with no special cases. A mixed body breaks this:

- `Env` needs a bit of its own for `exit`.
- `! Env.Read, Env.Write` no longer equals `! Env`. The §4.3 sugar ("`! FS` is sugar for its children") gets one exception, and every row check has to carry it.

The vtable itself costs nothing either way. `Handler[Env]` has read, write and exit slots, and projection to `Env.Read` drops the exit slot correctly. The cost falls on row semantics, and through them on every reader. That is what we should guard.

**Why not A' (mixed allowed).** It keeps one shape in the language that has exactly one instance, a built-in. It also breaks the parent-equals-union invariant above for user effects too.

**Why not a built-in-only exception** (user effects get "never both", built-in `Env` keeps its shape). In round 1, I rejected B because users could not write what built-in `Rand` is. The same argument cuts here. §4.4.3 is printed in declaration syntax, so readers and LLMs will copy it and get `MixedEffectBody`. A built-in must be expressible in user syntax.

**The amendment:**
```blink
effect Env {
    effect Read { ... }
    effect Write { ... }
    effect Exit {
        /// Terminate the process with an exit code.
        fn exit(code: Int) -> Never
    }
}
```
- `! Env` still grants `env.exit`.
- `! Env.Read` and `! Env.Write` still do not.
- `handler Env { ... fn exit ... }` still compiles (flat op list; see round 1, item 7).
- The capability table gains a row: `! Env.Exit` = `env.exit(...)`.
- Implementation: the hard-coded env namespace list in src/typecheck.bl (~24517) maps `exit` to `Env.Exit`, not to the `Env` parent. The impl ticket must cover this, as web says.

**Does this reopen the ratified Env rows?**

Yes, narrowly, and only in letter.

- **"env.exit() placement" (5-0).** The row's substance stays: exit lives under Env, is spelled `env.exit(code) -> Never`, is tracked as an effect and can be caught by a handler, and Read or Write alone cannot reach it. The one change: `! Env.Exit` alone now grants it, where the row said "requires `! Env`". That widens what a caller can ask for. It does not widen what any existing row grants. Every program valid today stays valid with the same meaning.
- **"Env sub-effect granularity" (5-0).** That row rejected splitting *Read* (no `Env.Args`) and rejected flattening. `Exit` splits neither. It gives an existing op a grantable name. It does add a third child, which is the "decision point" aiml worried about. In practice that decision rarely comes up: code that exits writes `! Env` today and can keep writing it.

**Justification.** Both rows were decided before anyone asked whether an effect body may mix ops and children. A ratified example should not be the only instance of a shape the language otherwise forbids. Amending the example costs one spec edit and one table row. Keeping it costs a permanent exception in every row check.

If the panel prefers to leave those rows untouched, my second choice is A' over a built-in-only exception. Even then, I hold that A plus the amendment is right.

STABLE, ready to vote.

**Web/Scripting:**

**I withdraw `Env.Exit`**

The moderator's facts change my answer. `Env.Exit` reopens both ratified 5-0 rows: "exit requires `! Env` (parent)" and "Keep Env.Read + Env.Write, no third child". The only gain is consistency for a built-in effect that users never declare. No user has asked for `! Env.Exit` alone, and the aiml rationale for two children ("a third = 50% more decision points") is a DX argument I agree with. Reopening two unanimous rows to tidy one spec code block is a bad trade.

**My answer: rule A governs user declarations; §4.4.3 stays, labelled as built-in**

- **User-declared effects:** rule A as voted. A body holds ops or sub-effects, never both. `MixedEffectBody` otherwise.
- **§4.4.3 semantics:** unchanged. `env.exit` stays a parent-only op that needs `! Env`. The compiler already does this through its hard-coded `env` namespace, not through a parsed declaration, so no compiler change follows.
- **§4.4.3 text:** add one sentence right after the code block:
  "`Env` is built-in. `exit` is a parent-only operation: only `! Env` grants it. User-declared effects cannot declare one; their operations live on leaves (§4.12)."
  Also add a short comment on the `fn exit` line inside the block: `// built-in only: parent-level op`.
- **§4.12:** state the general fact once: "A built-in effect may have a shape that user declarations cannot express. Today the only case is `Env.exit`, a parent-only operation (§4.4.3)."

Why this matters for DX: §4.4.3 is the most-read effect example in the spec, and people and LLMs copy it. Without the label, someone pastes the shape into their own effect, gets `MixedEffectBody`, and files a "the spec's own example doesn't compile" bug. That is how this ticket started. The label plus the comment turns that into a 5-second read. The `MixedEffectBody` fix-it text should not suggest the Env shape.

**Does this reopen a ratified row?**

No. Both Env rows stand as written. The only new text is a label and a cross-reference.

**Rejected alternatives**

- **A' (mixed bodies legal for users, Env's rule generalised):** every user learns a rule that only one built-in needs. I am still against it.
- **Env.Exit (my round-1 pick):** reopens two 5-0 rows for no user-facing gain. Withdrawn.

STABLE, ready to vote.

**PLT:**

**Diagnosis.** The spec is already inconsistent with itself, whatever we decide on z4xxkg:
- §4.3 says a parent is its children: `! FS` is sugar for `! FS.Read, FS.Write, …`.
- §4.4.3 gives `Env` an op of its own. So ops(Env) ≠ ops(Env.Read) ∪ ops(Env.Write), and `! Env` is not sugar for `! Env.Read, Env.Write`.

So "A' vs A + amend" is not a new question. Ruling for A' means rewriting §4.3 as well.

**Position: one rule for every effect declaration, built-in or user. Amend §4.4.3 with a child `effect Exit { fn exit(code: Int) -> Never }`.** This is web's shape, and it fits my model exactly.

**Reject a carve-out for built-ins** ("XOR for user effects, Env is special"). I argued for A from the parity of built-in `Rand` with user effects. A built-in shape that users cannot declare is the same gap in reverse. A mock `handler Env` also has to be typed against ops(Env), and users write those.

**Reject A'** (mixed bodies, where a parent's own ops need the whole parent).
- It is sound. Typing still works with ops(P) = own(P) ⊎ ⋃ ops(C), and projection is still restriction.
- But every own op can only be granted as a bundle with all of its siblings. `env.exit` needs no read or write authority. Bundling it with them gives the caller authority it never uses: a real loss of least authority with no benefit.
- It also makes parent rows intensional everywhere. Readers and tools can no longer expand `! E` to its children.

**What changes in §4.4.3 (and §4.3's tree listing):**
- `effect Env { effect Read {…} effect Write {…} effect Exit { fn exit(code: Int) -> Never } }`.
- Capability table: add `! Env.Exit` → `env.exit(...)`. `! Env` stays "all of the above".
- Prose: "`env.exit()` requires `! Env.Exit` (granted by `! Env`); `! Env.Read` or `! Env.Write` alone cannot call it." The motivation sentence ("neither observation nor mutation, it is process termination") now supports a separate child, which says this better than "requires the parent" did.

What keeps working: the handle `env`, the call `env.exit(1)`, every `! Env` row, every `handler Env { … fn exit … }` (ops(Env) is unchanged), and the E-diagnostic for `! Env.Read` code that calls exit. Every program that compiles today still compiles. The only new thing is that `! Env.Exit` is allowed. The compiler's hard-coded `env.*` table (typecheck.bl ~24517) needs one entry remapped, and the impl ticket must list it.

**Does this reopen the ratified rows?**
- *Q3 "env.exit() placement" (5-0):* the substance is kept. What Q3 decided, and what all five rationales argue, is "on the `env` handle, not a `Process` effect, not a free fn, handler-interceptable, `-> Never`". All of that stays. Only the clause "Requires `! Env` (parent)" changes. No ballot option set child against parent, and no rationale defends the parent requirement. It came in as a side effect of the placement choice. Amending one clause that nobody debated, to restore a §4.3 invariant, is justified. I flag it plainly so the ballot records it as an amendment and not as silent drift.
- *Q4 "Env sub-effect granularity" (5-0):* the letter is touched, the substance is not. Q4 rejected `Env.Args` (splitting Read) and flattening. `Exit` does neither, and adds no new op. AI/ML's "third sub-effect = more decision points" applies only weakly. A user who wants exit writes `! Env`, as today. `! Env.Exit` is optional extra precision that no one is forced to choose. If the panel finds this decisive, the fallback I'd accept is A' limited to a closed list of built-in effects, recorded as a known exception to §4.3. I rank it below the amendment.

STABLE, ready to vote. Ballot item: A + Env.Exit amendment (preferred) vs A' (reject).

**DevOps/Tooling:**

**Position change: I now vote A' (mixed bodies legal; an op declared on a node needs that node's full capability). I withdraw `MixedEffectBody` (round-1 item 2). §4.4.3 does not change.**

**The rule (one recursive rule, no special cases)**

An effect node may declare ops, children, or both. Granting a node grants its own ops plus all of its children. An op declared directly on a node is granted only by that node, never by one of its children.

- A leaf with ops (`effect Store { fn get ... }`) is the case "a node with ops and no children". The three flat examples stay legal.
- A pure tree (`DB`, `Metrics`) is the case "a node with children and no own ops". Nothing changes.
- `Env` is the case "both". `env.exit` needs `! Env`, and `! Env.Read` does not grant it. That is exactly the ratified text.

This replaces "never both". It is simpler to state, to implement and to show in tooling. The walker is one recursion: ops(node) = own ops ∪ ops(children). Completeness for `Handler[E]` is over ops(E). Projection to `Handler[E.Child]` takes ops(E.Child) only, so the parent's own ops are not included.

My round-1 objection was that "`! Store.Read` could not say whether it grants `store.get`". The ratified Env row already answers it: no. The capability has a name, the parent. It needs no anonymous child (C stays rejected).

**Diagnostics and tooling**

```
error[UndeclaredEffect] (E0500): `env.exit` requires `! Env`
  --> cli.bl:4:9
   |
 1 | fn run_cli() ! Env.Read, IO {
   |                -------- grants Env.Read only
 4 |         env.exit(1)
   |         ^^^^^^^^ declared on `Env` itself, not on a sub-effect
   = help: change `Env.Read` to `Env`
```
- LSP hover on an op shows the node that grants it: `Env.exit` (requires `Env`), `Env.Read.args`.
- Completion on `env.` under `! Env.Read` hides `exit` or marks it "needs `! Env`".
- `blink fmt` keeps the source order. I propose no reorder rule; YAGNI.

**Why not web's `Env.Exit` amendment**

It reopens both 5-0 rows:
- The placement row says exit "Requires `! Env` (parent)". With an `Env.Exit` child, `! Env.Exit` alone grants it.
- The granularity row says "Keep Env.Read + Env.Write", with no third child, and the AI/ML rationale names the cost of a third child explicitly.

Neither row has a new fact against it. The only new fact is that our "never both" draft clashes with them. When a fresh draft clashes with two ratified 5-0 rows, the draft should give way. Also, a sandbox that may exit but not read argv has no real use.

**Why not "built-ins may mix, users may not"**

The spec shows `Env` in user declaration syntax. Users and LLMs copy spec code blocks. A form the spec prints but users cannot write is the bug class this ticket exists to close (`Rand` was the first case).

**Spec edits**

- §2 production: `EffectDecl ::= 'effect' Name ( '{' ( FnSig | EffectDecl )* '}' )?`, with the depth limit in prose (two levels in v1, as in round 1).
- §4.3/§4.12, one sentence: "An operation declared directly on an effect requires that effect; a sub-effect does not grant it."
- §4.4.3: no change. It becomes the worked example of that sentence.
- Round-1 items 1, 3–7 stand. The leaf-to-tree split (item 7) stays source-compatible: the ops move into children, `handler Store` still covers all ops, and rows using `! Store` still grant all of them.

**Reopens a ratified row?**

No. This answer codifies both Env rows as written.

STABLE, ready to vote

**AI/ML:**

**Principle from my seat:** a spec code block written as `effect X { ... }` is a template that models copy. If §4.4.3 shows a mixed body while the user rule forbids one, models will write mixed user effects and hit `MixedEffectBody`. A built-in may have privileges, but it must not be *displayed* in a user-illegal shape. So "built-ins are exempt, leave §4.4.3 as is" is the one answer I reject outright.

**Rule for user effects:** A, unchanged ("ops live on leaves; no mixed body"). A' (mixed bodies allowed) is rejected. It turns the most common example in the spec into a second rule ("a parent's own ops need the whole parent"), which models must learn and apply inconsistently.

**§4.4.3, first choice: web's amendment.** Move `exit` into a child `effect Exit { fn exit(code: Int) -> Never }`. What stays the same:
- `env.exit(...)` spelling.
- `! Env` grants it.
- `! Env.Read` / `! Env.Write` still cannot call it.
- `handler Env { ... fn exit ... }` (completeness is over all ops of Env).
- `main`, which holds `! Env` anyway.

What is new: `! Env.Exit` alone grants exit. The capability table gains one row, and §4.4.3 then obeys the same rule as every user effect. One rule with zero exceptions is the cheapest thing for a model to learn.

**Does it reopen the ratified rows?**
- *"env.exit() placement" (requires `! Env`):* partly. The ratified *reason* (decisions/env-effect-api.md; spec prose: "neither pure observation nor environment mutation — it is process termination") is fully kept, because Exit is its own capability, distinct from Read and Write. Only the means changes: "the parent" becomes "the parent or its own Exit child". The reopening is justified because the old means is now inexpressible under a rule all six seats chose. Keeping it would leave the spec with an example that contradicts its own grammar.
- *"Env sub-effect granularity" (Read + Write, no Args):* I don't think so. That row rejected splitting *observation* (Args out of Read). My quote there ("adding third = 50% more decision points") was about the Read/Write choice every env-reading function makes. Exit adds no choice to that path. Code that reads env still picks Read or Write. Only code that calls exit outside main would ever name `Env.Exit`, and it can still write `! Env`. If the panel reads the row as "exactly two children", then this reopens it, for the same reason as above.

**Fallback if the panel will not touch either row:** keep Env's semantics exactly (exit needs `! Env`, no Exit child) and rewrite the §4.4.3 block so it is not a declaration. Show the Read and Write children as declarations and list `exit` separately under "Operations of the parent (built-in only)", with a sentence saying user effects cannot declare parent-level ops. This is worse (a permanent built-in-only capability shape), but it still keeps every `effect { }` block in the spec user-legal.

**Impl note:** agree with web. The hard-coded `env.*` grant list (src/typecheck.bl ~24517) must map `exit` to `Env.Exit` | `Env`, and a test must prove `! Env.Read` still rejects `env.exit`.

STABLE, ready to vote

**Minimalism:**

**Minimalism: Phase B round 2 (z4xxkg), the §4.4.3 Env mixed body**

**My answer (A + built-in exception): keep "never both" for user-declared effects. Leave the semantics of §4.4.3 unchanged. Add one sentence to §4.4.3 and one to §4.12 saying that Env's parent-level `exit` is a built-in exception that user syntax cannot write.**

Proposed text:
- §4.12: "A user effect body holds operations or sub-effects, not both (`MixedEffectBody`). The built-in `Env` (§4.4.3) is the only effect with an operation on a parent. That shape is reserved to the compiler."
- §4.4.3, under the block: "This block shows the built-in API. It is not a user declaration: `exit` sits on the parent so that only full `! Env` grants it, and user effects cannot declare this shape (§4.12)."

**Why not web's amend (a new `Env.Exit` child)**
- It reopens both ratified rows. Q3 says exit "Requires `! Env` (parent)", and `! Env.Exit` alone would break that. Q4 says "Keep Read + Write", 5-0, and the AI/ML reason given there was that a third child adds decision points.
- It changes behavior that people chose on purpose. The Q3 panel wanted exit to need full Env authority. A least-privilege `! Env.Exit` is a new feature that nobody asked for. Adding a feature to make a grammar rule tidy is the wrong order of things.
- It adds surface: a new grantable name, an E0538 path, and a docs row.

**Why not A' (allow mixed bodies, where parent ops need the whole parent)**
- It turns one built-in special case into a general rule for every user. That brings in the questions from Phase A: an op with no grantable name of its own, what projection does with parent-owned slots, and one more rule for newcomers.
- No user effect in the spec, stdlib, tests or src needs a parent-only op. Generalizing a rule that has exactly one user is YAGNI.

**Why the exception is acceptable**
- Built-in effects are already outside user syntax. The compiler does not parse Env from a declaration: `env.*` comes from a hard-coded intrinsic list (src/typecheck.bl, `register_intrinsic_fn_sig("env.exit", ...)`). Until this ticket, `Rand` was also a shape users could not write. One documented exception for one built-in is cheaper than a new rule for everyone.
- This order keeps every option open. If a real user effect later needs a parent-only op, a future panel can relax `MixedEffectBody` into A'. That change is additive and breaks nothing. Web's amend, by contrast, changes the meaning of a ratified row today and cannot be undone without a break.
- Training-data risk is small and bounded. An LLM that copies the Env shape into a user effect gets `MixedEffectBody`, a named error with a fix-it, and repairs it in one step. The note in §4.4.3 tells human readers the same thing.

**Ratified rows:** this reopens neither one. Q3 (exit requires parent `! Env`) and Q4 (only Read + Write) stand as written. The only thing that changes is that the "never both" rule is scoped to user-declared effects.

**Implementation:** no compiler change is needed for Env. The parser's `MixedEffectBody` check applies only to parsed declarations, and Env is not one.

**To web:** I agree that the ballot needs this item. I ask that it carry three options: (a) A + amend with `Env.Exit`, (b) A', and (c) A + built-in exception (mine).

STABLE, ready to vote.

#### Phase C — Final vote

##### Q1: May an effect declare operations directly in its body? (6-0 for A)

**Systems:**

1. **Vote** — A.
2. **Reasoning** — A leaf with ops compiles to the same thing a sub-effect does today: one evidence entry and one vtable struct with N function pointers, one evidence load plus one indirect call per op. B adds a name level that buys no grant precision and no speed, and leaves users unable to write what built-in `Rand` already is. C puts parent-owned slots behind a capability no row can name, so projection stops being a plain slot copy.
3. **Concern** — The op-registration walk in typecheck and codegen gains a top-level `methods` path, and if the impl adds it as a third special case beside the depth-2 child loop (not one recursive walk), the shapes will drift again.

**Web/Scripting:**

1. **Vote** — A
2. **Reasoning** — `effect Store { fn get(key: Str) -> Int }` is the form a JS/Python/TS dev writes first, because it reads like an interface. Three spec examples already use it, so readers have learned it. B adds a wrapper with no meaning to the smallest useful effect, and a newcomer cannot explain why it is needed.
3. **Concern** — The parser fix lands without the §4.12 prose and §2 grammar, so the next reader again learns the form only from examples.

**PLT:**

**Vote:** A
**Reasoning:** A leaf with ops is exactly a Koka effect: ops(L) is its declared set, and `! L`, `Handler[L]`, completeness, auto-delegation and E0539 are all already stated over ops(E), so no typing rule changes. It also closes the gap where the built-in `Rand` is a shape no user can declare. B is sound but adds a mandatory node with no meaning in the capability lattice; C makes a parent's own ops grantable only through an unnamed node.
**Concern:** The implementation may add a "top-level methods" branch next to the depth-2 child walk instead of one recursive ops(node) function, and the two paths will drift.

**DevOps/Tooling:**

1. **Vote:** A
2. **Reasoning:** Today's "expected effect, got fn" is a token-level error on the form that three spec examples, users and LLMs all reach for first. The flat form gives the simplest tooling surface: `store.` completion lists ops directly, and "add missing effect" inserts `! Store`, not an invented middle child. It also makes the built-in `Rand` shape something users can write, so `blink doc` and hover render one leaf format for built-in and user effects.
3. **Concern:** The parser fix lands but typecheck/codegen still skip the top-level `methods` list, so a flat effect parses and then fails later with an unrelated error. The impl ticket must test the full path (parse, row check, handler, call).

**AI/ML:**

1. **Vote** — A.
2. **Reasoning** — Three spec authors wrote the flat form without thinking, so models will write it too. Every effect system in the training data (Koka, OCaml 5, Unison, Effekt) declares ops flat. B makes the writer invent a child name (`Ops`? `Main`?) that has no right answer, so code splits across names. The flat form also saves tokens on every row (`! Store` against `! Store.Ops`).
3. **Concern** — If the parser change and the three examples do not land together, the spec and the compiler disagree again and models learn from whichever one they saw last.

**Minimalism:**

1. **Vote:** A
2. **Reasoning:** This removes an asymmetry. It adds no feature. A child body already holds ops, and the built-in `Rand` is already a top-level leaf with ops. Option B taxes the most common effect with a child name that means nothing, and C adds a hidden capability that nobody asked for.
3. **Concern:** Users may treat "leaf with ops" as the default and never split effects into children, so the hierarchy gets little use. That is acceptable.

##### Q2: Bodies with both ops and sub-effects, and the built-in §4.4.3 `Env` (4-2 for Q2-a; web and min dissent for Q2-c → Phase D)

**Systems:**

1. **Vote** — Q2-a (never both, amend Env with an `Exit` child). Second choice Q2-b; Q2-c last.
2. **Reasoning** — With never-both, every row normalizes to a set of leaves and a parent is the OR of its children's leaf bits, so subsumption, the E0539 discharge check and projection coverage are one bitset subset test. Q2-b and Q2-c both keep a node with its own bit, so `! Env.Read, Env.Write` stops equalling `! Env` and every row check carries an exception; Q2-c also prints a shape in declaration syntax that users who copy it will hit `MixedEffectBody` on. The amendment changes no program that compiles today: `! Env` still grants `env.exit`, Read or Write alone still does not, and `handler Env { ... fn exit ... }` keeps its flat op list. It touches the letter of two 5-0 rows (it adds a grantable `! Env.Exit` and a third child), not their substance, and I record that as a deliberate amendment.
3. **Concern** — If Q2-c wins, the built-in exception must live only in the hard-coded `env.*` grant table, never as a general parent-own-op path in the row checker, or the exception spreads to user effects by accident.

**Web/Scripting:** *(dissent)*

1. **Vote** — Q2-c (with aiml's variant: show §4.4.3 so it does not look like a declaration, and list `exit` separately as a built-in parent op)
2. **Reasoning** — Users get one rule to learn ("ops live on leaves") and both 5-0 Env rows stay as written. Nobody has asked for `! Env.Exit` alone, and a third child adds a choice to every env-touching signature. sys and aiml are right that people copy spec blocks, so a label is not enough: §4.4.3 must not show a shape users cannot write. aiml's variant fixes that without changing any semantics. If Q2-c loses, I rank Q2-a above Q2-b, because a rule for all users that only one built-in needs is the worst DX trade.
3. **Concern** — If Q2-a wins, the ballot record must state that it amends the "env.exit() placement" row (exit no longer needs the parent). Otherwise the docs, `blink llms` and DECISIONS.md will say different things.

**PLT:**

**Vote:** Q2-a ("never both" + amend Env with `effect Exit`)
**Reasoning:** §4.3 defines a parent extensionally (`! FS` is sugar for its children); under Q2-a every row normalizes to a set of leaves, so subsumption, projection and the E0539 discharge check are plain set operations with no exception. Q2-b is sound (ops(P) = own(P) ⊎ ⋃ ops(C)) but makes parent rows intensional everywhere and bundles an op with sibling authority it never uses; Q2-c keeps that same intensional node in the language and only hides it from users, while users still type `handler Env` mocks against it. I checked decisions/env-effect-api.md Q3: all five rationales argue for "under Env, on the `env` handle, interceptable, `-> Never`", and none defends the "parent only" clause, so the amendment changes one undebated clause and keeps every program that compiles today valid with the same meaning.
**Concern:** If Q2-a wins, the ballot record must state plainly that it amends the "env.exit() placement" row (and touches the letter of "Env sub-effect granularity"), and the impl ticket must remap `exit` to `Env.Exit` in the hard-coded `env.*` table with a test that `! Env.Read` still rejects `env.exit`.

**DevOps/Tooling:**

1. **Vote:** Q2-a ("never both" + amend Env with an `Exit` child). Second choice Q2-b, last Q2-c.
2. **Reasoning:** I change my round-2 vote. I said A' reopens no ratified text, and that is false: §4.3 (04_effects.md:179) says `! FS` and its child list "are identical to the compiler", and §4.4.3 already breaks that. A' would make that break general, so every tool that expands or minimizes a row (hover, the "narrow this row" lint, the "add missing effect" code action) would need a parent-own-ops case. Under Q2-a the code action for `env.exit` can insert `! Env.Exit` (least authority) and not `! Env`, which also grants Read and Write. The spec prints no block that users cannot write, and `MixedEffectBody` stays one rule with no exceptions. Q2-c keeps a printed form that users cannot declare, which is the bug class this ticket exists to close.
3. **Concern:** The amendment touches the letter of two 5-0 rows, so DECISIONS.md must record it as an explicit amendment, and the impl ticket must remap the hard-coded `env.exit` grant and test that `! Env.Read` still rejects `env.exit`.

**AI/ML:**

1. **Vote** — Q2-a (never both + amend Env with an `Exit` child).
2. **Reasoning** — A spec code block written as `effect X { ... }` is a template that models copy. Q2-a is the only option with one rule and no exceptions, and that is the cheapest form for a model to learn from the spec alone. Q2-c shows a model a shape it must never copy and depends on a note the model may skip. Q2-b adds a second rule ("a parent's own ops need the whole parent"), which models will apply inconsistently. My earlier "third child = more decision points" quote was about the Read/Write choice every env-reading function makes; `Exit` does not add to that choice, because code that exits can still write `! Env`.
3. **Concern** — If Q2-c wins, the §4.4.3 block must stop looking like a user declaration (list `exit` apart from the block), or models will copy the mixed shape and hit `MixedEffectBody`.

**Minimalism:** *(dissent)*

1. **Vote:** Q2-c
2. **Reasoning:** Q2-c changes the least. It reopens neither 5-0 row, needs no compiler change (Env comes from a hard-coded intrinsic list, not a parsed declaration), and adds no grantable name. Q2-a adds `! Env.Exit`, a new capability that nobody asked for, only to make one code block tidy. Q2-b turns one built-in's shape into a rule every user must learn. Q2-c is also the cheapest to change later: a future panel can relax `MixedEffectBody` into Q2-b or add `Env.Exit` without breaking code, but it cannot remove `Env.Exit` once code names it.
3. **Concern:** If Q2-a wins, `Env.Exit` stays in the language for good, and the implementation ticket can miss the remap of `exit` in the hard-coded `env.*` grant list. A test must prove that `! Env.Read` still rejects `env.exit`.

##### Q3: Depth (6-0 Yes)

**Systems:**

1. **Vote** — Yes.
2. **Reasoning** — Depth costs nothing at run time: a tree of any depth flattens to one vtable (the union of leaf ops in declaration order), and projection to any subtree is a slot copy. So the limit is a readability and implementation choice; stating two levels now matches the parser and can be lifted later without a break. One recursive ops walker keeps the limit in one place, the parser diagnostic.
3. **Concern** — Typecheck or codegen keeps a hard-coded two-level loop beside the new walker, so lifting the limit later needs three edits instead of one.

**Web/Scripting:**

1. **Vote** — Yes
2. **Reasoning** — Two levels covers every effect in the spec, stdlib and tests. Fewer levels means fewer names to learn. A grandchild with a named diagnostic is a one-search fix; "expected fn, got effect" sends people to Stack Overflow. We can lift a stated limit later without breaking code.
3. **Concern** — Someone builds the implementation with special cases for depth 2 instead of the one recursive walker, so lifting the limit later costs a rewrite.

**PLT:**

**Vote:** Yes
**Reasoning:** The leaf/interior rule and the join-semilattice argument hold at any depth, so the limit is a grammar fact, not a soundness fact. Stating top level plus one level of children matches the parser and every existing use, and lifting it later is purely additive if the ops walker is recursive. A grandchild gets its own named diagnostic.
**Concern:** If the spec words the ops rule in terms of "children" instead of "nodes", lifting the limit later will need a semantic rewrite rather than a grammar change.

**DevOps/Tooling:**

1. **Vote:** Yes
2. **Reasoning:** A stated limit gives a named grandchild diagnostic in place of "expected fn, got effect", and raising the limit later breaks nothing. One recursive ops walker keeps the limit in one place (the parser), so the LSP and codegen need no depth-2 special case.
3. **Concern:** The grandchild diagnostic gets added as a generic parse error under deadline pressure; it must have its own name and a fix-it.

**AI/ML:**

1. **Vote** — Yes.
2. **Reasoning** — A limit stated in the spec is a fact a model can learn; a limit only the parser enforces shows up as a confusing parse error. Wording the ops rule independent of depth keeps the text true if a later panel lifts the limit. No code in stdlib, tests or src uses grandchildren, so a deeper tree only adds a "how deep?" choice.
3. **Concern** — The grandchild diagnostic may be left as a generic parse error in the implementation if the impl ticket does not name it.

**Minimalism:**

1. **Vote:** Yes
2. **Reasoning:** Nothing in the spec, stdlib, tests or src uses three levels. A stated limit can be lifted later without breaking code, but a "no limit" promise cannot be taken back. A depth-independent rule and one recursive walker cost nothing and keep that later lift a grammar-only change.
3. **Concern:** The grandchild diagnostic is a second new code for a case almost nobody will hit. Keep it as a short named message and do not grow it.

##### Q4: Diagnostic for a forbidden body shape (6-0 Named)

**Systems:**

1. **Vote** — Named (`MixedEffectBody`, E05xx, with fix-it).
2. **Reasoning** — The check is one branch on the first body token in `parse_effect_decl`, so a named code costs nothing extra in the compiler. A stable name is what `blink llms`, LSP code actions and fix-its key on; a generic UnexpectedToken ("expected effect, got fn") is the message that caused this ticket.
3. **Concern** — The fix-it text must not suggest the Env parent-level shape, or it points users at the form it forbids.

**Web/Scripting:**

1. **Vote** — Named
2. **Reasoning** — A named code (`MixedEffectBody`) is something users can search for and an LLM can repair from. The fix-it ("move these operations into a sub-effect") turns the error into a one-step edit. A generic parse error tells the user where the error is but not what rule they broke.
3. **Concern** — The fix-it text shows or suggests the Env shape and so teaches the form it rejects.

**PLT:**

**Vote:** Named (`MixedEffectBody`, E05xx, with fix-it)
**Reasoning:** The forbidden shape is a rule of the effect calculus, not a token-level slip, so the error must name the concept: "an effect body holds operations or sub-effects, not both". Whether the parser or checker reports it matters less than a stable code that `blink llms` and fix-its can key on. A generic UnexpectedToken is what produced this ticket.
**Concern:** The fix-it may suggest a child name that collides with an existing child, or under Q2-c point users at the Env shape they cannot write.

**DevOps/Tooling:**

1. **Vote:** Named (`MixedEffectBody`, E05xx, with a fix-it)
2. **Reasoning:** Q2-a is my vote, so I reinstate the code I withdrew in round 2. The name is what users search for, what `blink llms` documents and what LSP code actions key on. The error points at both the first `fn` and the first `effect`, and the help moves the ops into a named child.
3. **Concern:** The fix-it must not suggest a child name the user then has to rename everywhere; it should leave the name as a placeholder the LSP selects for editing.

**AI/ML:**

1. **Vote** — Named (`MixedEffectBody`, with a fix-it).
2. **Reasoning** — A model repairs code from the error name and the fix-it text; "expected effect, got fn" names a token, not the rule. A named code is also what `blink llms` and search can key on.
3. **Concern** — The fix-it text could suggest the `Env` shape or an arbitrary child name; it must say "move the operations into a sub-effect" and show a neutral example.

**Minimalism:**

1. **Vote:** Named
2. **Reasoning:** A named code adds no language surface, and tools and LLMs use the name to find the fix. A generic "expected effect, got fn" is the error that started this ticket. One named code with a fix-it is the smallest correct answer.
3. **Concern:** The fix-it text might suggest the Env shape or some other mixed shape. It must only suggest moving the ops into a named child.

##### Q5: Operation names unique across one top-level tree (6-0 Yes)

**Systems:**

1. **Vote** — Yes.
2. **Reasoning** — One handle means one flat op namespace, and one vtable means one slot per name. Without the rule, `db.get` is ambiguous at both the call site and the vtable slot, and the flat handler body cannot say which `get` it implements.
3. **Concern** — The duplicate must get a diagnostic that names both declaring nodes, not a generic redefinition error from the `{handle}.{op}` registration map.

**Web/Scripting:**

1. **Vote** — Yes
2. **Reasoning** — Users call `store.get`, never `store.Read.get`, so the handle is one flat namespace, and the spec must say so. A duplicate `get` must get a clear error that names both sub-effects, not a confusing call-site ambiguity later.
3. **Concern** — The duplicate error comes out as a generic redefinition error that does not name both declaring sub-effects.

**PLT:**

**Vote:** Yes
**Reasoning:** This is forced, not stylistic: calls are `handle.op` and a handler body is one flat op list (§4.7 `handler DB { fn read … fn write … fn admin … }`), so two `get` ops in one tree make both the call site and the handler body ambiguous. Stating it makes ops(E) a set keyed by name, which every other rule (completeness, projection) already assumes.
**Concern:** The check may run per sub-effect instead of over the whole tree and miss `DB.Read.get` vs `DB.Write.get`.

**DevOps/Tooling:**

1. **Vote:** Yes
2. **Reasoning:** `handle.op` is one flat namespace, and handler bodies list ops flat, so a duplicate makes the call site and the handler body ambiguous. The duplicate needs its own diagnostic that names both declaring sub-effects (`Metrics.Emit.get`, `Metrics.Query.get`), not a generic redefinition error.
3. **Concern:** Under Q2-a the rule also applies to `Env`, so the hard-coded `env.*` table must be checked against it, not only parsed declarations.

**AI/ML:**

1. **Vote** — Yes.
2. **Reasoning** — Calls are `handle.op` and handler bodies are flat lists of ops, so one tree is one op namespace. Stating it outright removes a guess a model would otherwise make from examples.
3. **Concern** — The duplicate-op diagnostic should name both declaring sub-effects, or the repair is not obvious.

**Minimalism:**

1. **Vote:** Yes
2. **Reasoning:** This is not a new rule. Flat `handle.op` calls and flat handler bodies already force it. Writing it down costs one sentence and closes an ambiguity at both the call site and the handler.
3. **Concern:** The duplicate-name error might reuse a generic redefinition message that does not name both declaring sub-effects.

##### Q6: `effect X {}` means `effect X`; `blink fmt` rewrites it (6-0 Yes)

**Systems:**

1. **Vote** — Yes.
2. **Reasoning** — Both are a marker leaf with a zero-slot vtable; ops(X) is empty either way, so the compiler emits the same thing. One canonical spelling via `blink fmt` costs nothing.
3. **Concern** — Small: fmt must not drop comments inside a `{}` body that holds only comments when it rewrites to the bare form.

**Web/Scripting:**

1. **Vote** — Yes
2. **Reasoning** — Users coming from TS write `interface X {}` without thinking about it; an error on `{}` would be an annoying papercut. `blink fmt` then keeps one canonical spelling in real code and in training data.
3. **Concern** — An LSP or doc tool shows `{}` and the bare form differently and makes users think the two forms differ.

**PLT:**

**Vote:** Yes
**Reasoning:** Both denote a leaf with ops(X) = ∅, so they are the same declaration; a canonical spelling is a tooling choice I do not object to.
**Concern:** None of substance; only that the parser must not read `{}` as an interior node with zero children, which would make `! X.Anything` give a different diagnostic.

**DevOps/Tooling:**

1. **Vote:** Yes
2. **Reasoning:** One canonical spelling, and the fmt goldens pin it. It costs no grammar rule because the production already accepts an empty body.
3. **Concern:** `blink fmt` must keep a doc comment or line comment inside `{}` when it rewrites; if it drops one, it loses user text.

**AI/ML:**

1. **Vote** — Yes.
2. **Reasoning** — One canonical spelling means one form in the training data. Making `{}` an error would add a special case with no gain.
3. **Concern** — None of weight; `blink fmt` must apply the rewrite, or both spellings spread.

**Minimalism:**

1. **Vote:** Yes
2. **Reasoning:** The grammar already accepts an empty body, and both forms have zero ops. Making it an error would add a special case. Having fmt rewrite it to the bare form gives one canonical spelling at no cost to the language.
3. **Concern:** None of note. The fmt rule must not drop doc comments inside the empty braces.

##### Q7: Grammar production for effect declarations (6-0 Yes)

**Systems:**

1. **Vote** — Yes (production matching the Q2 outcome, depth limit in prose).
2. **Reasoning** — The three flat examples drifted from the parser because no production existed. With a production, a mismatch between spec and parser is visible in one place instead of being found by an MVCE.
3. **Concern** — If Q2-c wins, the production and the §4.4.3 block disagree, and the spec must say clearly which one is the normative grammar for user code.

**Web/Scripting:**

1. **Vote** — Yes
2. **Reasoning** — This ticket exists because the form was defined only by examples, and the examples drifted from the parser. A production is the single place that tooling authors, doc readers and models can check. It must match the Q2 outcome exactly.
3. **Concern** — Prose and grammar disagree on the depth limit; I would rather encode it in the grammar (ChildEffect rule) than in prose next to it.

**PLT:**

**Vote:** Yes
**Reasoning:** The absence of a production is the root cause of this ticket: three examples drifted from the parser because prose alone did not fix the form. Under Q2-a/Q2-c the production `EffectDecl ::= 'effect' Name EffectBody?`, `EffectBody ::= '{' ( OpSig* | SubEffect* ) '}'`, `SubEffect ::= 'effect' Name ( '{' OpSig* '}' )?` makes the XOR rule and the depth limit fall out of the grammar. The depth limit also stays in prose so it reads as a v1 limit, not a design law.
**Concern:** If Q2-c wins, the grammar will not cover `Env` as printed, and readers will treat the §4.4.3 block as a counterexample to §2.

**DevOps/Tooling:**

1. **Vote:** Yes (ops-only or sub-effects-only, per plt's round-1 form; depth limit in prose)
2. **Reasoning:** The missing production is why three examples drifted from the parser. A production also gives the formatter, the LSP parser and any tree-sitter grammar one source to match.
3. **Concern:** The production and the parser drift again unless a test parses every `effect` block in sections/ and checks it against the production.

**AI/ML:**

1. **Vote** — Yes.
2. **Reasoning** — The gap exists because the form lived only in prose and examples. A production is the most compact and exact way to teach a model the body shape. I prefer the form that puts the depth limit in the grammar (`SubEffect ::= 'effect' Name ( '{' OpSig* '}' )?`), but the ballot's "limit in prose" is acceptable.
3. **Concern** — If the production and the prose depth limit are not next to each other, a reader may take the grammar as allowing unlimited depth.

**Minimalism:**

1. **Vote:** Yes
2. **Reasoning:** This gap exists because the form lived only in prose and examples, and three examples drifted from the parser. A production matching the Q2 outcome (ops-only or children-only for Q2-a/Q2-c) stops that drift. I prefer the two-rule form (`EffectDecl` and `ChildEffect`) so the grammar itself states depth 2, but prose beside it is acceptable.
3. **Concern:** If the depth limit is only in prose, the production and the parser can disagree again. The diagnostic tests must cover a grandchild.

##### Q8: E0538 note for a row that names an op of a leaf (6-0 Yes)

**Systems:**

1. **Vote** — Yes.
2. **Reasoning** — The note is a lookup in data the checker already holds (the leaf's op list), with no run-time cost and no language surface. Only E0538 is normative, which is the correct split between spec and tooling.
3. **Concern** — Note text that lists ops for a large effect may grow long; cap the list or the note becomes noise.

**Web/Scripting:**

1. **Vote** — Yes
2. **Reasoning** — `! Store.Get` and `! Clock.now_ms` are the mistakes a newcomer will make, since they look like dotted paths in other languages. A note that lists the real ops and gives the fix stops the bug report. Keeping the note text non-normative lets tooling improve it without a spec change.
3. **Concern** — The note handles only the capitalized child guess and misses the lowercase op name, or the reverse; it must cover both.

**PLT:**

**Vote:** Yes
**Reasoning:** Only the E0538 is normative: an op is not an effect, and a leaf has no children, so both rows name nothing in the lattice. The note listing the leaf's ops and suggesting `! Store` is good guidance and costs the spec nothing.
**Concern:** The note text may be copied into the spec as normative, and then fixed wording becomes a compatibility burden.

**DevOps/Tooling:**

1. **Vote:** Yes
2. **Reasoning:** One branch of one note: test whether the name after the dot is an op of the effect, then list the leaf's ops and suggest `! Store`. Only E0538 is normative, so the note text can improve without a spec change.
3. **Concern:** The note lists ops in a different order from the declaration, which makes it harder to read than the source.

**AI/ML:**

1. **Vote** — Yes.
2. **Reasoning** — `! Store.Get` and `! Clock.now_ms` are the exact mistakes a model makes when it maps ops to capabilities. A note that lists the ops and says "write `! Store`" turns that into a one-step repair. Keeping only E0538 normative is right; note text is tooling.
3. **Concern** — The note must cover both branches (invented child and op-as-child) or one common mistake gets a bare error.

**Minimalism:**

1. **Vote:** Yes
2. **Reasoning:** Only the existing E0538 code is normative. The note is tool text and adds no language surface. It points the user straight at `! Store`, which is the whole fix.
3. **Concern:** Implementers may treat the example note text as normative and make golden tests that break every time someone edits the wording.

##### Q9: Splitting a leaf into sub-effects keeps rows, handlers and calls valid (6-0 Yes)

**Systems:**

1. **Vote** — Yes.
2. **Reasoning** — A handler body is keyed on ops(E), not tree shape (§4.7 `handler DB { ... }`; tests with `handler Metrics { fn counter }` over `Metrics.Emit`), so `handler Store`, `! Store`, `store.get` and `Handler[Store]` survive the split. At the C level `Handler[Store]` keeps the same slots, and since Blink compiles the whole program, even a reordered split breaks no ABI.
3. **Concern** — The spec sentence must not promise a stable vtable layout across a split, only source compatibility, so a future separate-compilation story is not boxed in.

**Web/Scripting:**

1. **Vote** — Yes
2. **Reasoning** — "Can I start simple and refactor later?" is the first question a scripting dev asks, and the answer is yes (the `handler DB { ... }` example proves it). One sentence saying so removes the fear that the leaf form locks users in, which makes A cheap to adopt.
3. **Concern** — The sentence fails to say that adding or renaming ops during the split is still a break, so users read it as a promise it does not make.

**PLT:**

**Vote:** Yes
**Reasoning:** A split leaves ops(Store) unchanged, and rows, `Handler[Store]`, handler completeness and `store.op` calls are all defined over ops(E) and the handle, not over tree shape; §4.7's flat `handler DB { … }` and §4.4.3's `handler Env { … }` already show handlers on a parent listing child ops. Stating it prevents the wrong belief (raised in Phase A) that a split breaks handlers.
**Concern:** The statement must say "if no op is added, removed or renamed", or readers will take it as a promise that any later change to the effect is compatible.

**DevOps/Tooling:**

1. **Vote:** Yes
2. **Reasoning:** The spec already writes `handler DB { ... }` with flat ops over a parent, so completeness is over ops(E) and a split changes only the declaration. Saying so in one sentence tells users that a split is safe, and it tells tool authors that a rename refactor does not need to touch handlers.
3. **Concern:** Readers take "source-compatible" to mean ABI-stable across separately built packages; the sentence should say "source".

**AI/ML:**

1. **Vote** — Yes.
2. **Reasoning** — I was wrong in Phase A on this, and the panel corrected me from §4.7 (`handler DB { ... }` lists child ops flat). One sentence in the spec tells writers that the leaf form does not lock them in, which removes a reason to add a needless child "just in case".
3. **Concern** — Under Q2-b the sentence needs a qualifier about parent-own ops, so its wording must match the Q2 outcome.

**Minimalism:**

1. **Vote:** Yes
2. **Reasoning:** This is a fact that follows from rules already in the spec: completeness is over ops(E), the §4.7 `handler DB` lists child ops flat, and a parent grants all its children. Stating it in one sentence removes the main reason to avoid the leaf form (fear of lock-in), and it adds no rule.
3. **Concern:** If Q2-b wins, a split that leaves some ops on the parent changes which rows grant them. The sentence must then cover only splits that move every op into a child.

#### Phase D — Round 2 (Q2 only)

Q2 was 4-2, so the panel debated Q2 alone for one more round and voted again.

##### Debate

**Systems:**

**The other side's strongest argument (min): Q2-c is the one you can undo**

min is right on the facts. Moving from Q2-c to Q2-a later breaks no code, because adding `Env.Exit` is additive. Moving from Q2-a back means removing `Env.Exit`, which breaks every signature that names it. I accept that asymmetry.

It still loses on cost, for three reasons.

1. **Q2-c is not free to keep.** Its cost does not show up as a breaking change. It shows up as a node with its own capability bit that lives in the compiler and the tools from day one:
   - The row checker cannot treat `! Env` as the OR of its children. `! Env.Read, Env.Write` does not grant `env.exit`, so subsumption, the E0539 discharge check and projection coverage each need an `Env`-own-op case.
   - devops listed the tool side: hover, the "narrow this row" lint, and the "add missing effect" code action each need the same case.

   That is one exception repeated in each consumer, and it lasts until some later panel buys it back. Q2-c avoids a breaking change that may never come, and pays a lasting tax to do it.
2. **What `Env.Exit` costs to keep forever is close to zero.** It is a plain leaf, one more bit in the row bitset. It needs one remap in the hard-coded `env.*` table and one row in the capability table. It has no special path in the checker, the vtable or the tools, and its run-time cost is nothing. When a name costs that little to keep, the irreversibility does not matter. min's own concern (a missed remap) is covered by the test plt and devops asked for: `! Env.Read` still rejects `env.exit`.
3. **"Nobody asked for `! Env.Exit`."** devops gave the user: the "add missing effect" code action for `env.exit`. Under Q2-c that action must insert `! Env`, which also grants every Read and Write op. That over-grants by default, in the one tool most users rely on to write effect rows. Under Q2-a it inserts `! Env.Exit`, which is least authority. A CLI helper such as `fn fail(code: Int) -> Never ! Env.Exit` is a real signature. Today it is forced to claim the whole environment.

On web's point that both 5-0 rows stay as written under Q2-c: plt checked decisions/env-effect-api.md Q3, and no rationale defends the "parent only" clause. Q2-a amends one clause nobody debated. Every program that compiles today stays valid with the same meaning. I agree with web and plt that DECISIONS.md must record this as an explicit amendment of "env.exit() placement", and note the letter change to "Env sub-effect granularity".

**Final Q2 position**

**Q2-a**: never both, and amend §4.4.3 with `effect Exit { fn exit(code: Int) -> Never }`. The impl ticket must:
- remap `exit` to `Env.Exit` in the hard-coded `env.*` grant table, and
- test that `! Env.Read` and `! Env.Write` reject `env.exit` while `! Env` and `! Env.Exit` accept it.

STABLE, ready to vote.

**Web/Scripting:**

**Final position: Q2-a. I switch from Q2-c.**

I proposed `Env.Exit` in round 1 and withdrew it in round 2 for one reason: it seemed to reopen two unanimous rows for no user gain. The Q2-a side has answered both parts of that.

**plt (the rows):** decisions/env-effect-api.md Q3 argues for "under Env, on the `env` handle, interceptable, `-> Never`". None of the five rationales defends the "parent only" clause. Q2-a keeps every point those rationales argued for, and every program that compiles today keeps its meaning. The clause that changes was never debated. That removes my main objection.

**aiml (the user gain, and my own DX objection):** I said a third child adds a choice to every env-touching signature. aiml is right that it does not. A function that reads env still picks Read or Write as before. Only code that exits sees `Exit`, and `! Env` still works for it. So the "more decision points" cost lands on almost nobody.

**devops (tooling):** under Q2-a the "add missing effect" code action can insert `! Env.Exit`, which is least authority, not `! Env`, which also grants Read and Write. Under Q2-c, every row tool (hover, row narrowing, code actions) needs a parent-own-ops case for one built-in. From a DX view, Q2-a also means one rule with no footnote: "ops live on leaves; a parent is its children." Nobody has to learn an exception, and nobody hits a Stack Overflow question titled "why can Env do this but my effect can't?"

**To min's strongest argument (irreversibility):** true, `Env.Exit` cannot be removed once code names it. But nobody would want to remove it. It is a narrow, correct capability, and naming it costs users nothing. "We could add it later" holds for Q2-a's benefits too, but Q2-c keeps a printed exception in the spec until then, and that exception is the bug class this ticket exists to close.

**Conditions I carry from my Phase C concern**

- DECISIONS.md records Q2-a as an explicit amendment of the "env.exit() placement" row (exit now needs `! Env.Exit` or `! Env`, not only the parent). It also records that the "Env sub-effect granularity" row gains a third child, `Exit`. Docs, `blink llms` and DECISIONS.md must agree.
- The impl ticket remaps `exit` to `Env.Exit` in the hard-coded `env.*` grant table, with a test that `! Env.Read` and `! Env.Write` still reject `env.exit`, and one that `! Env.Exit` alone accepts it.

STABLE, ready to vote.

**PLT:**

**Final position: Q2-a.**

**The strongest Q2-c argument is min's: reversibility.** "Q2-c is cheapest to change later. A future panel can relax `MixedEffectBody` or add `Env.Exit` without breaking code, but it cannot remove `Env.Exit` once code names it." I accept the premise: a grantable name is permanent. I reject the conclusion, because Q2-c is not the reversible, zero-cost option it looks like. It makes something else permanent, in a worse place.

1. **Q2-c puts a permanent exception into the core typing relation, not into a table.** Under Q2-c, `! Env.Read, Env.Write` does not subsume `! Env`. Every relation over rows has to know this: subsumption, the E0539 discharge check, projection coverage for `Handler[Env]` → `Handler[Env.Read]`, and the "rows are sets of leaves" normal form that sys and devops build their tools on. §4.3 (04_effects.md:179) says a parent and its child list "are identical to the compiler". Q2-c keeps that sentence false for a built-in for good. It is "reversible" only in the sense that a later panel could pay the cost Q2-a pays now. Until then, every row-handling feature is written with a special case. sys's concern (keep the exception confined to the `env.*` table) cannot be met fully, because the exception is about how rows relate, not about which op a name grants.

2. **"Nobody asked for `! Env.Exit`."** Least authority is not a feature that waits for a request. §4.3 states it as the model: "children are independent capabilities that can be granted individually". The question is not whether anyone wants `Env.Exit`. The question is whether `exit` must be bundled with authority it never uses, and nobody has argued that it must. The Q3 rationales argue only for "under Env, on the `env` handle, interceptable, `-> Never`", and Q2-a keeps all of that.

3. **"Q2-a adds a choice to every env-touching signature" (web).** It does not. Code that exits keeps writing `! Env`, as it does today. `! Env.Exit` is an optional narrowing. The only forced Env choice, Read vs Write, is unchanged. aiml, who wrote the original "decision points" quote, agrees.

4. **"Q2-c needs no compiler change" (min).** True today. But a code fix is one remap plus one test, and a typing-rule exception is permanent. A one-time edit is cheaper than an exception carried in every row checker forever.

5. **What Q2-c concedes.** web's own variant has to hide the §4.4.3 block so it doesn't look like a declaration. A form the language needs but cannot print is a sign that the form shouldn't exist.

**Record for the ballot** (same as my Phase C concern): Q2-a explicitly amends the "env.exit() placement" row, from "Requires `! Env` (parent)" to "Requires `! Env.Exit`, granted by `! Env`". It touches the letter of "Env sub-effect granularity". The impl ticket remaps `exit` in the hard-coded `env.*` table and tests that `! Env.Read` and `! Env.Write` alone still reject `env.exit`, and that `! Env.Exit` alone accepts it.

STABLE, ready to vote

**DevOps/Tooling:**

**Final Q2 position: Q2-a** ("never both" + amend §4.4.3 with `effect Exit { fn exit(code: Int) -> Never }`).

**To min: "Q2-c changes the least and is cheapest to change later"**

This is the strongest argument for Q2-c. It is half right. If Q2-a adds `Env.Exit` and a later panel finds it was a mistake, no one can remove it. But Q2-c does not change "the least". It only moves the change to where readers cannot see it:

- §4.3 (04_effects.md:179) says `! FS` and its child list "are identical to the compiler". Under Q2-c, `! Env.Read, Env.Write` is not identical to `! Env`. The Env exception stays in the row semantics; Q2-c hides it from the declaration syntax only. Every tool that expands or minimizes a row must carry the case: hover, the "narrow this row" lint, the "add missing effect" code action, and the E0539 discharge check. sys's concern (keep it only in the hard-coded `env.*` table) limits where the exception lives. It does not remove the exception from the tools that read rows.
- Q2-c still has one rule for user effects and a different rule for one built-in. The spec text must explain that difference, and `blink llms` must teach it. That is a cost every reader pays, every time. The cost of `Env.Exit` is one name that some code never uses.
- On reversibility: Q2-c is not free to relax later either. Once tools ship with a special case for parent-own ops, removing it is the same kind of break as removing a name. The difference is that users can see a name, but they cannot see a hidden special case.

**To web: "a third child adds a choice to every env-touching signature"**

It does not. aiml answered this: code that exits keeps writing `! Env`, as it does today. Read/Write code never meets `Exit`. The only new choice is for a function whose sole env use is `exit`. For that function, the least-authority row `! Env.Exit` is the point of hierarchical effects (§4.3: "the long form is what most functions should use"). Under Q2-c the "add missing effect" code action for `env.exit` must insert `! Env`, which also grants argv, every env var and set_var. A capability tool should not have to suggest the widest grant.

**What Q2-a costs, stated plainly**

It amends the letter of two 5-0 rows. "env.exit() placement" stops saying "requires `! Env` (parent)"; the rest of that row stands (under Env, on the `env` handle, interceptable, `-> Never`). "Env sub-effect granularity" gains a third child. DECISIONS.md records both as explicit amendments by this panel, citing plt's check that no Q3 rationale defends the "parent only" clause. No program that compiles today changes meaning. The impl ticket remaps `exit` in the hard-coded `env.*` table, with a test that `! Env.Read` and `! Env.Write` still reject `env.exit`.

STABLE, ready to vote

**AI/ML:**

**Final position: Q2-a** (never both + amend §4.4.3 with an `Env.Exit` child).

**To min's strongest argument (reversibility: `Env.Exit` can be added later, never removed):** This is true in general, but here the cost is not equal on the two sides. Q2-c is not free to keep. It locks in a permanent exception in the meaning of rows. §4.3 (04_effects.md:179) says `! Env` and its child list "are identical to the compiler". Under Q2-c, `! Env.Read, Env.Write` is not `! Env`. A model that reasons from §4.3, as the spec tells it to, gets every Env row involving exit wrong, and no note in §4.4.3 repairs a rule stated in §4.3. Q2-a has a low removal cost by comparison. Almost all exit-calling code is `main` or a CLI entry that already holds `! Env`, so `Env.Exit` would appear in few signatures. "Cannot remove" is an overstatement for a name that is almost never written.

**To web's "a third child adds a choice to every env-touching signature":** It does not. A function that reads or writes env still picks between Read and Write, exactly as today. Only a function that calls `exit` outside `main` meets `Env.Exit`, and it may still write `! Env`, so no existing spelling becomes wrong. The decision point is added only where the capability is actually used.

**To min's "needs no compiler change":** Both options touch the hard-coded `env.*` grant table. Q2-c must keep the "parent-only op" bit there, and sys's concern shows that bit must never leak into the general row checker. Q2-a removes the special case. The implementation cost is about the same, and Q2-a leaves less code that exists for one effect only.

**Net, from my seat:** Q2-a gives one rule ("ops on leaves; a parent is its children") stated once in §4.3 and obeyed by every block in the spec. That is the most learnable outcome from the spec alone. Q2-c gives one rule plus a counter-example that models will copy or reason from. I accept web's and plt's condition: DECISIONS.md records Q2-a as an explicit amendment of the "env.exit() placement" row and of the letter of "Env sub-effect granularity".

STABLE, ready to vote

**Minimalism:**

**Minimalism: Phase D, Q2 (z4xxkg)**

**Final position: Q2-a. I change my vote.**

**The strongest argument comes from devops, with sys and plt behind it.** §4.3 (sections/04_effects.md:179) says: "Declaring a parent is syntactic sugar for declaring all children. `! FS` and `! FS.Read, FS.Write, FS.Delete, FS.Watch` are identical to the compiler." I checked that text. §4.4.3 contradicts it today: `! Env.Read, Env.Write` is not `! Env`.

I argued that Q2-c "changes the least" and that the exception was "only in docs". That was wrong. The exception is in the core row algebra. Under Q2-c:
- every row check, subsumption test, E0539 discharge check and projection keeps one intensional node (sys, plt);
- every tool that expands or narrows a row needs a parent-own-ops case (devops);
- users still write `handler Env { ... fn exit }` mocks against that node, so it is not hidden from them (plt).

That is existing complexity: a second rule that lives beside "a parent is the sum of its children". My charter says to vote yes when a change replaces existing complexity. Q2-a deletes that second rule. It adds one name, `Env.Exit`, and no rule. One name is cheaper than a permanent exception in the semantics.

**My "nobody asked for `! Env.Exit`" point.** It still holds as a cost, but a small one. Nobody has to write `! Env.Exit`: code that exits can keep `! Env`, and every program that compiles today keeps its meaning (aiml). The new capability is a side effect of making the algebra uniform, not the goal.

**My "Q2-a cannot be undone" point.** This is true, but it applies to both options. Under Q2-c, the contradiction with §4.3 also stays until someone pays to remove it. Under Q2-a, nothing needs to be removed.

**Ratified rows.** plt checked decisions/env-effect-api.md Q3. None of the five rationales defends the "requires parent" clause; they all argue for "under Env, on the `env` handle, interceptable, `-> Never`", and Q2-a keeps all of that. I accept the amendment on that basis.

**Conditions (same as sys, plt, devops, web):**
- DECISIONS.md records this as an explicit amendment of the "env.exit() placement" row ("exit no longer needs the parent"), with the letter of "Env sub-effect granularity" also touched.
- The implementation ticket remaps `exit` to `Env.Exit` in the hard-coded `env.*` grant table.
- A test proves that `! Env.Read` and `! Env.Write` still reject `env.exit`, and that `! Env` still grants it.

STABLE, ready to vote.

##### Re-vote: Q2 (6-0 for Q2-a; web and min switched from Q2-c)

**Systems:**

1. **Vote** — Q2-a
2. **Reasoning** — Under Q2-a, each row normalizes to a set of leaves and a parent is the OR of its children's bits. Subsumption, the E0539 discharge check and projection coverage are then one bitset subset test with no exception, as §4.3 (04_effects.md:179) requires. Q2-c keeps `Env` as a node with its own bit, so `! Env.Read, Env.Write` does not equal `! Env`, and every row consumer carries that case for good. `Env.Exit` costs one leaf bit, one remap in the hard-coded `env.*` table and zero run-time cost. Every program that compiles today keeps its meaning.
3. **Concern** — The impl ticket can miss the remap of `exit` in the hard-coded `env.*` grant table. It needs tests that `! Env.Read` and `! Env.Write` reject `env.exit`, and that `! Env` and `! Env.Exit` accept it. DECISIONS.md must also record this as an explicit amendment of the "env.exit() placement" and "Env sub-effect granularity" rows.

**Web/Scripting:**

1. **Vote** — Q2-a (never both + amend Env with an `Exit` child).
2. **Reasoning** — A JS or Python dev learns one rule: "ops live on leaves; a parent is its children", which §4.3 (04_effects.md:179) already states. Under Q2-c they must also learn the footnote "except Env", and they still meet it when they write a `handler Env { ... fn exit }` mock. Nobody has to write `! Env.Exit`, because `! Env` keeps working for code that exits and every program that compiles today keeps its meaning. The "add missing effect" code action can then suggest `! Env.Exit` and not the widest grant. plt checked that no Q3 rationale in decisions/env-effect-api.md defends the "parent only" clause, so the amendment drops no debated point.
3. **Concern** — If DECISIONS.md, §4.4.3, `blink llms` and the `MockEnv` row (DECISIONS.md:330, `Handler[Env]` covers `exit`) do not all record the amendment of "env.exit() placement" and the third child in "Env sub-effect granularity", users will see docs that disagree. The impl ticket can also miss the `env.*` grant remap: it needs a test that `! Env.Read`/`! Env.Write` reject `env.exit` and that `! Env.Exit` alone accepts it.

**PLT:**

1. **Vote** — Q2-a ("never both" for every effect + amend Env with `effect Exit { fn exit(code: Int) -> Never }`).
2. **Reasoning** — §4.3 (04_effects.md:179) defines a parent by extension: `! FS` and its child list "are identical to the compiler". Under Q2-a every row normalizes to a set of leaves, so subsumption, projection coverage and the E0539 discharge check are plain set operations with no exception. Q2-c keeps an intensional node in the core row relation, where `! Env.Read, Env.Write` does not equal `! Env`. A table cannot hold that exception, because it concerns how rows relate, not which op a name grants. The amendment changes one clause ("requires `! Env` (parent)") that no rationale in decisions/env-effect-api.md Q3 defends, and every program that compiles today keeps its meaning.
3. **Concern** — The impl ticket can miss the remap of `exit` to `Env.Exit` in the hard-coded `env.*` grant table. DECISIONS.md must record the change as an explicit amendment of the "env.exit() placement" row (line 250) and of the letter of "Env sub-effect granularity" (line 251). Tests must prove that `! Env.Read` and `! Env.Write` alone reject `env.exit`, and that `! Env` and `! Env.Exit` alone accept it.

**DevOps/Tooling:**

1. **Vote** — Q2-a

2. **Reasoning** — §4.3 (04_effects.md:179) says `! FS` and its child list "are identical to the compiler". Under Q2-a this holds for every effect, so each row tool (hover, the "narrow this row" lint, the "add missing effect" code action, the E0539 discharge check) treats a row as a set of leaves, with no case for a parent that has its own ops. The code action for `env.exit` can insert `! Env.Exit` (least authority), not `! Env`, which also grants argv, every env var and `set_var`. `MixedEffectBody` stays one diagnostic with no exception, and the spec prints no block that users cannot write.

3. **Concern** — The amendment changes the letter of two 5-0 rows ("env.exit() placement", "Env sub-effect granularity"), so if DECISIONS.md, §4.4.3, `blink llms` and the hard-coded `env.*` grant table do not all change in the same commit, they will disagree. The impl ticket must test that `! Env.Read` and `! Env.Write` reject `env.exit`, and that `! Env` and `! Env.Exit` accept it.

**AI/ML:**

1. **Vote** — Q2-a (never both + amend Env with an `effect Exit { fn exit(code: Int) -> Never }` child).
2. **Reasoning** — A model learns from the spec alone, and §4.3 (04_effects.md:179) states the rule it will reason from: a parent and its child list "are identical to the compiler". Q2-a is the only option where every block in the spec obeys that rule, so one sentence teaches the whole row algebra and no code block shows a shape the model must never copy. Q2-c keeps a counter-example that a §4.4.3 note cannot repair, because the model reasons from §4.3. The added decision point lands only on code that calls `exit` outside a holder of `! Env`, and `! Env` stays a valid spelling there, so no existing pattern a model has learned becomes wrong.
3. **Concern** — `blink llms`, §4.4.3, the DECISIONS.md amendment of "env.exit() placement" and the `MockEnv` docs (its `Handler[Env]` still intercepts `exit`) must all change in the same commit, or models will learn the old "requires parent" text from one source and the new `Env.Exit` grant from another.

**Minimalism:**

1. **Vote** — Q2-a

2. **Reasoning** — §4.3 (sections/04_effects.md:179) says `! FS` and its child list "are identical to the compiler", and the built-in Env breaks that today, because `! Env.Read, Env.Write` does not grant `env.exit`. Q2-c keeps that break as a second rule in the row algebra (subsumption, the E0539 discharge check, projection, and every row tool), so it is not "the smallest change". It is lasting complexity. My seat backs a change that removes existing complexity. Q2-a removes the second rule and adds one leaf name and no new rule, and every program that compiles today keeps its meaning. The "requires `! Env` (parent)" clause in DECISIONS.md:250 has no rationale in decisions/env-effect-api.md Q3, so the amendment drops only a clause that the panel did not debate.

3. **Concern** — `Env.Exit` stays in the language for good. If the impl ticket misses the remap of `exit` in the hard-coded `env.*` grant table, or DECISIONS.md rows 250–251 do not record the explicit amendment, docs and compiler will disagree. A test must prove that `! Env.Read` and `! Env.Write` reject `env.exit`, and that `! Env` and `! Env.Exit` accept it.

### AI-First Review

| Criterion | Result |
|---|---|
| Learnability | Pass — one rule ("ops live on nodes with no sub-effects"), stated in prose and grammar, with no built-in exception |
| Consistency | Pass — built-in and user effects share one shape; `Rand` is already a leaf with ops |
| Generability | Pass — the flat form is what three spec authors and the panel's reading of the training data reach for first |
| Debuggability | Pass — `MixedEffectBody`, `EffectNestingTooDeep` and `DuplicateEffectOp` are named, and E0538 lists a leaf's ops |
| Token Efficiency | Pass — `! Store` and `effect Store { fn get(...) }` drop a child name that means nothing |

### Final Spec

```blink
effect Store {
    fn get(key: Str) -> Int
    fn put(key: Str, value: Int)
}

effect Env {
    effect Read { ... }
    effect Write { ... }
    effect Exit {
        fn exit(code: Int) -> Never
    }
}

fn load() -> Int ! Store {
    store.get("count")
}
```

```
effect_decl  ::= "pub"? "effect" IDENT effect_body?
effect_body  ::= "{" ( op_sig* | child_effect* ) "}"
child_effect ::= "effect" IDENT ( "{" op_sig* "}" )?
op_sig       ::= "fn" IDENT "(" params? ")" ( "->" type )?
```

- A leaf effect declares its operations in its own body (Q1).
- Every body holds operations or sub-effects, never both; `MixedEffectBody` (E0541). Its fix moves the operations into a new sub-effect with a placeholder name and never suggests the parent-level shape (Q2, Q4).
- §4.4.3 `Env` gains a child `Exit`. `! Env` and `! Env.Exit` grant `env.exit`; `! Env.Read` and `! Env.Write` do not. Every program that compiles today keeps its meaning. This amends the *env.exit() placement* and *Env sub-effect granularity* rows: no rationale in [env-effect-api.md](env-effect-api.md) Q3 defends the "parent only" clause, and `Exit` neither splits `Read` nor flattens the tree (Q2).
- v1 trees have two levels; a grandchild is `EffectNestingTooDeep` (E0542). The ops rule does not depend on depth, and the compiler collects ops with one recursive walk (Q3).
- Operation names are unique across one top-level tree; a duplicate is `DuplicateEffectOp` (E0543) and names both declarations (Q5).
- `effect X {}` is `effect X`; `blink fmt` rewrites it. When the braces hold a comment, `blink fmt` keeps the braces and the comment; the panel asked only that fmt never drop a comment, and the moderator chose this way to meet it (Q6).
- The grammar sits in §4.12, beside the rules it encodes. The ballot said "§2"; §2 has no declaration grammar, and this repo places productions with their topic (Q7).
- `! Store.get` is E0538; a note lists the leaf's operations and the help names `! Store`. Only the error is normative (Q8).
- Splitting a leaf into sub-effects keeps rows, handlers and calls valid (Q9).

The moderator chose the names `EffectNestingTooDeep` and `DuplicateEffectOp` and the codes E0541–E0543; the panel voted for named diagnostics but did not name these two. E0540 stays free for `UnhandledEffectInTest` ([Unhandled Effect Operation](unhandled-effect-operation.md)).
