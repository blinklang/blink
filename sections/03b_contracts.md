## 3b. Refinement Types & Contracts

### 3b.1 Refinement Types

Refinement types are Pact's answer to the question every language designer faces: how much of a value's validity should the type system encode?

Most languages punt entirely -- `Int` means "any integer," and if you need a port number, you write runtime validation code. Fully dependent type systems go to the other extreme -- the type encodes everything, but inference becomes undecidable and error messages become incomprehensible.

Pact takes the middle path. Refinement types let you attach predicates to existing types using `@where`. The predicates are checked by an SMT solver (Z3) at compile time when possible, and at boundaries when not.

```pact
type Port = Int @where(self > 0 && self <= 65535)
type Percentage = Float @where(self >= 0.0 && self <= 100.0)
type NonEmptyStr = Str @where(self.len() > 0)
type EvenInt = Int @where(self % 2 == 0)
type PositiveInt = Int @where(self > 0)
```

#### How `@where` Works

The `@where` clause constrains the set of values that inhabit the type. `self` refers to the value being constrained. The predicate must be a boolean expression using only pure operations.

```pact
// Refined type in a function signature
fn listen(port: Port) ! Net {
    net.bind("0.0.0.0", port)
}

// The compiler verifies the argument satisfies the refinement
listen(8080)         // OK: 8080 > 0 && 8080 <= 65535, proven by SMT
listen(0)            // COMPILE ERROR: 0 does not satisfy (self > 0)
listen(70000)        // COMPILE ERROR: 70000 does not satisfy (self <= 65535)

// When the value is dynamic, the compiler inserts a check at the boundary
fn start_server(config: Config) ! Net {
    let port = config.port      // port is Int, not Port
    listen(port)                // COMPILE ERROR: cannot prove config.port satisfies Port
}

// Fix: validate at the boundary
fn start_server(config: Config) -> Result[(), ServerError] ! Net {
    let port = Port.try_from(config.port)?   // runtime check, returns Result
    listen(port)                              // OK: port is now Port
}
```

#### Refinements on Collection Types

```pact
type NonEmpty[T] = List[T] @where(self.len() > 0)

fn head[T](list: NonEmpty[T]) -> T {
    list.get(0).unwrap()   // safe: list is guaranteed non-empty
}

fn average(values: NonEmpty[Float]) -> Float {
    values.sum() / values.len().to_float()   // safe: no division by zero
}
```

#### Refinements on Struct Fields

```pact
type HttpResponse {
    status: Int @where(self >= 100 && self <= 599)
    headers: Map[Str, Str]
    body: Str
}
```

#### Why `@where` Syntax

The `@` prefix is Pact's annotation syntax. `@where` reads naturally -- "this type is `Int` where the value satisfies this predicate." It is visually distinct from the type itself, which prevents confusion between the base type and the constraint. It scales to complex predicates without syntactic noise:

```pact
type ValidEmail = Str @where(
    self.contains("@")
    && self.len() >= 3
    && self.len() <= 254
)
```

#### The Sweet Spot: 90% of Dependent Type Value at 10% of the Cost

Full dependent types let types depend on arbitrary values: `Vec[T, N]` where `N` is a value-level natural number. This is enormously powerful and enormously complex. Type inference becomes undecidable. Error messages become research papers. Even experienced Idris/Agda users spend significant time wrestling with the prover.

Refinement types with SMT give you the cases that actually matter in practice:

| What you get | Example |
|---|---|
| Range validation | `Port`, `Percentage`, `HttpStatus` |
| Non-emptiness | `NonEmpty[T]`, `NonEmptyStr` |
| Relational constraints | `StartDate @where(self < end_date)` |
| Modular arithmetic | `EvenInt`, `AlignedOffset` |
| String constraints | `NonEmptyStr`, length bounds |

What you don't get (and don't need for 95% of code): matrix dimension tracking, length-indexed vectors, proof-carrying code. These are deferred. If they're ever needed, the SMT foundation can be extended to support them. But shipping a language people can use today matters more than shipping a language that's theoretically complete.

---

### 3b.2 Contracts

Contracts are formal specifications on function behavior. Where refinement types constrain individual values, contracts constrain the relationship between inputs, outputs, and state.

Three annotation forms:

- `@requires(predicate)` -- precondition: what must be true before the function executes
- `@ensures(predicate)` -- postcondition: what must be true after the function returns
- `@invariant(predicate)` -- type invariant: what must always be true about a type's state

