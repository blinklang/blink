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
listen(0)            // WARNING (V0002): contract always fails: 0 > 0 is false
listen(70000)        // WARNING (V0002): contract always fails: 70000 <= 65535 is false

// When the value is dynamic, the compiler inserts a check at the boundary
fn start_server(config: Config) ! Net {
    let port = config.port      // port is Int, not Port
    listen(port)                // runtime check (V0004): config.port may be 0
}

// Fix: validate at the boundary
fn start_server(config: Config) -> Result[(), ServerError] ! Net {
    let port = Port.try_from(config.port)?   // runtime check, returns Result
    listen(port)                              // OK: port is now Port
}
```

A literal that fails the refinement gets the warning V0002 `ContractAlwaysFails` (§3b.4). The call still panics when it runs. A `@where` refinement on a parameter acts as an implied `@requires` for V0002, so `fn listen(port: Port)` and `@requires(port > 0 && port <= 65535) fn listen(port: Int)` give the same diagnostic at each call site.

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

Contracts attach to functions, to methods in `impl` blocks, and to trait method declarations. A trait method's contract binds every impl of that method; see *Contracts on Trait Methods* below.

**`@pure`.** `@pure` on a function says that the function is pure: its effective row is empty (§4.16.3). It performs no side effects and does not read or write module-level `let mut` bindings. The compiler checks the body. A `@pure` function whose effective row is not empty is `ImpureBodyForPureAnnotation` (E1307). A contract predicate can call only a `@pure` function (`ImpureCallInPredicate`, E1302).

#### Preconditions with `@requires`

```blink
@requires(index >= 0 && index < list.len())
fn get_unchecked[T](list: List[T], index: Int) -> T {
    list.internal_get(index)
}
```

The `@requires` clause is a promise by the caller: "I guarantee this condition holds before calling you." At every call site, the compiler proves the precondition, finds that it always fails (V0002), or inserts a runtime check (§3b.4).

```blink
fn example(items: List[Str]) {
    get_unchecked(items, 0)     // runtime check (V0004): items may be empty
    get_unchecked(["a"], 5)     // WARNING (V0002): contract always fails: 5 < ["a"].len() is false
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

#### Contracts That Call Their Own Function

A contract predicate of function `f` may not call `f`, directly or through a cycle. To check this rule, the compiler builds a graph: an edge runs from a function's contract predicates to each function they call. Calls in a function *body* are not edges, so a recursive body is still legal. A cycle in this graph is a compile error (`error[RecursiveContractPredicate]`, E1309). The diagnostic prints the cycle.

```blink
@ensures(result == depth(n))           // E1309 -- `depth`'s contract calls `depth`
@pure
fn depth(n: Int) -> Int {
    if n <= 0 { 0 } else { 1 + depth(n - 1) }    // OK: a body call is not an edge
}

@requires(is_ok(x))                    // E1309 -- cycle: `check` -> `is_ok` -> `check`
@pure
fn check(x: Int) -> Bool { x > 0 }

@requires(check(x))
@pure
fn is_ok(x: Int) -> Bool { x >= 0 }
```

```
error[RecursiveContractPredicate]: a contract of `check` calls `check`
 --> pred.bl:7:11
  |
7 | @requires(is_ok(x))
  |           ^^^^^^^^ `is_ok` is called here
  |
  = note: cycle: contract of `check` calls `is_ok`; contract of `is_ok` calls `check`
  = help: state the predicate without a call back into `check`
```

The rule applies the same way to trait methods: a predicate on `Trait.m` may not call `m` through any receiver. Without it, the verifier would need `m`'s contract to check `m`'s contract.

#### Contracts on Trait Methods

A trait method declaration may carry `@requires` and `@ensures`. Every impl of that method inherits them. The rule in one line: **an impl may promise more, never demand more.** It has the same narrow-only shape as the effect-row rule for impls (§3.6, E0904).

```blink
trait Stack {
    fn size(self) -> Int

    @requires(self.size() > 0)
    @ensures(result.size() == old(self.size()) - 1)
    fn drop_top(self) -> Self
}

type IntStack { items: List[Int] }

impl Stack for IntStack {
    fn size(self) -> Int { self.items.len() }

    // Inherits `@requires(self.size() > 0)` and the trait's `@ensures`.
    @ensures(result.items.len() == self.items.len() - 1)    // OK: an impl may add @ensures
    fn drop_top(self) -> IntStack {
        IntStack { items: self.items.drop_last() }
    }
}
```

**What an impl inherits.** The trait's `@requires` and `@ensures` apply to every impl of the method, with no restatement. The compiler elaborates each impl method to a plain function with this contract:

- `@requires`: the trait's predicate `P_t[σ]`
- `@ensures`: `Q_t[σ] && Q_i`, where `Q_t` is the trait's predicate and `Q_i` is the impl's own `@ensures` (true if the impl writes none)
- `@verify`: the effective policy (see *`@verify` on trait methods* below)

Here `σ` binds the trait's parameters to the impl's parameters by position (see *Parameter binding* below). From this point, the impl method is verified and run as any other function (§3b.3, §3b.4). Hover and `blink query` show this elaborated contract, with each inherited row tagged `[inherited: Trait.m]`.

**An impl may not write `@requires`.** A generic caller through `T: Trait` sees only the trait's precondition. If an impl could demand more, a call that is correct for the trait could fail for one type. A `@requires` on an impl method of a trait is a compile error (`error[TraitImplAddsPrecondition]`, E0912), even when the predicate is the same as the trait's. To restrict input, the fixes are:

- move the predicate to the trait method, so every caller sees it
- give the parameter a refinement type (§3b.1) in the trait's signature; a refined type on the impl alone is a param type mismatch (E0902), because it also demands more than the trait
- put the restricted operation in a free function that is not a trait method

```
error[TraitImplAddsPrecondition]: an impl of a trait method may not add `@requires`
 --> stack.bl:14:5
   |
14 |     @requires(self.items.len() > 1)
   |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `IntStack.drop_top` implements `Stack.drop_top`
   |
   = note: `@requires(self.size() > 0)` is already inherited from `Stack.drop_top`
   = help: a caller through `T: Stack` cannot see this precondition; move it to
           `Stack.drop_top`, give the parameter a refinement type in the trait, or use a free function
```

**An impl may add `@ensures`.** The impl's own `@ensures` is ANDed with the trait's. An impl `@ensures` that restates an inherited predicate adds nothing and gets a warning (`warning[RestatedInheritedEnsures]`, W0900); the compiler checks it once.

**What a caller assumes.** A call through a bound (`x.m()` with `x: T` and `T: Trait`) checks the trait's `@requires` at the call site and assumes only the trait's `@ensures` after it. Monomorphization never brings in a contract from the impl: a generic function verifies once, against the trait. A call that names the concrete type statically (`s.drop_top()` with `s: IntStack`) checks the same `@requires` and assumes both the trait's and the impl's `@ensures`.

**Parameter binding.** An impl may name its parameters differently from the trait (§3.6). Inherited predicates bind by position, with capture-avoiding substitution. `self` binds to position 0 whatever name the impl gives it. The compiler adds no parameter-name check. Every diagnostic and tool surface that shows an inherited predicate prints both names, for example "trait param `n` (impl param `count`)". This includes hover, `blink query`, V0002 diagnostics, and counterexample notes.

```blink
trait Buffer {
    @requires(n >= 0)
    @ensures(result.len() == n)
    fn take(self, n: Int) -> List[Int]
}

impl Buffer for Ring {
    // `n` binds to `count` by position: the inherited @requires is `count >= 0`.
    fn take(self, count: Int) -> List[Int] {
        self.items.take(count)
    }
}
```

**`@verify` on trait methods.** A trait method declaration may carry `@verify` with `fallback: "error"` or `fallback: "runtime"`. It is the default policy for every impl body of that method that has no `@verify` of its own. `@verify(fallback: "trust")` on a trait method declaration is a compile error (`error[TrustOnTraitMethod]`, E0913): a trust decision covers one body, and a trait author cannot see the bodies of downstream impls.

- An impl method's own `@verify` (`"trust"` included) replaces the trait's default as a whole. The two never merge.
- The default resolves at elaboration, before verification. It also applies to an open-default body and to each override of it.
- A fallback applies only when the outcome is Unknown (§3b.4). A Proven contract costs nothing, so a trait default never adds a check that the solver can remove.
- With no `@verify` on the trait method or the impl, an Unknown outcome gets a runtime check, as for any other function (§3b.4). An inherited runtime check runs in every build. The verification report lists the inherited runtime checks for each impl.

With `"error"`, a trait author can demand a proof from every impl. Adding `"error"` to a method of a published trait is a breaking change: an impl that compiled with a runtime check may now get V0003.

```blink
trait Score {
    @ensures(result >= 0 && result <= 100)
    @verify(fallback: "error")                // default for every impl body
    fn score(self) -> Int
}

impl Score for Exam {
    // No @verify: the trait's "error" default applies to this body.
    fn score(self) -> Int {
        self.correct * 100 / self.total
    }
}

impl Score for Model {
    @verify(fallback: "runtime")              // replaces the trait default; not redundant (no W0901)
    fn score(self) -> Int {
        self.eval_score()
    }
}

trait Shape {
    @ensures(result >= 0.0)
    @verify(fallback: "trust")                // E0913 -- "trust" on a trait method declaration
    fn area(self) -> Float
}
```

If the effective policy is `"error"` and the outcome is Unknown, the error is V0003 at the impl method. The message names the trait method that sets the default, and names the impl method as the place for `@verify`. For example, with a trait method `Gauge.level` that has `@ensures(result >= 0)` and `@verify(fallback: "error")`:

```
error[V0003]: contract unverifiable
 --> tank.bl:9:5
  |
9 |     fn level(self) -> Int {
  |     ^^^^^^^^ outcome unknown
  |
  = note: `@ensures(result >= 0)` is inherited from `Gauge.level`
  = note: `@verify(fallback: "error")` is inherited from `Gauge.level` and requires a proof
  = note: no solver ran; this compiler cannot prove contracts
  = help: add `@verify(fallback: "runtime")` to this impl method to check the contract at runtime
```

**Default methods.** A trait default body is verified once against the trait's contract, generically over `Self` (the default body is parametric in `Self`, §3.6 *Operations on `Self` in a Default Body*). Its monomorphized copies use that result. An open default's override inherits the same contract and must discharge it in its own body. A `final` default fixes both its body and its contract.

**Predicate scope.** A trait-method predicate may use the method's parameters, `self`, `result` (in `@ensures`), `old(...)`, and methods of the trait, of its supertraits, and of the bounds on its type parameters. The purity rules are the same as for function contracts (E1301, E1302).

**Supertraits.** A subtrait may not redeclare a supertrait method to add or change its contract. This is `E0733 SubtraitMethodRedeclaration` (§3.6 *The `final` Modifier*), for the same coherence reason: `x.m()` would have two contracts, one through each bound.

**`@ffi`.** A trait method that has a contract may not be implemented directly by an `@ffi` function. A safe wrapper implements it and carries the contract (E0803).

**Migration.** Before this rule, an impl method could carry `@requires`, and a trait method declaration could not carry contracts (E1110). An existing impl `@requires` is now E0912. To fix it, move the predicate to the trait method, give the parameter a refinement type in the trait's signature, or call a free function.

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
fn transfer(amount: Int, *, from: Account, to: Account) -> TransferResult {
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

#### Always Fails (Warning)

A `@requires` check always fails when it is false on every run that reaches the call. The compiler reports the warning V0002 `ContractAlwaysFails`. The runtime check stays: when the call runs, it still panics, or raises `validation.contract_violation(...)` at a system boundary (§9.2). A `@where` refinement (§3b.1) acts as an implied `@requires`, with the same code and the same diagnostic.

```
warning[V0002]: contract always fails
 --> account.bl:45:9
  |
45|     withdraw(balance, -5)
  |                       ^^ `-5 > 0` is false
  |
 ::: account.bl:22:1
22| @requires(amount > 0)
  | --------------------- contract declared here
  |
  = note: this call panics at run time
  = help: pass a value that satisfies `amount > 0`
```

The warning names the call site and the folded predicate.

**When it fires.** Every argument that the predicate reads is a literal at the call site, and the folded predicate is `false`. Only the arguments that the predicate reads must be literals. A literal is a tree of literals, parentheses, unary `-`, and `+ - * / %` (the tree of W0708), or a list, string or range literal whose parts are such trees. A `let` or `const` reference stops the tree. The predicate must fold in the const evaluator that compile-time constants use (E0546).

```blink
@requires(amount > 0)
fn withdraw(balance: Int, amount: Int) -> Int {
    balance - amount
}

fn demo(balance: Int, n: Int) {
    withdraw(balance, -5)       // WARNING (V0002): `-5 > 0` is false
    withdraw(balance, n)        // no V0002: n is not a literal; runtime check (V0004)
    let k = -5
    withdraw(balance, k)        // no V0002: a `let` reference stops the tree
}

test "a negative amount panics" {
    assert_panics { withdraw(10, -5) }   // no V0002 inside assert_panics
}
```

**When it does not fire.** V0002 does not fire when the fold panics, when the predicate cannot be evaluated (a call that is not const, an FFI call), or when the evaluator reaches its limit. The outcome is then Unknown, and the runtime check stays.

**Solver hits.** A solver may add a V0002 hit only where it proves that some run reaches the call and that the predicate is false on every run that reaches it. One counterexample never counts. This applies only to solver hits; literal hits fire in dead branches.

**Lint controls.** V0002 has the same shape as W0704 and W0708:

- It does not look through `let` or `const` references.
- It fires in a branch that never runs.
- It does not fire inside an `assert_panics` body.
- `@allow(ContractAlwaysFails)` suppresses it.
- The level is set under `[lints]` in `blink.toml`: `"off"`, `"warn"` or `"error"`. Only `[lints]` changes the level. `@verify(fallback: "error")` does not.

`@ensures` is not part of V0002 for now.

#### Unknown (Runtime Check by Default)

The solver cannot determine whether the contract holds. The predicate is beyond what the SMT theories can decide, the solver times out, or no solver ran. A counterexample on a dynamic input (a parameter, a field, I/O) is also Unknown: some runs fail and some pass, so the contract does not always fail. By default, the compiler inserts a runtime check:

- A `@requires` check runs at the function's entry, before the body. Every caller gets it.
- An `@ensures` check runs at each exit of the function, after `result` is known. Each `old(expr)` in the clause is evaluated once at entry and kept for the exit check.
- A failed check panics. At a system boundary (§9.2), a failed `@requires` check raises `validation.contract_violation(...)` in place of a panic (§4.4.2).

```blink
@requires(amount > 0)
@ensures(result.balance == old(self.balance) - amount)
fn withdraw(self: Account, amount: Int) -> Account {
    Account { balance: self.balance - amount, ..self }
}
// No @verify: if the outcome is Unknown, both clauses are checked at runtime.
```

The default needs no annotation. A function's own `@verify` governs its whole contract, `@requires` included. A caller never writes `@verify` for a callee's contract.

**Every build has the check.** A runtime contract check runs in every build mode, release included. No build flag, profile or `blink.toml` setting removes it. The only way to remove the check from one function is `@verify(fallback: "trust")` on that function. This rule follows from modular verification (§3b.3): a caller's proof assumes the callee's `@ensures`, so a build that removed the check would turn each callee contract into a trust that no reviewer can see.

**Cost.** A passing check costs the predicate and one predicted branch. The compiler formats the failure message only on the failure path, which it never inlines into the function. The verification report (`blink verify`) shows a cost class for each runtime check: `O(1)`, `calls a function`, or `walks a collection`. It also lists the `old()` snapshots that the check copies at entry.

**Failure message.** A failed runtime check prints:

- the contract text and its clause kind (`@requires` or `@ensures`)
- the function, and the span of the clause
- the value of each free variable of the predicate, with each value cut to a fixed length
- the caller

```
panic: contract violated: @requires(amount > 0)
  --> account.bl:4:1  in withdraw
   = amount = -5
   = called from transfer_all at account.bl:45:9
```

**Predicates that cannot run.** The runtime default applies to an executable predicate. A non-executable predicate whose outcome is Unknown is V0003 unless it has `@verify(fallback: "trust")`. A predicate is executable when the compiler can evaluate it as code: it is pure, it terminates, and it reads only finite values that the program holds. Each predicate form in this section is executable. The rule governs a form that is not, for example a quantifier over all of `Int` (a domain too large to walk), or a reference to a value that exists only for the proof and that the program does not hold.

**The default is visible.** Each contract that gets a runtime check has the info diagnostic `info[V0004]: contract checked at runtime`. V0004 is silent by default. It shows in the verification report and in `blink query`, with its source: `default`, `explicit`, or `inherited(Trait.method)`.

**Counterexamples.** When the solver finds a counterexample on a dynamic input, the counterexample shows in a note on V0004, in the `blink verify` report, and in V0003 under `@verify(fallback: "error")`. The text of a counterexample is not stable between solver versions. Until the compiler has a solver, no counterexample exists.

#### `@verify` Fallback Values

`@verify(fallback: ...)` sets what happens when the outcome is Unknown. It has no effect on a Proven or Always Fails outcome. V0002 fires under every `@verify` value, `"trust"` included. `@verify(fallback: "error")` does not make V0002 an error; only `[lints]` changes its level. A counterexample on a dynamic input is an Unknown outcome, so `"error"` gives V0003 for it.

| Value | When the outcome is Unknown |
|---|---|
| (no `@verify`) | Runtime check (the default) |
| `"runtime"` | Runtime check. Legal, but the same as the default unless it replaces a trait method's `"error"` |
| `"error"` | Compile error V0003. The contract must be proven |
| `"trust"` | No check. The compiler accepts the contract without proof |

**`"error"`: the contract must be proven.** Use it where a runtime check is not acceptable, for example in a hot loop or where a panic must not occur:

```blink
@requires(i >= 0 && i < xs.len())
@verify(fallback: "error")
fn read_at(xs: List[Int], i: Int) -> Int {
    xs.get(i).unwrap()
}
```

Until the compiler has a solver, every outcome is Unknown, so a contract with `"error"` always gets V0003.

```
error[V0003]: contract unverifiable
 --> read.bl:1:1
  |
 1| @requires(i >= 0 && i < xs.len())
  | ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ outcome unknown
  |
  = note: `@verify(fallback: "error")` requires a proof
  = note: no solver ran; this compiler cannot prove contracts
  = help: remove `@verify(fallback: "error")` to check the contract at runtime
```

When a solver ran and returned unknown, the second note says so, and the help also offers to simplify the predicate. The help never offers to simplify when no solver ran.

**`"trust"`: accept without proof.** The compiler takes the developer's word that the contract holds and inserts no check. Use it for a contract that describes behavior no solver or runtime check can confirm (cryptographic properties, probabilistic guarantees), or for a predicate that is not executable:

```blink
@ensures(result.entropy() >= 256)
@verify(fallback: "trust")
fn generate_key() -> PrivateKey ! Crypto {
    // Entropy is not something an SMT solver can reason about.
    // The contract documents the intent; testing and audits verify it.
}
```

Code reviewers and AI agents can search for `@verify(fallback: "trust")` to find each gap in the verification chain. The verification report also marks each Proven contract whose proof assumes a callee's `"trust"` contract, for example `proven (assumes: crypto.generate_key @ensures, trust)`. When the solver cannot list the callee contracts that a proof used, the report says `dependencies unknown`.

**Diagnostics.**

- An explicit `@verify(fallback: "runtime")` that is the same as the policy without it gets `warning[RedundantVerifyFallback]` (W0901), with an autofix that removes it. The compiler resolves the trait method's default before it decides. A `"runtime"` that replaces a trait method's `"error"` is not redundant and gets no warning.
- `@verify` on a function that has no `@requires` and no `@ensures` (own or inherited) gets `warning[VerifyWithoutContract]` (W0902), with an autofix that removes it.

**No project-wide policy.** The policy for a function comes only from its own `@verify`, its trait method's `@verify` (§3b.2), and the default. There is no module-level or `blink.toml` default. To make CI reject runtime checks or trusts, run `blink verify --deny runtime,trust`. It exits non-zero when a contract has one of the named outcomes, and it does not change what a contract means.

#### Why Default to a Runtime Check

Principle 4 (§1.2) says the compiler proves what it can and checks the rest at runtime. A runtime check is the "check the rest" part. It keeps each contract sound: a caller may assume a callee's `@ensures`, because the program stops before a false `@ensures` reaches the caller.

A default of "error on Unknown" fails this goal while no solver exists, and is weak after one exists. Each contract needs an annotation, so the easy path is to add `@verify(fallback: "trust")`, which removes the check. A runtime default makes the safe path the short path. The annotation is needed only to demand a proof (`"error"`) or to remove the check (`"trust"`), and both are visible and searchable.

#### Verification Summary

| Outcome | Meaning | Runtime cost | Developer action |
|---|---|---|---|
| **Proven** | SMT proved the contract | Zero | None needed |
| **Always Fails** | The predicate is false on every run that reaches the call (V0002, warning) | Runtime check stays, under every `@verify` value | Fix the call, or `@allow(ContractAlwaysFails)` |
| **Unknown** (default) | Runtime check inserted (V0004) | Check cost, every build | None needed; see the report for cost |
| **Unknown** + `"error"` | Proof required | N/A (won't compile, V0003) | Simplify the predicate, or remove `"error"` |
| **Unknown** + `"trust"` | Accepted without proof | Zero | Document why, audit manually |
| **Unknown**, not executable | No check can run | N/A (won't compile, V0003) | Add `"trust"`, or rewrite the predicate |

---

### 3b.5 Context-Sensitive Template Types

Blink's universal string interpolation (`"Hello, {name}!"`) is safe for display strings — but dangerous when interpolated strings flow to injection-sensitive contexts like databases, shells, or HTML templates. The template literal `t"..."` (§2.4.3) keeps the values apart from the text, and the `Template[C]` type makes sure that only a template reaches such a context, never a `Str`.

#### The Problem

```blink
fn get_user(id: Int) -> User? ! DB.Read {
    db.query_one(t"SELECT * FROM users WHERE id = {id}")
}
```

In most languages, interpolation into a query is textbook SQL injection. In Blink, it is safe: `t"..."` keeps `{id}` apart from the text, and `db.query_one` accepts `Template[DB]`, not `Str`. A string built by concatenation is a `Str`, so it cannot reach the database.

#### How `Template[C]` Works

`Template[C]` is a compiler-known **opaque** type parameterized by a phantom type `C` that identifies the injection context (DB, Shell, HTML, etc.). A template literal `t"..."` (§2.4.3) builds one: the compiler **decomposes** the literal into literal parts and interpolated values instead of concatenating them.

```blink
// What the developer writes:
db.query_one(t"SELECT * FROM users WHERE id = {id}")

// What the handler observes, for id = 42:
//   t.parts()  == ["SELECT * FROM users WHERE id = ", ""]
//   t.values() == [TemplateValue.Int(42)]

// A plain literal is a Str — normal concatenation:
Err(ApiError.NotFound("User {id} not found"))
```

The prefix decides what a literal builds: `t"..."` decomposes, and `"..."` concatenates. The parameter type decides what a site accepts: a `Template[DB]` parameter rejects a `Str`, and a `Str` parameter rejects a template. The safety comes from the parameter type, not from the `t`. A wrapper such as `fn run(sql: Str)` gives the safety up, whatever literal its callers write.

**Handler reassembly.** The handler — not the compiler — decides how to reassemble the template. Each database, shell, or HTML handler owns its dialect-specific parameterization syntax:

```blink
// PostgreSQL handler reassembles as: "SELECT * FROM users WHERE id = $1" with params [id]
// MySQL handler reassembles as: "SELECT * FROM users WHERE id = ?" with params [id]
// Shell handler applies quoting/escaping per-value
// HTML handler applies entity escaping per-value
```

This separation of concerns means the compiler never encodes dialect knowledge. User-authored effect handlers participate in parameterization on equal footing with stdlib handlers.

#### The `Template[C]` Surface (normative)

`Template[C]` has **no fields and no constructor**. Only a template literal `t"..."` builds one (§2.4.3). A `Raw[Str]` hole in that literal folds its text into the parts (see *`Raw(expr)` — The Escape Hatch* below). **Every part of a `Template[C]` is literal source text, or text folded in from a `Raw[Str]`.** To bind, return, store or pass a template keeps this true, so these need no further rule. A handler reads a template through two methods:

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

This rule is what makes the template literal the only way to put text into the parts. Without it, any function that receives a template could push text into the parts, with no `Raw` and no `RawBypassesParam`. *(Non-normative: an implementation may share storage between the template and the returned list until the first write, provided no program can observe the sharing.)*

The values follow the same rule. No Template value type is a shared cell (§3.6 *Shared cells*), so a write through another name, such as a `set_*` call on a `Bytes` that was a hole, does not change the template.

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
            TemplateValue.Bytes(b) => sqlite_bind_blob(stmt, i, b)
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
    Bytes(Bytes)
    Null
}
```

It is the same for every context `C`. To add a variant is a language change, because every handler's exhaustive `match` must then change (E0004 names each site). A handler names each variant; a `_` arm hides the next language change from E0004. A context with no use for a kind still names its arm and rejects the value there, for example with an `Err` that names the kind.

Each interpolation hole in a template literal becomes one value, by the hole's static type:

| Hole type | Value |
|---|---|
| `Int`, `I8`, `I16`, `I32`, `U8`, `U16`, `U32` | `TemplateValue.Int`, widened to `Int` |
| `Float`, `F32` | `TemplateValue.Float`, widened to `Float` |
| `Bool` | `TemplateValue.Bool` |
| `Str` | `TemplateValue.Str` |
| `Bytes` | `TemplateValue.Bytes` |
| `Option[T]`, where `T` is a type in the rows above | `Some(x)` gives the value for `x`; `None` gives `TemplateValue.Null` |
| `Raw[Str]` | No value: the text folds into the parts (see below; `Raw` wraps only a `Str`) |

`Display` is not invoked on a hole (§3.6 *Display Format Protocol*). Any other hole type is `error[TemplateHoleType]` (E0534). That includes `Char`, `U64`, `Option[Option[T]]` (`None` and `Some(None)` would both give `Null`, and the handler could not tell them apart), and every struct, enum, tuple and collection. The compiler reports it at typecheck, at the hole, and never at codegen. Each `help:` line is a repair that compiles and keeps the value a parameter:

- the type has `Display`: send its text, `{p.display()}`
- a struct with fields of a valid type: send a field, `{p.id}`
- `U64`: convert first, `let n = Int.try_from(big)?`, then `{n}`
- `List[U8]`: send it as bytes, `{Bytes.from_list(xs)}`
- `Option[Option[T]]`: `match` to one level of `Option` first

A `help:` line never offers `Raw(...)`. `Raw` is an audited bypass, not a repair for a type error. If no repair in the list applies to the type, the diagnostic gives the `note:` line only:

```
error[TemplateHoleType]: `Point` cannot be a Template value
 --> geo.bl:4:43
  |
4 |     db.execute(t"INSERT INTO pts VALUES ({p})")
  |                                           ^ `Point` is not a Template value type
  |
  = note: Template values are Int, Float, Bool, Str, Bytes, the narrower
          integers, F32, and Option of these
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

A built-in effect name does not reserve a type name (§4.3). In a module that declares `type DB`, `DB` in a type position is that type, so `Template[DB]` there names the user type.

*(Non-normative: a later lint may warn on an effect's type written in a position that holds values, such as `Map[Str, DB]`. Such a lint warns at the written annotation only, never through a generic binder, and is never an error.)*

**`C` comes from how the template is used.** A template literal has type `Template[α]`, where α is a new type variable (§2.4.3). The type that the site expects solves α, by the same bidirectional check as for any other expression. A later use in the same definition can also solve it, as for `[]` and `None` (§3.4 *Under-Determined Types*). `C` is never inferred from the effects in the enclosing signature. If α is not solved at the end of inference for the definition, the literal is `error[CannotInferType]` (E0301), and the span points at the `t"..."` literal. If two uses need different contexts, the error is at the second use, and a `note:` names the use that set `C`.

**`C` may be a type parameter.** `fn log_query[C](t: Template[C]) -> Int` is ordinary generic code and accepts a template of any context. A template literal passed to it with no other use that sets `C` is under-determined: `error[CannotInferType]` (E0301, §3.4), whose `help:` names the explicit type argument, for example `log_query[DB](t"...")`. *(Non-normative: each `C` is its own instantiation, as §3.4 *Explicit Type Application* (no erasure) requires. Every `Template[C]` has the same runtime layout, so the generated bodies for two contexts can be identical, and an implementation may merge identical bodies, as a linker may fold identical functions. No program can observe the merge, and the language does not require it.)*

**An unknown name is an error.** `Template[Usr]` with no declaration named `Usr` is `error[UnknownType]` (E0507), as in every other type annotation (§3.4 *Type Name Resolution*). It never becomes a type variable.

#### Compile Errors for `Str` and `Template` Mismatch

`Str` and `Template[C]` are different types, and neither converts to the other. A `Str` where `Template[C]` is expected is `error[TemplateMismatch]` (E0310), and so is a template where `Str` is expected. This stops tainted data from passing through a string variable: a `Str` has no holes, because its values were concatenated when it was built, and nothing can get them back.

For a plain literal, the `help:` adds the `t`. It points at the literal, and a tool can apply it:

```
error[TemplateMismatch]: expected `Template[DB]`, found `Str`
 --> user.bl:2:18
  |
2 |     db.query_one("SELECT * FROM users WHERE id = {id}")
  |                  ^ a plain string literal is a `Str`
  |
  = note: only a template literal `t"..."` builds a `Template[C]`
  = help: add the `t` prefix: `t"SELECT * FROM users WHERE id = {id}"`
```

For a `Str` value, no change at the call is a fix, because the text was built before the call:

```blink
// intentional-error example
fn get_user(id: Int) -> User? ! DB.Read {
    let q = "SELECT * FROM users WHERE id = {id}"   // Str: {id} is concatenated
    db.query_one(q)                                  // error[TemplateMismatch]
}
```

```
error[TemplateMismatch]: expected `Template[DB]`, found `Str`
 --> user.bl:3:18
  |
3 |     db.query_one(q)
  |                  ^ expected `Template[DB]`, found `Str`
  |
  = note: a `Str` has no holes; its values were concatenated when it was built
  = help: build it as a template literal: `let q = t"SELECT ..."`
```

In the other direction, the `help:` removes the `t`, and a tool can apply it:

```
error[TemplateMismatch]: expected `Str`, found a template literal
 --> greet.bl:2:16
  |
2 |     io.println(t"Hello, {name}!")
  |                ^ a `t"..."` literal builds a `Template`, not a `Str`
  |
  = help: remove the `t` prefix: `"Hello, {name}!"`
```

As for `TemplateHoleType`, no `help:` line offers `Raw(...)`.

#### `Raw(expr)` — The Escape Hatch

For dynamic SQL (table names, column lists, generated clauses), wrapping an interpolated expression in `Raw()` bypasses decomposition for that specific value — folding it into the literal parts instead.

`Raw[Str]` is a **real marker type**, not a spelling the compiler matches. `Raw(s)` with `s: Str` constructs a `Raw[Str]`, and the type carries the marker wherever the value goes:

- `Raw[Str]` implements **no `Display`**. The only thing that consumes it is a hole of a template literal `t"..."`, which concatenates the wrapped string into the adjacent literal segment, byte for byte.
- The marker survives a binding. `let r = Raw(table)` has type `Raw[Str]`, and `{r}` in a template literal is the same bypass as writing `Raw(table)` inline — with the same audit obligation.
- Nothing strips it implicitly. A `Raw[Str]` is not a `Str`, and there is no coercion from one to the other.

**This is a typing rule, not a rule on the source text.** In a template literal, each hole has a Template value type or the type `Raw[Str]`. A `Raw[Str]` hole folds and raises `RawBypassesParam`, whether the `Raw(...)` call is in the hole or the value came through a binding, a return or a generic call. A `Raw[Str]` in any other position, including a hole of a plain `"..."` literal, is `error[RawOutsideTemplate]` (E0530, below).

**`Raw` wraps only a `Str`.** The fold text is the string itself, so no type needs a rule for its text form. The compiler checks this where the `Raw` is built, at typecheck, and never at mono or codegen:

- `Raw(e)` requires `e: Str`. Any other type of `e` is `error[TemplateHoleType]` (E0534), and the span is the argument `e`. This holds when `e` has a type parameter `T` as its type: the error is at the generic definition, because `T` is not `Str`.
- A written type `Raw[X]` with `X` not `Str` is E0534 at that annotation. This holds in every place a type is written: a parameter, a return type, a field, a type alias and a type argument. `fn f[T](x: T) -> Raw[T]` is an error at its definition, not at a later instantiation.

So no value of type `Raw[X]` with `X` other than `Str` can exist, and a hole never has to consider one. The primary message names the rule, because the span is not at a hole: "`Raw` wraps only a `Str`, found `Int`". The `help:` lines remove the `Raw` and then apply the repairs of *Template Values* above to the type of `e`. They keep the value a parameter, and they never offer `Raw(...)`, as for every `TemplateHoleType`. If no repair applies, the diagnostic gives the `note:` line only:

```
error[TemplateHoleType]: `Raw` wraps only a `Str`, found `Int`
 --> page.bl:2:59
  |
2 |     db.query(t"SELECT * FROM posts ORDER BY id LIMIT {Raw(n)}")
  |                                                           ^ `n` is `Int`, not `Str`
  |
  = note: `Raw` folds only a `Str`; the text is the string, byte for byte
  = help: send it as a parameter: `{n}`
```

When the `Raw(...)` call is in a binding, the help drops the wrapper there: `let r = Raw(n)` gets `help: drop the wrapper: let r = n`, and the hole `{r}` then sends a parameter. A `Raw(opt)` with `opt: Option[Str]` gets `help: send it as a parameter: {opt}`, and `None` becomes `TemplateValue.Null`.

**A `Raw[Bytes]` is one case of this rule.** The parts are `List[Str]`, and a `Bytes` value has no lossless map into a `Str`. So `Raw(b)` with `b: Bytes` is E0534 at the argument, and its `help:` sends the value as a parameter:

```blink
// intentional-error example
fn store(img: Bytes) -> Result[Int, DBError] ! DB.Write {
    db.execute(t"INSERT INTO imgs VALUES ({Raw(img)})")   // error[TemplateHoleType]: `Raw` wraps
                                                         //   only a `Str`, found `Bytes`
                                                         // help: send it as a parameter: `{img}`
}
```

**`Raw` of a `Raw[Str]` is E0534 too**, because the argument is a `Raw[Str]`, not a `Str`. Its `help:` removes one `Raw`. This removes a bypass and adds none, so it keeps the rule above. The repair keeps exactly one `Raw[Str]` in the hole, and never removes both:

- `{Raw(Raw(s))}` gets `help: remove one Raw: {Raw(s)}`.
- `{Raw(r)}` with `r: Raw[Str]` gets `help: remove one Raw: {r}`.

**A value that is not a `Str` stays a parameter.** A number, a `Bool` or a `Float` in a template almost always belongs in a hole of its own type: `LIMIT {n}`, not `LIMIT {Raw(n)}`. Only when the context takes no parameter at that place, for example a column width in DDL, does the author build the text. The author then writes the conversion, and the audit sees it:

```blink
fn make_table(name: Str, width: Int) -> Result[Int, DBError] ! DB.Write {
    let w = width.display()
    db.execute(t"CREATE TABLE {Raw(name)} (title VARCHAR({Raw(w)}))")
}
```

```blink
fn dynamic_report(table: Str, id: Int) -> Result[Row, DBError] ! DB.Read {
    // Only table is concatenated into parts; id is a separate value
    db.query_one(t"SELECT * FROM {Raw(table)} WHERE id = {id}")
    // For table = "users", the handler observes:
    //   parts()  == ["SELECT * FROM users WHERE id = ", ""]
    //   values() == [TemplateValue.Int(id)]
    // "users" was folded from table into the first part
}

// Fully dynamic (all raw) — still works, just verbose
db.query_one(t"{Raw(whole_query)}")
```

**The audit warning fires where the bypass happens.** A `Raw[Str]` folded into a `Template[C]` is the un-parameterized interpolation, and that fold — and only that fold — raises `RawBypassesParam`:

```
warning[RawBypassesParam]: Raw() bypasses parameterization
 --> report.bl:3:35
  |
3 |     db.query_one(t"SELECT * FROM {Raw(table)} WHERE id = {id}")
  |                                   ^^^^^^^^^^ concatenated into the query text, not parameterized
  |
  = help: if `table` comes from user input, parameterize it instead: `{table}`
  = help: only if no parameterized form exists, record the review: add
          @trusted(audit: "AUDIT-ID") to the enclosing function; it needs a
          record `AUDIT-ID` in audits.toml
```

Neither help line is machine-applicable, and the second is never offered as a quick fix. The record holds the author's claim that the value cannot carry an injection; §9.1 *Audit Records* says what the record must hold and when its pin lapses.

The warning does **not** fire on an ordinary interpolated string, because an ordinary string contains no `Raw[Str]`. That is what making the marker a type buys: the trigger is the value's type, so it is neither defeated by binding the value to a variable first nor raised by a string that merely mentions the word.

`RawBypassesParam` is an **audit-gated** diagnostic: `@trusted(audit: K)` is its only suppression channel, and naming it in `@allow` or in `[lints]` is refused. The mechanism is stated once, for every diagnostic that uses it, in §9.1 *Audit-Gated Diagnostics*.

**A `Raw[Str]` in a position that does not consume it is an error.** Because `Raw[Str]` has no `Display`, a misplaced `Raw()` would otherwise fall through to `MissingDisplayImpl` (E0523), whose prescribed repairs — write an `impl`, call `.debug()` — are both impossible on a compiler-known marker type. It gets its own diagnostic instead, whose first repair compiles:

```blink
// intentional-error example
fn log_table(table: Str) ! IO {
    io.println("scanning {Raw(table)}")   // error[RawOutsideTemplate]: a `Raw[Str]` reached a
                                          //   position that does not consume it -- only a
                                          //   hole of a `t"..."` literal does
                                          // help: drop the wrapper: `"scanning {table}"`
}
```

**Why `Raw(expr)` instead of format specs or `Template.raw()`:**

- **Per-interpolation granularity.** Unlike a whole-string `raw()` which disables parameterization entirely, `Raw()` affects only the wrapped expression. Mixed safe/unsafe queries work naturally.
- **No string grammar extension.** `Raw(expr)` is just an expression inside `{...}` — zero new parser productions. No `:modifier` syntax that invites format specs (`:.2f`, `:>20`).
- **Type-system native.** Consistent with Blink's "types are the mechanism" philosophy. `Raw[Str]` is a compiler-known type like `Option[T]` or `Result[T,E]`.
- **Proven pattern.** Django's `mark_safe()`, Rails' `raw()`, Jinja2's `Markup()` — the industry consensus is to mark the VALUE, not the template slot.

#### Phantom Type Extensibility

The phantom type `C` in `Template[C]` enables the same mechanism for other injection contexts:

```blink
// Shell injection protection (future)
fn shell(cmd: Template[Shell]) -> Result[Output, ShellError]
process.shell(t"ls -la {path}")  // path is decomposed, handler quotes/escapes

// HTML/XSS protection (future)
fn render(template: Template[HTML]) -> SafeHtml
html.render(t"<div>{user_content}</div>")  // handler entity-escapes

// LDAP injection protection (future)
fn search(filter: Template[LDAP]) -> Result[List[Entry], LDAPError]
```

Each context defines its own reassembly strategy. The developer writes the same template literal everywhere — the parameter type ensures safety, and the handler decides how to make it safe.

#### Design Rationale

**Why not taint tracking:** Full information flow tracking (Section 9.3) requires tracking provenance on every value through inference, generics, and closures. `Template[C]` with `Raw[Str]` achieves 95% of the safety at the type boundary with minimal type system extension — two compiler-known types that enable per-interpolation safety control.

**Why a `t` prefix, and not a tag for each context:** `t` is a prefix on the one delimiter, as `#` is (§2.4.2). It adds no delimiter, so the "one string syntax" decision (§2.2) holds. A tag for each context, such as `sql"..."` or `html"..."`, would repeat what the phantom type `C` already says, and each new context would need a new tag. The `t` says only "keep the holes apart", and the type says where the template can go. An earlier rule had no prefix: a plain literal became a template when the site expected `Template[C]`. That rule was an implicit conversion, which Blink rejects elsewhere, and it worked only for a literal written directly as an argument. With `t`, a template is an ordinary expression that you can bind, return and pass, and the literal alone shows whether a hole is a value or text. A forgotten `t` is a compile error with a one-character fix (E0310). Python 3.14 uses the same spelling, `t"..."`, for the same meaning. (Panel vote: 6-0. See [Template literal prefix rationale](../decisions/template-literal-prefix.md).)

**Why phantom types:** `Template[DB]` and `Template[Shell]` are distinct types. You cannot pass a `Template[Shell]` to a function expecting `Template[DB]`. The phantom parameter prevents cross-context confusion at compile time.

**Why decomposed structure (not compiler-rewritten `$1/$2`):** Parameterization syntax is database-specific (PostgreSQL `$1`, MySQL `?`, Oracle `:name`). The compiler should decompose the interpolated string, not rewrite it. This follows the universal industry pattern: Python 3.14 `Template`, C# `FormattableString`, and JS tagged templates all have the language decompose and the library reassemble. User-authored effect handlers participate on equal footing with stdlib handlers.

**Why decomposed (not phantom-only):** Handlers need to read `parts()` and `values()` at runtime to reassemble the template with their dialect-specific syntax. A phantom over a plain string would leave handlers with an opaque string they cannot decompose.

**Why opaque (not a struct with fields):** A `values` field would need a type for "any interpolated value", and Blink has no surface top type (§3.4 *Under-Determined Types*). The closed `TemplateValue` enum is the type instead: it keeps each value's kind, so an `Int` reaches the driver as an integer, and a handler's `match` over it is exhaustive. Public fields would also let code build a template without a template literal, which is the one construction path the injection rule depends on.

**Why a `Bytes` variant:** A `Str` must be valid UTF-8 and a `Bytes` need not be, so no existing variant carries a binary value without loss. Database drivers bind a BLOB as its own kind (`sqlite3_bind_blob`, libpq binary parameters). Without the variant, the repair users find, `{b.to_hex()}`, compiles and stores text in a BLOB column. A context with no use for bytes, such as Shell or HTML, rejects them in a named arm.

**When a variant is admitted:** The enum is closed by a rule, not by habit. A new kind becomes a variant only if (a) a value of that kind has no lossless map into an existing variant, and (b) a driver we ship binds it as its own kind. A kind that fails (a), such as a timestamp that a driver sends as an integer or as text, stays a conversion at the hole. Each later vote on a variant applies this test. (Panel vote: 6-0. See [TemplateValue Bytes rationale](../decisions/template-value-bytes.md).)

**Cross-language precedent:**

| Language | Type | Decomposition | Reassembly |
|----------|------|---------------|------------|
| Python 3.14 | `Template` (`t"..."`) | `.args` alternating `(str, Interpolation)` | Handler walks args |
| C# | `FormattableString` | `.Format` + `.GetArguments()` | Handler reads format + args |
| JavaScript | Tagged template | `strings[]` + `values[]` | Tag function zips them |
| **Blink** | **`Template[C]` (`t"..."`)** | **`parts()` + `values()`** | **Handler matches `TemplateValue`** |
