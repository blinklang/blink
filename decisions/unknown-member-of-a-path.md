[< All Decisions](../DECISIONS.md)

# An Unknown Member of a Type Path or a Module Path — Design Rationale

**Gap:** §3.4 *Member case* said that `K.x`, where `K` has no function, associated function or constant `x` and `x` does not start with an uppercase letter, is "an unknown member of the type path, never E0547". It named no code: the example wrote a bare `error:`, and the catalog had no row for it. The call `K.zed(1)` got E0505 with a head that said "no type or trait declares method `zed`", with the span on `K`. A read `K.zed` passed `blink check` and stopped the build with an internal error, which breaks the promise of a clean check (§6.7). A module path `m.nope` already gave E0505, for a read and for a call, but its span was on the module name.

**Result:** One package passed 6-0 in Phase C with no dissent. All six seats had said `STABLE` after Phase B, so Phase D did not run. The package is:

- An unknown lowercase member of a type path is E0505 `UnresolvedMethod`, for a read and for a call. No new code, and no rename of E0505.
- The head is "no member `x` on type `K`", and for a module "no member `x` on module `m`". The span is the member name on both.
- The candidates are the functions, associated functions, constants and variants of `K`. A field is never a candidate.
- A fix is machine-applicable only when the rewritten site passes the checker, the payload forms agree, and the candidate is the one nearest across all kinds.
- A struct field named `x` adds a note and no fix.
- E0547 stays for an uppercase member. Its candidates in an expression include the type-scoped constants.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. The excerpts below are verbatim; some are cut to one paragraph.

#### Phase A — Independent proposals

All six seats chose option (a): E0505 for a read and for a call, with the catalog row widened. No seat proposed a new code. Three points were open after Phase A: whether a variant candidate is a machine fix (min said never), a note for a struct field (sys and aiml), and the candidates and span for the uppercase and module cases.


- **Code (aiml):**
  > An agent's repair loop keys on the code. The question an agent asks is "the thing after the dot
  > does not exist under this qualifier". Today that is E0505 for `mod.x`, `mod.x()`, `handle.op()`
  > and `K.x()`. Adding a new `UnknownMember` code for only `K.x` (read) would split one mistake
  > into two codes by a syntax detail (parens or not) and by qualifier kind. That is one more
  > decision point to learn, with no difference in the fix. A new code also means the
  > `mod.nope` read should move to it for consistency, which is churn for no gain.

- **Span (aiml):**
  > Span: the member name, not the head. A fix edits the member, so the span must cover what the
  > fix replaces (E0547 already does this). The module case should move its span to the member too.

- **Code (devops):**
  > `K.zed` and `K.zed(1)` are the same mistake: the name after `K.` names nothing. A user who adds `()` while they fix it must not see the code change under them. Tools key on the code: an LSP code action, an agent's retry loop, `@allow`-free CI greps, a dashboard of top errors. Two codes for one typo split all of those for no gain.

- **Code (min):**
  > The last two rows settle the question for me. The compiler already uses E0505 for a module path, read **and** call, with one head. The type path is the same shape (`Q.x`, `Q` not a value, `x` not found). A second code would split one user mistake across two codes by what kind of thing sits left of the dot.

- **Code (plt):**
  > Recommendation (a): E0505 for `K.zed` and `K.zed(...)`, row widened to a member read.

- **Reason (plt):**
  > Reason: a module path and a type path are the same judgment (lookup in a static namespace that
  > the checker knows in full). Today E0505 already covers that judgment for modules, read and call.
  > A new code for types only (b) would split one judgment into two codes by the kind of namespace,
  > which is the wrong axis. A new code for ALL static namespaces (move modules off E0505) is the
  > principled maximum, but it churns a row that carries the removed-names table, the E1023
  > candidate rule and the effect-handle fixes, for no gain in what a user can do. I reject (c): no
  > other code describes "no such member".

