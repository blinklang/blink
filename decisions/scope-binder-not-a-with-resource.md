[< All Decisions](../DECISIONS.md)

# A Scope Binder Is Not a With Resource — Design Rationale

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds. Ticket IDs in the quoted text are replaced with `[ticket]`.

#### Phase A — Independent proposals

- **Systems:** (excerpt, section `G2 ([ticket]): `with s as t` where `s` is a scope binder`)

>
> **Facts today.** The MVCE is check-clean and dumps core: the inner block frees the arena of `s`, then `pp.deref()` reads freed memory. Also check-clean today: `with (s) as t` and a closure `fn() { with s as u { ... } }` that captures `s` (g2b). Two nested `with ffi.scope()` blocks are legal and give two tags.
>
> ### G2-P1 (preferred): a scope binder may occur only as the receiver of a scope method; any other occurrence is E0819
>
> The binder of `with ffi.scope() as s` is the only name for that arena. Its legal uses are `s.alloc[T]()`, `s.alloc_n[T](n)`, `s.cstr(x)`, `s.take(p)`. Every other occurrence of `s` is E0819 FfiScopeNotWithResource at that occurrence, in check: as the resource of another `with` (bare or in parentheses), as an argument, in a `let`, a return, a field, or a capture into a closure. A closure that only calls `s.alloc` inside the block can stay legal if the scope-tag rules treat the capture as tag `s` (then an escape is E0601); if that is too much, E0819 on capture is the simple form.
>
> ```blink
> fn main() {
>     with ffi.scope() as s {
>         let pp = s.alloc[Ptr[Int]]()               // OK
>         with s as t {                              // error[E0819] at `s`: `s` is already the resource
>             let c = t.alloc[Int]()                 //   of the `with` at line 2
>         }                                          // help: use `s` here, or open a new scope:
>                                                    //   `with ffi.scope() as t { ... }`
>         with ffi.scope() as t {                    // OK: a second arena, its own tag
>             let c = t.alloc[Int]()
>             c.write(9)
>         }
>     }
> }
> ```
>
> Tradeoffs (systems): no new runtime state, no reference count, no double free. The rule is decidable from syntax plus the binder's type. The tag rule "one block, one tag, one free" stays true. The help is a suggestion, not a fix: both edits change when memory is freed.
>
> ### G2-P2: `with s as t` makes a child arena (rejected)
>
> The inner block frees only what `t` allocated. This is exactly `with ffi.scope() as t`, so it adds a second spelling, a parent link in the arena, and a tag whose parent is a binder rather than a block. No capability gained.
>
> ### G2-P3: `with s as t` is an alias with no cleanup (rejected)
>
> `t` is `s`; the inner exit frees nothing. Again no capability over writing `s`, and a `with` that runs no cleanup breaks what every other `with` means.
>
> Cross-language: Zig passes `std.mem.Allocator` by value and an `ArenaAllocator.deinit()` twice is a double free you find at run time; Rust's `bumpalo` uses a borrow on the arena so the second owner cannot free it. P1 gives the Rust result with a syntactic rule.

- **Web/Scripting:** (excerpt, section `G2 — `with s as t` where `s` is an `ffi.scope` binder`)

