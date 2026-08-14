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
import std.str.{StringBuilder}

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
    fn write(self, s: Str)
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
| `write` | `fn(self, s: Str)` | Append string. Requires `let mut` |
| `write_char` | `fn(self, c: Char)` | Append single character |
| `to_str` | `fn(self) -> Str` | Produce immutable `Str` (copies buffer) |
| `len` | `fn(self) -> Int` | Current content length in codepoints |
| `capacity` | `fn(self) -> Int` | Current buffer capacity |
| `clear` | `fn(self)` | Reset to empty, retains capacity for reuse |

**`to_str()` always copies.** The returned `Str` is an independent immutable value. Subsequent `write()` or `clear()` calls on the builder do not affect previously returned strings. This is the only safe semantics given GC-managed immutable `Str`.

**Interpolation optimization.** When the compiler sees `sb.write("{x}: {y}")` where the argument is an interpolated string literal, it lowers the call to a sequence of individual writes (`sb.write(x_str); sb.write(": "); sb.write(y_str)`) instead of materializing a temporary `Str`. This is a codegen optimization, transparent to the type system — the method signature is unchanged. (Vote: 4-1, Systems dissented wanting explicit multi-write.)

**When to use which:**
- **Interpolation** — inline composition, the 80% case
- **`concat`/`join`** — combining known pieces or a list of strings
- **`StringBuilder`** — loops building strings incrementally, codegen, or any case where `concat` in a loop would be O(N²)

(Panel vote: 3-1-1 for Option D. See [StringBuilder rationale](../decisions/string-builder.md).)

#### §3.2.2 Collection Methods

`List[T]`, `Map[K, V]`, and `Set[T]` are built-in collection types with method surfaces organized across four traits: `Sized` (shared, §3.2.1), `Contains[T]` (shared), and per-type operation traits (`ListOps[T]`, `MapOps[K, V]`, `SetOps[T]`). Iterator adapters (`.map()`, `.filter()`, `.collect()`, etc.) are default methods on `Iterator` (§3c.1) and are not repeated here.

##### Construction and Mutability

Collections are constructed via `Type.new()` for empty collections or literal syntax where available. Mutating methods (`push`, `pop`, `insert`, `remove`, `set`) require the binding to be `let mut`. Immutable bindings can only call non-mutating methods (`get`, `contains`, `len`, `keys`, `values`, etc.).

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
```

**Why `Type.new()` + `let mut`.** Mutability is a property of the *binding*, not the *type*. `List[T]` is one type regardless of whether the binding is mutable — no `MutList`/`ImmutableList` split, no doubled API surface, no coercion rules at function boundaries. `let mut` makes mutation points visible at the declaration site: `grep "let mut"` finds every mutation source. The C backend can emit `const` qualifiers for immutable bindings. (Vote: 5-0.)

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
| `List[T]` | Linear scan for element equality | Implemented (primitive elements) |
| `Map[K, V]` | Key presence check (equivalent to `contains_key`) | Implemented |

**Why a shared trait.** Containment is a universal set-theoretic predicate — "is X in this collection?" Every collection answers it, and generic code benefits: `fn has_item[C: Contains[T], T](c: C, item: T) -> Bool { c.contains(item) }`. The alternative — putting `contains` in each per-type trait — prevents writing functions generic over "any collection that can test membership." (Vote: 5-0.)

**Implementation status.** `Set`, `Map`, and `List` all implement `Contains`. `Map.contains(k)` is equivalent to `Map.contains_key(k)`. `List.contains` is implemented for **primitive element types** — `Int`, `Bool`, `Str`, `Float` — via a linear scan over element equality; `Str` elements use string-value equality. Lists of structs/enums and lists of nested collections (`List[List[_]]`, `List[Map[_,_]]`) are **not yet supported** — `.contains()` on those is a compile error (`UnresolvedMethod`), because element equality for those types is not yet defined (`==` on boxed structs is pointer identity, not field-wise). Use `xs.into_iter().filter(...)` for those cases until value equality lands.

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
}
```

The full `List[T]` method surface (13 methods from `ListOps` + 2 from `Sized` + 1 from `Contains`, plus `join` from `Joinable`):

