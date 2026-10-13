[< All Decisions](../DECISIONS.md)

# Native Dependency Keys and Link Names — Design Rationale

**Question.** Is a `[native-dependencies]` key (and the `@ffi` library argument) the linker `-l` name?

The §9.1.2 examples used the keys `libsodium`, `libpq` and `libcurl`. If the compiler passes a key to `-l`, the link line gets `-llibsodium`, and that library does not exist. The runtime-library decision (`ffi-runtime-libraries.md`) settled only `c` and `m`, where `"c"` is the `-l` name. The spec said nothing about how any other key maps to a linker flag. The implementation took `-l{key}` on a dynamic link, `-l:lib{key}.a` on a cross target, and ran `pkg-config --libs {key}` on the host for every entry that was not vendored. It also read a `pkg-config` field where the spec table listed `name`, and it read a `headers` field that the table did not list.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds.

#### Phase A — Independent proposals

Two proposals shaped the debate. Option L: one key per dependency, plus an optional ordered `libs` list of `-l` names that defaults to `[key]`. Option K: the key is the `-l` name, there is no `libs` field, and a library that needs several `-l` names gets one entry per library. All six panelists rejected a third option (S: strip a leading `lib` silently). Excerpts:

- **Systems** (favored L): "The key is the link name. An optional `libs` field gives a full list." On pkg-config: "A `system` entry never runs pkg-config. Today's code runs pkg-config for every non-vendored entry, so the link line changes with the state of the host." On Option S: "The same manifest line would mean `-lsodium` under one rule and `-llibfoo` under another. That is an alias, which Q3 of the runtime-libraries decision rejected."
- **Web/Scripting** (favored L): "Someone coming from JS or Python learns this library as **libsodium**." and "If they get `-llibsodium` and a linker error, they post a Stack Overflow question." Proposal W1: "The key is a free label. `@ffi` names the key. The compiler never passes the key to `-l` without a check."
- **PLT** (favored L): "A key cannot equal "the `-l` name" when some deps have zero `-l` names and others have two." Proposal A: "A `[native-dependencies]` key is a Blink-side identifier. It has one meaning: it names the dep, and `@ffi`'s first argument refers to it (E0820 when no key matches). It never reaches the linker directly."
- **DevOps** (favored L): "the key is the `-l` name by default, and a `libs` list overrides it. `type` alone picks the resolver, so the compiler never runs a pkg-config lookup the user did not ask for." On lookup failure: "If the lookup fails, that is an error; the build does not quietly fall back to `-l{key}`."
- **AI/ML** (favored K): "The key is the -l name and means one thing everywhere. No prefix magic." On several libraries: "More than one -l means more than one key. Each @ffi names the library that holds the symbol, so the source tells the truth. No `libs = [...]` list." On the pkg-config field: "pkg-config names (libsodium, libpq, zlib, openssl) almost never equal the -l name, so a default gives a wrong guess with no error."
- **Minimalism** (favored K): "It adds nothing: no field, no rule, no new diagnostic. It reuses a concept every C programmer already knows." On several libraries: "A library that needs more than one `-l` gets one entry per library. Blink links every entry, in the order the manifest declares them."

Points that no panelist contested in Phase A: `type = "system"` never runs pkg-config; static link order follows declared order; `headers` goes into the §9.1.2 schema table; the spec field `name` becomes `pkg-config` (Minimalism first kept `name`).

#### Phase B — Debate highlights

One round. Five panelists sent "stable, ready to vote". AI/ML sent "still debating".

- **Systems** moved from L to K:
  > "Under L, `@ffi("ssl", "EVP_MD_CTX_new")` binds a libcrypto symbol through the `ssl` key."

  On cross builds: "Under K it needs nothing: `ssl` and `crypto` are each a pkg-config entry on host and `libssl.a libcrypto.a` on `--target`, in manifest order." On duplicate flags: "When two entries emit the same flag, keep the **last** occurrence, not the first. Single-pass static linkers resolve left to right, so a later archive that needs `-lcrypto` breaks if the copy that stays sits before it."