>
> **Facts today.** The MVCE passes check and dumps core. Two nested `with ffi.scope()` blocks work
> (probe g2.bl prints `1`).
>
> ### G2-P1 (preferred): the resource of a scope `with` must be the call `ffi.scope()`; a binder is never a resource
>
> A scope binder may appear only as the receiver of its methods (`s.alloc`, `s.alloc_n`, `s.cstr`,
> `s.take`), in the block body or in a closure literal inside it (the scope-tag rules cover closures).
> `with s as t`, `with (s) as t`, and any other spelling that hands the binder to a second `with` are
> E0819 FfiScopeNotWithResource at the binder, in check. Help: "open a new scope:
> `with ffi.scope() as t { ... }`". A nested fn cannot reach `s` (it cannot be passed), so no new
> case there. Two nested `ffi.scope()` blocks stay legal, each with its own tag.
>
> ```blink
> fn main() {
>     with ffi.scope() as s {
>         let pp = s.alloc[Ptr[Int]]()
>         with s as t {                       // error[E0819]: `s` is a scope binder, not a new scope
>             let c = t.alloc[Int]()          // help: `with ffi.scope() as t { ... }`
>         }
>     }
>     with ffi.scope() as a {
>         let pa = a.alloc[Int]()
>         with ffi.scope() as b {             // OK: two scopes, two tags
>             let pb = b.alloc[Int]()
>             pb.write(1)
>             pa.write(pb.deref())
>         }
>         io.println("{pa.deref()}")          // prints 1
>     }
> }
> ```
>
> Tradeoffs. For: one way to open a scope; the "one scope per with" model in *Scope tags* stays
> true; the crash becomes a check error, so the Promise holds. Against: none for a user I can see;
> nobody needs an alias for a scope they already hold.
>
> Cross-language: Python `with f as g` on an already-entered context manager is legal and a common
> source of double-close bugs; Rust's borrow of an arena never re-enters it. Blink should not copy
> Python here.
>
> ### G2-P2: `with s as t` opens a child scope
>
> `t` gets a fresh tag inside `s`; the inner exit frees only `t`'s allocations. Works, but it is a
> second spelling of `with ffi.scope() as t`, and a reader will assume `t` is an alias of `s` (as in
> Python). That reading is wrong and leads to "why was my pointer freed" questions. Not preferred.

- **PLT:** (excerpt, section `G2: `with s as t` where `s` is an `ffi.scope` binder`)

>
> An `FfiScope` is a second-class value. Its only introduction is `with <expr> as s`, and its only elimination is a call to one of its four operations on the binder `s` (the help in b3.bl says this already). `with s as t` is an occurrence of the second class: it gives the same arena a second cleanup, which frees the outer block's memory early. The MVCE crashes at run time and check sees all of it, so allowing it breaks §6.7.1.
>
> ### G2-P1 (preferred): the binder is receiver-only; a closure that captures it carries its tag
>
> - Inside its block, the binder `s` may occur only as the receiver of `alloc`, `alloc_n`, `cstr`, `take`. Every other occurrence is E0819 at that occurrence, in check. That covers `with s as t`, `with (s) as t`, `let u = s`, `f(s)`, `return s`, `Some(s)`, and a field store. The `with s as t` report gets a help: "open a second scope: `with ffi.scope() as t { ... }`".
> - A closure literal that uses `s` as a receiver is legal. For *Scope tags*, the binder has tag `s`, so the closure has tag `s` (closure-literal row of the tag table). Capture rule 2 then makes an escape from block `s` E0601. This closes the b2.bl hole with no new rule: only one row ("the binder of `with ffi.scope() as s` has tag `s`").
> - A nested `fn` item captures nothing, so `s` is not in scope there (an unknown name, as today).
> - Two nested scopes, `with ffi.scope() as a { with ffi.scope() as b { ... } }`, stay legal. They are two tags, `a` encloses `b`.
>
> ```blink
> import blink.ffi
>
> fn main() {
>     with ffi.scope() as a {
>         let pp = a.alloc[Ptr[Int]]()
>         with ffi.scope() as b {                  // OK: a second arena, tag b
>             let c = a.alloc[Int]()               // OK: tag a, outlives b
>             c.write(9)
>             pp.write(c)
>         }
>         io.println("{pp.deref().deref()}")      // prints 9
>         let f = fn() -> Int { a.alloc[Int]().deref() }   // OK: closure has tag a
>         io.println("{f()}")                      // prints 0
>         with a as t { }                          // error[E0819] at `a`: help: `with ffi.scope() as t`
>     }
>     let mut keep = fn() -> Int { 0 }
>     with ffi.scope() as s {
>         keep = fn() -> Int { s.alloc[Int]().deref() }    // error[E0601]: closure with tag `s` stored past block `s`
>     }
> }
> ```
>
> Tradeoffs. The rule follows the type, as §9.1.1 says it must. One sentence ("receiver only") replaces the list in the E0819 row, and the scope chain stays linear, so the *Order* paragraph ("live tags form one chain") stays true. The closure case composes through the existing tag machinery and needs no new code.
>
> ### G2-P2: `with s as t` opens a child arena
>
> `t` is a new tag enclosed by `s`, and the inner exit frees only `t`'s allocations. This is sound, but it is a second spelling of `with ffi.scope() as t`, with nothing new to say. YAGNI. Reject.
>
> Cross-language: Scala 3 capture checking and Koka scoped effects treat a region handle as second-class (not storable, not returnable). Rust's `bumpalo`/`scope` APIs reach the same result through the lifetime on `&'s Scope`. A closure that borrows it gets `'s`, which is exactly the tag rule in P1.
>
> ---

