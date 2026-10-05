[< All Decisions](../DECISIONS.md)

# Str Byte-Range Slice and Out-of-Range Indices — Design Rationale

Resolves two spec gaps in one panel:

- **The byte-range slice of `Str`.** The spec had no byte-range slice. `substring(start, end)` is a codepoint slice and `len` is a codepoint count, but byte-level code (lexer, json, toml, args, path, the compiler) slices by byte offsets. The code had `Str.slice(start, end)` (a byte range, not in the spec) and a `substr(start, len)` alias. Questions: the name and signature of the byte-range slice, its out-of-range behaviour, whether `substr` stays, and whether `index_of` needs a byte twin.
- **Out-of-range indices for `substring` and `byte_at`.** The spec gave `byte_at(self, Int) -> U8` and `substring(self, Int, Int) -> Str` but said nothing about `start > end`, a negative index, or an index past the end.

Facts given to the panel: the codepoint-default decision with the `byte_` prefix ([String Methods](string-methods.md) Q3, 3-2); `List.get -> Option` and `List.set` panics; every slice in the runtime clamped; `lib/std/traits.bl` had drifted from the spec (`byte_at -> Int`, `index_of -> Int`, `substring(start, len)`); and caller counts (substring 95 in src, 53 in lib, 74 in tests). The brief said the spec had no UTF-8 invariant for `Str`; that was wrong (§3.2.3 *Bytes* says "Where `Str` guarantees UTF-8 validity"), and the moderator corrected it before Phase B.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds.

#### Phase A — Independent proposals

Each seat's full Phase A text, verbatim (headings demoted).

<details><summary><b>Systems</b></summary>

**What the hardware sees.** Byte offsets are what the CPU and the runtime work in. `blink_str_len` reads a header, so `byte_len()` is O(1). Every codepoint method is an O(n) walk. A byte loop that takes a codepoint `substring(i, 1)` per byte is O(n²). Byte code needs a byte-native slice and a byte-native search, and the names must say what they cost.

**A fact the brief got wrong:** `sections/03_types.md:657` says "Where `Str` guarantees UTF-8 validity". The runtime also assumes it (`runtime_core.h`, comment above `blink_str_next_char`). Today `substring` can break that invariant (jcfqh6). That makes it a soundness bug in the language, not only a gap in the spec.

---

##### Proposal S1 (recommended): `byte_slice`, ranges clamp, a cut inside a codepoint panics

```blink
trait StrOps {
    fn byte_len(self) -> Int
    fn byte_at(self, index: Int) -> U8                       // panics if index !in [0, byte_len)
    fn byte_slice(self, start: Int, end: Int) -> Str         // byte range [start, end)
    fn byte_index_of(self, needle: Str, from: Int) -> Option[Int]   // byte offset
    fn substring(self, start: Int, end: Int) -> Str          // codepoint range [start, end)
    fn index_of(self, needle: Str) -> Option[Int]            // codepoint index
}

fn next_ident(src: Str, start: Int) -> Str {
    let mut i = start
    while i < src.byte_len() && is_ident_byte(src.byte_at(i)) {
        i = i + 1
    }
    src.byte_slice(start, i)          // O(len), one memcpy, no walk
}

fn field(line: Str) -> Str {
    match line.byte_index_of("=", 0) {
        Some(eq) => line.byte_slice(eq + 1, line.byte_len()).trim()
        None => ""
    }
}

"café!".byte_slice(0, 4)     // panic: byte 4 is inside 'é'
"café!".byte_slice(0, 99)    // "café!" (end clamps to byte_len)
"café".substring(1, 99)      // "afé"  (end clamps to len)
"café".substring(3, 1)       // ""     (start >= end)
```

**The out-of-range rule.** One rule covers every range operation: `List.slice`, `Bytes.slice`, `substring`, `byte_slice`.

1. A start below 0 becomes 0.
2. An end past the length becomes the length.
3. If start >= end, the result is empty.

The rule is total, and the C is two `cmov`s with no branch. It is what the runtime does today (`blink_list_slice`, `blink_bytes_slice`, `blink_str_slice`), so step 1 of the jcfqh6 migration changes no behaviour, and gen0 agrees with gen1.

**The cut rule (byte_slice only).** Clamping never fixes a cut inside a multi-byte codepoint, because every possible result would be either invalid UTF-8 or a silent change of the caller's offset. So `byte_slice` panics when a clamped bound is not on a codepoint boundary. The check costs O(1): `(s[k] & 0xC0) != 0x80` at each end, which is two loads beside a memcpy. This is Rust's `&s[a..b]` rule. Real byte code (lexer, json, toml, path) always cuts at ASCII delimiters, so the check is never taken but still guards the invariant.

**Point access.** `byte_at` keeps its bare `U8` return and panics when `index !in [0, byte_len)`. One unsigned compare, `(uint64_t)i >= len`, also catches negative indices. Go (`s[i]`) and Rust (`s.as_bytes()[i]`) do the same. I reject `Option[U8]`: `byte_at` sits inside loops that `byte_len` already bounds, and it has 100+ callers of the form `s.byte_at(i) == 37`. `?? 0` at every site adds noise with no safety gain, and a 0 sentinel collides with a real NUL byte. Code that wants `Option` can use `Bytes.get`. Today `blink_str_char_at` is a bare `s[i]` with no check, so this rule closes the out-of-bounds read in 75jjhv. Also, code (`traits.bl:57`) returns `Int` where the spec says `U8`; code must change to match the spec.

**The name: `byte_slice`, not `slice`.** On `List` and `Bytes`, `slice` indexes elements, and a `Str` element is a `Char` (`for c in s`). A `Str.slice` on bytes would break that pattern without warning. The `byte_` prefix follows the decided rule (string-methods Q3) and puts the cost in the name.

**`byte_index_of` takes `from`.** The runtime already has `blink_str_index_of_from` because scanning from an offset is the hot need (`str.bl:193`, `:232`). Without `from`, a "find the next delimiter" loop re-scans the prefix, or allocates a slice per step. A negative `from` becomes 0. A `from` past the end, or not on a codepoint boundary, gives `None`. Returning `Option[Int]` costs nothing extra: it is a two-word struct returned in registers under SysV, with no heap.

##### Proposal S2 (alternative): every range panics (Rust/Go)

Same names, but an out-of-range bound or start > end panics. This catches off-by-one bugs that clamping hides, at the same cost. I put it second because the runtime clamps today, and an audit of the 222 substring callers for reliance on clamping is real work during the migration. If the panel weights finding bugs above migration cost, I accept S2. Mixing the two rules (clamp `substring`, panic on `List.slice`) is the one choice I oppose.

##### Rejected
- **Snap a cut to the previous boundary.** It is silent, and the offset then lies to the caller.
- **Make byte_slice return `Bytes`.** This needs a copy back to `Str` plus validation at every use.
- **Keep `substr`.** Its shape `(Int, Int)` matches `substring`, but it means byte start + byte count, so a mix-up compiles. That is the same hazard as jcfqh6.

---

##### Summary per question
- **75jjhv:** `substring` clamps (start<0→0, end>len→len, start>=end→""). `byte_at` panics outside `[0, byte_len)` and stays `-> U8`.
- **arsf0e Q1:** `fn byte_slice(self, start: Int, end: Int) -> Str`, half-open byte range. Remove `slice` from the `StrOps` code after the migration.
- **Q2:** Same clamp as every other range op. A cut inside a codepoint panics because the spec guarantees `Str` is UTF-8.
- **Q3:** Remove `substr`, with its 3 src callers and 7 test files, in migration step 1.
- **Q4:** `index_of` stays a codepoint `Option[Int]`. Add `byte_index_of(self, needle: Str, from: Int) -> Option[Int]`.

**The panel must also decide:**
- **The UTF-8 invariant.** Confirm that `Str` is always valid UTF-8 (`03_types.md:657`) and that no safe Str method may produce invalid UTF-8. This makes the rule a property of the type, not a habit.
- **`byte_at` on Str.** State its panic in the method table, matching `List.set`.
- **One range rule.** Make it normative for `List.slice` and `Bytes.slice` too. Today the spec says nothing on these.
- **`len()` cost.** Mark it O(n) in the method table so byte code does not loop with `i < s.len()`. A lint for `len()`/`substring` inside a `byte_at` loop is worth a separate ticket.

</details>

<details><summary><b>Web/Scripting</b></summary>

**One rule a JS or Python dev learns in five minutes:** "A read at one position gives `Option`. A range clamps. Writes and broken text panic."

The spec already uses most of this rule. `List.get`, `Bytes.get` and `char_at` give `Option`. The 03_types.md:449 text says "a read never panics on an index that is out of bounds", and `List.set` panics. Every slice in the runtime already clamps. So the change is small: `byte_at` breaks the read rule, and the spec does not yet say that ranges clamp.

---

##### Proposal W1: ranges clamp and position reads give Option

```blink
let s = "café!"

// Codepoint range, [start, end), clamped
s.substring(0, 4)      // "café"
s.substring(3, 99)     // "é!"   end past len stops at len
s.substring(-2, 2)     // "ca"   start < 0 becomes 0
s.substring(4, 1)      // ""     start >= end gives empty, never swapped

// Byte read at one position gives Option, the same as Bytes.get and List.get
s.byte_at(0)           // Some(99)
s.byte_at(99)          // None
let b = s.byte_at(i) ?? 0
```

- **Clamp ranges.** Python `s[2:99]` and JS `s.slice(2, 99)` both clamp and never throw. Users expect this. A panic on `substring(0, 99)` would cause a lot of "why does my string code crash" questions.
- **Negative indexes clamp to 0.** I do not want Python's "count from the end" meaning. It is a second meaning hidden inside one argument. With it, `substring(i - 1, j)` silently changes meaning when `i` is 0. Clamping to 0 is what JS `substring` does, and the runtime does it today.
- **start > end gives `""`.** It must not swap the two values. JS `substring` swaps them, and that is a well-known JS trap. Python gives an empty string, and so does `blink_bytes_slice` today.
- **`byte_at` gives `Option[U8]`.** The return type changes from `U8`. I accept the cost: 55 call sites in src and 66 in lib, all mechanical (`?? 0` or a pattern match). In exchange, `Str.byte_at` and `Bytes.get` work the same way, and the "a read never panics" principle has no exceptions. A memory note says gcc -O2 compiles an `Option` read in a tight loop well, so hot loops should cost almost nothing.
- **The same clamp rule goes into the spec for `List.slice` and `Bytes.slice`.** Today the spec does not say what they do with an out-of-range index. One rule should cover all three types.

The tradeoff: a clamp can hide an off-by-one bug. That is what scripting users already accept in Python and JS. Kotlin and Java throw on `substring`, and they get a lot of questions about it.

##### Proposal W2: `byte_slice` is the byte range; no `slice` on Str

```blink
let src = "let x = 1"
let mut i = 0
while i < src.byte_len() && src.byte_at(i) != Some(32) { i += 1 }
let word = src.byte_slice(0, i)                  // "let"

match src.byte_index_of("=") {
    Some(at) -> src.byte_slice(at + 1, src.byte_len()).trim()   // "1"
    None -> ""
}
```

- **Name it `byte_slice(start, end)`.** It follows the `byte_` prefix rule, which already has a vote behind it.
- **Remove `Str.slice`.** To a JS dev, `"abc".slice(1)` is the normal text slice. To a Rust or Go dev, `slice` means bytes. On `Str` the name is ambiguous whichever way the spec defines it. On `List` and `Bytes` it has one meaning, so it stays there.
- **Out-of-range indexes clamp, the same as W1.**
- **A cut inside a multi-byte codepoint panics** (Rust does the same). This is the only panic I propose, because the result would be a broken `Str`, which is the jcfqh6 bug. The check is O(1): look at whether the byte at `start` and at `end` is a continuation byte (`10xxxxxx`). Code that cuts on ASCII delimiters (lexer, JSON, TOML, path) never hits this panic. In JS, lone surrogates silently make garbage text, and many questions come from that. I would rather the program fail loudly.
- **The spec must also say that every `Str` is valid UTF-8.** This proposal depends on that rule.

##### Proposal W3: remove `substr`

`substr(start, len)` duplicates `substring` and takes its arguments in a different form. JS deprecated `substr` for exactly this reason: users mix up "length" and "end" in their arguments. It has 3 callers in src and 7 test files. Remove it with the 3-step migration. A tool or a fix-it should point users to `substring`.

##### Proposal W4: two `index_of` methods, each matching one slice

- `index_of(needle) -> Option[Int]` gives a codepoint index, as the spec says. It pairs with `substring`.
- `byte_index_of(needle) -> Option[Int]` gives a byte offset. It pairs with `byte_slice`.