| Method | Signature | Mutates | Notes |
|--------|-----------|---------|-------|
| `len` | `fn(self) -> Int` | no | Via `Sized` |
| `is_empty` | `fn(self) -> Bool` | no | Via `Sized` |
| `contains` | `fn(self, T) -> Bool` | no | Via `Contains`, linear scan — primitive element types (`Int`/`Bool`/`Str`/`Float`); struct/enum/nested-collection elements not yet supported (see §3.2.2 *The `Contains` Trait*) |
| `get` | `fn(self, Int) -> Option[T]` | no | Safe indexed access |
| `last` | `fn(self) -> Option[T]` | no | Last element |
| `index_of` | `fn(self, T) -> Option[Int]` | no | First occurrence |
| `push` | `fn(self, T)` | yes | Append to end |
| `pop` | `fn(self) -> Option[T]` | yes | Remove from end |
| `set` | `fn(self, Int, T)` | yes | Replace at index |
| `insert` | `fn(self, Int, T)` | yes | Insert at index, shift right |
| `remove` | `fn(self, Int) -> T` | yes | Remove at index, shift left |
| `clear` | `fn(self)` | yes | Reset to empty, retains capacity |
| `append` | `fn(self, List[T]) -> List[T]` | no | Concatenate, returns new list |
| `slice` | `fn(self, Int, Int) -> List[T]` | no | Sub-list `[start, end)`, returns new list |
| `join` | `fn(self, Str) -> Str` | no | Join with a separator — `List[Str]` only, via `Joinable` (§3.2.1) |
| `reverse` | `fn(self) -> List[T]` | no | Reversed copy |
| `sort` | `fn(self) -> List[T]` | no | Sorted copy (requires `T: Ord`) |

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

