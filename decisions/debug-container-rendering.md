[< All Decisions](../DECISIONS.md)

# `@derive(Debug)` Container Field Rendering — Design Rationale

### Problem Statement

`@derive(Debug)` codegen landed in commits `0568445` / `d361f84`. It renders structs, enums, and
scalar / `Str` / user-type fields correctly, but any field whose type is a **container**
(`List[T]` / `Option[T]` / `Map[K,V]`) renders the literal string `"<?>"` — a documented "v1
limitation" pinned by `tests/test_derive_debug.bl`.

Ticket `6977vk` was filed as `type:feature` to "recurse into elements" instead. Investigation
showed this is a **spec gap, not just an implementation gap**: `sections/03_types.md §3.6` defines
the per-field Debug model (`"TypeName { f: {f.debug()} }"`) but (a) never declares `List` / `Option`
/ `Map` as `Debug` implementors and (b) never defines their `debug()` output format. Picking a
format is user-visible language output → `type:spec` → resolved by the 6-expert panel.

Four questions went to the panel:

1. **Q1 — Do `List` / `Option` / `Map` implement `Debug`?** (i.e. render elements, or keep the
   placeholder?)
2. **Q2 — What is the output format** for each container, and in what form do
   elements/keys/values render?
3. **Q3 — What happens when an element / key / value type does not itself implement `Debug`?**
4. **Q4 — How deep does v1 render** — one container level, or fully recursive nesting?

### "Already decided" constraints handed to the panel

1. **Debug trait shape** = `fn debug(self) -> Str` (single pull method, §3.6). Unlike `Display`,
   `Debug` is *not* push-style — it returns a `Str`.
2. **Debug per-field model** = uniform: each field renders via `{field.debug()}`. The spec defines
   struct / enum / scalar leaf forms only.
3. **`Str.debug()`** = quoted + escaped; **`Int` / `Bool` / `Float.debug()`** = bare.
4. **Bounded-depth precedents**: assertion introspection is "one-level bounded depth"; `Clone` is
   "one-level deep, GC pointer copy, no recursion."
5. **`Display` sealed-default precedent**: `final` derived methods to prevent drift.
6. **Built-in trait table** (§3.6) currently does NOT list `List` / `Option` / `Map` as `Debug`
   implementors (only `Bytes` is explicitly listed).
7. **Strict-trait precedent**: interpolation requires `T: Display` — no auto-synthesis, no
   `<?>`-style silent fallback for missing impls (the `Display` panel was 5-0 against
   auto-synthesis / the `[object Object]` lie).

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated:
Phase A independent proposal → Phase A.5 mechanical dedupe → Phase C silent ballot → Phase D
focused re-debate on the single tied question (Q4).

#### Phase A — Independent proposals

> **Archival note.** The Phase A proposal workflow's full output (≈58 KB) rotated out of the
> session scratch directory before this record was written; only the leading portion survived
> verbatim. The **systems** proposal survived in full and is quoted verbatim below. The remaining
> five panelists' Phase-A proposals are not recoverable verbatim — but every one of them is
> represented verbatim in the Phase C ballot (below) and, for Q4, the Phase D re-debate, which
> were preserved in full. No Phase-A text is paraphrased or reconstructed here; absent text is
> marked as such rather than invented.