- **Web/Scripting** stayed on L: "Ask a web dev which archive holds `EVP_MD_CTX_new`. They do not know, and they should not need to." Web gave up two points: "**L-v1 (framing): I concede.**" and "**L-v5: I withdraw my "libs overrides pkg-config on host" rule.**" Web accepted AI/ML's field rule: "So I now support **`pkg-config` required on `type = "pkg-config"` entries**."
- **PLT** stayed on L: "K's rule is "the key is the `-l` name." That is true for only one of the three types." PLT proposed that the key framing is only wording: "Sys/DevOps ("the key is the `-l` name by default") and PLT/Web ("the key is a label") have the same mechanics, so the difference is only wording." PLT moved on the `lib` prefix: "I move from a warning to an **error**."
- **DevOps** stayed on L: "K is L without `libs`. The two give the same result for one-library entries, so the vote turns on openssl." DevOps moved on cross pkg-config entries: "My `-l:lib{key}.a` guessed from the key, and under the label framing that guess is wrong."
- **AI/ML** moved from K to L, with the Sys/DevOps framing: "PLT showed that K is partial: a vendored entry has zero -l names, and openssl through pkg-config gives two." AI/ML kept the key framing: "I keep the framing "the key IS the -l name unless `libs` says otherwise", not PLT/Web's "free label"."
- **Minimalism** stayed on K and conceded the field: "**K-v1: I concede to AI/ML.** The pkg-config field is renamed `pkg-config` and is REQUIRED for `type = "pkg-config"`." On the `lib` prefix, Minimalism moved from "no diagnostic" to a warning: "I choose a warning, not AI/ML's error, because K has no `libs` escape hatch, so a real `-l` name starting with `lib` must stay legal."
- Several panelists said `--explain-link` and the mapping of ld errors to blink.toml are tooling. DevOps: "This is tooling, not spec. File `--explain-link` and the mapping from `ld` errors to manifest lines as a chore."

#### Phase C — Final vote

- **Q1: Model for keys and link names. L (one key, optional `libs`, default `[key]`, `@ffi` names a key only) or K (the key is the `-l` name, no `libs`).** (3-3 tie → Phase D. L: Web, PLT, DevOps. K: Sys, AI/ML, Min.)
  - **Systems:** K — "Under K, one entry is one archive, so the link line is the manifest read top to bottom. Every non-vendored entry has a static form `libKEY.a`, with no extra rule." Concern: "If L wins, users will write `openssl = { type = "pkg-config", pkg-config = "openssl" }` with no `libs`. That builds on host and fails only on the first `--target` build."
  - **Web/Scripting:** L — "Under L, one entry with `libs = ["ssl", "crypto"]` puts the whole library on one line, and a static cross build gets its archive order from that line, so the user does not have to discover it by trial." Concern: "L-v8 makes `@ffi("ssl", "EVP_…")` name the owning key, not the archive that holds the symbol."
  - **PLT:** L — "The `@ffi` argument names a *dependency*, and a dependency can own zero, one or several archives. L puts that ownership in the data, so the map from an entry to its link flags is a total function of the entry and the target."
  - **DevOps:** L — "One dependency is one entry. A failed link points at one line in blink.toml, and `libs` order fixes the static order in one place." Concern: "The E0821-family error for a pkg-config entry on a cross target with no `libs` is new, and users will hit it on their first `--target` build."
  - **AI/ML:** K — "Sys's point decides it: under L-v8, `@ffi("ssl", "EVP_MD_CTX_new")` makes the source name the wrong archive." and "K has the fewest decision points: no `libs` field, no ownership rule, and no extra error for a pkg-config entry on a cross target." Concern: "If L wins, E0820 for `@ffi("crypto", …)` when `crypto` exists only inside another key's `libs` must carry a machine-applicable "use the owning key" fix."
  - **Minimalism:** K — "K closes the gap with zero new fields. Each entry is one archive, so each `@ffi` names the library that really holds the symbol." Concern: "openssl users write two entries and may order them wrong (`crypto` before `ssl`), which breaks a static link."
