[< All Decisions](../DECISIONS.md)

# `@ffi` Targets a Module-Level Function Only — Design Rationale

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds. Ticket IDs in the quoted text are replaced with `[ticket]`.

#### Phase A — Independent proposals

- **Systems:** (excerpt, section `G7 ([ticket]) `@ffi` on a trait impl method`)

> Fact: the ticket's `impl Tr for Foo { @ffi("labs") ... fn m(self) -> Int ! () }` passes check
> today (probe g7c.bl, exit 0) and the build fails in C. Blink has no inherent methods
> (03c_protocols.md:992), so that sub-question is moot. A type-scoped `@ffi fn Foo.abs(x: Int)` with
> no body does not parse today (`expected (, got .`); I did not separate whether that is the `@ffi`
> or the bodyless form.
>
> What the hardware sees: `self` is a Blink struct by value; a C symbol takes C types. To make P-B
> work we would need a receiver mapping rule, an `@ffi.struct` requirement on the receiver type, a
> per-receiver wrapper and a bodyless method form. The wrapper P-A asks the user to write is one line
> and gcc -O2 inlines it, so P-A costs nothing at run time.
>
> **G7-P1 (preferred): illegal on any trait method (impl or trait declaration); legal on a
> type-scoped fn.** `@ffi` on a method in an `impl` block or in a `trait` body is new code
> `FfiOnMethod` at the `@ffi` line, in `blink check`. Help: declare a free `@ffi fn` and call it from
> the method. E0803's "directly implement" clause then never fires, so the panel should fold it into
> the new code (E0803 keeps the contract-on-`@ffi fn` part). A type-scoped fn `fn T.name` has no
> receiver and its params map one to one, so `@ffi` on it is legal (the annotation table's `fn` row
> covers it).
>
> ```blink
> trait Tr { fn m(self) -> Int }
> type Foo { a: Int }
>
> @ffi("labs")
> @trusted(audit: "LIBC-LABS")
> fn c_abs(x: Int) -> Int ! ()
>
> impl Tr for Foo {
>     fn m(self) -> Int { c_abs(self.a) }    // OK: the wrapper implements the method
> }
>
> impl Tr for Foo {
>     @ffi("labs")                           // error[FfiOnMethod] at `@ffi`
>     @trusted(audit: "LIBC-LABS")
>     fn m(self) -> Int ! ()
> }
> ```
>
> Tradeoff: one mapping rule (Blink params = C params) stays true for every `@ffi`. A trait method's
> row and contract belong to the trait; a foreign symbol has neither, so the wrapper is where the
> claim about C and the trait's promise meet, and `blink audit` sees one `@ffi` site.
>
> **G7-P2: legal; the receiver crosses as the first C argument (needs `@ffi.struct` receiver).**
> Adds a receiver ABI rule and a bodyless method form for a gain of one line. Rejected.
>
> Cross-language: Rust `extern "C"` fns cannot be trait methods; you write `impl Tr for Foo { fn
> m(&self) -> i32 { unsafe { labs(self.a) } } }`. Same as P1.

- **Web/Scripting:** (excerpt, section `G7 ([ticket]): `@ffi` on an impl method`)

> ### G7-P1 (PREFERRED, option A): `@ffi` goes on a top-level `fn` only
>
> - `@ffi` on any method (trait impl, inherent impl, `mut self` or not) and on a type-scoped fn in
>   an impl block is a new error, **FfiOnMethod**, at the `@ffi` attribute, in `blink check`.
>   Help: bind the C function as a top-level `@ffi` fn and call it from the method.
> - E0803's second clause (an `@ffi` fn implementing a trait method with a contract) becomes a
>   case of this one; E0803 keeps only "no contracts on an `@ffi` fn".
>
> ```blink
> trait Tr { fn m(self) -> Int }
> type Foo { a: Int }
>
> impl Tr for Foo {
>     @ffi("labs")                          // error[FfiOnMethod]: `@ffi` binds a top-level fn
>     @trusted(audit: "LIBC-LABS")
>     fn m(self) -> Int ! ()
> }
>
> @ffi("labs")
> @trusted(audit: "LIBC-LABS")
> fn labs(x: Int) -> Int ! ()
>
> impl Tr for Foo {
>     fn m(self) -> Int { labs(self.a) }    // OK: a wrapper implements the method
> }
> ```
>
> Tradeoffs: the annotation table already says `@ffi` targets `fn`; P1 makes the compiler agree.
> "How does `self` reach C?" would be a permanent FAQ under B, and the answer differs per receiver
> type. The wrapper is one line and is where the receiver-to-C mapping belongs, in plain Blink.
>
> Cross-language: Rust `extern` fns are free items; Python ctypes binds module-level functions;
> Kotlin/JNI `external` methods exist but are a well-known pain point.
>
> ### G7-P2 (option B): legal, receiver passed as the first C argument
>
> Needs rules for struct receivers, `mut self`, generic impls and empty bodies. A lot of spec for
> saving one line. Rejected.

