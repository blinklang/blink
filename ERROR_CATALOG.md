# Pact Error Catalog

Complete catalog of all compiler diagnostics. Names are the primary identification scheme; numeric codes are secondary compact identifiers.

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
- **Codes** are secondary compact identifiers (E/W + 4 digits). Codes are never reused after retirement.
- **Suppression** uses names: `@allow(NonExhaustiveMatch)`.
- **`pact explain <name>`** prints a detailed explanation (future — not yet implemented).

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
| E09xx | Module capabilities |
| E10xx | Module resolution / imports |

---

## Error Names

| Name | Code | One-line | Category | Spec ref |
|------|------|----------|----------|----------|
| NonExhaustiveMatch | E0004 | Non-exhaustive match expression | Pattern matching | §3.5 |
| RefutableLetPattern | E0005 | Refutable pattern in `let` binding | Pattern matching | §3.5 |
| SealedTraitImpl | E0120 | Impl of sealed trait by non-builtin type | Traits | §3.6 |
| TraitBoundNotSatisfied | E0121 | Required trait bound not satisfied | Traits | §3.6, §3.8 |
| NonDerivableTrait | E0160 | Cannot derive trait — field type lacks required impl | Derive | §3.6.1 |
| SelfOutsideTraitOrImpl | E0170 | `Self` used outside trait or impl block | Traits | §3.6 |
| SelfNotConstructor | E0171 | `Self` used as constructor | Traits | §3.6 |
| TupleArityExceeded | E0180 | Tuple exceeds maximum arity (6) | Types | §3.8 |
| InconsistentPatternBindings | E0311 | Inconsistent bindings in OR-pattern | Pattern matching | §3.5 |
| MissingDisplayImpl | E0312 | Type does not implement `Display` for interpolation | Type checking | §3.6.1 |
| UndeclaredEffect | E0500 | Callee requires effect not declared by caller | Effects | §4.5 |
| InsufficientCapability | E0501 | Effect operation exceeds declared capability | Effects | §4.4 |
| QuestionMarkInvalidOperand | E0502 | `?` operator used on non-Result, non-Option type | Type checking | §3c.2 |
| CoalesceRequiresOption | E0503 | `??` operator used on non-Option value | Type checking | §3c.2 |
| UndefinedFunction | E0504 | Call to undefined function | Name resolution | §6.3 |
| UnresolvedMethod | E0505 | Unresolved method call on variable | Name resolution | §6.3, §3c.4 |
| UndefinedVariable | E0506 | Reference to undefined variable | Name resolution | §6.3 |
| UnknownType | E0507 | Reference to undefined type | Name resolution | §6.3 |
| QuestionMarkResultInNonResult | E0508 | `?` on Result in function not returning Result | Type checking | §3c.2 |
| QuestionMarkOptionInNonOption | E0509 | `?` on Option in function not returning Option | Type checking | §3c.2 |
| CapabilityBudgetExceeded | E0510 | Function effect exceeds module `@capabilities` budget | Effects | §4.8 |
| EffectMismatchInFnType | E0511 | Effect mismatch between expected and actual function type | Effects | §4.15 |
| QuestionMarkErrorMismatch | E0512 | `?` error type mismatch — inner E1 ≠ function return E2 | Type checking | §3c.2 |
| InvalidHandlerTypeParam | E0520 | `Handler[E]` used with non-effect type parameter | Effects | §4.7.1 |
| InsufficientHandlerCoverage | E0521 | Handler lacks required effect operations | Effects | §4.7.1 |
| UnhandledEffectInTest | E0540 | Unhandled effect in test block | Effects | §2.19 |
| CloseableEscapesScope | E0601 | `Closeable` value escapes `with...as` scope | Resources | §5.5 |
| CloseableStoredInCollection | E0602 | `Closeable` value stored in collection | Resources | §5.5 |
| MutableCaptureInSpawn | E0650 | `let mut` binding captured in `async.spawn` closure | Closures | §2.8 |
| ArenaValueEscapes | E0700 | Arena-scoped value escapes arena scope | Arena | §5.2 |
| EffectHandleShadowed | E0710 | Local variable shadows reserved effect handle name | Method resolution | §3c.4 |
| AmbiguousMethodCall | E0730 | Method found in multiple traits — ambiguous | Method resolution | §3c.4 |
| OrphanImpl | E0750 | Impl in package that defines neither trait nor type | Coherence | §3.6 |
| OverlappingImpls | E0760 | Two impls overlap for same (Trait, Type) pair | Coherence | §3.6 |
| FfiFunctionPublic | E0801 | FFI function cannot be `pub` | FFI | §9.1 |
| InvalidPtrTypeParam | E0810 | Invalid `Ptr[T]` type parameter | FFI | §9.1.1 |
| PtrOutsideFfiContext | E0811 | `Ptr[T]` used outside FFI context | FFI | §9.1.1 |
| EffectExceedsModuleCaps | E0900 | Effect exceeds module capabilities | Module caps | §10.2 |
| DuplicateModuleName | E1001 | Duplicate module name in package | Modules | §10.5 |
| CircularPackageDep | E1002 | Circular package dependency | Modules | §10.5 |
| PrivateItemAccess | E1003 | Access to private item in another module | Modules | §10.5 |
| DuplicateModuleBinding | E1004 | Duplicate `let` binding name at module level | Modules | §2.12.1 |
| AmbiguousImport | E1005 | Ambiguous import — name exists in multiple modules | Modules | §10.5 |
| PubLetMutForbidden | E1006 | `pub let mut` is forbidden — mutable state must use functions with effects | Modules | §2.12.1 |
| StdlibNotFound | E1050 | Stdlib module not found — installation incomplete | Stdlib | §10.7 |
| StdlibVersionMismatch | E1051 | Stdlib version mismatch with lockfile | Stdlib | §10.7 |
| PackageNotDeclared | E1052 | Package not declared in pact.toml — Tier 2 package needs explicit dependency | Stdlib | §10.7.1 |
| NonConstExpr | E1101 | Expression is not a compile-time constant | Const | §2.20 |
| ConstMutForbidden | E1102 | `const` binding cannot be `mut` | Const | §2.20 |
| NonConstStructDefault | E1103 | Struct field default is not a const expression | Const | §2.20 |
| NonConstKeywordDefault | E1104 | Keyword argument default is not a const expression | Const | §2.20 |
| NonConstRangeBound | E1105 | Range pattern bound is not a const expression | Const | §2.20 |

