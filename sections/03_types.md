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

#### §3.2.1 String Methods

Strings are not bare character arrays. They are UTF-8 encoded, GC-managed, immutable values with a method surface designed to be complete enough that 90% of programs never need a string utility library. Methods are organized into two traits: `Sized` (generic, shared with collections) and `StrOps` (string-specific).

##### The `Sized` Trait

`Sized` provides length-awareness to any container type. `Str`, `List[T]`, `Map[K, V]`, and `Set[T]` all implement it.

```pact
trait Sized {
    fn len(self) -> Int
    fn is_empty(self) -> Bool {
        self.len() == 0
    }
}
```

For `Str`, `.len()` returns the **codepoint count** — the number of Unicode scalar values, not the number of bytes. This is O(n) for general UTF-8 (the implementation may cache the result), but it gives the semantically correct answer: `"café".len()` is `4`, not `5`.

##### The `StrOps` Trait

All string-specific methods live in a single `StrOps` trait. `Str` is the only type that implements it.

```pact
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
| `replace` | `fn(self, Str, Str) -> Str` | Replace all occurrences |
| `index_of` | `fn(self, Str) -> Option[Int]` | Codepoint index of first match |
| `lines` | `fn(self) -> List[Str]` | Split by line endings |
| `parse_int` | `fn(self) -> Result[Int, ConversionError]` | Parse as integer |
| `parse_float` | `fn(self) -> Result[Float, ConversionError]` | Parse as float |
| `byte_len` | `fn(self) -> Int` | Byte count (O(1)) |
| `byte_at` | `fn(self, Int) -> U8` | Raw byte at offset |

##### Unicode Semantics

Pact strings are codepoint-oriented by default. All index-based methods operate on codepoint positions, not byte offsets.

```pact
let s = "café"
s.len()              // 4 (codepoints)
s.char_at(3)         // Some('é')
s.byte_len()         // 5 (UTF-8 bytes — 'é' is 2 bytes)
s.substring(0, 4)    // "café"
s.index_of("fé")     // Some(2)
```

Byte-access methods use the `byte_` prefix. These exist for interop, binary protocols, and performance-sensitive code that operates on raw UTF-8.

```pact
let s = "héllo"
s.byte_len()         // 6
s.byte_at(0)         // 104 (ASCII 'h')
s.byte_at(1)         // 195 (first byte of 'é')
```

**Why codepoint-default.** The choice is between three levels of abstraction: bytes (Go, C), codepoints (Python 3, Java), and grapheme clusters (Swift). Bytes are too low-level — indexing into the middle of a multibyte character is a bug factory. Grapheme clusters are linguistically correct but expensive and complex (cluster boundaries depend on Unicode version and locale). Codepoints hit the pragmatic middle: they correspond to what most programmers mean by "character," they are well-defined by Unicode, and they avoid the worst class of string bugs. The `byte_` prefix makes raw access available but intentionally inconvenient (panel vote: 3-2, Systems and PLT dissented wanting byte-default).

`Str` also implements `IntoIterator[Char]`, so `for c in str` iterates codepoints:

```pact
for c in "hello" {
    io.println("{c}")
}

// Or explicitly via .chars()
let vowels = "hello".chars().filter(fn(c) { "aeiou".contains("{c}") }).collect()
```

##### Parsing

`parse_int` and `parse_float` are methods on `Str` rather than standalone functions. They delegate to `TryFrom` internally but provide a discoverable, grep-able API surface.

```pact
let port = "8080".parse_int()?                      // Ok(8080)
let rate = "3.14".parse_float()?                     // Ok(3.14)
let bad = "not_a_number".parse_int()                 // Err(ConversionError)

// Common pattern: parse with default
let timeout = config.get("timeout") ?? "30"
let seconds = timeout.parse_int() ?? 30
```

##### String Building

For assembling strings from parts, Pact provides three mechanisms in v1:

1. **String interpolation** — for inline composition: `"Hello, {name}!"`
2. **`concat`** — for joining two strings: `greeting.concat(name)`
3. **`join`** — for assembling a list of strings with a separator:

```pact
let parts = ["Hello", "world"]
let sentence = parts.join(", ")          // "Hello, world"

