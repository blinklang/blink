## 3. Type System

### 3.1 Overview

Blink's type system exists to serve a single goal: **make incorrect programs unrepresentable**. Not aspirationally, not eventually -- at compile time, before a single byte of machine code is emitted.

The foundation is Hindley-Milner type inference extended with algebraic data types, traits, and targeted verification features. This is not a novel combination. ML, Haskell, Rust, and OCaml have proven these ideas over decades. What Blink adds is a pragmatic verification layer -- refinement types and contracts backed by an SMT solver -- that captures the 90% of dependent-type value that matters in practice, without the 90% of dependent-type complexity that makes languages unusable.

**Design philosophy:**

1. **Types are documentation the compiler enforces.** A function signature in Blink tells you its inputs, outputs, effects, failure modes, and value constraints. An AI agent (or a human) can understand a function's contract from its signature alone, without reading the body. This is locality of reasoning applied to types.

2. **Prove, don't test.** Testing checks examples. Types check universals. A test says "this worked for these 5 inputs." A type says "this works for all inputs, forever." The type system is the primary correctness mechanism; tests are the fallback for properties that can't be expressed as types.

3. **Progressive verification.** Not every function needs SMT-backed contracts. Simple functions get simple types. Critical functions get refinement types and contracts. The type system scales from "just annotate the signature" to "formally verify this precondition" without forcing the heavy machinery on code that doesn't need it.

4. **Inference is a token budget.** Every type annotation an AI writes costs tokens. Every annotation a human writes costs keystrokes. The inference engine should eliminate redundant annotations everywhere it can -- but never at function boundaries, where types serve as API documentation.

#### Diagnostic Discipline (normative)

Three rules govern every diagnostic the type system emits. They constrain diagnostics not yet written, and each is checkable one diagnostic at a time.

1. **Never emit a diagnostic whose prescribed repair does not exist.** If a rule rejects a program, some edit the diagnostic names must make the program legal. A `help:` that cannot be followed is worse than silence, because both a human and a tool will follow it — and a machine-applicable fix that compiles while deleting the construct the user needed is the worst outcome of all.

2. **Every typing rule must be visible to `blink check`.** No rule is enforced only at codegen. A rule the front end cannot see is a rule no editor, no formatter, no fixer, and no agent in a loop can act on, and it turns a user error into an internal compiler error. The `UnsolvedTypeVarAtCodegen` backstop (I0001) exists to catch violations of *this* rule, not to serve as one.

3. **Diagnostics at one program point must converge.** When more than one diagnostic fires at the same point, at least one prescribed repair, applied, must discharge all of them — and it must be the repair the diagnostic names *first*. Two diagnostics that each demand the opposite of the other leave the user with no terminating edit; a converging repair that is offered second is a guarantee a mechanical fixer never reaches.

---

### 3.2 Built-in Types

```blink
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

**Why one default `Int`.** Rust's numeric type matrix (`i8`/`i16`/`i32`/`i64`/`u8`/.../`usize`/`isize`) is a decision tree that produces wrong answers. LLMs pick `i32` when they mean `i64`, `usize` when they mean `u64`, and `u32` for values that go negative. Blink has `Int`. It's 64-bit. It's signed. It handles every integer you'll encounter in application code. The sized variants (`I8`, `U16`, etc.) exist for interop, binary protocols, and performance-critical paths where you've measured and know you need them.

**Why `Float` not `F32`/`F64`.** Same reasoning. 64-bit is correct for virtually all floating-point work. If you need 32-bit floats (GPU interop, large arrays where memory matters), that's a future extension, not a v1 concern.

**Why `[T]` sugar for `List[T]`.** Lists are the most common generic type. `[Str]` is 5 characters. `List[Str]` is 9. The sugar is unambiguous (square brackets in type position always mean List) and saves tokens in signatures that use lists heavily. Both forms are valid; the canonical formatter normalizes to whichever the project chooses.

**Why `Option` and `Result` are built-in.** These aren't library types bolted on after the fact. The compiler understands them: `T?` desugars to `Option[T]`, the `?` operator desugars to a match on `Result`, `??` desugars to a match on `Option`. Special syntax demands special compiler support.

**Stdlib API surface: methods only.** Built-in types expose their API exclusively through trait methods — `.len()`, `.split()`, `.push()`, `.write()`, etc. The underlying FFI bridge functions in `lib/std/` (e.g., `str_len`, `bytes_push`, `sb_write`) are internal implementation details: non-public, non-importable, not part of the API. There is one way to call an operation on a built-in type: method syntax. Constructors use static method syntax on the type name (`Bytes.new()`, `StringBuilder.with_capacity(1024)`, `Duration.ms(100)`). This follows Principle 2 — no decision point between `s.len()` and `str_len(s)`. (Panel vote: 4-1. See [Stdlib API Surface rationale](../decisions/stdlib-api-surface.md).)

#### §3.2.1 String Methods

Strings are not bare character arrays. They are UTF-8 encoded, GC-managed, immutable values with a method surface designed to be complete enough that 90% of programs never need a string utility library. Methods are organized into two traits: `Sized` (generic, shared with collections) and `StrOps` (string-specific).

##### The `Sized` Trait

`Sized` provides length-awareness to any container type. `Str`, `List[T]`, `Map[K, V]`, and `Set[T]` all implement it.

```blink
trait Sized {
    fn len(self) -> Int
    final fn is_empty(self) -> Bool {
        self.len() == 0
    }
}
```

`is_empty` is `final` (§3.6 *The `final` Modifier*): it is a fixed derived view of `len`. No `impl Sized` may override it — implementors provide `len` only, and `is_empty` is mechanically derived from `len() == 0`. This guarantees that `x.is_empty()` and `x.len() == 0` always agree.

For `Str`, `.len()` returns the **codepoint count** — the number of Unicode scalar values, not the number of bytes. This is O(n) for general UTF-8 (the implementation may cache the result), but it gives the semantically correct answer: `"café".len()` is `4`, not `5`.

##### The `StrOps` Trait

All string-specific methods live in a single `StrOps` trait. `Str` is the only type that implements it.

```blink
trait StrOps {
    // Character access
    fn char_at(self, index: Int) -> Option[Char]
    fn byte_len(self) -> Int
    fn byte_at(self, index: Int) -> U8

    // Search
    fn contains(self, needle: Str) -> Bool
    fn starts_with(self, prefix: Str) -> Bool
    fn ends_with(self, suffix: Str) -> Bool
    fn index_of(self, needle: Str) -> Option[Int]

    // Extraction and transformation
    fn substring(self, start: Int, end: Int) -> Str
    fn concat(self, other: Str) -> Str
    fn split(self, separator: Str) -> List[Str]
    fn lines(self) -> List[Str]
    fn to_upper(self) -> Str
    fn to_lower(self) -> Str
    fn trim(self) -> Str
    fn trim_left(self) -> Str
    fn trim_right(self) -> Str
    fn replace(self, needle: Str, replacement: Str) -> Str

    // Parsing
    fn parse_int(self) -> Result[Int, ConversionError]
    fn parse_float(self) -> Result[Float, ConversionError]
}
```

The full method surface (15 core methods from `Sized` + `StrOps`, plus byte-access and parsing):

| Method | Signature | Returns |
|--------|-----------|---------|
| `len` | `fn(self) -> Int` | Codepoint count |
| `is_empty` | `fn(self) -> Bool` | `self.len() == 0` |
| `char_at` | `fn(self, Int) -> Option[Char]` | Codepoint at logical index |
| `contains` | `fn(self, Str) -> Bool` | Substring presence |
| `starts_with` | `fn(self, Str) -> Bool` | Prefix check |
| `ends_with` | `fn(self, Str) -> Bool` | Suffix check |
| `substring` | `fn(self, Int, Int) -> Str` | Codepoint-indexed slice |
| `concat` | `fn(self, Str) -> Str` | Concatenation |
| `split` | `fn(self, Str) -> List[Str]` | Split by separator |
| `to_upper` | `fn(self) -> Str` | Uppercase (Unicode-aware) |
| `to_lower` | `fn(self) -> Str` | Lowercase (Unicode-aware) |
| `trim` | `fn(self) -> Str` | Strip leading/trailing whitespace |
| `trim_left` | `fn(self) -> Str` | Strip leading whitespace only |
| `trim_right` | `fn(self) -> Str` | Strip trailing whitespace only |
| `replace` | `fn(self, Str, Str) -> Str` | Replace all occurrences |
| `index_of` | `fn(self, Str) -> Option[Int]` | Codepoint index of first match |
| `lines` | `fn(self) -> List[Str]` | Split by line endings |
| `parse_int` | `fn(self) -> Result[Int, ConversionError]` | Parse as integer |
| `parse_float` | `fn(self) -> Result[Float, ConversionError]` | Parse as float |
| `byte_len` | `fn(self) -> Int` | Byte count (O(1)) |
| `byte_at` | `fn(self, Int) -> U8` | Raw byte at offset |

##### Unicode Semantics

Blink strings are codepoint-oriented by default. All index-based methods operate on codepoint positions, not byte offsets.

```blink
let s = "café"
s.len()              // 4 (codepoints)
s.char_at(3)         // Some('é')
s.byte_len()         // 5 (UTF-8 bytes — 'é' is 2 bytes)
s.substring(0, 4)    // "café"
s.index_of("fé")     // Some(2)
```

Byte-access methods use the `byte_` prefix. These exist for interop, binary protocols, and performance-sensitive code that operates on raw UTF-8.

```blink
let s = "héllo"
s.byte_len()         // 6
s.byte_at(0)         // 104 (ASCII 'h')
s.byte_at(1)         // 195 (first byte of 'é')
```

**Why codepoint-default.** The choice is between three levels of abstraction: bytes (Go, C), codepoints (Python 3, Java), and grapheme clusters (Swift). Bytes are too low-level — indexing into the middle of a multibyte character is a bug factory. Grapheme clusters are linguistically correct but expensive and complex (cluster boundaries depend on Unicode version and locale). Codepoints hit the pragmatic middle: they correspond to what most programmers mean by "character," they are well-defined by Unicode, and they avoid the worst class of string bugs. The `byte_` prefix makes raw access available but intentionally inconvenient (panel vote: 3-2, Systems and PLT dissented wanting byte-default).

`Str` also implements `IntoIterator[Char]`, so `for c in str` iterates codepoints:

```blink
for c in "hello" {
    io.println("{c}")
}

// Or explicitly via .chars()
let vowels = "hello".chars().filter(fn(c) { "aeiou".contains("{c}") }).collect()
```

##### Parsing

`parse_int` and `parse_float` are methods on `Str` rather than standalone functions. They delegate to `TryFrom` internally but provide a discoverable, grep-able API surface.

```blink
let port = "8080".parse_int()?                      // Ok(8080)
let rate = "3.14".parse_float()?                     // Ok(3.14)
let bad = "not_a_number".parse_int()                 // Err(ConversionError)

// Common pattern: parse with default
let timeout = config.get("timeout") ?? "30"
let seconds = timeout.parse_int() ?? 30
```

##### String Building

For assembling strings from parts, Blink provides four mechanisms:

1. **String interpolation** — for inline composition: `"Hello, {name}!"`
2. **`concat`** — for joining two strings: `greeting.concat(name)`
3. **`join`** — for assembling a list of strings with a separator:

```blink
let parts = ["Hello", "world"]
let sentence = parts.join(", ")          // "Hello, world"

let csv_line = values.join(",")          // "1,Alice,30"
let path = segments.join("/")            // "usr/local/bin"

// Building up dynamically
let mut lines: List[Str] = []
for user in users {
    lines.push("{user.name}: {user.email}")
}
let report = lines.join("\n")
```

`join` is defined on `List[Str]` via the `Joinable` trait:

```blink
trait Joinable {
    fn join(self, separator: Str) -> Str
}

impl Joinable for List[Str] {
    fn join(self, separator: Str) -> Str {
        // built-in implementation
    }
}
```

4. **`StringBuilder`** — for efficient incremental string building in loops and codegen:

```blink
fn build_json(fields: List[(Str, Str)]) -> Str {
    let mut sb = StringBuilder.new()
    sb.write("{")
    for entry in fields.enumerate() {
        let (i, (key, value)) = entry
        if i > 0 { sb.write(", ") }
        sb.write("{key}: {value}")
    }
    sb.write("}")
    sb.to_str()
}
```

`StringBuilder` is a mutable buffer backed by a contiguous byte array with amortized O(1) append. It is a compiler-known built-in type: like `Str`/`List`/`Map`/`Set`, both the type name (including `StringBuilder.new()` / `StringBuilder.with_capacity(n)`) and its methods are in the prelude and require no import. Methods are on the compiler-known `StringBuildOps` trait:

```blink
trait StringBuildOps {
    fn write[T: Display](self, x: T)
    fn write_char(self, c: Char)
    fn to_str(self) -> Str
    fn len(self) -> Int
    fn capacity(self) -> Int
    fn clear(self)
}
```

`StringBuilder` also implements `Sized` (via `len`/`is_empty`).

| Method | Signature | Notes |
|--------|-----------|-------|
| `new` | `fn() -> StringBuilder` | Empty buffer, default capacity |
| `with_capacity` | `fn(n: Int) -> StringBuilder` | Pre-allocate `n` bytes to avoid reallocs |
| `write` | `fn[T: Display](self, x: T)` | Append `x` rendered by `Display`; same as `x.fmt(sb)`. Requires `let mut` |
| `write_char` | `fn(self, c: Char)` | Append single character. Not generic; does not go through `Display` |
| `to_str` | `fn(self) -> Str` | Produce immutable `Str` (copies buffer) |
| `len` | `fn(self) -> Int` | Current content length in codepoints |
| `capacity` | `fn(self) -> Int` | Current buffer capacity |
| `clear` | `fn(self)` | Reset to empty, retains capacity for reuse |

**`to_str()` always copies.** The returned `Str` is an independent immutable value. Subsequent `write()` or `clear()` calls on the builder do not affect previously returned strings. This is the only safe semantics given GC-managed immutable `Str`.

**Interpolation optimization.** When the compiler sees `sb.write("{x}: {y}")` where the argument is an interpolated string literal, it lowers the call to a sequence of individual writes (`sb.write(x_str); sb.write(": "); sb.write(y_str)`) instead of materializing a temporary `Str`. This is a codegen optimization, transparent to the type system: the argument is a `Str`, so the call checks against `write[T: Display]` with `T = Str`, as any other `Str` argument does. (Vote: 4-1, Systems dissented wanting explicit multi-write.)

**When to use which:**
- **Interpolation** — inline composition, the 80% case
- **`concat`/`join`** — combining known pieces or a list of strings
- **`StringBuilder`** — loops building strings incrementally, codegen, or any case where `concat` in a loop would be O(N²)

(Panel vote: 3-1-1 for Option D. See [StringBuilder rationale](../decisions/string-builder.md).)

#### §3.2.2 Collection Methods

`List[T]`, `Map[K, V]`, and `Set[T]` are built-in collection types with method surfaces organized across four traits: `Sized` (shared, §3.2.1), `Contains[T]` (shared), and per-type operation traits (`ListOps[T]`, `MapOps[K, V]`, `SetOps[T]`). Iterator adapters (`.map()`, `.filter()`, `.collect()`, etc.) are default methods on `Iterator` (§3c.1) and are not repeated here.

##### Construction and Mutability

Collections are constructed via `Type.new()` for empty collections or literal syntax where available. A **mutating method** is a method that declares `mut self` (§3.6 *Mutable Parameters*): `push`, `pop`, `insert`, `remove`, `set` and `clear` on collections, and every `write` method on `StringBuilder`. A call to a mutating method needs a mutable **root**: the first name of the receiver path must be a `let mut` binding or a `mut` parameter. `p.xs.push(x)` needs `p` to be mutable. An immutable root can only call non-mutating methods (`get`, `contains`, `len`, `keys`, `values`, etc.). A violation is `error[E0610] MutationRequiresMut`.

```blink
// Empty collections
let mut list = List.new()
let mut map = Map.new()
let mut set = Set.new()

// Literal syntax (List only)
let names = ["Alice", "Bob", "Carol"]          // List[Str], immutable
let mut scores = [100, 95, 87]                 // List[Int], mutable

// Mutation requires let mut
list.push("hello")                              // OK — list is mut
names.push("Dave")                              // COMPILE ERROR — names is not mut

// The root of a field path decides (type Form { tags: List[Str] })
let mut form = Form { tags: List.new() }
form.tags.push("new")                           // OK — root `form` is mut
```

**Why `Type.new()` + `let mut`.** Mutability is a property of the *binding*, not the *type*. `List[T]` is one type regardless of whether the binding is mutable — no `MutList`/`ImmutableList` split, no doubled API surface, no coercion rules at function boundaries. `mut` marks every place where a mutation starts: each mutating call and each assignment names a `let mut` binding or a `mut` parameter. It does not mark every value that changes. Collections are shared cells (§3.6 *Shared cells*), so an immutable name can observe a change made through a `mut` alias:

```blink
let a = [1, 2]
let mut b = a          // warning[MutAliasOfImmutable] — `b` shares `a`'s list
b.push(3)              // `a` now holds 3 as well
```

(Vote: 5-0. Rationale text revised by the parameter-mutation panel, 6-0 — see [Parameter Mutation rationale](../decisions/parameter-mutation.md).)

##### The `Contains` Trait

`Contains` provides membership testing across all collection types. It is the one operation with identical semantics on lists (linear scan), maps (key lookup), and sets (hash lookup).

```blink
trait Contains[T] {
    fn contains(self, value: T) -> Bool
}
```

| Type | `contains` semantics | Status |
|------|---------------------|--------|
| `Set[T]` | Hash-based membership test | Implemented |
| `List[T]` | Linear scan for element equality; needs `T: Eq` | Implemented |
| `Map[K, V]` | Key presence check (equivalent to `contains_key`) | Implemented |

**Why a shared trait.** Containment is a universal set-theoretic predicate — "is X in this collection?" Every collection answers it, and generic code benefits: `fn has_item[C: Contains[T], T](c: C, item: T) -> Bool { c.contains(item) }`. The alternative — putting `contains` in each per-type trait — prevents writing functions generic over "any collection that can test membership." (Vote: 5-0.)

**Implementation status.** `Set`, `Map`, and `List` all implement `Contains`. `Map.contains(k)` is equivalent to `Map.contains_key(k)`. `List[T].contains` needs `T: Eq` and compares elements with `==` (§3.6 *Container Equality*) in a linear scan, so it applies to lists of `Eq` structs, enums and nested containers as well as primitives. An element type that does not implement `Eq` is a compile error (`UnresolvedMethod`).

**Note on `Str`.** `Str` exposes substring search as `"hello".contains("ell")` — semantically "contains substring," not "contains element." This routes through `StrOps` (§3.2.1); `Str` is not a meaningful `Contains[Char]` element-membership type. For character search use `someStr.contains("{c}")`.

##### The `ListOps` Trait

```blink
trait ListOps[T] {
    // Access
    fn get(self, index: Int) -> Option[T]
    fn last(self) -> Option[T]
    fn index_of(self, value: T) -> Option[Int]

    // Mutation (requires let mut)
    fn push(self, value: T)
    fn pop(self) -> Option[T]
    fn set(self, index: Int, value: T)
    fn insert(self, index: Int, value: T)
    fn remove(self, index: Int) -> T
    fn clear(self)

    // Transformation (returns new list)
    fn append(self, other: List[T]) -> List[T]
    fn slice(self, start: Int, end: Int) -> List[T]
    fn reverse(self) -> List[T]
    fn sort(self) -> List[T]
    fn sort_by(self, cmp: fn(T, T) -> Ordering ! _) -> List[T] ! _
}
```

The full `List[T]` method surface (14 methods from `ListOps` + 2 from `Sized` + 1 from `Contains`, plus `join` from `Joinable`):

| Method | Signature | Mutates | Notes |
|--------|-----------|---------|-------|
| `len` | `fn(self) -> Int` | no | Via `Sized` |
| `is_empty` | `fn(self) -> Bool` | no | Via `Sized` |
| `contains` | `fn(self, T) -> Bool` | no | Via `Contains`, linear scan by `==`; needs `T: Eq` (see §3.2.2 *The `Contains` Trait*) |
| `get` | `fn(self, Int) -> Option[T]` | no | Safe indexed access |
| `last` | `fn(self) -> Option[T]` | no | Last element |
| `index_of` | `fn(self, T) -> Option[Int]` | no | First occurrence |
| `push` | `fn(self, T)` | yes | Append to end |
| `pop` | `fn(self) -> Option[T]` | yes | Remove from end |
| `set` | `fn(self, Int, T)` | yes | Replace at index; panics when the index is out of bounds |
| `insert` | `fn(self, Int, T)` | yes | Insert at index, shift right |
| `remove` | `fn(self, Int) -> T` | yes | Remove at index, shift left |
| `clear` | `fn(self)` | yes | Reset to empty, retains capacity |
| `append` | `fn(self, List[T]) -> List[T]` | no | Concatenate, returns new list |
| `slice` | `fn(self, Int, Int) -> List[T]` | no | Sub-list `[start, end)`, returns new list |
| `join` | `fn(self, Str) -> Str` | no | Join with a separator — `List[Str]` only, via `Joinable` (§3.2.1) |
| `reverse` | `fn(self) -> List[T]` | no | Reversed copy |
| `sort` | `fn(self) -> List[T]` | no | Stable sorted copy (requires `T: Ord`) |
| `sort_by` | `fn(self, fn(T, T) -> Ordering ! _) -> List[T] ! _` | no | Stable sorted copy by a comparator (no bound on `T`) |

```blink
let mut items = [3, 1, 4, 1, 5]
items.push(9)                        // [3, 1, 4, 1, 5, 9]
let last = items.pop()               // Some(9), items is [3, 1, 4, 1, 5]
let val = items.get(2)               // Some(4)
items.set(0, 99)                     // [99, 1, 4, 1, 5]
items.insert(1, 42)                  // [99, 42, 1, 4, 1, 5]
let removed = items.remove(1)        // 42, items is [99, 1, 4, 1, 5]

let sorted = items.sort()            // [1, 1, 4, 5, 99] — new list
let rev = items.reverse()            // [5, 1, 4, 1, 99] — new list
let combined = items.append([6, 7])  // [99, 1, 4, 1, 5, 6, 7] — new list

items.contains(4)                    // true — linear scan (§3.2.2)
items.index_of(1)                    // Some(1) — first occurrence
items.last()                         // Some(5)
items.clear()                        // items is now [], capacity retained
```

**Sorting.** `sort` and `sort_by` return a sorted copy. The receiver keeps its order. Both sorts are **stable**: elements that compare `Equal` keep their input order. There is no unstable sort. `sort` needs `T: Ord`. `sort_by` takes a comparator that returns `Ordering` (§3.6) and needs no bound on `T`. `xs.sort()` gives the same result as `xs.sort_by(fn(a, b) { a.cmp(b) })`.

```blink
type Person { name: Str, age: Int }

let people = [
    Person { name: "Bo", age: 30 },
    Person { name: "Al", age: 25 },
    Person { name: "Cy", age: 30 },
]
let by_age = people.sort_by(fn(a, b) { a.age.cmp(b.age) })
// Al 25, Bo 30, Cy 30: Bo and Cy compare Equal and keep their input order

let oldest_first = people.sort_by(fn(a, b) { b.age.cmp(a.age) })
// Bo 30, Cy 30, Al 25: swap the arguments to sort in descending order

let by_age_then_name = people.sort_by(fn(a, b) {
    match a.age.cmp(b.age) {
        Equal => a.name.cmp(b.name)
        other => other
    }
})
```

To sort in descending order, swap the comparator's arguments. Do not call `.reverse()` on the result: `reverse` also reverses the order of equal elements.

The comparator may have effects. `sort_by` carries them through `! _`, as `map` does (§4.15.2). The number and the order of comparator calls are not specified. If the comparator does not return (a panic, or an effect that does not resume), the receiver is unchanged. The comparator need only be a total preorder; *Ord laws* (§3.6) gives the rules and what happens when a comparator breaks them.

There is no `sorted` method: `sort` already returns a new list. A call to `.sorted()` is `UnresolvedMethod`, and its help line says so.

**Why `.get()` returns `Option[T]`.** Out-of-bounds access is a runtime error in most languages. Returning `Option[T]` forces the caller to handle the absence case — a read never panics on an index that is out of bounds, and there are no null pointer exceptions. A write through `set` panics on an index that is out of bounds. Use `??` for default values: `list.get(i) ?? 0`.

**Why 13 methods (vote: 3-2).** Systems and PLT argued for 8, excluding `insert`, `remove`, `index_of`, and `last` as O(n) operations better served by iterator methods. Web/Scripting, DevOps, and AI/ML argued these are bread-and-butter operations in every major language (Python `list`, JS `Array`, Java `ArrayList`), and their absence would cause every user to write the same helpers on day one. The expanded surface won on developer experience grounds — performance characteristics should be documented, not hidden.

##### The `MapOps` Trait

```blink
trait MapOps[K, V] {
    // Access
    fn get(self, key: K) -> Option[V]
    fn keys(self) -> List[K]
    fn values(self) -> List[V]
    fn entries(self) -> List[(K, V)]
    fn get_or_default(self, key: K, default: V) -> V

    // Mutation (requires let mut)
    fn insert(self, key: K, value: V)
    fn remove(self, key: K) -> Option[V]
    fn contains_key(self, key: K) -> Bool
    fn clear(self)
}
```

The full `Map[K, V]` method surface (9 methods from `MapOps` + 2 from `Sized` + 1 from `Contains`):

| Method | Signature | Mutates | Notes |
|--------|-----------|---------|-------|
| `len` | `fn(self) -> Int` | no | Via `Sized` |
| `is_empty` | `fn(self) -> Bool` | no | Via `Sized` |
| `contains` | `fn(self, K) -> Bool` | no | Via `Contains`, key presence — equivalent to `contains_key` (see §3.2.2 *The `Contains` Trait*) |
| `get` | `fn(self, K) -> Option[V]` | no | Lookup by key |
| `get_or_default` | `fn(self, K, V) -> V` | no | Lookup with fallback |
| `keys` | `fn(self) -> List[K]` | no | All keys (unspecified order) |
| `values` | `fn(self) -> List[V]` | no | All values (unspecified order) |
| `entries` | `fn(self) -> List[(K, V)]` | no | All key-value pairs |
| `contains_key` | `fn(self, K) -> Bool` | no | Key presence check |
| `insert` | `fn(self, K, V)` | yes | Insert or update |
| `remove` | `fn(self, K) -> Option[V]` | yes | Remove by key |
| `clear` | `fn(self)` | yes | Reset to empty, retains capacity |

```blink
let mut config = Map.new()
config.insert("host", "localhost")
config.insert("port", "8080")

let host = config.get("host")              // Some("localhost")
let timeout = config.get_or_default("timeout", "30")  // "30"
config.contains_key("port")                // true
config.contains("port")                    // true (Contains, same as contains_key)

let ks = config.keys()                     // ["host", "port"] (unspecified order)
let vs = config.values()                   // ["localhost", "8080"] (unspecified order)
let es = config.entries()                  // [("host", "localhost"), ("port", "8080")]

