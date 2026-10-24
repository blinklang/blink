[< All Decisions](../DECISIONS.md)

# Nested Field Path Through a `Ptr` to an ffi Struct — Design Rationale

§9.1.3 gave field access on `Ptr[@ffi.struct T]` as `p.f.read()` and `p.f.write(v)`, one step deep. It said nothing
about a field inside an embedded `@ffi.struct` field. This program failed in the compiler:

```blink
@ffi.struct type Inner { b: Int, c: Int }
@ffi.struct type Outer { a: Inner, n: Int }

with ffi.scope() as s {
    let p: Ptr[Outer] = s.alloc()
    p.a.b.write(5)
    io.println("{p.a.b.read()}")
}
```

The compiler said `error[UnresolvedMethod]: unresolved method .write on type Int`. `p.a.b = 5` was
`error[NotAPlace]` (E0611), and its help and machine fix named `p.a.b.write(5)`, a form that did not compile. The
question was whether `p.a.b.read()` and `p.a.b.write(v)` are legal, and what the E0611 help names for a nested path.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | The fix for `h.q.b = v` (the path crosses a `Ptr` field) | A: machine fix `h.q.read().b.write(v)` | 5-1 (Minimalism dissent: B) |
| Q2 | The §9.1.3 text | A: replace the "desugars to a typed pointer-to-field" sentence with the rule (root, embedded step, use only `read()`/`write(v)`) | 4-2 (Systems, Minimalism dissent: B) |
| Q3 | The term in prose | A: "field address" in §9.1.3 prose; no surface name, not a value | 5-1 (Minimalism dissent: B) |
| Q4 | §9.1.1 scope tags | A: "at any embedded depth" at all three sites | 5-1 (Minimalism dissent: B) |
| Q5 | A field named `read` or `write` | A: one line in §9.1.3, no example block | 6-0 |

The first Phase C ballot gave Q1 4-2, Q2 4-2, Q3 5-1, Q4 4-2 and Q5 3-3. Phase D settled Q1, Q4 and Q5. See Phase D.

Points all six seats stated by the end of Phase B, not balloted:

- `p.a.b.read()` and `p.a.b.write(v)` are legal at any embedded depth, at the sum of the C offsets. `p.a.read()` and
  `p.a.write(Inner { .. })` stay legal.
- The path stops at a `Ptr` field reached through it: `h.q.read().b.write(v)`.
- A `Ptr` value at the root of a path is not such a step: `s.p.f.write(v)` stays legal and stays the E0611 fix for
  `s.p.f = v`. §2.22 shows one example of each case side by side.
- A path outside `read()`/`write()` is rejected at every depth, with one named diagnostic and not an ICE: bare `p.a`,
  bare `p.a.b`, and `h.q.b.write(v)`. The `h.q.b` form gets help to load the pointer first, naming `h.q.read().b`.
  The spec does not name the code number. The code table does.
- E0611: `p.a.b = v` gets the machine fix `p.a.b.write(v)`. `op=` gets help only: `p.a.b.write(p.a.b.read() op rhs)`.
  The §2.22 text becomes "`write` on the same path" plus one nested example.
- A field named `read` or `write`: the call parentheses decide. No new rule.

### Compiler behavior before the decision

The moderator ran probes with the gen1 compiler and gave the results to the panel:

- `p.a.b.write(5)` and `p.a.b.read()`: `error[UnresolvedMethod]` on type Int.
- `p.n.write(3)`, `p.a.read().b` and `p.a.write(Inner { b: 7, c: 8 })`: run.
- bare `p.a`: internal compiler error `FieldOwnerWithoutDecl`; `check` accepts it.
- `p.a.b = 5`: E0611 with a help and machine fix `p.a.b.write(5)` that does not compile.
- `h.q.write(i)` and `h.q.read().b.write(9)` (`h: Ptr[Holder]`, `q: Ptr[Inner]`): run.
- `h.q.b.write(9)`: internal compiler error `FieldOwnerWithoutDecl`.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in
independent-proposal, debate, vote rounds. Phase A is excerpted from each panelist's own text. Phases B, C and D
are quoted from each panelist's file, without its heading line.

#### Phase A — Independent proposals

All six seats proposed that the path walks through embedded `@ffi.struct` fields and stops at a `Ptr` field.

- **Systems** (`A/sys.md`):

> A field path `p.f1.f2...fn` on `p: Ptr[T]` is legal when `T` is `@ffi.struct` and each of `f1..f(n-1)` is an embedded `@ffi.struct` field (not a `Ptr`). The path is one field address. `.read()` loads the last field at its C offset. `.write(v)` stores it. The offset is the sum of the field offsets along the path. The compiler knows it at compile time.
>
> [...]
>
> My rule does not cover `h.q.b` where `h: Ptr[Holder]` and `q` is a `Ptr[Inner]` field. That path needs two memory accesses: load `q`, then address `b` in the pointee. A path that hides a load hides a cost and a possible fault. The user must write the load: `h.q.read().b.write(9)`.
>
> [...]
>
> Section 9.1.1 scope tags: "a field reached through `p.field`" becomes "a field reached through `p.field`, at any embedded depth".

- **Web/Scripting** (`A/web.md`):

> A JS/Python/Kotlin developer reads `p.a.b` as "field b of field a of p". `p.a.b = 5` already gets E0611 whose help names `p.a.b.write(5)`. If that form does not compile, the compiler gives advice that fails. The user then guesses, and each guess is a Stack Overflow question. The simple rule: the dotted path is the same path in the read, the write and the help.
>
> [...]
>
> This is the trap case: `o.b = 5` compiles and silently changes nothing in C memory. A Python dev hits this at once.
>
> [...]
>
> Path through a `Ptr` field (the `h.q.b` row): the rule stops there. A step through a `Ptr` field is a load of a pointer, not an offset add. [...] The fix for `h.q.b = 9` is help only, naming `h.q.read().b.write(9)`.

- **PLT** (`A/plt.md`):

> Let `FA[F]` be the compiler-internal type of a field address. It has no surface name, cannot be bound, and is not a value (the "no first-class pointer-to-field" decision stands).
>
> - (P-root) `p : Ptr[S]`, `S` an `@ffi.struct`, `S` has field `f : F`. Then `p.f : FA[F]`.
> - (P-step) `e : FA[S]`, `S` an `@ffi.struct`, `S` has field `g : G`. Then `e.g : FA[G]`. The offset is the sum of the offsets along the path, computed at compile time.
> - (P-use) `e : FA[F]` supports exactly `.read() : F` and `.write(v : F)`. Any other use of an `FA` is rejected.
>
> [...]
>
> A `Ptr` held in a value root is a different case: `s.p.f.write(v)` with `s: S` (a value) and `s.p : Ptr[T]` is `P-root` on the value `s.p`. It stays legal, as §2.22 already says.