- **DevOps:** (excerpt, section `G2: `with s as t` when `s` is an `ffi.scope` binder`)

>
> **Today (probed):** `with s as t` and `with (s) as u` pass check; the MVCE dumps core in run.
> `let x = s` is E0819, and its existing help says "inside the block, use `s` only as the receiver
> of its operations: `s.alloc[T]()`, `s.alloc_n[T](n)`, `s.cstr(text)`, `s.take(p)`". Two
> nested `with ffi.scope()` blocks are fine (prints 4). Second hole: a closure that names `s`,
> returned out of the `with` block, passes check and runs after the arena is freed (g2c.bl).
>
> ### G2-P1 (preferred): a binder is a receiver only; E0819 for every other position
>
> The `ffi.scope()` call is the only expression that may be a `with` resource of type `FfiScope`.
> A binder `s` may occur only as the receiver of `alloc`, `alloc_n`, `cstr`, `take`. `with s as t`,
> `with (s) as t`, `with id(s) as t` are E0819 at `s`. A closure that names `s` takes the tag of
> `s` (scope-tag table: a captured binder counts as a captured value with tag `s`), so a closure
> that escapes the block is E0601 at the escape.
>
> ```blink
> with ffi.scope() as s {
>     let p = s.alloc[Int]()                   // OK
>     with ffi.scope() as t {                  // OK: a second, inner arena
>         let q = t.alloc[Int]()
>     }
>     with s as t { }                          // error[E0819] at `s`
> }
> fn mk() -> fn() -> Int {
>     with ffi.scope() as s {
>         fn() -> Int { s.alloc[Int]().deref() }   // error[E0601]: closure holds scope `s`
>     }
> }
> ```
>
> E0819 message for `with s as t`: "`s` is already the resource of the `with` block at line N; a
> `with` resource must be a new `ffi.scope()`". Help 1 (machine-applicable): replace `with s as t`
> with `with ffi.scope() as t` (gives a real inner arena, the likely intent). Help 2: use `s`
> directly. The existing receiver-only help already teaches this rule, so the diagnostic and
> the rule agree.
>
> Tradeoffs: one position list, no new semantics, the help text already exists. Cost: none for
> users; nobody can mean "close the outer arena early".
>
> ### G2-P2: `with s as t` legal, inner block is a no-op alias
>
> `t` is an alias of `s` and the inner exit frees nothing. Tradeoff: legal code that looks like
> a nested arena and is not; LSP hover must say "alias of `s`, frees nothing". A reader (human or
> AI) who copies the pattern expects an inner free. Silent behavior beats a crash, but loses to an
> error.
>
> Cross-language: Rust's `bumpalo` or `typed_arena` has no "re-enter as a new scope" form; a
> nested scope is a new arena.

- **AI/ML:** (excerpt, section `G2 — `with s as t` where `s` is an `ffi.scope` binder`)