let csv_line = values.join(",")          // "1,Alice,30"
let path = segments.join("/")            // "usr/local/bin"

// Building up dynamically
let mut lines: List[Str] = []
for user in users {
    lines = lines.append("{user.name}: {user.email}")
}
let report = lines.join("\n")
```

`join` is defined on `List[Str]` via the `Joinable` trait:

```pact
trait Joinable {
    fn join(self, separator: Str) -> Str
}

impl Joinable for List[Str] {
    fn join(self, separator: Str) -> Str {
        // built-in implementation
    }
}
```

**Why `join` over a mutable builder.** A mutable `StrBuf` type is the standard approach for languages without GC-optimized string concatenation. Pact defers `StrBuf` to v1.1 — the combination of interpolation, `concat`, and `join` covers the vast majority of string assembly patterns. The `join` idiom (build a `List[Str]`, then join) is simple, composable, and produces correct results without requiring the programmer to manage buffer state.

#### §3.2.2 Collection Methods

`List[T]`, `Map[K, V]`, and `Set[T]` are built-in collection types with method surfaces organized across four traits: `Sized` (shared, §3.2.1), `Contains[T]` (shared), and per-type operation traits (`ListOps[T]`, `MapOps[K, V]`, `SetOps[T]`). Iterator adapters (`.map()`, `.filter()`, `.collect()`, etc.) are default methods on `Iterator` (§3c.1) and are not repeated here.

##### Construction and Mutability

Collections are constructed via `Type.new()` for empty collections or literal syntax where available. Mutating methods (`push`, `pop`, `insert`, `remove`, `set`) require the binding to be `let mut`. Immutable bindings can only call non-mutating methods (`get`, `contains`, `len`, `keys`, `values`, etc.).

```pact
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

```pact
trait Contains[T] {
    fn contains(self, value: T) -> Bool
}
```

| Type | `contains` semantics |
|------|---------------------|
| `List[T]` | Linear scan for element equality |
| `Map[K, V]` | Key presence check (equivalent to `contains_key`) |
| `Set[T]` | Hash-based membership test |
| `Str` | Substring presence (already in `StrOps`, `Contains` not applied) |

**Why a shared trait.** Containment is a universal set-theoretic predicate — "is X in this collection?" Every collection answers it, and generic code benefits: `fn has_item[C: Contains[T], T](c: C, item: T) -> Bool { c.contains(item) }`. The alternative — putting `contains` in each per-type trait — prevents writing functions generic over "any collection that can test membership." (Vote: 5-0.)

**Note on `Str`.** `Str` implements `StrOps.contains(Str)` for substring search (§3.2.1). `Str` does not implement `Contains[Char]` — use `StrOps.contains("{c}")` for character search. This avoids confusion between "contains substring" and "contains element" semantics.

##### The `ListOps` Trait

```pact
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

    // Transformation (returns new list)
    fn append(self, other: List[T]) -> List[T]
    fn reverse(self) -> List[T]
    fn sort(self) -> List[T]
}
```

The full `List[T]` method surface (12 methods from `ListOps` + 2 from `Sized` + 1 from `Contains`):

| Method | Signature | Mutates | Notes |
|--------|-----------|---------|-------|
| `len` | `fn(self) -> Int` | no | Via `Sized` |
| `is_empty` | `fn(self) -> Bool` | no | Via `Sized` |
| `contains` | `fn(self, T) -> Bool` | no | Via `Contains`, linear scan |
| `get` | `fn(self, Int) -> Option[T]` | no | Safe indexed access |
| `last` | `fn(self) -> Option[T]` | no | Last element |
| `index_of` | `fn(self, T) -> Option[Int]` | no | First occurrence |
| `push` | `fn(self, T)` | yes | Append to end |
| `pop` | `fn(self) -> Option[T]` | yes | Remove from end |
| `set` | `fn(self, Int, T)` | yes | Replace at index |
| `insert` | `fn(self, Int, T)` | yes | Insert at index, shift right |
| `remove` | `fn(self, Int) -> T` | yes | Remove at index, shift left |
| `append` | `fn(self, List[T]) -> List[T]` | no | Concatenate, returns new list |
| `reverse` | `fn(self) -> List[T]` | no | Reversed copy |
| `sort` | `fn(self) -> List[T]` | no | Sorted copy (requires `T: Ord`) |