- **PLT:** (excerpt, section `G7. Is @ffi on an impl method legal?`)

> An `@ffi` fn is a claim that a C symbol has the given C signature. A method has a receiver whose
> type is `Self`; in `impl[T] Tr for Box[T]` it is generic, and no single C symbol can stand for
> every instance. Defining how a receiver crosses the C boundary is a new ABI rule for a case that a
> one-line wrapper already covers.
>
> ### G7-P1 (preferred): @ffi targets only a module-level fn
>
> - `@ffi` on any fn inside an `impl` block (a trait impl method, an inherent method, a type-scoped
>   fn with no receiver) is an error at the `@ffi`, in check. New code: `FfiOnMethod` (E08xx). The
>   help: "declare the @ffi fn at module level and call it from the method".
> - E0803 then needs no trait clause: no `@ffi` fn can implement a trait method at all. Its second
>   half and 03b:408 become "a trait method is implemented by a wrapper"; E0803 keeps only "no
>   contract on an @ffi fn".
>
> ```blink
> trait Tr { fn m(self) -> Int }
> type Foo { a: Int }
>
> @ffi("labs", header: "stdlib.h")
> @trusted(audit: "LIBC-LABS")
> fn c_labs(x: Int) -> Int ! ()
>
> impl Tr for Foo {
>     fn m(self) -> Int { c_labs(self.a) }     // OK: a wrapper implements the method
> }
>
> impl Foo {
>     @ffi("labs")                             // error[FfiOnMethod]: @ffi targets a module-level fn
>     @trusted(audit: "LIBC-LABS")
>     fn abs_of(x: Int) -> Int ! ()
> }
> ```
>
> Tradeoffs: the annotation table (07, §11.1) is then right as written; one target, no receiver ABI,
> no generic-impl question, no empty-body rule for methods. The cost: one wrapper line per method.
>
> ### G7-P2: legal, with a receiver rule
>
> `self` is the first C argument and must meet *Signature Types* (an `@ffi.struct` by value); the
> impl must not be generic; a type-scoped fn binds as a free fn. Rejected: three new rules and a
> generic-impl exclusion for no new expressive power. A trait impl through @ffi also bypasses the
> trait's default-body and contract guarantees that the wrapper keeps visible.
>
> Cross-language: Rust `extern "C"` blocks hold only free functions; a trait impl calls them.
> Haskell FFI imports are top-level only. OCaml `external` is a value declaration at module level.

- **DevOps:** (excerpt, section `G7 ([ticket]) `@ffi` on a trait impl method`)

> **G7-P1 (preferred): illegal. `@ffi` on any method, in an impl (trait or inherent) or a trait,
> and on a type-scoped fn, is E1110 UnexpectedAnnotation: the 11.1 Target column says `fn`, and
> rows that allow methods list `trait method` apart.**
>
> ```blink
> impl Tr for Foo {
>     @ffi("labs")                        // error[E1110] at `@ffi`
>     @trusted(audit: "LIBC-LABS")
>     fn m(self) -> Int ! ()
> }
>
> @ffi("labs")                            // OK: a free fn binds the symbol
> @trusted(audit: "LIBC-LABS")
> fn c_labs(x: Int) -> Int ! ()
>
> impl Tr for Foo {
>     fn m(self) -> Int { c_labs(self.a) }   // the method says which value reaches C
> }
> ```
> ```
> error[E1110]: `@ffi` cannot be used on a method
>   = help: bind the symbol with a free `@ffi fn`, and call it from the method
> ```
> No new code: E1110 already is "annotation on a target its row does not list". E0803's second
> clause ("may not directly implement a trait method that has a contract") becomes unreachable,
> and the writer should cut it so the catalog does not suggest the form is legal.
>
> Tradeoffs: the wrapper is two lines and makes the receiver-to-C mapping explicit, which is what
> `blink audit` and a reviewer need to see. B (legal) needs new rules for which params cross,
> what happens to `self` of a struct type, and an empty-body rule for methods; each new rule is a
> new diagnostic and a new way to get an ICE. No user benefit beyond two saved lines.
>
> **G7-P2 (B, legal for a non-struct receiver only).** Against: a rule that depends on the
> receiver's type gives an error that moves when the type changes.
>
> Cross-language: Rust `extern "C"` items are free fns only; a method wraps them. Same in Swift
> and Go (cgo calls in methods are explicit `C.f(...)` calls).