If one search returned bytes and the slice took codepoints, users would mix the two units. That works for ASCII and breaks on the first "é", which is exactly the kind of bug a test with ASCII data never finds. The names must tell the user which unit they are working in. `Option` replaces the `-1` result in code today. `-1` is a JS habit that I do not want to keep.

---

##### Position per question

| Question | Position |
|---|---|
| 75jjhv `substring` out of range | Clamp: start<0 → 0; end>len → len; start≥end → `""`. No swap, no counting from the end |
| 75jjhv `byte_at` out of range | Return type becomes `Option[U8]`, the same as `Bytes.get`. No panic, no clamp |
| arsf0e Q1 name and signature | `byte_slice(start: Int, end: Int) -> Str`, [start, end) in bytes. Remove `Str.slice` |
| arsf0e Q2 out of range | Clamp, the same as Q1. A cut inside a codepoint panics |
| arsf0e Q3 `substr` | Remove (3-step migration) |
| arsf0e Q4 `index_of` / `byte_index_of` | `index_of` → `Option[Int]` codepoint index. Add `byte_index_of` → `Option[Int]` byte offset |

##### Other items the panel must decide

1. **Every `Str` is valid UTF-8.** The spec does not say this. W2's panic depends on it, and so does the codepoint switch.
2. **One clamp rule for every range.** Write it down once and apply it to `Str.substring`, `Str.byte_slice`, `List.slice` and `Bytes.slice`.
3. **A search with a start offset.** A lexer needs `byte_index_of(needle, from)`, or it must slice before each search, which allocates. I lean towards YAGNI until a real caller needs it, but the panel should note it.
4. **Code in lib/std/traits.bl does not match the spec.** `StrOps` there declares `substring(start, len)` with a length argument, and `byte_at` and `index_of` return `Int`. A user who reads the code learns a different API from the spec. The fix must change `traits.bl` and the spec together, not one at a time.

</details>

<details><summary><b>PLT</b></summary>

**One fact the brief has wrong.** The spec already gives `Str` a UTF-8 invariant. `sections/03_types.md:657` says: "Where `Str` guarantees UTF-8 validity, `Bytes` carries no encoding invariant." That makes jcfqh6 more than a bad answer. A byte slice that returns half of `é` produces a value of type `Str` that breaks the type's own invariant, so the type is unsound. Any byte-range slice on `Str` must keep the invariant, whatever the out-of-range rule turns out to be.

##### Proposal P1: three typing rules for partiality, applied everywhere

**R1. A point read never makes up a value.** If the return type can express failure (`Option`), out-of-range gives `None`. If it cannot (a bare `U8`), out-of-range is a broken precondition and the call panics. Clamping a point read is unsound: `"abc".byte_at(99)` would return a byte the string does not hold at that index.

**R2. A range read is a total projection.** `start` and `end` are each clamped to `[0, len]`, and `start >= end` gives an empty result. This is not "works in practice". Clamping is monotone and idempotent, so the concatenation law still holds for every `a <= b <= c`, including indices out of range:
`s.slice(a, b).concat(s.slice(b, c)) == s.slice(a, c)`.
Any empty result is also a real value of the type, so nothing is made up. The same rule covers `List.slice`, `Bytes.slice`, `Str.substring` and `Str.byte_slice`, and it is what the runtime already does.

**R3. A byte range must not split a codepoint.** After clamping, if either end of a `byte_slice` falls inside a multi-byte codepoint, the call panics. Clamping can repair a length but not an encoding. I rejected "snap down to the nearest boundary": it is lawful (monotone), but it hides a real logic error in byte code. Byte offsets that come from byte loops land on ASCII delimiters, so a split is a bug and should fail loudly.

```blink
let s = "café!"
s.byte_len()            // 6
s.byte_at(1)            // 97
s.byte_at(99)           // panic: byte index 99 out of range for byte_len 6
s.char_at(99)           // None
s.substring(1, 99)      // "afé!"   (R2: end clamped to len 5)
s.substring(3, 1)       // ""       (R2)
s.byte_slice(0, 3)      // "caf"
s.byte_slice(0, 4)      // panic: byte offset 4 is not a char boundary (R3)
s.byte_slice(-5, 99)    // "café!"  (R2)
```

The one-line rule for users: **point reads are `Option` or panic, never clamp. Range reads clamp. Writes panic.** This matches `List.get`/`List.set` and `Int.clamp` (which panics when `min > max`), and it can be written as typing side conditions.

##### Proposal P2: the method prefix names the index domain

Every `Str` method that takes or returns an `Int` index works in exactly one domain, and its name says which one. `byte_*` methods use byte offsets. Methods without the prefix use codepoint indices. Under this rule a byte-range `Str.slice` is ill-named, because nothing in the name says "byte".

```blink
fn read_ident(src: Str, start: Int) -> Str {
    let mut i = start
    while i < src.byte_len() && is_ident_byte(src.byte_at(i)) {
        i = i + 1
    }
    src.byte_slice(start, i)
}

fn after_colon(line: Str) -> Option[Str] {
    match line.byte_index_of(":") {
        Some(i) => Some(line.byte_slice(i + 1, line.byte_len()))
        None => None
    }
}
```

What follows from it:
- `byte_slice(self, start: Int, end: Int) -> Str` uses a half-open byte range `[start, end)`.
- `Str.slice` is removed. The other option, a codepoint `slice` beside `substring`, would give one operation two names.
- `substr(start, len)` is removed. Every range in the language is half-open `(start, end)`. A second `(start, count)` form is how jcfqh6 happened: the code passed a count where the spec meant an end.
- `index_of(Str) -> Option[Int]` returns a codepoint index, as the spec already says.
- Add `byte_index_of(Str) -> Option[Int]`, which returns a byte offset. Without it, byte code has to pair a codepoint index with a byte slice. Both are plain `Int`, so the type checker cannot catch the mix-up.
- `byte_at` returns `U8` as the spec says. The code's `-> Int` in `lib/std/traits.bl:57` is drift and must be brought in line with the spec.

