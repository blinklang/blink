[< All Decisions](../DECISIONS.md)

# audits.toml diagnostics — Design Rationale

### Panel Deliberation

Quotes are the panelists' own words. A mark `[...]` shows text left out. Three questions came to the panel. What does `audits.toml` report when a value has the wrong type? What does it report for a key at the top level that is not in a record? What does it report when the file is not valid TOML? The panel also had to say what a gated site shows next to a bad record, and what `blink audit pin` does with a file that has faults.

Example file used in the votes (`audits.toml`):

```toml
[A-1]
claim = "getpid has no side effects"
pins = { "m.f" = 3 }

[A-2]
claim = "reads only"
pins = "x"
```

#### Phase A — Independent proposals

**Systems:**

> LOAD RULE (covers all three). The loader reads and checks audits.toml once per package per invocation, as a whole file, whether or not an annotation names a record.

> Q1 WRONG VALUE TYPE: new error `AuditRecordBadValue` (next free E08xx). Do not use E0830: that code means "unknown key".

**Web/scripting:**

> Rule I champion (90% case): a fault in audits.toml is reported IN audits.toml, at the token at fault, with a message that says what was found and what was expected.

**PLT:**

> The composition rule is **poisoning**, which works like the error type in a type checker. A record with an L1 error, or every record when the file fails L0, is *poisoned*:

> (b) A poisoned record never suppresses anything. This fails closed: the gated diagnostic fires again, with a note that points at the file error.

**DevOps/tooling:**

> Why not E0830: tools filter and quick-fix by code. The E0830 fix is "rename the key to the nearest one". For `claim = 3` that fix is wrong, because the key is correct.

**AI/ML:**

> the code tells the agent what kind of fix to make. E0830 means "rename or delete this key". A wrong type means "rewrite this value". These are different fixes, so they need different codes.

**Minimalism:**

> So no case needs a new audit code. The one real gap, TOML syntax, is not about audits at all. It must get one code for every TOML file, not a code for audits.toml alone.

> Tradeoff: a bad record that no annotation uses stays silent.

#### Phase B — Debate highlights

All six seats confirmed six shared points: a top-level `K = { claim = "..." }` and `K.claim = "..."` are record K; one TOML syntax code serves every TOML file; a duplicate table or key is that code and never a merge; a file that does not parse gives no records; the build fails; `blink audit pin` refuses on a syntax error.

On the wrong type of `claim`, five seats chose a new value code in `audits.toml`. Minimalism withdrew its plan to reuse E0829.

**Minimalism:**

> Once V4 checks the whole file at load (see V4), a use-site-only check has no reason to exist. devops is right that the E0830 rename fix is wrong when the key is correct, so my widen-E0830 fallback is also out. That gives one new value code.

**Systems:**

> A diagnostic that says "no record A-1" while the record is right there is a false statement, and Q1-R leaves a bad record silent until a use.

**PLT:**

> Against Q1-R: it makes the result depend on whether some annotation uses the record. Then the same file is wrong in one build and right in another, and a cleanup that removes the last `@trusted` hides the fault. A file fault must be a property of the file.

**AI/ML:**

> E0829's help is wrong for a record that exists, and that wrong help is what causes the duplicate-record loop above.

On a pin value of the wrong type, the seats split. Systems, DevOps and Minimalism chose to read it as a pin that blink cannot read. Web, PLT and AI/ML chose a value error.

**Web/scripting:**

> So "a pin is always a TOML string" costs nothing and keeps one simple rule for users: wrong TOML type is an error, an odd string is stale.

**DevOps/tooling:**

> The fault is not hidden, because the warning comes back with a note that names audits.toml:line:col.

#### Phase C — Final vote

**P — a pins value of the wrong type.** P-E: `pins = "x"` and `"m.f" = 3` are both the value error. P-S: `pins = "x"` is the value error, and `"m.f" = 3` is a pin that blink cannot read. Result: **P-E 3-3 against P-S 3-3.** The panel ran Phase D on this question.

**Web/scripting** (P-E):

> Under P-S, a typo like `3` turns into a lapsed-pin warning in a .bl file, so the user goes to the wrong file.

**Minimalism** (P-S):