#### Preconditions with `@requires`

```pact
@requires(index >= 0 && index < list.len())
fn get_unchecked[T](list: List[T], index: Int) -> T {
    list.internal_get(index)
}
```

The `@requires` clause is a promise by the caller: "I guarantee this condition holds before calling you." The compiler verifies at every call site that the precondition is satisfied.

```pact
fn example(items: List[Str]) {
    get_unchecked(items, 0)     // COMPILE ERROR: cannot prove 0 < items.len()
}

fn safe_example(items: NonEmpty[Str]) {
    get_unchecked(items, 0)     // OK: NonEmpty guarantees len() > 0, so 0 < len()
}
```

#### Postconditions with `@ensures`

```pact
@ensures(result.len() == list.len())
@ensures(result.is_sorted())
fn sort[T: Ord](list: List[T]) -> List[T] {
    // ... implementation ...
}
```

In `@ensures` clauses, `result` refers to the function's return value. The compiler verifies that the implementation actually satisfies the postcondition.

#### The `old()` Expression

Postconditions often need to reference the state of inputs *before* the function executed. The `old()` expression captures pre-call values:

```pact
@ensures(result.len() == old(list.len()) + 1)
fn append[T](list: List[T], item: T) -> List[T] {
    // ... implementation ...
}

@ensures(result.balance == old(self.balance) - amount)
fn withdraw(self: Account, amount: Int) -> Result[Account, InsufficientFunds] {
    if self.balance < amount {
        Err(InsufficientFunds)
    } else {
        Ok(Account { balance: self.balance - amount, ..self })
    }
}
```

`old(expr)` is evaluated once, before the function body executes. It creates a snapshot that the postcondition can reference. This is how you express "the balance decreased by exactly the withdrawal amount" without introducing mutable state tracking.

#### Type Invariants with `@invariant`

Type invariants are constraints that must hold for every instance of a type at all times. They are checked at construction and after every mutation.

```pact
type BankAccount {
    owner: Str
    balance: Int
    @invariant(self.balance >= 0)
}

type SortedList[T: Ord] {
    items: List[T]
    @invariant(self.items.is_sorted())
}

type DateRange {
    start: Date
    end: Date
    @invariant(self.start <= self.end)
}
```

The `@invariant` annotation means: any function that constructs or modifies this type must leave the invariant satisfied. The compiler verifies this at every construction site and every function that takes `self` as mutable.

```pact
let account = BankAccount { owner: "Alice", balance: -100 }
// COMPILE ERROR: invariant violation -- balance >= 0 not satisfied

let account = BankAccount { owner: "Alice", balance: 1000 }
// OK: invariant holds
```

#### A Complete Example

```pact
type Stack[T] {
    items: List[T]
    capacity: Int
    @invariant(self.items.len() <= self.capacity)
    @invariant(self.capacity > 0)
}

@requires(stack.items.len() < stack.capacity)
@ensures(result.items.len() == old(stack.items.len()) + 1)
fn push[T](stack: Stack[T], value: T) -> Stack[T] {
    Stack {
        items: stack.items.append(value)
        capacity: stack.capacity
    }
}

@requires(stack.items.len() > 0)
@ensures(result.1.items.len() == old(stack.items.len()) - 1)
fn pop[T](stack: Stack[T]) -> (T, Stack[T]) {
    let item = stack.items.last().unwrap()
    let rest = Stack {
        items: stack.items.drop_last()
        capacity: stack.capacity
    }
    (item, rest)
}
```

#### SMT Verification

Contracts are verified by an integrated SMT solver (Z3). The solver is **lazy** -- it is only invoked when contracts exist. Code without `@requires`, `@ensures`, or `@invariant` annotations never touches the solver. The type checker handles everything else with standard Hindley-Milner inference.

When the solver runs, it attempts to prove that:
1. Every `@requires` clause is satisfied at every call site
2. Every `@ensures` clause follows from the implementation given the preconditions
3. Every `@invariant` holds at every construction and mutation point

The solver works with the theories of: linear integer arithmetic, bitvectors, arrays (for list operations), uninterpreted functions, and boolean logic. These cover the vast majority of practical contract verification.

---

### 3b.3 Contract Composition and Modular Verification

