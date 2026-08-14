## 3c. Protocols & Conversions

### 3c.1 Iterator Protocol

`for x in collection { }` is Blink's primary iteration construct. It requires a formal protocol: two compiler-known traits that define what "iterable" means and how iteration proceeds.

#### Two Iteration Worlds: Eager Collections, Lazy Iterators

Blink has two distinct worlds, and one door between them.

- A **collection** (`List`, `Set`, `Map`, `Range`, `Str`) is a value you already hold. Its adapter methods are **eager**: `list.map(f)` walks the list now and returns a new `List`. A collection method takes a collection and answers a collection.
- An **`Iterator[T]`** is a lazy, single-pass *recipe* for producing elements on demand. Its adapter methods are **lazy**: they build a pipeline description and touch no elements until something consumes them. An iterator method takes an iterator and answers an iterator.

The one rule that governs both worlds:

> **Collection method in, collection out. Iterator method in, iterator out. `.into_iter()` is the door.**

`.into_iter()` crosses from a collection into the lazy world; `.collect()` crosses back. There is no implicit conversion in either direction (§3c.2 — Blink has no implicit conversions), so the boundary is always visible in source.

```blink
let names = ["Alice", "Bob", "Carol"]

let shouted = names.map(fn(n) { n.to_upper() })   // eager — shouted : List[Str]

let first_two = names
    .into_iter()                       // cross into the lazy world
    .filter(fn(n) { n.len() > 3 })
    .take(2)
    .collect()                    // cross back — first_two : List[Str]
```

**Why eager collection adapters.** A `List` is data you already have in memory; mapping over it should give you data you already have. Every mainstream ecosystem that a working programmer knows — JavaScript `Array.map`, Python list comprehensions, Kotlin `List.map`, Java requiring an explicit `.stream()` first — landed on *eager on the collection, lazy opt-in on a separate carrier*. Making `list.map` lazy imports the single most-asked lazy-evaluation footgun: a side-effecting map that is never consumed silently does nothing, with no diagnostic — which contradicts Blink's stance that under-determined behavior is a hard error, not a silent guess (§3.4 *Under-Determined Types*, `E0301`). Eager keeps evaluation order equal to source order. (Vote: 5-0, Minimalism dissented — see below.)

**Why not one uniform rule.** Making *all* adapters lazy is one rule instead of two, and the Minimalism panelist held that line: `list.map(f).filter(g).sum()` under eager evaluation allocates intermediate lists that a uniform-lazy pipeline would not. The trade the majority accepted: the two-worlds cost is a *type mismatch on a named type* — `expected List[Int], found Iterator[Int]`, fixed by adding `.collect()` or dropping `.into_iter()` — which is loud, greppable, and self-correcting, whereas the uniform-lazy cost is a *silent no-op* that produces a wrong program with a green build. A benign, frequent, self-correcting error beats a fatal, frequent, silent one. Blink also has effect rows: an eager adapter chain whose closures are pure is provably deforestable, so the intermediate lists are a *permitted* optimization target, not a permanent tax. (Minimalism dissent recorded: [Iterator Protocol rationale](../decisions/iterator-protocol.md).)

#### `Iterator[T]` — a Sealed, Lazy Carrier

`Iterator[T]` is a **built-in, sealed, opaque type**, not a user-implementable trait. Its representation is unspecified: it holds a source plus a chain of adapters, and the compiler chooses the layout. Users cannot write `impl Iterator[Int] for Foo` — the type is closed, exactly as `Str` and `List` are closed. Its adapter surface is a sealed set of built-in methods (dispatched like `StrOps`/`ListOps`, §3c.4), which no user program may extend or override.

An iterator is a **restartable recipe, not a stateful cursor.** This is forced by Blink's value semantics: values are copied on bind (§3.6, there is no `&mut self`), and there is no linearity checker to forbid aliasing. If an iterator were a mutable cursor, `let b = a` would give two handles to one advancing position, and advancing `b` would observably advance `a` — mutable state aliased through a value type, which the language forbids everywhere else. Modeling the carrier as a persistent recipe — conceptually `Unit -> Option[(T, Iterator[T])]`, the same shape as OCaml's `Seq.t` — removes the hazard: each node is re-entered, never mutated in place, so copying is free and re-traversal recomputes rather than resumes.

```blink
let evens = (0..10).into_iter().filter(fn(n) { n % 2 == 0 })
let a = evens.collect()   // [0, 2, 4, 6, 8]
let b = evens.collect()   // [0, 2, 4, 6, 8] — re-traversal recomputes; `a` is unaffected
```

The one exception is an iterator built from a mutable closure (`iter.from_fn`, below): its re-traversal behaviour is **unspecified** — it may resume rather than restart. Iterators derived from a collection via `.into_iter()` are always restartable.

#### Lazy Adapter Methods

The adapter methods on `Iterator[T]` are lazy: each returns a new iterator and touches no elements until a consuming method or a `for` loop pulls from the end. They are compiler-provided; the bodies are internal (the carrier layout is unspecified), so only signatures are shown.

