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

2. **Every typing rule must be visible to `blink check`.** No rule is enforced only at codegen. A rule the front end cannot see is a rule no editor, no formatter, no fixer, and no agent in a loop can act on, and it turns a user error into an internal compiler error.

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
Str             // UTF-8 string
Char            // Unicode scalar value

// Logic
Bool            // true, false

// Unit
()              // The unit type. One value. No information.

// Bottom
Never           // The bottom type. No values. The type of code that cannot finish.

// Collections
List[T]         // Growable ordered sequence
Map[K, V]       // Hash map
Set[T]          // Hash set

// Core ADTs (defined in stdlib, special compiler support)
Option[T]       // Some(value) | None. Written T? in a type
Result[T, E]    // Ok(value) | Err(error)
```

**`Never` is the bottom type.** `Never` has no values. It is the type of a construct that cannot finish normally: a call to `panic(...)`, `todo()` or `unreachable()` (§2.20), a call to a function declared `-> Never`, a jump (§2.11 *Jumps*), or a `loop` that no `break` targets. §3.3 *Divergence and Body Completeness* lists every such construct. No literal, constructor or conversion makes a `Never`. Only a construct that diverges (§3.3) has this type. A program may write `Never` in any type position: a return type, a parameter, a field, a `let` annotation, or a type argument such as `Result[Int, Never]`. `Never` is a subtype of every type. Inference never chooses `Never` for a slot that the program left open (§3.4 *Under-Determined Types*). `Never` is not `()`: `()` has one value, and `Never` has none.

Because `Never` is a subtype of every type (§3.3), a value of type `Never` fits wherever any type is expected. This does not go through a type constructor: `List[Never]` is not a `List[Int]`, `Result[Int, Never]` is not a `Result[Int, Str]`, and `fn() -> Never` is not a `fn() -> Int`. To widen such a value, take it apart and build it again:

```blink
fn load() -> Result[Int, Str] {
    let r: Result[Int, Never] = Ok(3)
    match r {
        Ok(v) => Ok(v),
        Err(e) => e,
    }
}
```

The `Err(e)` arm is required (§3.5 *Exhaustiveness*). Its body `e` has type `Never`, so it fits the declared return type `Result[Int, Str]`. A type mismatch (E0300) between a type that has `Never` as a type argument and a wider type names this `match` rewrite as its repair. It may also name a `map_err` call with the target error type written out.

`Never` implements no trait unless the prelude declares an impl of that trait for `Never`. No rule derives an impl for `Never` from the fact that it has no values.

The prelude declares seven impls for `Never`: `Eq`, `Ord`, `Hash`, `Clone`, `Debug`, `Display` and `Serialize`. This list is closed. **Each prelude impl for `Never` holds only methods that take a `Never` argument.** That sentence limits the list. It does not give `Never` an impl of each trait that meets it. So `Never` has no `Deserialize` (`from_json` is static), no `Default`, no `From` or `TryFrom` in either direction, and none of the numeric operator traits. No method of these impls can run, because no value of type `Never` exists. The spec states no `debug()` or `display()` text for `Never`, and the laws that tie `Ord`, `Hash` and `Debug` to `Eq` (§3.6) hold with nothing to check.

These impls let the conditional container impls (§3.6 *Container Equality*, *Debug vs Display*) and user derives reach a type argument that is `Never`:

```blink
@derive(Eq, Hash, Debug)
type Key[E] { id: Int, tag: E }

fn first(r: Result[Int, Never]) -> Int {
    assert_eq(r, r)              // Eq and Debug on Result[Int, Never]
    let shown = "{r.debug()}"    // "Ok(3)" when r is Ok(3)
    r.unwrap()                   // unwrap needs Debug on the Err arm
}
```

`"{r}"` is still an error (E0523) for every `Result`, because `Result` has no `Display` (§3.6 *Debug vs Display*). `Key[Never]` is a valid type: it is `Eq`, `Hash` and `Debug`, but it has no values.

When a trait bound fails because `Never` has no impl of the trait (E0306), the error adds a `note:` that lists the seven impls above and a `help:`. When the `Never` is a type argument of a value's type, and the type that the `match` rewrite above gives meets the bound, the help names that rewrite. Otherwise the help names the bound that failed. The error never suggests deriving or implementing the trait for `Never`.

`-> Never` does not remove the effect row. `fn exit(code: Int) -> Never` in `Env.Exit` (§4.4.3) still needs `! Env.Exit` at each call.

**Why short names.** `Str` not `String`. `Int` not `Integer`. `Bool` not `Boolean`. These are the most-written types in any codebase. Over thousands of occurrences, 3 characters vs 6 saves real token budget. All types are PascalCase -- no special casing rules, no distinction between "primitive" and "user-defined." `Str` and `UserProfile` follow the same convention.

**Why one default `Int`.** Rust's numeric type matrix (`i8`/`i16`/`i32`/`i64`/`u8`/.../`usize`/`isize`) is a decision tree that produces wrong answers. LLMs pick `i32` when they mean `i64`, `usize` when they mean `u64`, and `u32` for values that go negative. Blink has `Int`. It's 64-bit. It's signed. It handles every integer you'll encounter in application code. The sized variants (`I8`, `U16`, etc.) exist for interop, binary protocols, and performance-critical paths where you've measured and know you need them.

**Why `Float` not `F32`/`F64`.** Same reasoning. 64-bit is correct for virtually all floating-point work. If you need 32-bit floats (GPU interop, large arrays where memory matters), that's a future extension, not a v1 concern.

**One Spelling for List and Option Types.** Each of these types has one spelling in a type position (Principle 2):

| Type | Spelling | Not a spelling |
|------|----------|----------------|
| List of `T` | `List[T]` | `[T]` |
| Option of `T` | `T?` | `Option[T]` |

A type position is a parameter, return, field, `let` or type alias annotation, a type argument inside another type, and an explicit type-argument list at a call.

- **`[T]` in a type** is `ListTypeBrackets` (E1131). A generic binder list (`fn f[T]`, `impl[T]`) is not a type. The machine-applicable fix writes `List[T]`. In an expression, square brackets keep their meaning: `[1, 2]` is a list literal and `[..a, ..b]` is a spread.
- **`Option[T]` in a type** is `OptionTypeLongForm` (E1132). The machine-applicable fix writes `T?`, also inside other types: `List[Option[Int]]` becomes `List[Int?]`, and `f[Option[Int]](x)` becomes `f[Int?](x)`.
- **`Option` stays a name.** A path (`Option.Some`), the self type of an `impl` header, a trait bound and prose keep the name `Option`. Only the type positions above take `T?`.
- **`?` is a type suffix.** It applies to the type before it: `List[Int]?` is an optional list, `List[Int?]` is a list of optional values, and `(Int, Str)?` is an optional tuple.
- **Nested Option.** The type parser reads a `??` token as two `?` suffixes, so `Int??` is `Option[Option[Int]]`. In an expression, `??` stays the defaulting operator.
- **Identity.** `T?` names the compiler-known `Option` by identity, so a user type named `Option` does not change it (§10.6 *Shadowing Rules*).
- **No warning release.** E1131 and E1132 are errors at once. Each keeps its machine-applicable fix.

`blink fmt` writes `List[T]` and `T?`. No setting picks another spelling. Diagnostics and their fixes print types the same way: `expected Str?, found Int`, and the E0301 fix `: List[T]`.

```blink
type Profile {
    name: Str
    tags: List[Str]
    bio: Str?
    scores: List[Int?]
}

fn first_tag(p: Profile) -> Str? {
    p.tags.get(0)
}

fn lookup(cache: Map[Str, Int?], key: Str) -> Int?? {
    cache.get(key)
}
```

**Why one spelling.** Two spellings of one type is a choice with no effect on the program, and Principle 2 removes such choices. `T?` is the short form of the most common wrapper and the §2.2 locked spelling. `[T]` saved four characters, but it is the same text as a list literal and a generic binder, so `List[T]` stays the one list spelling. Making the long Option form a diagnostic, and not only a formatter rewrite, keeps one spelling in code that never goes through `blink fmt`. (Panel vote: see [Single Type Spellings rationale](../decisions/type-sugar-single-spelling.md).)

**Why `Option` and `Result` are built-in.** These aren't library types bolted on after the fact. The compiler understands them: `T?` is the type-position spelling of `Option[T]`, the `?` operator desugars to a match on `Result`, `??` desugars to a match on `Option`. Special syntax demands special compiler support.

**Stdlib API surface: methods only.** Built-in types expose their API exclusively through trait methods — `.len()`, `.split()`, `.push()`, `.write()`, etc. No function form of a built-in method exists. There is one way to call an operation on a built-in type: method syntax. Constructors use static method syntax on the type name (`Bytes.new()`, `StringBuilder.with_capacity(1024)`, `Duration.ms(100)`). This follows Principle 2 — no decision point between `s.len()` and `str_len(s)`. (Panel vote: 4-1. See [Stdlib API Surface rationale](../decisions/stdlib-api-surface.md).)

**The rule binds the standard library.** No `std` module exports a function form of a built-in method. A `std` function that a method or the compiler lowers to is not exported, so user code cannot name it. Derived code (§3.6.1, §3.6.2) calls such functions after name resolution, so no visibility rule applies to those calls.

**Removed function forms.** Earlier versions of the standard library exported function forms of built-in methods. A call to one of these names gives the usual undefined-function error (E0504), with a fix that names the replacement. An import that names one of them (`import std.list.{list_map}`) gets the same error and fix at the import. The compiler keeps the table below for good. It looks in the table only when name lookup fails, so a program that declares its own `fn parse_int` still compiles and calls that function. The third column says when the replacement does not give the same result type or value. Then the fix must change more than the call.

| Removed name | Replacement | Result changes |
|---|---|---|
| `list_map(xs, f)`, `list_filter(xs, p)`, `list_flat_map(xs, f)` | `xs.map(f)`, `xs.filter(p)`, `xs.flat_map(f)` (§3.2.2) | no |
| `list_fold(xs, init, f)` | `xs.fold(init, f)` | no |
| `list_any(xs, p)`, `list_all(xs, p)`, `list_find(xs, p)` | `xs.any(p)`, `xs.all(p)`, `xs.find(p)` | no |
| `list_for_each(xs, f)` | `for x in xs { f(x) }` | no |
| `list_enumerate(xs)`, `list_zip(a, b)`, `list_skip(xs, n)` | `xs.enumerate()`, `a.zip(b)`, `xs.skip(n)` | no |
| `list_slice(xs, a, b)` | `xs.slice(a, b)` | no |
| `list_sort(xs)`, `list_sort_by(xs, cmp)` | `xs.sort()`, `xs.sort_by(cmp)` | no |
| `map_filter(m, p)`, `map_map_values(m, f)` | `m.filter(p)`, `m.map_values(f)` (§3.2.2) | no |
| `map_fold(m, init, f)` | `m.fold(init, f)` | no |
| `map_merge(a, b)` | `a.merge(b)` | no |
| `map_for_each(m, f)` | `for (k, v) in m { f(k, v) }` | no |
| `str_split(s, d)`, `str_lines(s)`, `str_replace(s, a, b)` | `s.split(d)`, `s.lines()`, `s.replace(a, b)` (§3.2.1) | no |
| `str_trim(s)`, `str_trim_left(s)`, `str_trim_right(s)` | `s.trim()`, `s.trim_start()`, `s.trim_end()` | no |
| `str_to_upper(s)`, `str_to_lower(s)` | `s.to_upper()`, `s.to_lower()` | no |
| `str_join(parts, d)` | `parts.join(d)` | no |
| `str_char_at_opt(s, i)` | `s.char_at(i)` | no |
| `str_cp_index_of(s, n)`, `str_byte_index_of(s, n, from)` | `s.index_of(n)`, `s.byte_index_of(n, from)` | no |
| `str_from_code_point(n)` | `Char.from_code_point(n)?`, then `"{c}"` (§3c.3) | yes: `Str` becomes `Result[Char, ConversionError]` |
| `int_to_str(n)`, `float_to_str(x)` | `"{n}"`, `"{x}"` | no |
| `parse_int(s)` | `s.parse_int()` (§3.2.1 *Parsing*) | yes: `Int` becomes `Result[Int, ConversionError]`, and text such as `"12x"` or `""` gives `Err` |
| `parse_float(s)` | `s.parse_float()` | yes: `Float` becomes `Result[Float, ConversionError]`, and text such as `"1.5x"` or `""` gives `Err` |
| `json_escape_str(s)` | `json.stringify(JsonValue.Str(s))` (§3.6.2) | yes: the result has the surrounding quotes |
| `list_concat(a, b)` | `a.append(b)` (§3.2.2 *Concatenation*) | no |
| `Map()`, `Map[K, V]()` | `Map.new()`, `Map.new[K, V]()` (§3.2.2 *Construction and Mutability*) | no |
| `Set()`, `Set[T]()` | `Set.new()`, `Set.new[T]()` | no |
| `Bytes()` | `Bytes.new()` | no |
| `List.new()`, `List.new[T]()` | `[]`, with the element type from an annotation (`let xs: List[T] = []`), from the expected type or from a later use | no |
| `xs.chain(ys)` on `List` | `xs.append(ys)`; for a lazy sequence, `xs.into_iter().chain(ys.into_iter())` (§3c.1) | no |
| `m.contains_key(k)` on `Map` | `m.contains(k)` (§3.2.2 *The `Contains` Trait*) | no |

```
error[UndefinedFunction]: undefined function `parse_int`
 --> main.bl:3:15
  |
3 |     let n = num.parse_int(text)
  |                 ^^^^^^^^^ not found in module `std.num`
  |
  = note: `parse_int` is a method on `Str`
  = fix: text.parse_int()
  = help: `.parse_int()` returns `Result[Int, ConversionError]`; add `?` or match on the result
```

**Removed methods.** A row that names a method call also names the receiver type. The compiler looks at such a row only when method lookup fails for a receiver of that type, so `Iterator.chain` and a `chain` method from a user trait on `List` still resolve as usual. The failed call is the usual unresolved-method error (E0505), and it carries the fix from the row. The third column and the `blink fix` rules apply to a method row as they do to a function row. The table holds only names that a released version of Blink or its standard library accepted. A released type is replaced when a decision names a successor type for it. A row for a method of a replaced type is keyed by the successor type, because a program that has moved to the new API holds a value of that type. The key does not give the successor type the old method: the call stays an error, and the row gives the fix.

```
error[UnresolvedMethod]: no method `contains_key` on `Map[Str, Int]`
 --> main.bl:4:12
  |
