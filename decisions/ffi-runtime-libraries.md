[< All Decisions](../DECISIONS.md)

# Runtime Libraries in `@ffi` — Design Rationale

**Question.** Must a project manifest declare the C library and libm that `@ffi("c", ...)` and `@ffi("m", ...)` bindings name?

Before this decision the spec said two things that disagreed. The §9.1.2 Compiler-Managed Dependency List put libc and libm in the runtime row and said "Users never declare them in `blink.toml`". The `[native-dependencies]` rule and gate #275 said every `@ffi` library needs an entry (E0820). The CLI took the strict reading, so programs that bind `strlen` or `cos` got MissingNativeDep. The CLI also skipped the check when no `blink.toml` existed, and the spec did not define the one-argument form `@ffi("sym")` that `lib/std` and the tests use.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds.

#### Phase A — Independent proposals

All six proposed the same core rule: `c` and `m` need no manifest entry. No panelist proposed the spec as written (option b). Excerpts:

- **Systems:** "The library names `c` and `m` name the compiler-managed runtime libraries (§9.1.2). An `@ffi` that names one of them needs no `[native-dependencies]` entry. A `[native-dependencies]` key `c` or `m` is error E0823: the compiler, not the manifest, resolves these libraries." On cross builds: "With `c = { type = "system" }` on `--target`, §9.1.2 gives E0821, because the entry is system-only with no vendored source. The user must then add `link = "dynamic"`, which is false: `zig cc -target` supplies a static libc for the target." On spelling: "The library argument of `@ffi` is the name the linker sees (`-l<name>`). The C library is `c`, never `libc`." On the one-argument form: "`@ffi(symbol)` with no library binds a symbol from the compiler-managed runtime libraries. It adds no link flag and needs no manifest entry." On scope: "I would keep the implicit set at only what is on every link line: `c` and `m`."
- **Web/Scripting:** "The bar: a Python or JS dev calls `cos` from libm. Do they hit an error about a library they never chose, all in their first 5 minutes? Today they do, and it's a bad first touch for FFI." Proposed P1 "`c` and `m` are implicit, and declaring them is an error"; P2 "The runtime libraries are spelled `"c"` and `"m"`, the names passed to `-l`. `@ffi("libc", ...)` and `@ffi("libm", ...)` are a compile error with a fix-it to `"c"` / `"m"`"; P3 "`@ffi("symbol")` (with optional `header:`) binds a symbol from the compiler-managed runtime libraries and needs no manifest entry. A symbol from any other library must use the two-argument form"; P4 "With no `blink.toml`, `[native-dependencies]` is empty. Compiler-managed libraries still resolve, and every other `@ffi` library is E0820."
- **PLT:** "The rule should not read "the library must appear in blink.toml". It should read "the library name must resolve in an environment"." Proposed Γ = Γ₀ ⊎ manifest, Γ₀ = {c, m}: "If the manifest could override `m` (for example `m = { type = "vendored", ... }`), there would be two libms in one link, and the runtime already depends on one. Disjoint union makes that state impossible to write." And: "Γ₀ is exactly the runtime row. pthread is not in Γ₀ … If the toolchain always links `-pthread`, Γ₀ should grow by a spec revision, as §9.1.2 requires. It should not grow by implementation drift." On the one-argument form (Proposal 4, follow-up, separate ticket): "I recommend `@ffi("sym", header: …)` ≡ `@ffi("c", "sym", header: …)`, so it type-checks under Proposal 1 without a special case. The alternative is to restrict the form to `lib/std`. Either way, the moderator should file this so the gate has no unspecified bypass."
- **DevOps:** "I propose closing this gap with a closed set of reserved library names that need no manifest entry (option (a)), with one spelling for each and diagnostics that LSP and CI can act on." Proposed W0820 NonCanonicalFfiLib for `"libc"`/`"libm"` and W0823 RedundantNativeDep for a manifest key: "It is a warning, not an error, so the projects that already declared `m` under the current rule keep building." On no manifest: "Today the CLI skips the check when there is no manifest, so a single-file script silently passes `-lsodium` that nothing declared. That is the hole decision #275 was meant to close." Against (b): "the E0820 help would also tell users to add `m = { type = "system" }`, which breaks cross builds with E0821 unless E0821 exempts it, and that exemption is option (a) again."
- **AI/ML:** "§9.1.2 lists "runtime | libc, libm | System (always available)" as compiler-managed … §9.1.4 says every `@ffi` library needs an entry. An AI that reads the spec alone has no way to choose between them … So this is a fix for a contradiction, not new policy." On the strict reading: "When an LLM sees MissingNativeDep for libm, its likely fix is a `type = "system"` entry, and that entry only adds a dead `-lm`. Under Q4 that dead flag breaks an invariant." Diagnostic requirement: "The E0820 help must give the exact entry in the spec schema (`type = "system"`, not `{ system = true }`)."
- **Minimalism:** "the spec already answers this question, but in two places that disagree … Option (b) keeps both sentences and leaves the contradiction in place. The fix should remove that contradiction and add nothing else." M1: "The library names `"c"` and `"m"` name the runtime libraries in §9.1.2. They are compiler-managed and need no `[native-dependencies]` entry. A `[native-dependencies]` key `c` or `m` is error E0820. Every other `@ffi` library name must have an entry." M2: "A program with no `blink.toml` checks `@ffi` as if `[native-dependencies]` were empty." Offered M3 as an alternative: "`@ffi("symbol")` binds a symbol from the compiler-managed runtime libraries (§9.1.2). `@ffi("library", "symbol")` binds a user-managed library and always needs a `[native-dependencies]` entry. The library names `"c"`, `"libc"` and `"m"` are errors that point to the one-argument form." And: "Pick M3 only if the panel wants to define the one-argument form now. If not, take M1 and file the one-argument form as its own gap."