> P-E adds a new rule ("a pin value is always a string") plus a promise about how future pin formats will look, and it turns tool-owned opaque data into a hard error.

**R — what `blink audit pin K` does when `audits.toml` has an error.** R-F: refuse on any error in any record. R-Wp: rewrite K's `pins` when only K's `pins` is bad. R-Wk: replace K's `pins` in place and refuse only on a syntax error or a bad or empty claim in K. Result: **R-Wk 4-2.** Web and Systems voted R-F in Phase C.

**Web/scripting** (R-F):

> Concern: on a large audits.toml that has an unrelated broken record, a user who only wants to pin K must fix someone else's record first, and that will annoy people.

**C — what a gated site shows next to a bad record.** C-F: no E0829. The gated warning fires again with one note that points at the error. C-H: no E0829, and the warning does not fire again; the error in `audits.toml` lists the sites. Result: **C-F 5-1** (Web/scripting dissent).

**Systems:**

> the gated warnings are true, and fail closed means they show. C-H changes what you see for reasons that have nothing to do with the code at the site, and the output then changes when someone fixes audits.toml.

> Concern: one broken pins line in the stdlib's audits.toml can print many warnings and push the root error off screen. The root error must sort first.

**Web/scripting (dissent):**

> When the whole file has a syntax error, 40 UnauditedFfi warnings each with the same note bury the one error that matters.

**CU — does the error in `audits.toml` also list the sites?** Result: **CU-Y 4-2** in Phase C (DevOps/tooling and Minimalism dissent).

**Systems:**

> the "used by" note on the file error lets a person who edits audits.toml see what the fault breaks without a search. It costs one note per use.

**AI/ML:**

> The link goes both ways. An agent that starts from the audits.toml error sees which functions depend on the record, and can re-check them after the fix without a search.

**PLT:**