- **Q2: Wording of the key rule. N1 ("the key is the library's link name (the `-l` name)", under L completed with "unless `libs` is given") or N2 ("A key names the dependency; `@ffi` refers to it. Its link names are `libs`, which defaults to `[key]`").** (N1, 5-1)
  - **Systems:** N1 — ""The key is the link name" is the c/m rule extended to every library, so the `@ffi` argument has one meaning."
  - **Web/Scripting:** N1 — "A newcomer can learn this in one sentence, and it matches the c/m rule people already read in §9.1."
  - **PLT (dissent):** N2 — "N1 ("the key is the link name unless `libs` is given") is false for a `vendored` entry (no link name) and for a `pkg-config` entry on host (the flags come from pkg-config). A rule with unstated exceptions is two rules."
  - **DevOps:** N1 — "Diagnostics talk in link names ("key `libsodium` links as `-llibsodium`"). N1 makes that message a direct reading of the spec sentence, and it is the same sentence as the c/m rule."
  - **AI/ML:** N1 — ""The key is the -l name" is the sentence the c/m decision already established, so a model learns one rule for all libraries." Concern: "Readers may take N1 to mean that a vendored entry emits `-l{key}`. The spec needs one clause saying that vendored entries add no flag."
  - **Minimalism:** N1 — "One sentence, the same rule as c/m. It is the only wording that fits K, and under L "unless `libs` is given" keeps the override visible."
- **Q3: The pkg-config package field. R (rename `name` to `pkg-config`, required on `type = "pkg-config"`, no default) or D (rename, defaults to the key).** (R, 6-0)
  - **Systems:** R — "Once keys are link names, a default of `sodium`, `pq`, `z` or `curl` names a pkg-config package that does not exist in any of the four examples."
  - **Web/Scripting:** R — "After the rename, a default of the key is wrong for every spec example (`sodium`/`libsodium`, `z`/`zlib`)."
  - **PLT:** R — "I change from D. With the U4 example keys (`sodium`, `z`), a default equal to the key is wrong in the common case. A default that is usually wrong is not a sound default."
  - **DevOps:** R — "With keys renamed to link names, a default would look up the wrong package in every spec example." Concern: "The error for a missing `pkg-config` field must not suggest the key as the value."
  - **AI/ML:** R — "After the rename, a default of "the key" is wrong for every spec example (`sodium`/libsodium, `curl`/libcurl, `pq`/libpq, `z`/zlib)."
  - **Minimalism:** R — "A required field costs one token, and a wrong default costs a failed build."
- **Q4: A key spelled with a `lib` prefix. E (compile error before link, with fixes) or W (warning).** (E, 5-1)
  - **Systems:** E — "`-llibX` searches for `liblibX.so`. I know of no real library that needs that: `libiberty` links as `-liberty`."
  - **Web/Scripting:** E — "Users ignore warnings, and the next thing they see is raw `ld` output, which is the Stack Overflow question this whole ticket exists to prevent."
  - **PLT:** E — "Under L, `libs = ["libfoo"]` already expresses a real `-llibfoo`, so an error makes nothing legal impossible." Concern: "The fix that renames the key must rewrite every `@ffi` site atomically, or a half-applied fix produces E0820."
  - **DevOps:** E — "A warning lets `-llibsodium` reach ld, and the user then reads raw linker output with no Blink span."
  - **AI/ML:** E — "Agents in a build loop skip warnings and then get raw `ld` output with no Blink span."
  - **Minimalism (dissent):** W (E acceptable if L wins) — "Under K there is no `libs` escape hatch. An error would make a real `-l` name that starts with `lib` impossible to write, which is a hole in the language, however rare." and "Under L, `libs = ["libfoo"]` is the escape hatch, so E costs nothing there."
- **Q5: Two declared entries emit the same link flag. First (keep the first) or Last (keep the last).** (Last, 6-0; Minimalism moved from First)
  - **Systems:** Last — "A single-pass static linker resolves left to right. An archive must sit after every object or archive that needs it, and the last occurrence is the latest position, so it satisfies every earlier user." Concern: "A true cycle (A needs B, and B needs A) is not solved by any deduplication rule."
  - **Web/Scripting:** Last — "Single-pass static linkers resolve left to right, so keeping the last copy is the choice that does not break a later archive that needs it."
  - **PLT:** Last — "Deleting an *earlier* copy of a flag keeps every archive after all of its users, so it keeps any line that resolved before the dedupe."
  - **DevOps:** Last — "Duplicates also arise under L, because pkg-config outputs overlap (curl's static flags include `-lssl -lcrypto`)."
  - **AI/ML:** Last — "Sys is right: single-pass static linkers resolve left to right, so the copy that stays must follow every archive that needs it."
  - **Minimalism:** Last — "I concede to Sys."