---

## Warning Names

| Name | Code | One-line | Category | Spec ref |
|------|------|----------|----------|----------|
| LossyConversion | W0350 | Int-to-Float conversion loses precision | Numeric | §3c.3 |
| RawBypassesParam | W0310 | `Raw()` bypasses query parameterization | Contracts | §3b.5 |
| CloseableWithoutScope | W0600 | `Closeable` value used outside `with...as` block | Resources | §5.5 |
| UnauditedFfi | W0800 | Unaudited foreign function call | FFI | §9.1 |
| UnscopedPointerAlloc | W0810 | Pointer allocation outside `ffi.scope()` | FFI | §9.1.1 |
| LocalShadowsDep | W1000 | Local module shadows a dependency | Modules | §10.5 |
| NameShadowsPrelude | W1010 | Name shadows a prelude type | Modules | §10.6 |
| IncompleteStateRestore | W0550 | Speculative lookahead saves some but not all written bindings | Mutation analysis | §4.16 |
| UnrestoredMutation | W0551 | Function writes module-level state without restoring it in a speculative context | Mutation analysis | §4.16 |

---

## Compiler-Implemented Codes

The self-hosting compiler (`src/codegen_types.pact`, `src/codegen_expr.pact`) currently implements these error codes:

| Code | Name | Implementation |
|------|------|---------------|
| E0500 | UndeclaredEffect | `codegen_types.pact` — effect propagation check |
| E0501 | InsufficientCapability | `codegen_types.pact` — `@capabilities` budget check |
| E0502 | QuestionMarkInvalidOperand | `codegen_expr.pact` — `?` operator type check (to move to typecheck phase) |
| E0503 | CoalesceRequiresOption | `codegen_expr.pact` — `??` operator type check |
| E0508 | QuestionMarkResultInNonResult | Not yet implemented — requires type checker |
| E0509 | QuestionMarkOptionInNonOption | Not yet implemented — requires type checker |
| E0512 | QuestionMarkErrorMismatch | Not yet implemented — requires type checker |
| E0504 | UndefinedFunction | `typecheck.pact` — name resolution + `codegen_expr.pact` — codegen |
| E0505 | UnresolvedMethod | `codegen_methods.pact` — method dispatch (codegen phase) |
| E0506 | UndefinedVariable | `typecheck.pact` — name resolution |
| E0507 | UnknownType | `typecheck.pact` — name resolution |
| W0501 | UnknownMethod | `typecheck.pact` — name resolution (warning, may be false positive for struct field closures) |
