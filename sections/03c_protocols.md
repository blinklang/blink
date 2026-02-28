## 3c. Protocols & Conversions

### 3c.1 Iterator Protocol

`for x in collection { }` is Pact's primary iteration construct. It requires a formal protocol: two compiler-known traits that define what "iterable" means and how iteration proceeds.

#### The `Iterator` Trait

```pact
trait Iterator[T] {
    fn next(self) -> Option[T]
}
```

One required method. Call `next()` repeatedly; it returns `Some(value)` for each element and `None` when exhausted. An iterator is a stateful cursor — once `next()` returns `None`, subsequent calls continue to return `None`.

**Why single-method.** `has_next()` + `next()` (Java) requires callers to coordinate two calls and creates invalid states (calling `next()` without `has_next()`). A single `next() -> Option[T]` encodes both "is there more?" and "give me the value" in one atomic operation. No invalid states, no double calls, no off-by-one bugs. (Vote: 3-2, Systems and PLT dissented wanting `size_hint()`.)

#### The `IntoIterator` Trait

```pact
trait IntoIterator[T] {
    fn into_iter(self) -> Iterator[T]
}
```

`IntoIterator` converts a value into an `Iterator`. This separates "thing that can be iterated" (a collection) from "thing that tracks iteration state" (an iterator). Collections implement `IntoIterator`; the returned `Iterator` does the actual traversal.

```pact
impl IntoIterator[T] for List[T] {
    fn into_iter(self) -> Iterator[T] {
        ListIterator { items: self, index: 0 }
    }
}
```

Iterators themselves implement `IntoIterator` trivially (return `self`), so you can pass an iterator where an iterable is expected:

```pact
impl IntoIterator[T] for Iterator[T] {
    fn into_iter(self) -> Iterator[T] { self }
}
```

**Why the separation.** A `List[Str]` is not an iterator — it has no cursor position. If `List` implemented `Iterator` directly, iterating the same list twice would require resetting internal state, and two concurrent `for` loops over the same list would interfere. `IntoIterator` produces a fresh `Iterator` each time, so:

```pact
let names = ["Alice", "Bob", "Carol"]
for n in names { io.println(n) }   // first pass — fresh iterator
for n in names { io.println(n) }   // second pass — new fresh iterator
```

Both loops work correctly. Each `for` calls `names.into_iter()` independently.

#### `for` Loop Desugaring

The compiler desugars `for x in expr { body }` into:

```pact
let mut __iter = expr.into_iter()
loop {
    match __iter.next() {
        Some(x) => { body }
        None => break
    }
}
```

`break` exits the loop. `continue` skips to the next `__iter.next()` call. This desugaring is the *only* way `for` interacts with the iterator protocol — no special compiler magic beyond calling `into_iter()` and `next()`.

#### Lazy Adapter Methods

Iterator adapters are default methods on `Iterator`. They return new lazy iterators that transform elements on demand — no intermediate collections are allocated.

```pact
trait Iterator[T] {
    fn next(self) -> Option[T]

    // Transforming
    fn map[U](self, f: fn(T) -> U) -> Iterator[U] {
        MapIterator { source: self, f }
    }

    fn filter(self, predicate: fn(T) -> Bool) -> Iterator[T] {
        FilterIterator { source: self, predicate }
    }

    // Slicing
    fn take(self, n: Int) -> Iterator[T] {
        TakeIterator { source: self, remaining: n }
    }

    fn skip(self, n: Int) -> Iterator[T] {
        SkipIterator { source: self, remaining: n }
    }

    // Combining
    fn zip[U](self, other: Iterator[U]) -> Iterator[(T, U)] {
        ZipIterator { a: self, b: other }
    }

    fn enumerate(self) -> Iterator[(Int, T)] {
        EnumerateIterator { source: self, index: 0 }
    }

    fn chain(self, other: Iterator[T]) -> Iterator[T] {
        ChainIterator { first: self, second: other }
    }

    // Consuming (these drain the iterator)
    fn collect(self) -> List[T] {
        let mut result = []
        for item in self {
            result.push(item)
        }
        result
    }

    fn fold[U](self, init: U, f: fn(U, T) -> U) -> U {
        let mut acc = init
        for item in self {
            acc = f(acc, item)
        }
        acc
    }

    fn count(self) -> Int {
        self.fold(0, fn(n, _) { n + 1 })
    }

    fn any(self, predicate: fn(T) -> Bool) -> Bool {
        for item in self {
            if predicate(item) { return true }
        }
        false
    }

    fn all(self, predicate: fn(T) -> Bool) -> Bool {
        for item in self {
            if !predicate(item) { return false }
        }
        true
    }

    fn find(self, predicate: fn(T) -> Bool) -> Option[T] {
        for item in self {
            if predicate(item) { return Some(item) }
        }
        None
    }

    fn flat_map[U](self, f: fn(T) -> Iterator[U]) -> Iterator[U] {
        FlatMapIterator { source: self, f, current: None }
    }

    fn for_each(self, f: fn(T)) {
        for item in self { f(item) }
    }
}
```

