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
- **Suppression** uses names: `@allow(NonExhaustiveMatch)`.
- **`blink explain <name>`** prints a detailed explanation (future — not yet implemented).
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
| W060x | Linting |
| W061x | Resource scope lints |
| E07xx | Method resolution / arena / coherence |
| E08xx | FFI |
| E09xx | Module capabilities / trait contracts |
| E10xx | Module resolution / imports |
| E13xx | Refinement contracts (predicate sublanguage) |
| E14xx | Generic collections / Hash + Eq bounds |
| V00xx | Contract verification outcomes |
| I00xx | Internal compiler errors (ICE) |

---

## Internal Compiler Errors (ICE)

Internal compiler errors indicate a bug in the compiler itself, not in your code.
If you encounter one, please report it at https://github.com/blinklang/blink/issues.

ICE codes use the `I` prefix. They cannot be suppressed with `@allow`.

| Name | Code | One-line |
|------|------|----------|
| UnsolvedTypeVarAtCodegen | I0001 | An unsolved type variable reached monomorphization — the front end should have reported `CannotInferType` (E0301) first |
| UnhandledIterableAtCodegen | I0002 | A `for` loop's iterable passed the front-end check but code generation has no emitter for its type |
| MisplacedIrKindAtPrint | I0003 | An IR node of the wrong class reached the C printer — a statement where a value is required, or the reverse |
| CodegenStageNotBuilt | I0004 | A code-generation stage this build does not contain was reached |
| PoisonedIrAtSeam | I0005 | A negative IR node id was handed to a producer that must embed it — the caller ignored a stop it had already been told about |

---

## Error Names