- **Systems** (verbatim, full):
  - **Q1:** "Yes — List[T], Option[T], and Map[K,V] must implement Debug and render their elements;
    the \"<?>\" placeholder must go. From the SYSTEMS view this is essentially free: the Serialize
    derive already proves the codegen pattern (emit_list_serialize at codegen_derive.bl:378 walks
    blink_list_len/blink_list_get in an inline monomorphized C for-loop carrying the element kind
    via the type-pool, tp_child1_kind/tp_child1_sname). Debug is the same loop with debug-form leaf
    rendering instead of JSON. Keeping a placeholder would be the \"[object Object]\" silent-fallback
    the panel already voted 5-0 against (constraint 7), so it must be removed."
  - **Q2 (List):** "List[T].debug() = \"[\" + elements joined by \", \" + \"]\", where each element
    is rendered by its OWN debug() (debug-form, not display-form). Separator is comma-space \", \"
    to match the struct field separator already emitted at codegen_derive.bl:537. Example: List[Int]
    {1,2,3} -> \"[1, 2, 3]\"; List[Str] {\"a\",\"b\"} -> [\"a\", \"b\"] (note the inner quotes —
    Str.debug() is quoted+escaped per constraint 3, so it is \"[\\\"a\\\", \\\"b\\\"]\"). The
    generated C is the existing inline for-loop: emit \"[\", then `for (_i...) { if (_i>0) concat
    \", \"; concat <elem>.debug(); }`, then \"]\". Zero extra allocation over the concats already
    present."
  - **Q2 (Option):** "Option[T].debug(): Some renders \"Some(\" + inner.debug() + \")\", None
    renders the bare word \"None\". Examples: Option[Int] Some(42) -> \"Some(42)\"; Option[Str]
    Some(\"hi\") -> \"Some(\\\"hi\\\")\" (renders as Some(\"hi\")); None -> \"None\". This mirrors the
    enum data-variant debug form already specced (\"Variant({f.debug()})\", constraint 2) — Option IS
    an enum, so Some/None is just the existing variant rendering. Codegen: a tag check on the
    monomorphized Option struct (Option is already monomorphized per-T, constraint 8), branch to the
    Some(inner.debug()) concat or the literal \"None\"."
  - **Q2 (Map):** "Map[K,V].debug() = \"{\" + entries joined by \", \" + \"}\", each entry rendered
    \"key.debug(): value.debug()\" — key and value BOTH in debug-form, separated by colon-space
    \": \". Example: Map[Str, Int] {\"a\": 1, \"b\": 2} -> \"{\\\"a\\\": 1, \\\"b\\\": 2}\" i.e.
    renders as {\"a\": 1, \"b\": 2} (string keys are quoted because Str.debug() quotes). Map[Int,
    Bool] {1: true} -> \"{1: true}\". Codegen iterates the monomorphized map (constraint 8) emitting
    an inline loop, prepending \", \" for entries after the first, same shape as the List loop."
  - **Q2 (empty):** "Empty collections render their delimiters with nothing inside (the inline
    for-loop simply iterates zero times — no special-casing in codegen, which is the cheapest
    possible path): empty List -> \"[]\"; empty Map -> \"{}\"; Option None -> \"None\" (None is not
    \"empty\", it is its own variant word). No trailing/leading separators because the `if (_i > 0)`
    guard suppresses the separator on the first iteration."
  - **Q3:** "Reject at typecheck — extend E0520 to recurse into the element/value type.
    tc_debug_field_ok (typecheck.bl:892) currently only checks user struct/enum names and the
    comment at 888-891 explicitly calls container-element non-Debug \"a known v1 limitation\"; that
    hole is exactly this bug. The fix: when a field's type is List/Option/Map, peel to the element
    type (Map peels BOTH K and V) and re-run the same Debug check; raise E0520 pointing at the
    offending element type if it does not derive/implement Debug. SYSTEMS rationale: codegen's
    emit_field_debug invariant (codegen_derive.bl:509-510) already documents \"non-Debug nested
    fields are rejected earlier in typecheck; by codegen the nested debug() always exists.\" Honoring
    that invariant for elements means codegen never has to emit a runtime placeholder or null —
    every leaf is a statically-known monomorphized call. A placeholder would reintroduce the silent
    fallback and force a runtime branch that buys nothing."
  - **Q4 (full recursion):** "Full recursion, not one-level. Each container's element rendering is
    just a call to that element's .debug(), and List[List[Int]] means the inner element type is
    itself List[Int] whose debug() is generated by the same rule — recursion falls out for free with
    no depth counter, no placeholder, no extra codegen path. This differs from the Clone/assertion
    bounded-depth precedents (constraint 5) for a concrete SYSTEMS reason: those bound depth to avoid
    unbounded RECURSIVE TRAVERSAL cost or pointer-chasing on cyclic/large graphs at runtime; Debug
    rendering already pays a full O(n) string-concat walk of the data either way, and Blink's value
    types here (List/Option/Map of value elements) are acyclic by construction, so there is no
    runaway to bound. The E0520 recursion in Q3 is what statically guarantees every nested element
    has a debug() to call, so unbounded structural nesting is sound. Examples that must render fully:
    List[List[Int]] {{1,2},{3}} -> \"[[1, 2], [3]]\"; Option[List[Int]] Some([1]) -> \"Some([1])\";
    Map[Str, List[Int]] {\"a\":[1,2]} -> \"{\\\"a\\\": [1, 2]}\"."
  - **Cross-language:** "Rust's #[derive(Debug)] is the direct analog: Vec<T>, Option<T>, and
    HashMap<K,V> all impl Debug iff their element/key/value types impl Debug (a where-bound the
    compiler enforces at type-check, exactly the E0520-recursion in Q3 — no placeholder, hard error),
    and they render fully-recursively. Rust formats Vec as [a, b], Option as Some(x)/None, and Map as
    {k: v} — element-wise via {:?} (debug form), which is precisely the output I specced; I
    deliberately matched Rust's bracket/colon conventions. Python's repr() likewise recurses (list
    repr calls repr on elements, dict shows {k!r: v!r}) and quotes string elements inside containers
    even though str at top level is bare — the same quoted-inside / debug-form distinction Blink's
    Str.debug() already encodes. Go's %#v is the same idea with more type noise. Across all three,
    the universal rule is \"container Debug == recurse with the element's Debug, gated by the element
    being Debug\" — there is no precedent in any of these languages for a runtime placeholder, which
    confirms removing \"<?>\"."

- **Web/Scripting** (verbatim fragment — only the opening of the proposal survived the scratch
  rotation): "YES — List[T], Option[T], and Map[K,V] must implement Debug (conditionally, on their
  element/value types deriving Debug), and the built-in trait table in §3.6 must be amended to list
  them. Keeping containers as a \"<?>\" placeholder is the single most damaging option for the 90%
  use case: the entire reason a JS/Python dev reaches for debug/repr is to dump a struct mid-bug,
  and a struct full of \"<?>\" tells you nothing about the actual data. Every Python `repr`, Rust
  `{:?}`, and `JSON.stringify` recurses into collections — a dev who …" *(remainder not recoverable;
  Web's full Q1–Q4 position is preserved verbatim in the Phase C ballot and Phase D re-debate
  below.)*

