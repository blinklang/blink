[< All Decisions](../DECISIONS.md)

# `Char` Debug-Form — Design Rationale

### Problem Statement

`sections/03_types.md` (§3.6) specifies the scalar leaf forms of `Debug`: `Str` is quoted+escaped,
`Int`/`Bool`/`Float` are bare. The built-in trait table (`:1832`) lists `Char` as a `Debug`
implementor (`Y`) — but the *Debug vs Display* table had **no `Char` row**, so `Char.debug()` was
undefined in the spec while being required to produce *something*.

The current compiler renders a `Char` as its **bare decimal code point** everywhere in derived
`Debug` — a `Char` field holding `'a'` renders `97`, a `List[Char]` element `'x'` renders `120`.
This is not a designed form: `Char` (`CT_CHAR`) is included in `is_hash_scalar_ct`
(`src/codegen_types.bl:4435`), so every derive path in `src/codegen_derive.bl` that hits that bucket
emits `int_to_str(...)`. `Char` fell through the numeric-scalar branch by accident.

The gap surfaced while implementing ticket **4dbjfr** (support `Map[Char, Int]` keys in derived
`Debug`): a map key must render in debug-form via the same shared element check as values, but the
debug-form of a `Char` was undefined. The question generalizes to `Char`'s debug-form language-wide
(struct field, list element, option inner, map key, and a bare `someChar.debug()` — all must agree).
Picking the form is user-visible language output → `type:spec` → 6-expert panel.

Two questions went to the panel:

1. **Q1 — What is `Char`'s debug-form?**
2. **Q2 — How is a non-printable scalar outside the ratified escape set (e.g. `U+0007` BEL)
   rendered in v1?**

### "Already decided" constraints handed to the panel

1. **Container Debug rendering (panel 6-0):** debug-form elements/keys/values; `Str` quoted+escaped,
   `Int`/`Bool`/`Float` bare. `Char` was never specified here — that omission *is* this gap.
2. **Debug trait shape:** `fn debug(self) -> Str` — a pull method returning a `Str`.
3. **`Debug` = structural developer representation**; `Display` = user-facing; separate traits.
4. **`Char → Str` (panel 5-0):** `From[Char] for Str` + `Char.to_str()`, infallible — a `Char`
   already has a canonical single-character `Str` form.
5. **`Char → Int` (panel 4-1):** `Char.to_int()` + `From[Char] for Int`; PLT dissented — "`Char` is
   not numeric; putting it into the numeric conversion lattice is a false conceptual model."
6. **`Char` literals (panel 4-1):** source syntax is `'x'` with escape set
   `\n \r \t \\ \b \f \0 \'`. `\u{...}`/`\x..` deferred (task 19v5gb); non-ASCII via
   `Char.from_code_point(...)`. Exactly one Unicode scalar value; surrogates invalid.
7. **No silent fallback (panel 5-0):** the `[object Object]`-style lie is banned; `Debug` output
   must be a faithful representation.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated:
Phase A independent proposal → Phase A.5 mechanical dedupe → Phase B open debate → Phase C silent
ballot. Phase D was not triggered (both questions were unanimous).

#### Phase A — Independent proposals

All six independently produced the same option-space; the dedupe collapsed it to: **A** single-quoted
char-literal form, **B** keep `97`, **C** double-quoted (delegate to `Str.debug()`), **D** bare
unquoted char. All six named A as their primary; B/C/D appeared only as rejected alternatives.

- **Systems** (verbatim excerpt): "**A (single-quoted, `'a'`/`'\n'`/`'😀'`, escape set = char-literal
  escapes):** my pick. Faithful, type-distinct, matches Rust and Blink's own Char-is-a-type stance.
  Cost: one small runtime fn + 4 one-line codegen branches, fully monomorphized, ~O(1)/char. Changes
  shipped `97` output — acceptable and cheapest-now since Char-debug is niche and `97` was never
  spec'd." On B: "it's zero-cost but it's a *faithful-representation failure* (constraint #7). The
  debug output of a `Char` is indistinguishable from an `Int` with the same value … Cheap, but wrong."

- **Web/Scripting** (verbatim excerpt): "**Kill the `97`. It is the single most confusing debug
  output a scripting dev can hit.** A Python/JS/Ruby dev who prints a char for debugging expects to
  *see the character*, delimited so they can tell it apart from a string. `97` for `'a'` is an
  outright lie-by-omission … Rust is the decisive precedent — its `char` is the same 'one Unicode
  scalar value' type as Blink's, and its Debug is single-quoted-escaped."

- **PLT** (verbatim excerpt): "Char currently earns *nothing*: `'a'.debug()` == `97` == `(97).debug()`
  … `'a'` collides head-on with `Int` 97. **Two different types with different values, same debug
  string.** That is a non-injective Debug, and it is exactly the numeric-lattice conflation I
  dissented against on the Char→Int vote: rendering Char as `97` *is* treating Char as its integer
  codepoint." Primary Proposal A: "single-quoted, char-literal-escaped … Injective, round-trippable,
  ML/Rust-consensus, parallel to `Str.debug()`, honors 'Char is not numeric.'"

