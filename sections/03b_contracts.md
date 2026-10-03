## 3b. Refinement Types & Contracts

### 3b.1 Refinement Types

Refinement types are Blink's answer to the question every language designer faces: how much of a value's validity should the type system encode?

Most languages punt entirely -- `Int` means "any integer," and if you need a port number, you write runtime validation code. Fully dependent type systems go to the other extreme -- the type encodes everything, but inference becomes undecidable and error messages become incomprehensible.

Blink takes the middle path. Refinement types let you attach predicates to existing types using `@where`. The predicates are checked by an SMT solver at compile time when possible, and at boundaries when not.

```blink
type Port = Int @where(self > 0 && self <= 65535)
type Percentage = Float @where(self >= 0.0 && self <= 100.0)
type NonEmptyStr = Str @where(self.len() > 0)
type EvenInt = Int @where(self % 2 == 0)
type PositiveInt = Int @where(self > 0)
```

#### How `@where` Works

The `@where` clause constrains the set of values that inhabit the type. `self` refers to the value being constrained. The predicate must be a boolean expression using only pure operations.

```blink
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

```blink
type NonEmpty[T] = List[T] @where(self.len() > 0)

fn head[T](list: NonEmpty[T]) -> T {
    list.get(0).unwrap()   // safe: list is guaranteed non-empty
}

fn average(values: NonEmpty[Float]) -> Float {
    values.sum() / values.len().to_float()   // safe: no division by zero
}
```

#### Refinements on Struct Fields

```blink
type HttpResponse {
    status: Int @where(self >= 100 && self <= 599)
    headers: Map[Str, Str]
    body: Str
}
```

#### Why `@where` Syntax

The `@` prefix is Blink's annotation syntax. `@where` reads naturally -- "this type is `Int` where the value satisfies this predicate." It is visually distinct from the type itself, which prevents confusion between the base type and the constraint. It scales to complex predicates without syntactic noise:

```blink
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

Contracts attach to functions and to methods in `impl` blocks. A `@requires`, `@ensures` or `@verify` on a trait method declaration is a compile error (E1110); contracts on trait methods are not yet specified.

#### Preconditions with `@requires`

```blink
@requires(index >= 0 && index < list.len())
fn get_unchecked[T](list: List[T], index: Int) -> T {
    list.internal_get(index)
}
```

The `@requires` clause is a promise by the caller: "I guarantee this condition holds before calling you." The compiler verifies at every call site that the precondition is satisfied.

```blink
fn example(items: List[Str]) {
    get_unchecked(items, 0)     // COMPILE ERROR: cannot prove 0 < items.len()
}

fn safe_example(items: NonEmpty[Str]) {
    get_unchecked(items, 0)     // OK: NonEmpty guarantees len() > 0, so 0 < len()
}
```

#### Postconditions with `@ensures`

```blink
@ensures(result.len() == list.len())
@ensures(result.is_sorted())
fn sort[T: Ord](list: List[T]) -> List[T] {
    // ... implementation ...
}
```

In `@ensures` clauses, `result` refers to the function's return value. The compiler verifies that the implementation actually satisfies the postcondition.

#### The `old()` Expression

Postconditions often need to reference the state of inputs *before* the function executed. The `old()` expression captures pre-call values:

```blink
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

```blink
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

```blink
let account = BankAccount { owner: "Alice", balance: -100 }
// COMPILE ERROR: invariant violation -- balance >= 0 not satisfied

let account = BankAccount { owner: "Alice", balance: 1000 }
// OK: invariant holds
```

#### A Complete Example

```blink
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

Contracts are verified by the compiler's static checker, which uses an SMT solver. Code without `@requires`, `@ensures`, or `@invariant` annotations has nothing to verify.

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

```blink
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

**Incrementality.** Change one function, re-verify only that function and its direct callers.

**Composability.** Libraries publish contracts. Consumers verify against those contracts without access to the library's source code. The contract is the interface.