**Deferred (P2'):** distinct nominal types `ByteOffset` and `CharIndex` would make domain confusion a type error, as in Rust's `TextSize` or Swift's `String.Index`. That is the sound end state. It costs arithmetic friction in every byte loop, and ~160 `byte_at` call sites already take `Int`. I am not proposing it now. The prefix rule is the naming version of the same discipline, and it does not rule out adding the types later.

##### Tradeoffs (PLT view)

- R1 panics instead of returning `Option[U8]` for `byte_at`. `Option[U8]` would be fully total, but the caller's loop guard (`i < byte_len()`) already proves the precondition, and an `.unwrap()` at every one of ~160 hot call sites would only repeat that proof. `char_at` stays `Option` because codepoint indices usually come from outside the string, not from a guard over it.
- R3 brings a panic into a range read. This is the one exception to "range reads clamp", and it exists only because `Str` has an invariant that `Bytes` and `List` lack. Code that wants a range with no panic can use `Bytes.from_str(s).slice(a, b).to_str()`, which returns a `Result`.
- R2 hides off-by-one bugs in ranges. I accept that because the projection is lawful and it is the convention in Python, JavaScript and Go (`[:]` with a cap check). Rust panics on ranges, but Rust is the outlier among scripting-facing languages.

**Cross-language:**
- Rust `&s[a..b]` panics on a non-boundary. That is R3, and it is the model for keeping the invariant.
- Python slicing clamps. That is R2.
- OCaml `String.sub` raises on an out-of-range argument. Strict, but it does not follow the concatenation law at the edges.
- Swift avoids the problem with opaque indices, which is P2'.

##### Per-question summary

- **75jjhv, `substring`:** clamp. Each end is clamped to `[0, len()]` in codepoints, `start >= end` gives `""`, and `end` is an end, not a count.
- **75jjhv, `byte_at`:** panic when `i < 0 || i >= byte_len()`. Keep the `-> U8` return type and fix the code to match.
- **arsf0e Q1:** `byte_slice(self, start: Int, end: Int) -> Str`, a half-open byte range. Remove `Str.slice`.
- **arsf0e Q2:** clamp as in R2, plus a panic when either end splits a codepoint (R3).
- **arsf0e Q3:** remove `substr` and use one range convention everywhere.
- **arsf0e Q4:** `index_of` returns a codepoint `Option[Int]`. Add `byte_index_of -> Option[Int]` in byte offsets.

**Other things the panel must decide:**
1. State the UTF-8 invariant on `Str` explicitly in the `Str` section, not only in the `Bytes` section, and require every `Str` constructor to keep it.
2. Write the R1/R2/R3 partiality rule into the spec once, and point each method row at it.
3. Make `List.slice` and `Bytes.slice` follow R2 explicitly. The spec says nothing about them today.
4. Whether `byte_index_of` and `index_of` also need a `from` start-offset overload. Byte scanners usually need one.
5. Keep P2' (nominal index types) on record as a deliberate deferral, not a rejection.

</details>

<details><summary><b>DevOps</b> (relayed copy; a few passages were excerpted with "..." in transit)</summary>

DevOps/Tooling Phase A proposal: indexing panics, ranges clamp, byte_slice is the byte range, and the substring flip goes through a codemod.

##### The main risk: a silent meaning change
Today `substring(start, len)` takes a byte start and a byte COUNT (lib/std/traits.bl:62). The spec makes it `substring(start, end)` in codepoints. Both versions take two Ints, so a call that compiles today will still compile after the flip and mean something else. No compiler error, lint, or LSP hover can catch it. That is the worst kind of change for tooling. The budget: 222 substring, 16 substr, 154 byte_at and 328 index_of call sites in src+lib+tests. The order of steps matters more than the names.

##### Proposal 1: names
- Add `fn byte_slice(self, start: Int, end: Int) -> Str`: a byte range [start, end). It follows the `byte_` prefix rule (decisions/string-methods.md Q3). In the LSP, typing `s.byte_` then lists byte_len, byte_at, byte_slice and byte_index_of together, so the whole byte API is easy to find.
- Remove `slice` from Str. On List and Bytes, `slice` counts elements. On Str the unit is unclear, and that unclear unit caused this ticket. The "no method" error forces the writer to pick a unit:
```
error[E....]: Str has no method `slice`
  help: use `substring` for codepoint positions: s.substring(a, b)
  help: use `byte_slice` for byte offsets:     s.byte_slice(a, b)
```
- Remove `substr`. It has a third convention (start, len). The fix rewrites `s.substr(a, n)` to `s.byte_slice(a, a + n)`.
- Keep `index_of(Str) -> Option[Int]` as a codepoint index, as the spec says. Add `fn byte_index_of(self, needle: Str) -> Option[Int]`. Without it, byte code has to mix a codepoint index with a byte slice, which is exactly the bug class we are closing.

##### Proposal 2: out-of-range rule (Python's rule, the same for all slice families)
Indexing one element: an absent value or a panic. Ranges: clamp.
- `char_at -> Option[Char]` and `List.get -> Option[T]` stay as they are.
- `byte_at(i) -> U8` panics when i is out of bounds. Why the `byte_` methods are an exception to 03_types.md:449 ("a read never panics"): `byte_` is the low-level escape hatch, used in loops that already check `i < s.byte_len()`. If it returned Option[U8], 154 sites would gain `.unwrap()`, and readers and lints could no longer tell a real risk from noise. Add one sentence to the spec at :449 that names this exception.
- `substring`, `byte_slice`, `List.slice` and `Bytes.slice` all clamp: start<0 -> 0, end>len -> len, start>=end -> empty. The runtime does this today (71ba31ad), and it is total. The spec text must cover List.slice too, or we get a fourth convention.
- One exception: if `byte_slice` cuts inside a multi-byte codepoint, it panics (jcfqh6). This adds an invariant to the spec: "every Str is valid UTF-8". The check is O(1): the byte at each end must not be a continuation byte (0b10xxxxxx). If we snapped to a boundary instead, the data would change silently. Lexer, json and path code slice at ASCII delimiters, so the check never fires for them.

##### Proposal 3: migration steps (each step is its own regen, per CLAUDE.md)
1. Add `byte_slice` and `byte_index_of`. Mark `substr` and `Str.slice` with `@deprecated(fix: "replace")` (06_tooling.md:1751).
2. Codemod with `blink migrate`: today's `.substring(a, n)` becomes `.byte_slice(a, a + n)`, `.substr` the same, `Str.slice(a, b)` becomes `.byte_slice(a, b)`. Byte-offset `index_of` calls that feed a byte slice become `byte_index_of`, and `-1` checks become Option. ...The `index_of` -> `byte_index_of` change is manual.
3. Flip `substring`, `len`, `char_at` and `index_of` to codepoints. Remove `substr` and `Str.slice`.

##### Follow-on lint (not a blocker)
W-unit-mix ... fires when an `index_of`/`len`/`char_at` result flows into `byte_slice`/`byte_at`, or when a `byte_index_of`/`byte_len` result flows into `substring`/`char_at`.

Cross-language: Python clamps slices and raises on an index. Rust panics on a byte range that is not on a char boundary. Go's s[a:b] is bytes and panics out of range. JS substring clamps and swaps start/end. We do not swap.

##### Per-question summary
- 75jjhv: `byte_at` panics with idx and byte_len in the message. `substring` clamps, and start>=end gives "". The rule is written once and covers Str, List and Bytes slices.
- arsf0e Q1: `byte_slice(start, end) -> Str`, a byte range. `slice` is removed from Str.
- Q2: clamps like substring. Panics only on a cut inside a codepoint. Add "Str is always valid UTF-8" to the spec.
- Q3: `substr` is removed, through `@deprecated` with a machine-applicable rewrite to byte_slice.
- Q4: `index_of -> Option[Int]` is a codepoint index. Add `byte_index_of -> Option[Int]`.
- The panel must also decide: the step order; the explicit exception text for `byte_` at :449; and whether the UTF-8 invariant also covers `Str` built from Bytes or FFI (constructors must validate, or the invariant is false).

</details>

<details><summary><b>AI/ML</b></summary>

##### The risk I am scoring

An LLM does not get Blink strings wrong because it lacks a feature. It gets them wrong when a Blink name matches a name from its training data but has different semantics. That code compiles, passes ASCII tests, and returns wrong output on the first `é`. I rank each option by three things: how much silent wrong code it lets through, how many decision points it adds, and how many tokens a common loop costs.

There are three collisions in the current tree:

1. **`substring(start, len)`** in code vs **`substring(start, end)`** in the spec. Every major prior (JS, Java, C#, Kotlin) reads `substring` as start and end. JS `substr(start, len)` is the deprecated twin that models already mix up with `substring`. Today a model writes `s.substring(i, j)` meaning end, and gets a count.
2. **`Str.slice` as a byte range.** In every prior (Python `s[a:b]`, JS `slice`, Kotlin `slice`), `slice` on a string counts characters. `List.slice` counts elements, and Blink's `Str` iterates `Char`. A byte-range `Str.slice` gives correct output on ASCII test data and wrong output on real text.
3. **Clamping.** It hides off-by-one errors. A model's off-by-one with clamping gives a short string and no signal. With a panic, the first test fails with a message.

##### Proposal A (my primary): one prefix rule, strict ranges

**Rule the model learns once:** a `byte_` method takes and returns byte offsets. Every other `Str` index is a codepoint index. No exceptions and no unprefixed byte method.

```blink
trait StrOps {
    fn char_at(self, index: Int) -> Option[Char]
    fn byte_at(self, index: Int) -> U8              // panics: index < 0 or >= byte_len()
    fn index_of(self, needle: Str) -> Option[Int]   // codepoint index
    fn byte_index_of(self, needle: Str) -> Option[Int]
    fn substring(self, start: Int, end: Int) -> Str // codepoints, [start, end)
    fn byte_slice(self, start: Int, end: Int) -> Str // bytes, [start, end)
}
```

Byte-loop code, as the lexer, json and path code is written:

```blink
fn read_ident(src: Str, start: Int) -> Str {
    let mut i = start
    while i < src.byte_len() && is_ident_byte(src.byte_at(i)) {
        i = i + 1
    }
    src.byte_slice(start, i)
}

fn split_key(line: Str) -> Option[(Str, Str)] {
    let eq = line.byte_index_of("=")?
    Some((line.byte_slice(0, eq), line.byte_slice(eq + 1, line.byte_len())))
}
```

Codepoint code:

```blink
let s = "café!"
s.substring(0, 4)          // "café"
s.index_of("é")            // Some(3)
s.byte_index_of("é")       // Some(3)
s.byte_slice(0, 4)         // panics: byte 4 is not a codepoint boundary
```

**Out-of-range rule, one sentence for all four index methods.** `substring`, `byte_slice`, `byte_at` and the existing `List.slice`/`Bytes.slice` panic when `start < 0`, `start > end`, or `end > len` (in the method's own unit). `byte_slice` also panics when either bound is inside a multi-byte codepoint. The panic message names the method, both bounds and the length.

Why panic instead of Option or clamp:

- **Option** costs `.unwrap()` or `?` on about 220 call sites, and in the tightest byte loops. Models will use `.unwrap()` without thinking, which turns it back into a panic with a worse message. `char_at`/`get` stay Option because a single-element read with no prior bound check is the common case. A range slice almost always follows a computed, already-checked offset.
- **Clamp** is the Python/JS prior, so a model will not be surprised by it. But it also hides the model's own mistakes. When a model hands a slice the wrong bounds, I want a crash in the test, not short output in production.
- **Boundary panic** on `byte_slice` keeps every `Str` valid UTF-8. That one invariant lets a model trust `len`, `char_at` and `for c in s` on any string, including one built from a byte slice. Rust has trained models on exactly this rule (`&s[a..b]` panics off a char boundary), so the prior already exists.

**`substr`: remove it.** It adds a second signature shape for the same job and the most confused name pair in JS training data. Its 3 src callers and 7 test files move to `substring`/`byte_slice`.

**`Str.slice`: remove it from `StrOps`.** It does not go to codepoints, and it does not stay as a byte alias. If two names do one job, a model has a choice to make every time it slices.

**`index_of`/`byte_index_of`:** both are needed. Without `byte_index_of`, a model will pair the codepoint `index_of` with `byte_slice`. That passes on ASCII and is wrong on everything else, which is the worst kind of silent bug. A matched pair whose names share a prefix makes the right pairing the obvious one. Also return `Option[Int]` instead of `-1`, because models trained on JS/Java write `if i >= 0` and get the sentinel case wrong.

**Cross-language:** Rust matches this most closely (bytes, panic on range and boundary). Go is bytes and panics. Swift is safe but its token cost is high (`String.Index`), and models do badly with it. Python/JS clamp. Java throws.

##### Proposal B (fallback if the panel wants "reads never panic")

Use the same names, plus `byte_at -> Option[U8]` and `fn get_slice/byte_get_slice -> Option[Str]` next to the panicking forms, as Rust does with `get(a..b)`. I do not recommend it now: it adds a decision point at every slice site, and YAGNI applies until a caller needs it.

##### Migration hazard the panel must own

`substring` changes meaning at all ~222 call sites: (start, len) in bytes becomes (start, end) in codepoints. If that is done as a rename in place, both semantics exist at once and models learn from both. Order:
1. Add `byte_slice`/`byte_index_of`.
2. Move every byte caller to them.
3. Only then switch `substring` to codepoints.

The 3-step bootstrap dance fits this. The runtime clamping merged in 71ba31ad must also become a panic, and every caller that relies on the clamp has to be audited.

##### Per-question summary

- **75jjhv:** `byte_at` and `substring` panic on any out-of-range bound (`<0`, `start>end`, past the end) with a descriptive message. No clamp, no Option. `char_at`/`List.get` keep Option.
- **arsf0e Q1:** `byte_slice(self, start: Int, end: Int) -> Str`, end-exclusive. Remove `slice` from `Str`.
- **Q2:** Same rule as 75jjhv, plus a panic on a non-codepoint boundary. Strings stay valid UTF-8.
- **Q3:** Remove `substr`.
- **Q4:** `index_of -> Option[Int]` in codepoints, and add `byte_index_of -> Option[Int]` in bytes.
- **Also decide:**
  - State in the spec that every `Str` is valid UTF-8.
  - Apply the same panic rule to `List.slice`/`Bytes.slice`, which are spec-silent today, so all slices behave alike.
  - Fix the `StrOps` code drift (`byte_at -> Int`, `index_of -> Int`) to match the spec signatures.

</details>

<details><summary><b>Minimalism</b></summary>

**Correction to the brief:** it says "The spec does not state that every Str is valid UTF-8." It does. `sections/03_types.md:657` says: "Where `Str` guarantees UTF-8 validity, `Bytes` carries no encoding invariant." So any byte-range slice must keep that guarantee. This rules out the option of letting a slice produce invalid UTF-8.

##### My rule: subtract first

We have five slice-like names on Str: `substring`, `substr`, `slice`, and the proposed `byte_slice` and `byte_index_of`. We need two operations, a codepoint range and a byte range. One name for each. Every alias also costs a doc row, a training-data split and an LLM guessing which one to call.

---

##### Proposal M1: one name for each axis, and a closed `byte_` set

```blink
trait StrOps {
    fn char_at(self, index: Int) -> Option[Char]
    fn index_of(self, needle: Str) -> Option[Int]        // codepoint index
    fn substring(self, start: Int, end: Int) -> Str      // codepoint [start, end)

    fn byte_len(self) -> Int
    fn byte_at(self, index: Int) -> Option[U8]
    fn byte_index_of(self, needle: Str) -> Option[Int]   // byte offset
    fn byte_slice(self, start: Int, end: Int) -> Str     // byte [start, end)
}
```

- **`byte_slice(start, end)`.** Do not declare `slice` a byte range. `List.slice` and `Bytes.slice` index elements, and Str's elements are `Char` (`IntoIterator[Char]`). A byte-indexed `Str.slice` would mean something different under the same name. The `byte_` prefix rule is already decided (string-methods Q3), so this adds no new rule.
- **Remove `Str.slice` and `substr`.** About 10 callers use `substr` and about 58 use `.slice(` (shared with List and Bytes). Both are cheap to migrate. Neither is in the spec, so removing them leaves the spec as it is and only brings the code in line with it.
- **Add `byte_index_of`.** I resisted it, but the language cannot do without it. A codepoint `index_of` does not pair with `byte_slice`, and converting between them is O(n) per call. Without it, every lexer, parser or path splitter either goes quadratic or writes its own search loop. That is worse for the surface than one method.
- **Close the `byte_` set at four:** `byte_len`, `byte_at`, `byte_index_of`, `byte_slice`. The spec should say that any new `byte_` method (`byte_last_index_of`, `byte_starts_with` and so on) needs a panel vote. This stops the prefix from growing a second copy of StrOps.

Cross-language: Go has one byte API and Python has one codepoint API. Swift exposes several views, and that is the cost we are avoiding. Rust gets away with one name (`&s[a..b]`) because it has range syntax, which we do not have.

##### Proposal M2: one out-of-range rule for each operation shape

The spec already has the rule: "a read never panics on an out-of-bounds index; a write panics" (`03_types.md:449`). I would extend that rule and not invent a new one.

**Point reads return `Option`:**

```blink
let b = s.byte_at(i) ?? 0
match s.byte_at(i) {
    Some(c) => handle(c)
    None => done()
}
```

`byte_at -> Option[U8]` matches `Bytes.get -> Option[U8]` and `char_at -> Option[Char]` exactly. Today's bare `U8` is the only point read in the spec that breaks the rule. Making it panic would add an exception to the rule, so I prefer the Option. The 121 callers in src and lib pay `?? 0` or `.unwrap()`. Q3 already said byte access is "intentionally inconvenient". gcc -O2 compiles the Option away (we measured this when we tried to fuse Option checks).

**Range reads clamp.** This applies to all four slices (`List.slice`, `Bytes.slice`, `substring`, `byte_slice`). Each bound is clamped into `[0, len]`, where `len` is in the method's own unit. If `end <= start` after clamping, the result is empty.

```blink
"hello".substring(2, 99)    // "llo"
"hello".substring(-3, 2)    // "he"
"hello".substring(4, 1)     // ""
```

Clamping has real uses ("the first n or fewer"), it keeps slices total, and it is what the runtime does today for all four, so this needs no runtime change. It is one sentence, written once and applied to every slice. Python and JS clamp. Go and Rust panic, but they have range syntax and bounds-check elimination built around that choice.

**One exception: a `byte_slice` bound inside a codepoint panics.**

```blink
"café!".byte_slice(0, 4)    // panic: byte offset 4 is not on a char boundary
```

This is not a range question. It would break the type's own invariant, the same class of error as integer overflow, which also panics. A clamp has a correct meaning, but an offset in the middle of a codepoint never comes from a correct program: byte offsets come from scanning ASCII delimiters. Moving the bound down to a boundary would hide that bug and silently drop data. The check costs O(1): look at whether the byte at the bound is `0x80..0xBF`. Rust does the same.

##### Option rejected: "do it on `Bytes` instead"

The purest subtraction is to say that byte work belongs on `Bytes`, so Str gets no `byte_slice` or `byte_index_of`. I reject it. Every round trip costs a copy plus UTF-8 validation (`to_str -> Result`), and `Bytes` would then need its own `index_of`. That is more surface and more cost than M1.

##### Option rejected: keep `substr(start, len)`

A second way to say the same range, using a count where `List.slice` and `Bytes.slice` use an end. The runtime's count argument is the jcfqh6 bug and should not become spec.

---

##### Summary

| Question | Min position |
|---|---|
| **75jjhv: substring out of range** | Clamp into `[0, len()]` in codepoints. `end <= start` gives `""`. The same sentence covers List, Bytes and byte slices. |
| **75jjhv: byte_at out of range** | Change the signature to `byte_at(Int) -> Option[U8]`, matching `Bytes.get` and `char_at`. Reads never panic. (Fallback if the panel rejects the signature change: panic, never clamp.) |
| **arsf0e Q1: name and signature** | `byte_slice(start: Int, end: Int) -> Str`, a byte range `[start, end)`. `Str.slice` is removed, not repurposed. |
| **arsf0e Q2: out of range** | Clamp, as in 75jjhv. A bound in the middle of a codepoint panics, because Str guarantees UTF-8 (`03_types.md:657`). |
| **arsf0e Q3: substr** | Remove it. |
| **arsf0e Q4: index_of / byte_index_of** | `index_of -> Option[Int]` in codepoints, as the spec says. Add `byte_index_of -> Option[Int]` in bytes. Close the `byte_` set at four methods. |

**Also for the panel to decide:**
1. Confirm that Str's UTF-8 guarantee at `:657` is normative. The brief says the spec is silent on this. It is not, and the mid-codepoint panic depends on it.
2. `traits.bl` StrOps has drifted from the spec: `byte_at -> Int`, `index_of -> Int`, `substring(start, len)`. The decision should list the code-only shapes it removes.
3. The order of the migration is the 3-step bootstrap dance: add `byte_slice` and `byte_index_of`, move byte callers onto them, then flip `substring`, `len`, `char_at` and `index_of` to codepoints and delete `substr` and `Str.slice`.

</details>

#### Phase B — Debate highlights

After dedupe, all six Phase A proposals agreed on eight points (U1–U8): add `byte_slice(self, start: Int, end: Int) -> Str` over `[start, end)`; remove `Str.slice`; remove `substr`; keep `index_of -> Option[Int]` as a codepoint index; add `byte_index_of -> Option[Int]`; `byte_slice` panics when a bound falls inside a codepoint; state the UTF-8 invariant in the Str section; one out-of-range rule for `substring`, `byte_slice`, `List.slice` and `Bytes.slice`. Debate covered the rest: clamp or panic for ranges (V1), `byte_at` out of range (V2), the `byte_index_of` signature (V3), closing the `byte_` set (V4), and six side items (V5a–V5f).

Position changes in round 1, from each seat's own reply below:

- **AI/ML** moved from panic to clamp for range reads.
- **Web** and **Min** moved `byte_at` from `-> Option[U8]` to panic.
- **Sys** moved its `byte_index_of` boundary rule from `None` to panic.
- **PLT** and **DevOps** came to support a `from` argument, with a `from` inside a codepoint panicking.

All six seats signalled STABLE after round 1.

<details><summary><b>Systems</b>, round 1 reply</summary>

**U1–U8:** I agree with all eight. No dissent.

**V1: clamp. I hold this position.** AI/ML is right that clamping hides an off-by-one. But the bug class that does real damage here is a cut inside a codepoint, which breaks the type's invariant, and U6 already makes that panic. What clamping hides beyond that is a short string, not memory or encoding damage. V1-panic also has a cost that AI/ML's own text names: "the runtime clamping merged in 71ba31ad must also become a panic, and every caller that relies on the clamp has to be audited". That is 222 substring callers plus ~58 `.slice(` callers, audited while the substring meaning flips at the same time. Two semantic changes in one migration is the risk DevOps warned about. Clamping keeps step 1 a rename with no change in behaviour. If the panel votes for panic, I still accept it under U8 (one rule for all four); my only hard line stays "no mixing".

**V2: panic, keep `-> U8`. I hold this position.** To Web and Min: I concede the cost argument. The Option-fusion measurement shows gcc -O2 removes the Option, so this is not about cycles. My reasons are these:
1. The loop guard `i < byte_len()` already proves the precondition. PLT's R1 states it exactly: a point read whose return type cannot express failure panics, and it never makes up a value.
2. `?? 0` is the idiom Min proposes, and 0 is a real byte value (NUL). A default that is also valid data quietly turns a bug into a wrong answer. That is the same objection AI/ML has to clamping, applied here.
3. The 121 `.unwrap()`s that Option forces add no information.

I support DevOps's sentence at :449 that names `byte_` as the documented exception.

**V3: `from`. I hold this, with a fallback.** Web says YAGNI "until a real caller needs it". Real callers exist today: `lib/std/str.bl:193` and `:232` (split, replace) call `str_index_of_from` through FFI, because a delimiter scan without a start offset either re-scans the prefix (O(n²)) or allocates a slice per step. The first lexer or TOML reader a user writes in Blink has the same need, and without the offset they must reach for FFI. One signature with `from` covers both cases: `s.byte_index_of(x, 0)` is the plain form. Fallback: if the majority wants the plain form, then add `byte_index_of_from` by panel vote as soon as a non-stdlib caller appears, and record that plan in the decision now. I do not want a codepoint `index_of_from`. A codepoint offset forces an O(n) walk before the search, which defeats the purpose.

**V4: close the set. I am neutral, leaning yes, if it is recorded in DECISIONS.md and not in sections/.** The spec says what the language is. Panel procedure is governance, not semantics. My V3 signature keeps the set at four.

**V5:**
- a: In this decision, one sentence: "every safe path that makes a Str gives valid UTF-8; Bytes.to_str validates (it already returns Result); an @ffi/@trusted boundary is the caller's obligation." Anything to enforce at FFI goes in a follow-up ticket.
- b: In this decision. It changes one cell of the table and costs nothing, and without it `i < s.len()` loops go O(n²) after the flip.
- c: A follow-up ticket. It is useful, but it is lint design, not spec.
- d: Record it as a deferral, as PLT asks. That costs nothing.
- e: Nowhere. Rust's `get(a..b)` is worth adding only once a caller exists.
- f: An implementation ticket, not spec text. jcfqh6 already holds the 3-step order, and DevOps's `@deprecated(fix:)` codemod step belongs there too.

**STABLE, ready to vote.**

</details>

<details><summary><b>Web/Scripting</b>, round 1 reply</summary>

**U1–U8:** I agree with all eight. No dissent. Thanks for the fact correction on :657; it makes U6 a property of the type, not a new rule.

**V1: clamp.** AI/ML is right that a clamp hides an off-by-one. But the most common slice in scripting code is "first n chars or fewer": `title.substring(0, 80)`. That is idiomatic in Python and JS, and both humans and models write it with the intent to clamp. Under V1-panic, code that is correct by intent crashes on short input, and users fix it by adding `min(80, s.len())` at every site. That fix is the clamp, done by hand. V1-panic also needs a runtime change plus an audit of the 222 callers, and it gains nothing that the codepoint-boundary panic (U6) does not already give for the real data-loss case. I agree with Sys that a mix of the two rules is the worst result.

**V2: I change my vote to panic,** with two conditions. Sys made the point that changed my mind: under `?? 0` a missing byte and a real NUL byte look the same, so the Option gets turned back into a sentinel at every site. PLT's rule also reads well to a newcomer: "a point read never makes up a value: Option where the type can say so, else panic." Every `byte_at` loop already checks `i < s.byte_len()`, so `== Some(37)` at 121 sites is noise with no safety gain. The conditions:
- (a) DevOps's sentence at :449 names the `byte_` methods as the low-level exception.
- (b) The panic message names the index and `byte_len`. Without (a), a user who reads :449 asks "why does this read panic?"

Min, your Option version stays consistent with `Bytes.get`. I think the NUL collision outweighs that.

**V3: plain, and no required `from`.** Blink has no overloading (02_syntax.md:716). So Sys's form puts `, 0` on every simple call (`path.byte_index_of("/", 0)`), which is the 90% case. That is a cost every user pays, to help a few lexer loops. The scan from an offset is real: `str_index_of_from` exists and str.bl:193/:232 use it. But it is a std-internal helper today. If a user-facing caller appears, add `byte_index_of_from` under its own name and its own ticket. That also fits V4.

**V4: accept.** One sentence closing the `byte_` set costs nothing and stops `byte_starts_with` and the like from growing. Any spec change needs a vote anyway, so this mostly states intent. That is fine.

**V5:**
- a) **In this decision, one sentence:** "every safe path that builds a Str validates UTF-8". Without it, U6/U7 do not hold. An FFI audit goes in a follow-up ticket.
- b) **In this decision.** Mark `len()` O(n) in the table. It is one word, and it stops `while i < s.len()` loops in byte code.
- c) **Follow-up ticket.** The unit-mix lint is a good idea but not spec.
- d) **Note in the decision record as deferred, not rejected.** Nothing in sections/.
- e) **Nowhere (YAGNI).** AI/ML does not recommend it either.
- f) **The decision record states one constraint:** `substring` flips to codepoints only after every byte caller is on `byte_slice`. The steps themselves go in an implementation ticket. They are not spec text.