| Name | Code | One-line | Category | Spec ref |
|------|------|----------|----------|----------|
| NonExhaustiveMatch | E0004 | A `match` leaves an enum variant unhandled. Guarded arms do not contribute to coverage; a `_` or plain-binding arm makes the match exhaustive | Pattern matching | §3.9 |
| TypeError | E0300 | Type mismatch detected during type checking | Type checking | §3 |
| CannotInferType | E0301 | Inference left a type variable unbound — annotate the binding, or supply the type argument at the call when the callee's signature does not supply it. Reported where the repair attaches | Type checking | §3.4 |
| TypeArgArity | E0303 | A type-argument list has the wrong count for the declaration it applies to. In a type position that includes none (a bare `Channel`/`List`). At a callee or a struct-literal head, a written list of the wrong count (`decode[A, B](s)`, `plain[Int](3)`); an absent list there is left to inference. A non-generic declaration or a local value binds zero. Under- and over-application are one code. A rejected list supplies nothing: no E0301 or E0306 for that call's binders. Decided when the head resolves: at name resolution for a type or a path, once the receiver's type is known for a method | Name resolution | §3.4 |
| TraitBoundNotSatisfied | E0306 | A call's type argument (inferred or explicit) does not satisfy the type parameter's declared bound — checked against the arguments as written, before code generation | Type checking | §3.6 |
| TemplateMismatch | E0310 | String template parameter type does not match argument | Type checking | §3 |
| MissingReturn | E0311 | Control can reach the end of a block that must produce a value of type `R` along a path that yields `()` — a value-returning function whose tail can complete normally (a `while`/`for` tail, an `if` without `else`). The tail kind is carried as diagnostic data, not a separate code. Repair: add a trailing `return <value>`, or change the return type to `Option[R]`. A diverging tail (`panic`, or a `loop` no `break` targets) is accepted | Type checking | §3.3 |
| NoConversionImpl | E0312 | A conversion has no impl: `x.into()` and `T.from(x)` need `impl From[S] for T`, `T.try_from(x)` needs `impl TryFrom[S] for T`, with S the source's type (an alias is the type it names). Every type converts to itself. Repair: declare the impl, or use the named conversion (`.to_float()`, `.truncate()`, `.to_int_checked()`, `try_from`, `.to_string()`) | Type checking | §3c |
| NoIndexOperator | E0313 | A postfix `[...]` holds a value (`xs[1]`, `m["k"]`, `fns[0](x)`). Blink has no index operator. Decided by the bracket contents at name resolution, whether or not a call follows. Repair: `.get()` (returns `Option`), or `.0` for a tuple; no machine fix when a call follows. A store `xs[i] = v` is the same error: repair `.set(i, v)` (List, Bytes) or `.insert(k, v)` (Map), never `.insert` for a List | Name resolution | §3.4, §2.22 |
| TypeArgsWithoutCall | E0314 | A well-formed type-argument list with no call `(` or literal `{` after it (`let f = identity[Int]`). First help: remove the brackets when an expected type fixes the same arguments; annotate the binding when there is no expected type; no machine fix when they conflict | Type checking | §3.4 |
| UndeclaredEffect | E0500 | Callee requires effect not declared by caller. The declared row of an `@ffi` callee counts like any other row | Effects | §4.5 |
| CapabilityBudgetExceeded | E0501 | Function effect exceeds module `@capabilities` budget | Effects | §4.8 |
| QuestionMarkInvalidOperand | E0502 | `?` operator used on non-Result, non-Option type | Type checking | §3c.2 |
| UndefinedFunction | E0504 | Call to undefined function | Name resolution | §6.3 |
| UnresolvedMethod | E0505 | Unresolved method call on variable | Name resolution | §6.3, §3c.4 |
| UndefinedVariable | E0506 | Reference to undefined variable | Name resolution | §6.3 |
| UnknownType | E0507 | Reference to undefined type | Name resolution | §6.3 |
| QuestionMarkResultInNonResult | E0508 | `?` on Result in function not returning Result | Type checking | §3c.2 |
| QuestionMarkOptionInNonOption | E0509 | `?` on Option in function not returning Option | Type checking | §3c.2 |
| MissingKeywordArg | E0510 | A keyword parameter received no argument at all — the value is absent (contrast `UnlabeledKeywordArg`, where the value is present but unlabelled) | Name resolution | §2.13 |
| InvalidKeywordArg | E0511 | A call-site label names no keyword parameter of the callee — including a label written on a positional parameter | Name resolution | §2.13 |
| QuestionMarkErrorMismatch | E0512 | `?` error type mismatch — inner E1 ≠ function return E2 | Type checking | §3c.2 |
| CoalesceRequiresOption | E0513 | `??` operator used on non-Option value | Type checking | §3c.2 |
| AmbiguousMethodCall | E0522 | Unqualified method call resolves to a method defined by two or more implemented traits, a sealed built-in trait counting as one of them | Name resolution | §3c.4 |
| MissingDisplayImpl | E0523 | Interpolated `{expr}` type does not implement `Display` | Type checking | §3.6 |
| ReservedTypeName | E0524 | A `type`, type alias, `trait` or `effect` declaration takes a reserved name: `Self`, a scalar type that literal syntax produces, or `Void` | Name resolution | §10.6 |
| NoSuchField | E0525 | Field access names a field the struct, tuple, or opaque handle does not declare | Type checking | §3.2 |
| PositionalAfterKeyword | E0527 | A positional argument follows a labelled one in the same call | Name resolution | §2.13 |
| DuplicateKeywordArg | E0528 | The same call-site label appears twice in one call | Name resolution | §2.13 |
| UnlabeledKeywordArg | E0529 | A keyword parameter received its argument positionally — the value is present and unlabelled | Name resolution | §2.13 |
| RawOutsideTemplate | E0530 | A `Raw[T]` reached a position that does not consume it — only a `Template[C]` coercion does | Type checking | §3b.5 |
| PositionalParamDefault | E0531 | A default value written on a positional parameter — only parameters declared after `--` may carry one | Type checking | §2.13 |
| NonConstParamDefault | E0532 | A parameter default that is not a const expression | Type checking | §2.13, §2.21 |
| NonConstExpr | E0533 | The right-hand side of a `const` is not a const expression | Type checking | §2.21 |
| TemplateHoleType | E0534 | An interpolation hole in a `Template[C]` literal has a type outside the Template value set | Type checking | §3b.5 |
| EffectTypeAsValue | E0535 | An effect's type is written as the type of a value (`fn f(x: DB)`, `let x: DB`); it is valid only as a type argument | Type checking | §3b.5 |
| SubEffectAsType | E0536 | A sub-effect is written as a type (`Template[DB.Read]`); only a top-level effect gives a type | Type checking | §3b.5 |
| JsonTextForValue | E0537 | A `Str` is passed to a `from_json` that takes `JsonValue`, or `to_json()`'s result is used as a `Str`; the fix names `json.decode[T]` / `json.encode` | Type checking | §3.6.2 |
| UnknownEffect | E0538 | An effect row names an effect that is neither built-in nor declared. For `FFI` the help says a foreign call is not an effect and points to §9.1. When the name before the dot is a leaf effect, a note lists its operations and the help names the whole effect. No machine-applicable fix | Effects | §4.3, §4.12 |
| UnhandledEffect | E0539 | An effect reaches a root with no `with` that discharges it: a user-declared effect in `main`, or any effect in a test block. The header names the root (in `main`, or in test "..."); in `main` the help says user-declared effects have no root handler | Effects | §4.6, §2.20 |
| MixedEffectBody | E0541 | An effect body declares both operations and sub-effects; a body holds one or the other. The fix moves the operations into a new sub-effect with a placeholder name, never up to the parent | Parser | §4.12 |
| EffectNestingTooDeep | E0542 | A sub-effect declares a sub-effect; in v1 an effect tree has the top-level effect and one level of sub-effects | Parser | §4.12 |
| DuplicateEffectOp | E0543 | Two nodes of one top-level effect tree declare operations with the same name. The message names both declarations (`Metrics.Emit.get`, `Metrics.Query.get`) | Effects | §4.12 |
| CloseableEscapesScope | E0601 | `Closeable` value escapes `with...as` scope | Resources | §5.5 |
| MutableCaptureInSpawn | E0650 | A closure passed to `async.spawn` captures a `let mut` binding | Closures | §2.8 |
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
| ContractOnFfi | E0803 | `@requires`/`@ensures` not allowed on `@ffi` function | FFI | §9.1, §3b |
| InvalidPtrTypeParam | E0810 | Invalid `Ptr[T]` type parameter | FFI | §9.1.1 |
| PtrOutsideFfiContext | E0811 | `Ptr[T]` used outside FFI context | FFI | §9.1.1 |
| FfiStructGcField | E0812 | `@ffi.struct` field uses GC-managed or non-FFI type | FFI | §9.1.1 |
| FfiOffsetOnSingleton | E0813 | `Ptr.offset(i)` called on single-cell allocation | FFI | §9.1.1 |
| BytesGrowInWithPtr | E0814 | Bytes-growing call inside `bytes.with_ptr` closure | FFI | §9.1.1 |
| PinnedBytesEscape | E0815 | Pinned Bytes receiver escapes its `with_ptr` closure | FFI | §9.1.1 |
| BytesPtrCastForbidden | E0817 | Bytes coerced to `Ptr[U8]` outside `with_ptr` | FFI | §9.1.1 |
| FfiScopeNotWithResource | E0819 | An `FfiScope` value occurs somewhere other than as a `with ... as` resource — bound by `let`, passed, returned, stored, or written as a type argument (its libc arena would never be freed) | FFI | §9.1.1 |
| MissingNativeDep | E0820 | `@ffi` references undeclared native dependency | FFI | §9.2.1 |
| NativeDepUnavailableCrossTarget | E0821 | Native dependency unavailable for cross-target | FFI | §9.2.1 |
| BufOutsideFfiSurface | E0822 | The name `Buf` written outside the `@ffi.fn` / `@ffi.struct` surface — an annotated binding, a parameter or return type, a struct field, or a generic bound | FFI | §9.1.3.2 |
| CleanupPanickedDuringUnwind | E0824 | `exit(false)`/`close()` panicked during catchable unwind; original panic preserved, cleanup surfaces as warning | Test runner | §4.6.3 |
| IncompatibleStdlibArchive | E0840 | Installed stdlib archive built by a different toolchain than the linking compiler (ABI/struct-layout mismatch) — rejected at link time | FFI | §9.2.1 |
| SkipOutsideTest | E0827 | `skip()` called outside a `test { ... }` block | Type checking | §2.20 |
| AssertPanicsBodyReturned | E0831 | `assert_panics` body returned normally instead of panicking | Test runner | §2.20 |
| AssertPanicsMessageMismatch | E0832 | `assert_panics` panic message did not match expected pattern | Test runner | §2.20 |
| AssertPanicsOutsideTest | E0833 | `assert_panics` called outside a test | Test runner | §2.20 |
| AssertPanicsNestedExpectPanic | E0834 | `assert_panics` nested inside another `assert_panics` | Test runner | §2.20 |
| XfailMissingReason | E0835 | `test.failing(...)` missing or empty `reason:` | Type checking | §8.10.6 |
| AuditRecordNotFound | E0829 | `@trusted(audit: K)` names a `K` that has no record in the package's `audits.toml`, or whose record has an empty `claim` | FFI | §9.1 |
| AuditRecordUnknownKey | E0830 | A record in `audits.toml` holds a key other than `claim` and `pins`. The message names the allowed keys and the nearest one | FFI | §9.1 |
| TrustedRequiresAudit | E0836 | `@trusted` written without a non-empty `audit:` identifier | FFI | §9.1 |
| AuditGatedSuppression | E0837 | An audit-gated diagnostic (`UnauditedFfi`, `RawBypassesParam`) named in `@allow(...)` or under `[lints]` — refused, not ignored, because neither channel records anything | FFI | §9.1 |
| FfiOffsetUnknownStride | E0838 | `Ptr.offset` requires `@ffi.struct` element type | FFI | §9.1.1 |
| NonHandlerWithItem | E0839 | A `with` item without `as` is neither a `Handler[E]` nor a `BlockHandler` | Effects | §4.7 |
| TraitContractMissingMethod | E0900 | Trait contract: required method not implemented | Trait contract | §3.6 |
| TraitContractWrongArity | E0901 | Trait contract: method has wrong argument arity | Trait contract | §3.6 |
| TraitContractParamMismatch | E0902 | Trait contract: method parameter type mismatch | Trait contract | §3.6 |
| TraitContractReturnMismatch | E0903 | Trait contract: method return type mismatch | Trait contract | §3.6 |
| TraitContractEffectMismatch | E0904 | Trait contract: method effect mismatch | Trait contract | §3.6 |
| TraitContractExtraMethod | E0905 | Trait contract: impl declares method not in trait | Trait contract | §3.6 |
| TraitContractGenericMismatch | E0906 | Trait contract: generic-parameter mismatch | Trait contract | §3.6 |
| TraitContractSealedBuiltin | E0907 | Sealed built-in trait cannot be redefined or implemented for user types | Trait contract | §3.6 |
| PolyImplUnsupported | E0908 | Polymorphic impl header parses but is not yet compiled (project b1bdnh) | Trait contract | §3.6 |
| ImplBinderUnused | E0909 | Impl type-parameter binder unused in the impl header's type positions | Trait contract | §3.6 |
| TraitContractArgArity | E0910 | Impl supplies the wrong number of trait type arguments | Trait contract | §3.6 |
| CircularPackageDep | E1002 | Circular package dependency | Modules | §10.5 |
| PrivateItemAccess | E1003 | Access to private item in another module | Modules | §10.5 |
| VersionConflict | E1004 | Diamond dependency — incompatible package versions | Modules | §10.5 |
| AmbiguousImport | E1005 | Ambiguous import — name exists in multiple modules | Modules | §10.5 |
| ImportNotSelected | E1006 | Selective import does not list the referenced symbol | Modules | §10.5 |
| ModuleQualifiedType | E1007 | Type referenced via module-qualified path is invalid | Modules | §10.5 |
| InvalidModuleAnnotation | E1008 | `@module` value does not match parent package name | Modules | §10.1 |
| PackageEntryNotFound | E1009 | Package entry file `<pkg>/src/<name>.bl` is missing | Modules | §10.1 |
| OrphanFile | E1010 | Source file has no enclosing `blink.toml` | Modules | §10.1 |
| InvalidPackageName | E1011 | `[package].name` violates package-name grammar | Modules | §10.1 |
| DuplicateSymbol | E1012 | A module-level declaration (`type`, alias, `trait`, `effect`, `fn`, `let`) takes a name that a selective import (`import` or `pub import`) binds; the check uses the name after `as`. Replaces W0602 on that import entry | Modules | §10.5 |
| InlineModuleNotSupported | E1015 | Inline `mod name { ... }` blocks are not supported | Modules | §10.1 |
| PackageNotDeclared | E1052 | Package not declared in blink.toml — Tier 2 package needs explicit dependency | Stdlib | §10.7.1 |
| UnexpectedToken | E1100 | Parser found a token in an unexpected position | Parser | §2 |
| UnexpectedTokenString | E1101 | Unexpected token inside string interpolation | Parser | §2 |
| UnexpectedTokenPattern | E1102 | Unexpected token inside match pattern | Parser | §2 |
| KeywordAsIdentifier | E1103 | Reserved keyword used where an identifier was expected | Parser | §2 |
| InterpParseFailure | E1106 | Interpolation expression inside a string failed to parse | Parser | §2.4 |
| EmptyBraceExpr | E1107 | Empty `{}` used in expression position (use `Map()`) | Parser | §2 |
| FileNotFound | E1108 | `#embed(...)` referenced a file that does not exist | Parser | §2.20 |
| MutFieldNotSupported | E1109 | `mut` keyword on struct field declaration | Parser | §2 |
| UnexpectedAnnotation | E1110 | Annotation used in unsupported position | Parser | §2 |
| UnknownIntrinsic | E1111 | Unknown compile-time intrinsic (`#name`) | Parser | §2.20 |
| ModuleNotFound | E1200 | Import statement referenced a module that could not be found | Modules | §10.1 |
| InvalidStringBackedEnum | E1201 | String-backed enum variant value is not a string literal | Type checking | §3 |
| ContractPredicateNotDecidable | E1300 | Contract predicate uses construct outside SMT-decidable subset | Refinement contracts | §3b |
| EffectfulCallInPredicate | E1301 | Predicate calls a function with declared effects | Refinement contracts | §3b |
| ImpureCallInPredicate | E1302 | Predicate calls a function not marked `@pure` | Refinement contracts | §3b |
| LoopInPredicate | E1303 | Predicate uses `while`/`for`/`loop` | Refinement contracts | §3b |
| ResultOutsideEnsures | E1304 | `result` referenced outside an `@ensures` predicate | Refinement contracts | §3b |
| OldOutsideEnsures | E1305 | `old(_)` referenced outside an `@ensures` predicate | Refinement contracts | §3b |
| AssignmentInPredicate | E1306 | Predicate contains an assignment | Refinement contracts | §3b |
| ImpureBodyForPureAnnotation | E1307 | `@pure` function body contains a non-pure construct | Refinement contracts | §3b |
| ModifiesArgNotSimplePath | E1308 | `@modifies` argument is not a simple path | Refinement contracts | §3b |
| MapKeyNotHashable | E1400 | `Map` key / `Set` element type does not implement `Hash` (Float, container, `Bytes`/`StringBuilder`, `fn`, or a user type with no `Hash` impl, derived or written) | Generic collections | §3.6 |
| NonDerivableTrait | E1401 | A `@derive(Hash/Eq/Ord)` field's type does not implement the derived trait | Generic collections | §3.6 |
| ContractUnverifiable | V0003 | The solver can neither prove nor disprove a `@requires`/`@ensures`, and the fn has no `@verify(fallback: ...)` | Contract verification | §3b.4 |