- **DevOps** (`A/devops.md`):

> `p.a.b = 5`: E0611 help and machine fix stay `p.a.b.write(5)`. Once the rule above holds, the help names a form that compiles. This is the cheapest outcome: no change to the E0611 text, only the typechecker.
>
> [...]
>
> `h.q.b = 9` and `h.q.b.write(9)`: new error on the path-through-`Ptr`-field step. Message: "`.b` reads through the pointer in `q`. Load it first." Help: `h.q.read().b.write(9)`.
>
> [...]
>
> Name clash: if `Inner` has a field named `read` or `write`, `p.a.read()` is the call and `p.a.read.read()` reads the field. The call parentheses decide; no new rule.

- **AI/ML** (`A/aiml.md`):

> Depth does not matter. The same "path, then `read`/`write`" form holds at every depth, so a model learns one rule, not one rule per depth.
>
> [...]
>
> The `.read()` marks the pointer load, which is a real memory access. The user can see each load, and the spec already makes `h.q.read()` legal and working.

- **Minimalism** (`A/min.md`):

> `p.a.b.read()` and `p.a.b.write(v)` are legal. This adds no feature. The spec already says "a typed pointer-to-field that supports `.read()` / `.write(v)`" and §2.22 already says the E0611 fix calls `write` "on the same path". The gap is one missing sentence, and the compiler is behind it.
>
> [...]
>
> The workaround `p.a.write(Inner { b: 5, c: p.a.read().c })` is wrong to recommend: it must name every sibling field, and it breaks when someone adds a field.

#### Phase B — Debate highlights

One round (B1). The moderator sent a digest of the variations (V1 to V5) and each seat replied. Position shifts and
corrections:

- **Minimalism** moved on V1 (machine fix or help only for `h.q.b = v`):

> I change my position. Help only, no machine fix, as web says. The machine fix for `p.a.b = v` stays: the path does not change. For `h.q.b = v` the fix changes the path (it inserts `.read()`), and that is a second kind of fix. One kind of machine fix is the smaller surface.

- **Web** moved on V2 (a named code):

> I change my position. In Phase A I said the panel did not need a code. After reading devops, sys, plt and aiml, four seats want a named error instead of an ICE. A user who sees an ICE files a bug and loses trust in the language.

- **DevOps** withdrew its §2.22 sentence for a `Ptr` field in the middle of a path (V3):

> I change my Phase A position. My sentence for §2.22 case 1 [...] is wrong for this shape. `s.p` is a `Ptr` value, so the path starts there and the fix stays `s.p.f.write(v)`, as sys and plt say. Only a `Ptr` field reached through a field address (`h.q.b`, root `h: Ptr[Holder]`) needs `read()`.

- **Systems** stated the rule that separates the two cases:

> The rule: `read()` goes after a `Ptr` *field projection* (`h.q`), never after a `Ptr` *value* (`s.p`). The spec sentence should say this once, because the two cases look alike.

- **Minimalism** withdrew its "after the root" wording:

> My Phase A edit said "when the path has no `Ptr` field after the root". That reads wrongly for `s.p.f` with `s: S` a value, because `s.p` is a `Ptr` value and the path starts at it.

- **PLT** on V2:

> One code for "field address used outside `read()`/`write()`", and it covers bare `p.a`, bare `p.a.b` and `h.q.b` (devops). `h.q.b` is the same fault: `h.q` is a field address, and `.b` is neither `read` nor `write`. By P-use that is the whole rule, so no second code is needed.

- **Systems** and **Minimalism** kept the existing "desugars" sentence in §9.1.3 and added one sentence (V4); web, plt, devops and aiml replaced it. Web and aiml dropped the `FA[F]` notation from the spec text; Minimalism opposed the term itself:

> I oppose the new internal term `FA[F]` in the spec text. The spec says "there is no first-class pointer-to-field value"; a named internal notion adds vocabulary for no user gain. (Minimalism)

- On V5 (a field named `read` or `write`) web and aiml wanted spec text; Minimalism wanted a test only:

> I want one example in the spec with `p.a.read.read()` because the case looks odd, and an AI or a new user will ask. (Web)
>
> The `read`/`write` field-name case: the call parentheses decide; no new rule, no spec text. Add one test, not a sentence. (Minimalism)

All six replied "STATUS: stable, ready to vote".

#### Phase C — Final vote

Each seat read the Phase A and Phase B files before it voted. The moderator listed the agreed points (above) and
five questions. The text below is each seat's own text.

