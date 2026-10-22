[< All Decisions](../DECISIONS.md)

# SHA-256 in std — Design Rationale

**Result:** Q1 6-0 for M1 (module `std.digest`, SHA-256 only). Q2 5-1 for R3 in Phase D (an opaque `Sha256`; Minimalism dissented, for plain `Bytes`). Q3 5-1 for I1 (a value hasher, `Sha256State`; Minimalism dissented, for no hasher now). Q4a 5-1 for O1 (`Sha256.of`; Minimalism voted O2 and asked that the vote count as O1 once R3 won). Q4b 6-0 for T1 (digest `Sha256`, hasher `Sha256State`). Q2, Q4a and Q4b were 4-2 in Phase C and went to one Phase D round. AI-first review: 5/5 pass.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in four phases: independent proposals, one debate round, a silent vote, and a second silent vote on the three questions that split 4-2. Quoted text is each panelist's own words. A quote is a whole proposal, a whole section of a reply, or a whole ballot entry, with heading marks turned into bold text. A line that names a task-tracker ticket is left out, because those tickets are local to one machine; each omission is a whole line.

Questions:

- Q1: the module name. **M1** `std.digest`.
- Q2: the type that the one-shot call returns. **R1** plain `Bytes`, always 32 bytes. **R3** an opaque digest type, always 32 bytes, with a closed method list and a strict `from_hex`.
- Q3: the incremental hasher. **I0** none now. **I1** a value hasher with `new()`, `update(mut self, data: Bytes)` and `finish(self)`.
- Q4a: the one-shot call. **O1** `Sha256.of(data)`, a type-scoped fn. **O2** `digest.sha256(data)`, a free fn.
- Q4b: the type names under R3 and I1. **T1** digest `Sha256`, hasher `Sha256State`. **T2** hasher `Sha256`, digest `Sha256Digest`.

The panel did not vote on trait names. The moderator took `Digest` from the PLT proposal and `DigestWriter` from the DevOps proposal. Neither name has "Hash" in it, and no type or trait is named `Hasher`.

#### Phase A — Independent proposals

Full proposals, verbatim.

- **Systems:**

  > Seat question: what does the hardware see? SHA-256 is 64 rounds of 32-bit add/rotate/xor over a 64-byte block,
  > with a fixed 104-byte state (8 x u32 chaining value, a 64-byte tail buffer, a u64 length). Nothing in it needs the
  > heap, an effect, or dynamic dispatch. The spec must not add any of the three.
  >
  > ---
  >
  > **sys-1 (FIRST CHOICE): `std.digest`, pure, fixed-state hasher + one-shot fn, `Sha256Digest` newtype over Bytes**
  >
  > ```blink
  > import std.digest.{Sha256, Sha256Digest, sha256}
  > import std.fs.{FsError}
  >
  > // One-shot: pure, no effect row.
  > fn cache_key(src: Str) -> Str {
  >     sha256(Bytes.from_str(src)).to_hex()
  > }
  >
  > // Incremental: fixed state, no allocation per write.
  > fn tree_hash(files: List[Str]) -> Result[Sha256Digest, FsError] ! FS.Read {
  >     let mut h = Sha256.new()
  >     for path in files {
  >         let text = fs.read(path)?     // fs.read -> Result[Str, FsError] (04_effects.md:1005)
  >         h.write_str(text)
  >     }
  >     Ok(h.finish())
  > }
  >
  > fn lock_entry(d: Sha256Digest) -> Str {
  >     "sha256:{d.to_hex()}"
  > }
  > ```
  >
  > Surface (complete list):
  >
  > | Item | Signature | Note |
  > |---|---|---|
  > | `sha256` | `fn sha256(data: Bytes) -> Sha256Digest` | pure, cannot fail |
  > | `Sha256.new` | `fn new() -> Sha256` | fixed-size state |
  > | `Sha256.write` | `fn write(mut self, data: Bytes)` | same verb as `StringBuilder.write` |
  > | `Sha256.write_str` | `fn write_str(mut self, s: Str)` | hashes the UTF-8 bytes of `s`, no copy into a `Bytes` |
  > | `Sha256.finish` | `fn finish(self) -> Sha256Digest` | consumes nothing observable; the state is a value |
  > | `Sha256Digest` | `type Sha256Digest { Sha256Digest(Bytes) }` | transparent newtype (F20), always 32 bytes |
  > | `.to_hex` | `fn to_hex(self) -> Str` | 64 chars, lowercase, equals `sha256sum` |
  > | `.to_bytes` | `fn to_bytes(self) -> Bytes` | the 32 raw bytes |
  >
  > `Sha256Digest` implements `Eq`, `Clone`, `Debug`. It does NOT implement `Hash` (see below).
  >
  > **Why each choice, from the hardware up**
  >
  > 1. **Pure, no `! Crypto.Hash`.** SHA-256 is a total function of its input. An effect row on it buys nothing and
  >    costs three things:
  >    - every caller up the stack must carry the row (the compiler cache-key path in src/std_cache_key.bl,
  >      src/build_objcache.bl would gain an effect for arithmetic);
  >    - an effect is handler-swappable. A handler that returns a fake digest is an integrity hole in exactly the code
  >    - a handled op is an indirect call per invocation; a pure fn can inline and be const-evaluated.
  >    Go (`crypto/sha256.Sum256`), Rust (`sha2::Sha256::digest`), Zig (`std.crypto.hash.sha2.Sha256.hash`) are all
  >    plain functions. I propose the panel also fix the example at 03_types.md:1337 so it does not teach
  >    `! Crypto.Hash` for a digest. `Crypto.Hash` stays reserved (already decided); this proposal does not use it,
  >    and I would leave it for a keyed/secret-material op if one ever needs a capability gate.
  >
  > 2. **Module `std.digest`, not `std.crypto` and not `std.hash`.**
  >    - `std.hash` reads as the home of the `Hash` trait (seeded, U64, per-process). Two meanings of "hash" in one
  >      name is the confusion the ticket warns about.
  >    - `std.crypto` collides with the reserved `crypto` effect handle (04_effects.md:300: the handle is the
  >      lowercase effect name). Code that writes `crypto.` would mean an effect op in one file and a module item in
  >      another. It also promises sign/encrypt, which std does not ship.
  >    - "digest" names what the function returns, and gives a home for later algorithms without a rename.
  >    Python (`hashlib`) and Go (`crypto/sha256`) both kept it separate from the dict-hash machinery.
  >
  > 3. **`Sha256Digest` newtype over `Bytes`, not bare `Str` hex, not bare `Bytes`.**
  >    - Hex `Str` as the return type allocates 64 bytes of text and a UTF-8 Str for every digest, then every compare
  >      is a 64-byte compare. Raw is 32 bytes; hex is a call away (`to_hex`, already in BytesOps, F13).
  >    - Bare `Bytes` loses the 32-byte invariant and lets any `Bytes` flow where a digest is expected.
  >    - The newtype is zero-cost by the Errno precedent (F20): in C it is the `Bytes` itself, no wrapper struct.
  >    - A fixed `[U8; 32]` value type would avoid the heap for the digest entirely. Blink has no fixed-size array
  >      type, and adding one is not this ticket. The newtype keeps that door open: the representation is private,
  >      so a later fixed-size layout changes no user code.
  >
  > 4. **Hasher is a value with a fixed layout.** `Sha256` is 104 bytes of state. `write` processes whole 64-byte
  >    blocks in place and keeps the tail; no heap growth however much you feed it. That is the only way to hash the
  >    lib/pkg tree (F9) or a large input without building one giant `Bytes` (src/sha256.bl:62 reads the whole file
  >    today). With no fs handles in v1 (F18), the caller reads file-by-file and writes into one hasher, which is
  >    exactly what `find | sort | xargs cat | sha256sum` does.
  >    Note: v1 `fs.read` returns `Str` (04_effects.md:1005); there is no bytes read in the `fs` surface, so a
  >    binary file cannot reach the hasher through `fs` at all today. That is an `fs` gap, not a digest gap; I flag
  >    it for a friction ticket, not for this vote.
  >    `write_str` exists because `Bytes.from_str(s)` copies; a Str is already UTF-8 bytes, so the runtime can feed
  >    its buffer straight in. One extra method for a zero-copy path on the most common input type is worth it.
  >
  > 5. **SHA-256 only.** One algorithm has a caller (lockfile, compiler cache, lib/pkg). SHA-1 and MD5 are broken
  >    and would invite misuse; SHA-512 and BLAKE3 have no caller. BLAKE3 in particular is only fast with SIMD
  >    code paths, which is a large runtime surface to audit. Add each when a caller appears, as `Sha512`,
  >    `Blake3` beside `Sha256` in the same module, same method set.
  >
  > 6. **Not `Hash`.** `Sha256Digest` must not implement the `Hash` trait (already decided in spirit, F2/F3). A user who
  >    wants a digest as a Map key keys on `d.to_hex()`. I leave `Hash` off in v1: `Hash` for a newtype over Bytes is a one-line add later, and removing it
  >    would break code.
  >
  > 7. **No constant-time compare in v1.** SHA-256 over public data (lockfile, cache keys) has no secret, so `==`
  >    timing does not leak anything. Constant-time compare matters for MAC verification. That belongs with HMAC,
  >    which is out of scope. State in the spec that `Sha256Digest ==` is not constant-time.
  >
  > **Spec obligations (normative text I would want)**
  >
  > - Output equals FIPS 180-4 SHA-256; `to_hex` is lowercase, 64 chars (matches `sha256sum`, already decided).
  > - `sha256`, `Sha256.*` and `Sha256Digest.*` are pure: no effect row.
  > - `Sha256` state size and per-`write` cost are independent of total input length (no hidden buffering of the
  >   whole input). This is the one performance promise the spec should make, because a pure-Blink
  >   `List[Int]` implementation (src/sha256.bl) can silently break it. How std reaches C is an impl matter (F23).
  > - After `finish`, the hasher may be used again only after `Sha256.new()`; whether `finish` resets is
  >   specified (I propose: `finish(self)` takes `self` by value, so the old state stays valid and calling
  >   `write` after `finish` keeps hashing the prefix plus new data, like Go `h.Sum(nil)`). This lets a caller
  >   take a running digest at no cost.
  >
  > **Tradeoffs (sys)**
  >
  > - Pro: zero allocation per write; one 32-byte buffer per digest; pure, so it inlines and folds.
  > - Pro: the `Bytes` digest newtype keeps a future fixed-size repr possible without API change.
  > - Con: two surfaces (one-shot + hasher). The one-shot is `Sha256.new()` + `write` + `finish` in one call; I keep
  >   it because it is the 90% case and lets the runtime skip the tail-buffer copy for a single input.
  > - Con: `write_str` is a second write method. Drop it if the panel prefers one method; the cost is one
  >   `Bytes.from_str` copy per Str.
  >
  > ---
  >
  > **sys-2: one-shot only, `Sha256Digest` return, no hasher**
  >
  > ```blink
  > import std.digest.{sha256}
  >
  > fn key(src: Str) -> Str {
  >     sha256(Bytes.from_str(src)).to_hex()
  > }
  > ```
  >
  > Smallest surface. Fails the lib/pkg case at scale: the caller must `concat` every source file into one `Bytes`
  > first (O(total size) memory, plus O(n^2) copies if built by repeated `concat`). I list it so the panel sees the
  > cost of dropping the hasher; I oppose it.
  >
  > ---
  >
  > **sys-3: hex `Str` return (`sha256_hex(data: Bytes) -> Str`), copy src/sha256.bl as-is**
  >
  > ```blink
  > import std.digest.{sha256_hex}
  >
  > fn lock_entry(data: Bytes) -> Str {
  >     "sha256:{sha256_hex(data)}"
  > }
  > ```
  >
  > Matches today's compiler API and the lockfile shape directly. Costs a 64-byte text alloc per digest, doubles
  > compare cost, and gives no type for "this is a digest". A future `from_hex` would be needed to compare raw. I
  > oppose it as the primary API; `Sha256Digest.to_hex()` gives the same string in one call.
  >
  > ---
  >
  > **Position on the effect question (applies to all three)**
  >
  > Pure. I oppose any proposal that puts `! Crypto.Hash` on SHA-256. If the panel wants the reserved
  > `crypto.hash(...)` handle to exist, it should be a thin effectful wrapper over the pure fn, never the only path,
  > and the compiler's own cache keys must use the pure fn.