**Lazy means no work until consumed.** Calling `.map(f).filter(p)` builds a pipeline description — zero elements are processed. Elements flow through the pipeline one at a time when a consuming method (`collect`, `fold`, `count`, `for_each`, `any`, `all`, `find`) or a `for` loop pulls from the end.

```pact
// No intermediate List allocated — elements flow one at a time
let result = names
    .into_iter()
    .filter(fn(n) { n.len() > 3 })
    .map(fn(n) { n.to_upper() })
    .take(5)
    .collect()   // materialization point
```

**Why lazy by default.** Eager adapters (Python's `list.map()` style) allocate intermediate collections at every step. Chaining `.map().filter().take(5)` on a million-element list would allocate three intermediate lists, processing all million elements, only to discard all but 5. Lazy evaluation processes only what's needed — if `.take(5)` finds 5 matching elements after examining 20, the remaining 999,980 are never touched. (Vote: 5-0.)

**Why default methods.** Implement `next()` and get the entire adapter library for free. This minimizes what users (and AI) must write for custom iterators: one method, not twenty. Collections can override specific adapters for performance — `List.count()` can return the stored length rather than iterating. (Vote: 5-0.)

#### Built-in IntoIterator Implementations

| Type | `into_iter()` yields | Notes |
|------|---------------------|-------|
| `List[T]` | `T` | Elements in order |
| `Set[T]` | `T` | Unspecified order |
| `Map[K, V]` | `(K, V)` | Key-value pairs, unspecified order |
| `Range[T]` | `T` | Lazy; `0..1000000` allocates nothing |
| `Str` | `Char` | Unicode scalar values |
| `Iterator[T]` | `T` | Identity (returns self) |

#### Example: Custom Iterator

```pact
type Fibonacci {
    a: Int
    b: Int
}

fn fibonacci() -> Fibonacci {
    Fibonacci { a: 0, b: 1 }
}

impl Iterator[Int] for Fibonacci {
    fn next(self) -> Option[Int] {
        let value = self.a
        self.a = self.b
        self.b = value + self.b
        Some(value)
    }
}

// Usage
let fibs = fibonacci()
    .take(10)
    .collect()   // [0, 1, 1, 2, 3, 5, 8, 13, 21, 34]

let sum_of_even_fibs = fibonacci()
    .filter(fn(n) { n % 2 == 0 })
    .take(5)
    .fold(0, fn(acc, n) { acc + n })
```

#### Effectful Iteration: Deferred to v2

The v1 `Iterator` trait is pure — `next()` cannot perform effects. This means `for line in file.lines() ! IO` is not expressible through the iterator protocol in v1.

**Workaround for v1:** Use explicit loops with effect-performing calls:

```pact
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

**Why defer.** Effectful iterators interact with lazy evaluation in subtle ways: when does the effect fire? Does `.map()` over an effectful iterator inherit the effect? How does effect polymorphism compose with iterator type parameters? The effect system is powerful but young. Shipping pure iterators now and designing effectful iteration once real Pact codebases reveal the right patterns avoids baking in a wrong abstraction. (Vote: 3-2, Systems and PLT dissented wanting effects in v1.)

#### Pipe Operator Interaction

The `|>` pipe operator chains naturally with iterator methods:

```pact
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

Pact has no implicit conversions. Every type conversion is explicit, visible in source, and compiler-checked. Three compiler-known traits provide the conversion protocol.

#### The `From` Trait

```pact
trait From[T] {
    fn from(value: T) -> Self
}
```

`From[T]` is the single canonical conversion trait. To convert a value of type `T` into type `U`, implement `From[T] for U`. The conversion is infallible — it always succeeds.

```pact
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

```pact
let err: ConfigError = ConfigError.from(io_error)
```

**Every type has a reflexive From impl:** `impl From[T] for T { fn from(value: T) -> T { value } }` is compiler-provided for all types.

#### The `Into` Trait (Auto-Derived, Never User-Implemented)

```pact
trait Into[T] {
    fn into(self) -> T
}
```

`Into[T]` is the mirror of `From[T]`, providing method-call syntax: `value.into()`. The compiler auto-derives `Into[U] for T` whenever `From[T] for U` exists. Users **never** implement `Into` directly — implementing `From` is the only way.

```pact
// These are equivalent:
let err: ConfigError = ConfigError.from(io_error)
let err: ConfigError = io_error.into()   // works because From[IOError] for ConfigError exists
```

**Why auto-derive only.** If users could implement `Into` directly, you could create incoherent pairs (`A: Into[B]` without `B: From[A]`), breaking the bidirectional guarantee. One source of truth: implement `From`, get `Into` for free. (Vote: 4-1, AI/ML dissented wanting no Into at all — but method-call syntax is important for chaining.)

#### The `TryFrom` Trait

```pact
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

```pact
let port = Port.try_from(user_input)?
let small: I8 = I8.try_from(big_number)?
```

**Why fixed `ConversionError`, not per-impl error types.** Pact has no associated types. A generic `TryFrom[T, E]` would be more precise but creates cascading boilerplate: every TryFrom impl needs a custom error type, every call site needs a From impl to propagate that error into the caller's error type. A fixed ConversionError keeps the diagnostic story simple and eliminates trait-impl boilerplate explosion. (Vote: 3-2, Systems/PLT dissented wanting generic `TryFrom[T, E]`.)

**Refinement type integration.** Refinement types (§3b.1) auto-generate `TryFrom` impls. `type Port = Int @where(self > 0 && self <= 65535)` generates:

```pact
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

```pact
// expr? where expr : Result[T, E] desugars to:
match expr {
    Ok(val) => val
    Err(e) => return Err(e)   // e must match the function's error type exactly
}
```

**Rule 3: `?` on `Option[T]` requires the enclosing function to return `Option[U]`.** The function's return type must be an `Option`. If not, it is a compile error (E0509). Desugaring:

```pact
// expr? where expr : Option[T] desugars to:
match expr {
    Some(val) => val
    None => return None
}
```

```pact
fn find_user_email(id: Int) -> Option[Str] ! DB {
    let user = db.find_user(id)?    // returns None if user not found
    let profile = db.get_profile(user.id)?  // returns None if no profile
    Some(profile.email)
}
```

**Rule 4: For `Result[T, E1]`, the error type must exactly match the function's `Result[U, E2]` — `E1 == E2`.** There is no automatic `.into()` call on the error variant. Mismatched error types produce E0512.

```pact
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

```pact
fn load_user(id: Int) -> Result[User, AppError] ! DB {
    // Option → Result: use .ok_or() or match
    let user = db.find_user(id)
        .ok_or(AppError.NotFound("user {id}"))?
    Ok(user)
}
```

**Why no auto-conversion.** Pact explicitly rejected implicit conversions. Auto-calling `.into()` on `?` is implicit conversion — the error type changes without visible syntax at the call site. Explicit `.map_err()` makes every conversion visible, greppable, and unambiguous. Start strict, can relax later; can never tighten without breaking code. (Vote: 4-1, DevOps dissented wanting auto-conversion with strong diagnostics. Reaffirmed 5-0 during `?` operator validation deliberation.)

**Why both Result and Option.** `?` is fundamentally early-return sugar on the "failure" branch of a sum type. For `Result` that branch is `Err(e)`, for `Option` it is `None`. The same control flow pattern applies to both — forcing different syntax for structurally identical operations would be an arbitrary distinction. (Vote: 5-0.)

**Why type checking, not codegen.** `?` validation requires type information (is this a Result or Option? what are its type parameters?). Placing validation in the type checking phase ensures codegen only processes fully-validated programs, matching the phase gate architecture (§6.3). Invalid `?` usage that reaches codegen previously generated broken C output — the type checker eliminates this entire class of bugs. (Vote: 5-0.)

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

```pact
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
 --> math.pact:12:15
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

```pact
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

```pact
let x: Int = 42
let y: Float = 3.14
let z = x + y   // COMPILE ERROR: Int + Float not defined

// Fix: explicit conversion
let z = x.to_float() + y   // OK
```

This is unchanged from §2.18 and §3.6 — stated here for completeness.

#### Char Conversions

`Char` (Unicode scalar value) participates in the conversion system via `From`/`TryFrom` traits and named methods, following the same dual-API pattern as numeric types (§3c.3). `Char` is not a numeric type — it does not implement arithmetic traits — but its codepoint representation is an integer, so conversions between `Char` and `Int` are well-defined.

##### Char → Int (Infallible — `From`)

Every `Char` is a Unicode scalar value in the range 0x0000–0x10FFFF (excluding surrogates). This always fits in `Int` (i64), so the conversion is infallible.

| From | To | Method | Trait | Notes |
|------|----|--------|-------|-------|
| `Char` | `Int` | `.to_int()` | `From[Char] for Int` | Returns Unicode codepoint value |

```pact
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

```pact
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

```pact
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

When the compiler encounters `x.foo(args)`, it must determine what `foo` means. Pact has three kinds of entities reachable via dot syntax: struct fields, trait methods, and effect handle operations. This section specifies the resolution algorithm.

#### The Rule: Dot Means Method

`x.foo(args)` is **always** a method call — the compiler searches for a trait method named `foo` on the type of `x`. It is never a field access followed by a call.

To call a function stored in a struct field, use explicit parenthesized field access:

```pact
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

```pact
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

```pact
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
 --> config.pact:20:1
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

```pact
// Unqualified — works when unambiguous
user.display()

// Qualified — always works, required when ambiguous
Display.display(user)

// Qualified with trait bound
fn show[T: Display](val: T) -> Str {
    Display.display(val)   // equivalent to val.display()
}
```

Qualified syntax is also useful for calling a specific trait's default method when a type hasn't overridden it.

#### Effect Handle Operations

Effect handles (`io`, `db`, `fs`, `net`, `env`, `time`, `rand`, `crypto`, `process`, and user-defined effect handles) occupy a **reserved namespace** separate from local variables. When a function declares effects via `!`, the corresponding handle names are reserved within that function's scope. Local variables cannot shadow them.

```pact
fn example() ! IO, DB.Read {
    let io = 42          // COMPILE ERROR EffectHandleShadowed: `io` is reserved (effect handle for IO)
    let db = "hello"     // COMPILE ERROR EffectHandleShadowed: `db` is reserved (effect handle for DB)
    let fs = "ok"        // OK: function does not declare FS effects, `fs` is not reserved here
}
```

```
error[EffectHandleShadowed]: cannot shadow effect handle
 --> example.pact:2:9
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

Pact does not support `impl Foo { fn bar(self) ... }` (methods defined directly on a type without a trait). All methods must belong to a trait.

For type-specific operations, define a trait:

```pact
trait Parse {
    fn parse(self) -> Result[AST, ParseError]
}

impl Parse for Str {
    fn parse(self) -> Result[AST, ParseError] { /* ... */ }
}
```

**Why no inherent methods.** Inherent methods create a silent priority over trait methods — adding an inherent method to a type can change which code runs at existing call sites without any error. Without inherent methods, adding a trait impl can only cause ambiguity errors (which are loud and fixable), never silent behavior changes. One mechanism for methods (traits) follows Principle 2. (Vote: 4-1, Systems dissented wanting inherent methods to avoid single-method traits.)

#### Resolution Summary

| Syntax | Meaning | Resolved by |
|--------|---------|------------|
| `x.foo` | Field access | Type's field list |
| `x.foo(args)` | Trait method call | Trait lookup on x's type |
| `(x.foo)(args)` | Call function-typed field | Field access + function application |
| `Trait.foo(x, args)` | Qualified trait method call | Explicit trait + method |
| `handle.op(args)` | Effect handle operation | Effect declaration (`!`) |

#### Interaction with Other Features

**Iterator adapters** (§3c.1): `.map()`, `.filter()`, `.collect()` etc. are default methods on the `Iterator` trait. They resolve through normal trait method lookup.

**Operator desugaring** (§3.6): `a + b` desugars to `Add.add(a, b)` — a qualified trait call, not dot syntax. Operators bypass method resolution entirely.

**String interpolation** (§3.6.1): `"{value}"` requires `T: Display` at compile time. The compiler checks the trait bound during type checking, then optimizes codegen: built-in types use direct format specifiers, user types emit `Display.display(value)` as a qualified trait call. In `Query[C]` context, Display is not invoked — interpolation produces parameterized placeholders instead. See §3.6 Display Format Protocol.

**`self` in trait methods**: Inside an `impl Trait for Foo` block, `self` has type `Foo`. Field access on `self` uses `self.field`. Method calls on `self` use `self.method()` with normal trait lookup.
