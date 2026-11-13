[< All Decisions](../DECISIONS.md)

# Handler Clause Parameter Types — Design Rationale

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds. Ticket IDs in the quoted text are replaced with `[ticket]`.

#### Phase A — Independent proposals

- **Systems:** (excerpt, section `G6 ([ticket]) A handler clause with no parameter type`)

> Fact: `with handler Ee.Op { fn op(x) -> Int { x + 1 } } { ... }` is an ICE NodeCarriesNoType at
> check today (gen1 predates 542ae49b; the E0328 row does not list handler clauses).
>
> **G6-P1 (preferred): a clause is a signature; types are required.** An untyped clause parameter
> is E0328 MissingParamType at its name, in `blink check`; widen the E0328 row to name handler
> clauses. Help: write the type of the operation's parameter (machine-applicable: the compiler
> knows it from the operation, after E0549 resolution). A missing `-> T` reads as `-> ()`, so a
> clause for a non-unit operation with no result type is E0548 HandlerClauseMismatch (result type),
> as today's rule already says; its help prints the header.
>
> ```blink
> effect Ee { effect Op { fn op(x: Int) -> Int } }
>
> fn g() -> Int ! Ee.Op { ee.op(1) }
>
> fn main() ! IO {
>     with handler Ee.Op { fn op(x: Int) -> Int { x + 1 } } {   // OK
>         io.println("{g()}")
>     }
>     with handler Ee.Op { fn op(x) -> Int { x + 1 } } {        // error[MissingParamType] (E0328) at `x`
>         io.println("{g()}")
>     }
>     with handler Ee.Op { fn op(x: Int) { x + 1 } } {          // error[HandlerClauseMismatch] (E0548): result `()` vs `Int`
>         io.println("{g()}")
>     }
> }
> ```
>
> Tradeoff: no codegen difference; the clause compiles to one C function either way. P1 keeps one
> rule: an impl method implements a trait method and must write its types (E0328); a clause
> implements an operation the same way. A reader sees the ABI of the clause where it is written, and
> the checker has no inference path into handler headers (today's ICE class).
>
> **G6-P2: take the type from the operation, like a closure from an expected fn type.** Less typing,
> but a clause is not an expression with an expected type; it is matched by name to a header, so the
> "expected type" exists only after E0549 resolution. Then E0548's "a parameter type differs"
> check has nothing to compare, and a rename of the op's parameter type changes the clause silently.
>
> Cross-language: Koka and OCaml 5 handlers infer clause types (ML inference everywhere); Blink
> requires signature types everywhere, so it should here too.
>
> ---

- **Web/Scripting:** (excerpt, section `G6 ([ticket]): untyped handler clause parameters`)

> ### G6-P1 (PREFERRED, option A): a clause is a signature; untyped param is E0328 with a machine-applicable fix; an omitted result means `()`
>
> - A clause parameter with no type is E0328 MissingParamType, at the name, in `blink check`. The
>   compiler knows the operation's type, so the help writes it and is machine-applicable. That
>   param gets no E0548 as well.
> - No `-> T` on a clause means `-> ()`, as on every `fn`. For an operation with another result
>   that is E0548 (result type differs), with the operation header in the help.
>
> ```blink
> effect Ee { effect Op { fn op(x: Int) -> Int } }
>
> fn good() -> Int {
>     with handler Ee.Op { fn op(x: Int) -> Int { x + 1 } } { ee.op(1) }   // OK
> }
>
> fn bad1() -> Int {
>     with handler Ee.Op { fn op(x) -> Int { x + 1 } } { ee.op(1) }
>     // error[E0328]: parameter `x` has no type; help: write `x: Int` (from `Op.op`)
> }
>
> fn bad2() -> Int {
>     with handler Ee.Op { fn op(x: Int) { x + 1 } } { ee.op(1) }
>     // error[E0548]: the result type is (), `op` returns Int; help: fn op(x: Int) -> Int
> }
> ```
>
> Tradeoffs: TypeScript does infer method params in an object literal with a contextual type, so
> B is tempting for my seat. But a clause is written with `fn name(...)`, which every other place
> in Blink is a full signature; one form with two rules is the confusing choice. A reader of a
> handler sees the types without opening the effect. The fix is one keystroke in an editor because
> the help is machine-applicable, so the typing cost is near zero.
>
> ### G6-P2 (option B): untyped clause param takes the operation's type; result may be left out too
>
> Shorter handlers, TS-like. But two legal spellings of one clause, a style lint fight, and an
> omitted `-> T` meaning "take it from the op" here but `()` everywhere else. Not preferred.
>
> ---

- **PLT:** (excerpt, section `G6. May a handler clause leave a parameter type out?`)

> A clause is written with `fn name(params) -> R { }`, the syntax of a signature, and §3.3 requires
> annotations on signatures. Both options are sound: the operation's type is known when a clause is
> checked, so a bidirectional checker could push it in (P2). The question is one meaning per form.
>
> ### G6-P1 (preferred): a clause is a signature; an untyped clause parameter is E0328
>
> - A clause parameter with no type: E0328 MissingParamType at its name, in check. Widen the E0328
>   row to list "a handler clause". The help prints the operation's header as one line to copy
>   (the E0548 help text). The parameter then has the error type: no E0548 for it, no cascade.
>   This also removes today's ICE (NodeCarriesNoType).
> - E0548 stays for a written type that differs. Missing is not the same as differs: E0328 names
>   the cause.
> - A clause with no `-> R` has result `()`, as for any `fn`. For an operation whose result is not
>   `()`, that is E0548 (result type differs). The omitted result is never taken from the
>   operation.
>
> ```blink
> effect Ee { effect Op { fn op(x: Int) -> Int } }
>
> fn main() {
>     let a = with handler Ee.Op { fn op(x: Int) -> Int { x + 1 } } { ee.op(2) }   // OK, a is 3
>     let b = with handler Ee.Op { fn op(x) -> Int { x + 1 } } { ee.op(2) }        // error[E0328]: `x` has no type
>     let c = with handler Ee.Op { fn op(x: Int) { x + 1 } } { ee.op(2) }          // error[E0548]: result is (), the operation gives Int
>     io.println("{a}")
> }
> ```
>
> Tradeoffs: `fn f(x)` and `fn op(x)` mean one thing everywhere; the omitted result means `()`
> everywhere. A reader of a clause sees its types with no look-up. The cost: some typing, which the
> help removes in one copy.
>
> ### G6-P2: inherit the parameter types (and the result) from the operation
>
> Sound by bidirectional checking, and Koka and OCaml 5 handlers infer clause types. Rejected by
> this seat for Blink: it gives `fn op(x)` two meanings by position, and an omitted result would
> mean "the operation's result" in a clause but `()` in a fn. If the panel wants inference here,
> the honest form is a closure-like clause syntax, not `fn`.
>
> ---

- **DevOps:** (excerpt, section `G6 ([ticket]) handler clause with a param type left out`)

> **G6-P1 (preferred): a clause is a signature. An untyped clause param is E0328, with a
> machine-applicable fix that writes the operation's type. A left-out result type means `()`,
> as for any fn, so it is E0548 when the op does not return `()`.**
>
> ```blink
> effect Ee { effect Op { fn op(x: Int) -> Int } }
>
> with handler Ee.Op { fn op(x) -> Int { x + 1 } } { ... }       // error[E0328] at `x`
> with handler Ee.Op { fn op(x: Int) { x + 1 } } { ... }          // error[E0548]: result `()` vs `Int`
> with handler Ee.Op { fn op(x: Int) -> Int { x + 1 } } { ... }   // OK
> ```
> ```
> error[E0328]: parameter `x` has no type
>   = help: write `x: Int` (the type of parameter 1 of `Ee.Op.op`)   (machine-applicable)
> ```
> Unlike other E0328 sites, the type is known, so the param gets the op's type (not the error
> type) and the body gets no cascade. E0548's existing help prints the op header to copy; for a
> left-out result whose body type equals the op result, adding `-> T` is machine-applicable.
> The E0328 row already lists "an effect operation"; the writer adds "a handler clause".
>
> Tradeoffs: one rule for every `fn` header: what you see is the type. A clause can sit in a test
> file far from the effect; plain-text review (diffs, PR pages) has no hover. Typing the param is
> also free in an editor: a "fill clause from operation" code action writes the whole header,
> which E0548's help already prints.
>
> **G6-P2 (B): the clause takes the type from the operation, as a closure takes it from an
> expected fn type.** Fewer keystrokes; inlay hints cover editors. But it creates a second kind of
> `fn` header, and E0548 becomes "matches where written", which is harder to state and to test.
> Against.
>
> Both proposals fix today's check ICE and the build ICE.
>
> ---