- **Q1: The fix for `h.q.b = v` (the path crosses a `Ptr` field).** A: machine fix `h.q.read().b.write(v)`. B: help only, naming `h.q.read().b.write(v)`. (4-2: A for Systems, PLT, DevOps, AI/ML; B for Web, Minimalism)
  - **Systems:** A — The rewrite `h.q.read().b.write(v)` has one reading and compiles to the same two accesses the C code `h->q->b = v` makes: one load of `q`, one store of `b`. The added `.read()` shows the load in the diff, which is the cost visibility systems code needs. Same order of `place = rhs`, so no new evaluation-order risk. The `op=` form stays help only because the path repeats.
    - Concern: A machine fix that inserts a load changes the kind of fix (path edit, not call wrap), and a user who applies it without reading may not notice a new pointer load on a hot path.
  - **Web/Scripting:** B — The machine fix for `p.a.b = v` keeps the path and adds `.write(v)`. The fix for `h.q.b = v` changes the path: it inserts a `.read()`, which is a pointer load the user did not write. A user who clicks a quick-fix should get the same code with one call added, not a new memory access. Help text that names `h.q.read().b.write(v)` and says why costs the user one edit and teaches the rule.
    - Concern: If A wins, a quick-fix will insert a hidden pointer load in a diff the user skims, and the "every load is visible" rule will rest on the user reading the diff.
  - **PLT:** A — `h.q.read().b.write(v)` is the unique well-typed rewrite of `h.q.b = v`. It keeps the `place = rhs` evaluation order and the same effect order (load `q`, then store `b`). The added `.read()` is a load that the original path could not have, but the rewrite does not change the meaning of any program that compiled, since `h.q.b = v` never compiled. A certain, checkable rewrite should be a machine fix, with the diff visible to the user.
    - Concern: A second kind of machine fix (one that changes the path, not only the method) widens the fix surface, and a later change to `Ptr` loads could make the rewrite stale.
  - **DevOps:** A — `h.q.read().b.write(v)` is the only correct rewrite. It compiles, it keeps the `place = rhs` order, and the diff shows the added load. A certain, checkable rewrite should be a machine fix, so `blink fix` and the LSP quick-fix apply it with no user choice. Help-only forces the user to retype a form the tool already knows. The help text still says why the load is needed.
    - Concern: If the machine fix for the `h.q.b` form ships without a golden test, it can drift into naming a form that does not compile, which is the bug that opened this ticket.
  - **AI/ML:** A — The rewrite `h.q.read().b.write(v)` has one correct form, so a tool can apply it with no user choice. A machine fix gives a model a clean before/after pair to learn from; help only makes it guess and gives it no pair. The added load is visible in the diff, and the order of `place = rhs` stays.
    - Concern: If B wins, there are two kinds of E0611 help (fix and help only) for near-identical shapes, and a model will not know which shapes have a machine fix.
  - **Minimalism:** B — The machine fix for `p.a.b = v` keeps the path and only adds `.write(v)`. The fix for `h.q.b = v` changes the path (it inserts `.read()`), so it is a second kind of fix, with its own tests and its own fix site in `blink fix` and the LSP. One kind of machine fix is the smaller surface. The help still names `h.q.read().b.write(v)`, so the user loses one keystroke, not information.
    - Concern: If A wins, every later path-shape rule (a new embedded form, a new pointer step) will ask for its own rewriting fix, and the fix table will grow with no limit.

- **Q2: The §9.1.3 text.** A: replace the "desugars to a typed pointer-to-field" sentence with the rule (root, embedded step, use only `read()`/`write(v)`). B: keep the existing sentence and add one sentence after the Rule line. (4-2: A for Web, PLT, DevOps, AI/ML; B for Systems, Minimalism)
  - **Systems:** B — The existing "desugars to a typed pointer-to-field" sentence is already true at every depth: a nested path is one pointer-to-field at the summed offset. One sentence after the Rule line adds the walk and the stop at a `Ptr` field with the least churn, and it keeps the cost model (one address, one access) stated where it already sits.
    - Concern: If the old sentence stays beside the new one, the paragraph may read as two rules ("one step" then "any depth"), and the wording must make the second extend the first.
  - **Web/Scripting:** A — The old "desugars to a typed pointer-to-field" sentence describes one step only, and a reader who sees it next to `p.a.b` will ask what it means at depth 2. One replaced sentence that gives root, embedded step and use is shorter to learn than the old sentence plus a patch after the Rule line. A JS or Python dev reads it once and knows that a path of by-value struct fields takes only `read()` and `write(v)`.
    - Concern: If B wins, §9.1.3 keeps a "desugars" sentence that is wrong for depth 2 or more, and the added sentence has to contradict it.
  - **PLT:** A — The current "desugars to a typed pointer-to-field" sentence has no rule for a further step, which is the gap in the ticket. A typing rule needs three clauses: root, embedded step, use. Keeping the old sentence and adding one after the Rule line leaves two statements of one rule that can drift apart.
    - Concern: Replacing the sentence moves the existing wording that other sections cite, so §9.1.1 and §2.22 cross-references need a check.
  - **DevOps:** A — The rule must say how a step extends a path and that only `read()`/`write(v)` use it. The old "desugars to a typed pointer-to-field" sentence has no step rule, so a diagnostic and an LSP hover have no spec sentence to cite for a nested path. One replaced sentence is also less text than two sentences that overlap.
    - Concern: If the replacement sentence is loose, the compiler and the spec can disagree on bare-path rejection, and the user gets an error the spec does not explain.
  - **AI/ML:** A — Replace the "desugars to a typed pointer-to-field" sentence with the rule: root, embedded step, use only `read()`/`write(v)`. That sentence says nothing about the nested step, so a model reading the spec alone has to infer it. One rule stated in one place is cheaper to learn than an old sentence plus a patch sentence that must agree with it.
    - Concern: If B wins, the old sentence still implies a one-step shape, and a model may read the added sentence as an exception and not as the rule.
  - **Minimalism:** B — Keep the existing "desugars to a typed pointer-to-field" sentence and add one sentence after the Rule line. The addition states the new rule (embedded steps, `read()`/`write(v)` only) and leaves the decided text alone. A replacement edits text that the `ffi-struct-construction` panel already settled, for no user gain.
    - Concern: If A wins, the replaced sentence may lose a property of the old wording that no seat noticed, and the rule then lives in two places that can drift.

- **Q3: The term "field address" in spec prose** (no surface name, not a value; the `FA[F]` notation and the P-root/P-step/P-use names stay out of the spec text). A: use "field address" in §9.1.3 prose. B: no new term; keep "typed pointer-to-field". (5-1: B for Minimalism)
  - **Systems:** A — The thing exists in codegen: a compile-time offset sum with no runtime value. A short name for it lets the spec state "one access, no copy" in one phrase. It has no surface name and is not a value, so it adds no syntax and no runtime part.
    - Concern: A prose term can drift into a user-visible type name (hover text, error messages), and then users will try to bind it.
  - **Web/Scripting:** A — The spec needs a short noun for "what a path of by-value fields is", or each sentence repeats "typed pointer-to-field" and the reader asks if it is a value. The term has no surface name and the spec already says there is no first-class pointer-to-field value, so it adds one word and no syntax. The `FA[F]` notation and the P-rule names stay out of the spec.
    - Concern: If B wins, the spec keeps "typed pointer-to-field", and users will read it as a value type that they can bind.
  - **PLT:** A — "Field address" names the notion the use clause needs ("supports `.read()` and `.write(v)` and nothing else"). It has no surface name, cannot be bound and is not a value, so it adds no user-facing form. Without a term, the sentence must repeat "typed pointer-to-field" in every clause, and that phrase suggests a value.
    - Concern: A reader may take "field address" as a first-class value and ask for `let a = &p.f`, which the earlier panel rejected.
  - **DevOps:** A — Diagnostics, LSP hover (`field address Int (offset 8)`) and the error help need one stable noun. If the spec has no term, each tool picks its own wording and they drift apart. A term with no surface name and no value form adds no syntax. The `FA[F]` notation and P-rule names stay out of the spec, as all seats agree.
    - Concern: A reader may take "field address" for a first-class value; the spec must keep the line "there is no first-class pointer-to-field value" next to it.
  - **AI/ML:** A — One short name for the concept costs few tokens and lets the rule sentence, the diagnostic and the help all use the same word. It has no surface spelling and is not a value, so a user writes nothing new. I still keep `FA[F]` and P-root/P-step/P-use out of the spec.
    - Concern: If B wins, the spec has no short noun for what `p.a.b` is, and the diagnostic text must repeat a longer phrase or use a word the spec never defines.
  - **Minimalism:** B — The spec says there is no first-class pointer-to-field value. A new term, even with no surface name, adds vocabulary that a reader must learn and that no user ever writes. "Typed pointer-to-field" already exists in the text and covers the nested case. The P-root/P-step/P-use names stay in the decision file.
    - Concern: If A wins, "field address" reads as a type name, and users and models will ask how to declare or bind one.