**Locality.** Understanding why a function is correct requires reading only that function and the contracts of what it calls. Not the implementations. Not the transitive dependency tree. This directly serves the finite-context-window constraint of AI agents.

#### Contracts as Documentation

Even before SMT verification, contracts serve as machine-readable documentation:

```blink
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
 --> account.bl:15:1
  |
15| @ensures(result.balance == old(self.balance) - amount)
  | ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ proven by SMT
  |
  = note: no runtime check
```

This is the ideal outcome. Well-written contracts on well-written code are often provable. The incentive structure is correct: writing clearer code with tighter types makes contracts easier to prove, which removes the runtime check.

#### Disproven (Compile Error with Counterexample)

The solver finds a concrete input that violates the contract. The compiler reports a hard error with the counterexample.

```
error[V0002]: contract violation
 --> account.bl:22:1
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
 --> crypto.bl:8:1
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

```blink
@ensures(result.is_valid_signature())
@verify(fallback: "runtime")
fn sign(data: Str, key: PrivateKey) -> Signature ! Crypto {
    // If the solver can't prove the postcondition, a runtime assertion
    // checks it after every call. Fails fast if the contract is violated.
}
```

**Option 3: Trust.** Add `@verify(fallback: "trust")` to accept the contract as documentation. The compiler takes the developer's word that it holds. This is an escape hatch for contracts that describe behavior the solver fundamentally cannot reason about (cryptographic properties, probabilistic guarantees, etc.):

```blink
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

### 3b.5 Context-Sensitive Template Types

Blink's universal string interpolation (`"Hello, {name}!"`) is safe for display strings — but dangerous when interpolated strings flow to injection-sensitive contexts like databases, shells, or HTML templates. The `Template[C]` type makes the obvious code the safe code without changing developer syntax.

#### The Problem

```blink
fn get_user(id: Int) -> User? ! DB.Read {
    // Looks like string interpolation — but this goes to a database
    db.query_one("SELECT * FROM users WHERE id = {id}")
}
```

In most languages, this is textbook SQL injection. In Blink, it's safe — because `db.query_one` accepts `Template[DB]`, not `Str`.

#### How `Template[C]` Works

`Template[C]` is a compiler-known **opaque** type parameterized by a phantom type `C` that identifies the injection context (DB, Shell, HTML, etc.). When an interpolated string literal appears where `Template[C]` is expected, the compiler **decomposes** the string into literal parts and interpolated values instead of concatenating them.

```blink
// What the developer writes:
db.query_one("SELECT * FROM users WHERE id = {id}")

// What the handler observes, for id = 42:
//   t.parts()  == ["SELECT * FROM users WHERE id = ", ""]
//   t.values() == [TemplateValue.Int(42)]

// The second interpolation in the same function is Str context — normal concat:
Err(ApiError.NotFound("User {id} not found"))
```

The *receiving type* determines the behavior. The same `{id}` syntax means decomposition in a `Template[DB]` context and concatenation in a `Str` context.

**Handler reassembly.** The handler — not the compiler — decides how to reassemble the template. Each database, shell, or HTML handler owns its dialect-specific parameterization syntax:

```blink
// PostgreSQL handler reassembles as: "SELECT * FROM users WHERE id = $1" with params [id]
// MySQL handler reassembles as: "SELECT * FROM users WHERE id = ?" with params [id]
// Shell handler applies quoting/escaping per-value
// HTML handler applies entity escaping per-value
```

This separation of concerns means the compiler never encodes dialect knowledge. User-authored effect handlers participate in parameterization on equal footing with stdlib handlers.

#### The `Template[C]` Surface (normative)

`Template[C]` has **no fields and no constructor**. Only two things build one: the coercion of an interpolated string literal at a site that expects `Template[C]`, and the folding of a `Raw[T]` into that literal's parts (see *`Raw(expr)` — The Escape Hatch* below). A handler reads a template through two methods:

| Method | Signature | Returns |
|---|---|---|
| `parts` | `fn(self) -> List[Str]` | The literal segments, in source order |
| `values` | `fn(self) -> List[TemplateValue]` | The interpolated values, in source order |

The invariant is `t.parts().len() == t.values().len() + 1`. A literal with no holes has one part and no values.

**A `Template[C]` does not change after it is built.** No method returns a value through which a caller can change the template. Each call to `parts()` or `values()` returns a new list, and a change to that list does not change the template:

```blink
type Ctx {}

fn log_it(t: Template[Ctx]) -> Int {
    let mut ps = t.parts()
    ps.push("; DROP TABLE t")    // changes ps only
    t.parts().len()              // unchanged: the template still has its own parts
}
```

This rule is what makes the literal coercion the only way to put text into the parts. Without it, any function that receives a template could push text into the parts, with no `Raw` and no `RawBypassesParam`. *(Non-normative: an implementation may share storage between the template and the returned list until the first write, provided no program can observe the sharing.)*

A handler reads each value with a `match` over `TemplateValue`. Read `values()` once, before the loop, because each call makes a new list:

```blink
fn bind_template(stmt: Sqlite3Stmt, tpl: Template[DB]) -> Int {
    let vals = tpl.values()
    let mut i = 0
    for v in vals {
        i = i + 1                        // SQL parameters count from 1
        let rc = match v {
            TemplateValue.Int(n) => sqlite_bind_int(stmt, i, n)
            TemplateValue.Float(f) => sqlite_bind_double(stmt, i, f)
            TemplateValue.Bool(b) => sqlite_bind_int(stmt, i, if b { 1 } else { 0 })
            TemplateValue.Str(s) => sqlite_bind_text(stmt, i, s)
            TemplateValue.Null => sqlite_bind_null(stmt, i)
        }
        if rc != 0 { return rc }
    }
    0
}
```

#### Template Values (normative)

`TemplateValue` is a compiler-known, closed prelude enum:

```blink
type TemplateValue {
    Int(Int)
    Float(Float)
    Bool(Bool)
    Str(Str)
    Null
}
```

It is the same for every context `C`. To add a variant is a language change, because every handler's exhaustive `match` must then change (E0004 names each site).

Each interpolation hole in a `Template[C]` literal becomes one value, by the hole's static type:

| Hole type | Value |
|---|---|
| `Int`, `I8`, `I16`, `I32`, `U8`, `U16`, `U32` | `TemplateValue.Int`, widened to `Int` |
| `Float`, `F32` | `TemplateValue.Float`, widened to `Float` |
| `Bool` | `TemplateValue.Bool` |
| `Str` | `TemplateValue.Str` |
| `Option[T]`, where `T` is a type in the rows above | `Some(x)` gives the value for `x`; `None` gives `TemplateValue.Null` |
| `Raw[T]` | No value: the text folds into the parts (see below) |

`Display` is not invoked on a hole (§3.6 *Display Format Protocol*). Any other hole type is `error[TemplateHoleType]` (E0534). That includes `Char`, `U64`, `Option[Option[T]]` (`None` and `Some(None)` would both give `Null`, and the handler could not tell them apart), and every struct, enum, tuple and collection. The compiler reports it at typecheck, at the hole, and never at codegen. Each `help:` line is a repair that compiles and keeps the value a parameter:

- the type has `Display`: send its text, `{p.display()}`
- a struct with fields of a valid type: send a field, `{p.id}`
- `U64`: convert first, `let n = Int.try_from(big)?`, then `{n}`
- `Option[Option[T]]`: `match` to one level of `Option` first

A `help:` line never offers `Raw(...)`. `Raw` is an audited bypass, not a repair for a type error. If no repair in the list applies to the type, the diagnostic gives the `note:` line only:

```
error[TemplateHoleType]: `Point` cannot be a Template value
 --> geo.bl:4:44
  |
4 |     db.execute("INSERT INTO pts VALUES ({p})")
  |                                          ^ `Point` is not a Template value type
  |
  = note: Template values are Int, Float, Bool, Str, the narrower integers,
          F32, and Option of these
  = help: send it as a string value: `{p.display()}`
  = help: or send its fields: `{p.x}`
```

#### The Context Parameter `C` (normative)

`C` names any declaration in the type namespace: a `type`, a type alias, a `trait`, or an `effect` (these share one namespace, §10.6 *Shadowing Rules*). Two contexts are the same only when they name the same declaration; the module qualifies the name. `Template[C]` is **invariant** in `C`.

**An effect name denotes a type.** Each `effect` declaration also gives a nominal type of the same name. This type has no values, has no constructor, and is not a subtype of any other type. So `Template[DB]` names the `DB` effect's type, and it is distinct from `Template[Shell]`:

```blink
fn sink(t: Template[DB]) -> Int { t.values().len() }
fn cross(t: Template[Shell]) -> Int { sink(t) }   // error: expected `Template[DB]`, found `Template[Shell]`
```

Four rules limit this type:

1. **It is written only as a type argument.** `fn f(x: DB)` and `let x: DB` are `error[EffectTypeAsValue]` (E0535): effect `DB` is not a value type. Any type-argument position is allowed. `List[DB]` compiles, and because `DB` has no values the list is always empty, as `List[Never]` is. A generic `fn h[T](x: T)` bound at `T = DB` is sound: no value exists to pass.
2. **It does not enter effect positions.** An effect name in a type-argument position denotes its type, not the effect. `Handler[E]` still requires an effect, so `fn f[C](h: Handler[C])` is still a kind error (no effect-kinded generics in v1).
3. **Only a top-level effect gives a type.** `Template[DB.Read]` is `error[SubEffectAsType]` (E0536), whose `help:` names the parent effect `DB`.
4. **A marker type is also a valid context.** A context with no effect, such as HTML, declares one: `type Html {}`.

