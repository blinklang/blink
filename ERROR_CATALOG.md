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
- **Codes** are secondary comblink identifiers (E/W + 4 digits). Codes are never reused after retirement.
- **Suppression** uses names: `@allow(NonExhaustiveMatch)`.
- **`blink explain <name>`** prints a detailed explanation (future — not yet implemented).

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
| E07xx | Method resolution / arena / coherence |
| E08xx | FFI |
| E09xx | Module capabilities / trait contracts |
| E10xx | Module resolution / imports |
| E13xx | Refinement contracts (predicate sublanguage) |
| I00xx | Internal compiler errors (ICE) |

---

## Internal Compiler Errors (ICE)

Internal compiler errors indicate a bug in the compiler itself, not in your code.
If you encounter one, please report it at https://github.com/blinklang/blink/issues.

ICE codes use the `I` prefix. They cannot be suppressed with `@allow`.

| Name | Code | One-line |
|------|------|----------|
| *(reserved for future use)* | I0001+ | Internal compiler errors will be cataloged as they are defined |

---

## Error Names

| Name | Code | One-line | Category | Spec ref |
|------|------|----------|----------|----------|
| TypeError | E0300 | Type mismatch detected during type checking | Type checking | §3 |
| TemplateMismatch | E0310 | String template parameter type does not match argument | Type checking | §3 |
| UndeclaredEffect | E0500 | Callee requires effect not declared by caller | Effects | §4.5 |
| CapabilityBudgetExceeded | E0501 | Function effect exceeds module `@capabilities` budget | Effects | §4.8 |
| QuestionMarkInvalidOperand | E0502 | `?` operator used on non-Result, non-Option type | Type checking | §3c.2 |
| UndefinedFunction | E0504 | Call to undefined function | Name resolution | §6.3 |
| UnresolvedMethod | E0505 | Unresolved method call on variable | Name resolution | §6.3, §3c.4 |
| UndefinedVariable | E0506 | Reference to undefined variable | Name resolution | §6.3 |
| UnknownType | E0507 | Reference to undefined type | Name resolution | §6.3 |
| QuestionMarkResultInNonResult | E0508 | `?` on Result in function not returning Result | Type checking | §3c.2 |
| QuestionMarkOptionInNonOption | E0509 | `?` on Option in function not returning Option | Type checking | §3c.2 |
| MissingKeywordArg | E0510 | Required keyword argument not supplied at call site | Name resolution | §2 |
| InvalidKeywordArg | E0511 | Keyword argument name does not match any parameter | Name resolution | §2 |
| QuestionMarkErrorMismatch | E0512 | `?` error type mismatch — inner E1 ≠ function return E2 | Type checking | §3c.2 |
| CoalesceRequiresOption | E0513 | `??` operator used on non-Option value | Type checking | §3c.2 |
| CloseableEscapesScope | E0601 | `Closeable` value escapes `with...as` scope | Resources | §5.5 |
| ArenaValueEscapes | E0700 | Arena-scoped value escapes arena scope | Arena | §5.2 |
| ArenaTypeContainsCycle | E0701 | Type crossing `with arena { }` boundary contains a cycle | Arena | §5.2 |
| ArenaClosureTailUnsupported | E0702 | Closure-typed arena tail cannot be promoted (umbrella) | Arena | §5.2 |
| ArenaClosureTailNonLiteral | E0702a | Closure-typed arena tail isn't a literal bound in this block | Arena | §5.2 |
| ArenaClosureUnsupportedCapture | E0702d | Closure-tail capture kind unsupported by descriptor walker | Arena | §5.2 |
| FfiFunctionPublic | E0801 | FFI function cannot be `pub` | FFI | §9.1 |
| FfiNoEffects | E0802 | `@ffi` function declares no effects | FFI | §9.1 |
| ContractOnFfi | E0803 | `@requires`/`@ensures` not allowed on `@ffi` function | FFI | §9.1, §3b |
| InvalidPtrTypeParam | E0810 | Invalid `Ptr[T]` type parameter | FFI | §9.1.1 |
| PtrOutsideFfiContext | E0811 | `Ptr[T]` used outside FFI context | FFI | §9.1.1 |
| FfiStructGcField | E0812 | `@ffi.struct` field uses GC-managed or non-FFI type | FFI | §9.1.1 |
| FfiOffsetOnSingleton | E0813 | `Ptr.offset(i)` called on single-cell allocation | FFI | §9.1.1 |
| BytesGrowInWithPtr | E0814 | Bytes-growing call inside `bytes.with_ptr` closure | FFI | §9.1.1 |
| PinnedBytesEscape | E0815 | Pinned Bytes receiver escapes its `with_ptr` closure | FFI | §9.1.1 |
| WithPtrBodyTooComplex | E0816 | `Bytes.with_ptr` body is not a single inlinable expression | FFI | §9.1.1 |
| BytesPtrCastForbidden | E0817 | Bytes coerced to `Ptr[U8]` outside `with_ptr` | FFI | §9.1.1 |
| MissingNativeDep | E0820 | `@ffi` references undeclared native dependency | FFI | §9.2.1 |
| NativeDepUnavailableCrossTarget | E0821 | Native dependency unavailable for cross-target | FFI | §9.2.1 |
| FfiOffsetUnknownStride | E0822 | `Ptr.offset` requires `@ffi.struct` element type | FFI | §9.1.1 |
| TraitContractMissingMethod | E0900 | Trait contract: required method not implemented | Trait contract | §3.6 |
| TraitContractWrongArity | E0901 | Trait contract: method has wrong argument arity | Trait contract | §3.6 |
| TraitContractParamMismatch | E0902 | Trait contract: method parameter type mismatch | Trait contract | §3.6 |
| TraitContractReturnMismatch | E0903 | Trait contract: method return type mismatch | Trait contract | §3.6 |
| TraitContractEffectMismatch | E0904 | Trait contract: method effect mismatch | Trait contract | §3.6 |
| TraitContractExtraMethod | E0905 | Trait contract: impl declares method not in trait | Trait contract | §3.6 |
| TraitContractGenericMismatch | E0906 | Trait contract: generic-parameter mismatch | Trait contract | §3.6 |
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
| InlineModuleNotSupported | E1015 | Inline `mod name { ... }` blocks are not supported | Modules | §10.1 |
| PackageNotDeclared | E1052 | Package not declared in blink.toml — Tier 2 package needs explicit dependency | Stdlib | §10.7.1 |
| UnexpectedToken | E1100 | Parser found a token in an unexpected position | Parser | §2 |
| UnexpectedTokenString | E1101 | Unexpected token inside string interpolation | Parser | §2 |
| UnexpectedTokenPattern | E1102 | Unexpected token inside match pattern | Parser | §2 |
| KeywordAsIdentifier | E1103 | Reserved keyword used where an identifier was expected | Parser | §2 |
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