```pact
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

items.contains(4)                    // true
items.index_of(1)                    // Some(1) — first occurrence
items.last()                         // Some(5)
```

**Why `.get()` returns `Option[T]`.** Out-of-bounds access is a runtime error in most languages. Returning `Option[T]` forces the caller to handle the absence case — no index-out-of-bounds panics, no null pointer exceptions. Use `??` for default values: `list.get(i) ?? 0`.

**Why 12 methods (vote: 3-2).** Systems and PLT argued for 8, excluding `insert`, `remove`, `index_of`, and `last` as O(n) operations better served by iterator methods. Web/Scripting, DevOps, and AI/ML argued these are bread-and-butter operations in every major language (Python `list`, JS `Array`, Java `ArrayList`), and their absence would cause every user to write the same helpers on day one. The expanded surface won on developer experience grounds — performance characteristics should be documented, not hidden.

##### The `MapOps` Trait

```pact
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
}
```

The full `Map[K, V]` method surface (8 methods from `MapOps` + 2 from `Sized` + 1 from `Contains`):

| Method | Signature | Mutates | Notes |
|--------|-----------|---------|-------|
| `len` | `fn(self) -> Int` | no | Via `Sized` |
| `is_empty` | `fn(self) -> Bool` | no | Via `Sized` |
| `contains` | `fn(self, K) -> Bool` | no | Via `Contains`, key presence |
| `get` | `fn(self, K) -> Option[V]` | no | Lookup by key |
| `get_or_default` | `fn(self, K, V) -> V` | no | Lookup with fallback |
| `keys` | `fn(self) -> List[K]` | no | All keys (unspecified order) |
| `values` | `fn(self) -> List[V]` | no | All values (unspecified order) |
| `entries` | `fn(self) -> List[(K, V)]` | no | All key-value pairs |
| `contains_key` | `fn(self, K) -> Bool` | no | Key presence check |
| `insert` | `fn(self, K, V)` | yes | Insert or update |
| `remove` | `fn(self, K) -> Option[V]` | yes | Remove by key |

```pact
let mut config = Map.new()
config.insert("host", "localhost")
config.insert("port", "8080")

let host = config.get("host")              // Some("localhost")
let timeout = config.get_or_default("timeout", "30")  // "30"
config.contains_key("port")                // true
config.contains("port")                    // true (Contains trait, same as contains_key)

let ks = config.keys()                     // ["host", "port"] (unspecified order)
let vs = config.values()                   // ["localhost", "8080"] (unspecified order)
let es = config.entries()                  // [("host", "localhost"), ("port", "8080")]

let removed = config.remove("port")        // Some("8080")
```

**Why `contains_key` when `Contains` exists.** `Contains[K]` on `Map[K, V]` checks key presence — identical to `contains_key`. Both exist because `contains` comes from the generic `Contains` trait (for generic code) and `contains_key` lives in `MapOps` (for map-specific code that reads more clearly). They have identical semantics; the compiler may optimize `contains` to `contains_key` internally.

**Why 8 methods (vote: 3-2).** Systems and PLT argued for 6, noting that `entries` duplicates `IntoIterator` (which yields `(K, V)` tuples) and `get_or_default` duplicates `get(k) ?? default`. Web/Scripting, DevOps, and AI/ML argued that `entries` is the standard "dump the map" operation every developer expects (Python's `dict.items()`, JS's `Map.entries()`), and `get_or_default` eliminates the most common map boilerplate pattern. Discoverability and training data representation won.

##### The `SetOps` Trait

```pact
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

```pact
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