- **DevOps** (verbatim excerpt): "**Migration cost is ~zero:** `rg` across `tests/` finds NO golden
  output asserting Char debug-form as `97`. Every `97` in the suite is a `.to_int()`/`byte_at`
  codepoint assertion … Decisive for my domain: no fixture-migration tax." On the failure-message
  case: "`97`/`98` forces the reader to mentally run an ASCII table to see they had a one-codepoint
  drift `'a'`→`'b'`. Worse, it's ambiguous with `Int` … the spiritual cousin of the banned
  `[object Object]` lie."

- **AI/ML** (verbatim excerpt): "The rule 'quote textual scalars (Str double, Char single), leave
  numeric scalars bare' is ONE rule for all scalars. It actually *removes* the hidden decision 'is
  Char numeric or textual for debug?' … `Holder { c: 97 }` reads as *'an Int field holding 97'* — the
  debug output actively MIS-DIAGNOSES the type. … `97` has essentially no support in the training
  distribution."

- **Minimalism** (verbatim excerpt): "**there is no missing Char rule. There is a missing
  scalar-classification rule, and Char is currently filed under the wrong bucket.** … Char is text. A
  Char is literally 'a Str of length 1' in Blink's own already-decided model (constraint 4). The bug
  is that Char was silently sorted into the Bare family with the integers." On keep-`97` (its own M0,
  tabled then rejected): "It is an accidental bug — a C representation leaking through — that happens
  to compile. The spec should not bless it. Documenting a bug as intent is the most expensive thing a
  minimalist can do."

#### Phase B — Debate highlights

With all six primaries already on A, Phase B narrowed to (a) confirming A over B/C/D and (b) the
Q2 control-char sub-variation: **A-raw** (raw glyph for exotic controls, defer `\u{...}` to 19v5gb)
vs **A-hex** (emit `'\u{N}'` now, output-only).

- **PLT conceded A-hex → A-raw** (verbatim): "I argued A-hex for faithfulness, and I still hold that
  `'\u{7}'` is the theoretically correct injective rendering of a BEL. But the
  lexer-can't-parse-it-yet fact is decisive … A-hex would make Debug **emit a string that is not a
  valid Char literal in the language that produced it.** That breaks the very round-trip property I
  invoked to justify quoting in the first place. … make A-hex a hard dependent of 19v5gb … I'd ask
  the moderator to record that linkage so A-hex isn't lost — it's deferred, not rejected."

- **DevOps refined the round-trip invariant** (verbatim): "So `parse(c.debug()) == c` is unachievable
  for exotic controls under EITHER variant in v1. I over-claimed. The honest reconciliation: **Scope
  the property test to what's ratified.** The correct invariant for v1 is `parse(c.debug()) == c` for
  every Char in the ratified literal set … Exotic controls are simply out of the round-trip contract
  until 19v5gb."

- **Systems / Web / AI/ML / Minimalism all held A + A-raw**, on cost (raw reuses `Str`'s existing
  `json_escape_str` byte pass-through; A-hex adds a hex-format path Char otherwise never needs),
  DX/round-trip ("don't emit a form the lexer can't parse"), and YAGNI ("don't emit a syntax the
  language can't parse, for a case almost nobody hits, ahead of the task that defines that syntax").

#### Phase C — Final vote

- **Q1: `Char` debug-form → A (single-quoted char-literal form)** — **6-0**
  - **Systems:** A — "Char is a uint32_t codepoint at the C level, so the quoted-literal form costs
    nothing at runtime beyond the branch that already dispatches Str-vs-numeric buckets … The 97
    behavior is the accidental fall-through, not a designed contract." Concern: the shared helper must
    be the sole owner of quote-and-escape logic across all sites or the numeric fall-through returns.
  - **Web/Scripting:** A — "Every scripting language a web developer touches … quotes a char/string
    in its debug form so you can tell 97 (the number) from 'a' (the character). … Single quotes match
    Blink's Char-literal syntax, so debug output round-trips back to source." Concern: devs may briefly
    misread `'a'` as a length-1 string; the single-vs-double quote cue is worth teaching.
  - **PLT:** A — "Debug must be injective across the type lattice, and the bare-codepoint form
    `'a'`→`97` collapses `Char 'a'` onto `Int 97` … a single-quoted literal form restores injectivity
    (`'1'` ≠ Int `1`, `'a'` ≠ Str `"a"`) and is self-delimiting." Concern: the escape set must be
    pinned to exactly the ratified Char-literal set so the round-trip property has a decidable boundary.
  - **DevOps:** A — "the only option that stays type-injective in `assert_eq` failure messages … `97`
    reads as an integer and C's `"a"` reads as a one-char Str, both of which send you chasing phantom
    type bugs. … Zero golden-test churn." Concern: failure messages must render Char and Str with
    visibly different quote styles or the distinction gets lost in terminal text.
  - **AI/ML:** A — "the only form learnable from the spec's own quoting rule … without a second
    decision point … It matches the dominant Rust/Python training prior (`'a'` → `'a'`). Bare `97`
    (B) actively mis-teaches every model that Char is an integer." Concern: single-quote escaping must
    be pinned to exactly the ratified set or models over-generalize from Str's escapes.
  - **Minimalism:** A — "the subtractive choice: it deletes a mis-classification (Char smuggled into
    the numeric-scalar bucket) rather than adding a new rule … Keeping `97` (B) would require us to
    permanently document and defend a C-leak that contradicts the 5-0 faithfulness ban and 4-1
    explicit-only Char→Int, which is more standing rule-count, not less." Concern: the reverse-escape
    path is only free if it truly reuses the existing table with zero forked logic.

