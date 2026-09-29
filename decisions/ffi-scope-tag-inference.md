[< All Decisions](../DECISIONS.md)

# FFI Scope Tags: Inference, Not Syntax — Design Rationale

**Gap:** the spec reserved an `E0601 (tag-mismatch)` sub-kind ([`ffi-struct-construction`](ffi-struct-construction.md)) and wrote pointers as `Ptr[T]^σ` / `Buf[T]^σ`, but gave no surface syntax for σ on a function parameter and no typing rule for it. The motivating case was `writev`, whose `iovec` entries must not outlive the memory they point at.

**Result:** no syntax. The compiler infers a scope tag for each pointer-bearing value, and `tag-mismatch` is an *outlives* check on four closed store forms. All ten questions passed 6-0. Phase D did not run.

**Amends:** [`ffi-struct-construction`](ffi-struct-construction.md) (`@ffi.struct` gains `Ptr[T]` fields; the `tag-mismatch` sub-kind gets its definition) and [`buf-u8-runtime-representation`](buf-u8-runtime-representation.md) (`Buf` is no longer a legal `@ffi.struct` field type; `scope.alloc_n[T]` returns `Ptr[T]`, so `libc.copy_to_buf` is the only source of a `Buf`).

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds. The DevOps seat was re-spawned before Phase C after a tooling failure; the replacement started from the DevOps Phase A text and cast the DevOps round-1 text and ballot quoted below.

#### Phase A — Independent proposals

Every panelist independently proposed inference with no surface syntax. Attribute forms (`@same_scope(a, b)`, bare `@same_scope`, `@ffi.scope_linked`), explicit region parameters, and "defer" were also proposed. Full texts, verbatim, except that local tracker IDs read "the spec ticket" and "the implementation ticket":

<details><summary><b>Systems</b></summary>

> SYS PANELIST — Phase A proposal (σ-tagged parameters)
>
> **Premise check first.** The ticket describes the wrong problem, for two reasons.
>
> 1. **The motivating case cannot be declared at all.** The field list for `@ffi.struct` (§9.1.3, E0812 explain text in src/diagnostics.bl) allows sized scalars, `Bool` and other `@ffi.struct` types. `Ptr` is not on it, so `iovec.iov_base` has no legal field type today. `Buf` is legal in `@ffi.struct` fields (§9.1.3.2), but a `Buf[T]` is a `blink_buf_t*`: a pointer to `{data, len, cap}`. C's `iovec` holds `void*` plus `size_t`. A `Buf` field in an `@ffi.struct` therefore breaks the C ABI. The `_Static_assert` on size would catch it at build time, if it ever got emitted. The gap to fix is "how does a pointer get into a C struct field", not "how do users spell σ".
> 2. **Equality is the wrong typing rule.** "Same σ across params" rejects safe code and still needs the dangerous case to be defined. Storing an outer-scope pointer into an inner-scope iovec array is safe. Storing an inner-scope pointer into an outer-scope array is not, if that array is used after the inner scope frees. The sound relation is *outlives* (σ_value ⊒ σ_container), not `σ_a = σ_b`. `ffi.scope` is purely lexical, so outlives is just "is this scope an enclosing scope of that one". Any compiler can decide that from the AST with no annotations. Unification-by-equality is the Rust-lifetime shape that DECISIONS.md rejects, and it is also less precise.
>
> ---
>
> **SYS-1 (FAVORED): no σ syntax. Add an intra-procedural outlives check on stores, plus a conservative rule at call sites.**
>
> (a) Allow `Ptr[T]` as an `@ffi.struct` field type. It lowers to a raw `T*`, so the ABI is exact and it costs nothing. Keep `Buf` out of `@ffi.struct` fields; change the V3 table to say so.
>
> (b) **E0601 tag-mismatch** fires on `dst.write(v)`, `dst.field.write(v)` and `dst.offset(i).field.write(v)` when `v` has a scope tag σv, `dst` has tag σd, and σv does not enclose σd (and is not equal to it). Tags are the scope-binder origins that src/escape.bl already tracks. The work is to extend its origin tracking to stores and cell writes, which it skips today.
>
> (c) **Call rule.** A call that takes Ptr arguments and returns a Ptr gets a result tag equal to the innermost argument tag: the shortest-lived argument wins. This is Rust's elision rule with a min. It closes the "any call result is unscoped" hole in escape.bl. A call does not merge its arguments' tags into each other.
>
> (d) Inside `@ffi`/`@trusted` bodies, each parameter gets one fresh tag, "caller". The same tag for all parameters is sound because every argument is live for the whole call. A store of one parameter into another is accepted there and reported by `blink audit` as `ptr-store-param`. `@trusted` is already the audited trust boundary.
>
> ```blink
> @ffi.struct(header = "sys/uio.h", name = "iovec")
> pub type IoVec {
>     iov_base: Ptr[U8],
>     iov_len: Int,
> }
>
> @ffi("c", "writev")
> fn c_writev(fd: I32, iov: Ptr[IoVec], n: I32) -> Int
>
> fn send_two(fd: I32, a: Bytes, b: Bytes) -> Int ! IO {
>     with ffi.scope() as outer {
>         let iov = outer.alloc_n[IoVec](2)
>         let pa = outer.cstr(a)
>         iov.offset(0).iov_base.write(pa)          // OK: same scope
>         with ffi.scope() as inner {
>             let pb = inner.cstr(b)
>             iov.offset(1).iov_base.write(pb)      // E0601 (tag-mismatch): inner stored into outer
>         }
>         c_writev(fd, iov, 2)                      // would read freed memory
>     }
> }
> ```
>
> - **Cost:** zero at run time. σ is erased and codegen does not change. The analysis is one pass over each fn body, O(stores × scope depth).
> - **Risk:** stores inside a `@trusted` helper are not checked in the caller. I accept this: `@trusted` already means "the author vouches for this", and audit shows every such store.
> - **Cross-language:** Zig has no lifetimes and relies on reviewer discipline. This gives Zig's surface with a real check. Cyclone's regions had annotations and failed in the market. Rust's elision rules cover about 90% of signatures with no annotation; our lexical-only scopes let us reach 100%.
>
> ---
>
> **SYS-2 (fallback if the panel wants a signature-level contract): one anonymous marker, no σ variables.**
>
> ```blink
> @trusted(audit: "IOV-1")
> @ffi.scope_linked
> fn set_iov(iov: Ptr[IoVec], i: Int, base: Ptr[U8], len: Int) {
>     iov.offset(i).iov_base.write(base)
>     iov.offset(i).iov_len.write(len)
> }
> ```
>
> `@ffi.scope_linked` means "this fn may store any Ptr parameter into any other one". At the call site the compiler applies the outlives check from SYS-1(b) to every pair of Ptr arguments: every Ptr argument must enclose the tag of every container argument. That is a simple conservative approximation: all arguments must share the innermost tag, or be nested so that the value arguments are outer. Without the marker, (d) applies.
>
> - **Cost:** zero at run time. It is one attribute, not a type-grammar change. `^` stays XOR in the lexer, and `parse_bit_xor` needs no type-position fork.
> - **Tradeoff:** it is a boolean, so users cannot say which parameter flows into which. It over-rejects in rare patterns. I would take that over σ variables.
>
> ---
>
> **SYS-3 (explicitly opposed, listed so it gets a vote): surface `Ptr[T]^σ` with named σ variables.**
>
> ```blink
> @trusted(audit: "IOV-2")
> fn set_iov[σ](iov: Ptr[IoVec]^σ, base: Ptr[U8]^σ) { ... }
> ```
>
> This is region polymorphism, i.e. lifetime annotations. It contradicts §5:7 and §5:113 ("No region-variable annotations are required or accepted") and the DECISIONS.md rejection. It adds a lexer/parser fork on `^`, a new kind in the generics system, and mono keys that must ignore σ. Equality unification also rejects the safe outer-into-inner store. AI failure rates on annotated lifetimes are the documented reason this was rejected. It buys nothing that SYS-1 cannot see from lexical nesting.
>
> ---
>
> **Spec edits that go with SYS-1**
> - In §9.1.3, E0601 (tag-mismatch) becomes: "a scope-tagged `Ptr`/`Buf` stored into a cell whose scope tag it does not enclose".
> - Add the call-result rule (innermost argument tag) to §9.1.1's escape analysis.
> - Add `Ptr[T]` to the list of legal `@ffi.struct` field types. Remove `Buf` from the list of legal `@ffi.struct` field types, to fix the ABI mismatch. Either change needs a note that it touches ffi-struct-construction and buf-u8-runtime-representation.
> - Remove every `^σ` from spec prose, or mark it as meta-notation only and never source syntax.
> - The implementation ticket is then unblocked without a parser change.
>
> **Vote: SYS-1.** SYS-2 is an acceptable fallback. SYS-3 gets a no.

</details>

<details><summary><b>Web/Scripting</b></summary>

> **WEB panelist, Phase A: σ-tagged parameters**
>
> **The premise is shaky.** The ticket asks for syntax so that user code can write `Ptr[T]^σ` in a fn signature. The canonical case is `writev` with `Ptr[IoVec[T]^σ]`, but §9.1.3.3 already defers vectored I/O to "its own deliberated API". §5 says "no region-variable annotations are required or accepted", and DECISIONS.md rejects lifetimes. A JS or Python developer who opens a signature and sees `^σ` has met Rust's `'a` under a new name. Many Stack Overflow questions would follow: "what is σ", "why does my helper not compile", "how do I name the scope". The tag-mismatch check is what we need. Surface syntax is not.
>
> ---
>
> ### WEB-1 (FAVORED): Infer the tag and never write it. Callers get a conservative elision rule.
>
> σ stays a checker-internal fact, as it is today (escape.bl keys the tag on the scope binder name). E0601 `tag-mismatch` fires from three inferred rules. None of them needs a new token.
>
> 1. **Store rule.** A Ptr/Buf with tag A may be written through a Ptr with tag B (`.write(v)`, `.field.write(v)`, `.offset(i).write(v)`) only if scope A lives at least as long as scope B. An inner-scope pointer stored into outer-scope memory is `tag-mismatch`. This rule by itself catches the dangling `iov_base` bug.
> 2. **Call rule (elision).** An `@ffi`/`@trusted` fn that takes one or more Ptr/Buf params and returns a Ptr/Buf gives its result the tag of the shortest-lived Ptr/Buf argument at the call site. Callers need no annotation. This is the "most conservative guess" that Rust's elision rules make, but it is always on and has no opt-out.
> 3. **Unscoped rule.** A result from a call with no Ptr/Buf argument keeps today's behavior: unscoped (GC `alloc_ptr` or `take()`).
>
> ```blink
> @trusted(audit: "NET-7")
> fn pick(p: Ptr[U8], q: Ptr[U8]) -> Ptr[U8] {
>     p
> }
>
> fn demo() ! FFI {
>     with ffi.scope() as outer {
>         let slots = outer.alloc_n[Ptr[U8]](2)
>         with ffi.scope() as inner {
>             let tmp = inner.alloc_n[U8](64)
>             slots.offset(0).write(tmp)
>             // E0601 tag-mismatch: `tmp` is tied to scope `inner`, but it is
>             //   stored into memory owned by `outer`, which outlives it.
>             //   help: allocate `tmp` from `outer`, or copy the bytes.
>             let r = pick(slots.offset(1).read(), tmp)
>             // r takes the tag `inner` (shortest-lived argument)
>         }
>     }
> }
> ```
>
> The `writev` case then goes into curated stdlib, so users never touch an iovec:
>
> ```blink
> fn writev_bytes(fd: Int, chunks: List[Bytes]) -> Result[Int, Errno] ! IO
> ```
>
> This is a `std.libc` function that builds the iovec array inside one `ffi.scope`. Every `iov_base` comes from that one scope, and the store rule proves it. It departs from the naming law's `(buf, len)` → `data: Bytes` shape, so the "own deliberated API" that §9.1.3.3 promises still has to approve it. WEB-1 just makes that API possible without σ syntax.
>
> **Tradeoffs (DX):**
> - There is nothing to learn. Error text names the scopes the user wrote (`inner`, `outer`) and does not mention a Greek letter.
> - The elision rule is conservative. In the rare case where a helper's result depends only on its longer-lived argument, the helper gets a false positive. The fix a user already knows is to allocate from the outer scope or call `.take()`.
> - It keeps faith with §5 and the rejected-lifetimes row, so no prior decision is reopened.
> - Implementation cost is in escape.bl: tie call arguments to results, and check stores and cell writes. Those checks are missing today anyway, and the value-escape gaps (stores, closure captures) need the same work.
>
> **Cross-language:** Go escape analysis and Kotlin's `use {}` blocks both infer and never ask. TypeScript users accept inference that is sound but sometimes too conservative. They do not accept annotation tax.
>
> ---
>
> ### WEB-2 (fallback if the panel says a signature must state the tie): an attribute, not type syntax
>
> Allow this only on `@ffi`/`@trusted` fns:
>
> ```blink
> @trusted(audit: "NET-9")
> @same_scope(iov, base)
> fn set_iov(iov: Ptr[IoVec], base: Ptr[U8], len: Int) {
>     iov.iov_base.write(base)
>     iov.iov_len.write(len)
> }
> ```
>
> The rule: the arguments named in `@same_scope` must carry the same inferred tag at every call site, or E0601 `tag-mismatch` fires. A result can join the group with `@same_scope(return, base)`.
>
> **Tradeoffs:**
> - It reads as plain English and can be found with grep. It shows up in `blink audit`.
> - It needs no change to the lexer or parser, and it avoids `^` colliding with XOR in type position.
> - It is legal only where Ptr is already legal (the E0811 regions), so ordinary users never meet it.
> - Cost: one more attribute to document. The attribute is also a restricted form of region annotation, so the panel must say so openly against §5 ("not accepted").
>
> **Cross-language:** It is close to Python decorators and Kotlin annotations, which people read in seconds. Compare Rust's `fn f<'a>(x: &'a T, y: &'a U)`, which is a steady source of Stack Overflow questions.
>
> ---
>
> ### WEB-3 (REJECT): Literal `Ptr[T]^s` / `Buf[T]^s` in fn signatures with scope variables
>
> ```blink
> @trusted(audit: "X")
> fn join[s](a: Ptr[U8]^s, b: Ptr[U8]^s) -> Ptr[U8]^s { a }
> ```
>
> I oppose this.
> - It is lifetime parameters in all but name, and it reopens a rejected decision.
> - `^` already means XOR, so a type-position `^` is a parser hazard and confuses readers.
> - `FfiScope` cannot be passed as an argument, so `s` names a thing the user can never hold. That will generate "how do I get an `s`" questions.
> - The DECISIONS row cites a 30-40% AI failure rate on borrow-checker-style annotations. The same risk applies here.
>
> ---
>
> **Also flagged:** §9.1.3 :653 says `alloc_n` returns `Ptr[T]`, but §9.1.3.2 :741 says it returns `Buf[T]^σ`. The compiler returns `Ptr[T]`. Whatever the panel decides, the tag-mismatch implementation needs one answer to this. I favor keeping `Ptr[T]` as the type the user sees, with σ inferred, which is consistent with WEB-1.
>
> **Vote intent:** WEB-1, with WEB-2 as fallback. My answer to the spec ticket is to reject the syntax premise but ship the tag-mismatch check as inference.