**STABLE, ready to vote.**

</details>

<details><summary><b>PLT</b>, round 1 reply</summary>

**U1–U8:** I agree with all of them. On U8: `byte_slice` follows the shared range rule and also panics when a bound splits a codepoint (U6). That extra panic is not a second range rule. It protects the `Str` invariant, which `List` and `Bytes` do not have.

##### V1: clamp
Both rules are sound, so soundness does not decide this. What decides it is what each rule gives us. Clamp makes every slice a total function. It is idempotent and monotone, so for every `a <= b <= c` (in range or not) this holds:
`s.substring(a, b).concat(s.substring(b, c)) == s.substring(a, c)`
Panic makes slice a partial function whose precondition the caller must prove at every site.

AI/ML is right that clamping hides an off-by-one. But a short result is a real value with a defined meaning; the clamp makes up nothing. Point reads are where made-up values are the danger, and I keep those strict (V2). Clamp also matches the runtime today (71ba31ad) and Python/JS slicing. I agree with Sys: mixing the two rules is the one outcome I reject. If the panel picks panic, it must cover all four range methods.

##### V2: panic, with Option as an acceptable second choice
Min and Web are right that `Option[U8]` is sound, and it is more uniform. My rule R1 ("a point read never makes up a value: it returns Option, or it panics") allows both. Clamping is the only option I reject. I still prefer panic for three reasons:
- `byte_at` is the indexing primitive inside loops that `byte_len()` already bounds, so an Option only repeats a proof the caller has already done.
- `?? 0` makes up a NUL byte (Sys), which is exactly the made-up value R1 forbids, and it will become the common idiom.
- `Bytes.get` already serves code that wants an Option.

If V2-panic wins, I support the DevOps sentence at :449 naming `byte_` as the exception.

##### V3: accept `from`, but change Sys's edge rules
Sys has evidence (`blink_str_index_of_from`, str.bl:193/:232) that the hot path needs `from`, so this is not YAGNI. Signature: `byte_index_of(self, needle: Str, from: Int) -> Option[Int]`.
- `from < 0` becomes 0 and `from > byte_len()` gives `None`. `from` is a range start, so the V1 rule applies to it.
- **A `from` inside a codepoint panics. It does not give `None` as Sys proposes.** `None` means "not found". Returning it for a bad offset puts two different results into one value, and that hides the same bug class as U6. A panic here is consistent with U6.
- Corollary: a non-empty valid UTF-8 needle can only match at a codepoint boundary, because its first byte is never a continuation byte. So every `Some(i)` is a valid `byte_slice` bound. The spec should say this, because it is what makes the U5/U1 pairing safe.
- An empty needle returns `Some(from)` after clamping. This is well-defined only because a `from` inside a codepoint has already panicked.

The codepoint `index_of` gets no `from` for now (YAGNI).

##### V4: no
Every spec change already needs a panel vote. Writing that rule into the spec text for one prefix adds a rule about the process, not about the language. I abstain if the vote is close.

##### V5
- **a:** Belongs in this decision. If any constructor skips validation, U7 is false. `Bytes.to_str` already validates. Auditing the FFI constructors goes to a follow-up ticket.
- **b:** Yes. It is one table cell, and the prose already says O(n).
- **c:** Follow-up ticket.
- **d:** Put it in the decision record as a deferral, so a later ticket can cite it.
- **e:** Nowhere (YAGNI). AI/ML does not recommend it either.
- **f:** Implementation ticket, not spec text. The decision should still record one constraint: `substring` must not have both meanings in one release. Byte callers move to `byte_slice` before the flip.

STABLE, ready to vote.

</details>

<details><summary><b>DevOps</b>, round 1 reply</summary>

**U1-U8:** I agree with all of them. On U7: I accept the correction (03_types.md:657). The invariant already exists, so U6 enforces it and does not add it.