#### Phase B — Debate highlights

One round. All six sent "stable, ready to vote".

- **DevOps** withdrew both warnings: "Q2: I change to 2A, a compile error ... Code: use a new code, not E0820 ... Keys `libc` and `libm`: cover them too. Q3: I change to 3A, a compile error".
- **Minimalism** on the code: "I changed my mind on reusing E0820. E0820 means "you did not declare this library". This case means "you declared a library that you must not declare". Those are different faults with different fixes."
- **PLT** moved from 5B to 5A: "The one-argument form binds a symbol from Γ₀, the runtime set {c, m}, with no named member. It is not ≡ `@ffi("c", …)`, because lib/std may bind libm symbols that way and "c" would mislabel them."
- **Systems** against the "≡ c" wording: "`cos` is in libm, not libc. On glibc static links, libm is a separate archive. Saying "≡ c" states a false link edge. "Adds no link flag" is true for both libraries."
- **AI/ML** against 2B: "the warning keeps the build green. Agents in a loop treat a green build as done and do not read warnings, so the redundant entry stays and gets copied into the corpus."
- **Web/Scripting** against 5C: "it inverts the Q1 and Q3 result we all agreed on (`"c"` canonical), forces a migration of 41 test sites, and makes the most familiar spelling (`-lc`) an error. Two forms that each have a clear job are fine."
- **Minimalism** *(dissent on Q5)*: "5A adds a second way to bind libc: `@ffi("getenv")` and `@ffi("c", "getenv")` would mean the same thing. That is the same fault Q2 and Q3 reject. We cannot vote "one spelling" on Q2 and Q3 and then vote "two forms" on Q5."

Moderator fact surfaced before the vote: `src/diagnostics.bl` reserves E0823+ for unwind/cleanup, so the Q2 code is an allocation detail. The code chosen is E0841, in the toolchain / link integrity range.

#### Phase C — Final vote