items.contains(4)                    // true — linear scan (primitive elements, §3.2.2)
items.index_of(1)                    // Some(1) — first occurrence
items.last()                         // Some(5)
items.clear()                        // items is now [], capacity retained
```

**Why `.get()` returns `Option[T]`.** Out-of-bounds access is a runtime error in most languages. Returning `Option[T]` forces the caller to handle the absence case — no index-out-of-bounds panics, no null pointer exceptions. Use `??` for default values: `list.get(i) ?? 0`.

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
| `IntoIterator[T]` | List, Map, Set, Str, Range | `into_iter` | Yes (§3c.1) |
| `Joinable` | List[Str] | `join` | Yes (§3.2.1) |
| `StringBuildOps` | StringBuilder | `write`, `write_char`, `to_str`, `len`, `capacity`, `clear` | Yes |

> **`Contains` membership covers `Set`, `Map`, and `List`.** `Set.contains` is a hash lookup, `Map.contains` is key presence (identical to `contains_key`), and `List.contains` is a linear scan over **primitive element types** (`Int`/`Bool`/`Str`/`Float`). `List` elements that are structs/enums or nested collections are **not yet supported** (`UnresolvedMethod`) — element value-equality for those is not yet defined. Substring search on `Str` (`"hello".contains("ell")`) is a separate operation hosted by `StrOps` (§3.2.1), not element membership. This table reflects what compiles today.

All built-in method-surface traits are in the prelude — no import required. This matches the rationale from §10.6: operators like `for` desugar through `IntoIterator`, method calls resolve through traits, and requiring imports for built-in collection methods would add ceremony with no information value.

**These traits are sealed.** Their implementations are compiler-provided for the built-in types listed above; user code may not implement them (`impl StrOps for MyType`) or redefine them (`trait StrOps { … }`). Both are compile errors — the trait names are reserved by the prelude (§10.6), and a user implementation would create a second meaning for a method the compiler dispatches intrinsically. To add string-like or collection-like behavior to your own type, define your own trait with a different name.

A sealed trait may still be named in a generic bound — e.g. `fn f[T: Sized](x: T) -> Int { x.len() }`. `Sized` spans several built-in types, so a bound on it is genuinely polymorphic. A bound on a single-implementor trait (`StrOps`, `BytesOps`, `StringBuildOps`) is legal but degenerate: it is satisfiable only by the one built-in type that implements it (e.g. `[T: StrOps]` admits only `Str`), so it carries no more abstraction than naming that type directly.

---

#### §3.2.3 Additional Standard Library Types

Beyond the built-in primitives (§3.2) and collections (§3.2.2), Blink's standard library provides typed value types for domains where raw primitives lose semantic meaning. These types are not compiler-known and not in the prelude — they live in stdlib modules and require explicit import. The compiler's built-in effect handles reference these types for their operation signatures.

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
| `to_rfc3339` | `fn(self) -> Str` | ISO 8601 string |
| `to_unix_ms` | `fn(self) -> Int` | Milliseconds since epoch |
| `to_unix_secs` | `fn(self) -> Int` | Seconds since epoch |

Instant implements: `Eq`, `Ord`, `Hash`, `Display`, `Clone`, `Debug`. Does NOT implement arithmetic traits (sealed to built-in numerics). Use `.since()` and `.add()` named methods.

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

Duration implements: `Eq`, `Ord`, `Display`, `Clone`, `Debug`. Arithmetic via named methods (`.add()`, `.scale()`), not operators.

**Why Instant/Duration instead of raw Int.** Time points form an affine space over durations: `Instant - Instant → Duration`, `Instant + Duration → Instant`, but `Instant + Instant` is nonsensical. Raw `Int` allows all three operations — a type error that the type system should catch. Duration carries dimensional information; `Int` is dimensionless. `time.sleep(port_number)` type-checks with raw Int but is a bug. `time.sleep(Duration.seconds(5))` makes units explicit at every call site. (Panel vote: 5-0.)

**Why stdlib Tier 2, not prelude.** Instant and Duration require no special syntax, no special desugaring, and no special inference rules. They are nominal types with named methods. The effect system's `Time.Read` and `Time.Sleep` operations reference these types, creating a coupling between compiler effects and stdlib — resolved by pinning the type layout as part of the effect specification. Not every program uses time operations. (Panel vote: 5-0.)

**Wall-clock DateTime.** Calendar-aware datetime (year, month, day, timezone) lives in `std.time.DateTime`, constructed from an `Instant` via `DateTime.from(instant)`. Calendar decomposition carries unbounded complexity (timezones, DST, leap seconds) that belongs in stdlib, not built-in types.

##### Bytes (`std.bytes`, Tier 1)

`Bytes` is a contiguous byte buffer — the binary counterpart to `Str`. Where `Str` guarantees UTF-8 validity, `Bytes` carries no encoding invariant.

```blink
import std.bytes.Bytes

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
| `set_i16_le` / `set_i16_be` | `fn(self, Int, Int) -> Result[Void, Str]` | Write 2-byte signed at offset (in-place, bounds vs `len`) |
| `set_u16_le` / `set_u16_be` | `fn(self, Int, Int) -> Result[Void, Str]` | Write 2-byte unsigned at offset (in-place, bounds vs `len`) |
| `set_i32_le` / `set_i32_be` | `fn(self, Int, Int) -> Result[Void, Str]` | Write 4-byte signed at offset (in-place, bounds vs `len`) |
| `set_u32_le` / `set_u32_be` | `fn(self, Int, Int) -> Result[Void, Str]` | Write 4-byte unsigned at offset (in-place, bounds vs `len`) |
| `set_i64_le` / `set_i64_be` | `fn(self, Int, Int) -> Result[Void, Str]` | Write 8-byte signed at offset (in-place, bounds vs `len`) |
| `set_u64_le` / `set_u64_be` | `fn(self, Int, Int) -> Result[Void, Str]` | Write 8-byte unsigned at offset (in-place, bounds vs `len`) |
| `with_ptr` | `fn[R](self, fn(Ptr[U8]) -> R ! FFI) -> R ! FFI` | Closure-scoped FFI pin (see §9.1.3) |

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
- **Arity is exact.** Supplying the wrong count is an error, not a prompt to infer the remainder.
- **Bounds are checked against the arguments as written.** An explicit type argument satisfies the binder's bounds or the call is rejected; explicitness never bypasses a bound.

**A redundant type-argument list is permitted and carries no diagnostic.** When inference would have reached the same answer, writing the arguments anyway is neither an error nor a warning nor a lint — exactly as `let x: Int = 1` is permitted where `let x = 1` would do. A diagnostic here would be non-monotonic: adding an annotation elsewhere in the program could make an untouched line retroactively noisy.