</details>

<details><summary><b>PLT</b></summary>

> **PLT panel, Phase A: σ-tagged parameters**
>
> **The premise is wrong.** The ticket asks for surface syntax for `^σ`. That syntax would be region polymorphism with explicit region variables, which §5:113 and the "Ownership/lifetimes" row in DECISIONS.md reject: "No region-variable annotations are required or accepted". We do not need the syntax, because Blink's regions have a property that Cyclone and Tofte-Talpin regions lack.
>
> **The chain lemma.** An `ffi.scope` exists only as a `with ... as` resource. It cannot be let-bound, passed, returned or stored. `Ptr` and `Buf` exist only in syntactic FFI regions (E0811). So at any program point, the live scopes are exactly the lexically enclosing `with` binders, and they form a total order by nesting. A multi-resource `with a, b` unwinds LIFO, so `b ⊑ a`. Any two tags at a point are comparable, and the meet (the innermost of them) always exists. This is what makes inference complete without annotations. It is the same reason the arena rule in §5 needs no region variables.
>
> ---
>
> ### PLT-1 (favored): inferred tags, meet at calls, outlives-check at stores
>
> The judgement is `Γ ⊢ e : τ @ ρ`, where ρ is a scope binder or `⊤` (unscoped: the GC `alloc_ptr` fallback, or a `take()`n value). Order: `ρ₁ ⊑ ρ₂` means ρ₁ is nested in (dies no later than) ρ₂, and `⊤` is the top.
>
> 1. **Origin.** `s.alloc*`, `s.cstr` and `copy_to_buf` inside `with ffi.scope() as s` give tag `s`. `s.take(p)` gives `⊤`.
> 2. **Projection.** `p.offset(i)`, `p.field` and `p.read()` of a `Ptr[Ptr[T]]` inherit p's tag. Reading a pointer out of a scoped cell is conservative, because the stored value was checked against that cell's tag when it was written (rule 4).
> 3. **Call (the arg-to-result tie).** For `f(e₁..eₙ)` with a Ptr- or Buf-typed result, `tag(result) = ⊓ { tag(eᵢ) | eᵢ is Ptr/Buf-typed }`, or `⊤` when no such argument exists. This is the principal instance of the implicit signature `∀ρ. Ptr[A]@ρ × … → Ptr[C]@ρ`, with subsumption applied at each argument. It is sound for opaque `@trusted` bodies: the callee can only return a scoped pointer it received (its own scopes are E0601-checked in its body), and whatever it received lives at least as long as the meet.
> 4. **Store (this is `tag-mismatch`).** For `c.write(v)`, `c.field.write(v)` or a Buf field init, where `c @ σ` and `v @ τ`, require `σ ⊑ τ`: the stored value must outlive the cell. If not, report **E0601 tag-mismatch**, naming both binders.
> 5. **Escape (the existing `value-escape`).** Unchanged, except that it now uses rule 3, so `return helper(p)` is caught.
>
> ```blink
> @ffi("c", "writev")
> fn writev(fd: I32, iov: Ptr[IoVec], n: I32) -> Int
>
> @ffi.struct(header = "sys/uio.h", name = "iovec")
> pub type IoVec {
>     iov_base: Buf[U8],
>     iov_len: U64,
> }
>
> fn send_two(fd: I32, a: Bytes, b: Bytes) ! FFI {
>     with ffi.scope() as outer {
>         let iov = outer.alloc_n[IoVec](2)
>         iov.offset(0).iov_base.write(libc.copy_to_buf(a))   // @outer into @outer: ok
>         with ffi.scope() as inner {
>             let tmp = libc.copy_to_buf(b)                   // @inner
>             iov.offset(1).iov_base.write(tmp)               // E0601 tag-mismatch:
>             // cell @outer, value @inner; inner is not an outer scope of outer
>         }
>         writev(fd, iov, 2)                                  // would read a freed buffer
>     }
> }
> ```
>
> The canonical writev case is therefore expressed as a check on the store. It needs no annotation on the parameter.
>
> **Tradeoffs**
>
> - No new syntax, no region variables, and nothing for an AI to get wrong. It stays consistent with §5 and with the ownership/lifetimes rejection.
> - It is inference over a finite chain, with no unification variables, so it is decidable and linear.
> - The cost is precision. The meet rule sometimes gives a result a shorter tag than it could have. For example, `pick(outer_p, inner_q)` always gets `@inner`, even when the callee returns `outer_p`. That is conservative (sound) and does not produce false errors inside the inner scope. It only rejects code that returns the result after the inner scope has closed. I claim that code is rare in FFI. If a panelist can show a real counterexample, that is the trigger for PLT-2.
>
> **Required fix alongside this.** Today a tag is the binder *name* (src/escape.bl). Two nested scopes both written `as s` alias each other, and the check becomes unsound under shadowing. Tags must be binder identities (node ids). The name is used only in diagnostics.
>
> **Effects.** A tagged value passed as an effect-operation argument, or captured by a closure that escapes, counts as a store into the handler's or closure's scope. Under rule 4 that is illegal unless the handler or closure is installed within ρ. Without this rule a handler can keep the pointer past unwind, which is the same hole Koka closes for its local state (`st<h>`).
>
> **Cross-language.** Tofte-Talpin region inference (ML Kit) without region polymorphism; Cyclone's outlives relation `'r ⊑ 's` checked only at assignment; Haskell `runST` gets the same guarantee through a rank-2 type, which here the lexical `with` gives for free.
>
> ---
>
> ### PLT-2 (fallback only): explicit region parameters
>
> ```blink
> @trusted(audit: "IO-7")
> fn pick[σ](a: Ptr[U8]^σ, b: Ptr[U8]^σ) -> Ptr[U8]^σ { a }
> ```
>
> This is sound and more precise. The typing rule is ordinary prenex quantification over regions, instantiated at the call with the meet. It **reverses §5:113 and the lifetimes rejection**, so the panel should consider it only if it agrees PLT-1 is not enough, and must say so as an explicit reversal. It also adds a new lexical form for `^` in type position, which conflicts with XOR in the parser. I vote against it for v1.
>
> ### PLT-3 (rejected): `@same_scope(a, b)` attribute
>
> This is a relation encoded as an ad-hoc annotation. It has no typing rule that composes, it cannot express "result tied to argument", and it creates a second mechanism beside inference. No.
>
> ---
>
> ### Spec edits PLT-1 needs
>
> - Re-title the spec ticket to "E0601 tag inference: call meet and store outlives-check".
> - In §9.1.3, rewrite `^σ` as notation for a meta-level tag (it is not source syntax). Fix the `alloc_n` return-type conflict: :653 says `Ptr[T]`, :741 says `Buf[T]^σ`. Both can be right only if `alloc_n` has two overloads, and the panel must choose.
> - The implementation ticket is then unblocked, and its scope is rule 4 plus the rule 3 tie.
>
> **PLT vote: PLT-1.**

</details>

<details><summary><b>DevOps</b></summary>