- **Q1: `c` and `m` need no `[native-dependencies]` entry** (1A, 6-0)
  - **Systems:** 1A — "The runtime puts libc and libm on every link line, so a manifest entry for them adds no edge to the dependency graph. Under 1B, `c = { type = "system" }` triggers E0821 on every `--target` build". Concern: "The rule text must list exactly `c` and `m`."
  - **Web/Scripting:** 1A — "The 90% FFI case is libc or libm. It must work with zero config". Concern: "the E0820 help must say clearly that only the runtime libraries are exempt."
  - **PLT:** 1A — "1B forces an entry whose strategy the compiler ignores … That is a contradiction inside the spec, not a matter of style." Concern: "The spec text must say the set is exactly the §9.1.2 runtime row and changes only by spec revision."
  - **DevOps:** 1A — "1B would make the spec contradict itself." Concern: "Keep one closed-set constant" shared by the marker emitter and the validator.
  - **AI/ML:** 1A — "1A removes a contradiction a model cannot resolve from the spec." Concern: "models trained on Zig/cgo may still add `c`/`m` entries out of habit. Q2 catches that".
  - **Minimalism:** 1A — "1A adds no new rule. It removes a contradiction between two sentences of the spec." Concern: tools may hard-code the exception "instead of reading it from the §9.1.2 table".
- **Q2: a manifest key `c`, `m`, `libc` or `libm`** (2A compile error with its own code, delete fix, 6-0)
  - **Systems:** 2A — "The compiler cannot honor such an entry. A vendored or system `m` would either add a second libm to the link or be silently ignored."
  - **Web/Scripting:** 2A — "A warning leaves two valid manifests for one meaning". Concern: "The error must point at the blink.toml line, not at the @ffi site".
  - **PLT:** 2A — "The fault sits at a blink.toml key, not at an `@ffi` site, so it needs its own code." Concern: "the explain text for the new code must give the reason, which is that the runtime already links that library."
  - **DevOps:** 2A — "A new code lets the LSP and `blink explain` key the "delete this line" code-action on the code, not on the message text."
  - **AI/ML:** 2A — "Covering `libc`/`libm` keys closes the obvious second attempt after the first error." Concern: "Otherwise a model may "fix" the error by renaming the key to something else, such as `glibc`."
  - **Minimalism:** 2A — "A warning would keep the second form legal for good." Concern: the key list "can drift from the §9.1.2 table".
- **Q3: `@ffi("libc", ...)` / `@ffi("libm", ...)`** (3A compile error with machine-applicable fix, 6-0)
  - **Systems:** 3A — "The library argument is the `-l` name, so `"libc"` means `-llibc`, which does not exist."
  - **Web/Scripting:** 3A — "One spelling stops tutorials and copy-paste from carrying both spellings forever." Concern: the `libsodium`/`libcurl` keys need the sibling gap filed.
  - **PLT:** 3A — "two accepted spellings for one entity is an alias."
  - **DevOps:** 3A — "A linter can enforce one spelling only if the compiler refuses the other." Concern: "the fix must rewrite only the library argument, not the symbol string."
  - **AI/ML:** 3A — "An error with a machine-applicable fix costs exactly one retry."
  - **Minimalism:** 3A — "Users and LLMs copy whatever compiles, so a warning that still compiles would teach `"libc"` forever."
- **Q4: no `blink.toml` is the empty manifest** (4A, 6-0)
  - **Systems:** 4A — "The program then fails at compile time with E0820, not at link time with `ld: cannot find -lfoo`".
  - **Web/Scripting:** 4A — "Single-file scripts keep libc access". Concern: the help must show "a minimal blink.toml with `[native-dependencies]` and `type = "system"`".
  - **PLT:** 4A — "whether a manifest file exists must not change what a program means by switching a check off."
  - **DevOps:** 4A — "Today the CLI skips the check with no manifest, so a one-file script passes an undeclared -l flag silently". Concern: the help should say "run `blink init`, then add ...".
  - **AI/ML:** 4A — "the same source gives the same result whether or not a manifest exists." Concern: the help "must show a complete minimal file ([package] plus the entry)".
  - **Minimalism:** 4A — "one rule and no mode switch."