- **PLT / DevOps / AI/ML / Minimalism:** Phase-A proposals not recoverable verbatim (scratch
  rotation). Their positions are recorded verbatim in Phase C (all questions) and Phase D (Q4).

#### Phase A.5 — Mechanical dedupe

Q1, Q2, and Q3 collapsed to a single shared primary with no live disagreement: render elements
(drop `<?>`); `List` `[a, b]` / `Option` `Some(x)`·`None` / `Map` `{k: v}` with debug-form
elements, keys, and values and empties `[]` / `{}` / `None`; reject a non-Debug element / key /
value by extending **E0520** to recurse into the inner type(s). The only live split was **Q4**
(nesting depth), which went to the ballot.

#### Phase C — Final vote

- **Q1 — Do `List` / `Option` / `Map` implement `Debug`? (6-0 YES, render elements, drop `<?>`):**
  All six panelists independently voted to render elements and remove the placeholder, and to add
  the three container rows (each conditional on element/key/value `Debug`) to the §3.6 trait
  surface. The load-bearing argument, shared across the panel, is constraint 7: keeping `<?>` is
  the same silent fallback (`[object Object]` / auto-synthesis) the `Display` panel already
  rejected 5-0 — a struct dump full of `<?>` "tells you nothing about the actual data."

- **Q2 — Output format (6-0, independent convergence on the identical format):** All six
  panelists independently converged on the same format:
  - **List:** `[a, b, c]` — bracket-delimited, `, ` separator, **debug-form** elements (so
    `List[Str]` → `["a", "b"]` with quotes).
  - **Option:** `Some(x)` / `None` — `None` bare (no parens), inner in debug-form.
  - **Map:** `{k: v}` — brace-delimited, `, ` between entries, `: ` between key and value, both in
    debug-form.
  - **Empty:** `[]`, `{}`, `None` — no inner padding.