> **DEVOPS panelist — Phase A proposals (σ-tagged parameters)**
>
> My test for each design: what does the error say, can the LSP show it, and what does `blink fmt` do with it. A type-level `^σ` does badly on all three.
>
> ---
>
> ### DEVOPS-1 (favored): no σ syntax; tag-mismatch becomes a store-site "outlives" check that names scopes by their binders
>
> **Challenge to the premise.** The ticket asks for syntax so that user code can *write* `Ptr[T]^σ`. But §5 says "No region-variable annotations are required or accepted", and DECISIONS.md rejects lifetimes. A named σ on a parameter is a region variable. The real hazard behind the writev case is one thing: **a pointer from a shorter-lived scope is stored into memory that a longer-lived scope owns.** The compiler can find that store without any annotation, because stores can only happen inside an E0811 region.
>
> **Rules:**
> 1. The tag of a scope-minted Ptr/Buf is the name of its `with ... as` binder. escape.bl already uses this as its tag.
> 2. `tag-mismatch` fires when a value tagged with an inner scope is written into a cell whose tag is an outer scope. This covers `.write(v)`, `.field.write(v)` and stores into `Ptr[Ptr[T]]`. These are the unchecked stores that the brief lists as gaps today.
> 3. A call result that is a Ptr/Buf gets the **innermost** tag among its Ptr/Buf arguments. This is conservative, and it closes the current "call result is unscoped" hole.
>
> ```blink
> with ffi.scope() as outer {
>     let iov = outer.alloc_n[IoVec](2)
>     with ffi.scope() as inner {
>         let buf = inner.alloc_n[U8](64)
>         iov.iov_base.write(buf)
>     }
>     c_writev(fd, iov, 2)
> }
> ```
>
> ```
> error[E0601]: pointer stored into a longer-lived scope (tag-mismatch)
>   --> src/net.bl:5:9
>    |
>  2 |     let iov = outer.alloc_n[IoVec](2)
>    |               ----------------------- `iov` belongs to scope `outer`
>  4 |         let buf = inner.alloc_n[U8](64)
>    |                   --------------------- `buf` belongs to scope `inner`
>  5 |         iov.iov_base.write(buf)
>    |         ^^^^^^^^^^^^^^^^^^^^^^^ stores an `inner` pointer into `outer` memory
>    = note: `inner` is freed at line 6; `iov` is used until line 7
>    = help: allocate from the outer scope: `outer.alloc_n[U8](64)`
> ```
>
> **Tooling:**
> - The diagnostic uses the user's own names (`outer`, `inner`) and needs no Greek letter.
> - LSP hover shows `buf: Ptr[U8]  (scope: inner)` as an inferred hint, the way rust-analyzer shows inlay hints. It is displayed only and never written.
> - `blink fmt` has nothing to handle.
> - No lexer change. Today `^` is XOR only, and `Ptr[U8]^s` in a type position that is next to expressions (default args, let annotations) would be an ambiguity the parser has to resolve.
>
> **Tradeoff:** a `@trusted` helper body that stores one parameter into another is not checked at the call site. That is DEVOPS-2's job.
>
> *Cross-language:* Go escape analysis and Swift non-escaping closures are both inferred and never spelled. Users read the results in diagnostics and tooling, not in signatures.
>
> ---
>
> ### DEVOPS-2 (additive, only for helpers): `@same_scope(a, b)` attribute on `@ffi` / `@trusted` fns
>
> For a helper that combines pointers from its parameters (the writev bridge), use a declaration attribute that names parameters, not a type modifier:
>
> ```blink
> @trusted(audit: "LIBC-7")
> @same_scope(iov, base)
> fn set_iov(iov: Ptr[IoVec], base: Ptr[U8], len: Int) {
>     iov.iov_base.write(base)
>     iov.iov_len.write(len)
> }
> ```
>
> - **Body check:** storing parameter `p` into memory reachable from parameter `q` is tag-mismatch unless `@same_scope` lists both. This is the same check as DEVOPS-1, with parameters treated as distinct, unknown scopes.
> - **Call-site check:** the arguments in listed positions must carry the same binder tag.
>
> ```
> error[E0601]: arguments must come from the same ffi.scope (tag-mismatch)
>   --> src/net.bl:12:21
>    |
> 12 |     set_iov(iov, buf, 64)
>    |             ---  ^^^ `buf` belongs to scope `inner`
>    |             |
>    |             `iov` belongs to scope `outer`
>    = note: `set_iov` declares @same_scope(iov, base) at src/libc_iov.bl:2
> ```
>
> **Tooling:**
> - The LSP completes parameter names inside the attribute (same machinery as named args).
> - A misspelled name is an ordinary "unknown parameter" error.
> - `blink query --fn set_iov` prints the attribute verbatim, so the contract lives in the signature and does not depend on the body.
> - `blink audit` can list `@same_scope` sites under the FFI category.
>
> **Tradeoff:** it can express only "these are equal". It cannot express "the result lives as long as argument 1". Rule 3 of DEVOPS-1 covers result ties conservatively. I think equality is enough, because every motivating case (iovec, msghdr) is "all of these pointers from one scope".
>
> **Rejected alternative:** inferring the equality constraint from the helper body. It needs no syntax, but a change to the body would silently change errors at the callers, which is bad for API stability and gives confusing "why does this call fail now" reports.
>
> ---
>
> ### DEVOPS-3 (reject; listed so the panel records why): literal `Ptr[T]^σ` / `Buf[T]^σ` in signatures
>
> ```blink
> @trusted(audit: "LIBC-7")
> fn set_iov[s](iov: Ptr[IoVec]^s, base: Ptr[U8]^s) { ... }
> ```
>
> - It reintroduces region variables, against the §5 and DECISIONS.md rejections. The measured 30–40% AI failure rate on lifetime syntax applies directly.
> - **Lexer and parser:** `^` becomes context-sensitive (XOR or tag). Error recovery on `Ptr[U8]^` then gives two-way "expected expression / expected scope name" noise.
> - **Diagnostics:** the message has to explain "scope variable `s` bound at the call to…". That is rustc's lifetime-error UX, which is the worst-rated part of that toolchain.
> - **fmt:** needs spacing rules for `]^s`.
> - **LSP:** must invent a way to show a variable that no binder in the file declares.
> - **Spec conflict:** `Buf` nameability (E0822) and `FfiScope` non-passability already mean a scope never appears as a value in user code. A σ binder in a signature would be the first place it does.
>
> *Cross-language:* Rust's lifetime elision exists because explicit lifetimes hurt ergonomics. Blink should choose the full-elision version of that and not ship the explicit version first.
>
> ---
>
> ### Premise note for the moderator
>
> The canonical writev case is already deferred to "its own deliberated API" (§9.1.3.3). The most likely user surface is a curated `libc.writev_bytes(fd, List[Bytes])` whose `@trusted` body pins each element. Only stdlib would then write DEVOPS-2's attribute. The tag-mismatch implementation ticket can therefore ship DEVOPS-1 alone, and that already catches the unchecked stores the brief lists.
>
> **Favored:** DEVOPS-1 now, with DEVOPS-2 as its helper surface. Reject DEVOPS-3.

</details>

<details><summary><b>AI/ML</b></summary>

> **AIML panel: Phase A proposals on σ-tagged fn parameters**
>
> **Premise check.** The ticket assumes the fix is surface syntax for σ. But §5 says region variables are "not required *or accepted*". DECISIONS.md rejects lifetimes because AI fails the borrow checker 30-40% of the time. `Ptr[T]^s` on a parameter is a lifetime annotation with a new sigil. The actual need is to *reject* mismatched scopes, and inference can do that. Blink scopes are lexical and strictly nested (multi-resource `with a, b` unwinds LIFO), so the compiler always knows which of two live scopes is younger. It needs no user-written names.
>
> ---
>
> **AIML-1 (FAVORED): σ is inferred and never written. Tag-mismatch means "stored into older memory".**
>
> Three rules, and no new syntax.
>
> 1. **Origin tag.** A `Ptr`/`Buf` gets the tag of the scope that produced it: `s.alloc`, `s.alloc_n`, `s.cstr`, `.offset`, and `.field.read()` on a pointer from `s`. `.take()`, `alloc_ptr`, and pointers that C returns are *unscoped*, which counts as older than every scope.
> 2. **Call results (closes the escape.bl hole).** A call that returns `Ptr`/`Buf` gets the *youngest* tag among its pointer arguments. This is conservative, never rejects code, and needs no signature annotation. It is the same idea as Rust's elision rules, collapsed to one rule.
> 3. **E0601 tag-mismatch.** A pointer may be stored only into memory from its own scope or a younger one. This covers every store:
>    - `cell.write(p)`
>    - `p.field.write(q)`
>    - passing `q` to a parameter whose type holds pointers (`Ptr[Ptr[T]]`, `Ptr[S]` where `S` has a `Ptr`/`Buf` field, `Buf[IoVec]`), next to a container argument from an older scope. The callee could store `q` there, so this counts as a store.
>
> ```blink
> @ffi("c", "writev")
> fn c_writev(fd: I32, iov: Ptr[IoVec], n: I32) -> I64
>
> fn send_two(fd: I32, a: Bytes, b: Bytes) -> I64 ! FFI {
>     with ffi.scope() as outer {
>         let iov = outer.alloc_n[IoVec](2)
>         with ffi.scope() as inner {
>             let head = inner.cstr("hdr")
>             iov.offset(0).iov_base.write(head)   // E0601 tag-mismatch
>         }
>         c_writev(fd, iov, 2)
>     }
> }
> ```
>
> The diagnostic names both binders and gives a fix:
>
> ```
> error[E0601] tag-mismatch: `head` comes from scope `inner` (line 7), but it is
> stored into `iov` from the older scope `outer` (line 5). `inner` is freed first.
>   help: allocate `head` from `outer`, or call `.take()` on it
> ```
>
> - **Learnability:** The rule fits in one sentence: "don't store a younger pointer into older memory." It is the same intuition as "a closure can capture outer variables". An AI can learn it from the spec alone, with no training-data prior needed.
> - **Decision points:** Zero at write time. The only decision comes when the error fires, and the error names the fix.
> - **Tokens:** Zero per signature. The writev example needs no `^s` on any of about 5 pointer mentions.
> - **Cost:** A helper cannot promise "the result is tied to arg 1 only". It gets the youngest-tag result, and that can raise a false value-escape. That shape is rare, it lives in `@trusted` code, and `.take()` or reordering the scopes fixes it. I accept that cost.
> - **Cross-language:** This is Cyclone/Tofte-Talpin region inference without annotations, and Rust elision with one rule. Go escape analysis is the nearest analogue in the training data.
>
> ---
>
> **AIML-2: The same as AIML-1, with "same scope" in place of "same or younger".**
>
> The rule is "stored pointers and their destination must come from one scope". It is simpler to state and matches the current §9.1.3 wording ("the typing rule requires the same scope tag"). But it rejects safe code: storing an outer-scope pointer into inner-scope memory. That is how people naturally write nested scopes (a long-lived buffer, with a short-lived iovec array built around it). Each false rejection costs a repair round-trip, and AI repairs to a false rejection tend to go wrong (adding `.take()` everywhere, which leaks into GC fallback). I prefer AIML-1. I would accept AIML-2 as a v1 simplification only if the diagnostic suggests moving the allocation outward.
>
> ---
>
> **AIML-3 (OPPOSED, listed so the panel can reject it on the record): explicit σ syntax.**
>
> ```blink
> @trusted(audit: "IO-7")
> fn pick[^s](a: Ptr[U8]^s, b: Ptr[U8]^s) -> Ptr[U8]^s { ... }
> ```
>
> - It adds a new sigil in type position. `^` is currently XOR only, so every AI and every tokenizer has to learn a second meaning for it.
> - It adds a generic binder of a new kind, and a choice at every pointer parameter (tag it or not? same σ or a different one?). That is exactly the decision surface that makes Rust lifetimes fail.
> - It contradicts §5 "not accepted" and the ownership/lifetimes rejection. Adopting it would need an explicit relitigation vote.
> - Training-data prior: Rust's `'a` is well represented, but AI output for it is poor. A Blink-specific `^s` has no prior at all.
> - Its only gain over AIML-1 is precise multi-scope signatures (result tied to one argument). No user-facing code needs that: user code should call `std.libc.*`, and §9.1.3.3 defers writev/readv to their own deliberated API anyway.
>
> ---
>
> **Interaction notes (all for AIML-1):**
>
> - **Spec text:** `Ptr[T]^σ` / `Buf[T]^σ` stay as notation in the spec and in LSP hover, never as surface syntax. The hover shows the inferred scope ("from scope `outer`, line 5"), so debugging is easy without having to write anything.
> - **Nothing reopened:** FfiScope's scope-bound rules, E0811's syntactic region rule, and the Buf sealing are all untouched.
> - **Unblocks the implementation ticket:** tag-mismatch is implemented as store checks plus the call-site container rule, over the escape.bl origin map, extended to call args and results.
> - **Ticket scope:** writev and the other vectored calls still go through their own API deliberation. This proposal only makes that API writable later without adding syntax.

</details>

<details><summary><b>Minimalism</b></summary>

> MIN proposals: σ-tagged function parameters
>
> **Premise check first.** The ticket asks for "syntax + a typing rule that unifies σ across params". I think both parts are wrong.
>
> 1. **A user-written σ contradicts a settled decision.** §5:113 says "No region-variable annotations are required or accepted." DECISIONS.md rejects lifetimes. `Ptr[T]^σ` on a parameter is a named region variable, which is Rust's `&'a T` under another name. Adding it would reopen the rejected ownership row through the FFI back door.
> 2. **Equality is the wrong rule.** Look at `writev(iov, n)` where `iov[0].iov_base` comes from outer scope A and `iov[1].iov_base` comes from inner scope B. That is sound. Both scopes are live for the whole call, and C only reads the addresses during the call. The real hazard is **outlives**: a pointer from B stored into memory that A owns, then used after B unwinds. That is a *store escape*, the same thing as value-escape. A "same σ" rule rejects safe code and still misses the unsafe store, unless you also add the store check. And once you have the store check, the equality rule adds nothing.
> 3. **The motivating case cannot be written today anyway.** The `@ffi.struct` field list in §9.1.3 (I32/U64/F32/Bool/another struct...) does not include `Ptr[T]`. `Buf` is allowed as a field only under the V3 carve-out, and `Buf` is not implemented. `iovec { iov_base: Ptr[U8] }` is not a legal declaration. Also, §9.1.3.3 explicitly defers readv/writev to "their own deliberated API". This ticket designs type theory for a caller the spec has parked.
>
> ---
>
> ### MIN-1 (favored): no syntax. σ stays spec notation, inferred. "tag-mismatch" becomes an outlives check on stores and call results
>
> - `^σ` is **meta-notation in spec prose only**. It has no surface form, and the lexer's `^` stays XOR. Add one sentence to §9.1.3.2 that says so.
> - The σ of any `Ptr`/`Buf` value is **inferred** from its syntactic origin (the `with ffi.scope() as s` binder). Region is already purely syntactic (E0811), so this costs no new machinery.
> - **Call-result rule (elision without annotation).** A call that returns `Ptr`/`Buf` inside a scope block gets the *innermost* σ among its `Ptr`/`Buf` arguments. If it has none, it is unscoped (the `alloc_ptr` GC fallback). This is conservative and never unsound, and it closes the "helper launders the tag" hole in escape.bl today.
> - **`E0601 (tag-mismatch)` is redefined as:** a `Ptr`/`Buf` with σ_B is written (`.write(v)`, field write, or captured) into a cell whose σ_A strictly outlives σ_B. This is Blink's only lifetime relation, and the compiler reads it from lexical nesting. The user writes nothing.
>
> ```blink
> with ffi.scope() as outer {
>     let iov = outer.alloc_n[IoVec](2)
>     with ffi.scope() as inner {
>         let p = inner.alloc_n[U8](64)
>         iov.offset(0).iov_base.write(p)   // E0601 (tag-mismatch): `inner` value stored into `outer` cell
>         let rc = c_writev(fd, iov, 2)      // OK: both scopes live for the call
>     }
>     let rc2 = c_writev(fd, iov, 2)         // the use-after-free MIN-1 prevents
> }
> ```
>
> `@trusted fn helper(p: Ptr[U8], q: Ptr[U8]) -> Ptr[U8]` keeps its plain signature. At the call site its result takes the tag of the shorter-lived of `p` and `q`.
>
> **Tradeoffs.** It adds zero surface syntax, zero concepts for users, and no new diagnostic code. It reuses the escape pass. The cost: the call-result rule is conservative. A helper that returns a pointer tied only to its longer-lived argument gets the shorter tag, so a sound program is rejected. The workaround (inline the helper, or use `.take()`) is cheap, and such helpers are rare in FFI glue. Rust's lifetime elision rules show that most signatures never need names. Blink takes elision and drops the escape hatch.
>
> **Required spec edits.** Rewrite the E0601 (tag-mismatch) line in §9.1.3 from "combined where the typing rule requires the same scope tag" to the outlives-on-store definition. Fix the `alloc_n` return type contradiction: :653 says `Ptr[T]`, :741 says `Buf[T]^σ`. That inconsistency is a bigger real gap than this ticket.
>
> ---
>
> ### MIN-2: do nothing now. Close the spec ticket, rescope the implementation ticket
>
> This is the demand-gate option, in the spirit of the libc growth governance already in the spec. No user can write the motivating case: `Ptr` is not a legal `@ffi.struct` field, `Buf` does not exist, and writev is deferred. So:
>
> - Close the spec ticket as "premise invalid: region annotations are rejected by §5".
> - Rescope the implementation ticket to the **store-escape** hole that escape.bl has today (cell `.write()`, field writes, and captures are unchecked). That is a real soundness bug in shipped code, unlike the hypothetical multi-σ signature.
> - Keep the `tag-mismatch` name reserved in the spec until the deliberation on vectored I/O runs. That deliberation will likely ship `std.libc.writev_bytes(fd, parts: List[Bytes])` built on nested `with_ptr` pins or a copy, and then no user code ever builds an iovec.
>
> **Tradeoffs.** It costs the least and ships nothing speculative. The risk: the spec keeps a dangling sub-kind for a while. That is acceptable because it is already dangling.
>
> Go never exposed its escape analysis as syntax. Lua's C API has no lifetimes at all. Both lean on convention plus a curated surface, which is what γ-doctrine already says Blink does.
>
> ---
>
> ### MIN-3 (fallback only if the panel insists on explicit syntax): one anonymous region per signature, attribute not type
>
> If someone shows a case MIN-1's inference cannot handle, the smallest legal addition is a single fn-level attribute. It adds no type operator and no region variables:
>
> ```blink
> @trusted(audit: "IOV-1")
> @same_scope
> fn build_iov(base: Ptr[U8], iov: Ptr[IoVec]) -> Ptr[IoVec] { ... }
> ```
>
> It means: every `Ptr`/`Buf` in the signature shares one inferred σ, and the caller gets E0601 (tag-mismatch) if the arguments come from different scopes. It is still a boolean and not a lifetime language, so it cannot grow into `'a: 'b`. I oppose it unless someone brings a real program. Its combinatorial cost is low, but the demand today is zero.
>
> ---
>
> **Vote intent:** I favor **MIN-1**, with MIN-2's rescoping of the implementation ticket folded in. I reject any `^σ` or named region syntax: it breaks §5:113 and the ownership rejection, and it tests the wrong property (equality instead of outlives).