##### V1: clamp (I keep this position)
AI/ML is right that clamping gives no signal on an off-by-one. Against that:
1. Today the runtime clamps all four slices (71ba31ad). If we change to a panic, we must audit about 280 callers (222 substring plus the `.slice(` callers) for code that relies on the clamp, and do it during the same migration that flips substring's unit. Two semantic changes in one migration means that a test failure cannot tell you which change broke it.
2. "The first n or fewer" (`substring(0, 80)`) is a real idiom. With a panic, every such caller must write `.min(len)`, which is a clamp written by hand.
3. Python and JS users, and LLMs trained on them, already know "indexing fails, slicing clamps".

Sys says mixing the two rules is the one choice to avoid, and I agree. If the panel picks panic, it must apply to all four slices, and the runtime change must land as its own step, before the unit flip.

##### V2: panic, and keep `-> U8` (I keep this position)
Web and Min make the strongest argument against me: the spec has no index operator, so a panicking `byte_at` would be the only read that panics. I accept that this is a cost. But consider what the Option does in practice:
- `s.byte_at(i) ?? 0` turns an out-of-bounds read into a NUL byte without any signal. That is a clamp at a single point, which is the exact bug AI/ML objects to in V1.
- `.unwrap()` gives "called unwrap on None", with no index and no length. That message is worse than `blink: str byte_at index out of bounds: idx=7 byte_len=5`.

Almost every one of the 154 callers is already inside a loop bounded by `i < byte_len()`. So the Option adds noise and does not catch real bugs. The 03_types.md:449 text needs one sentence: "`byte_` methods are the raw-access layer; `byte_at` panics out of bounds." Min's fallback is also panic, so I count Min as acceptable here.

##### V3: take `from` as the only signature, but panic off a codepoint boundary
Sys points to a real caller: `blink_str_index_of_from`, used at str.bl:193 and :232. So YAGNI does not apply. Use one signature, `byte_index_of(needle, from)`, with callers that start at the beginning passing 0. Two names for one search would be more surface, and Blink has no overloading. I disagree with one detail from Sys: a `from` inside a codepoint must **panic**, not return None. A None looks like "not found", so a caller bug looks like a correct result. A panic matches U6. A negative `from` clamps to 0, and a `from` past the end gives None. Both follow the V1 clamp. `index_of` gets no `from` until a caller needs it.

##### V4: no spec text
A rule that says "this needs a panel vote" is a process rule, not language semantics. Record it in DECISIONS.md as a policy if Min wants it. I do not oppose that.

##### V5
- **a:** Part of this decision, because the spec must say that the invariant covers every constructor. The check of the Bytes/FFI paths is a follow-up bug ticket.
- **b:** Part of this decision. It is a one-cell edit to the table, and the prose already says O(n).
- **c:** Follow-up ticket. The rule does not depend on it.
- **d:** Record it in the decision as a deferral. It needs no spec text.
- **e:** Nowhere. YAGNI. AI/ML does not recommend it either.
- **f:** The decision record must state the order constraint: no codepoint `substring` until no caller uses the byte meaning. Without that constraint we get a silent change of meaning. The details go in an implementation ticket, not in sections/. The fix to the code drift in traits.bl (`byte_at -> Int`, `index_of -> Int`, `substring(start, len)`) goes in that same ticket (Web, Min).

**STABLE, ready to vote.**

</details>

<details><summary><b>AI/ML</b>, round 1 reply</summary>

**U1-U8:** I agree with all eight. No dissent.

##### V1: I change from panic to clamp

Web, PLT and Min gave me an argument from my own field that my Phase A missed. The most common string idiom a model writes is a truncation such as "first n chars": `s[:n]` in Python and `s.slice(0, n)` in JS. Models will write `s.substring(0, 80)` without first checking the length. With panic, that line compiles, passes a test on long input, and crashes in production on the first short string. That is the same class of silent-until-production fault I wanted to stop, and panic causes it more often than clamp does, because the truncation idiom is far more common in training data than a true off-by-one. PLT's law (concatenation holds for every `a <= b <= c`) also makes clamp predictable from the spec alone. Panic remains possible, but Sys accepts S2 only conditionally, and 5 of 6 seats chose clamp.

I agree with Sys that the rule must be the same for every range read. These conditions are still firm for me:
- `start > end` gives empty. No swap. JS `substring` swaps, and a model must not get that behaviour from us.
- A negative index clamps to 0. No count-from-end. I agree with Web: `i - 1` at 0 must not silently change meaning.
- The spec sentence lists all four methods by name and shows `"abc".substring(0, 99)` gives `"abc"` as an example. A model learns this rule from one example faster than from prose.

##### V2: panic, keep `-> U8`

I agree with Sys, PLT and DevOps. Min and Web: `Option[U8]` adds about 150 `.unwrap()` or `?? 0` sites. Models write `?? 0` by reflex, and Sys is right that 0 is a real NUL byte, so `?? 0` is silent wrong data in a lexer. A panic with the index and `byte_len` in the message is better for both humans and models. I support DevOps's sentence at :449 that names `byte_` methods as the one exception to "a read never panics". One documented exception costs less to learn than an unwrap at every hot site.

##### V3: plain `byte_index_of(self, needle: Str) -> Option[Int]`

YAGNI, as Web says. Sys's `from` form has three edge rules (negative, past end, off a boundary), and models will guess them wrong. If byte code later needs a start offset, add it in a separate ticket, with a parallel `index_of(needle, from)` so the two stay mirrored.

##### V4: I accept Min's statement

A closed set of four helps a model: "the `byte_` methods are exactly these four" is a fact it can memorise. The "needs a panel vote" clause adds nothing, because every spec change already needs one. Keep the list and drop that clause.

##### V5

- **a: in this decision, one sentence.** :657 already makes the invariant normative. Say that every Str constructor (from Bytes, FFI, literals) establishes it. Validation work goes in an implementation ticket.
- **b: yes.** Mark `len()` O(n) in the table. Models put `s.len()` in loop conditions, so they must see the cost.
- **c: follow-up ticket.** A unit-mix lint is the best defence against the codepoint/byte pairing mistake models make. It is not spec text.
- **d: record it as deferred.** I have no objection.
- **e: nowhere.** I withdraw my Proposal B.
- **f: implementation ticket.** The decision record names the hazard in one line: `substring` changes from (byte start, byte count) to (codepoint start, codepoint end), and that change must not happen until byte callers move to `byte_slice`. Both meanings must not exist in one tree.

**STABLE, ready to vote.**

</details>

<details><summary><b>Minimalism</b>, round 1 reply</summary>

**U1–U8:** no dissent.

**V1 (range reads): clamp.** No change. AI/ML says a panic finds bugs. That is true for an index read. For a range, clamping has correct uses ("the first n or fewer", "the rest after i"), and the runtime clamps all four slices today, so the clamp rule changes no code. A panic rule would turn every one of about 220 slice sites into a site that can panic, and we would need to audit each one. I agree with Sys that a mix of the two rules is the one bad result.

**V2 (byte_at): I change my vote to V2-panic.** Two arguments convinced me:
- Sys: `?? 0` makes a 0 sentinel that is the same as a real NUL byte. My own example used `?? 0`, so the Option form invites a quiet bug at every hot site.
- PLT R1: "a point read never makes up a value. If the return type can express failure, give None. If not, panic." With this rule, `byte_at` is no exception to `:449`. The return type decides. `List.get`, `Bytes.get` and `char_at` return Option, and `byte_at` returns U8, so it panics.

For a minimalist, panic is also the smaller change. The spec signature `-> U8` stays as it is. Only the code drift (`traits.bl:57 -> Int`) changes. I ask the panel to write PLT's R1 at `:449` in place of DevOps's "the `byte_` methods are an exception" sentence. A general rule is better than a named exception.

**V3 (byte_index_of): plain `(needle) -> Option[Int]`.** Sys is right that a search from an offset is a real need. But its only callers today are `split` and `replace` in `lib/std/str.bl:193` and `:232`, and they use the private FFI helper `str_index_of_from`, which can stay. No public caller needs `from` yet. A user scanner can `byte_slice` and then search. Also, a `from` on `byte_index_of` but not on `index_of` would make the two methods differ in shape. Add `from` with its own vote when a caller outside the stdlib needs it. This is a weak position: if Sys and PLT both still want `from`, I will not block it.

**V4 (close the `byte_` set at four):** I keep this. It costs one sentence and stops `byte_` from growing a second copy of StrOps, with a byte version of each search method. If the panel thinks the panel-vote clause is process noise, I accept "the `byte_` set is these four methods" with no clause.

**V5:**
- a) UTF-8 at every constructor: **a follow-up ticket.** The invariant is already spec text (`:657`). Code that breaks it is a bug, not a spec question.
- b) Mark `len()` as O(n) in the table: **yes, in this decision.** The prose at `:92` already says this. The table should not hide it.
- c) W-unit-mix lint: **nowhere in this decision.** File it as friction if the flip produces real unit-mix bugs. YAGNI.
- d) Record `ByteOffset`/`CharIndex` as deferred: **yes, one line.** It costs nothing, and it keeps the question open without adding surface.
- e) Option range forms (`get_slice`): **reject.** Even AI/ML does not recommend them, and they double every range method.
- f) Migration order: **an implementation ticket, not spec text.** The spec describes the end state, not the steps to get there. DevOps's codemod and order belong on the chore.

**STABLE, ready to vote.**

</details>

#### Phase C — Final vote

##### Q0: confirm U1–U8, mark `len()` O(n), defer nominal index types, no Option range forms (**6-0 A**)

- **Systems:**

  **Q0: A (confirm)**
  Reasoning: The package matches what I stated in round 1. Marking `len()` O(n) in the table is the cost note that stops `i < s.len()` loops going quadratic after the flip.
  Concern: The deferral of `ByteOffset`/`CharIndex` could be read later as a rejection unless the record says "deferred: arithmetic friction in byte loops", not "rejected".

- **Web/Scripting:**

  **Q0: A (confirm)**
  Reasoning: I stated every item in round 1 and still agree with each. The O(n) mark on `len()` matters most for my users. A Python dev writes `while i < s.len()` without thinking and needs to see the cost in the table.
  Concern: The deferral of `ByteOffset`/`CharIndex` gets read as a promise, and people ask "when?" in issues.

- **PLT:**

  **Q0: A (confirm)**
  Reasoning: I stated every item in the package in round 1. U6 and U7 together make `Str` a type with an invariant the code actually enforces. V5d keeps the nominal index types available as the principled end state.
  Concern: U7 holds only if every constructor keeps the invariant (Q6). Without that, U6 protects a property that other paths already break.

- **DevOps:**

  **Q0: A (confirm).**
  Reasoning: Every item in the package is either one edit to a table cell or a line in the decision record, and every seat agreed to all of them in round 1. Marking `len()` O(n) also helps tooling: an LSP hover shows the cost where the call is made.
  Concern: The deferral of `ByteOffset`/`CharIndex` (V5d) can go stale if no ticket cites it. Link it from the unit-mix lint ticket.

- **AI/ML:**

  **Q0: A (confirm)**
  Reasoning: every item in the package removes a decision point or a hidden cost that a model would otherwise guess at. Marking `len()` O(n) in the table matters most for my seat, because models copy `while i < s.len()` from Python and JS habits.
  Concern: a model reads only the table and not the prose, so the O(n) mark has to be in the table cell itself, not in a footnote.

- **Minimalism:**

  **Q0: A (confirm)**
  Reasoning: U1–U8 remove two names (`substr`, `Str.slice`) and add two (`byte_slice`, `byte_index_of`) that the language cannot do without. The surface does not grow. V5b changes one table cell. V5d is a note with no surface, and V5e keeps the range methods from doubling.
  Concern: "deferred, not rejected" for nominal index types can turn into a standing promise that later panels feel they must keep.

##### Q1: out-of-range rule for range reads (**6-0 A, clamp**)

- **Systems:**

  **Q1: A (clamp)**
  Reasoning: Clamping is total, two compares with no branch in C, and it is what all four runtime slices do today. So the first migration step is a rename with no change in behaviour, and the unit flip stays the only semantic change. The damage that clamping could hide (a cut inside a codepoint) already panics under U6.
  Concern: An off-by-one gives a short string with no signal. The test suite must cover the boundary cases, because the runtime will not catch them.

- **Web/Scripting:**

  **Q1: A (clamp)**
  Reasoning: `s.substring(0, 80)` means "80 or fewer" in Python and JS, and humans and models will write it that way. A panic makes code that is correct by intent crash on short input, and every fix is a clamp written by hand. Clamp is also what the runtime does today, so no caller changes behaviour.
  Concern: A real off-by-one gives a short string with no signal. Users find it late, in output and not in a test.

