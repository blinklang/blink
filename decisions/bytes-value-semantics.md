[< All Decisions](../DECISIONS.md)

# Bytes Value Semantics — Design Rationale

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds.

The gap: the §3 `Bytes` table gave `set_*_le/be` a plain `self` receiver and called them "in-place". §3.6 *Shared cells* did not list `Bytes`, and it says only a shared cell can change through a second name. gen1 followed the in-place side:

```blink
fn poke(b: Bytes) {
    let _ = b.set_u16_le(0, 7)
}

fn main() ! IO {
    let a = Bytes.zeroed(4)
    let b = a
    let _ = b.set_u16_le(0, 9)
    io.println("{a.get(0).unwrap()}")   // printed 9; §3.6 says 0
    poke(a)
    io.println("{a.get(0).unwrap()}")   // printed 7; §3.6 says 9
}
```

`push` and `write_*_le/be` also compiled on an immutable `let` and their growth showed through a second name. The §3 table did not list `new`, `push`, `set` or `write_*`, and the E0814 list in §9.1.3.1 named five methods that do not ship. The TemplateValue Bytes ruling (Q2) relied on `Bytes` not being a shared cell.

Panelist text below is quoted verbatim, except that tracker IDs are left out and panelist headings are set in bold. Option labels used in the ballots: **V** = `Bytes` is a value; **S** = `Bytes` joins the shared-cell list; **F** = frozen `Bytes` plus a builder type. **P-split** = `with_ptr` read-only plus `with_mut_ptr`; **P-root** = one `with_ptr` that may write only on a mutable root; **P-unchanged** = `with_ptr` as it was. **K / C / G** = keep, cut, or derive the E0814 list from a *grows* mark in the table. **W / O / I** = warn-first 3-step migration, one-step migration, or rollout order on the implementation ticket. **N / R** = add or reject a non-normative cost sentence.

#### Phase A — Independent proposals

##### Systems

What the hardware sees today: a `Bytes` is a `blink_bytes*`, a pointer to a {len, cap, data} header. A bind copies the pointer, so every name points at the same header. That is why the MVCE prints 9 and then 7. Both proposals below make Bytes a value, as §3.6 already requires. I reject (b).

**Proposal S1 (preferred): Bytes is a frozen value, and a new BytesBuilder is the shared cell. This is the Str/StringBuilder split.**

```blink
fn header(len: Int) -> Bytes {
    let mut bb = BytesBuilder.zeroed(8)
    let _ = bb.set_u32_le(0, 0xCAFE)
    let _ = bb.set_u32_le(4, len)
    bb.to_bytes()
}

pub fn read_bytes(fd: Fd, max: Int) -> Result[Bytes, Errno] ! FFI {
    let mut buf = BytesBuilder.zeroed(max)
    let rc = buf.with_ptr(fn(p) -> I64 { c_read(fd.to_i32(), p, max.to_u64()) })
    // check rc ...
    Ok(buf.slice(0, rc.to_int()))   // one copy, same as today
}

fn main() ! IO {
    let a = header(3)
    let b = a                      // pointer copy, no data copy
    io.println("{a.get(0).unwrap()}")   // Bytes has no set_*, so it cannot alias-mutate
}
```

- **Bytes** keeps only reads: get, slice, concat, read_*, to_*, from_*, zeroed, and a read-only with_ptr. Nothing can write to it after it is built. Bind, pass and return stay one pointer copy, with no flag, no check and no copy-on-write branch. The compiler may share the storage forever, which is the same rule as the `@derive(Clone)` boxed-field ruling.
- **BytesBuilder** goes on the §3.6 list. It has `new`, `zeroed`, `with_capacity`, `push`, `set(i, byte)`, `set_*_le/be`, `write_*_le/be`, `with_ptr` (C may write), `slice`, `len` and `to_bytes` (one O(n) copy, like `StringBuilder.to_str`). Each mutator declares `mut self`, so `mut` marks every place where a change starts. This also closes the "push on an immutable `let`" hole the brief measured.
- E0814 (no growth inside with_ptr) applies to BytesBuilder only. A Bytes cannot grow, so the check has nothing to catch there.
- TemplateValue Q2 holds as written: a Bytes in a hole cannot change.

Tradeoffs: you pay for a copy only where you can see it (`to_bytes`, `slice`), and nothing is ever implicit. The cost is a second type and a migration. Uses of set_* and write_* are confined to tests (about 30 call sites) plus the libc wrappers. A code-writing tool learns one rule that Str already teaches: the frozen type is a value, and the builder is the cell.

Cross-language: this is Go `[]byte` + `bytes.Buffer`, Java `byte[]`-free `ByteString` + `ByteArrayOutputStream`, Rust `Bytes`/`BytesMut` (the tokio `bytes` crate does exactly this split for the same reason).

Spec changes:
- §3 Bytes table: remove set_* and state "Bytes is immutable". Add a BytesBuilder table that holds the set_*/write_*/push/set rows, each with `mut self`. Remove the "append-only constructors" prose about Bytes.
- §3.6: add `BytesBuilder` to the shared-cell list.
- §3 line 94: change `Bytes.new()` to `BytesBuilder.new()`.
- §9.1.3:
  - Bytes.with_ptr is a read-only pin: C must not write through `p`. Every call site lands in the `blink audit` with_ptr category for review.
  - BytesBuilder.with_ptr is the write pin.
  - E0814 applies to BytesBuilder receivers.
  - Update the libc wrapper example to match.

**Proposal S2 (fallback): Bytes has value semantics through copy-on-write, and set_* become `mut self`.**

```blink
let mut a = Bytes.zeroed(4)
let b = a                     // shares storage, sets the header's shared bit
let _ = a.set_u16_le(0, 9)    // bit set: copy 4 bytes, rebind a, then write
io.println("{b.get(0).unwrap()}")   // 0
```

What it compiles to: Boehm has no reference counts, so this cannot work like Swift's `isUniquelyReferenced`. It needs a sticky "shared" bit in the header:
- Each copy of a live Bytes (a bind or pass where the source is used again) emits one store to set the bit.
- Each `mut self` writer emits a load and a branch, then possibly an O(n) copy and a pointer store back into the root.
- Last-use liveness can skip the bit for the common pattern of building in a fresh local and returning it.
- `with_ptr` that may write must unshare first, so it needs `mut self` too, and the libc read wrappers change to `let mut buf`.

Tradeoffs:
- A write's cost depends on aliasing history that the reader cannot see. That is the Swift array performance cliff. A set_* in a hot loop on a Bytes that was passed in once copies the whole buffer, which kills predictability.
- More codegen work and more ways to miscompile, because the bit and the liveness analysis must be right at every copy site.
- The upside is no new type.

Spec changes:
- §3 table: set_* become `fn(mut self, Int, Int)`.
- §3.6: state that Bytes is a value whose storage the compiler may share until a write.
- §9.1.3: `with_ptr` takes `mut self` for writers.

**Against (b) (put Bytes on the shared-cell list):**
- It is cheapest to compile, but it fixes the spec by breaking what other rulings rely on.
- It reopens Template Q2.
- It makes every Bytes held as a struct field, Map value or template hole silently mutable through any other name.
- The growth APIs then move the data buffer under any other name that holds the same header. That is the exact hazard §9.1.3 invariant 1 exists to prevent, and only lexically inside with_ptr do we check it.

**My ranking:** S1, then S2. I oppose (b).

##### Web/Scripting

**My position:** Bytes should be a value. Python developers read the name `Bytes` as Python's `bytes`, which nobody can change. A change that shows through a second name breaks that, and they will not expect it. Blink already pairs an immutable `Str` with a mutable `StringBuilder`, so Bytes should act like `Str` too.

---

**Proposal W1 (preferred): Bytes is a value; writers take `mut self`; copy-on-write**

```blink
fn poke(mut b: Bytes) {
    let _ = b.set_u16_le(0, 7)      // changes poke's copy only
}

fn main() ! IO {
    let a = Bytes.zeroed(4)
    let mut b = a
    let _ = b.set_u16_le(0, 9)
    io.println("{a.get(0).unwrap()}")   // 0
    io.println("{b.get(0).unwrap()}")   // 9
    poke(a)
    io.println("{a.get(0).unwrap()}")   // 0

    let c = Bytes.zeroed(4)
    let _ = c.set_u16_le(0, 1)          // error[E0610]: `c` is not mut
}
```

FFI fill uses a writable pin:

```blink
fn read_bytes(fd: Fd, max: Int) -> Result[Bytes, Errno] {
    let mut buf = Bytes.zeroed(max)
    let rc = buf.with_ptr_mut(fn(p) -> I64 { c_read(fd.to_i32(), p, max.to_u64()) })
    ...
    Ok(buf.slice(0, got))
}
```

**Tradeoffs (DX):**
- It fits the user's mental model, and the rule needs no exception: "only the §3.6 list changes through a second name" stays true.
- The `mut` at the call site tells the reader that a write happens there. That follows the parameter-mutation ruling as it stands.
- TemplateValue Q2 stays closed, and the TemplateValue Bytes implementation can go ahead.
- Cost: codegen needs copy-on-write. Under a GC there is no refcount, so the obvious way is a sticky "shared" bit. A bind, pass or return of a Bytes that a later write could reach sets the bit. A write to a buffer that has the bit set copies it first. The usual cases (build a fresh buffer and fill it, or read only) never copy. The worst case is one extra copy after the buffer gets a second name. The sys seat should check how much this costs. I accept one copy in return for no aliasing bugs.
- It breaks some code. The two libc wrappers that read and recv into a buffer change `let buf` to `let mut buf` and call `with_ptr_mut`. The `set_*` callers are only tests. Nothing outside the tree uses it yet, so the change is cheap now and costly later.