- **Web/Scripting:**

  > Seat: Web/Scripting. Test I apply: can a Python or Node dev hash a string on the first try, without reading
  > three spec sections, and without a Stack Overflow question about which "hash" they got?
  >
  > **web-1 (FIRST CHOICE): module `std.sha256`, two pure one-shot functions, Bytes digest, no newtype**
  >
  > ```blink
  > import std.sha256
  >
  > fn cache_key(src: Str) -> Str {
  >     sha256.hex(src)                          // 64 lowercase hex chars over the UTF-8 bytes of src
  > }
  >
  > fn tag(data: Bytes) -> Str {
  >     "sha256:{sha256.digest(data).to_hex()}"  // lockfile shape, 06_tooling.md:523
  > }
  >
  > test "sha256 matches sha256sum" {
  >     assert_eq(sha256.hex(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
  >     assert_eq(sha256.hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
  >     assert_eq(sha256.digest(Bytes.from_str("abc")).len(), 32)
  >     assert_eq(sha256.digest(Bytes.from_str("abc")).to_hex(), sha256.hex("abc"))
  > }
  > ```
  >
  > Surface, complete:
  >
  > | Function | Signature | Meaning |
  > |---|---|---|
  > | `sha256.digest` | `fn digest(data: Bytes) -> Bytes` | the 32-byte SHA-256 digest of `data` |
  > | `sha256.hex` | `fn hex(s: Str) -> Str` | `digest(Bytes.from_str(s)).to_hex()`: 64 lowercase hex chars |
  >
  > Rules:
  > - Both are **pure** and total. No effect, no error, no `Result`. The empty input is valid.
  > - The hex output is lowercase and equals `sha256sum` output for the same bytes (decided constraint).
  > - `hex` hashes the UTF-8 bytes of the `Str`. There is no normalization (no newline added, no trim).
  > - For hex over `Bytes`, the user writes `sha256.digest(b).to_hex()`. `Bytes.to_hex` already exists
  >   (03_types.md, F13), so no third function is needed.
  > - SHA-256 only. No SHA-1 or MD5 (broken; shipping them in a tier-1-forever std invites misuse, and
  >   "batteries included" does not oblige us to ship dead batteries). SHA-512 and BLAKE3 come later as sibling
  >   modules (`std.sha512`, `std.blake3`) with the same two-function shape, when a caller asks.
  >
  > **Why the module is `std.sha256` and not `std.crypto` or `std.hash`**
  >
  > This is the part that decides the number of confused users.
  >
  > - **`std.crypto` collides with the `crypto` effect handle.** 04_effects.md:300 reserves the handle
  >   `crypto` for `Crypto.*` (`crypto.hash(...)`, `crypto.sign(...)`). A module imported as `std.crypto`
  >   is also called as `crypto.xxx(...)`. A reader then sees `crypto.hash(data)` and cannot tell if it is a
  >   plain function or an effect operation that a handler can replace. That is a guaranteed Stack Overflow
  >   question, and a guaranteed wrong answer from an LLM.
  > - **`std.hash` collides with the `Hash` trait** in the reader's head. `x.hash()` is seeded, U64, and
  >   changes per process (F2). A module called `hash` whose output is stable across machines is the exact
  >   confusion the ticket warns about. Python already lives with `hash()` vs `hashlib`, and "why does
  >   `hash("a")` change between runs" is one of its most-asked questions. Do not copy that.
  > - **`std.sha256` says what it is.** The call site `sha256.hex(s)` needs no doc lookup. It matches the
  >   one-module-per-concern layout of lib/std (F16), and Go's `crypto/sha256` (`sha256.Sum256(b)`), which is the
  >   most-copied precedent in the systems/web overlap.
  >
  > **Why pure, not `! Crypto.Hash`**
  >
  > No JS, Python, Go, Kotlin or Rust dev thinks hashing a string is a side effect. If `sha256.hex` carried
  > `! Crypto.Hash`, every cache-key helper, every lockfile writer, and every function that calls them would
  > need the effect in its signature, for zero gain: SHA-256 has one correct output, so there is nothing a handler
  > could usefully swap in (a mock that returns a different digest makes a test lie). The compiler's own
  > src/sha256.bl is already pure (F6), and it is the only real caller we have.
  >
  > Consequence for the spec: the illustrative example at 03_types.md:1337
  > (`fn compute_hash(data: Bytes) -> Bytes ! Crypto.Hash { crypto.hash("sha256", data) }`) teaches a second,
  > effectful, string-keyed way to do the same thing. Replace it with the pure call:
  >
  > ```blink
  > fn compute_hash(data: Bytes) -> Bytes {
  >     sha256.digest(data)
  > }
  > ```
  >
  > I do not ask to remove the `Crypto.Hash` reservation (decided; not reopened). I note that after this vote it has
  > no user, and a later panel can decide if it means anything (for example a hardware or remote KMS digest).
  >
  > **Why `Bytes` and a `Str` helper, not a `Digest` newtype**
  >
  > - The 90% case is "give me the hex string" (cache keys, ETags, lockfile entries, content addressing).
  >   `sha256.hex(s)` is one call and returns a `Str` the user already knows how to print, compare and store.
  > - The other case is "give me raw bytes" (feed into HMAC later, write to a binary format). `Bytes` is the
  >   existing type for that. A `Digest` newtype adds a type to learn, a conversion at every boundary
  >   (`d.to_hex()`, `d.to_bytes()`), and an import, to protect against a bug (mixing a digest with other bytes)
  >   that I have never seen in a code review.
  > - Node returns a `Buffer` or a string depending on the `digest('hex')` argument; Python gives `.digest()` and
  >   `.hexdigest()`. Both are "bytes or hex string", no wrapper type. Users understand that split already.
  >
  > **Tradeoffs (web view)**
  > - Pro: two names to learn. Copy-paste from Python (`hashlib.sha256(s.encode()).hexdigest()`) maps to one call.
  > - Pro: no effect row noise; no new type; reuses `Bytes.to_hex`.
  > - Con: `hex` takes `Str` only. A user with `Bytes` who wants hex writes `.digest(b).to_hex()`. I accept that:
  >   it is discoverable from the table and the result is obvious.
  > - Con: no streaming. Input must fit in memory. See web-2.
  > - Con: `==` on two digests is not constant-time. That matters only for MAC checks, which this vote does not ship.
  >   When HMAC lands, it ships its own `verify` that compares in constant time; users should never compare MACs by hand.
  >
  > **What it fixes now**
  >
  > ```blink
  > import std.fs
  > import std.sha256
  >
  > fn package_hash(paths: List[Str]) -> Result[Str, FsError] ! FS.Read {
  >     let mut all = Bytes.new()
  >     for p in paths.sort() {
  >         all = all.concat(Bytes.from_str(fs.read(p)?))
  >     }
  >     Ok("sha256:{sha256.digest(all).to_hex()}")
  > }
  > ```
  >
  > The compiler's src/sha256.bl callers (F8) move to `std.sha256`, and src/sha256.bl goes away (one implementation,
  > not two). How it reaches C (F23) is the implementer's call.
  >
  > **web-2 (acceptable addition to web-1, not required): incremental hasher in the same module**
  >
  > Only if a panelist shows a caller that cannot hold the input in memory. The one I can see: hashing stdin in chunks
  > (`cat big.iso | mytool`), since `io.read_bytes(n)` is the only streaming input (fs has no handles, F18).
  >
  > ```blink
  > import std.sha256
  >
  > fn main() ! IO {
  >     let mut h = sha256.new()
  >     loop {
  >         let chunk = io.read_bytes(65536)
  >         h.update(chunk)
  >         if chunk.len() < 65536 { break }
  >     }
  >     io.println(h.finish().to_hex())
  > }
  > ```
  >
  > | Function / method | Signature | Meaning |
  > |---|---|---|
  > | `sha256.new` | `fn new() -> Sha256` | a fresh hasher |
  > | `Sha256.update` | `fn update(mut self, data: Bytes)` | feed more bytes |
  > | `Sha256.finish` | `fn finish(self) -> Bytes` | the 32-byte digest of all bytes fed so far; does not reset |
  >
  > - Names copied from what people already know: `update` (Python, Node, OpenSSL), `finish` (Rust `Hasher::finish`).
  >   Not `write`/`sum` (Go), because `write` reads as I/O to a scripting dev.
  > - `finish(self)` does not reset and does not consume, so calling it twice gives the same answer. Node's
  >   "digest already called" error is a well-known trap; do not reproduce it.
  > - `digest(b)` must equal `new()` + `update(b)` + `finish()`; write that as a spec rule and a test.
  > - Cost: one type and three names. I lean "defer until a caller", but if the panel adds it, this is the shape.
  >
  > **web-3 (reject): `crypto.hash("sha256", data)` with a string algorithm name**
  > This is the F5 illustration. Reject: a typo in `"sha265"` becomes a runtime error instead of a compile error,
  > the LSP cannot autocomplete the algorithm, and it puts a pure function behind an effect handle. Node's
  > `createHash(name)` takes a string only because JS had no other way; Blink does.
  >
  > **Out of scope, flagged for friction**
  > `fs` has no byte read. 03_types.md:1331 shows `fs.read_bytes(path)`, but the `fs` handle table
  > (04_effects.md:294) lists only `read/write/list_dir/stat/delete/watch`, and `fs.read` returns `Str`. So user code
  > cannot hash a binary file (a tarball, an image) at all today. That is an fs gap, not a hash gap, but it is the first
  > thing a user will hit after this ships. The moderator should file it.