---

## Warning Names

| Name | Code | One-line | Category | Spec ref |
|------|------|----------|----------|----------|
| RawBypassesParam | W0310 | `Raw()` bypasses query parameterization | Contracts | §3b.5 |
| UnknownMethod | W0501 | Method call could not be verified during type checking | Method resolution | §3c.4 |
| IncompleteStateRestore | W0550 | Speculative lookahead saves some but not all written bindings | Mutation analysis | §4.16 |
| UnrestoredMutation | W0551 | Function writes module-level state without restoring it in a speculative context | Mutation analysis | §4.16 |
| UnusedVariable | W0600 | Variable declared but never read | Linting | §6 |
| SetButNotRead | W0601 | Variable assigned but value never read | Linting | §6 |
| UnusedImport | W0602 | Module imported but no symbols referenced | Linting | §6 |
| ShadowedVariable | W0603 | Variable shadows another with the same name in an outer scope | Linting | §6 |
| UnreachableCode | W0700 | Code follows an unconditional return/break/continue | Linting | §6 |
| ArenaEffectRedundant | W0701 | `! Arena` on a function where every Arena call is already inside `with arena { }` | Arena | §5.2 |
| BitwisePrecedence | W0702 | Bitwise `&`/`|` mixed with comparison without parentheses | Linting | §6 |
| UnauditedFfi | W0800 | Unaudited foreign function call | FFI | §9.1 |
| MissingCanonicalHeader | W0812 | `@ffi.struct` header not declared in blink.toml | FFI | §9.2.1 |
| DeprecatedUsage | W2000 | Use of an item annotated `@deprecated` | Linting | §6 |

---

## Compiler-Implemented Codes

The self-hosting compiler (`src/codegen_types.bl`, `src/codegen_expr.bl`) currently implements these error codes:

| Code | Name | Implementation |
|------|------|---------------|
| E0500 | UndeclaredEffect | `codegen_types.bl` — effect propagation check |
| E0501 | CapabilityBudgetExceeded | `typecheck.bl` — `@capabilities` budget check |
| E0502 | QuestionMarkInvalidOperand | `codegen_expr.bl` — `?` operator type check (to move to typecheck phase) |
| E0513 | CoalesceRequiresOption | `codegen_expr.bl` — `??` operator type check |
| E0508 | QuestionMarkResultInNonResult | `codegen_expr.bl` — `?` on Result in non-Result function |
| E0509 | QuestionMarkOptionInNonOption | `codegen_expr.bl` — `?` on Option in non-Option function |
| E0512 | QuestionMarkErrorMismatch | Not yet implemented — requires type checker |
| E0504 | UndefinedFunction | `typecheck.bl` — name resolution + `codegen_expr.bl` — codegen |
| E0505 | UnresolvedMethod | `codegen_methods.bl` — method dispatch (codegen phase) |
| E0506 | UndefinedVariable | `typecheck.bl` — name resolution |
| E0507 | UnknownType | `typecheck.bl` — name resolution |
| W0501 | UnknownMethod | `typecheck.bl` — name resolution (warning, may be false positive for struct field closures) |
| E1004 | VersionConflict | `compiler.bl` — lockfile version conflict validation in `ensure_lockfile_loaded()` |
| E1008 | InvalidModuleAnnotation | `compiler.bl` — @module annotation validation in `load_module()` |
| E1052 | PackageNotDeclared | `compiler.bl` — Tier 2 stdlib import without blink.toml dependency |