- **AI/ML:** (excerpt, section `G7: @ffi on a method`)

> ### G7-P1 (PREFERRED): illegal on any method; new code at check
>
> `@ffi` targets a free fn only. On a trait impl method, an inherent impl method, or a type-scoped
> fn it is a new error, `FfiOnMethod`, at the `@ffi` line, in check. Help: bind a free `@ffi` fn and
> call it from the method. E0803's "an @ffi fn may not directly implement a trait method that has a
> contract" clause then cannot fire and is removed; the contract half stays.
>
> ```blink
> @ffi("labs")
> @trusted(audit: "LIBC-LABS")
> fn c_labs(x: Int) -> Int ! ()                   // OK: free fn
>
> trait Tr { fn m(self) -> Int }
> type Foo { a: Int }
> impl Tr for Foo {
>     fn m(self) -> Int { c_labs(self.a) }        // OK: wrapper
> }
>
> impl Tr for Foo {
>     @ffi("labs")                                // error[FfiOnMethod]: `@ffi` binds a free fn, not a method
>     @trusted(audit: "LIBC-LABS")
>     fn m(self) -> Int ! ()
> }
> ```
>
> Tradeoffs (AI): option B needs a model to learn which params reach C (the receiver? a field?),
> an empty-body rule for methods, and per-receiver wrappers; three decision points for a form a
> wrapper does in one line. The wrapper is also where `self.a` becomes a C-shaped argument, which
> the Signature Types rules already govern. One target, one rule, matches the 11.1 table.
>
> Cross-language: Rust `extern "C"` items are free fns; a trait impl calls them. Swift and Go
> (cgo) are the same.
>
> ### G7-P2: legal, receiver not passed
>
> `self` is dropped and the remaining params go to C. Surprising; a model will assume `self` is
> passed. Rejected.

- **Minimalism:** (excerpt, section `G7 ([ticket]) @ffi on an impl method`)

> ### G7-P1 (PREFERRED): illegal; E1110 UnexpectedAnnotation, and delete E0803's trait clause
>
> - `@ffi` targets a `fn` that is not a method: a top-level fn or a type-scoped fn
>   (`fn Foo.make(...)`, which has no receiver). On a method in an `impl` (trait or other) or a
>   trait, it is E1110 UnexpectedAnnotation (07:4842 rule 2: a target the row does not list), in
>   check, at the annotation. The Target cell of the `@ffi` row says so. No new code.
> - E0803's second clause ("an @ffi fn may not directly implement a trait method that has a
>   contract") can no longer happen. Delete it (03b:408 and the catalog row). Subtraction.
>
> ```blink
> trait Tr { fn m(self) -> Int }
> type Foo { a: Int }
>
> @ffi("labs")
> @trusted(audit: "LIBC-LABS")
> fn c_labs(x: Int) -> Int ! () {}                 // OK: a top-level fn
>
> impl Tr for Foo {
>     fn m(self) -> Int { c_labs(self.a) }         // OK: a wrapper implements the method
> }
>
> impl Tr for Foo {
>     @ffi("labs")                                 // error[UnexpectedAnnotation] (E1110): `@ffi` does not target a method
>     @trusted(audit: "LIBC-LABS")
>     fn m(self) -> Int ! () {}
> }
> ```
>
> Tradeoffs: option B would need rules for how a receiver crosses to C, which params reach the
> symbol, the empty body of a method, and a wrapper per receiver type: four new rules for a
> one-line wrapper that the user can write. The wrapper also is the one place a contract or a
> conversion lives, so FFI stays at the module edge where `blink audit` looks.
>
> Cross-language: Rust `extern` fns are free fns only; a trait impl calls them. Go cgo: same.