- **Q3 — Non-Debug element / key / value type (6-0 REJECT, no placeholder):** Extend **E0520** to
  peel the container and recurse on the element type — and on **both** `K` and `V` for `Map` —
  raising E0520 naming the offending inner type. A placeholder for the non-Debug case was rejected
  for the same reason as Q1: it would relocate the banned silent fallback one level down.

- **Q4 — Nesting depth (3-3 TIE → Phase D):** A genuine 3-3 split. **Full recursion** —
  systems, web, AI/ML. **One container level for v1** (hard E0520 at depth+1) — PLT, DevOps,
  minimalism. The split was **ship-scope, not soundness** — every panelist agreed on the facts:
  - Full recursion is the correct theoretical **end-state**.
  - The current `emit_list_serialize` machinery is genuinely **one-level**; full recursion requires
    new codegen (promoting container rendering to real monomorphized `debug()` symbols). Even the
    "full" voters (systems, AI/ML) flagged this as "real work, not free."
  - Whatever the v1 cap, deeper nesting must be a **hard E0520 error, never a silent placeholder**.

  The tie triggered a focused Phase D re-debate on Q4 only.

#### Phase D — Q4 re-debate + re-vote

Each panelist reacted to the opposing camp's strongest point, then re-voted on Q4 alone. The
reactions and re-votes survived in full; quoted verbatim.

**Reactions:**

- **Systems** *(holds FULL)*: "The strongest opposing point is MIN/PLT's verified fact: there is no
  composable per-value container `debug()` symbol today — `emit_list_serialize` is inline and
  one-level, so \"free recursion\" is a fiction, and full recursion means standing up the
  `blink_promote_{mangle}` per-monomorphization emitter as genuinely new machinery. That's correct,
  and I flagged it myself, so I won't pretend the cost away. But here's the systems-cost asymmetry
  that moves me to **hold FULL**: the one-level path isn't actually cheaper — it just front-loads a
  *throwaway* E0520 depth-check that we must then rip out and replace when the follow-up lands, and
  a depth-aware rejection in typecheck is itself non-trivial wiring against the same one-level
  type-pool the opposing camp says is the blocker. We pay for the descriptor-threading either way;
  one-level makes us pay *twice* (build the gate, then build the emitter, then delete the gate). …
  I'll move only if someone shows the E0520 depth-gate is materially cheaper to build than the
  descriptor-mangled emitter; absent that, full is the lower *total* cost."

- **Web/Scripting** *(flips FULL → ONE-LEVEL)*: "One-level holds. The opposing camp's strongest
  point is WEB's \"bug-at-depth+1\" trap — that `Map[Str, List[Int]]` rendering `{\"a\": <?>}`
  recreates the exact failure one layer down. That lands, and it's precisely why I won't accept a
  placeholder — but the answer to a silent-degradation trap is a LOUD compile error, not building a
  whole new monomorphized debug() emitter under v1 schedule pressure. A hard E0520 at depth+1 makes
  the boundary honest and visible at compile time (you literally cannot ship `{\"a\": <?>}`), which
  neutralizes WEB's trap without committing us to promote container rendering into per-monomorphization
  symbols plus a recursive descriptor — verified-real new machinery, not the \"free composition\"
  three votes leaned on. Ship one-level + hard E0520 now, file the recursive-emitter follow-up
  ticket, and let the inductive end-state land when it's built right rather than rushed into v1;
  subtraction first, expansion when earned."