**Phantom type parameters are legal in user code.** Because no binder is erased, a type parameter mentioned by no field is supplied by the type annotation and keeps its instantiations distinct:

```blink
type Template[C] {
    source: Str
}

let db: Template[DB] = Template { source: "SELECT 1" }
let sh: Template[Shell] = Template { source: "ls" }     // a distinct type from Template[DB]
```

`Template[DB]` and `Template[Shell]` are different types, and neither is assignable to the other. This pattern is not reserved to compiler-known types — it is the same mechanism `Template[C]` uses (§3b.5), available to user code on the same terms.

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

Every type expression written in a **type position** — a parameter type, a return type, a field type, a binding annotation, a nested type argument, or a struct-literal head — must denote a complete type. A type constructor of arity *n* denotes a complete type only when it is applied to exactly *n* type arguments. Writing a constructor with the wrong number of arguments — including **none** — does not denote a type; it is `error[TypeArgArity]` (E0303).

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

**E0303 is decided at name resolution, before inference runs.** A constructor's arity is a property of its declaration alone, so the mismatch is known the moment the annotation is read — no call site, and no inference, is consulted. This is what distinguishes E0303 from `error[CannotInferType]` (E0301, §3.4 *Under-Determined Types*): E0301 fires when inference *terminates* with a type variable no use ever fixed; E0303 fires when a type expression was never well-formed to begin with. A bare `Channel` annotation is not an unsolved variable that a later use might constrain — it names a slot the program neglected to fill, and no downstream use can fill an argument the annotation did not open. The two never co-fire on the same type expression: a well-formed constructor application may leave a variable under-determined (E0301), but an ill-formed one is rejected first (E0303).

**The repair depends on the case, and the first `help:` offered is normative** (§3.4 *Explicit Type Application*):

| Case | Example | Repair offered first |
| --- | --- | --- |
| Bare constructor, a type parameter is in scope | `fn relay[T](src: Channel)` | apply the parameter in scope — `Channel[T]` |
| Bare constructor, no type parameter is in scope | `fn relay(src: Channel)` | declare a binder on the enclosing declaration and apply it — `fn relay[T](src: Channel[T], dst: Channel[T])` |
| Under-applied (some, too few) | `Map[Str]` | supply the missing argument — `Map[Str, V]` |
| Over-applied (too many) | `List[Int, Str]` | remove the extra argument — `List[Int]` |

The binder-declaring repair is offered **only** when the constructor is bare *and* no type parameter already in scope can fill the slot. Where a parameter is in scope, applying it is the whole repair; suggesting a fresh binder there would shadow an available one.

**Trait references are not type expressions and are outside this rule.** A trait name in a bound (`T: Ord`) or an impl header does not occupy a type position — it constrains a type parameter rather than denoting a type (§3.6). Its arguments are governed by `error[TraitArgArity]` (E0910), the impl-header specialization of the same arity principle. So a generic signature that mentions a trait only in a bound is well-formed under E0303:

```blink
fn sort[T: Ord](xs: List[T]) -> List[T] { xs }   // OK -- `Ord` is a bound, not a type expression;
                                                  //       `List[T]` is a complete type
```

One principle — a constructor is applied to its exact arity — surfaces as E0303 in type positions and E0910 in trait positions, because the repair and the surrounding grammar differ between the two.

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

#### Recursive Types

Types can reference themselves. The compiler handles the indirection:

```blink
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

field_pattern  ::= IDENT ":" pattern                          // field with sub-pattern
               |   IDENT                                      // field punning

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

**Struct patterns.** Match struct types by field values. Type name is required (nominal matching). Field punning binds a field to a variable of the same name. `..` is required when not all fields are listed.

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
    fn fmt(self, sb: StringBuilder) ! StringBuilderPure
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
let mut names = scores.keys()
names.sort()
for name in names {
    io.println("{name}: {scores.get(name).unwrap()}")
}
```