*(Non-normative: a later lint may warn on an effect's type written in a position that holds values, such as `Map[Str, DB]`. Such a lint warns at the written annotation only, never through a generic binder, and is never an error.)*

**`C` comes from the expected parameter type.** At the coercion, the literal takes `C` from the type the site expects, by the same bidirectional check as any other expression. `C` is never inferred from the effects in the enclosing signature.

**`C` may be a type parameter.** `fn log_query[C](t: Template[C]) -> Int` is ordinary generic code and accepts a template of any context. A literal whose expected type is `Template[C]` with `C` still unbound is under-determined: `error[CannotInferType]` (E0301, §3.4), whose `help:` names the explicit type argument, for example `log_query[DB]("...")`. *(Non-normative: each `C` is its own instantiation, as §3.4 *Explicit Type Application* (no erasure) requires. Every `Template[C]` has the same runtime layout, so the generated bodies for two contexts can be identical, and an implementation may merge identical bodies, as a linker may fold identical functions. No program can observe the merge, and the language does not require it.)*

**An unknown name is an error.** `Template[Usr]` with no declaration named `Usr` is `error[UnknownType]` (E0507), as in every other type annotation (§3.4 *Type Name Resolution*). It never becomes a type variable.

#### Compile Errors for `Str` → `Template` Mismatch

A pre-built `Str` variable cannot be passed where `Template[C]` is expected. This prevents laundering tainted data through a string variable:

```blink
let q: Str = "SELECT * FROM users WHERE id = {id}"
db.query_one(q)  // COMPILE ERROR: expected Template[DB], got Str
```

```
error[E0310]: type mismatch
 --> user.bl:5:18
  |
5 |     db.query_one(q)
  |                  ^ expected `Template[DB]`, found `Str`
  |
  = note: string variables cannot be implicitly converted to Template
  = hint: pass the string literal directly, or wrap values in Raw() for dynamic SQL
```

This is intentional. The auto-decomposition only works on string *literals* at the call site, where the compiler can see the template structure. A `Str` variable is opaque — the compiler cannot extract parts from it.

#### `Raw(expr)` — The Escape Hatch

For dynamic SQL (table names, column lists, generated clauses), wrapping an interpolated expression in `Raw()` bypasses decomposition for that specific value — folding it into the literal parts instead.

`Raw[T]` is a **real marker type**, not a spelling the compiler matches. `Raw(expr)` constructs a `Raw[T]` from a `T`, and the type carries the marker wherever the value goes:

- `Raw[T]` implements **no `Display`**. The only thing that consumes it is a `Template[C]` coercion, which concatenates the wrapped value into the adjacent literal segment.
- The marker survives a binding. `let t = Raw(table)` has type `Raw[Str]`, and interpolating `t` into a template is the same bypass as writing `Raw(table)` inline — with the same audit obligation.
- Nothing strips it implicitly. A `Raw[T]` is not a `T`, and there is no coercion from one to the other.

```blink
fn dynamic_report(table: Str, id: Int) -> Result[Row, DBError] ! DB.Read {
    // Only table is concatenated into parts; id is a separate value
    db.query_one("SELECT * FROM {Raw(table)} WHERE id = {id}")
    // For table = "users", the handler observes:
    //   parts()  == ["SELECT * FROM users WHERE id = ", ""]
    //   values() == [TemplateValue.Int(id)]
    // "users" was folded from table into the first part
}

// Fully dynamic (all raw) — still works, just verbose
db.query_one("{Raw(whole_query)}")
```

**The audit warning fires where the bypass happens.** A `Raw[T]` folded into a `Template[C]` is the un-parameterized interpolation, and that coercion — and only that coercion — raises `RawBypassesParam`:

```
warning[RawBypassesParam]: Raw() bypasses parameterization
 --> report.bl:3:42
  |
3 |     db.query_one("SELECT * FROM {Raw(table)} WHERE id = {id}")
  |                                  ^^^^^^^^^^ concatenated into the query text, not parameterized
  |
  = help: if `table` comes from user input, parameterize it instead: `{table}`
  = help: only if no parameterized form exists, record the review: add
          @trusted(audit: "AUDIT-ID") to the enclosing function; it needs a
          record `AUDIT-ID` in audits.toml
```

Neither help line is machine-applicable, and the second is never offered as a quick fix. The record holds the author's claim that the value cannot carry an injection; §9.1 *Audit Records* says what the record must hold and when its pin lapses.

The warning does **not** fire on an ordinary interpolated string, because an ordinary string contains no `Raw[T]`. That is what making the marker a type buys: the trigger is the value's type, so it is neither defeated by binding the value to a variable first nor raised by a string that merely mentions the word.

`RawBypassesParam` is an **audit-gated** diagnostic: `@trusted(audit: K)` is its only suppression channel, and naming it in `@allow` or in `[lints]` is refused. The mechanism is stated once, for every diagnostic that uses it, in §9.1 *Audit-Gated Diagnostics*.

**A `Raw[T]` in a position that does not consume it is an error.** Because `Raw[T]` has no `Display`, a misplaced `Raw()` would otherwise fall through to `MissingDisplayImpl` (E0523), whose prescribed repairs — derive `Display`, write an `impl`, call `.debug()` — are all impossible on a compiler-known marker type. It gets its own diagnostic instead, whose first repair compiles:

```blink
// intentional-error example
fn log_table(table: Str) ! IO {
    io.println("scanning {Raw(table)}")   // error[RawOutsideTemplate]: a `Raw[T]` reached a
                                          //   position that does not consume it -- only a
                                          //   `Template[C]` coercion does
                                          // help: drop the wrapper: `"scanning {table}"`
}
```

**Why `Raw(expr)` instead of format specs or `Template.raw()`:**

- **Per-interpolation granularity.** Unlike a whole-string `raw()` which disables parameterization entirely, `Raw()` affects only the wrapped expression. Mixed safe/unsafe queries work naturally.
- **No string grammar extension.** `Raw(expr)` is just an expression inside `{...}` — zero new parser productions. No `:modifier` syntax that invites format specs (`:.2f`, `:>20`).
- **Type-system native.** Consistent with Blink's "types are the mechanism" philosophy. `Raw[T]` is a compiler-known type like `Option[T]` or `Result[T,E]`.
- **Proven pattern.** Django's `mark_safe()`, Rails' `raw()`, Jinja2's `Markup()` — the industry consensus is to mark the VALUE, not the template slot.

#### Phantom Type Extensibility

The phantom type `C` in `Template[C]` enables the same mechanism for other injection contexts:

```blink
// Shell injection protection
fn run(cmd: Template[Shell]) -> Result[Output, ShellError]
process.run("ls -la {path}")  // path is decomposed, handler quotes/escapes

// HTML/XSS protection (future)
fn render(template: Template[HTML]) -> SafeHtml
html.render("<div>{user_content}</div>")  // handler entity-escapes

// LDAP injection protection (future)
fn search(filter: Template[LDAP]) -> Result[List[Entry], LDAPError]
```

Each context defines its own reassembly strategy. The developer writes the same interpolation syntax everywhere — the receiving type ensures safety, and the handler decides how to make it safe.

#### Design Rationale

**Why not taint tracking:** Full information flow tracking (Section 9.3) requires tracking provenance on every value through inference, generics, and closures. `Template[C]` with `Raw[T]` achieves 95% of the safety at the type boundary with minimal type system extension — two compiler-known types that enable per-interpolation safety control.

**Why not a new string syntax:** Adding `sql"..."` or `q"..."` prefixes violates the "one string syntax" principle (Section 2.2). The receiving type determines behavior, not a prefix on the literal.

**Why phantom types:** `Template[DB]` and `Template[Shell]` are distinct types. You cannot pass a `Template[Shell]` to a function expecting `Template[DB]`. The phantom parameter prevents cross-context confusion at compile time.

**Why decomposed structure (not compiler-rewritten `$1/$2`):** Parameterization syntax is database-specific (PostgreSQL `$1`, MySQL `?`, Oracle `:name`). The compiler should decompose the interpolated string, not rewrite it. This follows the universal industry pattern: Python 3.14 `Template`, C# `FormattableString`, and JS tagged templates all have the language decompose and the library reassemble. User-authored effect handlers participate on equal footing with stdlib handlers.

**Why decomposed (not phantom-only):** Handlers need to read `parts()` and `values()` at runtime to reassemble the template with their dialect-specific syntax. A phantom over a plain string would leave handlers with an opaque string they cannot decompose.

**Why opaque (not a struct with fields):** A `values` field would need a type for "any interpolated value", and Blink has no surface top type (§3.4 *Under-Determined Types*). The closed `TemplateValue` enum is the type instead: it keeps each value's kind, so an `Int` reaches the driver as an integer, and a handler's `match` over it is exhaustive. Public fields would also let code build a template without the literal coercion, which is the one construction path the injection rule depends on.

**Cross-language precedent:**

| Language | Type | Decomposition | Reassembly |
|----------|------|---------------|------------|
| Python 3.14 | `Template` | `.args` alternating `(str, Interpolation)` | Handler walks args |
| C# | `FormattableString` | `.Format` + `.GetArguments()` | Handler reads format + args |
| JavaScript | Tagged template | `strings[]` + `values[]` | Tag function zips them |
| **Blink** | **`Template[C]`** | **`parts()` + `values()`** | **Handler matches `TemplateValue`** |