- **PLT** *(holds ONE-LEVEL)*: "I hold one-level. The opposing camp's strongest point is AIML's
  \"lowest-decision-point\" argument: a single inductive rule has no depth carve-out for a model or
  human to get wrong. I concede that is the cleaner *typing* story — but it conflates the typecheck
  rule with the codegen mechanism, and only the typecheck side is actually inductive today. Per Q3,
  the typechecker already recurses to statically guarantee every nested `debug()` symbol's *type* is
  valid; what does not exist is the *emitter* that materializes those symbols — `inner_desc_of`
  peels exactly one descriptor level (codegen_derive.bl:1318) and the flat `tp_child1_kind` carries
  no grandchild id. So the honest v1 is: keep the full inductive typecheck rule, cap the *emitter*
  at one level, and reject depth+1 with a hard E0520 — which is itself a single, total, non-silent
  rule, not the \"when-does-rendering-stop carve-out\" AIML fears, because there is no placeholder
  branch to get wrong. … PLT vote: ONE-LEVEL."

- **DevOps/tooling** *(holds ONE-LEVEL)*: "The full-recursion camp's strongest point is AIML's: full
  recursion is the lowest-decision-point rule, and a one-level cap plus boundary is itself a \"when
  does rendering stop\" carve-out that's a source of confident-but-wrong codegen. That's a real
  concern — but it cuts the opposite way once you look at what ships. The one-level + E0520 path
  makes the boundary a *typecheck-time* fact the user sees as a hard compile error, not a runtime
  rendering carve-out the codegen can silently fudge; the failure mode AIML fears (confident-but-wrong
  output) is exactly what E0520 forecloses. From a diagnostics-surface standpoint, a sharp \"E0520:
  nested container Debug not supported in v1, tracked in <ticket>\" is a *better* developer experience
  for v1 than a half-built recursive emitter that the panel itself flags may need the
  descriptor-mangled debug() rewrite (codegen_derive.bl:1338+) to actually deliver — shipping that
  under time pressure is how you get the silent \"null\"-at-depth+1 regression that emit_list_serialize
  already demonstrates. I hold ONE-LEVEL …"

- **AI/ML** *(flips FULL → ONE-LEVEL)*: "I hold ONE-LEVEL. The opposing camp's strongest point is
  AIML's \"lowest-decision-point\" framing — the single rule \"render every element all the way
  down\" has no carve-out for a model to get wrong, whereas a cap is a stopping-condition exception.
  That's real, but it cuts the other way on ship-scope: the decision point doesn't disappear with
  full recursion, it moves into the descriptor-mangled `debug()` emitter that SYS, WEB, and AIML all
  concede v1 doesn't have yet — promoting flat `tp_child1_kind` to recursive monomorphized symbols
  (codegen_derive.bl:1338+) is a new mechanism whose correctness can't be regen-verified for codegen
  bugs, so a wrong nested `debug()` symbol is exactly the confident-but-wrong output AIML wants to
  avoid, just relocated to where it's harder to catch. The honest move is one-level now with a hard
  E0520 at depth+1: a statically-checked sharp boundary the typechecker enforces today (the Q3
  recursion already proves the depth, so it can equally reject the depth) plus a follow-up ticket
  for the recursive emitter …"