**Cross-language:** Swift `Data` and `[UInt8]` work this way (a value with COW), and Swift developers do not ask about aliasing. Python `bytes` cannot change at all. Node's `Buffer.slice` shares memory while `Uint8Array.prototype.slice` copies. People hit that difference all the time on Stack Overflow, and Blink should not copy it.

**Spec text:**
- §3 Bytes table:
  - `set_*` become `fn(mut self, Int, Int) -> Result[(), Str]`, with the note "writes the receiver's own buffer; bounds vs `len`". Drop the words "in-place".
  - Add the methods the runtime already has: `new`, `push`, `write_*_le/be`. Each writer takes `mut self`.
  - Add `with_ptr_mut` as `fn[R](mut self, fn(Ptr[U8]) -> R ! _) -> R ! _`.
  - Add the sentence "Bytes is a value, like `Str`. A write through one name never shows through another (§3.6)."
- §9.1.3:
  - `with_ptr` gives a read-only pin. C must not write through it.
  - `with_ptr_mut` is the only way for C to write. It needs a mutable root, and it unshares the buffer before it pins it.
  - The pin invariants (memory does not move, the closure keeps the Bytes alive) and the E0814 no-grow check cover both forms.
- §3.6 does not change. §3b.5 does not change.
- Implementation note for codegen, not spec text: copy-on-write on a shared bit.

---

**Proposal W2 (fallback): Bytes joins the shared-cell list**

```blink
fn poke(mut b: Bytes) { let _ = b.set_u16_le(0, 7) }

fn main() ! IO {
    let a = Bytes.zeroed(4)
    let mut b = a
    let _ = b.set_u16_le(0, 9)
    io.println("{a.get(0).unwrap()}")   // 9, shared like List
}
```

**Tradeoffs:**
- It is the cheapest to build, because gen1 already behaves this way apart from the missing `mut self`. FFI fill needs no new method.
- It matches JS `Uint8Array`, Kotlin `ByteArray` and Python `bytearray`.
- But then `Bytes` and `Str` act in different ways, and the name promises the Python `bytes` model. I expect a steady stream of "why did my template or cached header change" questions.
- TemplateValue Q2 must reopen, and the Template doc would need a "clone before you store" warning.

**Spec text:**
- §3.6: add "`Bytes`" to the list.
- §3 table: writers take `mut self`.
- §3b.5: rewrite the Bytes sentence, and reopen Q2.

---

**In both proposals (not negotiable from my seat)**

- Every Bytes writer (`set_*`, `push`, `write_*`) declares `mut self`, and E0610 fires on an immutable root. The MVCE's `let b = a; b.push(5)` must not compile. Today gen1 lets any name grow any buffer, and that is the worst of both models.
- The §3 table must list every public method the runtime has: `new`, `push` and `write_*`. Today a user cannot find out from the spec how to build a Bytes value.

**Vote I will defend: W1.**

##### PLT

I'm the PLT seat, so I care about the typing rules. Here are my proposals.

**Main point, true whichever option wins:** `set_*` with plain `self` breaks the parameter-mutation ruling on its own. A method is mutating if and only if it declares `mut self`, and a mutating call needs a mutable root. `List` is a shared cell and `push` still needs `let mut`. So under (a) or (b), `set_*`, `push`, `write_*_le/be`, `clear`, `truncate` and `resize` all take `mut self`, and calling them on a plain `let` gives E0610. The real question is narrower: can a second name see the write?

---

**P1 (recommended): Bytes is a value. Writers take `mut self`. A new `with_mut_ptr` handles C writes.**

```blink
fn poke(mut b: Bytes) {
    let _ = b.set_u16_le(0, 7)       // changes only the callee's copy
}
fn main() ! IO {
    let mut a = Bytes.zeroed(4)
    let mut b = a
    let _ = b.set_u16_le(0, 9)
    io.println("{a.get(0).unwrap()}") // 0
    poke(a)
    io.println("{a.get(0).unwrap()}") // 0
}

fn read(fd: I32, n: Int) -> Result[Bytes, Str] ! IO {
    let mut buf = Bytes.zeroed(n)
    let got = buf.with_mut_ptr(fn(p) { c_read(fd, p, n) })
    if got < 0 { Err("read failed") } else { Ok(buf.slice(0, got)) }
}
```

Typing rules:
- `set_*`, `push`, `write_*`, `clear`, `truncate` and `resize` have type `fn(mut self, ...)`.
- `with_ptr(self, fn(Ptr[U8]) -> R ! _)` is a read pin. If C writes through that pointer, the program breaks §3.6, and `blink audit byte-pin` reports the call site.
- `with_mut_ptr(mut self, ...)` makes the storage unshared before the closure starts, then pins it. Memory still does not move during the closure, so the §9.1.3 invariants hold. E0814/E0815 apply to it too.

What codegen must do: the existing boxed-field ruling already lets the compiler share storage when no program can see the sharing. The proof is simple. Only a mutable root can start a write. So it is sound to share freely between immutable names and to unshare on the first write through a mutable root that may have an alias. Codegen can track this with a hidden uniqueness flag on each mutable root, or on each place path below it. Copying the value out clears the flag. A `mut self` writer copies the buffer if the flag is clear. A fresh `Bytes.zeroed` local that never escapes needs no copy at all. Boehm GC gives no refcount, so this flag stands in for Koka's Perceus reuse check.

Tradeoffs:
- No decided ruling changes. Template Q2 holds as written, and `clone()` on Bytes copies as users expect.
- Bytes stays a lawful `Eq` value, so it is safe as a key or hole.
- Cost: a loop that calls `set_*` through a root that was copied out pays one O(n) copy, then runs in place. This is the same as Swift's `Array`/`Data` copy-on-write, which works.
- Risk: the flag analysis is real codegen work. If it is wrong, we have an unsound program, so it needs a corpus of aliasing tests.

---

**P2 (fallback, if the codegen cost is too high): immutable Bytes plus a `ByteBuffer` shared cell, as with Str/StringBuilder.**

```blink
let mut bb = ByteBuffer.zeroed(8)
let _ = bb.set_u32_le(0, 42)
let frame: Bytes = bb.to_bytes()     // copies; frame never changes after this
```

`ByteBuffer` joins the §3.6 list. It owns `set_*`, `push`, `write_*` and `with_mut_ptr`. `Bytes` keeps only the read methods and `with_ptr`.

Tradeoffs: the type system does the work, so no runtime flags are needed, and Str/StringBuilder already set the precedent. But it reopens the Q-α-bytes-offset-API ruling (which put `set_*` on Bytes), it bends §3.2.2's "no MutX/X split", and it costs a copy at the boundary.

---

**Against (b), Bytes as a shared cell:**
- `clone()` on a shared cell does not copy (§3.6.1). So `b.clone()` would alias, which no user expects of a byte buffer.
- Every struct or template that holds Bytes could change at any depth, and Q2 must be reopened.
- Bytes is the I/O and crypto value type. If a key, digest or nonce can change after a check, that is a time-of-check/time-of-use hole that the type system could have closed.

Cross-language: Swift's `Data` is a COW value (P1). Rust has `Bytes`/`BytesMut` and Go has `string`/`[]byte`, both split by type (P2). Go's `[]byte` aliasing is the bug class that (b) would bring in.

---

**Spec changes for P1:**
- **§3 Bytes table:** writer signatures become `fn(mut self, ...)`, and the "in-place" wording becomes "in place on this value; no other name sees the write (§3.6)". Add rows for `push`, `write_*_le/be`, `new` and `with_mut_ptr`, which the runtime has but the table omits.
- **§3.6:** add one sentence: "Bytes is a value, not a shared cell. Its writers declare `mut self`."
- **§9.1.3:** the read wrapper example becomes `let mut buf` plus `with_mut_ptr`. State that `with_ptr` is a read pin, that C must not write through it, and that the audit reports it. List `with_mut_ptr` under E0814/E0815.
- **§3b.5:** no change.

##### DevOps

**Proposal D1: Bytes is a value; every mutator declares `mut self` (option a)**

`set_*`, `push`, `set` (index) and `write_*_le/be` become `mut self`, and the §3 table lists all of them. A call on an immutable root is the existing `E0610 MutationRequiresMut`, so we add no new error code. A bind, pass, return or `clone()` gives an independent value. The spec does not say how. Codegen picks copy-on-bind or copy-on-first-write, and it may share storage when no program can see the sharing, the same as the boxed-field ruling.

```blink
fn poke(mut b: Bytes) {
    let _ = b.set_u16_le(0, 7)       // changes poke's copy only
}
fn main() ! IO {
    let mut a = Bytes.zeroed(4)
    let mut b = a
    let _ = b.set_u16_le(0, 9)
    io.println("{a.get(0).unwrap()}") // 0
    poke(a)
    io.println("{a.get(0).unwrap()}") // 0
}
```

Without `mut`, the user sees this:

```
error[E0610]: MutationRequiresMut
  --> main.bl:3:13
   |
 2 |     let b = Bytes.zeroed(4)
   |         - help: make this binding mutable: `let mut b`
 3 |     let _ = b.set_u16_le(0, 9)
   |             ^^^^^^^^^^^^ `set_u16_le` declares `mut self`
```

Why I back it:
- The fix-it is mechanical. The LSP code action, the `mut` inlay hint and the unused-`mut` lint already exist for List and StringBuilder, and they cover Bytes for free. Option (b) produces no diagnostic at all. The MVCE compiles clean and prints 9, which is the worst error message there is: none.
- It keeps one rule. "Only §3.6 types change through a second name" is what hover docs, the TemplateValue Q2 ruling and every LLM-written program rely on. Adding Bytes to the list would make the list longer and every explanation of it longer too.
- Rust's `Vec<u8>` with `&mut`, Swift's `Data` (copy-on-write) and Go's arrays (not slices) all work like this. Go's `[]byte` aliasing is a well-known source of bugs. We should not copy it.

Cost: code that leans on aliasing breaks. Today that is only tests/test_bytes.bl and two compiler tests. A copy can cost speed on a large buffer, but codegen can avoid it when it proves the value has one owner.

**Proposal D2: split the FFI pin by direction**

`with_ptr` (plain `self`) pins the bytes read-only and gives `Ptr[U8]` for C `const` uses. A new `with_mut_ptr` (`mut self`) pins for C to write into. The read wrappers change from `let buf` to `let mut buf`:

```blink
pub fn read_bytes(fd: Fd, max: Int) -> Result[Bytes, Errno] ! IO {
    let mut buf = Bytes.zeroed(max)
    let rc = buf.with_mut_ptr(fn(p) -> I64 { c_read(fd.to_i32(), p, max.to_u64()) })
    ...
}
```

Why: today an immutable `let buf` changes under C. That is the same hole as the ticket, reached through FFI. The split gives `blink audit` a real direction. Its `byte-pin` category becomes `byte-pin-read` and `byte-pin-write`, which matches §9.1.3's own phrase, "pins the caller's Bytes read-only". E0814 and E0815 apply to both forms, and the no-move rule does not change. The pin covers the receiver's storage, so the closure writes into the value the `mut` root owns. Codegen must make that storage unique before it pins (copy if shared). Rust's `as_ptr` and `as_mut_ptr` make the same split.

Cost: one more method, and the curated wrappers need a one-line edit each. If the panel will not add a method, the fallback is that `with_ptr` itself becomes `mut self`. That is sound, but the read-only pin on a write wrapper's argument then needs a `let mut` for no reason, and the audit loses the direction.

**Proposal D3: name the growth methods in the spec**

The §3 Bytes table must list `new`, `push`, `set`, `write_*_le/be` (all `mut self` except `new`) and `extend`, `append`, `clear`, `truncate` and `resize` if they ship. Whatever E0814 names must be in the table. Today the LSP autocompletes methods that the spec does not define, so hover has no source of truth.

**Spec text changes**

- §3 Bytes table: change the receiver of `set_*` to `mut self`, add rows for the growth methods, and replace "in-place" with "writes at offset in this value; a bind or pass copies (§3.6)".
- §3 line 389: add "`set_*`, `push`, `set` and `write_*` on Bytes" to the list of mutating methods.
- §3.6: add one sentence: "Bytes is a value, not a shared cell."
- §9.1.3: add `with_mut_ptr` with the signature `fn[R](mut self, fn(Ptr[U8]) -> R ! _) -> R ! _`, change the read-wrapper example to `let mut buf` with `with_mut_ptr`, and say `with_ptr` is read-only (C must not write through `p`). Split the audit category in two.
- §3b.5 and Q2 stand unchanged, so we do not need to reopen them.

##### AI/ML

**Proposal 1 (recommended): Bytes joins the §3.6 shared-cell list, and every mutator declares `mut self`**

```blink
fn poke(mut b: Bytes) {
    b.set_u16_le(0, 7)?             // OK: root `b` is mut
}

fn peek(b: Bytes) -> Int {
    b.set_u16_le(0, 1)?             // error[E0610]: `b` is not mut
    b.read_u16_le(0).unwrap()
}

fn main() ! IO {
    let mut a = Bytes.zeroed(4)
    let b = a                       // b shares a's buffer, same as a List
    a.set_u16_le(0, 9)?
    io.println("{b.get(0).unwrap()}")   // 9
    poke(a)
    io.println("{a.get(0).unwrap()}")   // 7
}
```

The gen1 output stays as it is. What changes is the `mut` rule: a mutating call on Bytes now needs a mutable root, as it already does for List.

Tradeoffs for code generation and learning:

- **One rule, not two.** A model already learns "List/Map/Set/StringBuilder are shared, and a mutation needs a `mut` root." Bytes is the buffer type, so a model expects it to behave like List. Option (a) would add a second mutation model for a single type. That is a new decision point, and models get it wrong because they do not see it often.
- **Training priors agree.** Go `[]byte`, JS `Uint8Array`, Python `bytearray`, Java `ByteBuffer` and C# `byte[]` all share a buffer through a second name. Only Swift `Data` (copy-on-write) and Rust `Vec<u8>` (move) do not. A model writing Blink will assume sharing, so (b) matches what it writes without help.
- **No hidden O(n) copies.** The runtime uses Boehm GC and has no refcount, so (a) needs copy-on-bind, or a uniqueness bit plus copy-on-write. Both cost something that neither a model nor a human can see in the source. Bytes carries I/O and crypto payloads, so the cost is large and hard to find.
- **`with_ptr` stays sound.** The memory does not move, and nothing copies under the pin. Under (a) with copy-on-write, `with_ptr` would have to force a copy first, or C would write into a buffer that two names share.
- **Token cost:** `mut` on the buffer binding (plus a `mut` parameter where a function mutates its argument). That is small, and it marks where a mutation starts, which helps a model read the code.

Exact spec changes:

1. **§3.6 Shared cells:** add the item "`Bytes`" after "`List`, `Map` and `Set`".
2. **§3 Bytes table:** change the `set_*` signatures to `fn(mut self, Int, Int) -> Result[(), Str]`. Add the rows the brief found missing: `new` (`fn() -> Bytes`), `push` (`fn(mut self, U8)`), `set` (`fn(mut self, Int, U8)`) and `write_*_le/be` (`fn(mut self, Int)`). Also list `extend`, `append`, `clear`, `truncate` and `resize` as `mut self` if they ship, because E0814 already names them. Replace "in-place" with: "Writes into the shared buffer (§3.6). The receiver root must be mut."
3. **§3 line 410 example:** add one sentence saying Bytes follows the same `MutAliasOfImmutable` warning as List.
4. **§3b.5 (reopen Template Q2):** replace the sentence with: "A `Bytes` hole holds a copy made when the template is built. A later write through another name does not change the template." A model expects interpolation to capture the value at the time of the call, as an f-string does, and the copy is one per Bytes hole. I would rather reopen Q2 than keep a rule whose premise is false.
5. **§9.1.3:** no change to the invariants. The curated read wrappers can keep `let buf = Bytes.zeroed(n)`, because C writes outside Blink's `mut` tracking and the `byte-pin` audit category covers it. See sub-question 1b.

Migration uses the 3-step process: the compiler first warns on a non-mut root, then src/lib/tests change to `let mut`, then the warning becomes E0610.

**Proposal 1b (sub-question): split the pin into `with_ptr` (read-only, `self`) and `with_mut_ptr` (`mut self`)**

```blink
let mut buf = Bytes.zeroed(n)
let got = buf.with_mut_ptr(fn(p) { c_read(fd, p, n) })
```

- **For:** every mutation has a visible `mut` root, so the rule has no FFI exception. The prose already says a write wrapper "pins the caller's Bytes read-only", so the type would then say so too.
- **Against:** a second pin verb adds a decision point. It only touches the curated `std.libc` wrappers, not user code.

I lean yes, but weakly. If the panel wants fewer verbs, I can accept Proposal 1 alone.

**Proposal 2 (rejected, listed for contrast): value semantics, as in option (a)**

Bytes would act like Str or Swift `Data`, with `set_*` declaring `mut self` on a `let mut` root and copy-on-bind or copy-on-write in codegen. The Template Q2 text would stay true.

I reject it for four reasons:

- It sets Bytes apart from List, so a model has two mutation models to learn.
- Under Boehm GC there is no cheap way to know a buffer is unique, so the copies are hidden and O(n).
- `with_ptr` would have to force a copy before each pin.
- Every model trained on Go, JS or Python mispredicts aliasing in this design.

If the panel wants an immutable byte type, the Str/StringBuilder split is the precedent: immutable `Bytes` plus a shared-cell `BytesBuilder`. That adds a type and splits the I/O API, so its cost is higher than Proposal 1's.

**My vote**

Proposal 1, plus 1b if others support it, and reopen Template Q2 with the copy-at-build rule.

##### Minimalism

**Proposal M1 (my pick): Bytes is a value. Mutators take `mut self`. Option (b) is rejected.**