| Trait | Applies to | Methods | In prelude |
|-------|-----------|---------|------------|
| `Sized` | Str, List, Map, Set | `len`, `is_empty` | Yes |
| `Contains[T]` | List, Map, Set | `contains` | Yes |
| `ListOps[T]` | List | 12 methods | Yes |
| `MapOps[K, V]` | Map | 8 methods | Yes |
| `SetOps[T]` | Set | 3 methods | Yes |
| `IntoIterator[T]` | List, Map, Set, Str, Range | `into_iter` | Yes (§3c.1) |
| `Joinable` | List[Str] | `join` | Yes (§3.2.1) |

All collection traits are in the prelude — no import required. This matches the rationale from §10.6: operators like `for` desugar through `IntoIterator`, method calls resolve through traits, and requiring imports for built-in collection methods would add ceremony with no information value.

---

#### §3.2.3 Additional Standard Library Types

Beyond the built-in primitives (§3.2) and collections (§3.2.2), Pact's standard library provides typed value types for domains where raw primitives lose semantic meaning. These types are not compiler-known and not in the prelude — they live in stdlib modules and require explicit import. The compiler's built-in effect handles reference these types for their operation signatures.

##### Instant and Duration (`std.time`, Tier 2)

`time.read()` returns `Instant` — an opaque, nanosecond-precision point in time. `time.sleep()` accepts `Duration` — a typed time span with named constructors that encode units.

```pact
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

**Instant** is an opaque struct (no public fields). Internal representation: `int64_t` nanoseconds since epoch. C codegen: `typedef struct { int64_t nanos; } pact_instant;` — same footprint as `Int`, but nominally typed.

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

```pact
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

C representation: `typedef struct { uint8_t* data; int64_t len; int64_t cap; } pact_bytes;` — contiguous, cache-friendly, FFI-compatible. This is fundamentally different from `List[U8]`, which is a GC-managed array with potential per-element boxing overhead.

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

Bytes implements: `Sized`, `Eq`, `Clone`, `Debug`, `IntoIterator[U8]`.

**Why a separate type from `List[U8]`.** Memory layout is non-negotiable for I/O, FFI, and crypto. `List[U8]` makes no contiguous-memory guarantee — every FFI call would require copying to a C buffer. `memcpy` on contiguous `Bytes` is SIMD-optimized; iterating boxed `List[U8]` has pointer-chasing overhead per element. For a 1MB file read, this is 10-100x slower. (Panel vote: 5-0.)

**Why Tier 1, not prelude.** `Bytes` is needed by core effects (`FS.Read`, `Net.Connect`, `Crypto.Hash`) but not every program does binary I/O. Tier 1 means it ships with the compiler and is version-locked. The API surface should remain minimal in Tier 1; richer operations (base64, compression) belong in higher tiers. (Panel vote: 5-0.)

##### Numeric Extensions

**F32** (built-in, sized numeric family):

```pact
let x: F32 = F32.from(3.14)
let y: F32 = x.mul(F32.from(2.0))
let back: Float = y.to_float()     // widening via From, infallible
```

`F32` maps to C `float` (32-bit IEEE 754). It joins the existing sized numeric family (`I8`, `I16`, `I32`, `U8`, `U16`, `U32`, `U64`). Widening `F32 → Float` via `From` (infallible). Narrowing `Float → F32` via `TryFrom` (precision loss). F32 is relevant for GPU interop, ML inference weights, and memory-constrained numerical arrays. (Panel vote: 5-0.)

**Decimal** (`std.decimal`, Tier 2):

```pact
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

```pact
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

GC-managed arbitrary-precision integer. Arithmetic via named methods. `From[Int]` for widening. Needed for cryptography, combinatorics, and scientific computing. Not the default `Int` — Pact chose `Int = i64` for predictable C codegen performance. (Panel vote: 5-0.)

**Why sealed arithmetic is not extended.** The 4-1 sealed decision applies uniformly. `Decimal` and `BigInt` are library types with library implementations, not hardware-mapped primitives. If `Decimal` gets `+`, users rightfully ask why their `Money` newtype cannot. Named methods `.add()`, `.mul()` are usable and maintain the bright-line boundary. (Panel vote: 5-0.)

##### UUID (`std.uuid`, Tier 2)