- **Q4: §9.1.1 scope tags: "a field reached through `p.field`".** A: add "at any embedded depth". B: no change. (4-2: A for Systems, Web, DevOps, AI/ML; B for PLT, Minimalism)
  - **Systems:** A — The tag rule is a safety rule for FFI memory; a reader should not infer from "one step" wording that depth changes the tag. Four words close the gap at no cost. The effect is the same as plt's "no change" reading, stated once.
    - Concern: If the phrase is added here and not at the other "through `p.field`" sites, the spec implies that those sites differ.
  - **Web/Scripting:** A — The phrase costs three words and removes the question "does the tag rule stop at one step?" for a reader who has just seen `p.a.b`. Users and AI readers do not read a decision file, so the reading "no change" must be in the spec text, not in plt's head. The phrase is harmless if redundant.
    - Concern: If B wins, a reader of §9.1.1 alone can think the tag rule covers one step and nothing deeper.
  - **PLT:** B — The scope-tag text says a field reached through `p.field` has the tag of `p`. A nested path is a `p.field` path by P-step, so the rule holds at every depth with no change. Adding "at any embedded depth" there suggests that the rule needed an extension, and that invites the opposite reading in places where the text lacks it.
    - Concern: A reader who sees only §9.1.1 may think nested paths are out of scope for the tag rule, so the impl ticket needs one E0601 test at depth 2.
  - **DevOps:** A — Plt is right that the tag rule holds at every depth with no change. One explicit phrase states it, so no reader must infer it, and the E0601 help can quote it. This meets my Phase B condition: the phrase says "at any embedded depth", and the decision file records plt's no-change reading.
    - Concern: The phrase is redundant, and a later edit to the tag rule may update one place and miss the other.
  - **AI/ML:** A — "At any embedded depth" is three words, and it removes a guess: a model cannot know from the one-step wording that the tag rule holds at depth 2. The rule is the same either way (devops: only if the no-change reading is also stated), and the added phrase states it.
    - Concern: If A wins, the phrase may suggest that depth changes the tag rule, unless the text says the tag is the same at every depth.
  - **Minimalism:** B — The scope-tag rule says "a field reached through `p.field`". plt shows it holds at every depth with no change, and the new §9.1.3 sentence already says a nested path is a field path. A second statement of the same fact is a second place to keep correct.
    - Concern: If A wins, the extra words are harmless, but a reader may infer that other places in §9.1.1 that lack the phrase do not hold at depth.

- **Q5: The `read`/`write` field-name case.** A: one example or note in §9.1.3. B: a test only, no spec text. (3-3: A for Web, PLT, AI/ML; B for Systems, DevOps, Minimalism)
  - **Systems:** B — The call parentheses already decide; this is not a rule. A test pins the behaviour in the compiler at no cost to the spec size. A field named `read` is rare in C structs we bind.
    - Concern: With no spec text, a second implementation of the compiler or an LLM that reads only the spec may guess wrong on `p.a.read.read()`.
  - **Web/Scripting:** A — `p.a.read.read()` looks odd, and a new user or an AI will ask which `read` is the call. One example in §9.1.3 answers that before the question reaches a forum. The rule is already settled (parentheses decide), so the cost is one line.
    - Concern: If B wins, the rule lives only in a test, and the first user with a field named `read` has to find it by trial.
  - **PLT:** A — `p.a.read` as a field and `p.a.read()` as the method share a prefix, so the typing rule needs one sentence that says the call parentheses decide. A spec that leaves this to a test leaves the grammar of the path ambiguous on paper. One example is cheap and settles it for the implementer and for the reader.
    - Concern: A spec example for a rare name clash adds weight to §9.1.3 and may suggest the case is common.
  - **DevOps:** B — This is a parsing and tooling note: the call parentheses decide, with no new rule. A golden test and an LSP completion test pin the behavior. A spec example for a rare name clash adds text that every reader must carry.
    - Concern: A model or new user who names a field `read` has no spec text to check, and learns the rule only from a test or an error.
  - **AI/ML:** A — A field named `read` is odd enough that a model will guess, and a wrong guess gives silent wrong code. One example line, `p.a.read.read()`, prevents it at a cost of one line. A test checks the compiler but a model learning from the spec never sees the test.
    - Concern: If B wins, a model that meets a field named `read` or `write` has no spec text to learn from and must guess between the call and the field.
  - **Minimalism:** B — The call parentheses decide, and that is how the language already treats a field and a method of the same name. No new rule exists, so no spec text is needed. One test fixes the behavior, and the test is the spec for tools.
    - Concern: If A wins, the spec gains an odd example that suggests this case needs special care, and it invites the same note for every other name clash.

#### Phase D — Round 2

Q3 was not reopened (5-1, Minimalism dissent). Q1, Q2, Q4 and Q5 were split 4-2, 4-2, 4-2 and 3-3. The moderator
sent the Phase C votes and asked each seat to answer the strongest argument against its own vote.

**D1: focused debate** (own text, in full)

- **Systems:**