```blink
// Transforming
fn map[U](self, f: fn(T) -> U) -> Iterator[U]
fn filter(self, predicate: fn(T) -> Bool) -> Iterator[T]
fn flat_map[U](self, f: fn(T) -> Iterator[U]) -> Iterator[U]

// Slicing
fn take(self, n: Int) -> Iterator[T]
fn skip(self, n: Int) -> Iterator[T]

// Combining
fn zip[U](self, other: Iterator[U]) -> Iterator[(T, U)]
fn enumerate(self) -> Iterator[(Int, T)]
fn chain(self, other: Iterator[T]) -> Iterator[T]

// Consuming (these drain the iterator)
fn collect(self) -> List[T]
fn fold[U](self, init: U, f: fn(U, T) -> U) -> U
fn count(self) -> Int
fn any(self, predicate: fn(T) -> Bool) -> Bool
fn all(self, predicate: fn(T) -> Bool) -> Bool
fn find(self, predicate: fn(T) -> Bool) -> Option[T]
fn for_each(self, f: fn(T))
```

`zip` and `enumerate` answer **tuples** — `Iterator[(T, U)]` and `Iterator[(Int, T)]` — never `List[List[...]]`, which would erase the element types (there is no type that is "`Int` or `T`"). (Vote: 6-0.)

**Lazy means no work until consumed.** `.map(f).filter(p)` builds a pipeline description — zero elements are processed. Elements flow through one at a time when a consuming method (`collect`, `fold`, `count`, `for_each`, `any`, `all`, `find`) or a `for` loop pulls from the end.

```blink
// No intermediate List allocated — elements flow one at a time
let result = names
    .into_iter()
    .filter(fn(n) { n.len() > 3 })
    .map(fn(n) { n.to_upper() })
    .take(5)
    .collect()   // materialization point
```

**Why lazy in the iterator world.** Chaining `.map().filter().take(5)` on a million-element source would, under eager evaluation, process all million elements only to discard all but 5. Lazy evaluation processes only what is needed — if `.take(5)` is satisfied after examining 20 elements, the remaining 999,980 are never touched. Laziness is the whole point of crossing into the iterator world with `.into_iter()`; the collection world stays eager. (Vote: 5-0.)

#### `for` Loop Desugaring and `IntoIterator`

`for` iterates anything that produces an `Iterator`. The bridge is the compiler-known `IntoIterator` trait, whose one method `into_iter` is the crossing door — **the same call `.into_iter()` you write by hand** to move from a collection into the lazy world. There is one name for the crossing:

```blink
trait IntoIterator[T] {
    fn into_iter(self) -> Iterator[T]
}
```

The compiler desugars `for x in expr { body }` into:

```blink
let mut __iter = expr.into_iter()
loop {
    match __iter.next() {   // next() is the carrier's internal pull; not a public method
        Some(x) => { body }
        None => break
    }
}
```

`break` exits the loop; `continue` skips to the next internal pull. `expr.into_iter()` produces a fresh iterator each time, so two `for` loops over the same collection do not interfere:

```blink
let names = ["Alice", "Bob", "Carol"]
for n in names { io.println(n) }   // first pass — fresh iterator
for n in names { io.println(n) }   // second pass — new fresh iterator
```

Writing `.into_iter()` explicitly (the door of §3c.1) and letting `for` desugar to it are the same operation — `for n in names` and `for n in names.into_iter()` are equivalent, because `names.into_iter()` already yields an `Iterator[T]` and `Iterator`'s own `into_iter()` is the identity.

**`IntoIterator` is sealed in v1.** Only the built-in collections (and `Iterator` itself, reflexively) implement it. A user type cannot yet implement `IntoIterator` directly — that extension point is deferred to v2 (see below). The built-in implementations:

| Type | `into_iter()` yields | Notes |
|------|---------------------|-------|
| `List[T]` | `T` | Elements in order |
| `Set[T]` | `T` | Unspecified order |
| `Map[K, V]` | `(K, V)` | Key-value pairs, unspecified order |
| `Range[T]` | `T` | Lazy; `0..1000000` allocates nothing |
| `Str` | `Char` | Unicode scalar values |
| `Iterator[T]` | `T` | Identity (returns self) |

#### Custom Iteration: `iter.from_fn`

Because `Iterator` is sealed, a custom source does not implement a trait — it *constructs* an iterator with the free function `iter.from_fn`, which wraps a closure that yields `Some(value)` per element and `None` at the end. The closure holds its state in ordinary `mut` captures, the same way every other closure in the language does:

```blink
fn fibonacci() -> Iterator[Int] {
    let mut a = 0
    let mut b = 1
    iter.from_fn(fn() {
        let v = a
        a = b
        b = v + b
        Some(v)
    })
}

let fibs = fibonacci()
    .take(10)
    .collect()   // [0, 1, 1, 2, 3, 5, 8, 13, 21, 34]

let sum_of_even_fibs = fibonacci()
    .filter(fn(n) { n % 2 == 0 })
    .take(5)
    .fold(0, fn(acc, n) { acc + n })
```

`iter.unfold(init, step)` is the same idea with the state passed explicitly rather than captured: `step` takes the current state and returns `Some((element, next_state))` or `None`.