let removed = config.remove("port")        // Some("8080")
config.clear()                             // config is now empty, capacity retained
```

**Why `contains_key` when `Contains` exists.** `Contains[K]` on `Map[K, V]` checks key presence — identical to `contains_key`. Both exist because `contains` comes from the generic `Contains` trait (for generic code) and `contains_key` lives in `MapOps` (for map-specific code that reads more clearly). They have identical semantics; the compiler may optimize `contains` to `contains_key` internally.

**Why 9 methods (vote: 3-2).** Systems and PLT argued for 6, noting that `entries` duplicates `IntoIterator` (which yields `(K, V)` tuples) and `get_or_default` duplicates `get(k) ?? default`. Web/Scripting, DevOps, and AI/ML argued that `entries` is the standard "dump the map" operation every developer expects (Python's `dict.items()`, JS's `Map.entries()`), and `get_or_default` eliminates the most common map boilerplate pattern. Discoverability and training data representation won.

##### The `SetOps` Trait

```blink
trait SetOps[T] {
    // Mutation (requires let mut)
    fn insert(self, value: T) -> Bool
    fn remove(self, value: T) -> Bool

    // Set algebra
    fn union(self, other: Set[T]) -> Set[T]
}
```

The full `Set[T]` method surface (3 methods from `SetOps` + 2 from `Sized` + 1 from `Contains`):

| Method | Signature | Mutates | Notes |
|--------|-----------|---------|-------|
| `len` | `fn(self) -> Int` | no | Via `Sized` |
| `is_empty` | `fn(self) -> Bool` | no | Via `Sized` |
| `contains` | `fn(self, T) -> Bool` | no | Via `Contains`, hash lookup |
| `insert` | `fn(self, T) -> Bool` | yes | Returns `true` if new |
| `remove` | `fn(self, T) -> Bool` | yes | Returns `true` if present |
| `union` | `fn(self, Set[T]) -> Set[T]` | no | Returns new set |

```blink
let mut seen = Set.new()
seen.insert("Alice")                       // true (new)
seen.insert("Alice")                       // false (already present)
seen.contains("Alice")                     // true
seen.remove("Alice")                       // true (was present)

let a: Set[Int] = Set.new()
let b: Set[Int] = Set.new()
// ... insert elements ...
let combined = a.union(b)                  // all elements from both
```

**Why core 4 + remove/contains (vote: 3-2).** PLT and DevOps argued for full set algebra (7 methods including `intersection`, `difference`, `symmetric_difference`), noting that sets without set algebra are "just deduplicated lists." Systems, Web/Scripting, and AI/ML argued that `intersection`/`difference` appear rarely in application code and are expressible via iterator filter chains: `a.into_iter().filter(fn(x) { b.contains(x) }).collect()`. The minimal surface won on YAGNI grounds — set algebra can be added later via trait extension without breaking changes.

##### Trait Summary

These are the **built-in method-surface traits** — the traits that host the method API of the built-in types. Like every compiler-known trait, they are in the prelude (§10.6): the trait names are in scope without import, and method dispatch on a built-in receiver (`"x".len()`, `sb.write(...)`) is resolved intrinsically by the compiler to a direct call — it never consults whether the trait name is imported.

| Trait | Applies to | Methods | In prelude |
|-------|-----------|---------|------------|
| `Sized` | Str, List, Map, Set, Bytes, StringBuilder | `len`, `is_empty` | Yes |
| `Contains[T]` | Set, List, Map | `contains` (element/key membership) | Yes |
| `StrOps` | Str | string methods (`char_at`, `byte_at`, `contains`, `split`, `to_upper`, `trim`, `replace`, …) | Yes |
| `BytesOps` | Bytes | byte methods (`push`, `get`, `slice`, `to_str`, `to_hex`, `read_u32_be`, …) | Yes |
| `ListOps[T]` | List | 13 methods | Yes |
| `MapOps[K, V]` | Map | 9 methods | Yes |
| `SetOps[T]` | Set | 3 methods | Yes |
| `IntoIterator[T]` | List, Map, Set, Str, Range, Channel | `into_iter` | Yes (§3c.1) |
| `Joinable` | List[Str] | `join` | Yes (§3.2.1) |
| `StringBuildOps` | StringBuilder | `write`, `write_char`, `to_str`, `len`, `capacity`, `clear` | Yes |

> **`Contains` membership covers `Set`, `Map`, and `List`.** `Set.contains` is a hash lookup, `Map.contains` is key presence (identical to `contains_key`), and `List.contains` is a linear scan that compares elements with `==`, so it needs `T: Eq`. Substring search on `Str` (`"hello".contains("ell")`) is a separate operation hosted by `StrOps` (§3.2.1), not element membership. This table reflects what compiles today.

All built-in method-surface traits are in the prelude — no import required. This matches the rationale from §10.6: operators like `for` desugar through `IntoIterator`, method calls resolve through traits, and requiring imports for built-in collection methods would add ceremony with no information value.

**These traits are sealed.** Their implementations are compiler-provided for the built-in types listed above; user code may not implement them (`impl StrOps for MyType`) or redefine them (`trait StrOps { … }`). Both are compile errors — the trait names are reserved by the prelude (§10.6), and a user implementation would create a second meaning for a method the compiler dispatches intrinsically. To add string-like or collection-like behavior to your own type, define your own trait with a different name.

A sealed trait may still be named in a generic bound — e.g. `fn f[T: Sized](x: T) -> Int { x.len() }`. `Sized` spans several built-in types, so a bound on it is genuinely polymorphic. A bound on a single-implementor trait (`StrOps`, `BytesOps`, `StringBuildOps`) is legal but degenerate: it is satisfiable only by the one built-in type that implements it (e.g. `[T: StrOps]` admits only `Str`), so it carries no more abstraction than naming that type directly.

---

#### §3.2.3 Additional Standard Library Types

Beyond the built-in primitives (§3.2) and collections (§3.2.2), Blink's standard library provides typed value types for domains where raw primitives lose semantic meaning. Except for the types listed in §10.6 *Compiler-Known Type Names* (`Bytes`, `F32`), these types are not compiler-known and not in the prelude — they live in stdlib modules and require explicit import. The compiler's built-in effect handles reference these types for their operation signatures.

##### Instant and Duration (`std.time`, Tier 2)

`time.read()` returns `Instant` — an opaque, nanosecond-precision point in time. `time.sleep()` accepts `Duration` — a typed time span with named constructors that encode units.

```blink
import std.time.{Instant, Duration}

fn measure_latency() -> Duration ! Time.Read {
    let start = time.read()         // returns Instant
    do_work()
    start.elapsed()                 // returns Duration
}

fn retry_with_backoff(attempt: Int) ! Time.Sleep {
    let delay = Duration.ms(1000 * (2 ** attempt))
    time.sleep(delay)
}

fn format_log() -> Str ! Time.Read {
    let now = time.read()
    now.to_rfc3339()    // "2026-02-14T12:00:00Z"
}
```

**Instant** is an opaque struct (no public fields). Internal representation: `int64_t` nanoseconds since epoch. C codegen: `typedef struct { int64_t nanos; } blink_instant;` — same footprint as `Int`, but nominally typed.

| Method | Signature | Notes |
|--------|-----------|-------|
| `elapsed` | `fn(self) -> Duration ! Time.Read` | Time since this instant |
| `since` | `fn(self, other: Instant) -> Duration` | Duration between two instants |
| `add` | `fn(self, d: Duration) -> Instant` | Point in the future |
| `to_rfc3339` | `fn(self) -> Str` | RFC 3339 string in UTC, whole seconds only |
| `to_unix_ms` | `fn(self) -> Int` | Milliseconds since epoch |
| `to_unix_secs` | `fn(self) -> Int` | Seconds since epoch |

Instant implements: `Eq`, `Ord`, `Hash`, `Display`, `Clone`, `Debug`. Does NOT implement arithmetic traits (sealed to built-in numerics). Use `.since()` and `.add()` named methods.

Instant's `Display` writes RFC 9557 in UTC with a `Z` offset: `2026-02-14T12:00:00Z`. A zero fraction of a second is left out. Any other fraction is written without trailing zeros: `2026-02-14T12:00:00.5Z`, `2026-02-14T12:00:00.000000001Z`. An instant before the epoch rounds down to the earlier second: 500 ms before the epoch is `1969-12-31T23:59:59.5Z`. `to_rfc3339` does not change: it always drops the fraction.

**Duration** is a typed time span. Internal representation: `int64_t` nanoseconds. Named constructors enforce units at construction — no ambiguity between seconds and milliseconds.

| Constructor | Signature | Example |
|-------------|-----------|---------|
| `Duration.nanos` | `fn(Int) -> Duration` | `Duration.nanos(1000)` |
| `Duration.ms` | `fn(Int) -> Duration` | `Duration.ms(500)` |
| `Duration.seconds` | `fn(Int) -> Duration` | `Duration.seconds(5)` |
| `Duration.minutes` | `fn(Int) -> Duration` | `Duration.minutes(1)` |
| `Duration.hours` | `fn(Int) -> Duration` | `Duration.hours(24)` |

| Method | Signature | Notes |
|--------|-----------|-------|
| `to_ms` | `fn(self) -> Int` | Total milliseconds |
| `to_seconds` | `fn(self) -> Int` | Total seconds (truncated) |
| `to_nanos` | `fn(self) -> Int` | Total nanoseconds |
| `add` | `fn(self, Duration) -> Duration` | Sum of durations |
| `sub` | `fn(self, Duration) -> Duration` | Difference |
| `scale` | `fn(self, Int) -> Duration` | Multiply by scalar |
| `is_zero` | `fn(self) -> Bool` | Zero-length check |
| `to_iso8601` | `fn(self) -> Str` | ISO 8601 duration: `PT1H2M3.5S` |

Duration implements: `Eq`, `Ord`, `Display`, `Clone`, `Debug`. Arithmetic via named methods (`.add()`, `.scale()`), not operators.

Duration's `Display` writes the same text as Go's `time.Duration.String`. A duration of one second or more uses `h`, `m` and `s`, with a fraction of a second on `s`: `1h2m3.5s`, `1m30s`, `1m0s`, `1h0m0s`. Once a larger unit is written, each smaller unit is written too, as `0` if needed. A shorter duration uses the largest of `ms`, `µs` (U+00B5) and `ns` that fits: `500ms`, `1.5µs`, `1ns`. Zero is `0s`. A negative duration starts with `-`: `-1.5s`. A fraction never has trailing zeros.

`to_iso8601` writes `PT`, then each of `H`, `M` and `S` that is not zero: `PT1H2M3.5S`, `PT1M`, `PT0.5S`. Zero is `PT0S`. It never writes a `D` unit, so 48 hours is `PT48H`. A negative duration starts with `-`: `-PT1.5S`.

**Why Instant/Duration instead of raw Int.** Time points form an affine space over durations: `Instant - Instant → Duration`, `Instant + Duration → Instant`, but `Instant + Instant` is nonsensical. Raw `Int` allows all three operations — a type error that the type system should catch. Duration carries dimensional information; `Int` is dimensionless. `time.sleep(port_number)` type-checks with raw Int but is a bug. `time.sleep(Duration.seconds(5))` makes units explicit at every call site. (Panel vote: 5-0.)

**Why stdlib Tier 2, not prelude.** Instant and Duration require no special syntax, no special desugaring, and no special inference rules. They are nominal types with named methods. The effect system's `Time.Read` and `Time.Sleep` operations reference these types, creating a coupling between compiler effects and stdlib — resolved by pinning the type layout as part of the effect specification. Not every program uses time operations. (Panel vote: 5-0.)

**Wall-clock DateTime.** Calendar-aware datetime (year, month, day, timezone) lives in `std.time.DateTime`, constructed from an `Instant` via `DateTime.from(instant)`. Calendar decomposition carries unbounded complexity (timezones, DST, leap seconds) that belongs in stdlib, not built-in types.

##### Bytes (compiler-known, §10.6)

`Bytes` is a contiguous byte buffer — the binary counterpart to `Str`. Where `Str` guarantees UTF-8 validity, `Bytes` carries no encoding invariant.

```blink
fn read_binary(path: Str) -> Bytes ! FS.Read {
    fs.read_bytes(path)
}

fn compute_hash(data: Bytes) -> Bytes ! Crypto.Hash {
    crypto.hash("sha256", data)
}

fn encode(s: Str) -> Bytes {
    Bytes.from_str(s)           // UTF-8 bytes
}

fn decode(b: Bytes) -> Result[Str, ConversionError] {
    b.to_str()                  // validates UTF-8
}
```

C representation: `typedef struct { uint8_t* data; int64_t len; int64_t cap; } blink_bytes;` — contiguous, cache-friendly, FFI-compatible. This is fundamentally different from `List[U8]`, which is a GC-managed array with potential per-element boxing overhead.

| Method | Signature | Notes |
|--------|-----------|-------|
| `len` | `fn(self) -> Int` | Via `Sized` |
| `is_empty` | `fn(self) -> Bool` | Via `Sized` |
| `get` | `fn(self, Int) -> Option[U8]` | Byte at index |
| `slice` | `fn(self, Int, Int) -> Bytes` | Sub-buffer (copy) |
| `concat` | `fn(self, Bytes) -> Bytes` | Concatenation |
| `to_str` | `fn(self) -> Result[Str, ConversionError]` | UTF-8 decode |
| `to_hex` | `fn(self) -> Str` | Hex string |
| `to_list` | `fn(self) -> List[U8]` | Convert to list |
| `from_str` | `fn(Str) -> Bytes` | UTF-8 encode |
| `from_list` | `fn(List[U8]) -> Bytes` | From list |
| `zeroed` | `fn(Int) -> Bytes` | Pre-sized buffer with `len == n`, all zero |
| `read_u16_le` / `read_u16_be` | `fn(self, Int) -> Result[Int, Str]` | Decode 2-byte little/big-endian unsigned at offset |
| `read_u32_le` / `read_u32_be` | `fn(self, Int) -> Result[Int, Str]` | Decode 4-byte little/big-endian unsigned at offset |
| `read_i32_le` / `read_i32_be` | `fn(self, Int) -> Result[Int, Str]` | Decode 4-byte little/big-endian signed at offset |
| `read_i64_le` / `read_i64_be` | `fn(self, Int) -> Result[Int, Str]` | Decode 8-byte little/big-endian signed at offset |
| `set_i16_le` / `set_i16_be` | `fn(self, Int, Int) -> Result[(), Str]` | Write 2-byte signed at offset (in-place, bounds vs `len`) |
| `set_u16_le` / `set_u16_be` | `fn(self, Int, Int) -> Result[(), Str]` | Write 2-byte unsigned at offset (in-place, bounds vs `len`) |
| `set_i32_le` / `set_i32_be` | `fn(self, Int, Int) -> Result[(), Str]` | Write 4-byte signed at offset (in-place, bounds vs `len`) |
| `set_u32_le` / `set_u32_be` | `fn(self, Int, Int) -> Result[(), Str]` | Write 4-byte unsigned at offset (in-place, bounds vs `len`) |
| `set_i64_le` / `set_i64_be` | `fn(self, Int, Int) -> Result[(), Str]` | Write 8-byte signed at offset (in-place, bounds vs `len`) |
| `set_u64_le` / `set_u64_be` | `fn(self, Int, Int) -> Result[(), Str]` | Write 8-byte unsigned at offset (in-place, bounds vs `len`) |
| `with_ptr` | `fn[R](self, fn(Ptr[U8]) -> R ! _) -> R ! _` | Closure-scoped FFI pin; forwards the closure's effect row (see §9.1.3) |

The `set_*_le/be(off, v)` family is the symmetric counterpart of the existing `read_*_le/be(off)` family: it writes at a given offset, requires `off + width <= len` (returns `Err` otherwise — does not grow), and complements the append-only `write_*_le/be(v)` constructors. `set_*` and `write_*` are deliberately distinct verbs: `set` writes in-place at a known offset, `write` appends. (Panel decision: [`ffi-struct-construction`](../decisions/ffi-struct-construction.md), Q-α-bytes-offset-API.)

Bytes implements: `Sized`, `Eq`, `Clone`, `Debug`, `IntoIterator[U8]`.

**Why a separate type from `List[U8]`.** Memory layout is non-negotiable for I/O, FFI, and crypto. `List[U8]` makes no contiguous-memory guarantee — every FFI call would require copying to a C buffer. `memcpy` on contiguous `Bytes` is SIMD-optimized; iterating boxed `List[U8]` has pointer-chasing overhead per element. For a 1MB file read, this is 10-100x slower. (Panel vote: 5-0.)

**Why Tier 1, not prelude.** `Bytes` is needed by core effects (`FS.Read`, `Net.Connect`, `Crypto.Hash`) but not every program does binary I/O. Tier 1 means it ships with the compiler and is version-locked. The API surface should remain minimal in Tier 1; richer operations (base64, compression) belong in higher tiers. (Panel vote: 5-0.)

##### Numeric Extensions

**F32** (built-in, sized numeric family):

```blink
let x: F32 = F32.from(3.14)
let y: F32 = x.mul(F32.from(2.0))
let back: Float = y.to_float()     // widening via From, infallible
```

`F32` maps to C `float` (32-bit IEEE 754). It joins the existing sized numeric family (`I8`, `I16`, `I32`, `U8`, `U16`, `U32`, `U64`). Widening `F32 → Float` via `From` (infallible). Narrowing `Float → F32` via `TryFrom` (precision loss). F32 is relevant for GPU interop, ML inference weights, and memory-constrained numerical arrays. (Panel vote: 5-0.)

**Decimal** (`std.decimal`, Tier 2):

```blink
import std.decimal.Decimal

fn calculate_tax(price: Decimal, rate: Decimal) -> Decimal {
    price.mul(rate)
}

let price = Decimal.from_str("19.99")?
let tax_rate = Decimal.from_str("0.0825")?
let tax = calculate_tax(price, tax_rate)    // exact: "1.649175"
```

128-bit fixed-point representation. Covers financial use cases (38 digits of precision) without unbounded allocation. Arithmetic via named methods (`.add()`, `.sub()`, `.mul()`, `.div()`) — sealed arithmetic traits are not extended. `Decimal` implements `Eq`, `Ord`, `Display`, `Clone`. Construction: `Decimal.from_str(Str)`, `Decimal.from_int(Int)`, `Decimal.zero()`.

**BigInt** (`std.math`, Tier 2):

```blink
import std.math.BigInt

fn factorial(n: Int) -> BigInt {
    let mut result = BigInt.one()
    let mut i = 2
    while i <= n {
        result = result.mul(BigInt.from(i))
        i = i + 1
    }
    result
}
```

GC-managed arbitrary-precision integer. Arithmetic via named methods. `From[Int]` for widening. Needed for cryptography, combinatorics, and scientific computing. Not the default `Int` — Blink chose `Int = i64` for predictable C codegen performance. (Panel vote: 5-0.)

**Why sealed arithmetic is not extended.** The 4-1 sealed decision applies uniformly. `Decimal` and `BigInt` are library types with library implementations, not hardware-mapped primitives. If `Decimal` gets `+`, users rightfully ask why their `Money` newtype cannot. Named methods `.add()`, `.mul()` are usable and maintain the bright-line boundary. (Panel vote: 5-0.)

##### UUID (`std.uuid`, Tier 2)

```blink
import std.uuid.UUID

fn create_user(name: Str) -> User ! DB.Write, Rand {
    let id = UUID.random()      // requires ! Rand
    db.write("INSERT INTO users (id, name) VALUES ({id}, {name})")
    User { id: id, name: name }
}

fn lookup(raw_id: Str) -> Result[User, AppError] ! DB.Read {
    let id = UUID.parse(raw_id)?    // validates format
    db.read("SELECT * FROM users WHERE id = {id}")
}
```

C representation: `typedef struct { uint64_t hi; uint64_t lo; } blink_uuid;` — 16 bytes, two 64-bit words. Fast comparison (`memcmp` on 16 bytes vs 36-byte string), fast hashing (already well-distributed).

| Method | Signature | Notes |
|--------|-----------|-------|
| `random` | `fn() -> UUID ! Rand` | Random v4 UUID |
| `parse` | `fn(Str) -> Result[UUID, ConversionError]` | Parse canonical format |
| `to_str` | `fn(self) -> Str` | Canonical "8-4-4-4-12" |
| `to_bytes` | `fn(self) -> Bytes` | 16-byte binary |
| `is_nil` | `fn(self) -> Bool` | All zeros check |

UUID implements: `Eq`, `Ord`, `Hash`, `Display`, `Clone`, `Debug`, `Serialize`, `Deserialize`.

**Why a nominal type, not Str.** UUID is 128 bits, not 36 characters. The `Str` representation is lossy (2.25x memory, slower comparison, no binary form). A distinct type prevents confusion: `fn get_user(id: UUID)` is self-documenting; `fn get_user(id: Str)` is ambiguous. `UUID.parse()` validates once and carries the proof in the type. (Panel vote: 5-0.)

**Why `UUID.random()` requires `! Rand`.** UUID v4 generation needs entropy. This integrates naturally with the effect system — in tests, `with mock_rand(seed: 42) { UUID.random() }` gives deterministic UUIDs. Parsing is pure: `UUID.parse(str)` returns `Result[UUID, ConversionError]` with no effect. (Panel vote: 5-0.)

##### Type Classification Summary

| Type | Location | Tier | Prelude | Rationale |
|------|----------|------|---------|-----------|
| `Instant` | `std.time` | 2 | No | Effect return type, opaque, nanosecond precision |
| `Duration` | `std.time` | 2 | No | Effect parameter type, named constructors eliminate unit confusion |
| `Bytes` | `std.bytes` | 1 | No | Contiguous binary buffer for I/O, FFI, crypto |
| `F32` | built-in | — | Yes | Sized numeric alongside I8–U64, maps to C `float` |
| `Decimal` | `std.decimal` | 2 | No | 128-bit fixed-point for financial arithmetic |
| `BigInt` | `std.math` | 2 | No | Arbitrary-precision integer for crypto/scientific |
| `UUID` | `std.uuid` | 2 | No | 128-bit identity type, Rand effect integration |

##### Sized Integer Types

Blink provides a family of fixed-width integer types alongside the default `Int`. These are first-class nominal types -- not refinements of `Int`, not aliases, not newtypes. A `U8` has a fundamentally different *representation* than an `Int`: 8 bits instead of 64 bits. Refinement types constrain values; sized types constrain representation. Different widths have different overflow boundaries, different bitwise semantics, and different memory layouts.

**Type table:**

| Type | Width | Range | C Type | Signed |
|------|-------|-------|--------|--------|
| `I8` | 8-bit | -128 to 127 | `int8_t` | Yes |
| `I16` | 16-bit | -32,768 to 32,767 | `int16_t` | Yes |
| `I32` | 32-bit | -2,147,483,648 to 2,147,483,647 | `int32_t` | Yes |
| `Int` | 64-bit | -2^63 to 2^63-1 | `int64_t` | Yes |
| `U8` | 8-bit | 0 to 255 | `uint8_t` | No |
| `U16` | 16-bit | 0 to 65,535 | `uint16_t` | No |
| `U32` | 32-bit | 0 to 4,294,967,295 | `uint32_t` | No |
| `U64` | 64-bit | 0 to 2^64-1 | `uint64_t` | No |

All sized types map directly to their C equivalents for zero-cost FFI. No wrapper structs, no indirection -- `U8` *is* `uint8_t` in the generated C. (Panel vote: 5-0.)

**Why not just `Int` everywhere.** `Int` (64-bit) is the default and covers most use cases. Sized types exist for three reasons: (1) memory efficiency -- `[U8]` is 8x denser than `[Int]`, critical for buffers, images, and network protocols; (2) C FFI -- matching the exact width the foreign function expects; (3) domain semantics -- a byte is 0-255, not -2^63 to 2^63-1. Use `Int` unless you have a specific reason not to. (Panel vote: 3-1-1, Web dissented wanting refinement types, AI/ML dissented wanting FFI-only.)

**Overflow behavior:**

Arithmetic overflow is checked by default. An operation that exceeds the type's range panics at runtime with a descriptive message. The compiler also catches overflow in constant expressions at compile time.

```blink
let x: U8 = 255
let y = x + 1               // RUNTIME PANIC: U8 overflow in addition (255 + 1)

let bad: I8 = 127 + 1       // COMPILE ERROR: constant overflow in I8 (127 + 1 = 128, max 127)
```

For intentional modular arithmetic, use the explicit wrapping methods:

```blink
let x: U8 = 255
let y = x.wrapping_add(1)   // y == 0 (wraps around)

let a: I8 = 127
let b = a.wrapping_add(1)   // b == -128 (wraps around)
```

**Why checked by default.** Silent overflow is the source of countless security vulnerabilities and subtle bugs. The wrapping methods make modular arithmetic opt-in and visible -- the intent is clear in the source code. Performance-sensitive inner loops can use wrapping methods where profiling shows the checks matter; everywhere else, the safety net catches bugs. (Panel vote: 3-2, Web/AI dissented wanting panic-always with no wrapping escape hatch.)

**Bitwise operations:**

Bitwise operators are available on all integer types (`Int`, `I8`, `I16`, `I32`, `U8`, `U16`, `U32`, `U64`). They are *not* available on `Float`, `Bool`, or `Str`.

| Expression | Desugars to | Trait | Description |
|------------|-------------|-------|-------------|
| `a & b` | `BitAnd.bit_and(a, b)` | `BitAnd` | Bitwise AND |
| `a \| b` | `BitOr.bit_or(a, b)` | `BitOr` | Bitwise OR |
| `a ^ b` | `BitXor.bit_xor(a, b)` | `BitXor` | Bitwise XOR |
| `a << b` | `Shl.shl(a, b)` | `Shl` | Left shift |
| `a >> b` | `Shr.shr(a, b)` | `Shr` | Right shift (arithmetic for signed, logical for unsigned) |
| `~a` | `BitNot.bit_not(a)` | `BitNot` | Bitwise NOT (complement) |

Bitwise traits are **sealed** to integer types, following the same pattern as arithmetic traits (§3.6). Shift amounts are `U32` (matching the underlying C shift semantics). Shifting by more than the bit width is a runtime panic.

```blink
trait BitAnd {
    fn bit_and(self, other: Self) -> Self
}

trait BitOr {
    fn bit_or(self, other: Self) -> Self
}

trait BitXor {
    fn bit_xor(self, other: Self) -> Self
}

trait Shl {
    fn shl(self, amount: U32) -> Self
}

trait Shr {
    fn shr(self, amount: U32) -> Self
}

trait BitNot {
    fn bit_not(self) -> Self
}
```

**Precedence:** Bitwise operators bind *lower* than comparison operators. This means `x & mask == 0` parses as `x & (mask == 0)`, which is almost certainly not what you intended. The compiler emits a warning (W0700) and requires explicit parentheses:

```blink
// WARNING: bitwise operator has lower precedence than comparison
let bad = flags & 0x0F == 0          // W0700: add parentheses