> **Q1. Keep A.** Strongest argument against: web, a quick-fix inserts a pointer load in a diff the user skims. The answer is cost, not meaning. The user cannot get this form wrong by skimming: the original `h.q.b = v` never compiled, and the fix adds exactly one `.read()` that the user must accept in a diff. The same load is in the C they replace (`h->q->b = v`). Without the fix, the user types the same text by hand, with no check. min's point (a second fix kind) is real but small: one fix site that inserts a fixed token. I accept that `op=` stays help only, since it repeats the path.
>
> **Q2. Keep B.** Strongest argument against: web and plt, the old sentence stays and a new one sits beside it, so two statements can drift. I check the old sentence: it says `p.field` desugars to a typed pointer-to-field. That is true at depth 1 and does not claim "only one step". It is incomplete, not wrong. One added sentence that starts "The path may go on through embedded `@ffi.struct` fields" extends it and cannot contradict it. Replacement touches text that other sections cite. I hold B, and I accept A's wording if the drafter keeps the cited phrases.
>
> **Q4. Keep A.** Strongest argument against: plt and min, a nested path is a `p.field` path, so the phrase implies an extension that is not needed. I agree the rule holds with no change. But web is right that users and models read the spec, not the decision file. Four words state the reading once, in the place that governs E0601 for FFI memory. I think the risk of a wrong inference is larger than the risk of redundancy. This is a weak hold.
>
> **Q5. I change to A.** My Phase C concern was the strongest argument: a spec-only reader (a model, a second compiler) may guess wrong on `p.a.read.read()`. aiml's point removes my reason for B. One short example costs little. It is rare for C structs, but the cost of a wrong guess is a silent read of the wrong thing. I keep the test as well.

- **Web/Scripting:**

> **Q1. Change: B to A.** The strongest argument against me is plt's: `h.q.b = v` never compiled, so the rewrite changes no working program, and the user sees the diff. I said the load is hidden. It is not: the `.read()` shows in the diff, and the E0611 message can say why it was added. aiml adds a second point that I weigh more: with B there are two kinds of E0611 help for near-identical shapes, and a JS or Python dev will ask why one gets a quick-fix and the other does not. A quick-fix that works is the "just works" case. `op=` stays help only, because the path repeats and a side effect can double. I vote A.
>
> **Q2. No change: A.** The strongest argument against me is sys's: the "desugars to a typed pointer-to-field" sentence is true at every depth, and a replacement edits settled text. It is true, but it says nothing about the step, so a reader cannot tell if `p.a.b` is a field address or an `Int` copy (the ticket's bug). plt's drift point also holds: two statements of one rule will part. Other sections cite the rule, not the sentence, so the move costs little. I keep A.
>
> **Q4. No change: A.** The strongest argument against me is plt's and min's: by P-step a nested path is a `p.field` path, so the rule already holds, and adding words suggests it needed an extension. I accept that the rule holds. My point is that a reader of §9.1.1 alone does not know this. Sys's concern is real too: if I add the phrase here and not at the other "through `p.field`" sites, they look different. I keep A on condition that the edit covers every such site in one pass. If that condition fails, B is better than a partial A.
>
> **Q5. No change: A.** The strongest argument against me is min's: the language already treats a field and a method of the same name this way, so there is no new rule and no text is needed. For a human reader that may hold. An AI or a second implementation that reads only the spec has no such prior for `@ffi.struct` field addresses, where `p.a.read` is a path step and `p.a.read()` is a call. One line costs less than one wrong guess. I keep A.

- **PLT:**

> **Q1 (A, machine fix).** Strongest argument against: the fix inserts a pointer load the user did not write, and it adds a second kind of fix (min, web). Answer: the original `h.q.b = v` has no meaning, so the rewrite changes no program that compiled. The load is not hidden: the user sees `.read()` in the diff, and the help text says why. The fix site is the same one that emits `p.a.b.write(v)`. It differs only in where it inserts `.read()`. The cost is one extra golden test. A rewrite that is certain and checkable should be a fix. I do not change my vote.
>
> **Q2 (A, replace the sentence).** Strongest argument against: the existing "desugars to a typed pointer-to-field" sentence is true at every depth, and a replacement edits settled text (sys, min). Answer: I accept that the sentence is not false. It is incomplete. It gives the root rule (P-root) and says nothing on the step (P-step) or the use limit (P-use), and the ticket exists because of that gap. A kept sentence plus an added sentence states one rule twice, and the two can drift. The replacement keeps the settled content (typed offset, `read`/`write`, no first-class value). Only the wording changes. I do not change my vote. If A loses, the added sentence must repeat none of the old one.
>
> **Q4 (B, no change).** Strongest argument against: users and models read the spec, not a decision file, so the "no change" reading must be on the page (web). Answer: this is a fair point, but the fix is one sentence in §9.1.3, which §9.1.1 names as the place that extends the table. Under Q2 A, §9.1.3 already says "at any depth". A phrase in the scope-tag row then says the same fact a second time, and it implies the other "through `p.field`" sites (the cell definition, rule 1) need it too. I do not change my vote. I would accept A only if the same phrase goes into all three sites.
>
> **Q5 (A, one example).** Strongest argument against: a test shows the compiler behaviour, the case is rare, and the call parentheses already decide (sys, devops, min). Answer: a second compiler and a model that reads only the spec have no test to read. The cost is one line in a paragraph the vote rewrites anyway. The case looks like a conflict between a field and a method, so the spec should settle it on paper. I do not change my vote.
>
> No vote changes.

- **DevOps:**

> **Q1 (keep A).** Strongest argument against: web's "a quick-fix inserts a hidden pointer load in a diff the user skims", and min's "a second kind of fix with its own fix site". The load is not hidden. The user typed a path that crosses a `Ptr` field, so the load is already in the program's meaning, and the fix shows it as `.read()` in the diff. The path rewrite is a local text insert at one known node, with one golden test. It is not a new family of fixes. The reverse cost is real: help only for one shape and a fix for a near-identical shape gives two kinds of E0611 output, which aiml names. The LSP quick-fix is marked as a fix the user previews before apply. No change.
>
> **Q2 (keep A).** Strongest argument against: sys's "the existing sentence is already true at every depth", and min's "do not edit settled text". The sentence is true, but it states no step rule. A diagnostic, a hover and an LSP completion for `p.a.` have no sentence to cite for how a path grows or why `h.q.b` stops. Keeping it and adding a second sentence leaves two statements of one rule (plt). The edit is small and the other sections cite the term, not the sentence. No change.
>
> **Q4 (keep A).** Strongest argument against: plt and min: a nested path is a `p.field` path by the step rule, so the phrase suggests the rule needed an extension. I accept that the phrase is redundant. It costs six words, and it lets the E0601 help and an AI reader see depth is covered without deriving it. Sys's concern is valid: if the phrase goes in, the other "through `p.field`" sites must use the same wording, or the spec implies they differ. I ask the impl to sweep those sites. No change.
>
> **Q5 (change to A).** Strongest argument against my vote: aiml and plt. A model that learns from the spec never sees the test, and a second compiler implementation has no text to check for `p.a.read.read()`. My Phase C reasoning said a spec example adds text every reader must carry. One line in §9.1.3 is small, and the golden test and LSP test still stay as the tooling pin. I change my vote to A: one example or note, keeping the text to one line.