- **Minimalism** *(holds ONE-LEVEL)*: "ONE-LEVEL holds. The full camp's strongest point is AIML's
  \"lowest-decision-point\" framing — one rule, no carve-out for a model to misgenerate — and I
  concede it is the cleaner invariant in the abstract. But it conflates the typing rule with the
  codegen surface: a hard E0520 at depth+1 is itself a single, statically-decidable rule with zero
  placeholder ambiguity, so the no-silent-fallback invariant is fully preserved without building the
  per-monomorphization debug() emitter now. The honest subtraction math: full recursion ships a new
  recursive descriptor plus monomorphized debug() symbols (verified-real machinery, since
  emit_list_serialize falls back to 'null' at depth+1 today), whereas one-level ships an error-emit
  at a boundary we already detect — strictly less surface for v1. … YAGNI: build the emitter when
  the ticket is pulled, not on speculation."

**Re-votes (Q4):**

- **Systems → FULL** *(dissent)*: "The one-level camp's cost argument rests on the recursive
  per-monomorphization debug() emitter being unverifiable new machinery, but codegen_derive.bl:1338+
  already ships exactly that pattern: blink_promote_list recurses via
  emit_promote_elem_into(inner_desc_of(desc)) and emits composing blink_promote_{mangle} symbols
  over the same depth-carrying descriptor strings (L:/M:K|V/O:/S:), and it's regen-stable today. So
  the debug emitter mirrors a proven shape rather than inventing one, which materially lowers the
  FULL cost the opposing camp priced as substantial. … one-level forces us to build a throwaway
  E0520 depth-gate against the same one-level type-pool, then build the emitter anyway, then delete
  the gate — paying for descriptor threading twice."
  - *Concern (recorded):* "If the debug emitter diverges from the promote pattern in ways regen
    can't catch (codegen correctness isn't self-host-verified), a wrong nested debug() symbol ships
    as confident-but-wrong output, so FULL must land with dedicated nested-container tests, not lean
    on regen."

- **Web/Scripting → ONE-LEVEL** *(flipped)*: "My Phase C trap — that nested containers re-create the
  silent-degradation bug one layer down — is fully answered by a hard E0520 at depth+1, not by
  building the recursive emitter under v1 schedule pressure; a loud compile error is the DX-correct
  boundary for a JS/Python migrant … SYS's \"pay twice\" point is the one genuine pull toward FULL,
  but PLT's split holds: the inductive typecheck rule is kept and only the emitter is capped, so the
  gate isn't throwaway."
  - *Concern:* "If the recursive-emitter follow-up ticket gets deprioritized, users hitting E0520 on
    common shapes like Map[Str, List[Int]] are stuck with no debug output for an extended period,
    which erodes the very DX the cap was meant to protect."

- **PLT → ONE-LEVEL**: "The soundness invariant lives in the typecheck rule, not the emitter, and
  that rule is already fully inductive per Q3 — the typechecker recurses to prove every nested
  element's type is Debug, so it can equally reject depth+1 as a hard E0520. What v1 lacks is purely
  the codegen artifact: inner_desc_of peels exactly one descriptor level (codegen_derive.bl:1318)
  and the flat tp_child1_kind carries no grandchild id … Against SYS's \"pay twice\" objection: the
  typecheck depth-gate is not throwaway because it is the permanent end-state typecheck rule with a
  relaxed cap, and a regen pass cannot verify the new emitter's codegen correctness, so rushing it on
  a 3-3 tie risks the confident-but-wrong nested debug() symbol rather than catching it."
  - *Concern:* "A user who nests Map[Str, List[Int]] hits a hard compile error for a case they
    reasonably expect to work, so the follow-up recursive-emitter ticket must be promptly prioritized
    or the E0520 boundary becomes a lingering papercut rather than a temporary cap."

- **DevOps → ONE-LEVEL**: "Verified in codegen_derive.bl that the default emit path falls back to
  placeholder rendering at the container boundary and the recursive per-monomorphization promoter is
  genuinely new machinery, so full means shipping unverifiable codegen on a 3-3 tie. The E0520
  typecheck recursion that proves nested debug validity already exists, so a hard depth+1 error is
  cheap and reuses it. A sharp compile error with a ticket reference is a better v1 developer
  experience than a rushed emitter that can regress to the existing silent fallback, which regen
  cannot catch."
  - *Concern:* "An imprecisely wired depth+1 E0520 could false-positive on a valid single-level case
    or miss deeper nesting, surfacing as a confusing escape rather than the clean boundary intended."