```blink
fn poke(b: Bytes) {
    b.set_u16_le(0, 7)?          // error[E0610]: `b` is not mut
}
fn poke_mut(mut b: Bytes) {
    let _ = b.set_u16_le(0, 7)   // OK; changes poke_mut's copy only
}
fn main() ! IO {
    let a = Bytes.zeroed(4)
    let mut b = a                // no MutAliasOfImmutable warning: a copy, not an alias
    let _ = b.set_u16_le(0, 9)
    io.println("{a.get(0).unwrap()}")   // 0
    io.println("{b.get(0).unwrap()}")   // 9
    poke_mut(b)
    io.println("{b.get(0).unwrap()}")   // 9
    let mut out = Bytes.new()
    out.push(1)                  // `mut` root needed, same as List
}
```

Why this adds the least:
- **It adds no new rule.** §3.6 already says that any type not on the list cannot change through a second name. Bytes is not on the list. The spec is right and gen1 is wrong. Fixing the code costs no spec concept. Option (b) grows a list that §3.6 calls "the only one".
- **Both options need `mut self` anyway.** The parameter-mutation ruling says a method mutates only if it declares `mut self`. So set_*, push and write_* must take `mut self` under (a) or (b). The only open question is aliasing, and §3.6 already answers it.
- **Q2 stays closed.** The TemplateValue ruling and §3b.5 stay as voted. Under (b), Template holes could change after capture. That is a security-flavoured leak in a contracts feature.
- **Bytes holds keys, hashes and wire frames.** Aliasing those lets a callee corrupt its caller's buffer, which Str users never see. Value semantics makes Bytes behave like Str, its text twin.
- **No BytesBuilder.** Str needs StringBuilder because Str has no mutators. Bytes with `mut self` mutators and binding-level `mut` already covers building. A second type would double the API, the split §3.2.2 rejects for List.

How it gets built stays out of the spec. The `@derive(Clone)` boxed-field ruling already says the compiler may share storage when no program can observe it. That one rule covers copy-on-bind, copy-on-write, and skipping copies through escape analysis. The cost is a copy when a buffer reaches a mutable root, and only when the compiler cannot prove the old name is dead.

**with_ptr interaction.** The memory-does-not-move invariant still holds, because a copy happens at the bind and never inside the closure. One new constraint: C may write through the pointer only if the receiver's root is mutable. At that point the compiler must give the receiver storage that no other name shares. The curated wrappers change from `let buf = Bytes.zeroed(n)` to `let mut buf = ...`, which is three lines in lib/std/libc.bl. Read-only pins (write_bytes, send_bytes) need no copy. `with_ptr` keeps plain `self`, so we add no `with_ptr_mut`. The `@trusted` audit already takes responsibility for what C does.

Cross-language: Swift `Data` and `Array` are values with copy-on-write and `mutating` methods. That is this design, and it works well. Go slices alias, and "append changed my caller's slice" is a well-known Go bug. Rust `Vec<u8>` cannot alias a write without `&mut`.

Spec text changes:
- **§3 Bytes table:** set_* signatures become `fn(mut self, Int, Int) -> Result[(), Str]`. Change the note "in-place, bounds vs len" to "at offset; Err if off + width > len; never grows". Add the missing rows, all `mut self`: `new`, `push`, `set`, `write_*_le/be`. Add one sentence after the table: "Bytes is a value, not a shared cell (§3.6). A mutating method needs a mutable root (§3.2.2), and the change shows only through that root."
- **§3.6:** the list does not change. Add an example after "A value of any other type…": "for example, after `let mut b = a` and `b.push(1)`, `a` is unchanged when `a` is a Bytes."
- **§3.6.1 Clone:** Bytes `clone()` equals a copy on bind, so it is an independent buffer.
- **§9.1.3:** "C code may write through the pointer only when the receiver's root is a `let mut` binding or a `mut` parameter. The compiler then gives the receiver storage that no other name shares. With any other receiver, the pin is read-only." Update the wrapper example to `let mut buf`.
- **§3b.5:** no change.

**Proposal M2 (fallback, not preferred): make Bytes immutable, like Str.** set_* would return a new Bytes (`-> Result[Bytes, Str]`), and growth would move to a builder. This removes all mutation surface, but it costs O(n) per set_*, breaks the with_ptr fill pattern that C needs, and adds a BytesBuilder type. It also reverses the 6-0 offset-API vote. I list it only to show that removing surface is the more expensive path here. I vote no on it.

**Vote intent:** yes on (a) as M1, no on (b). (b) adds a list entry and reopens a 6-0 ruling to legalize a codegen bug.

#### Phase B — Debate (round 1, all six STABLE)

After round 1, every seat moved to V on Q1, all agreed on `mut self` writers (Q2) and a complete table (Q3a), and Min conceded P-root and AI/ML dropped P-unchanged (Q4). Splits remained on the E0814 list, the migration and the cost sentence.

##### Systems

**Q1: I concede F and now hold V.**

PLT and Min are right that F has costs I did not count. It reopens the 6-0 offset-API ruling, which put `set_*` on Bytes. It also brings back the X/MutX split that §3.2.2 rejects for List. My case for F was cost predictability, not semantics. V can give that predictability if codegen keeps three cost promises:

1. A bind, pass, return or store into a field, List or template hole never copies the bytes. It is one pointer copy plus, at most, one store to a "shared" bit in the header.
2. Only a `mut self` writer or `with_mut_ptr` can copy, and it copies only when the buffer may have a second live name. After that copy, writes run in place until the next copy-out.
3. A buffer that never had a second name never copies. This is the common "zeroed, fill, return" path. Codegen uses last-use liveness so a move does not set the bit.

This is Swift `Data` without refcounts. PLT's flag on each mutable root and the sticky bit in my S2 are two ways to build it. Codegen may pick either. Per the "no impl details in spec" rule, the three promises go in the decision record and the codegen chore, not in sections/. The spec says only "Bytes is a value, not a shared cell".

To AI/ML on S: the Go `[]byte` prior is real. But (b) leaves `clone()` aliasing (§3.6.1), reopens Q2, and lets a callee grow a buffer under its caller's name. That last one is the move hazard behind §9.1.3 invariant 1. An extra `mut` is a cheaper price for a model than any of those. AI/ML's own objection to V, "hidden O(n) copies", is bounded by promise 2: at most one copy per alias event, never one per write.

**Q2: hold.** Every writer declares `mut self`, and E0610 fires on an immutable root. All six seats agree.

**Q3: hold, with one refinement.** The table lists every method the runtime ships (`new`, `push`, `set`, `write_*_le/be`, `set_*`, `with_mut_ptr`). The E0814 list names only methods that exist. Today it cites `append`, `extend`, `clear`, `truncate` and `resize`, which have no rows. Either they get rows or E0814 keeps them under "any future method tagged `@bytes_grows`". The spec must not name methods that do not exist.

**Q4: I hold P-split (`with_ptr` for read, `with_mut_ptr` for write) and oppose P-root.**