- **Q5: the one-argument form `@ffi("sym")`** (5A define it now, 5-1, Minimalism dissent; wording 5A-i "binds a symbol from the compiler-managed runtime libraries (c, m); needs no manifest entry; adds no link flag", 5-1, Minimalism for 5A-ii)
  - **Systems:** 5A-i — "5A-ii is false at the link level: `cos` comes from libm, and on glibc static links libm is a separate archive from libc." Concern: "The spec should name the two-argument form as the preferred spelling outside lib/std."
  - **Web/Scripting:** 5A-i — "lib/std ships this form today, so leaving it out of the spec leaves the same kind of gap we are closing." Concern: "a later diagnostic for an unresolved bare symbol is worth a ticket."
  - **PLT:** 5A-i — "Defining it now closes the unspecified way around the check." Concern: under 5A-ii, tools "will report libm symbols as libc."
  - **DevOps:** 5A-i — "I move from my 5A-ii wording to 5A-i … 5A-i's "adds no link flag" is also a rule a test can check directly." Concern: "the spec must state that `header:` keeps its meaning in this form".
  - **AI/ML:** 5A-i — "lib/std teaches this form to anyone who reads it, so the spec must define it". Concern: "The spec should give one sentence saying when to use which".
  - **Minimalism:** *(dissent)* 5B, ranked 5B > 5C > 5A; wording 5A-ii if 5A wins — "5A gives two forms for one binding … That is the fault Q2 and Q3 just rejected". Concern: "Q5 should require that `blink fmt` or the linter picks one."

5-1 on Q5 did not trigger Phase D. The user signed off on the tally.

#### AI-first review

4/5 pass. Generability fails: two forms bind runtime symbols. The spec answers with one sentence: prefer the two-argument form outside `lib/std`. Minimalism's canonical-form lint is filed as a follow-up.

#### After the vote

Writing the spec showed that `lib/std` also uses `@ffi` to bind the Blink runtime's own C symbols (`blink_*`, `blinkrt_*`), and the §9.1 `Clock` example bound one of them under `"c"`. Wording 5A-i does not cover these symbols. The user ruled that this is an implementation detail: the spec says nothing about runtime-internal symbols, the example now binds the real libc function `clock`, and a chore tracks a compiler-known marking for `lib/std`'s runtime-internal bindings.

### Final Spec

```blink
@ffi("c", "getenv")
@trusted(audit: "ENV-001")
fn raw_getenv(name: Ptr[U8]) -> Ptr[U8] ! Env

@ffi("m", "cos")
@trusted(audit: "MATH-001")
fn c_cos(x: Float) -> Float ! ()

@ffi("cos", header: "math.h")
@trusted(audit: "LIBM-COS")
fn c_cos2(x: Float) -> Float ! ()
```

```toml
[package]
name = "p"
version = "0.1.0"
# no [native-dependencies] entry for c or m
```

- `c` and `m` are the runtime libraries: the §9.1.2 runtime row (libc, libm). They need no `[native-dependencies]` entry and add no link flag. The set is exactly these two and changes only by spec revision.
- A `[native-dependencies]` key `c`, `m`, `libc` or `libm` is E0841 `CompilerManagedNativeDep`, with its span on the key and a machine-applicable fix that deletes the line.
- `@ffi("libc", ...)` and `@ffi("libm", ...)` are E0820, with a machine-applicable fix that changes only the library argument to `"c"` / `"m"`.
- A program with no `blink.toml` is checked as if `[native-dependencies]` were empty. The E0820 help then tells the user to create `blink.toml` (`blink init`) and shows a complete file.
- `@ffi("sym")` binds a symbol from `c` and `m`, needs no entry and adds no link flag. `header:` has the same meaning in both forms. Prefer the two-argument form outside `lib/std`; a third-party symbol must use the two-argument form.