- **AI/ML → ONE-LEVEL** *(flipped)*: "I verified the agreed facts: emit_list_serialize
  (codegen_derive.bl:378) is flat — tp_child1_kind reads only the immediate child, and a nested
  CT_LIST falls through to the null branch at line 405, so full recursion means wiring debug() into
  the separate recursive blink_promote_{mangle} descriptor walker (1184-1264, 1338+) that does not
  currently feed the serializer. From the AI/ML lens, the decision point I care about does not vanish
  under FULL — it relocates into a new per-monomorphization emitter whose nested debug() symbols
  cannot be regen-verified for codegen correctness … The Q3 typecheck recursion already proves nested
  depth statically, so it can equally reject depth+1 as a hard E0520 today; that ships the
  no-silent-fallback invariant immediately as a single total rule."
  - *Concern:* "A literal E0520 boundary risks teaching models and users that nested-container Debug
    is permanently unsupported, so the follow-up emitter ticket must be high-priority and the
    diagnostic must name the tracking ticket to keep the cap visibly temporary."

- **Minimalism → ONE-LEVEL**: "The no-silent-fallback invariant is what matters for v1, and a hard
  E0520 at depth+1 delivers it fully without building the descriptor-mangled per-monomorphization
  debug() emitter that SYS, WEB, and AIML all concede does not exist yet. … Against SYS's \"pay
  twice\" argument: the recursive emitter is a regen-unverifiable codegen surface, and rushing it in
  on a tie is precisely how emit_list_serialize's silent-null regression landed; deferring it to a
  ticket with dedicated tests is the lower true cost. YAGNI — build the emitter when a user has
  actually nested a Map[Str, List[Int]] in anger."
  - *Concern:* "If the recursive-emitter follow-up ticket is never prioritized, users hit the E0520
    wall on common shapes like List[List[Int]] and the language looks half-finished for an indefinite
    period."

**Phase D result: Q4 is 5-1 for ONE-LEVEL** (systems dissents, holding full; web and AI/ML flipped
full → one-level after the re-debate). This is a **soft consensus**: the lone dissenter concedes
one-level is acceptable and that full "must land with dedicated nested-container tests, not lean on
regen" — i.e. the dissent is a future-ticket argument, not a blocking objection.

**Verified SYS template hint.** SYS's revote claim that `codegen_derive.bl:1338+` already ships a
recursive `blink_promote_{mangle}` descriptor emitter (`descriptor_mangle` / `inner_desc_of` /
`desc_primary_ct` / `emit_promote_elem_into`, the arena-promotion path) was checked and is
**accurate** — a fully-recursive debug emitter could mirror that proven shape rather than invent one.
This lowers the cost of the deferred end-state, so it is captured as a **template hint on the
follow-up ticket**, not as grounds to overturn the 5-1.

#### Phase 8.5 — AI-First Review

Scored the resolved decision against the five AI-first criteria — all pass (0/5 fail, proceed):

- **Learnability.** The rule is "every field renders via `.debug()`, including containers; format
  matches Rust `{:?}` / Python `repr`." Learnable from spec + the format examples alone; the
  one-level cap is a single stated boundary. Pass.
- **Consistency.** Follows the existing uniform per-field model; the E0520-recurse mirrors how
  direct struct fields are already checked; the bounded-depth cap matches the `Clone` / assertion
  precedents (constraint 4). Pass.
- **Generability.** Output format is fully specified with concrete examples; an AI generating
  `@derive(Debug)` code has no format ambiguity. Pass.
- **Debuggability.** Non-Debug elements and depth+1 both produce a named E0520 (with a tracking-ticket
  reference per the panel) — no silent fallback. Strong self-correction signal. Pass.
