# Blink Error Catalog

Complete catalog of all compiler diagnostics. Names are the primary identification scheme; numeric codes are secondary comblink identifiers.

## Identification Format

**Human-facing (terminal):**
```
error[NonExhaustiveMatch]: non-exhaustive match
```

**JSON (structured output):**
```json
{
  "name": "NonExhaustiveMatch",
  "code": "E0004",
  "severity": "error",
  "message": "non-exhaustive match",
  ...
}
```

## Conventions

- **Names** are PascalCase, stable API. Once published, a name is frozen — never renamed, never reassigned.
- **Codes** are secondary comblink identifiers (E/W/V + 4 digits). Codes are never reused after retirement.
- **Suppression** uses names: `@allow(UnusedVariable)`. `@allow` takes names only. Suppress a warning only when the code is correct as written; the usual repair for `UnusedVariable` is to remove or rename the binding.
- **Nearest-name suggestion.** A diagnostic that suggests a name compares the written name with its candidate names after it ignores case, `_` and `-`. If exactly one candidate is nearest, and it is near enough, the `help:` line names it. If two or more candidates are equally near, or no candidate is near enough, there is no suggestion. The implementation sets how near is near enough. For one compiler version, the same input gives the same suggestion in the compiler, the language server and `blink explain`. Each row that suggests a name says which names are its candidates.
- **Only warnings can be suppressed.** `@allow` and `[lints]` reach only names listed under *Warning Names* (§4.16.8). The catalog row decides, not the severity in effect, so a warning promoted to an error is still reachable. Any other live name is the error `NotAWarningName` (E0847). No `@allow` or `[lints]` entry suppresses E0847 or changes its severity, and every level is refused, `"error"` included. The named error still fires at its own site.
  - **Help:** the first `help:` line says to remove the argument or key. The next line gives the named error's own primary help. Where a row has a better repair through its own control, that repair is catalog data, taken from the same source as the named error's help: `ContractUnverifiable` (V0003) → change `@verify(fallback: ...)`; `CapabilityBudgetExceeded` (E0501) → widen `@capabilities`. When no repair fits the `@allow` site, the help is generic and a `note:` names `blink explain <Name>`. The help never proposes another `@allow` argument and never proposes a `_ => panic(...)` arm.
  - **Check order:** E0842 is checked first. E0837 and E0847 cover separate name sets, because the audit-gated list holds warnings only (§9.1), so no order between them is given.
- **Each `@allow` argument and each `[lints]` key must identify a live diagnostic** — one listed under *Error Names*, *Warning Names*, *Info Names* or *Internal Compiler Errors*, not under *Retired Codes*. Any other argument or key is the error `UnknownDiagnosticName` (E0842): a misspelled name, a retired name or code, or a code given to `@allow`. E0842 is an error, so no `@allow` or `[lints]` entry suppresses it or changes its severity. The compiler reports each such argument and key, not only the first. An audit-gated name is `AuditGatedSuppression` (E0837), and a live name that is not a warning name is `NotAWarningName` (E0847), not E0842.
  - **Retired name or code:** the `help:` line says to remove the argument or key. A `note:` lists the *Replaced by* cell of its *Retired Codes* row as information only. The help never proposes a replacement as an `@allow` argument.
  - **Code given to `@allow`:** the `help:` line names the live diagnostic that has that code.
  - **Any other string:** the `help:` line suggests a name by the nearest-name rule above. The candidates are the live names. A retired name or a code is never suggested.
  - No two live names are equal when case, `_` and `-` are ignored.
- **`blink explain <name-or-code>`** prints a detailed explanation of a live diagnostic and exits 0. For a retired name or code, the first line says it is retired, the output shows the same *Replaced by* list as the E0842 note, and the exit status is 0. For any other string, it prints `no diagnostic named <string>`, a suggestion by the nearest-name rule if there is one, and exits with a non-zero status.
- **Every entry in this catalog is bound by the three rules in §3.1 *Diagnostic Discipline*:** a diagnostic never prescribes a repair that does not exist, no rule is enforced only at codegen, and diagnostics firing at one program point must converge on a repair the first `help:` names.

---

## Category Ranges

| Range | Category |
|-------|----------|
| E00xx | Pattern matching / exhaustiveness |
| E01xx | Type identity / traits / derive |
| E03xx | Type checking / type mismatch |
| W055x | Mutation analysis |
| E05xx | Effects / capabilities |
| E06xx | Resource scope / closures |
| E061x | Mutation analysis (assignment and mutable roots) |
| W060x | Linting |
| W061x | Resource scope lints |
| W070x | Linting |
| E07xx | Method resolution / arena / coherence |
| E08xx | FFI |
| E09xx | Module capabilities / trait contracts |
| E10xx | Module resolution / imports |
| W10xx | Modules / manifest |
| E11xx | Parser / lexer |
| W11xx | Parser / type spelling |
| E13xx | Refinement contracts (predicate sublanguage) |
| E14xx | Generic collections / Hash + Eq bounds |
| V00xx | Contract verification outcomes |
| V11xx | String literal hints |
| I00xx | Internal compiler errors (ICE) |

---

## Internal Compiler Errors (ICE)

Internal compiler errors indicate a bug in the compiler itself, not in your code.
If you encounter one, please report it at https://github.com/blinklang/blink/issues.

ICE codes use the `I` prefix. `@allow` and `[lints]` take warning names only, so an ICE name in either is `NotAWarningName` (E0847) (§4.16.8).

| Name | Code | One-line |
|------|------|----------|
| UnsolvedTypeVarAtCodegen | I0001 | An unsolved type variable reached monomorphization — the front end should have reported `CannotInferType` (E0301) first |
| UnhandledIterableAtCodegen | I0002 | A `for` loop's iterable passed the front-end check but code generation has no emitter for its type |
| MisplacedIrKindAtPrint | I0003 | An IR node of the wrong class reached the C printer — a statement where a value is required, or the reverse |
| CodegenStageNotBuilt | I0004 | A code-generation stage this build does not contain was reached |
| PoisonedIrAtSeam | I0005 | A negative IR node id was handed to a producer that must embed it — the caller ignored a stop it had already been told about |
| ParserInternalLimit | I0012 | The parser's node pool or sublist stack met a state it can not hold — a limit of its layout, or a call out of order or out of bounds; the compiler stops |
| TypedefQueuedNotWritten | I0013 | The shared types header of a per-module build ended with a typedef queued and never written |
| TwoDeclarationsOneCSymbol | I0014 | Two declarations reached code generation under one C symbol; the compiler stops before cc sees the unit |

---

## Error Names