---

## Warning Names

| Name | Code | One-line | Category | Spec ref |
|------|------|----------|----------|----------|
| RawBypassesParam | W0310 | A `Raw[T]` was folded into a `Template[C]`, bypassing query parameterization. Audit-gated: `@trusted(audit: K)` is its only suppression channel — `@allow` and `[lints]` are refused | Contracts | §3b.5 |
| UnknownMethod | W0501 | Method name resolves to nothing and the receiver's type is not known at the call | Method resolution | §3c.4 |
| IncompleteStateRestore | W0550 | Speculative lookahead saves some but not all written bindings | Mutation analysis | §4.16 |
| UnrestoredMutation | W0551 | Function writes module-level state without restoring it in a speculative context | Mutation analysis | §4.16 |
| UnusedVariable | W0600 | Variable declared but never read | Linting | §6 |
| SetButNotRead | W0601 | Variable assigned but value never read | Linting | §6 |
| UnusedImport | W0602 | Module imported but no symbols referenced | Linting | §6 |
| ShadowedVariable | W0603 | Variable shadows another with the same name in an outer scope | Linting | §6 |
| UnusedTypeParamBinder | W0604 | Type parameter occurs nowhere in the declaration or its body; the binder is removable | Linting | §3.4 |
| ScopedValueWithoutWith | W0610 | A `Closeable` or `BlockHandler` value reaches anything other than a `with` item (flow-based). Suppress with `@trusted(audit: K)`; upgrade to an error with `W0610 = "error"` under `[lints]` | Resources | §5.5 |
| UnreachableCode | W0700 | Code follows an unconditional return/break/continue | Linting | §6 |
| ArenaEffectRedundant | W0701 | `! Arena` on a function where every Arena call is already inside `with arena { }` | Arena | §5.2 |
| BitwisePrecedence | W0702 | Bitwise `&`/`|` mixed with comparison without parentheses | Linting | §6 |
| OverrideOfDeprecatedDefault | W0731 | `impl` overrides a trait default marked `@deprecate_override` | Trait sealing | §3.6 |
| SealedMethodNameCollision | W0734 | A method in an `impl` for a built-in type has the same name as a method a sealed trait gives that type; unqualified calls of the name are E0522. Fires at the method only, never at calls. On by default, never an error, no effect on resolution | Method resolution | §3c.4 |
| UnauditedFfi | W0800 | Unaudited foreign function call. Audit-gated: `@trusted(audit: K)` is its only suppression channel — `@allow` and `[lints]` are refused | FFI | §9.1 |
| MissingCanonicalHeader | W0812 | `@ffi.struct` header not declared in blink.toml | FFI | §9.2.1 |
| ShadowedPreludeName | W1010 | A `type`, type alias, `trait` or `effect` declaration takes a compiler-known type name or prelude trait name that is not reserved; it shadows the builtin in its module. The `help:` line names the `import blink.core.{X as Y}` (or `blink.ffi`) escape | Modules | §10.6 |
| DeprecatedUsage | W2000 | Use of an item annotated `@deprecated` | Linting | §6 |