- **Token Efficiency.** One annotation per type; no verbose syntax. The only token cost is users
  hitting E0520 on nested shapes needing a workaround — a v1 boundary, not a per-use cost. Pass.

### Final Spec

```blink
@derive(Debug)
type Inventory { items: List[Str], count: Option[Int], tags: Map[Str, Int] }

let tags: Map[Str, Int] = Map()
tags["rare"] = 1
let inv = Inventory { items: ["sword", "shield"], count: Some(2), tags: tags }
inv.debug()
// => "Inventory { items: [\"sword\", \"shield\"], count: Some(2), tags: {\"rare\": 1} }"
```

*(Note: the panel's resolved-spec snippet wrote the map field as `tags: { "rare": 1 }`; Blink has
no brace map literal — `Map()` is the constructor, NOT `{}` — so the example is corrected to use
`Map()` + index assignment. The rendered `debug()` output is unchanged.)*

Locked design points:

- **Conditional (constrained) Debug instances.** `List[T]`, `Option[T]`, and `Map[K,V]` implement
  `Debug` — but conditionally: `Debug[List[T]]` iff `Debug[T]`, `Debug[Option[T]]` iff `Debug[T]`,
  `Debug[Map[K,V]]` iff `Debug[K]` *and* `Debug[V]`. The §3.6 derivable/built-in trait surface gains
  the three rows, each gated on element/key/value `Debug`. The `<?>` placeholder is removed.
- **Output format** (elements / keys / values render in **debug-form** — `Str` quoted + escaped):
  - `List[T].debug()` → `"[" + elems.join(", ") + "]"`, each elem via its own `.debug()`. Empty →
    `"[]"`.
  - `Option[T].debug()` → `"Some(" + inner.debug() + ")"` | `"None"` (None bare, no parens).
  - `Map[K,V].debug()` → `"{" + entries.join(", ") + "}"`, each entry
    `key.debug() + ": " + value.debug()`. Empty → `"{}"`.
  - Separators: `, ` between elements/entries, `: ` between map key and value. No inner padding.
- **Non-Debug element / key / value → E0520, no placeholder.** A container field is Debug-renderable
  iff its type argument(s) are `Debug`; otherwise **E0520** names the offending inner type. `Map`
  requires **both** `K` and `V`. The placeholder is never reintroduced for this case — that would
  relocate the banned silent fallback one level down.
- **One container level for v1.** Nested containers (`List[List[T]]`, `Option[List[T]]`,
  `Map[K, List[V]]`, …) are rejected with a **hard E0520 at depth+1** — never a placeholder. The
  message names the v1 limit and the tracking ticket so the cap reads as temporary, not permanent.
- **Full recursion is the deferred end-state.** The soundness / no-silent-fallback invariant lives
  in the **typecheck rule** (already inductive via Q3: the typechecker recurses to prove every nested
  element's type is `Debug`), not in the emitter. The fully-recursive per-monomorphization `debug()`
  emitter is deferred to a follow-up ticket, to land with dedicated nested-container codegen tests
  (regen proves self-host stability, not codegen correctness). SYS's template hint: mirror the
  `blink_promote_{mangle}` recursive descriptor emitter (`codegen_derive.bl:1338+`).

### Vote summary

Q1: 6-0 (List/Option/Map implement Debug, render elements, drop `<?>`). Q2: 6-0 (format —
independent convergence on the identical `[a, b]` / `Some(x)`·`None` / `{k: v}` with debug-form
elements/keys/values and empties `[]`/`{}`/`None`). Q3: 6-0 (reject non-Debug element/key/value via
extended E0520; no placeholder). Q4: 3-3 R1 → **5-1 R2 for one-level** (systems dissent, holding
full; web and AI/ML flipped after the Phase D re-debate). Soft consensus on Q4: the dissenter agrees
one-level is acceptable and that full must land with dedicated tests. AI-First Review: 0/5 fail,
proceed.