- **Reason (sys):**
  > The reason from my seat: `K.zed` is a static lookup in one fixed table (type-scoped fns, associated
  > fns from impls, type-scoped constants). The compiler resolves it at check, and the C output has
  > either a direct symbol or nothing. The `(` after the name does not change which lookup failed, so
  > it must not change the code. A module path works the same way and already gives E0505 for both
  > forms. Two codes for the same failed table lookup would make tools and agents branch on syntax that
  > has no effect on the failure.

- **Code (web):**
  > `K.zed` and `K.zed(1)` are the same mistake: nothing named `zed` lives after `K.`. A JS/Python dev sees one error, not two. Two codes for "read" vs "call" makes people ask "why does adding `()` change the error code?" That is a Stack Overflow question we can avoid.

**The open points, Phase A:**


- **Variant candidate (min):**
  > Candidates: the existing §3.4 rule — type-scoped fns, associated fns, type-scoped constants, **and the variants of `K`**. A variant candidate is a help line only, never machine-applicable, because `K.zed` → `K.Zed` changes the case and so the meaning class (fn to variant). A fn or constant candidate with one match is machine-applicable, as in E1023.

- **Variant candidate (sys):**
  > The rename is machine-applicable only when the forms agree, the same rule as E0547: `Level.high`
  > to `Level.High` (no payload, read form) applies; `Level.high(1)` to `Level.High(1)` does not,
  > because `High` takes no payload. Rename to a function candidate (`Level.pars("x")` to
  > `Level.parse("x")`) applies for a call; for a read it applies only when a function value of that
  > name is legal there.

- **Variant candidate (web):**
  > The rename is machine-applicable when the payload form agrees (same rule as E0547): `Level.high` to `Level.High` yes; `Level.high()` to `Level.High` not as a plain rename (the help writes `Level.High`, no fix). `d` gets the poison type; no cascade.

- **Field note (sys):**
  > u2 (struct): `no member `nope` on struct `T``. When the name is a field of `T` (`T.n`), add a
  > `note:` "`n` is a field of `T`; read it on a value, such as `t.n`". A struct has no static fields,
  > and this is the usual reason a C or Go programmer writes `T.n`. No fix.

- **Field note (aiml):**
  > Help candidates: the type-scoped fns, associated fns and type-scoped constants of `K`, plus the
  > variants of `K` (as §3.4 says). A variant candidate is the most likely intent for an agent
  > coming from Python/TS enums (`Level.high`, `Color.red`).

- **Constants in the uppercase case (web):**
  > Keep the existing rule: E0547 for an enum, and for a non-enum type. One tweak: when the type has type-scoped constants, add them to the candidates and the list, so `Config.MAXX` suggests `Config.MAX` instead of only "it has no variants". A dev reaching for a constant should not be told about variants.

- **Constants in the uppercase case (plt):**
  > Keep the existing rule: E0547. One small point for the writer: the uppercase set is variants plus
  > type-scoped constants, so the E0547 candidates should also hold the constants of `K`. For a struct,
  > `T.NOPE` can only mean a constant; when `T` declares `const T.MAX`, the help should suggest it
  > rather than only say "it has no variants". This is a help change, not a code change.