- **Uncontested (U1–U7, all 6-0 accept):**
  - **U1:** `type = "system"` never runs pkg-config; only `type = "pkg-config"` does. Systems: "This is the reproducibility fix. The same manifest must give the same link line on every host."
  - **U2:** A failed pkg-config lookup (missing tool or unknown package) is an error at the entry; no fallback to `-l{key}`.
  - **U3:** Every declared entry links, in manifest order (and in `libs` order inside an entry if L wins), whether or not an `@ffi` names it. Systems: "Static transitive archives that no `@ffi` names must still reach the line."
  - **U4:** Spec examples become `sodium`, `curl`, `pq`, and `zlib` becomes key `z` with pkg-config package `zlib`; E0820/E0821 help and `blink audit` samples follow.
  - **U5:** Add `headers` to the §9.1.2 schema table.
  - **U6:** The spec says "static `lib<name>.a`"; the driver chooses the spelling. Systems: "`-l:` is GNU ld/lld only, and Apple ld64 rejects it, so the spec must not name it."
  - **U7:** `--explain-link` and mapping ld `cannot find -lX` back to the blink.toml line are tooling chores, outside the spec vote. Minimalism: "Tooling, not spec." Web: "These are the highest-value DX items here, so file them as chores right away."

#### Phase D — Round 2 (Q1 only)

Q2 to Q5 and U1 to U7 were closed. Only Q1 went to a second round.

**D1 debate highlights**

- **Systems** (K) dropped the false-edge argument: "I concede this. U3 links every entry, so "`@ffi` names the archive" is a convention under both options, not a checked property." Systems rested on cross builds: under K "No case is an error. K is total."
- **Web/Scripting** (L) also gave up its Phase C case: "Sys, AI/ML and Min are right that U3 removes my Phase C failure case." Web asked a new question: "which option fails at compile time with a Blink span, and which fails in `ld`?" Web's example: "On the first `--target` build, K emits `libopenssl.a` and `libzlib.a`. Neither exists, so the user sees raw `ld: cannot find`."
- **PLT** (L) agreed that no tool can check which archive an `@ffi` names: "An invariant the system cannot observe is a comment, not a meaning." PLT then proposed a collapse of the two options:

  > "Q2 passed N1: "the key is the link name unless `libs` is given." Take N1 literally on every non-vendored type, including a `pkg-config` entry on a cross target. That entry then links `lib<key>.a` when `libs` is absent, exactly as under K. This removes the extra E0821-family error that Sys and Min count against L. I withdraw my L-v4 error in favor of what N1 already says."
- **DevOps** (L): "Take a static curl. ... Under K, `curl = { type = "pkg-config", pkg-config = "libcurl" }` emits `libcurl.a` on `--target`, and then ld fails with `undefined reference to nghttp2_…`. That error has no span and no fix."
- **AI/ML** (K): "N1 already won 5-1, and only K keeps it true without exceptions." On the owning-key error: "LLMs know that EVP lives in libcrypto and will write `crypto`. So L adds an error on the guess a generator is most likely to make".
- **Minimalism** (K) listed what each side adds beyond the decided rules: "K's cost is one more line for openssl. L's cost is the right-hand column." (the right-hand column being `libs`, the L-v8 ownership rule, and the extra diagnostics).

**D2 silent re-vote.** Option L (5-1). Minimalism dissents: K.

- **Systems:** L (moved from K) — "My D1 vote for K rested on cross-target totality. PLT's collapse removes that difference: N1 applied literally gives `lib<key>.a` under both options." Concern: "If K wins, a library with several archives that also uses pkg-config, such as openssl, must be split into entries that each run the same lookup."
- **Web/Scripting:** L — "L can ask for it at compile time with a span and a fix. A `lib<key>.a` default, under K or under PLT's collapsed L, asks for it through raw `ld` output in a CI image."
- **PLT:** L — "Web and DevOps persuaded me, so I reverse my D1 withdrawal." and "A function that returns a wrong answer with no error is worse than a partial function that refuses before link with a span and a fix."
- **DevOps:** L — "L with the error catches this before the link, on the exact line, with a machine-applicable fix." and "Even with PLT's fallback, L is K plus one optional list: every K manifest stays valid with the same link line, so I would still vote L."
- **AI/ML:** L (moved from K) — "Without that error I would vote K, because PLT's collapsed L then fails exactly as K does." Concern: "If L wins, two valid ways to write openssl (one `libs` entry or two entries) is a new decision point, so the spec must show one blessed form."
- **Minimalism (dissent):** K — "`libs` adds no power; it adds a second way to write a library that needs several archives (two entries, or one entry with `libs`). Two spellings for one meaning is the surface I exist to vote against." Concern: "if L wins, the spec must pick one form (`libs`) for its openssl example and say which form to prefer."