let good = (flags & 0x0F) == 0       // OK: intent is clear
```

**Why lower precedence than comparison.** This matches C's precedence table. Changing it would surprise every programmer with C/C++/Java experience and create a different class of bugs. Instead, the mandatory-parentheses warning eliminates the footgun while preserving familiar precedence. (Panel vote: 4-1, AI/ML dissented wanting named methods instead of operators.)

**Standard methods on sized integer types:**

All sized integer types support the following methods (in addition to arithmetic trait impls and conversion methods documented in §3c.3):

| Method | Signature | Notes |
|--------|-----------|-------|
| `abs` | `fn(self) -> Self` | Panics on min value for signed types (e.g., `I8(-128).abs()`). No-op on unsigned types |
| `min` | `fn(self, Self) -> Self` | Returns the smaller of two values |
| `max` | `fn(self, Self) -> Self` | Returns the larger of two values |
| `pow` | `fn(self, U32) -> Self` | Integer exponentiation. Panics on overflow |
| `clamp` | `fn(self, Self, Self) -> Self` | Clamp value to `[min, max]` range. Panics if `min > max` |

Wrapping arithmetic methods for intentional modular arithmetic:

| Method | Signature | Notes |
|--------|-----------|-------|
| `wrapping_add` | `fn(self, Self) -> Self` | Modular addition (wraps on overflow) |
| `wrapping_sub` | `fn(self, Self) -> Self` | Modular subtraction (wraps on underflow) |
| `wrapping_mul` | `fn(self, Self) -> Self` | Modular multiplication (wraps on overflow) |

```blink
let x: I32 = -42
let a = x.abs()              // 42
let b = x.min(0)             // -42
let c = x.max(0)             // 0
let d = x.clamp(-10, 10)     // -10
let e: U8 = 2
let f = e.pow(8)             // RUNTIME PANIC: U8 overflow (256 > 255)
let g = e.pow(7)             // 128
```

**Literal syntax:**

Integer literals have no suffix syntax. The type is determined by context: the expected type from a variable annotation, function parameter, or surrounding expression. When no context is available, an unadorned integer literal defaults to `Int`.

```blink
let byte: U8 = 255       // OK: 255 fits in U8
let bad: U8 = 300        // COMPILE ERROR: 300 exceeds U8 range (0..255)
let x = 42               // type is Int (default)

fn process(val: U8) { }
process(200)              // OK: literal 200 fits in U8
process(300)              // COMPILE ERROR: 300 exceeds U8 range
```

The compiler performs range checking on all constant expressions assigned to sized types. This catches errors at compile time rather than runtime. Non-constant expressions are checked at runtime via the overflow machinery described above.

**Why no literal suffixes.** Languages like Rust use `42u8`, `100i32`, etc. Blink omits suffixes because (1) function signatures already provide the context -- `fn process(val: U8)` makes `process(200)` unambiguous; (2) suffixes add visual noise to a language designed for readability; (3) the rare case where disambiguation is needed can use a type annotation: `let x: U8 = 42`. (Panel vote: 4-1, Systems expert preferred constructor syntax `U8(42)`.)

**Why not refinement types.** Sized integers are not `Int @where(self >= 0 && self <= 255)`. Refinement types constrain values but not representation -- a refined `Int` still occupies 64 bits. `U8` occupies 8 bits, enables efficient array layouts (`[U8]` is 8x denser than `[Int]`), and maps directly to C `uint8_t` for zero-cost FFI. The overflow and bitwise semantics also differ by width: `U8(255) + U8(1)` wraps to 0 (with `wrapping_add`), while a refined `Int` would just be 256. These are fundamentally different kinds of types serving different purposes. (Panel vote: 5-0.)

---

### 3.3 Type Inference

Blink uses Hindley-Milner type inference with the following rule: **annotations are required on function signatures, inferred everywhere else.**

```blink
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

```blink
// Forward: type of map's output inferred from closure body
let lengths = names.map(fn(n) { n.len() })   // List[Int]

// Backward: closure param type inferred from map's expected input
let upper = names.map(fn(n) { n.to_upper() }) // n is Str, inferred from List[Str]
```