| Name | Code | One-line | Category | Spec ref |
|------|------|----------|----------|----------|
| NonExhaustiveMatch | E0004 | A `match` leaves an enum variant unhandled. Guarded arms do not contribute to coverage; a `_` or plain-binding arm makes the match exhaustive | Pattern matching | §3.9 |
| InconsistentPatternBindings | E0005 | The alternatives of an OR-pattern do not bind the same names, or bind one name at different types or with `mut` in some alternatives only. One error per OR-pattern; each missing name, each type difference and each `mut` difference is a note. A `mut` difference alone carries a fix that puts `mut` on the binder in every alternative | Pattern matching | §3.5 |
| TypeError | E0300 | Type mismatch detected during type checking. In a pattern: a qualified variant of a different enum (`Other.Q(v)` on a `T` scrutinee) or a struct pattern of a different struct type. The header names both types, the span is the whole path or type name, and the help lists the variants of the expected type; when that type declares a variant of the same name and payload form, the fix `T.Q` is machine-applicable. Binders under the pattern have the poison type, and an unguarded such arm turns off E0004 for the match | Type checking | §3, §3.5 |
| CannotInferType | E0301 | Inference left a type variable unbound — annotate the binding, or supply the type argument at the call when the callee's signature does not supply it. Reported where the repair attaches | Type checking | §3.4 |
| TypeArgArity | E0303 | A type-argument list has the wrong count for the declaration it applies to. In a type position that includes none (a bare `Channel`/`List`). At a callee or a struct-literal head, a written list of the wrong count (`decode[A, B](s)`, `plain[Int](3)`); an absent list there is left to inference. A non-generic declaration or a local value binds zero. Under- and over-application are one code. A rejected list supplies nothing: no E0301 or E0306 for that call's binders. Decided when the head resolves: at name resolution for a type or a path, once the receiver's type is known for a method | Name resolution | §3.4 |
| TraitBoundNotSatisfied | E0306 | A call's type argument (inferred or explicit) does not satisfy the type parameter's declared bound — checked against the arguments as written, before code generation | Type checking | §3.6 |
| EnumPatternNeedsEnumScrutinee | E0308 | A refutable pattern names a variant, but the type at that pattern position is not an enum: a builtin scalar, a struct, a tuple, a list or other builtin type, or a type parameter. The name is a bare name with an uppercase first character, with or without a payload, or a qualified `E.V`. The span is the variant name. This includes `MAX =>` or `Red =>` on an `Int`: neither is a new binding. The help says "to bind the value, write a lowercase name"; when a value with that name is in scope and the position is not a type parameter, a second `help:` line shows the guard repair `n if n == MAX =>`, or, below the top of the arm, says to write a lowercase name there and add `if n == MAX`. For a type parameter the compiler reports it where the generic function is defined | Type checking | §3.5, §3.4 |
| TemplateMismatch | E0310 | A `Str` where `Template[C]` is expected, or a template where `Str` is expected; neither converts to the other. For a plain literal the help adds the `t` prefix (`t"..."`), and for a template literal it removes it; both are machine-applicable. A `Str` value has no machine fix. No help offers `Raw(...)` | Type checking | §2.4.3, §3b.5 |
| MissingReturn | E0311 | Control can reach the end of a block that must produce a value of type `R` along a path that yields `()` — a value-returning function whose tail can complete normally (a `while`/`for` tail, an `if` without `else`), or a closure whose return type comes from a valued `return` and whose tail can complete with `()`. The tail kind is carried as diagnostic data, not a separate code. Repair: add a trailing `return <value>`, or change the return type to `Option[R]`. When `R` is `Never`, the help names only a diverging tail (`panic(...)`, `unreachable()`, or a call to a `-> Never` function) and does not offer `Option[R]`. A diverging tail (`panic`, or a `loop` no `break` targets) is accepted | Type checking | §3.3 |
| NoConversionImpl | E0312 | A conversion has no impl: `x.into()` and `T.from(x)` need `impl From[S] for T`, `T.try_from(x)` needs `impl TryFrom[S] for T`, with S the source's type (an alias is the type it names). Every type converts to itself. Repair: declare the impl, or use the named conversion (`.to_float()`, `.truncate()`, `.to_int_checked()`, `try_from`, `.to_string()`) | Type checking | §3c |
| NoIndexOperator | E0313 | A postfix `[...]` holds a value (`xs[1]`, `m["k"]`, `fns[0](x)`). Blink has no index operator. Decided by the bracket contents at name resolution, whether or not a call follows. Repair: `.get()` (returns `Option`), or `.0` for a tuple; no machine fix when a call follows. A store `xs[i] = v` is the same error: repair `.set(i, v)` (List, Bytes) or `.insert(k, v)` (Map), never `.insert` for a List. A store also gets a one-line reason `note:` (brackets hold types; elements use methods). A Map compound `m[k] op= v` gets a `note:` with the default form `m.insert(k, (m.get(k) ?? 0) op v)` first, then the `.unwrap()` form; a literal `0` only for `+=`/`-=` on Int/Float, else a placeholder that does not parse; no machine fix | Name resolution | §3.4, §2.22 |
| TypeArgsWithoutCall | E0314 | A well-formed type-argument list with no call `(` or literal `{` after it (`let f = identity[Int]`). First help: remove the brackets when an expected type fixes the same arguments; annotate the binding when there is no expected type; no machine fix when they conflict. A list after a type and before a type-scoped function (`Map[Str, Int].new()`): move the list after the function name (`Map.new[Str, Int]()`); machine-applicable for standard library types, a suggestion for user types | Type checking | §3.4 |
| MissingField | E0315 | A struct literal, a variant brace literal or a labelled variant paren payload gives no label to a field that has no default, and has no `..source`. One per literal, at the type or variant name; it lists each missing field and its type in declaration order. A field that is the unique suggestion of an unknown label in the same literal is left out, and an empty list reports nothing. Help: add each field with a value; for a struct declared in the package being compiled, also "or give it a default". No machine-applicable fix. A struct pattern or variant brace pattern that leaves out fields with no `..` is `PatternMissingRest` (E0319), not this code | Type checking | §2.14, §3.4 |
| DuplicateField | E0316 | The same label appears twice in one struct literal, variant brace literal or labelled variant paren payload, with or without `..source`; or twice in one struct pattern or variant brace pattern, at any depth and in any pattern position. At the second label, with a `note:` at the first. Help: remove one. No machine-applicable fix. In a pattern, the arm is a bad arm (it covers nothing, an unguarded one turns off E0004, and it gets no unreachable report); binders keep their field types | Type checking | §2.14, §2.16, §3.5 |
| VariantSpread | E0317 | A variant brace literal holds `..source`; copy-update applies to struct literals only. Help: write every field, or match on the source to bind its fields | Type checking | §3.4, §2.16 |
| IntLiteralOutOfRange | E0318 | An integer literal's exact value is outside the range of its type: the expected type at the literal, or `Int` with none. One code for every integer type and every base; a hex literal is a value, not a bit pattern. A negative literal (one unary `-` on a literal, optional parentheses) under an unsigned type is E0318 for every value, `-0` included, with the note `unsigned types hold no negative values`. Covers literal patterns, range-pattern bounds and const contexts (not E0546). With no expected type, the message names the default `Int`, and a help offers a `U64` annotation when the value fits; above the `U64` maximum, the message says no integer type holds the value and gives no help. No `@allow` | Type checking | §3.2, §3.3, §2.21 |
| PatternMissingRest | E0319 | A struct pattern or a variant brace pattern (bare or qualified) leaves out one or more fields and has no `..`. One per pattern, at the type or variant name; it lists each missing field and its type in declaration order. A field that is the unique suggestion of an unknown label in the same pattern is left out of the list, and an empty list reports nothing. A field default does not count as naming the field. Two fixes, always in this order: add `..` (machine-applicable; the preferred fix), then `f: _` for each left-out field `f` (structured output only; never machine-applicable; it keeps the pattern closed, so a field added later reports again). A missing `..` alone is not a bad arm: the compiler checks the arm as if the pattern had `..`. Checked after E0316 and E0525 | Type checking | §3.5 |
| UndeclaredEffect | E0500 | Callee requires effect not declared by caller. The declared row of an `@ffi` callee counts like any other row. Not for `State`: E0552 covers it | Effects | §4.5 |
| CapabilityBudgetExceeded | E0501 | Function effect exceeds module `@capabilities` budget | Effects | §4.8 |
| QuestionMarkInvalidOperand | E0502 | `?` operator used on non-Result, non-Option type | Type checking | §3c.2 |
| UndefinedFunction | E0504 | Call to undefined function. When the callee names a type (`List()`, `Registry()`), the first help names the type's one empty form: `[]` for `List`, `T.new()` when `T` has a type-scoped `new` with no parameters, a struct literal when the caller can write one, else no form | Name resolution | §6.3 |
| UnresolvedMethod | E0505 | Unresolved method call on variable. When a visible effect has an op of that name whose declared first parameter type equals the receiver type, the help gives the handle form (`process.wait(child)`) in its first line. The fix adds the call rewrite and, when the row lacks the effect, the effect to the row, both machine-applicable; with two or more matching effects the help lists each and the fix is not machine-applicable. A type parameter or the poison type matches no op | Name resolution | §6.3, §3c.4, §4.4 |
| UndefinedVariable | E0506 | Reference to undefined variable | Name resolution | §6.3 |
| UnknownType | E0507 | Reference to undefined type | Name resolution | §6.3 |
| QuestionMarkResultInNonResult | E0508 | `?` on Result in function not returning Result | Type checking | §3c.2 |
| QuestionMarkOptionInNonOption | E0509 | `?` on Option in function not returning Option | Type checking | §3c.2 |
| MissingKeywordArg | E0510 | A keyword parameter received no argument at all — the value is absent (contrast `UnlabeledKeywordArg`, where the value is present but unlabelled) | Name resolution | §2.13 |
| InvalidKeywordArg | E0511 | A call-site label names no keyword parameter of the callee — including a label written on a positional parameter | Name resolution | §2.13 |
| QuestionMarkErrorMismatch | E0512 | `?` error type mismatch — inner E1 ≠ function return E2 | Type checking | §3c.2 |
| CoalesceRequiresOption | E0513 | `??` operator used on non-Option value | Type checking | §3c.2 |
| NameCollision | E0518 | A struct has the name of a variant of an enum in the same package or of a prelude enum. The reach is the package, not the module. A dependency's variant does not collide. An import entry that binds such a struct is E0518 at the import entry; the fix is an alias | Type checking | §3.4 |
| AmbiguousConstruction | E0519 | A bare variant name in value position (nullary, payload call or brace literal) that two or more candidate enums declare (§3.4 *Global-unique*), a prelude carrier counting, with no expected type to pick one | Type checking | §3.4 |
| StrPlusUnsupported | E0521 | `+` with a `Str` operand, or `+=` on a `Str` place (a variable or a field). One diagnostic per `+` chain, over the whole chain. The fix is one interpolated string with one hole per operand; it is machine-applicable only when every operand is `Str`, and otherwise a suggestion with the exact replacement text. `s += t` gets the fix `s = "{s}{t}"` under the same rule | Type checking | §2.19 |
| AmbiguousMethodCall | E0522 | Unqualified method call resolves to a method defined by two or more implemented traits, a sealed built-in trait counting as one of them | Name resolution | §3c.4 |
| MissingDisplayImpl | E0523 | Interpolated `{expr}` type does not implement `Display` | Type checking | §3.6 |
| ReservedTypeName | E0524 | A `type`, type alias, `trait` or `effect` declaration takes a reserved name: `Self`, a scalar type that literal syntax produces, or `Void` | Name resolution | §10.6 |
| NoSuchField | E0525 | A field access names a field that the struct, tuple or opaque handle does not declare; or a label in a struct literal, a variant brace literal or a labelled variant paren payload names a field that the type or variant does not declare. For a label, the candidates for the nearest-name suggestion (see *Conventions*) are the declared fields the literal does not already label; with one suggestion, the rename is machine-applicable; with none, the help lists the declared fields and marks those given. The help adds "or add the field to `T`" only when `T` is declared in the package being compiled. The same code covers a label in a struct pattern or a variant brace pattern (bare `Rect { w, .. }` or qualified `Shape.Rect { w, .. }`), at any depth and in any pattern position. The candidates are the declared fields that the pattern does not already label; with one suggestion, the rename is machine-applicable. For a punned label (`Point { x, yy }`), the fix writes `y: yy`: the binder and the arm body stay as they are, and no use is renamed. The help has no "or rename the binder" line and no "or add the field to `T`" line for a pattern label. In a pattern, the arm is a bad arm (it covers nothing, an unguarded one turns off E0004, and it gets no unreachable report), and only a binder under the unknown label has the poison type | Type checking | §3.2, §2.14, §3.5 |
| PositionalAfterKeyword | E0527 | A positional argument follows a labelled one in the same call | Name resolution | §2.13 |
| DuplicateKeywordArg | E0528 | The same call-site label appears twice in one call | Name resolution | §2.13 |
| UnlabeledKeywordArg | E0529 | A keyword parameter received its argument positionally — the value is present and unlabelled. Help only: no machine-applicable fix, since only the author knows which value is for which parameter | Name resolution | §2.13 |
| RawOutsideTemplate | E0530 | A `Raw[T]` reached a position that does not consume it — only a hole of a template literal `t"..."` does; a hole of a plain `"..."` literal is an error | Type checking | §3b.5 |
| PositionalParamDefault | E0531 | A default value written on a positional parameter — only parameters declared after the `*` marker may carry one | Type checking | §2.13 |
| NonConstParamDefault | E0532 | A parameter default that is not a const expression | Type checking | §2.13, §2.21 |
| NonConstExpr | E0533 | The right-hand side of a `const` is not a const expression | Type checking | §2.21 |
| TemplateHoleType | E0534 | An interpolation hole in a template literal `t"..."` has a type outside the Template value set, or is a `Raw[Bytes]`, which cannot fold into the parts (help: `{b}`) | Type checking | §3b.5 |
| EffectTypeAsValue | E0535 | An effect's type is written as the type of a value (`fn f(x: DB)`, `let x: DB`); it is valid only as a type argument | Type checking | §3b.5 |
| SubEffectAsType | E0536 | A sub-effect is written as a type (`Template[DB.Read]`); only a top-level effect gives a type | Type checking | §3b.5 |
| JsonTextForValue | E0537 | A `Str` is passed to a `from_json` that takes `JsonValue`, or `to_json()`'s result is used as a `Str`; the fix names `json.decode[T]` / `json.encode` | Type checking | §3.6.2 |
| UnknownEffect | E0538 | An effect row names an effect that is neither built-in nor declared. For `FFI` the help says a foreign call is not an effect and points to §9.1. When the name before the dot is a leaf effect, a note lists its operations and the help names the whole effect. No machine-applicable fix | Effects | §4.3, §4.12 |
| UnhandledEffect | E0539 | An effect reaches a root with no `with` that discharges it: a user-declared effect in `main`, or any effect but `State` in a test block. It never fires for `State`, which the roots hold (§4.16.1). The header names the root (in `main`, or in test "..."); in `main` the help says user-declared effects have no root handler | Effects | §4.6, §2.20 |
| MixedEffectBody | E0541 | An effect body declares both operations and sub-effects; a body holds one or the other. The fix moves the operations into a new sub-effect with a placeholder name, never up to the parent | Parser | §4.12 |
| EffectNestingTooDeep | E0542 | A sub-effect declares a sub-effect; in v1 an effect tree has the top-level effect and one level of sub-effects | Parser | §4.12 |
| DuplicateEffectOp | E0543 | Two nodes of one top-level effect tree declare operations with the same name. The message names both declarations (`Metrics.Emit.get`, `Metrics.Query.get`) | Effects | §4.12 |
| DefaultOutsideHandlerOp | E0544 | `default` used outside the body of a handler operation, with no local binding named `default` in scope. A closure body is not an operation body, even when the closure is written inside one; there the message names the closure, the first help line says to call `default` in the operation body itself, and the second says a closure that runs while the operation runs can call through the handle (`audit.record(l)`). Outside any operation, the help shows the call through the effect's handle, built from the call (`audit.record("x")`), or says in words to call through the handle or move the call into a handler operation. No machine-applicable fix. A `default` binding in scope makes `default.x` ordinary member access (E0505 for a missing member) | Effects | §4.7.1 |
| StateNotHandleable | E0545 | A `handler State { ... }`, or a `with` that names `State`. `State` has no operations and no handler; the roots hold it | Effects | §4.16.1 |
| ConstEvalPanic | E0546 | Evaluation of a const expression in a const context (a `const` right-hand side, a struct field default, a keyword default, a range-pattern bound) would panic: integer `/` or `%` by zero, signed `MIN / -1`, or integer overflow. The span is the subexpression that fails, with one `note:` for each `const` reference that leads to the failing value | Type checking | §2.21 |
| NoSuchVariant | E0547 | A variant pattern or a qualified variant construction names a variant that its enum does not declare (`Somee(v)`, `K.Zed`, `K.Zed(1)`), or a bare name with an uppercase first character and no payload (`Dott`) names no variant of the enum at that pattern position. A bare uppercase name at a position whose type is not an enum is E0308, not E0547. The span is the variant name. The candidates for the nearest-name suggestion (see *Conventions*) are the variants of the enum that are visible at the site, matched or not; with one suggestion, the rename is machine-applicable only when the payload forms agree; with none, the help lists the declared variants. The terminal text may shorten the list and count the rest; structured output lists every variant. When exactly one visible enum declares a bare name, a `note:` names it. Unlike E0525, the help never says "add the variant": a misspelled variant almost never means the enum lacks one, and that line would invite an agent to add a wrong variant. Binders have the poison type; an unguarded such arm turns off E0004 and gets no unreachable report | Type checking | §3.5, §3.4 |
| HandlerClauseMismatch | E0548 | A handler clause names an operation of the handled effect, and its header differs from the header of the operation: the count of parameters, a parameter type, the result type, the `*,` marker (missing, extra or moved), or a keyword name or its order. Also a default written on a clause parameter. Types are equal after alias expansion, with no subtyping. A clause for a `-> Never` operation writes `-> Never`, and a `-> Never` clause for an operation with another result type is also E0548. The message and the JSON output name the part of the header that differs. The `help:` prints the header of the operation as one line to copy. Machine-applicable: delete a default; add, delete or move `*,`; put keyword names in the order of the operation; a keyword rename that maps one name to one name when the new name is free in the body (the fix renames the uses too); add a missing parameter when its name does not occur free in the clause body and its place is clear. Not machine-applicable: a rewrite of the header that changes a parameter type or the result type. Applies to user effects and to every built-in effect. Only the first clause for an operation is checked. Never fires on a clause that gets E0549. Related codes: E0549, E0550 | Effects | §4.7 |
| UnknownHandlerOp | E0549 | A handler clause names no operation of the handled effect. The `note:` lists the operations of the effect. With one suggestion by nearest name, the rename is machine-applicable only when the clause already matches the header of that operation and no other clause names it. Two clauses with one name that is no operation get E0549 each, and no E0550. Related codes: E0548, E0550 | Effects | §4.7 |
| DuplicateHandlerClause | E0550 | A second or later clause for one operation in one handler. It fires on the second and later clauses only, with a `note:` at the first clause. Only the first clause is checked for E0548. No machine-applicable fix: a tool cannot know which body to keep. Related codes: E0548, E0549 | Effects | §4.7 |
| UnsourcedEffectWildcard | E0551 | A `_` in the row of a function or of an impl method has no source: the function or method has no `! _` callback or handler parameter, and no type parameter whose bound has a method with a `_` row. The `_` in a trait-method declaration is not checked. The message says why the `_` has no source and names the two possible sources. Fires for every such `_`, and instead of E0904 on the same method. The `help:` line is "name the effects" | Effects | §4.15.2 |
| UndeclaredModuleState | E0552 | A boundary function (`pub fn`, `pub` method, trait impl method) touches module state, through its body or a call, and its row does not name `State`. One `note:` per binding: its name, read or written, the access location, and the call it goes through. Machine-applicable fix: add `State` to the row. E0500 does not fire for `State` | Effects | §4.16.1 |
| CloseableEscapesScope | E0601 | `Closeable` value escapes `with...as` scope | Resources | §5.5 |
| MutationRequiresMut | E0610 | A mutation whose root is not mutable: a call to a `mut self` method, or `=`/`op=`, whose first name is not a `let mut` binding, a `mut` pattern binder or a `mut` parameter. A closure's assignment to a captured binding is included, with a label at the capture. Machine-applicable fix: insert `mut` on a local `let` with a plain name, or before a local pattern binder (destructuring `let`, `for`, `match`; every alternative of an OR-pattern). Help only for the name after `as` in `with` (bind a new `let mut` name), a module-level `let` (the help says `mut` adds `State` to each reader's and writer's row) and an imported `pub let` (names E1013). Reported after E0611 and E0612 | Mutation analysis | §3.2.2, §2.22, §3.5 |
| NotAPlace | E0611 | The left side of `=`/`op=` is not a place: a step goes through a `Ptr` (at the root or mid-path, any root kind), or the root is a temporary such as a call result. For a `Ptr` step with `=`: machine-applicable `p.f.write(rhs)` when `rhs` is a literal, a name or a field path of names; otherwise, in a block statement, a fix that binds `rhs` to a new name on the line before; otherwise help only. With `op=`: help only, `p.f.write(p.f.read() op rhs)`, with a note that it is not atomic. A temporary root: help only, bind it first. Checked first: a `Ptr` step, then a temporary root | Mutation analysis | §2.22 |
| ParamAssign | E0612 | An assignment to a parameter or to a field of one, `self` included, with or without `mut`. Help: copy it to a new `let mut` name; in `Scoped.enter()`, build the value in the `with` item. Reported after E0611, before E0610. Ships first as a warning (§3.6 *Mutable Parameters*). A binder in a parameter pattern is a parameter | Mutation analysis | §3.6 |
| MutOnPattern | E0613 | `mut` before a pattern that is not a binder: a tuple, struct, constructor, variant, `_`, literal or range (`let mut (x, y)`, `for mut (k, v)`, `mut _`), before a struct field label (`{ mut x: px }`), or before the name after `as` in `with`. Machine-applicable fix: put `mut` on each binder inside a tuple, struct or constructor (keeps the meaning); `x: mut px` for a field label; otherwise remove `mut` | Patterns | §3.5, §2.18 |
| MutableCaptureInSpawn | E0650 | A closure passed to `async.spawn` captures a `let mut` binding or a `mut` pattern binder | Closures | §2.8 |
| SpawnTouchesModuleState | E0651 | A function value passed to `async.spawn`, closure literal or named function, whose effective row contains `State`. The help says to pass the data in, return it from the task, or use a `Channel` | Closures | §4.16.6, §2.8 |
| ArenaValueEscapes | E0700 | Arena-scoped value escapes arena scope | Arena | §5.2 |
| ArenaTypeContainsCycle | E0701 | Type crossing `with arena { }` boundary contains a cycle | Arena | §5.2 |
| ArenaClosureTailUnsupported | E0702 | Closure-typed arena tail cannot be promoted (umbrella) | Arena | §5.2 |
| ArenaClosureTailNonLiteral | E0702a | Closure-typed arena tail isn't a literal bound in this block | Arena | §5.2 |
| ArenaClosureUnsupportedCapture | E0702d | Closure-tail capture kind unsupported by descriptor walker | Arena | §5.2 |
| SealedMethodOverride | E0731 | `impl` overrides a trait default method declared `final` | Trait sealing | §3.6 |
| FinalRequiresBody | E0732 | `final` modifier applied to a body-less (required) trait method | Trait sealing | §3.6 |
| QualifiedHeadNotTrait | E0740 | The left side of `for` in an impl-qualified call head `(Trait for Type)` does not name a trait. When the left side is a type and the right side is a trait, the note says which side is the trait and the help gives the swapped head; otherwise the help suggests no swap | Method resolution | §3c.4 |
| FfiFunctionPublic | E0801 | FFI function cannot be `pub` | FFI | §9.1 |
| FfiNoEffects | E0802 | `@ffi` function declares no effects | FFI | §9.1 |
| ContractOnFfi | E0803 | `@requires`/`@ensures` not allowed on `@ffi` function, and an `@ffi` fn may not directly implement a trait method that has a contract | FFI | §9.1, §3b |
| InvalidPtrTypeParam | E0810 | Invalid `Ptr[T]` type parameter | FFI | §9.1.1 |
| PtrOutsideFfiContext | E0811 | `Ptr[T]` used outside FFI context | FFI | §9.1.1 |
| FfiStructGcField | E0812 | `@ffi.struct` field uses GC-managed or non-FFI type | FFI | §9.1.1 |
| FfiOffsetOnSingleton | E0813 | `Ptr.offset(i)` called on single-cell allocation | FFI | §9.1.1 |
| BytesGrowInWithPtr | E0814 | Bytes-growing call inside `bytes.with_ptr` closure | FFI | §9.1.1 |
| PinnedBytesEscape | E0815 | Pinned Bytes receiver escapes its `with_ptr` closure | FFI | §9.1.1 |
| BytesPtrCastForbidden | E0817 | Bytes coerced to `Ptr[U8]` outside `with_ptr` | FFI | §9.1.1 |
| FfiScopeNotWithResource | E0819 | An `FfiScope` value occurs somewhere other than as a `with ... as` resource — bound by `let`, passed, returned, stored, or written as a type argument (its libc arena would never be freed) | FFI | §9.1.1 |
| MissingNativeDep | E0820 | `@ffi` references undeclared native dependency. When the name is in the `libs` of another entry, the help names the key that owns it | FFI | §9.1.2 |
| NativeDepUnavailableCrossTarget | E0821 | Native dependency unavailable for cross-target: a `system` entry with no `link = "dynamic"`, or a `pkg-config` entry with no `libs` | FFI | §9.1.2 |
| BufOutsideFfiSurface | E0822 | The name `Buf` written outside the `@ffi.fn` / `@ffi.struct` surface — an annotated binding, a parameter or return type, a struct field, or a generic bound | FFI | §9.1.3.2 |
| CleanupPanickedDuringUnwind | E0824 | `exit(false)`/`close()` panicked during catchable unwind; original panic preserved, cleanup surfaces as warning | Test runner | §4.7.2 |
| IncompatibleStdlibArchive | E0840 | Installed stdlib archive built by a different toolchain than the linking compiler (ABI/struct-layout mismatch) — rejected at link time | FFI | §9.2.1 |
| CompilerManagedNativeDep | E0841 | `[native-dependencies]` key names a runtime library (`c`, `m`, `libc`, `libm`) that the compiler already links | FFI | §9.1.2 |
| NativeDepKeyLibPrefix | E0844 | A `[native-dependencies]` key starts with `lib` and is used as a link name (the entry is not `vendored` and gives no `libs`), so it would link `-llib...`. Span on the key. Two machine-applicable fixes: rename the key and every `@ffi` that names it in one edit, or add `libs` | FFI | §9.1.2 |
| PkgConfigPackageMissing | E0845 | A `type = "pkg-config"` entry has no `pkg-config` field. The field has no default; the help shows a full entry and never suggests the key as the package name | FFI | §9.1.2 |
| PkgConfigLookupFailed | E0846 | The `pkg-config` lookup for an entry failed: the tool is missing or has no such package. No fallback to `-l<key>` | FFI | §9.1.2 |
| FfiIncompatibleType | E0848 | A parameter type or the return type of an `@ffi` declaration is not on the closed list of FFI-compatible types (`Str`, `Bytes`, `List[T]`, `Option[T]` for a `T` that is not an `@ffi.opaque` type, `Never` as a parameter or inside another type, a plain struct, a closure type, a type parameter). Checked after alias expansion. `Void` stays E0828, a bad `Ptr` argument stays E0810, a bad `Buf` argument keeps its own rule. The `help:` names the fix for the shape written. `@trusted(audit: K)` does not cover it and `@allow` does not suppress it | FFI | §9.1 |
| InvalidRuntimeBinding | E0849 | `@runtime` is used outside `lib/std`, or its symbol does not start with `blink_`. The `help:` says that a C function uses `@ffi` | FFI | §9.1 |
| SkipOutsideTest | E0827 | `skip()` called outside a `test { ... }` block | Type checking | §2.20 |
| AssertPanicsBodyReturned | E0831 | `assert_panics` body returned normally instead of panicking | Test runner | §2.20 |
| AssertPanicsMessageMismatch | E0832 | `assert_panics` panic message did not match expected pattern | Test runner | §2.20 |
| AssertPanicsOutsideTest | E0833 | `assert_panics` called outside a test | Test runner | §2.20 |
| AssertPanicsNestedExpectPanic | E0834 | `assert_panics` nested inside another `assert_panics` | Test runner | §2.20 |
| XfailMissingReason | E0835 | `test.failing(...)` missing or empty `reason:` | Type checking | §8.10.6 |
| AuditRecordNotFound | E0829 | `@trusted(audit: K)` names a `K` that has no record in the package's `audits.toml`, or whose record has an empty `claim` | FFI | §9.1 |
| AuditRecordUnknownKey | E0830 | A record in `audits.toml` holds a key other than `claim` and `pins`. The message names the allowed keys and the nearest one (see *Conventions*) | FFI | §9.1 |
| TrustedRequiresAudit | E0836 | `@trusted` written without a non-empty `audit:` identifier | FFI | §9.1 |
| AuditGatedSuppression | E0837 | An audit-gated diagnostic (`UnauditedFfi`, `RawBypassesParam`) named in `@allow(...)` or under `[lints]` — refused, not ignored, because neither channel records anything | FFI | §9.1 |
| UnknownDiagnosticName | E0842 | An `@allow` argument or `[lints]` key that does not identify a live diagnostic: a misspelled name, a retired name or code, or a code given to `@allow`. Refused, not ignored. No `@allow` or `[lints]` entry suppresses it. The `help:` line removes a retired entry, names the diagnostic for a code, or suggests the one nearest live name (see *Conventions*) | Linting | §4.16.8 |
| InvalidLintLevel | E0843 | A `[lints]` value that is not `"off"`, `"warn"` or `"error"`. Refused, not ignored: no `@allow`, `[lints]` entry or `--strict` changes it. Span on the value token; help lists the valid levels | Linting | §4.16.8 |
| NotAWarningName | E0847 | An `@allow` argument or `[lints]` key that names a live diagnostic not listed under *Warning Names*: an error, an info diagnostic or an internal compiler error. Refused, not ignored, at every level (`"error"` included). No `@allow` or `[lints]` entry suppresses it. The named error still fires at its own site. The `help:` line removes the entry, then gives the named error's repair (see *Conventions*) | Linting | §4.16.8 |
| FfiOffsetUnknownStride | E0838 | `Ptr.offset` needs a pointee with a C size (not `Void`, an `@ffi.opaque` handle or a type parameter) | FFI | §9.1.1 |
| NonHandlerWithItem | E0839 | A `with` item is neither a `Handler[E]` nor a scoped value (a `Scoped` type, `Closeable` types included). If it is a `Result` or an `Option`, the help says to add `?` | Effects | §4.7 |
| TraitContractMissingMethod | E0900 | Trait contract: required method not implemented | Trait contract | §3.6 |
| TraitContractWrongArity | E0901 | Trait contract: method has wrong argument arity | Trait contract | §3.6 |
| TraitContractParamMismatch | E0902 | Trait contract: method parameter type mismatch | Trait contract | §3.6 |
| TraitContractReturnMismatch | E0903 | Trait contract: method return type mismatch | Trait contract | §3.6 |
| TraitContractEffectMismatch | E0904 | Trait contract: method effect mismatch. Only a trait-method row with no `_` limits its impls; an impl-chosen `_` (no callback source) limits none (§4.15.2) | Trait contract | §3.6 |
| TraitContractExtraMethod | E0905 | Trait contract: impl declares method not in trait | Trait contract | §3.6 |
| TraitContractGenericMismatch | E0906 | Trait contract: generic-parameter mismatch | Trait contract | §3.6 |
| TraitContractSealedBuiltin | E0907 | Sealed built-in trait cannot be redefined or implemented for user types | Trait contract | §3.6 |
| PolyImplUnsupported | E0908 | Polymorphic impl header parses but is not yet compiled (project b1bdnh) | Trait contract | §3.6 |
| ImplBinderUnused | E0909 | Impl type-parameter binder unused in the impl header's type positions | Trait contract | §3.6 |
| TraitContractArgArity | E0910 | Impl supplies the wrong number of trait type arguments | Trait contract | §3.6 |
| MissingSupertraitImpl | E0911 | An impl of a trait whose supertrait the implementing type does not implement; every impl must satisfy each supertrait of its trait | Trait contract | §3.6 |
| TraitImplAddsPrecondition | E0912 | An impl method of a trait writes `@requires`; the impl inherits the trait method's `@requires` and may not add to it. The `note:` names the inherited contract; the `help:` names the fixes (move it to the trait, a refinement type in the trait's signature, a free fn) | Trait contract | §3b.2 |
| TrustOnTraitMethod | E0913 | `@verify(fallback: "trust")` on a trait method declaration; only `"runtime"` or `"error"` may be a trait default | Trait contract | §3b.2 |
| TraitContractKeywordMismatch | E0914 | An impl method does not repeat the keyword parameters of its trait method: the `*` marker is missing, added or in another place, a keyword name differs, or the keyword order differs. The `note:` points at the trait declaration and names the first part that differs; the `help:` prints the expected impl header with no defaults | Trait contract | §3.6 |
| TraitImplWritesDefault | E0915 | An impl method writes a default on a keyword parameter of its trait method; the impl inherits the trait's default and may not write one, even the same one. The `note:` names the inherited default; the `help:` says to delete the impl's default or to change the trait's | Trait contract | §3.6 |
| CircularPackageDep | E1002 | Circular package dependency | Modules | §10.5 |
| PrivateItemAccess | E1003 | Access to private item in another module | Modules | §10.5 |
| VersionConflict | E1004 | Diamond dependency — incompatible package versions | Modules | §10.5 |
| AmbiguousImport | E1005 | Two imports in one file bind one name (bare name or module qualifier) to different items; the check uses the name after `as`. A selective import binds its qualifier too, so `import a.x.{P}` + `import b.x.{Q}` is E1005 on `x`; help gives `import b.x as bx.{Q}`. Two imports of the same item get W0602 instead; a selective import's qualifier bound again to the same module gets nothing. Replaces W0602 on the colliding entry | Modules | §10.5 |
| ImportNotSelected | E1006 | Selective import does not list the referenced symbol | Modules | §10.5 |
| ModuleQualifiedType | E1007 | Type referenced via module-qualified path is invalid | Modules | §10.5 |
| InvalidModuleAnnotation | E1008 | `@module` value does not match parent package name | Modules | §10.1 |
| PackageEntryNotFound | E1009 | Package entry file `<pkg>/src/<name>.bl` is missing | Modules | §10.1 |
| OrphanFile | E1010 | Source file has no enclosing `blink.toml` | Modules | §10.1 |
| InvalidPackageName | E1011 | `[package].name` violates package-name grammar, is empty, or is not a string. Span on the value (§8.9.8); the empty case has its own message | Modules | §10.1, §8.9.8 |
| DuplicateSymbol | E1012 | A module-level declaration (`type`, alias, `trait`, `effect`, `fn`, `const`, `let`) takes a name that an import (`import` or `pub import`) binds: a listed name or the qualifier; the check uses the name after `as`. Replaces W0602 on that import entry | Modules | §10.5 |
| UnknownDependencyField | E1014 | A field that the spec does not define in a dependency entry (the inline table of a key in `[dependencies]` or `[dev-dependencies]`) or in a native-dependency entry. Span on the key; help offers the nearest field of that entry kind (see *Conventions*); a `note:` says that an unknown field changes what is built, so it is never ignored. Not suppressible: no `[lints]` entry changes it. The toolchain reports every unknown field, in source order, before the load fails. Not reported inside a section that W1001 reports | Manifest | §8.9.8 |
| DuplicateModuleBinding | E1016 | One module-scope name has two meanings: a module declares it twice (a `let` and a `fn`), or a module-scope `let`, `let mut`, `const` or `fn` takes the name of a variant of an enum in the same package or of a prelude enum. An import entry that binds a value with such a name is E1016 at the import entry; the fix is an item alias. A dependency's variant does not collide | Modules | §2.12.1 |
| UnsupportedEdition | E1017 | `[package] edition` is a string of four digits that is a year after the newest edition this toolchain knows. The file may be correct and the toolchain too old. Span on the value token. The message names the toolchain version and the newest known edition. Help: install a newer `blink`, and `blink editions` lists the known editions; it never offers a lower edition. No machine-applicable fix. No fallback edition. Not a warning: no `@allow` or `[lints]` entry lowers it (E0847). Checked for each package in the graph; a dependency adds a `note:` with a span on its entry in the dependent manifest, plus the chain from the root when it is not direct. W1001 and unknown-key warnings in the same manifest add a `note:` at the value that states the fact. `blink migrate --edition` and `blink editions --edition` give it with the span on the argument | Manifest | §8.9.8, §8.16.1 |
| InvalidEdition | E1018 | `[package] edition` names no edition and is not E1017: a string that is not a year, a year before the first edition, a year at or below the newest known edition that names no edition, or a value that is not a string. Span on the value token. Help: the nearest known edition (see *Conventions*; the candidates are the known editions), and `blink editions` lists them. Machine-applicable fix only for a TOML integer that names a known edition: it quotes the value. No fallback edition. Not a warning: no `@allow` or `[lints]` entry lowers it (E0847). Checked for each package in the graph; a dependency adds a `note:` with a span on its entry in the dependent manifest, plus the chain from the root when it is not direct. W1001 and unknown-key warnings in the same manifest add no note. `blink migrate --edition` and `blink editions --edition` give it with the span on the argument | Manifest | §8.9.8, §8.16.1 |
| InlineModuleNotSupported | E1015 | Inline `mod name { ... }` blocks are not supported | Modules | §10.1 |
| MissingManifestKey | E1019 | A required `blink.toml` key is absent. Covers today only: no `[package]` section (one diagnostic, span line 1 column 1, zero width) and `[package]` without `name` or `version` (one diagnostic per key, span the `[package]` header). An empty value is not this code. When an unknown-key diagnostic fired in `[package]` and that key is the nearest-name match for the missing key (see *Conventions*), adds a `note:` at it and the help says to rename it. A later required key needs its own vote | Manifest | §8.9.8 |
| InvalidPackageVersion | E1020 | `[package].version` is empty, not a string, or not a SemVer 2.0.0 version. Span on the value. Help says `"1.2"` is a dependency constraint, not a package version; for `"1"` and `"1.2"` it gives the padded version, not machine-applicable | Manifest | §8.9.8 |
| MissingDependencySource | E1021 | A dependency entry has no source. Span on the token that names the dependency: the key (inline form) or the whole `[header]` (table form). Help lists the sources the toolchain supports; when the entry holds a key that only some sources take (today `tag`, `git` only), it names every source that takes the key. Adds a `note:` at an unknown field in the entry that is the nearest-name match for a source key (candidates: source keys only) | Manifest | §8.9.8 |
| ConflictingDependencySources | E1022 | A dependency entry has two or more sources. Primary span on the second source key in source order; a label on each other source key. Help says an entry takes exactly one source and never picks one; no machine-applicable fix | Manifest | §8.9.8 |
| PackageNotDeclared | E1052 | Package not declared in blink.toml — Tier 2 package needs explicit dependency | Stdlib | §10.7.1 |
| UnexpectedToken | E1100 | Parser found a token in an unexpected position | Parser | §2 |
| UnexpectedTokenString | E1101 | Unexpected token inside string interpolation | Parser | §2 |
| UnexpectedTokenPattern | E1102 | Unexpected token inside match pattern | Parser | §2 |
| KeywordAsIdentifier | E1103 | Reserved keyword used where an identifier was expected | Parser | §2 |
| InterpParseFailure | E1106 | Interpolation expression inside a string failed to parse | Parser | §2.4 |
| EmptyBraceExpr | E1107 | Empty `{}` used in expression position (use `Map.new()`) | Parser | §2 |
| FileNotFound | E1108 | `#embed(...)` referenced a file that does not exist | Parser | §2.20 |
| MutFieldNotSupported | E1109 | `mut` keyword on struct field declaration | Parser | §2 |
| UnexpectedAnnotation | E1110 | Annotation used in unsupported position | Parser | §2 |
| UnknownIntrinsic | E1111 | Unknown compile-time intrinsic (`#name`) | Parser | §2.20 |
| UnexpectedCharacter | E1113 | The lexer found a character that starts no token | Lexer | §2 |
| EmptyUnicodeEscape | E1114 | `\u{}` with no hex digits | Lexer | §2.4 |
| UnicodeEscapeTooLong | E1115 | `\u{...}` with more than 6 hex digits | Lexer | §2.4 |
| InvalidUnicodeEscapeDigit | E1116 | A character in `\u{...}` that is not a hex digit | Lexer | §2.4 |
| UnterminatedUnicodeEscape | E1117 | `\u{` with no closing `}` | Lexer | §2.4 |
| SurrogateEscape | E1118 | `\u{...}` names a surrogate code point (0xD800–0xDFFF) | Lexer | §2.4 |
| UnicodeEscapeOutOfRange | E1119 | `\u{...}` names a value above 0x10FFFF | Lexer | §2.4 |
| UnicodeEscapeNeedsBraces | E1120 | `\uXXXX` or `\UXXXXXXXX` without braces; help writes `\u{...}` | Lexer | §2.4 |
| HexEscapeNotSupported | E1121 | `\x..` escape; help writes `\u{..}` | Lexer | §2.4 |
| NulInStr | E1122 | `"\0"` or `"\u{0}"`: a `Str` cannot hold NUL; help names `Bytes` | Lexer | §2.4 |
| UnknownEscape | E1123 | An escape that is not valid in its literal kind (string or char). Help lists the valid escapes. Where the escape has a known meaning in another language, the help gives the Blink fix first: `\e` `\a` `\v` → `\u{..}`; `"\'"` and `'\"'` → the plain quote; regex letters such as `\d` `\w` `\s` → raw string `#"..."#` | Lexer | §2.4 |
| EmptyCharLiteral | E1124 | `''` holds no character; help shows `' '` and notes that an empty `Str` is `""` | Lexer | §2.4 |
| MultiCharLiteral | E1125 | A char literal holds two or more scalar values (closed, or open to the end of the line); help shows the double-quoted `Str` | Lexer | §2.4 |
| UnterminatedLiteral | E1126 | A char, string, template or raw-string literal with no closer. Primary span on the opening delimiter, `note:` at the end of the line (char) or file (string); help names the exact closer, `#` count included | Lexer | §2.4 |
| MixedOperatorPrecedence | E1127 | An operand of an operator in one integer operator group (arithmetic, shift, `&`, `^`, `\|`) is a bare operator expression of a different group, e.g. `x << n + 1` or `x \| y & 3`. The `help:` line shows both groupings; the language server offers both rewrites, neither machine-applicable | Parser | §2.19 |
| QualifierAliasAfterList | E1128 | `as` after a selective import list (`import b.x.{Q} as bx`); the qualifier alias goes between the path and the list. Machine-applicable fix writes `import b.x as bx.{Q}` and keeps the list, item aliases included; the import is then checked as fixed, with no second diagnostic for the order | Parser | §10.5 |
| NonInitExpr | E1129 | The initializer of a module-level `let` or `let mut` is not a static expression: a call, a read of a module `let`, `if`/`match`/block/`with`, string interpolation, `return` or `?`. One diagnostic per initializer; primary span and label on the first part that is not static, secondary labels on the rest. Help gives the fix for the kind: compute in `main` or fill a `let mut` on first use (with its `State` cost), make the source a `const`, or move the code into a function | Type checking | §2.12.1 |
| InterpDoubleBrace | E1130 | The first token of a string hole's expression is `{`, whitespace skipped, in every string form and depth: `"{{x}}"`, `"{ {x} }"`, `t"{{x}}"`, `#"#{{x}}"#`. `#"{{x}}"#` holds no hole and is not this error. Help: for a literal brace, write `\{` or use `#"..."#`; to start the expression with a block, wrap it in `( )` | Parser | §2.4 |
| ListTypeBrackets | E1131 | Square brackets with no name before them in a type position (`xs: [Int]`, `-> [Str]`, `Map[Str, [Int]]`). Machine-applicable fix writes `List[T]`. A list literal or spread in an expression is not this error. No warning release | Parser | §3.2 |
| OptionTypeLongForm | E1132 | `Option[T]` in a type position: an annotation, a type argument inside another type, or an explicit type-argument list at a call. Machine-applicable fix writes `T?` (`List[Option[Int]]` → `List[Int?]`, `Option[Option[Int]]` → `Int??`). `Option` as a path (`Option.Some`), the self type of an `impl` header and a trait bound are not this error. No warning release | Type checking | §3.2 |
| JumpNotAllowedHere | E1133 | A jump (`return`, `return e`, `break`, `continue`) in a position where it may not stand, for example `let x = return 3`, `f(return 1)`, `1 + return 2`, the left operand of `??` or an operand of `&&` or `\|\|`. The message names the keyword: "`return` cannot stand here: a jump is not an expression". The note lists the four legal positions: as a statement, as the tail of a block, as the body of a match arm that has no braces, and as the right operand of `??`. Default help: put the jump in its own statement before this line; for an operand of `&&` or `\|\|`, the help shows the `if !cond { return e }` form. A jump in parentheses (`o ?? (return 0)`) is this error, because parentheses wrap an expression; the fix removes the parentheses and is machine-applicable | Parser | §2 |
| ModuleNotFound | E1200 | Import statement referenced a module that could not be found | Modules | §10.1 |
| InvalidStringBackedEnum | E1201 | String-backed enum variant value is not a string literal | Type checking | §3 |
| ContractPredicateNotDecidable | E1300 | Contract predicate uses construct outside SMT-decidable subset | Refinement contracts | §3b |
| EffectfulCallInPredicate | E1301 | Predicate calls a function with declared effects | Refinement contracts | §3b |
| ImpureCallInPredicate | E1302 | Predicate calls a function not marked `@pure` | Refinement contracts | §3b |
| LoopInPredicate | E1303 | Predicate uses `while`/`for`/`loop` | Refinement contracts | §3b |
| ResultOutsideEnsures | E1304 | `result` referenced outside an `@ensures` predicate | Refinement contracts | §3b |
| OldOutsideEnsures | E1305 | `old(_)` referenced outside an `@ensures` predicate | Refinement contracts | §3b |
| AssignmentInPredicate | E1306 | Predicate contains an assignment | Refinement contracts | §3b |
| ImpureBodyForPureAnnotation | E1307 | `@pure` function has a non-empty effective row, `State` included | Refinement contracts | §3b.2, §4.16.3 |
| ModifiesArgNotSimplePath | E1308 | `@modifies` argument is not a simple path | Refinement contracts | §3b |
| RecursiveContractPredicate | E1309 | A contract predicate of fn `f` calls `f`, directly or through a cycle of contract predicates (body calls are not edges); the diagnostic prints the cycle | Refinement contracts | §3b.2 |
| MapKeyNotHashable | E1400 | `Map` key / `Set` element type does not implement `Hash` (Float, container, `Bytes`/`StringBuilder`, `fn`, or a user type with no `Hash` impl, derived or written) | Generic collections | §3.6 |
| NonDerivableTrait | E1401 | A `@derive(Hash/Eq/Ord/Serialize/Deserialize)` field's type does not implement the derived trait. For `Serialize` and `Deserialize` this includes a field declared `Option[Option[T]]` (`T??`), read after alias expansion and before generic substitution; the help writes a user enum | Generic collections | §3.6, §3.6.2 |
| NotDerivable | E1402 | A `@derive` argument does not denote a derivable compiler-known trait by identity: a user trait, a local trait that shadows a prelude trait, a compiler-known trait @derive cannot synthesize, or a name no trait in scope has; for a shadow, help gives `import blink.core.{X as Y}` and `@derive(Y)` | Generic collections | §3.6.1, §10.6 |
| ContractUnverifiable | V0003 | The outcome of a `@requires`/`@ensures` is Unknown, and the effective policy is `@verify(fallback: "error")` (own, or for an impl method the trait method's default), or the predicate is not executable and has no `"trust"`. The message says when no solver ran, and names the trait method when the policy is inherited | Contract verification | §3b.4 |

---

## Warning Names

| Name | Code | One-line | Category | Spec ref |
|------|------|----------|----------|----------|
| RawBypassesParam | W0310 | A `Raw[T]` was folded into a `Template[C]`, bypassing query parameterization. Audit-gated: `@trusted(audit: K)` is its only suppression channel — `@allow` and `[lints]` are refused | Contracts | §3b.5 |
| UnknownMethod | W0501 | Method name resolves to nothing and the receiver's type is not known at the call | Method resolution | §3c.4 |
| PartialHandler | W0545 | A handler expression for an effect marked `@handle_all` (or one of its sub-effects) omits a primitive operation of the effect it handles. Derived operations (with a body in the effect declaration) never count. Fires in all code. Silenced by writing the operation (any body; `default.op(args)` forwards on purpose), `@allow` or `[lints]`. Machine-applicable fix: adds each missing operation with its exact signature and the body `default.op(args)`. The help adds a note: `default.<op>()` answers from the outer handler; if the handler answers `<other op>` from its own state, answer `<op>` from the same state. When the omitted operation returns an opaque type, the help also names the `pub` type-scoped functions that build it (for `Time.monotonic`: `Monotonic.from_offset`) | Effects | §4.7.1 |
| IncompleteStateRestore | W0550 | Speculative lookahead saves some but not all written bindings | Mutation analysis | §4.16 |
| UnrestoredMutation | W0551 | Function writes module-level state without restoring it in a speculative context | Mutation analysis | §4.16 |
| ModuleLetMutNeverWritten | W0552 | A module-level `let mut` that no code in its module writes; its readers carry `State` for no reason. Machine-applicable fix: declare it with `let` | Mutation analysis | §4.16.2 |
| UnusedVariable | W0600 | Variable declared but never read | Linting | §6 |
| SetButNotRead | W0601 | Variable assigned but value never read | Linting | §6 |
| UnusedImport | W0602 | Module imported but no symbols referenced | Linting | §6 |
| ShadowedVariable | W0603 | Variable shadows another with the same name in an outer scope | Linting | §6 |
| UnusedTypeParamBinder | W0604 | Type parameter occurs nowhere in the declaration or its body; the binder is removable | Linting | §3.4 |
| UnusedResult | W0605 | Reserved, not yet emitted. A `Result[T, E]` value is dropped by a bare expression statement; `let _ =` opts out. The `fs` decision voted this lint; the constant and `blink explain` text land with the emit site | Linting | §3 |
| DiscardedCollectionCopy | W0606 | A statement drops the result of a `ListOps`, `MapOps` or `SetOps` method that does not mutate and returns the receiver's type (`append`, `slice`, `reverse`, `sort` and `sort_by` on `List`, `union` on `Set`), so the call does nothing. Mutating methods never warn; `let _ =` opts out. Suppress with `@allow(DiscardedCollectionCopy)` or `W0606 = "off"` under `[lints]` | Linting | §3.2.2 |
| ScopedValueWithoutWith | W0610 | A scoped value (a `Scoped` type, `Closeable` types included) reaches anything other than a `with` item (flow-based). Suppress with `@allow(ScopedValueWithoutWith)`; `@trusted(audit: K)` does not suppress it; upgrade to an error with `W0610 = "error"` under `[lints]` | Resources | §5.5 |
| ScopedValueEnteredTwice | W0611 | A scoped value (a `Scoped` type, `Closeable` types included) reaches more than one `with` item on one execution path, including a `with` in a loop that enters a value built outside it, unless every path after that `with` leaves the loop; a copy is the same value (flow-based, same analysis as W0610). Suppress with `@allow(ScopedValueEnteredTwice)`; `@trusted(audit: K)` does not suppress it; upgrade to an error with `W0611 = "error"` under `[lints]` | Resources | §5.5 |
| UnreachableCode | W0700 | Code follows an unconditional return/break/continue | Linting | §6 |
| ArenaEffectRedundant | W0701 | `! Arena` on a function where every Arena call is already inside `with arena { }` | Arena | §5.2 |
| TodoInCode | W0703 | A call resolves to the built-in `todo()`. Fires in every context, test blocks included; in a test the `help:` line names `@skip`. `unreachable()` has no warning | Linting | §2.20 |
| DivisionByLiteralZero | W0704 | The divisor of an integer `/` or `%` is an integer literal 0, with optional parentheses and unary `-`; the expression always panics. A `const` reference or a `let` binding with the value 0 does not trigger it. Fires in a branch that never runs; does not fire inside an `assert_panics` body | Linting | §3.6 |
| PanicInLibrary | W0705 | A reference resolves to the built-in `panic()` (a call or a value use) outside test blocks, in a library package: one whose entry module `src/<name>.bl` declares no `fn main`. Private functions included; `todo()` and `unreachable()` exempt. The one `help:` names `Result` with the enclosing function's return type; the notes give the scope fact, `unreachable()` for a path that can never run, and `@allow`. No machine-applicable fix. Suppress with `@allow(PanicInLibrary)`; `@trusted(audit: K)` does not suppress it; set the level with `W0705 = "off"` or `"error"` under `[lints]` | Linting | §2.20 |
| NegativeZeroComparison | W0706 | An operand of a `Float` or `F32` comparison is a written negative zero: one unary `-` over a float literal with the value zero, with optional parentheses (`-(-0.0)` does not match). Covers calls that resolve to the `Float`/`F32` impl of `==`, `!=`, `eq`, `ne`, `<`, `<=`, `>`, `>=`, `cmp`, `ieee_eq`, and `assert_eq`/`assert_ne` at `T = Float`/`F32`; either operand, also when both are literals. A `const` reference or a `let` binding that holds -0.0 does not trigger it; nor do `min`, `max` or `contains`. Fires in a branch that never runs, in test blocks and in `assert_panics` bodies. The `help:` lines name `is_sign_negative()`; no machine-applicable fix. Suppress with `@allow(NegativeZeroComparison)`; set the level with `W0706 = "off"` or `"error"` under `[lints]` | Linting | §3.6 |
| FloatSelfComparison | W0707 | The two operands of a `Float` or `F32` `==`, `!=`, `<`, `<=`, `>` or `>=` are the same local, parameter or field path, written with the same tokens; the result never changes because `NaN == NaN`. Calls and indexing do not match. `<`/`>` say "always false" with no NaN reason. The `help:` line names the replacement (`x != x` -> `x.is_nan()`; `==`/`<=`/`>=` -> `!x.is_nan()`); a suggested fix only, never applied by `blink fix`. Suppress with `@allow(FloatSelfComparison)`; set the level with `W0707 = "off"` or `"error"` under `[lints]` | Linting | §3.6 |
| LiteralArithmeticOverflow | W0708 | An integer operation in a tree of integer literals always overflows its type: leaves are integer literals (a negative literal is a leaf), nodes are parentheses, unary `-` and `+ - * / %`; each operation is checked at the type the checker gives it (`-(-128)` at `I8` warns; `-128` does not). One warning for each tree, at the first operation that fails. A `const` reference or a `let` binding stops the tree. Not for `<<` or `>>`; a literal 0 divisor is W0704 only. Not in a const context (E0546 there). Fires in a branch that never runs; does not fire inside an `assert_panics` body. Suppress with `@allow(LiteralArithmeticOverflow)`; set the level with `W0708 = "off"` or `"error"` under `[lints]` | Linting | §3.6 |
| OverrideOfDeprecatedDefault | W0731 | `impl` overrides a trait default marked `@deprecate_override` | Trait sealing | §3.6 |
| SealedMethodNameCollision | W0734 | A method in an `impl` for a built-in type has the same name as a method a sealed trait gives that type; unqualified calls of the name are E0522. Fires at the method only, never at calls. On by default, never an error, no effect on resolution | Method resolution | §3c.4 |
| UnauditedFfi | W0800 | Unaudited foreign function call. Audit-gated: `@trusted(audit: K)` is its only suppression channel — `@allow` and `[lints]` are refused | FFI | §9.1 |
| MissingCanonicalHeader | W0812 | `@ffi.struct` header not declared in blink.toml | FFI | §9.2.1 |
| RestatedInheritedEnsures | W0900 | An impl `@ensures` restates a predicate it already inherits from the trait method | Trait contract | §3b.2 |
| RedundantVerifyFallback | W0901 | An explicit `@verify(fallback: "runtime")` is the same as the policy without it; autofix removes it. Quiet where it replaces a trait method's `"error"` | Contract verification | §3b.4 |
| VerifyWithoutContract | W0902 | `@verify` on a fn with no `@requires` and no `@ensures`, own or inherited; autofix removes it | Contract verification | §3b.4 |
| ContractAlwaysFails | V0002 | A `@requires` (or a `@where` refinement, as an implied `@requires`) is false on every run that reaches the call; with no solver, every argument the predicate reads is a literal at the call site and the folded predicate is `false`. The runtime check stays. Fires in a branch that never runs; does not fire inside an `assert_panics` body; fires under every `@verify` value; does not fire when the fold fails. `@requires` only, not `@ensures`. A counterexample on a dynamic input is not V0002 (it is Unknown, see V0004). Suppress with `@allow(ContractAlwaysFails)`; set the level under `[lints]` | Contract verification | §3b.4 |
| ShadowedDependency | W1000 | An import matches both a module in the local `src/` and a dependency; the local module wins | Modules | §10.5 |
| UnknownManifestSection | W1001 | A top-level `blink.toml` section that the spec does not define. Span on the `[header]`; help offers the nearest defined section (see *Conventions*). Promotable by `--strict` and `[lints]`. E1200 and E1052 add a `note:` that points at it when both fire in one build | Manifest | §8.9.8 |
| UnknownManifestKey | W1002 | A key that the spec does not define in `[package]` or `[capabilities]`. Span on the key; help offers the nearest key of the same table (see *Conventions*; the candidates are the keys of that table only). Promotable by `--strict` and `[lints]`. Not reported inside a section that W1001 reports. When `[package]` lacks a required key and this key is its nearest-name match, `MissingManifestKey` (E1019) adds a `note:` that points at it | Manifest | §8.9.8 |
| ShadowedPreludeName | W1010 | A `type`, type alias, `trait` or `effect` declaration takes a compiler-known type name or prelude trait name that is not reserved; it shadows the builtin in its module. The `help:` line names the `import blink.core.{X as Y}` (or `blink.ffi`) escape | Modules | §10.6 |
| DeprecatedUsage | W2000 | Use of an item annotated `@deprecated` | Linting | §6 |

---

## Info Names

Info diagnostics never fail a build. They are silent in terminal output by default and show in reports and structured output.

| Name | Code | One-line | Category | Spec ref |
|------|------|----------|----------|----------|
| ContractProven | V0001 | The solver proved a contract; it has no runtime check | Contract verification | §3b.4 |
| ContractRuntimeChecked | V0004 | A contract's outcome is Unknown and it has a runtime check; the source is `default`, `explicit` or `inherited(Trait.method)` | Contract verification | §3b.4 |
| EscapeHeavyString | V1100 | A `"..."` literal (not `t"..."`) with 3 or more `\"`, `\{` and `\\` escapes, which a `#"..."#` literal of depth 1 to 3 writes with the same value. Machine-applicable fix: that literal at the smallest depth that fits. | String literals | §2.4.2 |

---

## Retired Codes

A retired code and its name are never reused (see *Conventions*). `blink explain` on a retired name or code says it is retired and names the codes that replace it. Naming one in `@allow` or as a `[lints]` key is `UnknownDiagnosticName` (E0842). A Code cell of "—" means this catalog published the name, but no compiler ever emitted it under a code.

| Name | Code | Retired because | Replaced by |
|------|------|-----------------|-------------|
| CallSiteTypeArgs | E0307 | It refused explicit type application at a call, which §3.4 *Explicit Type Application* makes legal | TypeArgArity (E0303), NoIndexOperator (E0313), TypeArgsWithoutCall (E0314) |
| WithPtrBodyTooComplex | E0816 | It rejected a `Bytes.with_ptr` body of more than one expression, an inlining limit of the old codegen; §9.1.3 lets the body be any `fn(Ptr[U8]) -> R` | None |
| CloseableWithoutScope | — | The lint it named now covers every scoped value, `Closeable` types included, under a new name. Its old code, W0600, belongs to `UnusedVariable` | ScopedValueWithoutWith (W0610) |
| UnknownDerive | E1112 | It matched a `@derive` argument by spelling. A `@derive` argument now resolves by scope (§10.6) | NotDerivable (E1402) |
| BitwisePrecedence | W0702 | It warned on a bitwise operator with a comparison operand. Bitwise operators now bind tighter than comparison (§2.19), and a mix of operator groups is a parse error | MixedOperatorPrecedence (E1127) |

---

## Compiler-Implemented Codes

The self-hosting compiler (`src/codegen_types.bl`, `src/codegen_expr.bl`) currently implements these error codes:

| Code | Name | Implementation |
|------|------|---------------|
| E0004 | NonExhaustiveMatch | `typecheck.bl` — `tc_check_match_exhaustive`, on a match whose scrutinee resolves to a declared enum, or to a type parameter of the function being checked (`tc_check_type_param_match_exhaustive`: only an unguarded arm that matches every value covers it). Under-approximating: Int/Str/Char ranges, tuple/struct patterns and nested refutable sub-patterns contribute nothing rather than risk a false positive |
| E0005 | InconsistentPatternBindings | `typecheck.bl` — `tc_check_or_pattern_bindings`, from the match statement walk, for each OR-pattern in an arm's pattern at any depth |
| E0500 | UndeclaredEffect | `typecheck.bl` — `tc_check_effect_rows`, at each call to a fn or method that declares effects, each user effect operation, and each `! Arena` callee, in every fn but `main`. Not yet checked: a builtin namespace call (`io.println`), the declared row of an `@ffi` callee, and test blocks |
| E0501 | CapabilityBudgetExceeded | `typecheck.bl` — `@capabilities` budget check |
| E0502 | QuestionMarkInvalidOperand | `codegen_expr.bl` — `?` operator type check (to move to typecheck phase) |
| E0513 | CoalesceRequiresOption | `codegen_expr.bl` — `??` operator type check |
| E0827 | SkipOutsideTest | `typecheck.bl` — rejects `skip()` outside a test body (via the §2.20 test-only symbol fence) |
| E0835 | XfailMissingReason | `typecheck.bl` — rejects `test.failing(...)` with a missing or empty `reason:` |
| E0508 | QuestionMarkResultInNonResult | `codegen_expr.bl` — `?` on Result in non-Result function |
| E0509 | QuestionMarkOptionInNonOption | `codegen_expr.bl` — `?` on Option in non-Option function |
| E0512 | QuestionMarkErrorMismatch | Not yet implemented — requires type checker |
| E0504 | UndefinedFunction | `typecheck.bl` — name resolution + `codegen_expr.bl` — codegen |
| E0505 | UnresolvedMethod | `typecheck.bl` — unresolved method on any receiver whose type is known: struct/enum, and the builtin scalars/containers (primary) + `codegen_methods.bl` — method dispatch (fail-open backstop) |
| E0506 | UndefinedVariable | `typecheck.bl` — name resolution |
| E0507 | UnknownType | `typecheck.bl` — name resolution |
| E0547 | NoSuchVariant | `typecheck.bl` — `tc_pattern_fault`, from the pattern walk `tc_check_pattern_types` at every depth (match arms, nested matches, for-in), including a bare uppercase name with no payload in a match arm, and the qualified construction sites (`K.Zed`, `K.Zed(..)`, `K.Zed {..}`) via `tc_report_no_such_variant_value`. Codegen `UnknownVariant` stays as an internal-error backstop |
| E0308 | EnumPatternNeedsEnumScrutinee | `typecheck.bl` — `tc_pattern_fault` (`OnScalar`, `NoVariants`) through `tc_report_pattern_fault`, the same lookup as E0547, before mono, so a type parameter is reported in the generic function. The bind and guard helps come from `tc_bare_name_on_non_enum_help` |
| E0519 | AmbiguousConstruction | `typecheck.bl` — `tc_report_ambiguous_construction`, when `tc_pick_bare_variant` (or `tc_bare_variant_from_program` for a brace literal) finds two or more enums, a prelude carrier counting, for a bare variant with no expected type: at a nullary name, a payload call and a brace literal |
| W0501 | UnknownMethod | `typecheck.bl` — name resolution records the call, inference reports it (soft class only: the receiver's type is a bare typevar or unresolved at the call; a KNOWN receiver type is E0505 instead) |
| E1004 | VersionConflict | `compiler.bl` — lockfile version conflict validation in `ensure_lockfile_loaded()` |
| V0003 | ContractUnverifiable | `typecheck.bl` — `tc_check_contract_verifiable`, one error per contract. With no solver, every contract without `@verify` gets it |
| E1008 | InvalidModuleAnnotation | `compiler.bl` — @module annotation validation in `load_module()` |
| E1052 | PackageNotDeclared | `compiler.bl` — Tier 2 stdlib import without blink.toml dependency |