```pact
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

C representation: `typedef struct { uint64_t hi; uint64_t lo; } pact_uuid;` — 16 bytes, two 64-bit words. Fast comparison (`memcmp` on 16 bytes vs 36-byte string), fast hashing (already well-distributed).

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

**Keyword labels are not part of the type.** Declaration-site keyword parameters (see [2.13](02_syntax.md#213-declaration-site-keyword-arguments)) use `--` to separate positional from keyword params, but labels are call-site enforcement only. The function type ignores labels entirely:

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

### 3.5 Pattern Matching

Pattern matching is Pact's primary mechanism for branching on data shape. Every `match` expression must exhaustively cover all possible values of the scrutinee type. The compiler rejects non-exhaustive matches at compile time.

```pact
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

```pact
match status {
    200 => "ok"
    404 => "not found"
    _ => "other"
}
```

**Constructor.** Matches enum variants, destructuring their fields.

```pact
fn area(shape: Shape) -> Float {
    match shape {
        Circle(r) => 3.14159 * r * r
        Rectangle(w, h) => w * h
        Point => 0.0
    }
}
```

**Nested patterns.** Patterns compose — any sub-position accepts a full pattern.

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

**Tuple patterns.** Match and destructure tuple values (see also §3.8).

```pact
fn classify(pair: (Int, Int)) -> Str {
    match pair {
        (0, 0) => "origin"
        (0, _) => "y-axis"
        (_, 0) => "x-axis"
        _ => "other"
    }
}
```

**Struct patterns.** Match struct types by field values. Type name is required (nominal matching). Field punning binds a field to a variable of the same name. `..` is required when not all fields are listed.

```pact
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

```pact
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
 --> input.pact:5:5
  |
5 |     Some(x) | None => use(x)
  |     ^^^^^^^   ^^^^ `None` does not bind `x`
  |
  = help: all alternatives must bind the same variables
```

#### Range Patterns

Integer and character ranges match contiguous value sets. Both `..` (exclusive end) and `..=` (inclusive end) are supported, consistent with range expression syntax (§2.9). Bounds must be const expressions (§2.20). Only `Int`, sized integers (`I8`, `U8`, etc.), and `Char` types are allowed — not `Float` or `Str`. The exhaustiveness checker tracks covered ranges.

```pact
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

```pact
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

```pact
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
 --> geometry.pact:15:5
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

```pact
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
 --> auth.pact:3:5
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

```pact
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

trait Clone {
    fn clone(self) -> Self
}