A function whose result depends on unsorted `Map`/`Set` iteration order is **not** referentially transparent with respect to its `Map`/`Set` arguments, even though it has no effect annotation. The compiler's purity analysis (§4 effects, truly-pure classification) treats iteration over a `Map`/`Set` as an opaque-order read of process state: any function that iterates a `Map` or `Set` is conservatively excluded from memoization and reordering. Iteration order is **not** part of a `Map`/`Set` value's identity — two maps with equal entry sets are `==`-equal regardless of insertion history or seed.

**Float keys.** `F32`/`F64` do not implement `Hash`, and a `Float` (or any type transitively containing one) used as a `Map`/`Set` key is rejected at type-check as `E1400 MapKeyNotHashable`. This is a permanent contract, not a missing impl: float equality cannot satisfy the `Eq`/`Hash` coherence law — `-0.0 == 0.0` holds while the two have distinct bit patterns, so a bitwise hash would map equal values to different buckets. Round to an integer key instead.

**Non-hashable keys and elements in general.** Only builtin scalars (`Int`, sized ints, `Bool`, `Char`, `Str`), a tuple whose elements are all hashable, and a user `struct`/`enum` carrying `@derive(Hash, Eq)` implement `Hash`. Every other type — every container (`List`, `Map`, `Set`, `Option`, `Result`), `Bytes`, `StringBuilder`, and any `fn`/closure type — has no `Hash` impl and cannot gain one via `@derive`, so using one as a `Map` key or `Set` element is rejected at type-check as `E1400 MapKeyNotHashable`, the same code as the Float case above. A tuple is hashable **if and only if** every one of its elements is; `(Int, Option[Int])` is rejected because its second element is not, even though `(Int, Str)` is accepted.

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

**Effect-row subtype for open overrides.** When an open default declares effect row `R_d` and an `impl` provides an override declaring row `R_o`, the typechecker requires `R_o ⊆ R_d`. An override may *narrow* the effect signature (drop effects the default declares but the override does not use) but may not *widen* it (introduce effects the default does not declare). See §4.5 *Effect Composition Rules* for the subtyping lattice. `final` defaults are effect-monomorphic at their declaration site — no override exists to widen them.

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
    fn fmt(self, sb: StringBuilder) ! StringBuilderPure   // self: Self, enables x.fmt(sb)
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

**`self` is always passed by value.** Blink is garbage-collected — there is no by-reference vs by-move distinction. The `self` parameter is a value like any other parameter. No `&self`, `&mut self`, or `self: Box[Self]` forms exist.

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

`Bool` is not a numeric type, so `+ - * / %` reject a `Bool` operand -- the same rule the bitwise operators follow. Blink has no truthiness, so a `Bool` never reads as 0 or 1. Count with an explicit conditional:

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