</details>

#### Phase B — Debate highlights

One round. All attribute and explicit-syntax proposals were withdrawn; the panel moved from equality to *outlives*, and from scope names to binder nodes.

- **PLT:** **Rebuttal to SYS-1(d).** SYS says: "each parameter gets one fresh tag, 'caller'. The same tag for all parameters is sound because every argument is live for the whole call." It is live during the call, but a store can outlive the call. `set_iov(iov_outer, buf_inner)` stores a pointer that dangles after `inner` unwinds, and nothing at the call site catches it. `blink audit` records the store, but that does not make it sound. With the container rule, SYS-1(d) can stay as it is inside bodies, because the caller carries the check. DEVOPS-2's body check becomes unnecessary for the same reason. The remaining trust surface is a callee that stores into memory it did not receive as an argument. That is `@trusted`'s job.
- **Systems:** **Opt-ATTR, all three spellings: NO for v1. I withdraw SYS-2.** AIML-1's container-argument rule does SYS-2's job with no attribute. At a call, a younger Ptr passed next to an older argument whose type can hold pointers (`Ptr[Ptr[T]]`, `Ptr[S]` where S has a Ptr field) counts as a store. That rule reads only the types in the signature, so it needs no body inference and does not trigger DEVOPS's "body change silently changes caller errors" objection.
- **PLT:** **V4: I concede to SYS-1(a).** My `iov_base: Buf[U8]` was wrong: `Buf` is a `blink_buf_t*`, which breaks the C ABI. Allow `Ptr[T]` fields. **Add a condition:** an `@ffi.struct` with a Ptr field is *Ptr-bearing*, and E0811 then applies to the struct type itself. Otherwise a by-value `IoVec` could carry a `Ptr` out of an FFI region. The change amends ffi-struct-construction (E0812) and the buf V3 table, so it needs a separate vote.
- **DevOps:** **V3: binder node identity. I concede.** PLT's shadowed `as s` example is correct, and my rule 1 was unsound. When two live binders share a name, diagnostics and hover print `s (line 4)`, never a bare `s`.
- **AI/ML:** **V1: outlives. I withdraw AIML-2.** MIN's case convinced me: iov entries from outer and inner scopes are sound during the call, and equality rejects it. A false rejection costs an AI a repair loop, which tends to end in `.take()` spam.
- **Web/Scripting:** *(dissent, withdrawn in Phase C)* **V2:** writes, field writes and `Ptr[Ptr[T]]` cells: YES. Closure captures: YES; a JS developer expects a closure to keep what it captures, and this is the classic way to get a dangling pointer. Effect-op args: YES, for the same reason. AIML-1's call-as-store rule: **NO**. It turns `c_writev(fd, iov, 2)`-shaped calls into errors whenever a younger pointer sits next to an older struct. That call is safe because both scopes are alive, and MIN-1's example shows it is legal. Param-into-param stores: **SYS-1d** (one shared caller tag, reported by `blink audit` as `ptr-store-param`). DEVOPS-2's body check needs the attribute that I now reject.
- **DevOps:** **V2: all store kinds, including AIML-1's container rule.** WEB says the rule "turns `c_writev(fd, iov, 2)`-shaped calls into errors". It does not: that call has one Ptr argument, so nothing is paired. The rule fires only when a younger Ptr and an older pointer-holding argument go into the same call. Diagnostic requirement: the error must point at the callee's parameter type, or users read it as a compiler bug:
- **Minimalism:** **Opt-ATTR (all three spellings, including my own MIN-3): NO. I withdraw MIN-3.** AIML-1's call-site rule removes the one case ATTR was meant to cover (see V2). Once that rule is in, `@same_scope` / `@ffi.scope_linked` is a second way to do the same thing. PLT-3's objection is right: "a second mechanism beside inference". WEB-2 admits it "is also a restricted form of region annotation, so the panel must say so openly against §5". I will not vote to open that door for zero known callers.
- **DevOps:** WEB: "Punishing the caller in their place gives the worst developer experience of any option." Worse DX is a use-after-free with no error, which SYS-1d alone permits (`set_iov(iov_outer, buf_inner)`, then `writev` after `inner` closes). The container-rule error names both scopes, the parameter and the fix.

Web/Scripting withdrew this dissent in Phase C; see its Q2 ballot below.

Full round-1 texts, verbatim:

<details><summary><b>Systems</b></summary>