- **AI/ML:**

> **Q1 (machine fix).** Strongest argument against: min says it is a second kind of fix with its own fix site, and web says it adds a pointer load the user did not write. Answer: the fix site is the same one. E0611 already rewrites a path to `write` on that path, and this case only adds `.read()` after a `Ptr` field. The load is visible in the diff, and `h.q.b = v` never compiled, so no working program changes. Web's skimming risk applies to every quick-fix. A model learns a fix it can see as a before/after pair; help-only text is not a pair. I keep A.
>
> **Q2 (replace the sentence).** Strongest argument against: sys says the "desugars to a typed pointer-to-field" sentence is already true at every depth, and a replacement edits settled text. Answer: the sentence says "`p.field`", which a reader takes as one step, and it states no step rule. A model that reads only the spec must infer depth 2 from it. Adding a sentence leaves two statements of one rule, which plt notes can drift apart. Replacing the sentence keeps the settled meaning. I keep A.
>
> **Q4 (scope tags, "at any embedded depth").** Strongest argument against: plt and min say the rule already holds at every depth, so the phrase suggests an extension and makes a second place to keep correct. Sys adds that other "through `p.field`" sites would then look different. These points are real, and the gain for a model is small: it already reads the tag as a property of the cell, and the nested path is a `p.field` path. I do not move yet, but I accept B if the panel wants one fewer edit site. I keep A, weakly.
>
> **Q5 (field-name example).** Strongest argument against: min and devops say no new rule exists, and a spec example for a rare clash is text every reader carries. Answer: one line costs few tokens. The error is silent: a wrong guess compiles as the other meaning. Sys's own concern names the same case, a reader of the spec alone guessing wrong. A test does not reach that reader. I keep A.
>
> No vote changes.

- **Minimalism:**

> **Q1 (B, help only).** Strongest argument against: plt and aiml say a certain, checkable rewrite should be a fix, and the user sees the diff. I accept the rewrite is certain. My point is not safety but surface: `p.a.b = v` keeps the path, and `h.q.b = v` rewrites it and adds a pointer load. That is a second fix kind in `blink fix` and the LSP, with its own tests. web's concern (a skimmed quick-fix hides a load) adds weight on the same side. The cost of B is small: the help names the exact text to type. I keep B.
>
> **Q2 (B, keep and add).** Strongest argument against: web says the "desugars" sentence is wrong at depth 2, and plt says two statements of one rule can drift. sys answers the first point and I agree: the sentence speaks of `p.field`, and it stays true. It is incomplete, not wrong. The added sentence extends it and does not contradict it. On drift: one sentence stating the rule once, next to the Rule line, is one place to keep correct. A replacement moves wording that other sections cite. I keep B.
>
> **Q4 (B, no change).** Strongest argument against: web says readers do not read decision files, so the "no change" reading must be in the spec. The new §9.1.3 sentence already says a nested path is a field path, and §9.1.1 says "a field reached through `p.field`". A reader who joins the two gets the answer. sys's own concern applies: adding the phrase here and not at other "through `p.field`" sites implies those sites differ. I keep B.
>
> **Q5 (B, test only).** Strongest argument against: aiml and plt say a reader of the spec alone never sees the test, and may guess wrong on `p.a.read.read()`. This is the strongest argument in this round. My answer: the language already resolves a field and a method of one name by the call parentheses, in every other place. A spec that adds a note here implies this site is special. I keep B, and I would not object to a one-line note without an example.

D1 moves: Web changed Q1 to A. Systems and DevOps changed Q5 to A. Web, PLT and DevOps tied A on Q4 to a
change at all three §9.1.1 sites in one pass.

**D2: silent re-vote** (Q1, Q2, Q4, Q5; each seat read the Phase C and D1 files first)

- **Q1: The fix for `h.q.b = v`.** (5-1: A for Systems, Web, PLT, DevOps, AI/ML; B for Minimalism)
  - **Systems:** A — `h.q.read().b.write(v)` has one reading. It compiles to the same two accesses as the C `h->q->b = v`: one load of `q`, one store of `b`. The `.read()` shows that load in the diff, and the order of `place = rhs` does not change. `h.q.b = v` never compiled, so the fix changes no working program. `op=` stays help only because the path repeats.
    - Concern: A user who applies the quick-fix without reading the diff may not notice a new pointer load on a hot path.
  - **Web/Scripting:** A — `h.q.b = v` never compiled, so the rewrite `h.q.read().b.write(v)` changes no working program, and the `.read()` shows in the diff. With B, a JS or Python dev gets a quick-fix for `p.a.b = v` and none for `h.q.b = v`, and asks why. A fix that works is the "just works" case. `op=` stays help only.
    - Concern: A user who skims the quick-fix diff may not notice the added `.read()` is a pointer load.
  - **PLT:** A — `h.q.read().b.write(v)` is the unique well-typed rewrite of `h.q.b = v`. It keeps the order of `place = rhs` and the order of effects (load `q`, then store `b`). `h.q.b = v` never compiled, so the rewrite changes the meaning of no program. The fix site inserts a fixed token, and the load shows in the diff.
    - Concern: A fix that edits the path, not only the method, widens the fix surface, and a later change to how a `Ptr` loads could leave the rewrite stale.
  - **DevOps:** A — The rewrite `h.q.read().b.write(v)` has one correct form. `blink fix` and the LSP quick-fix can apply it, and the `.read()` shows in the diff. help only for this shape and a fix for `p.a.b = v` gives two kinds of E0611 output for near-identical code. The fix site is the same one that emits `write`; only the insert point differs.
    - Concern: A user who applies the quick-fix without reading the diff gets a pointer load on a hot path that they did not write.
  - **AI/ML:** A — The rewrite `h.q.read().b.write(v)` is the only well-typed form, so a tool can apply it with no choice. A model learns from a before/after pair; help-only text gives it no pair. web moved to A, and the load shows in the diff.
    - Concern: If A wins, a user who skims the quick-fix diff may not notice the added pointer load.
  - **Minimalism:** B — `p.a.b = v` keeps the path and adds `.write(v)`; `h.q.b = v` edits the path and inserts a load. That is a second fix shape with its own golden test and its own site in `blink fix` and the LSP. The help names the exact text, so the user loses one edit, not information. `op=` is already help only, so help only for this shape has precedent.
    - Concern: With A, each later path shape will ask for its own rewriting fix, and the fix table has no stated limit.