An iterator built by `from_fn` is **one-shot**: its captured state advances as it is consumed, so re-traversing it is unspecified. This is the deliberate exception to the restartable-recipe rule above — collection-derived iterators restart, `from_fn` iterators may not.

**To make your own type iterable in v1**, expose a method that returns an iterator, and iterate that:

```blink
trait Walkable {
    fn walk(self) -> Iterator[Int]
}

impl Walkable for Tree {
    fn walk(self) -> Iterator[Int] {
        // ... build and return an iterator over the tree, e.g. via iter.from_fn
    }
}

for x in my_tree.walk() { io.println("{x}") }
```

`walk` is a plain user method that returns an `Iterator[T]`; the `for` loop then drives that carrier directly. This is one visible method call, not a materializing `.to_list()`. Because `IntoIterator` is sealed in v1, `walk` cannot be named `into_iter` and made implicit — writing `for x in my_tree` directly is the v2 extension below.

#### Sealed in v1, User `IntoIterator` Deferred to v2

Both `Iterator` and `IntoIterator` are **sealed** in v1: users construct iterators with `iter.from_fn`, but cannot implement either trait for their own types. The panel chose to stage the open extension point rather than ship it now (Vote: Phase B 3-3 → Phase D **4-2** for staging; DevOps and Minimalism dissented, wanting `IntoIterator` opened in v1).

The reasoning: unsealing is a *monotone*, non-breaking change — v2 can open `IntoIterator` to user types without invalidating a single v1 program — whereas shipping an open protocol whose central invariant (carrier persistence) cannot yet be stated in the type system is not reversible. v1's real `from_fn` usage becomes the evidence that shapes v2's open-world design, including the diagnostics and completion the open trait will need. In v2, `for x in my_tree` (no `.into_iter()`) becomes expressible by implementing `IntoIterator[T] for Tree` with `into_iter` returning the sealed carrier.

Only `IntoIterator` is the extension point that opens. `Iterator[T]` itself — the carrier type and its adapter surface — stays **sealed permanently**: a user type becomes iterable by *producing* an `Iterator` (via `into_iter`), never by *being* one. This keeps the carrier's layout and its persistence invariant fully under compiler control for all versions.

#### Effectful Iteration: Deferred to v2

The v1 iterator is **pure** — an adapter closure that performs effects is a v1 error, and `Iterator[T]` carries exactly one user-visible type parameter, now and permanently. This means `for line in file.lines() ! IO` is not expressible through the iterator protocol in v1.

The effect row is **reserved** rather than surfaced: it lives only in the carrier's internal representation (the monomorphization key, §4.15.3), never in v1 surface syntax or diagnostics. Because `Iterator[T]` stays a one-parameter type and the row rides the internal mono key, v2 can widen the family to effectful iteration as a **conservative extension** — every v1 program keeps its exact typing — instead of a breaking change that would rewrite the effect signature of every function that touches an iterator. (The PLT panelist argued for threading a live effect-row variable through the v1 checker immediately; the panel reserved the design without building the checker plumbing yet.)

**Workaround for v1:** Use explicit loops with effect-performing calls:

```blink
fn process_lines(path: Str) -> Result[(), AppError] ! FS.Read, IO.Log {
    with fs.open(path)? as file {
        loop {
            match fs.read_line(file) {
                Some(line) => io.log("Line: {line}")
                None => break
            }
        }
    }
}
```

**Why defer.** Effectful iterators interact with lazy evaluation in subtle ways: when does the effect fire? Does `.map()` over an effectful iterator inherit the effect? How does effect polymorphism compose with iterator type parameters? The effect system is powerful but young. Shipping pure iterators now and designing effectful iteration once real Blink codebases reveal the right patterns avoids baking in a wrong abstraction. (Vote: 3-2, Systems and PLT dissented wanting effects in v1.)

#### Pipe Operator Interaction

The `|>` pipe operator chains naturally with iterator methods:

```blink
let result = data
    |> fn(d) { d.into_iter() }
    |> fn(i) { i.filter(fn(x) { x > 0 }) }
    |> fn(i) { i.map(fn(x) { x * 2 }) }
    |> fn(i) { i.collect() }

// But method chaining is usually cleaner for iterators:
let result = data.into_iter()
    .filter(fn(x) { x > 0 })
    .map(fn(x) { x * 2 })
    .collect()
```

Both forms are valid. Method chaining is idiomatic for iterator pipelines; `|>` is for composing standalone functions.

---

### 3c.2 Type Conversions: From, Into, TryFrom

Blink has no implicit conversions. Every type conversion is explicit, visible in source, and compiler-checked. Three compiler-known traits provide the conversion protocol.

#### The `From` Trait

```blink
trait From[T] {
    fn from(value: T) -> Self
}
```

`From[T]` is the single canonical conversion trait. To convert a value of type `T` into type `U`, implement `From[T] for U`. The conversion is infallible — it always succeeds.

```blink
type ConfigError {
    IO(IOError)
    Parse(ParseError)
    Validation(ValidationError)
}

impl From[IOError] for ConfigError {
    fn from(e: IOError) -> ConfigError { ConfigError.IO(e) }
}

impl From[ParseError] for ConfigError {
    fn from(e: ParseError) -> ConfigError { ConfigError.Parse(e) }
}
```