#### Phase B — Debate highlights

- **Systems:** (excerpt)

> ## G7: change on both variations.
>
> - Scope: I move to illegal for a type-scoped fn too (web, aiml, devops, plt). It has no receiver
>   ABI problem, but the form does not parse today, nobody needs it, and the wrapper costs nothing
>   at -O2. One rule: `@ffi` targets a module-level fn.
> - Code: I move to E1110 UnexpectedAnnotation (devops, min). The rule is "an annotation outside
>   its §11.1 target", which is what E1110 is; it already covers `@ffi.struct` on an alias. The
>   help names the free `@ffi fn` + wrapper. A new code per misplaced annotation is surface for no
>   gain.

- **Web/Scripting:** (excerpt)

> ## G7: no change on scope. Any `@ffi` inside an `impl` or `trait` block is illegal, including a fn with no receiver. On the code: I accept E1110 UnexpectedAnnotation in place of a new FfiOnMethod if its help names the fix (a module-level `@ffi` fn and a wrapper method).
>
> - Against allowing receiverless fns: the rule "`@ffi` lives at module level" fits in one sentence. Type-scoped `fn Foo.abs` does not parse today, so nothing depends on it. If the panel wants namespaced foreign fns later, it is a new feature with its own vote.
>
> ready to vote

- **PLT:** (excerpt)

> ## G7: illegal on a method; code E1110 (change from FfiOnMethod)
>
> - Code: E1110 UnexpectedAnnotation already means "an annotation in an unsupported position".
>   That is exactly this error. A new code adds nothing to the type theory. I change to E1110.
> - A fn with no receiver: I vote illegal inside an `impl` block, because then one target rule
>   holds: `@ffi` goes on a module-level `fn` only. I see no soundness issue with a no-receiver
>   form (it has no receiver ABI), so I do not block "legal". Fact (sys): `fn Foo.abs(...)` with
>   `@ffi` does not parse today, so "legal" would need a grammar addition. YAGNI.
>
> ready to vote

- **DevOps:** (excerpt)

> ## G7: change of code. I take the new `FfiOnMethod` (majority) over E1110. A dedicated code gets its own
> `--explain` page and a fixed help ("bind the symbol with a free `@ffi fn`, call it from the method").
> E1110's help is per row, which is weaker. Scope: illegal on any fn inside an `impl` or a trait, with or
> without a receiver, and on a type-scoped `fn Foo.make`. The rule is "`@ffi` targets a module-level
> free fn". That rule is syntactic, so the LSP can flag it on the line as you type. A receiver-based rule
> needs the type. sys's probe: `fn Foo.abs` with no body does not parse today, so no user code breaks.
>
> Ready to vote.

- **AI/ML:** (excerpt)