- **Q2: The §9.1.3 text.** (4-2: A for Web, PLT, DevOps, AI/ML; B for Systems, Minimalism)
  - **Systems:** B — The "desugars to a typed pointer-to-field" sentence is incomplete, not wrong: a nested path is one address at the summed offset, one access, no copy. That sentence holds the cost model, and other sections cite it. One added sentence after the Rule line gives the embedded step, the stop at a `Ptr` field and the `read()`/`write(v)`-only use. The new sentence must extend the old one and must not repeat it.
    - Concern: If the old sentence stays beside the new one, the paragraph can read as two rules ("one step", then "any depth"), and the drift that plt and web name can happen.
  - **Web/Scripting:** A — The old "desugars to a typed pointer-to-field" sentence gives no step rule, so a reader cannot tell if `p.a.b` is a field address or an `Int` copy. One sentence with root, embedded step and use is shorter to learn than the old sentence plus a patch. Other sections cite the term, not the sentence.
    - Concern: If B wins, the old sentence still reads as one step, and the added sentence reads as an exception.
  - **PLT:** A — The "desugars to a typed pointer-to-field" sentence gives the root clause only. A typing rule needs three clauses: root, embedded step, use. Keeping the old sentence and adding one after the Rule line states one rule twice, and the two statements can drift. The replacement keeps the settled content (typed offset, `read`/`write`, no first-class value) and changes only the wording.
    - Concern: The replaced sentence is cited from other sections, so the §9.1.1 and §2.22 cross-references need a check in the same edit.
  - **DevOps:** A — The old "desugars" sentence has no step rule. A diagnostic or an LSP hover for `p.a.` has no sentence to cite for how a path grows or why `h.q.b` stops. One replaced sentence states the rule once and cannot drift from a second statement.
    - Concern: Other sections may cite the old wording, and the edit may leave a stale reference.
  - **AI/ML:** A — The "desugars" sentence has no step rule, so a model that reads only the spec must infer depth 2. A kept sentence plus an added one states one rule twice, and the two can drift. Replacing it keeps the settled content and gives one place to learn the rule.
    - Concern: If A wins, other sections that cite the old wording must be checked, or a cross-reference points at text that is gone.
  - **Minimalism:** B — The "desugars to a typed pointer-to-field" sentence is incomplete, not wrong, and the `ffi-struct-construction` panel settled it. One added sentence after the Rule line states the embedded step and the `read()`/`write(v)` limit, once. A replacement moves wording that other sections cite, for no user gain.
    - Concern: If A wins, the replaced sentence may drop a property of the old wording that no seat noticed.

- **Q4: §9.1.1 scope tags.** A is the edit at all three sites (scope-tag row, cell definition, rule 1) in one pass. (5-1: A for Systems, Web, PLT, DevOps, AI/ML; B for Minimalism)
  - **Systems:** A — The tag rule is a safety rule for FFI memory. A reader of §9.1.1 alone should not have to infer that depth does not change the tag. I vote A on the condition that stands in D1: the same phrase goes into all three "through `p.field`" sites (scope-tag row, cell definition, rule 1) in one pass. The tag rule itself does not change at any depth; the phrase only states it.
    - Concern: If the edit covers one site and not the others, the spec implies that the other sites differ, and then B would have been better.
  - **Web/Scripting:** A — A reader of section 9.1.1 alone should not have to infer that the tag rule holds at depth 2. The option as written puts "at any embedded depth" into all three sites (scope-tag row, cell definition, rule 1) in one pass, which is the condition I set. A partial edit would be worse than none, so the impl must cover all three.
    - Concern: If the edit lands at one site only, the spec implies the other sites differ.
  - **PLT:** A — I voted B because one added phrase in one site implies that the other sites differ. D1 moved web, devops and sys to the same condition: the phrase goes into every "through `p.field`" site of §9.1.1 (the scope-tag row, the cell definition, rule 1) in one pass. I vote A only on that condition. With a full sweep, the three sites agree, and a reader of §9.1.1 alone sees that depth does not change the tag. If the sweep is partial, I vote B.
    - Concern: If the edit lands at the scope-tag row only, the unedited sites read as one-step rules, and that is worse than no change.
  - **DevOps:** A — I accept that the rule holds at every depth with no change. The phrase lets the E0601 help and an AI reader see this with no derivation. I vote A only with the one-pass condition: the same wording goes into the scope-tag row, the cell definition and rule 1 together. A partial edit makes the sites look different.
    - Concern: If the edit covers only one site, the spec implies the other "through `p.field`" sites differ.
  - **AI/ML:** A — A model cannot tell from the one-step wording that the tag rule holds at depth 2; the phrase removes that guess for few tokens. I vote A on the condition web, plt and devops state: the same phrase goes into all three sites (scope-tag row, cell definition, rule 1) in one pass. A partial edit would make the sites look different, and a model would read that as a real difference.
    - Concern: If the three sites are not all edited, the spec implies depth matters at the sites that lack the phrase.
  - **Minimalism:** B — The tag rule holds at every depth with no change, and the new §9.1.3 text says a nested path is a field path. A conditional A means a sweep of three sites (scope-tag row, cell definition, rule 1) to restate one fact. web says a partial A is worse than B, and I agree: a full A is three more places to keep correct.
    - Concern: If A wins, the phrase must go into all three sites in one pass, or the spec implies the sites differ.