Calling convention: `TargetType.from(value)`.

```blink
let err: ConfigError = ConfigError.from(io_error)
```

**Every type has a reflexive From impl:** `impl From[T] for T { fn from(value: T) -> T { value } }` is compiler-provided for all types.

#### The `Into` Trait (Auto-Derived, Never User-Implemented)

```blink
trait Into[T] {
    fn into(self) -> T
}
```

`Into[T]` is the mirror of `From[T]`, providing method-call syntax: `value.into()`. The compiler auto-derives `Into[U] for T` whenever `From[T] for U` exists. Users **never** implement `Into` directly — implementing `From` is the only way.

```blink
// These are equivalent:
let err: ConfigError = ConfigError.from(io_error)
let err: ConfigError = io_error.into()   // works because From[IOError] for ConfigError exists
```

**Why auto-derive only.** If users could implement `Into` directly, you could create incoherent pairs (`A: Into[B]` without `B: From[A]`), breaking the bidirectional guarantee. One source of truth: implement `From`, get `Into` for free. (Vote: 4-1, AI/ML dissented wanting no Into at all — but method-call syntax is important for chaining.)

#### The `TryFrom` Trait

```blink
type ConversionError {
    message: Str
    source_type: Str
    target_type: Str
}

trait TryFrom[T] {
    fn try_from(value: T) -> Result[Self, ConversionError]
}
```

`TryFrom[T]` is for fallible conversions — conversions that may fail at runtime. The error type is a fixed `ConversionError` struct carrying a human-readable message and the source/target type names.

```blink
let port = Port.try_from(user_input)?
let small: I8 = I8.try_from(big_number)?
```

**Why fixed `ConversionError`, not per-impl error types.** Blink has no associated types. A generic `TryFrom[T, E]` would be more precise but creates cascading boilerplate: every TryFrom impl needs a custom error type, every call site needs a From impl to propagate that error into the caller's error type. A fixed ConversionError keeps the diagnostic story simple and eliminates trait-impl boilerplate explosion. (Vote: 3-2, Systems/PLT dissented wanting generic `TryFrom[T, E]`.)

**Refinement type integration.** Refinement types (§3b.1) auto-generate `TryFrom` impls. `type Port = Int @where(self > 0 && self <= 65535)` generates:

```blink
impl TryFrom[Int] for Port {
    fn try_from(value: Int) -> Result[Port, ConversionError] {
        if value > 0 && value <= 65535 {
            Ok(value)  // value is now Port
        } else {
            Err(ConversionError {
                message: "value {value} does not satisfy: self > 0 && self <= 65535"
                source_type: "Int"
                target_type: "Port"
            })
        }
    }
}
```

#### Compiler-Known Conversion Traits

| Trait | Compiler behavior |
|-------|------------------|
| `From[T]` | Infallible conversion. User-implemented. Enables `Into` auto-derivation. |
| `Into[T]` | Auto-derived from `From`. Provides `.into()` method-call syntax. Never user-implemented. |
| `TryFrom[T]` | Fallible conversion returning `Result[Self, ConversionError]`. User-implemented. Auto-generated for refinement types. |

#### The `?` Operator and Error Types

The `?` operator is early-return sugar for unwrapping `Result[T, E]` and `Option[T]`. It is validated during the **type checking phase** — codegen never sees an invalid `?` usage. Four rules govern its behavior:

**Rule 1: Operand must be `Result[T, E]` or `Option[T]`.** Using `?` on any other type is a compile error (E0502).

**Rule 2: `?` on `Result[T, E]` requires the enclosing function to return `Result[U, E2]`.** The function's return type must be a `Result`. If not, it is a compile error (E0508). Desugaring:

```blink
// expr? where expr : Result[T, E] desugars to:
match expr {
    Ok(val) => val
    Err(e) => return Err(e)   // e must match the function's error type exactly
}
```

**Rule 3: `?` on `Option[T]` requires the enclosing function to return `Option[U]`.** The function's return type must be an `Option`. If not, it is a compile error (E0509). Desugaring:

```blink
// expr? where expr : Option[T] desugars to:
match expr {
    Some(val) => val
    None => return None
}
```

```blink
fn find_user_email(id: Int) -> Option[Str] ! DB {
    let user = db.find_user(id)?    // returns None if user not found
    let profile = db.get_profile(user.id)?  // returns None if no profile
    Some(profile.email)
}
```

**Rule 4: For `Result[T, E1]`, the error type must exactly match the function's `Result[U, E2]` — `E1 == E2`.** There is no automatic `.into()` call on the error variant. Mismatched error types produce E0512.

```blink
fn read_config(path: Str) -> Result[Config, ConfigError] ! IO {
    // COMPILE ERROR E0512: ? error type mismatch —
    //   inner type `IoError` does not match function return error type `ConfigError`
    let text = io.read_file(path)?

    // Fix: explicit conversion with .map_err()
    let text = io.read_file(path)
        .map_err(fn(e) { ConfigError.from(e) })?
    let parsed = toml.parse(text)
        .map_err(fn(e) { ConfigError.from(e) })?
    validate(parsed)
        .map_err(fn(e) { ConfigError.from(e) })?
    Ok(parsed)
}
```