- **PLT:**

  **Q1: A (clamp)**
  Reasoning: Clamp is a total, monotone, idempotent projection, so `s.substring(a, b).concat(s.substring(b, c)) == s.substring(a, c)` holds for every `a <= b <= c`, in range or not. A truncated or empty result is a real value of the type, not a made-up one. With one rule for all four methods, the law holds across `Str`, `List` and `Bytes`.
  Concern: An off-by-one in a range now returns a short value with no signal. The spec must show the edge cases (`"abc".substring(0, 99)` gives `"abc"`, and `start > end` gives `""` with no swap) so that nobody mistakes the clamp for JavaScript's swap rule.

- **DevOps:**

  **Q1: A (clamp).**
  Reasoning: The runtime clamps today, so step 1 of the migration changes names only and not behaviour. That keeps a test failure during the substring unit flip pointing at one cause. The truncation idiom (`substring(0, 80)`) stays correct, and clamping produces no new runtime failures that users must learn to read.
  Concern: An off-by-one now gives a short string and no signal. Only tests or the unit-mix lint can catch it. No runtime message ever will.

- **AI/ML:**

  **Q1: A (clamp)**
  Reasoning: "first n chars or fewer" (`s.substring(0, 80)`) is the most common slice idiom in training data, and models write it without a length check. Clamp makes that code correct. Panic makes it crash on the first short input. The four bans (no swap, no count-from-end, start>=end gives empty, one rule for all four) remove the two JS/Python priors that would otherwise give silent wrong output.
  Concern: a model trained on JS `substring` may expect `(5, 2)` to swap; the spec must show `"hello".substring(5, 2)` gives `""` as an example, or that prior wins.

- **Minimalism:**

  **Q1: A (clamp)**
  Reasoning: one total rule, written once for four methods. It needs no runtime change and no audit of about 280 callers during the unit flip. "The first n or fewer" is a real idiom, and under panic every caller would write the clamp by hand. U6 already makes the one harmful case (a cut inside a codepoint) fail loudly.
  Concern: an off-by-one in byte code gives a short string with no signal, so a test must check the length to find it.

##### Q2: `byte_at` out of range (**6-0 A, panic and keep `-> U8`**)

- **Systems:**

  **Q2: A (panic, keep `-> U8`)**
  Reasoning: The loop guard `i < byte_len()` already proves the bound. The check is one unsigned compare that also catches negative indices, and the message carries the index and byte_len, which `.unwrap()` would lose. `?? 0` would make up a NUL byte, which is a real value.
  Concern: Today `blink_str_char_at` is a bare `s[i]`. If the implementation forgets the check in the inline fast path, the spec says panic while the C still reads out of bounds. Test it at index == byte_len and at a negative index.

- **Web/Scripting:**

  **Q2: A (panic, keep `-> U8`)**
  Reasoning: `?? 0` turns a missing byte into a real NUL byte, which is silent wrong data in a lexer. Every byte loop already checks `byte_len()`, so an Option only adds noise. A panic message with the index and `byte_len` tells a newcomer what they did wrong.
  Concern: A user who learned "reads never panic" from `List.get` is surprised, so the :449 text must make the rule clear.

- **PLT:**

  **Q2: A (panic, keep `-> U8`)**
  Reasoning: A point read must never make up a value. `U8` cannot express absence, so an out-of-range index is a broken precondition, and the loop guard `i < byte_len()` already proves that precondition. The Option form gets turned back into a sentinel through `?? 0`, and that sentinel collides with a real NUL byte.
  Concern: Callers that want a read that cannot panic must go through `Bytes.get`. That should be stated once in the spec so it does not appear to be an oversight.

- **DevOps:**

  **Q2: A (panic, keep `-> U8`).**
  Reasoning: The message `blink: str byte_at index out of bounds: idx=7 byte_len=5` is a better diagnostic than `.unwrap()` on None, and better than a silent NUL from `?? 0`. All 154 callers already check `i < byte_len()`, so an Option would add noise with no gain.
  Concern: The panic text must name the method, the index and byte_len, in the same format as `blink_list_index_oob`. If it falls back to a generic panic, most of the reason to choose this option is gone.

- **AI/ML:**

  **Q2: A (panic, keep `-> U8`)**
  Reasoning: with `Option[U8]`, models would add `?? 0` by reflex at every hot site, and 0 is a real NUL byte, so a bug becomes silent wrong data. A panic that names the index and `byte_len` is loud and easy to diagnose. Byte loops already prove the bound with `i < s.byte_len()`.
  Concern: `byte_at` is the only `Str` read that panics, so a model that generalises "Blink reads give Option" will write `match s.byte_at(i) { Some(b) => ... }` and get a type error. That error is loud, but it costs a model one retry.

- **Minimalism:**

  **Q2: A (panic, keep `-> U8`)**
  Reasoning: this keeps the spec signature as it is, so it is the smallest change. `?? 0` makes a NUL byte look like real data (Sys), and the loop guard already proves the bound. Code that wants an Option has `Bytes.get`.
  Concern: `byte_at` becomes the only read in the spec that can panic. Without the Q3 sentence, users will think it is an inconsistency.

##### Q3: the text at the `List.get` rationale (**6-0 B, general rule**)

- **Systems:**

  **Q3: B (general rule)**
  Reasoning: PLT's R1 makes `byte_at` follow from its return type, not from a named exception, so the rule needs no updating when another point read is added. It says the same thing about the code the C compiler gets as DevOps's sentence does, in one rule.
  Concern: A reader may not see that `byte_at` panics unless the method table also says so. Keep "panics out of bounds" in the `byte_at` row as well.

- **Web/Scripting:**

  **Q3: B (general rule)**
  Reasoning: A newcomer can predict the behaviour from the signature alone: `Option` means `None`, a bare type means a panic. One rule they can apply is easier to learn than a list of exceptions to memorise. It also covers any future point read without new text.
  Concern: The rule is abstract. Without a short `byte_at` example next to it, users still ask why `byte_at` panics and `char_at` does not.

- **PLT:**

  **Q3: B (state the general rule)**
  Reasoning: A rule the type determines (Option where the return type can say absent, panic where it cannot) explains `List.get`, `Bytes.get`, `char_at`, `byte_at` and `List.set` from a single principle. A named exception explains only one method, and the next raw read will need another exception.
  Concern: Someone can read the rule as permission to add any bare-typed read that panics. The text should keep the clause "never makes up a value" so that clamping a point read stays forbidden.

- **DevOps:**

  **Q3: B (the general rule).**
  Reasoning: I wrote option A, but Min and PLT's rule is better for docs and hover text. It explains every point read we have, and every future one, with one sentence and no exception list. A user who reads `-> U8` in the signature can predict the panic without memorising an exception.
  Concern: The phrase "makes up a value" must have an example beside it (`byte_at` panics, `char_at` gives None). Without one, readers may take it as a rule about clamping ranges.

- **AI/ML:**

  **Q3: B (general rule)**
  Reasoning: a model learns a rule it can apply to any method faster than a list of exceptions. "A point read returns Option when its type can say absent, and otherwise panics" predicts the behaviour of every current and future method from its signature alone. A named exception only covers `byte_at`, and a model has to memorise it.
  Concern: the general rule is abstract, so the sentence must name `byte_at` as its example. Without that, a model reading :449 still does not connect it to `byte_at`.

- **Minimalism:**

  **Q3: B (general rule)**
  Reasoning: one general rule ("a point read never makes up a value: Option when the type can say absent, otherwise panic") covers List.get, Bytes.get, char_at and byte_at, with no special cases. A named exception for `byte_` is a second rule that later methods will cite to justify more exceptions.
  Concern: if A wins, the sentence that names `byte_` as an exception will become the precedent that the next "raw" method cites to panic without discussion.

##### Q4: `byte_index_of` signature (**3-3 A/B, went to Phase D**)

- **Systems:**

  **Q4: B (`from`; a `from` inside a codepoint panics)**
  Reasoning: The hot path needs a search from an offset (`blink_str_index_of_from`, str.bl:193/:232). Without it, a scanner re-scans its prefix or allocates a slice per step. I move from C to B: PLT and DevOps are right that None for a bad offset puts "bug" and "not found" in one value, and a panic is consistent with U6. The boundary check is O(1), one byte load.
  Concern: If A wins, users will write `s.byte_slice(i, n).byte_index_of(x)` in loops, which is an alloc and copy per step, and is O(n²) on long input.

- **Web/Scripting:**

  **Q4: A (no `from`)**
  Reasoning: Blink has no overloading, so `from` would add `, 0` to the most common call. That cost falls on every user, for the few lexer loops that need it. The std-internal `str_index_of_from` covers today's real callers. Add `byte_index_of_from` by vote when a caller outside std appears.
  Concern: The first user lexer either slices per step (allocation) or rescans, and no public API offers a fix until a follow-up lands.

- **PLT:**

  **Q4: A (plain, no `from`)**
  Reasoning: I change my round-1 position. Web pointed out that Blink has no overloading (02_syntax.md:716), so B puts `, 0` on every common call to serve a hot path that today only stdlib uses, through the private `str_index_of_from`. Both forms are sound. If a public `from` form is added later under its own name, the rule from my round 1 still binds it: a `from` inside a codepoint panics, never `None`. The corollary holds for A: a non-empty valid needle matches only at a codepoint boundary, so every `Some(i)` is a valid `byte_slice` bound. The spec should state that.
  Concern: User scanners will write `s.byte_slice(i, n).byte_index_of(x)` and pay an allocation per step until a `from` form exists.

- **DevOps:**

  **Q4: B (`from` required; a `from` inside a codepoint panics).**
  Reasoning: Real scanners need a start offset. Without one, user code does `byte_slice` and then a search, then adds the offsets back by hand (`i + found`). That is a common source of off-by-offset bugs, and it allocates on each step. The panic on a bad boundary matches U6, so None always means "not found".
  Concern: If A wins, a user lexer either goes O(n²) or reaches for FFI. Record in the decision now how a `from` form gets added later.

- **AI/ML:**

  **Q4: A (plain, no `from`)**
  Reasoning: Blink has no overloading, so a required `from` adds `, 0` to the 90% case. Models will also expect `index_of` and `byte_index_of` to have the same shape, and a `from` on only one of them breaks that expectation. The real `from` callers today are inside std and use a private helper. Add `byte_index_of_from` under its own name when a public caller needs it.
  Concern: user lexers will search with `s.byte_slice(i, n).byte_index_of(x)`, which allocates each step, or re-scan from 0, which goes quadratic. If that pattern shows up, the `_from` form must follow quickly.

- **Minimalism:**

  **Q4: B (`from`, a `from` inside a codepoint panics)**
  Reasoning: I change from round 1. Blink has no overloading (Web), so the plain form now means `byte_index_of_from` later, a fifth `byte_` name that breaks the Q5 set. One signature with `from` stays at one method permanently. Its edge rules add nothing new: a negative `from` is the Q1 clamp, and a `from` inside a codepoint is the U6 panic. A panic is right because None would mix up "not found" and "bad offset" (PLT, DevOps).
  Concern: `, 0` at every simple call is permanent noise, and models may pass a codepoint index from `index_of` as `from`. It panics only when it lands inside a multi-byte codepoint, so most mixed-up values pass with no error.

##### Q5: closing the `byte_` method set (**3-3 A/C, went to Phase D**)

- **Systems:**

  **Q5: C (DECISIONS.md only)**
  Reasoning: The spec describes the language. A rule about which methods need a panel vote is process, not semantics, and every spec change already needs a vote.
  Concern: Without spec text, a later contributor may add `byte_starts_with` and the like as stdlib conveniences without seeing the record.

- **Web/Scripting:**

  **Q5: A (list the four, no process clause)**
  Reasoning: "The `byte_` methods are exactly these four" is one fact a user can learn and that the LSP completion confirms. The process clause is governance, and every spec change already needs a vote.
  Concern: The list gets read as frozen forever, and a real need such as `from` stalls.

- **PLT:**

  **Q5: C (DECISIONS.md only)**
  Reasoning: The method table in sections/ already lists the `byte_` methods. A sentence saying "exactly these four" repeats the table, and a clause about panel votes is governance, not language semantics. A record in DECISIONS.md keeps the intent and adds no spec text.
  Concern: Without spec text, a future change could add `byte_` methods quietly. Reviewers must check the DECISIONS.md entry.

- **DevOps:**

  **Q5: C (DECISIONS.md only).**
  Reasoning: The spec should describe the language, and a closed list is a policy about how the language grows. A row in DECISIONS.md gives the same protection and does not need a spec edit each time the set changes.
  Concern: If A wins, the spec list and `traits.bl` can drift apart. A per-module invariant check in ci-release should compare them.

- **AI/ML:**

  **Q5: A (spec sentence, no process clause)**
  Reasoning: "the `byte_` methods are exactly these four" is one fact a model can store and check, and it stops models from inventing `byte_starts_with` or `byte_split` from the prefix pattern. The process clause tells a model nothing about the language.
  Concern: if a fifth method (such as `byte_index_of_from`) is added later and this sentence is not updated, the spec contradicts itself and models trust the wrong part.