Y* = total ordering semantics. Unsigned types don't impl `Neg`. `Float` doesn't impl `Hash`.

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
    fn fmt(self, sb: StringBuilder) ! Fmt {
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

**Parametricity (normative).** A polymorphic impl body must be **parametric in its type parameters**. The body may not:

- **Dispatch on `T`'s identity.** `if T == Int { ... }`, `match T { ... }`, and equivalent constructs are compile errors.
- **Inspect `T`'s runtime layout, size, alignment, or pointer-kind.** No `sizeof`-like form exists in the source language for type parameters.
- **Call any function that exposes `T`'s runtime shape.** This rules out reading `T` from any reflective API.

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
    fn fmt(self, sb: StringBuilder) ! Fmt {
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

The compiler uses `Closeable` to power lint W0600 (warn when a `Closeable` value is used outside a `with...as` block) and errors E0601/E0602 (closeable escapes scope). See section 5.5 for the full mechanism.

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
| `Display` | `fn display(self) -> Str` | — |
| `Debug` | `fn debug(self) -> Str` | — |
| `Serialize` | `fn to_json(self) -> JsonValue` | — |
| `Deserialize` | `fn from_json(json: JsonValue) -> Result[Self, JsonError]` | — |

##### Clone Semantics

`Clone` performs a **logical copy** (one-level deep): allocate a new struct or enum wrapper, copy field values. GC pointers are copied, not recursively cloned.

- **Value types** (`Int`, `Float`, `Bool`, `Char`): value copy (trivial)
- **`Str`**: new GC root to same string data (strings are immutable, sharing is safe)
- **Collections** (`List`, `Map`, `Set`): new GC root to same backing storage. Mutations to a cloned collection **do** affect the original — same semantics as JS spread (`{...obj}`) or Python `copy.copy()`
- **User structs/enums**: field-wise value copy via derived `Clone`

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

String interpolation (`"{value}"`) invokes `Display`. Explicit `value.debug()` is required for the structural form.

`List`, `Option`, and `Map` implement `Debug` **conditionally** — a `List[T]` is `Debug` iff its
element type `T` is `Debug`; an `Option[T]` iff `T` is `Debug`; a `Map[K,V]` iff **both** `K` and
`V` are `Debug`. These are the only conditional (constrained) built-in `Debug` instances; their
element-wise rendering and the v1 nesting boundary are specified in *Container Debug Rendering*
below.

**Scalar debug-forms.** The scalar leaf forms split by whether the type is textual or not. `Int`,
`Float`, `Bool`, and the sized integers render **bare** — their `debug()` equals their `display()`.
The textual scalars render **quoted and escaped** in their own source-literal syntax, so a debug
string is re-readable and unambiguous about its type: `Str.debug()` is double-quoted (`"a".debug()`
is `"\"a\""`), and `Char.debug()` is single-quoted (`'a'.debug()` is `"'a'"`). The single-quote
delimiter keeps a `Char` distinct from a one-character `Str` in debug output, and — because it treats
the character as text rather than its integer code point — keeps `Debug` consistent with `Char` not
being a numeric type (§3c). A `Char` is **never** rendered as its bare code point: `'a'.debug()` is
`'a'`, not `97`.

`Char.debug()` escapes exactly the ratified `Char` literal escape set (§2, char literals): `\n`,
`\r`, `\t`, `\\`, `\b`, `\f`, `\0`, and `\'`. Every other scalar — all printable ASCII and every
non-ASCII Unicode scalar — is emitted as its literal UTF-8 character between the quotes. This gives
the invariant that **`Char.debug()` emits only escapes the lexer already accepts**: for any `Char`
`c` in the ratified literal set, `c.debug()` is a valid `Char` literal that reconstructs `c`
(round-trip). The one v1 gap is a non-printable scalar that has no named escape (e.g. `U+0007` BEL):
it is emitted as its raw byte(s) between the quotes, which is faithful but not always legible and not
re-readable. A `'\u{N}'` output form for those is deferred to the task that adds `\u{...}` as input
syntax (tracked in `qvan6m`), so input and output escaping land together.

| `Char` value | `debug()` | | `Char` value | `debug()` |
|---|---|---|---|---|
| `'a'` | `'a'` | | `'\n'` | `'\n'` |
| `'1'` | `'1'` (≠ `Int` `1` → `1`) | | `'\''` | `'\''` |
| `' '` | `' '` | | `'\\'` | `'\\'` |
| `'😀'` | `'😀'` (raw UTF-8) | | `'\0'` | `'\0'` |

The `Char` debug-form flows unchanged into every container position — a `Char` struct field, a
`List[Char]` element, an `Option[Char]` inner value, and a `Map[Char, V]` key all render via the same
`Char.debug()`, so they agree by construction. A `Map[Char, Int]` with the entry `'a' -> 1` renders
`{'a': 1}`; a `List[Char]` of `['h', 'i']` renders `['h', 'i']`.

##### Display Trait Shape

`Display` has two surfaces, exactly one of which is user-implementable. Implementors write `fmt`; the trait derives `display` from it.

```blink
trait Display {
    fn fmt(self, sb: StringBuilder) ! StringBuilderPure
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
    fn fmt(self, sb: StringBuilder) {
        sb.write("(")
        sb.write(self.x)
        sb.write(", ")
        sb.write(self.y)
        sb.write(")")
    }
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

**`StringBuilderPure` effect.** `fmt` is declared with the `StringBuilderPure` effect (§4.x): it may write into the supplied `StringBuilder`, but it cannot read external state, perform IO, allocate observably, or mutate any state outside the builder. This makes `fmt` referentially transparent given a fixed `(self, sb_initial_state)`, which is what makes the sealed `display` derivation safe and the interpolation cache-friendly.

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
// Produces: Template[DB] {
//     parts: ["SELECT * FROM users WHERE id = ", " AND name = ", ""],
//     values: [42, "Alice"]   ← raw typed values, not strings
// }
```

The set of types valid as Template values is compiler-known: `Int`, `Float`, `Str`, `Bool`, `Option[T]` (where `T` is a valid value type). Using a type outside this set in a Template interpolation is a compile error. The `Raw(expr)` marker type bypasses decomposition for a specific interpolation (see §3b.5).

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
| `Clone` | `Type { f1: self.f1, f2: self.f2, ... }` (value copy, no recursive clone) |
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
| `Clone` | Match + reconstruct variant with copied field values |
| `Display` | Variant name for unit variants; `"Variant(f1, f2)"` for data-carrying |
| `Debug` | `"Variant"` for unit variants; `"Variant({f1.debug()}, {f2.debug()})"` for data-carrying |

##### Container Debug Rendering

A field of a `@derive(Debug)` type may be a container — `List[T]`, `Option[T]`, or `Map[K,V]`. The
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

```blink
@derive(Debug)
type Inventory { items: List[Str], count: Option[Int], tags: Map[Str, Int] }

let tags: Map[Str, Int] = Map()
tags["rare"] = 1
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

Two container shapes stay rejected with `E0520` at **every** level of nesting (not just the top
field): `Set` and `Result` are not Debug-renderable, and a `Map` whose **key** type is itself a
container (`Map[List[Int], V]`, etc.) is rejected — map keys must be a scalar (`Str` / `Char` /
`Int` / `Bool` / sized-int) or a `@derive(Debug, Hash, Eq)` struct. (Container-typed map *values*
render fine; only container keys are excluded, because the renderer reads keys back through the map's
key-ops storage layer, which has no descriptor for a container key.)

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
to prove every nested element / key / value type is `Debug` (rejecting non-Debug, `Set`/`Result`,
and container map keys at any level). The emitter materializes one recursive per-monomorphization
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
`Map[K,V]`), the check peels the container and recurses on the element type — and on **both** `K`
and `V` for a `Map` — so `E0520` also names a non-Debug *element/key/value* type, and a container
nested inside a container (depth+1) raises `E0520` under the v1 one-level limit. See *Container Debug
Rendering* above.

#### §3.6.2 Serialization Traits

Blink provides compiler-known `Serialize` and `Deserialize` traits for JSON serialization. These are Tier 1 (ship with the compiler) and derivable via `@derive`.

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

`JsonError` is a single error type covering both serialization and deserialization failures:

```blink
type JsonError {
    message: Str
}
```

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
| Enum with `@derive(Serialize)` | Tagged object: `{"variant": "Name", "fields": {...}}` |

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

#### §3.6.3 JSON Codec Module

The `std.json` module provides the public API for JSON parsing, serialization, and typed deserialization. All functions are pure — IO effects belong to the caller.

##### Module API

```blink
import std.json

// Parse JSON string into dynamic JsonValue tree
json.parse(input: Str) -> Result[JsonValue, JsonError]

// Convert JsonValue tree to comblink JSON string
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

##### Dynamic Navigation (JsonValue Methods)

`JsonValue` provides navigation methods returning `Option` for partial access into the JSON tree. Navigation is inherently partial — a key may not exist, an index may be out of bounds, a value may not be the expected type. `Option` is the canonical encoding of partiality in Blink, composing naturally with `?` (early return) and `??` (default value).

```blink
// Structural navigation
fn get(self, key: Str) -> Option[JsonValue]    // object field lookup
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

The unit type `()` is the 0-tuple — a type with exactly one value, carrying no information. It is the implicit return type of functions and blocks that produce no value.

```blink
fn log(msg: Str) ! IO {
    io.println(msg)
}
// return type is (), omitted by convention
```

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
| `Clone` | Element-wise clone | All elements: `Clone` |

```blink
// Eq — works because Int and Str both implement Eq
let a = (1, "hello")
let b = (1, "hello")
assert_eq(a, b)

// Ord — lexicographic comparison
let pairs = [(3, "c"), (1, "b"), (1, "a")]
let sorted = pairs.into_iter().sort().collect()
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
  = help: implement `Ord` for `Canvas`, or extract a sortable key
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