- Codegen must know at the call whether to unshare. With P-split the method name tells it: `with_ptr` never copies, and `with_mut_ptr` unshares once, then pins.
- Under P-root, the binding's mutability decides. A `mut` parameter passed to `write_bytes` for some other reason would trigger a needless O(n) unshare before a read-only `write(2)`. That is a hidden copy on the I/O hot path, which is exactly what I object to.
- The split also gives `blink audit` a direction (DevOps's `byte-pin-read`/`byte-pin-write`).
- On the name, I take `with_mut_ptr`. It matches Rust's `as_mut_ptr`, and three seats already use it.
- E0814 and E0815 apply to both pins.

**Q5: hold the AI/ML 3-step.**

1. Add `mut self` on the writers as a warning, and add `with_mut_ptr`. Run regen.
2. Migrate lib/std/libc.bl (`let mut buf` + `with_mut_ptr`), tests/test_bytes.bl and the two compiler tests. Run regen.
3. Make the warning E0610 and turn on value codegen. Run regen.

The codegen change in step 3 needs an aliasing corpus before it lands: bind, pass, return, struct field, List element, template hole, closure capture, and a pin after an alias. A wrong bit means silent aliasing, the same bug as this ticket.

Held: Q1 V, Q2 mut self, Q3 full table + honest E0814 list, Q4 P-split (`with_mut_ptr`), Q5 3-step.

STABLE — ready to vote

##### Web/Scripting

**Q1: I hold Option V.**

- **Concede to DevOps, Min and PLT:** keep the mechanism out of the spec. I drop "copy-on-write" from my heading. The spec says "Bytes is a value". The boxed-field ruling already lets codegen share storage that no program can see.
- **Rebut AI/ML on training priors.** The list leaves out the biggest prior of all. Python `bytes` cannot change, and the name `Bytes` copies that type, not `bytearray`. Most of the Go, JS and Java types on the list have a different name (`[]byte`, `Uint8Array`, `ByteBuffer`). A JS dev also does not expect `Uint8Array.slice` to copy while `Buffer.slice` shares, which proves my point: aliasing a buffer is a known trap, not a comfort. AI/ML's own fix for Templates ("a hole holds a copy made at build time") adds a special copy rule for one feature. That is the second mutation model AI/ML says it wants to avoid.
- **Rebut Sys S1 / PLT P2 (two types).** Python has `bytes` plus `bytearray`, and "which one do I use, and why can't I change this one?" is a stock Stack Overflow question. Under S1, a user who calls `read()` and wants to patch a header must learn a second type, a `to_bytes()` copy, and which side each method sits on. Under V they write `let mut` and get on with it. That is the 90% case. Str needs StringBuilder because building text by appending is the common path. For bytes, the common path is "fill a fixed buffer, then read it", and one type covers that.
- **Concede to Sys:** under V, a write's cost depends on whether the value got a second name earlier, and you cannot see that in the code. That is real, but it costs at most one copy, then the writes run in place. Swift users live with this. A silent wrong answer (S) is worse than a slow first write (V).

**Q2: `mut self` on every writer, and E0610 on an immutable root.** No change; all six of us agree.

**Q3: the table lists every method the runtime ships and every method E0814 names.** No change.

**Q4: I hold P-split.**

- **Name: I concede `with_mut_ptr`.** Three seats chose it, and it matches Rust's `as_mut_ptr`. With the name chosen, nobody has to look it up.
- **Rebut Min's P-root.** With P-root, the same call `buf.with_ptr(...)` means "C may write" or "C must not write", and only the binding three lines up tells you which. A reader, a reviewer and the audit tool all have to trace the root to know whether C writes. Two verbs put the direction at the call site. That also gives DevOps the `byte-pin-read` / `byte-pin-write` audit split for free. One extra method name costs less than a rule that hides in the binding.
- **Rebut AI/ML's P-unchanged.** If an immutable `let buf` can change under C, the hole the ticket reports is still open, only now it comes through FFI. AI/ML already leans toward 1b, so I count that as support for P-split.

**Q5: I accept AI/ML's 3-step path** (warn, migrate the tree, then error). The bootstrap protocol requires it in any case, because src and lib/std hold the code that changes. I add one point. The aliasing fix in codegen (V) can land in the same release as step 1, because only tests/test_bytes.bl and two compiler tests depend on the aliasing.

**Positions:** Q1 V, Q2 `mut self` + E0610, Q3 full table, Q4 P-split with the name `with_mut_ptr`, Q5 3-step.

STABLE — ready to vote

##### PLT

**Q1: I hold V.**

- **To AI/ML (S):** No one has answered the `clone()` point. §3.6.1 says a clone of a shared cell refers to the same cell, so under S `b.clone()` aliases. Your own §3b.5 fix ("a Bytes hole holds a copy made when the template is built") brings back value semantics at one site. That shows S leaks: every place that needs a stable Bytes (holes, keys, digests, struct fields) must copy by hand. Your `with_ptr` claim also fails. Under V the copy happens before the pin, never inside it, so invariant 1 holds.
- **To Sys (F):** Your predictability point is fair. But the cost is bounded. A root pays at most one O(n) copy each time it gains a second name, and then it writes in place. F reverses a 6-0 ruling (`set_*` on Bytes) and the §3.2.2 "no MutX/X split" ruling to remove one branch per write. I keep F only as a fallback.
- **Refinement:** the spec stays silent on the mechanism. One non-normative sentence answers Sys without fixing a technique: "A write through a mutable root copies the buffer at most once after that root's value gains another name."

**Q2: all writers take `mut self`, and E0610 fires on an immutable root.** Everyone agrees. This holds under every option.

**Q3: the table is complete.** I agree, with two additions:
1. Add a row for the write pin.
2. E0814 must name only methods that exist. Today it lists `extend`, `append`, `clear`, `truncate` and `resize`, which the table lacks. Either ship them or define E0814 as "a call to a Bytes method the table marks *grows*". I prefer the marker, so the two lists cannot drift apart.

**Q4: I hold P-split (`with_ptr` reads, `with_mut_ptr` writes).**

- **Against P-root (Min):** "a method is mutating iff it declares `mut self`" is a decided rule. P-root makes `with_ptr` mutating or not depending on the caller's root. The method's type no longer says what it does, so the rule stops composing. Example: a generic helper `fn f(b: Bytes) { b.with_ptr(...) }` cannot tell which kind of pin it holds. P-root also forces an unshare copy on every read pin of a `mut` root, because the compiler cannot know C only reads.
- **Against P-unchanged (AI/ML):** C changes a value behind an immutable `let`. That breaks §3.6 under V and breaks the iff rule under S.
- **Name:** `with_mut_ptr`. The `mut` prefix matches `mut self` and Rust's `as_mut_ptr`. I am not attached to the name.
- **Note:** under V, E0815 matters for soundness only on the write pin. A callee that got a copy of a pinned buffer would see C's writes. On the read pin it is just caution. Keep both as they are; YAGNI.

**Q5: migration.** The 3-step plan (warn → migrate → E0610) is a bootstrap procedure, not spec text, so I accept it as the implementation plan. One ordering rule matters: the codegen unshare must land with or before E0610. Otherwise we ship a window where `let mut b = a` still aliases. The tests in tests/test_bytes.bl that assert aliasing must flip in that same step.

STABLE — ready to vote

##### DevOps

**Q1: aliasing model. I hold **V**.**

**To AI/ML (S):** "Models expect sharing" cuts both ways. Under S, the MVCE compiles clean and prints 9. Nothing in the tooling can flag it. No lint can tell an intended alias from a bug, because both are legal. Under V, the wrong guess, "I changed `b`, so `a` changed", fails in a test, and the `mut` it needs is a fix-it the LSP already offers for List. S also reopens a 6-0 ruling (Q2) and makes `clone()` on Bytes alias. No user expects that, and hover would have to warn about it on every Bytes `clone()`.

**To Sys (F):** I accept that cost predictability is the best case for F. But F has the worse diagnostic surface. A user who writes `Bytes.zeroed(8).set_u32_le(...)`, which is the shape the 6-0 offset-API vote shipped, gets "no method `set_u32_le` on `Bytes`". We would need a custom "did you mean BytesBuilder?" note on every writer name, and autocomplete splits across two types for one job. F also reopens Q-α-bytes-offset-API and bends §3.2.2's no-MutX/X rule. Str needs StringBuilder because Str has no mutators. Bytes can have them.

**On the COW cost cliff (Sys S2):** tooling, not spec text, answers this. I propose that codegen record each unshare copy it emits in a hot path. Then a later `blink build --explain-copies` (or a perf lint) can point at the bind that caused the copy. Swift never shipped that, and it is why its cliff hurts. The spec stays mechanism-free, as Min and PLT also want.

**Q2: receivers. **`mut self` on every writer; E0610 on an immutable root.****
This is unanimous. One addition: the E0610 fix-it for Bytes must name the root binding (`let b` → `let mut b`), the same as List does today. There is no new code.

**Q3: table completeness. **Full table.****
Every method the runtime ships and every method E0814 names gets a row. If a method has no row, it is not public, and the LSP must not offer it.

**Q4: the pin. I hold **P-split**, named `with_mut_ptr` (Rust `as_mut_ptr` precedent; three seats already chose that spelling).**

**To Min (P-root):** P-root makes the same call mean different things depending on how the root was bound. Hover on `with_ptr` cannot say "C may write here", and `blink audit` cannot sort pins by direction without redoing the root analysis. It also costs speed. `write_bytes(mut data)` on a `let mut` buffer that has an alias would unshare (copy) for a pin that only reads. With P-split, the direction is in the signature, the audit splits into `byte-pin-read` and `byte-pin-write` for free, and a read pin never copies. That is one verb more. P-root is cheaper only on paper.

**To AI/ML (P-unchanged):** an immutable `let buf` that C fills is the ticket's bug moved behind FFI. The audit records it but does not close it.

**Q5: migration. **No user-facing warning stage.****
Only tests and lib/std use these methods, and Blink has no external users who depend on Bytes aliasing. Fixing a spec gap needs no deprecation window. The work follows the normal bootstrap order:
1. Add `with_mut_ptr` and the full table.
2. Move the libc wrappers and tests to `let mut` + `with_mut_ptr`.
3. Enforce E0610 on Bytes writers and switch codegen to value semantics.

That ordering belongs on the implementation ticket. It is not spec text.

STABLE — ready to vote

##### AI/ML

**Q1: aliasing model. I now hold Option V and drop Option S.**

I concede. Three points from the others changed my view:

- **PLT on `clone()`.** Under S, `b.clone()` on a shared cell does not copy (§3.6.1). No model and no human expects `clone()` on a byte buffer to alias. That is a trap the spec text would teach on purpose.
- **Web on the name.** I said the training priors favour sharing. That was only half true. The type name `Bytes` matches Python `bytes`, which is immutable, and `Str` is Blink's value twin. A model reads `Bytes` as "like Str", not "like bytearray". The prior I cited belongs to `[]byte` and `Uint8Array`, which have other names.
- **Min on rule count.** The spec as written already gives the answer: "a value of any other type cannot change through a second name." A model that learns §3.6 from the spec alone predicts value behaviour for Bytes today. Under V, the spec stays right and only gen1 changes. Under S, the list grows and Q2 reopens. V adds fewer facts for a model to learn.

My cost point (Boehm GC, no refcount, so copies are hidden) still holds, but it is a codegen cost, not a learnability cost. Min and DevOps keep the mechanism out of spec text, and I agree. Sys S2's warning about write cost depending on aliasing history is real. Codegen should handle it with liveness, not the spec.

**Against Option F:** it adds a decision point at every buffer ("Bytes or BytesBuilder?"), plus a `to_bytes()` copy and a second method table. It also reopens the 6-0 offset-API ruling. It is a clean design, but it costs more tokens and more choices than V. I vote no.

**Q2: receivers. All mutators declare `mut self`, and a call on an immutable root is E0610. Agreed by all.**

**Q3: table completeness. Every method the runtime ships and every method E0814 names goes in the §3 table. Agreed by all.**

**Q4: the C write pin. I now hold P-split with the name `with_mut_ptr`. I drop P-unchanged.**

Under V, P-unchanged is unsound: C writing through a `let buf` pin can change storage that another name shares. So it must go.

**Against P-root (Min):** one method whose meaning depends on how a binding three lines up was declared is a hidden decision point. A model that writes `let buf` plus `with_ptr` gets no error, and C then writes into shared storage. P-split puts the direction in the method name and the `mut self` receiver, so the type checker catches the mistake (E0610). It also gives the audit a direction (`byte-pin-read` / `byte-pin-write`, from DevOps).

**On the name:** use `with_mut_ptr`, not `with_ptr_mut`. It matches Rust's `as_mut_ptr`, which models know well, and three of the four panelists who want a split already use it.

**Q5: migration. I keep the 3-step process, adjusted for V.**

1. Add `mut self` to the writers as a warning, add `with_mut_ptr`, and add the codegen that unshares on a write. Then run `task regen`.
2. Migrate src, lib and tests to `let mut` and `with_mut_ptr`. Tests that assert aliasing (tests/test_bytes.bl) change their expected output in this step. Then run `task regen`.
3. Make the warning E0610, and make C writes through `with_ptr` an audit error. Then run `task regen`.

Template ticket unblocks after step 1, because Q2 stands.

STABLE — ready to vote

##### Minimalism

**Q1: I hold V.**
- *To Sys (S1, option F):* S1 adds a type, reverses the 6-0 offset-API ruling, and brings in the MutX/X split that §3.2.2 rejects. That is three costs to avoid one copy that the reader cannot see. The "perf cliff" is one O(n) copy per value after it gets a second name. It is not a copy per write. The common patterns (fill a fresh local, read-only use) never copy. If S2's numbers later show real harm, we can add F then, but we cannot take it back once it ships.
- *To AI/ML (option S):* the priors argument cuts the other way. The name `Bytes` comes from Python, where `bytes` is immutable, and Str, its Blink twin, is a value. S also does not remove the hidden copy. It moves it into §3b.5 as a Template-only copy rule, which is a special case that Q2 voted 6-0 to avoid. And `clone()` on a shared cell aliases (§3.6.1), so under S `b.clone()` would not copy a byte buffer. No user expects that. "One rule" is V: only the list aliases.
- *To Web and Sys S2:* the spec text must not name the shared bit or copy-on-write. The boxed-field ruling already permits any mechanism that no program can observe. Put the mechanism in a codegen chore.

**Q2: I hold "every writer takes `mut self`".** Under V, add one line: `let mut b = a` gives no `MutAliasOfImmutable` warning for Bytes, because it is a copy.

**Q3: list every shipped method, and only those.** I agree with adding `new`, `push`, `set` and `write_*_le/be` to the table. I object to adding `extend`, `append`, `clear`, `truncate` and `resize` "if they ship". None of them exists in lib/std/bytes.bl, and YAGNI says the table should not list them. The E0814 list in §9.1.3.1 names them today, so I propose cutting that list to the shipped growers (`push`, `write_*`) plus the existing `@bytes_grows` rule. Also drop `concat` from the E0814 list: it takes `self` and returns a new value, so it cannot move the receiver's memory.

**Q4: I concede to P-split, named `with_mut_ptr`.** My P-root gave one call two meanings that depend on the binding, which is a hidden rule. One extra verb costs less than that rule, and it makes "every write has a `mut` root" true with no FFI exception. DevOps's fallback (`with_ptr` takes `mut self`) is worse, because write wrappers would need a `mut` copy just to read. Of the two names I choose `with_mut_ptr`, as three seats do, and it matches Rust's `as_mut_ptr`. I reject P-unchanged, because an immutable `let buf` that C changes is this ticket's hole again, reached through FFI.

**Q5: migration.** Nothing outside this tree uses `set_*`, and Blink is pre-1.0. A warn-first phase adds a diagnostic that docs and tools must carry, and nobody gains from it. Make the change in one step: E0610 at once, with the tests and libc wrappers updated in the same change. Apply the bootstrap protocol (CLAUDE.md) only where src itself calls a changed method, which today is no call site in src outside the tests. I do not support AI/ML's 3-step warning path.

STABLE — ready to vote

#### Phase C — Final vote

- **Q1: aliasing model** — V, 6-0
- **Q2: writer receivers** — Y, 6-0
- **Q3a: method table** — Y, 6-0
- **Q3b: E0814 growth list** — G, 6-0
- **Q4: how C writes into a Bytes** — P-split, 6-0
- **Q5: migration** — I 4, W 1 (web), O 1 (min); went to Phase D
- **Q6: cost sentence in the spec** — R, 5-1 (web dissent: N)

##### Systems

**Q1: V**
Reasoning: Bytes as a value keeps §3.6 true, keeps Template Q2 closed and keeps `clone()` honest. Under V, a bind stays one pointer copy, and a writer copies only after the buffer gains a second name, so the cost is bounded and local. F gave the same safety with no hidden branch, but it reopens a 6-0 ruling and splits the type, and V's cost is small enough to accept.
Concern: an unsharing step that codegen gets wrong (a missed bit on a field, List or capture store) brings back silent aliasing, the exact bug in this ticket. So value codegen must not land without an aliasing corpus.

**Q2: Y**
Reasoning: The parameter-mutation ruling already requires `mut self` on any mutating method. The `mut` root is also the one signal codegen needs to know where a copy may happen. Without it, any name could grow a buffer that another name holds.
Concern: none from my seat beyond migration churn in tests.

**Q3a: Y**
Reasoning: The spec is the contract that codegen and the runtime ABI build against. A method that ships without a row has no defined receiver, cost or bounds behaviour. A row with no method is a promise the runtime breaks.
Concern: the table can drift again unless a check ties the table rows to the stdlib surface.

**Q3b: G**
Reasoning: Use one source of truth. The table marks a method *grows*, and E0814 means "a grows method on the pinned receiver". Then the pin's no-move rule follows the methods that can actually realloc, and nobody keeps two lists in sync by hand. `concat` returns a new value and never moves the receiver's storage, so it falls out by itself.
Concern: a `grows` mark left off a new method is a use-after-move under a live C pointer. So the mark should be required on any method that can realloc, not optional.

**Q4: P-split**
Reasoning: The method name tells codegen at the call site whether to unshare: `with_ptr` never copies, and `with_mut_ptr` unshares once, then pins. P-root ties the copy to how the binding was declared, so a read-only `write(2)` on a `mut` parameter would pay a needless O(n) copy on the I/O hot path. P-unchanged lets C write into a buffer that two names share, which breaks V.
Concern: C that writes through a `with_ptr` pointer is undefined behaviour that the compiler cannot catch. The `byte-pin-read` audit category must make those sites easy to find.

**Q5: I**
Reasoning: The order of steps follows the repo's self-hosting protocol, which already forces the 3-step for breaking changes. It is not a language rule a Blink user sees. Put the steps, and the rule that value codegen with its aliasing corpus lands with or before E0610, on the implementation ticket.
Concern: if the ticket drops the order, E0610 could land before value codegen and leave a gap where `mut` is required but aliasing still shows.

**Q6: R**
Reasoning: Copy timing is lowering detail, and sections/ holds language rules, not cost models. The three cost promises (no copy on bind, at most one copy after a second name appears, no copy for a buffer that never had one) belong in the decision record and the codegen chore. There they bind the implementation without freezing a mechanism into the spec.
Concern: users who look only at the spec may assume a copy happens on every bind and avoid passing Bytes, so the decision record must be linked from the §3 Bytes text.

##### Web/Scripting

**Q1 — Vote: V**
Reasoning: The name `Bytes` copies Python's `bytes`, so users expect a value that no second name can change, the same as `Str`. V keeps §3.6 as it is, so the one rule users learn ("only the listed types change through a second name") stays true. F makes every user choose between two byte types for the common case of filling a buffer and reading it, and that choice is a stock Stack Overflow question in Python.
Concern: If codegen copies on every bind, not on the first write, I/O-heavy code gets slow and users blame the language.

**Q2 — Vote: Y**
Reasoning: A user already writes `let mut` before `xs.push(...)` on a List, so Bytes should ask for the same thing. E0610 already has a fix-it that adds `mut`, so the error tells the user how to fix the code.
Concern: Code that calls `set_*` with `let _ =` on a plain `let` breaks, and the error must point at the binding, not only at the call.

**Q3a — Vote: Y**
Reasoning: Today a user cannot learn from the spec how to build a Bytes value, because `new` and `push` are missing from the table. Hover docs and autocomplete need one source of truth.
Concern: The table drifts again unless a CI check compares it with the runtime's public methods.

**Q3b — Vote: G**
Reasoning: With G, a user looks in one place, the §3 table, to find out whether a method grows the buffer. Two hand-kept lists drift, which is how this ticket started. G also drops `concat` for free, because it does not grow its receiver.
Concern: The E0814 message must name the *grows* mark and point at the §3 row, or the user does not know why the call fails.

**Q4 — Vote: P-split**
Reasoning: You can see the direction at the call site: `with_mut_ptr` means C writes, and `with_ptr` means C reads. With P-root, you must trace the binding to know which, and that is hard for a reviewer and for the audit tool. It is one extra method, it has the same name as Rust's `as_mut_ptr`, and only the curated wrappers use it.
Concern: Users copy wrapper code and call `with_ptr` where C writes, so the audit and the docs must flag that case clearly.

**Q5 — Vote: W**
Reasoning: The bootstrap protocol requires the steps anyway, because src and lib/std hold the code that changes. With a warning first, users get one release to add `mut` before the build breaks. That is kinder than a hard error with no notice.
Concern: The warning step must not ship without value codegen behind it, or the warning describes rules the binary does not follow.

**Q6 — Vote: N**
Reasoning: A JS or Python dev who reads "Bytes is a value" asks at once, "does every write copy the buffer?" One sentence that says no to this question prevents a defensive `clone()` habit and a lot of forum threads. Swift's docs give the same promise for `Array` and `Data`, and it helps.
Concern: If the sentence reads as normative, it binds codegen to a copy-on-write method the panel chose to leave open.

##### PLT

**Q1: V**
Reasoning: §3.6 already gives the rule: a type that is not on the list cannot change through a second name. V makes gen1 match the spec, so no decided ruling changes. Under S, `clone()` aliases and Template Q2 must reopen. F is sound, but it reverses the 6-0 offset-API ruling and the §3.2.2 "no split" ruling.
Concern: the codegen unshare analysis is the soundness proof now, and one missed copy site gives a silent alias that no type error reports.

**Q2: Y**
Reasoning: the parameter-mutation ruling says a method mutates if and only if it declares `mut self`. Writers with plain `self` break that rule under every aliasing model. With `mut self`, E0610 marks every place a mutation starts.
Concern: none from my seat. The vote is the same under V, S or F.

**Q3a: Y**
Reasoning: the table is the type signature users and tools rely on. A method that ships without a row has no typing rule in the spec.
Concern: the table may drift again as the runtime adds methods, unless a check in `task ci` ties the table to lib/std/bytes.bl.

**Q3b: G**
Reasoning: when one rule is stated in two places, the copies drift apart, and the E0814 list already names five methods that do not exist. If E0814 is defined by a *grows* mark in the table, `concat` drops out on its own, because it takes `self` and returns a new value. That is the same as Min's cut, with no second list. The existing `@bytes_grows` attribute can be the mechanism behind the mark.
Concern: E0814 is a syntactic check, so the mark must stay correct on each new method, or the pin stops being sound.

**Q4: P-split**
Reasoning: whether a method writes must show in its own type. P-root makes `with_ptr` writing or not depending on the caller's root, which breaks the rule from Q2 and does not compose through generic helpers. P-unchanged lets C change a value behind an immutable `let`, which breaks §3.6.
Concern: a user who calls `with_ptr` where they need `with_mut_ptr` lets C write through a read pin. Only the audit catches that, not the type checker.

**Q5: I**
Reasoning: the ordering is a bootstrap procedure, not language semantics, so it does not belong in sections/. The one constraint that matters is that the value codegen lands with or before E0610. That constraint goes on the implementation ticket.
Concern: if no one records that ordering on the ticket, a window could ship where `let mut b = a` still aliases.

**Q6: R** (I withdraw my N proposal)
Reasoning: on reflection, "at most once" is a promise that a simple per-root uniqueness flag cannot always keep. For example, a root with two Bytes fields may copy twice. A cost promise in sections/ would then constrain the mechanism, which V says the spec leaves open. The decision record and the codegen chore are the right home for it.
Concern: users get no written cost model in the spec, so a performance cliff, as in Swift, may surprise them.

##### DevOps

**Q1: V**
Reasoning: Under V, a wrong guess about aliasing shows up as an E0610 with a fix-it the LSP already offers, or as a test that fails. Under S it compiles clean, and no lint can tell an intended alias from a bug. F splits autocomplete across two types and needs a custom note on every writer name.
Concern: copies that codegen adds where the user cannot see them will produce speed reports that no tool can explain unless codegen records where each unshare copy happens.

**Q2: Y**
Reasoning: It matches the parameter-mutation ruling and reuses E0610, its fix-it and the unused-`mut` lint with no new code. The MVCE's `let b = a; b.push(5)` must not compile.
Concern: the E0610 note must name the root binding even when the receiver is a field path (`p.buf.set_u16_le`), or the fix-it points at the wrong line.

**Q3a: Y**
Reasoning: The table is the source of truth for hover, autocomplete and `blink doc`. If a method has no row, it is not public, and the LSP must not offer it.
Concern: the runtime can ship a method again without a table row unless a `task ci` check compares the two.

**Q3b: G**
Reasoning: One source means the E0814 list and the table cannot drift. Hover can show "grows" on the method, and the E0814 message can cite the table row. A hand-kept list in §9.1.3.1 already names methods that do not ship.
Concern: the *grows* mark must reach the checker from the stdlib declaration (for example `@bytes_grows`), not from a list in the compiler that copies the spec.

**Q4: P-split**
Reasoning: The direction lives in the signature, so hover, `blink audit` (`byte-pin-read` / `byte-pin-write`) and code review see it without a root analysis. A read pin never copies, but under P-root a read-only pin on a `let mut` root with an alias would.
Concern: nothing stops C from writing through a `with_ptr` pointer, so the audit category and the `@trusted` text carry that promise alone.

**Q5: I**
Reasoning: No users outside the tree depend on Bytes aliasing, so a warning stage protects nobody. The order of the steps is a bootstrap question for the implementation ticket.
Concern: if the ticket enforces E0610 before value codegen lands, the tree passes through a state where `mut` is required but aliasing still shows.

**Q6: R**
Reasoning: A cost sentence in sections/ becomes a promise every backend must keep, and the spec should say what a program means, not how fast it runs. The cost goes in the decision record and the codegen chore, and later tooling (a copy-explain flag or perf lint) can show it to users.
Concern: with no written cost model, users may assume every bind copies and work around a cost that does not exist.

##### AI/ML

**Q1 — Vote: V**
**Reasoning:** The §3.6 text already says that a type not on the list cannot change through a second name, so a model that learns from the spec alone predicts value behaviour for Bytes today. V keeps that rule true with no new fact to learn. A model also reads the name `Bytes` as the twin of `Str` and of Python `bytes`, and `clone()` on a value copies, as every model expects. S teaches an aliasing `clone()`, and F adds a "Bytes or builder?" choice at every buffer.
**Concern:** If codegen copies too much, users and models may fall back to `List[U8]` workarounds for performance, which splits the idiom.

**Q2 — Vote: Y**
**Reasoning:** This is the same rule as for List: a method that mutates declares `mut self`, and its root must be `mut`. The E0610 fix-it is mechanical, so a model that forgets `mut` gets a clear one-line repair.
**Concern:** Generated code that discards a result with `let _ = b.set_*` may hide the `mut` need from a reader. The examples in the spec should use `?`.

**Q3a — Vote: Y**
**Reasoning:** A model can only write what the spec documents. Today the runtime ships `new`, `push` and `write_*`, but the spec does not list them, so models guess, or call methods that the spec never promised. One full table is the single source of truth.
**Concern:** The table can drift from lib/std/bytes.bl again unless a check enforces it.

**Q3b — Vote: G**
**Reasoning:** One list, in one place, means one fact to learn. A "grows" mark in the §3 table makes E0814 follow from the method table, so a model does not need to remember a second list that can drift. It also removes `concat`, which never mutated its receiver, with no special case.
**Concern:** The "grows" column adds a column that every reader of the table must parse, even if they never use FFI.

**Q4 — Vote: P-split**
**Reasoning:** The direction shows in the method name and in the `mut self` receiver, so the type checker catches a model that writes `let buf` and then lets C fill it. P-root makes one method's meaning depend on how a binding was declared, which is a hidden decision point. `with_mut_ptr` matches Rust's `as_mut_ptr`, which models already know.
**Concern:** A model may call `with_ptr` and pass `p` to a C function that writes, and only the audit, not the compiler, catches that.

**Q5 — Vote: I**
**Reasoning:** The spec describes the end state, and a model learns from that state, not from the order of the rollout. The CLAUDE.md bootstrap protocol already makes this change a multi-step process, so the implementation ticket should hold the order (W in practice, with value codegen in place before E0610).
**Concern:** If the ticket lands E0610 before value codegen, the compiler would accept `let mut` code whose writes still show through a second name.

**Q6 — Vote: R**
**Reasoning:** Spec text is the training data, and a cost promise in sections/ reads as a semantic guarantee. "At most once" may also be false under a mechanism that codegen picks later. The decision record and the codegen chore are the right place to hold it.
**Concern:** Without a stated cost model, models may add a defensive `clone()` before writes, which wastes a copy.

##### Minimalism

**Q1 — Vote: V**
Reasoning: V adds no rule. §3.6 already says that only types on the list change through a second name, so the spec is right and the code is wrong. S grows "the only list" and reopens a 6-0 ruling. F adds a type and brings in the MutX/X split that §3.2.2 rejects.
Concern: if the codegen for copy-on-write or copy-on-bind is wrong, it is unsound, and the failure is silent, so the chore needs a dedicated corpus of aliasing tests.

**Q2 — Vote: Y**
Reasoning: The parameter-mutation ruling already says a method mutates only if it declares `mut self`, so this applies a vote we already took. It reuses E0610, its fix-it and the LSP support, so we add no new surface.
Concern: someone may give a future Bytes writer plain `self` and the hole opens again, so the spec table should mark each writer.

**Q3a — Vote: Y**
Reasoning: The spec must describe what ships, all of it and nothing more. A row for a method that does not exist is surface with no user.
Concern: none from my seat.

**Q3b — Vote: G**
Reasoning: G beats my own C. It replaces a list that must be kept in step by hand with one reference to the table, so the E0814 list and the methods cannot drift apart. That leaves one list, kept in one place, and `concat` drops out because it does not grow the receiver.
Concern: the "grows" marker must be in the table text, or E0814 refers to nothing.

**Q4 — Vote: P-split**
Reasoning: I withdraw P-root. It gave one call two meanings that depend on how the binding was declared, and that hidden rule costs more than one extra method. P-split makes "every write starts at a `mut` root" true with no FFI exception. P-unchanged leaves this ticket's hole open through C.
Concern: users may reach for `with_mut_ptr` by default, which forces needless `let mut` and unshare copies on read-only pins.

**Q5 — Vote: O**
Reasoning: Nothing outside this tree calls `set_*`, and Blink is pre-1.0. A warning phase adds a diagnostic that docs and tools must carry, and nobody gains from it. One step, with the value codegen landing in the same change as E0610, gives no window where the two disagree.
Concern: if E0610 lands before the value codegen, the tree passes `mut` checks while still aliasing, so the two must ship together.

**Q6 — Vote: R**
Reasoning: A cost promise in sections/ fixes one mechanism in place, and it is an implementation detail that the boxed-field ruling deliberately leaves open. The promise belongs in the decision record and the codegen chore.
Concern: without a written bound, a lazy implementation could copy on every write and still meet the spec.

#### Phase D — Round 2 (Q5)

Q5 was 4-1-1 in Phase C. One focused round on Q5 only; all six re-voted I. Result: **I, 6-0 R2 after 4-1-1 R1.**

##### Systems

**Response:** All six texts share one hard rule: value codegen must land with or before E0610. W, O and I differ only in where the steps get written down. Web's "one release of notice" and Min's "no users outside the tree" are both claims about rollout, and the implementation ticket is the place to weigh them. The spec only records the end state. Under the bootstrap protocol the ticket will likely end up close to W for src and lib/std, since the compiler's own code changes. But that is a process fact, not something a Blink user sees.

**Vote: I**

**Reasoning:** The rollout order is a repo bootstrap procedure, and sections/ describes the language, not how this compiler moves to it. The decision record should still carry the one ordering rule all six seats named: value codegen and its aliasing corpus land with or before E0610. That rule then binds the ticket without putting rollout steps in the spec.

**Concern:** If the decision record leaves out the ordering rule, the ticket could land E0610 first. That opens a window where `mut` is required but writes still show through a second name.

##### Web/Scripting

Response: DevOps and Min are right that nobody outside this tree uses `set_*` or aliasing on Bytes. So my main reason for W, "give users one release to add `mut`", protects no real user. Sys, PLT and AI/ML are also right that the order of the steps is a bootstrap procedure, and the spec describes the end state. All six concerns name the same risk: E0610 lands before value codegen. One ticket rule handles it, and that rule needs no spec text.

**Final vote: I**
Reasoning: A Blink user reads only the end state in sections/, so the order of the rollout does not affect them. The CLAUDE.md bootstrap protocol already decides how many steps the tree needs. The implementation ticket should record the order, with one hard rule: value codegen and its aliasing tests land with or before E0610.
Concern: If no one copies that rule onto the implementation ticket, a release could require `mut` while writes still show through a second name.

##### PLT

Response: All six texts agree on the one constraint with semantic weight: value codegen lands with or before E0610. Web's warning release and Min's single step are both valid rollout plans, and they differ only in the order of the work. That difference is not part of the language, so a spec vote should not fix it. The CLAUDE.md protocol may force several regens in any case, which makes O hard to promise. To Web: a warning that ships before value codegen describes rules the binary does not follow. That is the same hazard everyone names, and the ticket must close it either way.

**Final vote: I**
Reasoning: sections/ describes the end state, and the end state is the same under W and O. Whether a deprecation warning ships for one release is a call for the implementation ticket and release notes. The panel's ruling should record one binding constraint for that ticket: value codegen, with its aliasing tests, lands with or before E0610 and any warning.
Concern: if the decision record leaves out that constraint, the ticket may enforce `mut` while aliasing still shows.

##### DevOps

**Response.** All six texts share the same concern: value codegen must land with or before E0610. The disagreement is only about where that rule lives. To Web: a warning gives a user one release of notice, but no users outside the tree depend on this. While the warning is out, it tells users to add `mut` to code whose writes still show through a second name, unless value codegen has already landed. To Min: one change is fine as an implementation choice, but self-hosting may force the steps apart anyway, and the spec should not care which way it goes. I keep I, and the decision record should state the constraint everyone shares, not leave it to the ticket alone.

**Q5: I**
Reasoning: The spec describes the end state, and the rollout order is a bootstrap question set by the repo's self-hosting protocol. The decision record should still carry one binding rule for the implementation ticket: value codegen and its aliasing tests land with or before E0610. Whether that takes one change or three is the implementer's call under that rule.
Concern: if the decision record leaves out the "with or before" rule, the ticket may enforce `mut` while writes still show through a second name.

##### AI/ML

**Response:** All six texts name the same single risk: E0610 must not land before value codegen. So the real agreement is one ordering constraint, not a choice of step count. Web's point about a warning release for users is fair, but DevOps and Min are right that no code outside the tree depends on Bytes aliasing, so the warning protects no one. Min's one-step option and Web's three steps are both valid ways to meet the constraint. The bootstrap protocol, not the spec, decides which one the repo can use. That is why the order belongs on the ticket.

**Final vote: I**

**Reasoning:** sections/ is training data, and a model learns the end state from it, not the rollout. A migration plan in the spec would become stale text after it ships. The decision record should still state the constraint once: "value codegen lands with or before E0610". The ticket then holds the step order.

**Concern:** If the decision record omits that constraint, the implementer may not see the risk that all six panelists flagged.

##### Minimalism

Response: Sys, PLT, DevOps and AI/ML are right that the rollout order is not language semantics, and keeping it out of sections/ is the smaller choice, which is my seat's whole lens. What I cared about in O was two things: no user-facing warning that docs must carry, and no window where E0610 holds but aliasing still shows. Both fit on the implementation ticket. All four I texts share the same concern I raised, so the ticket constraint is not in dispute. To Web: the bootstrap protocol forces steps inside this tree, but it does not force a released warning diagnostic. Nobody outside the tree depends on the old behaviour.

**Q5 — Vote: I**
Reasoning: The spec describes the end state, and a migration order in sections/ is text that dies the day it ships. The ticket should record two rules. First, value codegen with its aliasing corpus lands with or before E0610. Second, any warning step stays internal to the bootstrap and never becomes a documented diagnostic.
Concern: the ticket may keep a warn-first step as a shipped diagnostic code, which would leave dead surface in the error index.

### Final Spec

```blink
// Bytes is a value. It is not a shared cell (§3.6).
fn new() -> Bytes
fn set(mut self, Int, Int)                                  // panics outside [0, len)
fn push(mut self, Int)                                      // grows
fn write_u16_le(mut self, Int)                              // grows; also _be, u32, i32, i64
fn set_u16_le(mut self, Int, Int) -> Result[(), Str]        // also _be, i16, i32, u32, i64, u64
fn with_ptr[R](self, fn(Ptr[U8]) -> R ! _) -> R ! _         // read-only pin
fn with_mut_ptr[R](mut self, fn(Ptr[U8]) -> R ! _) -> R ! _ // C may write
```

- `Bytes` is a value: a write through one name never shows through another, for bind, pass, return, `clone()`, a struct field and a template hole. The mechanism is a codegen choice, not spec text.
- Every writer declares `mut self`; a call on an immutable root is `E0610`.
- The §3.2.3 table lists every shipped method and no unshipped one.
- `E0814` rejects, inside a pin closure, a call on the pinned receiver to any method the table marks *grows* (`push`, `write_*_le/be`). The table is the only list. `concat` and `slice` return a new value and do not grow.
- `with_ptr` is read-only: C must not write through the pointer, and only the audit can catch a violation. `with_mut_ptr` needs a mutable root. `E0814` and `E0815` cover both pins. The curated libc read wrappers use `let mut buf` and `with_mut_ptr`.
- No rollout text in sections/. **Binding on the implementation:** value codegen, with its aliasing tests, lands with or before `E0610` for Bytes writers, so no build requires `mut` while writes still show through a second name. Any warn-first step stays inside the bootstrap and never ships as a documented diagnostic (Min, Phase D).
- No cost text in sections/. The cost promises the codegen must keep, quoted from Sys (Phase B):

1. A bind, pass, return or store into a field, List or template hole never copies the bytes. It is one pointer copy plus, at most, one store to a "shared" bit in the header.
2. Only a `mut self` writer or `with_mut_ptr` can copy, and it copies only when the buffer may have a second live name. After that copy, writes run in place until the next copy-out.
3. A buffer that never had a second name never copies. This is the common "zeroed, fill, return" path. Codegen uses last-use liveness so a move does not set the bit.

- The TemplateValue Bytes ruling (Q2) stands as written.
