[< All Decisions](../DECISIONS.md)

# Clone of a Boxed Field (Copy on Bind) — Design Rationale

The question: when the compiler stores a struct or enum field out of line (a heap box, for example a payload of the enum's own type), does `@derive(Clone)` share that box or copy it? The derived `clone()` body was `return self;` for every shape, which shares it, while §3.6.1 said Clone would "allocate a new struct or enum wrapper".

The panel found that no program can tell the two answers apart: a payload field is not a place (§2.22), so no write reaches a boxed node, and Blink has no identity operator. The gap was in the wording, not in the meaning.

Panelist text below is verbatim. Local tracker IDs are replaced by bracketed descriptions.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. The user asked for one more round on the Q5 clause, then handed the tie to the moderator.

#### Phase A — Independent proposals

**Systems:**

> **SYSTEMS proposal: the spec should describe Clone by what a program can observe, and the compiler shares the box**
>
> I checked the packet's facts myself. `lo_embeds_tid` (src/layout.bl:700) matches packet fact 1 exactly: the field type is the owner, or a tuple that contains it, and the walk stops at anything else. Fact 3 also holds: an enum payload is not a place (§2.22), so no write can reach into a boxed node.
>
> **Core point: no program can tell reading A from reading B.** A boxed node is only ever reached through a payload binder. No write can go through it, and Blink has no identity operator. The packet says "the answer matters as soon as a boxed field is mutable." Today a boxed field cannot be mutated. So the question is not which answer the program sees. It is which cost we let the compiler pay, and which promise we write down for the future.
>
> **Proposal 1 (main): copies share boxes. The spec states this, and gives the reason.**
>
> Add to §3.6.1 Clone Semantics, and refer to it from §3.4:
>
> > **Recursive fields.** A field whose type reaches its own type (§3.4) is stored behind a hidden pointer. The compiler chooses this; the program does not write it. No place (§2.22) reaches inside that pointer, so a bind, a copy or a `clone()` shares it. The result is still a full value copy for every program. `clone()` does not allocate a new node.
>
> Also replace the first sentence ("allocate a new struct or enum wrapper, copy field values") with:
>
> > `clone()` on a struct or enum gives the same value as a copy on bind (§3.6). Each field is copied by value. `Str`, `List`, `Map` and `Set` fields stay shared.
>
> ```blink
> @derive(Clone, Eq)
> type Tree {
>     Leaf
>     Node(v: Int, next: Tree)
> }
>
> fn main() ! IO {
>     let a = Tree.Node(1, Tree.Node(2, Tree.Leaf))
>     let b = a.clone()
>     let mut c = a
>     c = Tree.Leaf
>     io.println("{a == b}")
> }
> ```
>
> What this compiles to: `clone` is `return self;`, which is what the compiler emits today. That is one struct copy, no allocation, and no GC pressure. `c = Tree.Leaf` replaces c's own word and leaves `a` and `b` unchanged.
>
> Tradeoffs:
> - **For it:** clone and bind have the same cost, O(size of the inline value). Reading B needs one GC allocation per boxed field on every clone, but copies made by bind would still share. That would give bind and clone different meanings for the same value, all to guard against a write that cannot happen. It costs time and buys a contradiction.
> - **Against it:** the rule depends on one fact: "no place reaches a box." Any future feature that makes a payload or tuple element a place, or lets recursion go through `Option` ([the recursion-through-Option ticket]), breaks that fact without anyone noticing.
>
> **Proposal 2 (the guard, which goes with 1): an invariant future features must keep**
>
> > A field the compiler boxes is never the inside of a place. A feature that would make it one must also define copy-on-write for that box: a write through a shared box first copies the node into a box the writer owns.
>
> This turns "is sharing safe?" into a check each future proposal must pass ([the recursion-through-Option ticket], payload places, `Option[Self]` recursion). With it, Proposal 1 stays true and nobody has to think about it again. Copy-on-write puts the cost only on the write that needs it, as Swift does with its value types.
>
> **Rejected: reading B as written.** Each clone allocates, and the result is only one level deep anyway (the copied node still shares its own `next`). So you pay to allocate but do not get independent values; that is what `DeepClone` would be for. B also contradicts §3c ("values are copied on bind"), because bind does not allocate.
>
> **Cross-language note:** OCaml, Haskell and Rust's `Rc<T>` share immutable recursive nodes, and a copy is a pointer copy. Swift's indirect enums box the payload, share it on copy, and copy on write. Proposal 2 is the Swift rule, held in reserve until Blink makes a box writable. None of these languages allocates a node to clone an immutable recursive value.
>
> **My vote, ranked:** 1+2 together, then 1 alone. B: no.

**Web/Scripting:**

> **Web/scripting proposal on [this ticket]: a boxed field is invisible, and Clone works the same as a copy on bind**
>
> **Core claim.** Reading A and Reading B describe a choice the program cannot see. The spec should not pick between two ways to store the field. It should say the storage is invisible. I checked the packet against sections/: enum payloads are reached only through `match` binders, which are not places (§2.22). Binding copies a value (§3.6, §3c). `==` is structural, and the spec has no identity operator. So a Blink program has no way to tell "shared box" from "own box". If we write either reading into the spec, users and LLMs will reason about pointers that Blink does not let them touch. That is the Stack Overflow question we want to prevent ("does clone share my tree?").
>
> **Proposal 1 (main): say it in terms of values, then name the boxed case as invisible**
>
> Add to §3.6.1, after the "User structs/enums" bullet:
>
> > - **Recursive fields**: a field whose type contains its own owner type (for example `next: Tree` in `Node(v: Int, next: Tree)`) holds a value, the same as any other struct or enum field. The compiler may store such a field behind a pointer (§3.4). That pointer is not part of the language. No program can observe whether two values share it, because a struct or enum value is copied on bind and an enum payload is not a place. A clone of a recursive value acts as a value copy at every level. Only collections (`List`, `Map`, `Set`) stay shared after a clone.
>
> Also edit the lead sentence. "GC pointers are copied, not recursively cloned" becomes "Collection handles are copied, not recursively cloned". "GC pointers" is the phrase that caused this ticket, and a JS or Python user cannot map it to a type they wrote.
>
> ```blink
> @derive(Clone, Eq)
> type Tree {
>     Leaf
>     Node(v: Int, next: Tree)
> }
>
> fn main() ! IO {
>     let a = Tree.Node(1, Tree.Leaf)
>     let b = a.clone()
>     io.println("{a == b}")
> }
> ```
>
> The rule for users is short: **structs and enums are values, collections are shared cells, and clone copies one level, which only matters for collections.** A Python dev learns it in five minutes. The JS rule is the same: spread copies, and nested arrays stay shared.
>
> **Tradeoffs.**
> - For: no new concept, and it matches the emitted C (`return self;`). It does not tie the compiler to one layout, so the compiler stays free to intern or copy-on-write later. It also keeps "boxed" out of the user's vocabulary.
> - Against: it is an invariant the compiler must keep. If someone later adds payload places, `ref` binders or an identity operator, sharing becomes visible and this text breaks. Mitigation: the spec sentence names the two facts it depends on (copy on bind, and payloads are not places), so whoever changes either one will see the dependency. The open ticket [the recursion-through-Option ticket] (recursion through Option/payload) needs the same invariant, so the two should cite each other.
>
> **Proposal 2 (fallback, if the panel insists on picking a reading): Reading B, stated over bind**
>
> If the panel wants the text to say what is stored, choose Reading B. State it once, for bind and copy in general rather than for Clone alone: "binding or cloning a struct or enum value produces a value that does not share mutable state with the original, except through collections." Clone is then just bind under a trait name.
>
> Reading A I oppose outright. It makes `Tree` act like a reference type only when the compiler happened to box a field. That gives users a rule they cannot predict from their source: the same field shares or doesn't depending on a layout choice. Kotlin data classes and Python dataclasses at least share every nested object consistently. Reading A would be strictly worse than both.
>
> **Cross-language notes.** Swift enums with `indirect` are the closest model. The box exists but the semantics stay pure value semantics, and the docs say exactly that. Rust's `Box<T>` clone deep-copies the node, which also gives value behaviour. Both languages hide the box, and so should we.
>
> **Vote position:** Proposal 1. Proposal 2 is my second choice. Against Reading A as written.

**PLT:**

> The packet's codebase facts check out. `src/layout.bl:344` boxes a field only when it embeds its owner directly or through a tuple. Struct self-embedding has no finite value, so every boxed slot is an enum payload. Payloads are not places (§2.22), so no write path ever passes through a box.
>
> # PLT proposal: Clone and boxed fields
>
> ## The PLT question
> Is there a program that tells Reading A and Reading B apart? If there is not, the ticket is not a choice between two meanings. It is a question about how the spec should state the one meaning that holds under both.
>
> ## The equivalence argument
> 1. Structs and enums are values copied on bind (§3.6, §3c). Their denotation is a tree with no identity.
> 2. A program can see sharing in only two ways: an identity operator or a write. The packet confirms Blink has no identity operator, and `==` is structural Eq.
> 3. A write needs a place (§2.22): a field path rooted at a `let mut` binding. Enum payloads and Option payloads are not places, and a boxed slot is always an enum payload field. So no place ever passes through a box.
> 4. So the box contents are immutable after construction. Two handles to one immutable value are the same as two copies. A and B are observationally equivalent, and the gap is a representation leak into the spec.
>
> ## Proposal P1 (main): state Clone by type, and make boxing invisible
> Replace the "GC pointers are copied" sentence in §3.6.1 with:
>
> > `Clone` is defined by the declared type of each field, not by its representation. For a value type (Int, Float, Bool, Char, Str, and every user struct, enum and tuple), `x.clone()` equals `let y = x`: a copy of the value. For a shared cell (List, Map, Set), it copies the reference, so the clone and the original share one cell (one level deep).
> >
> > **Representation invariance.** The compiler can store a field in a heap box, for example a recursive enum payload. A box is not a shared cell. It does not change the meaning of any program. The compiler can share a box between copies only while no write can reach its contents. If a later rule makes such a write possible, the compiler must copy the box before the write.
>
> Add to §3.4 Recursive Types: "The indirection has value semantics. Two copies of a recursive value never observe each other's changes."
>
> ```blink
> @derive(Clone)
> type Tree {
>     Leaf
>     Node(v: Int, next: Tree)
> }
>
> fn main() ! IO {
>     let a = Tree.Node(1, Tree.Leaf)
>     let b = a.clone()
>     let c = a
>     io.println("{a == b} {a == c}")
> }
> ```
>
> The spec meaning is Reading B. The emitted `return self;` is a correct way to build it, by the equivalence above.
>
> **Tradeoffs.** This keeps the theory clean: values have no identity, so equational reasoning holds and `x.clone() == x` is a law for value types. Clone for value types becomes the identity function, which matches what the compiler emits today. The cost is a standing duty on future features: any rule that adds payload places, `&mut`, or interior mutability must keep this property (copy before write) or break the spec.
>
> **Cross-language.** OCaml and Haskell make the same choice: immutable recursive variants share structure freely, and that sharing is invisible. Swift enums with `indirect` are boxed but keep value semantics through copy-before-write. Rust's `Box<T>` Clone does a deep copy of the node because Rust has `&mut`. Blink does not, so it does not need to.
>
> ## Proposal P2 (secondary): one law for bind and Clone
> State one rule in §3.6 and use it in §3.6.1, §3.2.2 and §3c:
>
> > Bind, pass and return copy a value. Every type is either a **value** (copied with no identity) or a **cell** (List, Map, Set, Channel, Handle; copied as a reference). A value's copy holds copies of its value fields and the same references to its cell fields. Derived Clone is that copy.
>
> This removes the need to list types one by one in the Clone section. It also gives [the recursion-through-Option ticket] (E0701 recursion through immutable indirection) the lemma it needs: a cycle can only form through a cell, because the value graph is a tree.
>
> ## Reject
> Reading A as spec text. It makes the meaning depend on `layout.field_layout_of`, a compiler choice the program never wrote. That breaks abstraction: a change to layout would change what programs mean.
>
> ## Side note
> I did not check how `type S { next: Option[S] }` is laid out. Option stops the walk, so its carrier may embed S by value. That would be a layout bug, not a semantic one, and it does not change the argument above.

**DevOps:**

> ### DevOps/Tooling proposal on [this ticket]: a boxed field is invisible to the program
>
> **Fact check.** I checked the packet against §2.22. The packet's line 26 says "the answer matters as soon as a boxed field is mutable". Under the current rules a boxed field can never be written in place:
> - Today a field is only boxed if its declared type is its own owner (fact 1). A struct cannot hold itself (fact 2), so every boxed field is an enum payload field.
> - An enum payload field is reached only through a `match` binder, and a binder is not a place (§2.22).
> - `let mut n = binder` copies on bind (§3.6). After that, `n` can only be replaced whole. An enum has no field path, so `n.next = ...` is not a place.
>
> So no program can tell reading A from reading B. Sharing a node that nothing can write is the same as copying it. The spec gap is real, but it is a gap in the wording, not in the behavior.
>
> **Proposal 1 (my main proposal): state the rule over values, not over how they are stored.**
>
> Add to §3.6.1:
>
> > Clone and bind act on values. Storage the compiler picks, such as a boxed recursive payload, is not part of a value's meaning. The compiler may share storage between two values only when no place can reach that storage (§2.22). Field-wise copy then means the same thing for boxed and inline fields. Only the shared cells named above (Str, List, Map, Set) show sharing to the program.
>
> Then add one line under §3.4 Recursive Types: "The indirection is never a place. Two values may share it, and no program can tell."
>
> ```blink
> @derive(Clone)
> type Tree {
>     Leaf
>     Node(v: Int, next: Tree)
> }
>
> fn main() ! IO {
>     let a = Tree.Node(1, Tree.Leaf)
>     let mut b = a.clone()
>     b = Tree.Node(2, Tree.Leaf)
>     match a {
>         Tree.Node(v, _) => io.println("{v}")
>         Tree.Leaf => io.println("leaf")
>     }
> }
> ```
>
> This prints `1` under both readings. The program has no way to write into `a`'s node.
>
> Tradeoffs from tooling:
> - **No new diagnostic.** I would rather not add a check or an error code. Users never type a box, so an error that names one would confuse them.
> - **Clear hover text.** The LSP hover on a recursive payload field can say "stored by reference (shared, never written in place)". That is true under every reading, so the hover never has to change.
> - **Stable formatter and lint output.** Neither tool depends on how a field is laid out, which is how it should be.
> - **A rule the codegen must keep.** Today's `return self;` clone stays correct. If a later change ever makes a boxed field a place, it must copy on write or reject the write. I want that stated in the spec, so a future change that breaks it fails the spec test, not a user program.
>
> **Proposal 2 (fallback, if the panel wants reading B written down): copy the box.**
>
> The clone gets a box of its own, one level deep. Tooling cost: none to see, but it allocates for nothing, because nothing can tell the copy from the original. I vote against it. It writes down behavior that no program can observe, and it adds a rule users must learn for no gain.
>
> **Link to [the recursion-through-Option ticket].** If the panel later allows recursion through Option or a struct field, a boxed field could become a place. At that point this rule decides the answer: storage that a place can reach must not be shared, so the compiler must copy that box. I would put that clause in now. Then [the recursion-through-Option ticket] cannot quietly turn on reading A for writable storage.
>
> **Other languages.** Rust's `Box<T>: Clone` copies the box, because `&mut` makes the contents reachable for writes. Haskell and OCaml share immutable constructor cells, and no program can tell. Blink's place rules put it in the Haskell/OCaml group today, so the spec should say so in plain words.
>
> **Recommendation:** Proposal 1, plus the [the recursion-through-Option ticket] clause.

**AI/ML:**

> AI/ML PANELIST — PHASE A PROPOSAL ([this ticket])
>
> Framing: An LLM writing Blink cannot see layout.field_layout_of. Any rule that depends on whether the compiler boxed a field is a rule the model cannot learn from source alone. So the rule must be stated by declared type, and the boxed case must be stated as invisible.
>
> Fact check (packet is right): I grepped sections/ for mutable match binders (`Some(mut x)`, `ref mut`, "binder ... mut") and found none. Payload fields are not places (§2.22). So no program can write through a boxed payload field. Readings A and B produce the same observable result: you cannot tell them apart. The ticket's "matters as soon as a boxed field is mutable" names a case the language does not have.
>
> PROPOSAL 1 (primary): Clone of a struct or enum = copy on bind. Boxing is not observable.
>
> Spec wording for §3.6.1, replacing the "User structs/enums" bullet:
> - **User structs/enums**: `x.clone()` gives the same value as `let y = x`. Each field is copied by its declared type, using the rules above. A field whose declared type is a struct or enum is a value, and the copy is a value too, even when the compiler stores that field out of line (for example, a payload of the enum's own type). The program cannot see whether such storage is shared, because a payload field is not a place (§2.22). The compiler may share it.
>
> Add to §3.4 Recursive Types: "The indirection is not visible. A field of the owner's own type acts as a value in bind, Clone and `==`."
>
> ```blink
> @derive(Clone, Eq)
> type Tree {
>     Leaf
>     Node(v: Int, next: Tree)
> }
>
> fn main() ! IO {
>     let a = Tree.Node(1, Tree.Leaf)
>     let b = a.clone()
>     io.println("{a == b}")  // true; a and b are independent values
> }
> ```
>
> Tradeoffs (my domain):
> - Fewer decisions: one rule ("clone = bind copy, by declared type") in place of two (by type, or by representation). The model needs no layout knowledge.
> - Matches the generated code today (derived Clone is `return self;`), so this is not a compiler change. It records the existing behavior as the rule.
> - Token cost: about 3 lines of spec.
> - Risk: if a later feature makes payloads places (mutable binders, payload update), the "cannot see" sentence breaks. Mitigation: Proposal 2.
>
> PROPOSAL 2 (guard, works with 1): Lock the invariant, not just the case.
>
> Add to §3.6: "Only collections (`List`, `Map`, `Set`) are shared cells. A value of any other type, at any depth, cannot be changed through a second name. A feature that makes a payload or an out-of-line field a place must copy that storage before the write (copy on write) so this stays true."
>
> Why: this is the one sentence an LLM needs to reason about aliasing in Blink: "only collections alias". It also unblocks [the recursion-through-Option ticket], which asks for proof that no cycle can form through payload fields; this sentence is that proof's premise.
>
> PROPOSAL 3 (rejected by me, for the record): Reading A stated by representation ("a boxed field shares its node"). It makes the spec describe a compiler choice, it adds a third sharing category next to collections, and it gives the model a fact it cannot check from source. No.
>
> Cross-language: Swift indirect enums box payloads and still have value semantics; the box is invisible because enum payloads are immutable. Rust `Box<T>` clone copies deeply, but Rust exposes the Box in the type. Blink is the Swift case: no Box in source, so no Box in the rule. OCaml/Haskell share immutable nodes freely for the same reason: sharing an immutable value is not observable.
>
> Vote preference: 1 + 2.

**Minimalism:**

> Proposal from the minimalism seat, ranked by preference.
>
> ## M1 (preferred): Close it with the existing rules plus one invariance sentence. No new semantics.
>
> **Finding:** I checked the packet's facts against sections/. Readings A and B cannot be told apart by any Blink program, today or under the rules already decided. A boxed field is an enum payload (fact 2). A payload is reached only through a `match` binder, and a binder is not a place (§2.22). No `let mut` path reaches into a payload. Blink has no identity operator, and `==` is structural (fact 5). The one case where sharing shows is a collection inside the node. That collection is shared under **both** readings, because B's copy of the node still copies only one level. So the two readings give the same observable result. The ticket's own note confirms this: the derived Clone is `return self` for every shape.
>
> The ticket assumes "the answer matters as soon as a boxed field is mutable". No such field can exist under current rules. The gap is in the wording, not in the semantics.
>
> **Spec text** (add to §3.6.1, after the "User structs/enums" bullet):
>
> > **Representation is not semantics.** The compiler can store a field indirectly, for example a field of a recursive type (§3.4). That choice is invisible: a struct or enum value has value semantics, whatever its storage. Clone, bind and pass-by-value give the same observable result for such a field as for an inline one. Only `List`, `Map`, `Set` and other shared cells (§3.2.2) are shared, and only they can show a mutation made through another name.
>
> Also add one clause to §3.4: "The indirection is a representation choice and has no observable effect (§3.6.1)."
>
> ```blink
> @derive(Clone, Eq)
> type Tree {
>     Leaf
>     Node(v: Int, next: Tree)
> }
>
> fn main() ! IO {
>     let a = Tree.Node(1, Tree.Leaf)
>     let b = a.clone()
>     // No program can mutate a's `next` in place: a payload is not a place.
>     // So whether b shares a's boxed node is not observable.
>     io.println("{a == b}")
> }
> ```
>
> **Tradeoffs:**
> - No change to the compiler. The current `return self` stays correct, and the implementation keeps its freedom (shared boxes, hash-consing, inline storage later).
> - The rule states a fact that holds for the whole language, so it does not need a new rule for each boxed shape. This follows the principle at §3.6 line 1799, which says behavior follows the declared type and not how the compiler spells or stores it.
> - **Constraint we take on:** any future feature that makes a payload a place, adds identity comparison, or lets a non-collection type hold interior mutability must keep this invariant or reopen it. That is the correct burden. It puts the cost on whoever adds the mutation, not on Clone. Link this to [the recursion-through-Option ticket], which needs the same "no mutation through payload or struct field" proof.
>
> **Cross-language:** OCaml and Haskell share immutable subterms freely, and no program can see it. Swift indirect enums are boxed and still have value semantics. Swift is the closest precedent and is exactly this rule.
>
> ## M2 (fallback, if the panel wants Clone's own text to name the case)
>
> One sentence in the Clone bullet: "A field stored indirectly is copied like any other value field. Because struct and enum values cannot be mutated in place through such a field, sharing the stored node is a valid implementation." This is Reading B in the text and Reading A in the implementation, made legal by the same invariance argument. It is more words for the same result. I support it only if M1's general sentence is considered too broad.
>
> ## Rejected
> - **Reading A in the spec** ("Clone shares boxed nodes"): this puts a compiler representation choice into the language contract. It conflicts with §3.6/§3c value semantics and would block later layout changes.
> - **Reading B as a real deep-allocate requirement:** it forces allocation for no observable gain. It is also DeepClone by the back door, and that was deferred 3-2.
> - **A new trait, attribute or `indirect` keyword:** Swift needed `indirect` only because it does not infer the boxing. Blink does (§3.4). There is nothing to add.
>
> **Vote position:** M1 > M2 >> anything that adds surface.

#### Phase B — Debate (one round; all six then said "stable, ready to vote")

Facts the moderator gave the panel: the emitted `Option` carrier for a struct payload holds the payload by pointer (`typedef struct { int tag; blink_A* value; } blink_Option_A;`); §3.6 already said a struct copy shares only its shared-cell fields; §3.2.2 lists `StringBuilder.write` as a mutating method.

**Minimalism:**

> V1: I side with the "invisible, may share" wording. Sys's version says "`clone()` does not allocate a new node", which writes today's codegen into the contract. That takes away freedom we gain nothing by giving up, for example interning the box or storing it inline later. The spec should state what a program can observe, not what the compiler costs.
>
> V2: I accept one guard sentence, but it must not choose the mechanism. Sys, PLT and AI/ML write "must copy before the write". DevOps is right that the feature could also reject the write. A future panel should make that choice when the feature arrives, not us now. My wording: "A feature that lets a write reach such storage must keep this rule." That is one sentence and adds no new concept. It still gives [the recursion-through-Option ticket] its premise.
>
> V3: I vote no on the general value/cell law in this ticket. PLT P2 and AI/ML P2 are good ideas, but they are a rewrite of §3.6, and this gap is one missing sentence. PLT P2 also names Channel and Handle as cells, and nobody on the panel has checked that claim against the spec. If the panel wants the law, file it as its own spec ticket and check its facts there. Keep this one small.
>
> V4: I vote no on listing `Str` as shared. A `Str` is immutable, so its sharing cannot be observed, which is the same as a box. Putting it in the "shared" list next to List/Map/Set tells readers that sharing can be observed where it cannot. Sys and DevOps: this is the same mistake the ticket asks us to fix. I would also not hard-code the list. §3.2.2 already lists the mutating cells, and it includes StringBuilder, which every list proposed here leaves out. That shows why enumerating cells in two places goes stale. Write "shared cells (§3.2.2)" and give List/Map/Set only as examples.
>
> V5: I support Web's edit, "GC pointers" -> "Collection handles". That phrase caused this ticket, and the change is a deletion, not an addition. PLT's longer replacement is also acceptable, but it adds more words. I prefer Web's.
>
> Summary of my position: M1 text, plus the guard sentence from V2 without the mechanism, plus Web's V5 edit. Nothing in §3.6 beyond that.
>
> Stable, ready to vote.

**DevOps:**

> **DevOps/Tooling, Phase B round 1**
>
> **V1. The compiler MAY share; the spec should not promise it.** I am against sys P1's wording "`clone()` does not allocate a new node". It turns an implementation fact into a contract. Docs, hover text and the LLM reference would then repeat a promise about how the compiler works, and a later change to layout (hash-consing, putting small nodes inline) would break the spec without changing any program. I would keep sys's point about cost as a non-normative note ("today a clone of a struct or enum is one value copy and does not allocate"). Also, plt P1 says "the spec meaning is Reading B": I would keep both reading names out of the spec. "Reading A" and "Reading B" belong to the ticket; a user reading §3.6.1 should never see them.
>
> I also take back my own Phase A hover text, "stored by reference (shared, never written in place)". It names sharing, which is the same leak I object to in sys's wording. The hover should say "value (stored out of line)" and nothing more.
>
> **V2. Yes, put the copy-before-write duty in the spec text.** Tooling needs a sentence that a reviewer or a conformance test can point to. A dependency named only in the design notes (web, min) will not be in front of the person who later adds payload places or `mut` binders. One sentence in the style of sys P2 or aiml P2 is enough.
>
> **V3. §3.6.1 + §3.4 + aiml P2's single sentence in §3.6.** "Only shared cells alias; a value of any other type, at any depth, cannot be changed through a second name." This is the one line that error messages and LSP explanations can quote (for example the MutAliasOfImmutable warning text). I am not for plt P2's full value/cell list in this ticket. It names Channel and Handle, and nobody here has checked those against §3.2.2. That is a scope jump, and it can have its own ticket.
>
> **V4. I correct my Phase A list: take Str out.** Str is immutable, so sharing a Str is no more visible than sharing a box. Listing it next to List/Map/Set repeats the representation-over-meaning mistake this ticket is about. I would use min's form, "shared cells (§3.2.2)", and not list the types. That way the Clone section and §3.2.2 cannot drift apart when a new cell type comes in (§3.2.2 already lists StringBuilder.write, which none of our lists name).
>
> **V5. I support web's edit.** "GC pointers" is the phrase that caused this ticket. No user can map it to a type they wrote, and no diagnostic can point to it. I would use: "Shared cells (§3.2.2) are copied by reference, not recursively cloned."
>
> **My combined text:** devops P1 / min M1 core sentence + aiml P2 guard sentence + web V5 edit + min V4 reference.
>
> Stable, ready to vote.

**Systems:**

> SYSTEMS, Phase B round 1. Stable, ready to vote.
>
> **V1: I drop "shares" and accept "may share".** The moderator's probe changes my view. The Option carrier holds `blink_A* value`, so the compiler already stores struct payloads out of line in places `lo_embeds_tid` never sees. My P1 described the box as "a field whose type reaches its own type". That is too narrow already, and it would bind the spec to one layout routine. The rule must cover any storage the compiler picks: recursive payloads, Option carriers, and whatever comes later. "Not observable; the compiler may share" (web, aiml, devops, min) is the correct shape. My cost claim does not change: `return self;` stays legal, so clone and bind cost the same.
>
> **V2: the copy-before-write duty goes in the spec text. This is not negotiable for me.** web and min say the sentence "names its dependencies". That is a comment, not a rule. [the recursion-through-Option ticket] is already open and asks for recursion through Option/payload. If no clause binds it, a later change can make a box writable, and sharing then leaks into user programs without any spec text being broken. plt's "Representation invariance" paragraph has the right content. Either plt's wording or aiml P2's wording is fine with me.
>
> **V3: yes to one general law in §3.6, and aiml P2 is the closer version.** "Only shared cells alias; any other value, at any depth, cannot change through a second name" is the property codegen depends on. It is also the premise [the recursion-through-Option ticket] needs. plt P2 says the same thing, but it lists Channel and Handle as cells, and I have not checked that against §3.2.2. Whichever text wins should not keep its own list.
>
> **V4: refer to §3.2.2 and do not list types (min's form).** I withdraw `Str` from my list. Str is immutable, so sharing it cannot be seen either; it is the same argument as for the box. A list in the Clone section will drift away from §3.2.2. `StringBuilder` is already a mutating type that every list in Phase A missed.
>
> **V5: replace both representation phrases.** "GC pointers are copied" and "allocate a new struct or enum wrapper" both describe storage. Neither is true of the emitted C: no wrapper is allocated, and the clone is `return self;`. Replace them with "clone() on a struct or enum equals a copy on bind; cells (§3.2.2) stay shared, one level deep."
>
> **plt on "The spec meaning is Reading B":** I do not object as long as the text says that sharing is a valid implementation. But we should not label the result A or B at all. Both readings are about storage, and the text we agree on says storage has no meaning.
>
> **My vote:** devops P1 / aiml P1 wording for the core text, plus plt's representation-invariance clause (copy before write), plus aiml P2's general law in §3.6, which points to §3.2.2 for the list of cells.

**Web/Scripting:**

> Web/scripting, Phase B round 1: we agree on the core (the box is invisible, clone = copy on bind). My positions on V1-V5 follow.
>
> **V1: use "may share", not "shares".** I disagree with sys P1's wording ("a bind, a copy or a `clone()` shares it ... does not allocate a new node"). The rule is right, but it uses the words users fear. A JS or Python dev who reads "shares" in the Clone section will ask "so my clone is linked to the original?". Every Stack Overflow answer will then have to explain why that doesn't matter. Say the storage is invisible and the compiler MAY share it (devops, aiml, min, plt). Sys's cost argument still holds, because "may" allows `return self;`. plt: the reasoning that "the spec meaning is Reading B" is fine, but keep the words "Reading B" out of the spec text.
>
> **V2: yes, put the copy-before-write duty in the spec, as one sentence.** I move from "name the dependency" to supporting a normative clause, as sys P2, aiml P2, plt and devops proposed. A dependency that only gets a mention is one that no one will notice later. Keep it to one sentence in §3.6.1, for example: "A feature that makes such storage reachable by a write must copy it before the write." Don't add a separate subsection.
>
> **V3: add the general law, but keep it short.** aiml P2's sentence is the best DX text on the table: "a value of any other type, at any depth, cannot be changed through a second name." That is the mental model in one line. I support adding it to §3.6. I am against plt P2's full value/cell list in this ticket. It names Channel and Handle, which no one here has checked against their own sections. Do that taxonomy as a separate ticket.
>
> **V4: don't list `Str` as shared, and fix "only collections".** `Str` is immutable, so sharing it can't be seen. If we put it in the "stays shared" list, users will ask "can my string change under me?". Also, §3.2.2 lists `StringBuilder.write` as a mutating method, so StringBuilder is a cell too. aiml's "only collections (List, Map, Set)" is therefore wrong as written, and so was my own P1 list. I adopt min's wording: "`List`, `Map`, `Set` and other shared cells (§3.2.2)". It is correct now and stays correct when new cells are added.
>
> **V5:** in line with V4, the lead sentence should read "Shared-cell handles are copied, not recursively cloned". Drop "GC pointers" in every version. plt's "defined by the declared type" sentence also works if the moderator prefers it.
>
> Combined text I'd vote for: aiml P1 bullet + min's cell wording + the one-sentence copy-before-write clause + aiml P2's law in §3.6 + one line in §3.4.
>
> Stable, ready to vote.

**PLT:**

> PLT Phase B round 1: I back the shared core and am stable, ready to vote.
>
> All six main proposals say the same thing: a value has no identity, and boxing is representation. My positions on the open points:
>
> V1: "may share" is the rule; sys's sentence should become a note. sys's "`clone()` does not allocate a new node" promises an implementation detail. A future copy-on-write or arena layout could allocate and still be correct, so the spec should not forbid it. The sentence is fine as an informative note under the rule. I withdraw my own line "The spec meaning is Reading B". Both readings mean the same thing, so naming one of them only confuses readers. Say instead: "every implementation in which no write reaches shared storage is correct."
>
> V2: the copy-before-write clause goes in the spec text. This is the soundness point. Without it, M1/web P1 are true only by accident of today's place rules, and [the recursion-through-Option ticket] or a mutable binder would break them silently. The clause turns a fact about today into an invariant each future feature must keep. Wording: "Storage the compiler shares between values is never inside a place. A feature that would put it inside one must copy that storage before the write." It should cover ANY indirection, not only `field_layout_of`'s PointerBoxed. The moderator's probe shows the Option carrier also holds its payload by pointer (`blink_A* value`), so a rule that names "boxed recursive fields" alone would miss that case.
>
> V3: yes to a general value/cell law in §3.6. Merge my P2 and aiml P2. One law covers bind, pass, return and Clone, so §3.6.1 shrinks to "derived Clone is the copy on bind". It is also the premise [the recursion-through-Option ticket] needs: values form a tree, and only cells can close a cycle.
>
> V4: the shared-cell list is wrong in two places.
> - (a) Remove `Str` from it (sys, devops). Str is immutable, so its sharing cannot be seen. It is a value by the same argument as the box. Leaving it in teaches users and LLMs that a Str can alias. devops's text "Only the shared cells named above (Str, ...) show sharing" is false for Str.
> - (b) aiml's "Only collections are shared cells" is too narrow. StringBuilder (§3.2.2 lists `.write`), Channel and Handle can also show a change made through another name.
>
> So use min's form, which refers to §3.2.2 and does not repeat a list. Make §3.2.2 the one list of cells, and add StringBuilder, Channel and Handle to it if they are not already there.
>
> V5: yes, remove "GC pointers". It is the root cause of this ticket. Replace it with the declared-type wording, or with web's "collection handles" if the wider rewrite does not pass.
>
> Preferred package: common P1 core ("may share", by declared type) + the V2 clause covering any indirection + the V3 law, with the cell list defined in §3.2.2 only. Second choice: P1 + V2 without the V3 law. Against: any text that names Reading A, and any requirement that a clone must allocate.

**AI/ML:**

> I sent my round 1 reply to the moderator and said I'm stable and ready to vote.
>
> **Correction to my own Phase A text.** My Proposal 2 said "only `List`, `Map`, `Set` are shared". That is wrong. §3.2.2 makes `StringBuilder` a shared type too: its `write` methods mutate it, like `push` on a collection. plt also names Channel and Handle. I withdrew my list so the spec doesn't teach an incomplete one.
>
> **My positions on the five open points:**
> - **Which types are shared (V4):** List them once, in one section, and have every other section point there. Two lists that differ give an LLM two answers. `Str` should not be on that list: strings can't be changed, so sharing them is as invisible as the box. Sys and devops listed `Str` as shared.
> - **How to word the box (V1):** Say the compiler "may share" the storage. Sys wanted "`clone()` does not allocate a new node", but that promises a storage choice, which is the leak this ticket is about. It would also block the copy-before-write rule below.
> - **Copy-before-write (V2):** Keep it in the spec. plt's "Representation invariance" paragraph is the best wording, so I dropped my own sentence for it. It also gives ticket [the recursion-through-Option ticket] the fact it needs to start from.
> - **General rule (V3):** I back plt's rule that every type is either a value or a shared type, stated in §3.6. The Clone section then shrinks to one line: derived Clone is the copy made on bind.
> - **Lead sentence (V5):** Replace "GC pointers are copied". No type a user writes is called a "GC pointer".
>
> **Combined position:**
> - plt's Proposal 1 text plus its "Representation invariance" paragraph.
> - plt's value-or-shared rule, with a single list of shared types.
> - `Str` in the value group.
> - The lead sentence reworded.
>
> I asked the moderator to check the full list of shared types against `sections/`. I'm waiting for the vote.

#### Phase C — Silent vote

Facts given with the ballot: §3.2.2 has no list headed "shared cells"; §3.6 named `List`, `Map`, `Set` and closures or handlers that captured `let mut`; §4.7 and §2.8 call a captured `let mut` a shared cell; no spec text says whether a `Channel` or an effect handle is shared after a copy.

- **Q1: the box is not observable and the compiler MAY share it** — 6-0
- **Q2: guard on future features** — A 4 (Systems, PLT, DevOps, AI/ML), B 1 (Web), C 1 (Minimalism) → Phase D
- **Q3: one general law in §3.6** — A 5-1, **Minimalism (dissent)**: file it as its own ticket
- **Q4: refer to the shared-cell list, do not name `Str`** — 6-0 (four ballots: the reference must point at §3.6, not §3.2.2)
- **Q4b: one shared-cell list in this ticket** — Yes 4 (AI/ML, DevOps, Web, Systems), No 2 (Minimalism, PLT) → Phase D
- **Q5: lead sentence** — C 3 (AI/ML, Web, Systems), A 1 (Minimalism), B 1 (DevOps), D 1 (PLT) → Phase D

**AI/ML:**

> AI/ML — PHASE C BALLOT
>
> Q1 — Vote: A
> Reasoning: An LLM cannot see storage choices, so a rule about storage is a rule it cannot apply. "Not observable, MAY share" gives the model nothing to track and leaves room for a copy-before-write path later. A non-normative note about the current allocation is fine.
> Concern: Some reader may still treat "may share" as a hint that sharing can be observed; the sentence must put "not observable" first.
>
> Q2 — Vote: A (plt)
> Reasoning: It names the duty (copy before the write), not just "keep the rule". A model or a future spec author then has one action to take, not a choice between copying and rejecting. It also gives [the recursion-through-Option ticket] its premise in plain words.
> Concern: "never inside a place" is only true while §2.22 stays as it is, so the sentence should cite §2.22.
>
> Q3 — Vote: A
> Reasoning: One sentence, "only shared cells can change through a second name", is the most useful aliasing fact a model can hold about Blink, and it costs about 25 tokens. plt's full taxonomy (B) is good, but it is a bigger edit that would touch Channel/Handle (no spec text says how those behave), so it belongs in its own ticket. Option C leaves the core law out of the place where users will look.
> Concern: If the shared-cell list is incomplete, this "only" sentence becomes a false claim, so it depends on Q4b.
>
> Q4 — Vote: A
> Reasoning: Naming Str as shared teaches a model that a Str can show a mutation through an alias, which is false. Referring to the list, rather than copying it, keeps one source of truth.
> Concern: "(§3.2.2)" points to a section that has no list (fact 2), so the reference must point to the list Q4b chooses.
>
> Q4b — Vote: Yes
> Reasoning: Facts 1–3 show three partial lists in three sections, and they differ (§3.6 has closures/handlers; §3.2.2 implies StringBuilder; neither has both). For an LLM, two lists that differ give two answers to one question, and the general law (Q3) needs a complete list to be true. Put the one list in §3.6, next to the existing "Passing or binding a struct copies its fields" text (fact 1), and include: List, Map, Set, StringBuilder, and a closure or handler that captured a `let mut` binding. §3.2.2, §2.8 and §4 then point to it. Channel and Handle: file a separate ticket (fact 4), because deciding them is new spec work.
> Concern: Leaving Channel/Handle out while the list says "only" makes the list wrong if they turn out to be cells, so the follow-up ticket must be filed in the same change.
>
> Q5 — Vote: C (sys), with its reference changed to point to the Q4b list
> Reasoning: "clone() on a struct or enum equals a copy on bind" is one equation a model can apply with no layout knowledge, and it is the shortest option. D is correct but longer, and it repeats the declared-type rule that the Clone bullets already state. A and B keep "copied" ambiguous: copied pointer, or copied value?
> Concern: If the reference stays "§3.2.2", it points to a section with no list.

**Minimalism:**

> Minimalism Phase C ballot.
>
> Q1: A.
> Reasoning: The spec should state what a program can observe, not what the compiler costs. "`clone()` does not allocate" writes today's codegen into the contract, and it blocks interning or inline storage later. As a non-normative note it does no harm.
> Concern: A reader can take "may share" to mean the sharing can be seen. The sentence must say clearly that it cannot.
>
> Q2: C.
> Reasoning: The guard has to make sure that a future feature cannot quietly break the rule. Whether that feature copies before the write or rejects the write is that feature's own design question, and DevOps named both as valid. A and B decide it now, with no feature on the table to decide it against. That is a decision made too early.
> Concern: If B wins, "copy before write" becomes a promise a future panel has to work around even when rejecting the write is the better design.
>
> Q3: C.
> Reasoning: This gap is one missing sentence. A general value/cell law changes §3.6 and needs its own fact check. Fact 4 shows the cell list is not settled: the spec says nothing about Channel or Handle. Put a law that depends on unchecked facts in its own ticket, not into this one.
> Concern: If A wins, "at any depth, cannot be changed through a second name" claims too much for Channel and Handle, which the spec has not yet classified.
>
> Q4: A, with one change of reference because of facts 1 and 2. §3.2.2 has no list of shared cells. The complete existing list is §3.6 (03_types.md:2446), which names List, Map, Set and closures or handlers that captured a `let mut`. So the text should read "`List`, `Map`, `Set` and other shared cells (§3.6)". Do not name `Str`.
> Reasoning: An immutable Str has the same unobservable sharing as a box. If the text calls it shared, it repeats the mistake this ticket fixes. Referring to an existing list, instead of writing a second one, keeps one source.
> Concern: A reference that points to the wrong section gives readers nothing to follow. My Phase A text pointed to §3.2.2, and that was wrong. Check the target before merging.
>
> Q4b: No.
> Reasoning: With the Q4 reference changed to §3.6:2446, this ticket adds no list and needs none. Making §3.6 the one list, and fixing the "Collections are shared cells" rationale wording in §3.2.2, is cleanup that belongs in its own ticket, together with the Q3 law and the Channel/Handle question (fact 4).
> Concern: Until that ticket closes, §3.2.2's "Collections are shared cells" is an incomplete statement: it leaves out closure captures.
>
> Q5: A ("Shared-cell handles are copied, not recursively cloned.")
> Reasoning: It uses the fewest words and has no section reference. B and C both cite §3.2.2, which facts 1 and 2 show does not hold a list. Given fact 1 (closures that capture a `let mut` are cells too), I drop my round 1 preference for "Collection handles", which would leave them out.
> Concern: "Shared cell" is not defined in one place. A reader must find §3.6:2446 to learn what it covers. The Q4b follow-up ticket fixes that.

**PLT:**

> PLT Phase C ballot: Q1 A, Q2 A, Q3 A, Q4 A (with the § reference pointed at §3.6), Q4b No, Q5 D.
>
> Q1
> Vote: A.
> Reasoning: The spec should state meaning (an observational equivalence), not an allocation strategy. "Does not allocate" is a promise about implementation. A correct copy-on-write or arena layout would break it, and no program could see the difference.
> Concern: Readers will skip "may share" and treat today's sharing as a guarantee. The note must be clearly marked as non-normative.
>
> Q2
> Vote: A.
> Reasoning: Only A keeps the theorem true by construction. C leaves "keep this rule" with no fixed meaning, so a later feature could argue about it. D makes the equivalence an accident of today's place rules. A is also broader than B on purpose: it covers any shared storage, including the Option carrier pointer, not only boxed recursive fields. Rejecting the write (a static error) also keeps the rule true, so A could say "copy that storage before the write, or reject the write" with no loss.
> Concern: Someone adding payload places or mutable binders may miss this rule. Cross-reference it from §2.22 (places) so it is seen where places are defined.
>
> Q3
> Vote: A.
> Reasoning: Fact 1 shows §3.6 already states most of the law for one level. A adds the missing "at any depth" quantifier, and that quantifier is the lemma [the recursion-through-Option ticket] needs. B's full taxonomy would duplicate §3.6 text that already exists and would force us to decide Channel/Handle now (fact 4).
> Concern: "Cannot be changed through a second name" must be read as observable change. If it is read as storage identity, it contradicts Q1 A.
>
> Q4
> Vote: A, with one fix. Point the reference at §3.6 (line 2446), not §3.2.2. Fact 2 says §3.2.2 has no list of cells. Fact 1 says §3.6 does, and it also counts closures and handlers that capture a `let mut` binding.
> Reasoning: Str is immutable, so its sharing cannot be observed. It is a value by the same argument as the box. Naming it as shared (B) teaches a false aliasing model.
> Concern: A reference to the wrong section leaves readers with no list to follow. Check the target before you write it.
>
> Q4b
> Vote: No. File it as a separate ticket.
> Reasoning: One list is the right end state. But fact 4 shows that Channel and Handle copy semantics are not specified at all. Settling them is a new spec decision, not a wording fix, and it should not ride on this ticket. For now, §3.6 line 2446 is the de facto list, and Q4's reference should point there.
> Concern: The separate ticket stays at low priority, and the lists in §3.2.2, §3.6 and §4 drift further apart.
>
> Q5
> Vote: D. C is a close second.
> Reasoning: D states the principle that settles this ticket and any future layout question: Clone follows the declared type, not the representation. C says the same about bind but leaves out "not by representation". That clause is the part that stops a new reading by representation from appearing.
> Concern: D is longer. If it is cut down to fit, the "not by its representation" clause must stay.

**DevOps:**

> DevOps/Tooling Phase C ballot for [this ticket].
>
> Q1: A
> Reasoning: Docs, hover text and the LLM reference repeat what the spec states. If the spec states a fact about allocation, that fact becomes a contract no program can test, and a layout change (hash-consing, inline small nodes) would break the spec without changing any program's output. sys's cost note is still useful, so it goes in as a non-normative note.
> Concern: "MAY share" can read as permission to share writable storage. Q2's guard must sit next to it, not in another section.
>
> Q2: A
> Reasoning: A reviewer or a conformance test needs both halves in one sentence it can point to. The first half is the invariant (shared storage is never inside a place). The second half is the required fix (copy before the write). B states only the fix, and C states neither, so whoever adds payload places or `mut` binders gets no answer from the spec.
> Concern: "copy before the write" rules out the other legal fix, a compile error that rejects the write. If the panel wants that path open, add "or reject the write".
>
> Q3: A
> Reasoning: An error message or an LSP explanation can quote this one sentence (for example in the MutAliasOfImmutable text). B's taxonomy names Channel and Handle, which fact 4 says the spec does not cover. That is new scope and needs its own ticket.
> Concern: "at any depth" has to stay true for a struct field that holds a closure that captured `let mut`. The sentence has to defer to the cell list (Q4b), not to a hand-written type list.
>
> Q4: A, with one amendment. Fact 2 shows §3.2.2 has no list of shared cells, so a reference to §3.2.2 points at nothing. Point it at §3.6 instead (line 2446), which has the only real list: List, Map, Set, and a closure or handler that captured a `let mut` binding.
> Reasoning: Str is immutable, so listing it as shared is the same representation-over-meaning leak this ticket fixes. A reference does not drift; a copied list does.
> Concern: A reference to a section with no list sends readers and tools to a dead end. That is why I vote Yes on Q4b.
>
> Q4b: Yes, minimal. Name the existing §3.6 sentence (line 2446) as the one list of shared cells, and have §3.6.1, §3.2.2's rationale and the new Q3 sentence refer to it. Do not add Channel or Handle here. File those as a separate spec ticket (fact 4).
> Reasoning: Q3, Q4 and Q5 all need a target for their reference. Picking one is cheap, and it settles what every other line in this ticket points to.
> Concern: The §3.6 sentence is written as prose about structs, not as a list. It may need light rewording to work as a reference target.
>
> Q5: B, with the reference changed to §3.6 per Q4/Q4b: "Shared cells (§3.6) are copied by reference, not recursively cloned."
> Reasoning: It removes "GC pointers", the phrase that caused this ticket, and names a concept the user can find in the spec. C mixes the struct rule into the lead sentence. D is good text but long for a lead sentence, and its content is already covered by Q1 and Q3.
> Concern: "by reference" may make users think of pass-by-reference. If that wording is the problem, web's "handles are copied" (A) is fine as an alternative.

**Web/Scripting:**

> Web/scripting Phase C ballot.
>
> **Q1: A**
> Reasoning: Users and LLMs should not learn a rule about storage they never wrote. "Not observable, the compiler MAY share it" answers the question "is my clone linked?" with a clear no, and still allows today's `return self;`. sys's no-allocation point is useful to implementers, so put it in a non-normative note.
> Concern: if the note's text drifts toward "copies share the box", the user-facing confusion comes back. The note must say why sharing is safe, not only that it happens.
>
> **Q2: B**
> Reasoning: one sentence that names the remedy (copy before write) gives future feature authors a concrete duty that a test can check. C ("must keep this rule") leaves the choice of mechanism open, and an open choice is what lets a feature quietly turn on Reading A. A says the same thing as B in more words.
> Concern: it commits the language to copy-on-write over a compile error for some future feature. If that feature's panel wants to reject the write instead, it must amend this sentence on purpose. I'm fine with that.
>
> **Q3: A**
> Reasoning: "a value of any other type, at any depth, cannot be changed through a second name" is the one-line mental model a JS or Python dev needs. Fact 1 shows §3.6 almost states it already, so this is one sentence, not a new concept. plt's full taxonomy needs checks on Channel and Handle (fact 4) that nobody has done.
> Concern: if the sentence refers to a cell list that doesn't exist (see Q4b), readers get a dangling reference.
>
> **Q4: A, with the reference changed from §3.2.2 to §3.6**
> Reasoning: don't name `Str` as shared, because it's immutable and naming it makes users ask whether strings can change. Facts 1 to 3 show §3.2.2 has no cell list and leaves out captured `let mut` closures and handlers, but §3.6 line 2446 already lists them. Use "`List`, `Map`, `Set` and other shared cells (§3.6)".
> Concern: with §3.2.2 as the target, the reference points readers to the wrong section and misses closures.
>
> **Q4b: Yes, but scoped**
> Reasoning: Q3 and Q4 both refer to "shared cells", so this ticket must give that phrase one home, or we ship a dangling reference. Make the existing §3.6 sentence the single list: List, Map, Set, StringBuilder, and closures or handlers that captured a `let mut` binding. All of these are already in the spec. Have §3.2.2, §2.8 and §4 refer to it. Channel and Handle (fact 4) go to a separate ticket. This ticket should not decide new semantics.
> Concern: the scoped list could be read as closed, implying Channel and Handle are values, before their ticket decides. Add "this list is not yet complete for Channel and Handle", or file that ticket at once.
>
> **Q5: C, with the cell reference changed to §3.6**
> Reasoning: "clone() on a struct or enum equals a copy on bind" is the most useful sentence for a newcomer. It makes clone a thing they already understand and removes a separate concept. A (mine) is accurate but describes a mechanism. C states the outcome.
> Concern: a reader may then ask "so why does Clone exist?". One clause on its purpose (generic code with a `T: Clone` bound) heads that off.

**Systems:**

> SYSTEMS, Phase C ballot.
>
> **Q1. Vote: A.**
> Reasoning: "May share" still allows `return self;`, so clone stays the cost of one value copy with no allocation. That was all I needed from B. The moderator's probe shows `blink_A*` inside Option carriers, so the compiler already holds values out of line outside `field_layout_of`. A rule written about one boxing site would be wrong on day one. My "does not allocate" line is fine as a non-normative note about cost.
> Concern: if nothing in the text says that sharing is the expected implementation, a later reader may "fix" clone into an allocating copy, and that would be a silent cost regression.
>
> **Q2. Vote: A.**
> Reasoning: plt's wording does two things. It states the invariant (shared storage is never inside a place), and it names the fix (copy before write). That gives codegen a mechanism it can build now: a COW check on the write path only, as Swift does, and it costs nothing on reads or copies. C defers the mechanism. That leaves [the recursion-through-Option ticket] free to pick "reject the write", which may end up as a confusing error with no syntax to point at. B covers only "reachable by a write" and omits the invariant itself.
> Concern: COW needs a uniqueness test or an unconditional copy at the write. Whichever feature first turns this on must price that cost, not just cite the clause.
>
> **Q3. Vote: A.**
> Reasoning: one sentence is the property the backend relies on when it emits a C struct copy for bind and `return self;` for clone. If any non-cell value could alias, both would be unsound. plt's full taxonomy (B) asserts Channel and Handle semantics that no section states (fact 4). That is new spec, not a fix, and it belongs in its own ticket.
> Concern: "at any depth" must be read as "through any field path or payload". If someone reads it as including captured `let mut` cells inside a closure field, it contradicts §3.6 line 2446, so the sentence must defer to the cell list.
>
> **Q4. Vote: A, but the reference must point to a section that really holds the list (see Q4b).**
> Reasoning: Str is immutable, so sharing it cannot be observed, the same as a box. A second list will drift: every Phase A list missed StringBuilder.
> Concern: fact 2 shows that §3.2.2 has no list headed "shared cells", so "(§3.2.2)" points at something that is not there.
>
> **Q4b. Vote: Yes, limited in scope.**
> Reasoning: facts 1–3 show three partial lists today (§3.6 line 2446, §3.2.2, §4/§2.8). A reference with no single target is the same gap as this ticket. Make §3.6 (line 2446, the copy-on-bind paragraph that already names cells) the one list. Fill it only with what the spec already claims: List, Map, Set, StringBuilder, and a closure or handler that captured a `let mut` binding. Point §3.2.2, §3.6.1 and §4 at it. Channel and Handle are not covered by any text (fact 4), so they go to a separate ticket and are not added here.
> Concern: putting StringBuilder in the list is a claim about copy behaviour that no section states outright; the only basis is that its write methods take `mut self`. Someone should check that the runtime really shares it on copy.
>
> **Q5. Vote: C**, with "(§3.2.2)" replaced by the single list from Q4b.
> Reasoning: C removes both phrases that describe storage. "GC pointers" and "allocate a new struct or enum wrapper" are both false for the emitted C. It defines clone by bind, so the two cannot drift apart. A and B fix only the first phrase. D is acceptable but longer, and it repeats the Q3 law.
> Concern: "one level deep" next to "equals a copy on bind" could read as if bind were also shallow in some way that a user can see. The note should say that shallow only matters for cells.

#### Phase D — Round 2 on Q2, Q4b, Q5

New facts: a probe showed a copy of a `StringBuilder` shares its contents (`let mut b = a; b.write("y")` makes `a` read `xy`); §3.3 *Display* relies on `fmt` writing into the caller's `sb`.

- **Q2: A, amended with "or reject the write" and a §2.22 cross-reference** — 6-0 R2 (4-1-1 R1)
- **Q4b: Yes, scoped to what the spec and runtime already state** — 6-0 R2 (4-2 R1). Minimalism and PLT changed from No: without `StringBuilder` on the list, the Q3 law would be false on the day it landed.
- **Q5: C, reference set to §3.6** — 6-0 R2 (3-1-1-1 R1)

**Minimalism:**

> Minimalism Phase D re-vote: Q2 A with "or reject the write"; Q4b Yes; Q5 C with §3.6.
>
> Q2: I re-vote A, on the condition that plt's and devops' amendment goes in: "...must copy that storage before the write, or reject the write." With that change, A says what C said, and it is more specific. My only objection was that the old text chose the mechanism too early. The amendment fixes that. I also support plt's cross-reference from §2.22.
>
> Q4b: I re-vote Yes, and I change my vote because of fact 5. A copy of a StringBuilder shares its contents, but the list in §3.6:2446 does not name StringBuilder. Q3 passed, so the spec will now say "a value of any other type, at any depth, cannot be changed through a second name". Against the current list, that sentence is false for StringBuilder. A law that is wrong when it is written is worse than having no law, so this ticket must fix the list it depends on. Keep it small: make §3.6:2446 the one list, add `StringBuilder` to it, and make §3.2.2's "Collections are shared cells" refer to that list. Channel and Handle stay out of the list until a ticket classifies them (fact 4). The general law must not claim anything about them, so its wording should be "only the shared cells listed in §3.6" and not "only these types".
>
> Q5: I re-vote C, with the reference changed to §3.6 as aiml, web and sys proposed: "clone() on a struct or enum equals a copy on bind; shared cells (§3.6) stay shared, one level deep." It ties Clone to bind, so it uses no new idea. Now that a single list exists to refer to, it costs one sentence more than A. I accept that.

**AI/ML:**

> AI/ML — PHASE D
>
> Q2: re-vote A. I accept the amendment "copy that storage before the write, or reject the write" (plt, devops). Only spec authors face that choice, not users or models writing Blink, so it adds no decision point to the language. Combined with the §2.22 cross-reference plt asked for, it also covers min's wish to leave both paths open (C) and web's copy duty (B).
>
> Q4b: re-vote Yes, scoped (sys/web/devops form). Fact 5 settles sys's concern: a StringBuilder copy shares its contents today, so StringBuilder belongs on the list, and every Phase A list missed it. That is the drift a single list prevents. To plt and min: Q3 and Q4 are already decided, and both refer to "shared cells". Without a single home, this ticket ships a reference that no section answers fully. Make §3.6 line 2446 that home, holding only what the spec or runtime already states (List, Map, Set, StringBuilder, closure/handler that captured `let mut`). Add web's note that Channel and Handle are not yet decided, and file that ticket in the same change.
>
> Q5: re-vote C, with the reference changed to §3.6, and I accept plt's clause: "`clone()` on a struct or enum equals a copy on bind, defined by declared type, not by representation; shared cells (§3.6) stay shared, one level deep." The added clause costs a few tokens and blocks the exact misreading that caused this ticket. It should make C acceptable to plt (D's core) and devops (B's reference). I also back web's half-clause on purpose ("Clone exists for generic `T: Clone` code") if it fits.

**DevOps:**

> DevOps/Tooling Phase D re-vote: Q2 A (amended), Q4b Yes (scoped), Q5 C (I move from B).
>
> Q2: A, but only with plt's amendment: "copy that storage before the write, or reject the write". This answers min's objection (C): it does not settle copy vs reject before any feature exists. It still keeps what C drops, which is the invariant itself and a short closed list of legal fixes that a reviewer can check. sys's worry that a reject would be a confusing error is a question for that future feature's diagnostic, not a reason to forbid the option now. I also back plt's request to cross-reference this rule from §2.22, where places are defined. That is where an author adding payload places will look.
>
> Q4b: Yes, scoped as sys and web wrote it. One list in §3.6: List, Map, Set, StringBuilder, and a closure or handler that captured a `let mut` binding. Fact 5 settles StringBuilder: the runtime shares it on copy today. Fact 6 (Display writes into the caller's `sb`) only works because it is a cell. To plt and min: all of this content is already in the spec. Gathering it is not a new decision, and without a single list Q3, Q4 and Q5 all refer to nothing. Include web's line "not yet complete for Channel and Handle", and file that ticket in the same change.
>
> Q5: C, with the reference changed to the §3.6 list. sys convinced me: C also removes "allocate a new struct or enum wrapper", which B leaves in, and it is false for the emitted C. If plt's clause "not by its representation" fits in the same bullet, add it. It is the sentence a hover or a diagnostic would quote.

**PLT:**

> PLT Phase D re-vote: Q2 A with "or reject the write"; Q4b Yes, scoped (changed from No); Q5 C with the reference set to §3.6 (changed from D).
>
> Q2: A, with "or reject the write" added. min's objection is fair: choosing copy-on-write now picks a mechanism with no feature to judge it against. Adding "or reject the write" answers that and keeps the invariant. Copying and rejecting both keep the equivalence true, so the soundness argument does not care which one a later feature picks. min's C states no duty at all, and web's B leaves out the invariant. Wording: "Storage the compiler shares between values is never inside a place (§2.22). A feature that would put it inside one must copy that storage before the write, or reject the write." Add a cross-reference from §2.22 back to this rule.
>
> Q4b: Yes, scoped. I change from No. My No was about not deciding Channel/Handle here. The scoped Yes from sys, web and devops does not decide them. It only names one list of what the spec already claims: List, Map, Set, StringBuilder, and a closure or handler that captured a `let mut` binding. Fact 5 confirms StringBuilder in the runtime. Fact 6 confirms it in the spec: Display relies on the caller seeing writes made into `sb`. Without one list, the Q3 law ("only shared cells…") points at nothing. Condition: add web's note that the list does not yet cover Channel and Handle, and file their ticket in the same change.
>
> Q5: C, with the reference set to §3.6 (the Q4b list). I change from D. Q1 A and Q3 A already state "storage is not observable", so D's "not by representation" clause is now covered elsewhere. C's equation (clone = copy on bind) is the shorter way to say the same thing. I accept sys's note that shallow copying only matters for cells.

**Web/Scripting:**

> Web/scripting, Phase D.
>
> **Q2: I change my vote to A, with "or reject the write" added and a cross-reference from §2.22.**
> sys and devops are right that B leaves out the invariant itself. min is right that "copy" alone decides a future feature's design too early. plt's amended A answers both: it states the invariant and gives two legal remedies, either of which a future panel can pick and a reviewer can check. A cross-reference from §2.22 puts the rule in front of whoever adds places. That is where it will actually be read.
> Re-vote: **A**, conditional on adding "or reject the write" and the §2.22 cross-reference.
>
> **Q4b: Yes, scoped (no change).**
> Fact 5 settles sys's doubt: the runtime shares a StringBuilder after a copy, so putting it on the list records existing behaviour and adds nothing new. Fact 6 (Display's `fmt` writes into a caller's `sb`) only works because StringBuilder is a cell, so §3.3 already depends on it. plt and min say a list is out of scope. But Q3 (decided) says "only shared cells". Without one list, that sentence points at three lists that disagree, and that ships a new gap. Use the §3.6 list: List, Map, Set, StringBuilder, and closures or handlers that captured a `let mut` binding. Point §3.2.2, §2.8, §3.3 and §4 at it, and file Channel and Handle as a separate ticket in the same change.
> Re-vote: **Yes**.
>
> **Q5: C, with the reference changed to §3.6 and plt's clause folded in.**
> Wording: "`clone()` on a struct or enum equals a copy on bind, whatever its storage. Shared cells (§3.6) stay shared, one level deep." The phrase "whatever its storage" keeps plt's "not by representation" guard in four words. The lead stays short enough for a newcomer.
> Re-vote: **C** (with the amendment). I'd accept C without the amendment as a second choice.

**Systems:**

> SYSTEMS, Phase D.
>
> **Q2: re-vote A, amended to "copy that storage before the write, or reject the write", with a cross-reference from §2.22.** I accept plt's and devops's amendment. From the hardware side, rejecting the write is the cheapest correct answer: a compile error costs nothing at run time. My Phase C worry was a confusing error with no syntax to point at. That is a diagnostic-quality problem for whatever feature arrives, not a reason to forbid the option. The amendment also answers min's objection (A no longer picks the mechanism too early), while keeping what C leaves out: the invariant itself, and a closed set of legal fixes. web, B is now a subset of amended A.
>
> **Q4b: re-vote Yes, limited in scope.** Fact 5 settles my Phase C concern: a StringBuilder copy shares its contents (prints `xy`). Fact 6 shows the spec already relies on that through Display. min and plt want Q4 to point at §3.6:2446 as it stands. That paragraph does not name StringBuilder, so the Q3 law ("only shared cells change through a second name") would be false on the day it lands. The probe proves a counterexample. A law we just voted 5-1 cannot ship with a known counterexample. So the list must include StringBuilder now. Channel and Handle still go to a separate ticket, filed in the same change, and the list carries web's line saying it is not yet complete for those two.
>
> **Q5: re-vote C, reference changed to §3.6, adding plt's clause.** The wording I vote for: "`clone()` on a struct or enum equals a copy on bind, by declared type and not by representation. Shared cells (§3.6) stay shared, one level deep." That keeps the clause plt needs, and devops's "§3.6" target. It also keeps both storage phrases out ("GC pointers", "allocate a wrapper"). C without plt's clause is my second choice; B as revised by devops is my third.

#### Round 3 — Q5 clause (asked for by the user)

Texts: **S** "...equals a copy on bind, by declared type and not by representation"; **W** "...whatever its storage"; **N** no clause. Plus a Yes/No on a clause saying why `Clone` exists.

- **Clause:** N 3 (Minimalism, Web, Systems), S 2 (PLT, DevOps), W 1 (AI/ML). No majority. Every N voter ranked W above S.
- **Purpose clause:** Yes 5-1. **Minimalism (dissent)**: not as normative text; a rationale note is fine.
- **"One level deep":** Systems, PLT, DevOps and Minimalism each proposed moving shallowness onto the cells (for example PLT: "Shared cells (§3.6) stay shared; a clone does not copy their contents"). Web and AI/ML found the old wording fine.
- **Tiebreak:** the user handed the decision to the moderator, who chose **N**, the plurality: Q1's text in the same subsection already says storage is not observable, and a second copy of that rule could drift from the first. The spec takes PLT's form of the cell sentence and the purpose clause.

**AI/ML:**

> AI/ML — Q5 CLAUSE ROUND
>
> Vote: W.
>
> Reasoning: The lead sentence is the line a model is most likely to read and quote, so the guard against a storage-based reading belongs there, even if Q1 says it again further down. N drops that guard. Between S and W, W says the same thing in plainer words: "whatever its storage" uses everyday words, while "representation" is jargon, and "by declared type" repeats what the Clone bullets already say field by field. W is also a few tokens shorter. I drop my own S wording in favor of W.
>
> On sys's point: I agree that "one level deep" next to "copy on bind" can read as a visible shallowness. W keeps "one level deep" attached to "shared cells", which limits it to cells. That is enough.
>
> T: Clone purpose clause: Yes, kept short, for example: "Clone exists so generic code with a `T: Clone` bound can copy a value." My domain reason: an LLM that reads "clone equals bind" will ask why Clone exists. Without an answer it either sprinkles needless `.clone()` calls on structs (wasted tokens, noise in training data) or drops `T: Clone` bounds that generic code needs. One clause stops both mistakes.

**DevOps:**

> DevOps/Tooling Q5 clause vote: S, sys's wording. T: Clone purpose clause: Yes.
>
> S: The lead sentence is the line that hover text, `blink llms` output and diagnostic explanations will quote on its own, cut off from the Q1 text below it. "By declared type" gives a reader a rule they can apply from their own source. W's "whatever its storage" brings storage back into the one sentence this ticket set out to clean. N is correct, but it leans on Q1 sitting nearby, and a quoted line does not carry its neighbours. I prefer sys's wording to aiml's: two short sentences, no semicolon, and "by declared type" rather than "defined by declared type".
>
> On sys's Phase C worry: "Shared cells (§3.6) stay shared, one level deep" already puts "one level deep" on the cells, not on bind. If the panel wants it tighter, "Shared cells (§3.6) stay shared; clone does not copy their contents" removes the doubt without adding a word about storage.
>
> T: Yes, as one short clause, for example "Clone exists so generic code with a `T: Clone` bound can copy a value." Once clone equals bind, "why does Clone exist?" is the first question a user asks, and the docs page should answer it in one line, not leave it to a forum thread.

**Minimalism:**

> Minimalism Q5 clause vote: N. Purpose clause: No.
>
> Vote: N.
> Reasoning: Q1 A already puts "the storage cannot be observed, and the compiler may share it" into the same subsection, §3.6.1. S's "not by representation" and W's "whatever its storage" repeat that a few lines later. Saying a rule twice in one section creates two texts that can drift apart, which is how this ticket started. plt makes the same point. If the user wants the clause anyway, I prefer W to S. "Whatever its storage" is plain words, and "by declared type and not by representation" is jargon.
>
> On sys's point: "one level deep" is a real risk next to "copy on bind". The fix is to put it on the cells, not to add a clause about storage: "...shared cells (§3.6) stay shared; Clone does not clone them." That has the same length and drops "one level deep" from this sentence. The DeepClone note already says the rest.
>
> T: Clone purpose clause: No, as normative text. It changes no rule. Put it in a rationale note if the user wants it.

**Web/Scripting:**

> Web/scripting, extra round on the Q5 clause.
>
> plt is right. Q1 A sits in the same section (§3.6.1) and already says the storage can't be observed. Any clause here would repeat it. My own W ("whatever its storage") only made sense while that guard had no other home. Now it has one. S is the worst of the three for a newcomer: "by declared type and not by representation" is type-theory wording a JS or Python dev has to look up. The lead sentence should give the user the rule ("clone = copy on bind"), and the guard belongs in the sentence beside it.
>
> On sys's concern: "one level deep" placed next to "copy on bind" is fine. It already sits next to "shared cells", which tells the reader where shallowness can be seen.
>
> **Vote: N.** Second choice W, then S. Between the S wordings I prefer sys's (two sentences beat a semicolon).
>
> **T (purpose clause): Yes**, if kept to one short sentence, e.g. "Clone exists so that generic code with a `T: Clone` bound can copy any value." Without it, "clone equals a copy on bind" sends every new user to ask "then why call clone()?". That is the Stack Overflow question this ticket should answer up front.

**Systems:**

> SYSTEMS, Q5 clause round. I vote N, and Yes to the T: Clone clause.
>
> **Vote: N.** plt is right. The Q1 A text sits in the same §3.6.1, and it already says the storage cannot be observed and the compiler may share it. Q3 A states the law in §3.6. The lead sentence would repeat both. A repeated clause is a second place that can drift from the first, and that is how this ticket began. If the panel wants a clause anyway, I prefer W over S, because "whatever its storage" names the thing actually in doubt in fewer words. Between the two S wordings I prefer mine; aiml's semicolon run-on reads worse.
>
> **Optional wording fix, not a condition of my vote:** "one level deep" next to "copy on bind" still hints that bind is shallow in a way a user can see. Better: "a shared cell (§3.6) is not cloned; the copy refers to the same cell."
>
> **T: Clone purpose clause: Yes, one short clause.** Example: "Clone exists so generic code can copy a `T: Clone` value." If clone equals bind, a reader will ask why the trait exists, and generic code is the answer. It costs nothing at run time.
>
> **A fact the moderator should check, outside this round:** sections/03_types.md:4237 has a row "`Clone` | Element-wise clone | All elements: `Clone`". That looks like it contradicts "collections share backing storage on clone" in §3.6.1. If it applies to List, Map or Set, it needs its own ticket.

**PLT:**

> PLT Q5 clause vote: S, in sys's wording, plus Yes to the purpose clause.
>
> Why S over W and N: In Phase D I said Q1 and Q3 cover "not by representation", and they do. But the lead sentence is the one readers quote, and this ticket started because the lead sentence described storage. "By declared type" is a positive rule: it says what decides each field's copy. "Whatever its storage" (W) only rules one thing out. N leaves the reader to put the rule together from two other paragraphs. The clause costs four words.
>
> Wording: sys's, because its full sentences read better than aiml's semicolon form.
>
> Fix for sys's own concern: "one level deep" next to "copy on bind" can read as if bind were shallow. I would drop "one level deep" here, or change it to "Shared cells (§3.6) stay shared; a clone does not copy their contents." That says the same thing and puts it on the cells, not on bind.
>
> T: Clone purpose clause: Yes, one clause, for example: "Clone exists so that generic code can copy a value of a type bound by `T: Clone`." Without it, "clone equals bind" makes readers ask why Clone exists at all.

### Final Spec

```blink
@derive(Clone)
type Tree {
    Leaf
    Node(value: Int, next: Tree)
}

let a = Tree.Node(value: 1, next: Tree.Leaf)
let b = a.clone()          // same value as `let b = a`
```

- `clone()` on a struct or enum equals a copy on bind. Shared cells stay shared; a clone does not copy their contents. `Clone` exists so generic code with a `T: Clone` bound can copy a value (§3.6.1 *Clone Semantics*).
- A field the compiler stores out of line is a value. No program can see whether copies share it, and the compiler may share it.
- Storage the compiler shares between values is never inside a place (§2.22). A feature that would put it inside one must copy that storage before the write, or reject the write.
- §3.6 *Shared cells* is the one list: `List`, `Map`, `Set`, `StringBuilder`, and a closure or handler that captured a `let mut` binding. `Channel` and effect handles are not yet classified.
- Only a shared cell can change through a second name. A value of any other type, at any depth, cannot.
- `Str` is a value: it cannot change, so sharing its bytes is not observable.
- "GC pointers are copied" and "allocate a new struct or enum wrapper" are removed.