4 |     if ages.contains_key("ann") {
  |             ^^^^^^^^^^^^ not found
  |
  = note: `contains_key` was removed; `contains` tests key presence on a `Map`
  = fix: ages.contains("ann")
```

**Removed empty forms.** Each type has one empty form (§3.2.2 *Construction and Mutability*). The older forms are errors. Each error carries the fix from its table row:

- **`Map()`, `Map[K, V]()`, `Set()`, `Set[T]()` and `Bytes()`** name a function that does not exist, so each is `error[UndefinedFunction]` (E0504). The machine-applicable fix keeps the type arguments that the code wrote: `Map()` becomes `Map.new()`, `Map[K, V]()` becomes `Map.new[K, V]()`, `Set()` becomes `Set.new()`, `Set[T]()` becomes `Set.new[T]()`, and `Bytes()` becomes `Bytes.new()`.
- **`List.new()`** names a missing function in the scope of `List`, so it is `error[UnresolvedMethod]` (E0505). The machine-applicable fix writes `[]`. Both forms take their element type from the same sources, so the edit does not change the type.
- **`List.new[T]()`** is `error[UnresolvedMethod]` (E0505). The fix writes `[]` and the type `List[T]`. It is machine-applicable only when the call is the whole initializer of a `let` whose pattern is a plain name with no annotation. Then one edit writes the annotation and `[]` together: `let xs = List.new[Int]()` becomes `let xs: List[Int] = []`. In any other place the fix is a suggestion only, because the call does not own a place for the annotation. When the `let` has an annotation that disagrees with `[T]`, there is no fix, and the type error stands.
- **A kept form has no diagnostic.** `let s: Set[Str] = Set.new[Str]()` is correct.
- **The fix text comes from the table rows above.** There is one source for it.

`List()`, `List[T]()` and `StringBuilder()` have no row. No released version of Blink accepted them, and the table holds only names that a released version accepted. Each is E0504. The help of that error names the one empty form of the type (§6.3.5 *Error Recovery*).

```
error[UndefinedFunction]: undefined function `Map`
 --> main.bl:3:15
  |
3 |     let ages = Map[Str, Int]()
  |                ^^^ `Map` is a type, not a function
  |
  = fix: Map.new[Str, Int]()
```

Some names have no method twin, because a different form is the one way. A loop over a collection is a `for` loop: there is no `for_each` method on `List` or `Map`. A method-not-found error for `xs.for_each(f)` or `m.for_each(f)` gives help that shows the `for` loop. A `Str` from a codepoint goes through `Char`. A JSON string goes through the JSON encoder.

(Panel vote: 6-0 on the table. See [Removed Function Forms rationale](../decisions/removed-function-forms.md). The `list_concat`, `List.chain` and `Map.contains_key` rows and the method rows: 6-0. See [Duplicate APIs rationale](../decisions/duplicate-apis.md). The empty-form rows: 6-0; the owner removed the warning release. See [Empty Collection Constructors rationale](../decisions/empty-collection-constructors.md).)

#### §3.2.1 String Methods

Strings are not bare character arrays. They are UTF-8 encoded, immutable values with a method surface designed to be complete enough that 90% of programs never need a string utility library. Methods are organized into two traits: `Sized` (generic, shared with collections) and `StrOps` (string-specific).

**Every `Str` is valid UTF-8.** Every safe way to make a `Str` gives valid UTF-8: literals, interpolation, the `Str` methods, `StringBuilder`, and `Bytes.to_str`, which returns `Err` on input that is not valid UTF-8 or that holds a NUL byte (a `Str` cannot hold NUL). A `Str` that comes in through `@ffi` or `@trusted` code (§9) must also be valid UTF-8. The compiler cannot check that, so the author of that boundary must make sure of it. The codepoint methods and the `byte_slice` boundary check depend on this invariant.

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

For `Str`, `.len()` returns the **codepoint count** — the number of Unicode scalar values, not the number of bytes. This is O(n) for general UTF-8, but it gives the semantically correct answer: `"café".len()` is `4`, not `5`.

##### The `StrOps` Trait

All string-specific methods live in a single `StrOps` trait. `Str` is the only type that implements it.

```blink
trait StrOps {
    // Character access
    fn char_at(self, index: Int) -> Option[Char]
    fn byte_len(self) -> Int
    fn byte_at(self, index: Int) -> U8
    fn byte_slice(self, start: Int, end: Int) -> Str

    // Search
    fn contains(self, needle: Str) -> Bool
    fn starts_with(self, prefix: Str) -> Bool
    fn ends_with(self, suffix: Str) -> Bool
    fn index_of(self, needle: Str) -> Option[Int]
    fn byte_index_of(self, needle: Str, from: Int) -> Option[Int]

    // Extraction and transformation
    fn substring(self, start: Int, end: Int) -> Str
    fn concat(self, other: Str) -> Str
    fn split(self, separator: Str) -> List[Str]
    fn lines(self) -> List[Str]
    fn to_upper(self) -> Str
    fn to_lower(self) -> Str
    fn trim(self) -> Str
    fn trim_start(self) -> Str
    fn trim_end(self) -> Str
    fn trim_by(self, pred: fn(Char) -> Bool ! _) -> Str ! _
    fn trim_start_by(self, pred: fn(Char) -> Bool ! _) -> Str ! _
    fn trim_end_by(self, pred: fn(Char) -> Bool ! _) -> Str ! _
    fn strip_prefix(self, prefix: Str) -> Option[Str]
    fn strip_suffix(self, suffix: Str) -> Option[Str]
    fn pad_start(self, width: Int, fill: Char) -> Str
    fn pad_end(self, width: Int, fill: Char) -> Str
    fn repeat(self, n: Int) -> Str
    fn replace(self, needle: Str, replacement: Str) -> Str

    // Parsing
    fn parse_int(self) -> Result[Int, ConversionError]
    fn parse_float(self) -> Result[Float, ConversionError]
}
```

The full method surface (`Sized` + `StrOps`):

| Method | Signature | Returns |
|--------|-----------|---------|
| `len` | `fn(self) -> Int` | Codepoint count (O(n)) |
| `is_empty` | `fn(self) -> Bool` | `self.len() == 0` |
| `char_at` | `fn(self, Int) -> Option[Char]` | Codepoint at logical index; `None` when out of bounds |
| `contains` | `fn(self, Str) -> Bool` | Substring presence |
| `starts_with` | `fn(self, Str) -> Bool` | Prefix check |
| `ends_with` | `fn(self, Str) -> Bool` | Suffix check |
| `substring` | `fn(self, Int, Int) -> Str` | Codepoint-indexed slice `[start, end)`; clamps |
| `concat` | `fn(self, Str) -> Str` | Concatenation |
| `split` | `fn(self, Str) -> List[Str]` | Split by separator |
| `to_upper` | `fn(self) -> Str` | Uppercase (Unicode-aware) |
| `to_lower` | `fn(self) -> Str` | Lowercase (Unicode-aware) |
| `trim` | `fn(self) -> Str` | Strip leading and trailing whitespace (`Char.is_whitespace`) |
| `trim_start` | `fn(self) -> Str` | Strip leading whitespace only |
| `trim_end` | `fn(self) -> Str` | Strip trailing whitespace only |
| `trim_by` | `fn(self, fn(Char) -> Bool ! _) -> Str ! _` | Strip leading and trailing codepoints that match the predicate |
| `trim_start_by` | `fn(self, fn(Char) -> Bool ! _) -> Str ! _` | Strip leading codepoints that match the predicate |
| `trim_end_by` | `fn(self, fn(Char) -> Bool ! _) -> Str ! _` | Strip trailing codepoints that match the predicate |
| `strip_prefix` | `fn(self, Str) -> Option[Str]` | The rest after the prefix; `None` when `self` does not start with it |
| `strip_suffix` | `fn(self, Str) -> Option[Str]` | The rest before the suffix; `None` when `self` does not end with it |
| `pad_start` | `fn(self, Int, Char) -> Str` | Fill before the text up to `width` codepoints; never truncates |
| `pad_end` | `fn(self, Int, Char) -> Str` | Fill after the text up to `width` codepoints; never truncates |
| `repeat` | `fn(self, Int) -> Str` | `n` copies of `self`; panics when `n < 0` |
| `replace` | `fn(self, Str, Str) -> Str` | Replace all occurrences |
| `index_of` | `fn(self, Str) -> Option[Int]` | Codepoint index of first match |
| `lines` | `fn(self) -> List[Str]` | Split by line endings |
| `parse_int` | `fn(self) -> Result[Int, ConversionError]` | Parse as integer |
| `parse_float` | `fn(self) -> Result[Float, ConversionError]` | Parse as float |
| `byte_len` | `fn(self) -> Int` | Byte count (O(1)) |
| `byte_at` | `fn(self, Int) -> U8` | Raw byte at offset; panics when out of bounds |
| `byte_slice` | `fn(self, Int, Int) -> Str` | Byte-range slice `[start, end)`; clamps; panics when a bound falls inside a codepoint |
| `byte_index_of` | `fn(self, Str, Int) -> Option[Int]` | Byte offset of first match at or after `from` |

The `byte_` methods are exactly the four in this table: `byte_len`, `byte_at`, `byte_slice` and `byte_index_of`. The prefix does not extend to other methods; there is no `byte_split` or `byte_starts_with`.

**Line splitting.** `lines` splits at `\n` and at `\r\n`, and removes the terminators. A terminator at the end of the string does not make an empty last item, and a string with no terminator is one line. So `"a\nb\n".lines()` and `"a\r\nb".lines()` give `["a", "b"]`, `"\n".lines()` gives `[""]`, and `"".lines()` gives `[]`. These are the rules of `io.read_line()` (§4.4.9), so `io.read_all().lines()` gives the same lines as repeated `io.read_line()` calls.

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
s.byte_len()                // 6
s.byte_at(0)                // 104 (ASCII 'h')
s.byte_at(1)                // 195 (first byte of 'é')
s.byte_slice(0, 3)          // "hé" (bytes 0..3; 'é' is 2 bytes)
s.byte_index_of("l", 0)     // Some(3)
s.byte_index_of("l", 4)     // Some(4)
```

Byte code pairs `byte_index_of` with `byte_slice`. Both use byte offsets into the same string, so a scanner never adds offsets back by hand:

```blink
fn fields(line: Str) -> List[Str] {
    let mut out: List[Str] = []
    let mut start = 0
    loop {
        match line.byte_index_of(",", start) {
            Some(i) => {
                out.push(line.byte_slice(start, i))
                start = i + 1
            }
            None => {
                out.push(line.byte_slice(start, line.byte_len()))
                return out
            }
        }
    }
}
```

A non-empty needle that is valid UTF-8 can only match at a codepoint boundary. So every `Some(i)` from `byte_index_of` is a valid `byte_slice` bound, and so is `i + needle.byte_len()`.

Do not mix the two units. `index_of`, `char_at`, `substring` and `len` use codepoint indices; `byte_index_of`, `byte_at`, `byte_slice` and `byte_len` use byte offsets. Both are `Int`, so the type checker does not catch a codepoint index passed to a `byte_` method. On ASCII text the two units agree, so the mistake shows only on non-ASCII input.

##### Out-of-range indices

A **point read** reads one element at an index: `char_at`, `byte_at`, `List.get`, `Bytes.get`. A point read never makes up a value. It returns `Option` when its return type can say "absent", and otherwise panics:

- `char_at` returns `Option[Char]`, so an index out of bounds gives `None`.
- `byte_at` returns a bare `U8`, so an index `< 0` or `>= byte_len()` panics. The panic message names the method, the index and `byte_len`. Byte loops already prove the bound with `i < s.byte_len()`. Code that wants an `Option[U8]` uses `Bytes.get`.

A **range read** returns the part of a sequence in the half-open range `[start, end)`: `substring`, `byte_slice`, `List.slice` and `Bytes.slice`. All four use the same rule. A range read clamps its bounds and never panics on an out-of-range index:

- `start < 0` is read as `0`.
- `end` past the length is read as the length (`len()` for `substring`, `byte_len()` for `byte_slice`, `len()` for `List` and `Bytes`).
- `start >= end` gives an empty result. The bounds are not swapped.
- A negative index does not count from the end.

```blink
"abc".substring(0, 99)      // "abc"
"abc".substring(-5, 2)      // "ab"
"hello".substring(5, 2)     // "" (no swap)
[1, 2, 3].slice(1, 99)      // [2, 3]
```

A clamped result is a real value of the type, so the rule keeps this law for every `a <= b <= c`, in range or not: `s.substring(a, b).concat(s.substring(b, c)) == s.substring(a, c)`.

`byte_slice` adds one rule: after clamping, it panics when `start` or `end` falls inside a multi-byte codepoint. The result would not be valid UTF-8, and the method does not move the bound to a boundary for you.

```blink
"café".byte_slice(0, 4)     // panics: byte 4 is inside 'é' (bytes 3..5)
"café".byte_slice(0, 5)     // "café"
```

`byte_index_of(needle, from)` searches from byte offset `from`. A `from < 0` is read as `0`. A `from` past `byte_len()` gives `None`. A `from` inside a multi-byte codepoint panics, so `None` always means "not found" and never "bad offset". Use `from = 0` to search the whole string.

**Why codepoint-default.** The choice is between three levels of abstraction: bytes (Go, C), codepoints (Python 3, Java), and grapheme clusters (Swift). Bytes are too low-level — indexing into the middle of a multibyte character is a bug factory. Grapheme clusters are linguistically correct but expensive and complex (cluster boundaries depend on Unicode version and locale). Codepoints hit the pragmatic middle: they correspond to what most programmers mean by "character," they are well-defined by Unicode, and they avoid the worst class of string bugs. The `byte_` prefix makes raw access available but intentionally inconvenient (panel vote: 3-2, Systems and PLT dissented wanting byte-default).

`Str` also implements `IntoIterator[Char]`, so `for c in str` iterates codepoints:

```blink
for c in "hello" {
    io.println("{c}")
}

// Or explicitly via .into_iter()
let vowels = "hello".into_iter().filter(fn(c) { "aeiou".contains("{c}") }).collect()
```

##### Trim, Strip, Pad and Repeat

Methods that work on one side of a string name the side `start` (the first codepoint) and `end` (the last codepoint): `trim_start`, `trim_end`, `trim_start_by`, `trim_end_by`, `pad_start`, `pad_end`. The names do not say `left` or `right`. There is no `trim_left` or `trim_right` method; a call to either is `UnresolvedMethod` (E0505) with a help line that names `trim_start` or `trim_end`. (Panel vote: 6-0.)

**Whitespace.** `trim`, `trim_start` and `trim_end` strip exactly the codepoints for which `Char.is_whitespace` is true: the 25 codepoints of the Unicode `White_Space` property (§3.2.4). That set includes `\t`, `\n`, `\r`, U+000B, U+000C, U+0085 and U+00A0 as well as space. For every `s`:

- `s.trim() == s.trim_by(fn(c) { c.is_whitespace() })`
- `s.trim_start() == s.trim_start_by(fn(c) { c.is_whitespace() })`
- `s.trim_end() == s.trim_end_by(fn(c) { c.is_whitespace() })`

**Trim by predicate.** `trim_start_by(pred)` removes codepoints from the start while `pred` returns `true`, and stops at the first codepoint for which it returns `false`. `trim_end_by` does the same from the end. `trim_by` does both. The predicate sees each codepoint as a `Char`. To strip a fixed set of codepoints, test membership in the predicate:

```blink
let path = "//usr/lib//".trim_by(fn(c) { c == '/' })      // "usr/lib"
let n = "0042".trim_start_by(fn(c) { c == '0' })          // "42"
let word = "--a-b--".trim_by(fn(c) { "-_".contains("{c}") }) // "a-b"
```

**Strip a prefix or suffix.** `strip_prefix(p)` returns `Some(rest)` when `self` starts with `p`, where `rest` is `self` without that one leading `p`. It returns `None` when `self` does not start with `p`. `strip_suffix` is the same at the end. An empty argument gives `Some(self)`. For every `s` and `p`: `s.strip_prefix(p)` is `Some(r)` exactly when `s.starts_with(p)`, and then `p.concat(r) == s`.

```blink
"v1.2.0".strip_prefix("v")       // Some("1.2.0")
"1.2.0".strip_prefix("v")        // None
"main.bl".strip_suffix(".bl")    // Some("main")
"aaa".strip_prefix("a")          // Some("aa") (one copy only)
```

**Pad.** `pad_start(width, fill)` puts copies of `fill` before `self` until the result has `width` codepoints. `pad_end` puts them after `self`. The `fill` argument is a required `Char`. `width` counts codepoints, the same unit as `len()`. A pad never truncates: when `width <= self.len()`, a negative `width` included, the result is `self`. For every `s`, `w` and `c`: `s.pad_start(w, c).len() == w.max(s.len())`.

```blink
"7".pad_start(3, '0')      // "007"
"ab".pad_end(5, '.')       // "ab..."
"hello".pad_start(3, ' ')  // "hello" (never truncates)
```

`width` counts codepoints, not terminal columns. A wide CJK character or an emoji takes two columns in most terminals but counts as one codepoint, so a padded table that holds them does not line up on screen.

`pad_start` with `'0'` does not know about a sign: `"-7".pad_start(3, '0')` is `"0-7"`. To zero-pad an `Int`, use `Int.display_zero_padded` (§3.6.1 *Fixed-Decimal and Zero-Padded Forms*), which puts the zeros after the sign.

**Repeat.** `s.repeat(n)` returns `n` copies of `s`, one after the other. `n == 0` gives `""`. `n < 0` panics: the panic message names the count, and its help names `pad_start` and `pad_end`, because a negative count most often comes from `" ".repeat(width - s.len())` on text wider than `width`. When `self.byte_len() * n` overflows `Int`, the call panics. For every `s` and `n >= 0`: `s.repeat(n).len() == s.len() * n`. (Panel vote: 4-2 after Phase D, Web and AI/ML dissented wanting `n <= 0` to give `""`.)

```blink
"ab".repeat(3)        // "ababab"
"-".repeat(0)         // ""
"-".repeat(-1)        // panics: repeat count -1 is negative
```

##### Parsing

`parse_int` and `parse_float` are methods on `Str` rather than standalone functions. They give a discoverable, grep-able API surface. No silently lossy parse function exists in the standard library: every parse of text gives `Err` on text it does not fully accept.

The whole text must match one of these grammars, with nothing before or after it:

```
int      = sign? digits
float    = sign? ( numeric | special )
sign     = "+" | "-"
numeric  = digits ( "." digits )? exponent?
exponent = ( "e" | "E" ) sign? digits
special  = "nan" | "inf" | "infinity"
digits   = one or more ASCII "0" to "9"
```

- `parse_int` accepts `int`. `parse_float` accepts `float`. Both use the same `sign`.
- `special` ignores letter case, for the ASCII letters A to Z only: `NaN`, `INF` and `Infinity` match. No other case mapping applies.
- A sign on `nan` has no effect under `==`: every NaN is `==` every other NaN (*Float Total Ordering*).
- These are `Err`: whitespace before or after the text (call `s.trim()` first), `_`, hex forms, `nan(...)`, a decimal mark other than `.`, and `.5` or `1.` (a digit must be on each side of `.`). The result does not depend on the locale.
- `parse_float` rounds to nearest, ties to even, for any count of digits and any exponent length.
- A `numeric` text whose rounded value is ±infinity gives `Err`. A value that rounds to a subnormal or to zero gives `Ok`, with the sign kept: `"-1e-400"` gives `Ok(-0.0)`.
- `parse_int` gives `Err` for a value outside the `Int` range.
- A parse does not check for canonical text: `"+007".parse_int()` gives `Ok(7)`. To check that `s` is canonical, compare `n.display() == s`.

**Why `.5` and `1.` are `Err`.** No common writer produces these forms by default. A later change to accept them breaks no program, but a later change to refuse them would. (Vote: 4-2, Web/Scripting and AI/ML dissented.)

**Errors.** On failure the result is `Err(ConversionError)`. Its `message` names one cause class from this list:

1. surrounding whitespace, with a hint to call `.trim()`;
2. an unexpected character;
3. missing digits (empty text, no digit on one side of `.`, or no digit after the exponent mark);
4. a value out of range.

The cause class is part of the contract. The wording of `message` is not, so programs must not compare it. The message may also give a position. The size of the message does not grow with the size of the input. If it quotes the input, it quotes a bounded excerpt.

**Laws.** For every text `t`:

- **Round trip.** `x.display().parse_float() == Ok(x)` for every `Float` `x` (§3.6 *Float Text Form*).
- **Int text is Float text.** When `t.parse_int()` gives `Ok`, `t.parse_float()` gives `Ok` with that value, rounded to nearest, ties to even.
- **One number reader.** `json.parse` first matches its own RFC 8259 number grammar (§3.6.2 *Numbers*). For a JSON number `t` that becomes a `JsonValue.Float`, the value is `t.parse_float()`, and when that gives `Err`, `json.parse` gives `Err`. `parse_float` does not decide what JSON accepts.
- **Literals.** The text of every Blink `Float` literal parses with `parse_float` to the value of that literal. This law does not require the literal grammar to accept every text that `parse_float` accepts.
- **Finite in, finite out.** A `numeric` text never gives NaN or ±infinity.

```blink
let port = "8080".parse_int()?                      // Ok(8080)
let rate = "3.14".parse_float()?                     // Ok(3.14)
let bad = "not_a_number".parse_int()                 // Err(ConversionError)
let big = "1E5".parse_float()                        // Ok(100000.0)
let pos = "+1.5e+3".parse_float()                    // Ok(1500.0)
let inf = "-Infinity".parse_float()                  // Ok(-inf)
let half = ".5".parse_float()                        // Err: digit required before "."
let huge = "1e999".parse_float()                     // Err: value out of Float range
let padded = " 2.5".parse_float()                    // Err: surrounding whitespace, call .trim()

match padded {
    Ok(v) => io.println("{v}")
    Err(e) => io.println(e.message)
}

// Common pattern: parse with default
let timeout = config.get("timeout") ?? "30"
let seconds = match timeout.parse_int() {
    Ok(n) => n
    Err(_) => 30
}
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

`StringBuilder` is a mutable buffer with amortized O(1) append. It is a compiler-known built-in type: like `Str`/`List`/`Map`/`Set`, both the type name (including `StringBuilder.new()` / `StringBuilder.with_capacity(n)`) and its methods are in the prelude and require no import. Methods are on the compiler-known `StringBuildOps` trait:

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
| `with_capacity` | `fn(n: Int) -> StringBuilder` | Empty buffer with `capacity() >= n` (§3.2.2 *Capacity*) |
| `write` | `fn[T: Display](self, x: T)` | Append `x` rendered by `Display`; same as `x.fmt(sb)`. Requires `let mut` |
| `write_char` | `fn(self, c: Char)` | Append single character. Not generic; does not go through `Display` |
| `to_str` | `fn(self) -> Str` | Produce immutable `Str` (copies buffer) |
| `len` | `fn(self) -> Int` | Current content length in codepoints |
| `capacity` | `fn(self) -> Int` | Current buffer capacity (§3.2.2 *Capacity*) |
| `clear` | `fn(self)` | Reset to empty, retains capacity for reuse |

**`to_str()` always copies.** The returned `Str` is an independent immutable value. Subsequent `write()` or `clear()` calls on the builder do not affect previously returned strings. This is the only safe semantics given immutable `Str`.

**When to use which:**
- **Interpolation** — inline composition, the 80% case
- **`concat`/`join`** — combining known pieces or a list of strings
- **`StringBuilder`** — loops building strings incrementally, codegen, or any case where `concat` in a loop would be O(N²)

(Panel vote: 3-1-1 for Option D. See [StringBuilder rationale](../decisions/string-builder.md).)

#### §3.2.2 Collection Methods

`List[T]`, `Map[K, V]`, and `Set[T]` are built-in collection types with method surfaces organized across four traits: `Sized` (shared, §3.2.1), `Contains[T]` (shared), and per-type operation traits (`ListOps[T]`, `MapOps[K, V]`, `SetOps[T]`). The lazy adapters on `Iterator` (`.map()`, `.filter()`, `.collect()`, etc.) are default methods there (§3c.1). `ListOps` and `MapOps` have their own eager adapters, listed below.

##### Construction and Mutability

Each type has one form for an empty value (Principle 2). A type that has an empty literal uses it, as `""` is the empty `Str`. Every other type uses `Type.new()`.

| Type | Empty form |
|------|------------|
| `List[T]` | `[]` |
| `Map[K, V]` | `Map.new()` |
| `Set[T]` | `Set.new()` |
| `Bytes` | `Bytes.new()` |
| `StringBuilder` | `StringBuilder.new()` |

The type arguments of an empty value come from the annotation, from the expected type, or from a later use (§3.4 *Under-Determined Types*). Where none of these gives them, write them in a bracket list after the callee, as for any generic function (§3.4 *Explicit Type Application*): `Map.new[Str, Int]()`. No rule is specific to constructors. The standard library declares these constructors with the type's own parameters as their binders, in the type's order: `Map.new[K, V]()`, `Set.new[T]()` and `List.with_capacity[T](n)`. A list of the wrong count is `error[TypeArgArity]` (E0303) on `new`, so `Map.new[Str]()` is an error. A user type's `fn Registry.new[T]()` is an ordinary function (§2.12.3), and the language does not check the order of its binders.

`Map()`, `Map[K, V]()`, `Set()`, `Set[T]()`, `Bytes()`, `List.new()` and `List.new[T]()` are not forms of an empty value (§3.2 *Removed empty forms*). `List.with_capacity(n)` also makes an empty list (see *Capacity* below).

A **mutating method** is a method that declares `mut self` (§3.6 *Mutable Parameters*): `push`, `pop`, `insert`, `remove`, `set` and `clear` on collections, every `write` method on `StringBuilder`, and every writer on `Bytes` (§3.2.3 *Bytes*). A mutation needs a mutable **root**: the first name of the receiver path or of the place must be a `let mut` binding, a `mut` pattern binder (§3.5 *Mutable Binders*) or a `mut` parameter. A mutation is a call to a mutating method, or an assignment `=` or `op=` (§2.22 *Assignment places*). `p.xs.push(x)` needs `p` to be mutable. An immutable root can only call non-mutating methods (`get`, `contains`, `len`, `keys`, `values`, etc.). A violation is `error[E0610] MutationRequiresMut`. A `mut` parameter is a mutable root only for a call. An assignment to a parameter, or to a field of one, is `error[E0612] ParamAssign` with or without `mut` (§3.6 *Mutable Parameters*), and the compiler reports it in place of E0610 (§2.22 *Writes that are not to a place*).

The fix for E0610 depends on how the root is declared:

- **A local `let` with a plain name:** a machine-applicable fix inserts `mut` (`let mut names`). When several mutations have the same root, they get the same edit, and `blink fix` applies it once (§8.6).
- **A local pattern binder** (a name in a destructuring `let`, a `for` pattern or a `match` arm): a machine-applicable fix inserts `mut` before the binder where it is declared (§3.5 *Mutable Binders*). The help shows the user's own pattern after the edit, for example `for (k, mut v) in pairs` or `Point { x: mut px, .. }`. In an OR-pattern, the fix edits every alternative.
- **A binder in a parameter pattern:** it is a parameter (§3.6 *Mutable Parameters*). An assignment to it is E0612, not E0610.
- **The name after `as` in `with expr as name { }`:** help only. That name is never `mut` (§2.18). The help says to bind a new `let mut` name inside the block.
- **A module-level `let`:** help only. The help says why in one clause: `mut` adds `State` to the row of each function that reads or writes the binding (§4.16), which can cause errors far from the edit.
- **A `pub let` from another module:** help only. The help says that `pub let mut` is not allowed (E1013, §2.12.1).

```blink
// Empty collections
let mut list = []
let mut map = Map.new()
let mut set = Set.new()
let mut typed = Map.new[Str, Int]()             // type arguments written at the call

// Literal syntax (List only)
let names = ["Alice", "Bob", "Carol"]          // List[Str], immutable
let mut scores = [100, 95, 87]                 // List[Int], mutable

// Mutation requires let mut
list.push("hello")                              // OK — list is mut
names.push("Dave")                              // COMPILE ERROR — names is not mut

// The root of a field path decides (type Form { tags: List[Str] })
let mut form = Form { tags: [] }
form.tags.push("new")                           // OK — root `form` is mut
```

**Why `Type.new()` + `let mut`.** Mutability is a property of the *binding*, not the *type*. `List[T]` is one type regardless of whether the binding is mutable — no `MutList`/`ImmutableList` split, no doubled API surface, no coercion rules at function boundaries. `mut` marks every place where a mutation starts: each mutating call and each assignment names a `let mut` binding, a `mut` pattern binder or a `mut` parameter. It does not mark every value that changes. Collections are shared cells (§3.6 *Shared cells*), so an immutable name can observe a change made through a `mut` alias:

```blink
let a = [1, 2]
let mut b = a          // warning[MutAliasOfImmutable] — `b` shares `a`'s list
b.push(3)              // `a` now holds 3 as well
```

(Vote: 5-0. Rationale text revised by the parameter-mutation panel, 6-0 — see [Parameter Mutation rationale](../decisions/parameter-mutation.md).)

##### Capacity

`List.with_capacity(n)` makes an empty list that can hold `n` elements before it grows. Use it only when you know the final size before the first `push`. The list is empty: `len()` is 0 and no element is set. A `push` past `n` grows the list as usual. Apart from `capacity()`, `n` changes no result.

```blink
fn squares(n: Int) -> List[Int] {
    let mut out = List.with_capacity(n)
    for i in 0..n {
        out.push(i * i)
    }
    out
}
```

`capacity()` returns how many elements the list can hold before it grows. The language promises only these three rules:

- `xs.capacity() >= xs.len()` at all times.
- `capacity() >= n` right after `List.with_capacity(n)`.
- `clear()` does not lower `capacity()`.

The growth factor and all exact values are unspecified, and a release can change them. Use `capacity()` in tests and diagnostics. Do not branch on it.

Every `with_capacity` constructor (`List`, `StringBuilder`) follows the same rules:

- `n <= 0` gives the same result as `new()`. It does not panic.
- `len()` is 0 after construction.
- When a large `n` cannot be allocated, the program takes the same out-of-memory path as any other allocation.

`Map` and `Set` have no `with_capacity` and no `capacity()`.

(Panel vote: 6-0 on `with_capacity`; 6-0 on `capacity()` in round 2 after 3-3 in round 1; 4-2 on `n <= 0`. See [List Capacity rationale](../decisions/list-capacity.md).)

##### The `Contains` Trait

`Contains` provides membership testing across all collection types. It is the one membership name on lists (linear scan), maps (key lookup), and sets (hash lookup).

```blink
trait Contains[T] {
    fn contains(self, value: T) -> Bool
}
```

| Type | `contains` semantics |
|------|---------------------|
| `Set[T]` | Hash-based membership test |
| `List[T]` | Linear scan for element equality; needs `T: Eq` |
| `Map[K, V]` | Key presence check |

**Why a shared trait.** Containment is a universal set-theoretic predicate — "is X in this collection?" Every collection answers it, and generic code benefits: `fn has_item[C: Contains[T], T](c: C, item: T) -> Bool { c.contains(item) }`. The alternative — putting `contains` in each per-type trait — prevents writing functions generic over "any collection that can test membership." (Vote: 5-0.)

`Set`, `Map`, and `List` all implement `Contains`. `Map.contains(k)` tests whether `k` is a key; it does not look at values. Each impl states what `contains` means for its type. The trait states no general rule that ties `contains` to iteration: a `Map` iterates `(K, V)` pairs, but its `contains` takes a key. `List[T].contains` needs `T: Eq` and compares elements with `==` (§3.6 *Container Equality*) in a linear scan, so it applies to lists of `Eq` structs, enums and nested containers as well as primitives. An element type that does not implement `Eq` is a compile error (`UnresolvedMethod`).

**Note on `Str`.** `Str` exposes substring search as `"hello".contains("ell")` — semantically "contains substring," not "contains element." This routes through `StrOps` (§3.2.1); `Str` is not a meaningful `Contains[Char]` element-membership type. For character search use `someStr.contains("{c}")`.

##### The `ListOps` Trait

```blink
trait ListOps[T] {
    // Access
    fn get(self, index: Int) -> Option[T]
    fn last(self) -> Option[T]
    fn index_of(self, value: T) -> Option[Int]

    // Capacity (§3.2.2 Capacity)
    fn capacity(self) -> Int

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

    // Eager adapters (§3c.1: collection method in, collection out)
    fn map[U](self, f: fn(T) -> U ! _) -> List[U] ! _
    fn filter(self, pred: fn(T) -> Bool ! _) -> List[T] ! _
    fn flat_map[U](self, f: fn(T) -> List[U] ! _) -> List[U] ! _
    fn fold[U](self, init: U, f: fn(U, T) -> U ! _) -> U ! _
    fn any(self, pred: fn(T) -> Bool ! _) -> Bool ! _
    fn all(self, pred: fn(T) -> Bool ! _) -> Bool ! _
    fn find(self, pred: fn(T) -> Bool ! _) -> Option[T] ! _
    fn enumerate(self) -> List[(Int, T)]
    fn zip[U](self, other: List[U]) -> List[(T, U)]
    fn skip(self, n: Int) -> List[T]
}
```

The full `List[T]` method surface (25 methods from `ListOps` + 2 from `Sized` + 1 from `Contains`, plus `join` from `Joinable`):

| Method | Signature | Mutates | Notes |
|--------|-----------|---------|-------|
| `len` | `fn(self) -> Int` | no | Via `Sized` |
| `is_empty` | `fn(self) -> Bool` | no | Via `Sized` |
| `contains` | `fn(self, T) -> Bool` | no | Via `Contains`, linear scan by `==`; needs `T: Eq` (see §3.2.2 *The `Contains` Trait*) |
| `get` | `fn(self, Int) -> Option[T]` | no | Safe indexed access |
| `last` | `fn(self) -> Option[T]` | no | Last element |
| `index_of` | `fn(self, T) -> Option[Int]` | no | First occurrence |
| `capacity` | `fn(self) -> Int` | no | Elements the list holds before it grows (§3.2.2 *Capacity*) |
| `push` | `fn(self, T)` | yes | Append to end |
| `pop` | `fn(self) -> Option[T]` | yes | Remove from end |
| `set` | `fn(self, Int, T)` | yes | Replace at index; panics when the index is out of bounds |
| `insert` | `fn(self, Int, T)` | yes | Insert at index, shift right |
| `remove` | `fn(self, Int) -> T` | yes | Remove at index, shift left |
| `clear` | `fn(self)` | yes | Reset to empty, retains capacity |
| `append` | `fn(self, List[T]) -> List[T]` | no | Concatenate, returns new list |
| `slice` | `fn(self, Int, Int) -> List[T]` | no | Sub-list `[start, end)`, returns new list; clamps (§3.2.1 *Out-of-range indices*) |
| `join` | `fn(self, Str) -> Str` | no | Join with a separator — `List[Str]` only, via `Joinable` (§3.2.1) |
| `reverse` | `fn(self) -> List[T]` | no | Reversed copy |
| `sort` | `fn(self) -> List[T]` | no | Stable sorted copy (requires `T: Ord`) |
| `sort_by` | `fn(self, fn(T, T) -> Ordering ! _) -> List[T] ! _` | no | Stable sorted copy by a comparator (no bound on `T`) |
| `map` | `fn(self, fn(T) -> U ! _) -> List[U] ! _` | no | New list of `f(x)` for each element, in order |
| `filter` | `fn(self, fn(T) -> Bool ! _) -> List[T] ! _` | no | New list of the elements for which `pred` is `true`, in order |
| `flat_map` | `fn(self, fn(T) -> List[U] ! _) -> List[U] ! _` | no | The lists `f(x)` joined end to end, in order |
| `fold` | `fn(self, U, fn(U, T) -> U ! _) -> U ! _` | no | `f(acc, x)` from the first element to the last, starting with `init` |
| `any` | `fn(self, fn(T) -> Bool ! _) -> Bool ! _` | no | `true` if `pred` is `true` for one element; stops at the first; `false` on an empty list |
| `all` | `fn(self, fn(T) -> Bool ! _) -> Bool ! _` | no | `true` if `pred` is `true` for every element; stops at the first `false`; `true` on an empty list |
| `find` | `fn(self, fn(T) -> Bool ! _) -> Option[T] ! _` | no | First element for which `pred` is `true`; stops there |
| `enumerate` | `fn(self) -> List[(Int, T)]` | no | Each element with its index, from 0 |
| `zip` | `fn(self, List[U]) -> List[(T, U)]` | no | Pairs by position; the length is that of the shorter list |
| `skip` | `fn(self, Int) -> List[T]` | no | All but the first `n` elements; `n <= 0` gives a copy, `n >= len()` gives `[]` |

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

**Concatenation.** Each concatenation has one form:

- Two lists: `a.append(b)`.
- A list literal with extra elements, or three or more sources: spread, `[..a, x, ..b]` (§2.16 *List Literal Spread*).

Both forms make a new list in O(`a.len() + b.len()`) time, and neither operand changes. There is no `+` on lists, no `List.chain` and no `list_concat` (§3.2 *Removed function forms*). For a lazy sequence that does not copy, use `Iterator.chain` (§3c.1).

```blink
let all = evens.append(odds)              // two lists
let framed = [header, ..rows, footer]     // literal with extra elements
let merged = [..a, ..b, ..c]              // three sources
```

A list literal of exactly two spreads and nothing else gets the warning `BareSpreadConcat` (W0709), unless one of the two sources is itself a list literal. `blink fix` rewrites the literal to `a.append(b)`. It only suggests the edit when a comment sits inside the literal. A first source that is not a primary or postfix expression goes in parentheses in the edit. ERROR_CATALOG.md has the full rule.

```blink
let bad = [..a, ..b]                      // W0709: write a.append(b)
let kept = [..a, ..[2, 3]]                // OK: a source is a list literal
let also_kept = [..[], ..a]               // OK: a source is a list literal
let framed = [..a, 0, ..b]                // OK: a plain element
let from_option = [..x ?? y, ..z]         // W0709: the edit is (x ?? y).append(z)
```

```
warning[W0709]: two lists join with `append`, not a spread
 --> m.bl:3:13
  |
3 |     let z = [..x, ..y]
  |             ^^^^^^^^^^ two spreads and no other element
  |
  = help: write `x.append(y)`
```

(Panel vote: 5-1, Minimalism dissenting for spread only; 6-0 on the cost text. See [Duplicate APIs rationale](../decisions/duplicate-apis.md).)

**Sorting.** `sort` and `sort_by` return a sorted copy. The receiver keeps its order. Both sorts are **stable**: elements that compare `Equal` keep their input order. There is no unstable sort. `sort` needs `T: Ord`. `sort_by` takes a comparator that returns `Ordering` (§3.6) and needs no bound on `T`. `xs.sort()` gives the same result as `xs.sort_by(fn(a, b) { a.cmp(b) })`. Because `sort` returns a copy, `xs.sort()` as a bare statement does nothing, and it draws warning W0606 (*Discarded copies* below).

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

**Eager adapters.** `map`, `filter`, `flat_map`, `fold`, `any`, `all`, `find`, `enumerate`, `zip` and `skip` walk the list when they are called and return a new value (§3c.1 *Two Iteration Worlds*). The receiver does not change. The effect row of the call is the row of `f` or `pred` (§4.15.2), and each effect occurs during the call, in element order. `any`, `all` and `find` stop at the first element that decides the result, so `pred` is not called on the elements after it.

```blink
let nums = [3, 1, 4, 1, 5]
let doubled = nums.map(fn(n) { n * 2 })              // [6, 2, 8, 2, 10]
let big = nums.filter(fn(n) { n > 2 })               // [3, 4, 5]
let total = nums.fold(0, fn(acc, n) { acc + n })     // 14
let has_four = nums.any(fn(n) { n == 4 })            // true
let first_even = nums.find(fn(n) { n % 2 == 0 })     // Some(4)
let pairs = ["a", "b"].zip([1, 2, 3])                // [("a", 1), ("b", 2)]
let rest = nums.skip(2)                              // [4, 1, 5]
```

There is no `for_each` method on `List`. A `for` loop is the one way to run code for each element. A call to `xs.for_each(f)` is `UnresolvedMethod`, and its help shows `for x in xs { f(x) }`. For lazy work, cross into the iterator world with `.into_iter()` (§3c.1).

**Why `.get()` returns `Option[T]`.** Out-of-bounds access is a runtime error in most languages. Returning `Option[T]` forces the caller to handle the absence case, and there are no null pointer exceptions. The general rule (§3.2.1 *Out-of-range indices*): a point read never makes up a value. It returns `Option` when its return type can say "absent", and otherwise panics. So `List.get` and `char_at` give `None` out of bounds, and `Str.byte_at`, which returns a bare `U8`, panics. A write through `set` panics on an index that is out of bounds. A range read such as `slice` clamps. Use `??` for default values: `list.get(i) ?? 0`.

**Why the first 13 methods (vote: 3-2).** The ten eager adapters came later (vote 6-0; see [Removed Function Forms rationale](../decisions/removed-function-forms.md)). Systems and PLT argued for 8, excluding `insert`, `remove`, `index_of`, and `last` as O(n) operations better served by iterator methods. Web/Scripting, DevOps, and AI/ML argued these are bread-and-butter operations in every major language (Python `list`, JS `Array`, Java `ArrayList`), and their absence would cause every user to write the same helpers on day one. The expanded surface won on developer experience grounds — performance characteristics should be documented, not hidden.

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
    fn clear(self)

    // Eager adapters (§3c.1: collection method in, collection out)
    fn filter(self, pred: fn(K, V) -> Bool ! _) -> Map[K, V] ! _
    fn map_values[U](self, f: fn(K, V) -> U ! _) -> Map[K, U] ! _
    fn fold[U](self, init: U, f: fn(U, K, V) -> U ! _) -> U ! _
    fn merge(self, other: Map[K, V]) -> Map[K, V]
}
```

The full `Map[K, V]` method surface (12 methods from `MapOps` + 2 from `Sized` + 1 from `Contains`):

| Method | Signature | Mutates | Notes |
|--------|-----------|---------|-------|
| `len` | `fn(self) -> Int` | no | Via `Sized` |
| `is_empty` | `fn(self) -> Bool` | no | Via `Sized` |
| `contains` | `fn(self, K) -> Bool` | no | Via `Contains`, key presence (see §3.2.2 *The `Contains` Trait*) |
| `get` | `fn(self, K) -> Option[V]` | no | Lookup by key |
| `get_or_default` | `fn(self, K, V) -> V` | no | Lookup with fallback |
| `keys` | `fn(self) -> List[K]` | no | All keys, in iteration order |
| `values` | `fn(self) -> List[V]` | no | All values, in iteration order |
| `entries` | `fn(self) -> List[(K, V)]` | no | All key-value pairs, in iteration order |
| `insert` | `fn(self, K, V)` | yes | Insert or update |
| `remove` | `fn(self, K) -> Option[V]` | yes | Remove by key |
| `clear` | `fn(self)` | yes | Reset to empty, retains capacity |
| `filter` | `fn(self, fn(K, V) -> Bool ! _) -> Map[K, V] ! _` | no | New map of the entries for which `pred` is `true`, in `self`'s order |
| `map_values` | `fn(self, fn(K, V) -> U ! _) -> Map[K, U] ! _` | no | New map with the same keys, in the same order; each value is `f(k, v)` |
| `fold` | `fn(self, U, fn(U, K, V) -> U ! _) -> U ! _` | no | `f(acc, k, v)` for each entry in iteration order, starting with `init` |
| `merge` | `fn(self, Map[K, V]) -> Map[K, V]` | no | Shallow merge into a new map: on a key in both maps, the argument's value wins. Order: `self`'s keys, then the new keys of the argument (*Hash Contract and Seeding*) |

```blink
let mut config = Map.new()
config.insert("host", "localhost")
config.insert("port", "8080")

let host = config.get("host")              // Some("localhost")
let timeout = config.get_or_default("timeout", "30")  // "30"
config.contains("port")                    // true (key presence)

let ks = config.keys()                     // ["host", "port"] (insertion order)
let vs = config.values()                   // ["localhost", "8080"] (insertion order)
let es = config.entries()                  // [("host", "localhost"), ("port", "8080")]

let removed = config.remove("port")        // Some("8080")
config.clear()                             // config is now empty, capacity retained

let mut ages = Map.new()
ages.insert("ann", 31)
ages.insert("bo", 17)
ages.insert("cy", 45)
let adults = ages.filter(fn(k, v) { v >= 18 })            // {"ann": 31, "cy": 45}
let labels = ages.map_values(fn(k, v) { "{k}:{v}" })      // {"ann": "ann:31", "bo": "bo:17", "cy": "cy:45"}
let sum = ages.fold(0, fn(acc, k, v) { acc + v })         // 93
let mut base = Map.new()
base.insert("host", "localhost")
base.insert("port", "80")
let mut overrides = Map.new()
overrides.insert("port", "8080")
overrides.insert("tls", "on")
let merged = base.merge(overrides)
// host: "localhost", port: "8080", tls: "on" (base's keys first; overrides wins on port)
```

**Map adapters.** `filter`, `map_values`, `fold` and `merge` walk the map when they are called, in iteration order, and return a new value. The receiver does not change. The effect row of the call is the row of `f` or `pred` (§4.15.2), and each effect occurs during the call. `merge` is shallow: a value that is itself a `Map` is replaced, not merged. The merge is not symmetric. In `a.merge(b)`, `b`'s value wins for a key in both maps, and that key keeps its position from `a`. There is no `for_each` method on `Map`: use `for (k, v) in m { }`, as for `List`.

**Why no `contains_key`.** `Contains[K]` on `Map[K, V]` already tests key presence, so a second name for the same test is a choice with no difference (Principle 2). `contains` is the name that generic code uses, and it is the name that Python's `k in d` and JavaScript's `Map.has` lead users to. `m.contains_key(k)` is a removed method (§3.2 *Removed methods*). (Panel vote: 6-0. See [Duplicate APIs rationale](../decisions/duplicate-apis.md).)

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
| `union` | `fn(self, Set[T]) -> Set[T]` | no | Returns new set; `self`'s order, then new elements of the argument (*Hash Contract and Seeding*) |

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

These are the **built-in method-surface traits** — the traits that host the method API of the built-in types. Like every compiler-known trait, they are in the prelude (§10.6): the trait names are in scope without import, and method dispatch on a built-in receiver (`"x".len()`, `sb.write(...)`) resolves without the trait name being imported.

| Trait | Applies to | Methods | In prelude |
|-------|-----------|---------|------------|
| `Sized` | Str, List, Map, Set, Bytes, StringBuilder | `len`, `is_empty` | Yes |
| `Contains[T]` | Set, List, Map | `contains` (element/key membership) | Yes |
| `StrOps` | Str | string methods (`char_at`, `byte_at`, `contains`, `split`, `to_upper`, `trim`, `replace`, …) | Yes |
| `BytesOps` | Bytes | byte methods (`push`, `get`, `slice`, `to_str`, `to_hex`, `read_u32_be`, …) | Yes |
| `ListOps[T]` | List | 25 methods | Yes |
| `MapOps[K, V]` | Map | 12 methods | Yes |
| `SetOps[T]` | Set | 3 methods | Yes |
| `IntoIterator[T]` | List, Map, Set, Str, Range, Channel | `into_iter` | Yes (§3c.1) |
| `Joinable` | List[Str] | `join` | Yes (§3.2.1) |
| `StringBuildOps` | StringBuilder | `write`, `write_char`, `to_str`, `len`, `capacity`, `clear` | Yes |

> **`Contains` membership covers `Set`, `Map`, and `List`.** `Set.contains` is a hash lookup, `Map.contains` is key presence, and `List.contains` is a linear scan that compares elements with `==`, so it needs `T: Eq`. Substring search on `Str` (`"hello".contains("ell")`) is a separate operation hosted by `StrOps` (§3.2.1), not element membership.

All built-in method-surface traits are in the prelude — no import required. This matches the rationale from §10.6: operators like `for` desugar through `IntoIterator`, method calls resolve through traits, and requiring imports for built-in collection methods would add ceremony with no information value.

**These traits are sealed.** Their implementations are compiler-provided for the built-in types listed above; user code may not implement them (`impl StrOps for MyType`) or redefine them (`trait StrOps { … }`). Both are compile errors — the trait names are reserved by the prelude (§10.6), and a user implementation would create a second meaning for a method the compiler dispatches intrinsically. To add string-like or collection-like behavior to your own type, define your own trait with a different name.

Sealing forbids an impl of the sealed trait itself. It does not forbid a user trait that gives a built-in type a method with a name a sealed trait already uses, such as `impl Tidy for Str { fn trim(self) -> Str { … } }`. The sealed trait and the user trait are then two owners of the name, so an unqualified call is E0522 and a qualified call picks one; the impl draws warning W0734 (§3c.4 *Built-in Type Method Dispatch*).

A sealed trait may still be named in a generic bound — e.g. `fn f[T: Sized](x: T) -> Int { x.len() }`. `Sized` spans several built-in types, so a bound on it is genuinely polymorphic. A bound on a single-implementor trait (`StrOps`, `BytesOps`, `StringBuildOps`) is legal but degenerate: it is satisfiable only by the one built-in type that implements it (e.g. `[T: StrOps]` admits only `Str`), so it carries no more abstraction than naming that type directly.

**Discarded copies.** Some collection methods return a new collection and leave the receiver as it was. The warning `W0606 DiscardedCollectionCopy` fires when a statement calls such a method and drops the result. A method draws the warning when all three of these hold:

- It is a row of the `ListOps`, `MapOps` or `SetOps` table above, called on a `List`, `Map` or `Set`.
- Its row says Mutates = no.
- It returns the receiver's own type: `List[T]` on a `List`, `Map[K, V]` on a `Map`, `Set[T]` on a `Set`.

These are `append`, `slice`, `reverse`, `sort`, `sort_by`, `filter` and `skip` on `List`, `filter` and `merge` on `Map`, and `union` on `Set`. A mutating method such as `push`, `pop`, `insert`, `remove` or `clear` never draws W0606: it does its work on the receiver, so a statement that drops its result is correct code.

```blink
let mut xs = [1, 2]
xs.append([3])                 // W0606: xs is still [1, 2]
xs = xs.append([3])            // OK: xs is [1, 2, 3]
let longer = xs.append([4])    // OK
let _ = xs.append([5])         // OK: `let _ =` drops the result on purpose
xs.pop()                       // OK: pop changes xs
```

A statement drops its result when it comes before the last statement of a block, when it is the last statement of a function that returns nothing, when it is the body of a loop, and when it is a branch of an `if` or `match` that itself drops its result. The operand of `return` is not a statement result, so it is never dropped (§3.3 *Divergence and Body Completeness*). The warning covers only the sealed built-in collection methods. It does not cover a user function or a user method, even one with the same name. `@allow(DiscardedCollectionCopy)` on the enclosing function silences it, as does `W0606 = "off"` under `[lints]`.

---

#### §3.2.3 Additional Standard Library Types

Beyond the built-in primitives (§3.2) and collections (§3.2.2), Blink's standard library provides typed value types for domains where raw primitives lose semantic meaning. Except for the types listed in §10.6 *Compiler-Known Type Names* (`Bytes`, `F32`), these types are not compiler-known and not in the prelude — they live in stdlib modules and require explicit import. The compiler's built-in effect handles reference these types for their operation signatures.

##### Instant and Duration (`std.time`, Tier 2)

`time.read()` reads the wall clock and returns `Instant` — an opaque, nanosecond-precision point in time. `time.monotonic()` reads the monotonic clock and returns `Monotonic`. `time.sleep()` accepts `Duration` — a typed time span with named constructors that encode units.

**Two clocks.** The wall clock gives the time of day. Another program or an administrator can set it, so it can jump forward or back. The monotonic clock never goes back and does not follow such changes, but its readings have no relation to the date. Use `time.read()` for a timestamp, and `time.monotonic()` to measure elapsed time. Both need `Time.Read`.

```blink
import std.time.{Instant, Duration}

fn measure_latency() -> Duration ! Time.Read {
    let start = time.monotonic()    // returns Monotonic
    do_work()
    time.monotonic().since(start)   // returns Duration
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

**Instant** is an opaque type (§2.12.2), declared `pub opaque type Instant` in `std.time`. It has nanosecond precision. Code builds an `Instant` only through `time.read()` and its type-scoped functions, such as `Instant.from_epoch_secs` and `Instant.parse` (§2.12.3).

**The std.time range.** An `Instant` lies in the std.time range 1677-09-22T00:00:00Z ..= 2262-04-11T23:47:16.854775807Z. Every Instant constructor checks this range: `Instant.parse` returns `Err` outside it; `Instant.add` and `Instant.from_epoch_secs` panic outside it, as `Int` overflow does. The range starts on a whole day, so every `Instant` has a `Date` (*Date and Weekday* below). Calendar fields use the proleptic Gregorian calendar in UTC, with no leap seconds.

| Method | Signature | Notes |
|--------|-----------|-------|
| `elapsed` | `fn(self) -> Duration ! Time.Read` | Time since this instant |
| `since` | `fn(self, other: Instant) -> Duration` | Duration between two instants |
| `add` | `fn(self, d: Duration) -> Instant` | This instant moved by `d` (`d` may be negative); panics outside the std.time range |
| `date` | `fn(self) -> Date` | The UTC calendar day of this instant; total |
| `hour` | `fn(self) -> Int` | UTC hour, 0..=23 |
| `minute` | `fn(self) -> Int` | UTC minute, 0..=59 |
| `second` | `fn(self) -> Int` | UTC second, 0..=59; the fraction is dropped |
| `to_rfc3339` | `fn(self) -> Str` | RFC 3339 string in UTC, whole seconds only |
| `to_unix_ms` | `fn(self) -> Int` | Milliseconds since epoch |
| `to_unix_secs` | `fn(self) -> Int` | Seconds since epoch |

| Function | Signature | Notes |
|----------|-----------|-------|
| `Instant.from_epoch_secs` | `fn(s: Int) -> Instant` | Panics outside the std.time range |
| `Instant.parse` | `fn(s: Str) -> Result[Instant, ConversionError]` | Closed RFC 3339 grammar below; normalizes the offset to UTC |

The calendar fields round down, as `Display` does: for 500 ms before the epoch, `date()` is 1969-12-31, `hour()` is 23 and `second()` is 59.

**`Instant.parse` grammar.** `Instant.parse` accepts exactly this production, in ABNF (RFC 5234), and the whole text must match it:

```
date-time   = full-date ("T" / " ") full-time
full-date   = year "-" month "-" day        ; 4DIGIT "-" 2DIGIT "-" 2DIGIT
full-time   = hour ":" minute ":" second [fraction] time-offset
hour        = 2DIGIT                        ; 00..23
minute      = 2DIGIT                        ; 00..59
second      = 2DIGIT                        ; 00..59
fraction    = "." 1*9DIGIT
time-offset = "Z" / ("+" / "-") hh ":" mm   ; hh 00..23, mm 00..59
```

The separator is an uppercase `T` or exactly one U+0020 SPACE. The offset is `Z` (uppercase) or a numeric offset, and the result is the same instant in UTC. Seconds are required. The fraction uses `.` and has 1 to 9 digits. Nothing outside this grammar is accepted: no lowercase `t` or `z`, no comma fraction, no missing seconds, no second `60`, no space before the offset, no text before or after. Widening it is a spec change. Text with no offset is an error that says how to fix it (*Errors* below), because a time with no offset does not name one instant.

Instant implements: `Eq`, `Ord`, `Hash`, `Display`, `Clone`, `Debug`. Does NOT implement arithmetic traits (sealed to built-in numerics). Use `.since()` and `.add()` named methods.

Instant's `Display` writes RFC 9557 in UTC with a `Z` offset: `2026-02-14T12:00:00Z`. A zero fraction of a second is left out. Any other fraction is written without trailing zeros: `2026-02-14T12:00:00.5Z`, `2026-02-14T12:00:00.000000001Z`. An instant before the epoch rounds down to the earlier second: 500 ms before the epoch is `1969-12-31T23:59:59.5Z`. `to_rfc3339` does not change: it always drops the fraction.

**Monotonic** is an opaque type, declared `pub opaque type Monotonic` in `std.time`. Code reads the clock through `time.monotonic()`. A `Time` handler builds the reading it returns with the type-scoped function `Monotonic.from_offset`, and any other code can call it too. `Monotonic` has no `Display` and no conversion to or from `Instant`, so a monotonic reading cannot be mixed with a wall-clock time. The clock has no epoch: the origin of the built-in clock is unspecified and can change from one run to the next. Code must not depend on its value.

| Function | Signature | Notes |
|----------|-----------|-------|
| `Monotonic.from_offset` | `fn(d: Duration) -> Monotonic` | The reading `d` after the origin of a clock; pure; panics when `d` is negative |

| Method | Signature | Notes |
|--------|-----------|-------|
| `since` | `fn(self, earlier: Monotonic) -> Duration` | Time from `earlier` to this reading; never negative when `earlier` was read first from the same clock |

`Monotonic.from_offset` panics when `d` is negative, because a monotonic reading is never before its origin. The panic message contains the offset, for example `Monotonic.from_offset: negative offset -5ns; a monotonic reading is never before its origin`.

`since` is the exact signed difference of the two offsets. It is negative when `earlier` is the later reading. It never panics, except on `Int` overflow. Two readings from different clocks, for example one from the built-in clock and one from a handler's `from_offset`, give a `Duration` with no meaning, and no error. `since` is the only way to observe a reading: there is no `to_offset`, no `add`, no comparison and no `Display`.

Where code has no reading yet, it holds a `Monotonic?`. A zero offset is a real reading, not a mark for "not started".

**Why `from_offset` is public.** A `Time` handler can live in any module, and §2.12 has no friend visibility. So a handler outside `std.time` can build a reading only through a `pub` function. Building a value observes no clock, so `Time.Read` still tracks every read of the clock. The type still cannot mix with `Instant`: `from_offset` takes a `Duration`, and no function converts between the two types.

A handler builds each reading from its own state:

```blink
fn stepping(step: Duration) -> Handler[Time] {
    let mut elapsed = Duration.nanos(0)
    handler Time {
        fn read() -> Instant { Instant.from_epoch_secs(0) }
        fn monotonic() -> Monotonic {
            elapsed = elapsed.add(step)
            Monotonic.from_offset(elapsed)
        }
        fn sleep(d: Duration) { }
    }
}
```

A `Time` handler that omits `monotonic` gets W0545, and its help names `Monotonic.from_offset` (§4.7.1).

##### Date and Weekday

**Date** is an opaque type, declared `pub opaque type Date` in `std.time`. It is one day of the proleptic Gregorian calendar, with no time of day and no time zone. Its range is 1677-09-22 ..= 2262-04-11, the whole days of the std.time range. Code builds a `Date` only through `Date.from_ymd`, `Date.parse`, `instant.date()` and `add_days`.

| Function | Signature | Notes |
|----------|-----------|-------|
| `Date.from_ymd` | `fn(y: Int, m: Int, d: Int) -> Result[Date, ConversionError]` | `m` is 1..=12; `d` is 1 to the last day of that month |
| `Date.parse` | `fn(s: Str) -> Result[Date, ConversionError]` | `YYYY-MM-DD` only: 4 digits, `-`, 2 digits, `-`, 2 digits, nothing else |

| Method | Signature | Notes |
|--------|-----------|-------|
| `year` | `fn(self) -> Int` | 1677..=2262 |
| `month` | `fn(self) -> Int` | 1..=12 |
| `day` | `fn(self) -> Int` | 1..=31 |
| `weekday` | `fn(self) -> Weekday` | Day of the week |
| `add_days` | `fn(self, n: Int) -> Date` | `n` may be negative; panics outside the Date range |
| `days_since` | `fn(self, earlier: Date) -> Int` | Days from `earlier` to `self`; negative when `earlier` is later |
| `to_instant` | `fn(self) -> Instant` | 00:00:00Z on this day; total |

**Weekday** is a fieldless enum in `std.time`:

```blink
pub type Weekday { Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday }
```

`Weekday.Monday.to_int()` is 0 and `Weekday.Sunday.to_int()` is 6 (§3.4 *Tag Operations*). The ISO 8601 day number is `to_int() + 1`. `Display` writes the English name: `Monday`.

Date and Weekday implement: `Eq`, `Ord`, `Hash`, `Display`, `Clone`, `Debug`. `Debug` writes the same text as `Display`. `Date`'s `Display` writes `YYYY-MM-DD`: `2026-10-17`. Dates order by time, and weekdays order from Monday to Sunday.

**Errors.** Each parse and constructor failure is `Err(ConversionError)`. Its `message` starts with `invalid date: ` (from `Date.from_ymd` and `Date.parse`) or `invalid timestamp: ` (from `Instant.parse`), then gives exactly one of these texts. The texts are fixed, and tests check them word for word.

- **Syntax errors** give the byte offset, counted from 0, of the first byte that does not match the grammar:
  - `expected X at byte N (found 'c')`, where `X` is one of `digit`, `'-'`, `':'`, `'T' or ' '`, `'Z', '+' or '-'`, and `c` is the character that starts at byte `N`. At the end of the text, `(found end of input)` replaces `(found 'c')`.
  - `unexpected text at byte N (found 'c')`, for text after a complete value.
  - `more than 9 fraction digits at byte N`, where `N` is the offset of the tenth digit.
  - `no UTC offset at byte N; append Z if the time is UTC`, for `Instant.parse` text that ends where the offset starts.
- **Field errors** name the field's range and give no offset:
  - `month M out of range 1..12`
  - `day D out of range 1..L for YYYY-MM`, where `L` is the last day of that month
  - `hour H out of range 0..23`, `minute M out of range 0..59`, `second S out of range 0..59`
  - `offset hour H out of range 0..23`, `offset minute M out of range 0..59`
- **Range errors** name the std.time range and give no offset:
  - `YYYY-MM-DD outside 1677-09-22..2262-04-11`
  - `S outside 1677-09-22T00:00:00Z..2262-04-11T23:47:16.854775807Z`, where `S` is the input text

A check stops at the first error. Syntax comes first, then the fields from left to right, then the range, which `Instant.parse` checks after it applies the offset. In a `Date.from_ymd` message, the year is written as `y.display_zero_padded(4)` and the month and day with two digits. The panics use the same range text: `Date.add_days` panics with `date out of range: result outside 1677-09-22..2262-04-11`, and `Instant.add` and `Instant.from_epoch_secs` panic with `instant out of range: result outside 1677-09-22T00:00:00Z..2262-04-11T23:47:16.854775807Z`.

```blink
Date.parse("2026-1-07")          // Err: "invalid date: expected digit at byte 6 (found '-')"
Date.parse("2026-02-30")         // Err: "invalid date: day 30 out of range 1..28 for 2026-02"
Date.from_ymd(1677, 9, 21)       // Err: "invalid date: 1677-09-21 outside 1677-09-22..2262-04-11"
Instant.parse("2026-02-14t12:00:00Z")
// Err: "invalid timestamp: expected 'T' or ' ' at byte 10 (found 't')"
Instant.parse("2026-02-14 12:00:00")
// Err: "invalid timestamp: no UTC offset at byte 19; append Z if the time is UTC"
```

**Laws.** For every `d: Date`, every `i: Instant` and every `n: Int` where `d.add_days(n)` is in range:

- `Date.parse("{d}") == Ok(d)` and `Instant.parse("{i}") == Ok(i)`
- `d.to_instant().date() == d`
- `d.to_instant() <= i` exactly when `d <= i.date()`
- `d.add_days(n).days_since(d) == n`

The laws are on values. Text with an offset other than `Z`, a space separator or a fraction with trailing zeros does not round-trip as text: `Instant.parse("2026-02-14 12:00:00+01:00")` gives the instant whose `Display` is `2026-02-14T11:00:00Z`.

```blink
import std.time.{Instant, Date, Weekday}

// Each line starts with a 20-byte stamp: "2026-10-17 09:30:00Z GET /"
fn count_by_date(lines: List[Str]) -> Result[Map[Date, Int], ConversionError] {
    let mut counts: Map[Date, Int] = Map.new()
    for line in lines {
        let d = Instant.parse(line.substring(0, 20))?.date()
        counts.insert(d, (counts.get(d) ?? 0) + 1)
    }
    Ok(counts)
}

fn report(launch: Date) ! Time.Read, IO.Print {
    let today = time.read().date()
    io.println("{today} is a {today.weekday()}, {today.days_since(launch)} days after launch")
    // 2026-10-17 is a Saturday, 245 days after launch
}
```

Cut the stamp with `substring`, not `split(" ")`: a space separator splits the stamp in two.

**Out of v1.** Each item below needs its own panel decision.

- Time zones and zone names. `Instant` is UTC; an offset in parsed text is applied and then dropped.
- `add_months` and `add_years`. Month ends have no single right answer (January 31 plus one month).
- Format strings. Interpolate the accessors: `"{d.year()}/{d.month()}"`.
- `today()`. Write `time.read().date()`, which shows the `Time.Read` effect at the call.
- `day_of_year`.
- Leap seconds. A second of `60` is a field error.
- `and_time` or `at` to join a `Date` and a time of day. Write `d.to_instant().add(...)`.

**Duration** is a typed time span. Named constructors enforce units at construction — no ambiguity between seconds and milliseconds.

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

**Why stdlib Tier 2, not prelude.** Instant and Duration require no special syntax, no special desugaring, and no special inference rules. They are nominal types with named methods. The effect system's `Time.Read` and `Time.Sleep` operations reference these types, creating a coupling between compiler effects and stdlib, so the spec fixes these types as part of the effect specification. Not every program uses time operations. (Panel vote: 5-0.)

**Why Date and no DateTime.** An `Instant` is already a point in UTC, so a UTC `DateTime` would hold the same value under a second name, and each signature would have to choose one. `Instant` gets the time-of-day accessors, and `Date` is the one new value: a calendar day with no time. A zone-aware type needs time-zone data and its own panel; v1 has no zone support and reserves no name for it. (Panel vote: 6-0.)

**Why the std.time range starts at 1677-09-22.** An `Int64` count of nanoseconds reaches back to 1677-09-21T00:12:43.145224192Z, part way through a day. If the range started there, `instant.date()` could give 1677-09-21, and `Date.to_instant()` on that date would have no midnight to return. Starting the range at the next whole day keeps both conversions total. The cost is one range check in `Instant.add` and `Instant.from_epoch_secs`, which panic on overflow anyway. (Panel vote: 5-1; Web/Scripting dissented, to keep the full `Int64` domain for `Instant` and reject only in the parsers.)

**Why Monday is 0.** `Weekday` is a fieldless enum, and §3.4 gives the first variant the tag 0. Monday is first, as in ISO 8601. A second numbering method would give two numbers for one day; the ISO number is `to_int() + 1`. (Panel vote: 6-0.)

##### Bytes (compiler-known, §10.6)

`Bytes` is a contiguous byte buffer — the binary counterpart to `Str`. Where `Str` guarantees UTF-8 validity, `Bytes` carries no encoding invariant.

```blink
import std.digest.{Sha256}

fn first_four(data: Bytes) -> Bytes {
    data.slice(0, 4)            // a copy
}

fn compute_hash(data: Bytes) -> Sha256 {
    Sha256.of(data)             // pure; see Sha256 below
}

fn encode(s: Str) -> Bytes {
    Bytes.from_str(s)           // UTF-8 bytes
}

fn decode(b: Bytes) -> Result[Str, ConversionError] {
    b.to_str()                  // Err unless valid UTF-8 with no NUL
}
```

`Bytes` is a contiguous buffer. `with_ptr` and `with_mut_ptr` give FFI a `Ptr[U8]` to it. `List[U8]` is a different type and makes no such promise.

| Method | Signature | Notes |
|--------|-----------|-------|
| `len` | `fn(self) -> Int` | Via `Sized` |
| `is_empty` | `fn(self) -> Bool` | Via `Sized` |
| `get` | `fn(self, Int) -> Option[U8]` | Byte at index |
| `slice` | `fn(self, Int, Int) -> Bytes` | Sub-buffer `[start, end)` (copy); clamps (§3.2.1 *Out-of-range indices*) |
| `concat` | `fn(self, Bytes) -> Bytes` | Concatenation |
| `to_str` | `fn(self) -> Result[Str, ConversionError]` | UTF-8 decode; `Err` on bad UTF-8 or a NUL byte |
| `to_hex` | `fn(self) -> Str` | Hex string: lower case, two digits per byte |
| `to_list` | `fn(self) -> List[U8]` | Convert to list |
| `from_str` | `fn(Str) -> Bytes` | UTF-8 encode |
| `from_list` | `fn(List[U8]) -> Bytes` | From list |
| `new` | `fn() -> Bytes` | Empty buffer, `len == 0` |
| `zeroed` | `fn(Int) -> Bytes` | Pre-sized buffer with `len == n`, all zero |
| `read_u16_le` / `read_u16_be` | `fn(self, Int) -> Result[Int, Str]` | Decode 2-byte little/big-endian unsigned at offset |
| `read_u32_le` / `read_u32_be` | `fn(self, Int) -> Result[Int, Str]` | Decode 4-byte little/big-endian unsigned at offset |
| `read_i32_le` / `read_i32_be` | `fn(self, Int) -> Result[Int, Str]` | Decode 4-byte little/big-endian signed at offset |
| `read_i64_le` / `read_i64_be` | `fn(self, Int) -> Result[Int, Str]` | Decode 8-byte little/big-endian signed at offset |
| `set_i16_le` / `set_i16_be` | `fn(mut self, Int, Int) -> Result[(), Str]` | Write 2-byte signed at offset (bounds vs `len`) |
| `set_u16_le` / `set_u16_be` | `fn(mut self, Int, Int) -> Result[(), Str]` | Write 2-byte unsigned at offset (bounds vs `len`) |
| `set_i32_le` / `set_i32_be` | `fn(mut self, Int, Int) -> Result[(), Str]` | Write 4-byte signed at offset (bounds vs `len`) |
| `set_u32_le` / `set_u32_be` | `fn(mut self, Int, Int) -> Result[(), Str]` | Write 4-byte unsigned at offset (bounds vs `len`) |
| `set_i64_le` / `set_i64_be` | `fn(mut self, Int, Int) -> Result[(), Str]` | Write 8-byte signed at offset (bounds vs `len`) |
| `set_u64_le` / `set_u64_be` | `fn(mut self, Int, Int) -> Result[(), Str]` | Write 8-byte unsigned at offset (bounds vs `len`) |
| `set` | `fn(mut self, Int, Int)` | Write the low 8 bits of the value at index; panics when the index is not in `[0, len)` |
| `push` | `fn(mut self, Int)` | Append the low 8 bits of the value as one byte; *grows* |
| `write_u16_le` / `write_u16_be` | `fn(mut self, Int)` | Append 2-byte little/big-endian unsigned; *grows* |
| `write_u32_le` / `write_u32_be` | `fn(mut self, Int)` | Append 4-byte little/big-endian unsigned; *grows* |
| `write_i32_le` / `write_i32_be` | `fn(mut self, Int)` | Append 4-byte little/big-endian signed; *grows* |
| `write_i64_le` / `write_i64_be` | `fn(mut self, Int)` | Append 8-byte little/big-endian signed; *grows* |
| `with_ptr` | `fn[R](self, fn(Ptr[U8]) -> R ! _) -> R ! _` | Read-only closure-scoped FFI pin, legal only inside an FFI region (§9.1.1); C must not write through the pointer; forwards the closure's effect row (see §9.1.3) |
| `with_mut_ptr` | `fn[R](mut self, fn(Ptr[U8]) -> R ! _) -> R ! _` | Closure-scoped FFI pin that C may write through, legal only inside an FFI region (§9.1.1); forwards the closure's effect row (see §9.1.3) |

The `set_*_le/be(off, v)` family is the symmetric counterpart of the existing `read_*_le/be(off)` family: it writes at a given offset, requires `off + width <= len` (returns `Err` otherwise — does not grow), and complements the append-only `write_*_le/be(v)` writers. `set_*` and `write_*` are deliberately distinct verbs: `set` writes at a known offset, `write` appends. (Panel decision: [`ffi-struct-construction`](../decisions/ffi-struct-construction.md), Q-α-bytes-offset-API.)

**`Bytes` is a value.** `Bytes` is not a shared cell (§3.6 *Shared cells*). A write through one name never shows through another name. This holds for every copy: bind, pass, return, `clone()`, a struct field and a template hole. Every writer (`set`, `set_*`, `push`, `write_*` and `with_mut_ptr`) declares `mut self`, so a call to one needs a mutable root (§3.2.2 *Construction and Mutability*). A call on an immutable root is `error[E0610] MutationRequiresMut`.

```blink
fn header(len: Int) -> Result[Bytes, Str] {
    let mut b = Bytes.zeroed(4)
    b.set_u16_be(0, 1)?
    b.set_u16_be(2, len)?
    Ok(b)
}

fn main() ! IO {
    let a = Bytes.zeroed(2)
    let mut b = a
    b.push(5)                           // OK — root `b` is mut
    io.println("{a.len()} {b.len()}")   // 2 3 — `a` is unchanged
    a.push(5)                           // error[E0610] — `a` is not mut
}
```

A method marked *grows* in the table above can change `len` and move the storage of the buffer. §9.1.3.1 forbids a call to such a method inside a pin closure. A new `Bytes` method that can move the storage carries the mark. (Panel vote: 6-0. See [Bytes value semantics rationale](../decisions/bytes-value-semantics.md).)

Bytes implements: `Sized`, `Eq`, `Clone`, `Debug`, `IntoIterator[U8]`.

**Why a separate type from `List[U8]`.** `Bytes` is the type for I/O, FFI, and crypto. `List[U8]` makes no contiguous-memory guarantee, so it cannot give FFI a `Ptr[U8]` view. (Panel vote: 5-0.)

**Why Tier 1, not prelude.** `Bytes` is needed by core effects (`FS.Read`, `Net.Connect`, `Crypto.Hash`) but not every program does binary I/O. Tier 1 means it ships with the compiler and is version-locked. The API surface should remain minimal in Tier 1; richer operations (base64, compression) belong in higher tiers. (Panel vote: 5-0.)

##### Sha256 and Sha256State (`std.digest`)

`Sha256` is the SHA-256 digest of a byte sequence. It is always 32 bytes. `Sha256State` is a hasher that takes the input in parts. Both types are `opaque` (§2.12.2). The output is equal to SHA-256 as FIPS 180-4 defines it, and `to_hex` writes the same text that `sha256sum` prints. A digest is a pure function of its input: no function in this subsection has an effect row.

```blink
import std.digest.{Sha256, Sha256State}

fn digest_of(data: Bytes) -> Sha256 {
    Sha256.of(data)
}

fn digest_in_parts(a: Bytes, b: Bytes) -> Str {
    let mut h = Sha256State.new()
    h.update(a)
    h.update(b)
    h.finish().to_hex()
}

fn main() ! IO.Print {
    let d = Sha256.of(Bytes.from_str("abc"))
    io.println(d.to_hex())
    // ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
    let back = Sha256.from_hex(d.to_hex())
    io.println("{back == Some(d)}")     // true
}
```

The impls of `Digest` and `DigestWriter` are in the package that defines the types, so `to_hex`, `to_bytes`, `update` and `finish` need no trait import (§3.6 *Impl visibility*). `import std.digest` or the selective import above is enough.

| Function | Signature | Notes |
|----------|-----------|-------|
| `Sha256.of` | `fn(Bytes) -> Sha256` | Digest of the bytes |
| `Sha256.from_hex` | `fn(Str) -> Option[Sha256]` | Exactly 64 lower-case hex digits; else `None` |
| `to_hex` | `fn(self) -> Str` | 64 lower-case hex digits (`Digest`) |
| `to_bytes` | `fn(self) -> Bytes` | A new 32-byte buffer (`Digest`) |
| `Sha256State.new` | `fn() -> Sha256State` | A hasher that has read no input |
| `update` | `fn(mut self, Bytes)` | Add bytes to the input (`DigestWriter`) |
| `finish` | `fn(self) -> Sha256` | Digest of all input so far (`DigestWriter`) |

The list of `Digest` methods is closed: it has no `len`, no `algorithm` and no `Display`. `Sha256.of`, `Sha256.from_hex` and `finish` are the only ways to make a `Sha256`; there is no `from_bytes`. Every `Sha256.<fn>` returns a `Sha256`, or an `Option[Sha256]`. `Sha256` implements `Eq`, `Clone` and `Debug`. It does not implement `Display`, `Hash` or `Ord`. `==` on a `Sha256` is not constant-time: use it only where timing does not matter.

**Laws.** For every `d: Sha256`, every `s: Str` that `Sha256.from_hex` accepts and all `a: Bytes` and `b: Bytes`:

- `d.to_bytes().len() == 32`
- `d.to_hex()` is 64 lower-case hex digits
- `Sha256.from_hex(d.to_hex())` gives `Some(d)`
- `Sha256.from_hex(s)` gives `Some(x)` with `x.to_hex() == s`
- `Sha256.from_hex` gives `None` for a `Str` with an upper-case digit
- `Sha256State.new()`, then `update(a)`, then `update(b)`, then `finish()` gives `Sha256.of(a.concat(b))`

`finish` does not consume the hasher and does not reset it. A second call gives the same digest, and a later `update` adds to the same input. The cost of one `update` and the size of the hasher do not depend on the total input length.

`Sha256State` is a value, not a shared cell (§3.6 *Shared cells*). `let h2 = h` makes an independent copy:

```blink
fn copy_demo() ! IO.Print {
    let mut h = Sha256State.new()
    h.update(Bytes.from_str("ab"))
    let h2 = h                          // copy
    h.update(Bytes.from_str("c"))
    let abc = Sha256.of(Bytes.from_str("abc"))
    let ab = Sha256.of(Bytes.from_str("ab"))
    io.println("{h.finish() == abc}")   // true
    io.println("{h2.finish() == ab}")   // true
}
```

`Hash` is for container keys and has a seed for each process (§3.6 *Hash Contract and Seeding*). A `Sha256` is not a `Hash` key; it is a stable digest.

**Help texts.** A wrong name or type gets a fix that names the right form. The codes are the existing ones.

| Wrote | Code | Help |
|-------|------|------|
| `Sha256.new()` | E0504 | `Sha256State.new()` makes a hasher; `Sha256.of(data)` hashes in one call |
| `digest.sha256(data)` | E0504 | `Sha256.of(data)` |
| `import std.sha256` | E1200 | `import std.digest` |
| a `Sha256` where `Bytes` is expected | type mismatch | `.to_bytes()` |
| `h.update(x)` with `let h = Sha256State.new()` | E0610 | declare the hasher with `let mut` |

**Why one module with SHA-256 only.** The module is `std.digest`. There is no `std.crypto`, no `std.hash` and no algorithm named by a string, so a wrong algorithm name cannot compile. `Crypto.Hash` (§4.2) stays in the effect list; plain digests do not use it. (Panel vote: 6-0.)

**Why an opaque `Sha256` and not `Bytes`.** A `Bytes` value has any length and any content. A `Sha256` has 32 bytes by construction, so a signature that takes one needs no length check. A `Sha256` cannot be built from arbitrary bytes, so a function that returns one has computed it or parsed it. (Panel vote: 5-1; Minimalism dissented, for `Bytes`.)

**Why `Sha256State` is a value.** A hasher that copies on bind has the same rule as `Bytes`, and a copy can fork a running hash. (Panel vote: 5-1; Minimalism dissented, for no hasher now.)

**Why `Sha256.of`.** One call form for the one-shot case, type-scoped and without a trait or an import beyond the type. (Panel vote: 5-1; Minimalism voted for a free function and asked that the vote count for this form once the opaque type won. The type names `Sha256` and `Sha256State`: 6-0.)

**Why `update` and `finish` are `DigestWriter` methods.** The panel did not vote on trait names. The names `Digest` and `DigestWriter` come from the PLT and DevOps proposals. See [SHA-256 in std rationale](../decisions/sha256-std.md).

##### Numeric Extensions

**F32** (built-in, sized numeric family):

```blink
let x: F32 = F32.from(3.14)
let y: F32 = x.mul(F32.from(2.0))
let back: Float = y.to_float()     // widening via From, infallible
```

`F32` is a 32-bit IEEE 754 float. In `@ffi` signatures it maps to C `float`. It joins the existing sized numeric family (`I8`, `I16`, `I32`, `U8`, `U16`, `U32`, `U64`). Widening `F32 → Float` via `From` (infallible). Narrowing `Float → F32` via `TryFrom` (precision loss). F32 is relevant for GPU interop, ML inference weights, and memory-constrained numerical arrays. (Panel vote: 5-0.)

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

`Decimal` holds up to 38 decimal digits. It covers financial use cases. Arithmetic via named methods (`.add()`, `.sub()`, `.mul()`, `.div()`) — sealed arithmetic traits are not extended. `Decimal` implements `Eq`, `Ord`, `Display`, `Clone`. Construction: `Decimal.from_str(Str)`, `Decimal.from_int(Int)`, `Decimal.zero()`.

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

Arbitrary-precision integer. Arithmetic via named methods. `From[Int]` for widening. Needed for cryptography, combinatorics, and scientific computing. Not the default `Int`: `Int` is 64-bit. (Panel vote: 5-0.)

**Why sealed arithmetic is not extended.** The 4-1 sealed decision applies uniformly. `Decimal` and `BigInt` are library types with library implementations, not hardware-mapped primitives. If `Decimal` gets `+`, users rightfully ask why their `Money` newtype cannot. Named methods `.add()`, `.mul()` are usable and maintain the bright-line boundary. (Panel vote: 5-0.)

##### UUID (`std.uuid`, Tier 2)

```blink
import std.uuid.UUID

fn create_user(name: Str) -> User ! DB.Write, Rand {
    let id = UUID.random()      // requires ! Rand
    db.write(t"INSERT INTO users (id, name) VALUES ({id}, {name})")
    User { id: id, name: name }
}

fn lookup(raw_id: Str) -> Result[User, AppError] ! DB.Read {
    let id = UUID.parse(raw_id)?    // validates format
    db.read(t"SELECT * FROM users WHERE id = {id}")
}
```

`to_bytes` returns 16 bytes.

| Method | Signature | Notes |
|--------|-----------|-------|
| `random` | `fn() -> UUID ! Rand` | Random v4 UUID |
| `parse` | `fn(Str) -> Result[UUID, ConversionError]` | Parse canonical format |
| `to_str` | `fn(self) -> Str` | Canonical "8-4-4-4-12" |
| `to_bytes` | `fn(self) -> Bytes` | 16-byte binary |
| `is_nil` | `fn(self) -> Bool` | All zeros check |

UUID implements: `Eq`, `Ord`, `Hash`, `Display`, `Clone`, `Debug`, `Serialize`, `Deserialize`.

**Why a nominal type, not Str.** UUID is 128 bits, not 36 characters. A `Str` has no binary form. A distinct type prevents confusion: `fn get_user(id: UUID)` is self-documenting; `fn get_user(id: Str)` is ambiguous. `UUID.parse()` validates once and carries the proof in the type. (Panel vote: 5-0.)

**Why `UUID.random()` requires `! Rand`.** UUID v4 generation needs entropy. This integrates naturally with the effect system — in tests, `with mock_rand(42).as_handler() { UUID.random() }` gives deterministic UUIDs. Parsing is pure: `UUID.parse(str)` returns `Result[UUID, ConversionError]` with no effect. (Panel vote: 5-0.)

##### Type Classification Summary

| Type | Location | Tier | Prelude | Rationale |
|------|----------|------|---------|-----------|
| `Instant` | `std.time` | 2 | No | Effect return type, opaque, nanosecond precision |
| `Duration` | `std.time` | 2 | No | Effect parameter type, named constructors eliminate unit confusion |
| `Date`, `Weekday` | `std.time` | 2 | No | Calendar day with no time or zone; day of the week as a fieldless enum |
| `Bytes` | `std.bytes` | 1 | No | Contiguous binary buffer for I/O, FFI, crypto |
| `F32` | built-in | — | Yes | Sized numeric alongside I8–U64; `@ffi` maps it to C `float` |
| `Decimal` | `std.decimal` | 2 | No | Exact decimal (38 digits) for financial arithmetic |
| `BigInt` | `std.math` | 2 | No | Arbitrary-precision integer for crypto/scientific |
| `UUID` | `std.uuid` | 2 | No | 128-bit identity type, Rand effect integration |

##### Sized Integer Types

Blink provides a family of fixed-width integer types alongside the default `Int`. These are first-class nominal types -- not refinements of `Int`, not aliases, not newtypes. A `U8` has a different value range than an `Int`: 8 bits instead of 64 bits. Different widths have different overflow boundaries and different bitwise semantics.

**Type table:**

| Type | Width | Range | C Type (`@ffi` mapping) | Signed |
|------|-------|-------|--------|--------|
| `I8` | 8-bit | -128 to 127 | `int8_t` | Yes |
| `I16` | 16-bit | -32,768 to 32,767 | `int16_t` | Yes |
| `I32` | 32-bit | -2,147,483,648 to 2,147,483,647 | `int32_t` | Yes |
| `Int` | 64-bit | -2^63 to 2^63-1 | `int64_t` | Yes |
| `U8` | 8-bit | 0 to 255 | `uint8_t` | No |
| `U16` | 16-bit | 0 to 65,535 | `uint16_t` | No |
| `U32` | 32-bit | 0 to 4,294,967,295 | `uint32_t` | No |
| `U64` | 64-bit | 0 to 2^64-1 | `uint64_t` | No |

In `@ffi` signatures, each sized type maps to the C type in the table. (Panel vote: 5-0.)

**Why not just `Int` everywhere.** `Int` (64-bit) is the default and covers most use cases. Sized types exist for two reasons: (1) C FFI -- matching the exact width the foreign function expects; (2) domain semantics -- a byte is 0-255, not -2^63 to 2^63-1. Use `Int` unless you have a specific reason not to. (Panel vote: 3-1-1, Web dissented wanting refinement types, AI/ML dissented wanting FFI-only.)

**Overflow behavior:**

Arithmetic overflow is checked by default. An operation that exceeds the type's range panics at runtime with a descriptive message. In a const context (§2.21), an overflow is `ConstEvalPanic` (E0546), because the compiler evaluates the expression. Anywhere else, the program panics at run time; when the operands are only literals and the result always overflows, the compiler also gives the warning `LiteralArithmeticOverflow` (W0708, §3.6, *Literal arithmetic overflow*). A zero divisor is not overflow: in a const context it is a compile error (§2.21, *Const Evaluation Must Succeed*), and elsewhere it panics at run time (§3.6, *Integer Division*). The remainder `%` never exceeds the range, so for a signed type `MIN % -1` is 0 and does not panic (§3.6, *Integer Division*).

```blink
let x: U8 = 255
let y = x + 1               // RUNTIME PANIC: U8 overflow in addition (255 + 1)

let bad: I8 = 127 + 1       // RUNTIME PANIC: I8 overflow in addition (127 + 1 = 128, max 127); warning[LiteralArithmeticOverflow]
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

The decision to use operators, not named methods, had a panel vote of 4-1. AI/ML dissented and wanted named methods.

**Precedence:** Bitwise operators and shifts bind *tighter* than comparison operators, so `flags & 0x0F == 0` means `(flags & 0x0F) == 0`. A shift and each bitwise operator form a separate group. Mixing two groups, or a group with arithmetic, needs parentheses (§2.19 *Integer Operator Groups*):

```blink
let low_clear = flags & 0x0F == 0    // OK: (flags & 0x0F) == 0; fmt prints the parentheses
let word = (hi << 8) | lo            // OK
let bad = hi << 8 | lo               // error[MixedOperatorPrecedence] (E1127)
```

**`Bool` operands.** `&`, `|` and `^` take integer operands only. `(a == 0) & (b == 0)` is a type error, and its `help:` line names `&&` (or `||` for `|`).

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
let bad: U8 = 300        // error[IntLiteralOutOfRange]: 300 does not fit in U8 (0 to 255)
let x = 42               // type is Int (default)

fn process(val: U8) { }
process(200)              // OK: literal 200 fits in U8
process(300)              // error[IntLiteralOutOfRange]: 300 does not fit in U8 (0 to 255)
```

**Integer literal range.** An integer literal stands for the exact integer that its digits spell, in every base that the literal grammar allows. A literal in any base is a value, never a bit pattern. The literal gets its type at the literal: the expected type at that point, or `Int` when there is none. When the literal is checked against a type variable that nothing has solved yet, that variable becomes `Int`. The value must be in the range of the literal's type (*Type table* above). If it is not, the compiler gives `error[IntLiteralOutOfRange]` (E0318) at the literal. E0318 is the same for every integer type, and no `@allow` or `[lints]` setting turns it off.

- **No expected type.** The message says that the literal has the default type `Int`. When the value fits in `U64`, a `help:` offers an annotation, such as `let x: U64 = ...`. When the value is above the `U64` maximum (2^64-1), the message says that no integer type holds the value, and there is no `help:`.
- **Negative literals.** One unary `-` directly before an integer literal, with optional parentheses, makes one *negative literal*. Its value is the negated value of the literal. The check reads the expression as written, as W0704 and W0706 do (§3.6):
  ```
  N ::= "-" L | "(" N ")"
  L ::= INT_LIT | "(" L ")"
  ```
  `-128`, `(-128)` and `-(128)` match. `-(-5)`, `-(1 + 2)` and `-x` do not match: each is a call to `Neg` (§3.6). Under a signed type, the range check uses the negative value, so `let b: I8 = -128` is valid, and `-9223372036854775808` is the `Int` minimum. Under an unsigned type, every negative literal is E0318, whatever its value, `-0` included. The error has the note `unsigned types hold no negative values`. `-x` on an unsigned value keeps the `Neg` error.
- **Operator operands.** For `+ - * / % & | ^ == != < <= > >=`, a literal operand (a negative literal included) takes the integer type of the other operand, on either side. When an expected integer type `T` reaches one of `+ - * / % & | ^`, whose type is `T`×`T`→`T`, both operands are checked against `T`. A comparison gives `Bool`, so an expected type does not reach its operands. When both operands are literals and no type reaches them, both are `Int`. The right operand of `<<` and `>>` is `U32`, and the left operand gets the expected type, if there is one. This list is the only statement of operator positions for a literal; other sections refer to it.
- **Patterns.** A literal pattern and a literal bound of a range pattern take the type of the scrutinee and follow the same rule. A negative bound under an unsigned scrutinee is E0318.
- **Const contexts.** A literal out of range in a const context (§2.21) is E0318, not `ConstEvalPanic` (E0546), because nothing is evaluated. E0546 is for evaluation that would panic, such as overflow in an operation.

```blink
fn is_sign_negative_bits(x: Float) -> Bool {
    (x.to_bits() & 9223372036854775808) != 0   // OK: both literals are U64
}

fn main() {
    let mask: U64 = 9223372036854775808     // OK: 2^63 fits in U64
    let top: U64 = 1 << 63                  // OK: 1 is U64, 63 is U32
    let sum: U64 = 1 + 2                    // OK: both literals are U64
    let low = -9223372036854775808          // OK: the Int minimum, one negative literal
    let b: I8 = -(128)                      // OK: the same literal as -128

    let big = 9223372036854775808           // error[IntLiteralOutOfRange]: 9223372036854775808 does not fit in Int, the default type
                                            //   help: let big: U64 = 9223372036854775808
    let huge: U64 = 18446744073709551616    // error[IntLiteralOutOfRange]: no integer type holds 18446744073709551616
    let n: U64 = -1                         // error[IntLiteralOutOfRange]: -1 does not fit in U64
                                            //   note: unsigned types hold no negative values
    let z: U8 = -0                          // error[IntLiteralOutOfRange]: -0 is a negative literal
                                            //   note: unsigned types hold no negative values

    let mut xs = []
    xs.push(9223372036854775808)            // error[IntLiteralOutOfRange]: the element type is not known here, so the literal is Int
                                            //   help: let mut xs: List[U64] = []

    match mask {
        18446744073709551615 => io.println("max")   // OK: the pattern is U64
        _ => io.println("other")
    }
}
```

A literal does not wait for a later line to fix its type, as Rust's `{integer}` does. Its type is known at the literal, so it never leaves a type variable that would need a default (§3.4 *Under-Determined Types*).

The compiler checks the range of each literal at the literal (E0318, *Integer literal range*). It evaluates an expression only in a const context (§2.21), where an overflow is E0546. Other arithmetic is checked at run time by the overflow machinery described above; for arithmetic on literals only, the warning W0708 reports an overflow that always happens (§3.6, *Literal arithmetic overflow*).

**Why no literal suffixes.** Languages like Rust use `42u8`, `100i32`, etc. Blink omits suffixes because (1) function signatures already provide the context -- `fn process(val: U8)` makes `process(200)` unambiguous; (2) suffixes add visual noise to a language designed for readability; (3) the rare case where disambiguation is needed can use a type annotation: `let x: U8 = 42`. (Panel vote: 4-1, Systems expert preferred constructor syntax `U8(42)`.)

**Why not refinement types.** Sized integers are not `Int @where(self >= 0 && self <= 255)`. A refined `Int` is still an `Int`: it has the 64-bit range and overflow of `Int`. `U8` has an 8-bit range and maps to C `uint8_t` in `@ffi` signatures. The overflow and bitwise semantics also differ by width: `U8(255) + U8(1)` wraps to 0 (with `wrapping_add`), while a refined `Int` would just be 256. These are fundamentally different kinds of types serving different purposes. (Panel vote: 5-0.)

#### §3.2.4 Char Methods

`Char` classifies and converts a codepoint through methods on `Char`. There is no `std.char` module and no free-function form (§3.2, *Stdlib API surface: methods only*). Conversions between `Char`, `Int` and `Str` are in §3c.3 *Char Conversions*.

| Method | Signature | True for |
|--------|-----------|----------|
| `is_ascii` | `fn(self) -> Bool` | Codepoints 0 to 127 (`0..=127`) |
| `is_ascii_digit` | `fn(self) -> Bool` | `'0'..='9'` |
| `is_ascii_alpha` | `fn(self) -> Bool` | `'A'..='Z'` and `'a'..='z'` |
| `is_ascii_alphanumeric` | `fn(self) -> Bool` | `is_ascii_digit` or `is_ascii_alpha` |
| `is_ascii_upper` | `fn(self) -> Bool` | `'A'..='Z'` |
| `is_ascii_lower` | `fn(self) -> Bool` | `'a'..='z'` |
| `is_whitespace` | `fn(self) -> Bool` | The 25 codepoints of the Unicode `White_Space` property (below) |
| `to_digit` | `fn(self, Int) -> Option[Int]` | — (returns the digit value in a radix; see below) |

An `is_ascii_*` method is false for every codepoint above 127. The name says so, because a letter outside ASCII is still a letter: `'É'.is_ascii_upper()` is `false`, and `'é'.is_ascii_alpha()` is `false`.

`is_whitespace` is true for exactly these codepoints, and these are the codepoints that `trim`, `trim_start` and `trim_end` strip (§3.2.1 *Trim, Strip, Pad and Repeat*):

| Codepoints | Names |
|------------|-------|
| U+0009–U+000D | tab, line feed, vertical tab, form feed, carriage return |
| U+0020 | space |
| U+0085 | next line |
| U+00A0 | no-break space |
| U+1680 | Ogham space mark |
| U+2000–U+200A | en quad to hair space (11 codepoints) |
| U+2028 | line separator |
| U+2029 | paragraph separator |
| U+202F | narrow no-break space |
| U+205F | medium mathematical space |
| U+3000 | ideographic space |

There is no `is_ascii_whitespace`.

`c.to_digit(radix)` returns the value of `c` as one digit in base `radix`. `'0'..='9'` have the values 0 to 9, and `'a'..='z'` and `'A'..='Z'` have the values 10 to 35. The result is `Some(value)` when that value is less than `radix`, and `None` otherwise, including for every codepoint outside ASCII. A `radix` outside `2..=36` panics.

```blink
'7'.to_digit(10)     // Some(7)
'f'.to_digit(16)     // Some(15)
'F'.to_digit(16)     // Some(15)
'9'.to_digit(8)      // None
'x'.to_digit(10)     // None
'1'.to_digit(37)     // panics: radix 37 is outside 2..=36
```

```blink
fn digit_sum(s: Str) -> Int {
    let mut total = 0
    for c in s {
        total += c.to_digit(10) ?? 0
    }
    total
}
```

(Panel votes: names and the whitespace set 6-0; `is_ascii_upper`/`is_ascii_lower` 5-1 and `is_ascii` 5-1, Minimalism dissented both times; `to_digit` 6-0.)

#### §3.2.5 Float Rounding

`Float` has three rounding methods. Each takes no argument and returns a `Float`, so the result keeps NaN and the infinities. To get an `Int`, call `.truncate()` on the result (§3c.3).

| Method | Signature | Result |
|--------|-----------|--------|
| `round` | `fn(self) -> Float` | The nearest integer value; a tie goes away from zero (IEEE 754 `roundToIntegralTiesToAway`) |
| `floor` | `fn(self) -> Float` | The largest integer value `<= self` (IEEE 754 `roundToIntegralTowardNegative`) |
| `ceil` | `fn(self) -> Float` | The smallest integer value `>= self` (IEEE 754 `roundToIntegralTowardPositive`) |

NaN, `inf`, `-inf`, `0.0` and `-0.0` come back unchanged.

```blink
2.5.round()          // 3.0
(-2.5).round()       // -3.0
2.4.round()          // 2.0
(-2.1).floor()       // -3.0
2.1.ceil()           // 3.0
let n = 7.6.round().truncate()   // 8 (Int)
```

`round` takes no digit count. To show a `Float` with a fixed number of decimal places, use `display_fixed` (§3.6.1 *Fixed-Decimal and Zero-Padded Forms*), which returns a `Str`. There is no `round_even`, `trunc` or `round(digits)`. (Panel vote: 6-0.)

---

### 3.3 Type Inference

Blink uses Hindley-Milner type inference with the following rule: **annotations are required on function signatures, inferred everywhere else.**

```blink
// Function signatures: fully annotated
fn add(a: Int, b: Int) -> Int {
    a + b
}

fn find_user(id: Int) -> Option[User] ! DB {
    db.query_one(t"SELECT * FROM users WHERE id = {id}")
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

**Keyword labels are not part of the type.** Declaration-site keyword parameters (see [2.13](02_syntax.md#213-declaration-site-keyword-arguments)) use the `*` marker to separate positional from keyword params, but labels are call-site enforcement only. The function type ignores labels entirely:

```blink
// This function:
fn transfer(amount: Int, *, from: Account, to: Account) -> Result[Transaction, BankError]

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

**Numeric literals.** Unadorned integer literals default to `Int`. Unadorned float literals default to `Float`. If context demands a specific size (e.g., assigning to a `U8` field), the literal is checked against the target type's range at compile time (§3.2 *Integer literal range*):

```blink
let port: U16 = 8080        // OK: 8080 fits in U16
let bad: U8 = 300           // error[IntLiteralOutOfRange]: 300 does not fit in U8 (0 to 255)
```

#### Divergence and Body Completeness

A block that stands in a **value position** — a function body, an `if`/`match` arm
whose result is used, the tail of a `with`-block, or a block bound by `let` — has a
*tail type*: the type of the value control produces when it reaches the end of the
block. A value-returning `fn(...) -> R` type-checks only when its body's tail type is a
subtype of `R`. This is the ordinary subtyping check; there is no loop-specific rule.

Two facts about the type lattice decide every case:

- **`Never` is a subtype of every type.** `Never` (§3.2) has no values, so a construct
  of type `Never` produces no value and satisfies any expected type.
- **`()` is a subtype only of `()`.** The unit type is ordinary; a block whose tail type
  is `()` satisfies `-> ()` and nothing else.

A construct has type `Never` when it **provably diverges** — control cannot leave it
normally:

- A call whose result type is `Never` — untracked divergence. This covers built-ins such
  as `panic(msg)`, `todo()`, `unreachable()` (§2.20) and `env.exit(code)` (§4.6), and a
  user function declared `-> Never`. The rule reads the callee's declared result type,
  never its name.
- A jump (§2.11 *Jumps* lists where one may stand) or `?`-propagation on the error path,
  in tail position — control leaves the block by another edge.
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
program type-check. The same holds for a call: its type is `Never` only when the callee
declares `-> Never`. A call whose result type is still open is not taken to diverge.

```blink
fn fail(msg: Str) -> Never {
    panic("config: {msg}")
}

// Accepted: `fail` returns Never, so the tail diverges and Never <: Int.
fn port(raw: Str) -> Int {
    if raw == "" { return 8080 }
    fail("bad port")
}
```

**error[MissingReturn] (E0311).** Fires when control can reach the end of a block that
must produce a value of type `R` along a path that yields `()` — a fall-through function
body, a value-position `if` without `else`, an arm that completes where a value was
required. The primary line names the cause ("this function can finish without returning a
value of type `R`"); the tail kind (loop, `if`-without-`else`, …) is carried as
diagnostic data, not as a separate error code, so an editor or agent can offer the right
repair from one stable key. The repair named first is the one that always compiles: add a
trailing `return <value>` (or a tail value expression), or — when "no value" is a real
outcome — change the return type to `Option[R]` (§3.7) and yield `None`. When `R` is
`Never`, no value of type `R` exists, so the help names only a diverging tail: a call to
`panic(...)` or `unreachable()`, or a call to a function declared `-> Never`. It does not
offer `Option[R]`. A diverging tail
(a call that returns `Never` such as `panic(...)` or `todo()`, or a `loop` no `break`
targets) is accepted and needs no repair. This
satisfies the Diagnostic Discipline of §3.1: every rejection names a repair that exists.

**`return` with a value.** `return e` checks `e` against the return type of the nearest
enclosing function or closure. This holds for every return type, `()` included. A
mismatch is `TypeError` (E0300), the same fault as for any other return type. In a
function that returns `()`, these stay legal: `return`, `return ()`, `return e` where
`e` has type `()`, and `return e` where `e` has type `Never`. The tail drop (§3.2.2,
*Discarded copies*) applies to the result of the last statement. The operand of
`return` is not a statement result, so the drop never applies to it.

```blink
fn lg() {
    io.println("hi")
}

fn tail() { 5 }                  // OK: the last statement drops its result
fn early() { return 5 }          // error[TypeError] (E0300): Int does not match return type ()
fn typed() -> () { return "s" }  // error[TypeError] (E0300): Str does not match return type ()

fn forward(b: Bool) {
    if b { return lg() }         // OK: lg() has type ()
    if b { return () }           // OK
    if b { return panic("x") }   // OK: the operand has type Never
    return                       // OK
}
```

The help of this E0300 names two repairs, in this order: add `-> T` to the signature, or
drop the value. Dropping the value keeps a call as its own statement: `return save(x)`
becomes `save(x)` and then `return`. When `()` comes from an omitted `-> R` or from an
expected parameter type, the error also points to that place.

**Closures.** A closure with an expected function type takes its return type from that
type. A closure with no expected type has the one type on which every `return e` and a
tail that can complete agree, and `()` when there is none.

```blink
fn h(cb: fn(Int) -> ()) { cb(1) }

h(fn(i: Int) { return i })                  // error[TypeError] (E0300): the expected type gives ()
h(fn(i: Int) { i })                         // OK: the tail is dropped

let k = fn() { return 5 }                   // fn() -> Int
let m = fn(b: Bool) { if b { return 5 } }   // error[MissingReturn] (E0311)
let q = fn() { return panic("x") }          // fn() -> ()
```

A `return e` whose operand has type `Never` adds no constraint. A tail that can complete
with `()` after a valued `return` is `MissingReturn` (E0311), as for a named function
with `-> R`. Exits that disagree are `TypeError` (E0300).

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

#### Newtypes

A **newtype** is a struct with exactly one field. It is a new type, distinct from the type of its field:

```blink
type Errno { code: Int }

fn open_failed(rc: Int) -> Result[Int, Errno] {
    Err(Errno { code: rc })
}

fn describe(r: Result[Int, Errno]) -> Str {
    match r {
        Ok(n) => "opened {n}"
        Err(Errno { code }) => "failed with errno {code}"
    }
}

fn main() {
    let e = Errno { code: 5 }
    let n: Int = e.code           // read the field
    let bad: Int = e              // error[TypeError]: declared type Int but got Errno
}
```

A newtype follows the rules of every other struct. Build it with a struct literal (`Errno { code: 5 }`), read it with `e.code`, and take it apart with a struct pattern. `@derive`, JSON and generics work as for any struct. The JSON form of `Errno { code: 2 }` is `{"code":2}`.

There is no implicit conversion between a newtype and its field type, in either direction. A newtype has no operators of its field type. To use the inner value, read the field.

Name the field for what it holds. Use `value` when nothing better fits.

A type alias is not a newtype. `type Errno = Int` gives a second name to `Int`: both names are the same type.

Blink has no tuple structs and no `newtype` keyword. A single-variant enum is an ordinary enum, not a newtype. To wrap a foreign type so that you can write an impl for it, see *Orphan Rule* (§3.6). For why `(T)` is not a 1-tuple, see *No 1-Tuples* (§3.8).

A form from another language gets an error that names the Blink form. No help line offers an enum form:

```blink
let a = Errno(5)
// error[UndefinedFunction]: `Errno` has no constructor call
//   help: build a value with a struct literal: `Errno { code: 5 }`

let b = e == 2
// error[TypeError]: expected Errno, got Int
//   help: read the field: `e.code == 2`

let c = e.0
// error[NoSuchField]: `Errno` has no field `0`
//   help: the field is `code`: `e.code`

type Errno(Int)
// error[ParseError]: Blink has no tuple structs
//   help: write `type Errno { code: Int }`
```

When the type has more than one field, the help for the first error writes every field with a placeholder.

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

**Variant names.** A variant name must start with an uppercase letter: a Unicode `Lu` or `Lt` character. Any other first character is `error[LowercaseVariant]` (E0555) at the variant: a lowercase letter (`circle`), `_` (`_x`, `_X`), or a letter that has no case (`東`). A name in a script that has no case starts with an uppercase letter of another script, such as `V東`.

```blink
type Shape {
    circle(Float)      // error[LowercaseVariant]
    Square(Float)
}
```

```
error[LowercaseVariant]: variant name must start with an uppercase letter
  help: rename the variant to `Circle`
```

The rename is machine-applicable only when both of these are true: the first character maps to exactly one `Lu` or `Lt` character, and `K` has no variant and no other `T.` member (§2.12.3) with the new name. The fix renames the declaration and every use. For a `pub` type, it renames the uses in every module of the package. In all other cases the help only says to start the name with an uppercase letter. The compiler keeps the variant under the name as written, so a use of it reports nothing more: one mistake gives one diagnostic.

The first character tells a variant from a binding in a pattern (§3.5 *Bare names: variant or binding*) and from a function in a type path (*Member case*, below). No variant has a lowercase name, so neither needs the declarations of a type to decide what a name means.

**Fields of a paren variant.** A paren variant names every field or none. A variant that declares both an unnamed field and a named field, in either order, is `error[MixedVariantFields]` (E0320) at the variant. A label could not name the unnamed field, so no label rule would be complete for it.

```blink
type Shape {
    Circle(radius: Float, tag: Int)    // ok: every field has a name
    Pair(Int, Int)                     // ok: no field has a name
    Both(Int, b: Int)                  // error[MixedVariantFields]
    Rev(a: Int, Int)                   // error[MixedVariantFields]
}
```

```
error[MixedVariantFields]: variant `Both` declares both named and unnamed fields
  help: name every field or none
```

#### Why One Keyword

Most languages split these: `struct` + `enum` (Rust), `data class` + `sealed class` (Kotlin), `type` + `datatype` (SML). Two keywords means two mental models, two sets of rules, and an AI that has to decide which one to use.

In Blink, `type` is `type`. If it has variants, it's a sum. If it has fields, it's a product. If it has variants where some carry fields, it's a sum of products. The compiler doesn't care about the taxonomy; it cares about the structure.

#### Variant Construction

Enum variants are constructed by naming the variant and supplying its payload. In an expression, a variant carries its enum: write `Enum.Variant`, `Enum.Variant(...)` or `Enum.Variant { ... }`. The four variants of `Option` and `Result` are the only exception: write `Some`, `None`, `Ok` and `Err` bare.

```blink
type QueryError {
    NotFound { msg: Str }
    Timeout { ms: Int }
}

let a = QueryError.NotFound { msg: "id 0" }   // a user variant: qualified
let b = QueryError.Timeout { ms: 30 }
let c = Some(a)                               // a prelude variant: bare
```

**The rule.** In an expression, a bare user variant is an error (*Unqualified variant*, below). The rule covers all three forms: `X`, `X(...)` and `X { ... }`. A *user variant* here is every variant except `Some`, `None`, `Ok` and `Err`: a variant of an enum of the module, of the package, of a dependency, or of the standard library. So write `Ordering.Less` and `JsonValue.Str("a")`, as for an enum that you declare.

Patterns do not change. In a pattern, a bare uppercase name names a variant of the type of the matched value (§3.5 *Pattern Forms*), and the qualified pattern stays legal. So `match c { Red => 1, Green => 2 }` is legal, but `let x = Red` is not.

**The bare list.** The list of bare variants is exactly `Some`, `None`, `Ok` and `Err`. These are the variants of `Option` and `Result`, and no others. Their qualified forms (`Option.Some(1)`, `Option.None`, `Result.Ok(x)`, `Result.Err(e)`) stay legal. The list is closed: no other prelude or standard-library enum joins it, and only a new panel vote can change it. `Ordering` (`Less`, `Equal`, `Greater`) and `JsonValue` are qualified like any other enum.

A bare `Some`, `None`, `Ok` or `Err` in an expression always names the prelude variant. This holds also when a user enum declares a variant of that name: write that variant qualified, as any other user variant. A type named `Some`, `None`, `Ok` or `Err` is a declaration error (E1016, §2.12.1).

**Resolving a bare name.** In an expression, a bare uppercase `Name`, `Name(...)` or `Name { ... }` never selects a user variant:

- `Name { ... }` reads the type namespace. It is a literal of the struct `Name` (§2.14), when the module declares that struct or binds it by an import entry. A hint never changes this. When no struct `Name` is in scope and a candidate enum (below) has a variant `Name`, the site is E0554. Otherwise the name is undefined.
- `Name` and `Name(...)` follow *Values come first* (below).

**Candidates for the help.** When a site is E0554, the compiler finds the variants that the bare name can mean. It uses them only to write the `help:` line. They never give the site a meaning. The *candidate* enums are:

- the enums of the site's module;
- the `pub` enums of the other modules of the site's package;
- the prelude enums;
- each enum of another package that the module binds by an import entry that names the type (`import palette.{Shade}`). A whole-module import (`import palette`) adds none of its enums.

A non-`pub` enum of another module is never a candidate.

A bare name that matches no candidate, but matches a `pub` enum of another package that the module does not import by name, is an undefined-name error at the name: `UndefinedVariable` (E0506) for `Name`, `UndefinedFunction` (E0504) for `Name(...)`. Its `help:` names that enum and gives the import entry and the qualified form as the fix. The binding has the poison type (§6.3.5), so no follow-on error appears.

**Expected type at a site.** A site has the expected type `T` at the positions below, and at no other. The list has a job only where a value needs a type from its context: it types a literal (§3.2), and it infers the type argument `T` of `None`, `Some(e)`, `Ok(e)` or `Err(e)`. It does no name resolution. A user variant is always qualified, and a bare `Some`, `None`, `Ok` or `Err` always names the prelude variant, so an expected type never selects a variant.

1. the value of `let x: T = e`;
2. the value of an assignment to a place of type `T` (`x = e`, `p.f = e`);
3. the tail of a function body, and the operand of `return`, where the function declares the return type `T`;
4. a call or method argument, where the declared parameter type is `T`. A parameter whose type is a type parameter of the callee gives no expected type, unless explicit type arguments fix it: `id[Option[Int]](None)` has the expected type `Option[Int]`, and `id(None)` has none;
5. a field value in a struct or variant brace literal, where the declared field type is `T`;
6. the payload of `Some(e)`, `Ok(e)` or `Err(e)` under an expected `Option[T]` or `Result[T, E]`: `T`, or `E` for `Err`;
7. each element of a list literal under an expected `List[T]`; element `i` of a tuple literal under an expected tuple type;
8. the right operand of `a ?? e`: the inner type of `a`;
9. an operand of `==`, `!=`, `<`, `<=`, `>` or `>=`. If exactly one operand is `None`, `Some(e)`, `Ok(e)` or `Err(e)` (or an `if`, `match` or block whose result values all have one of these forms), the other operand has a type of its own, and that type is the expected type of the first. A literal operand follows §3.2 *Operator operands*.

An expected type at a position reaches each branch value of an `if`, each arm value of a `match`, and the tail of a block. It does not reach a condition, a guard, a scrutinee, or a statement that is not the tail.

A struct has no bare form and no call form, so `Name` and `Name(...)` never find a struct. The brace form reads the type namespace, so a local `let` never changes what `Name { ... }` means.

Resolution is static. A bare name at a site denotes exactly one entity, and the compiler determines it statically.

**Values come first.** At a bare use of `Name` in an expression, or in a call `Name(...)`, the compiler looks in this order, and the first step that finds `Name` decides:

1. a local binding (a `let`, a parameter, a closure parameter or a pattern binder);
2. a module-scope value: a `let`, `let mut`, `const` or `fn` of the module, or an imported value;
3. a prelude variant: `Some`, `None`, `Ok` or `Err`.

If no step finds `Name`, and a candidate enum has a variant `Name`, the site is E0554 (*Unqualified variant*, below). Otherwise the name is undefined: E0506 for `Name`, E0504 for `Name(...)`. The head of a dotted path `Name.x` follows *Dotted heads*, below.

Step 2 never finds one of the four names, because a module-scope value with such a name is E1016 (§2.12.1). This holds for an imported value too: an import entry that binds such a value is E1016 at the import entry. A local can have one of the four names. It hides the prelude variant, and gets W1011 (§10.6 *Shadowing Rules*).

A value never hides a user variant, because a bare name never reaches a user variant. A value `Warm` and the variant `Tone.Warm` can both exist, and each spelling names one of them:

```blink
type Tone { Warm, Cool }

const Warm = 1                    // legal: the variant is always `Tone.Warm`

fn main() {
    let n = Warm                  // the const, 1
    let t = Tone.Warm             // the variant
    let u: Tone = Warm            // error[TypeError]: declared type Tone but got Int
                                  // help: write `Tone.Warm` for the variant
}
```

When a value gives a type error at a site whose expected type is an enum with a variant of that name, the error gets a `help:` line that names the qualified variant, for example `Tone.Warm`.

**Dotted heads.** At `Name.x` and `Name.x(...)`, `Name` can be a value, a name in the type namespace, or one of the four prelude variants. The compiler looks in this order, and the first step that finds `Name` decides:

1. a local binding, or a module-scope value, named `Name` (steps 1 and 2 of *Values come first*). Then `Name.x` is a field access or a method call on that value;
2. a name in the type namespace: a struct, enum, alias, trait or effect. Then `Name.x` is a *type path*: `x` is a member of the `T.` namespace of that type (§2.12.3). A member is a variant, a `fn T.name`, a `const T.X`, or an associated function of a trait;
3. the prelude variant `None`, or a `Some(...)`, `Ok(...)` or `Err(...)` form. Then `Name.x` is a field access or a method call on the variant value: `None.is_none()` and `Some(x).map(f)` read as the variant.

Step 3 covers these four names only. A user variant never heads a dotted path bare: `Red.x` is always the type or the value `Red`. When steps 1 and 2 find no `Name`, and a candidate enum has a variant `Name`, the site is E0554. So `Green.label()` is an error, and `Color.Green.label()` calls the method on the variant.

The compiler picks the reading from scope and namespaces only, never from the members of the type. If `x` is not a member of the type in step 2, the site is an error. The compiler does not read `Name.x` again as a value or as a variant value. So an `impl` that another module adds never changes what an existing site means.

**Member case.** In a type path `K.x`, the first character of `x` decides which members it can name:

- An uppercase first character (Unicode `Lu` or `Lt`) never names a function. `K.X` names a variant of `K` or a type-scoped constant `const K.X` (§2.12.3). When `K` is an enum that has neither, the site is `NoSuchVariant` (E0547).
- Any other first character never names a variant. `K.x` names a type-scoped function `fn K.x`, an associated function that a trait impl gives `K` (§3c.4), or a type-scoped constant. When `K` has none of these, the site is an unknown member of the type path, never E0547. The candidates of its nearest-name suggestion (ERROR_CATALOG *Conventions*) include the variants of `K`, so `K.zed` suggests the variant `K.Zed`.

No function in a `T.` namespace has an uppercase name (§2.12.3 *Function names*), so each case looks in one set of members, with no order between them.

```blink
type Level { Low, High }

fn Level.parse(s: Str) -> Level? { /* ... */ }

fn main() {
    let a = Level.High        // a variant
    let b = Level.parse("hi") // a type-scoped function
    let c = Level.Hihg        // error[NoSuchVariant]
    let d = Level.high        // error: `Level` has no member `high`; the help suggests `Level.High`
}
```

A bare `Name` and `Name(...)` stay under *Values come first*: a type name is never a bare value. A variant with the name of its own enum is E0518 (*Name collisions*, below).

When a site reads a type path and fails (an unknown member or a wrong number of arguments), and a candidate enum has a variant of that name, the error gets a `help:` line that names the qualified variant.

**Unqualified variant.** A bare user variant in an expression is `error[UnqualifiedVariant]` (E0554). The rule covers `X`, `X(...)` and `X { ... }`. It holds in every expression, also at a position with an expected type (*Expected type at a site*, above): an expected type never makes the bare form legal. A type named `X` in scope does not change it either. It does not reach patterns: a pattern finds its variant from the type of the matched value (§3.5). The help writes the qualified form. When one candidate enum has a variant `X`, the help is machine-applicable. When two or more have it, the help lists each qualified form.

```
error[E0554]: variant `Green` needs its enum in an expression
  help: write `Color.Green`
```

```blink
type Color { Red, Green }
type Red { A, B }                 // legal: the type `Red` and the variant `Color.Red` do not collide

fn paint(c: Color) -> Str {
    match c {
        Red => "red"              // a pattern: the variant `Color.Red`, from the type of `c`
        Green => "green"
    }
}

fn main() ! IO {
    let a = Red                   // error[UnqualifiedVariant]: variant `Red` needs its enum in an expression
                                  // help: write `Color.Red`
    let b: Color = Green          // error[UnqualifiedVariant]: an expected type does not make it legal
                                  // help: write `Color.Green`
    let c = Color.Red             // the variant
    let r = Red.A                 // a type path: variant `A` of the type `Red`
    io.println(paint(c))
}
```

The brace form follows the same rule. With no struct `NotFound` in scope, a bare `NotFound { ... }` is E0554, also inside a carrier whose expected type names the enum:

```blink
type QueryError {
    NotFound { msg: Str }
    Timeout { ms: Int }
}

fn lookup(id: Int) -> Result[Str, QueryError] {
    if id == 0 {
        return Err(NotFound { msg: "id 0" })              // error[UnqualifiedVariant]
                                                          // help: write `QueryError.NotFound { ... }`
    }
    if id < 0 {
        return Err(QueryError.NotFound { msg: "id < 0" })  // the variant
    }
    Ok("found")
}
```

**Name collisions** fall into two distinct kinds:

- **A type name equal to an enum variant name** is a **compile error at declaration time** (`error[NameCollision]`, E0518) in two cases: a struct has the name of a variant, or a variant has the name of its own enum. For a struct, the reach is the package, not the module: a struct in one module and a variant of that name in another module of the package collide. The variants of a prelude enum count as declared in every module. A variant of a dependency enum never gives E0518. An import entry that binds a struct named like a variant of the package or of the prelude is also E0518, at the import entry. The fix is an alias: `import geo.{Point as GeoPoint}`. A variant with the name of its own enum, such as `type Token { Token(Str), End }` or `type Errno { Errno(Int) }`, is E0518 at the variant, once, and not at each use. The type name `Token` would then be both a type and a variant of that type:

  ```
  error[NameCollision]: variant `Token` has the name of its enum `Token`
    help: rename the variant: `type Token { Word(Str), End }`

  error[NameCollision]: variant `Errno` has the name of its enum `Errno`
    help: rename the variant: `type Errno { Code(Int) }`
    help: to wrap one value, use a one-field struct (*Newtypes*, above): `type Errno { code: Int }`
  ```

  The struct help appears only for an enum with one variant and one payload. Neither help is machine-applicable. Within one package, a name is never both a product type and a sum injection, and a sum type is never one of its own injections. These two cases are the whole rule; it does not require all constructible names to be globally unique. For a struct, E0518 holds because `Name { ... }` reads as both a struct literal and a variant brace literal. An enum, alias, trait or effect has no such literal, so a type of one of those kinds named like a variant of a different enum is legal at its declaration. At a dotted head the type comes before the variant (*Dotted heads*, above), and a bare use of the variant is E0554 (*Unqualified variant*, above).

- **The same variant name in two different enums is legal.** For example, `Pending` may appear in both `JobState` and `NetState`. Each use in an expression names its enum. A bare `Pending` is E0554, and its help lists both qualified forms:

  ```blink
  type JobState { Pending, Running, Done }
  type NetState { Pending, Connected }

  fn main() {
      let s = JobState.Pending    // the variant of JobState
      let x = Pending             // error[UnqualifiedVariant]
                                  // help: write `JobState.Pending` or `NetState.Pending`
  }
  ```

No path ever silently picks a winner between two constructible names: a struct and a variant with one name is a declaration-time error (E0518), and a variant carries its enum in an expression. A value with the name of a user variant does not collide with it, because a bare name never reaches a user variant. A local named `Some`, `None`, `Ok` or `Err` hides the prelude variant. That is a shadow between scopes, by the order in *Values come first*, and W1011 marks it (§10.6 *Shadowing Rules*).

**A variant the enum does not declare.** A qualified construction `K.Zed`, `K.Zed(1)` or `K.Zed { .. }` where the enum `K` declares no variant `Zed` is `NoSuchVariant` (E0547). The span, the candidates, the machine-applicable rename and the variant list follow the pattern rule (§3.5 *Pattern Forms*); the payload form is that of the construction. The order of checks is also the same: resolve `K` (`UnknownType`, E0507), look up the variant (E0547), then compare with the expected type (`TypeError`, E0300). A name after `K.` that does not start with an uppercase letter is never a variant, so it never gets E0547 (*Member case*, above). A `Q` that is not an enum is E0547 in an expression too (`Int.Zed`, `Point.Zed(1)`). The message says what `Q` is, as in a pattern. A bare `Zedd(1)` that names no variant and no value stays `UndefinedFunction` (E0504). A binding whose value has the error, such as `x` in `let x = K.Zed`, has the poison type (§6.3.5), so a later use of `x` reports nothing more.

```blink
type Level { Low, High }

fn main() {
    let x = Level.Hihg     // error[NoSuchVariant]
    let y = x              // no further error: `x` has the poison type
}
```

```
error[NoSuchVariant]: `Level` has no variant `Hihg`
  help: did you mean `High`?
```

```blink
type Point { x: Int, y: Int }

fn main() {
    let a = Int.Zed          // error[NoSuchVariant]
    let b = Point.Zed(1)     // error[NoSuchVariant]
}
```

```
error[NoSuchVariant]: `Int` is not an enum; it has no variants
error[NoSuchVariant]: `Point` is a struct; it has no variants
```

Variant construction does not accept `..source`; copy-update (§2.16) applies to struct literals only. Every variant field must be supplied.

```blink
type Figure {
    Rect { width: Float, height: Float }
    Circle(radius: Float, tag: Int)
    Dot
}

fn widen(s: Figure) -> Figure {
    Figure.Rect { width: 2.0, ..s }
}
```

```
error[VariantSpread]: a variant literal cannot copy fields with `..s`
  help: write every field, or match on `s` to bind its fields (copy-update is for struct literals, §2.16)
```

A variant brace literal, and a variant paren payload that writes a label, follow the field rules of §2.14 *Checking a Literal's Fields*: `NoSuchField`, `DuplicateField` and `MissingField`. For a paren payload with a label these take the place of the argument-count error, so `Figure.Circle(radius: 1.0, radius: 2.0)` reports `DuplicateField` at the second `radius` and `MissingField` for `tag`, not a count.

A call may write any field by position or, if the variant names it, by label; a position fills the field at its index. In a paren payload, positional arguments come first. A positional argument after a labelled one is `PositionalAfterKeyword` (E0527), the code that a call gets for the same mistake (§2.13). The field rules then run on what the arguments fill: argument *i* fills field *i*, and a label fills the field it names. A label for a field that an earlier argument filled is `DuplicateField`, with a `note:` at the argument that filled it.

A wrong number of arguments in a variant paren payload is `VariantArgumentCount` (E0321). It applies to a payload that has no label, and to a payload that has more positional arguments than the variant has fields. It applies to `Some`, `Ok`, `Err`, `None` and to user variants alike. `TypeError` (E0300) stays for an argument of the wrong type. The error has a `note:` that lists the variant's fields in order, for every variant that has fields, `Some`, `Ok` and `Err` too. `MissingField` has the same `note:`. In the `note:`, each field that an argument filled, by position or by label, carries the mark `(given)`.

```blink
type Figure { Circle(radius: Float, tag: Int) }

fn main() {
    let a = Figure.Circle(1.0, 2)                 // ok
    let b = Figure.Circle(1.5, tag: 2)            // ok
    let c = Figure.Circle(tag: 2, radius: 1.5)    // ok
}
```

```blink
type Figure { Circle(radius: Float, tag: Int) }

fn main() {
    let d = Figure.Circle(1.0, radius: 2.0)       // error[DuplicateField], error[MissingField]
    let e = Figure.Circle(tag: 2, 1.0)            // error[PositionalAfterKeyword]
    let f = Figure.Circle(1.0)                    // error[VariantArgumentCount]
}
```

```
error[DuplicateField]: field `radius` is given twice
  note: argument 1 filled `radius`
error[MissingField]: `Figure.Circle` is missing field `tag` (Int)
  note: fields of `Figure.Circle`, in order: radius (Float) (given), tag (Int)
  help: add `tag: ` and a value
error[PositionalAfterKeyword]: a positional argument follows a labelled one
  note: `tag:` is the first label
  help: write the positional arguments first
error[VariantArgumentCount]: variant `Circle` takes 2 arguments, got 1
  note: fields of `Figure.Circle`, in order: radius (Float) (given), tag (Int)
```

A variant with no payload that gets arguments (`None(1)`, `Shape.Dot(1.0)`) is `VariantArgumentCount` too. The message says that the variant takes no arguments, and it has no `note:`. The help gives the one repair: remove the parentheses. The spec fixes that repair, not the exact words of the help.

**`Ok` takes one argument.** `Ok` has one field, as `Some` and `Err` do. The unit success is `Ok(())`, so `Ok()` is `VariantArgumentCount`:

- Where the success type is `()`, `Ok()` is a warning, with a machine-applicable fix to `Ok(())`. It becomes an error in the next release, and the diagnostic keeps its name and code (§8.16.1 *Rollout of a new error*).
- Where the success type is not `()`, `Ok()` is an error at once, with no fix. That program has no meaning, and `Ok(())` would be the wrong value there.
- Every other wrong count is an error at once.

In `let r = Ok()` the success type is not known. While `Ok()` is a warning, the compiler cannot say if the arity diagnostic is a warning or an error, so it reports `CannotInferType` (E0301) only. When `Ok()` is an error, it reports the arity error first and not E0301: a rejected term gives no type to infer from.

```blink
fn done() -> Result[(), Str] { Ok(()) }       // ok: the unit success
fn one() -> Option[Int] { Some(1) }           // ok
```

```blink
type Shape { Sq(Float, Float), Dot }

fn a() -> Result[(), Str] { Ok() }            // warning[VariantArgumentCount]: fix is Ok(())
fn b() -> Result[Int, Str] { Ok() }           // error[VariantArgumentCount]: at once, no fix
fn c() -> Option[Int] { Some() }              // error[VariantArgumentCount]
fn d() -> Shape { Shape.Dot(1.0) }            // error[VariantArgumentCount]
```

```
warning[VariantArgumentCount]: variant `Ok` takes 1 argument, got 0
  note: fields of `Ok`, in order: T
  help: write `Ok(())`
error[VariantArgumentCount]: variant `Ok` takes 1 argument, got 0
  note: fields of `Ok`, in order: T
error[VariantArgumentCount]: variant `Some` takes 1 argument, got 0
  note: fields of `Some`, in order: T
error[VariantArgumentCount]: variant `Shape.Dot` takes no arguments, got 1
  help: remove the parentheses
```

```blink
fn main() {
    let r = Ok()    // warning stage: error[CannotInferType] only; later: error[VariantArgumentCount] only
}
```

A variant with a positional payload, written with no argument list, is a function value (§3.4 *A payload variant named as a value*).

`blink fmt` does not canonicalize between the bare and qualified forms in either direction — a formatter must never change which entity a name resolves to.

#### Enums Are Nominally Distinct from `Int`

An enum is a distinct type from `Int`. Although each variant of a fieldless enum has an integer tag (see *Tag Operations* below), the tag does not make the enum *assignable* to `Int`, exactly as a `U8`'s 8-bit range does not make it assignable to `Int` (see *Sized Integer Types*). An enum value is not assignable to an `Int` target, and an `Int` is not assignable to an enum target — at let-bindings, function arguments, and function returns:

```blink
type State { Idle, Running, Done }

fn step(s: State) -> State { s }

fn main() {
    let n: Int = State.Idle   // error[TypeError]: declared type Int but got State
    let bad = step(2)         // error[TypeError]: argument 1 expects State, got Int
    let s: State = 7          // error[TypeError]: declared type State but got Int
}
```

The same holds for every nominal type, including a newtype (*Newtypes*, above): `type Errno { code: Int }` used as the error arm of `Result[Int, Errno]` cannot be confused with a plain `Int` count, which is the entire reason to prefer it over `Result[Int, Int]`.

**Tag Operations.** Three operations use an enum's integer tag: comparison with an `Int`, `Enum.to_int()` and `Enum.from_int()`. They are defined only on a **fieldless enum**, an enum whose variants all have no payload. The first variant in the declaration has the tag 0, and each next variant has the tag one greater.

- **Comparison with `Int`.** The comparison operators (`==`, `!=`, `<`, `<=`, `>`, `>=`) are defined between a fieldless enum and `Int`. They compare the enum's tag with the `Int` and yield `Bool`. This is a comparison, not an assignability claim, so it does not weaken the nominal distinctness above. A comparison of two values of the same fieldless enum is not a tag operation: it is the enum's `Ord` (§3.6 *Container Equality*, *Enum Ord*).
- **Crossing the boundary is explicit.** To get the tag as an `Int`, use `Enum.to_int()` (total). To go the other way, use `Enum.from_int(n) -> Option[Enum]`. It is fallible, because an arbitrary `Int` may not be a valid tag. There is no implicit coercion and no cast operator.

```blink
let s = State.Running
if s == State.Running { }   // OK: comparison, not assignment
let n = s.to_int()          // OK: State is fieldless
```

**Payload enums have no tag operations.** An enum with at least one payload variant has no comparison with `Int`, no `to_int()` and no `from_int()`. Each use is a compile error, `error[TypeError]`. A tag does not identify a payload value, and `from_int` cannot make one. To compare the payload, match on it:

```blink
type Reply { Code(Int), Silent }

let r = Reply.Code(5)
let a = r == 5         // error[TypeError]: Reply has a payload variant and does not compare with Int
                       //   help: match on the payload: match r { Reply.Code(n) => n == 5, _ => false }
let b = r.to_int()     // error[TypeError]: to_int() is defined only on fieldless enums
let ok = match r {
    Reply.Code(n) => n == 5
    Reply.Silent => false
}
```

This rule applies to every enum with a payload. A newtype is a struct and is not an enum, so this rule does not touch it; the stdlib `Errno` (§9.1.3.3) is a newtype.

> Pattern matching an `Int` scrutinee against enum-variant patterns (`match someInt { State.Idle => ... }`) is the pattern-side dual of the assignability rule and is likewise ill-typed.

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

**Display.** A Str-backed enum has no `Display` unless it implements one; `Display` is not derivable (§3.6.1). An `impl Display` can write `self.to_str()`, so that `"{Status.InProgress}"` is `in_progress`.

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
let tree = Tree.Branch(Tree.Leaf(1), Tree.Leaf(2))              // Tree[Int]
```

#### Explicit Type Application

A generic function's type parameters may also be supplied **explicitly**, in square brackets written directly after the callee:

```blink
let forecast = json.decode[Forecast](body)?
let buf = alloc_ptr[U8]()
```

Explicit type application is a third supply mechanism alongside inference at a construction site and a type annotation on the binding. All three name the same type parameters and differ only in where the program writes them. Brackets in this position can never be confused with indexing or comparison — Blink has no index operator, and element access is `.get()` (§2.6).

**No erasure.** Every type parameter a declaration binds is part of that declaration's instantiation, whether or not a parameter type or the return type mentions it. `probe[Int]()` and `probe[Str]()` are distinct instantiations. A type parameter is never dropped, never defaulted, and never merged with another instantiation's — the guarantee §3.4 *Under-Determined Types* makes at a binding, applied to a declaration.

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

*Rationale.* The rule this replaces refused `apply(identity, 3)` and accepted `let f = identity` followed by `apply(f, 3)` — the same value, one line apart, separated by where it was written rather than by anything about its type. A rule that distinguishes a term from its own η-expansion is a syntactic filter standing in a typing rule's position, and its prescribed repair — wrapping the name in a closure — means the same program. It refused one spelling of an identical program, it was defeated by one `let`, and it has been deleted rather than restated.

**A payload variant named as a value.** A variant with a positional payload, written with no argument list, is a function value. It may stand wherever a function value is expected, as a generic function's name may. A variant `V(P1, ..., Pn)` of the enum `E[ᾱ]` has the type `fn(P1, ..., Pn) -> E[ᾱ]`: one parameter for each payload type, in declaration order, and an empty effect row. A payload of two or more types gives that many parameters, not one tuple parameter. The binders `ᾱ` are the type parameters of the enum, and the rule above solves them: the expected type fixes them, and a reference whose binders nothing fixes is `error[CannotInferType]` (E0301) at the reference.

The rule covers the prelude variants and user variants alike. `Some` is `fn(T) -> Option[T]`, `Ok` is `fn(T) -> Result[T, E]`, and `Err` is `fn(E) -> Result[T, E]`. `Option.Some`, `Result.Ok` and `Result.Err` are the same values. A user variant is qualified, as in every expression: a bare `Leaf` is still `error[UnqualifiedVariant]` (E0554, *Variant Construction*), and this rule does not apply to it.

```blink
type Tree {
    Leaf(Int)
    Node(Tree, Tree)
    Empty
}

fn main() {
    let xs = [1, 2, 3]
    let opts = xs.map(Some)                         // OK -- fn(Int) -> Option[Int]; map's parameter fixes T = Int
    let leaves = xs.map(Tree.Leaf)                  // OK -- fn(Int) -> Tree
    let tree = leaves.fold(Tree.Empty, Tree.Node)   // OK -- fn(Tree, Tree) -> Tree: two parameters
    let f: fn(Int) -> Option[Int] = Some            // OK -- the annotation fixes T = Int
    let rs: List[Result[Int, Str]] = xs.map(Ok)     // OK -- the annotation fixes E = Str
}
```

`let f = Some` has no expected type, so nothing fixes `T`. In `xs.map(Ok)`, the parameter of `map` fixes `T`, but nothing fixes `E`. Each is E0301 at the reference, and the help names an annotation that fixes the binders:

```blink
fn main() {
    let xs = [1, 2, 3]
    let f = Some                  // error[CannotInferType] -- intentional-error example
                                  //   `T` of `Some` is unbound at this reference and nothing supplies it
                                  // help: annotate the binding:
                                  //   `let f: fn(Int) -> Option[Int] = Some`
    let rs = xs.map(Ok)           // error[CannotInferType] -- intentional-error example
                                  //   `E` of `Ok` is unbound at this reference and nothing supplies it
                                  // help: annotate the binding:
                                  //   `let rs: List[Result[Int, Str]] = xs.map(Ok)`
}
```

A labelled positional payload drops its labels, as every function value does (§2.13 *Limit of the guard*). For `Circle(radius: Float, tag: Int)` of `Figure`, `Figure.Circle` is `fn(Float, Int) -> Figure`.

Three forms are not this function value:

- **A variant with named fields** (a brace payload) is not a function value. It has no positional form, so it names no function. Naming it with no brace literal is `error[TypeError]` (E0300), and the help writes a closure.
- **A variant with no payload** is a value of its enum, never `fn() -> E`. Where a function is expected, it is a type mismatch (E0300), and the help writes a closure that returns the variant.
- **`Ok` as a value** is only the one-parameter function `fn(T) -> Result[T, E]`. Where `fn() -> Result[(), E]` is expected, it is a type mismatch (E0300), and the help writes `fn() { Ok(()) }`.

A wrong number of parameters is also a type mismatch (E0300): `Tree.Node` has two parameters, so it does not fit `fn(Tree) -> Tree`, and it does not fit a function of one tuple parameter.

```blink
type Tree {
    Leaf(Int)
    Node(Tree, Tree)
    Empty
}

type Shape {
    Circle { radius: Float }
    Point
}

type Color { Red, Green }

fn later(f: fn() -> Color) -> Color { f() }

fn main() {
    let ss = [1.0, 2.0].map(Shape.Circle)       // error[TypeError] -- intentional-error example
                                                // help: write `fn(r) { Shape.Circle { radius: r } }`
    let c = later(Color.Red)                    // error[TypeError]: a type mismatch -- intentional-error example
                                                // help: write `fn() { Color.Red }`
    let k: fn() -> Result[(), Str] = Ok         // error[TypeError]: a type mismatch -- intentional-error example
                                                // help: write `fn() { Ok(()) }`
    let g: fn(Tree) -> Tree = Tree.Node         // error[TypeError]: a type mismatch -- intentional-error example
    let pairs = [(Tree.Empty, Tree.Empty)]
    let ts = pairs.map(Tree.Node)               // error[TypeError]: a type mismatch -- intentional-error example
                                                //   `map` expects a function of one `(Tree, Tree)` parameter
}
```

```
error[TypeError]: variant `Shape.Circle` has named fields and is not a function value
  help: write `fn(r) { Shape.Circle { radius: r } }`
```

*Rationale.* `Some` and `fn(x) { Some(x) }` are the same term, so the rationale above applies word for word: a rule that refused `xs.map(Some)` would refuse one spelling of an identical program. A brace payload has no call form, so no one closure is equal to it. A variant with no payload is a value, not a function: `Color.Red` and `fn() { Color.Red }` are different terms.

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

*Rationale.* The gate is drawn where it is because **W0604 fires exactly when deleting the binder is a safe edit** — when the declaration still compiles afterwards and means the same thing, so the fix the lint prescribes cannot break working code. Occurrence is what makes that property checkable: any mention of `T` anywhere in the declaration or its body is a way the declaration could depend on `T`, and a mention in a body form the language has not been given yet is still a mention. Stated as a predicate the counterfactual needs machinery the gate does not — the comparison is between programs modulo the mechanical erasure of type-argument lists at call sites, since deleting any binder turns `tag[Int]()` into an arity error on its own. The occurrence clause is the rule; safety of the prescribed edit is the reason the rule is drawn there. If a future type position lets a body depend on `T` without naming it, this rationale is the criterion for amending the clause.

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

**E0303 is decided when the head resolves, from the declaration's binder count and the written list alone.** For a method callee (`x.decode[A, B]()`), the receiver's type selects the method, so the count is checked once that type is known. The call's own arguments play no part in the check. E0303 is reported instead of E0301 and E0306. A constructor's arity is a property of its declaration alone, so the mismatch is known the moment the head is resolved. This is what distinguishes E0303 from `error[CannotInferType]` (E0301, §3.4 *Under-Determined Types*): E0301 fires when inference *terminates* with a type variable no use ever fixed; E0303 fires when a type expression was never well-formed to begin with. A bare `Channel` annotation is not an unsolved variable that a later use might constrain — it names a slot the program neglected to fill, and no downstream use can fill an argument the annotation did not open. The two never co-fire on the same type expression: a well-formed constructor application may leave a variable under-determined (E0301), but an ill-formed one is rejected first (E0303).

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

An item is a **type** when it parses as a type expression and every name in it resolves in the type namespace (§2.12.1): to a type, a type alias, or a type parameter in scope. Every other item is a **value**: a literal, a local, a constant, or any other expression. Name resolution decides this in every case, so the code never depends on the receiver's type. `xs[i]` and `self.items[i]` get the same code at the same stage.

**A name in both namespaces.** A bracket item is in type position, so each name in it resolves the same way as in a type annotation: only the type namespace is searched. A value of the same name, at module scope or as a local, does not change the result. A `let` binds in the value namespace and cannot hide a type (§10.6 *Shadowing Rules*). So `make[MAX]()` and `let d: List[MAX]` always read `MAX` as the same type. Names in the arguments of a type application, such as the `MAX` in `xs[List[MAX]]`, are in type position too.

**A name that does not resolve.** When a name in an item resolves in neither namespace, only the name-resolution error is reported for that bracket suffix. E0313, E0303 and E0314 are not reported for it, because the correct code depends on what the name turns out to be: a type gives E0303, a value gives E0313 (§3.1 rule 3). This also applies to a name inside a compound item, such as `Foo` in `xs[List[Foo]]`. Other bracket suffixes in the same expression are checked as usual.

E0303 is checked before E0314 because deleting the list discharges both. A value head with type contents, such as `xs[Int]`, is therefore E0303 (`xs` takes 0 type arguments), and its repair, deleting the list, exists.

When the head is a value and the item is a bare name that also has a value binding, the author most likely meant to read an element. The first `help:` is then the element read, chosen from the receiver's type as for E0313 below: `.get()` where the type has it, and a field access for a tuple. Deleting the list is the second `help:`. When the receiver has neither, deleting the list is the only `help:`. Any bracket diagnostic on a bare-name item that also has a value binding carries a `note:` that names both declarations and says that the name is read as a type:

```blink
type MAX { n: Int }
const MAX = 2

fn make[T]() -> List[T] { [] }

fn main() {
    let xs = [10, 20, 30]
    let a = make[MAX]()        // OK -- `MAX` is the type
    let b: List[MAX] = a       // OK -- the same type
    let c = xs[MAX]            // error[TypeArgArity]: `xs` takes 0 type arguments
                               // note: `MAX` is read as a type here (line 1); it is also a value (line 2)
                               // help: `xs.get(MAX)` returns `Option[Int]`
                               // help: delete the list -- `xs`
    let d = xs[List[MAX]]      // error[TypeArgArity]: `xs` takes 0 type arguments
                               // help: delete the list -- `xs`
}
```

**NoIndexOperator (E0313).** Element access is a method call. The first `help:` depends on the receiver's type: `.get()` where the type has it, and a field access for a tuple:

```blink
fn main() {
    let xs = [10, 20, 30]
    let pair = (1, "a")
    let mut ages: Map[Str, Int] = Map.new()
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

Every store diagnostic, plain or compound, also carries a one-line `note:` that gives the reason: brackets hold types, and a program reads and writes elements with methods. The spec fixes what the note says, not its words. The reason must be true for every receiver type and every position, so the note never gives a reason that holds for one container only, such as an allocation. The headline stays `Blink has no index operator`.

For `xs[i] op= v` on a `List` or `Bytes`, the machine-applicable fix is `xs.set(i, xs.get(i).unwrap() op v)`. The fix writes `i` twice, so it keeps the meaning only when `i` is a literal, a local binding or a `const`, as name resolution sees it. A module-level `let mut` or a call does not qualify. The help says that the fix panics when `i` is out of bounds, because `set` does. For any other index, and for a nested place, the diagnostic carries a `note:` to bind the index with `let` first, and offers no machine-applicable fix.

For `m[k] op= v` on a `Map`, a missing key has no value to apply `op` to, and only the author knows what that case means. So the diagnostic offers no machine-applicable fix. Its `note:` names two forms, the default form first:

- `m.insert(k, (m.get(k) ?? 0) op v)` when a missing key starts at a default value.
- `m.insert(k, m.get(k).unwrap() op v)` when a missing key is a bug. This form panics on a missing key.

The note writes the literal default (`0` or `0.0`) only for `+=` and `-=` on an `Int` or `Float` value. For any other operator or value type, a default of zero is wrong or does not type-check, so the note writes a placeholder such as `<default>` in its place. The placeholder must not parse as a Blink expression, so that a copied note fails to compile and never runs with a wrong default. Both forms write `k` twice, so when `k` is not a literal, a local binding or a `const`, the note also says to bind the key with `let` first.

The example below shows the reason note on the plain stores only. The compound stores carry it too.

```blink
fn main() {
    let mut xs = [10, 20, 30]
    let mut ages: Map[Str, Int] = Map.new()
    let i = 1

    xs[0] = 5              // error[NoIndexOperator]: Blink has no index operator
                           // help: `xs.set(0, 5)`
                           // note: brackets hold types (`List[Int]`); elements use methods
    ages["bob"] = 41       // error[NoIndexOperator]: Blink has no index operator
                           // help: `ages.insert("bob", 41)`
                           // note: brackets hold types (`List[Int]`); elements use methods
    xs[i] += 1             // error[NoIndexOperator]: Blink has no index operator
                           // help: `xs.set(i, xs.get(i).unwrap() + 1)` (panics when `i` is out of bounds)
    ages["bob"] += 1       // error[NoIndexOperator]: Blink has no index operator
                           // note: `ages.insert("bob", (ages.get("bob") ?? 0) + 1)` when a missing key starts at 0,
                           //       or `ages.insert("bob", ages.get("bob").unwrap() + 1)` when it is a bug
    ages["bob"] *= 2       // error[NoIndexOperator]: Blink has no index operator
                           // note: `ages.insert("bob", (ages.get("bob") ?? <default>) * 2)` when a missing key
                           //       starts at a default, or `ages.insert("bob", ages.get("bob").unwrap() * 2)`
}
```

**TypeArgsWithoutCall (E0314).** A type-argument list supplies type arguments to a call or a literal. With neither after it, nothing uses it. E0301 does not apply, because the brackets bind the type parameters. The first `help:` depends on the context:

| Context | Example | First `help:` |
| --- | --- | --- |
| An expected type fixes the same type arguments that were written | `apply(identity[Int], 3)` | remove the brackets — `apply(identity, 3)` |
| A binding, and no expected type | `let f = identity[Int]` | annotate and remove the brackets, as one edit — `let f: fn(Int) -> Int = identity` |
| An expected type fixes different type arguments | `apply(identity[Str], 3)` | none that can be applied by machine; the diagnostic names both types |
| The list follows a type and a type-scoped function follows the list | `Map[Str, Int].new()` | move the list after the function name — `Map.new[Str, Int]()` |

Removing the brackets is offered first only when the expected type gives the same arguments that were written. Where they differ, removing the brackets would still compile, but it would silently change the instantiation the program asked for. That is a change of meaning, not a repair. The conflict between the written and the expected type is the real defect, and only the author can say which one is correct.

**A list after a type, then a type-scoped function.** `Map[Str, Int].new()` is E0314. The type head takes no list in a term position; a type-scoped function declares its own binders and takes the list after its name (§2.12.3, §3.4 *Explicit Type Application*). For a standard library type the fix is machine-applicable: `Map[Str, Int].new()` becomes `Map.new[Str, Int]()`. For a user type the fix is a suggestion only, because the language does not check that the binders of the function follow the order of the type's parameters. `Registry[Int].new()` may mean `Registry.new[Int]()` or another order of binders.

A binding whose initializer is E0313 or E0314 gets no further E0300 or E0301 from that initializer (§3.1 rule 3).

#### Under-Determined Types

Inference at a binding is a two-state judgment: either every type variable is resolved to a concrete type, or the ones that cannot be resolved are **reported**. There is no third state — Blink never *defaults* an unresolved type variable to a concrete type, and there is no user-facing "unknown" or "any" type that inference can fall into.

When Hindley-Milner inference finishes a binding with a type variable still unbound — not fixed by an annotation and not fixed by any later use — that binding is `error[CannotInferType]`. The repair for a binding is a type annotation.

> **The repair is whatever reaches the open type variable, and E0301 is reported where that repair attaches.** For the bindings below, an annotation on the `let` reaches it, so the diagnostic points at the `let`. For a type parameter that the callee's signature does not supply, the annotation cannot reach it and the repair is an explicit type-argument list at the call — so the diagnostic points there instead, including when the call is a bare statement with no binding at all (§3.4 *Explicit Type Application*). One rule, one diagnostic, reported at the edit that fixes it.

```blink
fn f() {
    let x = []          // error[CannotInferType]: element type of `x` is undetermined
    let n = None        // error[CannotInferType]: the inner type of `n` is undetermined
    let m = Map.new()   // error[CannotInferType]: key/value types of `m` are undetermined
}
```

The fix in every case is to annotate the binding:

```blink
fn f() {
    let x: List[Int] = []
    let n: Int? = None
    let m: Map[Str, Int] = Map.new()
}
```

This is one rule applied uniformly: an empty `[]`, a bare `None`, an empty `Map.new()`/`Set.new()`, and an under-constrained generic construction are not four cases — they are one case, "inference left a type variable unbound," reported by one diagnostic.

**Later use still determines the type — there is no error when it does.** The error fires only when inference *terminates* with the variable unbound, so a binding constrained by a subsequent use is inferred normally with no annotation:

```blink
fn g() {
    let mut xs = []   // element type inferred from the push below
    xs.push(1)        // xs : List[Int] — no annotation, no error
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

**A later use does not choose an impl.** `xs.push(1)` fixes the type that `xs` holds. It does not reopen the choice of an impl. A call through a generic type's qualifier that matches two impls, such as `Box.from(xs)`, is E0301 at the call, whatever a later statement does with the result (§3c.2 *A Generic Qualifier That Matches Two Impls*).

**Under-determination flows through construction.** An under-constrained generic construction is the same error, reported at the binding, with the enclosing constructor's parameters named:

```blink
type GKV[K, V] {
    m: Map[K, V]
}

fn f() {
    let b = GKV { m: Map.new() }   // error[CannotInferType]: type parameters K, V of `GKV`
                                   //   are undetermined — no use constrains them
    // fix: let b: GKV[Int, Str] = GKV { m: Map.new() }
}
```

The diagnostic points at the binding — where the annotation fix applies — and carries a secondary span at the empty constructor (`Map.new()` / `[]`) explaining why the parameter is open (`error[CannotInferType]`, E0301 — see [ERROR_CATALOG.md](../ERROR_CATALOG.md)). This mirrors the variant rules (§3.4): no path ever silently picks a winner.

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

There is no "an Ok-only value proves the error type is uninhabited, so resolve it to a bottom type" rule. Inferring a type the program never wrote — whether the erased unit `Void` or a bottom `Never` — into an unconstrained slot is the same unlicensed substitution the two-state model forbids; a `Never` error type is reached only when a program *writes* `Result[Int, Never]`, never chosen by inference for an open slot. A genuine `Result[Void, Str]` or an explicitly-written `Result[Int, Never]` is unaffected.

#### Type Name Resolution (normative)

A type name denotes **one declaration identity**.

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

**Hygiene.** Syntax that the compiler expands, and types the compiler inserts, refer to the compiler-known type **by identity**, never by the name that is in scope at the use site. This covers `T?` and `??` (`Option`), `?` (`Result`/`Option`), `for` (`IntoIterator`/`Iterator`), `..`/`..=` (`Range`), `==`/`<` and the other operators (their traits), `with` (`Handler`, `Scoped`, `Closeable`), `async.spawn` (`Handle`), template literals (`Template[C]`), literals (`Int`, `Float`, `Str`, `Char`, `Bool`), and every other desugaring in this spec. A trait name that the user writes (a bound, an `impl`, a supertrait clause, a `@derive` argument) is not a desugaring and resolves by scope (§10.6 *Shadowing a Prelude Trait*). A module that declares its own `Option` still gets the builtin `Option` from `x?`:

```blink
type Option {
    label: Str
}                                 // warning[W1010]: shadows compiler-known type `Option`

fn first(xs: List[Int]) -> Int? {  // `Int?` is the builtin Option[Int], by identity
    let x = xs.get(0)?
    Some(x)
}
```

**Identity, not spelling, selects behavior.** Behavior depends on a type's declaration identity, not on its spelling. Two types with the same name and different identities are different types everywhere.

The set of names that may not be declared at all, and the rule for a declaration that takes any other compiler-known name, are in §10.6 *Shadowing Rules*.

#### Recursive Types

Types can reference themselves. A recursive field is a value like any other, and a copy of it follows §3.6.1 *Clone Semantics*.

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

bind_pattern  ::= binder "as" atomic_pattern
               |  atomic_pattern

binder        ::= "mut"? IDENT                                // a name the pattern binds

atomic_pattern ::= "_"                                        // wildcard
               |   binder                                     // variable binding
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
               |   TYPE_NAME "{" field_patterns "}"           // struct, or variant with named fields
               |   TYPE_NAME "." IDENT "{" field_patterns "}" // qualified variant with named fields

pattern_list  ::= pattern ( "," pattern )*

field_patterns ::= field_pattern ( "," field_pattern )* ( "," ".." )?
               |   ".."

field_pattern  ::= MEMBER_NAME ":" pattern                    // field with sub-pattern; a keyword is legal (§2.23)
               |   binder                                     // field punning; the name is never a keyword

guard         ::= "if" expression

match_arm     ::= pattern guard? "=>" expression
```

`TYPE_NAME` and `IDENT` are both identifiers. In a refutable pattern, the first character of a bare name decides whether it is a variant or a binding (*Bare names: variant or binding*, below). A `mut` before a name that is a variant is not a binder (*Mutable Binders*, below).

#### Pattern Forms

**Wildcard.** `_` matches any value and discards it.

**Variable binding.** An identifier binds the matched value to a new variable in the arm body.

**Bare names: variant or binding.** The first character of a bare name, and the kind of pattern it is in, decide what the name means.

A pattern is *refutable* when it can fail to match (*Refutable vs Irrefutable Patterns*, below). The rule applies at every refutable pattern position. Today these are the pattern of a `match` arm, at any depth, and the pattern operand of `assert_matches` (§2.20). A future form that takes a refutable pattern uses this rule. In a refutable pattern:

- A bare name whose first character is an uppercase letter (Unicode `Lu` or `Lt`) names a variant of the type at that position, with or without a payload (`Red`, `Red(x)`, `Red { .. }`). A type with that name in scope does not change this: E0554 (§3.4 *Unqualified variant*) covers expressions only. If that type is not an enum, it is `EnumPatternNeedsEnumScrutinee` (E0308). If the enum has no variant of that name, it is `NoSuchVariant` (E0547).
- A bare name whose first character is not an uppercase letter (a lowercase letter, `_`, or a letter that has no case) never names a variant, because no variant has such a name (§3.4 *Variant names*). With no payload, it is a new binding. With a payload (`x(1)`, `x { .. }`), it is `NoSuchVariant` (E0547) when the type at that position is an enum, and `EnumPatternNeedsEnumScrutinee` (E0308) when it is not.

The first character decides, so a reader and the compiler know which names an arm binds before they know the type of the scrutinee. The rule has this reason: without it, a typo (`Dott`) or the name of a constant (`MAX`) would be a new binding that matches every value. That binding hides every later arm and turns off the exhaustiveness check. Every variant name starts with an uppercase letter, so the protection covers every variant.

In an irrefutable pattern (`let`, a parameter, a closure parameter, `for`), any bare name with no payload is a new binding, and W1011 applies as §10.6 *Shadowing Rules* says. A bare name with a payload must name a variant.

No value binding, local or module-scope, changes what a pattern means.

```blink
type Color { Red, Green }

fn name(c: Color) -> Str {
    let Red = 5                    // a local: the variant stays `Color.Red`
    match c {
        Red => "red"               // still `Color.Red`: the scrutinee is a Color
        Green => "green, not {Red}"  // an expression: `Red` is the local, 5
    }
}

fn show(n: Int) -> Str {
    match n {
        Red => "n is red"          // error[EnumPatternNeedsEnumScrutinee]: Int has no variant `Red`
        _ => "other"
    }
}
```

An uppercase name on a type that is not an enum gets E0308. To bind the value, write a lowercase name:

```blink
fn bind(n: Int) -> Str {
    match n {
        red => "n is {red}"        // OK: a lowercase name is a new binding
    }
}
```

A constant is not a pattern. It gets the same error. When a value with that name is in scope, the help also shows a second repair: bind the value and compare it in a guard:

```blink
const MAX = 10

fn check(n: Int) -> Str {
    match n {
        MAX => "at the limit"      // error[EnumPatternNeedsEnumScrutinee]
        _ => "below"
    }
}
```

```
error[EnumPatternNeedsEnumScrutinee]: match arm names variant `MAX`, but the value being matched has type `Int` -- a scalar has no variants
  help: to bind the value, write a lowercase name
  help: to compare with the value `MAX`, write a guard: `n if n == MAX =>`
```

```blink
fn check(n: Int) -> Str {
    match n {
        n if n == MAX => "at the limit"  // OK: a guard compares with the value
        _ => "below"
    }
}
```

A binder in a refutable pattern cannot have the name of an uppercase variant, because that name is the variant. W1011 (§10.6 *Shadowing Rules*) covers only a binder named `Some`, `None`, `Ok` or `Err`, so a pattern binder gets W1011 only in an irrefutable pattern.

**A variant the enum does not declare.** A variant pattern must name a variant that its enum declares. The compiler reports `error[NoSuchVariant]` (E0547) for:

- a bare name with a payload (`Somee(v)`, `Zed { .. }`) when the type at that pattern position is an enum that has no variant of that name;
- a bare name with no payload and an uppercase first character (`Dott`) when the type at that pattern position is an enum that has no variant of that name;
- a qualified name `K.Zed`, with or without a payload, when the enum `K` declares no variant `Zed`.

A variant pattern needs an enum. When the type at the pattern position is not an enum, a bare name with a payload, and a bare name with an uppercase first character and no payload, is `EnumPatternNeedsEnumScrutinee` (E0308), as *Bare names: variant or binding* says. The rule is "not an enum". These types are examples, not a full list: a builtin scalar, a struct, a tuple, a `List` or a `Map`, and a type parameter. A type alias is resolved first, so an alias of an enum is an enum. For a struct, the message says that the type has no variants: "`Point` is a struct; it has no variants". For a scalar or a builtin generic type, the message says: "`Int` is not an enum; it has no variants". For a type parameter, the help suggests no variant. The compiler reports E0308 for a type parameter where the generic function is defined, not at a call.

```blink
fn total(xs: List[Int]) -> Int {
    match xs {
        Empty => 0         // error[EnumPatternNeedsEnumScrutinee]
        _ => 1
    }
}
```

```
error[EnumPatternNeedsEnumScrutinee]: `List[Int]` is not an enum; it has no variants
  help: to bind the value, write a lowercase name
```

When the type at the pattern position is not known yet, the compiler reports `CannotInferType` (E0301, §3.4 *Under-Determined Types*), not E0547 or E0308. A variant pattern on a builtin scalar, bare or qualified, is `EnumPatternNeedsEnumScrutinee` (E0308, §3.4 *Enums Nominally Distinct from Int*). A qualified pattern `Q.V` where `Q` is not an enum is a different error: it is E0547 (*Qualified names and the wrong type*, below). A bare name with no payload whose first character is not an uppercase letter is a binding, so it never gets E0547.

The rule applies at every depth. In `Some(Somee(v))` on an `Option[Option[Int]]`, the inner pattern is checked against the payload type of `Some`, so `Somee` gets E0547.

The span is the variant name: `Somee` in `Somee(v)`, `Zed` in `K.Zed`. The help uses the nearest-name suggestion (ERROR_CATALOG *Conventions*). Its candidates are the variants of the enum at that pattern position that are visible at the site. A variant that another arm already matches stays a candidate. Outside the module of a `pub opaque type`, the help lists and suggests no variant of that type. With one suggestion, the rename is machine-applicable only when the payload forms agree: a pattern with no payload and a unit variant, a `( )` payload and a variant declared with `( )`, or a `{ }` payload and a variant declared with `{ }`. Otherwise the help names the variant but the fix is not machine-applicable. With no suggestion, the help lists the declared variants. The terminal text may shorten a long list and give a count of the rest; the count line names `--format json` and `blink explain NoSuchVariant`. Structured output (`--format json`, the language server) lists every variant.

```blink
type Shape { Circle(Float), Square(Float), Dot }

fn area(s: Shape) -> Float {
    match s {
        Circel(r) => 3.14159 * r * r   // error[NoSuchVariant]
        Square(w) => w * w
        Dott => 0.0                    // error[NoSuchVariant]: not a new binding
    }
}
```

```
error[NoSuchVariant]: `Shape` has no variant `Circel`
  help: did you mean `Circle`?
error[NoSuchVariant]: `Shape` has no variant `Dott`
  help: did you mean `Dot`?
```

The qualified form `Shape.Dott` gets the same error.

When a bare name with a payload is not a variant of the type at the position, and exactly one enum visible at the site declares that name, the error gets a `note:` that names the enum. The compiler finds that enum only to write the note; the note never changes what the pattern means:

```blink
type Token { Num(Int), Plus }
type Expr { Lit(Int), Add }

fn value(t: Token) -> Int {
    match t {
        Lit(n) => n        // error[NoSuchVariant]
        Plus => 0
    }
}
```

```
error[NoSuchVariant]: `Token` has no variant `Lit`
  note: `Lit` is a variant of `Expr`, not of `Token`; a pattern for `t` can name only variants of `Token`
  help: `Token` declares: Num, Plus
```

**Qualified names and the wrong type.** The compiler checks a qualified pattern `Q.V` in this order, and the first failure is the only error for that pattern:

1. Resolve `Q`. A name that is not a type is `UnknownType` (E0507).
2. Look up `V` in `Q`. A variant that `Q` does not declare is E0547, and the message names `Q`. If `Q` is a type that is not an enum, `Q` declares no variant, and the error is E0547. The message says what `Q` is. The scrutinee type does not change this.
3. Compare `Q` with the type at the pattern position. A different type is `TypeError` (E0300).

So `Other.Zed` on a `T` scrutinee gives one E0547 for `Other`, and no E0300. `Point.Zed` on a `Color` scrutinee, where `Point` is a struct, gives one E0547 too. A qualified variant of a different enum, such as `Other.Q(v)` on a `T` scrutinee, is E0300, the same error as `let t: T = Other.Q(1)`. A struct pattern of a different struct type, such as `Q { y }` on a `P` scrutinee, is also E0300. The header names both types, and the span is the whole path (`Other.Q`) or type name (`Q`). The help lists the variants of the expected type. When that type declares a variant with the same name and the same payload form, the help gives the fix `T.Q`, and the fix is machine-applicable.

```blink
type T { A(Int), Q(Int) }
type Other { Q(Int) }

fn f(x: T) -> Int {
    match x {
        Other.Q(v) => v    // error[TypeError]
        T.A(v) => v
    }
}
```

```
error[TypeError]: pattern of type `Other` used on a value of type `T`
  help: write `T.Q`; `T` declares: A, Q
```

A type parameter is equal only to itself. A qualified enum pattern or a struct pattern on a scrutinee of a type parameter is E0300, with or without bounds. The compiler reports it where the generic function is defined, not at a call.

```blink
type Color { Red, Green }

fn name[T](t: T) -> Str {
    match t {
        Color.Red => "red"     // error[TypeError]
        _ => "other"
    }
}
```

```
error[TypeError]: pattern of type `Color` used on a value of type `T`
```

A qualified pattern `Q.V` where `Q` is not an enum is E0547, whatever the scrutinee type. The header names what `Q` is. For a struct it says: "`Point` is a struct; it has no variants". For a scalar or a builtin generic type it says: "`Int` is not an enum; it has no variants". The span is the variant name.

```blink
type Point { x: Int, y: Int }
type Color { Red, Green }

fn f(c: Color) -> Int {
    match c {
        Point.Zed => 1     // error[NoSuchVariant]
        _ => 0
    }
}

fn g(xs: List[Int]) -> Int {
    match xs {
        List.Zed(v) => v   // error[NoSuchVariant]
        _ => 0
    }
}
```

```
error[NoSuchVariant]: `Point` is a struct; it has no variants
error[NoSuchVariant]: `List[Int]` is not an enum; it has no variants
```

Step 3 has one exception. On an `Int` (or another builtin number type), a qualified variant of an enum is `EnumPatternNeedsEnumScrutinee` (E0308), and the help suggests a conversion. The exception is for a builtin scalar position only. On a struct, a `List`, a tuple or a type parameter, the same pattern is E0300. These types are examples, not a full list.

```blink
type Color { Red, Green }
type Point { x: Int, y: Int }

fn from_int(n: Int) -> Str {
    match n {
        Color.Red => "red"   // error[EnumPatternNeedsEnumScrutinee]
        _ => "other"
    }
}

fn from_point(p: Point) -> Str {
    match p {
        Color.Red => "red"   // error[TypeError]
        _ => "other"
    }
}

fn from_list(xs: List[Int]) -> Int {
    match xs {
        Option.Some(v) => v  // error[TypeError]
        _ => 0
    }
}
```

```
error[EnumPatternNeedsEnumScrutinee]: match arm names variant `Color.Red`, but the value being matched has type `Int` -- a scalar has no variants
  help: match the enum itself, or cross the boundary explicitly with Color.from_int(...), which answers Option[Color]
error[TypeError]: pattern of type `Color` used on a value of type `Point`
error[TypeError]: pattern of type `Option` used on a value of type `List[Int]`
```

A type alias resolves at step 1. A qualified pattern through an alias of an enum is legal.

**After the error.** Each binder under a pattern with one of these errors has the poison type (§6.3.5). The compiler still checks the arm body and suppresses each diagnostic that only the poison type causes. *Exhaustiveness* below says how such an arm counts for coverage. These rules apply to `blink check` and to `blink build` alike: each variant pattern resolves to its enum and variant before code generation, or the compiler reports an error, so the two commands report the same diagnostics for one program.

**After a field error.** `NoSuchField` (E0525) and `DuplicateField` (E0316) in a struct pattern or a variant brace pattern (*Struct patterns* below) also leave the arm checked, but the poison is narrower. Only a binder under an unknown label has the poison type. A binder under a label that the type declares keeps the type of its field, and so does a binder under the second of two equal labels. `PatternMissingRest` (E0319) poisons nothing, and an arm with only this error is not a bad arm: the compiler checks it as if the pattern had `..`.

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

`..` in list patterns cannot bind a variable. Use `.slice()` or loops for tail access.

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

The compiler checks the labels of a struct pattern and of a variant brace pattern (`Rect { w, .. }` and `Shape.Rect { w, .. }`) in the same way. It checks them at every depth and in every pattern position: `match` arms, nested patterns, `let`, `for`, and each alternative of an OR-pattern. The labels form a set, as the labels of a literal do (§2.14 *Checking a Literal's Fields*). The checks run after the type-name checks (E0507, E0547, E0300) of *Qualified names and the wrong type*, in this order:

1. **A label twice** is `DuplicateField` (E0316). The error is at the second label, with a `note:` at the first.
2. **A label that the type or variant does not declare** is `NoSuchField` (E0525). The candidates for the nearest-name suggestion (Error Catalog, *Conventions*) are the declared fields that the pattern does not already label. With one suggestion, the rename is machine-applicable. With none, the help lists the declared fields and marks those the pattern already labels. For a punned label, as in `Point { x, yy }`, the fix writes `y: yy`. The binder and the arm body stay as they are, so the fix cannot change which name a use in the arm refers to. The help never says "or add the field to `T`" for a pattern label.
3. **Fields left out with no `..`** is `PatternMissingRest` (E0319). One error for each pattern, at the type or variant name. It lists each missing field and its type, in declaration order. A field that is the one suggestion for an unknown label in the same pattern is not missing. If the list is then empty, the compiler reports nothing. A field default (§2.14) does not count as naming the field: a pattern that leaves out a field with a default still needs `..`. The error gives two fixes, always in this order:
    1. Add `..`. This fix is machine-applicable and is the preferred fix.
    2. Write `f: _` for each left-out field `f`. This fix is in structured output, and is never machine-applicable. It keeps the pattern closed: a field that the type gains later is an error again.

`PatternMissingRest` is a different code from `MissingField` (E0315). A literal gives the missing fields values. A pattern only names or skips them.

```blink
type Point { x: Int, y: Int }

fn sum(p: Point) -> Int {
    match p {
        Point { x, y } => x + y                // field punning
    }
}

fn sum_long(p: Point) -> Int {
    match p {
        Point { x: px, y: py } => px + py      // the same pattern, with a binder for each label
    }
}
```

```blink
type Point3 { x: Int, y: Int, z: Int }

fn get_x(p: Point3) -> Int {
    match p {
        Point3 { x, y } => x        // error[PatternMissingRest]: `z` is left out
        Point3 { x, yy, .. } => x   // error[NoSuchField]: `yy`
    }
}
```

```
error[PatternMissingRest]: `Point3` pattern leaves out field `z` (Int) and has no `..`
  help: add `..`
  = fix: Point3 { x, y, .. }
  = fix: Point3 { x, y, z: _ }
error[NoSuchField]: `Point3` has no field `yy`
  help: did you mean `y`?
  = fix: y: yy
```

The first `PatternMissingRest` fix is machine-applicable. The second is not.

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

Multiple patterns separated by `|` share a single arm body. All alternatives must bind the same set of variable names with the same types and the same mutability (*Mutable Binders*, below). `|` binds looser than constructor application, tighter than `=>`. No nested OR inside constructors — use `Some(1) | Some(2)`, not `Some(1 | 2)`.

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

A binder that is `mut` in one alternative and not in another gets the same error. The fix puts `mut` on the binder in every alternative. `blink fix` can apply it, because the alternatives share one arm body:

```
error[InconsistentPatternBindings]: inconsistent bindings in OR-pattern
 --> input.bl:5:5
  |
5 |     Event.Click(mut x, y) | Event.Touch(x, y) => step(x, y)
  |                 -----                  ^ `x` is not `mut` here
  |                 |
  |                 `x` is `mut` here
  |
  = help: write `mut x` in every alternative, or in none
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

#### Mutable Binders (`mut`)

A **binder** is a name that a pattern binds: a variable binding, a punned field name, or the name before `as`. A binder is immutable, like a `let` binding (§2.2). To make a binder mutable, write `mut` directly before it. `let mut x = v` is the one-binder case of this rule. The rule is the same in `let`, `for`, `match` arms and parameter patterns.

```blink
fn widen(pair: (Int, Int), pts: List[(Str, Int)], o: Int?) {
    let (mut lo, mut hi) = pair         // two mutable binders
    lo -= 1
    hi += 1

    let (mut count, total) = (0, 10)    // `total` is not mut
    count += total
    io.println("{lo} {hi} {count}")

    for (name, mut score) in pts {      // only `score` is mut
        score += 1
        io.println("{name}: {score}")
    }

    match o {
        Some(mut n) => {
            n *= 2
            io.println("{n}")
        }
        None => {}
    }
}
```

**`mut` marks one name.** `mut` applies to the binder right after it and to nothing else. In `let mut whole as (a, b) = pair`, only `whole` is mutable; `a` and `b` are not. To make each of them mutable, write `let mut whole as (mut a, mut b) = pair`.

**Struct fields.** In a punned field, `mut` goes before the field name: `Point { mut x, .. }` is short for `Point { x: mut x, .. }`. In a renamed field, `mut` goes before the binder after the colon: `Point { x: mut px, .. }`. A field label is not a binder, so `Point { mut x: px }` is an error (below).

**`mut` before a pattern that is not a binder.** `mut` before a tuple, a struct, a constructor, a variant, `_`, a literal or a range binds no name. This is `error[E0613] MutOnPattern`. `blink fix` can apply each fix:

| Code | Fix |
|---|---|
| `let mut (x, y) = pair` | `let (mut x, mut y) = pair` |
| `for mut (k, v) in pairs` | `for (mut k, mut v) in pairs` |
| `Some(mut Point { x, y })` | `Some(Point { mut x, mut y })` |
| `Point { mut x: px }` | `Point { x: mut px }` |
| `mut _`, `mut 5`, `mut None` | remove `mut` |

For a tuple, struct or constructor, the fix puts `mut` on every binder inside it. This keeps the meaning of the old form. `for mut i in xs` is legal: `i` is a binder.

```
error[MutOnPattern]: `mut` must come before a name, not a tuple pattern
 --> pair.bl:2:9
  |
2 |     let mut (x, y) = pair
  |         ^^^ this `mut` marks no name
  |
  = help: put `mut` on each name in the pattern: `let (mut x, mut y) = pair`
```

**A `mut` binder is a mutable root.** A `mut` binder follows every rule for a `let mut` binding. It can be the root of an assignment or a mutating method call (§3.2.2 *Construction and Mutability*). `async.spawn` cannot capture it (E0650, §2.8). `warning[UnusedMut]` fires on each `mut` binder that the body never mutates (§3.6 *Lints*). A mutation whose root is a binder with no `mut` is `error[E0610] MutationRequiresMut`, and the fix inserts `mut` before that binder.

**A binder is a new local.** Binding copies the matched value into the binder, as `let` does. An assignment to a `mut` binder changes the binder only, never the matched value. A shared cell in the value stays shared (§3.6 *Shared cells*), so a mutating call on it shows through both names:

```blink
type User { name: Str, visits: Int, tags: List[Str] }

fn visit(u: User?) {
    match u {
        Some(mut v) => {
            v.visits += 1               // changes `v` only; `u` keeps the old count
            v.tags.push("seen")         // `tags` is a shared cell: `u` sees "seen" too
        }
        None => {}
    }
}
```

**Parameter patterns.** Each binder in a parameter pattern is a parameter (§3.6 *Mutable Parameters*). `mut` makes it a mutable root for a mutating method call only. An assignment to it is `error[E0612] ParamAssign`, with or without `mut`.

**`with ... as`.** The name after `as` in `with expr as name { }` is not a pattern binder. It is never `mut` (§2.18 *Rules*).

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
- **`Never` payloads** — a variant whose payload type is `Never` still needs an arm. The checker does not remove the arm because no value can reach it. The arm body may be the payload itself, which has type `Never` and fits any expected type. §3.2 shows the `Err(e) => e` form.
- **Unreachable arms** — an arm, or one OR-alternative, that earlier unguarded arms already cover is `UnreachableArm` (W0710), a warning. The check never reports a live arm. It may miss a dead one. It reports at least the shapes listed in *Unreachable arms* below. It never reports an arm for a variant whose payload type is `Never`.

**An arm with a bad pattern covers nothing.** A *bad arm* is an arm whose pattern, at any depth, has a `NoSuchVariant` (E0547) error, one of the pattern `TypeError` (E0300) errors of *Pattern Forms* above, or a `NoSuchField` (E0525) or `DuplicateField` (E0316) error in a struct pattern or a variant brace pattern (*Struct patterns* above). `PatternMissingRest` (E0319) alone does not make a bad arm: the checker treats the pattern as if it had `..`. The checker treats a bad arm as an arm that matches no value. It never treats it as `_`. Then:

- When a match has an unguarded bad arm, the compiler reports no `NonExhaustiveMatch` (E0004) for that match. The missing coverage is probably the variant that the bad arm tried to name.
- A guarded bad arm does not turn off E0004. A guarded arm never adds coverage, so an E0004 next to it stays true after the user corrects the name.
- The compiler reports no `UnreachableArm` (W0710) for the bad arm itself. Each other check runs as usual, E0005 included. Because the bad arm covers nothing, it never makes a later arm look unreachable, and each such report stays true whatever repair the user makes.

```blink
fn get(x: Option[Int]) -> Int {
    match x {
        Somee(v) => v      // error[NoSuchVariant]; no E0004 for `Some`
        None => 0          // checked as usual; not unreachable
    }
}

fn get_pos(x: Option[Int]) -> Int {
    match x {
        Somee(v) if v > 0 => v   // error[NoSuchVariant]
        None => 0
    }                            // error[NonExhaustiveMatch]: missing `Some`
}
```

**Unreachable arms.** Arms run from top to bottom: the first arm that matches runs. An arm is *unreachable* when the unguarded arms above it already match every value that its pattern matches. It never runs. This does not change what the program does, so it is a warning, not an error: `UnreachableArm` (W0710), with the header "unreachable match arm". The primary span is the pattern, not the body.

- **Never a live arm.** The check never reports an arm that some value can reach. It may miss an arm that no value can reach. A pattern with a refutable payload does not cover its variant: `Some(5)` above `Some(v)` is a live arm and gets no report. Range, tuple, struct and `Str` patterns may be missed.
- **Guards.** A guarded arm above covers nothing, because its guard may be false (the *Guards* rule of the list above). A guarded arm below gets a report when the unguarded arms above cover its pattern: the guard does not change that.
- **The reports that the check must give.** The check reports at least these arms: an arm after an unguarded `_` or bare binding; and an arm whose pattern is a variant, `true`, `false` or a literal that an earlier unguarded arm already names, when that variant's payload patterns are all irrefutable. It also always reports a pattern that is identical to an earlier unguarded pattern, in the same arm (an OR-alternative) or in an earlier arm. The test for this is equality of the two patterns, not a cover of refutable payloads. The check may miss any other dead arm.
- **OR-patterns.** Each dead alternative gets its own report, at the span of that alternative. When every alternative is dead, the arm gets one report.
- **More than one arm covers.** When no one earlier arm covers the pattern but the earlier arms cover it together, each earlier arm that is needed gets a label. A label never points at an arm that the cover does not need.
- **`Never` payloads.** The check never reports an arm for a variant whose payload type is `Never`. It does not reason about types with no values.
- **Bad arms.** A bad arm covers nothing and gets no report (above).

```blink
fn after_catch_all(x: Option[Int]) -> Int {
    match x {
        _ => 0
        Some(v) => v          // warning[UnreachableArm]
        None => 1             // warning[UnreachableArm]
    }
}

fn repeated_variant(x: Option[Int]) -> Int {
    match x {
        None => 0
        None => 1             // warning[UnreachableArm]
        Some(v) => v
    }
}

fn repeated_bool(b: Bool) -> Int {
    match b {
        true => 1
        false => 0
        true => 2             // warning[UnreachableArm]
    }
}

fn repeated_literal(n: Int) -> Int {
    match n {
        1 => 10
        1 => 11               // warning[UnreachableArm]
        _ => 0
    }
}

fn repeated_pattern(x: Option[Int]) -> Int {
    match x {
        Some(1) | Some(1) => 1    // warning[UnreachableArm] on the second alternative
        Some(1) => 2              // warning[UnreachableArm]
        Some(_) => 3
        None => 0
    }
}
```

The next functions show the other rules:

```blink
fn live_arm(x: Option[Int]) -> Int {
    match x {
        Some(5) => 1          // not reported
        Some(v) => v          // not reported: `Some(5)` does not cover `Some(v)`
        None => 0
    }
}

fn may_miss(n: Int) -> Int {
    match n {
        0..=10 => 1
        5 => 2                // dead, and the check may miss it
        _ => 0
    }
}

fn joint_cover(x: Option[Int]) -> Int {
    match x {
        None => 0
        Some(v) => v
        None | Some(_) => 9   // warning[UnreachableArm]: both arms above are needed
    }
}

fn guarded(x: Option[Int]) -> Int {
    match x {
        Some(v) if v > 0 => v     // covers nothing
        Some(v) => 0 - v          // not reported
        Some(_) => 5              // warning[UnreachableArm]: `Some(v)` covers it
        None => 0
    }
}
```

```
warning[UnreachableArm]: unreachable match arm
 --> src/shape.bl:5:9
  |
3 |         other => 0
  |         ----- this arm matches every value
5 |         Circle(r) => r * r
  |         ^^^^^^^^^ no value reaches this arm
  |
  = help: remove the arm, or move it above `other`
```

For `joint_cover`, the report puts a label on each of the two arms above (`None` and `Some(v)`) and the primary span on `None | Some(_)`.

The help is text only. No fix is machine-applicable, because the mistake may be in the earlier arm, so `blink fix` never changes the arms. Suppress the warning on a function with `@allow(UnreachableArm)`, or set its level with `W0710 = "off"` or `W0710 = "error"` under `[lints]` (§4.16.8).

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

// Mutable names: `mut` goes before each name that changes
let (mut lo, hi) = bounds(xs)

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

`Hash` is for container keys and its value has a seed for each process. For a cryptographic digest, see `Sha256` in §3.2.3 (`std.digest`).

`hash(self) -> U64` returns a hash of the value. Implementations must satisfy the coherence law with `Eq`: for any `a` and `b`, `a == b` implies `a.hash() == b.hash()`. Coherence is a property of `hash` against `eq`.

**Iteration order.** A `Map` or `Set` iterates in insertion order (vote: 6-0; see [Map/Set Insertion Order rationale](../decisions/map-insertion-order-reaudit.md)):

- `insert` adds a new key at the end. `insert` on a key that is already present replaces the value and keeps the key's position.
- `remove` keeps the relative order of the remaining keys. A key inserted again after `remove` goes at the end.
- `keys()`, `values()`, `entries()` and `for` give the same order.

```blink
let mut scores: Map[Str, Int] = Map.new()
scores.insert("carol", 3)
scores.insert("alice", 1)
scores.insert("carol", 4)
for (name, score) in scores {
    io.println("{name}: {score}")
}
// carol: 4
// alice: 1
```

A `Map` or `Set` made from other values is built by inserts in this order:

- `clone()` keeps the order.
- `a.union(b)` gives the elements of `a` in `a`'s order, then the elements of `b` that are not in `a`, in `b`'s order.
- `a.merge(b)` on a `Map` gives the keys of `a` in `a`'s order, then the keys of `b` that are not in `a`, in `b`'s order. A key in both takes `b`'s value.
- `filter` and `map_values` on a `Map` keep the receiver's order.
- `collect()`, and any build from a list, inserts in the order of the input. For a duplicate key, the key keeps its first position and takes the last value.
- A std deserializer inserts in document order, but keeps the first entry for a duplicate key (§3.6.2 *Map and Set Order*).

**Hash seed.** The runtime picks a random hash seed for each process. The random seed protects a `Map` or `Set` that holds untrusted keys from hash-flooding attacks. The seed controls only how keys go into buckets. It has no effect on iteration order, on `debug()` text, or on serializer output. The language has no API that reads or sets the seed.

**Equality and reuse.** Iteration order is **not** part of a `Map`/`Set` value's identity — two maps with equal entry sets are `==`-equal regardless of insertion history (§3.6 *Container Equality*). A compiler may reuse the result of a pure call only for arguments that are identical in representation. `==` does not license reuse: two `==` values can give different results (two equal maps can iterate in different orders).

**Float keys.** `F32`/`F64` do not implement `Hash`, and a `Float` (or any type transitively containing one) used as a `Map`/`Set` key is rejected at type-check as `E1400 MapKeyNotHashable`. This is a permanent contract, not a missing impl: float equality cannot satisfy the `Eq`/`Hash` coherence law — `-0.0 == 0.0` holds while the two have distinct bit patterns, so a bitwise hash would give equal values different hashes. Round to an integer key instead.

**Non-hashable keys and elements in general.** Only builtin scalars (`Int`, sized ints, `Bool`, `Char`, `Str`), `Never` (§3.2), a tuple whose elements are all hashable, and a user `struct`/`enum` that implements `Hash` and `Eq` implement `Hash`. `Never` is the only type outside these groups on the list; it gives no container a way in. A user type gets the two impls from `@derive(Hash, Eq)` or from a written `impl` (§3.6, *Trait Coherence*). A fieldless enum is `Eq` already (*Container Equality*), so it needs only `@derive(Hash)` or an `impl Hash`. Every other type — every container (`List`, `Map`, `Set`, `Option`, `Result`), `Bytes`, `StringBuilder`, and any `fn`/closure type — has no `Hash` impl and cannot gain one, so using one as a `Map` key or `Set` element is rejected at type-check as `E1400 MapKeyNotHashable`, the same code as the Float case above. A tuple is hashable **if and only if** every one of its elements is; `(Int, Option[Int])` is rejected because its second element is not, even though `(Int, Str)` is accepted.

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

`E0733` fires at the subtrait's redeclaration site, not at any call site, and applies to two cases: redeclaring a method a supertrait already provides as an open default, and redeclaring any supertrait method to add or change its contract (§3b.2 *Contracts on Trait Methods*). A normal `impl`-block override of that open default (without `final`) is unaffected — that is the ordinary replace-only override of §3.6 *The `final` Modifier*.

**Effect-row subtype for trait impls.** Every method an `impl` provides for a trait, whether it implements a required method or overrides an open default, must declare an effect row `R_i` with `R_i ⊆ R_t`, where `R_t` is the row the trait declares for that method. An impl may *narrow* the row (drop effects it does not use) but may not *widen* it (add effects the trait does not declare). A trait method with no `!` has the empty row, so every impl of it must also have no `!`. For a method whose row has no `_`, this rule is what lets a bound `T: Trait` stand as an upper bound on the effects of a call through it: a generic function with no `!` that calls `x.m()` for `x: T` performs no effects for any `T`. The rule covers fixed and empty rows. A trait method whose row has `_` and no callback source lets each impl choose its row (§4.15.2): only a row with no `_` bounds the impls, and effects beside that `_` limit no impl. A widening impl is rejected at the impl method with `error[TraitContractEffectMismatch]` (E0904). The check uses the impl method's effective row, so an impl that touches module state widens a row that lacks `State` (§4.16.1). See §4.5 *Effect Composition Rules* for the subtyping lattice. `final` defaults have no override site, so their row is fixed at the declaration.

Contracts on trait methods follow the same narrow-only shape: an impl inherits the trait method's `@requires` and `@ensures`, may add `@ensures`, and may not add `@requires` (E0912). See §3b.2 *Contracts on Trait Methods*.

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

**`self` is always passed by value.** Blink has no by-reference vs by-move distinction. The `self` parameter is a value like any other parameter. No `&self`, `&mut self`, or `self: Box[Self]` forms exist. `mut self` is a mutable parameter (see *Mutable Parameters* below), not a reference.

A method cannot change its caller's value through `self`. State that must persist across calls lives in a `let mut` binding captured by a closure or handler (§2.8, §4.7). An assignment to a field of `self`, or of any parameter, is a compile error (see *Mutable Parameters*).

**Shared cells.** Passing or binding a struct copies its fields. A field whose value is a shared cell refers to the same cell after the copy. After `let mut b = a` and `b.x = 2`, `a.x` is unchanged; after `b.xs.push(5)`, `a.xs` holds the new element too. The shared cells are:

- `List`, `Map` and `Set`
- `StringBuilder`
- a closure or handler that captured a `let mut` binding (§2.8, §4.7)

This list is the only one; other sections refer to it. `Bytes` is not on it: a `Bytes` is a value (§3.2.3 *Bytes*).

Across tasks, `async.spawn` freezes each shared cell its captures reach until the task is joined (§2.8 *Shared cells in a spawned task*), and `ch.send` copies each shared cell the sent value reaches (§4.13 *Channel operations*).

**Synchronized objects.** A synchronized object is a value whose state any task may use at the same time, with no freeze and no copy. The runtime makes each of its operations safe from any task. A copy of a synchronized object refers to the same state. The synchronized objects are:

- `Channel[T]`: a copy names the same queue (§4.13 *Channel operations*)
- `Handle[T]`: a copy names the same task (§4.13 *Handle[T]*)

A type joins this list only if each operation on it is safe from any task, and a value it hands from one task to another stays reachable from one task only. A `Channel` copies the value at send; a `Handle` gives its result only after its task has ended. Only the queue of a `Channel` and the join state of a `Handle` are synchronized. The values they carry are not: `ch.send` copies the shared cells a value reaches, so a value in a channel's buffer was copied when it was sent, and no other name reaches it. For this reason `async.spawn` and `ch.send` need not look inside a synchronized object: the freeze does not cover it, and the send does not copy it.

An effect handle name such as `io` or `db` is not on either list. It is not a value and cannot be bound, passed or sent (§3c.4 *Effect Handle Operations*). A `Handler[E]` value is a shared cell when its captures reach a `let mut` binding, as listed above.

Only a shared cell or a synchronized object can change through a second name. A value of any other type, at any depth, cannot. This holds for every copy: bind, pass, return and `clone()` (§3.6.1 *Clone Semantics*).

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

trait Push {
    fn push(mut self, x: Int)
}

impl Push for Stack {
    fn push(mut self, x: Int) {
        self.items.push(x)              // OK — `mut self`
    }
}
```

**Parameter patterns.** Each binder in a parameter pattern is a parameter and follows the rules of this subsection. `mut` on it allows a mutating method call. An assignment to it is E0612 (below), with or without `mut`:

```blink
fn fill((mut xs, n): (List[Int], Int)) -> Int {
    xs.push(n)                          // OK — `xs` is a mut parameter
    xs.len()
}
```

**A parameter is never assigned.** An assignment to a parameter, or to a field of one, is always a compile error, `error[E0612] ParamAssign`, with or without `mut`, `self` included. Such a write changes only the callee's copy of the value (§3.6 *`self` is always passed by value*), so the caller never sees it. To change a value locally, copy it to a new `let mut` name:

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

trait WithX {
    fn with_x(self, x: Int) -> Point
}

impl WithX for Point {
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

Inside `enter()` of a `Scoped` impl, a write to a field of `self` gets a different help line. The usual cause is an attempt to keep state for `exit()`, and a local copy does not reach `exit()`:

```
error[ParamAssign]: cannot assign to parameter `self`
 --> timer.bl:9:9
  |
9 |         self.start = time.read()
  |         ^^^^^^^^^^ `self` is a parameter
  |
  = note: `exit()` receives the value the `with` item built, not this copy
  = help: set `start` when the value is built, and build it in the `with` item (§4.7.2)
```

This help text appears only in `Scoped.enter()`. Every other parameter assignment gets the `let mut` help above.

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

**Foreign functions.** An `@ffi` or `@runtime` function has no Blink body to check. Its author declares `mut` on each parameter whose Blink value the foreign code changes (for example the `@runtime` binding `sb_write(mut sb: StringBuilder, s: Str)`). The compiler trusts this declaration and cannot verify it; it is part of the audited premise of the `@ffi` boundary (§9).

**Lints.** Two warnings support the rule. Neither is a guarantee:

| Warning | Fires on | Help |
|---|---|---|
| `MutAliasOfImmutable` | An argument to a `mut` parameter, or the right side of `let mut b = a`, when it is a place with a non-`mut` root | "`b` shares `a`'s collections; a change through `b` is visible through `a`" |
| `UnusedMut` | A `let mut` binding, `mut` pattern binder or `mut` parameter whose body never uses the mutability. It fires on each binder alone | Remove `mut` from that name. Does not fire on a `mut` an impl keeps from its trait, or on `@ffi` parameters |

`MutAliasOfImmutable` checks direct aliases only. An alias made through a call result (`id(a)`) or a struct literal (`W { xs: a }`) passes it. An immutable `let` is not a promise that the value behind it never changes (§3.2.2).

**Rollout.** Each new error in this subsection follows the rule of §8.16.1 *Rollout of a new error*.

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
Because every `impl` must satisfy the trait's supertraits, also under its own bounds
when it is polymorphic (*Polymorphic Trait Implementations*), a default body that
type-checks under the guarantee set is valid for every implementor — the check is
complete at the definition.

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

**`Add` is commutative.** For every type that implements `Add`, `a + b == b + a`, or both panic. For Float, `==` is the total order (*Float Total Ordering*), so every NaN is equal to every other NaN, whatever its sign or payload. Blink states no associativity law for `Add`: Int `+` is checked (overflow panics), and Float `+` rounds. A type whose `+` would not be commutative does not implement `Add`. `Str`, `Bytes` and `List` joining are such operations (§2.19 *String Concatenation*).

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
| `a < b` | `a.cmp(b) == Ordering.Less` | `Ord` |
| `a > b` | `a.cmp(b) == Ordering.Greater` | `Ord` |
| `a <= b` | `a.cmp(b) != Ordering.Greater` | `Ord` |
| `a >= b` | `a.cmp(b) != Ordering.Less` | `Ord` |

Operands must be the same type. Mixed-type arithmetic (`Int + Float`) is a compile error -- use explicit conversion.

#### Float Total Ordering

`Float` implements `Eq` and `Ord` with **total ordering** semantics (vote: 5-0; re-audit kept it, 6-0):

- `NaN == NaN` is `true` (restores reflexivity)
- `NaN` sorts greater than all other values
- `-0.0 == 0.0` is `true`
- `Float` does **not** implement `Hash` — bitwise hashing cannot stay coherent with `Eq` (e.g. `-0.0 == 0.0` with distinct bit patterns), so `Float` keys are rejected as `E1400` (see Hash Contract and Seeding, §3.6)

For IEEE 754 equality, use the method `x.ieee_eq(y)`. It is the IEEE 754 equality predicate (C's `==`): `NaN` is unequal to every value, itself included, and `(-0.0).ieee_eq(0.0)` is `true`. `x == y` is `true` exactly when `x.ieee_eq(y)` is `true` or both operands are `NaN`. No `Float` equality tells `-0.0` from `0.0`. To test the sign, use `x.is_sign_negative()` (*Built-in Float Methods*).

`F32` has the same total order and the same `ieee_eq`, with the signature `fn(self, F32) -> Bool`. Each type compares at its own width: an `F32` comparison is a binary32 comparison.

```blink
let nan = 0.0 / 0.0
assert(nan == nan)              // total order
assert(!nan.ieee_eq(nan))       // IEEE: NaN is unequal to itself
assert(nan.is_nan())            // the NaN test
assert(-0.0 == 0.0)             // warning[NegativeZeroComparison]: the zeros are equal
assert((-0.0).ieee_eq(0.0))     // warning[NegativeZeroComparison]
assert((-0.0).is_sign_negative()) // the sign of zero
```

##### Differences from IEEE 754

IEEE 754, and C, Rust, Python and JavaScript with it, make every comparison with NaN false except `!=`. Blink's `==`, `!=`, `<`, `<=`, `>` and `>=` use the total order, so code that relies on the IEEE results gives different answers. The differences are:

- `NaN == NaN` is true.
- `NaN != NaN` is false.
- When `y` is not NaN, `NaN > y` and `NaN >= y` are true, and `NaN < y` and `NaN <= y` are false.
- `NaN <= NaN` and `NaN >= NaN` are true.

An upper-bound check catches NaN. A lone lower-bound check lets it through:

```blink
fn clamp(x: Float, lo: Float, hi: Float) -> Float {
    if x > hi { return hi }    // Blink: NaN -> hi. C/Rust/Python: NaN passes through
    if x < lo { return lo }
    x
}
```

`x > max` is true for NaN, so it rejects NaN; under IEEE 754 it is false, and NaN passes. `x >= min` is also true for NaN, so it accepts NaN, where IEEE code would reject it. A guard such as `!(x >= 0.0)` does not reject NaN in Blink.

- To test for NaN, use `x.is_nan()` (*Built-in Float Methods*).
- To test for a finite value, use `x.is_finite()` (*Built-in Float Methods*).
- For IEEE equality, use `x.ieee_eq(y)`.
- `x != x` is always false in Blink. The compiler gives the warning `FloatSelfComparison` (W0707) for it and for the other comparisons of a value with itself (*Float Self Comparison*).

#### Built-in Float Methods

`Float` and `F32` have these built-in methods that work on the IEEE 754 form of a value. They need no import. Each row covers both types.

| Method | Signature on `Float` | Signature on `F32` | Returns |
|--------|----------------------|--------------------|---------|
| `to_bits` | `fn(self) -> U64` | `fn(self) -> U32` | The IEEE 754 binary64 (binary32) bit pattern |
| `from_bits` | `fn(U64) -> Float` (static) | `fn(U32) -> F32` (static) | The value with that bit pattern |
| `is_sign_negative` | `fn(self) -> Bool` | `fn(self) -> Bool` | The sign bit |
| `is_nan` | `fn(self) -> Bool` | `fn(self) -> Bool` | `true` exactly when the value is a NaN, of any sign or payload |
| `is_infinite` | `fn(self) -> Bool` | `fn(self) -> Bool` | `true` exactly when the value is `inf` or `-inf` |
| `is_finite` | `fn(self) -> Bool` | `fn(self) -> Bool` | `true` exactly when the value is neither a NaN nor an infinity |

A NaN is neither finite nor infinite. `0.0`, `-0.0` and every subnormal value are finite.

`from_bits` is total: every bit pattern is a value, so it returns `Float` (`F32`), not an `Option`. `to_bits` is not a conversion and has no `From` impl (§3c.3 *The `to_` rule for scalars*). A bitwise operator on a `Float` is a type error (§3.2.3 *Sized Integer Types*); its help names `to_bits()`.

**Laws.** For every `b: U64` and all `x`, `y` of type `Float` (and the same for `F32` over `U32`):

- **Round trip.** `Float.from_bits(b).to_bits() == b`. This holds for every NaN payload, signaling NaNs included.
- **Bits are finer than `==`.** If `x.to_bits() == y.to_bits()`, then `x == y`. The converse is false: `-0.0 == 0.0`, and two NaNs with a different sign or payload are `==`, but their bits differ.
- **Arithmetic.** An operation that gives a NaN does not fix the sign or payload of that NaN.
- **Sign.** `x.is_sign_negative()` is `true` exactly when the sign bit of `x` is set. That includes `-0.0` and a NaN with the sign bit set. `1.0 / x < 0.0` is `false` for every NaN, so it is not a sign test. To test for negative zero, use `x == 0.0 && x.is_sign_negative()`.
- **NaN test.** `x.is_nan() == !x.ieee_eq(x)`. `x != x` is not a NaN test, because it is always false (*Differences from IEEE 754*).
- **Classes.** For every `x`, exactly one of `x.is_nan()`, `x.is_infinite()` and `x.is_finite()` is `true`.
- **Infinity test.** For `Float`, `x.is_infinite() == (x == Float.INF || x == -Float.INF)`. A NaN is not `==` to either infinity.
- **Finite test.** `x.is_finite()` is `true` exactly when the exponent field of `x.to_bits()` is not all ones.
- **Copies keep every bit.** Copy, move, storage, and passing to or from an `@ffi` function keep every bit of a `Float` or `F32`. This law does not cover what C code does with the value.

```blink
fn main() {
    let z = -0.0
    assert(z == 0.0)                         // == does not see the sign
    assert(z.is_sign_negative())
    assert(!0.0.is_sign_negative())
    assert(z.to_bits() != 0.0.to_bits())     // the bits do
    let nan = Float.from_bits(9221120237041090561) // a quiet NaN, payload 1
    assert(nan == 0.0 / 0.0)                 // every NaN is == every NaN
    assert(nan.is_nan())                     // any payload is a NaN
    assert(nan.to_bits() == 9221120237041090561) // the payload is kept
    io.println(z.to_bits().display())        // 9223372036854775808
}
```

**Constants.** `Float` has two constants. They need no import, because the prelude declares them (§2.12.3 *Type-Scoped Declarations*).

- `Float.INF` is positive infinity. Negative infinity is `-Float.INF`.
- `Float.NAN` is a quiet NaN. The spec does not fix its sign or its payload.

`x == Float.NAN` is `true` for every NaN in Blink (*Float Total Ordering*). The preferred test is `x.is_nan()`. `F32.INF` and `F32.NAN` are not defined until `F32` is supported.

```blink
fn main() {
    let inf = Float.INF
    assert(inf.is_infinite() && (-inf).is_infinite())
    assert(!inf.is_finite())
    assert(Float.NAN.is_nan())
    assert(!Float.NAN.is_finite())           // a NaN is neither finite
    assert(!Float.NAN.is_infinite())         // nor infinite
    assert(1.5.is_finite() && (-0.0).is_finite())
    assert(0.0 / 0.0 == Float.NAN)           // every NaN is == every NaN; prefer is_nan()
}
```

#### Negative Zero Comparison

`-0.0` and `0.0` are equal in the total order (*Float Total Ordering*). So in a `Float` comparison, a `-` in front of a zero literal cannot change the result. Code that writes `x == -0.0` usually means a sign test, but the test is also `true` for `0.0`. The compiler gives the warning `NegativeZeroComparison` (W0706) when an operand of a `Float` or `F32` comparison is a *written negative zero*.

- **Written negative zero.** The check reads the operand as written. The operand is one unary `-` over a float literal with the value zero, with optional parentheses:
  ```
  N ::= "-" Z | "(" N ")"
  Z ::= FLOAT_LIT with the value zero | "(" Z ")"
  ```
  `-0.0`, `(-0.0)`, `-(0.0)` and `-0e0` match. `-(-0.0)` has two `-` and does not match. A `const` reference or a `let` binding that holds -0.0 does not trigger the warning, and neither do `0.0 * -1.0`, `-x` or `Float.from_bits(...)`. The check does no flow analysis, so it also fires in a branch that never runs.
- **Comparisons.** The warning fires when an argument is N and the call resolves to the `Float` or `F32` impl of one of these:
  - `Eq`: `==`, `!=`, `x.eq(y)`, `x.ne(y)`
  - `Ord`: `<`, `<=`, `>`, `>=`, `x.cmp(y)`
  - `ieee_eq`, with N as the receiver or the argument
  - the built-in `assert_eq` and `assert_ne`, when `T` is `Float` or `F32`

  Either operand can be N, also when the other operand is a literal. The check runs in typecheck on the resolved callee, not on the method name, so a method `eq` on another type that takes a `Float` argument does not fire. It fires only where the impl is concretely `Float` or `F32`: a generic body never warns because of one of its instantiations. A call that compares values inside its own body is not a comparison here, so `xs.contains(-0.0)` does not fire. `min` and `max` do not fire either: when the two values are equal, the sign of the result can depend on which one comes back.
- **Where.** It fires in test blocks and in the body of an `assert_panics` block (§2.20). The `assert_panics` rule of `DivisionByLiteralZero` does not apply here.
- **Patterns.** No pattern form can write `-0.0` today (*Pattern Grammar*). A change that adds such a pattern form must bring it under W0706 or make it an error.

```blink
fn classify(x: Float) -> Str {
    if x == -0.0 { return "negative zero" }   // warning[NegativeZeroComparison]
    if x <= -0.0 { return "not positive" }    // warning[NegativeZeroComparison]
    "positive"
}

fn negate(x: Float) -> Float { -x }

test "negate keeps the sign" {
    assert_eq(negate(0.0), -0.0)              // warning[NegativeZeroComparison]
}
```

```
warning[NegativeZeroComparison]: `-0.0` compares the same as `0.0`
 --> src/main.bl:2:13
  |
2 |     if x == -0.0 { return "negative zero" }
  |             ^^^^ this comparison is true for 0.0 and -0.0
  |
  = help: to test the sign, use `x.is_sign_negative()`
  = help: to test for negative zero, use `x == 0.0 && x.is_sign_negative()`
  = note: to test for zero, write `0.0`; it means the same and does not warn
```

- **Span and label.** The primary span is the N operand, not the whole comparison. The label for `==`, `ieee_eq` and `assert_eq` is "this comparison is true for 0.0 and -0.0". For `!=` and `assert_ne` it is "this comparison is false for 0.0 and -0.0". For `<`, `<=`, `>`, `>=` and `cmp` it is "this comparison gives the same result for 0.0 and -0.0".
- **Help.** The `help:` lines name `is_sign_negative()`. For `!=` and `assert_ne`, the negative-zero help is `x != 0.0 || !x.is_sign_negative()`. The help writes the other operand's text in place of `x` when that operand is a *simple path*: a name, or a field access on a simple path (`x`, `p.y`), with no call and no index. For any other operand, the help says to bind it first (`let v = negate(0.0)`, then `v == 0.0 && v.is_sign_negative()`). The help never repeats a call.
- **No machine-applicable fix.** The compiler cannot tell whether the code means the sign, negative zero, or zero, so `blink fix` changes nothing. An editor can offer the rewrites as code actions that a person selects.
- **`blink explain W0706`** shows `x == -0.0`, `x.ieee_eq(-0.0)`, `x.is_sign_negative()` and `x.to_bits() == (-0.0).to_bits()` side by side for `x = 0.0` and `x = -0.0`. It says that a `const` or `let` that holds -0.0 is not checked, and that moving `-0.0` into one does not make a sign test correct. It names `xs.contains(-0.0)` as a form the check does not see.

Suppress the warning on a function with `@allow(NegativeZeroComparison)`, or set its level with `W0706 = "off"` or `W0706 = "error"` under `[lints]` (§4.16.8). A function-level `@allow` overrides `[lints]`. A module-scope `let` or `const` has no enclosing function, so only `[lints]` controls W0706 there.

#### Float Self Comparison

In the total order (*Float Total Ordering*), a `Float` compared with itself always gives the same result: `x == x`, `x <= x` and `x >= x` are always true, and `x != x`, `x < x` and `x > x` are always false. Code ported from C, Rust or Python often writes `x != x` as a NaN test, and in Blink that test never passes. The compiler gives the warning `FloatSelfComparison` (W0707) when the two operands of a `Float` or `F32` comparison are the same place, written the same way.

- **Operators.** `==`, `!=`, `<`, `<=`, `>` and `>=`, when the operator resolves to the `Float` or `F32` impl of `Eq` or `Ord`. As for W0706, the check runs in typecheck on the resolved operator, only where the impl is concretely `Float` or `F32`.
- **Operands.** Both operands are the same local, parameter, or field path on one of those (`x`, `p.y`, `a.b.c`), written with the same tokens. An operand with a call or an index does not match: `f() != f()` and `xs.get(i) != xs.get(i)` do not fire. The check does no flow analysis: `let y = x` then `y != x` does not fire, and it fires in a branch that never runs.
- **Where.** It fires in test blocks and in the body of an `assert_panics` block (§2.20).

```blink
fn check(x: Float) -> Result[Float, Str] {
    if x != x { return Err("nan") }       // warning[FloatSelfComparison]
    if !(x >= 0.0) { return Err("negative") } // no warning, and NaN gets through
    Ok(x)
}
```

```
warning[FloatSelfComparison]: `x != x` is always false for a Float
 --> src/main.bl:2:8
  |
2 |     if x != x { return Err("nan") }
  |        ^^^^^^ NaN == NaN in Blink, so this is false for every value
  |
  = help: to test for NaN, use `x.is_nan()`
```

- **Span and label.** The primary span is the whole comparison. The message and label depend on the operator:

  | Operator | Message | Label | Help |
  |----------|---------|-------|------|
  | `!=` | `` `x != x` is always false for a Float `` | NaN == NaN in Blink, so this is false for every value | to test for NaN, use `x.is_nan()` |
  | `==`, `<=`, `>=` | `` `x == x` is always true for a Float `` (with the operator as written) | NaN == NaN in Blink, so this is true for every value | to test that the value is not NaN, use `!x.is_nan()` |
  | `<`, `>` | `` `x < x` is always false `` (with the operator as written) | this is false for every value | the comparison is always false; remove it or compare with a different value |

  The `<` and `>` rows give no NaN reason, because those comparisons are also always false under IEEE 754. The help writes the operand's text in place of `x`.
- **Suggested fix only.** For `!=`, the replacement is `x.is_nan()`. For `==`, `<=` and `>=`, it is `!x.is_nan()`. `<` and `>` have no replacement. The `help:` line and the JSON diagnostic (§8.6) carry the exact replacement text, and an editor can offer it as a code action that a person selects. The fix is not machine-applicable: it turns a branch that never runs into one that can run, so `blink fix` never applies it.
- **`blink explain W0707`** gives the results of the six comparisons for a NaN, in Blink and under IEEE 754 (*Differences from IEEE 754*). It names `!(x >= 0.0)` as a NaN guard that the check does not see and that lets NaN through in Blink.
- **Index operands.** Blink has no index operator today. A change that adds one must decide whether an indexed operand such as `xs[i]` matches.

Suppress the warning on a function with `@allow(FloatSelfComparison)`, or set its level with `W0707 = "off"` or `W0707 = "error"` under `[lints]` (§4.16.8). A function-level `@allow` overrides `[lints]`. A module-scope `let` or `const` has no enclosing function, so only `[lints]` controls W0707 there.

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
| Never | -- | -- | -- | -- | -- | -- | Y | Y | Y | Y | Y | Y |

Y* = total ordering semantics. Unsigned types don't impl `Neg`. `Float` doesn't impl `Hash`. `Bytes` equality is byte-wise; `Bytes` has no `Ord`. `Never` has no values, so no method of its impls can run (§3.2).

`Option`, `Result`, `List`, `Set`, `Map` and tuples implement `Eq` when their parts do — see *Container Equality* below.

**`Option` and `Result` instances.** `Option[T]` and `Result[T, E]` have the instances that `@derive` gives a user sum type with the same variants, for `Eq`, `Ord`, `Clone` and `Debug`. The bounds are the ones that *Generic Type Bound Inference* (§3.6.1) infers: `Option[T]` has the instance when `T` does, and `Result[T, E]` has it when `T` and `E` both do. *Container Equality*, *Ord for `Option` and `Result`* (below), *Clone Semantics* (§3.6.1) and *Debug vs Display* (§3.6.1) state each instance. `Hash` is not one of them: no container has a `Hash` impl (*Hash Contract and Seeding*). This rule does not cover JSON. The JSON instances of `Option` and `Result` are in *Option and Result in JSON* (§3.6.2).

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

`Option` and `Result` are `Eq` as `@derive(Eq)` makes a user sum type with the same variants: the variants must match, and then the payloads must be `==`.

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

    let mut s1: Set[Int] = Set.new()
    s1.insert(1)
    s1.insert(2)
    let mut s2: Set[Int] = Set.new()
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

**Enums.** A **fieldless enum** (§3.4 *Tag Operations*: no variant has a payload, as the declaration is written) is `Eq` with no derive and no impl. Two of its values are `==` when they are the same variant. An enum with at least one payload is `Eq` only through `@derive(Eq)` or a written `impl Eq`, the same as a struct (vote: 6-0; see [Enum Equality rationale](../decisions/enum-equality.md)). The payload types alone never make an enum `Eq`. So `Option[Color]` is `Eq` for a fieldless `Color`, and `Option[Shape]` is not `Eq` until `Shape` has `@derive(Eq)` or an `impl Eq`.

```blink
type Color { Red  Green  Blue }

@derive(Eq)
type Shape { Circle(r: Int)  Sq(s: Int) }

fn main() {
    let c = Color.Red == Color.Green            // OK: fieldless, compares the variant
    let s = Shape.Circle(1) == Shape.Circle(1)              // OK: derived
    let o = Some(Color.Red) == Some(Color.Red)  // OK: `Option[Color]` is `Eq`
    io.println("{c} {s} {o}")                   // false true true
}
```

A derive on a data enum checks each payload by the rule above, and fails at the declaration when a payload type is not `Eq`:

```blink
type Widget { id: Int }

@derive(Eq)
type Bag { Items(xs: List[Widget])  Empty }     // error[NonDerivableTrait] (E1401): `Widget` does not implement `Eq`
```

- **No `impl Eq` on a fieldless enum.** A written `impl Eq for E`, where `E` is a fieldless enum, is a compile error. `E` already compares by variant. A second `Eq` could make two values `==` that are different variants. Then `==` would disagree with the tag comparison with `Int`, and a derived `Hash` would break the `Hash`/`Eq` coherence law (*Hash Contract and Seeding*). To compare in a different way, write a named method.
- **A redundant derive is legal.** `@derive(Eq)` on a fieldless enum is allowed, with no error and no warning. The compiler checks it as it checks any `@derive`.
- **The first payload.** When a fieldless enum gets its first payload variant, `==` on it is an error until the declaration has `@derive(Eq)` or an `impl Eq`.
- **Recursive types.** `@derive(Eq)` and `impl Eq` on a recursive type resolve coinductively: while the compiler checks the payloads, it assumes that the type is `Eq`. This applies to a type that contains itself (`type Tree { Leaf  Node(kids: List[Tree]) }`), to two or more types that contain each other, also across modules, and to a generic type such as `Tree[T]`, where the derive adds the bound `T: Eq` (§3.6.1 *Generic Type Bound Inference*).

**Enum Ord.** A fieldless enum is also `Ord` with no derive and no impl. Its order is declaration order: a variant declared earlier is less than a variant declared later (vote: 6-0; see [Enum Ord rationale](../decisions/enum-ord.md)). This is the real `Ord` instance, so `.cmp()` works, a `T: Ord` bound accepts the enum, a tuple that holds it is `Ord`, and `@derive(Ord)` accepts a field of its type. An enum with at least one payload is `Ord` only through `@derive(Ord)` or a written `impl Ord`, the same as a struct. The payload types alone never make an enum `Ord`. `<`, `<=`, `>`, `>=` or `.cmp()` on an enum that is not `Ord` is a compile error that names the missing `Ord`.

```blink
type Priority { Low  Medium  High }

@derive(Ord)
type Task { p: Priority  id: Int }                     // OK: `Priority` is `Ord`

type Shape { Circle(r: Int)  Sq(s: Int) }

fn biggest[T: Ord](a: T, b: T) -> T {
    if a > b { a } else { b }
}

fn main() {
    let top = biggest(Priority.Low, Priority.High)     // Priority.High
    let o = Priority.Medium.cmp(Priority.Low)          // Ordering.Greater
    let t = (Priority.Low, 9) < (Priority.High, 0)     // true
    let bad = Shape.Circle(1) < Shape.Circle(2)                    // error: `Shape` does not implement `Ord`
                                                       //   help: add `@derive(Ord)` to `Shape`
}
```

- **Two traits, from the declaration.** The declaration of a fieldless enum gives it `Eq` and `Ord`, as an implicit derive, while the enum is fieldless as written. It gives no other trait: `Hash`, `Display`, `Debug`, `Clone` and `Serialize` each still need a `@derive` or an `impl`. So `Set[Priority]` needs `@derive(Hash)` on `Priority`. An explicit `@derive(Eq)` or `@derive(Ord)` names the same instance. It is legal, with no error and no warning.
- **No `impl Ord` on a fieldless enum.** A written `impl Ord for E`, where `E` is a fieldless enum, is a compile error, as a written `impl Eq` is. A second order would make `<` on `E` disagree with the comparison with `Int` and with `to_int()`. One diagnostic code covers a written `impl Eq` and a written `impl Ord` on a fieldless enum. The message names the trait that the user wrote and gives the reason. A second label points at the `type` line, where the built-in instance comes from. The help gives the fix in one line: for a different `Eq`, a named method; for a different order, a named key method used with `sort_by` (*The `ListOps` Trait*, §3.2.2). The `blink explain` page for the code also gives the second fix: when a `T: Ord` bound must hold with a different order, wrap the enum in a struct that has its own `impl Ord`.
- **The order agrees with the tag.** For a fieldless enum `E` and any `a: E`, `b: E`: `a < b` exactly when `a.to_int() < b.to_int()`, and the same holds for `<=`, `>`, `>=` and for `a.cmp(b)` against `a.to_int().cmp(b.to_int())`. The compiler gives this guarantee, and no user code can break it, because no second order on `E` can be written. It does not apply to an enum with a payload, which has no `to_int()`.
- **Str-backed enums.** A Str-backed enum (§3.4 *Str-Backed Enums*) is fieldless, so its order is declaration order, not the order of its backing strings. To compare by the strings, compare `a.to_str()` and `b.to_str()`.
- **Generic fieldless enums.** `type Tag[T] { A  B }` is fieldless as written, so it is `Eq` and `Ord` with no bound on `T`.
- **The first payload.** When a fieldless enum gets its first payload variant, it loses the implicit `Eq` and `Ord` together. `==`, `<` and `.cmp()` on it are errors until the declaration has the derives or impls.

##### Ord for `Option` and `Result`

`Option[T]` is `Ord` when `T: Ord`. `Result[T, E]` is `Ord` when `T: Ord` and `E: Ord`. The order is the one that `@derive(Ord)` gives a user sum type with the same variants: compare the variant first, then the payload (*Sum Type Codegen (Enums)*, §3.6.1). In words:

- `None` is less than every `Some(_)`. Two `Some` values compare by their payloads.
- Every `Ok(_)` is less than every `Err(_)`. Two `Ok` values compare by their `T` payloads, and two `Err` values compare by their `E` payloads.

The declarations of `Result` and `Option` (§7.2, §7.3) list the variants in this order, so the declaration-order rule for fieldless enums (*Enum Ord* above) and the words above give the same result. `Result[T, E]` needs `E: Ord` also when a program compares only `Ok` values: the bound is on the types, not on the values. The order agrees with the `Eq` of *Container Equality*, so the *Ord laws* below hold.

A tuple, or a type with `@derive(Ord)`, that holds an `Option` or a `Result` is `Ord` when its other parts are. `List[T].sort()` accepts a `T` of `Int?` or `Result[Int, Str]`.

```blink
@derive(Ord)
type Row { id: Int, score: Int? }                  // OK: `Int?` is `Ord`

fn main() {
    let xs = [Some(3), None, Some(1)].sort()       // [None, Some(1), Some(3)]
    let a = None < Some(0)                         // true
    let b = Ok(9) < Err("x")                       // true
    let c = Err("a") < Err("b")                    // true: same variant, compare payloads
    let d = (Some(1), 0) < (Some(1), 5)            // true: a tuple of `Ord` parts is `Ord`
}
```

**Ord.** `Set` and `Map` never implement `Ord`: no order over them is canonical and agrees with membership equality. `Option` and `Result` are `Ord` as stated above, and are not part of this exclusion.

**Eq laws.** An `Eq` impl must be reflexive (`a == a`), symmetric (`a == b` implies `b == a`) and transitive (`a == b` and `b == c` imply `a == c`). The compiler and the container impls may rely on these laws, as `Map` and `Set` rely on the Hash coherence law. Every built-in `Eq` obeys the laws; `Float` obeys them because `NaN == NaN` (*Float Total Ordering*). If a user impl breaks a law, `==` on a container that holds that type returns an unspecified `Bool`. It stays memory-safe.

**Ord laws.** An `Ord` impl must be a total order that agrees with `Eq`:

- `a.cmp(b) == Ordering.Equal` exactly when `a == b`.
- `a.cmp(b) == Ordering.Less` exactly when `b.cmp(a) == Ordering.Greater`.
- If `a.cmp(b) == Ordering.Less` and `b.cmp(c) == Ordering.Less`, then `a.cmp(c) == Ordering.Less`.

A `sort_by` comparator need only be a **total preorder**. It obeys the second and third laws, and `cmp(a, a)` is `Ordering.Equal`, but it may return `Ordering.Equal` for two values that are not `==`. A comparator on one field, such as `fn(a, b) { a.age.cmp(b.age) }`, does this, and stability (*The `ListOps` Trait*, §3.2.2) keeps such elements in their input order. Every built-in `Ord` obeys the laws; `Float` obeys them because `NaN` sorts last (*Float Total Ordering*). If a user `Ord` impl or a comparator breaks a law, `sort` and `sort_by` still terminate. They return a permutation of the input, in which each element occurs exactly once, in an unspecified order. They stay memory-safe and do not panic.

**Cyclic data.** `List`, `Map` and `Set` are shared cells, so a value can contain itself (for example, through a struct field that holds the list that holds the struct). `==` on cyclic data may not terminate. The compiler adds no cycle guard.

**Diagnostic for a failed `Eq` check.** When `==`, `!=`, an `Eq` bound (for example `assert_eq`, E0306) or `@derive(Eq)` (E1401) fails on a type that has no `Eq`, the error names the **innermost** type argument that has no `Eq`, and the chain from the operand type to it. It offers **at least** these machine-applicable fixes (§8.6):

- `@derive(Eq)` on that type, when it is a user-declared `struct` or `enum`. For an enum with a payload, the error also notes that only fieldless enums are `Eq` with no `@derive(Eq)`, and the fix edits the enum's declaration.
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

`Int / Int` performs integer division (truncates toward zero). `Float / Float` performs IEEE 754 division. On every integer type, `a / b` and `a % b` panic when `b` is 0. The panic message contains `division by zero`. The rest of the message and the source location are not specified.

On every integer type, for a non-zero `b` (a zero `b` panics, as above), `a % b` is `a - b * q`, where `q` is the exact quotient of `a` and `b` truncated toward zero, and the arithmetic is on the mathematical integers. The remainder has the sign of `a`, or is 0, and its magnitude is less than the magnitude of `b`. So the remainder is always in the type's range, and `%` never overflows (§3.2, *Overflow behavior*). Where `a / b` does not panic, `a == (a / b) * b + a % b`.

For a signed type, `MIN / -1` panics, because the quotient `-MIN` is out of range. `MIN % -1` is 0.

```blink
let a: I32 = -2147483648
let b: I32 = -1
let r = a % b       // 0
let q = a / b       // RUNTIME PANIC: I32 overflow in division (-2147483648 / -1)
let s = -7 % 3      // -1: the sign of the dividend (Python gives 2)
let t = 7 % -3      // 1
let z = 0
let m = 7 % z       // RUNTIME PANIC: Int division by zero
```

`%` is not the floored modulo of Python. Code that needs a result in `0..n` for a negative `a` must adjust the remainder itself.

**A literal zero divisor.** Outside a const context (§2.21), a divisor that is known to be 0 is not a compile error: the expression compiles and panics at run time. In a const context it is `ConstEvalPanic` (§2.21, *Const Evaluation Must Succeed*).

When the divisor of an integer `/` or `%` is an integer literal with the value 0, the compiler gives the warning `DivisionByLiteralZero` (W0704). The literal can have parentheses around it and a unary `-` before it. The check reads only the divisor as written:

- A `const` reference or a `let` binding with the value 0 does not trigger it.
- It does no flow analysis, so it also fires in a branch that never runs.
- It does not fire inside the body of an `assert_panics` block (§2.20). This rule belongs to this warning and to `LiteralArithmeticOverflow` (W0708) only; other warnings fire in an `assert_panics` body as they do elsewhere.

```blink
let a = 10 / 0          // warning[DivisionByLiteralZero]; RUNTIME PANIC: Int division by zero
let b = 10 % (-0)       // warning[DivisionByLiteralZero]

const PER_PAGE = 0

fn pages(total: Int) -> Int {
    if PER_PAGE == 0 { return 0 }
    total / PER_PAGE    // no warning: the divisor is a const reference
}
```

Suppress the warning on a function with `@allow(DivisionByLiteralZero)`, or set its level with `W0704` under `[lints]` (§4.16.8).

**Literal arithmetic overflow.** Outside a const context (§2.21), an integer operation that always overflows is not a compile error, when its operands are only literals. The expression compiles and panics at run time, as every overflow does (§3.2, *Overflow behavior*). In a const context it is `ConstEvalPanic` (§2.21, *Const Evaluation Must Succeed*). The compiler gives the warning `LiteralArithmeticOverflow` (W0708) for the largest tree of integer literals, defined by `K`. A negative literal `N` (§3.2, *Integer literal range*) is matched first:

```
K ::= N | L | "(" K ")" | "-" K | K op K        op in { + - * / % }
```

This grammar is wider than the negative-literal rule in §3.2. There, `-(-5)` is a call to `Neg` and is not a negative literal. Here, a unary `-` over a tree is a node of the tree, so `-(-128)` at `I8` warns because `-MIN` is out of range. `-128` is a negative literal, a leaf, and E0318 governs it. Shifts `<<` and `>>` are not part of the tree.

The warning reads the tree as written. It checks each operation at the type that the checker gives it (§3.2, *Operator operands*). Whether a literal tree in operand position of a non-literal expression takes the type of the other operand is not decided here. The warning uses whatever type the checker gives each operation.

- A `const` reference or a `let` binding stops the tree, whatever its value.
- It does no flow analysis, so it also fires in a branch that never runs.
- It does not fire inside the body of an `assert_panics` block (§2.20). This rule belongs to this warning and to `DivisionByLiteralZero` only.
- It does not fire in a const context (§2.21). `ConstEvalPanic` reports the fault there.
- It gives one warning for each tree, at the first operation that fails, in evaluation order: the left operand, then the right operand, then the operator.
- A literal 0 divisor is `DivisionByLiteralZero` (W0704) only. `LiteralArithmeticOverflow` never reports it, and W0704 still fires when W0708 fires on the same tree.

```blink
let bad: I8 = 127 + 1           // warning[LiteralArithmeticOverflow]; RUNTIME PANIC: I8 overflow in addition
let c: U8 = 200 * 2             // warning[LiteralArithmeticOverflow]; RUNTIME PANIC: U8 overflow in multiplication
let n: I8 = -128                // ok: a negative literal, in range
let m: I8 = -(-128)             // warning[LiteralArithmeticOverflow]; RUNTIME PANIC: I8 overflow in negation
let d: I8 = (127 + 1) / 0       // warning[LiteralArithmeticOverflow] at 127 + 1; warning[DivisionByLiteralZero] at 0
let b: U8 = 300                 // error[IntLiteralOutOfRange] (E0318): the literal does not fit

const LIMIT: I8 = 127

fn next() -> I8 {
    LIMIT + 1                   // no warning: a const reference stops the tree
}

test "overflow panics" {
    assert_panics {
        let _: I8 = 127 + 1     // no warning inside assert_panics
    }
}
```

Suppress the warning on a function with `@allow(LiteralArithmeticOverflow)`, or set its level with `W0708` under `[lints]` (§4.16.8). To make it a build error, write `W0708 = "error"`.

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

#### Keyword Parameters in Impls

The trait method's declaration governs every call to the method. A call on a concrete receiver (`b.k(1)`), a call through a bound (`t.k(1)` with `T: Kw`) and a qualified call (`Kw.k(b, 1)`) all read the trait method's `*` marker, keyword names and defaults. One method has one call surface. Function types stay free of labels (§2.13): the rules below are a check on the impl's declaration, not on types.

An impl method repeats the marker position and the keyword names of the trait method:

- The impl has the same number of positional parameters before `*` as the trait. Positional parameter names are free, and only their types are checked.
- The keyword parameters after `*` have the same names in the same order as in the trait. The order is part of the rule because the function type has full arity: a different order gives a different function type.
- The impl writes no default on a keyword parameter. It inherits the trait's default on every call path, as it inherits the trait's `@requires` (E0912), even when its default has the same value as the trait's. A default that only the impl writes is the same error. To change a default, change the trait, or pass the argument at the call.

```blink
trait Kw {
    fn k(self, a: Int, *, d: Int = 1) -> Int
}

type Box { v: Int }
type Crate { v: Int }
type Jar { v: Int }
type Tin { v: Int }

impl Kw for Box {
    fn k(self, n: Int, *, d: Int) -> Int { n * d }   // OK: `n` may differ, `d` inherits `= 1`
}

impl Kw for Crate {
    fn k(self, a: Int, *, d: Int = 5) -> Int { a * d }   // E0915 -- `d` inherits `= 1` from `Kw.k`
}

impl Kw for Jar {
    fn k(self, *, a: Int, d: Int) -> Int { a * d }   // E0914 -- the trait puts `*` after `a`
}

impl Kw for Tin {
    fn k(self, a: Int, *, e: Int) -> Int { a * e }   // E0914 -- the trait names the keyword `d`
}

fn g[T: Kw](t: T) -> Int { t.k(1) }

fn main() {
    let b = Box { v: 0 }
    io.println("{b.k(1)} {g(b)} {Kw.k(b, 1)}")   // 1 1 1: the trait's default fills `d` on every path
}
```

`E0914 TraitContractKeywordMismatch` reports a marker that is missing, added or in another place, a keyword name that differs, and a keyword order that differs. Its `note:` points at the trait declaration and names the first part that differs. Its `help:` prints the expected impl header: the trait's parameter list, with no defaults. `E0915 TraitImplWritesDefault` reports a default written on a keyword parameter of a trait method. Its `note:` says that the impl inherits the trait's default, and names the value. Its `help:` says to delete the default, or to change the default in the trait. Each code owns a different part of the header, so one fault never gives two errors. When one impl method breaks both rules, E0914 comes first. The header that it prints has no defaults, so that one edit clears both errors (§3.1 rule 3).

A fix for a marker that is missing, added or moved is machine-applicable. So is a fix for keyword order. A fix for a renamed keyword is machine-applicable only when each impl name matches one trait name by position and the new name is free in the body. That fix renames the uses in the body too. Otherwise a rename gets a `help:` only. A fix for E0915 that deletes a default is machine-applicable when the default has the same value as the trait's. A default with another value, or a default that only the impl writes, gets a `help:` only, because the deletion changes the value that a call passes (§3.1 rule 1).

Hover and `blink query` on an impl method show the defaults that it inherits from the trait.

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

Coherence guarantees that for any (Trait, Type) pair, at most one implementation exists in the entire program. This invariant is essential -- trait dispatch must be deterministic.

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

The workaround for the orphan restriction is the **newtype pattern** (§3.4 *Newtypes*) -- wrap the foreign type in a local struct:

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

**Why no specialization.** Specialization requires a partial ordering on impls and interacts with type inference in subtle, unsound ways. Rust has kept specialization unstable for over a decade due to repeated soundness holes. Without specialization, adding a new impl to a library can never silently change which impl is selected for existing code -- it can only cause a new overlap error, which is loud and fixable. Each (Trait, Type) pair has exactly one impl.

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

A header may name the type or the trait with a module qualifier (§10.1 *Qualified Access*). This impl is the same impl, and the orphan rule tests the same type:

```blink
// src/formatting.bl
import models

impl Display for models.User {
    fn display(self) -> Str {
        "{self.name} ({self.email})"
    }
}
```

**Impl visibility.** No syntax imports an impl. For a method call `x.foo()` where `x: T`, two rules give the candidate impls:

1. **An impl in `T`'s package goes with the value.** An impl that lives in the package that defines `T` is a candidate at every call site where its trait is visible. The file does not import `T`, the trait, or any module for it. How the code got the value does not matter: a factory call, a field, a closure parameter and a generic return all give the same methods.
2. **Any other impl needs its trait in scope.** An impl that lives only in the trait's package is a candidate when the trait is in scope at the call site. A trait is in scope when the module declares it, when a selective import binds its name (`import ext.{Extra}`), when the prelude gives it (§10.6), or when it bounds the receiver's type parameter. A whole-module import (`import ext`) does not put the traits of `ext` in scope for method calls. The call `x.zap()` uses `zap` as a bare name, and only a selection binds a bare name (§10.1 *Qualified Access*). The qualified call `ext.Extra.zap(x)` works with `import ext`.

A trait is **visible** at a call site when the file can name it: the module declares it, or it is `pub` in a module the file can import (§10.2). Rule 1 applies only to a visible trait, so a private helper trait in `T`'s package gives `T` no methods outside the module that declares it. A bound counts as a trait in scope, so a generic body calls the methods of its bounds (§3c.4 *Resolution is fixed where the call is checked*).

```blink
// Package clockm, src/clockm.bl
pub type Ctl { ms: Int }

pub trait CtlOps {
    fn advance(self, ms: Int) -> Ctl
}

impl CtlOps for Ctl {
    fn advance(self, ms: Int) -> Ctl { Ctl { ms: self.ms + ms } }
}

pub fn make() -> Ctl { Ctl { ms: 0 } }

// Package ext, src/ext.bl. It depends on clockm.
import clockm.{Ctl}

pub trait Extra {
    fn zap(self) -> Int
}

impl Extra for Ctl {
    fn zap(self) -> Int { self.ms * 2 }
}

// Package app. It depends on clockm and ext.
import clockm.{make}
import ext.{Extra}

fn run() -> Int {
    let c = make().advance(10)    // OK: the CtlOps impl lives in Ctl's package
    c.zap()                       // OK: the selective import puts Extra in scope
}
```

With `import ext` in place of `import ext.{Extra}`, `c.zap()` is E0505. The error says that `import ext` does not bring trait methods into method-call scope, and its fix changes the line to `import ext.{Extra}` (§3c.4 *Trait Method Lookup*).

**An impl header does not put its trait in scope.** Naming a trait in an impl header, bare or qualified, does not put it in scope. An impl body gets no special treatment (§3c.4 *Built-in Type Method Dispatch*). In `impl lib.Tr for ext.Pt` with `import lib`, a call `self.other()` to another method of `Tr` is E0505, the same as in any other function. To repair it, select the trait with `import lib.{Tr}`, or write the qualified call `lib.Tr.other(self)`.

The impls in `T`'s package are fixed by the contents of that package, at the version the build uses. They never depend on which modules the build loaded. An import in another file, or a module that some dependency loads, adds no candidates to this file. The same holds for rule 2: only this file's own declarations and imports put a trait in scope.

**A type's package may grow.** A release of `T`'s package can add an impl whose method name is the same as a method of a trait that a caller imports. The caller's unqualified calls with that name then become E0522, with no change to the caller's file. This is a breaking change for the package that adds the impl, and the E0522 help gives the qualified call for each owner. The program never changes what it does without a diagnostic.

**Why the type's package.** The code that a reader expects to work does work: a value from `udp_bind(addr)?` has the socket methods, and the file imports only `udp_bind`. A call's methods depend on two things: the receiver's type and this file's text. The package is also the unit of the orphan rule, so a library can move an impl from one of its files to another and no caller changes. An impl from another package is an extension, and the file opts in to it by name, as with extension methods in Kotlin and C#. Because a whole-module import does not enable method calls, each import shows its effect in the file text: a file that has `import ext` and no `ext.` does not use that import.

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

**An impl proves each supertrait under its own bounds.** An impl of a trait with supertraits (`Ord: Eq`, `Hash: Eq`) must show that its receiver type implements each supertrait. The impl may use only the bounds it writes, in the binder or in a `where` clause, and the supertraits of those bounds: `T: Ord` gives `T: Eq`. An impl that cannot show a supertrait is `error[MissingSupertraitImpl]` (E0911) at the impl header. A concrete impl is the case with no binder. The check runs once, at the impl. No use site checks it again.

```blink
type H[T] { v: T }

impl[T: Eq] Eq for H[T] { fn eq(self, o: H[T]) -> Bool { self.v == o.v } }

impl[T] Ord for H[T] { ... }         // E0911 -- H[T] is Eq only where T: Eq
impl[T: Eq] Ord for H[T] { ... }     // OK
impl[T: Ord] Ord for H[T] { ... }    // OK -- T: Ord gives T: Eq
```

(The three `Ord` impls are alternatives. A program has one.)

```
error[MissingSupertraitImpl]: impl Ord for H[T] requires H[T] to also implement supertrait `Eq` (trait Ord: Eq)
 --> h.bl:5:6
  |
5 | impl[T] Ord for H[T] { ... }
  |      ^ `H[T]` is `Eq` only where `T: Eq`
  |
  = help: add the bound: `impl[T: Eq] Ord for H[T]`
```

The help is machine-applicable. It adds only the bounds that the impl's own bounds do not already give, in the form the impl already uses: `: Eq` after a bare parameter, ` + Eq` on a bound list, or an item in the `where` clause. If the receiver type has no impl of the supertrait at all, the help is to derive it or to write it (`@derive(Eq)` on the type, or a hand-written `impl Eq`).

**No implied bounds.** The compiler never adds a bound that the user did not write. `impl[T] Ord for H[T]` does not mean `impl[T: Eq] Ord for H[T]`. A polymorphic impl varies behavior only through the bounds it writes.

**A derived supertrait impl.** The supertrait impl can come from `@derive`. The rule, the code, the message and the help are the same as for a hand-written pair, and a label or note points at the `@derive(...)` attribute. With `@derive(Eq)` on `H[T]`, the hand-written `impl[T] Ord for H[T]` is E0911, and the help is `impl[T: Eq] Ord for H[T]`. For the bounds of a derived impl, see *Supertrait Auto-Derivation*.

This rule makes the claim in *Operations on `Self` in a Default Body* true for a polymorphic impl. A generic function with `T: Loud` can call a method of `Named` on `T` (`trait Loud: Named`), because every impl of `Loud` proved `Named` under its own bounds.

**Instantiations.** Each distinct instantiation (`List[Int]`, `List[Str]`, `List[User]`, etc.) is a distinct type.

**No runtime type information.** Blink exposes no `size_of[T]`, `is_pointer_kind[T]`, `TypeRepr[T]`, `align_of[T]`, or `TypeId[T]` forms — neither to user code nor as `@compiler_internal` primitives.

**Parametricity (normative).** Any generic body (a generic function, a polymorphic impl, or a trait default body) must be **parametric in its type parameters**. The body may not:

- **Dispatch on `T`'s identity.** `if T == Int { ... }`, `match T { ... }`, and equivalent constructs are compile errors.
- **Inspect `T`'s runtime layout, size, alignment, or pointer-kind.** No `sizeof`-like form exists in the source language for type parameters.
- **Call any function that exposes `T`'s runtime shape.** This rules out reading `T` from any reflective API.
- **Read or write a field of `T`.** A type parameter declares no fields, and a bound adds only methods: `error[NoSuchField]` (E0525).

The **only legal way** for a polymorphic impl body to vary behavior based on `T` is to introduce a trait bound and call a method on that bound. `(x: T).display()` is permitted when `T: Display` — it resolves to the bound type's `Display` impl.

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

**Why parametricity is normative.** Parametricity is the *language guarantee* user code is allowed to assume about `T`. User code may rely on the bounds of `T` and on nothing else. Without the rule, the first `@trusted` block or FFI shim that peeks at `T` has no principled rejection.

**Interaction with coherence.** Polymorphic impls follow the same orphan, overlap, and placement rules as concrete impls. `impl[T] Trait for BuiltinGeneric[T] where T: Bound` and `impl Trait for BuiltinGeneric[Int]` overlap (because `Int` satisfies any reasonable `Bound`), and the program is rejected with `error[OverlappingImpls]` — Blink does not specialize. See [Trait Coherence](#trait-coherence) above for the full rules. See [polymorphic-builtin-generic-impls](../decisions/polymorphic-builtin-generic-impls.md) for the panel rationale.

---

#### Compiler-Known Traits

Certain traits have special meaning to the compiler. They are defined in the standard library but the compiler understands their semantics and can generate or enforce behavior based on them.

| Trait | Compiler behavior |
|-------|------------------|
| `Eq` | Enables `==` and `!=` operators. `@derive(Eq)` auto-generates structural equality. |
| `Ord` | Enables `<`, `>`, `<=`, `>=` and `cmp`. Requires `Eq`. |
| `Hash` | Enables use as `Map` key or `Set` element. Requires `Eq`. |
| `Clone` | Logical copy. `@derive(Clone)` auto-generates the same value as a copy on bind (§3.6.1 *Clone Semantics*). |
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
| `Closeable` | Signals non-memory resources needing deterministic cleanup. Enables `with...as` scoped resource blocks. A `Closeable` type also implements `Scoped` (§4.7.2). |
| `Scoped` | Enter and exit around a block. Enables `with` on a scoped value (§4.7.2). Every `Closeable` type implements it, with `Context = Self`. |
| `Iterator` | Enables `for`-loop iteration, lazy adapter methods (`.map()`, `.filter()`, etc.), and `.collect()` materialization. |
| `IntoIterator` | Enables a type to be used in `for x in expr`. Collections implement this to produce an `Iterator`. |

The `Closeable` trait is the simplest:

```blink
trait Closeable {
    fn close(self) ! _
}
```

The row `! _` means that each impl declares the effects of its own `close` (§4.15.2).

A type implementing `Closeable` holds resources (file handles, sockets, locks, database cursors) that must be released deterministically — not at some later, unspecified time, but at a specific point in the program. The `with...as` construct (section 2.18, section 5.5) guarantees `close()` is called on all exit paths.

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

The compiler uses `Closeable` to power the ScopedValueWithoutWith lint (warn when a `Scoped` value, `Closeable` types included, does not go into a `with`) and errors E0601/E0602 (closeable escapes scope). See section 5.5 for the full mechanism.

#### §3.6.1 Derive Mechanics

The `@derive` annotation (§11.1) instructs the compiler to auto-generate trait implementations. Seven traits are derivable in v1: `Eq`, `Ord`, `Hash`, `Clone`, `Debug`, `Serialize`, `Deserialize`. `Display` is not derivable: a type's user-facing text is a design choice, not a function of its structure. Write an `impl Display`, or use `Debug` for the structural form. `@derive(Display)` is E1402 `NotDerivable`.

The argument of `@derive` is a name that the user writes, so it resolves by scope. When it does not denote one of these seven compiler-known traits by identity, the compiler reports E1402 `NotDerivable`. In a module that shadows `Eq`, `@derive(Eq)` names the local trait and is E1402. `import blink.core.{Eq as CoreEq}` and `@derive(CoreEq)` derive the compiler-known trait (§10.6 *Shadowing a Prelude Trait*).

##### Derivable Trait Declarations

For reference, the seven derivable traits and their required methods:

| Trait | Method | Supertrait |
|-------|--------|------------|
| `Eq` | `fn eq(self, other: Self) -> Bool` | — |
| `Ord` | `fn cmp(self, other: Self) -> Ordering` | `Eq` |
| `Hash` | `fn hash(self) -> U64` | `Eq` |
| `Clone` | `fn clone(self) -> Self` | — |
| `Debug` | `fn debug(self) -> Str` | — |
| `Serialize` | `fn to_json(self) -> JsonValue` | — |
| `Deserialize` | `fn from_json(json: JsonValue) -> Result[Self, JsonError]` | — |

##### Clone Semantics

`clone()` on a struct or enum equals a copy on bind. Shared cells (§3.6 *Shared cells*) stay shared; a clone does not copy their contents. `Clone` exists so generic code with a `T: Clone` bound can copy a value.

- **Value types** (`Int`, `Float`, `Bool`, `Char`, `Str`): a copy of the value. A `Str` cannot change, so no program can see whether a copy shares its bytes.
- **`Bytes`**: a copy of the value. A write through the clone does not show in the original.
- **`List`, `Map`, `Set` and other shared cells** (§3.6 *Shared cells*): the clone refers to the same cell. A change made through the clone **does** show in the original — the same as JS spread (`{...obj}`) or Python `copy.copy()`.
- **`Option` and `Result`**: `Option[T]` is `Clone` when `T: Clone`, and `Result[T, E]` is `Clone` when `T: Clone` and `E: Clone`. The clone has the same variant as the original, and the payload is copied by the `clone` of its own type, so a written `impl Clone` on the payload type runs. When the payload's `clone` gives the same value as `let y = x` (every built-in type and every derived `Clone`), so does the clone of the `Option` or `Result`: a shared cell inside stays shared (the bullet above). It is not a deep copy.
- **User structs and enums**: `x.clone()` gives the same value as `let y = x`. Each field is copied by its declared type, using the rules above. A field whose declared type is a struct or enum is a value, and its copy is a value too (for example, a payload of the enum's own type, §3.4 *Recursive Types*).

**A write to a place stays in its value.** A write to a place (§2.22) changes only the value that owns that place, even when that value is a copy of another value. Only a shared cell (§3.6 *Shared cells*) or a synchronized object (§3.6 *Synchronized objects*) can change through a second name.

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

```blink
fn keep(r: Result[List[Int], Str]) -> (Result[List[Int], Str], Result[List[Int], Str]) {
    let c = r.clone()      // same value as `let c = r`; the `List` cell stays shared
    (r, c)
}
```

Deep clone is not provided in v1: no function or method makes a deep copy. `ch.send` copies the shared cells a value reaches, but only as part of the send (§4.13 *Shared cells cross a channel as copies*). A `DeepClone` trait can be added post-v1 for use cases requiring full structural independence.

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
Rendering* below. `Option` and `Result` have the `Debug` that `@derive(Debug)` gives a user sum type
with the same variants (*Option and Result instances*, §3.6): `Some(42)`, `None`, `Ok(42)`,
`Err("io")`.

**Debug agrees with Eq.** For a type that is both `Eq` and `Debug`, `a == b` must give
`a.debug() == b.debug()`. This is a contract of the same kind as `Hash` agreeing with `Eq` (*Hash
Contract and Seeding*); the compiler does not check it. A derived `Debug` obeys it when the type's
`Eq` is also derived. A hand-written `impl` of either trait must keep the two in agreement. This type
breaks the law, because its `Eq` ignores case but its derived `Debug` does not:

```blink
@derive(Debug)
type Tag { name: Str }

impl Eq for Tag {
    fn eq(self, other: Self) -> Bool {
        self.name.to_lower() == other.name.to_lower()
    }
}

// Tag { name: "Bob" } == Tag { name: "bob" } is true,
// but their debug() texts differ
```

The `Set` and `Map` debug order (*Container Debug Rendering*) depends on this law: when it holds for
the elements, keys and values, equal containers render the same text. Every built-in type obeys the
law. `Float` renders `-0.0` as `0.0` and every NaN as `NaN` (§3.6 *Float Text Form*), so two
`Float` values that `==` calls equal render the same text.

`Result.unwrap` and `Result.unwrap_err` also require `Debug` on the arm they panic on, and their
panic text ends with that payload's `debug()` (§7.5). A change to a type's `Debug` format therefore
also changes that panic text.

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

**`fmt` (push, required).** Pushes the rendered representation into a caller-provided `StringBuilder`. Recursive impls call `child.fmt(sb)` into the *same* builder, giving O(n) composition:

```blink
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

| Shape | When to use |
|-------|-------------|
| `"{x}"` interpolation | Building a Str literal |
| `x.display()` | Need a Str directly |
| `sb.write(x)` | Building into a builder you already own |

All three call `x.fmt(sb)`. They cannot disagree.

**`fmt` has no effect row.** `Display.fmt` declares no `!`, and that empty row is its contract. A function with no `!` performs no side effects (§4.1), and no impl may widen a trait method's row (§3.6 *Effect-row subtype for trait impls*). So no `fmt` impl can perform IO or use any other capability, and `"{x}"`, `x.display()` and `sb.write(x)` never need an effect or a handler in scope. An impl whose `fmt` declares an effect is rejected with `TraitContractEffectMismatch` (E0904). Writing into the supplied `sb` is not an effect: it mutates a parameter, which neither the effect row nor mutation analysis tracks (§4.16.2). Module state is in the effect row too: a `fmt` that reads or writes a module-level `let mut` binding has `State` in its effective row, so it is also E0904 (§4.16.6). There is no `StringBuilderPure` effect; `fmt(self, sb: StringBuilder) ! StringBuilderPure` names an undeclared effect.

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
   = help: implement `Display` for `Matrix` with an `impl Display for Matrix` block
   = note: use `matrix.debug()` for structural representation
```

Built-in types (`Int`, `Float`, `Bool`, `Str`, `Char`) have compiler-provided `Display` implementations. User types require an `impl Display for T` block; `Display` is not derivable (§3.6.1). There is no fallback to `Debug` and no auto-synthesis — the trait bound is checked like any other.

**Built-in `Display` impls.** The five impls for `Str`, `Int`, `Float`, `Bool` and `Char` are built in, and the list is closed: every other `Display` impl, including every derived one, writes through `sb.write`, `sb.write_char` or a child's `fmt`. `Str.fmt` appends the receiver's bytes to the builder. `Str.display()` returns a `Str` equal to the receiver.

**A scalar renders to `Str` only through `Display`.** To get a `Str` from an `Int`, `Float` or `Bool`, write `"{x}"` when the value is part of a larger string, and `x.display()` when you need the `Str` value alone. These types have no `to_str` and no `to_string` method. Rendering is not a conversion: a scalar has a `to_` method only as sugar over a `From` or `TryFrom` impl (§3c.3), and no `From[Int] for Str`, `From[Float] for Str` or `From[Bool] for Str` exists. `Char` has `to_str` because `From[Char] for Str` exists (§3c.3 *Char → Str*). Two methods give a different text form of a number: `Float.display_fixed` and `Int.display_zero_padded` (*Fixed-Decimal and Zero-Padded Forms*).

```blink
let n = 42
let s = n.display()                         // "42"
let line = "port {n}"                       // "port 42"
let names = [80, 443].map(fn(p) { p.display() })
```

A call to `to_str`, `to_string` or `toString` on one of these types is `UnresolvedMethod` (E0505). The help line names `display()` and interpolation, and the diagnostic carries a machine-applicable fix that replaces the method name with `display`. The type and the output stay the same:

```
error[E0505]: unresolved method `.to_string` on type Int
  --> src/server.bl:41:22
   |
41 |     let s = port.to_string()
   |                  ^^^^^^^^^
   = help: a number becomes a `Str` with `.display()`, or with `"{port}"` inside a larger string
   = fix: replace `.to_string()` with `.display()`
```

**Foreign spellings of the text helpers.** Where a common spelling from another language differs from the Blink method, the compiler gives a help line that names the Blink method. It is a hint only: the foreign name is never an alias, and the call stays an error. An unknown method name is `UnresolvedMethod` (E0505); a call that resolves but has the wrong arguments or result type is a type mismatch. (Panel vote: 5-1, Minimalism dissented.)

| Written | Help names |
|---------|------------|
| `x.to_fixed(n)`, `x.toFixed(n)`, `x.fixed(n)` on `Float` | `x.display_fixed(n)` |
| `x.round(n)` on `Float` | `x.display_fixed(n)` for text, or `x.round()` |
| `x.round()` where an `Int` is expected | `x.round().truncate()` |
| `c.is_digit(10)`, `c.is_digit()` on `Char` | `c.is_ascii_digit()`, or `c.to_digit(10)` |
| `c.is_alpha()`, `c.is_alphanumeric()`, `c.is_upper()`, `c.is_lower()` on `Char` | the `is_ascii_*` method of the same class |
| `s.is_ascii()` on `Str` | `c.is_ascii()` on each `Char` |
| `s.strip()`, `s.lstrip()`, `s.rstrip()` | `s.trim()`, `s.trim_start()`, `s.trim_end()` |
| `s.trim_left()`, `s.trim_right()` | `s.trim_start()`, `s.trim_end()` |
| `s.trim_matches(..)`, `s.trim_start_matches(..)`, `s.trim_end_matches(..)` | `s.trim_by(..)`, `s.trim_start_by(..)`, `s.trim_end_by(..)` with a `fn(Char) -> Bool` |
| `s.rjust(w)`, `s.padStart(w)`, `s.pad_left(w, c)` | `s.pad_start(w, ' ')` (or the given fill) |
| `s.ljust(w)`, `s.padEnd(w)`, `s.pad_right(w, c)` | `s.pad_end(w, ' ')` (or the given fill) |

**Every Display sink uses the same bound.** `"{x}"`, `x.display()`, `sb.write(x)` (§3.2 *String Building*) and the `io` print functions (§4.4) each require `T: Display` and nothing else. A `Str` argument is one `Display` type among five; it takes no separate path in the type system. A value that fails the bound at any of these sinks, or at any other call whose type parameter is bounded by `Display`, gets the same `MissingDisplayImpl` (E0523) error. The message names the sink and the span covers the argument:

```
error[E0523]: type `Matrix` does not implement `Display`
  --> app.bl:14:14
   |
14 |     sb.write(matrix)
   |              ^^^^^^ `Matrix` does not implement `Display`, which `StringBuilder.write` requires
   |
   = help: implement `Display` for `Matrix` with an `impl Display for Matrix` block
   = note: use `matrix.debug()` for structural representation
```

A `Raw[Str]` argument is the one exception: it reports `RawOutsideTemplate` (§3b.5 *`Raw(expr)` — The Escape Hatch*), not E0523.

**Typing rule.** The compiler checks `T: Display` for every `{expr}`. This is a standard trait bound check — identical to requiring `T: Eq` for equality comparison.

Example:

```blink
let name = "Alice"
let age = 30
let msg = "hello {name}, you are {age} years old"

// Type check: Str: Display ✓, Int: Display ✓
```

```blink
type Point { x: Float, y: Float }

impl Display for Point {
    fn fmt(self, mut sb: StringBuilder) {
        sb.write("(")
        sb.write(self.x)
        sb.write(", ")
        sb.write(self.y)
        sb.write(")")
    }
}

let p = Point { x: 1.0, y: 2.5 }
let msg = "at {p}"

// Type check: Point: Display ✓ (via impl)
// msg is "at (1.0, 2.5)"
```

**Template literals: Display not invoked.** In a template literal `t"..."` (§2.4.3, §3b.5), interpolation has different semantics — `{expr}` is decomposed into the `values` list as a typed value, not concatenated via Display. Display is **not** invoked in a template literal:

```blink
let id = 42
let name = "Alice"

// Plain literal, a Str — Display invoked:
let msg = "user {id}: {name}"           // "user 42: Alice"

// Template literal — Display NOT invoked:
let q: Template[DB] = t"SELECT * FROM users WHERE id = {id} AND name = {name}"
// q.parts()  == ["SELECT * FROM users WHERE id = ", " AND name = ", ""]
// q.values() == [TemplateValue.Int(42), TemplateValue.Str("Alice")]   ← typed values, not strings
```

The set of types valid as Template values is compiler-known: `Int` and the narrower integers `I8`, `I16`, `I32`, `U8`, `U16`, `U32` (widened to `Int`), `Float` and `F32` (widened to `Float`), `Bool`, `Str`, `Bytes`, and `Option[T]` where `T` is one of these (`None` becomes `TemplateValue.Null`). `Option[Option[T]]` is not valid. Any other type in a Template interpolation is `error[TemplateHoleType]` at typecheck, with repairs that keep the value a parameter (§3b.5 *Template Values*). The `Raw(s)` marker type, which wraps only a `Str`, bypasses decomposition for a specific interpolation (see §3b.5).

This separation is critical: calling `Display.display()` first and then decomposing the resulting `Str` would defeat `Template[C]`'s injection safety by losing type information and forcing all values through string round-tripping.

##### Float Text Form

`Float.display()` returns the text below, and `Float.debug()` returns the same text (§3.6.1 *Scalar debug-forms*). The spec fixes the output, not the algorithm. Ryu, Schubfach and Dragonbox all compute these digits.

1. **NaN.** Every NaN renders as `NaN`. The text does not show the sign or the payload bits.
2. **Infinity.** Positive infinity renders as `inf`, and negative infinity renders as `-inf`.
3. **Zero.** `0.0` and `-0.0` both render as `0.0`.
4. **Digits.** For any other finite `x`, choose digits d₁…dₙ (d₁ ≠ 0, dₙ ≠ 0) and an integer k so that the decimal value is d₁.d₂…dₙ × 10ᵏ:
   - n is the smallest count for which an n-digit decimal converts back to `x` under IEEE 754 binary64 round-to-nearest, ties-to-even.
   - If more than one n-digit decimal converts back to `x`, take the one nearest the exact value of `x`.
   - If two are equally near, take the one whose last digit is even.
5. **Layout.** Write `-` first when `x < 0`. Then:
   - When −4 ≤ k < 16, write the digits in plain form, with the decimal point placed by k. Add zeros so there is at least one digit on each side of `.`. Write no trailing zeros after `.`, except the one `0` that an integer value needs (`1.0`, `100.0`).
   - When k < −4 or k ≥ 16, write d₁, then `.`, then d₂…dₙ (or `0` when n is 1), then `e`, then `-` when k < 0, then the magnitude of k in decimal. The exponent has no `+` and no leading zeros (`1.0e16`, `1.5e-7`, `5.0e-324`).
6. **Fixed characters.** The decimal mark is always `.`, and the text has no digit grouping. The output depends on neither the locale nor the C library.

Every finite output matches `-? DIGITS '.' DIGITS ('e' '-'? DIGITS)?`. It always contains `.`, so a `Float` never renders as text that reads as an `Int`. This keeps `[1.0, 2.0].debug()` apart from `[1, 2].debug()`, and keeps a `Float` written as a JSON number a `JsonValue.Float` when `json.parse` reads it back (§3.6.2).

```blink
fn main() {
    let big = 10000000000000000.0
    let tiny = 0.00001
    io.println(0.1.display())                // 0.1
    io.println((0.1 + 0.2).display())        // 0.30000000000000004
    io.println(1.0.display())                // 1.0
    io.println((1.0 / 3.0).display())        // 0.3333333333333333
    io.println(123456789.0.display())        // 123456789.0
    io.println(9007199254740993.0.display()) // 9007199254740992.0
    io.println(big.display())                // 1.0e16
    io.println(0.0001.display())             // 0.0001
    io.println(tiny.display())               // 1.0e-5
    io.println((-0.0).display())             // 0.0
    io.println((0.0 / 0.0).display())        // NaN
    io.println((-1.0 / 0.0).display())       // -inf
    io.println([1.0, 2.5].debug())           // [1.0, 2.5]
}
```

**Laws.** For all `x` and `y` of type `Float`:

- **Round trip.** `x.display().parse_float() == Ok(x)`, with `==` as in *Float Total Ordering*. This holds for NaN and for `-0.0` too.
- **One text per value.** `x == y` exactly when `x.display() == y.display()`.

The text does not show the sign of zero or the bits of a NaN, because no `Float` equality tells those values apart. To read them, use `x.is_sign_negative()` and `x.to_bits()` (*Built-in Float Methods*).

**One form everywhere.** Every place that Blink, its standard library or the `blink` toolchain writes a finite `Float` as decimal text uses this form, unless this spec names a different form for that place. Such places include `display()`, `debug()`, string interpolation, power-assert values (§2.20), JSON number output (§3.6.2) and test-runner output (§8.10). `Float.display_fixed` is a named different form (*Fixed-Decimal and Zero-Padded Forms*). A form that is not decimal text, such as a bit pattern, is outside this rule. JSON writes NaN and the infinities as `null` (§3.6.2 *NaN and Infinity*), so this rule covers only its finite numbers.

**F32.** Whenever an `F32` renders as text, it uses the same rules, with the digits chosen for IEEE 754 binary32 in place of binary64. An `F32` that holds `0.1` renders as `0.1`. The same value widened to `Float` renders as `0.10000000149011612`, because it is a different `Float`. This rule does not add `F32` to the built-in `Display` impls.

##### Fixed-Decimal and Zero-Padded Forms

Two methods render a number in a form other than `display()`. Each is a named form in the sense of *One form everywhere*. Neither is a `Display` impl, and string interpolation never uses them; interpolation has no format specs. Write the call inside the hole: `"{price.display_fixed(2)}"`.

**`Float.display_fixed(self, digits: Int) -> Str`** writes `self` with exactly `digits` digits after the decimal point. The output does not depend on the locale or the C library (Rule 6 of *Float Text Form*), so an implementation computes the digits exactly and does not call the host `printf`.

1. **NaN and infinity.** NaN, `inf` and `-inf` render as `display()` renders them (Rules 1 and 2), whatever `digits` is.
2. **Rounding.** For a finite `x`, take the exact value of the binary64 `x` and round it to `digits` places after the decimal point. When the exact value is exactly halfway between two candidates, take the one whose last digit is even. The rounding acts on the stored value, not on the literal: `2.675` is stored as 2.67499999999999982236431605997495353221893310546875, so it renders as `"2.67"` with 2 digits.
3. **Sign.** Write `-` first only when `x < 0` and the rounded text has at least one non-zero digit. `-0.0`, and a negative value that rounds to all zeros, render with no sign.
4. **Layout.** Write the integer part in decimal with no leading zeros (a single `0` when it is zero) and no digit grouping. When `digits > 0`, write `.` and then exactly `digits` digits, trailing zeros included. When `digits == 0`, write no `.`. The output never uses exponent form.
5. **Range of `digits`.** `digits < 0` panics. There is no upper bound: a large `digits` writes the exact decimal expansion of the stored value, then zeros.

```blink
fn main() {
    let big = 1000000000000000000000.0
    io.println(3.14159.display_fixed(2))     // 3.14
    io.println(2.675.display_fixed(2))       // 2.67
    io.println(0.125.display_fixed(2))       // 0.12 (exact tie, to even)
    io.println(0.375.display_fixed(2))       // 0.38 (exact tie, to even)
    io.println(2.5.display_fixed(0))         // 2
    io.println(1.0.display_fixed(3))         // 1.000
    io.println((-0.001).display_fixed(2))    // 0.00
    io.println((-0.006).display_fixed(2))    // -0.01
    io.println(big.display())                // 1.0e21
    io.println(big.display_fixed(0))         // 1000000000000000000000
    io.println(0.1.display_fixed(20))        // 0.10000000000000000555
    io.println((0.0 / 0.0).display_fixed(2)) // NaN
}
```

`display_fixed` breaks a tie toward the even digit, and `Float.round` (§3.2.5) breaks a tie away from zero, so the two can differ on an exact tie: `2.5.display_fixed(0)` is `"2"`, while `2.5.round()` is `3.0`. `display_fixed` uses the same tie rule as C `%.*f`, Rust `{:.N}` and Python `f"{x:.Nf}"`, so it gives the same digits as those for every value; only Rule 3 (no sign on an all-zero result) differs from them. (Panel votes: name 6-0; tie rule 5-1, PLT dissented wanting ties away from zero; sign rule 6-0; `digits` rules 6-0.)

**`Int.display_zero_padded(self, width: Int) -> Str`** writes `self` in decimal with zeros between the sign and the digits, so the result has `width` characters. `width` counts the sign. The method never truncates: when `self.display().len() >= width`, a negative `width` included, the result is `self.display()`.

```blink
42.display_zero_padded(5)       // "00042"
(-7).display_zero_padded(3)     // "-07"
12345.display_zero_padded(3)    // "12345"
0.display_zero_padded(2)        // "00"
```

Compare `"-7".pad_start(3, '0')`, which gives `"0-7"` (§3.2.1 *Trim, Strip, Pad and Repeat*). (Panel vote: method 4-2, Web/Scripting and Minimalism dissented wanting no method; name 6-0.)

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
| `Hash` | Hash of all fields; equal values give equal hashes |
| `Clone` | `Type { f1: self.f1, f2: self.f2, ... }`: the same value as a copy on bind (§3.6.1 *Clone Semantics*) |
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
| `Hash` | Hash of the variant and the fields of data-carrying variants; equal values give equal hashes |
| `Clone` | The same value as a copy on bind (§3.6.1 *Clone Semantics*) |
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
| `Map[K,V]` | `"{" + entries.join(", ") + "}"`, each entry `key.debug() + ": " + value.debug()`, in sorted order (below) | `"{}"` |
| `Set[T]` | `"{" + elems.join(", ") + "}"`, each elem via its own `.debug()`, in sorted order (below) | `"{}"` |
| `Result[T,E]` | `"Ok(" + value.debug() + ")"` or `"Err(" + error.debug() + ")"` | — |
| tuple | `"(" + elems.join(", ") + ")"`, each elem via its own `.debug()` | — |

**Set and Map order.** `Set[T].debug()` sorts the rendered element strings by their UTF-8 bytes
before it joins them. `Map[K,V].debug()` sorts its entries by the UTF-8 bytes of `key.debug()`; when
two keys render the same text, it sorts those entries by the UTF-8 bytes of `value.debug()`.
`debug()` sorts so that `==` maps print the same text; their iteration order can differ (see
*Container Equality* and *Hash Contract and Seeding*, §3.6; *Debug agrees with Eq*, §3.6.1). Sorting by the debug string needs no `Ord` bound. The order is by
text, not by value: a `Set[Int]` of 1, 2 and 10 renders `{1, 10, 2}`, and a `Map[Int, Str]` that
maps 1 to `"a"`, 2 to `"b"` and 10 to `"c"` renders `{1: "a", 10: "c", 2: "b"}`. Only `debug()` sorts; `keys()`,
`values()` and `for` loops keep iteration order. An empty `Set` renders `{}`, the same text as an
empty `Map`; the static type tells them apart.

```blink
@derive(Debug)
type Inventory { items: List[Str], count: Option[Int], tags: Map[Str, Int] }

let mut tags: Map[Str, Int] = Map.new()
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
elements are excluded.) Outside a derive, the same shape fails a `T: Debug` bound
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

The rule is fully inductive. The typechecker recurses to prove every nested element / key / value
type is `Debug` (rejecting non-Debug types and container map keys or set elements at any level).
There is no depth cap, so an arbitrarily deep type renders, with no silent fallback at any level. See
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

1. If the supertrait is derived (in the same or an earlier `@derive`), use that derived implementation
2. If the supertrait is not implemented, the compiler auto-derives it
3. If the type has a hand-written `impl Eq`, deriving `Ord` or `Hash` is an error, `DeriveOverHandWrittenEq`

This means `@derive(Ord)` implicitly derives `Eq` if not already present. Rule 3 exists because a hand-written `Eq` is usually coarser than the structure, so a structural `Hash` or `Ord` would break the laws in *Derive Laws* below, and a `Map` or `Set` keyed on the type would give wrong results with no error. The diagnostic gives two fixes: derive `Eq` in place of the hand-written impl, or write `Hash` (or `Ord`) by hand so that it agrees with the hand-written `Eq`. The supertrait is the compiler-known `Eq` by identity, also in a module that shadows `Eq` (§10.6 *Shadowing a Prelude Trait*). Redundant listing like `@derive(Eq, Ord)` is allowed — no error, no warning. The `Eq` derivation happens once regardless.

The `Eq` that `@derive(Ord)` or `@derive(Hash)` adds carries the bounds that `@derive(Eq)` would carry (*Generic Type Bound Inference*), whether the derives are in one `@derive` attribute or in more than one. For `type H[T] { v: T }`, the added `Eq` is `impl[T: Eq] Eq for H[T]`, and `@derive(Ord)` gives `impl[T: Ord] Ord for H[T]`. The bound `T: Ord` gives `T: Eq`, so the pair meets the supertrait rule in *Polymorphic Trait Implementations* (E0911).

##### Derive Laws

A derived implementation satisfies these laws. A hand-written implementation of the same traits must satisfy them too; the compiler does not check a hand-written one.

- **`Eq`**: `==` is reflexive, symmetric and transitive.
- **`Hash` agrees with `Eq`**: if `a == b`, then `a.hash() == b.hash()`.
- **`Ord` is total and agrees with `Eq`**: for each `a` and `b`, exactly one of `a < b`, `a == b` and `a > b` holds, and `a.cmp(b)` is `Equal` exactly when `a == b`.
- **`Serialize` and `Deserialize` round-trip**: for a value `x` of type `T` that holds no NaN or infinite `Float`, and no `Some(v)` where `v.to_json()` is `JsonValue.Null`, `T.from_json(x.to_json())` is `Ok` of a value equal to `x`. A non-finite `Float` does not survive the round trip (§3.6.2 *NaN and Infinity*). A `Some(v)` where `v.to_json()` is `JsonValue.Null` does not survive it either: that position decodes as `None` (§3.6.2 *Option and Result in JSON*).

##### Error Reporting

An argument that is not a derivable compiler-known trait is E1402 `NotDerivable` (see *Derive Mechanics* above). When `@derive` fails because a field's type doesn't implement the required trait, the compiler reports **all** non-derivable fields in a single diagnostic (not just the first):

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

**`message`** is text for people. The spec fixes its location content:

- A parse error's `message` contains `line L, column C`. Both count from 1. Lines are split at `\n` (U+000A). The column counts bytes from the start of the line, the same unit as `Str.len()`.
- A decode error whose `path` is not `""` has a `message` that contains `at <path>`, for example `at $.items[2].age`.

*NaN and Infinity* and *Str-Backed Enums* below add content rules for some errors. The rest of the wording is not fixed, except that `json.decode[T]` and its two-step form give the same text (§3.6.3 *Typed Decoding and Encoding*).

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
- The value of a `JsonValue.Float` is `t.parse_float()` of the number text `t` (§3.2.1 *Parsing*, law *One number reader*). A number whose value rounds to ±infinity, such as `1e999`, makes `json.parse` give `Err`. Some JSON libraries give infinity for it.
- **An integer outside the `Int` range becomes a `Float` and loses precision.** `json.parse("18446744073709551615")` gives `Ok(JsonValue.Float(18446744073709551616.0))`, not an error. To keep a large ID exact, send it as a JSON string and give the field the type `Str`.
- A derived `from_json` for a `Float` field accepts `JsonValue.Int` and converts it, so `{"temp_c": 20}` decodes into `temp_c: Float`.
- A derived `from_json` for an `Int` field accepts only `JsonValue.Int`. It never narrows a `Float`, not even `3.0`.
- `as_float()` on a `JsonValue.Int` gives `Some`. `as_int()` on a `JsonValue.Float` gives `None`.

##### NaN and Infinity

JSON has no NaN and no infinity. A `JsonValue.Float` can hold either, so these rules decide what happens in each direction:

- **Encode.** `json.stringify`, `json.pretty` and `json.encode` write a `JsonValue.Float` that holds NaN, `inf` or `-inf` as `null`. They stay infallible. A finite `Float` uses the Float Text Form (§3.6).
- **Parse.** RFC 8259 has no `NaN`, `Infinity` or `-Infinity` token. Input that has one of these, in any ASCII case, makes `json.parse` give `Err`, although `parse_float` accepts the same text (§3.2.1 *Parsing*). The error `message` names the rejected token.
- **Decode.** A derived `from_json` for a `Float` field rejects `JsonValue.Null`. The error `message` says that the value was `null` and that the field expects `Float`. An `Option[Float]` field reads `null` as `None`.

The location rules for `message` still apply, and the rest of the wording is not fixed. For example:

```
NaN is not valid JSON: JSON has no NaN or Infinity, at line 1, column 7
expected Float, got null at $.temp_c
```

The first message is for `json.parse("\{\"a\": NaN}")`. The second is for a derived `from_json` that reads `{"temp_c": null}` into `temp_c: Float`.

**Laws.** For every `v` of type `JsonValue`:

- **Valid output.** `json.parse(json.stringify(v))` and `json.parse(json.pretty(v))` are `Ok`. So every `Str` that `json.encode` returns is text that `json.parse` accepts.
- **Round trip.** `json.parse(json.stringify(v)) == Ok(w)`, where `w` is `v` with each `JsonValue.Float` that holds NaN, `inf` or `-inf` replaced by `JsonValue.Null`.

`JsonValue` implements `Eq` with structural `==`: two values are equal when they are the same variant and their payloads are equal. A `Float` payload compares as in *Float Total Ordering*, so `JsonValue.Float(0.0)` equals `JsonValue.Float(-0.0)`. `Object` compares its `fields` as a list, so entry order and duplicate keys count. `JsonValue.Int(1)` does not equal `JsonValue.Float(1.0)`. `JsonValue` does not implement `Hash`, because `Float` does not.

A non-finite `Float` does not survive the round trip. A `Float` field that holds one encodes as `null`, and decoding that `null` into the field gives `Err`. An `Option[Float]` field that holds `Some` of a non-finite `Float` decodes as `None`.

To write a different value for a non-finite `Float`, test it with `x.is_finite()` before the encode:

```blink
import std.json

fn reading_json(x: Float) -> Str {
    if x.is_finite() {
        json.encode(x)
    } else {
        json.encode(0.0)    // not null, so the reader can decode it as a Float
    }
}
```

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
| `Option[T]` | `JsonValue.Null` for `None`, `T.to_json()` for `Some(v)`. Decode: `JsonValue.Null` is `None`, any other value is `T.from_json(j)` wrapped in `Some` |
| `Result[T, E]` | `{"Ok": v}` for `Ok(v)` and `{"Err": e}` for `Err(e)`. Decode: an object with exactly one entry, with the key `"Ok"` or `"Err"` |
| `List[T]` | `JsonValue.Array` |
| Struct with `@derive(Serialize)` | `JsonValue.Object` |
| Enum with `@derive(Serialize)`, not Str-backed | Tagged object: `{"variant": "Name", "fields": {...}}` |
| Str-backed enum with `@derive(Serialize)` | `JsonValue.Str` of its backing literal: `"in_progress"` |

##### Option and Result in JSON

The *Type Mapping* rows and the text below are the whole JSON rule for these two types. The rule of *Option and Result instances* (§3.6) does not apply to `Serialize` and `Deserialize`.

**`Option[T]`.** `Option[T]` is `Serialize` when `T: Serialize`, and `Deserialize` when `T: Deserialize`. `to_json` gives `JsonValue.Null` for `None` and `T.to_json()` for `Some(v)`. `from_json` gives `Ok(None)` for `JsonValue.Null`. For any other value `j`, it gives `T.from_json(j)` with `Ok(v)` changed to `Ok(Some(v))`. An `Err` from `T.from_json` is the result as it is; `Option` adds no step to its `path`. An `Option[Float]` field that reads `null` as `None` (*NaN and Infinity*) is one case of this rule.

**`Option[Option[T]]`.** The instance stays parametric: `Option[T]` is `Serialize` for every `T: Serialize`, and `T` may be an `Option`. So `fn send[T: Serialize](x: T?) -> JsonValue { x.to_json() }` compiles for every `T`. `Some(None)` and `None` of type `Int??` both give `JsonValue.Null`, and `null` decodes as `None`. The round-trip law (§3.6.1 *Derive Laws*) states this loss. The same loss occurs for `Some(JsonValue.Null)` in an `Option[JsonValue]`, and for any `Some(v)` where a written `to_json` returns `JsonValue.Null`.

A derive stops the common case. `@derive(Serialize)` or `@derive(Deserialize)` on a type with a field whose declared type is `Option[Option[T]]` (written `T??`) is E1401 `NonDerivableTrait`. The check reads the declared type of the field **after alias expansion and before generic substitution**:

- `type MaybeName = Str??`, used as a field type, is an error: the alias is the same type.
- A field `v: T?` in `type Box[T]` is not an error, and `Box[Int?]` is not an error. The field is not written `T??`. The round-trip law covers `Box[Int?]`: `Some(None)` decodes as `None`.

The check is a front-end check on a written type, like the template-hole rule (§3.6 *Display Format Protocol*, §3b.5), which rejects `Option[Option[T]]` for the same reason. It does not change what `Option[T]` implements.

The error has a `note:` and a `help:`. The `note:` says that the check covers only a field whose declared type is `T??`, and that a generic field (for example `Box[Int?]`), an `Option[JsonValue]` that holds `Some(JsonValue.Null)`, and a written `to_json` that returns `null` still collapse under the round-trip law. The `help:` writes an enum that names each case, with the field's own type for `T`:

```blink
@derive(Serialize)
type UserUpdate {
    name: Str??
}
```

```
error[NonDerivableTrait]: cannot derive `Serialize` for `UserUpdate`
 --> update.bl:1:9
  |
1 | @derive(Serialize)
  |         ^^^^^^^^^ cannot derive `Serialize`
  |
 --> update.bl:3:5
  |
3 |     name: Str??
  |     ^^^^^^^^^^^ `None` and `Some(None)` both encode as `null`
  |
  = note: this check covers only a field whose declared type is `T??`. A generic field such as `Box[Int?]`,
          an `Option[JsonValue]` that holds `Some(JsonValue.Null)`, and a `to_json` that returns `null`
          still collapse under the round-trip law (§3.6.1 Derive Laws)
  = help: replace the field type with an enum that names each case:
            @derive(Serialize, Deserialize)
            type Patch[T] {
                Keep
                Clear
                Replace(value: T)
            }
          and write the field as `name: Patch[Str]`
```

`Patch[T]` derives with no error, and its JSON is the tagged-object row of the *Type Mapping* table. A PATCH body that must tell "absent" from "set to null" needs this enum.

**`Result[T, E]`.** `Result[T, E]` is `Serialize` when `T: Serialize` and `E: Serialize`, and `Deserialize` when `T: Deserialize` and `E: Deserialize`. `to_json` gives a `JsonValue.Object` with one entry: the key `"Ok"` and the value `v.to_json()` for `Ok(v)`, or the key `"Err"` and the value `e.to_json()` for `Err(e)`. The keys are the variant names as Blink spells them; case matters.

`from_json` accepts a `JsonValue.Object` that has exactly one entry, with the key `"Ok"` or `"Err"`. For `"Ok"` it gives `T.from_json(j)` with `Ok(v)` changed to `Ok(Ok(v))`. For `"Err"` it gives `E.from_json(j)` with `Ok(e)` changed to `Ok(Err(e))`. An `Err` from the payload decode is the result as it is, and `Result` adds no step to its `path`. The first-entry rule for duplicate keys does not apply to `Result`: an object with two entries is an error, even when the keys are equal. Each of these inputs is a `JsonError`:

- an object with no entry, with two or more entries, or with one entry whose key is not exactly `"Ok"` or `"Err"` (for example `"ok"`);
- a value that is not an object.

The `message` of that error names both keys `"Ok"` and `"Err"`, says that case matters, and contains `at <path>` (*JsonError*). The `path` is the position of the `Result` value.

```blink
import std.json

@derive(Serialize, Deserialize)
type Reply {
    outcome: Result[Int, Str]
}

fn main() ! IO {
    io.println(json.encode(Reply { outcome: Ok(7) }))        // {"outcome":{"Ok":7}}
    io.println(json.encode(Reply { outcome: Err("busy") }))  // {"outcome":{"Err":"busy"}}

    match json.decode[Reply]("{\"outcome\": {\"ok\": 1}}") {
        Ok(_) => io.println("decoded")
        Err(e) => io.println(e.message)
    }
}
```

The last call fails. The wording of the message is not fixed, but it has this content:

```
expected an object with exactly one key, "Ok" or "Err" (case matters), at $.outcome
```

A consumer that reads this JSON from another language checks the `"Ok"` key first: if `outcome` has the key `"Ok"`, the call succeeded and the value is the payload; otherwise it has the key `"Err"`.

##### Map and Set Order

When a std serializer (JSON or another format) encodes a `Map` or `Set`, it writes the entries in iteration order (*Hash Contract and Seeding*, §3.6). When a std deserializer builds a `Map` or `Set`, it adds the entries in document order. Where a key occurs more than once, the **first** entry gives both the position and the value, and the deserializer ignores each later entry with that key. This is the rule that `JsonValue.get` (§3.6.3) and derived `from_json` use. A round trip of a document with no duplicate keys keeps the key order.

A document `{"b": 1, "a": 2, "b": 3}` decodes into a `Map[Str, Int]` that iterates `b: 1`, then `a: 2`. The deserializer ignores `"b": 3`.

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

`std.json` keeps no global shared mutable state. A `JsonValue` is an ordinary value, and no call changes or frees a value that another caller holds.

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

There is no `null`, `nil`, or `None`-as-implicit-value: no value belongs to every type. `Never` (§3.2) is the bottom type, but it has no values. It marks code that cannot finish, not a value that might be missing. A `Str` is always a string. An `Int` is always an integer. If a value might be absent, the type says so:

```blink
// This function might not find a user. The type says so.
fn find_user(id: Int) -> Option[User] ! DB {
    db.query_one(t"SELECT * FROM users WHERE id = {id}")
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

fn read_config(path: Str) -> Result[Config, ConfigError] ! FS.Read {
    let text = fs.read(path).map_err(fn(e) { ConfigError.from(e) })?
    let parsed = parse_toml(text).map_err(fn(e) { ConfigError.from(e) })?
    validate_config(parsed).map_err(fn(e) { ConfigError.from(e) })?
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

`(T)` in type or expression position is always parenthesization, never a 1-tuple. The 1-ary product is isomorphic to `T` and adds no expressiveness. For newtype wrapping, use a one-field struct (§3.4 *Newtypes*):

```blink
// Not a 1-tuple — just parenthesized
let x: (Int) = 42        // same as: let x: Int = 42
let y = (some_expr)       // same as: let y = some_expr

// For newtype wrapping, use a one-field struct
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

**Why cap at 6.** Tuples are anonymous — elements have no names, only positions. Beyond 3-4 elements, positional access (`.4`, `.5`) becomes unreadable and error-prone. A cap at 6 provides headroom for real use cases (coordinate triples, tagged pairs, iterator adapters) while pushing complex data toward named structs where field names carry semantic information.

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
| `Hash` | Hash of all elements; equal tuples give equal hashes | All elements: `Hash` |
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
