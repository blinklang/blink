[< All Decisions](../DECISIONS.md)

# `Void` vs the Unit Type (`()`) — Design Rationale

## The gap (br 6xm4pk)

The spec contradicted itself. §9.1.1 (sections/07) said `Void` "is a special opaque type
valid **only** as a `Ptr` type parameter … cannot be used as a standalone type, function
parameter, or return type outside of `Ptr`", and §9.1.1's E0825 rule says "`Void` has no
value representation." Yet ~90 normative sites across the spec and stdlib used
`Result[Void, E]` and `-> Void` in ordinary value position (test-body `?` elaboration,
`fs.write`/`fs.delete`, Bytes setters, DB writers, `Cleanup`). Separately, `()` (the
0-tuple, §3.8) was documented as the inhabited unit type, and the running compiler
collapsed both spellings onto one tid (`TYPE_VOID`). The deliberation had to (1) resolve
which spelling is the unit type, (2) fix the relationship between `Void` and `()`, and
(3) reconcile all three against the prior 6-0 *Under-determined types* ruling, which had
declared "Void is an ordinary inhabited, encodable type."

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds.

#### Phase A — Independent proposals

Panelists originated a spread of end-states. After mechanical dedupe (Phase A.5) they
collapsed to four, plus a variant that surfaced in debate:

- **A** — both `Void` and `()` legal unit spellings on one tid; fmt may normalize; neither an error.
- **A′** (surfaced by DevOps in Phase B) — `Void` is the canonical *named* unit type; `()` in a unit position is an error-with-fix pointing to `Void`; zero source migration.
- **B** — `()` canonical, `Void` a permanent legal alias forever (no error).
- **C** — `()` is THE unit type; `Void` retired to the FFI-only `Ptr[Void]` marker; non-`Ptr` `Result[Void, E]` / `-> Void` rewritten to `()`; `Void`-as-value is an error-with-fix; generic-at-`()` allowed, generic-at-`Void` rejected; ~92-site mechanical migration.
- **D** — delete `Void` entirely including FFI; replace `Ptr[Void]` with a new opaque mechanism.