---

## Retired Codes

A retired code and its name are never reused (see *Conventions*). `blink explain` on a retired name or code says it is retired and names the codes that replace it. A Code cell of "—" means this catalog published the name, but no compiler ever emitted it under a code.

| Name | Code | Retired because | Replaced by |
|------|------|-----------------|-------------|
| CallSiteTypeArgs | E0307 | It refused explicit type application at a call, which §3.4 *Explicit Type Application* makes legal | TypeArgArity (E0303), NoIndexOperator (E0313), TypeArgsWithoutCall (E0314) |
| WithPtrBodyTooComplex | E0816 | It rejected a `Bytes.with_ptr` body of more than one expression, an inlining limit of the old codegen; §9.1.3 lets the body be any `fn(Ptr[U8]) -> R` | None |
| CloseableWithoutScope | — | The lint it named now covers every `Closeable` and `BlockHandler` value, under a new name. Its old code, W0600, belongs to `UnusedVariable` | ScopedValueWithoutWith (W0610) |

---

## Compiler-Implemented Codes

The self-hosting compiler (`src/codegen_types.bl`, `src/codegen_expr.bl`) currently implements these error codes:

| Code | Name | Implementation |
|------|------|---------------|
| E0004 | NonExhaustiveMatch | `typecheck.bl` — `tc_check_match_exhaustive`, on a match whose scrutinee resolves to a declared enum. Under-approximating: Int/Str/Char ranges, tuple/struct patterns and nested refutable sub-patterns contribute nothing rather than risk a false positive |
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
| W0501 | UnknownMethod | `typecheck.bl` — name resolution records the call, inference reports it (soft class only: the receiver's type is a bare typevar or unresolved at the call; a KNOWN receiver type is E0505 instead) |
| E1004 | VersionConflict | `compiler.bl` — lockfile version conflict validation in `ensure_lockfile_loaded()` |
| V0003 | ContractUnverifiable | `typecheck.bl` — `tc_check_contract_verifiable`, one error per contract. With no solver, every contract without `@verify` gets it |
| E1008 | InvalidModuleAnnotation | `compiler.bl` — @module annotation validation in `load_module()` |
| E1052 | PackageNotDeclared | `compiler.bl` — Tier 2 stdlib import without blink.toml dependency |