- **AI/ML:** (excerpt, section `G6: handler clause with a parameter type left out`)

> ### G6-P1 (PREFERRED): a clause is a signature; types and result are written
>
> - An untyped clause parameter is E0328 MissingParamType (widen its row to name "a handler
>   clause"). Because the operation is known, the fix is machine-applicable: insert the operation's
>   parameter type.
> - A clause with no `-> R` has the result `()`, as any fn does. For an operation whose result is
>   not `()`, that is E0548 HandlerClauseMismatch (result type differs); the help prints the
>   operation header to copy. Today `fn op(x: Int) { x + 1 }` for `-> Int` passes check (probe
>   g6b): a bug under this proposal. Today `fn op(x)` ICEs NodeCarriesNoType (probe g6).
>
> ```blink
> effect Ee { effect Op { fn op(x: Int) -> Int } }
>
> with handler Ee.Op { fn op(x: Int) -> Int { x + 1 } } { ... }   // OK
> with handler Ee.Op { fn op(x) -> Int { x + 1 } } { ... }        // error[E0328] at `x`; fix: `x: Int`
> with handler Ee.Op { fn op(x: Int) { x + 1 } } { ... }          // error[E0548]: result `()` differs from `Int`
> ```
>
> Tradeoffs (AI): a clause is spelled `fn name(params) -> R { }`, exactly a fn item. One rule ("a
> `fn` with a name writes its types") beats a special case a model must remember ("except in a
> handler, where it looks like a closure"). The help copies the header, so the fix costs the model
> one paste. The types also make a handler readable alone, which matters when a model edits a
> handler far from its effect.
>
> Cross-language: Koka, OCaml 5 and Unison infer clause types, but they infer fn signatures too;
> Blink does not (§3.3), so their choice does not carry over.
>
> ### G6-P2: inference from the operation (option B)
>
> Saves a few tokens per clause, but adds a decision point (which `fn` forms infer?) and makes a
> clause differ from a fn that looks the same.
>
> ---

- **Minimalism:** (excerpt, section `G6 ([ticket]) Untyped handler clause parameter`)

> Probes: `fn op(x) -> Int { x + 1 }` in a handler ICEs at check (NodeCarriesNoType).
> `fn op(x: Int) { x + 1 }` for an op `-> Int` checks clean and ICEs at run (C type mismatch).
>
> ### G6-P1 (PREFERRED): a clause is a signature; widen E0328, and E0548 covers the result
>
> - A clause parameter with no type is E0328 MissingParamType, in check, at the name. Add
>   "a handler clause" to the E0328 list. Because the operation gives the type, the fix is
>   machine-applicable here: write `x: Int`.
> - A clause with no `-> T` has result `()`, as every fn does. For an operation whose result is
>   not `()` it is E0548 HandlerClauseMismatch (result type differs), with the existing help that
>   prints the operation header. No new rule; today's clean check is a bug against E0548.
>
> ```blink
> effect Ee { effect Op { fn op(x: Int) -> Int } }
>
> fn g() -> Int ! Ee.Op { ee.op(1) }
>
> fn main() {
>     let a = with handler Ee.Op { fn op(x: Int) -> Int { x + 1 } } { g() }   // OK
>     let b = with handler Ee.Op { fn op(x) -> Int { x + 1 } } { g() }        // error[MissingParamType] (E0328) at `x`
>     let c = with handler Ee.Op { fn op(x: Int) { x + 1 } } { g() }          // error[HandlerClauseMismatch] (E0548): result `()`, operation gives `Int`
>     io.println("{a} {b} {c}")
> }
> ```
>
> Tradeoffs: one rule for every `fn ... (...)` header in the language (§3.3), and no third kind
> of function (signature-shaped but closure-inferred). The clause reads on its own: the type is
> on the page. Cost: more typing in handlers; the machine fix pays it.
>
> ### G6-P2 (rejected): infer from the operation, as a closure does
>
> Adds a special case to §3.3 and to E0328's list of exceptions; a reader must open the effect to
> know `x`. Koka and OCaml 5 infer clause types, but they infer every fn; Blink does not.
>
> ---

#### Phase B — Debate highlights

- **Systems:** (excerpt)

> G1, G5, G6: no objection.

- **Web/Scripting:** (excerpt)

> G1, G5, G6: no objection. I accept devops' note at the param's `mut` for G1.

- **PLT:** (excerpt)

> G1, G5, G6: no objection.

- **DevOps:** (excerpt)

> G1, G5, G6: no objection. Writer note for G1: error at the capture, note at the `mut` of the param.

- **AI/ML:** (excerpt)

> G1, G5, G6: no objection.

- **Minimalism:** (excerpt)

> G1, G5, G6: no objection.

#### Phase C — Final vote

- **G6-Q1: an untyped clause parameter is E0328; an omitted `-> R` means `()`** (6-0, option A; the other option was to reject)

- **Systems:**

> ## G6-Q1: A
> Reasoning: a clause compiles to one C function either way; requiring types matches the impl-method rule and removes the inference path into handler headers that ICEs today.
> Concern: none.

- **Web/Scripting:**

> ## G6-Q1: A
> Reasoning: a clause is written `fn name(...)`, which is a full signature everywhere else in Blink. The machine-applicable fix makes the typing cost near zero.
> Concern: TS users will expect contextual inference on handler params; the help must show the type to write, taken from the op.

- **PLT:**

> ## G6-Q1: A
> Reasoning: a clause is written with `fn` signature syntax, so `fn op(x)` and an omitted result must mean what they mean everywhere else. Inference would be sound by bidirectional checking, but it would give one form two meanings by position.
> Concern: users from Koka or OCaml 5 expect inferred clause types. The fix from the operation type must be machine-applicable so the cost is one keystroke.

- **DevOps:**

> ## G6-Q1: A
> Reasoning: every `fn` header shows its types, so a reader without hover (diffs, PR pages) can still see them. The op's type is known, so the fix is machine-applicable and the body gets no cascade. It also closes today's check ICE and build ICE.
> Concern: E0548's help for a left-out `-> R` must say "a fn with no `-> R` returns `()`", or users will read it as a type mismatch they did not write.

- **AI/ML:**

> ## G6-Q1: A
> Reasoning: a clause is spelled exactly like a fn item, so "a named `fn` writes its types" stays one rule with no handler exception. The fix is machine-applicable from the operation header, so the token cost to repair is near zero.
> Concern: models that learned effect handlers from Koka/OCaml will omit types often; the help must print the full header to copy.

- **Minimalism:**

> ## G6-Q1: A
> Reasoning: a clause is a signature; one rule for every `fn (...)` header, and the op gives the fix.
> Concern: handler-heavy test code gets wordier; the machine fix must cover it.

### Final Spec

```blink
effect Ee {
    effect Op { fn op(x: Int) -> Int }
    effect Note { fn note(msg: Str) }
}

with handler Ee.Op {
    fn op(x) -> Int { x + 1 }       // error[E0328]: `x` has no type; fix: `x: Int`
} { ee.op(1) }

with handler Ee.Op {
    fn op(x: Int) { }               // error[E0548]: no `-> R` means `()`, the operation returns `Int`
} { ee.op(1) }

with handler Ee.Note {
    fn note(msg: Str) { }           // OK: the operation has no result
} { ee.note("hi") }
```

- A handler clause is a signature. An untyped clause parameter is E0328 `MissingParamType`, and the E0328 row covers handler clauses.
- The compiler does not take the type from the operation. The fix is machine-applicable and writes the type from the operation.
- A clause that leaves out `-> R` has the result type `()`. It is E0548 `HandlerClauseMismatch` when the operation's result is not `()`.
- Spec text: §3.3 *A signature parameter with no type*, §4.7 *Clause signatures*, E0328 and E0548 in ERROR_CATALOG.md.