**No cross-type `?`.** Using `?` on `Option[T]` in a function returning `Result[U, E]` — or vice versa — is a compile error. There is no implicit wrapping of `None` into `Err(NoneError)`. If you need to convert between Option and Result, use explicit methods:

```blink
fn load_user(id: Int) -> Result[User, AppError] ! DB {
    // Option → Result: use .ok_or() or match
    let user = db.find_user(id)
        .ok_or(AppError.NotFound("user {id}"))?
    Ok(user)
}
```

**Why no auto-conversion.** Blink explicitly rejected implicit conversions. Auto-calling `.into()` on `?` is implicit conversion — the error type changes without visible syntax at the call site. Explicit `.map_err()` makes every conversion visible, greppable, and unambiguous. Start strict, can relax later; can never tighten without breaking code. (Vote: 4-1, DevOps dissented wanting auto-conversion with strong diagnostics. Reaffirmed 5-0 during `?` operator validation deliberation.)

**Why both Result and Option.** `?` is fundamentally early-return sugar on the "failure" branch of a sum type. For `Result` that branch is `Err(e)`, for `Option` it is `None`. The same control flow pattern applies to both — forcing different syntax for structurally identical operations would be an arbitrary distinction. (Vote: 5-0.)

**Why type checking, not codegen.** `?` validation requires type information (is this a Result or Option? what are its type parameters?). Placing validation in the type checking phase ensures codegen only processes fully-validated programs, matching the phase gate architecture (§6.3). Invalid `?` usage that reaches codegen previously generated broken C output — the type checker eliminates this entire class of bugs. (Vote: 5-0.)

**`?` inside test bodies.** A `test "..." { body }` block has no written return type, but `?` is permitted inside its body. The compiler implicitly elaborates the body to `Result[Void, TestError]` whenever any `?` appears, and rewrites each `Err`/`None` arm to render via `Display[E]` into a sealed `TestError` carrier. `Display[E]` is required at every `?` site (E0514 if missing). The same elaboration rule applies in both `blink check` and `blink test`. See §2.20 *Error Propagation: `?` in Test Bodies* for the full lowering. Closures passed to ordinary higher-order functions (`for_each` and any user-callable HOF) do **not** inherit this elaboration and continue to obey Rules 2 and 3 against their own return types. The one exception is the property closure given as the **direct syntactic argument** of the `prop_check` intrinsic: it is a closed test-grammar surface (the runner is its sole caller, like the test body) and receives the same `Result[Void, TestError]` elaboration on its own account — see §2.20 *Property-Based Testing*. A `prop_check` argument bound to a `let` first is a value, not a closed surface, and obeys Rules 2/3 normally. (Vote: 6-0 implicit elaboration, 6-0 `TestError` carrier shape, 5-1 explicit reject of annotation form; `prop_check` direct-argument elaboration follow-up 6-0.)

---

### 3c.3 Numeric Conversions

Numeric types support both named conversion methods (for discoverability) and From/TryFrom impls (for generic programming). Named methods are sugar over the trait impls — one source of truth.

#### Widening Conversions (Infallible — `From`)

Widening conversions never lose information. They are implemented via `From` and also available as named methods.

| From | To | Method | Notes |
|------|----|--------|-------|
| `I8` | `I16`, `I32`, `Int` | `.to_i16()`, `.to_i32()`, `.to_int()` | Sign-extends |
| `I16` | `I32`, `Int` | `.to_i32()`, `.to_int()` | Sign-extends |
| `I32` | `Int` | `.to_int()` | Sign-extends |
| `U8` | `U16`, `U32`, `U64`, `I16`, `I32`, `Int` | `.to_u16()`, `.to_u32()`, `.to_u64()`, `.to_i16()`, `.to_i32()`, `.to_int()` | Zero-extends |
| `U16` | `U32`, `U64`, `I32`, `Int` | `.to_u32()`, `.to_u64()`, `.to_i32()`, `.to_int()` | Zero-extends |
| `U32` | `U64`, `Int` | `.to_u64()`, `.to_int()` | Zero-extends |
| `U64` | — | — | No infallible widening (would need U128 or Int is 64-bit signed) |
| `Int` | `Float` | `.to_float()` | Loses precision for \|n\| > 2^53 |
| `Float` | — | — | No infallible widening target |

```blink
// Via named method
let f = my_int.to_float()

// Via From trait (equivalent)
let f = Float.from(my_int)

// In generic code
fn widen[T: From[U8]](byte: U8) -> T { T.from(byte) }
```

**Int -> Float precision note.** `Int` (64-bit signed) to `Float` (64-bit IEEE 754) is classified as widening because no integer value causes a runtime failure. However, integers with absolute value greater than 2^53 lose precision. The compiler emits warning W0350 when a literal integer outside the exact-float range is converted:

```
warning[W0350]: lossy conversion
 --> math.bl:12:15
  |
12|     let f = (9007199254740993).to_float()
  |             ^^^^^^^^^^^^^^^^^^^^^^^^^^^ Int value exceeds Float's exact integer range (2^53)
  |
  = note: value will be rounded to nearest representable Float
```