>
> **Facts today:** the MVCE checks clean and dumps core (ticket). `with s as t` inside a closure
> literal also checks clean.
>
> ### G2-P1 (PREFERRED): an `FfiScope` binder is not a `with` resource — E0819
>
> The resource of a `with` whose type is `FfiScope` must be an `ffi.scope()` call. Any other
> expression of type `FfiScope` there (`s`, `(s)`, `s` captured by a closure, in any nesting) is
> E0819 FfiScopeNotWithResource at that expression, in check. Two nested fresh scopes stay legal
> with two tags. The binder's only legal uses are the receivers of `alloc`, `alloc_n`, `cstr`,
> `take` (and a closure that only does those).
>
> ```blink
> fn main() ! IO {
>     with ffi.scope() as a {
>         let p = a.alloc[Int]()
>         with ffi.scope() as b {           // OK: a second arena, freed at its own exit
>             let q = b.alloc[Int]()
>             q.write(1)
>         }
>         with a as t {                     // error[E0819]: `a` is already a scope binder
>             let c = t.alloc[Int]()        //   help: allocate from `a` directly,
>         }                                 //   or open a new arena `with ffi.scope() as t`
>         p.write(2)
>     }
> }
> ```
>
> Tradeoffs: a model reading `with s as t` has three plausible readings: alias, child arena
> (Zig `ArenaAllocator` over a parent, Rust `bumpalo` scopes), or "re-enter". Each reading gives
> different free times; the wrong one is a use-after-free. A rule that removes the form removes
> the guess. Zero cost to the common pattern; the two help lines give the two correct rewrites.
> It also keeps the *Scope tags* invariant "one tag per block" without a new case.
>
> ### G2-P2: legal alias, inner exit frees nothing
>
> `t` gets the tag of `s`; the inner `with` runs no cleanup. Coherent, but it adds the only
> `with` in the language whose exit does nothing, which a model must learn as an exception. It
> also gives two spellings for "allocate from `s`".
>
> ### G2-P3: legal child arena
>
> Inner `with s as t` opens a new arena freed at its exit. This is exactly what
> `with ffi.scope() as t` already does, so it is a second spelling with a hidden meaning.
>
> ---

- **Minimalism:** (excerpt, section `G2 — `with s as t` when `s` is an `ffi.scope` binder`)

>
> Facts today: the MVCE checks clean and dumps core. Also clean in check today (probe e.bl): a closure that captures `s`, calls `s.alloc` and is pushed into a list that outlives the block, and `with (s) as t`. The closure case is the same hole by another path: it stores the scope.
>
> ### G2-P1 (PREFERRED): the resource of a scope `with` is an `ffi.scope()` call; the binder is only a receiver
>
> - The resource of a `with ... as` that gives an `FfiScope` must be the call `ffi.scope()` itself. Any other expression of type `FfiScope` there (`s`, `(s)`, a block that yields `s`) is E0819 at that expression.
> - The binder `s` may occur only as the receiver of an `FfiScope` method (`s.alloc`, `s.alloc_n`, `s.cstr`, `s.take`). A closure that names `s` is E0819 at the use of `s` (a capture stores the scope). A nested `fn` cannot see `s` anyway.
> - Two scopes stay legal: `with ffi.scope() as a { with ffi.scope() as b { ... } }` — that already gives a child arena with its own cleanup.
>
> ```blink
> import blink.ffi
>
> fn main() {
>     with ffi.scope() as a {
>         let p = a.alloc[Int]()
>         with ffi.scope() as b {           // OK: a second, inner arena
>             let q = b.alloc[Int]()
>             q.write(1)
>         }
>         with a as t {                     // error[FfiScopeNotWithResource] (E0819) at `a`
>             p.write(2)
>         }
>         let f = fn() { a.alloc[Int]() }   // error[FfiScopeNotWithResource] (E0819) at `a`
>     }
> }
> ```
>
> Tradeoffs: no new semantics. "Legal, inner block is an alias that does not clean up" invents a `with` that has no exit action; "legal, inner frees only `t`'s allocations" re-invents nested `ffi.scope()`. Both add a concept to buy nothing. The closure ban loses `xs.map(fn(x) { s.cstr(x) })`; a `for` loop does the same job, and a later batch can lift the ban if users need it (relaxing is cheap; tightening after 1.0 is not). The tag rules' "one scope per block, tags nest lexically" stays true with no edit.
>
> Cross-language: Rust's scoped-thread and arena APIs give the scope only as a borrowed handle to a closure; the handle cannot be re-scoped either.
>
> ### G2-P2: E0819 for `with s as t` only, leave closures to E0601 escape analysis
>
> Smaller rule, but the closure path stays a use-after-free that check accepts — it breaks *The Promise*. Not preferred.