- **Module span (min):**
  > Span: the member name, as E0547 does — not the head (today's module report points at the head `semver`, which is the less useful span; align it while we are here).


#### Phase B — Debate highlights

The moderator merged the six proposals into five points of agreement (C1–C5) and four points that differed (V1–V4). Round 1 ran once. All six replies ended `STABLE: ready to vote`.

- C1: a read or a call through `K.x` with a lowercase first character, where `K` declares no such member, is E0505, for the read and the call. No new code.
- C2: the span is on the member name.
- C3: the candidates are the functions, associated functions, constants and variants of `K`.
- C4: `K.Zed` stays E0547. A module path stays E0505. A call through an effect handle is E0505, and a read of a handle keeps E0506.
- C5: the E0505 row widens to cover a member read, and the §3.4 `Level` example shows `error[UnresolvedMethod]`.

**V1. Is a variant candidate a machine-applicable fix?** Min moved from "never" to the E0547 rule. Systems, PLT and DevOps/Tooling added a condition: the rewritten site must pass the checker. AI/ML and Web/Scripting added a second: exactly one suggestion across all kinds.


- **Min (moves: concedes V1):**
  > I said "never". The other five reuse the E0547 rule: the fix is machine-applicable only when the payload forms agree. Reusing a rule the catalog already has is the smaller choice; my "never" was a second rule. My worry was that the fix changes a fn name into a variant. But if the forms agree, the result type-checks or reports a normal E0300, so the fix is safe.

- **PLT (adds the type-check condition):**
  > min is right about one risk: the rename moves `x` from the function set to the variant set. The
  > payload-form check alone does not catch every case where that changes the type at the site. A
  > fix that a tool applies blindly has to give a program that type-checks. So I add the condition
  > the E0505 row already uses for its effect-handle candidates: **the rewritten site must type-check
  > and add no diagnostic.** When both conditions hold, the fix is the only reading that can be meant,
  > so I keep it machine-applicable. This answers min's risk and keeps the E0547 rule for the common
  > case.

- **Systems (adds the type-check condition):**
  > Keep the E0547 rule (forms agree), and add the guard that E0505 already uses for its other fixes:
  > the rewritten expression must type-check at its expected type. This answers min's concern without
  > a separate "never for a variant" rule.

- **DevOps/Tooling (adds the type-check condition):**
  > I keep the E0547 rule: the fix applies on its own only when the forms agree. A read of a unit variant matches a read, and a call matches a payload variant of the same arity. I add one guard, the one the E0505 row already uses for the module-function fix: there is no fix when the rewritten site would not type-check.

- **AI/ML (makes the conditions explicit):**
  > To meet min halfway, I make the conditions explicit. All three must be true:
  > 1. exactly one suggestion across the whole candidate set (fns, constants and variants
  >    together), so a near fn and a near variant together give no fix;
  > 2. the payload forms agree;
  > 3. the same rule as E0547 for everything else.

- **Web/Scripting (adds the one-suggestion condition):**
  > One guard I would add for min: when `K` also has a fn or constant candidate that is just as near, there are two suggestions, so no fix (the normal one-suggestion rule). That covers the "meaning class" worry where it is real.

**V2. A note when the name is a field of a struct.** Web/Scripting moved to adopt it. Min and PLT accepted it. No seat argued against it.


- **Web/Scripting (moves: adopts V2):**
  > I missed this one. `Point.x` for a field is a top Python/JS habit (class attributes, `Point.prototype.x`). The plain "declares: ..." list does not say why, so the user asks Stack Overflow.

- **PLT:**
  > A field belongs to values of `T`, not to the namespace `T.`, so `T.n` is still a failed lookup
  > and still E0505. A `note:` that says where the name lives costs nothing in the type rule and
  > helps the common Python habit. Note only, no fix: the rewrite needs a value of `T`, and the
  > checker cannot pick one.

**V3. The E0547 candidates include type-scoped constants.** Systems and AI/ML moved from no change (or silence) to support. Min read its own Phase A line as the same behavior.


- **Systems (moves: supports V3):**
  > My Phase A said no change to E0547 for the uppercase case. That was about the code, and the code
  > stays. But the uppercase table is "variants and type-scoped constants" (§3.4 *Member case*), so the
  > candidates must be the same table; else `Config.MAXX` says "it has no variants" and hides
  > `Config.MAX`. Code and head stay; candidates and the member list add the constants.

- **AI/ML (moves: supports V3):**
  > This follows C3. The lowercase case lists every member that its first character can name, so
  > the uppercase case should do the same: variants and type-scoped constants. Same code and head.
  > One candidate rule for both cases is one less thing to learn.

- **Min:**
  > This is what I meant by "the E0547 help can list" them; the others made it explicit. It is not a new rule: §3.4 already says an uppercase `K.X` names a variant or a type-scoped constant, so the candidates should be the set the name could mean. Same code, same head.

**V4. The module path puts its span on the member.** DevOps/Tooling and Web/Scripting moved from optional or unchanged to support. PLT moved to support.


- **DevOps/Tooling (moves: supports V4 in this ticket):**
  > I wrote "optional". I now say do it here. C2 puts the span on the member for a type path. If the module path keeps the span on the qualifier, the LSP squiggle and the rename edit go to a different token for the same code and the same head shape. That is the split I argued against in V1. The cost is one span field and a few test rows.

- **PLT (moves: adopts V4):**
  > One lookup judgment should have one span rule, so the module path should follow it too. The
  > §4.4 examples already draw the caret under the member (`term.width`, `^^^^^ `term` has no member
  > `width``), so this also brings the compiler in line with its own spec. Head and code stay the
  > same.

- **Web/Scripting (moves: supports V4):**
  > I left the module path alone to keep scope small, but one span rule for every "no such name after the dot" is the point of using one code. Today `random.shufle` puts the caret on `random`, the part the user got right. Move it to `shufle`. The cost is small and it gives the same span on all three paths.

- **AI/ML:**
  > C2 puts the type-path span on the member. If the module path keeps its span on the head, the
  > same E0505 points at two different places, depending on whether the head is a module or a
  > type. An agent that reads the span to place an edit must then branch. The change is small and
  > the fix (E1023 candidates) already edits the member. I take it in scope, but I do not block
  > the vote on it.

**The head.** Min moved from "`K` has no member `x`" to the shape that the module head already uses.


- **Min (moves: takes the module head shape):**
  > I proposed "`K` has no member `x`". The module head "no member `x` on module `m`" already ships. Taking "no member `x` on type `K`" means the module head does not change at all: fewer edits, the same regex for both. I drop my wording.

- **PLT:**
  > I still prefer "no member `x` on type `K`" / "on module `m`", because the module head already
  > uses that shape and needs no change. I will not vote against the other shape.


#### Phase C — Final vote

**Q1: The package.** (6-0 for A)

- *Option A:* adopt the package: C1–C5; V1 with the three conditions (the rewritten site passes the checker, the payload forms agree, exactly one suggestion across functions, constants and variants); V2, the field note; V3, the constants as E0547 candidates; V4, the module span on the member.
- *Option B:* reject, and say which part.


  - **Systems:** A. — `K.x` is a static lookup in one fixed table at check time, and the code is the same whether or not a `(` follows. That matches what module paths already do, and it closes a hole where a clean `blink check` led to an ICE at build (§6.7). The fix guards (forms agree, the site type-checks, exactly one suggestion) keep automated rewrites safe. The field note and the constant candidates cost a lookup only on the error path, with no effect on a clean build or on the C output. *Concern:* The type-check guard on the V1 fix needs a re-check of the rewritten site. If the

  - **Web/Scripting:** A. — One code and one span rule for every "no such name after the dot" (module, type, effect handle call) can be taught in one sentence and matches Rust E0599, TS2339 and Python AttributeError. The variant suggestion fixes the most common habit (`Level.high` from Python and JS), and the field note covers the other one (`Point.x`). The fix rules (payload agrees, the result type-checks, one suggestion) mean an automatic edit never makes things worse. *Concern:* Because the code is named "UnresolvedMethod", people may not trust it for a value read such as `Level.high` until a later rename covers all paths together.

  - **PLT:** A. — A failed lookup in a static namespace (a module or a type) is one judgment, and the package gives it one code, one span rule and one candidate set, whether or not the site is a call. This keeps the error compositional: `K.zed(1)` fails at `Lookup(K, zed)`, as `K.zed` does. The V1 conditions (payload forms agree, the rewritten site type-checks, one suggestion) make every machine-applicable fix sound: it can only give a program that the checker accepts. V2 and V3 change only the notes and candidates, so they add no new typing rule, and the read closes the gap where check passes and build stops on an ICE. *Concern:* "the rewritten site type-checks and adds no diagnostic" needs the checker to try the

  - **DevOps/Tooling:** A. — A read and a call of the same typo get one code, one span (the member) and one head shape, whether the path is a type or a module. So one LSP matcher, one code action and one agent retry rule cover every `Q.x` miss. The V1 guards (forms agree, the rewrite type-checks, exactly one suggestion) let `blink fix` repair the common case-only typo (`Level.high`) with no risk of a silent change in meaning. V2 and V3 put the real fix in the help where a plain list would hide it. *Concern:* The module-path span move (V4) and the new head shape change shipped output, so existing tests and any user tooling that matches the old span or text will break unless the implementation updates them all at once.

  - **AI/ML:** A. — One code (E0505), one head shape and one span rule now cover every unknown member after a dot: module, type or effect-handle call. The only split is the uppercase case (E0547), and the first character of the token decides it, with no lookup. That is the fewest decision points an agent can learn from the spec alone. The V1 guards (payload forms agree, the site type-checks, one suggestion only) let an agent apply the common `Level.high` → `Level.High` fix with no extra turn, and never apply a fix that adds a new error. V2 and V3 add help only where an agent from Python or TS often goes wrong (`Point.x`, `Config.MAXX`). *Concern:* The name `UnresolvedMethod` on a value read with no call can lead an agent that

  - **Minimalism:** A. — The package adds no code, no syntax and no new rule. It reuses E0505 (as the module path already does), the E0547 fix rule and the existing nearest-name conventions, so one user mistake gets one code whatever stands left of the dot. V2 and V3 are help text over sets that §3.4 already defines, and V4 makes the span rule the same for every path kind. It fixes a check-clean ICE and the spec's own `Level.high` example, and it adds no surface. *Concern:* The E0505 row, already the longest in the catalog, grows again, and the name "UnresolvedMethod" now covers reads too. That debt needs its own catalog chore (split or rename), not a slow drift.


#### Phase D

Not triggered. Q1 passed 6-0.

### Facts From Other Languages

The panelists named these. The moderator did not check them.

- Rust gives one code, E0599, to `K::zed` and `K::zed()`, and suggests the variant by case (PLT, Systems, DevOps/Tooling, Web/Scripting, AI/ML).
- TypeScript gives TS2339 to a read and to a call alike; Python gives `AttributeError` (Web/Scripting, DevOps/Tooling, AI/ML).
- Go says "undefined" for both forms (Minimalism, Systems).

### Concerns Carried Into the Spec

- **The name `UnresolvedMethod` on a read (AI/ML, Web/Scripting, Minimalism):** the catalog row and the help say "member" in plain words. The name stays. A rename is its own change, for all paths together.
- **The E0505 row grows (Minimalism):** the new cases are one grouped sentence, not one sentence for each. A split or a rename of the row is a separate catalog chore.
- **The fix check (PLT, Systems):** the rule is on the result: the compiler offers a fix only for a site that it checked after the edit. The example `let f: fn() -> Level = Level.high` is in the spec as the case that gets no fix.
- **Shipped output changes (DevOps/Tooling):** the module span moves from the qualifier to the member. The spec already draws the caret under the member in §4.4 (`term.width`), so this brings the compiler in line with the spec. The rollout is a task of the implementation, not a rule of the spec.
- **A later exception (PLT):** a name that is an instance method of `K` and not a member that `K` declares (`Int.abs(-3)`) is outside this ruling. The E0505 text says "unless a rule of this specification gives that name its own code", so such a rule can name its own code later with no conflict.

### Final Spec

```blink
type Level { Low, High }

fn main() {
    let a = Level.high                   // error[UnresolvedMethod], fix: Level.High
    let f: fn() -> Level = Level.high    // error[UnresolvedMethod], help names Level.High, no fix
    let b = Level.high(1)                // error[UnresolvedMethod], help names Level.High, no fix
}
```

- The first character of the member picks the code: uppercase is E0547, any other character is E0505.
- Head: "no member `x` on type `K`", "no member `x` on module `m`". Span: the member name.
- Candidates: functions, associated functions, constants and variants of `K`. A field is never one.
- A fix needs all three: the rewritten site passes the checker; the payload forms agree (for a variant); one nearest candidate across all kinds.
- A field of a struct: a `note:` and no fix.
- E0547 in an expression: the candidates include the type-scoped constants (`Config.MAXX` suggests `Config.MAX`).
- Spec: §3.4 *Member case* and *An unknown member of a type path*; §3.4 *A variant the enum does not declare*; §10.5 *Import Errors*. Catalog: the `UnresolvedMethod` (E0505) and `NoSuchVariant` (E0547) rows.
