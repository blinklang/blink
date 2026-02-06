## 3. Type System

### 3.1 Overview

Pact's type system exists to serve a single goal: **make incorrect programs unrepresentable**. Not aspirationally, not eventually -- at compile time, before a single byte of machine code is emitted.

The foundation is Hindley-Milner type inference extended with algebraic data types, traits, and targeted verification features. This is not a novel combination. ML, Haskell, Rust, and OCaml have proven these ideas over decades. What Pact adds is a pragmatic verification layer -- refinement types and contracts backed by an SMT solver -- that captures the 90% of dependent-type value that matters in practice, without the 90% of dependent-type complexity that makes languages unusable.

**Design philosophy:**

1. **Types are documentation the compiler enforces.** A function signature in Pact tells you its inputs, outputs, effects, failure modes, and value constraints. An AI agent (or a human) can understand a function's contract from its signature alone, without reading the body. This is locality of reasoning applied to types.

2. **Prove, don't test.** Testing checks examples. Types check universals. A test says "this worked for these 5 inputs." A type says "this works for all inputs, forever." The type system is the primary correctness mechanism; tests are the fallback for properties that can't be expressed as types.

3. **Progressive verification.** Not every function needs SMT-backed contracts. Simple functions get simple types. Critical functions get refinement types and contracts. The type system scales from "just annotate the signature" to "formally verify this precondition" without forcing the heavy machinery on code that doesn't need it.

4. **Inference is a token budget.** Every type annotation an AI writes costs tokens. Every annotation a human writes costs keystrokes. The inference engine should eliminate redundant annotations everywhere it can -- but never at function boundaries, where types serve as API documentation.

---

### 3.2 Built-in Types

```pact
// Numeric
Int             // 64-bit signed integer. The default. Use this.
I8, I16, I32    // Sized signed integers (when you actually need them)
U8, U16, U32, U64  // Unsigned integers
Float           // 64-bit IEEE 754 floating point

// Text
Str             // UTF-8 string, GC-managed
Char            // Unicode scalar value

// Logic
Bool            // true, false

// Unit
()              // The unit type. One value. No information.

// Collections
List[T]         // Growable ordered sequence
[T]             // Shorthand -- [Str] is List[Str]
Map[K, V]       // Hash map
Set[T]          // Hash set

// Core ADTs (defined in stdlib, special compiler support)
Option[T]       // Some(value) | None
Result[T, E]    // Ok(value) | Err(error)
```

**Why short names.** `Str` not `String`. `Int` not `Integer`. `Bool` not `Boolean`. These are the most-written types in any codebase. Over thousands of occurrences, 3 characters vs 6 saves real token budget. All types are PascalCase -- no special casing rules, no distinction between "primitive" and "user-defined." `Str` and `UserProfile` follow the same convention.

**Why one default `Int`.** Rust's numeric type matrix (`i8`/`i16`/`i32`/`i64`/`u8`/.../`usize`/`isize`) is a decision tree that produces wrong answers. LLMs pick `i32` when they mean `i64`, `usize` when they mean `u64`, and `u32` for values that go negative. Pact has `Int`. It's 64-bit. It's signed. It handles every integer you'll encounter in application code. The sized variants (`I8`, `U16`, etc.) exist for interop, binary protocols, and performance-critical paths where you've measured and know you need them.

**Why `Float` not `F32`/`F64`.** Same reasoning. 64-bit is correct for virtually all floating-point work. If you need 32-bit floats (GPU interop, large arrays where memory matters), that's a future extension, not a v1 concern.

**Why `[T]` sugar for `List[T]`.** Lists are the most common generic type. `[Str]` is 5 characters. `List[Str]` is 9. The sugar is unambiguous (square brackets in type position always mean List) and saves tokens in signatures that use lists heavily. Both forms are valid; the canonical formatter normalizes to whichever the project chooses.

**Why `Option` and `Result` are built-in.** These aren't library types bolted on after the fact. The compiler understands them: `T?` desugars to `Option[T]`, the `?` operator desugars to a match on `Result`, `??` desugars to a match on `Option`. Special syntax demands special compiler support.

---

### 3.3 Type Inference

Pact uses Hindley-Milner type inference with the following rule: **annotations are required on function signatures, inferred everywhere else.**

```pact
// Function signatures: fully annotated
fn add(a: Int, b: Int) -> Int {
    a + b
}

fn find_user(id: Int) -> Option[User] ! DB {
    db.query_one("SELECT * FROM users WHERE id = {id}")
}

// Everything inside a function body: inferred
let x = 42                        // Int
let name = "Alice"                // Str
let names = ["Alice", "Bob"]      // List[Str]
let result = add(1, 2)            // Int
let maybe = names.get(0)          // Option[Str]
let doubled = names.map(fn(n) {   // List[Str]
    "{n}{n}"
})
```