- **Minimalism:**

  **Q5: A (spec sentence, no process clause)**
  Reasoning: "the `byte_` methods are exactly these four" is a fact about the language that both readers and models can memorize. PLT and DevOps are right that the vote clause is process, not semantics, so I drop it.
  Concern: a closed list in sections/ can make a legitimate fifth method look like a spec violation, not a normal amendment.

##### Q6: UTF-8 invariant reaching every `Str` constructor (**5-1 A**, Min dissent)

- **Systems:**

  **Q6: A (one sentence + audit ticket)**
  Reasoning: The `byte_slice` panic and the `byte_index_of` corollary are only sound if every safe constructor gives valid UTF-8. That belongs in the spec beside them, with the @ffi/@trusted boundary named as the caller's obligation. `Bytes.to_str` already validates.
  Concern: FFI-returned strings (env, argv, OS paths) may hold invalid UTF-8. The audit must decide whether to validate them at the boundary, at the cost of one O(n) pass per crossing.

- **Web/Scripting:**

  **Q6: A (one sentence plus an audit ticket)**
  Reasoning: The guarantee only helps users if it covers every way to get a Str. One sentence makes clear that FFI is the caller's obligation, so a broken Str has one place to blame.
  Concern: The FFI audit ticket sits idle, and the sentence promises more than the runtime gives.

- **PLT:**

  **Q6: A (one spec sentence plus an audit ticket)**
  Reasoning: A type invariant is a statement about every inhabitant, so the spec must say that every safe constructor establishes it. Otherwise U6 is not enough to guarantee it. Putting the obligation at the @ffi/@trusted boundary matches how the trust system already assigns responsibility.
  Concern: Until the audit closes, the spec promises a property that some code paths (raw FFI string builders) may not deliver.

- **DevOps:**

  **Q6: A (one sentence plus an audit ticket).**
  Reasoning: U6's boundary panic and U7 only hold if every safe constructor validates. The spec must say where the caller's obligation starts (@ffi/@trusted), so that a diagnostic or an audit has a line to check against.
  Concern: The FFI audit ticket may find constructors that do not validate today. Until they are fixed, the spec claims more than the runtime does.

- **AI/ML:**

  **Q6: A (one sentence + audit ticket)**
  Reasoning: U6 and the codepoint methods are only correct if every Str is valid UTF-8. A model reasons from the spec text, so the spec should say which paths guarantee validity and that @ffi/@trusted code must keep it.
  Concern: until the audit lands, an FFI path can produce an invalid Str, and the spec sentence says something the runtime does not yet ensure.

- **Minimalism:**

  **Q6: B (follow-up ticket only)**
  Reasoning: `:657` already says that Str guarantees UTF-8 validity. A second sentence restates it, and the FFI obligation clause belongs in the FFI/trust section, not in Str. The work that makes the invariant true is the audit, and that is a ticket.
  Concern: if A wins, the FFI obligation text lives in the Str section and drifts from the @trusted rules in sections/07.

##### Q7: migration order constraint (**6-0 A, in the decision record**)

- **Systems:**

  **Q7: A (constraint in the decision record)**
  Reasoning: Both the old and the new `substring` take `(Int, Int)`, so nothing fails to compile if both meanings coexist. That constraint is a property of this decision, not an implementation detail, so the record must state it.
  Concern: The flip is one large commit (four methods at once). If the gate is slow or flaky, someone may be tempted to split it, which would reopen the window where both meanings exist.

- **Web/Scripting:**

  **Q7: A (state it in the decision record)**
  Reasoning: A silent change of meaning in `substring` is the worst outcome for users, because the same call compiles and does something else. One line in the record keeps whoever does the work from flipping too early.
  Concern: Nothing has to read the decision record, so the constraint must also be copied into the implementation ticket.

- **PLT:**

  **Q7: A (state it in the decision record)**
  Reasoning: Two meanings for one name in a single tree is a soundness hazard at the source level. `(Int, Int)` type-checks under both meanings, so no checker can catch it. It belongs in the decision record as a constraint, and the steps belong in the ticket.
  Concern: The constraint is only text. A partial migration could still land unless the ticket checks that no caller uses the byte meaning before the flip.

- **DevOps:**

  **Q7: A (decision record).**
  Reasoning: This is the one change in the package that no compiler, lint or LSP can catch: same name, same arity, a different meaning. It must be written where every implementer reads it, not only in one ticket.
  Concern: The codemod's `(a, n)` to `(a, a + n)` rewrite is safe only for a pure `a`. Any other `a` needs a manual edit, and those sites are where the migration can go wrong.

- **AI/ML:**

  **Q7: A (decision record states the constraint)**
  Reasoning: if `substring` carries both meanings in one tree, the corpus that future models train on teaches both meanings, and the damage lasts longer than the migration. The constraint has to be visible where reviewers look, not only in a ticket.
  Concern: the implementation ticket could still do the flip as one large codemod, so tests that pass on ASCII input hide a wrong conversion; the codemod needs non-ASCII fixtures.

- **Minimalism:**

  **Q7: A (the decision record states the constraint)**
  Reasoning: a two-Int signature that changes meaning silently is the largest risk in this decision (DevOps). One line in the record costs nothing and adds no surface to sections/.
  Concern: a constraint that lives only in the decision record can be missed by whoever does the flip, so the implementation ticket must link to it.

##### Q8: unit-mix lint (**5-1 A, file a ticket now**, Min dissent)

- **Systems:**

  **Q8: A (file a follow-up ticket now)**
  Reasoning: Codepoint and byte indices are both plain `Int`, and only a lint or nominal types can catch a mix. With the nominal types deferred, the ticket is the only record of that gap. It costs nothing to file.
  Concern: Data-flow lints are hard to make precise. A noisy first version would teach users to suppress it.

- **Web/Scripting:**

  **Q8: A (file a follow-up ticket now)**
  Reasoning: Mixing a codepoint index with a byte slice passes ASCII tests and breaks on "é". That is the bug class with the most questions in this whole area. A ticket costs nothing and makes the follow-up plan concrete.
  Concern: The lint fires on correct code that converts between units on purpose, and users learn to suppress it.

- **PLT:**

  **Q8: A (file a follow-up ticket now)**
  Reasoning: With Q4=A and Q2=A, byte offsets and codepoint indices are both plain `Int`. The lint is the cheapest partial substitute for the deferred nominal types, and the flip of `substring` is exactly when unit-mix bugs will appear.
  Concern: Without type information, a dataflow lint will have false positives on arithmetic between the two units. Its scope must stay narrow, covering only direct flows from a method in one domain to a method in the other.

- **DevOps:**

  **Q8: A (file the ticket now).**
  Reasoning: Both units are `Int`, so the type checker cannot see a codepoint index passed to a byte method. A dataflow lint like W1401, with a machine-applicable swap to the matching method, is the cheap guard. It is most useful during the flip, which is why the ticket should exist before the flip.
  Concern: Intra-function dataflow misses a value that crosses a function boundary, so the lint gives partial coverage.

- **AI/ML:**

  **Q8: A (file the follow-up ticket now)**
  Reasoning: pairing a codepoint index with a byte slice is the most likely model error this decision leaves open. It compiles, passes on ASCII, and fails on real text. A lint is the only thing that catches it at compile time.
  Concern: a lint that tracks data flow between unit-typed calls can be noisy, and noise teaches models and users to suppress it; the ticket should say "direct flow only" for a first version.

- **Minimalism:**

  **Q8: B (nowhere now)**
  Reasoning: YAGNI. Q4's panic on a `from` inside a codepoint and U6 already catch some unit mixes at run time, though not all. A lint ticket without evidence of real bugs is backlog noise.
  Concern: unit-mix bugs on ASCII-only test input give no signal, so "file it when bugs appear" may mean we never see them.

#### Phase D — Round 2 (Q4 and Q5)

Both questions tied 3-3 in Phase C. Each seat wrote one focused argument after reading every seat's Phase C text, then all six arguments were relayed verbatim with one moderator fact: `sections/03_types.md:129` introduces the Str method table as "The full method surface". Then each seat re-voted.

##### Focused arguments

- **Systems:**

  **Q4: I hold B.** All three A voters (Web, PLT, AI/ML) wrote the same concern: user scanners will allocate per step or go quadratic. A knowingly ships that cost. B's cost is `, 0`, two tokens at the call site and zero at runtime. On "the real callers are inside std": std uses a private FFI helper because the public API cannot express the operation. That is the evidence of need, not an argument against it. Min's point decides it for me: with no overloading, A means a fifth name, `byte_index_of_from`, later. So we pay the migration and the naming twice. On AI/ML's shape argument: a codepoint `index_of` has no cheap `from` (it would be an O(n) walk), so the two methods already differ in cost. Different signatures make that visible.

  **Q5: I change to A, without the process clause.** I objected to process in sections/, and Min dropped that clause. "The `byte_` methods are exactly these four" is a fact about the language surface, not governance. AI/ML is right that it stops invented `byte_split`. It pairs with Q4=B. If Q4=A wins, the sentence becomes wrong when `_from` lands, which is another reason for B.

- **Web/Scripting:**

  **Q4: I change to B (`from` required; a `from` inside a codepoint panics).**
  Min showed that my Q4 A and my Q5 A do not fit together. With A, `byte_index_of_from` arrives later as a fifth name and breaks the closed set I voted for. All six of us also wrote the same concern under A: user lexers go O(n²) or allocate on every step. DevOps names the worse cost from my seat: users slice, search, then add the offset back (`i + found`). That off-by-offset bug produces the most questions in this area. JS `indexOf(x, fromIndex)` and Python `find(x, start)` already teach `from`, so a JS dev reads `s.byte_index_of("=", 0)` in seconds. `, 0` is small noise. A missing feature is a real gap.

  **Q5: I hold A (list the four, no clause).**
  PLT says the sentence repeats the table. It does not. The table lists what exists, and "exactly these four" tells users and models that the prefix does not extend to `byte_starts_with` or `byte_split`. The B vote on Q4 keeps the list true. DevOps's drift concern belongs in a ci-release check, which is cheap and not a reason to drop the sentence.

