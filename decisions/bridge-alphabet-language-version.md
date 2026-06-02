[< All Decisions](../DECISIONS.md)

# Bridge Alphabet Is a Language-Version Constant — Design Rationale

Resolves spec gap `48y6ra`: "Bridge alphabet expansion must be a language-version change, not an extension point." Follow-up to the PLT Phase C concern on [`buf-u8-runtime-representation`](buf-u8-runtime-representation.md): "if future panels ever make it user-extensible … W0816's source-determinism collapses and we re-enter the W08xx category violation — the panel should treat bridge-alphabet expansion as a *language version* change, never an open extension point."

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds.

#### Phase A — Independent proposals

The six proposals split on one central question: whether to formalize a NEW "language version" concept (in a new section) or harden the existing §9.1.3.2 prose without minting a concept.

- **Systems:** Proposed a new **§8.18 "Language Version"** in `06_tooling.md`, defining language version as a global compiler-binary property orthogonal to per-package editions. "The bridge alphabet must be a **compile-time constant baked into the compiler binary** … where 'third-party CANNOT extend it' is enforced *by the absence of any mechanism*, not by a check that could be bypassed." Stressed additive-only/monotonic growth: "a compiler upgrade can only suppress *more* W0816s, never introduce new ones. `-Werror` builds upgrade safely."

- **Web/Scripting:** Proposed a new "§13" subsection. "language version is the version of the Blink language the compiler implements — it ships *with the compiler*, the user never declares it, never selects it, and it does not appear in any manifest." Mapped it to the JS `node`/ECMAScript split. Core DX move: a self-contained `W0816` whose text says "in this version of Blink," NOT "wait for v2," with a copy-pasteable `scope.alloc_n[T]` fix; a hard rule that "the word 'edition' [must] never appear near the alphabet."

- **PLT:** Proposed a new §8.16.5 defining language version `λ`, the typing rule `BridgeAlpha(λ)`, and the soundness argument. "source-determinism of W0816 holds **iff** the alphabet is a global language-version constant. This is not a style preference; it is the unique parameterization under which the diagnostic is well-defined." Recommended **closed-world-by-absence** over open-world coherence: "provide **no** declaration form for bridge-membership at all … There is nothing to make incoherent because there is no instance-declaration surface." Proposed a belt-and-suspenders `E08xx`.

- **DevOps/Tooling:** Proposed **NO new section** — anchor in §9.1.3.2, reuse the existing `blink --version` `(compiler, stdlib)` split as the formal surface. "Don't create a §13 'language versioning' section … inventing one risks blurring into editions." Rejected any new error code: "I'd reject any proposal that adds an `E08xx` … the whole point is there's nothing there to gate." Proposed `blink --version --json` gains `bridge_alphabet: ["U8"]` — "single source of truth, so the reported set can never drift from the set the typechecker enforces."