#### Narrowing Conversions (Fallible — `TryFrom`)

Narrowing conversions may fail at runtime. They return `Result[T, ConversionError]`.

| From | To | Method | Fails when |
|------|----|--------|-----------|
| `Float` | `Int` | `.to_int_checked()` | NaN, Infinity, fractional part, out of Int range |
| `Float` | `I8`..`I32`, `U8`..`U64` | `.to_i8_checked()` etc. | Same + out of target range |
| `Int` | `I8`, `I16`, `I32` | `.to_i8_checked()` etc. | Value outside target range |
| `Int` | `U8`, `U16`, `U32`, `U64` | `.to_u8_checked()` etc. | Negative, or exceeds target max |
| `U64` | `Int` | `.to_int_checked()` | Value > Int max (2^63 - 1) |
| larger unsigned | smaller unsigned | `.to_u8_checked()` etc. | Exceeds target max |
| signed | unsigned (same/smaller) | `.to_u8_checked()` etc. | Negative |
| unsigned | signed (same width) | `.to_i8_checked()` etc. | Exceeds signed max |

```blink
// Via named method
let n = my_float.to_int_checked()?

// Via TryFrom trait (equivalent)
let n = Int.try_from(my_float)?

// Truncating (non-checked) — explicit intent
let n = my_float.truncate()  // rounds toward zero, panics on NaN/Inf
```

**Why both methods and trait impls.** Named methods (`.to_float()`, `.to_int_checked()`) are discoverable via LSP autocomplete — type `my_int.to_` and see available conversions. From/TryFrom impls enable generic conversion-bounded functions. Different use cases: methods for explicit call sites, traits for generic programming. (Vote: 4-1, AI/ML dissented wanting traits only.)

#### No Mixed-Type Arithmetic

Operands to arithmetic operators must be the same type. There is no implicit numeric promotion.

```blink
let x: Int = 42
let y: Float = 3.14
let z = x + y   // COMPILE ERROR: Int + Float not defined

// Fix: explicit conversion
let z = x.to_float() + y   // OK
```

This is unchanged from §2.19 and §3.6 — stated here for completeness.

#### Char Conversions

`Char` (Unicode scalar value) participates in the conversion system via `From`/`TryFrom` traits and named methods, following the same dual-API pattern as numeric types (§3c.3). `Char` is not a numeric type — it does not implement arithmetic traits — but its codepoint representation is an integer, so conversions between `Char` and `Int` are well-defined.

##### Char → Int (Infallible — `From`)

Every `Char` is a Unicode scalar value in the range 0x0000–0x10FFFF (excluding surrogates). This always fits in `Int` (i64), so the conversion is infallible.

| From | To | Method | Trait | Notes |
|------|----|--------|-------|-------|
| `Char` | `Int` | `.to_int()` | `From[Char] for Int` | Returns Unicode codepoint value |

```blink
let c = 'A'
let n = c.to_int()         // 65
let n = Int.from(c)        // 65 (equivalent, via From trait)

// In generic code
fn to_number[T: From[Char]](c: Char) -> T { T.from(c) }
```

**Note.** `.to_int()` returns the Unicode codepoint value, not an ASCII code. For ASCII characters the values coincide, but `'é'.to_int()` returns `233`, not an error. `Char` does not implement `Add`, `Sub`, or other arithmetic traits — use `.to_int()` to perform arithmetic on codepoint values, then convert back.

##### Int → Char (Fallible — `TryFrom`)

Not all integers are valid Unicode scalar values. Surrogate codepoints (0xD800–0xDFFF) and values above 0x10FFFF are rejected at runtime.

| From | To | Method | Trait | Fails when |
|------|----|--------|-------|-----------|
| `Int` | `Char` | `Char.from_code_point(n)` | `TryFrom[Int] for Char` | Surrogate (0xD800–0xDFFF) or > 0x10FFFF or negative |

```blink
let c = Char.from_code_point(65)?      // Ok('A')
let c = Char.from_code_point(0xD800)?  // Err(ConversionError)
let c = Char.from_code_point(-1)?      // Err(ConversionError)

// Via TryFrom trait (equivalent)
let c = Char.try_from(0x1F600)?        // Ok('😀')

// Round-trip
let n = 'Z'.to_int()                   // 90
let c = Char.from_code_point(n)?       // Ok('Z')
```

The named method `Char.from_code_point(n)` is the idiomatic form. It is sugar over `TryFrom[Int] for Char` and returns `Result[Char, ConversionError]`. The `ConversionError` message includes the invalid value (e.g., `"55296 is not a valid Unicode scalar value"`).

##### Char → Str (Infallible — `From`)

Every `Char` can be encoded as a single-codepoint UTF-8 string. This conversion is total.

| From | To | Method | Trait |
|------|----|--------|-------|
| `Char` | `Str` | `.to_str()` | `From[Char] for Str` |

```blink
let s = 'A'.to_str()      // "A"
let s = Str.from('é')     // "é" (via From trait)

// Useful in method chains
let vowels = "hello"
    .chars()
    .filter(fn(c) { "aeiou".contains(c.to_str()) })
    .map(fn(c) { c.to_str() })
    .collect()
```