> Concern: a list without a cap is noise. Give the first few sites, then a count (as in C-H's wording).

**DevOps/tooling (dissent):**

> the per-site note already connects each site to the file error in both directions that tools use (CI annotations and LSP). A list of sites on the file error repeats that, and it needs a rule for how long the list can be.

**Minimalism (dissent):**

> The note at each site already ties the site to the fault. A list of "used by" sites on the file error repeats that link in the other direction, and it needs its own shortening rule (first few sites, then a count).

**V1 — how many faults a file reports.** V1-A: the first syntax error only; in a file that parses, every duplicate table and key, in source order. V1-B: the first fault only. Result: **V1-A 5-1** (Minimalism dissent).

**PLT:**

> The rule must say that duplicates are reported only when the file has no syntax error, and that all of them are reported then.

**Minimalism (dissent):**

> Under TOML, a duplicate table or key is a parse failure. One rule, "the first fault in each file", needs no split between syntax errors and duplicates, and no recovery logic.

**AG — the nine points in the ruling.** Result: **6-0.**

#### Phase D — Round 2

Three questions stayed open: P (tied), R (does an error in K refuse) and CU.

**P — P-E 2, P-S 4.** AI/ML and PLT moved from P-E to P-S. DevOps moved from P-S to P-E. Result: **P-S 4-2** (Web/scripting and DevOps dissent).

**PLT:**

> the domain of a pin is any TOML value, and the reader maps every value it cannot read to "no usable pin for this function". That is the decided "unknown prefix reads as stale" rule, made total, with no new rule and no promise about future formats.

**AI/ML:**

> P-S keeps the damage to the one pin, and P-E makes every site of A-1 lose its suppression and fail the build. The note gives the position and the type found, so a reviewer can tell damage from an out-of-date pin.

**DevOps/tooling (dissent):**

> audits.toml gates the suppression of security diagnostics. Damage to it must fail a default CI run, not only a `--require-all` run.

**Web/scripting (dissent):**

> Under P-S, the user sees an UnauditedFfi warning in src/ and must read the note to find that the fault is in audits.toml, and that gap is what makes people ask "why is my audit ignored?".

All four P-S seats named the same concern, and the spec answers it:

**Systems:**

> Concern: a hand-damaged pin shows only as a warning that comes back, so it can stay in the file for a long time unless CI runs `blink audit --require-all`.

**R — R-Wk 6-0.** Web, Systems and Minimalism moved from R-F or from a narrower rule to R-Wk. An E0830 in K refuses. Minimalism had voted that it does not refuse in Phase C; it accepted the refusal in Phase D.

**Minimalism:**

> One rule: `blink audit pin K` refuses unless K would suppress once its pins are replaced (the file parses, K's claim is valid, K has no E0830).

**DevOps/tooling:**

> The refusal on an E0830 in K stops a false green: a re-pin that reports success while K still suppresses nothing.

**Web/scripting:**

> The help on a bad pins value can be one command that works the first time, for people and for agents.

**CU — CU-Y 5-1** (Minimalism dissent). DevOps moved from CU-N to CU-Y.

**Systems:**

> the site note runs from the site to the fault. This note runs from the fault to the sites, for the reader who opens audits.toml first: the LSP diagnostic on that file, or a reviewer of the diff.

**Minimalism (dissent):**

> The note at each site already ties the site to the fault, in the place where the tools show it. A "used by" list on the file error repeats that link in the other direction and adds a list to keep short. I accept the shortening as written if CU-Y wins, since it reuses the existing convention.

### Final Spec

```toml
[A-1]
claim = "getpid has no side effects"
pins = { "m.f" = 3 }

[A-2]
claim = "reads only"
pins = "x"
```

```
error[AuditRecordBadValue]: `pins` in audit record `A-2` must be a table, found a string
 --> audits.toml:7:8
  = note: used by @trusted(audit: "A-2") at src/db.bl:3:1
  = help: run `blink audit pin A-2`

warning[UnauditedFfi]: unaudited foreign function call
 --> src/db.bl:4:1
  = note: audit record `A-2` has an error (audits.toml:7:8); it suppresses nothing
```

- The compiler checks the whole `audits.toml` once per package, in source order, whether or not an annotation names a record. The result does not depend on which `.bl` files are in the compile.
- A top-level `K = { claim = "..." }` and `K.claim = "..."` are record K. A top-level `K.claimz = "..."` is `AuditRecordUnknownKey` (E0830).
- A `claim` that is not a string, a `pins` that is not a table, and a top-level key whose value is not a table are one code, `AuditRecordBadValue` (E0852). The span is the value, or the key for a top-level key. The help for a top-level key is to add a `[K]` header.
- `TomlSyntax` (E1024) is the one code for a TOML file that does not parse. It covers `blink.toml`, `audits.toml` and `blink.lock`. A table or key defined twice is the same code, with the span on the second definition and a note at the first.
- The toolchain reports the first syntax error of a file. It reports duplicates only when the file has no syntax error, and then it reports all of them in source order.
- A file that does not parse gives no records. The build fails. For `blink.toml` the load stops. The `.bl` files are still checked in the same run.
- A record with a fault suppresses nothing, and its annotation gets no `AuditRecordNotFound` (E0829). The gated warning fires again at each site with a note that points at the fault. The error of `audits.toml` prints before the warnings.
- A pin value that is not a string is not an error. Only the gated warning of that item fires again, with a note that names the type found. The help is `blink audit pin A-1 m.f`. `blink audit --require-all` fails on it.
- The error in `audits.toml` carries a `used by` note for each annotation of the record. The terminal text may shorten the list and count the rest, as for the candidates of an unknown import name. `--json` lists every site.
- `blink audit pin K` replaces the `pins` value of K in place and never adds a second `pins`. It refuses, with exit 1 and no write, on a syntax error, on a bad or empty claim in K and on E0830 in K. A fault in another record does not block it. After the write, the file parses, every other record reads back the same, and K reads back with the same claim and the new pins.

| Question | Result |
|----------|--------|
| P — pin value of the wrong type | P-S 4-2 in Phase D (Web/scripting and DevOps dissent) |
| R — `blink audit pin` with faults | R-Wk 6-0 in Phase D |
| C — gated site next to a bad record | C-F 5-1 (Web/scripting dissent) |
| CU — `used by` note on the error | CU-Y 5-1 in Phase D (Minimalism dissent) |
| V1 — faults reported | V1-A 5-1 (Minimalism dissent) |
| AG — nine points | 6-0 |