**Q1 sub-point: a `pkg-config` entry with no `libs` on a cross target.** The D2 ballot offered PLT's D1 collapse (link `lib<key>.a`, no error) and asked each L voter to say if they wanted the E0821-family error kept. The error stays a compile error in the E0821 family. Four L voters keep it: Web, PLT, DevOps, AI/ML.
- **Web/Scripting:** "I want the E0821-family error kept for a cross-target `pkg-config` entry with no `libs`, not PLT's `lib<key>.a` default."
- **PLT:** "**Keep the E0821-family error** for a `pkg-config` entry on a cross target with no `libs`."
- **DevOps:** "A `pkg-config` entry with no `libs` on a cross target should be a compile error on that entry, with help that names the `libs` line."
- **AI/ML:** the L vote is conditional: "L, with the E0821-family error KEPT".
- **Systems (dissent on the sub-point):** "Vote: L, in the form PLT gave in D1. A pkg-config entry with no `libs` on a cross target links `lib<key>.a`, and there is no E0821-family error."

### Moderator notes

These notes are moderator wording, not panel wording.

- Panelists wrote "E0842" for the error on a key that starts with `lib`. E0842 is already UnknownDiagnosticName, so the spec uses E0844. The error for a missing `pkg-config` field is E0845, and a failed pkg-config lookup (U2) is E0846. The panel named neither code.
- The panel spoke of a "use the owning key" fix for `@ffi("crypto", ...)`. The spec puts that fix in the help of E0820.
- Scope of E0844 as written in the spec: it fires when the key is a link name, that is, the entry is not vendored and gives no `libs`. A `libs` element may start with `lib`. This keeps PLT's stated reason for Q4 E true: an error "makes nothing legal impossible".
- The standing rule that a `system` entry on a cross target is E0821 unless `link = "dynamic"` was decided earlier. The panel did not vote on it again.

### Final Spec

```toml
[native-dependencies]
sodium = { type = "system" }
pq = { type = "vendored", path = "vendor/libpq.c" }
z = { type = "pkg-config", pkg-config = "zlib" }
openssl = { type = "pkg-config", pkg-config = "openssl", libs = ["ssl", "crypto"] }
```

```blink
@ffi("openssl", "EVP_MD_CTX_new")
@trusted(audit: "SEC-101")
fn raw_md_ctx_new() -> Ptr[Void] ! Crypto
```

- The key is the library's link name, the `-l` name, unless the entry gives `libs`. `libs` is an ordered list of link names.
- `@ffi` names a key only. `@ffi("crypto", ...)` where `crypto` is only a `libs` element is E0820, and its help names the owning key (`openssl`).
- A `system` entry never runs pkg-config.
- A pkg-config lookup that fails (missing tool or unknown package) is E0846, with its span on the entry. The compiler does not fall back to `-l{key}`.
- The `pkg-config` field is required on a `type = "pkg-config"` entry and has no default. A missing field is E0845.
- Every entry links, in manifest order, whether or not an `@ffi` names it. Inside one entry, `libs` links in list order. When two entries emit the same flag, the driver keeps the last one.
- A key that is a link name and starts with `lib` is E0844. It has two machine-applicable fixes: rename the key and every `@ffi` that uses it, or add `libs`.
- A host `pkg-config` entry links the output of pkg-config.
- A cross-target `pkg-config` entry links the static `lib<name>.a` for each name in `libs`. With no `libs`, it is E0821.
- A `vendored` entry adds no link flag.
- Prefer one entry with `libs` over one entry per library.
- `headers` is in the §9.1.2 schema table.
- `--explain-link` and the mapping of ld errors to the blink.toml line are tooling chores. They are outside the spec.