**When to use `.to_str()` vs interpolation.** Use `"{c}"` when embedding a `Char` in a larger string. Use `c.to_str()` when a standalone `Str` value is needed — function arguments, map/collect chains, struct fields. Both produce identical output; the choice is contextual, not semantic.

##### Summary Table

| Conversion | Direction | Method | Trait | Fallible? |
|------------|-----------|--------|-------|-----------|
| Char → Int | widening | `.to_int()` | `From[Char] for Int` | No |
| Int → Char | narrowing | `Char.from_code_point(n)` | `TryFrom[Int] for Char` | Yes |
| Char → Str | encoding | `.to_str()` | `From[Char] for Str` | No |

(Vote: Q1 4-1, Q2 4-1, Q3 5-0. See [Char Conversions rationale](../decisions/char-conversions.md).)

---

### 3c.4 Method Resolution

When the compiler encounters `x.foo(args)`, it must determine what `foo` means. Blink has three kinds of entities reachable via dot syntax: struct fields, trait methods, and effect handle operations. This section specifies the resolution algorithm.

#### The Rule: Dot Means Method

`x.foo(args)` is **always** a method call — the compiler searches for a trait method named `foo` on the type of `x`. It is never a field access followed by a call.

To call a function stored in a struct field, use explicit parenthesized field access:

```blink
type Button {
    on_click: fn() -> ()
    label: Str
}

let b = Button { on_click: fn() { io.println("clicked") }, label: "OK" }
b.on_click()       // COMPILE ERROR: no method `on_click` found for type `Button`
(b.on_click)()     // OK: field access, then call the fn() value
```

**Why not auto-call fields.** If `x.foo()` could mean both "call method foo" and "access field foo (which is callable), then call it," the compiler needs a priority rule, and adding a trait impl to a type could silently change which code runs at existing call sites. Separating the two syntactically — `.foo()` for methods, `(x.foo)(args)` for field-calls — makes every call site unambiguous. The `(x.foo)(args)` form is explicit: it says "I know this is a field, I want to call it."

#### Field Access (No Parens)

Plain `x.foo` without parentheses is always field access. It is valid only when `foo` is a field of x's type.

```blink
type User {
    name: Str
    age: Int
}

let u = User { name: "Alice", age: 30 }
u.name      // "Alice" — field access
u.age       // 30 — field access
u.name()    // method call: searches traits for `name(self) -> ?` on User
```

This means field access and method calls occupy distinct syntactic positions: `x.foo` is a field, `x.foo()` is a method. No ambiguity.

#### Trait Method Lookup

When the compiler sees `x.foo(args)`, it searches all traits in scope that x's type implements, looking for a method named `foo` with a compatible signature. The search follows these rules:

1. **Single match.** Exactly one trait in scope has `foo` for this type → call it.
2. **No match.** No trait in scope has `foo` for this type → compile error.
3. **Multiple matches.** Two or more traits have `foo` for this type → compile error with disambiguation hint.

```blink
trait Serializable {
    fn serialize(self) -> Str
}

trait Debuggable {
    fn serialize(self) -> Str
}

impl Serializable for Config {
    fn serialize(self) -> Str { /* JSON */ }
}

impl Debuggable for Config {
    fn serialize(self) -> Str { /* debug format */ }
}

let c = Config { /* ... */ }
c.serialize()                // COMPILE ERROR: ambiguous — found in Serializable and Debuggable
Serializable.serialize(c)    // OK: qualified call, JSON format
Debuggable.serialize(c)      // OK: qualified call, debug format
```

```
error[AmbiguousMethodCall]: ambiguous method call
 --> config.bl:20:1
  |
20| c.serialize()
  |   ^^^^^^^^^ method `serialize` found in multiple traits
  |
  = note: `serialize` is defined in both `Serializable` and `Debuggable`
  = help: use qualified syntax to disambiguate:
  |   Serializable.serialize(c)
  |   Debuggable.serialize(c)
```

#### Qualified Method Calls

Any trait method can be called using qualified syntax: `TraitName.method(receiver, args)`. The receiver is passed explicitly as the first argument (the `self` parameter).

```blink
// Unqualified — works when unambiguous
user.display()

// Qualified — always works, required when ambiguous
Display.display(user)

// Qualified with trait bound
fn show[T: Display](val: T) -> Str {
    Display.display(val)   // equivalent to val.display()
}
```

Qualified syntax is also useful for calling a specific trait's default method, or a `final` (sealed) default whose body is fixed by the trait — like `Display.display`, which is always defined as `let sb = StringBuilder.new(); self.fmt(sb); sb.to_str()` regardless of which type implements `Display`.

Qualified call is a *call-site* mechanism, not a *super-call* mechanism. Inside an `impl` block overriding an open trait default, writing `Trait.method(self, ...)` does not reach the trait's default body — it resolves to the same method the call site sees, which is the impl's override. Blink has no method-resolution-order chain to walk back through. If an override needs the default's body, factor that body into a free helper function and call the helper from both sites. See §3.6 *The `final` Modifier* for the replace-only override rule.

#### Effect Handle Operations