#### Phase B — Debate highlights

- **Systems:** (excerpt, section `G2 variation: G2-TAG (changed from "either")`)

> TAG. A use of `s` inside a closure is still a method receiver (`s.alloc`), so the core rule
> already allows it; CAP adds a special case that bans a use the core rule allows. The escape
> hazard is the same one the tag rules already handle for captured pointers: give a closure that
> captures a scope binder the tag of that binder (one added row in the inference table, since
> `FfiScope` is not pointer-bearing today), and storing it past the block is E0601. No runtime
> cost, no new code. CAP is safe too, but it bans the useful shape (a callback that allocates into
> the caller's arena) for no gain in safety. Writer note: the tag table needs that row stated, or
> TAG is not specified.

- **Web/Scripting:** (excerpt, section `G2 variation: G2-TAG (no change)`)

> I keep TAG. `with ffi.scope() as s { let ps = names.map(fn(n) { s.cstr(n) }) ... }` is the
> natural way a JS/Python/Kotlin dev builds a `char**` argv or a list of C strings. CAP makes that
> an error and sends them to a `for` loop with a manual `push`. That costs something, and FFI users
> will hit it on their first day.
>
> Against CAP: the hole is the escape, not the capture. A closure that is called inside the block is
> safe, and the tag rules already handle "value with tag s stored past block s" as E0601. One sentence
> closes the hole: "a closure that names the binder `s` has tag `s`". After that, the stored-closure
> probes (plt/b2.bl, devops/g2c.bl, min/e.bl) are E0601 in check, so the Promise holds. min's point
> ("relaxing later is cheap") is true, but CAP blocks a common idiom to avoid one row in the tag
> table that we need anyway. Condition for my vote: the spec text must say that the binder itself
> gives a closure tag `s`. Today's row reads "the innermost tag of the values it captures", and `s`
> is not pointer-bearing, so without that sentence TAG leaves the hole open.

- **PLT:** (excerpt, section `G2 variation: G2-TAG (no change)`)

>
> Argument against G2-CAP:
> - **It is not uniform.** A closure that captures a *pointer* with tag `s` is already legal, and E0601 polices its escape (Capture rule 2). A closure that captures the *scope* has the same lifetime hazard: it is valid while block `s` is live and invalid after. CAP gives the scope a stricter rule than its own pointers, with no extra soundness. Any escape path that TAG misses is also a hole for pointer captures today, so the fix belongs in E0601, not in a special ban.
> - **It costs expressiveness for nothing.** `xs.map(fn(x) { s.cstr(x) })` and a `with_ptr(fn(p) { ... s.alloc ... })` callback are the natural shapes in FFI glue. CAP forces a manual `for` loop.
> - **TAG adds no concept.** One table row ("the binder of `with ffi.scope() as s` has tag `s`") reuses the closure-literal row and Capture rule 2. Inside the closure, `s` is still used only as a receiver, so the receiver-only rule stays as it is. `with s as u` inside a closure is still E0819 by the core rule.
>
> What it rests on: E0601 must really catch every closure escape past block `s` (return, store in an outer cell, push into an outer list, send to a handler). The probes show it does not catch them today for a captured binder, because the binder has no tag. TAG is exactly that fix. A test for each escape form should go with it.

- **DevOps:** (excerpt, section `G2 variation: G2-TAG (no change)`)

>
> New probes (probe/devops/):
> - g2f.bl: a closure that captures a scoped `p` and is returned from the block is ALREADY E0601
>   today ("Ptr from `with ffi.scope() as s` cannot escape the block", at the closure literal).
> - g2g.bl: `xs.map(fn(x) { s.cstr(x) })` inside the block passes check today.
>
> So TAG adds one fact to a rule that already works ("a captured binder counts as a value with
> tag `s`") and reuses a diagnostic that already exists and points at the right place. CAP turns
> g2g, an inline non-escaping closure, into an error. Its help ("use a `for` loop") is a rewrite
> that no fixer can apply, for code that has no hazard. A rule that rejects safe code produces a
> diagnostic that users learn to fight. CAP is simpler to state, but in practice it takes away
> `map`/`filter` with `s.cstr`, the most common FFI string pattern.
>
> Writer note: today the E0601 help says "wrap the escaping value in s.take(...)". For a closure
> that captures the binder itself, that help is wrong (`take` does not apply to a scope). That
> case must get its own help: "the closure calls `s.alloc`; `s` is freed at line N. Allocate with
> `alloc_ptr` in the closure, or call it inside the block."

- **AI/ML:** (excerpt, section `G2 variation: switch from CAP to TAG`)

> Phase A said a captured `s` is E0819. I now back **G2-TAG**.
> - A helper closure inside the block (`let mk = fn(n: Str) -> Ptr[U8] { s.cstr(n) }`) is a pattern that models and people write by habit. CAP rejects safe code, and the model then has to learn an exception: "you may call `s.alloc` in the block but not in a closure in the block".
> - TAG adds no new rule. A closure that captures `s` gets tag `s`, the same as a closure that captures a pointer from `s`. The existing E0601 rule then catches the escape. One rule ("a value tagged `s` may not outlive block `s`") is easier to learn than two rules.
> - The core stays as it is: `with s as t` and `with (s) as t` are E0819 at `s`.
> - Condition: the spec must say that the binder counts as a tagged capture in the closure-literal row of the tag table. Otherwise TAG has the hole the probes found (plt b2, devops g2c, min e).

- **Minimalism:** (excerpt, section `G2 variation: changed from G2-CAP to G2-TAG`)

> I proposed CAP. TAG is the smaller rule, so I switch. The tag table already has the row "A closure literal: the innermost tag of the values it captures" (07:~2137), and capture rule 2 (07:~2153) already makes a tagged closure that escapes its block E0601. TAG adds one row: "the binder of `with ffi.scope() as s` has tag `s`." CAP adds a new E0819 site and bans `xs.map(fn(x) { s.cstr(x) })` inside the block, which is sound code. A ban that the existing rules make unnecessary is surface that buys nothing.
> Condition: the row must say that the binder carries a tag even though `FfiScope` is not pointer-bearing. The *Pointer-bearing types* paragraph says only those values (and closures that capture them) carry a tag, so without this the closure gets no tag and the probe hole stays open. Writer note: the E0601 text must name the closure and block `s`.

#### Phase C — Final vote

- **G2-Q1: a scope binder may not be the resource of another `with`, and may be used only as the receiver of `alloc`, `alloc_n`, `cstr`, `take` (6-0, core; the other option was to reject)**

- **Systems:**

> ## G2-Q1
> **Vote:** A (core)
> **Reasoning:** `with s as t` frees the arena of `s` at the inner exit, which is a use-after-free that check sees today and does not report (the MVCE dumps core). A rule that a binder may only be a receiver costs nothing at run time and keeps "one block, one tag, one free" true. A child arena or an alias with no cleanup gives nothing that `with ffi.scope() as t` does not already give.
> **Concern:** Every E0819 site needs its own help text: for `with s as t`, "use `s`, or open a new `ffi.scope()`", not the `let` rewrite help.

- **Web/Scripting:**

> ## G2-Q1
> **Vote:** A (core)
> **Reasoning:** `with ffi.scope()` is the one way to open a scope, and a binder is never a second scope. A user who reads `with s as t` as an alias (the Python reading) would get a use-after-free. Check now catches what used to dump core.
> **Concern:** The E0819 help must say "open a new scope: `with ffi.scope() as t`". A bare "not a with resource" message will confuse users, because `s` came from a `with`.

- **PLT:**

> ## G2-Q1
> **Vote:** Core (accept)
> **Reasoning:** An `FfiScope` is second-class. `with ffi.scope() as s` is its only introduction, and a receiver call on `s` is its only elimination. `with s as t` gives the same arena a second cleanup that `blink check` can see, so allowing it breaks §6.7.1. Nested fresh scopes keep the live tags in one lexical chain.
> **Concern:** "Receiver only" must also cover an `FfiScope` reached by another path (a block that yields `s`, a call `id(s)`), not only the bare name and `(s)`.

- **DevOps:**

> ## G2-Q1
> **Vote:** A (core)
> **Reasoning:** The existing E0819 help already says to use `s` only as the receiver of its operations, so the rule and the diagnostic agree. The help offers a suggestion, `with ffi.scope() as t`, for the likely intent. It turns a crash that check passed into an error in check.
> **Concern:** The message must name the `with` at line N that already owns `s`, or a user reads E0819 ("may occur only as a with resource") as a contradiction when `s` IS written as a with resource.

- **AI/ML:**

> ## G2-Q1
> **Vote:** A
> **Reasoning:** `with s as t` has three plausible readings (alias, child arena, re-enter), and a wrong guess gives a use-after-free. Removing the form removes the guess. The help gives the two correct rewrites, and the common pattern costs nothing.
> **Concern:** The E0819 text must name the shape "already a scope binder" with its own help, not reuse the let-binding help, or the fix loop gets the wrong repair.

- **Minimalism:**

> ## G2-Q1
> **Vote:** A (core)
> **Reasoning:** The binder is receiver-only. That is the narrowest reading of "only as a `with` resource", and nested `with ffi.scope()` already gives a child arena, so `with s as t` would only be a second spelling with a broken cleanup. It needs no new semantics.
> **Concern:** The E0819 row must list the binder-reuse case explicitly, or readers will keep taking "`s` is the resource" as legal.

- **G2-Q2: a closure literal that names the binder `s` is legal and has tag `s` (6-0, TAG; the other option, CAP, was E0819 at the use of `s` in the closure)**

- **Systems:**

> ## G2-Q2
> **Vote:** TAG
> **Reasoning:** The core rule already allows the receiver use of `s` inside a closure. The hazard is the escape, and the existing closure-literal row plus Capture rule 2 (E0601) already handle that for captured pointers. One table row ("the binder of `with ffi.scope() as s` has tag `s`") closes the probe hole with no runtime cost, and it keeps `xs.map(fn(x) { s.cstr(x) })`.
> **Concern:** The fix is only as good as E0601's escape coverage (return, outer cell, outer list, handler, effect send). Each form needs a test, or the hole stays open where E0601 does not look today.

- **Web/Scripting:**

> ## G2-Q2
> **Vote:** TAG
> **Reasoning:** `names.map(fn(n) { s.cstr(n) })` is the everyday way to build C strings, and CAP would ban safe code to avoid one table row. The hazard is the escape, and E0601 already reports escapes at the closure literal.
> **Concern:** If the spec does not say plainly that the binder carries tag `s` even though `FfiScope` is not pointer-bearing, the hole stays open. The E0601 help ("wrap in `s.take`") is also wrong for a captured binder and needs its own text.

- **PLT:**

> ## G2-Q2
> **Vote:** TAG
> **Reasoning:** A captured scope has the same lifetime hazard as a captured pointer with tag `s`, so it should obey the same rule (Capture rule 2, E0601). CAP is a special case that adds no safety and bans safe code such as `xs.map(fn(x) { s.cstr(x) })`. TAG is one row in the tag table: the binder has tag `s`.
> **Concern:** TAG is only as sound as E0601's escape analysis. The tag-table row must be stated (a binder carries a tag although `FfiScope` is not pointer-bearing), with a test for each escape form: return, outer cell, outer list, handler.

- **DevOps:**

> ## G2-Q2
> **Vote:** TAG
> **Reasoning:** E0601 already catches a returned closure that captures a scoped pointer (probe g2f.bl), so TAG extends a working diagnostic by one table row. CAP would reject safe inline code such as `xs.map(fn(x) { s.cstr(x) })` with a help that no fixer can apply.
> **Concern:** Today's E0601 help, "wrap the escaping value in s.take(...)", is wrong for a closure that captures the binder. That case needs its own help, or the first fix users try fails.

- **AI/ML:**

> ## G2-Q2
> **Vote:** TAG
> **Reasoning:** `xs.map(fn(x) { s.cstr(x) })` inside the block is a habit in generated FFI code. CAP refuses it, and a model then has to learn an exception to the receiver rule. TAG reuses the one escape rule (E0601) that already polices captured pointers, so there is one rule to learn.
> **Concern:** If the tag table does not say that the binder itself carries tag `s` (`FfiScope` is not pointer-bearing), the stored-closure hole stays open and check breaks the Promise.

- **Minimalism:**

> ## G2-Q2
> **Vote:** TAG
> **Reasoning:** TAG adds one row to the tag table and reuses the closure-literal row and capture rule 2. CAP adds a new ban on sound code (`xs.map(fn(x) { s.cstr(x) })`). The smaller rule is the one that the existing machinery already enforces.
> **Concern:** The spec must say that the binder carries tag `s` even though `FfiScope` is not pointer-bearing. Without that sentence the closure gets no tag and the probe hole stays open, so every escape form needs a test.

### Final Spec

```blink
with ffi.scope() as s {
    let all = xs.map(fn(x) { s.cstr(x) })     // OK
    with ffi.scope() as inner { }              // OK, a new scope
    with s as t { }                            // error[FfiScopeNotWithResource] (E0819) at `s`
    let a = s                                  // E0819 at `s`
    keep = fn() -> Int { s.alloc[Int]().deref() }   // error[E0601] tag-mismatch (assignment)
}
```

- Only an `ffi.scope()` call may be the resource of a scope's `with`. `with s as t` and `with (s) as t` are E0819 at `s`, in `blink check`. The message names the `with` that owns `s`. The help says "open a new scope with `with ffi.scope() as t`".
- The binder may be the receiver of `alloc`, `alloc_n`, `cstr` and `take` only. Any other use is E0819 at that use: an argument, a `let`, a return, a field, a block that yields `s`, `id(s)`.
- Each E0819 site has its own help. The `let` rewrite help is never given for a binder.
- Nested `with ffi.scope()` blocks stay legal: two scopes, two tags.
- A closure that uses `s` as a receiver is legal and has tag `s`. The tag table has a row for the binder, although `FfiScope` is not pointer-bearing. A closure with tag `s` that leaves block `s` is E0601: by return, as the tail, in a store to an outer cell, in a push to an outer list (a call beside a pointer-holding argument; a `List`, `Map` or `Set` of function types is pointer-holding for such a closure), or as an effect argument.
- The E0601 help for such a closure does not say "wrap in `s.take(...)`". It gives its own text.
- Spec text: §9.1.1 *The `FfiScope` type*, *Scope tags*, *E0601 message conditions*; E0819 and E0601 in ERROR_CATALOG.md.