> SYS — Phase B round 1
>
> **Options**
> - **Opt-INFER: YES.** It has zero runtime cost, σ is erased, codegen does not change, and the pass is linear. PLT's chain lemma is the reason completeness holds without annotations.
> - **Opt-ATTR, all three spellings: NO for v1. I withdraw SYS-2.** AIML-1's container-argument rule does SYS-2's job with no attribute. At a call, a younger Ptr passed next to an older argument whose type can hold pointers (`Ptr[Ptr[T]]`, `Ptr[S]` where S has a Ptr field) counts as a store. That rule reads only the types in the signature, so it needs no body inference and does not trigger DEVOPS's "body change silently changes caller errors" objection.
> - **Opt-EXPLICIT: NO.** It reverses §5, adds a fork on `^` in the parser, and gives nothing that the codegen or the runtime can use.
> - **Opt-DEFER: NO as a way to close the ticket, YES to its rescope.** The unchecked-store hole is a use-after-free in shipped code today, so the store check ships now. Fold MIN-2's rescope of the implementation ticket into INFER.
>
> **Variations**
> - **V1: outlives.** DEVOPS-2 says: "equality is enough, because every motivating case (iovec, msghdr) is 'all of these pointers from one scope'." That is not true of real I/O code. The common shape is a long-lived buffer (a connection's receive ring) with a short-lived iovec array built around it on each call. Equality rejects that shape, and the usual forced fix is `.take()`, which moves the buffer onto the GC fallback path. That is a cost at run time to satisfy a rule that is wrong.
> - **V2:** `.write`, field write and `Ptr[Ptr]` cell writes: yes. Closure captures: yes; a closure that escapes is a heap cell. Effect-op arguments: yes (PLT). A handler that keeps the argument is a store into the handler's scope. Cheapest rule: reject unless the handler is installed inside ρ. AIML's container-argument rule: yes, see above. It replaces SYS-1(d)'s call-site half. Inside `@trusted` bodies I keep one caller tag for all params plus the `ptr-store-param` audit entry. DEVOPS-2's "params are distinct unknown scopes" would reject `set_iov` with no way to make it legal except an attribute, and I voted against the attribute.
> - **V3: binder node identity. I change my Phase A position.** PLT is right that `with ffi.scope() as s { with ffi.scope() as s { … } }` makes tags keyed by name unsound. Names are for diagnostics only.
> - **V4: allow `Ptr[T]` as an `@ffi.struct` field; reject `Buf` fields.** PLT's example `iov_base: Buf[U8]` is an ABI bug. §9.1.3.2 defines `Buf` as a pointer to `{void* data; int64_t len; int64_t cap}`. C's `iovec.iov_base` is `void*` to the bytes. writev would then send the header struct, not the payload. The `_Static_assert` on size would pass, because both are pointer-sized, so nothing catches it. Only a `Ptr[T]` field lowers to the C layout.
> - **V5: `alloc_n` returns `Ptr[T]`.** `Buf` is sealed and has no methods. If `alloc_n` returned `Buf`, then `.offset(i)` and `.field.write` would be unreachable, and the poll example at :653 would not compile. Fix :741 to read "`Buf` comes only from `copy_to_buf`". That also matches the compiler.
> - **V6: yes.** `^σ` is meta-notation and never a token.
> - **V7: yes.** The new text: "a scope-tagged Ptr/Buf stored into a cell whose scope strictly outlives the value's scope".
> - **V8: out of scope. Leave it to the vectored-I/O deliberation.** One systems note for that deliberation: `writev_bytes(fd, List[Bytes])` cannot pin a dynamic number of `Bytes` with the CPS `with_ptr` bracket, which was PLT's own point in ffi-struct-construction. So that wrapper would copy each chunk into scope memory. That is one memcpy per chunk, and zero-copy is the only reason to call writev. Design the wrapper with that cost in view.
>
> **Rebuttals**
> - MIN-1: "C only reads the addresses during the call." That is true of writev and false of `aio_write`, `io_uring_prep_writev` and `setvbuf`, which keep the pointer after they return. No inferred rule can see a retention on the C side. The spec should say that tag-mismatch covers stores the Blink side can see, and that a C function which keeps a pointer is out of scope and left to the audit.
> - PLT rule 3 (meet at calls) is sound, and also conservative for C functions that return static memory (`getenv`). That is acceptable.
>
> **Changes from Phase A:** SYS-2 withdrawn (AIML's container-argument rule replaces it); V3 changed from binder name to node identity. SYS-1 otherwise stands.
>
> stable, ready to vote

</details>

<details><summary><b>Web/Scripting</b></summary>

> **WEB: Phase B round 1**
>
> ### Options
>
> - **Opt-INFER: YES.** All six panelists favor it. It is the answer that a JS or Python developer never has to learn. Errors name `outer` and `inner`, which are the user's own words.
> - **Opt-ATTR: NO for v1. I withdraw WEB-2.** PLT-3 is right: "it cannot express 'result tied to argument', and it creates a second mechanism beside inference." The only caller is a stdlib writev bridge that §9.1.3.3 has not designed yet. Adding an attribute before that caller exists is YAGNI. If the vectored-I/O deliberation shows a real need, it can add one then. Of the three spellings, I rank them `@same_scope(a, b)` > bare `@same_scope` > `@ffi.scope_linked`. Named parameters read best, but I vote for none of them now.
> - **Opt-EXPLICIT: NO.** My reasons are the same as in WEB-3.
> - **Opt-DEFER: PARTIAL.** I support MIN-2's rescope of the implementation ticket to the store-escape hole. I oppose closing the spec ticket with the tag-mismatch definition left dangling. Opt-INFER *is* the definition, so we should write it into the spec now. "Reserved until later" produces "what does this error mean" questions.
>
> ### Variations
>
> - **V1: outlives.** AIML-2's equality rule rejects the natural pattern "long-lived buffer, short-lived iovec array". Each false rejection is a Stack Overflow question, and AIML-1 itself says AI repairs of them go wrong.
> - **V2:** writes, field writes and `Ptr[Ptr[T]]` cells: YES. Closure captures: YES; a JS developer expects a closure to keep what it captures, and this is the classic way to get a dangling pointer. Effect-op args: YES, for the same reason. AIML-1's call-as-store rule: **NO**. It turns `c_writev(fd, iov, 2)`-shaped calls into errors whenever a younger pointer sits next to an older struct. That call is safe because both scopes are alive, and MIN-1's example shows it is legal. Param-into-param stores: **SYS-1d** (one shared caller tag, reported by `blink audit` as `ptr-store-param`). DEVOPS-2's body check needs the attribute that I now reject.
> - **V3: node identity.** Users copy and paste `with ffi.scope() as s` blocks inside each other all the time. A tag keyed on the name gives wrong answers in exactly that case. Diagnostics still print the name and line.
> - **V4: support SYS-1a**, recorded as its own ruling because it touches two prior decisions. A `Buf` field that silently has the wrong C layout is worse than any syntax question.
> - **V5: `alloc_n` returns `Ptr[T]`.** `Buf` is sealed and has no `.offset`, so a `Buf` return would break ffi-struct-construction's own `alloc_n[T](n)` + `.offset(i)` + `.field.write` model. The compiler already returns `Ptr[T]`. Edit :741 so that only `copy_to_buf` returns a `Buf`.
> - **V6: YES.** Add one sentence saying `^σ` is meta-notation and not source syntax.
> - **V7: YES.** Use SYS-1's wording: "a scope-tagged `Ptr`/`Buf` stored into a cell whose scope tag it does not enclose".
> - **V8: note only.** It is not decided here. §9.1.3.3 owns it, and INFER already makes it possible later.
>
> ### Rebuttals
>
> - DEVOPS-2: "I think equality is enough, because every motivating case (iovec, msghdr) is 'all of these pointers from one scope'." The iovec case is exactly where outer-into-inner mixing is safe and common, as SYS and MIN both showed. An equality attribute would teach users a stricter rule than the language needs.
> - AIML-1: "The callee could store `q` there, so this counts as a store." Under that rule the most common safe FFI call becomes an error. Callee-side stores already belong to `@trusted` and audit (SYS-1d). Punishing the caller in their place gives the worst developer experience of any option on the table.
>
> ### Change from Phase A
>
> 1. I withdraw the WEB-2 fallback. PLT-3's argument, plus the fact that no caller exists yet, settles it.
> 2. I adopt SYS-1d, V3 (node identity) and V4 (SYS-1a), which I did not address in Phase A.
>
> My vote: **Opt-INFER** plus the MIN-2 rescope of the implementation ticket, V1 outlives, V2 without the call-as-store rule, and V3 through V7 as above.
>
> stable, ready to vote

</details>

<details><summary><b>PLT</b></summary>

> **PLT, Phase B round 1**
>
> **Options**
>
> - **Opt-INFER: YES.** It must include AIML-1's call-site container rule (see V2). Without that rule it has a hole.
> - **Opt-ATTR, all spellings: NO.** When INFER includes the container rule, the attribute adds nothing that is sound. SYS-2's `@ffi.scope_linked` ("any Ptr param may be stored into any other") is exactly the assumption the container rule makes for every call, so a marker that turns it on is redundant. DEVOPS-2 and WEB-2 `@same_scope(a, b)` use equality, which rejects the safe outer-into-inner store (V1). MIN-3 is equality over the whole signature, which is worse.
> - **Opt-EXPLICIT: NO. I withdraw PLT-2 as a fallback.** My only reason for PLT-2 was result precision (`pick` tied to one argument). Nobody showed a program that needs it, and it reverses §5.
> - **Opt-DEFER: NO.** MIN-2 correctly calls the store hole "a real soundness bug in shipped code". Fixing it needs the tag-mismatch rule, so the rule has to be written now. I agree with MIN on the ticket's premise: close the spec ticket as "premise invalid" and record the INFER rule as its resolution.
>
> **Variations**
>
> - **V1: outlives, not equality.** The typing rule is `σ_cell ⊑ τ_value`: the stored value must live at least as long as the cell. Equality is not the principal constraint. It is strictly stronger than this rule and buys no soundness.
> - **V2: the store set is:**
>   - explicit writes (all panelists);
>   - closure captures that escape;
>   - effect-operation arguments, where the handler's scope counts as the cell;
>   - **AIML-1's container rule**: at a call, a Ptr/Buf argument with tag τ, next to an argument whose pointee transitively holds a Ptr/Buf and has tag σ, requires `σ ⊑ τ`. This rule is what makes bodies soundly modular: the callee may store any argument into any other, and the caller over-approximates.
>
>   **Rebuttal to SYS-1(d).** SYS says: "each parameter gets one fresh tag, 'caller'. The same tag for all parameters is sound because every argument is live for the whole call." It is live during the call, but a store can outlive the call. `set_iov(iov_outer, buf_inner)` stores a pointer that dangles after `inner` unwinds, and nothing at the call site catches it. `blink audit` records the store, but that does not make it sound. With the container rule, SYS-1(d) can stay as it is inside bodies, because the caller carries the check. DEVOPS-2's body check becomes unnecessary for the same reason. The remaining trust surface is a callee that stores into memory it did not receive as an argument. That is `@trusted`'s job.
> - **V3: binder identity, not name.** DEVOPS-1 rule 1 is unsound. Take `with ffi.scope() as s { let c = s.alloc_n[Ptr[U8]](1); with ffi.scope() as s { c.write(s.alloc_n[U8](8)) } }`. Both binders are `s`, so the check compares `s` with `s` and passes, and the stored pointer dangles. Keep names for diagnostics only; DEVOPS's error format still works.
> - **V4: I concede to SYS-1(a).** My `iov_base: Buf[U8]` was wrong: `Buf` is a `blink_buf_t*`, which breaks the C ABI. Allow `Ptr[T]` fields. **Add a condition:** an `@ffi.struct` with a Ptr field is *Ptr-bearing*, and E0811 then applies to the struct type itself. Otherwise a by-value `IoVec` could carry a `Ptr` out of an FFI region. The change amends ffi-struct-construction (E0812) and the buf V3 table, so it needs a separate vote.
> - **V5: `alloc_n` returns `Ptr[T]`.** `Buf` is sealed: it has no `.offset` and no field access. If `alloc_n` returned `Buf[T]`, every alloc_n + `.offset(i).field.write(v)` example in ffi-struct-construction would fail to typecheck. :741 is the error. `Buf` comes only from `copy_to_buf`. Amend that "only ways to obtain" line in §9.1.3.2.
> - **V6: yes.** `^σ` is meta-notation only.
> - **V7: yes.** New definition: "tag-mismatch: a scope-tagged Ptr/Buf stored, by write, capture, effect argument, or a call beside a pointer-holding argument, into a cell whose scope it does not enclose."
> - **V8: out of scope.** §9.1.3.3 owns vectored I/O. INFER with V4 makes a curated `writev_bytes` expressible and checkable. It does not approve it.
>
> **Changes from Phase A**
>
> - I withdraw PLT-2.
> - I adopt AIML-1's container rule, which fills the hole in my rule 3: PLT-1's call rule tied only arguments to the result.
> - I concede V4 to SYS and add the Ptr-bearing condition.
>
> stable, ready to vote

</details>

<details><summary><b>DevOps</b></summary>

> **DEVOPS, Phase B round 1**
>
> ### Options
>
> - **Opt-INFER: YES.** No parser or fmt change; errors name the user's own binders. It must include AIML-1's container rule (V2).
> - **Opt-ATTR, all spellings: NO. I withdraw DEVOPS-2.** My Phase A case for it was API stability: "a change to the body would silently change errors at the callers." AIML-1's container rule reads only the callee's parameter *types*, so it gives that stability with no attribute. My `@same_scope(a, b)` also used equality, the wrong relation (V1).
> - **Opt-EXPLICIT: NO.** As DEVOPS-3: `^` gets a second meaning, and errors turn rustc-style.
> - **Opt-DEFER: NO as a way to close; YES to the implementation-ticket rescope.** An error code with a reserved but undefined sub-kind is a bad `blink explain E0601` page.
>
> ### Variations
>
> - **V1: outlives. I change my position.** SYS's receive-buffer case shows equality rejects normal code, and its only fix (`.take()`) is also wrong.
> - **V2: all store kinds, including AIML-1's container rule.** WEB says the rule "turns `c_writev(fd, iov, 2)`-shaped calls into errors". It does not: that call has one Ptr argument, so nothing is paired. The rule fires only when a younger Ptr and an older pointer-holding argument go into the same call. Diagnostic requirement: the error must point at the callee's parameter type, or users read it as a compiler bug:
>
> ```
> error[E0601]: pointer from a shorter-lived scope passed beside a pointer container (tag-mismatch)
>   --> src/net.bl:9:9
>    |
>  9 |         set_iov(iov, buf, 64)
>    |                 ---  ^^^ `buf` belongs to scope `inner` (line 7)
>    |                 |
>    |                 `iov` belongs to scope `outer` (line 4)
>    = note: parameter `iov: Ptr[IoVec]` can hold pointers (`IoVec.iov_base: Ptr[U8]`),
>            so `set_iov` may store `buf` in it
>    = help: allocate `buf` from `outer`
> ```
>
>   Closure captures and effect-op arguments: yes, but each diagnostic must label the capture or the `perform` site as the store, not only the binding. Inside `@trusted` bodies: SYS-1d (one caller tag, `ptr-store-param` audit row). It is sound only with the container rule, as PLT showed.
> - **V3: binder node identity. I concede.** PLT's shadowed `as s` example is correct, and my rule 1 was unsound. When two live binders share a name, diagnostics and hover print `s (line 4)`, never a bare `s`.
> - **V4: YES to SYS-1a**, recorded as an amendment to both prior decisions. A `Buf` field passes the size `_Static_assert`, so that ABI bug has no diagnostic. I support PLT's Ptr-bearing condition on E0811. Its message must name the field: "`IoVec` holds `Ptr` in field `iov_base` (line 3), so it may appear only in an FFI region".
> - **V5: `alloc_n` returns `Ptr[T]`.** It matches the compiler. Fix :741.
> - **V6: YES.** Hover and diagnostics print `(scope: outer)`, never `^σ`.
> - **V7: YES**, with PLT's wording, which lists the four store forms. `blink explain E0601` gives one example per form.
> - **V8: out of scope.**
>
> ### Rebuttals
>
> - WEB: "Punishing the caller in their place gives the worst developer experience of any option." Worse DX is a use-after-free with no error, which SYS-1d alone permits (`set_iov(iov_outer, buf_inner)`, then `writev` after `inner` closes). The container-rule error names both scopes, the parameter and the fix.
> - SYS: C-side retention (`aio_write`, `io_uring`). Agreed that it is out of scope. `blink audit` should list `@ffi` fns that take a Ptr, so reviewers can find these.
>
> ### Changes from Phase A
>
> I withdraw DEVOPS-2. I move from equality to outlives (V1) and from binder name to node identity (V3). I adopt the container rule, SYS-1d, and SYS-1a with PLT's Ptr-bearing condition.
>
> stable, ready to vote

</details>

<details><summary><b>AI/ML</b></summary>

> **AIML, Phase B round 1**
>
> **Options**
>
> - **Opt-INFER: YES.** Six of six panelists favor it. For AI, it adds zero tokens and zero decisions at write time, and the diagnostic names the fix.
> - **Opt-ATTR (all spellings): NO for v1.** Each spelling adds a new decision to every `@trusted` helper ("do I need `@same_scope` here? which params?"), and an AI will guess wrong in both directions. Two of the spellings (`@same_scope(a, b)`, bare `@same_scope`) also encode *equality*, which SYS and MIN both showed is the wrong relation. `@ffi.scope_linked` is the least bad, but see V2: a signature-only call-site rule gives the same protection with no attribute.
> - **Opt-EXPLICIT: NO.** Same reasons as AIML-3. PLT, who proposed it, also votes against it.
> - **Opt-DEFER: partly.** I accept MIN-2's rescoping of the implementation ticket to the store hole. I reject "do nothing": we should resolve the spec ticket by writing the inference rules into the spec now, so that the vectored-I/O deliberation starts from a defined check and not from a dangling sub-kind.
>
> **Variations**
>
> - **V1: outlives. I withdraw AIML-2.** MIN's case convinced me: iov entries from outer and inner scopes are sound during the call, and equality rejects it. A false rejection costs an AI a repair loop, which tends to end in `.take()` spam.
> - **V2: all of the listed stores**, with one unifying rule so that AI learns one concept, not a list: *a closure or an effect-op argument is a value with a tag (the meet of what it captures or receives), and it goes through the same store and escape checks.* A closure that is called only inside the scope is then accepted with no extra rule.
>   - Param-into-param: I support SYS-1d in the body (accepted, audited), **paired with** my AIML-1 call-site rule. The pair keeps it sound: in a call to a fn with a param type that holds pointers, every other pointer argument must outlive the container argument. Otherwise SYS-1d lets `set_iov(iov_outer, buf_inner)` followed by `writev` after `inner` closes compile silently. That is the exact bug the ticket describes.
> - **V3: node identity.** PLT is right that name keys are unsound under shadowing. Diagnostics print the name, plus the line when two scopes share a name.
> - **V4: agree with SYS-1a** (`Ptr[T]` fields, no `Buf` fields). The ABI argument settles it. For AI it also means one pointer type in C structs instead of a choice. It amends buf-u8-runtime-representation, so the decision record must say so.
> - **V5: `alloc_n` returns `Ptr[T]`; fix :741.** Deciding point: `Buf` is sealed with no methods, so an `alloc_n` that returned `Buf` could not support `.offset(i)` or `.field.write`, which ffi-struct-construction requires. Two overloads would give AI a choice with no signal for which to use.
> - **V6: yes.** **V7: yes**, using the outlives wording. **V8: out of scope.** INFER makes `writev_bytes` possible, and its own deliberation decides it.
>
> **Rebuttals**
>
> - WEB-2: "It reads as plain English and can be found with grep." That is true for reading, but it does not help generation. Nothing in the spec tells an AI *when* to write it, and the attribute's own check (equality) is the wrong one.
> - DEVOPS-2: "inferring the equality constraint from the helper body… a change to the body would silently change errors at the callers." I agree, and that is why my call-site rule reads only the callee's **param types**, never its body. It gives the same API stability as an attribute, without the attribute.
> - SYS-1d: "stores inside a `@trusted` helper are not checked in the caller. I accept this." I do not. `@trusted` vouches for the body's memory safety given valid inputs. It cannot vouch for scope ordering at call sites it never sees. The caller-side rule closes that gap at no syntax cost, and its fix is always mechanical: move the allocation outward.
>
> **Changes from Phase A:** I dropped AIML-2 (equality) and adopted V3 node identity, V4 SYS-1a, and V5 `Ptr[T]`. I keep AIML-1's call-site container rule as the sound complement to SYS-1d.
>
> stable, ready to vote

</details>

<details><summary><b>Minimalism</b></summary>

> MIN — Phase B round 1
>
> **Options**
>
> - **Opt-INFER: YES.** I back PLT-1's form of it: meet at calls, outlives at stores, binder node identity. All six panelists reached it on their own, which is the best sign that it is the smallest correct answer.
> - **Opt-ATTR (all three spellings, including my own MIN-3): NO. I withdraw MIN-3.** AIML-1's call-site rule removes the one case ATTR was meant to cover (see V2). Once that rule is in, `@same_scope` / `@ffi.scope_linked` is a second way to do the same thing. PLT-3's objection is right: "a second mechanism beside inference". WEB-2 admits it "is also a restricted form of region annotation, so the panel must say so openly against §5". I will not vote to open that door for zero known callers.
> - **Opt-EXPLICIT: NO.** It reverses §5:113 and the lifetimes rejection. Its own proposer votes against it.
> - **Opt-DEFER: CHANGED.** I drop "do nothing". INFER costs no syntax and fixes real holes in shipped escape.bl: unchecked stores, the call-result gap, name aliasing. I keep the rest of MIN-2: close the spec ticket as "premise invalid, no σ syntax" (or retitle it as PLT says), and scope the implementation ticket to INFER.
>
> **Variations**
>
> - **V1: outlives.** Equality (AIML-2) rejects the safe outer-into-inner store and adds nothing.
> - **V2: all store kinds.** That covers `.write`, field write, `Ptr[Ptr[T]]`, closure captures, and effect-op args. PLT is right that a handler holding a pointer past unwind is the same hole. I also want **AIML-1's call-site rule**: passing a younger pointer into a call that also gets an older pointer-holding container counts as a store. With that rule, **SYS-1d** (params share one caller tag inside `@trusted` bodies) is sound, because the caller already rejected the mismatched call. So I pick SYS-1d plus AIML-1 over DEVOPS-2's per-param annotation. The rule does not fire on `memcpy(dst_outer, src_inner)`, because `Ptr[U8]` does not hold pointers. The `ptr-store-param` audit row is fine as tooling. It is not a language rule.
> - **V3: node identity.** DEVOPS-1 rule 1 ("the tag is the name of its binder") is unsound when two nested scopes are both written `as s`. The name is for diagnostics only.
> - **V4: allow `Ptr[T]` in `@ffi.struct` fields: YES.** Without it no iovec can be declared, and every example on this panel is illegal. **Remove `Buf` fields: YES, but as a recorded amendment to buf-u8-runtime-representation, not a silent edit.** SYS is right that `Buf` is a `blink_buf_t*`, not `void*`. PLT-1's example (`iov_base: Buf[U8]`) breaks the C ABI, and `_Static_assert` would reject it.
> - **V5: `alloc_n` returns `Ptr[T]`.** :741 is the error. §9.1.3.2 says `Buf` has "no public methods", yet §9.1.3's own pollfd example calls `.offset(i)` and `.fd.write()` on the `alloc_n` result. A sealed `Buf` return would make `alloc_n` useless. `copy_to_buf` keeps returning `Buf[U8]`. Fix :741's "only ways to obtain" line.
> - **V6: YES.** `^σ` is spec meta-notation only.
> - **V7: YES.** Use the outlives wording: "a scope-tagged `Ptr`/`Buf` stored into a cell whose scope it does not outlive".
> - **V8: NO, not here.** §9.1.3.3 already sends vectored I/O to its own deliberation, and the naming law excludes it. Putting `writev_bytes` into this decision is exactly the scope creep that decision warned against.
>
> **Rebuttals**
>
> - DEVOPS-2: "every motivating case (iovec, msghdr) is 'all of these pointers from one scope'." That is false. An outer long-lived buffer placed into an inner short-lived iovec is the normal nesting (AIML-2 says so too), and equality rejects it.
> - DEVOPS-2 rejects body inference because "a change to the body would silently change errors at the callers". Under SYS-1d plus AIML-1 no body is inferred. The call-site rule reads only parameter *types*, so this objection does not apply.
> - PLT-1's example uses a `Buf[U8]` field. See V4.
>
> **Changes from Phase A:** I withdraw MIN-3. I drop MIN-2's "do nothing" but keep its ticket rescoping. I add V4 and AIML-1's call-site rule to the favored package.
>
> stable, ready to vote

</details>

#### Phase C — Final vote

- **Q1: Core resolution** (6-0, **INFER**)
  - **Systems:** INFER
    - Reasoning: σ is erased, so there is no runtime cost and codegen does not change. The check is one linear pass over each fn body. Scopes are lexical, so they form a total order, and every tag the compiler needs can be read from the AST.
    - Concern: the meet rule at calls gives some helper results a shorter tag than they need, which can produce false value-escape errors. Users might answer those with `.take()`, which moves the memory onto the GC fallback path.
  - **Web/Scripting:** INFER
    - Reasoning: The user writes no σ syntax, `^` stays XOR, and errors name the user's own `outer` / `inner` binders. A JS or Python developer understands "you stored a short-lived pointer into longer-lived memory" in seconds. All six panelists reached this independently, and that is a good sign it is the familiar answer.
    - Concern: The call-result rule (innermost argument tag) will sometimes give false errors for a helper that returns its longer-lived argument. The docs need a clear "why and how to fix" entry for that case.
  - **PLT:** INFER
    - Reasoning: The chain lemma holds. Scopes are lexical, cannot be passed, and nest strictly. So the live tags at any point form a total order, the meet always exists, and inference is complete with no region variables. That keeps §5:113 and the lifetimes rejection intact, and the check is decidable in one linear pass.
    - Concern: if Q2 fails, INFER checks only half of the soundness argument. SYS-1d then lets a mismatched store through the helper boundary with no error.
  - **DevOps:** INFER
    - Reasoning: No lexer, parser or fmt change, and `^` stays XOR. Errors name the user's own binders (`outer`, `inner`), and LSP hover can show `(scope: outer)` as a display-only hint. Every other option adds a surface that tooling has to parse, complete and explain.
    - Concern: The meet rule at calls can put a false value-escape on a helper result, and the error must then name the argument that set the tag or it will look arbitrary.
  - **AI/ML:** INFER
    - Reasoning: It adds zero tokens per signature and zero decisions at write time. The only rule an AI must learn is one sentence: "don't store a younger pointer into older memory". AI can learn that from the spec alone, and the diagnostic names the fix. Every other option adds syntax or an attribute with no spec signal for when to write it.
    - Concern: The rule is conservative, so false positives can happen. If their diagnostics do not name the mechanical fix (allocate from the outer scope), AI repair loops will fall back to `.take()` spam, which moves memory onto the GC path.
  - **Minimalism:** INFER
    - Reasoning: It adds no token, no attribute, no concept users must write. It keeps §5:113 and the lifetimes rejection intact. The check it needs fixes a use-after-free in shipped code, so it is not speculative surface. DEFER's useful half (the implementation-ticket rescope) is already part of INFER.
    - Concern: The inferred rules may grow case by case (one more "counts as a store" item per ticket) until the implicit rule set is as large as the syntax we refused. Hold the store list in V7 closed.

- **Q2: Call-site container rule** (6-0, **YES**)
  - **Systems:** YES
    - Reasoning: PLT's rebuttal to my SYS-1d is correct. The argument is live during the call, but a store can outlive the call, so `set_iov(iov_outer, buf_inner)` followed by writev is a use-after-free with no error. The rule reads only the callee's parameter types, so it needs no inference over the callee's body. WEB's worry about `c_writev(fd, iov, 2)` is wrong: that call has one Ptr argument, so the rule does not fire.
    - Concern: for a C fn that only reads a pointer-holding argument (e.g. `const struct iovec*`), the rule over-rejects. The fix is always to allocate from the outer scope, but users may see it as noise.
  - **Web/Scripting:** YES (changed from round 1)
    - Reasoning: In round 1 I claimed this rule breaks `c_writev(fd, iov, 2)`. DEVOPS is right that it does not: that call passes only one Ptr, so the rule does not fire. PLT's `set_iov(iov_outer, buf_inner)` case is a silent use-after-free without the rule. A clear error that names both scopes, the parameter and the fix is better DX than a crash.
    - Concern: Users may read the error as a compiler bug unless it names the callee parameter type that can hold pointers, as the DEVOPS diagnostic mockup does.
  - **PLT:** YES
    - Reasoning: This is what makes a helper's body sound to check on its own. The caller assumes the callee may store any pointer argument into any argument that can hold pointers. That is the most conservative reading of the callee's parameter types, and it reads only the signature. WEB's objection does not apply to `c_writev(fd, iov, 2)`: that call has one Ptr argument, so there is nothing to pair. The rule fires only on a younger Ptr beside an older pointer-holding argument, and that pairing is the bug itself.
    - Concern: the rule can over-reject helpers that take a container but never store into it. The diagnostic must name the parameter type that holds pointers, as in DEVOPS's example, or users read the error as a compiler bug.
  - **DevOps:** YES
    - Reasoning: It reads only the callee's parameter types, so a body edit never changes errors at callers. Without it, `set_iov(iov_outer, buf_inner)` followed by a later `writev` compiles with no error, which is the worst diagnostic outcome. It fires only when a younger Ptr and an older pointer-holding argument share a call, so `c_writev(fd, iov, 2)` is unaffected.
    - Concern: If the error does not point at the parameter type that "can hold pointers" (and the field that makes it so), users will report it as a compiler bug.
  - **AI/ML:** YES
    - Reasoning: Without it, `set_iov(iov_outer, buf_inner)` followed by `writev` compiles silently. That is the exact bug the ticket names. The rule reads only the callee's param types, so the outcome is predictable from the signature, and the fix is always the same move. WEB's counterexample does not apply: `c_writev(fd, iov, 2)` has one Ptr argument, so nothing is paired.
    - Concern: Users may read the error as a compiler bug unless it cites the callee parameter and the pointer-holding field, as in DEVOPS's example format.
  - **Minimalism:** YES
    - Reasoning: This one rule removes every reason for the ATTR family. It reads only parameter types, so a change to a callee body cannot change caller errors. WEB's objection does not hold: `c_writev(fd, iov, 2)` has one Ptr argument, so the rule never pairs anything. It fires only on the `set_iov(iov_outer, buf_inner)` shape, and that is the bug in the ticket.
    - Concern: The error fires at a call that looks harmless, so if the message does not name the pointer-holding parameter type (DEVOPS's format), users will file it as a compiler bug.

- **Q3: Param-into-param stores in `@trusted` bodies** (6-0, **SYS-1d**)
  - **Systems:** SYS-1d
    - Reasoning: with Q2 in place, the caller carries the check, so a shared caller tag in the body is sound. A body check would need the attribute we are rejecting. The audit row keeps these stores visible.
    - Concern: a callee that stores into memory it did not receive as an argument (a global, or a static C buffer) is still unchecked, and depends on the `@trusted` review.
  - **Web/Scripting:** SYS-1d
    - Reasoning: With Q2 in place the caller carries the check, so helper bodies stay simple and need no attribute. A per-parameter body check would reject ordinary `set_iov`-style helpers with no way to make them legal.
    - Concern: Stores into memory the callee did not receive as an argument still depend on `@trusted` review alone.
  - **PLT:** SYS-1d
    - Reasoning: If the Q2 rule holds at every call site, then one shared caller tag inside the body is sound, because every pairing that could dangle was already rejected at the caller. BODY-CHECK would reject `set_iov` with no legal fix except an attribute that the panel withdrew.
    - Concern: if Q2 fails, SYS-1d is unsound, and `ptr-store-param` in the audit only records the hole. It does not close it.
  - **DevOps:** SYS-1d
    - Reasoning: With the Q2 rule, the caller already carries the check, so a body check only adds false errors with no fix except an attribute that the panel rejected. The `ptr-store-param` audit row keeps these stores easy to find.
    - Concern: If Q2 fails, SYS-1d alone is unsound, and I would change this vote.
  - **AI/ML:** SYS-1d
    - Reasoning: The container rule already carries the check at the caller, so an in-body check would force an attribute that everyone rejected. One caller tag and an audit row is the simplest model to learn.
    - Concern: A callee that stores a param into memory it did not receive as an argument (a global, or C-side state) stays unchecked, and only `@trusted` review catches it.
  - **Minimalism:** SYS-1d
    - Reasoning: With Q2, the caller carries the check, so one shared caller tag inside the body is sound. BODY-CHECK would reject every legal `set_iov` unless we add the attribute we just voted down.
    - Concern: A `@trusted` body that stores an argument into memory it did not receive as an argument (a global, static C state) is not seen by either check. Only audit covers it.

- **Q4: Escaping closure captures and effect-op arguments count as stores** (6-0, **YES**)
  - **Systems:** YES
    - Reasoning: an escaping closure is a heap cell. A handler that keeps an argument is a cell whose lifetime is the handler's scope. Either can hold a freed pointer after unwind, which is the same bug as `.write`.
    - Concern: deciding whether a closure "escapes" needs an escape judgement that is exact. If it is conservative, it rejects closures that are only called inside the scope.
  - **Web/Scripting:** YES
    - Reasoning: A closure that keeps what it captures is the model every JS developer already has, and it is the classic way to get a dangling pointer. One rule for all store forms is easier to learn than a list of exceptions.
    - Concern: The diagnostic must point at the capture or the `perform` site, not only at the binding, or users will not find the store.
  - **PLT:** YES
    - Reasoning: A closure that escapes is a heap cell, and its tag is the meet of the tags it captures. A handler outside ρ that receives an effect-op argument can keep it past unwind, which is the same hole Koka closes with `st<h>`. Both reduce to the one store rule, so they add no new concept.
    - Concern: the handler case needs to know where the handler is installed. If the implementation takes a shortcut, such as rejecting every tagged effect argument, it will over-reject handlers installed inside the scope.
  - **DevOps:** YES
    - Reasoning: These are real ways for a pointer to outlive its scope. The diagnostic must label the capture or the `perform` site as the store, not only the `let` binding.
    - Concern: The "escaping" test for a closure must be easy to state, or users will get errors on closures they call only inside the scope.
  - **AI/ML:** YES
    - Reasoning: Treat a closure or effect argument as a value that carries a tag, and run it through the same store and escape checks. That is one concept, not a list of special cases, and a closure called only inside the scope stays legal.
    - Concern: Handler-scope reasoning ("installed within ρ") is the least intuitive part. Diagnostics must label the `perform` or capture site as the store.
  - **Minimalism:** YES
    - Reasoning: A closure that escapes and a handler that keeps its argument are both cells with a longer life. Treating them as stores reuses the same rule with no new concept. Leaving them out would be a known hole in a rule we are writing now.
    - Concern: Effect handlers are resolved dynamically, so "handler installed inside ρ" may reject some correct code where the handler is lexically outside but only ever runs inside the scope.

- **Q5: Tag identity** (6-0, **NODE**)
  - **Systems:** NODE
    - Reasoning: when a nested scope reuses the name `as s`, a name key compares `s` with `s` and passes a dangling store. That is unsound, and node identity costs the same.
    - Concern: when two binders share a name, diagnostics must print the line as well, or the error reads "s stored into s".
  - **Web/Scripting:** NODE
    - Reasoning: Users copy and paste nested `with ffi.scope() as s` blocks. A tag keyed on the name is unsound in exactly that case. Diagnostics still print the name, plus the line number when two names are equal.
    - Concern: None significant. Hover and diagnostics must disambiguate by line when names clash.
  - **PLT:** NODE
    - Reasoning: Tags keyed by name are unsound under shadowing. `as s` nested inside `as s` compares equal names, and the stored pointer dangles.
    - Concern: diagnostics must print the name and the line whenever two live binders share a name, or the error reads "s is not an outer scope of s".
  - **DevOps:** NODE
    - Reasoning: PLT's shadowed `as s` example shows that name keys are unsound. Diagnostics and hover still print the name, plus the line when two live binders share it.
    - Concern: A message that says "`s` stored into `s`" with no line numbers is confusing, so the line must always be printed when names collide.
  - **AI/ML:** NODE
    - Reasoning: Nested `as s` blocks are a very common copy-paste shape in generated code, and name keys are unsound there. Diagnostics print `s (line N)` when two live binders share a name.
    - Concern: None material. Implementers must not let name-based lookup creep back into escape.bl.
  - **Minimalism:** NODE
    - Reasoning: PLT's nested `as s` example proves names are unsound. This is a correctness fix, not a feature. Names stay in diagnostics.
    - Concern: Diagnostics must print `s (line N)` when two live binders share a name, or the error reads "s outlives s".

- **Q6: `@ffi.struct` pointer fields** (6-0, **PTR+E0811**)
  - **Systems:** PTR+E0811
    - Reasoning: a `Ptr[T]` field lowers to a raw `T*`, which matches the C layout. A `Buf` field is a `blink_buf_t*`, so writev would send the header, and the size `_Static_assert` passes because both are pointer-sized. PLT's condition is needed: without it, a by-value IoVec could carry a Ptr out of the FFI region, around E0811.
    - Concern: the propagation has to be transitive through nested `@ffi.struct` fields. A shallow check leaves a gap.
  - **Web/Scripting:** PTR+E0811
    - Reasoning: Without `Ptr` fields no iovec can be declared. A `Buf` field is a silent ABI bug with no diagnostic. The E0811 condition keeps pointers inside FFI regions, which matches where users already expect them to live.
    - Concern: The E0811 message on a Ptr-bearing struct must name the field, or users will not understand why a plain-looking struct is restricted.
  - **PLT:** PTR+E0811
    - Reasoning: A Buf field breaks the C ABI, so Ptr fields are necessary. Without the E0811 condition, a by-value Ptr-bearing struct is a type that carries a Ptr out of the FFI region. That breaks the syntactic region invariant E0811 exists to hold. The condition makes the confinement rule compositional over type constructors.
    - Concern: the condition must also cover a Ptr-bearing struct nested inside another struct. Implementations tend to check only fields one level deep.
  - **DevOps:** PTR+E0811
    - Reasoning: A `Buf` field passes the size `_Static_assert` and has the wrong C layout, so that bug gets no diagnostic at all. The E0811 condition stops a by-value struct from carrying a Ptr out of an FFI region. Its message must name the field: "`IoVec` holds `Ptr` in field `iov_base` (line 3)".
    - Concern: E0811 on a struct type is a new error shape, and a message that does not say which field makes the struct Ptr-bearing will be hard to fix.
  - **AI/ML:** PTR+E0811
    - Reasoning: It gives one pointer type for C struct fields (no choice between `Buf` and `Ptr`), and the layout is ABI-exact. The E0811 condition extends an existing rule ("anything holding a Ptr is FFI-only"), so there is no new rule to learn.
    - Concern: The E0811 message must name the Ptr field that makes the struct Ptr-bearing, or the error looks arbitrary.
  - **Minimalism:** PTR+E0811
    - Reasoning: Without `Ptr` fields no iovec, msghdr or sigaction can be declared, so every rule in this decision would guard code nobody can write. A `Buf` field is a silent ABI bug with no diagnostic, so it goes. The E0811 condition is not a new mechanism. It applies the existing region rule to a type that carries a `Ptr`, and it closes a laundering path out of the FFI region.
    - Concern: It amends two prior decisions (ffi-struct-construction and buf-u8-runtime-representation), and the record must say so clearly or the spec will contradict itself again, as :653 and :741 do today.

- **Q7: `scope.alloc_n[T](n)` return type** (6-0, **PTR**)
  - **Systems:** PTR
    - Reasoning: `Buf` is sealed and has no `.offset` or field access. If `alloc_n` returned `Buf`, the pollfd/iovec model in ffi-struct-construction could not be written. The compiler already returns `Ptr[T]`.
    - Concern: the "only ways to obtain a `Buf`" line in §9.1.3.2 must be edited as part of this change, or the spec stays self-contradictory.
  - **Web/Scripting:** PTR
    - Reasoning: The compiler already returns `Ptr[T]`, and every `.offset(i).field.write` example depends on it. A sealed `Buf` return would make `alloc_n` useless.
    - Concern: None; fix the :741 "only ways to obtain" line.
  - **PLT:** PTR
    - Reasoning: Buf is sealed and has no methods. If `alloc_n` returned `Buf[T]^σ`, the `.offset(i).field.write(v)` model decided in ffi-struct-construction would not typecheck. `Buf` comes only from `copy_to_buf`.
    - Concern: buf-u8-runtime-representation's "only ways to obtain" line and its doc banner ("for typed regions, use scope.alloc_n") must be amended in the same change, or the spec stays self-contradictory.
  - **DevOps:** PTR
    - Reasoning: It matches the compiler and the hover output today, and `Buf` is sealed, so a `Buf` return would break `.offset(i)` and `.field.write`.
    - Concern: The :741 "only ways to obtain Buf" line must be fixed in the same edit, or the spec contradicts itself again.
  - **AI/ML:** PTR
    - Reasoning: Sealed `Buf` has no `.offset` or field access, so a `Buf` return breaks every documented alloc_n example. `Ptr[T]` matches the compiler and gives AI one answer.
    - Concern: The two ways to obtain memory (`alloc_n` gives `Ptr`, `copy_to_buf` gives `Buf`) must be stated together in one place in the spec.
  - **Minimalism:** PTR
    - Reasoning: `Buf` is sealed with no methods, so a `Buf` return makes `.offset(i)` and `.field.write` impossible and breaks the spec's own pollfd example. The compiler already returns `Ptr[T]`. Fix :741 so `Buf` comes only from `copy_to_buf`.
    - Concern: None of substance. The risk is only a missed prose site that still says `Buf[T]^σ` for `alloc_n`.

- **Q8: `^σ` is spec meta-notation only** (6-0, **YES**)
  - **Systems:** YES
    - Reasoning: `^` stays XOR in the lexer, and no parser fork is needed.
    - Concern: the LSP hover banner in §9.1.3.2 still prints `Buf[T]^σ`, and users may try to type what they see.
  - **Web/Scripting:** YES
    - Reasoning: One sentence prevents users and AI from trying to write it.
    - Concern: Stale `^σ` prose elsewhere in the spec still misleads unless it is swept.
  - **PLT:** YES
    - Reasoning: The judgement `e : τ @ ρ` is a fact of the typing rules, not a source type former, and the spec must say so. Otherwise a later reader treats prose `^σ` as grammar.
    - Concern: none, provided every `^σ` in the prose points to the sentence.
  - **DevOps:** YES
    - Reasoning: One sentence prevents users and AI from trying to write it. Hover and errors print `(scope: outer)`, never `^σ`.
    - Concern: Old spec examples with `^σ` may still be copied into code, so the parser error on a `^` after a type should hint at this rule.
  - **AI/ML:** YES
    - Reasoning: If the spec's `^σ` looks like syntax, AI will generate it. One sentence prevents that.
    - Concern: Prose examples that still show `Ptr[T]^σ` inside code fences will get copied anyway. Keep it out of fenced Blink code.
  - **Minimalism:** YES
    - Reasoning: One sentence stops the next reader from filing this same ticket again. `^` stays XOR.
    - Concern: LSP hover or `blink doc` may still print `^σ` (the doc banner in §9.1.3.2 does), and users will try to type it. The banner should use "(scope: name)" wording.

- **Q9: Wording of `E0601 (tag-mismatch)`** (6-0, **PLT-1 wording**)
  - **Systems:** PLT-1 wording (four store forms)
    - Reasoning: it lists every store form the rule checks, including the container rule from Q2. My shorter SYS-1 wording leaves out the call-site and effect forms that I am voting for.
    - Concern: the explain page needs one example per form, or the call-site form will read as a compiler bug.
  - **Web/Scripting:** PLT-1 wording (four store forms)
    - Reasoning: Listing the four forms gives `blink explain E0601` one example per form, which is how people actually learn an error. An abstract "stored into a cell" line makes users guess what counts as a cell.
    - Concern: A list can read as closed; the text must say these are all the store forms and not examples.
  - **PLT:** PLT-1 wording (four store forms)
    - Reasoning: The definition must list every place a store can happen: write, escaping capture, effect argument, and call beside a pointer-holding argument. If it lists only explicit writes, implementers will stop there, as escape.bl did for value-escape. Both wordings state the same outlives relation; SYS's text is fine for that part.
    - Concern: the list grows as the language grows. The spec should call it exhaustive and require that any new way to store a value adds a row.
  - **DevOps:** PLT-1 wording (four store forms)
    - Reasoning: The `blink explain E0601` page needs one example per form, and PLT's list gives that structure directly. SYS's wording is shorter but hides the call and capture forms.
    - Concern: A long definition line may be hard to read, so the explain page should carry the examples and the definition should stay short.
  - **AI/ML:** PLT-1 wording (four store forms)
    - Reasoning: An explicit list of the four store forms can be learned and checked from the spec alone. "Stored into a cell" leaves captures, effect args and container calls implicit.
    - Concern: The list must be closed and exhaustive, or readers will assume unlisted forms are legal.
  - **Minimalism:** PLT-1 wording (four store forms)
    - Reasoning: SYS's shorter text leaves open whether a call beside a pointer-holding argument, a capture or an effect argument is a "store". An error definition must be closed and complete, so implementers and `blink explain` can enumerate it. Listing the forms also caps the set (see my Q1 concern).
    - Concern: A fifth store form found later will need a spec edit, which is the right cost but will be tempting to skip.

- **Q10: C-side retention is out of scope** (6-0, **YES**)
  - **Systems:** YES
    - Reasoning: `aio_write`, io_uring and `setvbuf` keep a pointer after they return, and no inferred rule on the Blink side can see that. The spec must say so, so that "tag-mismatch passed" is not read as "this pointer is safe".
    - Concern: users will still assume the check covers this case, unless `blink audit` lists every `@ffi` fn that takes a Ptr.
  - **Web/Scripting:** YES
    - Reasoning: Being honest about what the check covers stops people from filing "why didn't this catch my aio_write crash" bugs. Saying it is out of scope and pointing to `blink audit` is the right expectation to set.
    - Concern: Users may still assume full coverage, so the curated `std.libc` docs for such calls need explicit warnings.
  - **PLT:** YES
    - Reasoning: A soundness claim must state what it assumes. The type system sees only Blink-side flows, so an FFI callee that keeps a pointer past return is part of the trust base, the same as a `@trusted` body. Stating that boundary is more honest than implying full coverage.
    - Concern: users may read "tag-mismatch passed" as "no use-after-free". `blink audit` should list `@ffi` fns that take a Ptr, as DEVOPS suggested, so the trust base is visible.
  - **DevOps:** YES
    - Reasoning: No inferred rule can see what C does after a call returns, so the spec should say so and not imply a guarantee. `blink audit` should list `@ffi` fns that take a Ptr so reviewers can find them.
    - Concern: Users may read a clean compile as "pointer-safe" for `aio_write`-style calls, so the E0601 explain text should state this limit.
  - **AI/ML:** YES
    - Reasoning: Stating the boundary stops both humans and AI from assuming the check covers `aio_write` or `io_uring`. An honest limit is easier to reason about than an implied guarantee.
    - Concern: Users may still over-trust a clean build. `blink audit` should list `@ffi` fns that take a Ptr.
  - **Minimalism:** YES
    - Reasoning: SYS is right that `aio_write`, `io_uring` and `setvbuf` defeat any Blink-side inference, and my Phase A claim "C only reads the addresses during the call" was too broad. Stating the limit is cheaper and more honest than a new annotation to describe C behavior. This is exactly what `@trusted` and audit exist for.
    - Concern: Users will read "E0601 checks tag-mismatch" as a full guarantee. The spec text and `blink explain E0601` must state the limit plainly.

### Final Spec

Governing text: [§9.1.1 *Scope tags*](../sections/07_trust_modules_metadata.md), plus the `@ffi.struct` field list and §9.1.3.2 amendments.

```blink
@ffi.struct(header = "sys/uio.h", name = "iovec")
pub type IoVec {
    iov_base: Ptr[U8],
    iov_len: U64,
}

@trusted(audit: "NET-012")
fn set_iov(iov: Ptr[IoVec], buf: Ptr[U8], len: U64) {
    iov.iov_base.write(buf)   // OK here: `iov` and `buf` share the caller's tag
    iov.iov_len.write(len)
}

fn send_two(fd: Int) ! IO {
    with ffi.scope() as outer {
        let iov = outer.alloc_n[IoVec](2)
        with ffi.scope() as inner {
            let buf = inner.alloc_n[U8](64)
            set_iov(iov, buf, 64)   // error[E0601] tag-mismatch: `buf` does not outlive `iov`
        }
        c_writev(fd, iov, 2)
    }
}
```

- No surface σ. `Ptr[T]^σ` / `Buf[T]^σ` are spec meta-notation; `^` stays XOR. Hover prints `(scope: outer)`.
- Tags are inferred: `s.alloc*` / `s.cstr` / `copy_to_buf` originate a tag; `take`, `alloc_ptr`, `null_ptr` give unscoped; projections inherit; a call result gets the innermost tag of its pointer-bearing arguments.
- A tag is the scope binder node, not its name. Same-named live binders print as `s (line N)`.
- `tag-mismatch`: a tagged value stored into a cell whose scope it does not enclose. The store forms are closed and exhaustive: write, escaping capture, effect argument, call beside a pointer-holding argument. A new way to store a value needs a new row.
- Inside an `@trusted` body all pointer-bearing parameters share the caller's tag; `blink audit` lists parameter-into-parameter stores as `ptr-store-param`. This is sound only together with the call-site rule.
- `@ffi.struct` accepts `Ptr[T]` fields and rejects `Buf` fields (`E0822`). A struct with a `Ptr` field at any depth is subject to E0811, and the error names the field.
- `scope.alloc_n[T](n)` returns `Ptr[T]`. `libc.copy_to_buf` is the only source of a `Buf`.
- A C function that keeps a pointer after it returns is outside the check and belongs to the audited trust base.

**Spec-writer notes (derived, not separately voted):** to make the voted rules total, the spec text defines *pointer-bearing* types (anything containing `Ptr`/`Buf`, including through `@ffi.struct` fields), counts `List`/`Map`/`Set` with pointer-bearing elements as pointer-holding parameters and as cells, counts `let mut` assignment as a write, gives struct/tuple/`Some`/`Ok`/`Err` values the innermost tag of their parts, counts `?` as a value-escape path, tags a handler cell by the scope around its install site, and gives a pointer parameter of a closure literal (the `Bytes.with_ptr` shape) a fresh tag whose block is the closure body. These follow from the Q1 and Q9 rules applied to the rest of the type system.