Opening leanings: Systems opened on **B** (permanent alias, one tid), PLT on a distinct-kinds
model (`()` : `Type`, `Void` : an `FFITag` kind), AI/ML on a single-spelling error-gated
corpus, Minimalism on **D** (delete the overloaded name), Web on **A**, DevOps on **A**/**A′**.

#### Phase B — Debate highlights

Debate converged hard on **C**. Quoted verbatim, with attribution:

- **PLT (the crux that dismantled B):** *"A kind with exactly ONE inhabitant (`Void`), that never appears in a binder, never generalizes, never composes, and can only sit as `Ptr`'s argument, is not a kind you reify — it is a single **formation rule**: '`Void` is well-formed only as the argument of `Ptr[_]`; everywhere else it is E08xx.' That rule is *observationally identical* to my FFITag story and far cheaper in spec prose and in the checker."*

- **Systems (moving off B → C):** *"B collapses these onto one tid and then needs E0825 to re-separate them at every Ptr op. plt is right: that carve-out IS the kind distinction, hidden under one name and smuggled back as a lint. Option C keeps the two kinds explicit, so E0825 stops being a lint and becomes a soundness consequence."* And, retracting his own Phase A objection: *"My Phase A ODR argument DISSOLVES under C — I'll retract it. … C is 'distinct with DISJOINT legal positions,' which has no such hazard."*

- **Minimalism (conceding D → C):** *"Overload: gone. … Inversion: gone, and in fact REVERSED into a virtue. Under C, `Void` names a no-value-representation FFI pointee … That MATCHES the Haskell/ML 'Void = uninhabited' canon I cited."* And: *"under C, §07:195's 'only as a `Ptr` type parameter' stops being a *policing restriction* and becomes the *definition* of the type. There is no added rule — the confinement IS the type."*

- **AI/ML (rebutting DevOps's IDE argument for A):** *"An LLM does not type-ahead; it emits the whole token. Completability is irrelevant to generation. … `Result<(), E>` is the single most-seen 'fallible-returns-nothing' pattern in the corpus (Rust) — the model emits `()` at high probability regardless of LSP behavior."* On the migration: *"The migration is a **one-time** mechanical cost … The two-spellings corpus is a **permanent, self-reinforcing** cost paid by every future AI-generated Blink program."*

- **Web (moving A → C):** backed C with three conditions — mechanical codemod, crisp §07 FFI wording, and *"explicitly re-spell the 6-0 test-body `?` target to `Result[(), TestError]`."*

- **DevOps (holding A′ as a principled dissent):** *"the self-correcting error is ORTHOGONAL to which spelling is canonical"* — so A′ takes the error mechanism the panel wants **and** the name DevOps judged more legible: *"`Result[Void,E]` vs the paste-error look of `Result[(),E]`"*, at zero migration.

The one live disagreement entering the vote was **A′ vs C** — both error-gated and self-correcting, differing only on which spelling is canonical (and therefore on whether `Void` keeps a value-role, which Systems/PLT argued re-fuses the two kinds and re-opens E0825-as-lint).

#### Phase C — Final vote

**Q1 — Primary resolution (A / A′ / B / C / D): C wins 5-1.**

- **Systems:** C — *"C is the only option whose type-position rules match the actual C backend — `()` is an object type with a representation … `Void` is the incomplete `void` pointee reachable only through `void*`. Every other option fuses those two kinds under one name and needs an E0825 carve-out to separate them again, demoting a soundness rule to a lint."* Concern: the ~92-site migration touches lib/std AND the self-hosting compiler, so a sloppy codemod could break the Gen1/Gen2 bootstrap — must be followed by `task regen` + `task ci`.
- **Web:** C — *"One unit spelling error-gated (not just fmt-converged) is the only option that stops the codebase — explicit training data — from teaching two spellings … `()` carries no false inhabited/uninhabited prior the way `Void` does for JS/TS/Java devs."* Concern: the codemod may miss `Void` spellings fmt can't reach (macro-expanded, generated), leaving hand-fixes that must be caught by `task regen`.
- **PLT:** C — *"only C separates the inhabited unit `()` (honest `Result[(), TestError]` Ok payload) from C's no-value `void*` pointee `Void` (keeps `Ptr[Void].deref()` correctly E0825); A′/B misname the unit or break E0825, D's `Ptr[()]` is `calloc(1, sizeof(void))` — a C violation."* Concern: the rewrite must land as one atomic codemod or a half-migrated corpus leaves both spellings live.
- **AI/ML:** C — *"one surface spelling enforced by a hard error is the dominant factor — it makes the corpus converge and model mistakes self-correct, which A/B forfeit forever. `()` rides the Rust `Result<(), E>` prior … while `Ptr[Void]` preserves the `*mut c_void` prior that D discards."* Concern: if the codemod leaves any residue, the corpus keeps the wrong spelling — migration must be 100%, not 95%.
- **Minimalism:** C — *"C is the only option that deletes the overload rather than preserving two unit spellings. … §07:195 turns from a policing restriction into the type's own definition, so the surviving surface is two non-overlapping concepts with zero special-case rules."* Concern: the rewrite must land as one mechanical codemod in a single regen; a partial migration leaves the exact ambiguity being ended.
- **DevOps:** *(dissent)* A′ — *"A′ delivers the self-correcting error surface … while keeping `Void` as the type canon, which is the only spelling that is autocomplete-completable in type position and reads cleanly in error text … It costs zero migration. The error mechanism the panel wants is orthogonal to canon choice — A′ takes that mechanism AND the better-reading name."* Concern: `Void` carries a semantic-prior that mispredicts inhabitance, so a first-time reader needs one hover/doc hit.

**Q2 — Formulation of C (C-lite formation-rule vs C-formal reified kind): C-lite wins 6-0 (unanimous).**

Every panelist chose the single formation rule over reifying a kind/`FFITag`. Representative reasoning:
- **PLT:** *"a kind whose only inhabitant is `Void`, that never binds, generalizes, or composes, does not earn reification in a language with no user-facing kind system — a single formation rule … is observationally identical and far cheaper in spec prose and checker."*
- **Systems:** *"one hard well-formedness rule … enforces the exact invariant … with a position check rather than a kind system the self-hosting compiler must carry and re-derive for a single one-off marker (YAGNI)."* Concern (shared by DevOps, PLT, Web): it must remain a **hard error**, never softened to a lint, or the soundness guarantee silently evaporates; and a future contributor may miss the prose-only rationale and "relax" the rule.

**Q3 — Ratify reinterpreting the prior 6-0 "Void inhabited/encodable" as "the unit type is `()`; `Void` demoted to the FFI `Ptr[Void]` marker": Yes wins 5-1.**

- **Systems / Web / PLT / AI/ML / Minimalism:** Yes — *"this is a refinement, not a reversal — the prior 6-0 'inhabited/encodable' property transfers cleanly onto `()` … while `Void` is demoted to the representation-less `Ptr[Void]` marker"* (Systems). Shared concern: record it as a **refinement recorded inline beside the original 6-0**, not re-litigation, so the earlier outcome doesn't read as reopenable, and so no future reader cites "Void is inhabited" to justify `Void`-as-value.
- **DevOps:** *(dissent)* No — but **explicitly conditional**: *"A′ keeps `Void` as the ordinary inhabited encodable unit type the panel ratified 6-0 … If C carries Q1, this reinterpretation follows and I'd accept it then; as a standalone ratification against my Q1 vote it is No."* Since C carried Q1, this dissent is self-resolving.

#### Phase D — not triggered

No question resolved closer than 5-1 (Q1 5-1, Q2 6-0, Q3 5-1), so Phase D did not run. The
two 5-1 results are the same DevOps dissent, and its Q3 half is self-resolving once C won Q1.

#### Step 8.5 — AI-First review: 5/5 pass

Learnability (one spelling, one rule), Consistency (`()` is a regular member of the tuple
family; the confinement of `Void` is its definition, not a special case), Generability
(`()` rides the dominant `Result<(), E>` prior), Debuggability (E0828 is a hard,
self-correcting error pointing at `()`), Token Efficiency (`()` is shorter than `Void` and
carries no misprediction cost). 0 criteria fail.

### Final Spec

```blink
// () is THE unit type — inhabited, encodable, "no meaningful value".
fn log(msg: Str) ! IO {          // return type is (), omitted by convention
    io.println(msg)
}

fn save(row: Row) -> Result[(), DBError] ! DB.Write {   // success carries no value
    // ...
    Ok(())
}

let seen: Map[Str, ()] = Map.new()   // set-as-map: () is a legal generic argument

// Void is the FFI-only marker for C's incomplete `void` pointee.
fn raw_sqlite3_close(db: Ptr[Void]) -> Int   // Ptr[Void] == void*  — legal

// Errors:
fn bad() -> Void { }                 // error[E0828]: `Void` used outside `Ptr` — use `()`
let x: Result[Void, E] = ...         // error[E0828]: use `Result[(), E]`
let p: Ptr[Void] = ...
let v = p.deref()                    // error[E0825]: `Void` names no value to read
```

Locked design points:

- **`()` (§3.8) is the unit type** — the inhabited, encodable "no meaningful value" type: one value, a representation, usable as a return, a field, and a generic argument (`Result[(), E]`, `Map[Str, ()]`).
- **`Void` (§9.1.1) is the FFI-only marker** for C's incomplete `void` pointee — well-formed **only** as the argument of `Ptr[_]` (`Ptr[Void]` = `void*`), with no value representation.
- **`Void` in any non-`Ptr` position is `error[VoidOutsidePtr]` (E0828)**, a hard error whose fix points at `()`. Generic-at-`()` allowed; generic-at-`Void` rejected.
- **`Ptr[Void].deref()` / `.write()` stay E0825** — a soundness consequence of `Void` having no value, not a lint.
- **Formulation is a formation rule, not a reified kind** (C-lite): one well-formedness predicate; the two-kinds distinction is rationale prose only.
- **The prior 6-0 *Under-determined types* ruling is refined, not reversed**: the "ordinary inhabited, encodable" unit is `()`, not `Void`. The I0001 codegen backstop still keys on *kind*, never the `"Void"` tag.
- **Migration** is one atomic mechanical codemod of the ~92 non-`Ptr` `Result[Void, E]` / `-> Void` sites (spec sections done; lib/std + `src/` pending implementation), gated by self-host regen + `task ci` — 100%, not 95%.