- **AI/ML:** "do NOT introduce a third versioning concept." Argued the alphabet was never edition-eligible (editions can't touch cross-package type-system semantics, §8.16.1), so the gap resolves "WITHOUT a third concept." Proposed an `llms.txt` `language:` stanza (`bridge_alphabet: [U8]`, `bridge_alphabet_extensible: false`, `bridge_diag: W0816`) so a tool generating `@ffi.fn` bindings "knows without trial-and-error that only `Buf[U8]` is legal." Flagged: "I'd score a 'language version distinct from edition' as a FAIL on learnability."

- **Minimalism:** "REJECT the 'new language-version concept' framing. This is a one-line prose hardening of existing §9.1.3.2 … Net language-surface delta: zero." On guarantee (3): "You cannot extend what has no extension point … Adding an *enforcement mechanism* … would require first *inventing the extension syntax* so there's something to reject — that is the C++-committee anti-pattern." On guarantee (1): "Minting a formal 'language version' entity … to hold a single closed set `{U8}` is sugar, not foundation."

#### Phase A.5 — Mechanical dedupe

Two distinct options on the central question (Q1): **Option A** (new formal "language version" concept + new section — sys/web/plt) vs **Option B** (no new concept; harden §9.1.3.2 prose + §8.16.1 back-reference — devops/aiml/min). Flagged sub-questions: **Q2** new error code `E08xx` (plt yes; devops/min no); **Q3** machine-queryable surface (`--version --json` field vs `llms.txt` stanza — compatible or competing?).

#### Phase B — Debate highlights

Phase B ran one round and converged. The major position shifts — all three Option-A proponents migrated to Option B:

- **Web (A→B):** "I revise from Option A toward Option B … On reflection, a NEW formal 'language version' concept *hurts* that DX goal more than it helps … Option B's framing — 'language version is just the compiler/spec revision `blink --version` already prints' — maps onto knowledge they have, and costs zero new concepts." Kept three conditions: mandatory naming-guard sentence in §8.16.1, the self-contained `W0816` text, one canonical `blink doc bytes-bridge` anchor.

- **Systems (A→B):** "I am revising off pure Option A toward a hybrid that lands closer to Option B. The Option-B objection is correct and I was over-building … I withdraw my §8.18 placement." Standing constraint (carried into the vote): "the alphabet check must remain a non-gating coverage check — `Buf[T]` type-checks for all T, the alphabet only decides W0816."

- **PLT (A→B, concedes E08xx):** "I am moving substantially toward the Option-B camp … my Phase A claim that §8.16.5 is *necessary* was too strong — I withdraw 'load-bearing.'" The proof needs only two negatives, **both already in the spec**: not edition-keyed (§8.16.1) and not stdlib-keyed (§9.1.3.2). One refinement kept: "§9.1.3.2 must include a single sentence that *pins the referent* of 'language version'." On Q2: **"I CONCEDE. Drop it."** — "an error code is a *typing/elaboration rule*, and a rule presupposes a syntactic form it rejects … 'No mechanism' is the stronger guarantee precisely because it requires no mechanism."

- **DevOps:** accepted a *named* axis "IF it's named, not *sectioned*. There's a difference … We need one definitional sentence wherever the editions axis is already defined (§8.16.1), establishing the dual." On Q2, sharpened the tooling case: "the moment it's in the error-code registry, `blink explain`… LSP quick-fix tables, and the llms.txt error catalog all have to carry an entry describing a non-existent feature … AI agents trained on the error catalog will infer the extension syntax *exists* and hallucinate it."

- **AI/ML:** held Option B, sharpened by the moderator fact: "putting a 'global cross-package axis distinct from editions' *inside 06_tooling.md right next to the editions machinery* … is the single worst place for an AI to learn a NOT-edition concept, because adjacency in the spec is itself training signal." Accepted naming the axis inline once defined as the existing `blink --version` revision.

- **Minimalism:** "B+inline-rule captures everything A's proponents actually need (formal soundness, a defined λ, hardened guarantees) minus the new section — so it should be the compromise, not a 3-3 stalemate." On Q3: "devops's JSON field is genuinely justified and is NOT scope creep, because it adds zero language surface — it surfaces an *already-existing* compiler constant … through an *already-existing* command."

Q3 resolved as compatible-not-competing: both surfaces are projections of one compiler constant, asserted equal to the typechecker's table by a build-time test.

#### Phase C — Final vote

**Q1 — Constraint home & form: Option B (prose in §9.1.3.2 + §8.16.1 inline-named back-reference, no new section).** (6-0, R2 after 3-3 R1 A/B split resolved in debate)

- **Systems:** B, named-inline — "A new versioning concept buys zero codegen and zero ABI change … But the §8.16.1 back-reference must NAME the property … because a reader of the editions section otherwise concludes editions are the whole versioning story and the cross-package invariant is invisible at the exact site where someone would look to extend it." *Concern:* prose-only risks the guarantees rotting if a future edit touches the bridge section without re-reading §8.16.1; the inline naming keeps the two sites cross-linked.
- **Web:** B, named-inline — "Naming the axis inline … is worth the one extra noun because the confusion being defused is literally 'can my edition change this?' — disambiguation-by-contrast alone leaves the dev to infer the answer, and inferred answers become Stack Overflow questions." *Concern:* the §8.16.1 sentence must state plainly the user never declares or selects the language version.
- **PLT:** B, named-inline — "The soundness obligation closes on two negatives already in the spec … so no new formal concept is load-bearing; prose suffices. I vote named-inline rather than contrast-only because the failure mode this task exists to prevent is a reader conflating 'language version' with 'edition' — and a phrase is only safely disambiguated when its referent is named." *Concern:* if the pin-the-referent sentence is dropped, "language version" reverts to a dangling phrase and loses its anchor.
- **DevOps:** B — "naming the 'language version' axis inline gives the spec its referent without minting a section that future authors would treat as a bucket for more global invariants. `blink --version` already physically reports the axis, so the concept is described, not invented. Blast radius stays one constant." *Concern:* §8.16.1 and §9.1.3.2 must cross-link explicitly.
- **AI/ML:** B, named-inline — "B keeps the versioning surface an AI must reason about at its current count … adding no fourth axis … a named axis pinned to an existing one is more learnable than an unnamed 'this is what editions are NOT.'" *Concern:* the §8.16.1 sentence must pin "language version" to `blink --version` in the same breath it names it.
- **Minimalism:** B, named-inline — "The constraint's only referent in the entire spec is the bridge alphabet itself, so a standalone versioning concept would be circular surface with no second use site … Naming the rule inline (λ = the spec/compiler revision) discharges the soundness obligation in place without paying for a new section." *Concern:* the §8.16.1 back-reference must explicitly say it is NOT a third axis.

**Q2 — New `E08xx` error code for a hypothetical extension-syntax attempt: NO.** (6-0)

- **Systems:** NO — "A reserved error code for misusing extension syntax presupposes the extension syntax exists — it would be unreachable dead code … dead diagnostics are untestable and rot."
- **Web:** NO — "An error code for a non-existent extension syntax teaches readers that a lockable door exists; 'no mechanism' is both the stronger guarantee and the more learnable one."
- **PLT:** NO — "specifying E08xx would require writing a bridge-membership extension production into the grammar just to forbid it. 'No such production exists' is strictly stronger." *Concern:* G2's wording should cover "introducing any bridge-membership declaration form" as itself a language-version change.
- **DevOps:** NO — "the code would document a non-existent feature in the explain/LSP/llms.txt catalogs and risk agents hallucinating that the syntax exists." *Concern:* leave a one-line note in DECISIONS.md that NO code was reserved deliberately.
- **AI/ML:** NO — "A documented error code for extending the alphabet would surface in the llms.txt diagnostic table and lead an AI to infer an extension syntax exists — the precise hallucination we are preventing."
- **Minimalism:** NO — "Pre-reserving a code for a syntax we are simultaneously committing never to add is dead surface that subtly signals 'an extension point is expected someday,' undercutting the by-construction guarantee."

**Q3 — Machine-queryable surface: BOTH, derived from one compiler constant.** (6-0)

- **Systems:** BOTH — "`blink --version --json` … is the CI-load-bearing surface … The llms.txt stanza is the agent-facing renderer of the same fact; both MUST derive from the single typechecker constant that drives W0816, never a hand-maintained list, or the assertion becomes a lie." *Concern:* enforce single-source with a test asserting `--json` equals the typechecker's table.
- **Web:** BOTH — "they serve different consumers … sourcing both from the single W0816 constant means no drift risk." *Concern:* the single-source wiring must be enforced in code, not just intended.
- **PLT:** BOTH — "both … must be projections of that same constant so they cannot drift from the predicate that actually fires. `--version --json` is the normative surface CI asserts against for `-Werror` reproducibility; llms.txt is a derived training-data view."
- **DevOps:** BOTH — "two consumers, two projections, both derived from the single in-compiler constant W0816 reads, with `bridge_alphabet_extensible: false` on both making G3 machine-readable." *Concern:* the build-time equality test is load-bearing; without it "one constant" is a convention, not an invariant.
- **AI/ML:** BOTH — "Both projecting the one compiler constant that drives W0816 guarantees the docs can never contradict compiler behavior — the worst training-data failure mode." *Concern:* a test must assert both surfaces equal the typechecker's table.
- **Minimalism:** BOTH — "both still add zero language surface — they project an already-existing compiler constant through already-existing channels … The single-constant derivation is non-negotiable." *Concern:* if either surface is ever hand-edited instead of generated, it becomes a drift vector worse than no surface.

#### Phase D — Round 2

Not triggered. All three questions resolved 6-0 in Phase C (Q1 reached 6-0 in debate before the silent vote; no question was closer than 6-0 at the ballot).

### Final Spec

```blink
// Legal — U8 is in the v1 bridge alphabet, no diagnostic:
@ffi.fn("c", "read")
fn libc_read(fd: I32, buf: Buf[U8], cap: I64) -> I64

// W0816 — I32 is outside the alphabet; non-gating (this still type-checks),
// the diagnostic is self-contained and edition-invariant:
@ffi.fn("c", "memcpy_i32")
fn memcpy_i32(dst: Buf[I32], src: Buf[I32], n: I64)
// W0816: Buf[i32] declared in @ffi.fn signature; only Buf[U8] crosses the
//        byte bridge in this version of Blink. The bridge alphabet is fixed
//        by the compiler version and cannot be extended by a package, stdlib
//        helper, edition, or build flag. For a typed scope-tied region use
//        `scope.alloc_n[i32](n)` instead. See `blink doc bytes-bridge`.

// There is NO syntax to add to the alphabet — closed by construction (G3):
//   @bridge_alphabet(I32)   // no such attribute
//   bridge T = I32          // no such keyword
// The only way I32 ever joins the alphabet is a spec amendment (G2).
// The typed-region path is the working answer indefinitely:
fn fill[T](scope: FfiScope, n: I64) -> Buf[T] {
    scope.alloc_n[T](n)
}
```

Locked design points:

- **No new versioning axis, no new section.** Three guarantees hardened as prose in §9.1.3.2; the language-version/edition dual named inline in §8.16.1.
- **"Language version"** = the compiler/spec revision reported by `blink --version`, NOT the per-package `edition` (§8.16.1) and NOT package semver. Not a knob — it is which `blink` binary you run.
- **G1** — `BridgeAlpha(λ)` is a function of language version alone (no edition/stdlib/flag/env/link-time input); this is what makes `W0816` source-deterministic.
- **G2** — expansion = panel deliberation + `DECISIONS.md` + version bump; monotonically non-shrinking (conservative extension; `W0816` can only ever narrow on upgrade).
- **G3** — no third-party/stdlib/edition/link-time extension; closed **by construction** (no extension syntax exists). No `E08xx` reserved.
- **Non-gating** — `Buf[T]` type-checks for every `T`; the alphabet decides only `W0816` firing, never instantiation.
- **One constant, three projections** — `blink --version --json` (`bridge_alphabet`, `bridge_alphabet_extensible: false`; normative, CI-assertable), `llms.txt` `language:` stanza (derived), and `W0816` firing — all projections of one compiler constant, asserted equal by a build-time test.
- **W0816 text** — self-contained, "in this version of Blink" (never "wait for v2"), deep-links the single `blink doc bytes-bridge` anchor (shared with `E0822`).

#### iff-rationale (PLT, recorded per Phase B request)

`W0816`'s required property is that its firing be a pure function of `(source, language version)`. The firing predicate is `T ∉ BridgeAlpha(λ)`; determinism holds **iff** `BridgeAlpha` has no free parameter beyond `λ`:

- **Edition-keying fails** — editions are per-package; a `Buf[T]` flowing across a package boundary would have two alphabet memberships at the two ends, making the bridge typing rule non-confluent across the edge (breaks subject-reduction for any bridge value crossing a package boundary). This is the cross-package incoherence §8.16.1 forbids.
- **Stdlib-keying fails** — `BridgeAlpha(λ, stdlibVer)` means two CI runs with identical `(source, λ)` but different resolved stdlib produce different firings; `-Werror` becomes non-reproducible. This is the rejected **W08xx** free-variable leak.
- Only `BridgeAlpha(λ)` with `λ` uniform across the build has no free variable beyond `(source, λ)`. Source-determinism is a *coherence* property (one canonical answer to "is `T` bridge-able"), which forces a globally-agreed set, which forces `λ` — not edition, not package.

### Follow-Up

- **Impl ticket** filed for the spec resolved here (typecheck/codegen surfacing of `bridge_alphabet` in `blink --version --json`, llms.txt projection, the build-time single-source equality test, W0816 text + `blink doc bytes-bridge` anchor).
- **Deliberate note:** NO `E08xx` (or any) diagnostic was reserved for an extension attempt, by design (Q2, 6-0). A future author must not "close the gap" by adding one; if a future language version ever introduces bridge-membership syntax, that change mints its own diagnostic under G2 deliberation.