The verification model is **modular**: each function is verified independently using only its own contracts and the contracts of functions it calls. There is no whole-program analysis.

This is the key architectural decision that makes contract verification scale.

#### How Modular Verification Works

When verifying function `A` that calls function `B`:

1. The verifier checks that `A` satisfies `B`'s `@requires` at the call site
2. The verifier assumes `B`'s `@ensures` hold after the call
3. The verifier does NOT look at `B`'s implementation

```pact
@requires(list.len() > 0)
@ensures(result >= 0)
fn find_min(list: List[Int]) -> Int {
    // ... implementation ...
}

@requires(values.len() > 0)
@ensures(result <= find_min(values))
fn compute_lower_bound(values: List[Int]) -> Int {
    let min = find_min(values)     // (1) verifier checks: values.len() > 0 -- satisfied by @requires
                                    // (2) verifier assumes: min >= 0 -- from find_min's @ensures
    min - 1                         // (3) verifier checks: min - 1 <= min -- trivially true
}
```

The verifier never reads `find_min`'s body when verifying `compute_lower_bound`. It trusts `find_min`'s contracts. When `find_min` itself is verified, the solver checks that its implementation satisfies its own `@ensures`. Each function is an island.

#### Why Modular Verification

**Scalability.** Whole-program analysis is O(program size). Modular verification is O(function size). A million-line codebase verifies in the same time as a thousand-line codebase, function by function.

**Incrementality.** Change one function, re-verify only that function and its direct callers. The compiler-as-service daemon can do this in milliseconds.

**Composability.** Libraries publish contracts. Consumers verify against those contracts without access to the library's source code. The contract is the interface.

**Locality.** Understanding why a function is correct requires reading only that function and the contracts of what it calls. Not the implementations. Not the transitive dependency tree. This directly serves the finite-context-window constraint of AI agents.

#### Contracts as Documentation

Even before SMT verification, contracts serve as machine-readable documentation:

```pact
/// Transfers funds between accounts.
@requires(amount > 0)
@requires(from.balance >= amount)
@ensures(result.from.balance == old(from.balance) - amount)
@ensures(result.to.balance == old(to.balance) + amount)
fn transfer(amount: Int, -- from: Account, to: Account) -> TransferResult {
    // The contracts tell you everything about this function's behavior.
    // The implementation is almost redundant.
}
```

An AI agent reading this signature knows: the amount must be positive, the source account must have sufficient funds, and after the transfer, the balances change by exactly the transfer amount. It doesn't need to read the body to understand the behavior, generate correct call sites, or write tests.

---

### 3b.4 Verification Outcomes

When the SMT solver processes a contract, exactly one of three outcomes occurs:

#### Proven (Zero Runtime Cost)

The solver proves the contract holds for all possible inputs. The contract is compiled away entirely -- no runtime check, no overhead, as if it were never written.

```
info[V0001]: contract proven
 --> account.pact:15:1
  |
15| @ensures(result.balance == old(self.balance) - amount)
  | ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ proven by SMT
  |
  = note: zero runtime cost
```

This is the ideal outcome. Well-written contracts on well-written code are often provable. The incentive structure is correct: writing clearer code with tighter types makes contracts easier to prove, which makes them free.

#### Disproven (Compile Error with Counterexample)

The solver finds a concrete input that violates the contract. The compiler reports a hard error with the counterexample.

```
error[V0002]: contract violation
 --> account.pact:22:1
  |
22| @requires(amount > 0)
  | ^^^^^^^^^^^^^^^^^^^^^ violated at call site
  |
  = counterexample: amount = -5
  = note: called from transfer_all() at line 45
  = fix: add validation before call:
  |
44|     if amount > 0 {
45|         withdraw(account, amount)
46|     }
```

This is a real bug caught at compile time with a concrete failing input. The error message tells the developer (or AI) exactly what went wrong and suggests a fix. This is strictly better than a test failure -- it proves the bug exists for a specific input rather than hoping the test suite happened to exercise it.

#### Unknown (Configurable Fallback)

The solver can't determine whether the contract holds or not. The predicate is beyond what the SMT theories can decide, or the solver times out. By default, this is a compile error:

```
error[V0003]: contract unverifiable
 --> crypto.pact:8:1
  |
 8| @ensures(result.is_valid_signature())
  | ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ solver returned unknown
  |
  = note: the SMT solver could not prove or disprove this contract
  = help: options:
  |   1. Simplify the contract predicate
  |   2. Add @verify(fallback: "runtime") to insert a runtime check
  |   3. Add @verify(fallback: "trust") to accept without verification
```