trait Debug {
    fn debug(self) -> Str
}
```

The `Ordering` type used by `Ord.cmp` is compiler-known and auto-imported in the module prelude (vote: 5-0):

```pact
type Ordering {
    Less
    Equal
    Greater
}
```

#### The `Self` Type

`Self` is a built-in type alias that refers to the implementing type. It is valid in exactly two contexts:

1. **Trait declarations** — `Self` refers to whichever type will implement the trait.
2. **`impl` blocks** — `Self` refers to the type being implemented.

Outside these contexts, `Self` is a compile error.

```pact
trait Eq {
    fn eq(self, other: Self) -> Bool       // Self = the implementing type
    fn ne(self, other: Self) -> Bool {
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
 --> utils.pact:3:18
  |
3 |     fn clone() -> Self {
  |                    ^^^^ `Self` is only valid inside trait declarations and impl blocks
```

**`self` is sugar for `self: Self`.** The first parameter of a trait method can be written as bare `self`, which desugars to `self: Self`. Method-call syntax (`x.method()`) requires the first parameter to be literally `self` — a method with `self` renamed (e.g., `this: Self`) is callable only via qualified syntax `Trait.method(this)`.

```pact
trait Display {
    fn display(self) -> Str          // self: Self, enables x.display()
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
 --> shapes.pact:12:9
  |
12|         Self { x: 0, y: 0 }
  |         ^^^^ cannot construct with `Self`
  |
  = help: use the concrete type name: `Point { x: 0, y: 0 }`
```

**`self` is always passed by value.** Pact is garbage-collected — there is no by-reference vs by-move distinction. The `self` parameter is a value like any other parameter. No `&self`, `&mut self`, or `self: Box[Self]` forms exist.

#### Arithmetic Traits

```pact
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
 --> vector.pact:8:1
  |
8 | impl Add for Vector2 {
  | ^^^^^^^^ `Add` is sealed -- only built-in numeric types may implement it
  |
  = note: arithmetic traits (Add, Sub, Mul, Div, Rem, Neg) are compiler-restricted
  = help: define a named method instead: `fn add(self, other: Vector2) -> Vector2`
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
- `Float` does **not** implement `Hash` (float equality is fraught for hashing)

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

#### Trait Coherence

Coherence guarantees that for any (Trait, Type) pair, at most one implementation exists in the entire program. This invariant is essential -- trait dispatch must be deterministic, and evidence-passing compilation ([Codegen Backend rationale](../decisions/codegen-backend-bootstrap.md)) requires exactly one vtable per (Trait, Type) pair at every call site.

Three rules enforce coherence: the orphan rule, the overlap rule, and the impl placement rule.

#### Orphan Rule

`impl Trait for Type` is allowed in module M if and only if **M's package defines Trait or M's package defines Type** (or both). A third-party package cannot implement a trait from package X for a type from package Y.

```pact
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
 --> myapp/formatting.pact:3:1
  |
3 | impl Display for HttpResponse {
  | ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ neither `Display` nor `HttpResponse` is defined in this package
  |
  = note: impl must be in the package that defines the trait or the type
  = help: define a newtype wrapper, or add this impl to the `http` package
```

The workaround for the orphan restriction is the **newtype pattern** -- wrap the foreign type in a local struct:

```pact
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

```pact
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
 --> render.pact:12:1
  |
5 | impl Render for List[T] where T: Display {
  | ------------------------------------------ first impl
  ...
12| impl Render for List[Int] {
  | ^^^^^^^^^^^^^^^^^^^^^^^^^^ overlaps: `List[Int]` matches both impls
  |
  = note: Pact does not support specialization
  = help: use a newtype wrapper or restructure with a helper trait
```

**Why no specialization.** Specialization requires a partial ordering on impls and interacts with type inference in subtle, unsound ways. Rust has kept specialization unstable for over a decade due to repeated soundness holes. Without specialization, adding a new impl to a library can never silently change which impl is selected for existing code -- it can only cause a new overlap error, which is loud and fixable. Each (Trait, Type) pair maps to exactly one vtable with zero ambiguity.

**Workarounds for specialized behavior:** Use a helper trait to dispatch on the element type, or use the newtype pattern to create a distinct type with its own impl.

#### Impl Placement

The impl placement rule follows from the orphan rule: `impl Trait for Type` must live in a module belonging to the package that defines `Trait` or the package that defines `Type`. Within that package, any module is acceptable -- the impl does not need to be in the same file as the type or trait declaration.

```pact
// Package: myapp

// src/models.pact — defines User
pub type User {
    name: Str
    email: Str
    age: Int
}

// src/formatting.pact — impl in same package as User, different file
import models.{User}

impl Display for User {
    fn display(self) -> Str {
        "{self.name} ({self.email})"
    }
}
```

This is valid because `User` is defined in `myapp` and the impl is also in `myapp`. Intra-package module references are allowed (§10.5).

**Impl visibility.** Impls are automatically brought into scope when the type or the trait is imported. There is no syntax to import an impl directly -- importing `User` or importing `Display` is sufficient for the compiler to find and use `impl Display for User`.

```pact
import models.{User}

// Display impl for User is automatically visible because User is in scope
let s = user.display()
```

This means the compiler's impl search is: for `x.foo()` where `x: T`, find all impls of traits with method `foo` for type `T` that are reachable through the import graph. An impl is reachable if it is in a package that the current compilation unit depends on (directly or transitively) and either the trait or the type is in scope.

**Why auto-visibility.** Requiring explicit impl imports would be pure boilerplate -- you would need to know the module path of every impl for every trait you use. Auto-visibility on trait/type import means that importing a type gives you access to all its behavior, and importing a trait gives you access to all types that implement it. This is the right default for locality of reasoning: one import, complete behavior.

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

```pact
trait Closeable {
    fn close(self)
}
```

A type implementing `Closeable` holds resources (file handles, sockets, locks, database cursors) that must be released deterministically — not when the GC gets around to it, but at a specific point in the program. The `with...as` construct (section 2.17, section 5.5) guarantees `close()` is called on all exit paths.

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
| Struct | `"User { name: \"Alice\", age: 30 }"` | User-defined |

String interpolation (`"{value}"`) invokes `Display`. Explicit `value.debug()` is required for the structural form.

##### Display Format Protocol

String interpolation `"hello {name}"` desugars to a string concatenation where each `{expr}` requires `T: Display` at compile time. The protocol has three aspects: requirement enforcement, desugaring mechanism, and context-sensitive behavior.

**Requirement: strict compile error.** Every `{expr}` in a string literal requires the expression's type to satisfy `T: Display`. If the type does not implement `Display`, the compiler emits an error:

```
error[MissingDisplayImpl]: type `Matrix` does not implement `Display`
  --> app.pact:12:34
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
   - **User types**: emit `Display.display(expr)` — a qualified trait call producing a `Str`, then concatenate.

Example desugaring:

```pact
let name = "Alice"
let age = 30
let msg = "hello {name}, you are {age} years old"

// Type check: Str: Display ✓, Int: Display ✓
// Codegen (conceptual C):
//   snprintf(buf, ..., "hello %s, you are %d years old", name, age)
```

```pact
@derive(Display)
type Point { x: Float, y: Float }

let p = Point { x: 1.0, y: 2.5 }
let msg = "at {p}"

// Type check: Point: Display ✓ (via @derive)
// Codegen (conceptual C):
//   char* tmp = Display_display_Point(p);
//   snprintf(buf, ..., "at %s", tmp)
```

The two-phase approach preserves the semantic guarantee (every interpolated type has a Display impl) while allowing the C backend to use efficient format specifiers for built-in types. This matches the current compiler's existing snprintf-based codegen.

**Query[C] context: Display not invoked.** In `Query[C]` typed strings (§3b.5), interpolation has different semantics — `{expr}` produces a parameterized placeholder, not a string concatenation. Display is **not** invoked in Query context:

```pact
let id = 42
let name = "Alice"

// Normal Str context — Display invoked:
let msg = "user {id}: {name}"           // "user 42: Alice"

// Query[DB] context — Display NOT invoked:
let q: Query[DB] = "SELECT * FROM users WHERE id = {id} AND name = {name}"
// Produces: Query { template: "SELECT * FROM users WHERE id = $1 AND name = $2",
//                   params: [42, "Alice"] }  ← raw typed values, not strings
```

The set of types valid as Query parameters is compiler-known: `Int`, `Float`, `Str`, `Bool`, `Option[T]` (where `T` is a valid param type). Using a type outside this set in a Query interpolation is a compile error. The `Raw(expr)` marker type bypasses parameterization for a specific interpolation (see §3b.5).

This separation is critical: calling `Display.display()` first and then parameterizing the resulting `Str` would defeat `Query[C]`'s injection safety by losing type information and forcing all parameters through string round-tripping.

##### Product Type Codegen (Structs)

For a product type, derived traits operate field-by-field in declaration order:

```pact
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
| `Display` | `"{f1}, {f2}, ..."` compact comma-separated |
| `Debug` | `"TypeName { f1: {f1.debug()}, f2: {f2.debug()}, ... }"` |

##### Sum Type Codegen (Enums)

For a sum type, derived traits match on variant pairs:

```pact
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

##### Generic Type Bound Inference

When deriving for a generic type, the compiler **infers** trait bounds on type parameters from field usage:

```pact
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
 --> myfile.pact:1:9
  |
1 | @derive(Hash)
  |         ^^^^ cannot derive `Hash`
  |
 --> myfile.pact:3:5
  |
3 |     temperature: Float
  |     ^^^^^^^^^^^^^^^^^^ `Float` does not implement `Hash`
  |
 --> myfile.pact:4:5
  |
4 |     weight: Float
  |     ^^^^^^^^^^^^^ `Float` does not implement `Hash`
  |
  = help: remove `Hash` from @derive, or implement `Hash` manually
```

All failing fields are reported in one pass so the developer can fix everything at once.

#### §3.6.2 Serialization Traits

Pact provides compiler-known `Serialize` and `Deserialize` traits for JSON serialization. These are Tier 1 (ship with the compiler) and derivable via `@derive`.

##### Trait Declarations

```pact
trait Serialize {
    fn to_json(self) -> JsonValue
}

trait Deserialize {
    fn from_json(json: JsonValue) -> Result[Self, JsonError]
}
```

`JsonValue` is a compiler-known enum representing the JSON data model:

```pact
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

```pact
type JsonError {
    message: Str
}
```

##### Derive Behavior

`@derive(Serialize)` generates a `to_json` implementation that converts each field to a `JsonValue` and wraps them in `JsonValue.Object`. Field names in JSON match struct field names exactly — no renaming in v1.

```pact
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

| Pact Type | JSON Representation |
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

```pact
let json_val = forecast.to_json()       // pure: data → data
let json_str = json.stringify(json_val)  // pure: JsonValue → Str
fs.write(file, json_str)?               // effectful: ! FS.Write
```

##### Usage

```pact
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

```pact
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

```pact
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

##### Dynamic Navigation (JsonValue Methods)

`JsonValue` provides navigation methods returning `Option` for partial access into the JSON tree. Navigation is inherently partial — a key may not exist, an index may be out of bounds, a value may not be the expected type. `Option` is the canonical encoding of partiality in Pact, composing naturally with `?` (early return) and `??` (default value).

```pact
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

```pact
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

```pact
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

```pact
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

```pact
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

### 3.8 Tuple Types

Tuples are anonymous product types — fixed-size, heterogeneous, ordered collections of values. They serve as lightweight grouping for returning multiple values, iterating over key-value pairs, and passing small bundles of data without defining a named struct.

#### Syntax

```pact
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

```pact
fn log(msg: Str) ! IO {
    io.println(msg)
}
// return type is (), omitted by convention
```

#### No 1-Tuples

`(T)` in type or expression position is always parenthesization, never a 1-tuple. The 1-ary product is isomorphic to `T` and adds no expressiveness. For newtype wrapping, use a named struct:

```pact
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

```pact
let ok = (1, 2, 3, 4, 5, 6)           // OK: arity 6
let bad = (1, 2, 3, 4, 5, 6, 7)       // COMPILE ERROR
```

```
error[TupleArityExceeded]: tuple arity exceeds maximum
 --> data.pact:3:11
  |
3 |     let x = (1, 2, 3, 4, 5, 6, 7)
  |             ^^^^^^^^^^^^^^^^^^^^^^^ tuple has 7 elements, maximum is 6
  |
  = help: use a named struct for data with more than 6 fields
```

**Why cap at 6.** Tuples are anonymous — elements have no names, only positions. Beyond 3-4 elements, positional access (`.4`, `.5`) becomes unreadable and error-prone. A cap at 6 provides headroom for real use cases (coordinate triples, tagged pairs, iterator adapters) while pushing complex data toward named structs where field names carry semantic information. The cap also bounds the compiler's trait impl generation to a small fixed set of arities.

#### Element Access

Tuple elements are accessed by zero-indexed numeric fields: `.0`, `.1`, `.2`, etc. These are compile-time resolved field accesses, not method calls.

```pact
let point = (10.0, 20.0, 30.0)
let x = point.0    // 10.0
let y = point.1    // 20.0
let z = point.2    // 30.0
```

Out-of-bounds access is a compile error:

```pact
let pair = (1, 2)
pair.2              // COMPILE ERROR: tuple (Int, Int) has no field `2`
```

#### Destructuring

Tuples support irrefutable destructuring in `let` bindings (see also §3.5):

```pact
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

```pact
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

```pact
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
 --> render.pact:5:12
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
