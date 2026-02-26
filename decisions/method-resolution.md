[< All Decisions](../DECISIONS.md)

# Method Resolution — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 4 questions.

**Q1: Effect handle namespace — reserved vs shadowable (5-0 for reserved)**

- **Systems:** Reserved. Effect handles compile to evidence-vector slots — not variables, capability proofs. Shadowing would require checking handler-compatibility at every use site. Keep the invariant simple: handle name → evidence slot, always.
- **Web/Scripting:** Reserved. If a dev writes `let io = 5` inside a function with `! IO` and `io.println` silently breaks, the bug is incomprehensible. Effect handles must be sacred.
- **PLT:** Reserved. Handles are capability witnesses. The typing rule for `io.println(x)` checks that `IO.Print` is in the effect row — trivially correct when `io` is a fixed binding in a separate namespace. If shadowable, the type rule must verify the variable's type matches at every use.
- **DevOps:** Reserved. LSP go-to-definition on `io.println` should always jump to the effect operation signature, never to some local variable. If shadowable, go-to-definition becomes context-dependent.
- **AI/ML:** Reserved. LLMs would shadow effect handles by accident constantly — `io`, `db`, `fs` are common variable names in training data. Making them reserved eliminates an entire error class.

**Q2: Dot-call semantics — method-only or field-call too (5-0 for method-only)**

- **Systems:** Method-only. `x.foo()` should compile to a single vtable dispatch or direct call. If it can also mean "load field, then indirect call," the codegen has two paths. `(x.callback)(args)` is explicit and compiles to a load+call.
- **Web/Scripting:** Method-only. `obj.method()` means method call. `(obj.field)(args)` for callable fields is unusual but the case is rare. Parentheses make intent clear.
- **PLT:** Method-only. Separating field projection (`.foo`) from method dispatch (`.foo()`) in typing rules avoids needing a "field-or-method?" judgment form. `(x.foo)(args)` is explicit projection-then-application — two rules composed, not one ambiguous rule.
- **DevOps:** Method-only. LSP autocomplete for `x.` shows methods uniformly. If fields could be callable too, autocomplete must inspect field types to decide which get `()` appended.
- **AI/ML:** Method-only. In training data, `x.foo()` is overwhelmingly a method call. Same syntax for two semantics = generation errors. `(x.callback)(args)` has a distinct visual pattern.

**Q3: Multiple trait methods — error at impl site or call site (5-0 for call-site)**

- **Systems:** Call site. Two independent authors defining traits with the same method name is realistic. Preventing a type from implementing both kills composability. Qualified syntax `Trait.method(x)` at the ambiguous call site is the right fix.
- **Web/Scripting:** Call site. Blocking impls is too aggressive — you'd discover the problem when adding a dependency, not when writing code. Error at call site with "did you mean `TraitA.foo(x)` or `TraitB.foo(x)`?" is better DX.
- **PLT:** Call site. Forbidding at impl site violates the open-world assumption for traits. Types should be freely implementable for any trait whose contract they satisfy.
- **DevOps:** Call site. Error message can list both traits, show signatures, offer quick-fix to insert qualified form. Error at impl site gives "you can't implement this trait" with no actionable fix for third-party traits.
- **AI/ML:** Call site. Call-site errors happen where the AI is generating code and can immediately fix. Impl-site errors happen at definition time, far from where the AI is working.

**Q4: Inherent methods — yes or no (4-1 for no)**

- **Systems:** Yes. Inherent methods are essential for type-specific operations that don't belong to any trait. Forcing everything through traits creates artificial trait proliferation — one-method traits that exist only to give a type a method. *(dissent)*
- **Web/Scripting:** No. One way to define methods: in traits. No "should this be inherent or a trait?" decision. A one-method trait is fine — the overhead is one line.
- **PLT:** No. Inherent methods create silent priority over trait methods. Adding an inherent method to a type can change which code runs at existing call sites without any error. Without inherent methods, adding a trait impl can only cause ambiguity errors, never silent behavior change.
- **DevOps:** No. "Where is this method defined?" has one answer: in a trait impl block. LSP searches trait impls only. With inherent methods, LSP must also search `impl Foo { }` blocks.
- **AI/ML:** No. "All methods live in traits" is a single rule. One mechanism = one pattern = better generation accuracy. Consistent with Pact's rejection of alternatives everywhere.