The developer has three options:

**Option 1: Simplify the contract.** Rewrite the predicate to use operations the solver understands. This is the best outcome -- it means the contract is now provable.

**Option 2: Runtime fallback.** Add `@verify(fallback: "runtime")` to insert a runtime check. The contract becomes an assertion that runs in debug builds (and optionally in release builds):

```pact
@ensures(result.is_valid_signature())
@verify(fallback: "runtime")
fn sign(data: Str, key: PrivateKey) -> Signature ! Crypto {
    // If the solver can't prove the postcondition, a runtime assertion
    // checks it after every call. Fails fast if the contract is violated.
}
```

**Option 3: Trust.** Add `@verify(fallback: "trust")` to accept the contract as documentation. The compiler takes the developer's word that it holds. This is an escape hatch for contracts that describe behavior the solver fundamentally cannot reason about (cryptographic properties, probabilistic guarantees, etc.):

```pact
@ensures(result.entropy() >= 256)
@verify(fallback: "trust")
fn generate_key() -> PrivateKey ! Crypto {
    // Entropy is not something an SMT solver can reason about.
    // The contract documents the intent; testing and audits verify it.
}
```

#### Why Default to Error on Unknown

The safe default is to reject code the compiler can't verify. This ensures that `@ensures` and `@requires` are not treated as comments -- if you write a contract, the compiler holds you to it. The `@verify(fallback: ...)` annotation is an explicit, visible, auditable acknowledgment that verification is relaxed for this specific contract. Code reviewers and AI agents can search for `@verify(fallback: "trust")` to find every place where the verification chain has a gap.

#### Verification Summary

| Outcome | Meaning | Runtime cost | Developer action |
|---|---|---|---|
| **Proven** | SMT proved the contract | Zero | None needed |
| **Disproven** | SMT found a counterexample | N/A (won't compile) | Fix the bug |
| **Unknown** (default) | SMT can't decide | N/A (won't compile) | Simplify, add fallback, or trust |
| **Unknown** + `runtime` | Runtime assertion inserted | Assertion cost | Monitor for violations |
| **Unknown** + `trust` | Accepted on faith | Zero | Document why, audit manually |

---

### 3b.5 Context-Sensitive Query Types

Pact's universal string interpolation (`"Hello, {name}!"`) is safe for display strings — but dangerous when interpolated strings flow to injection-sensitive contexts like databases, shells, or HTML templates. The `Query[C]` type makes the obvious code the safe code without changing developer syntax.

#### The Problem

```pact
fn get_user(id: Int) -> User? ! DB.Read {
    // Looks like string interpolation — but this goes to a database
    db.query_one("SELECT * FROM users WHERE id = {id}")
}
```

In most languages, this is textbook SQL injection. In Pact, it's safe — because `db.query_one` accepts `Query[DB]`, not `Str`.

#### How `Query[C]` Works

`Query[C]` is a compiler-known type parameterized by a phantom type `C` that identifies the injection context (DB, Shell, HTML, etc.). When an interpolated string literal appears where `Query[C]` is expected, the compiler automatically extracts `{expr}` interpolations as bound parameters instead of concatenating them into the string.

```pact
// What the developer writes:
db.query_one("SELECT * FROM users WHERE id = {id}")

// What the compiler sees:
db.query_one(Query.param("SELECT * FROM users WHERE id = $1", [id]))

// The second interpolation in the same function is Str context — normal concat:
Err(ApiError.NotFound("User {id} not found"))
```

The *receiving type* determines the behavior. The same `{id}` syntax means parameterization in a `Query[DB]` context and concatenation in a `Str` context.

#### Compile Errors for `Str` → `Query` Mismatch

A pre-built `Str` variable cannot be passed where `Query[C]` is expected. This prevents laundering tainted data through a string variable:

```pact
let q: Str = "SELECT * FROM users WHERE id = {id}"
db.query_one(q)  // COMPILE ERROR: expected Query[DB], got Str
```

```
error[E0310]: type mismatch
 --> user.pact:5:18
  |
5 |     db.query_one(q)
  |                  ^ expected `Query[DB]`, found `Str`
  |
  = note: string variables cannot be implicitly converted to Query
  = hint: pass the string literal directly, or wrap values in Raw() for dynamic SQL
```