- **PLT:**

  **Q4: I change to B.** DevOps's point about adding offsets back by hand is a compositionality argument, and I gave it too little weight in Phase C. Under A, a scanner has to write `i + s.byte_slice(i, n).byte_index_of(x)?`. The search returns an offset into the slice, not into `s`, so every caller has to convert between the two by hand. That is where off-by-offset bugs come from, and it allocates on every step. Under B the result is already an offset into `s`, so it feeds `byte_slice(s, ...)` with no conversion. The plain case is `from = 0`, so B covers A as a special case and there is never a second method. Min is right that A means a fifth name later. The `, 0` is a real cost, but it is only syntax. The conversion bug is semantic. Min's concern is that a codepoint index passed as `from` slips past the check. That is the same mix-up of units as passing it to `byte_slice` under A, so A does not avoid it either. Q8 (the unit-mix lint) is what covers that mix-up. The `index_of` shape does not match `byte_index_of`, and I accept that: a codepoint `from` costs an O(n) walk (Sys).

  **Q5: I hold C, weakly.** Without the process clause, A is a true description of the language, and I would not block it. Its only cost is that the sentence can go stale while the method table stays correct (AI/ML's concern). C gives the same guidance without that risk.

- **DevOps:**

  **Q4: I keep B.** Web, PLT and AI/ML weigh the cost of `, 0`, but that cost is loud and paid once. A call that leaves it out fails to compile, and the error has a machine-applicable fix that inserts `, 0`, so the LSP writes it for the user. A's cost is silent and recurs. All three A seats name the same result in their own concern: `s.byte_slice(i, n).byte_index_of(x)` in a loop. That allocates on each step, and the caller must add `i` back to the result by hand. Leaving out `+ i` is an off-by-offset bug that compiles, passes on input with one match, and no diagnostic can see. Min is also right that A leads to a fifth name, `byte_index_of_from`, later. AI/ML's point about shape breaks nothing: `index_of` can take `from` by its own vote when a caller needs it.

  **Q5: I change to A.** Min and AI/ML gave me a tooling reason I missed. The no-method error for `s.byte_split(...)` can cite one normative sentence: "the `byte_` methods are byte_len, byte_at, byte_index_of, byte_slice". A record in DECISIONS.md cannot be cited in a diagnostic. My worry about drift is answered by the invariant check in ci-release. Under Q4=B, the list stays at four with no later edit.

- **AI/ML:**

  **Q4: I hold A.** Min's own concern decides this for me: a required `from: Int` is a slot that models will fill with the wrong unit. They will pass `index_of(...)` results or `len()`, and that passes silently unless it lands inside a multi-byte codepoint. The plain form has no such slot. DevOps's `i + found` risk is real, but it is one known pattern, and it is visible in the code. Sys's allocation cost is a performance cost, not wrong output. My seat ranks silent wrong output first. Min says A forces a fifth name later. That is true, but only if a public caller appears, and if it does, a vote that adds one name under its own ticket is the normal process.

  **Q5: I hold A.** PLT says the table already lists the methods. It lists them, but it does not say the list is complete, and "complete" is the fact that stops models from inventing `byte_starts_with` from the prefix pattern. DevOps's drift concern applies to every table in sections/, so it is not a reason to omit this one sentence. A later amendment edits one sentence; that is an ordinary spec change, not a violation.

- **Minimalism:**

  **Q4: I keep B.** Read the concerns of the three A seats. Web, PLT and AI/ML each predict that user lexers will slice per step or go quadratic until `byte_index_of_from` lands, and AI/ML says it "must follow quickly". So A is not the smaller surface. It is two methods with a delay between them, and B is one method. The edge rules of B are the Q1 clamp plus the U6 panic, so they add no new rule. AI/ML's argument about matching shapes does not hold: Sys showed that a `from` on the codepoint `index_of` costs an O(n) walk, so the two methods should differ. The cost of B is `, 0` at the plain call sites. That is one token, and it tells the reader where the search starts.

  **Q5: I change to C.** PLT is right. The `StrOps` table (03_types.md:129) is already introduced as "the full method surface", so it already lists the `byte_` methods as a closed set. A sentence saying "exactly these four" repeats the table. Repeated spec text is the thing my seat cuts, and it creates the drift risk that AI/ML and DevOps name. Record the intent in DECISIONS.md. The table is the normative list.

##### Q4 re-vote: `byte_index_of` signature (**6-0 B, `from` required**)

- **Systems:**

  **Q4: B (`from` required; from<0 clamps to 0, from>byte_len gives None, a `from` inside a codepoint panics)**
  Reasoning: The search returns an offset into `s` itself, so it feeds `byte_slice` directly with no allocation per step and no `i + found` conversion (PLT, DevOps). It is one method for good, and its edge rules reuse Q1 and U6. AI/ML says a bad `from` slips past silently. Under A, the same wrong unit slips past just as silently in `byte_slice`, so A does not remove that risk; Q8 covers it.
  Concern: The required `, 0` at every plain call could make users reach for the codepoint `index_of` out of habit, and that call is O(n) in byte code.

- **Web/Scripting:**

  **Q4: B (`byte_index_of(needle, from)`, `from` required)**
  Reasoning: Under A, all six seats predict the same bug: users slice per step and add the offset back by hand. That bug passes simple tests and is silent. B returns an offset into `s` that feeds `byte_slice` directly, and `from` is a parameter JS (`indexOf(x, fromIndex)`) and Python (`find(x, start)`) devs already know. DevOps's machine fix for a missing `, 0` makes the one cost of B cheap to pay.
  Concern: A model passes a codepoint index as `from` and gets a silent wrong start on non-ASCII text (AI/ML). The Q8 unit-mix lint has to cover `from` as well.

- **PLT:**

  **Q4: B (`byte_index_of(needle, from)`)**
  Reasoning: The result is an offset into `s` itself, so it can go straight into `s.byte_slice(...)` with no conversion. Under A, every caller has to add the slice start back by hand, and a missed `+ i` compiles and passes simple tests. B covers A as the case `from = 0`, so no second name is needed later. The edge rules are rules we already decided: the Q1 clamp and the U6 panic.
  Concern: A codepoint index passed as `from` is wrong but passes silently unless it lands inside a multi-byte codepoint (AI/ML). The Q8 unit-mix lint must cover `from` as a byte-domain argument.

- **DevOps:**

  **Q4: B (`from` required, from<0 clamps to 0, from>byte_len gives None, a `from` inside a codepoint panics).**
  Reasoning: B's cost, `, 0`, fails at compile time and has a machine-applicable fix. A's cost is the slice-search-add-offset loop: it allocates on every step, and a missing `+ i` is a bug no diagnostic can see. AI/ML is right that `from` is a slot that can take a value in the wrong unit. But A has the same slot in the `byte_slice(i, n)` it forces on the caller (PLT), and the Q8 unit-mix lint covers both.
  Concern: The panic for a `from` inside a codepoint must name the method, the offset and the codepoint it cuts. Without that, it is the only clue for a unit mix-up, and a bare panic wastes it.

- **AI/ML:**

  **Q4: B (`from` required; from<0 clamps, from>byte_len gives None, a `from` inside a codepoint panics)**
  Reasoning: I change my vote. My seat ranks wrong output with no error first, and DevOps and PLT showed that A has that fault: `i + s.byte_slice(i, n).byte_index_of(x)?` makes the caller add the offset back by hand. A missing `+ i` compiles, passes on input with one match, and gives wrong output. PLT is also right that the unit-mix slot I named exists under A as well, because a wrong-unit value can go into `byte_slice` just as easily; Q8's lint covers both. Python `find(x, start)` and JS `indexOf(x, from)` give models a strong prior for this shape, so `, 0` costs few tokens and few errors.
  Concern: models will pass an `index_of` or `len()` result as `from`, and on ASCII-only test input that gives correct results, so the Q8 unit-mix lint must cover the `from` argument.

- **Minimalism:**

  **Q4: B (`from` required)**
  Reasoning: one method covers the plain case (`from = 0`) and the scanner case, so we never add a fifth `byte_` name. Its edge rules reuse the Q1 clamp and the U6 panic. PLT's point settles the cost argument: under A, the result is an offset into the slice, not into `s`, and the caller must add `i` back by hand. B removes that bug class by design. AI/ML's wrong-unit slot also exists under A, at `byte_slice`, so A does not avoid it.
  Concern: a codepoint index passed as `from` panics only when it lands inside a multi-byte codepoint. Otherwise the search runs from the wrong offset with no signal, so the unit-mix ticket (Q8) carries real weight.

##### Q5 re-vote: closing the `byte_` method set (**4-2 A, spec sentence**; PLT, Min dissent)

- **Systems:**

  **Q5: A (spec sentence listing the four, no process clause)**
  Reasoning: Line 129 says "full method surface", but that is a claim about the table as it stands today, not a rule that the `byte_` prefix covers no further methods. DevOps's point decides it for me: a no-method error for `byte_split` can cite one normative sentence, and a DECISIONS.md row cannot be cited that way. Under Q4=B the list stays at four, so the sentence does not go stale.
  Concern: The sentence and the table can drift apart. The ci-release invariant check DevOps proposed must compare the sentence with `traits.bl`.

- **Web/Scripting:**

  **Q5: A (spec sentence listing the four, no process clause)**
  Reasoning: Min's fact is fair: the table is "the full method surface". But users read "full" as "what exists today", not "the prefix stops here". A one-line sentence also gives the no-method error for `s.byte_split(...)` a normative line to cite (DevOps), which helps a newcomer more than a DECISIONS.md row they will never open. With Q4=B, the list stays at four with no later edit.
  Concern: The sentence and the table drift apart. The ci-release invariant check must compare both with `traits.bl`.

- **PLT:**

  **Q5: C (DECISIONS.md only)**
  Reasoning: The moderator confirmed that 03_types.md:129 introduces the table as "the full method surface". The spec already states that the list is complete, so the set of `byte_` methods is closed by the table itself. A second sentence repeats a normative fact, and a repeated fact can go stale while the table stays correct. A diagnostic can cite the table as easily as the sentence.
  Concern: Readers who skim past the table's heading may not see that the list is complete. If A wins, the sentence should sit directly under the table and point to it.

- **DevOps:**

  **Q5: A (spec sentence listing the four, no process clause).**
  Reasoning: Min says the table at :129 already lists "the full method surface". That covers every Str method, though, and does not say the `byte_` prefix is closed. One sentence saying so gives the no-method error for `byte_split` and the like a direct, normative line to cite. With Q4=B, the list stays true without a later edit.
  Concern: The sentence and the table can drift apart. The ci-release invariant check must compare the spec list with `traits.bl`.

- **AI/ML:**

  **Q5: A (spec sentence listing the four, no process clause)**
  Reasoning: The table header says "full method surface", but a model learns a closed set faster from one direct sentence than from a table header. It also does not infer from the table that the `byte_` prefix does not extend to `byte_split` or `byte_starts_with`. DevOps's point decides it: a no-method diagnostic can cite a normative sentence, and it cannot cite DECISIONS.md. With Q4=B, the set stays at four, so the sentence does not go stale.
  Concern: the sentence and the table can drift apart, so the ci-release invariant check that DevOps proposed should compare both with `traits.bl`.

- **Minimalism:**

  **Q5: C (DECISIONS.md only)**
  Reasoning: the moderator confirmed that :129 already calls the table "the full method surface", so the closed set is already normative. A sentence saying "exactly these four" states the same fact a second time, and a second copy can drift. DevOps wants a diagnostic to cite a source. It can cite the table row as easily as a sentence.
  Concern: if A wins, a later amendment that edits the table but not the sentence, or the reverse, leaves the spec contradicting itself.

### Final Spec

```blink
trait StrOps {
    fn char_at(self, index: Int) -> Option[Char]       // None when out of bounds
    fn byte_len(self) -> Int                             // O(1)
    fn byte_at(self, index: Int) -> U8                   // panics when out of bounds
    fn byte_slice(self, start: Int, end: Int) -> Str     // [start, end) in bytes; clamps
    fn index_of(self, needle: Str) -> Option[Int]        // codepoint index
    fn byte_index_of(self, needle: Str, from: Int) -> Option[Int]  // byte offset
    fn substring(self, start: Int, end: Int) -> Str      // [start, end) in codepoints; clamps
    // ...
}

"abc".substring(0, 99)        // "abc"
"hello".substring(5, 2)       // "" (no swap)
"café".byte_slice(0, 4)       // panics: byte 4 is inside 'é'
"héllo".byte_index_of("l", 0) // Some(3)
```

- **Byte API.** `byte_slice(start, end)` and `byte_index_of(needle, from)` join `byte_len` and `byte_at`. The `byte_` methods are exactly these four, and the spec says so under the Str method table. `Str.slice` and `substr` are removed.
- **Point reads** never make up a value: `Option` when the return type can say absent, otherwise panic. `char_at`, `List.get` and `Bytes.get` give `None`; `byte_at` panics, with a message that names the method, the index and `byte_len`.
- **Range reads** (`substring`, `byte_slice`, `List.slice`, `Bytes.slice`) clamp: `start < 0` → 0, `end` past the length → the length, `start >= end` → empty, no swap, no count from the end.
- **`byte_slice`** panics when a bound, after clamping, falls inside a multi-byte codepoint. It does not snap to a boundary.
- **`byte_index_of`**: `from < 0` → 0, `from` past `byte_len` → `None`, `from` inside a codepoint panics, so `None` means only "not found". Every `Some(i)` is a valid `byte_slice` bound.
- **UTF-8.** Every safe way to make a `Str` gives valid UTF-8; `@ffi`/`@trusted` code carries the obligation for a `Str` it makes.
- **`len`** is marked O(n) in the method table.
- **No `Option`-returning range forms.**

Spec text: §3.2.1 *String Methods* (UTF-8 paragraph, `StrOps`, method table, *Unicode Semantics*, *Out-of-range indices*), §3.2.2 *Why `.get()` returns `Option[T]`* and the `List.slice` row, §3.2.3 the `Bytes.slice` row.

### Recorded in this decision, not in the spec

- **Migration order (Q7, 6-0).** Today `substring(start, n)` takes a byte start and a byte count. The spec makes it `substring(start, end)` in codepoints. Both take two `Int`s, so no checker can see a call that changes meaning. `substring` must never carry both meanings in one tree. Byte callers move to `byte_slice` (and `index_of` byte callers to `byte_index_of`) before `substring`, `len`, `char_at` and `index_of` change to codepoints. A codemod may rewrite `substr(a, n)` to `byte_slice(a, a + n)` only when `a` is a pure expression; other sites need a hand edit.
- **Nominal index types deferred, not rejected (Q0).** Distinct `ByteOffset` and `CharIndex` types would let the type checker catch a unit mix. They stay open for a later panel; the unit-mix lint ticket links here.
- **Adding a `from` form for `index_of`** needs its own vote. A codepoint `from` costs an O(n) walk, so the shapes of `index_of` and `byte_index_of` differ on purpose.

### Follow-ups

- Implementation project: runtime, `lib/std/traits.bl`, the three-step bootstrap migration, tests.
- Audit every path that makes a `Str` from `Bytes` or FFI for UTF-8 validation (Q6).
- Unit-mix lint: a codepoint value that flows into a `byte_` method or the reverse, direct flows only at first, covering the `from` argument (Q8).