Effect handles (`io`, `db`, `fs`, `net`, `env`, `time`, `rand`, `crypto`, `process`, and user-defined effect handles) occupy a **reserved namespace** separate from local variables. When a function declares effects via `!`, the corresponding handle names are reserved within that function's scope. Local variables cannot shadow them.

```blink
fn example() ! IO, DB.Read {
    let io = 42          // COMPILE ERROR EffectHandleShadowed: `io` is reserved (effect handle for IO)
    let db = "hello"     // COMPILE ERROR EffectHandleShadowed: `db` is reserved (effect handle for DB)
    let fs = "ok"        // OK: function does not declare FS effects, `fs` is not reserved here
}
```

```
error[EffectHandleShadowed]: cannot shadow effect handle
 --> example.bl:2:9
  |
2 |     let io = 42
  |         ^^ `io` is reserved as the effect handle for `IO`
  |
  = note: function `example` declares effect `IO`, which reserves the name `io`
  = help: choose a different variable name
```

Effect handle operations are syntactically identical to method calls (`io.println(msg)`, `db.read(query)`), but they are resolved through the effect system, not through trait lookup. The compiler knows which identifiers are effect handles from the function's `!` declaration, so there is never ambiguity between `io.println()` (effect operation) and a hypothetical trait method `println` on some type — `io` is not a value of any type, it is a capability handle.

**Why reserved.** Effect handles are capability proofs (§4.4). Allowing `let io = something_else` would break the guarantee that `io.println()` always routes through the effect handler chain. The reserved namespace ensures go-to-definition on any effect operation always reaches the effect declaration, LSP always shows effect operations in autocomplete, and the evidence-passing compilation ([Codegen Backend rationale](../decisions/codegen-backend-bootstrap.md)) can assume handle names are stable.

#### No Inherent Methods

Blink does not support `impl Foo { fn bar(self) ... }` (methods defined directly on a type without a trait). All methods must belong to a trait.

For type-specific operations, define a trait:

```blink
trait Parse {
    fn parse(self) -> Result[AST, ParseError]
}

impl Parse for Str {
    fn parse(self) -> Result[AST, ParseError] { /* ... */ }
}
```

**Why no inherent methods.** Inherent methods create a silent priority over trait methods — adding an inherent method to a type can change which code runs at existing call sites without any error. Without inherent methods, adding a trait impl can only cause ambiguity errors (which are loud and fixable), never silent behavior changes. One mechanism for methods (traits) follows Principle 2. (Vote: 4-1, Systems dissented wanting inherent methods to avoid single-method traits.)

#### Built-in Type Method Dispatch

Built-in types (`Str`, `List[T]`, `Map[K,V]`, `Set[T]`, `Bytes`, `StringBuilder`, `Instant`, `Duration`, `Iterator[T]`) have their methods defined by compiler-known traits (`Sized`, `StrOps`, `ListOps`, `MapOps`, `SetOps`, `StringBuildOps`, `IteratorOps`, etc.). These surfaces are **sealed** — a user program cannot implement or override them. The underlying FFI bridge functions in `lib/std/` are internal — not part of the public API. Users interact exclusively through method syntax (§3.2).

**Implementation note:** The current compiler implements dispatch for these types via hardcoded pattern matching in `codegen_methods.bl` rather than real trait resolution. This is an implementation shortcut — the spec-level semantics are trait-based, and the compiler should migrate to real trait resolution as the trait system matures. The hardcoded dispatch produces identical codegen (direct C function calls) and is invisible to users.

#### Resolution Summary

| Syntax | Meaning | Resolved by |
|--------|---------|------------|
| `x.foo` | Field access | Type's field list |
| `x.foo(args)` | Trait method call | Trait lookup on x's type |
| `(x.foo)(args)` | Call function-typed field | Field access + function application |
| `Trait.foo(x, args)` | Qualified trait method call | Explicit trait + method |
| `handle.op(args)` | Effect handle operation | Effect declaration (`!`) |

#### Interaction with Other Features

**Iterator adapters** (§3c.1): `.map()`, `.filter()`, `.collect()` etc. are the sealed built-in method surface of the opaque `Iterator[T]` carrier, dispatched like the other built-in types above (`StrOps`/`ListOps`), not user-overridable trait defaults. Collections carry their own **eager** adapter surface that answers a collection; `.into_iter()` crosses into the lazy `Iterator` surface and `.collect()` crosses back.

**Operator desugaring** (§3.6): `a + b` desugars to `Add.add(a, b)` — a qualified trait call, not dot syntax. Operators bypass method resolution entirely.

**String interpolation** (§3.6.1): `"{value}"` requires `T: Display` at compile time. The compiler checks the trait bound during type checking, then optimizes codegen: built-in types use direct format specifiers, user types emit `value.fmt(sb)` — a direct push into the interpolation's internal `StringBuilder`, with no intermediate `Str` per slot. In `Template[C]` context, Display is not invoked — interpolation produces parameterized placeholders instead. See §3.6 Display Format Protocol.

**`self` in trait methods**: Inside an `impl Trait for Foo` block, `self` has type `Foo`. Field access on `self` uses `self.field`. Method calls on `self` use `self.method()` with normal trait lookup.