This is intentional. The auto-parameterization only works on string *literals* at the call site, where the compiler can see the template structure. A `Str` variable is opaque — the compiler cannot extract parameters from it.

#### `Raw(expr)` — The Escape Hatch

For dynamic SQL (table names, column lists, generated clauses), wrapping an interpolated expression in `Raw()` bypasses parameterization for that specific value. `Raw[T]` is a compiler-known marker type — when `Query[C]` coercion encounters `{Raw(expr)}`, it concatenates instead of parameterizing.

```pact
fn dynamic_report(table: Str, id: Int) -> Result[Row, DBError] ! DB.Read {
    // Only table is concatenated; id is still a bound parameter
    db.query_one("SELECT * FROM {Raw(table)} WHERE id = {id}")
    // Compiler: Query.param("SELECT * FROM users WHERE id = $1", [id])
    //           with "users" concatenated from table
}

// Fully dynamic (all raw) — still works, just verbose
db.query_one("{Raw(whole_query)}")
```

`Raw()` usage emits a compiler warning:

```
warning[W0310]: Raw() bypasses parameterization
 --> report.pact:3:42
  |
3 |     db.query_one("SELECT * FROM {Raw(table)} WHERE id = {id}")
  |                                  ^^^^^^^^^^ concatenated, not parameterized
  |
  = help: add @trusted(audit: "AUDIT-ID") to suppress this warning
  = help: use `pact audit --raw-queries` to review all Raw() usage
```

The warning is suppressed by `@trusted`, creating an auditable trail — the same mechanism used for FFI.

**Why `Raw(expr)` instead of format specs or `Query.raw()`:**

- **Per-interpolation granularity.** Unlike `Query.raw()` which disables parameterization for the entire string, `Raw()` affects only the wrapped expression. Mixed safe/unsafe queries work naturally.
- **No string grammar extension.** `Raw(expr)` is just an expression inside `{...}` — zero new parser productions. No `:modifier` syntax that invites format specs (`:.2f`, `:>20`).
- **Type-system native.** Consistent with Pact's "types are the mechanism" philosophy. `Raw[T]` is a compiler-known type like `Option[T]` or `Result[T,E]`.
- **Proven pattern.** Django's `mark_safe()`, Rails' `raw()`, Jinja2's `Markup()` — the industry consensus is to mark the VALUE, not the template slot.

#### Phantom Type Extensibility

The phantom type `C` in `Query[C]` enables the same mechanism for other injection contexts:

```pact
// Shell injection protection
fn run(cmd: Query[Shell]) -> Result[Output, ShellError]
process.run("ls -la {path}")  // path is escaped/parameterized

// HTML/XSS protection (future)
fn render(template: Query[HTML]) -> SafeHtml
html.render("<div>{user_content}</div>")  // auto-escaped

// LDAP injection protection (future)
fn search(filter: Query[LDAP]) -> Result[List[Entry], LDAPError]
```

Each context defines its own parameterization/escaping strategy. The developer writes the same interpolation syntax everywhere — the receiving type ensures safety.

#### `pact audit` Integration

`pact audit --raw-queries` tracks all `Raw()` usage alongside FFI:

```
$ pact audit --raw-queries

Raw() usage (bypasses parameterization):
  db/legacy.pact:42    {Raw(table)} in Query[DB]     UNAUDITED
  db/migration.pact:8  {Raw(name)} in Query[DB]      audit: MIG-001

1 of 2 raw interpolations unaudited.
```

CI can enforce `pact audit --no-unaudited-raw` to block merges with unreviewed raw queries.

#### Design Rationale

**Why not taint tracking:** Full information flow tracking (Section 9.3) requires tracking provenance on every value through inference, generics, and closures. `Query[C]` with `Raw[T]` achieves 95% of the safety at the type boundary with minimal type system extension — two compiler-known types that enable per-interpolation safety control.

**Why not a new string syntax:** Adding `sql"..."` or `q"..."` prefixes violates the "one string syntax" principle (Section 2.2). The receiving type determines behavior, not a prefix on the literal.

**Why phantom types:** `Query[DB]` and `Query[Shell]` are distinct types. You cannot pass a `Query[Shell]` to a function expecting `Query[DB]`. The phantom parameter prevents cross-context confusion with zero runtime cost.