- **PLT:**

  > ---
  >
  > **plt-1 (FIRST CHOICE): `std.digest`, pure, one nominal opaque type per algorithm, a `Digest` trait for the shared surface**
  >
  > **Code**
  >
  > ```blink
  > @module("digest")
  >
  > // Shared surface of every digest type. Methods must belong to a trait
  > // (§3c.4 No Inherent Methods), so the trait is the method surface, not decoration.
  > pub trait Digest {
  >     fn to_bytes(self) -> Bytes      // a fresh buffer; mutating it never changes the digest
  >     fn to_hex(self) -> Str          // lowercase hex, 2 chars per byte
  > }
  >
  > pub opaque type Sha256 {
  >     bytes: Bytes                    // exactly 32 bytes; invariant protected by `opaque`
  > }
  >
  > pub fn Sha256.of(data: Bytes) -> Sha256 { /* FIPS 180-4 */ }
  >
  > // Strict parse: exactly 64 chars of [0-9a-f]. Anything else, "" included, is None.
  > pub fn Sha256.from_hex(s: Str) -> Option[Sha256] { /* ... */ }
  >
  > impl Digest for Sha256 { /* ... */ }
  > // Also: impl Eq, Clone, Debug (prints `Sha256(<hex>)`), Display (prints <hex>).
  > // Not Hash (03_types.md:3559 contract is for container keys; decided). Not Ord.
  > ```
  >
  > Use site (lib/pkg's lockfile check, without `sha256sum`):
  >
  > ```blink
  > import std.digest.{Sha256, Digest}
  >
  > fn package_hash(sources: List[Bytes]) -> Str {
  >     let all = sources.fold(Bytes.new(), fn(acc, b) { acc.concat(b) })
  >     "sha256:{Sha256.of(all).to_hex()}"
  > }
  >
  > fn verify(expected: Str, sources: List[Bytes]) -> Result[(), Str] {
  >     if !expected.starts_with("sha256:") {
  >         return Err("lockfile hash has no sha256: prefix")
  >     }
  >     match Sha256.from_hex(expected.substring(7, expected.len())) {
  >         None => Err("lockfile hash is not 64 lowercase hex digits")
  >         Some(want) => {
  >             let all = sources.fold(Bytes.new(), fn(acc, b) { acc.concat(b) })
  >             if Sha256.of(all) == want { Ok(()) } else { Err("hash mismatch") }
  >         }
  >     }
  > }
  > ```
  >
  > **Normative rules I want in the spec text**
  >
  > - **R1 Typing.** `Sha256.of : fn(Bytes) -> Sha256`, empty effect row. Total: no `Option`, no `Result`, no panic for any input, the empty `Bytes` included.
  > - **R2 Purity.** `Sha256.of` and every `Digest` method are pure (§4.16, empty effective row). They are legal in a `@pure` fn and in a package with `capabilities = []`.
  > - **R3 Correctness law.** `Sha256.of(b).to_hex()` equals the FIPS 180-4 SHA-256 of `b` in lowercase hex (the `sha256sum` text, decided).
  > - **R4 Representation laws.** `d.to_bytes().len() == 32`; `d.to_hex().len() == 64`; `Sha256.from_hex(d.to_hex()) == Some(d)`; and if `Sha256.from_hex(s) == Some(d)` then `d.to_hex() == s`. The last law is why the parse accepts lowercase only: it makes hex text and digest values one-to-one, so a `Str` compare and a `Sha256` compare can never disagree.
  > - **R5 No aliasing.** `to_bytes` returns a new buffer. `Bytes` is mutable (`push`, `set`), so returning the internal buffer would let a caller change a value that `Eq` already compared. That is a soundness hole for an immutable value type; the spec must close it.
  > - **R6 Equality.** `==` on `Sha256` is bytewise and **not** constant-time. The spec says so in one sentence. A digest of public data is not a secret; a MAC tag is, and that is a separate future type (see plt-4).
  >
  > **Why this shape (PLT)**
  >
  > 1. **Pure, not `! Crypto.Hash`.** An effect in Blink marks an operation a handler can intercept (§4.7). If `Crypto.Hash` were a handled operation, a handler could return a different digest for the same input, and `Sha256.of(a) == Sha256.of(a)` would stop being a theorem. A cache key, a lockfile check, and a content address all depend on that theorem. The row also costs real things: a `capabilities = []` package (04_effects.md:2887) could not hash, and no `@pure` function could. The compiler's own `src/sha256.bl` is already pure (F6). Effects track interaction with the world; SHA-256 has none. Over-approximation is "sound" in the narrow sense, but it is the wrong denotation and it composes badly.
  >    - Consequence: the example at 03_types.md:1337 (`crypto.hash("sha256", data) ! Crypto.Hash`) contradicts this and must be rewritten to the plt-1 form. The `Crypto.Hash` sub-effect comment "hash functions (SHA, BLAKE, etc.)" (04_effects.md:167) then describes nothing. The brief lists the `Crypto` reservation as decided, so I do not reopen it here; I ask the moderator to file a follow-up `type:spec` to re-scope or remove `Crypto.Hash`. Leaving it as is invites an implementer to put digests behind it later.
  > 2. **`std.digest`, not `std.crypto`, not `std.hash`.** `crypto` is the reserved effect handle (04_effects.md:300). §4 says the handle is a "visual anchor that traces directly back to the capability in the signature". A module `crypto` with pure functions makes `crypto.sha256(x)` look like a capability use when it is not, which breaks that local-reasoning guarantee. `hash` collides in meaning with the seeded, process-local `Hash` trait (F2), which is the confusion the ticket names. `digest` is the precise term (FIPS 180-4 calls the output a "message digest") and it names the family, so SHA-512 or BLAKE3 later is a new type in the same module, not a new module.
  > 4. **A `Digest` trait.** Methods must come from a trait (§3c.4), so `d.to_hex()` needs one. One trait for all algorithms also gives a sound generic bound: `fn label[D: Digest](d: D) -> Str` works for every future algorithm with no new API.
  > 5. **SHA-256 only.** YAGNI: the only consumers (compiler cache keys, lockfile) need SHA-256, and the lockfile format already names it. The design makes each later algorithm additive (a new opaque type plus `impl Digest`), so deferring costs nothing.
  > 6. **No `Hash` impl, as decided.** Note for the record: implementing the `Hash` trait for `Sha256` (so it can be a `Map` key) is sound and additive later; it is not the same as reusing `Hash` as the digest API. Until then, `d.to_hex()` is the key.
  >
  > **Cross-language**
  >
  > Rust `sha2::Sha256::digest(b)` returns a fixed-size array typed by the algorithm; Go `sha256.Sum256(b)` returns `[32]byte` (a typed fixed array, not a slice) for the same reason. Both are pure functions. Haskell `cryptonite` types `Digest SHA256` by algorithm with a phantom parameter; Blink has no need for the phantom, a nominal type per algorithm gives the same separation with less machinery. Python `hashlib.new("sha256")` is the stringly-typed design I reject in plt-3.
  >
  > ---
  >
  > **plt-2 (supports plt-1, second priority): incremental state with value semantics**
  >
  > Only if the panel wants streaming now. Today the sources of chunked data are `io.read_fully(fd, n)` and `UnixStream` reads; fs has no handles (decided), so for files this buys nothing yet. I rank it below plt-1 for that reason, but if it ships, this is the only shape I consider sound.
  >
  > ```blink
  > pub opaque type Sha256State {
  >     h: List[Int]        // representation is private; impl may be a fixed C struct
  >     pending: Bytes
  >     total: Int
  > }
  >
  > pub const Sha256State.EMPTY = /* initial H0..H7, no pending bytes */
  > pub fn Sha256State.update(st: Sha256State, data: Bytes) -> Sha256State { /* ... */ }
  > pub fn Sha256State.finish(st: Sha256State) -> Sha256 { /* ... */ }
  >
  > // A pure fold, no mutation, no "already finished" state:
  > fn hash_chunks(chunks: List[Bytes]) -> Sha256 {
  >     Sha256State.finish(chunks.fold(Sha256State.EMPTY, fn(st, c) { Sha256State.update(st, c) }))
  > }
  > ```
  >
  > (If `const` cannot hold this value, `fn Sha256State.new() -> Sha256State` is the same thing.)
  >
  > Laws:
  > - **L1 Homomorphism.** `finish(update(update(EMPTY, a), b)) == Sha256.of(a.concat(b))`. Chunking never changes the result. This is the law lib/pkg's "cat all files | sha256sum" needs.
  > - **L2 Persistence.** `update` does not change `st`. After `let s1 = Sha256State.update(s, a)` and `let s2 = Sha256State.update(s, b)`, both are valid and independent. `finish` does not consume `st`; it may be called again and gives the same `Sha256`.
  >
  > Why value semantics and not a mutable `StringBuilder`-style hasher: Blink has no affine or linear types, so a mutable hasher has two states the type system cannot see ("open", "finished"). `update` after `finish` becomes a runtime error or a silent wrong answer, and `let h2 = h` aliases one buffer so two "independent" hashes corrupt each other. A persistent state has neither problem: every value is a valid state, and the functions stay pure (R2 holds). The cost is a copy of about 100 bytes of state per `update`; that is noise next to the compression work on any chunk worth streaming. Rust's `Sha256: Clone` with `update(&mut self)` relies on the borrow checker to make the mutable form safe; Blink does not have that, so it must not copy that API.
  >
  > Naming: `Sha256State`, never `Hasher`. `Hasher` is the Rust/Java name for the *non-crypto* `Hash` machinery, the exact confusion the ticket warns about.
  >
  > ---
  >
  > **plt-3 (OPPOSE): `crypto.hash("sha256", data) -> Bytes` as in 03_types.md:1337**
  >
  > Listed so the panel can vote it down explicitly.
  >
  > ```blink
  > fn compute_hash(data: Bytes) -> Bytes ! Crypto.Hash {
  >     crypto.hash("sha256", data)
  > }
  > ```
  >
  > - The output length depends on a runtime `Str`, so no type can state "32 bytes".
  > - An unknown name (`"sha265"`) is a run-time failure the signature does not show (it returns `Bytes`, not `Result`), so either it panics or returns a garbage value.
  > - Digests of different algorithms share one type and compare as `false` instead of failing to compile.
  > - It forces the `Crypto.Hash` effect on a pure function (plt-1 point 1).
  > This is Python's `hashlib.new(name)`. It is the right shape for a dynamic language and the wrong one for Blink.
  >
  > ---
  >
  > **plt-4 (NOTE, not for this vote): where the future crypto line sits**
  >
  > To keep plt-1 from painting the language into a corner: if the panel later adds HMAC or signatures, the MAC tag must be its own opaque type whose `Eq` is constant-time, distinct from `Sha256`. Key generation and nonces draw on `Rand` (already an effect). Signing with a key the program holds is still pure; only operations against keys outside the program (an OS keystore, an HSM) are candidates for a `Crypto.*` effect. plt-1 is compatible with every one of these paths. I do not propose any of it now.

- **DevOps/tooling:**

  > I judge each option by what the user sees: the import line, what the LSP completes after the dot, what `blink doc` shows, what an error says, and what lands in a lockfile or a log. Two repo facts drive my first choice:
  >
  > - **No inherent methods** (sections/03c_protocols.md:826, 4-1). Every instance method must come from a trait. A hasher with `.update()` / `.finish()` needs a trait; free functions do not.
  > - **A module name equal to an effect handle is a known trap.** `fs`, `io`, `net` already share a name with a std module, and the spec copes by keeping operations on the handle and *types* in the module (04_effects.md:1111). Free functions in such a module collide with handle methods; the repo has a recorded bug class for that ("stdlib free fn named like net/io/fs intrinsic"). `crypto` is a reserved handle (04_effects.md:300). A `std.crypto` module with a free fn `crypto.sha256(...)` puts a pure module call and an effect-handle call behind the same `crypto.` prefix. Hover, go-to-definition, completion and the "missing effect" diagnostic must then guess which one the user meant.
  >
  > ---
  >
  > **devops-1 (FIRST CHOICE): `std.digest` — opaque `Digest`, type-scoped one-shot, trait-based incremental, pure**
  >
  > **Surface**
  >
  > ```blink
  > import std.digest.{Digest, Sha256, DigestWriter, DigestError}
  >
  > fn cache_key(src: Str) -> Str {
  >     Sha256.of(Bytes.from_str(src)).to_hex()          // "ba7816bf..." (64 lowercase hex, = sha256sum)
  > }
  >
  > fn hash_package(files: List[Bytes]) -> Digest {
  >     let mut h = Sha256.new()
  >     for f in files {
  >         h.update(f)
  >     }
  >     h.finish()
  > }
  >
  > fn check_lock(entry: Str, actual: Digest) -> Result[Bool, DigestError] {
  >     let want = Digest.parse(entry)?                  // "sha256:<64 hex>"
  >     Ok(want == actual)
  > }
  >
  > fn show(d: Digest) ! IO {
  >     io.println("{d}")                                // "sha256:ba7816bf..."
  > }
  > ```
  >
  > **Declarations (spec shape, not implementation)**
  >
  > ```blink
  > @module("std.digest")
  >
  > pub opaque type Digest {
  >     algo: Str
  >     raw: Bytes
  > }
  >
  > pub type DigestError {
  >     Empty
  >     MissingPrefix
  >     UnknownAlgorithm { name: Str }
  >     BadLength { expected: Int, got: Int }
  >     BadHex { at: Int }
  > }
  >
  > pub trait DigestWriter {
  >     fn update(mut self, data: Bytes)
  >     fn finish(self) -> Digest
  > }
  >
  > pub opaque type Sha256 {
  >     state: Bytes
  > }
  >
  > pub fn Sha256.new() -> Sha256 { ... }
  > pub fn Sha256.of(data: Bytes) -> Digest { ... }
  > impl DigestWriter for Sha256 { ... }
  >
  > pub fn Digest.parse(s: Str) -> Result[Digest, DigestError] { ... }
  > // trait methods (via a small std trait, since Blink has no inherent methods):
  > //   d.to_hex() -> Str        bare lowercase hex, sha256sum-compatible
  > //   d.to_bytes() -> Bytes    raw 32 bytes
  > //   d.algorithm() -> Str     "sha256"
  > impl Display for Digest { ... }   // "sha256:<hex>" — the lockfile form (06_tooling.md:523)
  > impl Debug for Digest { ... }     // Digest(sha256:<hex>)
  > impl Eq for Digest { ... }
  > // NOT Hash: the decided rule says a digest must not implement Hash. Map keys use d.to_hex().
  > ```
  >
  > **Rules I ask the panel to fix**
  >
  > 1. **Pure.** `Sha256.of`, `update`, `finish` carry no effect. Hashing bytes in memory reads no clock, no file, no entropy. The compiler's own src/sha256.bl is pure, and its cache-key callers would otherwise all grow `! Crypto.Hash`. The example at 03_types.md:1337 (`crypto.hash("sha256", data) ! Crypto.Hash`) becomes a stale example: a chore rewrites it to `Sha256.of(data)`.
  > 2. **`Crypto.Hash` sub-effect:** remove it (keep `Sign`, `Encrypt`, `Decrypt` reserved; that is a separate question). A reserved effect with no operation is dead surface: the LSP completes `crypto.hash` with no signature behind it, and users who see `! Crypto.Hash` in the effect list will add it to pure code for no reason. If the panel keeps it, the spec must say what it gates, or it stays a trap.
  > 3. **SHA-256 only in v1.** Name the trait and the `Digest` type so that `Sha512`, `Blake3` can join later without a new API shape. No SHA-1 / MD5: shipping a broken hash in a tier-1-forever std (DECISIONS.md:313) means we carry it and its lint forever.
  > 5. **Docs cross-link.** The `Hash` trait doc (03_types.md:3559) gets one sentence: "`hash()` is seeded per process; for a stable digest use `std.digest`." That one line answers the most likely Stack Overflow question and gives the LSP hover something to show.
  >
  > **Diagnostics this gives**
  >
  > ```
  > error[E....]: lockfile entry for "json" has an invalid hash
  >   --> blink.lock:14:8
  >    |
  > 14 | hash = ""
  >    |        ^^ empty hash
  >    = help: run `blink update json` to write a new `sha256:<hex>` entry
  > ```
  >
  > Each `DigestError` variant maps to one sentence of that message. With `BadLength { expected: 64, got: 63 }` the tool can say "63 hex digits, expected 64", not "hash mismatch". Today the pipe through `sha256sum` gives an empty string and no error at all.
  >
  > **Tradeoffs (tooling view)**
  >
  > - (+) `std.digest` cannot collide with any effect handle. `digest.` is never an effect prefix, so completion after `Sha256.` and `d.` is exact and go-to-definition has one target.
  > - (+) The name says "digest", not "hash". A user who types `hash` in completion sees `Hash.hash() -> U64` and nothing else; the two concepts stay apart in search and in `blink doc`.
  > - (+) `Display` gives the self-describing `sha256:` form. A bare 64-hex string in a log does not tell the reader which algorithm made it; `to_hex()` is there when a tool needs the bare form (cache keys, sha256sum output).
  > - (−) One new trait (`DigestWriter`) for one impl. The no-inherent-methods rule forces it; free fns `sha256_update(mut h, data)` are the only alternative, and they break the method-call style that completion depends on.
  > - (−) `Display` (prefixed) and `to_hex()` (bare) differ. That is one decision point for a user. I accept it because the lockfile, `blink doc` and log output all want the prefixed form, and the docs state it in one line.
  > - (−) No file streaming. fs has no file handles in v1 (04_effects.md:1113), so `Sha256.of(fs.read_bytes(path)?)` reads the whole file. That is fine for source packages. A path-taking `Sha256.of_file` waits for file handles; adding it now would bake in a whole-file read behind a name that suggests streaming.
  >
  > **Cross-language note**
  >
  > Ruby `Digest::SHA256` and D `std.digest.sha` use the "digest" name for exactly this reason. Go `crypto/sha256` works because Go has no effect handle named `crypto`. Rust's `sha2` crate uses a `Digest` trait with `update` / `finalize`, the same split as devops-1. Python `hashlib` names it "hash" and the Python docs then spend a paragraph telling users it is not `hash()`.
  >
  > ---
  >
  > **devops-2: `std.crypto` module, free functions, pure**
  >
  > ```blink
  > import std.crypto.{Digest}
  >
  > fn key(src: Str) -> Str {
  >     crypto.sha256(Bytes.from_str(src)).to_hex()
  > }
  > ```
  >
  > Same `Digest` type and parse rules as devops-1, but one-shot free fns `crypto.sha256(data)` and an incremental `crypto.sha256_new()` / `crypto.sha256_update(mut h, data)` / `crypto.sha256_finish(h)`.
  >
  > - (+) Familiar to Go and Node users.
  > - (−) `crypto.` is the reserved handle of the `Crypto` effect (04_effects.md:300). `crypto.sha256(...)` (pure module fn) and `crypto.sign(...)` (effect op) look alike at the call site but follow different rules: one needs `import std.crypto`, the other needs `! Crypto.Sign`. The "missing effect" and "unknown function" errors must each guess which one the user meant. This repeats the net/io/fs free-fn collision we already had to fix.
  > - (−) Free-fn incremental API does not show up after `h.` in completion.
  >
  > I oppose this unless the panel also moves the effect handle off `crypto`.
  >
  > ---
  >
  > **devops-3: minimal — promote src/sha256.bl as `std.sha256`, hex Str only**
  >
  > ```blink
  > import std.sha256
  >
  > fn key(src: Str) -> Str {
  >     sha256.hex(Bytes.from_str(src))
  > }
  > ```
  >
  > One function, `sha256.hex(data: Bytes) -> Str`, pure. Lockfile code builds `"sha256:" + sha256.hex(data)` by hand.
  >
  > - (+) Smallest surface; the compiler and lib/pkg can switch at once; zero new traits.
  > - (−) Tier-1 forever: a second algorithm later means a second module (`std.sha512`) or a breaking change.
  >
  > This is my fallback if the panel rejects a new trait and type. It is better than nothing; it is not what I would want to support in an LSP for ten years.
  >
  > ---
  >
  > **Ranking**
  >
  > devops-1 > devops-3 > devops-2. On the effect question I vote pure in every option, and remove `Crypto.Hash`.

- **AI/ML:**

  > Lens: can a model write correct SHA-256 code from the spec alone, on the first try, with few decision points and few tokens? The main risks I see are name collisions, not the algorithm. Blink already has three things that a model will confuse with a digest API: the `Hash` trait (`x.hash() -> U64`), the reserved `crypto` effect handle (`crypto.hash(...)`, 04_effects.md:300), and the example at 03_types.md:1337 (`crypto.hash("sha256", data) ! Crypto.Hash`). The module name and call shape must keep clear of all three.
  >
  > ---
  >
  > **aiml-1 (FIRST CHOICE): `std.digest`, pure functions, Bytes in, Bytes out, plus one incremental type**
  >
  > **Surface**
  >
  > ```blink
  > // lib/std/digest.bl
  > pub fn sha256(data: Bytes) -> Bytes      // 32 bytes
  >
  > pub type Sha256 { ... }                  // opaque incremental state
  > // Sha256.new() -> Sha256
  > // fn update(mut self, data: Bytes)
  > // fn finish(self) -> Bytes              // 32 bytes; receiver stays usable
  > ```
  >
  > **Use**
  >
  > ```blink
  > import std.digest
  >
  > fn cache_key(src: Str) -> Str {
  >     digest.sha256(Bytes.from_str(src)).to_hex()
  > }
  >
  > fn tree_hash(paths: List[Str]) -> Result[Str, FsError] ! FS.Read {
  >     let mut h = digest.Sha256.new()
  >     for p in paths {
  >         h.update(Bytes.from_str(fs.read(p)?))
  >     }
  >     Ok("sha256:" + h.finish().to_hex())
  > }
  > ```
  >
  > `tree_hash` is what lib/pkg needs (F9): the same digest as `cat sorted files | sha256sum`, with no shell-out and no whole-tree buffer.
  >
  > Repo fact: the spec `fs` surface has `fs.read(path) -> Result[Str, FsError]` only (04_effects.md:1005); there is no `fs.read_bytes`, although the 03_types.md:1333 example calls one. For .bl sources (UTF-8) `Bytes.from_str(fs.read(p)?)` is exact. Hashing a non-UTF-8 file has no spec path today; that is an fs gap, not a digest gap, and the 03_types.md:1333 example should be fixed in the same chore as :1337.
  >
  > **Decisions in this proposal, and why**
  >
  > 1. **Module `std.digest`, qualifier `digest`.**
  >    - `std.crypto` gives the qualifier `crypto`, which is the reserved effect handle. `crypto.sha256(x)` reads as an effect operation. A model will then add `! Crypto` or `! Crypto.Hash` to the signature, or write `crypto.hash("sha256", x)` from the 03_types.md:1337 example. Each of these is a compile error or a silent wrong effect row. Two meanings for one identifier is the worst case for learnability.
  >    - `std.hash` gives `hash`, which is the `Hash` trait method name. `hash.sha256(x)` next to `x.hash()` invites the model to think the two are related (for example, to call `x.hash()` and hex it for a lockfile). The brief says the naming must avoid this confusion; `hash` fails that test.
  >    - `std.sha256` puts the algorithm in the module name, so SHA-512 or BLAKE3 later means a new module per algorithm and a new import per algorithm. That is more surface for the same concept.
  >    - `digest` is the word Python (`hexdigest`), Ruby (`Digest::SHA256`), Rust (`digest` crate, `sha2::Digest`) and Go (`Sum`/digest) use for this output. It has no other meaning in Blink. It names the concern, so later algorithms go in the same module with the same shape: `digest.sha512(...)`, `digest.Sha512`.
  >
  > 2. **Pure, no effect.** SHA-256 is a total, deterministic function of its input. A model reasons about effects from "does this touch the world?"; SHA-256 does not, so a model will write it without an effect row. Requiring `! Crypto.Hash` makes every caller up the chain add it (cache keys, lockfile checks, test helpers), which is token cost at every signature and a frequent miss. There is also no handler story: mocking a digest has no use, and a handler that changes it breaks the sha256sum equality that is already decided. `Crypto` stays reserved as decided (for Sign/Encrypt/Decrypt, where keys and randomness make it effectful); this proposal only says SHA-256 does not use `Crypto.Hash`.
  >    - Required follow-up chore (not a spec change of the effect table): rewrite the 03_types.md:1337 example to `digest.sha256(data)` with no effect row. As long as that example stays, models trained on the spec will copy `crypto.hash("sha256", data)`. Also add one line under the `Crypto` row (04_effects.md:300) that says plain digests are pure functions in `std.digest`.
  >
  > 3. **`Bytes` in, `Bytes` out; hex via the existing `.to_hex()`.**
  >    - One input type and one output type is one decision point fewer than a Str/Bytes or hex/raw matrix (`sha256_hex`, `sha256_bytes_hex`, `sha256_str` ... as in src/sha256.bl, F7). A model then composes from parts it already knows: `Bytes.from_str` (F13) and `.to_hex()` (F13). Both are in the spec and lowercase hex, which matches sha256sum (decided).
  >    - Common case token cost: `digest.sha256(Bytes.from_str(s)).to_hex()`. About ten more tokens than a `sha256_hex(s)` helper, but zero new names to learn and no wrong choice to make.
  >    - No `Digest` newtype. A newtype adds a type, a `.to_bytes()`, and a question at every use ("do I unwrap it?"). Its only gain is a distinct type for comparison, which nothing in the brief needs. Bytes `==` is fine for integrity checks (lockfile, cache). Constant-time compare is a MAC problem; it belongs with HMAC if HMAC ever ships.
  >
  > 4. **One incremental type, `Sha256`, with `new` / `update(mut self)` / `finish(self)`.**
  >    - The shape is the same as `StringBuilder` (F18) and the `mut self` rule (03_types.md:661), so a model already has the pattern from the spec. It is also the shape in Python `hashlib`, Go `hash.Hash`, Rust `Digest`, Node `createHash().update().digest()`; training data and spec agree.
  >    - It is needed: fs has no file handles in v1 (decided), and lib/pkg hashes many files as one stream (F9). Without it, the only path is to `concat` every file into one Bytes.
  >    - `finish(self)` does not consume or reset: Blink values copy on bind (03c_protocols.md:42), so there is no use-after-finish trap to document. `digest.sha256(b)` is defined as `Sha256.new()` + `update(b)` + `finish()`; the spec says so in one sentence.
  >    - No `sha256_file(path)`. It mixes `FS.Read` into a pure module and duplicates the loop above. YAGNI.
  >
  > 5. **Algorithms: SHA-256 only now.** The ticket has one user need. The module name and the fn/type pair leave a fixed slot for more: `digest.<algo>(Bytes) -> Bytes` and `digest.<Algo>`. A model that knows `sha256` will guess `sha512` correctly the day it ships. No algorithm-by-string (`hash("sha256", ...)`): a typo becomes a runtime error, and the return length depends on a string.
  >
  > **Tradeoffs (aiml)**
  >
  > - (+) Zero overlap with `Hash`, `.hash()`, `crypto`, `Crypto.Hash`. One import, one fn, one type.
  > - (+) Every piece of the common call is already in the spec (`Bytes.from_str`, `.to_hex()`, `mut self`).
  > - (+) Lockfile shape is plain string concat: `"sha256:" + d.to_hex()`.
  > - (-) Str callers write `Bytes.from_str(...)`. Models may first try `digest.sha256("abc")`; the type error is E-mismatched Str/Bytes, and the fix is mechanical. The spec example must show the Str form so it is learned from the doc.
  > - (-) No hex decode (`Bytes.from_hex`) exists (F13), so comparing to a stored `sha256:<hex>` is done as hex Str compare. That works; a decoder is a separate Bytes question.
  >
  > **Cross-language**
  >
  > Python `hashlib.sha256(b).hexdigest()`; Go `sha256.Sum256(b)` + `hex.EncodeToString`; Rust `Sha256::digest(b)` + `hex::encode`; Node `createHash("sha256").update(b).digest("hex")`. Blink's `digest.sha256(b).to_hex()` is the shortest of these that stays fully typed.
  >
  > ---
  >
  > **aiml-2 (fallback): same as aiml-1 but add `sha256_hex(s: Str) -> Str`**
  >
  > If the panel weights the 90% case (hash a Str, get hex) above "one way to do it":
  >
  > ```blink
  > import std.digest
  >
  > fn key(src: Str) -> Str {
  >     digest.sha256_hex(src)
  > }
  > ```
  >
  > - (+) Shortest common call; matches the compiler's own `sha256_hex` (F7), so src/ could migrate to it with no change at call sites.
  > - (-) Two ways to hash a Str; the model must pick. For every future algorithm the pair doubles (`sha512`, `sha512_hex`). I would accept this only with a rule that every algorithm gets exactly `<algo>` and `<algo>_hex` and nothing more, so the pattern stays guessable.
  >
  > ---
  >
  > **Positions on other likely options**
  >
  > - **Against `std.crypto`** for this: collision with the reserved `crypto` handle (see 1). If the panel wants a crypto module later for Sign/Encrypt, it should be the effect handle, not a module.
  > - **Against `! Crypto.Hash`** on SHA-256: effect row with no world contact, no useful handler, high miss rate in generated signatures.
  > - **Against a `Digest` newtype** now: extra type and unwrap step for no current need.
  > - **Against algorithm-by-string**: runtime failure for what is a compile-time choice.
  > - **"Do nothing"** is not an option: lib/pkg ships an integrity check that passes on empty hashes (F11).

- **Minimalism:**

  > My frame: the need is real and foundational. Content addressing (lockfile `sha256:<hex>`, build cache keys, package integrity) is something the toolchain itself needs today, and a user cannot write it safely without a library. So "reject" is wrong here. But the need is exactly one algorithm, one-shot, over bytes already in memory. Ship that and nothing else. Every other piece in the ticket (incremental hasher, digest newtype, more algorithms, Str overload, hex-returning twin, effect row) has no caller today.
  >
  > **min-1 (FIRST CHOICE): `std.sha256`, one pure function, returns Bytes**
  >
  > ```blink
  > import std.sha256
  >
  > fn lock_entry(src: Bytes) -> Str {
  >     "sha256:{sha256.sum(src).to_hex()}"
  > }
  >
  > fn same_text(a: Str, b: Str) -> Bool {
  >     sha256.sum(Bytes.from_str(a)) == sha256.sum(Bytes.from_str(b))
  > }
  > ```
  >
  > Spec surface, in full:
  >
  > | Item | Signature | Meaning |
  > |---|---|---|
  > | `sha256.sum` | `fn(data: Bytes) -> Bytes` | SHA-256 (FIPS 180-4) digest of `data`; the result has length 32 |
  >
  > Decisions inside min-1, each the smallest choice:
  >
  > 1. **Module `std.sha256`, not `std.crypto` or `std.hash`.**
  >    - `std.hash` collides in the reader's head with the `Hash` trait, which is seeded, U64 and per-process (03_types.md:3559-3590). The ticket itself names this risk.
  >    - `std.crypto` collides in the compiler's head: `crypto` is already the reserved handle of the `Crypto` effect (04_effects.md:300). `import std.crypto` then `crypto.sha256(x)` puts a module qualifier and an effect handle on the same identifier. This repo has hit that class of bug before (stdlib free fn vs net/io/fs intrinsic). A name we must special-case is not minimal.
  >    - `std.crypto` also promises a family (HMAC, signatures, AEAD) we do not intend to ship. An honest name for one algorithm is the algorithm.
  >    - Fits F16: one module per concern, named for the concern (`semver`, `json`, `toml`).
  > 2. **Pure, no effect row.** SHA-256 of a byte buffer is a total, deterministic function. It reads no ambient state, touches no capability, and a handler cannot give a different correct answer. An effect row on it would only force `! Crypto.Hash` up every caller chain (lib/pkg, the compiler cache, user build tools) for zero safety gain, and would make it unusable in pure code such as a `@derive`-style cache key. The compiler's own src/sha256.bl is already pure (F6). `Crypto` stays reserved for the operations that need key material or entropy (sign, encrypt, decrypt). I do not propose to delete `Crypto.Hash` here (reserved, out of scope), but its example at 03_types.md:1337 should stop being the model for SHA-256; see min-1 follow-up below.
  > 3. **Bytes in, Bytes out.** One input type: a Str caller writes `Bytes.from_str(s)` (one call, and it makes the UTF-8 encoding step visible, which is the step people get wrong across languages). One output type: hex is `.to_hex()`, which already exists. A `sum_hex` twin or a `Str` overload doubles the surface to save six tokens.
  > 4. **No `Digest` newtype.** A newtype earns its place when it stops a real mix-up. The one real hazard of a raw digest is timing-unsafe compare of a MAC tag. SHA-256 alone is not a MAC, and there is no HMAC in this proposal, so the newtype guards nothing. If HMAC ever ships, that is the time to add a tag type with constant-time `==`. Adding a newtype now also forces a choice of its trait set (Eq? Hash? Display? Debug? to_hex?), each a decision point with no caller.
  > 5. **No incremental hasher.** There is no streaming source to feed one: fs has no file handles in v1 (04_effects.md:1113) and there is no Reader trait (F19). Every current caller has the full input in memory (src/sha256.bl:62 reads the whole file; lib/pkg concatenates sorted files). A `Sha256` state type with `update/finish` adds a mutable type, a use-after-finish rule, and a second way to compute the same thing. Add it in the same change that adds file handles, where it has a caller.
  > 6. **SHA-256 only.** SHA-1 and MD5 are broken and exist only for legacy interop; shipping them in tier-1-forever std (DECISIONS.md:313) means supporting them forever. SHA-512 and BLAKE3 have no caller in the toolchain or the lockfile format. Each later algorithm is a sibling module (`std.blake3`) with the same one-function shape, so min-1 does not block them.
  > 7. **Name `sum`.** It matches `sha256sum`, the tool whose output the result must equal, and Go's `sha256.Sum256`. Reads as `sha256.sum(data)`.
  >
  > Follow-up spec edit (same change): rewrite the 03_types.md:1337 example. Today it shows `crypto.hash("sha256", data)` under `! Crypto.Hash`, which is algorithm-by-string (a typo is a runtime failure) and contradicts point 2. Replace with a Bytes example that does not touch hashing, or with `sha256.sum(data)` and no row.
  >
  > Tradeoffs (min's view):
  > - Pro: one name, one signature, zero new types, zero new effects, zero new diagnostics. An LLM or a newcomer has no choice to get wrong.
  > - Pro: every future addition (hasher, HMAC, BLAKE3) is purely additive; nothing in min-1 must later be deprecated.
  > - Con: hashing a 2 GB file needs 2 GB of memory. Accepted until file handles exist; no caller today hashes a file it cannot hold.
  > - Con: `Bytes == Bytes` is not constant-time. Harmless for content addressing; only matters for secret comparisons, which need HMAC, which is not here.
  >
  > Cross-language: Go `crypto/sha256.Sum256(data) [32]byte` is the model, a package named for the algorithm with a one-shot function; the streaming `hash.Hash` came with `io.Writer`, which Go had from day one and Blink does not. Python `hashlib.sha256(b).digest()` takes bytes only, not str, for the encoding reason in point 3. Lua and Scheme cores ship no hashing at all; that is the floor, and we sit one function above it because the toolchain needs it.
  >
  > **min-2 (acceptable fallback): min-1 plus `sum_hex`**
  >
  > Same as min-1, plus `sha256.sum_hex(data: Bytes) -> Str` (lowercase, 64 chars).
  >
  > ```blink
  > import std.sha256
  >
  > fn lock_entry(src: Bytes) -> Str {
  >     "sha256:{sha256.sum_hex(src)}"
  > }
  > ```
  >
  > Only argument for it: most call sites (lockfile, cache keys, every call in F8/F9) want hex, so the hex form is the 90% path. Against: two spellings of one result, and a reader must learn both. I prefer min-1 and would vote min-2 over anything that adds a hasher type, a newtype, or a `Crypto.Hash` row.
  >
  > **min-3 (reject in std, vendor into lib/pkg): not my choice, listed for completeness**
  >
  > **Positions on likely proposals from other seats (pre-debate)**
  >
  > - `std.crypto` with many algorithms: oppose (handle collision with `crypto`, tier-1-forever cost per algorithm).
  > - `crypto.hash("sha256", data)` by string name: oppose (runtime failure for a typo; the type system should name the algorithm).
  > - `! Crypto.Hash` on SHA-256: oppose (pure function; row cost on every caller; no handler can vary it).
  > - Incremental `Sha256` hasher now: oppose until a streaming input exists.
  > - `Digest` newtype: oppose until HMAC exists.

#### Phase B — Debate highlights

One round. All six seats said they were ready to vote. Below are each seat's text on the return type (V2) and on the incremental hasher (V4), verbatim.

- **Systems (V2):**

  > **V2. Return type — move from R2 to R3 (plt-1 opaque `Sha256` + `Digest` trait); R1 second; oppose R4**
  >
  > Concession: my R2 (transparent newtype) loses to plt's point. A transparent single-payload type lets any module
  > `pub opaque type` (02 §2.12.2, "changes visibility only", value semantics unchanged) gives the invariant at the
  > same cost: in C both are the 32-byte `Bytes` buffer and nothing else. R2 has no advantage left, so I drop it.
  >
  > - R3 cost: identical to R1 at run time. `to_bytes` returning a fresh 32-byte buffer (plt R5) is a 32-byte copy;
  >   since `Bytes` is a value, a copy is what binding does anyway. No objection.
  > - `Sha256.from_hex` (strict lowercase, 64 chars, `None` otherwise): support. It is the cheap, total way to turn a
  >   lockfile string into a value and makes "" an error by construction.
  > - R1 (plain `Bytes`): acceptable second. Same machine code; loses only the type-level invariant. I prefer R3
  >   because the invariant is free.
  > - R4 (devops `Digest { algo: Str, raw: Bytes }`): oppose. It moves the algorithm from the type to a run-time
  >   string: every digest carries an extra `Str`, every `==` compares two strings before the bytes, and the digest
  >   length is no longer static. It is the `crypto.hash("sha256", ...)` design that all six seats rejected, moved one
  >   layer down. The `"sha256:<hex>"` parse it offers is a lockfile-format concern; lib/pkg strips the prefix and
  >   calls `Sha256.from_hex`. `DigestError` with five variants for one algorithm is surface with no second caller.
  > - Variation: state that `==` on a digest is not constant-time. Support (sys, plt R6).

- **Systems (V4):**

  > **V4. Incremental hasher — I1 with plt-2's laws (merge)**
  >
  > Merge I state:
  > - An opaque value type with `new()`, `update(mut self, data: Bytes)`, `finish(self) -> <digest type>`.
  > - It is a value, not a shared cell (03_types.md:3794 list unchanged).
  > - `finish` does not consume or reset the receiver; calling it twice gives the same result (web-2, aiml-1, plt L2).
  > - Law L1 (homomorphism): `new()` + `update(a)` + `update(b)` + `finish()` equals the one-shot of `a.concat(b)`.
  > - Name: `Sha256` if the digest is `Bytes` (R1); `Sha256State` if the digest type is `Sha256` (R3). Never `Hasher`.
  >
  > Concessions: verb `update`, not `write` (four seats; Python/Node/Rust/OpenSSL). Drop my `write_str`: the
  > `Bytes.from_str` copy is a memcpy, far cheaper than the 64-round compression over the same bytes, so it buys
  > under a few percent and costs a second feed method.
  >
  > Reply to min-1 / web (defer the hasher): the caller exists today. lib/pkg hashes the concatenation of every
  > sorted `.bl` file (F9). Without a hasher the code is web-1's own example, `all = all.concat(...)` in a loop.
  > `Bytes` is a value, so each `concat` copies the whole prefix: O(n^2) bytes moved for n files, plus the whole
  > tree held in memory. With the hasher it is O(total) work and 104 bytes of state. Deferring until fs handles
  > exist means shipping the quadratic version into lib/pkg now. The type costs one opaque struct and one trait.

- **Web/Scripting (V2):**

  > **V2. Return type — R1 plain `Bytes`. Ranking: R1 > R3 > R2 > R4**
  >
  > - **R1.** Two types a user already knows (`Bytes` in, `Bytes` out) and `.to_hex()` they already know. Python
  >   `.digest()`/`.hexdigest()` and Node `Buffer`/`'hex'` users map onto it at once.
  >   never returns empty Bytes under R1; it always returns 32 bytes. The bug was a shell-out that produced `""` and a
  >   lockfile check that accepted it. The fix sits where lockfile text is read: lib/pkg must reject a hash that is not
  >   `sha256:` plus 64 lowercase hex chars. That is a ten-line check in lib/pkg. It does not need a new type in a
  >   tier-1-forever std.
  > - **R3 is the honest version of a typed digest**, if the panel wants one: opaque, so the 32-byte invariant holds.
  >   It costs a type, a trait (`Digest`), `from_hex`, Display, and an import of two names before you can call
  >   `.to_hex()`. That is real learning cost for a guard against a mix-up I have not seen in review.
  > - **R2 gets the cost without the benefit.** A transparent newtype means any module can write
  >   `Sha256Digest(Bytes.new())`, so the 32-byte invariant is not enforced, yet the user still unwraps and imports.
  > - **R4 has a concrete trap.** Display prints `sha256:<hex>` but `to_hex()` prints bare hex. The most natural
  >   line a user writes for a lockfile, `"sha256:{d}"`, then gives `sha256:sha256:ba78...`. And `Digest.parse` plus a
  >   five-variant `DigestError` is a lockfile parser. It belongs in lib/pkg, not std.
  > - **Variation (constant-time):** yes, state in one sentence that `==` on a digest is ordinary, not constant-time.
  >   It costs nothing and stops a reader assuming otherwise.

- **Web/Scripting (V4):**

  > **V4. Incremental hasher — I1, `update` / `finish`, ship it now**
  >
  > I move from "optional" to "ship". Two repo facts changed my mind:
  >
  > 1. **The lib/pkg caller is a loop over files**, and without a hasher the only path is
  >    `all = all.concat(...)` per file. That copies the growing buffer every time: quadratic in the number of
  >    files. sys-2 says this and it is true. The first thing a user writes for "hash my directory" is that loop,
  >    and it is slow in a way they will not see until a big tree.
  > 2. **The aliasing objection (plt-2) is already answered by the language.** 03c_protocols.md:42 says values copy
  >    on bind and there is no `&mut self`. A hasher with `update(mut self, data)` is the same kind of thing as
  >    `List.push` or `StringBuilder.write` (03_types.md:661): `let h2 = h` gives two independent states. No new rule.
  >
  > Shape I vote for (aiml-1 / web-2, with devops-1's trait since Blink has no inherent methods):
  >
  > ```blink
  > import std.digest
  >
  > fn tree_hash(paths: List[Str]) -> Result[Str, FsError] ! FS.Read {
  >     let mut h = digest.Sha256.new()
  >     for p in paths.sort() {
  >         h.update(Bytes.from_str(fs.read(p)?))
  >     }
  >     Ok("sha256:{h.finish().to_hex()}")
  > }
  > ```
  >
  > - Verb **`update`**, not `write` (sys-1). To a JS/Python dev `write` means I/O; `update` is the word in
  >   Python `hashlib`, Node `createHash`, OpenSSL and Rust `Digest`. `StringBuilder.write` writes text, which is
  >   not what a hasher does.
  > - **No `write_str`/`update_str`.** One feed method. The `Bytes.from_str` copy is small, and one method is one
  >   less thing to choose.
  > - **`finish(self)` does not reset and may be called again.** Node's "Digest already called" error is a known
  >   trap; do not copy it. Spec law: `digest.sha256(b) == new + update(b) + finish`.
  > - **Name the trait for the action, not `Hasher`** (plt is right about `Hasher`). devops's `DigestWriter` is fine
  >   by me; so is any name without "Hash" in it.
  >
  > **I oppose plt-2 (persistent `Sha256State`).** `st = Sha256State.update(st, c)` is a functional idiom most
  > web/scripting devs have never used. The bug it invites is the one I see most in code review of immutable APIs:
  > the user writes `Sha256State.update(st, c)` and drops the result, and gets the hash of nothing, with no error. The
  > mutable form cannot fail that way. The soundness reason for plt-2 (aliasing) does not apply, see point 2 above.
  >
  > If the panel picks I0 (min), that is additive later and I will not call it a disaster. But "no streaming source"
  > undercounts: many files in a loop and `io.read_bytes(n)` on stdin are both streaming inputs today.

- **PLT (V2):**

  > **V2 Return type: **R3 (opaque per-algorithm type)**, trimmed**
  >
  > 1. **Invariant.** "Always 32 bytes" is a fact about the value. With R1 it is a comment; any `Bytes` is a "digest". With R2 (sys, transparent newtype) any module can write `Sha256Digest(Bytes.new())`; the zero-cost argument is the same for `opaque` (§2.12.2: "opaque changes visibility only"), so R2 pays the same cost as R3 and gets no invariant. If the panel wants a wrapper, it must be opaque.
  > 2. **Algorithm separation.** With R1, a later SHA-512 digest and a SHA-256 digest are both `Bytes`, and `==` between them is a well-typed `false`. With R3 it is a compile error. This is the plt-3 argument against algorithm-by-string, applied to the result type. Every seat accepted it for the input; it holds for the output too.
  > 3. **Future MAC tag.** min and web both say "add a tag type with constant-time `==` when HMAC ships." That plan means a MAC tag type distinct from `Bytes`, so at that point raw `Bytes` digests and typed MAC tags would sit next to each other in std. R3 now makes the family uniform.
  >
  > Against R4 (devops, one `Digest` with an `algo: Str` field): this moves the algorithm back to a run-time value. `sha256_digest == sha512_digest` type-checks and returns `false`, which is the plt-3 defect again in a smaller form. What R4 gets right is parsing `sha256:<hex>` with typed errors (`Empty`, `BadLength`, ...). That belongs to the lockfile reader, which can be written on top of R3 in a few lines: check the prefix, then `Sha256.from_hex`. I would not put `DigestError` in std for one consumer.
  >
  > Trim, answering min's "a newtype forces trait-set choices with no caller": `Sha256` implements `Eq`, `Clone`, `Debug`, plus the `Digest` trait (`to_bytes`, `to_hex`). **No `Display`** in this decision: devops wants it prefixed and others would expect bare hex, and either choice breaks a round-trip law with `from_hex` unless a second parse fn is added. Callers write `d.to_hex()`. Keep `Sha256.from_hex(Str) -> Option[Sha256]` (strict: 64 lowercase hex chars), with the law `Sha256.from_hex(d.to_hex()) == Some(d)` and its converse. That law makes a hex-`Str` compare and a typed compare agree, which is the property a lockfile check depends on.
  >
  > If the panel picks R1, I can live with it: it is sound, only less precise. I oppose R2 (cost of R3 without the benefit) more than R1.
  >
  > **Variation, equality:** yes, state in one sentence that `==` on a digest is not constant-time (sys, plt). It costs nothing and keeps a future reader from using it for MAC checks.

- **PLT (V4):**

  > **V4 Incremental: **I1, merged with the plt-2 laws**
  >
  > Shape (method names per V2 result; with R3):
  >
  > ```blink
  > import std.digest.{Sha256, Sha256State, DigestState}
  >
  > fn tree_hash(texts: List[Str]) -> Sha256 {
  >     let mut st = Sha256State.new()
  >     for t in texts {
  >         st.update(Bytes.from_str(t))
  >     }
  >     st.finish()
  > }
  > ```
  >
  > - `fn update(mut self, data: Bytes)`, `fn finish(self) -> Sha256`. The methods come from a trait (no inherent methods); devops's `DigestWriter` or my `DigestState` both work. **Never `Hasher`** (all seats agree).
  > - Laws for the spec text: (L1) `finish` after `update(a)` then `update(b)` equals `Sha256.of(a.concat(b))`, so chunking never changes the result; (L2) `finish` does not reset and may be called again with the same result (web-2, aiml-1). Copy independence needs no law, it follows from value semantics.
  > - The one-shot is defined by L1 with one chunk: `Sha256.of(b)` equals `new` + `update(b)` + `finish` (web-2).
  > - It has a caller: lib/pkg hashes many sorted files as one stream (F9), and `io.read_bytes(n)` is a chunked source. Without I1, the lib/pkg fold over `concat` copies O(n²) bytes (sys-2). To min: this is not a second, divergent path. L1 makes the two paths provably equal, and the spec states that as a law.
  > - Verb: `update` over `write`. `write` invites a later `Writer` trait to absorb the hasher with a different contract (errors, short writes); `update` is total and says so. Weak preference.
  > - Against sys's `write_str`: one feed method. The copy in `Bytes.from_str` is for the implementation to remove, not something the spec needs to add a name for.

- **DevOps/tooling (V2):**

  > **V2 Return type: R3 (plt), with the value type named `Sha256Digest`**
  >
  > I drop R4 (my own). plt is right: one nominal type per algorithm makes `UnknownAlgorithm` and `MissingPrefix` unreachable at the type level, and the `sha256:` prefix is a lockfile concern that lib/pkg owns. I also accept `Option` over my `Result[_, DigestError]`. lib/pkg can say "63 hex digits, expected 64" by checking the length itself before the parse, so a std error type for one caller is not worth it.
  >
  > R2 (sys, transparent newtype): plt's point stands. A transparent newtype lets any module write `Sha256Digest(Bytes.new())`, which breaks the 32-byte invariant that `from_hex` and `to_hex` rely on. Opaque costs nothing more at runtime.
  >
  > **Naming (the part the ballot must fix).** plt-1 calls the *digest* `Sha256`. sys-1, aiml-1 and web-2 call the *hasher* `Sha256`. If both shapes reach the ballot under one name, `Sha256` means two different things across the proposals, and completion after `Sha256.` lists a different set in each. I back sys's names: hasher `Sha256`, value `Sha256Digest`. This matches Rust `sha2::Sha256` and Go `sha256.New()`, where the algorithm name is the hasher. It also makes type errors self-explanatory: `expected Sha256Digest, found Str` needs no doc lookup, while `expected Sha256, found Str` leaves the reader to guess whether a hasher was meant. plt's trait `Digest` keeps its name; the trait describes the value.

- **DevOps/tooling (V4):**

  > **V4 Incremental: I1, verb `update`, no `write_str`**
  >
  > There is a caller today. lib/pkg hashes every `.bl` file in a package as one stream (F9). Without a hasher, the user's only path is `concat` in a loop, which is web-1's own lib/pkg example (`all = all.concat(...)`). That is O(n²) copying, as sys notes. min-1 drops a real caller.
  >
  > I prefer I1 over plt-2's persistent state, and the repo answers plt's soundness concern. 03c_protocols.md:42 says "values are copied on bind (§3.6, there is no `&mut self`) ... mutable state aliased through a value type, which the language forbids everywhere else". So `let h2 = h` copies the state, and two hashers cannot share a buffer. If `finish(self)` neither resets nor consumes (sys, aiml, web-2 all say so), there is no "finished" state either. Every `Sha256` value is a valid state, as in I2. The difference is the tooling surface. I2 is `Sha256State.update(st, c)`, a type-scoped call, so nothing shows after `st.` in completion, and every call repeats the type name. I1 is `h.update(c)`, the pattern users know from `StringBuilder` and every other language. Spec law (web-2): `Sha256.of(b) == { let mut h = Sha256.new(); h.update(b); h.finish() }`.
  >
  > Verb `update`, not `write` (web: `write` reads as I/O, and Python, Node, OpenSSL and Rust `Digest` all say `update`). I drop sys's `write_str`: it is one more name for a one-copy saving that the runtime can make later without an API change.
  >
  > Methods need a trait (no inherent methods). Name it for what it does, and never `Hasher`. My `DigestWriter` from devops-1 is fine; I do not care about the exact name as long as it is not `Hasher`.

- **AI/ML (V2):**

  > **V2. Return type: R3-shaped opaque type, named `Sha256Digest` (sys-1 name, plt-1 rules)**
  >
  > I drop plain `Bytes` (my aiml-1). Reasons:
  > - **Token cost is zero for the common path.** `.to_hex()` is the call a model writes on both `Bytes` and a digest type. `x.to_hex()` reads the same, so the newtype adds no tokens and no new name to the 90% case.
  > - **Opaque, not transparent (against R2).** A transparent `Sha256Digest(Bytes)` lets anyone build `Sha256Digest(Bytes.new())`. A model that sees the payload form will write it to "construct a digest from stored bytes", and it then breaks the 32-byte rule.
  > - **Name the digest `Sha256Digest`, not `Sha256` (against plt-1's naming).** Every prior a model has (Rust `Sha256::new()`, Python `hashlib.sha256()`, Node `createHash`, Java `MessageDigest`) uses the algorithm name for the hasher. If `Sha256` is the output type, `Sha256.new()` fails and models write it anyway. So `Sha256` = hasher and the one-shot constructor, `Sha256Digest` = output. This is also how Rust `sha2` splits it (`Sha256` hasher, `Sha256::digest(b)` one-shot).
  > - **Against R4 (devops-1 algorithm-tagged `Digest` with prefixed `Display`).** `Display` that prints `sha256:<hex>` while `to_hex()` prints bare hex is a decision point with a silent wrong answer: a model that writes the lockfile line as `"sha256:{d}"` gets `sha256:sha256:...`, and one that writes `"{d}"` for a cache key gets a prefix it did not want. Neither fails to compile. I would ship no `Display` at all, so `"{d}"` is a compile error that points to `to_hex()`. The lockfile prefix parse (`"sha256:"` + `from_hex`) belongs in lib/pkg, which owns that format; `DigestError` with five variants for one caller is surface the std does not need.
  > - Not constant-time `==`: state it in one sentence (sys, plt R6). Agree with plt-4 that a MAC tag is a separate type later.

- **AI/ML (V4):**

  > **V4. Incremental hasher: I1 mutable, verb `update`, no `write_str`**
  >
  > - Need: lib/pkg hashes a sorted list of files as one stream (F9). Without a hasher the spec teaches `all = all.concat(...)` in a loop (web-1's own lib/pkg example), which is quadratic. Models copy spec examples; the spec must not show that loop as the way to hash many inputs.
  > - **Reply to plt-2 on I2.** plt says a mutable hasher has an "open/finished" state and that `let h2 = h` aliases one buffer. Neither holds in Blink: plt's own cite (03c_protocols.md:42) says values are copied on bind and there is no `&mut self`, and 07_trust_modules_metadata.md:1222 says a `mut self` write "never shows through another name". So `let h2 = h` is two independent hashers, and since `finish(self)` does not reset, there is no finished state. I1 under value semantics *is* plt's persistent state, with the method syntax that StringBuilder and Bytes writers already teach. I2's `Sha256State.update(st, c)` fold form is correct but a shape no model will produce unprompted; it costs more tokens at every call.
  > - Verb `update` over `write` (sys-1): `update` is the hashlib/Node/OpenSSL/Rust-`Digest` verb, and in Blink `write` is an `fs`/`io` word. Fewer wrong guesses.
  > - No `write_str` / `update_str`: one feed method. The copy is an implementation matter; if it matters, the runtime can special-case `Bytes.from_str` feeding.
  > - Traits: since methods must come from a trait, the spec needs one trait for `update`/`finish` and one for `to_hex`/`to_bytes`. Names must avoid `Hasher` (plt). I suggest `DigestState` for the first and `Digest` for the second; I do not hold a strong view on the names, only that neither contains "Hash".

- **Minimalism (V2):**

  > **V2. Return type — R1 plain `Bytes`, and I oppose R2, R3 and R4**
  >
  > The case for a digest type rests on three claims. None of them holds today.
  >
  > 2. **"`sha1 == sha256` should be a type error" (plt).** There is no `sha1`, and the unanimous point says none is coming in this decision. A type that guards against an algorithm we refuse to ship is YAGNI.
  > 3. **The cost the moderator's own fact check confirms.** There are no inherent methods (03c_protocols.md:826). So R2, R3 and R4 each need a new trait just to carry `to_hex` and `to_bytes`. R3 needs `Digest` (trait), `Sha256` (type), `from_hex`, and impls of `Display` and `Debug`. R4 needs `Digest`, `DigestError`, `DigestWriter`, `Sha256`, `parse`, `algorithm`, and two output forms (prefixed `Display` against bare `to_hex`), which devops itself counts as a decision point. Plain `Bytes` reuses `.to_hex()` and `==`, which exist today, and adds zero traits.
  >
  > sys's point on R2 ("a newtype keeps a later fixed-size representation open") is the strongest argument for a type, and I take it seriously. But a fixed `[U8; 32]` needs a fixed-array type, which Blink does not have and which no one proposes. If that type ever lands, the right move is a new function that returns it, not a wrapper today on speculation.
  >
  > R4 also hard-codes `algo: Str` inside the digest. That is the string-named algorithm, the thing all six seats rejected, moved inside a value.
  >
  > **Variation, constant-time:** yes, state it. One sentence in the spec: "`==` on a digest is ordinary bytewise equality and is not constant-time; do not use it to compare secrets." That costs nothing and stops a real misuse. (sys, web, plt all say the same.)
  >
  > **Variation, lowercase `to_hex`:** I hold this one. `Bytes.to_hex` (03_types.md:1360) says only "Hex string". The decided sha256sum constraint depends on lowercase. The runtime already uses `%02x` (bootstrap/runtime_core.h:2276), so this is a spec sentence, not a behavior change. Under R1 it is the only normative text the hex form needs.

- **Minimalism (V4):**

  > **V4. Incremental hasher — I0, defer**
  >
  > This is my main point of disagreement. sys, aiml and devops say lib/pkg needs streaming (F9). Look at what lib/pkg actually has:
  >
  > - `fs.read` returns `Str` (04_effects.md:1005), and there are no file handles in v1. Each file is already fully in memory when it is read, whatever the hasher looks like.
  > - The input is the source `.bl` files of one package. That is kilobytes to a few megabytes.
  > - sys-2's objection ("repeated `concat` is O(n^2)") is real, but it does not need a hasher. `List[Str].join` exists (lib/std/traits.bl:158), so one join and one `Bytes.from_str` is linear:
  >
  > ```blink
  > import std.digest
  >
  > fn package_hash(paths: List[Str]) -> Result[Str, FsError] ! FS.Read {
  >     let mut texts: List[Str] = []
  >     for p in paths.sort() {
  >         texts.push(fs.read(p)?)
  >     }
  >     Ok("sha256:{digest.sha256(Bytes.from_str(texts.join(""))).to_hex()}")
  > }
  > ```
  >
  > That matches `find | sort | xargs cat | sha256sum` byte for byte. The peak memory is the package source size, which lib/pkg already holds file by file. No caller in the repo needs a hasher. The compiler reads whole files today (src/sha256.bl:62), and web-2 says the only real streaming input is stdin chunks, which none of our callers use.
  >
  > What a hasher costs, from the other seats' own files:
  > - A trait, because of the no-inherent-methods rule (devops-1 `DigestWriter`).
  > - An argument the panel has not closed: mutable state that the type system cannot see as "finished" (plt-2), against value copy on bind (aiml-1). Four seats proposed four different shapes: `write` against `update`, a `write_str` or not, mutable against persistent, consume-on-`finish` or not. Spec text that has not settled is a bad thing to lock in as tier-1 forever (DECISIONS.md:313).
  > - A second way to compute the same digest, plus a law to keep the two in step.
  >
  > When the language gets file handles or a Reader trait, the hasher gets a real caller, and the panel can then pick its shape against a real use. Nothing in R1 plus I0 blocks that: it is purely additive.
  >
  > If the panel adds a hasher anyway, my fallback order is:
  > 1. web-2/aiml-1: `update(mut self, Bytes)`, `finish(self) -> Bytes` that does not reset, and the law one-shot == `new` + `update` + `finish`.
  > 2. Then plt-2 (persistent).
  >
  > I oppose `write_str` (sys): it is a second feed method to skip one copy, and the panel can add it later if a profile asks.

#### Phase C — Silent vote

| Question | Result |
|---|---|
| Q1 module | M1: all six |
| Q2 return type | R3 4 (Systems, PLT, DevOps, AI/ML); R1 2 (Web, Minimalism) |
| Q3 hasher | I1 5 (Systems, Web, PLT, DevOps, AI/ML); I0 1 (Minimalism, dissent) |
| Q4a one-shot call | O1 4 (Systems, PLT, DevOps, AI/ML); O2 2 (Web, Minimalism) |
| Q4b type names | T1 4 (Systems, PLT, Minimalism, DevOps); T2 2 (Web, AI/ML) |

**Q1**

- **Systems:**

  > **Q1. Module name**
  > **Vote:** M1 `std.digest`
  > **Reasoning:** One module holds the shared trait and every later algorithm, so tier-1-forever std grows by types, not by modules. `digest` collides with no effect handle and no trait name, so codegen and name resolution need no special case.
  > **Concern:** A later non-SHA family (a MAC tag with constant-time `==`) may get pushed into `std.digest` because it is the only home, which mixes secret-bearing types with public digests.

- **Web/Scripting:**

  > **Q1. Module name**
  > **Vote:** M1 `std.digest`
  > **Reasoning:** It names the concern, not one algorithm, so a later algorithm is a new name in a module users
  > already import. It has no other meaning in Blink, so it stays clear of the seeded `Hash` trait and the `crypto`
  > effect handle. Those are the two places a Python or JS dev would get lost.
  > **Concern:** Users will still search for "hash" first. The `Hash` trait doc and the `Crypto` row must point to
  > `std.digest` in one line each, or the first Stack Overflow answer will be `x.hash()`.

- **PLT:**

  > **Q1. Module name**
  > **Vote:** M1 `std.digest`
  > **Reasoning:** The shared trait for the digest surface needs one module to live in. With one module per algorithm, a generic bound `[D: Digest]` has no home. `digest` also has no meaning that clashes with the `Hash` trait or the `crypto` effect handle.
  > **Concern:** Later algorithms may be added to `std.digest` one at a time without a rule that each one has the same surface, so the family drifts.

- **DevOps/tooling:**

  > **Q1. Module name**
  >
  > **Vote:** M1 `std.digest`
  >
  > **Reasoning:** The qualifier `digest` is not an effect handle and is not the name of a trait method. Completion, hover and go-to-definition therefore have one target, and the "missing effect" diagnostic never has to guess whether `digest.` meant a capability. One module per concept also gives LSP auto-import one choice when SHA-512 or BLAKE3 arrives, not one module per algorithm.
  >
  > **Concern:** Users from Go will type `import std.sha256` first, so the "unknown module" error must suggest `std.digest`, or this name becomes a repeated question.

- **AI/ML:**

  > **Q1. Module name**
  > **Vote:** M1 `std.digest`
  > **Reasoning:** One import holds every later algorithm, so a model guesses one module name, not one per algorithm. It does not collide with the `crypto` effect handle (a reserved local name, 03c_protocols.md:810-818) or with the `Hash` trait method `.hash()`. A lower-case `sha256` qualifier would be shadowed by the most natural local name, `let sha256 = ...`.
  > **Concern:** `digest` is also a natural local name (`let digest = ...`), so code that calls through the qualifier (`digest.Sha256.of(...)`) can still be shadowed; the spec examples should use the selective import `import std.digest.{Sha256}`.

- **Minimalism:**

  > **Q1. Module name**
  >
  > **Vote:** M1 `std.digest`
  >
  > **Reasoning:** One module per concern, and the concern is the digest, not the algorithm. A later algorithm then adds one item to an existing module instead of a new module and a new import. The name keeps clear of the `Hash` trait and of the `crypto` effect handle, which was my hard rule.
  >
  > **Concern:** "digest" can become a home for scope creep (HMAC, KDFs, checksums) because the name invites it, so each addition still needs a caller before it lands.

**Q2**

- **Systems:**

  > **Q2. Return type of the one-shot function**
  > **Vote:** R3 opaque digest type
  > **Concern:** If the implementation wraps the buffer in an extra struct or box instead of passing the `Bytes` itself, every digest pays an indirection the spec did not ask for.

- **Web/Scripting:**

  > **Q2. Return type of the one-shot function**
  > **Vote:** R1 plain `Bytes`
  > **Reasoning:** `Bytes` in, `Bytes` out, `.to_hex()` for text: every part is something a user already knows, and it
  > maps directly onto Python `.digest()`/`.hexdigest()` and Node `Buffer`/`'hex'`. The empty-hash bug sat in lib/pkg's
  > lockfile reading, not in the digest type, and a 32-byte result can never be empty. An opaque type adds a trait,
  > an import and `to_bytes()` at every boundary to guard against a mix-up I have not seen in review.
  > **Concern:** If R3 wins, users who want raw bytes or a Map key must find `to_bytes()`/`to_hex()` through a trait
  > they have to import. If the trait import is not automatic with the type, "no method `to_hex`" becomes the first
  > error every newcomer hits, so the spec example must show the exact import line.

- **PLT:**

  > **Q2. Return type**
  > **Vote:** R3 opaque digest type
  > **Reasoning:** "Always 32 bytes" becomes a fact about the type, not a comment. A digest from one algorithm compared with a digest from another is a compile error, not a well-typed `false`. The strict `from_hex` with the round-trip law (`from_hex(d.to_hex()) == Some(d)` and the converse) makes a hex-text compare and a typed compare agree. `opaque` costs nothing at run time (§2.12.2), so the invariant is free.
  > **Concern:** The spec could state the representation laws (length 32, strict lowercase parse, round trip) only in prose. They must be normative text with tests, or the opaque type protects nothing.

- **DevOps/tooling:**

  > **Q2. Return type of the one-shot function**
  >
  > **Vote:** R3 opaque digest type
  >
  > **Concern:** `from_hex` returns `Option`, so each caller writes its own error text for a bad entry ("63 digits, expected 64"). lib/pkg must do that carefully, or the user sees a bare "invalid hash".

- **AI/ML:**

  > **Q2. Return type of the one-shot function**
  > **Vote:** R3 opaque digest type
  > **Reasoning:** The common call `.to_hex()` is the same on `Bytes` and on the digest type, so the type adds no tokens and no new name to the 90% path. It makes an empty digest impossible to build (`from_hex("")` is `None`), which closes the empty-hash lockfile bug by type rather than by a prose rule models forget. Opaque, not transparent, so no model can "construct" a digest from arbitrary bytes. No `Display` means `"{d}"` is a compile error that points to `to_hex()`, not a silent wrong string.
  > **Concern:** Models will first try to pass a digest where `Bytes` is expected (or call `.len()` on it); the type-mismatch diagnostic must name `to_bytes()` as the fix.

- **Minimalism:**

  > **Q2. Return type of the one-shot function**
  >
  > **Vote:** R1 plain `Bytes`
  >
  > **Reasoning:** The function is total and always gives 32 bytes, so the empty-hash bug cannot come from it. The other half of that bug is lockfile text, and lib/pkg must check that text whatever std returns. R3 needs a new opaque type, a trait for `to_hex`/`to_bytes`, a hex parser that `Bytes` itself lacks, and three trait impls, all to guard against a mix-up between algorithms we refuse to ship. Plain `Bytes` reuses `==` and `.to_hex()` with no new names, and a typed digest can still be added later without breaking anyone.
  >
  > **Concern:** If R3 wins, `from_hex` exists only on the digest type while `Bytes` has no hex decode, which leaves an odd gap in the Bytes surface that the next ticket will ask to fill.

**Q3**

- **Systems:**

  > **Q3. Incremental hasher**
  > **Vote:** I1 value hasher
  > **Reasoning:** Fixed ~104-byte state, in-place `update` on a `let mut` root, and a copy only when a second name is bound; the existing value rules (03_types.md:1387, :3794) make it sound with no new rule. I0's `join("")` is linear, so I withdraw my O(n^2) point against it, but it still holds the whole input in memory and gives no path for chunked stdin (`io.read_bytes`) or any future fs handle. The sys line (state size and per-`update` cost independent of total input length) must be in the normative text.
  > **Concern:** A pure-Blink implementation over `List[Int]`, or a `Bytes` tail that is reallocated on each `update`, would meet the API and L1 but miss the cost line, and nobody notices until a large input.

- **Web/Scripting:**

  > **Q3. Incremental hasher**
  > **Vote:** I1 value hasher
  > **Reasoning:** "Hash my directory" is a loop over files, and without a hasher users write `all = all.concat(...)`,
  > which is quadratic and slow in a way they do not see until a big tree. `new()` / `update` / `finish` is the shape
  > every scripting dev knows from `hashlib` and `createHash`. Value semantics (copy on bind) means `let h2 = h` is
  > safe with no new rule, and a non-resetting `finish` avoids Node's "Digest already called" trap.
  > **Concern:** `update(mut self, ...)` needs `let mut h`; a user who writes `let h = ...` gets E0610. The error text
  > should say "declare the hasher with `let mut`", not only the generic mutation message.

- **PLT:**

  > **Q3. Incremental hasher**
  > **Vote:** I1 value hasher
  > **Reasoning:** Blink copies values on bind, so a `mut self` hasher means `h = update(h, b)`. There is no aliasing and no use-after-finish state, so it is sound without affine types. Law L1 proves the one-shot and the incremental paths equal, so this is one function with two entry points, not two semantics. lib/pkg and `io.read_bytes` give it real callers. I accept sys's constant-state rule.
  > **Concern:** An implementation might back the hasher with a shared C buffer for speed. That would make it a hidden shared cell and break copy-on-bind. The spec must say the hasher is a plain value, not one of the shared cells listed at 03_types.md:3794.

- **DevOps/tooling:**

  > **Q3. Incremental hasher**
  >
  > **Vote:** I1 value hasher
  >
  > **Reasoning:** lib/pkg hashes a package's sorted files as one stream today. A hasher keeps that a loop of `h.update(...)`, which completion offers after `h.`. Copy-on-bind (03c_protocols.md:42) and a non-consuming `finish` mean the hasher has no hidden "finished" state, so no rule exists that a lint or a runtime error would need to enforce. Law L1 also gives a direct golden test.
  >
  > **Concern:** If an implementation makes the hasher a shared cell (as `StringBuilder` is), `let h2 = h` breaks the value rule without a word from the compiler, so the spec text and a corpus test must pin copy-on-bind for this type.

- **AI/ML:**

  > **Q3. Incremental hasher**
  > **Vote:** I1 value hasher
  > **Reasoning:** `new` / `update(mut self)` / `finish(self)` is the shape the spec already teaches (StringBuilder, Bytes writers, `mut self`) and the shape every model's priors hold (hashlib, Node, Rust `Digest`). Under value semantics (03_types.md:3794-3800) `let h2 = h` forks the state and `finish` has no "already finished" trap, so there is nothing extra to learn. Without it, the spec has to teach join-or-concat-then-hash for multi-input hashing, and models copy that into loops.
  > **Concern:** If the implementation makes the hasher a shared C cell for speed, it breaks the "only these types share" list and copy-on-bind; the spec text must say the hasher is a plain value.

- **Minimalism (dissent):**

  > **Q3. Incremental hasher**
  >
  > **Vote:** I0 none now
  >
  > **Reasoning:** No caller in the repo needs it. `fs.read` gives back whole files as `Str`, there are no file handles in v1, and lib/pkg gets the exact `sha256sum` result in linear time with `texts.join("")` and one hash. A hasher is a trait, a type, a second path to the same result, and a law to keep the two in step, all locked in as tier-1 forever. When file handles or a Reader trait land, the hasher gets a real caller and can be added then, and adding it later breaks nothing.
  >
  > **Concern:** If I1 wins, `finish` that neither consumes nor resets is fine under value copy, but the spec must test the copy-on-bind claim for an opaque type whose C form holds a buffer, or `let h2 = h` will alias in the runtime even though the spec says it cannot.

**Q4a**

- **Systems:**

  > **Q4a. One-shot call**
  > **Vote:** O1 `Sha256.of(data)`
  > **Reasoning:** The moderator confirmed a type-scoped fn needs no trait, so `Sha256.of` costs nothing extra and keeps the algorithm in the type, where the compiler can see it. It also matches the `Type.name(...)` constructor shape users already know from `Bytes.from_str` and `Sha256.from_hex`.
  > **Concern:** Under T2 the one-shot `Sha256.of(data)` would return a `Sha256Digest` while `Sha256.new()` returns a hasher, so one type name produces two different types.

- **Web/Scripting:**

  > **Q4a. One-shot call**
  > **Vote:** O2 `digest.sha256(data)`
  > **Reasoning:** One import (`import std.digest`) and a call that reads like Go `sha256.Sum256` or Python
  > `hashlib.sha256`. `Sha256.of(data)` makes a user import a type name only to hash once, and `of` is not a word
  > anyone types into search. O2 works under R1 and R3 alike.
  > **Concern:** If O1 wins, a user who imports only the module (`import std.digest`) must write
  > `digest.Sha256.of(b)`; the docs must show the one form that works so users do not guess between the two.

- **PLT:**

  > **Q4a. One-shot call**
  > **Vote:** O1 `Sha256.of(data)`
  > **Reasoning:** Under R3 the one-shot is a type-scoped constructor of the type it returns, the same form as `Duration.ms`. Each algorithm adds one type and its functions, and adds no free names to the module. It also keeps `from_hex` and `of` in one `Sha256.` namespace.
  > **Concern:** If R1 wins instead, O1 has no type to hang on, and the fallback name must be settled cleanly, not patched in later.

- **DevOps/tooling:**

  > **Q4a. One-shot call**
  >
  > **Vote:** O1 `Sha256.of(data)`
  >
  > **Reasoning:** Every entry point for the algorithm hangs off one type name, so typing `Sha256.` lists the one-shot, and with it the parse or the hasher constructor, depending on Q4b. `blink doc Sha256` then shows the whole surface on one page. A free `digest.sha256` splits the surface between a module function and a type.
  >
  > **Concern:** LLM-written code will still try `digest.sha256(data)`, so the "undefined function" help should point to `Sha256.of`.

- **AI/ML:**

  > **Q4a. One-shot call**
  > **Vote:** O1 `Sha256.of(data)`
  > **Reasoning:** A capitalised type-scoped call cannot be shadowed by a lower-case local, and it puts the one-shot next to `Sha256.new()` in completion after `Sha256.`. Rust `sha2` uses the same split (`Sha256::digest(b)` next to `Sha256::new()`).
  > **Concern:** Models with Go/Python priors will try `sha256(data)` or `digest.sha256(data)` first; the spec example and the unknown-name diagnostic should show `Sha256.of`.

- **Minimalism:**

  > **Q4a. One-shot call**
  >
  > **Vote:** O2 `digest.sha256(data)`
  >
  > **Reasoning:** Under R1 there is no `Sha256` digest type for `Sha256.of` to hang on, so a free function is the only form that adds no type. It reads as "the sha256 digest of data" and matches the module qualifier style of the rest of std (`json.`, `path.`).
  >
  > **Concern:** If O1 wins together with I1, `Sha256.of` and `Sha256.new()` sit side by side, and users may not see at once which of them gives a digest and which gives a hasher.

**Q4b**

- **Systems:**

  > **Q4b. Type names under R3 + I1**
  > **Vote:** T1 digest `Sha256`, hasher `Sha256State`
  > **Reasoning:** The value users store, compare and parse is the digest, so it gets the short name; `Sha256.of`, `Sha256.from_hex` and `Sha256` in a signature all mean the same type. The hasher is the rarer, transient type, and `State` says what it is without the word "Hash".
  > **Concern:** Users from Rust/Go expect `Sha256` to be the hasher and will try `Sha256.new()`; the error must point to `Sha256State.new()`.

- **Web/Scripting:**

  > **Q4b. Type names under R3 + I1**
  > **Vote:** T2 hasher `Sha256`, digest `Sha256Digest`
  > **Reasoning:** `Sha256.new()` then `.update(...)` then `.finish()` is the hashlib/createHash object a scripting dev
  > expects: the thing you build is named for the algorithm. `Sha256Digest` in a signature says what the value is
  > without a doc lookup. `Sha256State` is a word from implementation, not from use.
  > **Concern:** Under T1, `Sha256` is the result and `Sha256State` is the builder, the reverse of hashlib and Rust
  > `sha2`, so copied code from those languages will call `Sha256.new()` and fail.

- **PLT:**

  > **Q4b. Type names**
  > **Vote:** T1 digest `Sha256`, hasher `Sha256State`
  > **Reasoning:** The digest is the value users store, compare and pass around, so it gets the short name. The hasher is a transient fold state, and `State` names what it is. Under T2, `Sha256.of(...)` would return a `Sha256Digest`, not a `Sha256`, so the constructor name and its result type would not match.
  > **Concern:** Users from Rust or Go expect `Sha256` to be the hasher, and the docs must make the split clear at the top of the module.

- **DevOps/tooling:**

  > **Q4b. Type names under R3 + I1**
  >
  > **Vote:** T1 digest `Sha256`, hasher `Sha256State`
  >
  > **Reasoning:** I change from my Phase B position (T2). With O1 likely, T1 makes `Sha256.of(data)` return a `Sha256`: the type-scoped function builds its own type. Under T2, `Sha256.of` would return a different type (`Sha256Digest`), and hover on that call would surprise. `Sha256State` is clear enough that "expected Sha256, found Sha256State" in a type error explains itself.
  >
  > **Concern:** Rust users expect `Sha256` to be the hasher and will write `Sha256.new()`. With T1 that is an undefined type-scoped function, so its help must name `Sha256State.new()`.

- **AI/ML:**

  > **Q4b. Type names under R3 + I1**
  > **Vote:** T2 hasher `Sha256`, digest `Sha256Digest`
  > **Reasoning:** Every prior a model has names the hasher after the algorithm: Rust `Sha256::new()`, Python `hashlib.sha256()`, Java `MessageDigest`, Node `createHash("sha256")`. Under T1, `Sha256.new()` (the first thing a model writes to stream) does not exist and `Sha256State` must be learned from the spec. Under T2, both `Sha256.new()` and `Sha256.of(b)` compile, and the output type says what it is in its name.
  > **Concern:** If T1 wins, the spec needs an explicit example of `Sha256State.new()` near the top of the module doc, or models will write `Sha256.new()` and `.update()` on the digest type.

- **Minimalism:**

  > **Q4b. Type names under R3 + I1**
  >
  > **Vote:** T1 digest `Sha256`, hasher `Sha256State`
  >
  > **Reasoning:** This part matters only if R3 and I1 both win. The digest is the value most code holds, passes and compares, so it gets the short name. The hasher is the rare, stateful one, and `State` in its name says so. It also reads right with O1: `Sha256.of(data) -> Sha256`.
  >
  > **Concern:** Under T1, a user who knows Go or Rust may write `Sha256.new()` expecting a hasher and get a "no such function" error. The diagnostic must point to `Sha256State.new()`.

#### Phase D — Q2, Q4a and Q4b re-vote after one debate round

Q2, Q4a and Q4b were 4-2, so one focused debate round ran on them. The seats disagreed on whether `import std.digest` alone reaches `to_hex` and the other methods. PLT first said it did not. The moderator checked the spec text and put it in the Phase D ballot (verbatim):

> 03_types.md:4696-4699, *Impl visibility*:
> - Rule 1: "An impl that lives in the package that defines `T` is a candidate at every call site where its trait is visible. The file does not import `T`, the trait, or any module for it."
> - Rule 2: "An impl that lives only in the trait's package is a candidate when the trait is in scope at the call site. ... A whole-module import (`import ext`) does not put the traits of `ext` in scope for method calls."
> - "A trait is **visible** at a call site when the file can name it: the module declares it, or it is `pub` in a module the file can import."
>
> 03c_protocols.md:646 repeats rule 1 for method lookup. Under R3, the digest type, its trait and its impls are all in `std.digest`.

Result: Q2 R3 5-1 (Minimalism dissented, R1). Q4a O1 5-1 (Minimalism voted O2; its own request is quoted below). Q4b T1 6-0 (Web and AI/ML moved from T2). Votes, verbatim:

- **Systems:**

  > **Q2. Return type of the one-shot function**
  > **Vote:** R3
  > **Reasoning:** Under R1 and R3 the C value is the same 32-byte `Bytes`; `opaque` changes visibility only, so the length invariant, the strict parse and "no empty digest" cost nothing at run time. Rule 1 of *Impl visibility* (03_types.md:4696) makes `to_hex` resolve with only the type imported, so the trait adds no call-site cost either. With std tier-1 forever, the return type is chosen once; a typed digest added later would break callers or add a second one-shot.
  > **Concern:** The closed method list (no `len`, no `from_bytes`) will push users to `to_bytes()` copies in hot paths, so the implementation must keep `to_bytes` a single 32-byte copy with no hex round trip.
  >
  > **Q4a. One-shot call**
  > **Vote:** O1 `Sha256.of(data)`
  > **Reasoning:** A type-scoped fn needs no trait and no dispatch; it is a direct call. It keeps `of`, `from_hex` and the type in one `Sha256.` namespace, so one algorithm is one name in docs and completion.
  > **Concern:** Code written from Go/Python priors will try `digest.sha256(data)`, and the unknown-name help must point to `Sha256.of`.
  >
  > **Q4b. Type names under R3 + I1**
  > **Vote:** T1 digest `Sha256`, hasher `Sha256State`
  > **Reasoning:** Every `Sha256.` function then returns a `Sha256`; under T2 `Sha256.of` and `Sha256.new()` return two different types. The digest is the value code stores and compares, so it gets the short name. Names do not change codegen; this vote rests on the one-rule argument.
  > **Concern:** Rust users will write `Sha256.new()` first, so the help naming `Sha256State.new()` must ship with the type, not later.

- **Web/Scripting:**

  > **Q2. Return type of the one-shot function**
  > **Vote:** R3
  > **Reasoning:** The impl-visibility rule (03_types.md:4696, rule 1) means `Sha256.of(b).to_hex()` works with no trait
  > import, so the 90% call costs the same as under plain `Bytes`. With that cost gone, R3 gives users a strict
  > `from_hex` for lockfile text and makes `"sha256:{d}"` a compile error that points to `to_hex()`, so no tool can
  > write the wrong text by accident.
  > **Concern:** With no `from_bytes` and no `len`, a user who has 32 raw bytes from a binary file format cannot get a
  > digest back, and will round-trip through `to_hex`/`from_hex`; if that shows up in friction logs, add a checked
  > `from_bytes` then.
  >
  > **Q4a. One-shot call**
  > **Vote:** O1 `Sha256.of(data)`
  > **Reasoning:** Under R3 the one-shot builds the digest type, so `Sha256.of` beside `Sha256.from_hex` puts the
  > common surface under one `Sha256.` prefix in completion and in `blink doc`. It matches `Duration.ms` and
  > `Bytes.from_str`, which users already know, and `digest.Sha256.of(b)` works with a plain module import.
  > **Concern:** Python and Go users will first type `digest.sha256(b)`; the unknown-name help must name `Sha256.of`.
  >
  > **Q4b. Type names under R3 + I1**
  > **Vote:** T1 digest `Sha256`, hasher `Sha256State`
  > **Reasoning:** The one-shot is the common path, and under T1 `Sha256.of(data)` returns a `Sha256`, so hover and type
  > errors show one name for one call. The hasher is the rare path and can carry the longer name; the refined help for
  > `Sha256.new()` gives the first wrong guess a one-line fix.
  > **Concern:** Code copied from hashlib or Rust `sha2` will call `Sha256.new()`; if the help text does not ship with
  > the feature, that error is the first thing streaming users hit.

- **PLT:**

  > Correction first: my Phase D claim that `import std.digest` plus `d.to_hex()` gives E0505 was wrong. The moderator's check of 03_types.md:4696 rule 1 shows that the digest type, its trait and its impls all live in `std.digest`, so the impl is a candidate wherever the trait is visible. No import of the trait is needed. The ergonomic cost of R3 that I conceded to web does not exist.
  >
  > **Q2**
  > **Vote:** R3
  > **Reasoning:** R1 is permanent once shipped: tier-1 forever means a `Bytes` result can never become a typed digest without breaking callers or adding a second API. R3 makes the 32-byte, lower-case, round-trip laws normative facts about the type, and makes digests of different algorithms a compile error rather than a well-typed `false`. With rule 1 of *Impl visibility*, R3 costs no extra import. `d.to_bytes()` gives the R1 value in one call.
  > **Concern:** The closed builder list (`of`, `from_hex`, `finish`) holds only if the implementation never adds an internal `from_bytes` that leaks through `pub`. The representation laws need tests that check every builder.
  >
  > **Q4a**
  > **Vote:** O1 `Sha256.of(data)`
  > **Reasoning:** Under R3, the type-scoped constructor returns its own type, so `Sha256.` holds the whole digest surface (`of`, `from_hex`) and each future algorithm adds one type and no free names. If R1 wins, I ask the moderator to read my vote here as O2, since O1 has no type to hang on under R1.
  > **Concern:** Separate tallies could produce R1 + O1 or R3 + O2, which do not fit together. The decision text must state the pairing.
  >
  > **Q4b**
  > **Vote:** T1 digest `Sha256`, hasher `Sha256State`
  > **Reasoning:** T1 keeps the rule that `T.of` / `T.from_hex` build a `T`. Under T2, `Sha256.new()` and `Sha256.of(b)` in one namespace return two different types. The prior-driven mistake `Sha256.new()` becomes a loud, local error whose help names `Sha256State.new()`.
  > **Concern:** Code copied from Rust or Python will hit that error often, so the help text is a required part of the decision, not optional polish.

- **DevOps/tooling:**

  > **Q2. Return type of the one-shot function**
  >
  > **Vote:** R3
  >
  > **Reasoning:** The moderator's fact settles the import question. The impl lives in the package that defines the type, so `to_hex()` resolves wherever the trait is visible, and `import std.digest.{Sha256}` is enough. R3 then costs the user nothing at the call site, and it moves the lockfile check into one tested place, `from_hex`. With R1 every tool writes that check again. A type name in hover and in mismatch errors also beats `Bytes`, which tells the reader nothing.
  >
  > **Concern:** `from_hex` returns `Option`, so lib/pkg must still write a clear message for a bad lockfile entry (empty, wrong length, upper case), or the user sees a bare "invalid hash".
  >
  > **Q4a. One-shot call**
  >
  > **Vote:** O1
  >
  > **Reasoning:** Everything a user needs for the algorithm sits under one type name. Typing `Sha256.` lists `of` and `from_hex`, and `blink doc Sha256` is the full page. A free function would split that surface between the module and the type, and completion would show half of it in each place.
  >
  > **Concern:** Users and models will write `digest.sha256(data)` first, so the "undefined function" help (E0504) must offer `Sha256.of(data)` as a fix the tool can apply.
  >
  > **Q4b. Type names under R3 + I1**
  >
  > **Vote:** T1
  >
  > **Reasoning:** With O1, `Sha256.of(data)` returns a `Sha256` and `Sha256.from_hex` returns a `Sha256`, so the function's name and its result type agree in hover and in signatures. The likely wrong guess, `Sha256.new()`, has one exact fix, `Sha256State.new()`, which the option text already requires the help to name. T2 instead makes one type name produce two types, a mismatch that never goes away.
  >
  > **Concern:** If the E0504 help for `Sha256.new()` ships without that fix, users from Rust and Python will hit a dead end on the first streaming call.

- **AI/ML:**

  > **Q2. Return type of the one-shot function**
  > **Vote:** R3
  > **Reasoning:** The moderator's check of rule 1 (03_types.md:4696) confirms that `to_hex` works on the digest with no trait import, so the common path `Sha256.of(b).to_hex()` costs the same tokens and names as plain `Bytes`. The type makes an empty or wrong-length digest impossible to build, so the lockfile bug is closed by a rule the compiler checks, not by prose a model forgets. The closed method list and no `Display` mean `"{d}"` and `d.len()` are compile errors with a fix, not silent wrong answers.
  > **Concern:** Models will pass a digest where `Bytes` is expected; the type-mismatch help must name `to_bytes()`.
  >
  > **Q4a. One-shot call**
  > **Vote:** O1
  > **Reasoning:** A capitalised type-scoped call cannot be shadowed by a lower-case local such as `digest` or `sha256`, and it keeps `of`, `from_hex` and the type in one place for completion and docs. Each later algorithm then adds one type with the same functions, a pattern a model can extend from one example.
  > **Concern:** Go/Python priors will produce `digest.sha256(data)` first; the unknown-name help should name `Sha256.of`.
  >
  > **Q4b. Type names under R3 + I1**
  > **Vote:** T1
  > **Reasoning:** Under T1 every `Sha256.<fn>` returns a `Sha256`, a rule with no exceptions that a model can learn from the spec alone. T2 matches Rust/Python priors for the hasher but makes the return type of `Sha256.<fn>` vary per function, a decision point at every call and signature. The prior mismatch under T1 costs one compile error with a named fix, and only on the rare streaming path.
  > **Concern:** If the module doc does not show `Sha256State.new()` + `update` + `finish` in its first example, models will keep writing `Sha256.new()`.

- **Minimalism (dissent on Q2; Q4a vote to be read as O1):**

  > **Q2. Return type of the one-shot function**
  >
  > **Vote:** R1 plain `Bytes`
  >
  > **Reasoning:** The refined R3 is the smallest typed digest I could ask for. The moderator's fact check also removes the trait-import cost, so R3 is not harmful. It is still early. The 32-byte fact and the strict parse guard against algorithms we do not ship and against a lockfile parse that lib/pkg must write anyway, because lib/pkg still strips `sha256:` and writes its own error text. A typed digest can be added later without breaking any R1 caller. Once in tier-1 std, the type and its trait can never be taken back.
  >
  > **Concern:** If R3 wins, the closed method list and the no-`from_bytes` rule must stay normative text. Otherwise the first "convenience" request (`len`, `Display`, `from_bytes`) erodes the invariant that is the type's only reason to exist.
  >
  > **Q4a. One-shot call**
  >
  > **Vote:** O2 `digest.sha256(data)`
  >
  > **Reasoning:** This follows from my Q2 vote: under R1 there is no digest type for `Sha256.of` to hang on. If R3 wins, read this vote as O1. A free function that returns an opaque `Sha256` would give one surface two entry points for no gain.
  >
  > **Concern:** If the Q2 and Q4a results split (R3 with O2, or R1 with O1), the API gets an entry point that does not match its result type, so the moderator should reconcile Q4a with Q2 before the spec text is written.
  >
  > **Q4b. Type names under R3 + I1**
  >
  > **Vote:** T1 digest `Sha256`, hasher `Sha256State`
  >
  > **Reasoning:** With T1, every type-scoped function returns its own type: `Sha256.of`, `Sha256.from_hex`, `Sha256State.new`. The digest is the value that sits in signatures and struct fields, so it should get the short name. The cost is one diagnostic: the help for `Sha256.new()` names `Sha256State.new()`.
  >
  > **Concern:** Copied Rust and Python code will reach for `Sha256.new()` first, so if that help is missing or vague, T1's first contact with users is an error with no fix.

Minimalism's Q2 text calls R3 "the smallest typed digest I could ask for" and says "R3 is not harmful", and still votes R1 because "It is still early." Its Q4a text asks that the vote be read as O1 if R3 wins. R3 won, so Q4a is counted 5-1 for O1.

### Final Spec

```blink
import std.digest.{Sha256, Sha256State}

fn main() ! IO.Print {
    let d = Sha256.of(Bytes.from_str("abc"))
    io.println(d.to_hex())
    // ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
    match Sha256.from_hex(d.to_hex()) {
        Some(back) => io.println("{back == d}")     // true
        None => io.println("bad hex")
    }

    let mut h = Sha256State.new()
    h.update(Bytes.from_str("a"))
    h.update(Bytes.from_str("bc"))
    io.println("{h.finish() == d}")                 // true
}
```

Locked points:

- Module `std.digest`. SHA-256 only. No `std.crypto`, no `std.hash`, no algorithm named by a string.
- `pub opaque type Sha256`: always 32 bytes. `to_hex(self) -> Str` and `to_bytes(self) -> Bytes` (a new 32-byte buffer) come from `pub trait Digest`. The method list is closed: no `len`, no `algorithm`, no `Display`.
- `Sha256.from_hex(s: Str) -> Option[Sha256]` accepts exactly 64 lower-case hex digits, else `None`.
- `Sha256.of`, `Sha256.from_hex` and the hasher's `finish` are the only ways to build a `Sha256`. No `from_bytes`.
- `Sha256` implements `Eq`, `Clone` and `Debug`. It does not implement `Display`, `Hash` or `Ord`. `==` is not constant-time.
- Laws, normative: `d.to_bytes().len() == 32`; `d.to_hex()` is 64 lower-case hex digits; `Sha256.from_hex(d.to_hex())` gives `Some(d)`; for a `Str` that `from_hex` accepts, `.to_hex()` gives it back; `from_hex` rejects upper case.
- The output equals SHA-256 as FIPS 180-4 defines it.
- `pub opaque type Sha256State` is a plain value, not a shared cell. `Sha256State.new()`. `update(mut self, data: Bytes)` and `finish(self) -> Sha256` come from `pub trait DigestWriter`. `finish` neither consumes nor resets. `update` is the only feed method.
- Law L1: `new()`, `update(a)`, `update(b)`, `finish()` equals `Sha256.of(a.concat(b))`. The cost of one `update` and the size of the hasher do not depend on the total input length.
- `Sha256.of(data: Bytes) -> Sha256` is a type-scoped fn with no effect row.
- Trait names `Digest` (PLT proposal) and `DigestWriter` (DevOps proposal) come from those proposals. The panel did not vote on them.
- Impl visibility rule 1 puts the impls with the types, so the methods need no trait import. `import std.digest` is enough.
- `Bytes.to_hex` gives lower case, two digits per byte. No hex helper fn and no `Bytes.from_hex` in this decision.
- `Hash` is not the digest. The `Hash` trait text points to `std.digest`.
- `Crypto.Hash` stays. The effect text says a plain digest is a pure function and needs no effect.
- Help texts: `Sha256.new()` gets `Sha256State.new()` and `Sha256.of(data)`; `digest.sha256(data)` gets `Sha256.of(data)`; `import std.sha256` gets `import std.digest`; a `Sha256` where `Bytes` is expected gets `.to_bytes()`; `update` on a `let` hasher is E0610 with the `let mut` fix. No new error code.

### Concerns

From the Phase C and Phase D ballots:

- Systems: a later MAC type with a constant-time `==` must not go into `std.digest`; `to_bytes` is one 32-byte copy.
- PLT: each later algorithm in `std.digest` gets the same surface; no public `from_bytes` may leak; tests must check every way to build a `Sha256`.
- DevOps: lib/pkg must give clear errors for a bad lockfile hash; the `Sha256.new()` help must ship with the feature.
- Web: the module doc opens with the import line and both examples; if friction logs show a need, add a checked `from_bytes` later.
- AI/ML: the type-mismatch help names `to_bytes()`.
- Minimalism: scope creep in `digest`; the closed method list and the no-`from_bytes` rule must stay normative; lib/pkg strips the `sha256:` prefix and writes its own error text.
- The hasher must stay a plain value, and a test must show copy on bind (Systems, Web, DevOps, AI/ML).

### Amendments

None.

### Implementation notes

- The corpus needs a test for each law, for the copy-on-bind rule, and for each help text.

### Open cases and follow-ups

- Re-scope or remove `Crypto.Hash` (a spec task).
- `Bytes.from_hex` does not exist. A caller with hex text uses `Sha256.from_hex` only for a digest.
- `fs` has no byte read, so a program cannot hash a file without a text read. The old spec example that called `fs.read_bytes` named an operation that does not exist; the example was replaced.

### AI-first review

- Learnability — pass. `Sha256.of(data)` and `Type.from_hex` match `Bytes.from_str` and `Duration.ms`; one example shows both uses.
- Consistency — pass. Type-scoped fns return their own type; the hasher is a value like `Bytes`.
- Generability — pass. A closed method list and no `from_bytes` leave one way to write each task.
- Debuggability — pass. Each likely wrong guess gets a help text with the right form (see the table in the subsection).
- Token efficiency — pass. The common path is one call: `Sha256.of(data).to_hex()`.
