[< All Decisions](../DECISIONS.md)

# Additional Built-in Types — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 5 questions. All votes unanimous.

**Q1: DateTime/Instant value type — what `time.read()` returns (5-0 for stdlib Instant)**

- **Systems:** `struct { int64_t nanos; }` is zero-cost nominal typing. Same codegen as raw Int but prevents nonsense like adding two timestamps. Tier 2 placement needs stable ABI contract with effect system.
- **Web/Scripting:** Every JS dev knows `Date.now()` returning a raw number is painful — you immediately wrap it. Go's `time.Now()` returning `time.Time` is vastly better DX. One import line is nothing; LSP handles it. Methods like `.to_rfc3339()` and `.elapsed()` are discoverable on the value.
- **PLT:** Time points form an affine space over durations. `Int` collapses point/vector distinction, allowing nonsensical `time1 + time2`. Distinct `Instant` type encodes correct algebraic structure statically. Tier 2 keeps the core language small.
- **DevOps:** Diagnostic difference between `got Int` and `got Instant` is massive. LSP hover and autocomplete for `.elapsed()`, `.to_rfc3339()` is a huge ergonomics win. Missing import diagnostic: `Instant not found. Did you mean: import std.time.Instant?`
- **AI/ML:** Raw Int maximizes initial generation accuracy but creates long-tail hallucination bugs. Stdlib Instant with `.to_rfc3339()` gives LLMs method-call patterns matching Rust/Go/Python training data. Import is one learnable pattern.

**Q2: Duration type — what `time.sleep()` accepts (5-0 for stdlib Duration)**

- **Systems:** Named constructors kill unit confusion bugs. `.scale(Int)` method handles sealed-trait ergonomic gap — compiles to a single `imul`. Zero overhead wrapper.
- **Web/Scripting:** `time.sleep(5000)` — milliseconds? seconds? Every web dev has been bitten. `Duration.seconds(5)` is self-documenting and eliminates entire class of bugs. Named constructors guide toward correct usage.
- **PLT:** Duration carries dimensional information; `Int` is dimensionless. Mars Climate Orbiter was lost to a unit confusion bug — same error class. Named constructors enforce units at construction, the only correct approach without a units-of-measure system.
- **DevOps:** `time.sleep(5)` — 5ms or 5 seconds? No tooling can catch this with raw Int. With Duration: `expected Duration, got Int. Hint: use Duration.ms(5) or Duration.seconds(5)`. Actionable error messages teach the API.
- **AI/ML:** Strongest vote. Unit confusion with raw Int is a *guaranteed* bug source. Python-trained LLMs write `time.sleep(5)` meaning seconds. `Duration.seconds(5)` is unambiguous — LLMs can't get the unit wrong.

**Q3: Bytes/ByteArray (5-0 for stdlib Bytes, Tier 1)**

- **Systems:** `List[U8]` with boxed elements is 8-24 bytes overhead *per byte*. Contiguous `uint8_t*` buffer is non-negotiable for I/O, FFI, crypto. Tier 1 because FS/Net effects must return contiguous memory.
- **Web/Scripting:** Web devs deal with binary data constantly — file uploads, image processing, crypto. `List[U8]` is semantically wrong and performance-terrible. Dedicated `Bytes` with `.slice()`, `.to_hex()` is table stakes.
- **PLT:** `List[U8]` is parametrically correct but representationally wrong. Same lesson as Haskell's `[Word8]` vs `ByteString`. Nominal type boundary lets compiler guarantee contiguous layout.
- **DevOps:** Debug output `Bytes(ff d8 ff e0 ...)` vs `[255, 216, 255, 224, ...]`. Hex display alone justifies a dedicated type. Error: `expected Str, got Bytes. Hint: use data.to_str()`.
- **AI/ML:** `List[U8]` triggers `.decode("utf-8")` hallucinations from Python training data. Dedicated `Bytes` maps to Go's `[]byte` (very well-represented in training data).

**Q4: Numeric extensions (5-0 for F32 built-in + Decimal/BigInt stdlib)**

- **Systems:** F32 maps to `float`, uses existing FPU hardware, fits sized-numeric pattern. Decimal/BigInt are complex enough for stdlib Tier 2. 128-bit fixed-point for Decimal representation.
- **Web/Scripting:** F32 fits sized numeric pattern. Decimal matters for payments — e-commerce, fintech need exact arithmetic. BigInt useful for crypto and large ID spaces.
- **PLT:** F32 is isomorphic to I8/I16/I32 — fixed-size primitive with direct C type. Excluding it is unprincipled asymmetry. Decimal/BigInt have variable/unbounded representations — categorically different. Sealed arithmetic must be absolute; named methods for Decimal/BigInt.
- **DevOps:** F32 consistent with I8/U64 in error messages. Decimal: `expected Decimal, got Float. Hint: use Decimal.from_str("19.99")`. Overflow diagnostics can suggest BigInt.
- **AI/ML:** F32 alongside I32/U64 is consistent pattern. Stdlib Decimal critical — without it, LLMs use Float for money 100% of the time. BigInt niche enough for stdlib, not built-in.

**Q5: UUID classification (5-0 for stdlib UUID, Tier 2)**

- **Systems:** 16-byte `memcmp` beats 36-byte string comparison. Memory: 160MB vs 360MB for 10M rows. Tier 2 is right — no effect handle signature needs UUID.
- **Web/Scripting:** Every web API uses UUIDs. `UUID.random()`, `UUID.parse()`, `.to_str()` is basic web infrastructure. Type safety: `fn get_user(id: UUID)` is self-documenting.
- **PLT:** UUIDs and strings have different algebras. `uuid.concat(other_uuid)` type-checks with Str but produces garbage. Nominal type prevents confusion. Not phantom-typed by version — premature for v1.
- **DevOps:** Parse errors are clear: `UUID.parse("not-a-uuid")` → `Err(ConversionError("invalid UUID format"))`. LSP: `.to_str()`, `.random()`, `.parse()` all discoverable.
- **AI/ML:** `UUID.random()` has excellent training data: Java `UUID.randomUUID()`, Python `uuid.uuid4()`, Go `uuid.New()`. Type safety catches arbitrary string passing. Recommend `.random()` — shortest, avoids version-specific naming.