- **Q5: The `read`/`write` field-name case.** A is one note in §9.1.3 (`p.a.read()` is the call; `p.a.read.read()` reads the field). (6-0: A)
  - **Systems:** A — I change from Phase C. A second compiler or a model that reads only the spec has no test to read. `p.a.read` is a field step and `p.a.read()` is a call; a wrong guess reads or writes the wrong thing and compiles. One line in §9.1.3 costs little. The golden test stays as the tooling pin.
    - Concern: The note can suggest that this name clash needs special care, and can invite the same note for other clashes.
  - **Web/Scripting:** A — `p.a.read.read()` looks wrong at first glance, and a new user or an AI will ask which `read` is the call. One line in section 9.1.3 answers it before the question reaches a forum. A test does not reach a reader of the spec. The golden test stays too.
    - Concern: If B wins, the first user with a field named `read` finds the rule by trial.
  - **PLT:** A — `p.a.read` (a field) and `p.a.read()` (the call) share a prefix, so the path grammar needs one sentence that says the call parentheses decide. A reader of the spec alone, such as a model or a second compiler, has no test to consult. One line settles it on paper.
    - Concern: A spec example for a rare name clash adds weight to §9.1.3 and may suggest that the case is common.
  - **DevOps:** A — I changed to A in D1. A model or a second compiler that reads only the spec has no test to read. Keep it to one line; the golden test and LSP completion test stay as the tooling pin.
    - Concern: A long example for a rare case adds text that every reader must carry.
  - **AI/ML:** A — A wrong guess between `p.a.read()` (call) and `p.a.read.read()` (field read) compiles as the other meaning, so the error is silent. A model that learns from the spec never sees a test. One line, as min accepts, costs few tokens.
    - Concern: If B wins, a model that meets a field named `read` or `write` has no spec text and must guess.
  - **Minimalism:** A — Five seats now want text, and the stated cost is one line. A spec-only reader (a model, a second compiler) has no test to read, and a wrong guess is silent. I vote for a one-line note, with no example block, and keep the test too.
    - Concern: A note on one name clash invites the same note for every other field/method name clash.

### Dissents

Each dissent is the seat's own D2 text (above), in short.

- **Minimalism, Q1 (B):** "`p.a.b = v` keeps the path and adds `.write(v)`; `h.q.b = v` edits the path and inserts a load. That is a second fix shape with its own golden test and its own site in `blink fix` and the LSP." Concern: "With A, each later path shape will ask for its own rewriting fix, and the fix table has no stated limit."
- **Systems, Q2 (B):** "The 'desugars to a typed pointer-to-field' sentence is incomplete, not wrong: a nested path is one address at the summed offset, one access, no copy." Concern: "If the old sentence stays beside the new one, the paragraph can read as two rules ('one step', then 'any depth'), and the drift that plt and web name can happen."
- **Minimalism, Q2 (B):** "A replacement moves wording that other sections cite, for no user gain." Concern: "If A wins, the replaced sentence may drop a property of the old wording that no seat noticed."
- **Minimalism, Q3 (B, Phase C; not reopened):** "A new term, even with no surface name, adds vocabulary that a reader must learn and that no user ever writes."
- **Minimalism, Q4 (B):** "A conditional A means a sweep of three sites (scope-tag row, cell definition, rule 1) to restate one fact."

How the ruling answers the concerns that the dissents and the winning seats raised:

- The Q2 text keeps the cost model (one address at the summed offset, one access, no copy) and the line "there is no first-class pointer-to-field value" beside the term, so the replaced sentence loses neither property.
- §9.1.1 and §2.22 cite `p.field.read()`, `p.field.write(v)` and "write on the same path". None cites the replaced sentence by its words. Only §9.1.3 used the words "pointer-to-field".
- Q4: all three §9.1.1 sites change in one pass.

### Reading gaps

In D2, DevOps reported a partial read: some Phase C and D1 files only as digest quotes, and part of its output was cut short. Its D2 votes match its D1 positions and its Phase C reasoning, and no D2 vote turns on its vote. All other seats listed every file as read in full.

### Final Spec

§9.1.3 *Field access on `Ptr[@ffi.struct T]`* gives three rules (root, embedded step, use) for a **field address**. It keeps the cost model and the "no first-class pointer-to-field value" line. A path stops at a `Ptr` field reached through it.

```blink
@ffi.struct(header: "geo.h", name: "inner")
pub type Inner { b: Int, c: Int }

@ffi.struct(header: "geo.h", name: "outer")
pub type Outer { a: Inner, n: Int }

@ffi.struct(header: "geo.h", name: "holder")
pub type Holder { q: Ptr[Inner], n: Int }

fn demo(i: Ptr[Inner]) ! IO {
    with ffi.scope() as scope {
        let p: Ptr[Outer] = scope.alloc[Outer]()
        p.a.b.write(5)                   // any embedded depth, one store
        io.println("{p.a.b.read()}")
        p.a.write(Inner { b: 7, c: 8 })  // the whole embedded struct

        let h: Ptr[Holder] = scope.alloc[Holder]()
        h.q.write(i)
        h.q.read().b.write(9)            // load `q`, then store `b`
        // h.q.b.write(9)                // error[BareFieldAddress]
    }
}
```

Locked points:

- `p.a.b.read()` and `p.a.b.write(v)` are legal at any embedded depth, at the sum of the C offsets. One address, one access, no copy.
- `p.a.read()` and `p.a.write(Inner { .. })` stay legal.
- The path stops at a `Ptr` field reached through it: `h.q.read().b.write(v)`. A `Ptr` value at the root is not such a step: `s.p.f.write(v)` stays legal.
- A path outside `read()`/`write(v)` is rejected at every depth with one named diagnostic, `BareFieldAddress` (E0850), not an ICE. The `h.q.b` form gets help to load the pointer first, naming `h.q.read().b`.
- E0611: `p.a.b = v` gets the machine fix `p.a.b.write(v)`. `h.q.b = v` gets the machine fix `h.q.read().b.write(v)`. `s.p.f = v` keeps `s.p.f.write(v)`. `op=` stays help only, with the path repeated.
- §9.1.1 says "at any embedded depth" at the scope-tag row, the cell definition and rule 1.
- A field named `read` or `write`: the call parentheses decide. One line in §9.1.3.
- The spec text does not name the code number. ERROR_CATALOG names E0850.

Open points (the spec leads the compiler):

- gen1 rejects `p.a.b.read()` and `p.a.b.write(v)` with `UnresolvedMethod` on `Int`.
- gen1 gives an internal compiler error (`FieldOwnerWithoutDecl`) for bare `p.a` and for `h.q.b.write(v)`.
- The E0611 help for `p.a.b = v` names a form that gen1 rejects until the first point is fixed.
- Tests for the implementation: the E0611 help and fix at depth 1, 2 and 3 and for the `h.q.b` form; `s.p.f.write(v)`; a field named `read` or `write`; E0601 at depth 2.