**Why require annotations at function boundaries.** A function signature is a contract. It tells callers what to provide and what to expect. If the signature is inferred from the body, understanding the contract requires reading the implementation -- the exact opposite of locality of reasoning. An AI agent browsing an API surface gets complete type information from signatures alone. A human reviewing a PR reads signatures to understand the change. Inference at the boundary would save a few tokens per function at the cost of making every function opaque.

**Why infer everything else.** Inside a function body, types are implementation detail. `let x: Int = 42` carries no information that the compiler doesn't already know from `42`. Every redundant annotation is a token the AI had to generate and the human has to read. Inference reclaims those tokens for code that matters.

**Bidirectional inference.** Type information flows both forward (from definitions to uses) and backward (from uses to definitions). This handles common patterns without annotation:

```pact
// Forward: type of map's output inferred from closure body
let lengths = names.map(fn(n) { n.len() })   // List[Int]

// Backward: closure param type inferred from map's expected input
let upper = names.map(fn(n) { n.to_upper() }) // n is Str, inferred from List[Str]
```

**Keyword labels are not part of the type.** Declaration-site keyword parameters (see [2.11](02_syntax.md#211-declaration-site-keyword-arguments)) use `--` to separate positional from keyword params, but labels are call-site enforcement only. The function type ignores labels entirely:

```pact
// This function:
fn transfer(amount: Int, -- from: Account, to: Account) -> Result[Transaction, BankError]

// Has type: fn(Int, Account, Account) -> Result[Transaction, BankError]
// The -- and labels are invisible to the type system
```

This means closures, trait implementations, and higher-order functions work without label awareness:

```pact
// A closure assigned to a variable with compatible type
let f: fn(Int, Account, Account) -> Result[Transaction, BankError] = transfer

// Passing as a higher-order function argument
fn apply(op: fn(Int, Account, Account) -> Result[Transaction, BankError]) { ... }
apply(transfer)  // works — labels are erased at the type level
```

Direct call sites enforce labels (the compiler errors if you call `transfer` without `from:` and `to:`). But when a function is passed as a value, labels are erased. This keeps the type system simple — 99% of same-typed-param bugs occur at direct call sites, where labels are enforced.

**Numeric literals.** Unadorned integer literals default to `Int`. Unadorned float literals default to `Float`. If context demands a specific size (e.g., assigning to a `U8` field), the literal is checked against the target type's range at compile time:

```pact
let port: U16 = 8080        // OK: 8080 fits in U16
let bad: U8 = 300           // COMPILE ERROR: 300 exceeds U8 range (0..255)
```

---

### 3.4 Algebraic Data Types

Pact uses a single `type` keyword for all user-defined types. The compiler distinguishes sum types (variants) from product types (fields) by structure, not by separate keywords.

#### Product Types (Structs)

A type with only named fields is a product type:

```pact
type User {
    name: Str
    email: Str
    age: Int
}

// Construction
let user = User { name: "Alice", email: "alice@example.com", age: 30 }

// Field access
let name = user.name
```

#### Sum Types (Enums)

A type with variants is a sum type. Variants can carry data or be unit-like:

```pact
type Color {
    Red
    Green
    Blue
    Custom(r: U8, g: U8, b: U8)
}

type Shape {
    Circle(radius: Float)
    Rectangle(width: Float, height: Float)
    Point
}
```

#### Why One Keyword

Most languages split these: `struct` + `enum` (Rust), `data class` + `sealed class` (Kotlin), `type` + `datatype` (SML). Two keywords means two mental models, two sets of rules, and an AI that has to decide which one to use.

In Pact, `type` is `type`. If it has variants, it's a sum. If it has fields, it's a product. If it has variants where some carry fields, it's a sum of products. The compiler doesn't care about the taxonomy; it cares about the structure.

#### Generic Types

Type parameters use square brackets:

```pact
type Pair[A, B] {
    first: A
    second: B
}

type Tree[T] {
    Leaf(value: T)
    Branch(left: Tree[T], right: Tree[T])
}

type Either[L, R] {
    Left(L)
    Right(R)
}
```

Type parameters are inferred at construction sites when possible:

```pact
let pair = Pair { first: "hello", second: 42 }  // Pair[Str, Int]
let tree = Branch(Leaf(1), Leaf(2))              // Tree[Int]
```

#### Recursive Types

Types can reference themselves. The compiler handles the indirection:

```pact
type JsonValue {
    Null
    Boolean(Bool)
    Number(Float)
    Str(Str)
    Array(List[JsonValue])
    Object(Map[Str, JsonValue])
}
```

---

### 3.5 Exhaustive Pattern Matching

Every `match` must cover all possible variants. The compiler rejects non-exhaustive matches at compile time.

```pact
fn area(shape: Shape) -> Float {
    match shape {
        Circle(r) => 3.14159 * r * r
        Rectangle(w, h) => w * h
        Point => 0.0
    }
}
```

Add a variant to `Shape` and every match that doesn't handle it becomes a compile error:

```
error[E0004]: non-exhaustive match
 --> geometry.pact:15:5
  |
15|     match shape {
  |     ^^^^^ missing pattern: `Triangle`
  |
  = fix: add arm `Triangle(base, height) => <expr>`
```

**Nested patterns:**

```pact
fn describe(val: JsonValue) -> Str {
    match val {
        Null => "null"
        Boolean(true) => "yes"
        Boolean(false) => "no"
        Number(n) => "number: {n}"
        Str(s) => "string: {s}"
        Array(items) => "array of {items.len()}"
        Object(map) => "object with {map.len()} keys"
    }
}
```

**Guard clauses:**

```pact
fn classify(n: Int) -> Str {
    match n {
        0 => "zero"
        n if n > 0 => "positive"
        _ => "negative"
    }
}
```

**Destructuring in `let`:**

```pact
let User { name, email, .. } = get_current_user()
let (first, second) = split_pair(data)
```

**Why exhaustiveness matters for AI.** The single most common bug AI-generated code produces is the forgotten case. A missing `None` handler, an unhandled error variant, an enum value added without updating all consumers. Exhaustive matching makes this class of bug structurally impossible. The compiler mechanically identifies what's missing and suggests the fix. An AI agent can apply the fix automatically -- this is the generate-compile-fix loop working as designed.

---

### 3.6 Traits

Traits define shared behavior. They are the sole polymorphism mechanism in Pact. There is no inheritance, no subtyping, no implicit conversions.

#### Trait Declaration

```pact
trait Display {
    fn display(self) -> Str
}

trait Eq {
    fn eq(self, other: Self) -> Bool
    fn ne(self, other: Self) -> Bool {
        !self.eq(other)
    }
}

trait Hash: Eq {
    fn hash(self) -> U64
}

trait Ord: Eq {
    fn cmp(self, other: Self) -> Ordering
}
```

Traits can have default method implementations (`ne` above). Traits can require other traits (`Hash: Eq` means implementing `Hash` requires implementing `Eq`).

#### Trait Implementation

```pact
impl Display for Color {
    fn display(self) -> Str {
        match self {
            Red => "Red"
            Green => "Green"
            Blue => "Blue"
            Custom(r, g, b) => "rgb({r}, {g}, {b})"
        }
    }
}

impl Eq for Color {
    fn eq(self, other: Color) -> Bool {
        match (self, other) {
            (Red, Red) => true
            (Green, Green) => true
            (Blue, Blue) => true
            (Custom(r1, g1, b1), Custom(r2, g2, b2)) =>
                r1 == r2 && g1 == g2 && b1 == b2
            _ => false
        }
    }
}
```

#### Trait Bounds

Generics are constrained by trait bounds:

```pact
fn max[T: Ord](a: T, b: T) -> T {
    match a.cmp(b) {
        Greater => a
        _ => b
    }
}

fn print_all[T: Display](items: List[T]) ! IO {
    for item in items {
        io.println(item.display())
    }
}

// Multiple bounds
fn dedup[T: Eq + Hash](items: List[T]) -> List[T] {
    let mut seen = Set.new()
    items.filter(fn(item) {
        seen.insert(item)
    })
}
```

#### Why Traits Over Inheritance

Inheritance creates vertical hierarchies. Understanding a method call requires traversing the class tree upward through potentially dozens of files. This is anti-locality at its worst -- a single method dispatch can depend on code scattered across an entire codebase.

Traits are horizontal. Each `impl` block is self-contained. To understand what `Display` does for `Color`, you read one block. No parent classes, no `super` calls, no method resolution order, no fragile base class problem, no diamond inheritance.

For AI, this is critical. An AI generating a trait impl needs context from two places: the trait declaration and the type definition. Not the entire class hierarchy. Two files, not fifteen.

Traits also support retroactive implementation -- you can implement a trait for a type you didn't define (subject to coherence rules). This enables extending types with new behavior without modifying their source, which is impossible with class inheritance.

---

#### Compiler-Known Traits

Certain traits have special meaning to the compiler. They are defined in the standard library but the compiler understands their semantics and can generate or enforce behavior based on them.

| Trait | Compiler behavior |
|-------|------------------|
| `Eq` | Enables `==` and `!=` operators. `@derive(Eq)` auto-generates structural equality. |
| `Ord` | Enables `<`, `>`, `<=`, `>=` and `cmp`. Requires `Eq`. |
| `Hash` | Enables use as `Map` key or `Set` element. Requires `Eq`. |
| `Display` | Enables string interpolation (`"{value}"`). |
| `Closeable` | Signals non-memory resources needing deterministic cleanup. Enables `with...as` scoped resource blocks. |

The `Closeable` trait is the simplest:

```pact
trait Closeable {
    fn close(self)
}
```

A type implementing `Closeable` holds resources (file handles, sockets, locks, database cursors) that must be released deterministically — not when the GC gets around to it, but at a specific point in the program. The `with...as` construct (section 2.15, section 5.5) guarantees `close()` is called on all exit paths.

```pact
type FileHandle {
    fd: Int
    path: Str
}

impl Closeable for FileHandle {
    fn close(self) ! FS {
        fs.close_fd(self.fd)
    }
}
```

The compiler uses `Closeable` to power lint W0600 (warn when a `Closeable` value is used outside a `with...as` block) and errors E0601/E0602 (closeable escapes scope). See section 5.5 for the full mechanism.

---

### 3.7 No Null, No Exceptions

These are not restrictions. They are the elimination of two categories of bugs that account for more production incidents than any other.

#### No Null

There is no `null`, `nil`, `None`-as-implicit-value, or bottom type that inhabits every type. A `Str` is always a string. An `Int` is always an integer. If a value might be absent, the type says so:

```pact
// This function might not find a user. The type says so.
fn find_user(id: Int) -> Option[User] ! DB {
    db.query_one("SELECT * FROM users WHERE id = {id}")
}

// The caller MUST handle the absence. The compiler enforces this.
let user = find_user(42)
// user is Option[User] -- you cannot call .name on it directly

// Option 1: Default value with ??
let name = find_user(42)?.name ?? "Unknown"

// Option 2: Pattern match
match find_user(42) {
    Some(u) => io.println("Found: {u.name}")
    None => io.println("User not found")
}

// Option 3: Early return with ?
fn get_user_name(id: Int) -> Option[Str] ! DB {
    let user = find_user(id)?   // returns None if not found
    Some(user.name)
}
```

The `T?` sugar makes optional types concise in signatures:

```pact
fn find_user(id: Int) -> User? ! DB      // same as Option[User]
fn get_config(key: Str) -> Str?           // same as Option[Str]
```

#### No Exceptions

There is no `throw`, no `try/catch`, no unchecked exceptions, no exception hierarchy. Operations that can fail return `Result[T, E]`:

```pact
fn parse_port(s: Str) -> Result[Int, ParseError] {
    let n = parse_int(s)?
    if n < 1 || n > 65535 {
        Err(ParseError { message: "port out of range: {n}" })
    } else {
        Ok(n)
    }
}

fn read_config(path: Str) -> Result[Config, ConfigError] ! IO {
    let text = io.read_file(path)?             // IOError -> ConfigError
    let parsed = parse_toml(text)?             // ParseError -> ConfigError
    validate_config(parsed)?                    // ValidationError -> ConfigError
    Ok(parsed)
}
```

The `?` operator is the error propagation mechanism. It unwraps `Ok` or returns early with `Err`. Every error path is visible in the return type. Every propagation point is visible in the body (the `?` character). There is no invisible control flow.

#### Why This Is Right for an AI-First Language

**Null**: AI models produce null-related bugs at a rate proportional to how easy the language makes it to forget null checks. In languages with null, every reference is implicitly `T | null`, and every dereference is an implicit null check that the programmer (or AI) might forget. In Pact, if a value can be absent, the type says `Option[T]`, and the compiler refuses to let you use it as a `T` without handling the `None` case. The bug category is structurally eliminated.

**Exceptions**: Exceptions create invisible control flow. A function signature says `fn process(data: Str) -> Report`, but the function might throw `IOException`, `ParseException`, `ValidationException`, or anything its callees throw. The signature lies. An AI reading the signature gets incomplete information. In Pact, the same function says `fn process(data: Str) -> Result[Report, ProcessError] ! IO` -- complete, honest, compiler-checked.

The `?` operator is one character with unambiguous semantics. Compare to try/catch blocks where AI commonly generates: wrong catch order, overly broad catches (`catch (Exception e)`), missing finally clauses, and incorrect resource cleanup. The `?` operator has one behavior. There's nothing to get wrong.

---

### 3.8 Refinement Types

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

### 3.9 Contracts

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

### 3.10 Contract Composition and Modular Verification

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

### 3.11 Verification Outcomes

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