> ## G7: no change on scope; CHANGED on the code: E1110 UnexpectedAnnotation
>
> - Code: switch to E1110. Its row is "annotation used in unsupported position" tied to the
>   §11.1 table, and G7's ground is that table. One code for "this annotation does not go here"
>   is easier to learn than one code per annotation and target. The specific help ("bind a
>   module-level `@ffi` fn and call it from the method") carries the useful part.
> - Scope: illegal on every fn inside an `impl` or `trait` and on a type-scoped `fn T.name`, with
>   or without a receiver. One rule: `@ffi` goes on a module-level fn. Against the sys/min carve-out
>   for `fn T.name`: it does not parse today, so no user code depends on it, and it adds a
>   "receiver or not" decision point to save one wrapper line.
>
> ready to vote

- **Minimalism:** (excerpt)

> ## G7: CHANGED scope. Code: E1110 UnexpectedAnnotation.
>
> Scope: `@ffi` targets a module-level fn only. Any fn in an impl or trait, and a type-scoped
> `fn Foo.make` too, is the error. I drop my Phase A exception for type-scoped fns: it does not
> parse today, nobody needs it (a module-level binding plus a one-line `fn Foo.make` wrapper
> does it), and "module-level fn" is the shortest Target cell.
>
> Code: E1110 already is "an annotation on a target its row does not list". A new `FfiOnMethod`
> code duplicates that row for one annotation. If the panel wants a specific message, give E1110
> an `@ffi` help line ("bind a module-level fn and call it from the method"). Weak preference;
> I will not block on the code.
>
> ready to vote

#### Phase C — Final vote

The first question was settled in round 1: all six panelists chose "`@ffi` targets a module-level fn only", with E0803's "directly implement a trait method" clause removed.

- **G7-Q1: which code** (6-0, E1110 `UnexpectedAnnotation`, with a help that names the module-level `@ffi fn` and a wrapper; the other option was a new code `FfiOnMethod`)

- **Systems:**

> ## G7-Q1: E1110
> Reasoning: the rule is "an annotation outside its §11.1 target", which is what E1110 is, and it already covers `@ffi.struct` on an alias. A help line naming the module-level `@ffi fn` plus a wrapper carries the fix; the wrapper is free at -O2.
> Concern: E1110's per-row help must be specific for `@ffi`, or the fix is lost in a generic message.

- **Web/Scripting:**

> ## G7-Q1: E1110
> Reasoning: the error is "this annotation does not go here", which is what E1110 means. A specific help line ("bind a module-level `@ffi` fn and call it from the method") carries the useful part. Fewer codes to learn.
> Concern: E1110's generic message may read as a parser complaint; the `@ffi` help line must be specific, or users will not find the wrapper pattern.

- **PLT:**

> ## G7-Q1: E1110
> Reasoning: E1110 already means "an annotation in an unsupported position", and this is exactly that. A new code adds no distinction that the type theory needs, and the per-row help can name the module-level `@ffi fn` plus a wrapper.
> Concern: if E1110's help stays generic, users get a weaker message than a dedicated code would give. The writer must give this case its own help line.

- **DevOps:**

> ## G7-Q1: E1110
> Reasoning: I change from NEW. E1110 already is "an annotation on a target its row does not list", and it covers `@ffi.struct` on an alias, so a new code repeats a row. My want was a fixed, specific help, and E1110 can carry an `@ffi` help line ("bind a module-level `@ffi fn` and call it from the method").
> Concern: if the `@ffi`-specific help line is not specified, E1110 prints only the generic target list and the user does not learn the wrapper fix.

- **AI/ML:**

> ## G7-Q1: E1110
> Reasoning: E1110 already means "an annotation outside its §11.1 target", which is exactly this error; one code for every misplaced annotation is easier to learn than one per annotation. A specific `@ffi` help line (module-level `@ffi fn` + wrapper method) carries the fix.
> Concern: E1110's help must be per annotation, or the model gets a generic message with no repair.

- **Minimalism:**

> ## G7-Q1: E1110
> Reasoning: E1110 already means "an annotation on a target its §11.1 row does not list", and it already covers `@ffi.struct` on an alias. A code per misplaced annotation is surface for no gain; the `@ffi`-specific help carries the fix.
> Concern: E1110's `--explain` page must show the `@ffi` wrapper fix, or devops' point (a weaker help) comes true.

### Final Spec

```blink
trait Tr { fn m(self) -> Int }
type Foo { a: Int }

@ffi("c", "labs")
@trusted(audit: "LIBC-LABS")
fn c_labs(x: Int) -> Int ! ()                // OK: a module-level `@ffi` fn

impl Tr for Foo {
    fn m(self) -> Int { c_labs(self.a) }     // OK: the method is a wrapper
}

impl Tr for Foo {
    @ffi("c", "labs")                        // error[E1110] at the `@ffi`
    @trusted(audit: "LIBC-LABS")
    fn m(self) -> Int ! ()
}
```

- `@ffi` targets a module-level fn only. An `@ffi` on any fn in an `impl` or `trait` block, with or without a receiver, and on a type-scoped `fn T.name`, is E1110 `UnexpectedAnnotation` at the `@ffi`, in `blink check`.
- The help says to declare a module-level `@ffi fn` and call it from the method.
- The §11.1 annotation table changes the Target cell of `@ffi`.
- E0803 loses its clause about an `@ffi` fn that directly implements a trait method with a contract. E0803 keeps "no contract on an `@ffi` fn".
- Spec text: §9.1 *`@ffi` Binds a Module-Level Function*, §11.1, §3b.2 *`@ffi`*, E1110 and E0803 in ERROR_CATALOG.md.
