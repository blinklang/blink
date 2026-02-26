[< All Decisions](../DECISIONS.md)

# Keyword Arguments & Defaults — Design Rationale

### Problem Statement

Positional-only parameters create two classes of problems:

1. **Same-typed parameter swap bugs.** `transfer(from, to, amount)` where `from` and `to` are both `Account` — positional-only means a swap is type-correct but semantically wrong. LLMs swap same-typed positional args at 3-8% per call site.

2. **API evolution brittleness.** Adding a parameter to a positional-only function breaks every caller. Without defaults, the most common API evolution (adding an optional parameter) is always breaking.

### Cross-Language Survey

- **Python**: Full keyword args + defaults. Hugely popular but creates positional-or-keyword ambiguity, mutable default gotcha, `*args/**kwargs` untypeable black holes.
- **Swift**: External/internal param names. Best-in-class readability but dual naming is complex.
- **Kotlin**: Named args + defaults. Clean but "two ways to call" violates Principle 2.
- **Rust**: No keyword args, no defaults. Builder pattern workaround. #1 requested feature in surveys.
- **Go**: No keyword args, no defaults. Functional options pattern. Widely considered an ergonomics failure.

### Decision: Declaration-Site `--` Separator

The function author decides which params are positional and which are keyword. The caller has no choice.

```pact
fn transfer(amount: Int, -- from: Account, to: Account) -> Result[Transaction, BankError]
transfer(300, from: alice, to: bob)
```

**`--` separator won 3-1-1** (3 for `--`, 1 for `;`, 1 for `*`). `--` is the most visually distinctive, hard to confuse with any Pact syntax. `;` triggers statement-terminator instinct in AI. `*` (Python precedent) was considered too subtle.

**Labels as call-site sugar won 5-0 (unanimous).** Function type is `fn(Int, Account, Account)` regardless of `--`. Keeps closures and HOFs simple. No label propagation tracking needed.

### Decision: Struct Field Defaults

Struct fields can declare compile-time constant defaults. Primary config and API evolution mechanism.

```pact
type ServerConfig {
    host: Str = "0.0.0.0"
    port: Port = 8080
    debug: Bool = false
}
ServerConfig { port: 3000 }  // host and debug use defaults
```

Adding a field with a default is always backwards-compatible.

### Decision: Reject Function Parameter Defaults

Function param defaults interact with closures, HOFs, and partial application. Struct field defaults cover the same use cases with less type system complexity.