- **Q2: exotic control chars → A-raw (raw glyph; `'\u{N}'` deferred to 19v5gb)** — **6-0**
  - **Systems:** A-raw — "Reusing Str's existing json_escape_str byte-policy means zero new escaper
    code … Emitting \u{N} output that can't be parsed back (A-hex) creates an asymmetry the compiler
    would carry until 19v5gb." Concern: raw control bytes (e.g. BEL) can mangle terminal rendering.
  - **Web/Scripting:** A-raw — "Output should never claim a syntax the language can't yet parse …
    the classic copy-from-console-into-source failure." Concern: a raw invisible control char between
    quotes is unreadable until 19v5gb.
  - **PLT:** A-raw — "emitting `'\u{N}'` now produces output that does not parse back — a Debug form
    that fails round-trip is a soundness regression … A-raw keeps the round-trip property total over
    the ratified escape set." Concern: A-hex must be recorded as deferred-and-linked to 19v5gb so
    input and output land atomically.
  - **DevOps:** A-raw — "Output that lies about being parseable is worse than output that's plainly a
    raw glyph." Concern: an invisible/terminal-controlling glyph can render as nothing in CI logs.
  - **AI/ML:** A-raw — "A-hex creates a copy-paste trap that is uniquely damaging to AI workflows … a
    model reads `'\u{7}'`, reasonably pastes it into source, and hits a compile error." Concern:
    19v5gb should prioritize the `\u{...}` round-trip rather than lingering indefinitely.
  - **Minimalism:** A-raw — "A-raw adds no machinery — it inherits Str's already-ratified byte
    pass-through policy … A-hex would bolt on a hex-format path Char otherwise never needs." Concern:
    raw control bytes are mildly unfaithful for terminals, but that is 19v5gb's problem to close.

### AI-First Review

Scored 5/5 pass. Learnability: derivable from the table + one paragraph ("textual scalars quoted, Str
double / Char single; numeric bare"). Consistency: mirrors `Str.debug()`, reuses the ratified
Char-literal escape set, removes a mis-classification rather than adding a case. Generability: `'a'`
matches the dominant Rust/Python prior; single principle. Debuggability: `'a'` is type-injective in
`assert_eq` diffs / hover where `97` and `"a"` are not. Token efficiency: 1-char delta, no verbosity.

### Final Spec

```blink
'a'.debug()   // "'a'"
'1'.debug()   // "'1'"      (≠ Int 1 -> "1")
'\n'.debug()  // "'\n'"
'\''.debug()  // "'\''"
'\\'.debug()  // "'\\'"
'😀'.debug()  // "'😀'"     (raw UTF-8 between the quotes)

// flows unchanged into every container position:
@derive(Debug)
type Cell { c: Char }
Cell { c: 'a' }.debug()             // "Cell { c: 'a' }"
// List[Char] ['h', 'i']            -> "['h', 'i']"
// Option[Char] Some('z')           -> "Some('z')"
// Map[Char, Int] {'a': 1}          -> "{'a': 1}"
```

Locked design points:

- `Char.debug()` = the character in **single quotes**, escaping exactly the ratified `Char` literal
  set (`\n \r \t \\ \b \f \0 \'`); every other scalar (printable ASCII + all non-ASCII Unicode
  scalars) emitted as its literal UTF-8 character between the quotes.
- **Changes the current `97`.** The bare-code-point form was an accidental fall-through of `Char`
  into the numeric-scalar bucket, not a designed contract.
- Rationale: **injectivity/faithfulness** — `'a'`≠`97` (not `Int`), `'a'`≠`"a"` (not one-char `Str`);
  consistent with "`Char` is not numeric" (§3c); honors the 5-0 no-silent-fallback ban.
- **Invariant:** `Char.debug()` emits only escapes the lexer already accepts, so `parse(c.debug()) == c`
  for every `c` in the ratified literal set (round-trip).
- **Deferred-and-linked:** a `'\u{N}'` output form for non-printable scalars with no named escape is
  deferred to **task qvan6m (successor to the cancelled 19v5gb)** (which adds `\u{...}` as *input* syntax); input and output escaping land
  together. Until then such a scalar is emitted as its raw byte(s) — faithful, not always legible.
- All positions (struct field, `List[Char]`, `Option[Char]`, `Map[Char, V]` key, bare `.debug()`)
  route through **one shared `Char` debug helper**, so they agree by construction.