**Keyword labels are not part of the type.** Declaration-site keyword parameters (see [2.13](02_syntax.md#213-declaration-site-keyword-arguments)) use `--` to separate positional from keyword params, but labels are call-site enforcement only. The function type ignores labels entirely:

```blink
// This function:
fn transfer(amount: Int, -- from: Account, to: Account) -> Result[Transaction, BankError]

// Has type: fn(Int, Account, Account) -> Result[Transaction, BankError]
// The -- and labels are invisible to the type system
```

This means closures, trait implementations, and higher-order functions work without label awareness:

```blink
// A closure assigned to a variable with compatible type
let f: fn(Int, Account, Account) -> Result[Transaction, BankError] = transfer

// Passing as a higher-order function argument
fn apply(op: fn(Int, Account, Account) -> Result[Transaction, BankError]) { ... }
apply(transfer)  // works — labels are erased at the type level
```

Direct call sites enforce labels (the compiler errors if you call `transfer` without `from:` and `to:`). But when a function is passed as a value, labels are erased. This keeps the type system simple — 99% of same-typed-param bugs occur at direct call sites, where labels are enforced.

**Numeric literals.** Unadorned integer literals default to `Int`. Unadorned float literals default to `Float`. If context demands a specific size (e.g., assigning to a `U8` field), the literal is checked against the target type's range at compile time:

```blink
let port: U16 = 8080        // OK: 8080 fits in U16
let bad: U8 = 300           // COMPILE ERROR: 300 exceeds U8 range (0..255)
```

#### Divergence and Body Completeness

A block that stands in a **value position** — a function body, an `if`/`match` arm
whose result is used, the tail of a `with`-block, or a block bound by `let` — has a
*tail type*: the type of the value control produces when it reaches the end of the
block. A value-returning `fn(...) -> R` type-checks only when its body's tail type is a
subtype of `R`. This is the ordinary subtyping check; there is no loop-specific rule.

Two facts about the type lattice decide every case:

- **`Never` is a subtype of every type.** `Never` (§2.20) is the bottom type — it has no
  values, so a construct of type `Never` never produces one and vacuously satisfies any
  expected type.
- **`()` is a subtype only of `()`.** The unit type is ordinary; a block whose tail type
  is `()` satisfies `-> ()` (equivalently `-> Void`) and nothing else.

A construct has type `Never` when it **provably diverges** — control cannot leave it
normally:

- `panic(msg)` and `env.exit(code)` (§2.20, §4.6) — untracked divergence.
- A bare `return`, `?`-propagation on the error path, `break`, or `continue` in tail
  position — control leaves the block by another edge.
- A `loop { }` that **no `break` targets** — it runs forever. The search for a targeting
  `break` does not descend into a nested loop (whose `break` targets the inner loop) or
  into a closure body. See §2.11.
- An `if`/`match` all of whose reachable arms diverge.

Every other construct can complete normally and carries its ordinary type. In particular
a `while` or `for` loop always has type `()` — the condition may be false on entry, or
the iterable may be empty or exhaust — and an `if` with no `else` has type `()`. When `R`
is not `()`, such a tail fails the subtype check.

```blink
// Rejected: the loop can finish (n may be <= 0 on entry, or fall through),
// so the body's tail type is (), which is not a subtype of Int.
fn first_hit(n: Int) -> Int {
    while n > 0 {
        if lucky(n) { return 7 }
    }
}   // error[MissingReturn] (E0311)

// Accepted: the tail diverges, so its type is Never <: Int.
fn serve() -> Int {
    loop {
        let req = next_request()
        if req.is_stop() { return req.code() }
    }
}

// Accepted: a trailing value makes the tail an Int.
fn scan(n: Int) -> Int {
    let mut i = n
    while i > 0 {
        if lucky(i) { return i }
        i = i - 1
    }
    0
}

// Accepted: the honest type when "not found" is a real outcome.
fn find(n: Int) -> Option[Int] {
    let mut i = n
    while i > 0 {
        if lucky(i) { return Some(i) }
        i = i - 1
    }
    None
}
```

**Why reject rather than complete the value for you.** The alternatives — accept the
program and return a zero value, or accept it and panic at run time — both make the
program *do something* the author never wrote. That is the pattern already forbidden for
inference (§3.4, *Under-Determined Types*): the compiler does not fabricate a value for a
slot the program left open. Falling off the end of a value-returning function is the same
open slot, reached along a control path instead of through an inference variable, and it
gets the same answer — a compile-time error, not a fabricated value. See
[DECISIONS.md](../DECISIONS.md).

`Never` here is not inference choosing the bottom type for an open slot — which §3.4
forbids. A loop's type is fixed by its own structure (whether a `break` targets it),
decided before it is compared against `R`; the check never *picks* `Never` to make a
program type-check.

**error[MissingReturn] (E0311).** Fires when control can reach the end of a block that
must produce a value of type `R` along a path that yields `()` — a fall-through function
body, a value-position `if` without `else`, an arm that completes where a value was
required. The primary line names the cause ("this function can finish without returning a
value of type `R`"); the tail kind (loop, `if`-without-`else`, …) is carried as
diagnostic data, not as a separate error code, so an editor or agent can offer the right
repair from one stable key. The repair named first is the one that always compiles: add a
trailing `return <value>` (or a tail value expression), or — when "no value" is a real
outcome — change the return type to `Option[R]` (§3.7) and yield `None`. A diverging tail
(`panic(...)`, or a `loop` no `break` targets) is accepted and needs no repair. This
satisfies the Diagnostic Discipline of §3.1: every rejection names a repair that exists.

---

### 3.4 Algebraic Data Types

Blink uses a single `type` keyword for all user-defined types. The compiler distinguishes sum types (variants) from product types (fields) by structure, not by separate keywords.

#### Product Types (Structs)

A type with only named fields is a product type:

```blink
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

```blink
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

In Blink, `type` is `type`. If it has variants, it's a sum. If it has fields, it's a product. If it has variants where some carry fields, it's a sum of products. The compiler doesn't care about the taxonomy; it cares about the structure.

#### Variant Construction

Enum variants are constructed by naming the variant and supplying its payload. A variant may be constructed in either of two forms:

```blink
type QueryError {
    NotFound { msg: Str }
    Timeout { ms: Int }
}

let a = QueryError.NotFound { msg: "id 0" }   // qualified
let b = NotFound { msg: "id 0" }              // bare — resolves to QueryError.NotFound
```

The bare form (`NotFound { msg: "x" }`) and the qualified form (`QueryError.NotFound { msg: "x" }`) are equivalent: they construct the same value and emit identical code. Bare construction mirrors the forms that already exist elsewhere in the language — bare tuple-style construction (`Leaf(1)`, see *Generic Types* below) and bare struct-style patterns (`NotFound { msg }` in a `match` arm, §3.5). Construction and pattern matching are duals; both accept the bare and qualified spellings.

**Resolution order.** At a bare struct-style construction site `Name { ... }`, the compiler resolves `Name` in this order:

1. **Qualified** — if the site is already written `Enum.Variant { ... }`, that names the variant directly.
2. **Hint-directed** — the expected type at the site (a binding annotation, a function return type, a function parameter type, or a `Result`/`Option` carrier such as `Ok`/`Err`/`Some`) names an enum that has a variant `Name`. The hint is consulted *first* among the unqualified rules so that resolution is determined locally: a distant enum declaration can never retroactively change which variant a site resolves to.
3. **Global-unique** — if no hint applies, `Name` resolves to the one enum variant of that name across the whole program. If the name is not globally unique, see the ambiguity rule below.

Resolution is entirely compile-time; there is no runtime dispatch.

**Name collisions** fall into two distinct kinds:

- **A struct name equal to an enum variant name** is a **compile error at declaration time** (`error[NameCollision]`), reported over the whole program (so it catches collisions across modules). A name is either a product type or a sum injection — never both. This rule is narrowly scoped to the struct-vs-variant case only; it does not require all constructible names to be globally unique.

- **The same variant name in two different enums is legal.** For example, `Pending` may appear in both `JobState` and `NetState`. Such a name is resolved by the hint:

  ```blink
  type JobState { Pending, Running, Done }
  type NetState { Pending, Connected }

  let s: JobState = Pending   // hint (binding annotation) selects JobState.Pending
  ```

  When a bare construction of a name shared across enums has no hint to resolve it, that specific site is a **compile error** (`error[AmbiguousConstruction]`) requiring qualification:

  ```blink
  fn f() {
      let x = Pending   // error[AmbiguousConstruction]: 'Pending' is a variant of both
                        // JobState and NetState; qualify as JobState.Pending or NetState.Pending
  }
  ```

No path ever silently picks a winner: every collision is either a declaration-time error (struct vs variant) or a use-site error requiring qualification (variant vs variant with no hint).

A bare struct-style construction with a payload in carrier position resolves through the carrier's expected type:

```blink
fn lookup(id: Int) -> Result[Str, QueryError] {
    if id == 0 {
        return Err(NotFound { msg: "id 0" })   // Err's carrier expects QueryError
    }
    Ok("found")
}
```

The `..` rest sigil is a pattern-only construct (§3.5); it has no meaning in construction, where every field must be supplied (or defaulted, see *Product Types*).

`blink fmt` does not canonicalize between the bare and qualified forms in either direction — a formatter must never change which entity a name resolves to.

#### Enums Are Nominally Distinct from `Int`

An enum is a distinct type from `Int`. Although a variant lowers to an integer tag at runtime, the tag's representation does not make the enum *assignable* to `Int`, exactly as a `U8`'s 8-bit representation does not make it assignable to `Int` (see *Sized Integer Types*). An enum value is not assignable to an `Int` target, and an `Int` is not assignable to an enum target — at let-bindings, function arguments, and function returns:

```blink
type State { Idle, Running, Done }

fn step(s: State) -> State { s }

fn main() {
    let n: Int = State.Idle   // error[TypeError]: declared type Int but got State
    let bad = step(2)         // error[TypeError]: argument 1 expects State, got Int
    let s: State = 7          // error[TypeError]: declared type State but got Int
}
```

This is what makes a single-payload enum a real newtype: `type Errno { Errno(Int) }` used as the error arm of `Result[Int, Errno]` cannot be confused with a plain `Int` count, which is the entire reason to prefer it over `Result[Int, Int]`.

**Comparison is unaffected.** The comparison operators (`==`, `!=`, `<`, `<=`, `>`, `>=`) remain defined between an enum and `Int`: they compare the shared tag representation and yield `Bool`. This is a representation-level operation, not an assignability claim, so it does not weaken the nominal distinctness above.

```blink
let s = State.Running
if s == State.Running { }   // OK — comparison, not assignment
```

**Crossing the boundary is explicit.** To obtain the tag as an `Int`, use `Enum.to_int()` (total). To go the other way, `Enum.from_int(n) -> Option[Enum]` is fallible — an arbitrary `Int` may not be a valid tag — so it returns `Option`. There is no implicit coercion and no cast operator.

> Pattern matching an `Int` scrutinee against enum-variant patterns (`match someInt { State.Idle => ... }`) is the pattern-side dual of the assignability rule and is likewise ill-typed. Enforcement of that case is staged behind the compiler's internal `kind: Int → NodeKind` representation migration; the rule itself holds from this decision.

#### Str-Backed Enums

An enum can give each variant a string literal. The literal is the variant's backing value:

```blink
type Status {
    Open = "open"
    InProgress = "in_progress"
    Done = "done"
}

let s = Status.InProgress
let wire = s.to_str()                  // "in_progress"
let back = Status.from_str("done")     // Some(Status.Done)
let bad = Status.from_str("Done")      // None: the match is case-sensitive
```

**Declaration rules.** Each rule below is a compile error when a declaration breaks it:

- Every variant has a backing literal, or no variant has one. An enum that mixes the two is an error.
- A variant with a backing literal has no payload. `Custom(code: Int) = "custom"` is an error.
- The backing value is a plain string literal: no interpolation and no `const` name. This is `error[InvalidStringBackedEnum]` (E1201).
- No two variants have the same backing literal. The error should point at both variants.

**Conversion methods.** The compiler gives every Str-backed enum two methods:

| Method | Signature | Result |
|--------|-----------|--------|
| `to_str` | `fn to_str(self) -> Str` | The variant's backing literal. Total |
| `from_str` | `fn from_str(s: Str) -> Option[Self]` | `Some(v)` for the variant whose literal equals `s`, else `None` |

`from_str` compares bytes. The match is exact and case-sensitive, and it applies no Unicode normalization: `"café"` in NFC and `"café"` in NFD are different inputs, and at most one of them matches.

**Laws.** For every Str-backed enum `T`, every `x: T` and every `s: Str`:

1. `T.from_str(x.to_str()) == Some(x)`.
2. `from_str` never returns a variant whose literal differs from its input:

   ```blink
   match T.from_str(s) {
       Some(v) => v.to_str() == s   // always true
       None => true
   }
   ```

3. With `@derive(Deserialize)`, `T.from_json(JsonValue.Str(s))` is `Ok(v)` exactly when `T.from_str(s) == Some(v)` (§3.6.2).

**`from_str` returns `Option` on purpose.** This is the same choice as `Enum.from_int(n) -> Option[Enum]` above: an arbitrary `Str` may not name a variant, and there is only one way to fail, so there is nothing for an error value to say. It is not a `Result` in the way of Rust's `FromStr`.

**Display.** A Str-backed enum has no `Display` unless it declares one. With `@derive(Display)`, its output equals `to_str()`: `"{Status.InProgress}"` is `in_progress`, not `InProgress` (§3.6.1 *Sum Type Codegen*).

**JSON.** With `@derive(Serialize)`, a Str-backed enum serializes as a JSON string of its backing literal, not as a tagged object (§3.6.2 *Type Mapping*).

**Backing literals rename variants, not fields.** A backing literal gives an enum value its wire spelling. It is not a precedent for renaming struct fields in JSON: `@json("name")` field renaming stays out of v1 (§3.6.2).

> **Reference implementation:** `to_str` does not allocate; it returns a static string. `from_str` compares lengths, then bytes, and does not allocate or hash. This note describes one compiler. It is not a language rule, and other implementations may differ.

#### `Bool` Is Distinct from `Int`

`Bool` and `Int` are different types. A `Bool` is not assignable to an `Int` target, and an `Int` is not assignable to a `Bool` target. This holds at let-bindings, assignments, function arguments, function returns, struct fields and collection elements, and in both directions:

```blink
fn takes_bool(b: Bool) -> Bool { b }

fn main() {
    let a: Bool = 1           // error[TypeError]: declared type Bool but got Int
    let n: Int = true         // error[TypeError]: declared type Int but got Bool
    let r = takes_bool(7)     // error[TypeError]: argument 1 expects Bool, got Int
}
```

**Conditions take only `Bool`.** The condition of `if` and `while`, a match guard, and each operand of `&&`, `||` and `!` must have type `Bool`. An `Int` is never a condition, and an integer literal is no exception: `if n { }`, `while 1 { }` and `!n` on an `Int` are compile errors (§2.19 *No Truthiness*).

**`Bool` does not compare with `Int`.** `==` and `!=` between a `Bool` and an `Int` are compile errors. This differs from enums, which compare with `Int` through their tag. An enum has a documented numeric identity (`Enum.to_int()`), and a `Bool` has none: `==` is `Eq.eq(self, other: Self)`, and a `Bool` never reads as 0 or 1 (§3.6 *Arithmetic Traits*). Write the test directly:

| Rejected | Write |
|---|---|
| `flag != 0`, `flag == 1` | `flag` |
| `flag == 0`, `flag != 1` | `!flag` |
| `if n { }` where `n: Int` | `if n != 0 { }` |
| `let b: Bool = 1` / `0` | `true` / `false` |
| `let n: Int = flag` | `let n = if flag { 1 } else { 0 }` |

A function that answers a yes/no question returns `Bool`, not `Int`: `fn is_digit(c: Int) -> Bool`, never `-> Int` with 0 and 1.

**Patterns follow the same rule.** A literal pattern must have the scrutinee's type. An integer pattern against a `Bool` scrutinee, or a `true`/`false` pattern against an `Int` scrutinee, is a compile error:

```blink
fn main() {
    let b = true
    let s = match b {
        1 => "one"        // error[TypeError]: pattern of type Int cannot match a value of type Bool
        _ => "other"
    }
}
```

An exhaustive `match` on a `Bool` needs only `true` and `false` arms (§3.5 *Exhaustiveness*). This is sound because every `Bool` value is `true` or `false`.

**No conversion methods.** `Bool` has no `to_int()`, and `Int` has no `to_bool()`; there is no `Bool.from_int`. The conversions are one expression each: `if b { 1 } else { 0 }` for `Bool` to `Int`, and `n != 0` for `Int` to `Bool`. There is no cast operator.

**Every `Bool` is `true` or `false`.** No program can make a `Bool` hold any other value. The type rules above close the paths inside Blink, and values that come in from C are made canonical at the FFI boundary (§9.1.3 *`Bool` at the FFI boundary*).

**Diagnostics.** Each rejected form reports `error[TypeError]` (E0300) with the caret under the offending operand, the fixed note `Blink has no truthiness`, and a machine-applicable `help:` that gives the rewrite from the table above:

```
error[TypeError]: if condition must be Bool, got Int
  --> a.bl:3:8
  |
3 |     if n { io.println("x") }
  |        ^ Int
  note: Blink has no truthiness
  help: compare explicitly: `n != 0`
```

A call to `.to_int()` on a `Bool` reports the missing method, with a `help:` line that gives `if b { 1 } else { 0 }`.

#### Generic Types

Type parameters use square brackets:

```blink
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

```blink
let pair = Pair { first: "hello", second: 42 }  // Pair[Str, Int]
let tree = Branch(Leaf(1), Leaf(2))              // Tree[Int]
```

#### Explicit Type Application

A generic function's type parameters may also be supplied **explicitly**, in square brackets written directly after the callee:

```blink
let forecast = json.decode[Forecast](body)?
let buf = alloc_ptr[U8]()
```

Explicit type application is a third supply mechanism alongside inference at a construction site and a type annotation on the binding. All three name the same type parameters and differ only in where the program writes them. Brackets in this position can never be confused with indexing or comparison — Blink has no index operator, and element access is `.get()` (§2.6).

**No erasure.** Every type parameter a declaration binds belongs to that declaration's monomorphization key, whether or not a parameter type or the return type mentions it. `probe[Int]()` and `probe[Str]()` are distinct instantiations and compile to distinct functions. A type parameter is never dropped from the key, never defaulted, and never collapsed onto another instantiation's — the guarantee §3.4 *Under-Determined Types* makes at a binding, applied to a declaration.

**When brackets are mandatory.** A type parameter is **supplied by the signature** when it occurs in a parameter type or in the return type: inference solves it from the call's arguments, or from the annotation on the binding the call feeds. A type parameter the signature does not supply has no other source, so every call must write it:

```blink
fn probe[T]() -> Int { 1 }       // T occurs in no parameter type and not in the return type

fn main() {
    let n = probe[Int]()         // OK -- the call supplies T
    let m = probe()              // error[CannotInferType]: type parameter `T` of `probe` has
                                 //   no source -- it is bound by the declaration but supplied
                                 //   by neither a parameter nor the return type
}
```

Whether a type parameter is supplied by the signature is decidable from the signature alone — no call site, and no function body, is consulted.

**A generic function named as a value.** A generic function's name may be written wherever a function value is expected, with no arguments and no brackets. The expected type is a source of type information exactly as a parameter type is, and the declaration's binders are solved by unifying its type against it:

```blink
fn identity[T](x: T) -> T { x }

fn apply(f: fn(Int) -> Int, n: Int) -> Int { f(n) }

fn main() {
    let r = apply(identity, 3)            // OK -- the parameter type `fn(Int) -> Int` fixes T = Int
    let g: fn(Str) -> Str = identity      // OK -- the annotation fixes T = Str
    io.println("{r}")
    io.println(g("ok"))
}
```

No separate rule governs the bare form. A reference whose binders the expected type does not fix is under-determined, and that is `error[CannotInferType]` (E0301) like every other under-determination — reported at the reference, where its repair attaches:

```blink
fn identity[T](x: T) -> T { x }

fn main() {
    let f = identity                      // error[CannotInferType] -- intentional-error example
                                          //   `T` is unbound at this reference and nothing supplies it
                                          // help: annotate the binding:
                                          //   `let f: fn(Int) -> Int = identity`
}
```

The first `help:` names the **annotation**, not a bracket form. Brackets on a callee supply type arguments to a *call*; this position has no call, so there is nothing for them to attach to. Writing them anyway — `let f = identity[Int]` — is `error[TypeArgsWithoutCall]` (E0314, §3.4 *Postfix Brackets That Are Not a Type Application*).

*Rationale (normative).* The rule this replaces refused `apply(identity, 3)` and accepted `let f = identity` followed by `apply(f, 3)` — the same value, one line apart, separated by where it was written rather than by anything about its type. A rule that distinguishes a term from its own η-expansion is a syntactic filter standing in a typing rule's position, and its prescribed repair — wrapping the name in a closure — lowers to the identical allocation and the identical indirect call. It refused one spelling of a machine-identical program, it was defeated by one `let`, and it has been deleted rather than restated.

**Where the error is reported.** `error[CannotInferType]` (E0301) is reported **where its repair attaches**. For an under-determined *binding* that is the `let` (§3.4 *Under-Determined Types*). For a type parameter with no source it is the call's type-argument position, because that is where the brackets go — including when the call stands alone as a statement and there is no binding to annotate:

```blink
fn main() {
    probe()                      // error[CannotInferType] reported at the call, not at a binding
}
```

**Two repairs, in a fixed order.** When a call is under-determined *and* the declaration binds a type parameter nothing supplies, two repairs exist: write the type argument at this call, or delete the binder from the declaration. The order in which a diagnostic offers them is **normative, not presentational** — a tool, or a reader, applies the first `help:` and stops.

**Deleting the binder is offered first** whenever the lint below reports it as removable. Both repairs make the program compile, but only the deletion discharges both diagnostics at once, and it discharges them for every other call of that declaration rather than for this one. Offering the type argument first would make the path of least resistance "write `[Int]` and leave a meaningless binder in place" — one keystroke in an editor, applied unread, at every call site of a declaration whose signature is the actual defect. Where the binder is *not* removable, the type argument is the only repair and is offered alone.

**All type-argument lists obey one discipline.** Wherever a program may write a type expression, it may write its type arguments explicitly, and the rules are the same in every position — a callee, a parameter type, a return type, a field type, a nested type argument, or a struct-literal head:

```blink
let r = Registry[User] { entries: [] }      // OK -- brackets on a struct-literal head
```

- **All or none.** A type-argument list supplies every one of the declaration's type parameters or none of them. There is no partial application and no placeholder for "infer this one."
- **Arity is exact.** Supplying the wrong count is `error[TypeArgArity]` (E0303) in every position — at a callee exactly as in a type position (§3.4 *Kind-Correctness*) — not a prompt to infer the remainder.
- **Bounds are checked against the arguments as written.** An explicit type argument satisfies the binder's bounds or the call is rejected; explicitness never bypasses a bound. The error is E0306, or E0523 for a `Display` bound (§3.6 *Trait Bounds*).

**A redundant type-argument list is permitted and carries no diagnostic.** When inference would have reached the same answer, writing the arguments anyway is neither an error nor a warning nor a lint — exactly as `let x: Int = 1` is permitted where `let x = 1` would do. A diagnostic here would be non-monotonic: adding an annotation elsewhere in the program could make an untouched line retroactively noisy.

**Phantom type parameters are legal in user code.** Because no binder is erased, a type parameter mentioned by no field is supplied by the type annotation and keeps its instantiations distinct:

```blink
type Meters {}
type Feet {}

type Tagged[C] {
    source: Str
}

let m: Tagged[Meters] = Tagged { source: "12.5" }
let f: Tagged[Feet] = Tagged { source: "41.0" }     // a distinct type from Tagged[Meters]
```

`Tagged[Meters]` and `Tagged[Feet]` are different types, and neither is assignable to the other. This pattern is not reserved to compiler-known types — it is the same mechanism the compiler-known `Template[C]` uses (§3b.5), available to user code on the same terms.

**Lint: a type parameter that occurs nowhere.** `W0604 UnusedTypeParamBinder` fires when **the type parameter occurs nowhere in the declaration or its body.** That is the whole gate, and it is decided by inspection of one declaration:

```blink
fn tag[T]() -> Int { 1 }                       // W0604 -- T occurs nowhere; the binder is removable

fn assert_serializable[T: Serialize]() { }     // no warning -- T occurs in its own bound
fn probe[T]() -> Int { let xs: List[T] = [] xs.len() }  // no warning -- T occurs in the body
fn cell[T]() -> Ptr[T] { alloc_ptr[T]() }      // no warning -- T occurs in the return type
```

A **bound is an occurrence.** `T: Serialize` partitions the instantiations into well-typed and ill-typed, so the binder decides which programs exist: `assert_serializable[NotSerializable]()` is rejected and `assert_serializable[User]()` is accepted. Deleting that binder would accept both. A declaration whose only mention of `T` is its bound is a compile-time assertion, and warning that `T` is unused would assert something untrue about the code.

*Rationale (normative).* The gate is drawn where it is because **W0604 fires exactly when deleting the binder is a safe edit** — when the declaration still compiles afterwards and means the same thing, so the fix the lint prescribes cannot break working code. Occurrence is what makes that property checkable: any mention of `T` anywhere in the declaration or its body is a way the declaration could depend on `T`, and a mention in a body form the language has not been given yet is still a mention. Stated as a predicate the counterfactual needs machinery the gate does not — the comparison is between programs modulo the mechanical erasure of type-argument lists at call sites, since deleting any binder turns `tag[Int]()` into an arity error on its own. The occurrence clause is the rule; safety of the prescribed edit is the reason the rule is drawn there. If a future type position lets a body depend on `T` without naming it, this rationale is the criterion for amending the clause.

W0604 is a warning and not an error: a binder nothing supplies is still callable, because the brackets reach it. Nothing about such a declaration is unsound — it is merely a declaration whose every call must carry a type argument that changes nothing, and the lint is what keeps those out of a codebase.

#### Kind-Correctness of Type Expressions

Every type expression written in a **type position** — a parameter type, a return type, a field type, a binding annotation, or a nested type argument — must denote a complete type. A type constructor of arity *n* denotes a complete type only when it is applied to exactly *n* type arguments. Writing a constructor with the wrong number of arguments — including **none** — does not denote a type; it is `error[TypeArgArity]` (E0303).

```blink
fn relay(src: Channel, dst: Channel) { }   // error[TypeArgArity]: `Channel` takes 1 type argument, 0 were given
```

`Channel` is a type constructor of arity 1, so `Channel` standing alone is not a type — it is a constructor with its argument missing. The same rule rejects a partially applied constructor and an over-applied one:

```blink
fn f(m: Map[Str]) { }          // error[TypeArgArity]: `Map` takes 2 type arguments, 1 was given
fn g(xs: List[Int, Str]) { }   // error[TypeArgArity]: `List` takes 1 type argument, 2 were given
```

This is one rule, not three cases. Under-application (too few arguments, of which the bare name is the *k* = 0 extreme) and over-application (too many) are the same failure — a type expression whose applied arity does not match the constructor's declared arity — and carry the same code in both directions.

**The rule is uniform across builtins and user generics.** `Channel`, `List`, `Map`, `Set`, and `Option` are type constructors on exactly the terms a user's `type Registry[T]` is; none is a special case. A bare `Registry` in a type position is `error[TypeArgArity]` for the same reason a bare `Channel` is.

```blink
type Registry[T] {
    entries: List[T]
}

fn lookup(r: Registry) { }      // error[TypeArgArity]: `Registry` takes 1 type argument, 0 were given
```

**A callee and a struct-literal head are term positions, and the rule covers every list written there.** In a type position an absent list counts as zero arguments. In a term position an absent list is not an application: inference supplies the binders, and a binder it cannot fix is `error[CannotInferType]` (E0301, §3.4 *Explicit Type Application*). That is why `Pair { first: "hi", second: 1 }` and `probe()` are judged by inference and not by this rule. A list that *is* written in a term position must supply exactly as many arguments as the declaration binds, and the wrong count is `error[TypeArgArity]` (E0303) — the same code as in a type position, because it is the same failure:

- At a callee, the count is the called declaration's **own** binders. The binders of an impl come from the receiver, since impl selection admits no type-argument list (§3.6).
- A non-generic declaration binds zero, and so does a local value. A list on either is always the wrong count.

```blink
fn decode[T](s: Str) -> T { ... }
fn plain(n: Int) -> Int { n }

type Registry[T] {
    entries: List[T]
}

fn main() {
    let a = decode[Forecast, Str](body)          // error[TypeArgArity]: `decode` takes 1 type argument, 2 were given
    let b = plain[Int](3)                        // error[TypeArgArity]: `plain` takes 0 type arguments, 1 was given
                                                 // help: delete the list: `plain(3)`
    let r = Registry[User, Int] { entries: [] }  // error[TypeArgArity]: `Registry` takes 1 type argument, 2 were given
    let p = Pair { first: "hi", second: 1 }      // OK -- term position, no list, inference supplies the binders
}
```

**A rejected list supplies nothing.** When E0303 fires on a list, the list binds none of the declaration's type parameters. Neither `error[CannotInferType]` (E0301) nor `error[TraitBoundNotSatisfied]` (E0306) is reported for the binders of that call: an ill-arity list has no argument *i* for binder *i*, so "unbound" and "bound not met" have no meaning there. Fixing the count is the converging repair (§3.1 rule 3).

**E0303 is decided when the head resolves, from the declaration's binder count and the written list alone.** For a type expression or a path callee, that is at name resolution, before inference runs. For a method callee (`x.decode[A, B]()`), the receiver's type selects the method, so the count is checked once that type is known. In neither case is inference of the call's own arguments consulted. A constructor's arity is a property of its declaration alone, so the mismatch is known the moment the head is resolved. This is what distinguishes E0303 from `error[CannotInferType]` (E0301, §3.4 *Under-Determined Types*): E0301 fires when inference *terminates* with a type variable no use ever fixed; E0303 fires when a type expression was never well-formed to begin with. A bare `Channel` annotation is not an unsolved variable that a later use might constrain — it names a slot the program neglected to fill, and no downstream use can fill an argument the annotation did not open. The two never co-fire on the same type expression: a well-formed constructor application may leave a variable under-determined (E0301), but an ill-formed one is rejected first (E0303).

**The repair depends on the case, and the first `help:` offered is normative** (§3.4 *Explicit Type Application*):

| Case | Example | Repair offered first |
| --- | --- | --- |
| Bare constructor, a type parameter is in scope | `fn relay[T](src: Channel)` | apply the parameter in scope — `Channel[T]` |
| Bare constructor, no type parameter is in scope | `fn relay(src: Channel)` | declare a binder on the enclosing declaration and apply it — `fn relay[T](src: Channel[T], dst: Channel[T])` |
| Under-applied (some, too few) | `Map[Str]` | supply the missing argument — `Map[Str, V]` |
| Over-applied (too many) | `List[Int, Str]` | remove the extra argument — `List[Int]` |
| Term position, and inference fixes every binder once the list is gone | `pair[Int, Str, Bool](1, "a")` | delete the list — `pair(1, "a")` |
| Term position, and inference does not fix every binder | `probe[Int, Str]()` | write the list with the exact count, naming the binders — `probe[T]()` |

The binder-declaring repair is offered **only** when the constructor is bare *and* no type parameter already in scope can fill the slot. Where a parameter is in scope, applying it is the whole repair; suggesting a fresh binder there would shadow an available one.

In a term position, deleting the list is offered first whenever inference then fixes every binder. That edit always compiles, because a redundant list is never required (§3.4 *Explicit Type Application*), and it needs no guess about which of the written arguments the author meant. The exact-count list is offered only when deletion would leave a binder with no source.

**Trait references are not type expressions and are outside this rule.** A trait name in a bound (`T: Ord`) or an impl header does not occupy a type position — it constrains a type parameter rather than denoting a type (§3.6). Its arguments are governed by `error[TraitArgArity]` (E0910), the impl-header specialization of the same arity principle. So a generic signature that mentions a trait only in a bound is well-formed under E0303:

```blink
fn sort[T: Ord](xs: List[T]) -> List[T] { xs }   // OK -- `Ord` is a bound, not a type expression;
                                                  //       `List[T]` is a complete type
```

One principle — a constructor is applied to its exact arity — surfaces as E0303 in type and term positions and E0910 in trait positions, because the repair and the surrounding grammar differ between the two.

#### Postfix Brackets That Are Not a Type Application

Blink has no index operator (§2.6). A postfix `[...]` after an expression is legal only as a type-argument list written directly before `(` (a call) or `{` (a struct-literal head). Every other bracket suffix is an error. The **contents of the brackets** decide which error, checked in this order:

1. **Any item is a value:** `error[NoIndexOperator]` (E0313), whether or not a call follows.
2. **Every item is a type:** the brackets are a type-argument list, and their count is checked against the head (§3.4 *Kind-Correctness*). The wrong count is `error[TypeArgArity]` (E0303). A value head, or a non-generic declaration, binds zero.
3. **The list is well-formed, and no `(` or `{` follows:** `error[TypeArgsWithoutCall]` (E0314).

An item is a **type** when it parses as a type expression and every name in it resolves to a type or a type parameter. Every other item is a **value**: a literal, a local, a constant, or any other expression. Name resolution decides this in every case, so the code never depends on the receiver's type. `xs[i]` and `self.items[i]` get the same code at the same stage.

E0303 is checked before E0314 because deleting the list discharges both. A value head with type contents, such as `xs[Int]`, is therefore E0303 (`xs` takes 0 type arguments), and its repair, deleting the list, exists.

**NoIndexOperator (E0313).** Element access is a method call. The first `help:` depends on the receiver's type: `.get()` where the type has it, and a field access for a tuple:

```blink
fn main() {
    let xs = [10, 20, 30]
    let pair = (1, "a")
    let mut ages: Map[Str, Int] = Map()
    ages.insert("bob", 41)

    let x = xs[1]          // error[NoIndexOperator]: Blink has no index operator
                           // help: `xs.get(1)` returns `Option[Int]`
    let t = pair[0]        // error[NoIndexOperator]: Blink has no index operator
                           // help: a tuple field is `pair.0`
    let a = ages["bob"]    // error[NoIndexOperator]: Blink has no index operator
                           // help: `ages.get("bob")` returns `Option[Int]`
}
```

When a call follows the brackets, as in `handlers[0](req)`, the element is an `Option` that must be unwrapped before the call. No single edit is correct in every enclosing function: `?` compiles only in a function that returns `Option`, and `.unwrap()` panics when the element is missing. So the diagnostic carries a `note:` saying that `handlers.get(0)` returns an `Option` to `match` on before calling, and it offers no machine-applicable fix. A receiver whose type has neither `.get()` nor tuple fields also gets no machine-applicable fix (§3.1 rule 1).

**A store through brackets.** An index is not an assignment place (§2.22 *Assignment places*), so `xs[i] = v` and `xs[i] op= v` are E0313 by the same rule. The first `help:` names one write method, chosen from the receiver's type: `.set(i, v)` for a `List` or `Bytes`, and `.insert(k, v)` for a `Map`. It never names `.insert` for a `List`. `List.insert` compiles, but it shifts the elements and changes the length, so it changes the meaning of the program. When the receiver's type is not known, the help names both methods, each with its receiver type, and offers no machine-applicable fix.

For `xs[i] op= v` on a `List` or `Bytes`, the machine-applicable fix is `xs.set(i, xs.get(i).unwrap() op v)`. The fix writes `i` twice, so it keeps the meaning only when `i` is a literal, a local binding or a `const`, as name resolution sees it. A module-level `let mut` or a call does not qualify. The help says that the fix panics when `i` is out of bounds, because `set` does. For any other index, for a `Map` receiver, and for a nested place, the diagnostic carries a `note:` to bind the index with `let` first, and offers no machine-applicable fix.

```blink
fn main() {
    let mut xs = [10, 20, 30]
    let mut ages: Map[Str, Int] = Map()
    let i = 1

    xs[0] = 5              // error[NoIndexOperator]: Blink has no index operator
                           // help: `xs.set(0, 5)`
    ages["bob"] = 41       // error[NoIndexOperator]: Blink has no index operator
                           // help: `ages.insert("bob", 41)`
    xs[i] += 1             // error[NoIndexOperator]: Blink has no index operator
                           // help: `xs.set(i, xs.get(i).unwrap() + 1)` (panics when `i` is out of bounds)
}
```

**TypeArgsWithoutCall (E0314).** A type-argument list supplies type arguments to a call or a literal. With neither after it, nothing uses it. E0301 does not apply, because the brackets bind the type parameters. The first `help:` depends on the context:

| Context | Example | First `help:` |
| --- | --- | --- |
| An expected type fixes the same type arguments that were written | `apply(identity[Int], 3)` | remove the brackets — `apply(identity, 3)` |
| A binding, and no expected type | `let f = identity[Int]` | annotate and remove the brackets, as one edit — `let f: fn(Int) -> Int = identity` |
| An expected type fixes different type arguments | `apply(identity[Str], 3)` | none that can be applied by machine; the diagnostic names both types |

Removing the brackets is offered first only when the expected type gives the same arguments that were written. Where they differ, removing the brackets would still compile, but it would silently change the instantiation the program asked for. That is a change of meaning, not a repair. The conflict between the written and the expected type is the real defect, and only the author can say which one is correct.

A binding whose initializer is E0313 or E0314 gets no further E0300 or E0301 from that initializer (§3.1 rule 3).

#### Under-Determined Types

Inference at a binding is a two-state judgment: either every type variable is resolved to a concrete type, or the ones that cannot be resolved are **reported**. There is no third state — Blink never *defaults* an unresolved type variable to a concrete type, and there is no user-facing "unknown" or "any" type that inference can fall into.

When Hindley-Milner inference finishes a binding with a type variable still unbound — not fixed by an annotation and not fixed by any later use — that binding is `error[CannotInferType]`. The repair for a binding is a type annotation.

> **The repair is whatever reaches the open type variable, and E0301 is reported where that repair attaches.** For the bindings below, an annotation on the `let` reaches it, so the diagnostic points at the `let`. For a type parameter that the callee's signature does not supply, the annotation cannot reach it and the repair is an explicit type-argument list at the call — so the diagnostic points there instead, including when the call is a bare statement with no binding at all (§3.4 *Explicit Type Application*). One rule, one diagnostic, reported at the edit that fixes it.

```blink
fn f() {
    let x = []          // error[CannotInferType]: element type of `x` is undetermined
    let n = None        // error[CannotInferType]: the inner type of `n` is undetermined
    let m = Map()       // error[CannotInferType]: key/value types of `m` are undetermined
}
```

The fix in every case is to annotate the binding:

```blink
fn f() {
    let x: List[Int] = []
    let n: Int? = None
    let m: Map[Str, Int] = Map()
}
```

This is one rule applied uniformly: an empty `[]`, a bare `None`, an empty `Map()`/`Set()`, and an under-constrained generic construction are not four cases — they are one case, "inference left a type variable unbound," reported by one diagnostic.

**Later use still determines the type — there is no error when it does.** The error fires only when inference *terminates* with the variable unbound, so a binding constrained by a subsequent use is inferred normally with no annotation:

```blink
fn g() {
    let mut xs = List.new()   // element type inferred from the push below
    xs.push(1)                // xs : List[Int] — no annotation, no error
}
```

A use that does *not* constrain the type parameter does not rescue the binding. `.len()`, `.is_empty()`, and `.is_none()` observe the container, not its element, so a binding used only through them stays under-determined and is an error:

```blink
fn h() {
    let x = []      // error[CannotInferType]: element type is undetermined
    x.len()         // observes the list, not the element type — does not constrain `x`
}
```

There is no exception for a value that is "never used in a way that would expose the missing type." Whether the under-determined value is later observed is a whole-function property; making the binding's legality depend on it would break locality of reasoning (§1) — you could no longer tell whether `let x = []` is valid without reading the rest of the body, and a later edit adding `x.push(y)` could retroactively change the binding's status. The binding is judged at the binding, once.

**Under-determination flows through construction.** An under-constrained generic construction is the same error, reported at the binding, with the enclosing constructor's parameters named:

```blink
type GKV[K, V] {
    m: Map[K, V]
}

fn f() {
    let b = GKV { m: Map() }   // error[CannotInferType]: type parameters K, V of `GKV`
                               //   are undetermined — no use constrains them
    // fix: let b: GKV[Int, Str] = GKV { m: Map() }
}
```

The diagnostic points at the binding — where the annotation fix applies — and carries a secondary span at the empty constructor (`Map()` / `[]`) explaining why the parameter is open (`error[CannotInferType]`, E0301 — see [ERROR_CATALOG.md](../ERROR_CATALOG.md)). This mirrors the `AmbiguousConstruction` rule (§3.4): no path ever silently picks a winner.

**A type parameter named by no field is reported too.** The rule is the same one: every type parameter the declaration binds must be determined, and a phantom parameter is determined only by an annotation on the binding or by a type-argument list on the literal head. So `let w = W { n: 1 }` for `type W[T] { n: Int }` is `error[CannotInferType]` on `T` — repaired by `let w: W[Int] = W { n: 1 }` or by `let w = W[Int] { n: 1 }`. This follows from *no erasure* (§3.4 *Explicit Type Application*): a phantom parameter is part of the type's identity, so leaving it open leaves the type open. It is also the Hindley-Milner discipline Blink's ancestry (§1.3) shares with OCaml, SML, Haskell, and Rust — an unconstrained type variable is resolved by unification or reported, never assigned a type the program did not ask for.

> There is no surface `unknown` / `any` / `?` type in Blink. The concept "a type not yet known" exists only inside the compiler as a transient inference state; it is never a type a program can name, hold, or produce. A value's type is always fully determined or the program does not type-check.

**The judgment is a property of the type, not of the syntactic position.** An unsolved type variable is `error[CannotInferType]` wherever a value's type is finalized — a `let`, a tuple element, a match scrutinee, a struct field, a call argument, a return — never only at a `let`. The same value receives the same answer in every position: a position that silently completes an open variable is a bug, not a second rule.

This governs a sum-type constructor that pins some of its type parameters and leaves the rest open. `Ok(3)` has type `Result[Int, E]` — the argument pins the `Ok` payload, but nothing constrains the error type `E`, so `E` is an unsolved variable exactly as the inner type of a bare `None` is. It is `error[CannotInferType]`, and it is that error in every position, including inside a tuple that is the scrutinee of a `match`:

```blink
fn f() -> Int {
    match (Ok(3), 9) {            // error[CannotInferType]: the error type of `Ok(3)` is undetermined
        (a, n) => {                //   — nothing pins the `Err` type of this `Result`
            match a {
                Ok(v) => v + n
                Err(e) => n        // binds `e` but discards it — observes the container, not `E`
            }
        }
    }
}
```

The `Err(e) => n` arm does not rescue the scrutinee. It binds `e` but discards it without observing its type, so — like `.len()` on a list of undetermined element type — it constrains the container's shape, not the open parameter. A fully-determined variant is unaffected: `match (Some(5), 9)` compiles, because `Some(5)` pins `Option`'s only parameter and leaves nothing open.

**What pins `E`.** The error type of a `Result` is determined by any one of four things: a type annotation on the binding (`let r: Result[Int, Str] = Ok(3)`), a `?` in a context whose error type it must match, a `match` arm that reads the `Err` payload's type, or an enclosing return type that names it. When none is present, `E` is under-determined and the constructor must state it. The repair is an explicit type-argument list on the constructor — `Ok[Int, Str](3)` (§3.4 *Explicit Type Application*) — placed where the open parameter lives. As with every under-determined binding, E0301 is reported where its repair attaches (§3.4, as amended): the `let` when a binding dominates the value, otherwise the constructor's type-argument position, with the dual-span blame at the open constructor.

There is no "an Ok-only value proves the error type is uninhabited, so resolve it to a bottom type" rule. Inferring a type the program never wrote — whether the erased unit `Void` or a bottom `Never` — into an unconstrained slot is the same unlicensed substitution the two-state model forbids; a `Never` error type is reached only when a program *writes* `Result[Int, Never]`, never chosen by inference for an open slot. The I0001 backstop that catches a variable reaching monomorphization keys on the variable's *kind*, never on the concrete tag it would have been given, so a genuine `Result[Void, Str]` or an explicitly-written `Result[Int, Never]` is unaffected.

#### Type Name Resolution (normative)

A type name resolves **once**, at name resolution, to **one declaration identity**. Every later phase — inference, trait resolution, monomorphization, code generation — works on that identity and never looks the name up again.

- A name that resolves to no declaration is `error[UnknownType]` (E0507).
- Only an explicit `[T]` binder on the enclosing declaration creates a type variable. A type name is never turned into a type variable because it is unresolved, special, or compiler-known.
- An `effect` name used as a type resolves to the nominal type that the effect declaration gives. That type has no values and is written only as a type argument (§3b.5 *The Context Parameter `C`*).
- A `type` declaration the compiler accepts is a declaration that code in the same module can name, construct, and use as a type. There is no declaration that is accepted and then unusable.

```blink
type Handler {    // warning[W1010]: shadows compiler-known type Handler
    n: Int
}

fn use_it(h: Handler) -> Int { h.n }

fn main() {
    io.println("{use_it(5)}")    // error[TypeError]: expected `Handler (main)`, found `Int`
}
```

```
error[TypeError]: mismatched types
 --> main.bl:6:25
  |
6 |     io.println("{use_it(5)}")
  |                         ^ expected `Handler (main)`, found `Int`
  |
  = note: `Handler` here is `type Handler` (main.bl:1), which shadows the compiler-known `Handler[E]` (blink.core)
  = help: to name the compiler-known type, import it under another name: import blink.core.{Handler as EffectHandler}
```

`Handler` in `use_it` is the module's own struct (it shadows the compiler-known `Handler[E]`, §10.6 *Shadowing Rules*), so `use_it(5)` is an ordinary type mismatch. It is never a type variable that accepts `5`.

**Hygiene.** Syntax that the compiler expands, and types the compiler inserts, refer to the compiler-known type **by identity**, never by the name that is in scope at the use site. This covers `T?` and `??` (`Option`), `?` (`Result`/`Option`), `for` (`IntoIterator`/`Iterator`), `..`/`..=` (`Range`), `==`/`<` and the other operators (their traits), `with` (`Handler`, `Closeable`), `async.spawn` (`Handle`), `Template[C]` coercion, literals (`Int`, `Float`, `Str`, `Char`, `Bool`), and every other desugaring in this spec. A module that declares its own `Option` still gets the builtin `Option` from `x?`:

```blink
type Option {
    label: Str
}                                 // warning[W1010]: shadows compiler-known type `Option`

fn first(xs: List[Int]) -> Int? {  // `Int?` is the builtin Option[Int], by identity
    let x = xs.get(0)?
    Some(x)
}
```

**Identity, not spelling, selects behavior.** No compiler phase may choose behavior — a runtime representation, a method surface, a desugaring, a C name — from a type's name string. It chooses it from the declaration identity alone. Two types with the same name and different identities are different types everywhere.

The set of names that may not be declared at all, and the rule for a declaration that takes any other compiler-known name, are in §10.6 *Shadowing Rules*.

#### Recursive Types

Types can reference themselves. The compiler handles the indirection, and no program can see it: a recursive field is a value like any other, and a copy of it follows §3.6.1 *Clone Semantics*.

```blink
type Tree {
    Leaf
    Node(value: Int, children: List[Tree])
    Named(labels: Map[Str, Tree])
}
```

The JSON data model is the compiler-known `JsonValue` (§3.6.2), not a user declaration.

---

### 3.5 Pattern Matching

Pattern matching is Blink's primary mechanism for branching on data shape. Every `match` expression must exhaustively cover all possible values of the scrutinee type. The compiler rejects non-exhaustive matches at compile time.

```blink
match value {
    pattern => expression
    pattern if guard => expression
}
```

#### Pattern Grammar

```
pattern       ::= or_pattern

or_pattern    ::= bind_pattern ( "|" bind_pattern )*

bind_pattern  ::= IDENT "as" atomic_pattern
               |  atomic_pattern

atomic_pattern ::= "_"                                        // wildcard
               |   IDENT                                      // variable binding
               |   INT_LIT                                    // integer literal
               |   FLOAT_LIT                                  // float literal
               |   BOOL_LIT                                   // true | false
               |   STR_LIT                                    // string literal
               |   INT_LIT ".." INT_LIT                       // exclusive range
               |   INT_LIT "..=" INT_LIT                      // inclusive range
               |   CHAR_LIT ".." CHAR_LIT                     // char exclusive range
               |   CHAR_LIT "..=" CHAR_LIT                    // char inclusive range
               |   TYPE_NAME                                  // unit variant
               |   TYPE_NAME "." IDENT                        // qualified unit variant
               |   TYPE_NAME "(" pattern_list ")"             // constructor
               |   TYPE_NAME "." IDENT "(" pattern_list ")"   // qualified constructor
               |   "(" pattern_list ")"                       // tuple
               |   TYPE_NAME "{" field_patterns "}"           // struct

pattern_list  ::= pattern ( "," pattern )*

field_patterns ::= field_pattern ( "," field_pattern )* ( "," ".." )?
               |   ".."

field_pattern  ::= MEMBER_NAME ":" pattern                    // field with sub-pattern; a keyword is legal (§2.23)
               |   IDENT                                      // field punning; never a keyword

guard         ::= "if" expression

match_arm     ::= pattern guard? "=>" expression
```

#### Pattern Forms

**Wildcard.** `_` matches any value and discards it.

**Variable binding.** An identifier binds the matched value to a new variable in the arm body.

**Literal.** Integer, float, boolean, and string literals match by value equality.

```blink
match status {
    200 => "ok"
    404 => "not found"
    _ => "other"
}
```

**Constructor.** Matches enum variants, destructuring their fields.

```blink
fn area(shape: Shape) -> Float {
    match shape {
        Circle(r) => 3.14159 * r * r
        Rectangle(w, h) => w * h
        Point => 0.0
    }
}
```

**Nested patterns.** Patterns compose — any sub-position accepts a full pattern.

```blink
fn describe(val: JsonValue) -> Str {
    match val {
        JsonValue.Null => "null"
        JsonValue.Bool(true) => "yes"
        JsonValue.Bool(false) => "no"
        JsonValue.Int(n) => "int: {n}"
        JsonValue.Float(f) => "float: {f}"
        JsonValue.Str(s) => "string: {s}"
        JsonValue.Array(items) => "array of {items.len()}"
        JsonValue.Object(fields) => "object with {fields.len()} fields"
    }
}
```

**Tuple patterns.** Match and destructure tuple values (see also §3.8).

```blink
fn classify(pair: (Int, Int)) -> Str {
    match pair {
        (0, 0) => "origin"
        (0, _) => "y-axis"
        (_, 0) => "x-axis"
        _ => "other"
    }
}
```

**List patterns.** Match list values by length and element values. Square brackets in pattern position.

```blink
fn dispatch(command_path: List[Str]) -> Str {
    match command_path {
        [] => "help"
        ["build"] => "building"
        ["daemon", "start"] => "starting daemon"
        ["daemon", "stop"] => "stopping daemon"
        ["daemon", sub] => "unknown daemon subcommand: {sub}"
        [cmd] => "unknown command: {cmd}"
        _ => "too many segments"
    }
}
```

Rest wildcard `..` matches zero or more trailing elements (tail position only, no binding):

```blink
fn process(tokens: List[Str]) -> Str {
    match tokens {
        [] => "done"
        [first, ..] => "processing: {first}"
    }
}
```

`..` in list patterns cannot bind a variable. Use `.slice()` or loops for tail access. (Rest binding deferred — would require O(n) copy or a slice type.)

The `..` rest sigil is unified across struct and list patterns — same concept ("remaining elements I didn't name"), same sigil. See §2.16 for the full spread/rest operator specification, including the construction-side dual (`..source` in struct literals).

**Exhaustiveness**: list patterns are length-checked. The compiler tracks which concrete lengths are covered. A wildcard `_` or `..` arm is **always required** — lists are unbounded, so finite length patterns cannot be exhaustive. `[]` + `[_, ..]` IS exhaustive (covers empty + non-empty).

```
error[NonExhaustiveMatch]: non-exhaustive match on List[Str]
 --> cli.bl:15:5
  |
15|     match path {
  |     ^^^^^ patterns cover lengths 0, 1, 2 — no catch-all for longer lists
  = help: add a `_` wildcard arm or `[_, _, ..] rest pattern
```

**Struct patterns.** Match struct types by field values. Type name is required (nominal matching). Field punning binds a field to a variable of the same name, so a field named by a keyword cannot use the short form: write `Event { type: t, .. }` (§2.23 *Members and Bindings*). `..` is required when not all fields are listed.

```blink
match user {
    User { name: "admin", .. } => grant_admin_access()
    User { name, age, .. } if age >= 18 => allow_access(name)
    User { name, .. } => deny_access(name)
}

// Nested: struct inside enum
match response {
    Ok(User { name, email, .. }) => send_welcome(name, email)
    Err(ApiError.NotFound(msg)) => log_error(msg)
    Err(_) => log_error("unknown error")
}

// Field punning: { name } is short for { name: name }
match config {
    ServerConfig { port, debug: true, .. } => start_debug(port)
    ServerConfig { port, .. } => start(port)
}
```

#### OR-Patterns

Multiple patterns separated by `|` share a single arm body. All alternatives must bind the same set of variable names with the same types. `|` binds looser than constructor application, tighter than `=>`. No nested OR inside constructors — use `Some(1) | Some(2)`, not `Some(1 | 2)`.

```blink
match status_code {
    200 | 201 | 204 => handle_success(response)
    400 | 422 => handle_client_error(response)
    500 | 502 | 503 => handle_server_error(response)
    code => handle_unknown(code)
}

match event {
    Event.Click(x, y) | Event.Touch(x, y) => handle_input(x, y)
    Event.Quit => break
    _ => {}
}
```

```
error[InconsistentPatternBindings]: inconsistent bindings in OR-pattern
 --> input.bl:5:5
  |
5 |     Some(x) | None => use(x)
  |     ^^^^^^^   ^^^^ `None` does not bind `x`
  |
  = help: all alternatives must bind the same variables
```

#### Range Patterns

Integer and character ranges match contiguous value sets. Both `..` (exclusive end) and `..=` (inclusive end) are supported, consistent with range expression syntax (§2.9). Bounds must be const expressions (§2.21). Only `Int`, sized integers (`I8`, `U8`, etc.), and `Char` types are allowed — not `Float` or `Str`. The exhaustiveness checker tracks covered ranges.

```blink
fn classify_http(code: Int) -> Str {
    match code {
        100..=199 => "informational"
        200..=299 => "success"
        300..=399 => "redirect"
        400..=499 => "client error"
        500..=599 => "server error"
        _ => "unknown"
    }
}

// Combined with OR-patterns
match score {
    0 => "zero"
    1..=59 => "failing"
    60..=100 => "passing"
    _ => "invalid"
}
```

#### Pattern Binding (`as`)

Bind the matched value to a name while simultaneously destructuring it. The bound name gets the pre-destructured value (scrutinee type). Syntax: `name as pattern`.

```blink
match get_config() {
    config as ServerConfig { port, .. } if port > 1024 =>
        start_with_config(config, port)
    _ => start_with_defaults()
}

match event {
    original as Event.Request(req) => {
        log_event(original)
        handle(req)
    }
    _ => {}
}
```

#### Guard Clauses

A guard is a boolean expression attached to a match arm with `if`. The arm matches only when the pattern matches AND the guard evaluates to `true`. Guards must be pure expressions — no effect operations in guard position. Guards are opaque to the exhaustiveness checker; a match with guards always requires a wildcard or otherwise complete coverage.

```blink
fn classify(n: Int) -> Str {
    match n {
        0 => "zero"
        n if n > 0 => "positive"
        _ => "negative"
    }
}
```

Guards apply to the entire OR-pattern group: `Some(x) | Some(y) if x > 0` means `(Some(x) | Some(y)) if x > 0`.

#### Exhaustiveness

Every `match` must cover all possible values. The compiler performs exhaustiveness analysis and rejects incomplete matches.

```
error[NonExhaustiveMatch]: non-exhaustive match
 --> geometry.bl:15:5
  |
15|     match shape {
  |     ^^^^^ missing pattern: `Triangle`
  |
  = fix: add arm `Triangle(base, height) => <expr>`
```

The exhaustiveness checker handles:
- **Enum variants** — tracks which variants are covered
- **Boolean** — `true` and `false` must both appear (or wildcard)
- **Integer/char ranges** — tracks covered intervals, reports uncovered ranges
- **Nested patterns** — recursive analysis through constructors, tuples, and structs
- **Guards** — treated as opaque (may be false), so guarded arms do not contribute to exhaustiveness
- **OR-patterns** — union of covered patterns per alternative

**Why exhaustiveness matters for AI.** The single most common bug AI-generated code produces is the forgotten case. A missing `None` handler, an unhandled error variant, an enum value added without updating all consumers. Exhaustive matching makes this class of bug structurally impossible. The compiler mechanically identifies what's missing and suggests the fix. An AI agent can apply the fix automatically — this is the generate-compile-fix loop working as designed.

#### Refutable vs Irrefutable Patterns

Patterns are classified as **irrefutable** (always match) or **refutable** (may fail to match).

`let` bindings and `for` loops require **irrefutable** patterns. A refutable pattern in `let` position is a compile error. `match` arms accept refutable patterns.

**Irrefutable patterns** (allowed in `let` and `for`):
- Variable binding: `let x = ...`
- Wildcard: `let _ = ...`
- Tuple of irrefutable patterns: `let (a, b) = ...`
- Struct with all irrefutable field patterns + `..`: `let User { name, .. } = ...`
- Single-variant enum: if an enum has exactly one variant, that variant's pattern is irrefutable
- Nested irrefutable: `let ((x, y), label) = ...`

**Refutable patterns** (only in `match` arms):
- Literals: `0`, `true`, `"hello"`
- Specific enum variants when the enum has multiple variants: `Some(x)`, `None`, `Ok(v)`
- Range patterns: `1..=5`
- OR-patterns: `Some(x) | None`
- Struct patterns with literal field values: `User { name: "admin", .. }`

```blink
// OK: irrefutable — tuple always has 2 elements
let (x, y) = get_point()

// OK: irrefutable — struct destructuring with rest
let User { name, email, .. } = get_user()

// OK: irrefutable in for loop
for (key, value) in map {
    io.println("{key}: {value}")
}
```

```
error[RefutableLetPattern]: refutable pattern in `let` binding
 --> auth.bl:3:5
  |
3 |     let Some(x) = maybe_value
  |         ^^^^^^^ pattern `None` not covered
  |
  = help: use `match` or `??` instead:
  |   let x = maybe_value ?? default_value
  |   match maybe_value { Some(x) => ..., None => ... }
```

#### Destructuring Summary

Destructuring is the irrefutable subset of pattern matching. It works uniformly in `let` bindings, `for` loops, and function parameters (§3.8 for tuples).

```blink
// Tuple destructuring
let (name, age) = get_user_info()
let (status, body) = parse_response(data)?

// Nested tuple destructuring
let ((x, y), label) = get_labeled_point()

// Struct destructuring
let User { name, email, .. } = get_current_user()

// Ignoring elements
let (_, count) = tally(items)

// In for loops
for (key, value) in map {
    io.println("{key}: {value}")
}
```

---

### 3.6 Traits

Traits define shared behavior. They are the sole polymorphism mechanism in Blink. There is no inheritance, no subtyping, no implicit conversions.

#### Trait Declaration

```blink
trait Display {
    fn fmt(self, mut sb: StringBuilder)
    final fn display(self) -> Str {
        let sb = StringBuilder.new()
        self.fmt(sb)
        sb.to_str()
    }
}

trait Eq {
    fn eq(self, other: Self) -> Bool
    final fn ne(self, other: Self) -> Bool {
        !self.eq(other)
    }
}

trait Hash: Eq {
    fn hash(self) -> U64
}

trait Ord: Eq {
    fn cmp(self, other: Self) -> Ordering
}

trait Clone {
    fn clone(self) -> Self
}

trait Debug {
    fn debug(self) -> Str
}
```

The `Ordering` type used by `Ord.cmp` is compiler-known and auto-imported in the module prelude (vote: 5-0):

```blink
type Ordering {
    Less
    Equal
    Greater
}
```

#### Hash Contract and Seeding

`hash(self) -> U64` returns a **pre-seed** value. Implementations must satisfy the coherence law with `Eq`: for any `a` and `b`, `a == b` implies `a.hash() == b.hash()`. Coherence holds at the trait level and is **independent of any runtime seed** — it is a property of `hash` against `eq`, not of how the runtime stores keys.

`Map` and `Set` mix a **process-global seed** into hash values before bucket selection. The seed is drawn once at process start and is **randomized per process by default**: iteration order over a `Map` or `Set`, and the concrete bucket a key lands in, vary from run to run, build to build, and across compiler versions. This is deliberate — randomization forces accidental order-dependence to fail early rather than rot silently (vote: 6-0; see [Hash Seed & Iteration Order rationale](../decisions/hash-seed-iteration-order.md)).

The seed perturbs **only** bucket placement. It is never observable through `hash()`, never stored, serialized, or compared, and is set once before `main` runs — it is not an effect, not a capability, and there is no API that reads or sets it from Blink code. Programs therefore **must not** depend on iteration order; code that needs a stable order must sort the keys or entries explicitly:

```blink
let names = scores.keys().sort()
for name in names {
    io.println("{name}: {scores.get(name).unwrap()}")
}
```

A function whose result depends on unsorted `Map`/`Set` iteration order is **not** referentially transparent with respect to its `Map`/`Set` arguments, even though it has no effect annotation. The compiler's purity analysis (§4 effects, truly-pure classification) treats iteration over a `Map`/`Set` as an opaque-order read of process state: any function that iterates a `Map` or `Set` is conservatively excluded from memoization and reordering. Iteration order is **not** part of a `Map`/`Set` value's identity — two maps with equal entry sets are `==`-equal regardless of insertion history or seed (§3.6 *Container Equality*).

**Float keys.** `F32`/`F64` do not implement `Hash`, and a `Float` (or any type transitively containing one) used as a `Map`/`Set` key is rejected at type-check as `E1400 MapKeyNotHashable`. This is a permanent contract, not a missing impl: float equality cannot satisfy the `Eq`/`Hash` coherence law — `-0.0 == 0.0` holds while the two have distinct bit patterns, so a bitwise hash would map equal values to different buckets. Round to an integer key instead.

**Non-hashable keys and elements in general.** Only builtin scalars (`Int`, sized ints, `Bool`, `Char`, `Str`), a tuple whose elements are all hashable, and a user `struct`/`enum` that implements `Hash` and `Eq` implement `Hash`. A user type gets the two impls from `@derive(Hash, Eq)` or from a written `impl` (§3.6, *Trait Coherence*). Every other type — every container (`List`, `Map`, `Set`, `Option`, `Result`), `Bytes`, `StringBuilder`, and any `fn`/closure type — has no `Hash` impl and cannot gain one, so using one as a `Map` key or `Set` element is rejected at type-check as `E1400 MapKeyNotHashable`, the same code as the Float case above. A tuple is hashable **if and only if** every one of its elements is; `(Int, Option[Int])` is rejected because its second element is not, even though `(Int, Str)` is accepted.

For pinning the seed (golden-file tests, fixture-driven runners, self-hosting diff stability) and for the `--deterministic` flag and `BLINK_MAP_SEED` environment variable, see §8.10.

#### The `final` Modifier

A trait may declare a default method as `final` to seal it against override. The `final` keyword is a method-level modifier on trait default methods only — it appears nowhere else in the language.

```blink
trait Eq {
    fn eq(self, other: Self) -> Bool
    final fn ne(self, other: Self) -> Bool {
        !self.eq(other)
    }
}
```

**Default policy: overridable.** A trait default method without `final` is overridable. Any `impl` block may shadow the trait's default with an impl-site body of the same signature. The impl's body fully replaces the default at every call site for that implementing type.

**Opt-in sealing.** A trait author writes `final fn name(...) { body }` to forbid override. Sealed methods route to the trait's body at every call site, regardless of which type implements the trait. Use `final` for defaults that are *definitional derivations* from required methods — bodies whose correctness depends on matching the required methods exactly. Leave defaults open when the body is a *performance-overridable adapter* (e.g., Iterator adapter defaults, §3c.1) where a concrete impl can supply a faster specialization without changing observable behavior.

**Sealing requires a body.** `final` on a body-less (required) method is a parse error:

```
error[FinalRequiresBody]: `final` cannot apply to a required method
 --> shapes.bl:3:5
  |
3 |     final fn area(self) -> Float
  |     ^^^^^ `final` may only modify a default method (one with a body)
  |
  = help: either provide a body, or remove `final`
```

**Override semantics: replace-only.** When an open default is overridden in an `impl`, the impl's body fully replaces the default. There is no super-call mechanism to reach the original default from inside an override — Blink has no inheritance and no method-resolution-order chain to walk. To reuse the default's body, factor it into a free helper function and call that from both the default and the override.

```blink
trait Numeric {
    fn value(self) -> Float
    fn double(self) -> Float {           // open default
        self.value() * 2.0
    }
}

impl Numeric for Distance {
    fn value(self) -> Float { self.meters }
    fn double(self) -> Float {           // OK: replaces the default
        self.meters * 2.0
    }
}
```

**Monotonic sealing: one legal direction.** A method's sealed-ness is fixed at the trait that first declares its body, and no subtrait may flip it in either direction. Concretely, where `SubTrait : SuperTrait`:

- **Down the chain (un-sealing forbidden).** If `SuperTrait` seals method `m`, then `SubTrait` cannot un-seal `m`, and no `impl SubTrait` may override `m`. Sealing is preserved down the supertrait chain.
- **Up the chain (strengthening forbidden).** If `SuperTrait` declares `m` as an *open* default, a subtrait may not re-declare `m` to seal it. Writing `final fn m { body }` (or any redeclaration of `m`) in `SubTrait` is rejected with `E0733 SubtraitMethodRedeclaration`.

Strengthening is forbidden because Blink resolves trait methods statically against the trait the bound names, with no method-resolution order (§3.6 *Why Traits Over Inheritance*). If a subtrait could re-seal `m` with a different body, the same receiver would dispatch to two different bodies depending on whether it is viewed through the `SuperTrait` bound or the `SubTrait` bound — `via_super[T: SuperTrait](x).m()` and `via_sub[T: SubTrait](x).m()` would disagree for the same `x`, breaking the `SubTrait <: SuperTrait` coherence the seal exists to protect. This is the symmetric closure of the down-the-chain rule: the seal lives where the method is born.

```
error[SealedMethodOverride]: cannot override sealed method `ne`
  --> ord_ext.bl:8:5
   |
8 |     fn ne(self, other: Self) -> Bool { ... }
   |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `Eq.ne` is `final` and `Ord : Eq`
   |
   = help: `final` defaults on supertraits remain sealed on subtraits and their impls
```

A subtrait that tries to strengthen an open supertrait default is rejected at the declaration site:

```blink
trait Greeter {
    fn greet(self) -> Str { "hello" }          // open default
}

trait LoudGreeter : Greeter {
    final fn greet(self) -> Str { "HELLO" }    // E0733 — rejected at this declaration
}
```

```
error[SubtraitMethodRedeclaration]: cannot seal inherited open default `greet`
  --> greet.bl:6:5
   |
6 |     final fn greet(self) -> Str { "HELLO" }
   |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `Greeter.greet` is an open default; `LoudGreeter : Greeter` may not re-seal it
   |
   = note: sealing is monotonic — a subtrait cannot strengthen a supertrait's open
           default, because `x.greet()` would resolve differently through the
           `Greeter` view than the `LoudGreeter` view
   = help: to seal `greet` for every implementor, mark it `final` on `Greeter` itself
   = help: to specialize behavior for one type, override `greet` normally in its `impl`
```

`E0733` fires at the subtrait's redeclaration site, not at any call site, and applies only to redeclaring a method a supertrait already provides as an open default. A normal `impl`-block override of that open default (without `final`) is unaffected — that is the ordinary replace-only override of §3.6 *The `final` Modifier*.

**Effect-row subtype for trait impls.** Every method an `impl` provides for a trait, whether it implements a required method or overrides an open default, must declare an effect row `R_i` with `R_i ⊆ R_t`, where `R_t` is the row the trait declares for that method. An impl may *narrow* the row (drop effects it does not use) but may not *widen* it (add effects the trait does not declare). A trait method with no `!` has the empty row, so every impl of it must also have no `!`. This rule is what lets a bound `T: Trait` stand as an upper bound on the effects of a call through it: a generic function with no `!` that calls `x.m()` for `x: T` performs no effects for any `T`. A widening impl is rejected at the impl method with `error[TraitContractEffectMismatch]` (E0904). See §4.5 *Effect Composition Rules* for the subtyping lattice. `final` defaults have no override site, so their row is fixed at the declaration.

```blink
trait Shout {
    fn shout(self) -> Int
}

type Box { v: Int }

impl Shout for Box {
    fn shout(self) -> Int ! IO {    // E0904 -- `Shout.shout` declares no effects
        io.print("{self.v}")
        self.v
    }
}
```

```
error[TraitContractEffectMismatch]: `shout` declares effects its trait method does not
  --> shout.bl:8:29
   |
8 |     fn shout(self) -> Int ! IO {
   |                            ^^ `IO` is not in the row of `Shout.shout`, which is empty
   |
   = help: remove `! IO` and do the IO at the call site, or add `IO` to `Shout.shout` in the trait
```

**Migration: `@deprecate_override` warning hop.** Flipping a stdlib default from open to sealed is a breaking change for downstream impls. The transition path is a two-step deprecate-then-seal:

1. The trait author marks the open default with `@deprecate_override`. Existing impls that override it still compile, but the compiler emits `W0731 OverrideOfDeprecatedDefault` at the override site.
2. In the next release, `@deprecate_override` is removed and `final` is added. Override sites that ignored the warning now hit `E0731 SealedMethodOverride`.

Flipping a sealed default to open is non-breaking and requires no migration.

#### The `Self` Type

`Self` is a built-in type alias that refers to the implementing type. It is valid in exactly two contexts:

1. **Trait declarations** — `Self` refers to whichever type will implement the trait.
2. **`impl` blocks** — `Self` refers to the type being implemented.

Outside these contexts, `Self` is a compile error.

```blink
trait Eq {
    fn eq(self, other: Self) -> Bool       // Self = the implementing type
    final fn ne(self, other: Self) -> Bool {
        !self.eq(other)
    }
}

impl Eq for Color {
    fn eq(self, other: Self) -> Bool {     // Self = Color
        // ...
    }
}
```

```
error[SelfOutsideTraitOrImpl]: `Self` outside trait or impl
 --> utils.bl:3:18
  |
3 |     fn clone() -> Self {
  |                    ^^^^ `Self` is only valid inside trait declarations and impl blocks
```

**`self` is sugar for `self: Self`.** The first parameter of a trait method can be written as bare `self`, which desugars to `self: Self`. Method-call syntax (`x.method()`) requires the first parameter to be literally `self` — a method with `self` renamed (e.g., `this: Self`) is callable only via qualified syntax `Trait.method(this)`.

```blink
trait Display {
    fn fmt(self, mut sb: StringBuilder)                        // self: Self, enables x.fmt(sb)
    final fn display(self) -> Str {                        // sealed default, enables x.display()
        let sb = StringBuilder.new()
        self.fmt(sb)
        sb.to_str()
    }
}

trait Combiner {
    fn combine(a: Self, b: Self) -> Self   // no `self` param — not a method
}

// Combiner must be called with qualified syntax:
let merged = Combiner.combine(left, right)
```

**`Self` is a type-position alias, not a constructor.** You cannot write `Self { field: value }` or `Self(args)` to construct values. Use the concrete type name.

```
error[SelfNotConstructor]: `Self` is not a constructor
 --> shapes.bl:12:9
  |
12|         Self { x: 0, y: 0 }
  |         ^^^^ cannot construct with `Self`
  |
  = help: use the concrete type name: `Point { x: 0, y: 0 }`
```

**`self` is always passed by value.** Blink is garbage-collected — there is no by-reference vs by-move distinction. The `self` parameter is a value like any other parameter. No `&self`, `&mut self`, or `self: Box[Self]` forms exist. `mut self` is a mutable parameter (see *Mutable Parameters* below), not a reference.

A method cannot change its caller's value through `self`. State that must persist across calls lives in a `let mut` binding captured by a closure or handler (§2.8, §4.7). An assignment to a field of `self`, or of any parameter, is a compile error (see *Mutable Parameters*).

**Shared cells.** Passing or binding a struct copies its fields. A field whose value is a shared cell refers to the same cell after the copy. After `let mut b = a` and `b.x = 2`, `a.x` is unchanged; after `b.xs.push(5)`, `a.xs` holds the new element too. The shared cells are:

- `List`, `Map` and `Set`
- `StringBuilder`
- a closure or handler that captured a `let mut` binding (§2.8, §4.7)

This list is the only one; other sections refer to it. It does not yet say whether a `Channel` or an effect handle is a shared cell.

Only a shared cell can change through a second name. A value of any other type, at any depth, cannot. This holds for every copy: bind, pass, return and `clone()` (§3.6.1 *Clone Semantics*).

#### Mutable Parameters

A parameter is a binding and follows the binding rule (§3.2.2 *Construction and Mutability*). A parameter is immutable unless it is declared `mut`. A `mut` parameter, `self` included, may be the root of a mutating method call. The caller shares every collection it passes, so a `mut` parameter tells the caller: **this function may change the shared cells you pass.**

```blink
fn add_route(mut srv: Server, r: Route) {
    srv.routes.push(r)                  // OK — root `srv` is mut
}

fn count(xs: List[Int]) -> Int {
    xs.push(0)                          // error[E0610] — `xs` is not mut
    xs.len()
}

impl Stack {
    fn push(mut self, x: Int) {
        self.items.push(x)              // OK — `mut self`
    }
}
```

**A parameter is never assigned.** An assignment to a parameter, or to a field of one, is always a compile error, with or without `mut`, `self` included. Such a write changes only the callee's copy of the value (§3.6 *`self` is always passed by value*), so the caller never sees it. To change a value locally, copy it to a new `let mut` name:

```blink
fn gcd(a: Int, b: Int) -> Int {
    let mut x = a
    let mut y = b
    while y != 0 {
        let t = y
        y = x % y
        x = t
    }
    x
}

impl Point {
    fn with_x(self, x: Int) -> Point {
        Point { x: x, y: self.y }       // build a new value; `self.x = x` is an error
    }
}
```

```
error[ParamAssign]: cannot assign to parameter `a`
 --> gcd.bl:3:9
  |
3 |         a = b
  |         ^ `a` is a parameter
  |
  = note: a write to a parameter changes only this function's copy
  = help: copy it to a new name: `let mut x = a`
```

The fix-it names a new binding. `let mut a = a` shadows the parameter and triggers `warning[W0603] ShadowedVariable`.

**What `mut self` covers.** A method is mutating if and only if it declares `mut self`. The standard library declares `mut self` on methods that change state Blink holds as a value: the contents of a `List`, `Map`, `Set` or `StringBuilder`. A change to state outside the language — memory behind a `Ptr`, a socket, a file, a database — is an effect, tracked by the effect row (§4) and the `@trusted` boundary (§9), not by `mut`. So `Ptr.write` (§9 *Pointer Operations*) and `TcpConn.write` take plain `self`, and a plain `let` pointer can write through.

**Traits and impls.** A trait method's `mut` markers are part of its contract. An impl may drop a `mut` that the trait declares, because an implementation that does not mutate satisfies a contract that allows mutation. An impl may not add a `mut` that the trait does not declare: `error[ImplAddsMut]`, with a related span on the trait's signature.

```blink
trait Display {
    fn fmt(self, mut sb: StringBuilder)
}

type Marker { id: Int }

impl Display for Marker {
    fn fmt(self, sb: StringBuilder) { }    // OK — drops `mut`, never mutates `sb`
}
```

**Function types erase `mut`.** A function type such as `fn(List[Int]) -> Int` carries no `mut` marker. A closure's `mut` parameter is local to that closure. A higher-order function can therefore change a collection through a closure argument with no `mut` at its own call site; `mut` marks where a mutation starts, not every path that reaches it.

**Foreign functions.** An `@ffi` function has no Blink body to check. Its author declares `mut` on each parameter whose Blink value the foreign code changes (for example `sb_write(mut sb: StringBuilder, s: Str)`). The compiler trusts this declaration and cannot verify it; it is part of the audited premise of the `@ffi` boundary (§9).

**Lints.** Two warnings support the rule. Neither is a guarantee:

| Warning | Fires on | Help |
|---|---|---|
| `MutAliasOfImmutable` | An argument to a `mut` parameter, or the right side of `let mut b = a`, when it is a place with a non-`mut` root | "`b` shares `a`'s collections; a change through `b` is visible through `a`" |
| `UnusedMut` | A `let mut` binding or `mut` parameter whose body never uses the mutability | Remove `mut`. Does not fire on a `mut` an impl keeps from its trait, or on `@ffi` parameters |

`MutAliasOfImmutable` checks direct aliases only. An alias made through a call result (`id(a)`) or a struct literal (`W { xs: a }`) passes it. An immutable `let` is not a promise that the value behind it never changes (§3.2.2).

**Rollout.** Each new error in this subsection ships first as a warning with a machine-applicable fix that `blink fix` applies, and becomes an error in the next release.

#### Operations on `Self` in a Default Body

Inside a trait's default method body, `self` has the abstract type `Self`. `Self`
is treated as an implicit type parameter of the trait, bounded by the trait's
**guarantee set**: the methods the trait itself declares, plus every method of each
trait named in its supertrait clause, transitively. An operator (which desugars to
a trait method — see *Operator Desugaring*) or a plain method call on a value of
type `Self` is well-formed **only when its backing trait is in the guarantee set**.
Any other operation on `Self` is rejected at the **trait definition**, before any
implementor exists.

This is the parametricity rule of *Polymorphic Trait Implementations* applied to
`Self`: a default body may vary behavior only through bounds the trait declares.
Because every `impl` must satisfy the trait's supertraits, a default body that
type-checks under the guarantee set is valid for every implementor — the check is
complete at the definition and is never re-run per implementor or per
monomorphization.

```blink
trait Eq {
    fn eq(self, other: Self) -> Bool
    fn ne(self, other: Self) -> Bool { !self.eq(other) }   // OK: eq is Eq's own method
}

trait Ranked: Ord {
    fn rank(self) -> Int
    fn before(self, other: Self) -> Bool { self < other }  // OK: `<` -> Ord.cmp, Ord is a declared supertrait
}
```

A body that uses an operator or method `Self` is not guaranteed to have is rejected
where it is written:

```
error[UnlicensedSelfOperation]: `<` on `Self` is not licensed by `Ranked`
 --> rank.bl:3:44
  |
3 |     fn before(self, other: Self) -> Bool { self < other }
  |                                            ^^^^^^^^^^^ `<` desugars to `Ord.cmp`, but `Ranked` does not require `Ord`
  |
  = note: in a default body `self` has the abstract type `Self`; an operator or method
          on `Self` is licensed only when the trait declares the backing trait as a supertrait
  = help: declare the supertrait so every implementor provides `<`:
              trait Ranked: Ord { ... }
```

**Arithmetic on `Self`.** The arithmetic traits (`Add`, `Sub`, `Mul`, `Div`, `Rem`,
`Neg`) are sealed to built-in numeric types (see *Arithmetic Traits*). A trait may
still name one as a supertrait — `trait Doubler: Add` is legal — but that restricts
its implementors to the built-in numerics, the only types that satisfy `Add`. So
`self + self` in a default body is licensed only for numeric-restricted traits and
can never be satisfied by a user-defined type. The diagnostic for a sealed backing
trait does **not** suggest adding the supertrait (an unsatisfiable repair); it states
the seal and offers the real alternatives:

```
error[UnlicensedSelfOperation]: `+` on `Self` is not licensed by `Doubler`
 --> num.bl:1:41
  |
1 | trait Doubler { fn double(self) -> Self { self + self } }
  |                                           ^^^^^^^^^^^ `+` desugars to `Add.add`, but `Doubler` does not require `Add`
  |
  = note: `Add` is a sealed arithmetic trait — only built-in numeric types implement it,
          so `trait Doubler: Add` would be satisfiable by no user type
  = help: make `double` a required method and let each implementor define it:
              fn double(self) -> Self
  = help: if the operation is numeric, use a concrete numeric type instead of `Self`
```

The rule is uniform across every operator family (`Add`–`Neg`, `Eq`, `Ord`) and
every plain method call on `self`. A call to one of the trait's own methods is always
licensed — that is what lets `Eq.ne` call `self.eq()` and `Display.display` call
`self.fmt()`.

#### Arithmetic Traits

```blink
trait Add {
    fn add(self, other: Self) -> Self
}

trait Sub {
    fn sub(self, other: Self) -> Self
}

trait Mul {
    fn mul(self, other: Self) -> Self
}

trait Div {
    fn div(self, other: Self) -> Self
}

trait Rem {
    fn rem(self, other: Self) -> Self
}

trait Neg {
    fn neg(self) -> Self
}
```

Arithmetic traits are **sealed** -- the compiler restricts implementations to built-in numeric types only. User-defined types cannot implement them. This prevents operator soup where `+` means something different on every type (vote: 4-1, Systems expert dissented wanting open impls).

```
error[SealedTraitImpl]: sealed trait
 --> vector.bl:8:1
  |
8 | impl Add for Vector2 {
  | ^^^^^^^^ `Add` is sealed -- only built-in numeric types may implement it
  |
  = note: arithmetic traits (Add, Sub, Mul, Div, Rem, Neg) are compiler-restricted
  = help: define a named method instead: `fn add(self, other: Vector2) -> Vector2`
```

`Bool` is not a numeric type, so `+ - * / %` reject a `Bool` operand -- the same rule the bitwise operators follow. Blink has no truthiness, so a `Bool` never reads as 0 or 1 (§3.4 *`Bool` Is Distinct from `Int`*). Count with an explicit conditional:

```blink
let hits = (if a { 1 } else { 0 }) + (if b { 1 } else { 0 })
```

If you need vector/matrix math, use named methods: `v1.add(v2)` -- clear and grep-able.

#### Operator Desugaring

Operators desugar to trait method calls. The full mapping:

| Expression | Desugars to | Trait |
|------------|-------------|-------|
| `a + b` | `Add.add(a, b)` | `Add` |
| `a - b` | `Sub.sub(a, b)` | `Sub` |
| `a * b` | `Mul.mul(a, b)` | `Mul` |
| `a / b` | `Div.div(a, b)` | `Div` |
| `a % b` | `Rem.rem(a, b)` | `Rem` |
| `-a` | `Neg.neg(a)` | `Neg` |
| `a == b` | `a.eq(b)` | `Eq` |
| `a != b` | `a.ne(b)` | `Eq` |
| `a < b` | `a.cmp(b) == Less` | `Ord` |
| `a > b` | `a.cmp(b) == Greater` | `Ord` |
| `a <= b` | `a.cmp(b) != Greater` | `Ord` |
| `a >= b` | `a.cmp(b) != Less` | `Ord` |

Operands must be the same type. Mixed-type arithmetic (`Int + Float`) is a compile error -- use explicit conversion.

#### Float Total Ordering

`Float` implements `Eq` and `Ord` with **total ordering** semantics (vote: 5-0):

- `NaN == NaN` is `true` (restores reflexivity)
- `NaN` sorts greater than all other values
- `-0.0 == 0.0` is `true`
- `Float` does **not** implement `Hash` — bitwise hashing cannot stay coherent with `Eq` (e.g. `-0.0 == 0.0` with distinct bit patterns), so `Float` keys are rejected as `E1400` (see Hash Contract and Seeding, §3.6)

For IEEE 754-strict comparison where `NaN != NaN` and `-0.0 != 0.0`: use `float.ieee_eq(other)` from stdlib.

#### Built-in Type Trait Implementations

| Type | Add | Sub | Mul | Div | Rem | Neg | Eq | Ord | Hash | Display | Clone | Debug |
|------|-----|-----|-----|-----|-----|-----|----|----|------|---------|-------|-------|
| Int | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y |
| I8/I16/I32 | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y |
| U8/U16/U32/U64 | Y | Y | Y | Y | Y | -- | Y | Y | Y | Y | Y | Y |
| Float | Y | Y | Y | Y | Y | Y | Y* | Y* | -- | Y | Y | Y |
| Bool | -- | -- | -- | -- | -- | -- | Y | -- | Y | Y | Y | Y |
| Str | -- | -- | -- | -- | -- | -- | Y | Y | Y | Y | Y | Y |
| Char | -- | -- | -- | -- | -- | -- | Y | Y | Y | Y | Y | Y |
| Bytes | -- | -- | -- | -- | -- | -- | Y | -- | -- | -- | Y | Y |

Y* = total ordering semantics. Unsigned types don't impl `Neg`. `Float` doesn't impl `Hash`. `Bytes` equality is byte-wise; `Bytes` has no `Ord`.

`Option`, `Result`, `List`, `Set`, `Map` and tuples implement `Eq` when their parts do — see *Container Equality* below.

#### Container Equality

The built-in containers implement `Eq` **conditionally**: a container is `Eq` when its parts are `Eq` (vote: 6-0; see [Container Equality rationale](../decisions/container-equality.md)). The compiler provides these impls. The orphan rule (*Trait Coherence*) stops user code from writing them.

| Type | `Eq` when | `a == b` is `true` when |
|------|-----------|-------------------------|
| `Option[T]` | `T: Eq` | both are `None`, or both are `Some` and the payloads are `==` |
| `Result[T, E]` | `T: Eq` and `E: Eq` | both are `Ok` with `==` payloads, or both are `Err` with `==` payloads |
| `List[T]` | `T: Eq` | the lengths are equal and the elements at each index are `==` |
| `Set[T]` | always (`Set` requires `T: Hash`, and `Hash: Eq`) | the sizes are equal and each element of `a` is a member of `b` |
| `Map[K, V]` | `V: Eq` (`K: Hash` gives `K: Eq`) | the key sets are equal and, for each key, the values are `==` |
| `Bytes` | always | the lengths are equal and the bytes are equal |
| tuple | every element is `Eq` | element-wise `==` (§3.8 *Auto-Derived Trait Implementations*) |

The check recurses through the type. `Option[List[Int]]` is `Eq` because `List[Int]` is `Eq`, because `Int` is `Eq`. `List[Widget]` is `Eq` only when `Widget` has an `Eq` impl or `@derive(Eq)`.

```blink
@derive(Eq)
type Point { x: Int, y: Int }

type Widget { id: Int }

fn main() {
    let a = [1, 2, 3]
    let b = [1, 2, 3]
    let same = a == b
    io.println("{same}")                            // true: same elements, same order

    let p: Option[List[Point]] = Some([Point { x: 1, y: 2 }])
    let q: Option[List[Point]] = Some([Point { x: 1, y: 2 }])
    let pq = p == q
    io.println("{pq}")                              // true

    let mut s1: Set[Int] = Set()
    s1.insert(1)
    s1.insert(2)
    let mut s2: Set[Int] = Set()
    s2.insert(2)
    s2.insert(1)
    let ss = s1 == s2
    io.println("{ss}")                              // true: insertion order is not part of the value

    let ws = [Widget { id: 1 }]
    // ws == ws                                     // error: `Widget` does not implement `Eq`
}
```

**Values, never identity.** `==` never compares identity. Two lists with equal elements are `==` when they are different cells, and wrapping a value in `Option` or `Result` does not change what `==` compares. `Set` and `Map` compare by membership: iteration order is not part of the value (*Hash Contract and Seeding*).

**Generic code.** `==` on a container of a type parameter needs the bound that the table gives. `fn same[T](a: Option[T], b: Option[T]) -> Bool { a == b }` is an error. Write `fn same[T: Eq](a: Option[T], b: Option[T]) -> Bool { a == b }`.

**Enums (interim rule).** An enum with no `Eq` impl and no `@derive(Eq)` is `Eq` only if every payload type is `Eq`. An enum with no payloads is `Eq`. So `Option[Color]` is `Eq` for a payload-free `Color`, and `Option[Shape]` is not `Eq` if a `Shape` variant carries a `List[Widget]`. Whether a data enum must write `@derive(Eq)` is an open question.

**Ord.** `Set` and `Map` never implement `Ord`: no order over them is canonical and agrees with membership equality.

**Eq laws.** An `Eq` impl must be reflexive (`a == a`), symmetric (`a == b` implies `b == a`) and transitive (`a == b` and `b == c` imply `a == c`). The compiler and the container impls may rely on these laws, as `Map` and `Set` rely on the Hash coherence law. For example, `==` may return `true` without comparing elements when both operands are the same cell. Every built-in `Eq` obeys the laws; `Float` obeys them because `NaN == NaN` (*Float Total Ordering*). If a user impl breaks a law, `==` on a container that holds that type returns an unspecified `Bool`. It stays memory-safe.

**Ord laws.** An `Ord` impl must be a total order that agrees with `Eq`:

- `a.cmp(b) == Equal` exactly when `a == b`.
- `a.cmp(b) == Less` exactly when `b.cmp(a) == Greater`.
- If `a.cmp(b) == Less` and `b.cmp(c) == Less`, then `a.cmp(c) == Less`.

A `sort_by` comparator need only be a **total preorder**. It obeys the second and third laws, and `cmp(a, a)` is `Equal`, but it may return `Equal` for two values that are not `==`. A comparator on one field, such as `fn(a, b) { a.age.cmp(b.age) }`, does this, and stability (*The `ListOps` Trait*, §3.2.2) keeps such elements in their input order. Every built-in `Ord` obeys the laws; `Float` obeys them because `NaN` sorts last (*Float Total Ordering*). If a user `Ord` impl or a comparator breaks a law, `sort` and `sort_by` still terminate. They return a permutation of the input, in which each element occurs exactly once, in an unspecified order. They stay memory-safe and do not panic.

**Cyclic data.** `List`, `Map` and `Set` are shared cells, so a value can contain itself (for example, through a struct field that holds the list that holds the struct). `==` on cyclic data may not terminate. The compiler adds no cycle guard.

**Diagnostic for a failed `Eq` check.** When `==`, `!=`, an `Eq` bound (for example `assert_eq`, E0306) or `@derive(Eq)` (E1401) fails on a type that has no `Eq`, the error names the **innermost** type argument that has no `Eq`, and the chain from the operand type to it. It offers **at least** these machine-applicable fixes (§8.6):

- `@derive(Eq)` on that type, when it is a user-declared `struct` or `enum`.
- `x.is_none()` in place of `x == None` (and `x.is_some()` in place of `x != None`), when one operand is a bare `None` literal. `is_none()` and `is_some()` need no `Eq`.

The exact wording is not normative, and tools may offer more fixes.

```
error[TypeError]: `Option[List[Widget]]` does not implement `Eq`
 --> app.bl:9:8
  |
9 |     if found == None {
  |        ^^^^^^^^^^^^^ `==` needs `Eq`
  |
  = note: `Option[List[Widget]]` is `Eq` only if `List[Widget]` is `Eq`,
          and `List[Widget]` is `Eq` only if `Widget` is `Eq`
  = help: add `@derive(Eq)` to `type Widget`
  = help: to test for `None`, write `found.is_none()`
```

#### Integer Division

`Int / Int` performs integer division (truncates toward zero). `Float / Float` performs IEEE 754 division. Division by zero on integers is a runtime panic.

Traits can have default method implementations (`ne` above). Traits can require other traits (`Hash: Eq` means implementing `Hash` requires implementing `Eq`).

#### Trait Implementation

```blink
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

```blink
fn max[T: Ord](a: T, b: T) -> T {
    match a.cmp(b) {
        Greater => a
        _ => b
    }
}

fn print_all[T: Display](items: List[T]) ! IO {
    for item in items {
        io.println(item)
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

An argument whose type does not implement the bound's trait is `error[TraitBoundNotSatisfied]` (E0306), with one exception: a failed `Display` bound is `error[E0523]` (`MissingDisplayImpl`) at every call, so a missing `Display` impl reads the same whether the call is `"{x}"`, `sb.write(x)`, `io.println(x)` or `print_all(xs)` (§3.6 *Display Format Protocol*).

#### Why Traits Over Inheritance

Inheritance creates vertical hierarchies. Understanding a method call requires traversing the class tree upward through potentially dozens of files. This is anti-locality at its worst -- a single method dispatch can depend on code scattered across an entire codebase.

Traits are horizontal. Each `impl` block is self-contained. To understand what `Display` does for `Color`, you read one block. No parent classes, no `super` calls, no method resolution order, no fragile base class problem, no diamond inheritance.

For AI, this is critical. An AI generating a trait impl needs context from two places: the trait declaration and the type definition. Not the entire class hierarchy. Two files, not fifteen.

Traits also support retroactive implementation -- you can implement a trait for a type you didn't define (subject to coherence rules). This enables extending types with new behavior without modifying their source, which is impossible with class inheritance.

#### Trait Coherence

Coherence guarantees that for any (Trait, Type) pair, at most one implementation exists in the entire program. This invariant is essential -- trait dispatch must be deterministic, and evidence-passing compilation ([Codegen Backend rationale](../decisions/codegen-backend-bootstrap.md)) requires exactly one vtable per (Trait, Type) pair at every call site.

Three rules enforce coherence: the orphan rule, the overlap rule, and the impl placement rule.

#### Orphan Rule

`impl Trait for Type` is allowed in module M if and only if **M's package defines Trait or M's package defines Type** (or both). A third-party package cannot implement a trait from package X for a type from package Y.

```blink
// OK: auth package defines AuthError, From is from prelude (compiler-known)
impl From[IOError] for AuthError {
    fn from(e: IOError) -> AuthError { AuthError.IO(e) }
}

// OK: json package defines Serializable and provides impls for built-in types
impl Serializable for Str {
    fn serialize(self) -> JsonValue { JsonValue.Str(self) }
}

// COMPILE ERROR: neither Display nor HttpResponse belong to this package
impl Display for HttpResponse {
    fn display(self) -> Str { "{self.status}" }
}
```

```
error[OrphanImpl]: orphan impl
 --> myapp/formatting.bl:3:1
  |
3 | impl Display for HttpResponse {
  | ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ neither `Display` nor `HttpResponse` is defined in this package
  |
  = note: impl must be in the package that defines the trait or the type
  = help: define a newtype wrapper, or add this impl to the `http` package
```

The workaround for the orphan restriction is the **newtype pattern** -- wrap the foreign type in a local struct:

```blink
type MyResponse {
    inner: HttpResponse
}

impl Display for MyResponse {
    fn display(self) -> Str { "{self.inner.status}" }
}
```

**Why strict orphan rules.** Without them, two packages could independently define `impl Display for HttpResponse`, and any program importing both would have two conflicting impls with no way to choose. This is Haskell's orphan instance problem -- widely considered a design mistake. Strict orphan rules make coherence a syntactic property (package ownership) rather than a whole-program analysis, keeping compilation fast and errors local.

For compiler-known traits (`Eq`, `Hash`, `Display`, `From[T]`, etc.), the compiler is considered the "defining package." Any user package can implement compiler-known traits for its own types. `@derive` generates impls in the type's defining module, which trivially satisfies the orphan rule.

#### No Impl Overlap

If two impls could both match a given type, the compiler rejects the program. There is no specialization -- no "more specific impl wins" rule.

```blink
trait Render {
    fn render(self) -> Str
}

// OK: impl for any List[T] where T has Display
impl Render for List[T] where T: Display {
    fn render(self) -> Str {
        self.into_iter().map(fn(x) { x.display() }).collect()
    }
}

// COMPILE ERROR: overlaps with List[T] where T: Display
// (Int implements Display, so List[Int] matches both)
impl Render for List[Int] {
    fn render(self) -> Str {
        "int list of {self.len()}"
    }
}
```

```
error[OverlappingImpls]: overlapping impls
 --> render.bl:12:1
  |
5 | impl Render for List[T] where T: Display {
  | ------------------------------------------ first impl
  ...
12| impl Render for List[Int] {
  | ^^^^^^^^^^^^^^^^^^^^^^^^^^ overlaps: `List[Int]` matches both impls
  |
  = note: Blink does not support specialization
  = help: use a newtype wrapper or restructure with a helper trait
```

**Why no specialization.** Specialization requires a partial ordering on impls and interacts with type inference in subtle, unsound ways. Rust has kept specialization unstable for over a decade due to repeated soundness holes. Without specialization, adding a new impl to a library can never silently change which impl is selected for existing code -- it can only cause a new overlap error, which is loud and fixable. Each (Trait, Type) pair maps to exactly one vtable with zero ambiguity.

**Workarounds for specialized behavior:** Use a helper trait to dispatch on the element type, or use the newtype pattern to create a distinct type with its own impl.

#### Impl Placement

The impl placement rule follows from the orphan rule: `impl Trait for Type` must live in a module belonging to the package that defines `Trait` or the package that defines `Type`. Within that package, any module is acceptable -- the impl does not need to be in the same file as the type or trait declaration.

```blink
// Package: myapp

// src/models.bl — defines User
pub type User {
    name: Str
    email: Str
    age: Int
}

// src/formatting.bl — impl in same package as User, different file
import models.{User}

impl Display for User {
    fn display(self) -> Str {
        "{self.name} ({self.email})"
    }
}
```

This is valid because `User` is defined in `myapp` and the impl is also in `myapp`. Intra-package module references are allowed (§10.5).

**Impl visibility.** Impls are automatically brought into scope when the type or the trait is imported. There is no syntax to import an impl directly -- importing `User` or importing `Display` is sufficient for the compiler to find and use `impl Display for User`.

```blink
import models.{User}

// Display impl for User is automatically visible because User is in scope
let s = user.display()
```

This means the compiler's impl search is: for `x.foo()` where `x: T`, find all impls of traits with method `foo` for type `T` that are reachable through the import graph. An impl is reachable if it is in a package that the current compilation unit depends on (directly or transitively) and either the trait or the type is in scope.

**Why auto-visibility.** Requiring explicit impl imports would be pure boilerplate -- you would need to know the module path of every impl for every trait you use. Auto-visibility on trait/type import means that importing a type gives you access to all its behavior, and importing a trait gives you access to all types that implement it. This is the right default for locality of reasoning: one import, complete behavior.

---

#### Polymorphic Trait Implementations

A polymorphic impl is parameterized over one or more type variables and may apply to a generic builtin type or to a user-defined generic type. The canonical form:

```blink
impl[T] Display for List[T] where T: Display {
    fn fmt(self, mut sb: StringBuilder) ! Fmt {
        sb.write("[")
        let mut first = true
        for item in self {
            if !first { sb.write(", ") }
            item.fmt(sb)
            first = false
        }
        sb.write("]")
    }
}
```

The `[T]` after `impl` introduces the type parameter; the `where` clause states the bounds it must satisfy.

**An impl binder must occur in the impl header's type positions.** A type parameter declared after `impl` must appear in the trait's type arguments, in the receiver's type arguments, or both. A binder appearing in neither is rejected at the declaration with `error[ImplBinderUnused]` (E0909):

```blink
impl[T] Show for IntBox { ... }          // E0909 -- T appears in neither the trait nor the receiver
impl[T] Convert[T] for IntBox { ... }    // OK -- T binds the trait's type argument
impl[T] Show for Box[T] { ... }          // OK -- T binds the receiver's type argument
```

**A `where`-clause bound does not rescue an impl binder.** `impl[T] Show for IntBox where T: Display` is still E0909. A bound *constrains* a type parameter; it does not *determine* one. An impl is selected by matching the trait and the receiver, so the header's type positions are the only places a selection could ever fix what `T` stands for — a binder absent from both is unfillable no matter how it is bounded.

This is the mirror image of the W0604 gate (§3.4 *Explicit Type Application*), and the two are consistent rather than contradictory. There, a bound *is* an occurrence, because a generic function's binder can be supplied by an explicit type argument and the bound decides which arguments are accepted. Here there is no supply site at all: impl selection admits no type-argument list, so no use site could ever repair the declaration. That distinction — between *constraining* a type parameter and *determining* it — is what makes a declaration-site **error** the right severity for an impl binder and a **warning** the right severity for a function binder. A declaration is rejected outright only when no use site could ever repair it; where a use site can, the diagnostic goes to the use site and the declaration gets a lint.

**Compilation model: monomorphization.** Each distinct instantiation referenced in the program (`List[Int]`, `List[Str]`, `List[User]`, etc.) compiles to a separate function. The compiler substitutes the concrete type for `T` before codegen, so each instantiation has type-appropriate storage and method dispatch baked in. The linker's dead-code stripping (`--gc-sections`) removes instantiations the final binary does not call. Stdlib monomorphizations live in the stdlib archive's `monolith.o`; user-code monomorphizations live as `static inline` in each `.o` that instantiates them. See [generic-mono-ownership-per-module](../decisions/generic-mono-ownership-per-module.md) for the storage rules.

**No runtime type information.** Blink exposes no `size_of[T]`, `is_pointer_kind[T]`, `TypeRepr[T]`, `align_of[T]`, or `TypeId[T]` forms — neither to user code nor as `@compiler_internal` primitives. The compiler decides layout and dispatch entirely at codegen time. Stdlib needs that require a layout query at the C level route through `@ffi` to a runtime C helper, not through a Blink intrinsic.

**Parametricity (normative).** Any generic body (a generic function, a polymorphic impl, or a trait default body) must be **parametric in its type parameters**. The body may not:

- **Dispatch on `T`'s identity.** `if T == Int { ... }`, `match T { ... }`, and equivalent constructs are compile errors.
- **Inspect `T`'s runtime layout, size, alignment, or pointer-kind.** No `sizeof`-like form exists in the source language for type parameters.
- **Call any function that exposes `T`'s runtime shape.** This rules out reading `T` from any reflective API.
- **Read or write a field of `T`.** A type parameter declares no fields, and a bound adds only methods: `error[NoSuchField]` (E0525).

The **only legal way** for a polymorphic impl body to vary behavior based on `T` is to introduce a trait bound and call a method on that bound. `(x: T).display()` is permitted when `T: Display` — it is dispatched at monomorphization time and resolves to the bound type's `Display` impl, not to a runtime type check.

```blink
// Allowed: behavior varies via trait bound, not via T's identity
impl[T] Sum for List[T] where T: Add[T, Output = T] + Zero {
    fn sum(self) -> T {
        let mut acc = T.zero()
        for item in self {
            acc = acc + item
        }
        acc
    }
}

// Compile error: body inspects T's identity
impl[T] Display for List[T] where T: Display {
    fn fmt(self, mut sb: StringBuilder) ! Fmt {
        if T == Int { sb.write("(ints)") }  // ERROR: cannot dispatch on T
        // ...
    }
}
```

The diagnostic for a parametricity violation reads:

```
error[E0701]: cannot inspect type parameter T
  --> mymod.bl:3:9
   |
3  |         if T == Int { ... }
   |         ^^^^^^^^^^^ T's identity is not available at runtime
   |
   = note: user impl bodies must be parametric in T (§3.6 Polymorphic Trait
     Implementations)
   = help: to vary behavior based on T's properties, add a trait bound:
     `where T: Eq` and call `(t: T).eq(other)` instead
```

**Why parametricity is normative, not just mechanical.** Monomorphization removes `T` before codegen, so a violation can't physically reach the C output. But parametricity is the *language guarantee* user code is allowed to assume about `T`, not just a consequence of how today's backend lowers generics. Spec-level enforcement preserves the compiler's freedom to change builtin layouts (e.g., niche-filled `Option[Int]`, future tagged-union changes), to add alternate backends (a `blink check` interpreter, JIT, or alternate linkage), or to evolve monomorphization strategy — none of which can silently weaken what user code is permitted to do. Without the spec rule, the first `@trusted` block or FFI shim that peeks at `T`'s lowered representation has no principled rejection, and every layout decision becomes a backward-compatibility commitment by accident.

**Interaction with coherence.** Polymorphic impls follow the same orphan, overlap, and placement rules as concrete impls. `impl[T] Trait for BuiltinGeneric[T] where T: Bound` and `impl Trait for BuiltinGeneric[Int]` overlap (because `Int` satisfies any reasonable `Bound`), and the program is rejected with `error[OverlappingImpls]` — Blink does not specialize. See [Trait Coherence](#trait-coherence) above for the full rules. See [polymorphic-builtin-generic-impls](../decisions/polymorphic-builtin-generic-impls.md) for the panel rationale.

---

#### Compiler-Known Traits

Certain traits have special meaning to the compiler. They are defined in the standard library but the compiler understands their semantics and can generate or enforce behavior based on them.

| Trait | Compiler behavior |
|-------|------------------|
| `Eq` | Enables `==` and `!=` operators. `@derive(Eq)` auto-generates structural equality. |
| `Ord` | Enables `<`, `>`, `<=`, `>=` and `cmp`. Requires `Eq`. |
| `Hash` | Enables use as `Map` key or `Set` element. Requires `Eq`. |
| `Clone` | Logical copy. `@derive(Clone)` auto-generates field-wise value copy (GC pointer copy, not recursive clone). |
| `Debug` | Developer-facing structural representation. `@derive(Debug)` auto-generates `"TypeName { field: {field.debug()} }"` format. |
| `Display` | Enables string interpolation (`"{value}"`). |
| `Add` | Enables `+` operator. Sealed to numeric types. |
| `Sub` | Enables `-` operator. Sealed to numeric types. |
| `Mul` | Enables `*` operator. Sealed to numeric types. |
| `Div` | Enables `/` operator. Sealed to numeric types. |
| `Rem` | Enables `%` operator. Sealed to numeric types. |
| `Neg` | Enables unary `-` operator. Sealed to signed numeric types. |
| `From[T]` | Infallible type conversion. Enables `Into[T]` auto-derivation. User-implemented. |
| `Into[T]` | Auto-derived mirror of `From`. Provides `.into()` method syntax. Never user-implemented. |
| `TryFrom[T]` | Fallible conversion returning `Result[Self, ConversionError]`. Auto-generated for refinement types. |
| `Closeable` | Signals non-memory resources needing deterministic cleanup. Enables `with...as` scoped resource blocks. |
| `Iterator` | Enables `for`-loop iteration, lazy adapter methods (`.map()`, `.filter()`, etc.), and `.collect()` materialization. |
| `IntoIterator` | Enables a type to be used in `for x in expr`. Collections implement this to produce an `Iterator`. |

The `Closeable` trait is the simplest:

```blink
trait Closeable {
    fn close(self)
}
```

A type implementing `Closeable` holds resources (file handles, sockets, locks, database cursors) that must be released deterministically — not when the GC gets around to it, but at a specific point in the program. The `with...as` construct (section 2.18, section 5.5) guarantees `close()` is called on all exit paths.

```blink
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

The compiler uses `Closeable` to power the ScopedValueWithoutWith lint (warn when a `Closeable` or `BlockHandler` value does not go into a `with`) and errors E0601/E0602 (closeable escapes scope). See section 5.5 for the full mechanism.

#### §3.6.1 Derive Mechanics

The `@derive` annotation (§11.1) instructs the compiler to auto-generate trait implementations. Eight traits are derivable in v1: `Eq`, `Ord`, `Hash`, `Clone`, `Display`, `Debug`, `Serialize`, `Deserialize`.

##### Derivable Trait Declarations

For reference, the eight derivable traits and their required methods:

| Trait | Method | Supertrait |
|-------|--------|------------|
| `Eq` | `fn eq(self, other: Self) -> Bool` | — |
| `Ord` | `fn cmp(self, other: Self) -> Ordering` | `Eq` |
| `Hash` | `fn hash(self) -> U64` | `Eq` |
| `Clone` | `fn clone(self) -> Self` | — |
| `Display` | `fn fmt(self, mut sb: StringBuilder)` (the trait supplies `final fn display(self) -> Str`; see *Display Trait Shape*) | — |
| `Debug` | `fn debug(self) -> Str` | — |
| `Serialize` | `fn to_json(self) -> JsonValue` | — |
| `Deserialize` | `fn from_json(json: JsonValue) -> Result[Self, JsonError]` | — |

##### Clone Semantics

`clone()` on a struct or enum equals a copy on bind. Shared cells (§3.6 *Shared cells*) stay shared; a clone does not copy their contents. `Clone` exists so generic code with a `T: Clone` bound can copy a value.

- **Value types** (`Int`, `Float`, `Bool`, `Char`, `Str`): a copy of the value. A `Str` cannot change, so no program can see whether a copy shares its bytes.
- **`List`, `Map`, `Set` and other shared cells** (§3.6 *Shared cells*): the clone refers to the same cell. A change made through the clone **does** show in the original — the same as JS spread (`{...obj}`) or Python `copy.copy()`.
- **User structs and enums**: `x.clone()` gives the same value as `let y = x`. Each field is copied by its declared type, using the rules above. A field whose declared type is a struct or enum is a value, and its copy is a value too, even when the compiler stores that field out of line (for example, a payload of the enum's own type, §3.4 *Recursive Types*). No program can see whether such storage is shared, because a payload field is not a place (§2.22 *Assignment places*). The compiler may share it.

**Shared storage stays out of places.** Storage the compiler shares between values is never inside a place (§2.22). A feature that would put it inside one must copy that storage before the write, or reject the write.

> **Note (not normative).** Today a derived `clone()` of a struct or enum is one value copy and does not allocate.

```blink
@derive(Clone)
type Tree {
    Leaf
    Node(value: Int, next: Tree)
}

let a = Tree.Node(value: 1, next: Tree.Leaf)
let b = a.clone()          // same value as `let b = a`
```

Deep clone is not provided in v1. A `DeepClone` trait can be added post-v1 for use cases requiring full structural independence.

##### Debug vs Display

`Debug` and `Display` are separate traits with no supertrait relationship.

- **`Debug`** = structural developer representation: `"TypeName { field: value }"`
- **`Display`** = user-facing string (often hand-written): `"Alice (alice@example.com)"`

Key differences:

| Type | `debug()` | `display()` |
|------|-----------|-------------|
| `Str` | `"\"Alice\""` (quoted) | `"Alice"` (unquoted) |
| `Int` | `"42"` | `"42"` |
| `Bool` | `"true"` | `"true"` |
| `Char` | `"'a'"` (single-quoted) | `"a"` (bare) |
| Struct | `"User { name: \"Alice\", age: 30 }"` | User-defined |
| `List[T]` (iff `T: Debug`) | `"[1, 2, 3]"` | — |
| `Option[T]` (iff `T: Debug`) | `"Some(42)"` / `"None"` | — |
| `Map[K,V]` (iff `K: Debug`, `V: Debug`) | `"{\"a\": 1}"` | — |
| `Set[T]` (iff `T: Debug`) | `"{1, 2}"` | — |
| `Result[T,E]` (iff `T: Debug`, `E: Debug`) | `"Ok(42)"` / `"Err(\"io\")"` | — |
| tuple (iff every element is `Debug`) | `"(1, \"a\")"` | `"(1, a)"` |

String interpolation (`"{value}"`) invokes `Display`. Explicit `value.debug()` is required for the structural form.

`List`, `Option`, `Map`, `Set`, `Result` and tuples implement `Debug` **conditionally** — a
`List[T]`, `Option[T]` or `Set[T]` is `Debug` iff `T` is `Debug`; a `Map[K,V]` iff **both** `K` and
`V` are `Debug`; a `Result[T,E]` iff **both** `T` and `E` are `Debug`; a tuple iff every element is
`Debug`. These are the only conditional (constrained) built-in `Debug` instances. They cover the same
types as the conditional `Eq` instances (*Container Equality*), so a value that can be compared can
also be shown, which the assertion built-ins need (§2.20 *Built-in Assertions*). Their element-wise
rendering and the one remaining exclusion (container map keys) are specified in *Container Debug
Rendering* below.

**Scalar debug-forms.** The scalar leaf forms split by whether the type is textual or not. `Int`,
`Float`, `Bool`, and the sized integers render **bare** — their `debug()` equals their `display()`.
The textual scalars render **quoted and escaped** in their own source-literal syntax, so a debug
string is re-readable and unambiguous about its type: `Str.debug()` is double-quoted (`"a".debug()`
is `"\"a\""`), and `Char.debug()` is single-quoted (`'a'.debug()` is `"'a'"`). The single-quote
delimiter keeps a `Char` distinct from a one-character `Str` in debug output, and — because it treats
the character as text rather than its integer code point — keeps `Debug` consistent with `Char` not
being a numeric type (§3c). A `Char` is **never** rendered as its bare code point: `'a'.debug()` is
`'a'`, not `97`.

`Char.debug()` and `Str.debug()` use one escape rule. For each scalar, in order:

1. **Named escape.** If the literal's escape table (§2.4) has a named escape for the scalar, emit
   it. Both types use `\n`, `\r`, `\t`, `\\`, `\b` and `\f`. `Char` also uses `\0` and `\'`.
   `Str` also uses `\"`, `\{` and `\}`.
2. **`\u{h}`.** Else, if the scalar is in the escape class below, emit `\u{h}`, with lowercase hex
   and no leading zeros: `'\u{7}'`, `"\u{1b}"`, `'\u{202e}'`.
3. **Raw.** Else emit the scalar as its UTF-8 character. This covers all other printable ASCII
   and every other non-ASCII scalar.

The escape class is this closed list:

| Range | Scalars |
|---|---|
| U+0000–U+001F | C0 controls (Unicode category Cc) |
| U+007F | DEL (Cc) |
| U+0080–U+009F | C1 controls (Cc) |
| U+200B–U+200F | zero-width space, zero-width non-joiner and joiner, left-to-right and right-to-left marks |
| U+2028–U+2029 | line separator, paragraph separator |
| U+202A–U+202E | bidi embeddings and overrides |
| U+2060–U+2064 | word joiner, invisible operators |
| U+2066–U+2069 | bidi isolates |
| U+FEFF | zero-width no-break space (byte order mark) |

These scalars are controls, or they hide or reorder the text around them on a terminal. A raw
U+202E can reorder a CI log line (Trojan Source, CVE-2021-42574). A raw U+200B makes two strings
that differ look equal in an `assert_eq` diff. **The list is frozen.** It does not follow Unicode
updates, and only a new spec decision can change it: each change alters `debug()` output, and so
golden files, for programs whose source did not change.

The rule gives the invariant that **debug output uses only escapes the lexer accepts**. For every
`Char` `c`, `c.debug()` is a valid char literal that reconstructs `c`. For every `Str` `s`,
`s.debug()` is a valid string literal that reconstructs `s` (round-trip). A `Str` cannot hold NUL,
so `Str.debug()` never needs `\u{0}`.

| `Char` value | `debug()` | | `Char` value | `debug()` |
|---|---|---|---|---|
| `'a'` | `'a'` | | `'\n'` | `'\n'` |
| `'1'` | `'1'` (≠ `Int` `1` → `1`) | | `'\''` | `'\''` |
| `' '` | `' '` | | `'\\'` | `'\\'` |
| `'😀'` | `'😀'` (raw UTF-8) | | `'\0'`, `'\u{0}'` | `'\0'` |
| `'\u{7}'` (BEL) | `'\u{7}'` | | `'\u{8}'` | `'\b'` |
| `'\u{202E}'` | `'\u{202e}'` | | `'\u{41}'` | `'A'` |

| `Str` value | `debug()` |
|---|---|
| `"tab\there"` | `"tab\there"` |
| `"\u{1b}[31m"` | `"\u{1b}[31m"` |
| `"a\u{200B}b"` | `"a\u{200b}b"` |
| `"é\u{1F600}"` | `"é😀"` |

The `Char` debug-form flows unchanged into every container position — a `Char` struct field, a
`List[Char]` element, an `Option[Char]` inner value, and a `Map[Char, V]` key all render via the same
`Char.debug()`, so they agree by construction. A `Map[Char, Int]` with the entry `'a' -> 1` renders
`{'a': 1}`; a `List[Char]` of `['h', 'i']` renders `['h', 'i']`.

##### Display Trait Shape

`Display` has two surfaces, exactly one of which is user-implementable. Implementors write `fmt`; the trait derives `display` from it.

```blink
trait Display {
    fn fmt(self, mut sb: StringBuilder)
    final fn display(self) -> Str {
        let sb = StringBuilder.new()
        self.fmt(sb)
        sb.to_str()
    }
}
```

**`fmt` (push, required).** Pushes the rendered representation into a caller-provided `StringBuilder`. Recursive impls call `child.fmt(sb)` into the *same* builder, giving O(n) composition with no intermediate allocations:

```blink
@derive(Display)
type Point { x: Int, y: Int }

impl Display for Point {
    fn fmt(self, mut sb: StringBuilder) {
        sb.write("(")
        sb.write(self.x)
        sb.write(", ")
        sb.write(self.y)
        sb.write(")")
    }
}
```

`sb.write` takes any `Display` value (§3.2 *String Building*), so `sb.write(self.x)` writes the `Int` field with no `.display()` call. The `io` print functions take the same bound (§4.4):

```blink
fn main() ! IO {
    let p = Point{ x: 3, y: 4 }
    io.println(p)          // "(3, 4)"
    io.println(42)         // "42"
    io.println("at {p}")   // "at (3, 4)"
}
```

**`display` (pull, sealed default).** Marked `final` — it cannot be overridden in any `impl` block. Provides Str-producing ergonomics for sites where no builder is in scope (error paths, test assertions, match arms):

```blink
let p = Point{ x: 3, y: 4 }
let s: Str = p.display()       // "(3, 4)"
```

**Diagnostic: general form.** `E0731 SealedMethodOverride` is the canonical error for any attempt to override a `final` trait default — `Display.display` is the running example here, but the diagnostic shape is the same for every sealed method (`Eq.ne`, `Sized.is_empty`, and user-authored `final` defaults). The span points at the offending `fn` declaration in the `impl` block; the message names the trait and method; the help line points the reader at the method whose body the sealed default derives from (`fmt` for `Display.display`, `eq` for `Eq.ne`, `len` for `Sized.is_empty`).

```
error[SealedMethodOverride]: cannot override sealed method `display`
  --> graphics.bl:18:5
   |
18 |     fn display(self) -> Str { "<custom>" }
   |     ^^^^^^^^^^^^^^^^^^^^^^^ `Display.display` is `final`; only `fmt` is implementable
   |
   = help: implement `fmt(self, sb)` instead — `display` is derived from it
```

**Sealing rationale.** A sealed default makes drift mechanically impossible: `value.display()` and any push-style consumption (interpolation, `sb.write(value)`) are guaranteed to produce identical output, because both route through the same `fmt`. Without sealing, a user `impl` could provide a `display` that diverges from `fmt` — different string for the same value depending on call site.

**Three call shapes, one impl.** Every `T: Display` is consumable three ways, all routing through `fmt`:

| Shape | Lowering | When to use |
|-------|----------|-------------|
| `"{x}"` interpolation | `x.fmt(sb_internal)` | Building a Str literal |
| `x.display()` | `let sb = ...; x.fmt(sb); sb.to_str()` | Need a Str directly |
| `sb.write(x)` | `x.fmt(sb)` | Building into a builder you already own |

The interpolation lowering (built-in fast-path optimization aside) and the `display` derivation share the same call: `x.fmt(sb)`. They cannot disagree.

**`fmt` has no effect row.** `Display.fmt` declares no `!`, and that empty row is its contract. A function with no `!` performs no side effects (§4.1), and no impl may widen a trait method's row (§3.6 *Effect-row subtype for trait impls*). So no `fmt` impl can perform IO or use any other capability, and `"{x}"`, `x.display()` and `sb.write(x)` never need an effect or a handler in scope. An impl whose `fmt` declares an effect is rejected with `TraitContractEffectMismatch` (E0904). Writing into the supplied `sb` is not an effect: it mutates a parameter, which neither the effect row nor mutation analysis tracks (§4.16.2). Access to module-level `let mut` bindings is governed by §4.16, not by the effect row. There is no `StringBuilderPure` effect; `fmt(self, sb: StringBuilder) ! StringBuilderPure` names an undeclared effect.

##### Display Format Protocol

String interpolation `"hello {name}"` desugars to a string concatenation where each `{expr}` requires `T: Display` at compile time. The protocol has three aspects: requirement enforcement, desugaring mechanism, and context-sensitive behavior.

**Requirement: strict compile error.** Every `{expr}` in a string literal requires the expression's type to satisfy `T: Display`. If the type does not implement `Display`, the compiler emits an error:

```
error[E0523]: type `Matrix` does not implement `Display`
  --> app.bl:12:34
   |
12 |     let s = "result: {matrix}"
   |                       ^^^^^^ `Matrix` does not implement `Display`
   |
   = help: add `@derive(Display)` or implement `Display` manually
   = note: use `matrix.debug()` for structural representation
```

Built-in types (`Int`, `Float`, `Bool`, `Str`, `Char`) have compiler-provided `Display` implementations. User types require `@derive(Display)` or a manual `impl Display for T` block. There is no fallback to `Debug` and no auto-synthesis — the trait bound is checked like any other.

**The intrinsic seam.** These five impls are prelude impls whose `fmt` body the compiler provides. They are the only `fmt` bodies that do not call `sb.write`, and the list is closed: every other `Display` impl, including every derived one, writes through `sb.write`, `sb.write_char` or a child's `fmt`. `Str.fmt` appends the receiver's bytes to the builder directly; it does not call `sb.write`, so `sb.write(s)` for a `Str` lowers to `s.fmt(sb)` and stops there. `Str.display()` returns a `Str` equal to the receiver. (Implementation note: the compiler-provided impl may return the receiver without a copy.)

**Every Display sink uses the same bound.** `"{x}"`, `x.display()`, `sb.write(x)` (§3.2 *String Building*) and the `io` print functions (§4.4) each require `T: Display` and nothing else. A `Str` argument is one `Display` type among five; it takes no separate path in the type system. A value that fails the bound at any of these sinks, or at any other call whose type parameter is bounded by `Display`, gets the same `MissingDisplayImpl` (E0523) error. The message names the sink and the span covers the argument:

```
error[E0523]: type `Matrix` does not implement `Display`
  --> app.bl:14:14
   |
14 |     sb.write(matrix)
   |              ^^^^^^ `Matrix` does not implement `Display`, which `StringBuilder.write` requires
   |
   = help: add `@derive(Display)` or implement `Display` manually
   = note: use `matrix.debug()` for structural representation
```

A `Raw[T]` argument is the one exception: it reports `RawOutsideTemplate` (§3b.5 *`Raw(expr)` — The Escape Hatch*), not E0523.

**Desugaring: two-phase (check + optimize).** The compiler processes string interpolation in two phases:

1. **Type check phase:** Verify `T: Display` for every `{expr}`. This is a standard trait bound check — identical to requiring `T: Eq` for equality comparison.

2. **Codegen phase:** Optimize based on type knowledge:
   - **Built-in types** (`Int`, `Float`, `Bool`, `Char`): emit direct format specifiers (`%d`, `%f`, `%s`, etc. in C backend). No function call overhead.
   - **`Str`**: emit direct string concatenation. No conversion needed.
   - **User types**: emit `expr.fmt(sb_internal)` — a direct push into the interpolation's internal `StringBuilder`. No intermediate `Str` allocation per interpolation slot, even for deeply nested types.

Example desugaring:

```blink
let name = "Alice"
let age = 30
let msg = "hello {name}, you are {age} years old"

// Type check: Str: Display ✓, Int: Display ✓
// Codegen (conceptual C):
//   snprintf(buf, ..., "hello %s, you are %d years old", name, age)
```

```blink
@derive(Display)
type Point { x: Float, y: Float }

let p = Point { x: 1.0, y: 2.5 }
let msg = "at {p}"

// Type check: Point: Display ✓ (via @derive)
// Codegen (conceptual C):
//   StringBuilder sb = sb_new();
//   sb_write_str(sb, "at ");
//   Display_fmt_Point(p, sb);     // pushes "Point { x: 1.0, y: 2.5 }" into sb
//   Str msg = sb_to_str(sb);
```

The two-phase approach preserves the semantic guarantee (every interpolated type has a Display impl) while allowing the C backend to use efficient format specifiers for built-in types. This matches the current compiler's existing snprintf-based codegen.

**Template[C] context: Display not invoked.** In `Template[C]` typed strings (§3b.5), interpolation has different semantics — `{expr}` is decomposed into the `values` list as a typed value, not concatenated via Display. Display is **not** invoked in Template context:

```blink
let id = 42
let name = "Alice"

// Normal Str context — Display invoked:
let msg = "user {id}: {name}"           // "user 42: Alice"

// Template[DB] context — Display NOT invoked:
let q: Template[DB] = "SELECT * FROM users WHERE id = {id} AND name = {name}"
// q.parts()  == ["SELECT * FROM users WHERE id = ", " AND name = ", ""]
// q.values() == [TemplateValue.Int(42), TemplateValue.Str("Alice")]   ← typed values, not strings
```

The set of types valid as Template values is compiler-known: `Int` and the narrower integers `I8`, `I16`, `I32`, `U8`, `U16`, `U32` (widened to `Int`), `Float` and `F32` (widened to `Float`), `Bool`, `Str`, and `Option[T]` where `T` is one of these (`None` becomes `TemplateValue.Null`). `Option[Option[T]]` is not valid. Any other type in a Template interpolation is `error[TemplateHoleType]` at typecheck, with repairs that keep the value a parameter (§3b.5 *Template Values*). The `Raw(expr)` marker type bypasses decomposition for a specific interpolation (see §3b.5).

This separation is critical: calling `Display.display()` first and then decomposing the resulting `Str` would defeat `Template[C]`'s injection safety by losing type information and forcing all values through string round-tripping.

##### Product Type Codegen (Structs)

For a product type, derived traits operate field-by-field in declaration order:

```blink
@derive(Eq, Clone, Debug)
type User { name: Str, email: Str, age: Int }

// Eq: field-wise equality
// generates:
impl Eq for User {
    fn eq(self, other: Self) -> Bool {
        self.name.eq(other.name) && self.email.eq(other.email) && self.age.eq(other.age)
    }
}

// Clone: field-wise value copy
// generates:
impl Clone for User {
    fn clone(self) -> Self {
        User { name: self.name, email: self.email, age: self.age }
    }
}

// Debug: structural representation
// generates:
impl Debug for User {
    fn debug(self) -> Str {
        "User { name: {self.name.debug()}, email: {self.email.debug()}, age: {self.age.debug()} }"
    }
}
```

Per-trait product type rules:

| Trait | Generated body |
|-------|---------------|
| `Eq` | `self.f1.eq(other.f1) && self.f2.eq(other.f2) && ...` |
| `Ord` | Lexicographic: compare `f1`, if `Equal` compare `f2`, ... |
| `Hash` | Combine field hashes with mixing: `hash(f1) ^ hash(f2) ^ ...` |
| `Clone` | `Type { f1: self.f1, f2: self.f2, ... }`: the same value as a copy on bind (§3.6.1 *Clone Semantics*) |
| `Display` | `fmt`: `sb.write(self.f1); sb.write(", "); sb.write(self.f2); ...` (comma-separated, push-style) |
| `Debug` | `"TypeName { f1: {f1.debug()}, f2: {f2.debug()}, ... }"` |

##### Sum Type Codegen (Enums)

For a sum type, derived traits match on variant pairs:

```blink
@derive(Eq, Debug)
type Color { Red, Green, Blue, Custom(r: U8, g: U8, b: U8) }

// Eq: match variant pairs, field-wise comparison
// generates:
impl Eq for Color {
    fn eq(self, other: Self) -> Bool {
        match (self, other) {
            (Red, Red) => true
            (Green, Green) => true
            (Blue, Blue) => true
            (Custom(r1, g1, b1), Custom(r2, g2, b2)) =>
                r1.eq(r2) && g1.eq(g2) && b1.eq(b2)
            _ => false
        }
    }
}

// Debug: variant name + fields
// generates:
impl Debug for Color {
    fn debug(self) -> Str {
        match self {
            Red => "Red"
            Green => "Green"
            Blue => "Blue"
            Custom(r, g, b) => "Custom({r.debug()}, {g.debug()}, {b.debug()})"
        }
    }
}
```

Per-trait sum type rules:

| Trait | Generated body |
|-------|---------------|
| `Eq` | Match variant pairs; field-wise eq within same variant; `_ => false` for mismatched variants |
| `Ord` | Compare variant index first; if same variant, field-wise lexicographic comparison |
| `Hash` | Hash variant index, then hash fields of data-carrying variants |
| `Clone` | The same value as a copy on bind (§3.6.1 *Clone Semantics*) |
| `Display` | Variant name for unit variants; `"Variant(f1, f2)"` for data-carrying. Exception: a Str-backed enum writes its backing literal, so the output equals `to_str()` (§3.4 *Str-Backed Enums*) |
| `Debug` | `"Variant"` for unit variants; `"Variant({f1.debug()}, {f2.debug()})"` for data-carrying |

##### Container Debug Rendering

A field of a `@derive(Debug)` type may be a container — `List[T]`, `Option[T]`, `Map[K,V]`,
`Set[T]`, `Result[T,E]` or a tuple. The
uniform per-field model (each field renders via `{field.debug()}`) holds: the container's own
`debug()` renders its contents, with every element, key, and value rendered in **debug-form** (so a
`Str` element is quoted and escaped, matching `Str.debug()`). The compiler provides these `debug()`
implementations as **conditional (constrained) built-in instances** — a container is
Debug-renderable iff its type argument(s) are themselves `Debug`.

**Format.** Each container renders as follows. Separators are `, ` between elements/entries and `: `
between a map key and its value; there is no inner padding.

| Type | `debug()` format | Empty |
|------|------------------|-------|
| `List[T]` | `"[" + elems.join(", ") + "]"`, each elem via its own `.debug()` | `"[]"` |
| `Option[T]` | `"Some(" + inner.debug() + ")"` when present | `"None"` (bare, no parens) |
| `Map[K,V]` | `"{" + entries.join(", ") + "}"`, each entry `key.debug() + ": " + value.debug()` | `"{}"` |
| `Set[T]` | `"{" + elems.join(", ") + "}"`, each elem via its own `.debug()`, in sorted order (below) | `"{}"` |
| `Result[T,E]` | `"Ok(" + value.debug() + ")"` or `"Err(" + error.debug() + ")"` | — |
| tuple | `"(" + elems.join(", ") + ")"`, each elem via its own `.debug()` | — |

**Set element order.** `Set[T].debug()` sorts the rendered element strings by their UTF-8 bytes
before it joins them. It does not use iteration order. The hash seed changes per process (*Hash
Contract and Seeding*), and two equal sets can hold their elements in different orders after
different insert and remove histories, so iteration order would break the rule that
`a == b` gives `a.debug() == b.debug()`. Sorting by the debug string needs no `Ord` bound. The order
is by text, not by value: a `Set[Int]` of 1, 2 and 10 renders `{1, 10, 2}`. An empty `Set` renders
`{}`, the same text as an empty `Map`; the static type tells them apart.

```blink
@derive(Debug)
type Inventory { items: List[Str], count: Option[Int], tags: Map[Str, Int] }

let mut tags: Map[Str, Int] = Map()
tags.insert("rare", 1)
let inv = Inventory { items: ["sword", "shield"], count: Some(2), tags: tags }
inv.debug()
// => "Inventory { items: [\"sword\", \"shield\"], count: Some(2), tags: {\"rare\": 1} }"
```

`Str` elements render quoted because the elements use debug-form: `List[Str]` of `["a", "b"]`
renders `["a", "b"]` (with the inner quotes), and a `Map[Str, Int]` with the entry `"a" -> 1`
renders `{"a": 1}`. `Char` elements likewise render single-quoted (`List[Char]` of `['a', 'b']`
renders `['a', 'b']`), per the scalar debug-forms rule above. Numeric scalar elements render bare:
`List[Int]` of `[1, 2, 3]` renders `[1, 2, 3]`.

**Conditional Debug — non-Debug element, key, or value.** A container field is Debug-renderable
only when its type argument(s) are `Debug`. If an element type, a map key type, or a map value type
does not itself implement `Debug`, the derive is rejected with **`E0520`** (`DeriveDebugFieldNoDebug`,
the same code raised for a direct non-Debug field in *Error Reporting* below) naming the offending
inner type. The check peels the container and recurses on the element type — and on **both** `K` and
`V` for a `Map`. There is no placeholder for the
non-Debug case: rendering `<?>` (or any silent stand-in) is forbidden, because it would relocate the
banned silent fallback (the panel's 5-0 rule against `[object Object]`-style fallbacks, *Display
Format Protocol*) one level down.

One container shape stays rejected with `E0520` at **every** level of nesting (not just the top
field): a `Map` whose **key** type is itself a container (`Map[List[Int], V]`, `Map[(Str, Int), V]`,
etc.), and for the same reason a `Set` whose **element** type is a container. Map keys and set
elements must be a scalar (`Str` / `Char` / `Int` / `Bool` / sized-int) or a struct that implements
`Debug`, `Hash` and `Eq`. (Container-typed map *values* render fine; only container keys and set
elements are excluded, because the renderer reads them back through the key-ops storage layer, which
has no descriptor for a container key.) Outside a derive, the same shape fails a `T: Debug` bound
with `E0306`, and the note names the container key type.

`Set` and `Result` were excluded from `Debug` until the assertion bound changed from `Display` to
`Debug`. The record gave no reason for that exclusion other than scope, and assertions need every
`Eq` container to be `Debug`, so the panel extended this decision to `Set`, `Result` and tuples
(vote: 6-0; see [assert_eq Debug bound](../decisions/assert-eq-debug-bound.md)).

```blink
type Plain { a: Int }              // does NOT derive Debug

@derive(Debug)
type Bad { items: List[Plain] }    // E0520 — element type `Plain` does not derive Debug
```

**Nested containers.** Container Debug is **fully recursive** by composition: a container whose
element, key, or value type is itself a (renderable) container renders through the composed
`debug()` of each level. There is no depth cap.

```blink
@derive(Debug)
type Nested { grid: List[List[Int]] }
Nested { grid: [[1, 2], [3]] }.debug()   // => "Nested { grid: [[1, 2], [3]] }"

@derive(Debug)
type Deep { m: Map[Str, List[Int]] }     // => "Deep { m: {\"a\": [1, 2]} }"

@derive(Debug)
type Maybe { xs: Option[List[Int]] }     // Some([1, 2]) => "Maybe { xs: Some([1, 2]) }"
```

The rule is fully inductive in both the **typecheck** and the **emitter**. The typechecker recurses
to prove every nested element / key / value type is `Debug` (rejecting non-Debug types and
container map keys or set elements at any level). The emitter materializes one recursive per-monomorphization
`debug()` function per distinct nested container shape (mirroring the arena-promotion descriptor
walker); these functions call each other, so an arbitrarily deep type renders through a chain of
composed calls with the no-silent-fallback invariant preserved at every level. See
[Container Debug rendering](../decisions/debug-container-rendering.md) for the full deliberation.

**Enum-variant fields.** Container Debug applies to struct fields **and** enum-variant fields alike;
both routes share the same generated recursive `debug()` functions.

```blink
@derive(Debug)
type E { V(items: List[Int]) }
E.V([1, 2]).debug()                      // => "V([1, 2])"
```

##### Generic Type Bound Inference

When deriving for a generic type, the compiler **infers** trait bounds on type parameters from field usage:

```blink
@derive(Eq)
type Pair[A, B] { first: A, second: B }

// generates with inferred bounds:
impl Eq for Pair[A, B] where A: Eq, B: Eq {
    fn eq(self, other: Self) -> Bool {
        self.first.eq(other.first) && self.second.eq(other.second)
    }
}
```

The compiler inspects each field's type. If a field has type `A`, and the derived trait requires calling `.eq()` on that field, then `A: Eq` is added as a bound. Concrete types (e.g., `Int`) are checked at derive time — if `Int` doesn't implement the trait, it's an error (see Error Reporting below).

For `@derive(Eq)`, a container or tuple field is checked by the rule in *Container Equality* (§3.6): `items: List[Item]` derives when `Item` is `Eq`, and `E1401 NonDerivableTrait` names `Item` when it is not. A field `List[A]` adds the bound `A: Eq`.

##### Supertrait Auto-Derivation

Some traits have supertraits: `Ord` requires `Eq`, `Hash` requires `Eq`. When deriving a trait with a supertrait requirement:

1. If the supertrait is already implemented (explicit `impl` or prior `@derive`), use the existing implementation
2. If not, the compiler auto-derives the supertrait

This means `@derive(Ord)` implicitly derives `Eq` if not already present. Redundant listing like `@derive(Eq, Ord)` is allowed — no error, no warning. The `Eq` derivation happens once regardless.

##### Error Reporting

When `@derive` fails because a field's type doesn't implement the required trait, the compiler reports **all** non-derivable fields in a single diagnostic (not just the first):

```
error[NonDerivableTrait]: cannot derive `Hash` for `Measurement`
 --> myfile.bl:1:9
  |
1 | @derive(Hash)
  |         ^^^^ cannot derive `Hash`
  |
 --> myfile.bl:3:5
  |
3 |     temperature: Float
  |     ^^^^^^^^^^^^^^^^^^ `Float` does not implement `Hash`
  |
 --> myfile.bl:4:5
  |
4 |     weight: Float
  |     ^^^^^^^^^^^^^ `Float` does not implement `Hash`
  |
  = help: remove `Hash` from @derive, or implement `Hash` manually
```

All failing fields are reported in one pass so the developer can fix everything at once.

For `@derive(Debug)` specifically, the per-field check fires **`E0520 DeriveDebugFieldNoDebug`** when
a field's type has no `debug()` to call. For a **container** field (`List[T]` / `Option[T]` /
`Set[T]` / `Map[K,V]` / `Result[T,E]` / tuple), the check peels the container and recurses on each
type argument — **both** `K` and `V` for a `Map`, **both** `T` and `E` for a `Result`, every element
of a tuple — so `E0520` also names a non-Debug *element/key/value* type at any depth. See *Container
Debug Rendering* above.

#### §3.6.2 Serialization Traits

Blink provides compiler-known `Serialize` and `Deserialize` traits for JSON serialization. These are Tier 1 (ship with the compiler) and derivable via `@derive`.

> **Spec-only.** The compiler does not build `JsonValue` or `JsonError` yet, so this section describes the language, not the current compiler. Today a derived `to_json` returns JSON text as `Str`, and a derived `from_json` takes a `Str` and returns `Result[Self, Str]`. That Str surface is not part of the language: it becomes `json.encode` and `json.decode[T]` (§3.6.3). Built today: `@derive(Serialize, Deserialize)` on structs and enums (with the Str signatures), and Str-backed enums (§3.4). Each part of this note goes when the compiler builds that part.

##### Trait Declarations

```blink
trait Serialize {
    fn to_json(self) -> JsonValue
}

trait Deserialize {
    fn from_json(json: JsonValue) -> Result[Self, JsonError]
}
```

`JsonValue` is a compiler-known enum representing the JSON data model:

```blink
type JsonValue {
    Null
    Bool(value: Bool)
    Int(value: Int)
    Float(value: Float)
    Str(value: Str)
    Array(items: List[JsonValue])
    Object(fields: List[(Str, JsonValue)])
}
```

`Object` keeps its entries in input order and keeps duplicate keys, so `json.stringify(json.parse(s)?)` does not drop or reorder them. Where a key occurs more than once, a lookup takes the **first** entry with that key. This holds for `JsonValue.get` (§3.6.3) and for derived `from_json`.

`JsonError` is a single error type covering both serialization and deserialization failures:

```blink
type JsonError {
    message: Str
    path: Str
}
```

**`path`** tells where in the value a decode error happened. It starts with `$`, the whole value. Each step adds `.name` for an object key or `[i]` for an array index: `$.items[2].age`. A key that is not an identifier is written as `["key"]`, in JSON string syntax: `$.headers["content-type"]`. A `path` of `""` means the location is not known. A parse error has `path: ""`, and so does an error that a hand-written `from_json` builds without a path.

When a derived `from_json` calls `from_json` for a field and gets `Err(e)`, it returns `e` with its own step put in `e.path` just after the `$`. A nested error from `$.age` in field `owner` becomes `$.owner.age`. A nested error with `path: ""` becomes `$.owner`. So a hand-written impl deep in the value still gets a path up to its own position.

**`message`** is text for people. The spec fixes only its location content:

- A parse error's `message` contains `line L, column C`. Both count from 1. Lines are split at `\n` (U+000A). The column counts bytes from the start of the line, the same unit as `Str.len()`.
- A decode error whose `path` is not `""` has a `message` that contains `at <path>`, for example `at $.items[2].age`.

The rest of the wording is not fixed, except that `json.decode[T]` and its two-step form give the same text (§3.6.3 *Typed Decoding and Encoding*).

##### Derive Behavior

`@derive(Serialize)` generates a `to_json` implementation that converts each field to a `JsonValue` and wraps them in `JsonValue.Object`. Field names in JSON match struct field names exactly — no renaming in v1.

```blink
@derive(Serialize, Deserialize)
type Forecast {
    city: Str
    temp_c: Float
    summary: Str
}

// Generated Serialize impl (conceptual):
impl Serialize for Forecast {
    fn to_json(self) -> JsonValue {
        JsonValue.Object([
            ("city", JsonValue.Str(self.city)),
            ("temp_c", JsonValue.Float(self.temp_c)),
            ("summary", JsonValue.Str(self.summary))
        ])
    }
}

// Generated Deserialize impl (conceptual):
impl Deserialize for Forecast {
    fn from_json(json: JsonValue) -> Result[Forecast, JsonError] {
        // Extract fields from JsonValue.Object, type-check each
    }
}
```

A derived `from_json` reads each field from the first object entry with that field's name. It fills in the `path` of every error it returns.

##### Numbers

JSON has one number type. `JsonValue` has two, and these rules decide between them:

- `json.parse` gives `JsonValue.Int` when the number has no fraction and no exponent and its value fits in `Int` (64-bit signed). It gives `JsonValue.Float` in every other case: `20` is `Int`, `20.0` and `2e1` are `Float`.
- **An integer outside the `Int` range becomes a `Float` and loses precision.** `json.parse("18446744073709551615")` gives `Ok(JsonValue.Float(18446744073709551616.0))`, not an error. To keep a large ID exact, send it as a JSON string and give the field the type `Str`.
- A derived `from_json` for a `Float` field accepts `JsonValue.Int` and converts it, so `{"temp_c": 20}` decodes into `temp_c: Float`.
- A derived `from_json` for an `Int` field accepts only `JsonValue.Int`. It never narrows a `Float`, not even `3.0`.
- `as_float()` on a `JsonValue.Int` gives `Some`. `as_int()` on a `JsonValue.Float` gives `None`.

##### Str-Backed Enums

With `@derive(Serialize)`, a Str-backed enum (§3.4) serializes as `JsonValue.Str(x.to_str())`. With `@derive(Deserialize)`, `from_json` accepts `JsonValue.Str(s)` and returns `Ok(v)` exactly when `T.from_str(s) == Some(v)`. Every other value is an error.

When the input is a string that is not a backing literal, the `JsonError` message names the rejected value, the enum type, and every valid literal in declaration order. For a long enum, the message may list the first N literals and give the count of the rest. For example (the wording is not fixed):

```
unknown value "closed" for Status at $.status; expected one of: "open", "in_progress", "done"
```

##### Type Mapping

| Blink Type | JSON Representation |
|-----------|-------------------|
| `Int` | `JsonValue.Int` |
| `Float` | `JsonValue.Float` |
| `Bool` | `JsonValue.Bool` |
| `Str` | `JsonValue.Str` |
| `Option[T]` | `JsonValue.Null` for `None`, `T.to_json()` for `Some(v)` |
| `List[T]` | `JsonValue.Array` |
| Struct with `@derive(Serialize)` | `JsonValue.Object` |
| Enum with `@derive(Serialize)`, not Str-backed | Tagged object: `{"variant": "Name", "fields": {...}}` |
| Str-backed enum with `@derive(Serialize)` | `JsonValue.Str` of its backing literal: `"in_progress"` |

##### Purity

Serialization is pure — `to_json()` returns a `JsonValue` with no effects. IO effects (writing to network, file) belong exclusively to the call site:

```blink
let json_val = forecast.to_json()       // pure: data → data
let json_str = json.stringify(json_val)  // pure: JsonValue → Str
fs.write(file, json_str)?               // effectful: ! FS.Write
```

##### Usage

```blink
@derive(Serialize, Deserialize)
type User { id: Int, name: Str, email: Str }

// Serialize
let user = User { id: 1, name: "Alice", email: "alice@example.com" }
let json_val = user.to_json()

// Deserialize
let parsed = User.from_json(json_val)?

// With Response helper (see HTTP types)
let response = Response.json(user)  // calls user.to_json() internally
```

##### Derive Bounds

Like other derived traits, `@derive(Serialize)` on a generic type infers bounds:

```blink
@derive(Serialize)
type Pair[A, B] { first: A, second: B }

// generates with inferred bounds:
impl Serialize for Pair[A, B] where A: Serialize, B: Serialize {
    fn to_json(self) -> JsonValue { ... }
}
```

##### JSON Text Is Not a `JsonValue`

Many languages name the method that returns JSON text `to_json`. In Blink, `to_json` returns a `JsonValue` and `from_json` takes one, so code written the other way is a type error. The compiler reports it as `error[JsonTextForValue]` (E0537) when:

- a `Str` is the argument to a `from_json` that takes a `JsonValue`, or
- the result of `to_json()` is used where a `Str` is required.

The diagnostic names `json.decode[T]` or `json.encode` as the replacement, and it carries a machine-applicable fix:

```blink
let u = User.from_json(body)?     // error[JsonTextForValue]: body is Str
let u = json.decode[User](body)?  // fix

let text: Str = u.to_json()       // error[JsonTextForValue]: to_json gives JsonValue
let text = json.encode(u)         // fix
```

The code, the trigger, the named replacements and the fix are part of the language. The message text is not.

#### §3.6.3 JSON Codec Module

The `std.json` module provides the public API for JSON parsing, serialization, and typed deserialization. All functions are pure — IO effects belong to the caller.

> **Spec-only.** The compiler does not build this module surface yet: none of `parse`, `stringify`, `pretty`, `decode`, `encode` or the `JsonValue` methods exist. Today `lib/std/json.bl` ships an integer-handle API (`json_parse`, `json_get`, `json_serialize`, `json_clear` and others). That API is not part of the language. It leaves the public surface in the release where `JsonValue` lands. Each part of this note goes when the compiler builds that part.

`std.json` keeps no global shared mutable state. A `JsonValue` is an ordinary value, and no call changes or frees a value that another caller holds. This also holds for any private store or cache behind the module.

##### Module API

```blink
import std.json

// Parse JSON string into dynamic JsonValue tree
json.parse(input: Str) -> Result[JsonValue, JsonError]

// Convert JsonValue tree to compact JSON string
json.stringify(value: JsonValue) -> Str

// Pretty-print JsonValue with indentation
json.pretty(value: JsonValue) -> Str

// Typed deserialization: parse string directly into T
json.decode[T: Deserialize](input: Str) -> Result[T, JsonError]

// Typed serialization shortcut: T → JSON string
json.encode[T: Serialize](value: T) -> Str
```

`json.decode[T]` is sugar for the two-step path `json.parse(s) |> T.from_json()`. The `Deserialize` trait's `from_json` method (§3.6.2) takes `JsonValue` — this is the canonical deserialization interface. `json.decode[T]` composes parse and from_json for convenience.

`json.encode[T]` is sugar for `json.stringify(value.to_json())`.

##### Typed Decoding and Encoding

The spec defines `json.encode` and `json.decode[T]` by their results, not by how they compute them:

- `json.encode(x)` returns the same `Str` as `json.stringify(x.to_json())`.
- `json.decode[T](s)` returns a `Result` equal to the result of this two-step form:

  ```blink
  match json.parse(s) {
      Ok(v) => T.from_json(v)
      Err(e) => Err(e)
  }
  ```

"Equal" includes every `JsonError` field: the same `path` and the same `message` text. Both paths accept the same inputs, give the same `Ok` values, and follow the number rules and the first-match key rule of §3.6.2.

An implementation may fuse the two steps into a reader or writer per type that builds no `JsonValue` tree. Only derived impls may fuse. When a field's type has a hand-written `Deserialize`, the fused reader parses that field's part of the input into a `JsonValue` and calls that type's `from_json`.

##### Dynamic Navigation (JsonValue Methods)

`JsonValue` provides navigation methods returning `Option` for partial access into the JSON tree. Navigation is inherently partial — a key may not exist, an index may be out of bounds, a value may not be the expected type. `Option` is the canonical encoding of partiality in Blink, composing naturally with `?` (early return) and `??` (default value).

```blink
// Structural navigation
fn get(self, key: Str) -> Option[JsonValue]    // object field lookup; first entry with the key
fn at(self, index: Int) -> Option[JsonValue]   // array index access
fn len(self) -> Int                            // array/object child count
fn keys(self) -> List[Str]                     // object keys (empty for non-objects)

// Type projection
fn as_str(self) -> Option[Str]
fn as_int(self) -> Option[Int]
fn as_float(self) -> Option[Float]
fn as_bool(self) -> Option[Bool]

// Type testing
fn is_null(self) -> Bool
fn is_str(self) -> Bool
fn is_int(self) -> Bool
fn is_float(self) -> Bool
fn is_bool(self) -> Bool
fn is_array(self) -> Bool
fn is_object(self) -> Bool
```

##### Usage: Dynamic Path (unknown or polymorphic JSON)

```blink
fn parse_forecast(city: Str, body: Str) -> Result[Forecast, WeatherError] {
    let json = json.parse(body).map_err(fn(e) { WeatherError.ParseFailed(e.message) })?
    Ok(Forecast {
        city: city
        temp_c: json.get("temp_c")?.as_float() ?? 0.0
        summary: json.get("summary")?.as_str() ?? "Unknown"
    })
}
```

##### Usage: Typed Path (known struct shape)

```blink
@derive(Serialize, Deserialize)
type Forecast {
    city: Str
    temp_c: Float
    summary: Str
}

// One-step: string → typed struct
let forecast = json.decode[Forecast](body)?

// Two-step: string → JsonValue → typed struct
let val = json.parse(body)?
let forecast = Forecast.from_json(val)?

// Serialize: typed struct → string
let output = json.encode(forecast)

// Pretty-print for debugging
io.println(json.pretty(forecast.to_json()))
```

##### Usage: Mixed (partially typed)

When JSON contains a known envelope with dynamic payload:

```blink
@derive(Deserialize)
type ApiResponse {
    status: Int
    data: JsonValue
}

let response = json.decode[ApiResponse](body)?
if response.status == 200 {
    let name = response.data.get("user")?.get("name")?.as_str() ?? "anonymous"
    io.println("Hello, {name}")
}
```

##### Pattern Matching on JsonValue

Since `JsonValue` is an enum, pattern matching works directly:

```blink
fn describe(val: JsonValue) -> Str {
    match val {
        JsonValue.Null => "null"
        JsonValue.Bool(b) => "bool: {b}"
        JsonValue.Int(n) => "int: {n}"
        JsonValue.Float(f) => "float: {f}"
        JsonValue.Str(s) => "string: {s}"
        JsonValue.Array(items) => "array of {items.len()}"
        JsonValue.Object(fields) => "object with {fields.len()} fields"
    }
}
```

---

### 3.7 No Null, No Exceptions

These are not restrictions. They are the elimination of two categories of bugs that account for more production incidents than any other.

#### No Null

There is no `null`, `nil`, `None`-as-implicit-value, or bottom type that inhabits every type. A `Str` is always a string. An `Int` is always an integer. If a value might be absent, the type says so:

```blink
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

```blink
fn find_user(id: Int) -> User? ! DB      // same as Option[User]
fn get_config(key: Str) -> Str?           // same as Option[Str]
```

#### No Exceptions

There is no `throw`, no `try/catch`, no unchecked exceptions, no exception hierarchy. Operations that can fail return `Result[T, E]`:

```blink
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

**Null**: AI models produce null-related bugs at a rate proportional to how easy the language makes it to forget null checks. In languages with null, every reference is implicitly `T | null`, and every dereference is an implicit null check that the programmer (or AI) might forget. In Blink, if a value can be absent, the type says `Option[T]`, and the compiler refuses to let you use it as a `T` without handling the `None` case. The bug category is structurally eliminated.

**Exceptions**: Exceptions create invisible control flow. A function signature says `fn process(data: Str) -> Report`, but the function might throw `IOException`, `ParseException`, `ValidationException`, or anything its callees throw. The signature lies. An AI reading the signature gets incomplete information. In Blink, the same function says `fn process(data: Str) -> Result[Report, ProcessError] ! IO` -- complete, honest, compiler-checked.

The `?` operator is one character with unambiguous semantics. Compare to try/catch blocks where AI commonly generates: wrong catch order, overly broad catches (`catch (Exception e)`), missing finally clauses, and incorrect resource cleanup. The `?` operator has one behavior. There's nothing to get wrong.

---

### 3.8 Tuple Types

Tuples are anonymous product types — fixed-size, heterogeneous, ordered collections of values. They serve as lightweight grouping for returning multiple values, iterating over key-value pairs, and passing small bundles of data without defining a named struct.

#### Syntax

```blink
// Type position
(Int, Str)
(Bool, Int, Float)
(T, Stack[T])

// Value construction
let pair = (42, "hello")
let triple = (true, 1, 3.14)

// Element access — positional, zero-indexed
pair.0          // 42
pair.1          // "hello"
triple.2        // 3.14

// Destructuring
let (code, message) = get_status()
let (key, value) = entry

// In function signatures
fn pop[T](stack: Stack[T]) -> (T, Stack[T]) {
    // ...
}

// As generic parameters
fn zip[T, U](a: Iterator[T], b: Iterator[U]) -> Iterator[(T, U)] {
    // ...
}
```

#### Unit Type

The unit type `()` is the 0-tuple — the type with exactly one value, carrying no information. It is the canonical "no meaningful value" type: the implicit return type of functions and blocks that produce no value, and the success payload of a fallible operation that returns nothing (`Result[(), E]`). `()` is an ordinary inhabited, encodable type — it has a value and a representation, so it can be returned, stored in a field, and used as a generic argument.

```blink
fn log(msg: Str) ! IO {
    io.println(msg)
}
// return type is (), omitted by convention
```

`()` is **not** `Void`. `Void` (§9.1.1) is the FFI-only marker for C's incomplete `void` pointee type; it has no value representation and is well-formed only as the argument of `Ptr[_]` (`Ptr[Void]` = `void*`). Wherever a value, parameter, or return type carries "no information," write `()`, never `Void` — using `Void` outside `Ptr` is a compile error (E0828).

#### No 1-Tuples

`(T)` in type or expression position is always parenthesization, never a 1-tuple. The 1-ary product is isomorphic to `T` and adds no expressiveness. For newtype wrapping, use a named struct:

```blink
// Not a 1-tuple — just parenthesized
let x: (Int) = 42        // same as: let x: Int = 42
let y = (some_expr)       // same as: let y = some_expr

// For newtype wrapping, use a struct
type UserId {
    value: Int
}
```

#### Arity Limit

Tuples support arity 0 (unit) through 6. A tuple with more than 6 elements is a compile error — use a named struct instead.

```blink
let ok = (1, 2, 3, 4, 5, 6)           // OK: arity 6
let bad = (1, 2, 3, 4, 5, 6, 7)       // COMPILE ERROR
```

```
error[TupleArityExceeded]: tuple arity exceeds maximum
 --> data.bl:3:11
  |
3 |     let x = (1, 2, 3, 4, 5, 6, 7)
  |             ^^^^^^^^^^^^^^^^^^^^^^^ tuple has 7 elements, maximum is 6
  |
  = help: use a named struct for data with more than 6 fields
```

**Why cap at 6.** Tuples are anonymous — elements have no names, only positions. Beyond 3-4 elements, positional access (`.4`, `.5`) becomes unreadable and error-prone. A cap at 6 provides headroom for real use cases (coordinate triples, tagged pairs, iterator adapters) while pushing complex data toward named structs where field names carry semantic information. The cap also bounds the compiler's trait impl generation to a small fixed set of arities.

#### Element Access

Tuple elements are accessed by zero-indexed numeric fields: `.0`, `.1`, `.2`, etc. These are compile-time resolved field accesses, not method calls.

```blink
let point = (10.0, 20.0, 30.0)
let x = point.0    // 10.0
let y = point.1    // 20.0
let z = point.2    // 30.0
```

Out-of-bounds access is a compile error:

```blink
let pair = (1, 2)
pair.2              // COMPILE ERROR: tuple (Int, Int) has no field `2`
```

#### Destructuring

Tuples support irrefutable destructuring in `let` bindings (see also §3.5):

```blink
let (name, age) = get_user_info()
let (status, body) = parse_response(data)?

// Nested destructuring
let ((x, y), label) = get_labeled_point()

// Ignore elements with _
let (_, count) = tally(items)

// In for loops
for (key, value) in map {
    io.println("{key}: {value}")
}
```

Pattern matching on tuples works in `match` expressions:

```blink
fn classify(pair: (Int, Int)) -> Str {
    match pair {
        (0, 0) => "origin"
        (0, _) => "y-axis"
        (_, 0) => "x-axis"
        (x, y) if x == y => "diagonal"
        _ => "other"
    }
}
```

#### Auto-Derived Trait Implementations

The compiler automatically implements traits for tuple types when all element types satisfy the trait. No `@derive` annotation needed — tuples are anonymous, so derivation is structural and implicit.

| Trait | Behavior | Derived when |
|-------|----------|-------------|
| `Eq` | Element-wise `==`. `(a0, a1) == (b0, b1)` iff `a0 == b0 && a1 == b1` | All elements: `Eq` |
| `Ord` | Lexicographic. Compare `.0` first; if equal, compare `.1`; etc. | All elements: `Ord` |
| `Hash` | Combine element hashes | All elements: `Hash` |
| `Display` | `"(a, b, c)"` format | All elements: `Display` |
| `Debug` | `"(a, b, c)"` format, each element via its own `.debug()` | All elements: `Debug` |
| `Clone` | Element-wise clone | All elements: `Clone` |

```blink
// Eq — works because Int and Str both implement Eq
let a = (1, "hello")
let b = (1, "hello")
assert_eq(a, b)

// Ord — lexicographic comparison
let pairs = [(3, "c"), (1, "b"), (1, "a")]
let sorted = pairs.sort()
// [(1, "a"), (1, "b"), (3, "c")]

// Hash — tuples as Map keys
let mut cache: Map[(Str, Int), Result] = Map.new()
cache.insert(("users", 42), result)

// Display — string interpolation
let point = (10, 20)
io.println("Point: {point}")   // "Point: (10, 20)"
```

When an element type lacks a trait, the tuple type also lacks it, and the compiler identifies the specific element:

```
error[TraitBoundNotSatisfied]: trait bound not satisfied
 --> render.bl:5:12
  |
5 |     let sorted = shapes.sort()
  |                         ^^^^ `(Int, Canvas)` does not implement `Ord`
  |
  = note: `Canvas` does not implement `Ord` (element .1 of tuple)
  = help: implement `Ord` for `Canvas`, or sort with a comparator: `shapes.sort_by(fn(a, b) { a.0.cmp(b.0) })`
```

#### Tuples vs Structs

Tuples and structs are both product types. Use tuples for ephemeral grouping; use structs when the data has identity or the fields need names.

| Use tuples for | Use structs for |
|----------------|-----------------|
| Multiple return values: `fn pop() -> (T, Stack[T])` | Domain types: `type User { name: Str, age: Int }` |
| Iterator adapters: `enumerate() -> Iterator[(Int, T)]` | Config: `type ServerConfig { host: Str, port: Int }` |
| Map iteration: `for (k, v) in map` | Public API types |
| Temporary grouping in local scope | Anything with more than 6 fields |
| Pattern matching on pairs | Anything that needs trait impls beyond the auto-derived set |
