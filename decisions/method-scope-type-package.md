[< All Decisions](../DECISIONS.md)

# Method Scope: Impls of the Type's Package — Design Rationale

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds.

The gap: §3.6 said an impl is reachable when "either the trait or the type is in scope". So a file that imports only a factory (`import clockm.{make}`) could not call the methods of the value it returns, and §4.4.6 (`udp_bind(addr)?` then `sock.recv_from(...)`) and §8.10.3 (which told tests to import `MockClock` only to switch on its methods) disagreed about it. The ticket proposed a rule keyed on the types that an imported function's signature names. A gen1 probe showed that the compiler followed neither text: it used any impl in any loaded module, so a call in one file compiled or failed depending on whether another file imported the trait's module, and W0602 flagged a load-bearing `import ext` with a fix that broke the build.

Panelist text below is quoted verbatim, except that tracker IDs are left out. The option labels used in the ballots: **H** = impls of the type's own package go with the value, other impls need their trait in scope; **K** = keep the §3.6 rule and enforce it; **G** = the ticket's signature-mention rule.

#### Phase A — Independent proposals

All six recommended the same shape (H) as their first proposal, and all six rejected the signature-mention rule (G) or kept it only as a fallback. The opening rule text of each:

- **Systems:**

> ## Main point
>
> The method a call resolves to costs nothing at runtime. Resolution is fixed when the call is checked (§3c.4 ~882), and mono emits a direct call to one symbol. Each option below compiles to the same machine code. So this is only a question of how predictable and how cheap compile-time work is.
>
> My main concern is the measured behavior, not the spec text. Today, `make().zap()` resolves or fails depending on whether some *other* module happens to load `ext` (the helper test). This means:
> - Resolution depends on the whole program's load graph, so the result is not hermetic.
> - A change in `helper` can break or fix a call in `main`.
>
> The fix must make resolution depend only on two inputs:
> 1. the receiver's type;
> 2. the current file's own imports.
>
> ---
>
> ## Proposal S1 (recommended): impls in the type's own package go with the type
>
> **Rule.** For `x.foo()` where `x: T`, the candidate impls are:
>
> 1. **Owner impls.** Each impl for `T` that lives in the package that defines `T`. They are always in scope when you hold a `T`, with no import. The owner is the package of the head type constructor.
> 2. **Trait-side impls.** Each impl for `T` that lives in another package (the trait's package). These are in scope only when the trait's name is bound in this file: a selective import, a local declaration, or the prelude.
> 3. A qualified-only `import m` does not bring trait methods into scope for dot syntax. The call `m.Trait.foo(x)` always works.
> 4. If 0 candidates match, the error is E0505. If 2 or more match, the error is E0522. This rule is already decided and I do not change it.
>
> ```blink
> // package clocklib, module clockm
> pub type Ctl { n: Int }
> pub trait CtlOps { fn bump(self) -> Int }
> impl CtlOps for Ctl { fn bump(self) -> Int { self.n + 1 } }
> pub fn make() -> Ctl { Ctl { n: 1 } }
>
> // package app, main.bl
> import clockm.{make}
> import std.testing.{mock_clock}
> import std.net.{SockAddr, NetError, udp_bind}
>
> fn main() {
>     print(make().bump())               // OK: CtlOps impl lives in Ctl's package
>     let mc = mock_clock(t)
>     mc.advance(Duration.ms(5))         // OK: MockClockOps lives in std, same as MockClock
> }
>
> // package app, ext.bl -- app owns this trait, not Ctl
> pub trait Extra { fn zap(self) -> Int }
> impl Extra for Ctl { fn zap(self) -> Int { 0 } }
>
> // main.bl, without importing Extra
> make().zap()
> // error[E0505]: no method `zap` for `Ctl` in scope
> //   help: `zap` is in trait `ext.Extra`; add `import ext.{Extra}`
> ```

- **Web/Scripting:**

> ## Position in one line
>
> If you hold a value, its own methods work. You should not have to import a name you never write.
>
> ## Proposal W1: "The value brings its own methods" (recommended)
>
> ### Rule
>
> For `x.foo()` where `x: T`, the impls the compiler searches are:
>
> 1. **Type-home impls.** These are impls for `T` in the package that defines `T`. They are always in scope when you hold a value of `T`. No import is needed. This covers every `*Ops` trait in the stdlib (`UdpSocketOps`, `MockClockOps`, `PidOps`, ...), and also an impl in `T`'s package of a foreign trait, for example `impl Display for Ctl`.
> 2. **Trait-home impls.** These are impls for `T` in the package that defines the *trait*, where `T` is foreign to that package. They are in scope only when the trait is in scope. "In scope" means one of these:
>    - you select the trait (`import ext.{Extra}`), or
>    - you import the trait's module (`import ext`), or
>    - the trait is in the prelude.
> 3. **Nothing else counts.** A module that the program loads only transitively adds no impls. The method set at a call site depends only on the type of `x` and on the imports in *this* file.
>
> The orphan rule says each impl lives in the trait's package or in the type's package. So rules 1 and 2 cover every impl, and each impl has exactly one way to come into scope.
>
> Rule 1 replaces the "named in an imported fn's signature" idea from the ticket. A signature rule breaks on common code: `make().inner`, `list.get(0)`, `opt.unwrap()`, closures, and generic returns such as `List[Ctl]`. In all of these you hold a `Ctl` but no imported signature names it. A rule keyed on the receiver's type has no such gaps, and you can teach it in one sentence.

- **PLT:**

> ## Proposal P1 (recommended): impls come with the receiver's type or with an in-scope trait
>
> ### The rule
>
> For `x.foo(args)` where `x: T`, and `H` is the head type constructor of `T` after alias expansion:
>
> ```
> Candidates(T, foo) =
>     { impl Tr for T' | T' unifies with T, Tr has foo, Tr is visible at the call site,
>                        and either
>                        (a) the impl lives in the package that defines H, or
>                        (b) Tr is in scope at the call site }
> ```
>
> - **(a) Type-home impls.** These are impls in the package that defines `H`. They are candidates whenever you hold a value of type `T`, however you got it: from a factory, a field, a generic function, or a pattern match. The trait must be `pub`. The trait name does not need to be imported.
> - **(b) Trait-home impls.** These are impls that live with the trait, in some other package. They are candidates only when the trait is in scope. "In scope" means one of these:
>   - the prelude, which covers the built-in `*Ops` traits;
>   - a bound on a type parameter;
>   - a bare import, `import m.{Tr}`;
>   - a module import, `import m`. Under §10 the file can name `m.Tr`, so the trait is in scope.
> - The rest stays as decided:
>   - one match: call it;
>   - no match: error;
>   - two or more matches: E0522 with `Trait.method(x)` hints;
>   - resolution is fixed at check time, and mono never looks the method up again.
>
> Under the strict orphan rule, every impl of `Tr for T` lives in `pkg(Tr)` or `pkg(H)`. So (a) ∪ (b) covers every impl. The rule needs no new idea: impls that ship with the type come with values of that type, and impls that ship with a trait come with the trait name.

- **DevOps:**

> ## Proposal T1 (recommended): the type's own impls go with the value; other impls need their trait in scope
>
> ### Rule
> For `x.foo()` where `x: T`, an impl `impl Tr for T` is a candidate when one of these is true:
>
> 1. **Home impl.** The impl is in the module that declares `T`. It is visible wherever a value of type `T` exists, even if the code never names `T`, its trait, or its module. For a generic type such as `List[Ctl]`, the home module is the one that declares `List`.
> 2. **Trait-side impl.** `Tr` is in scope at the call site in one of these ways:
>    - selected by name (`import m.{Tr}`)
>    - declared in the current module
>    - in the prelude (`Display`, `StrOps`, `ListOps`, ...)
>
> Nothing else counts. In particular, an impl is not a candidate just because its module was loaded through some other import. The current rule in §3.6 ("the trait or the type is in scope") is replaced by these two cases.
>
> The decided rules do not change. If two or more candidates have `foo`, the call is a compile error with a `Trait.method(x)` hint. There is still one impl per (Trait, Type), and the orphan rule is unchanged.

- **AI/ML:**

> ## Proposal A (recommended): impls in the type's home module are always visible; other impls need their trait in scope
>
> **Rule.** At a call `x.foo()` where `x: T`, an impl of trait `Tr` for `T` is a candidate if one of these is true:
>
> 1. **Type-home impl.** The impl is declared in the module that declares `T`. If you hold a `T`, you have `T`'s own methods. No import is needed, and the rule does not care how the value reached you.
> 2. **Trait in scope.** `Tr` is visible in this file. That means one of these:
>    - it is selectively imported (`import m.{Tr}`);
>    - its module is imported (`import m`), which counts because qualified access to `m.Tr` already works;
>    - it is declared in this file;
>    - it is a prelude trait;
>    - it is a generic bound in the current signature.
>
> Nothing else counts. An impl that only reaches the program because some other module loads it is not a candidate. This removes the leak the compiler has today (brief, behavior fact 24).
>
> If more than one candidate trait has `foo`, the call is a compile error with a `Trait.method(x)` hint. That rule is already decided and does not change.
>
> ```blink
> // module clockm
> pub type Ctl { n: Int }
> pub trait CtlOps { fn bump(self) -> Int }
> impl CtlOps for Ctl { fn bump(self) -> Int { self.n + 1 } }
> pub fn make() -> Ctl { Ctl { n: 1 } }
>
> // module ext
> import clockm.{Ctl}
> pub trait Extra { fn zap(self) -> Int }
> impl Extra for Ctl { fn zap(self) -> Int { 0 } }
>
> // main
> import clockm.{make}
> import std.testing.{mock_clock}
> import std.net.{SockAddr, NetError, udp_bind}
>
> fn main() {
>     make().bump()            // OK: CtlOps impl is type-home for Ctl
>     make().zap()             // error: Extra not in scope (see diagnostic below)
>     mock_clock(t0).advance(d)  // OK: MockClockOps lives with MockClock
>     let sock = udp_bind(addr)?
>     sock.recv_from(max: 512)?  // OK: §4.4.6 example becomes valid as written
> }
> ```

- **Minimalism:**

> ## Position in one line
> Do not add a "type named in an imported signature" rule. Replace the current rule with a simpler one that keys on the **value's type**, not on imports: **a type's own package's impls go with the type. A foreign trait's impls need that trait in scope.** This removes a condition and adds none.
>
> ## Proposal M1 (recommended): "Behavior goes with the type"
>
> ### Rule (replaces the §3.6 "Impl visibility" paragraph)
> For `x.foo()` where `x: T`, the candidate impls are:
> 1. Every impl for `T` declared in the package that defines `T`. These are always visible, no matter how the code got the value.
> 2. Every impl for `T` of a trait that is in scope at the call site: imported by name, its module imported, prelude, or a bound on a generic parameter in scope.
>
> Then apply the existing §3c.4 steps. One match: call it. No match: error. Two or more: E0522, disambiguate with `Trait.method(x)`.
>
> Delete "importing the type brings its impls into scope". Rule 1 makes it redundant, because you cannot hold a `T` without depending on `T`'s package.

#### Phase B — Debate highlights

The dedupe left one option family (H) with six sub-questions: V1 home = package or module; V2 whether a whole-module `import m` puts `m.Tr` in scope for method calls; V3/V4 bounds and visibility; V5 the missing-import hint; V6 whether a type imported only for its methods is unused. Round 1 settled V1 on the package (DevOps and AI/ML switched from module) and folded V3/V4 into one clause. V2 and V5 stayed split.

**V1 — the home unit.**

- **DevOps:**

> **V1 — what is "home"? CHANGE: package of T's head constructor (was: module).**
> Sys convinced me: "The current §3.6 rule already needs this index. 'Import `User`, find `impl Display for User` in formatting.bl' only works if the compiler knows the impls of each module in the package." My objection was that the compiler would have to load modules nobody imported. An impl index per package removes that objection. Go scans package headers, and rust-analyzer indexes crates. The LSP needs this index anyway for completion and for the V5 hint.
> The package rule is also better for diagnostics. Under the module rule, moving an impl into `user_impls.bl` in the same package breaks callers in other packages, and they get an error about a refactor they cannot see. Under the package rule a refactor inside a package does not change what callers can call. The orphan rule already uses the package as its unit, so the scope rule should use it too.
> Condition: the spec says the set is fixed by the contents of pkg(H) and does not depend on what got loaded. The compiler and the LSP read the same index.

- **AI/ML:**

> **V1, the "home" unit: CHANGE to package (the package that defines T's head constructor).**
> - With package as home, the scope rule follows the orphan rule exactly: "the impls that the type side of the orphan rule allows go with the type." A model learns one concept ("package"), not two (package for the orphan rule, module for scope).
> - With module as home, a refactor changes behavior downstream. Move `impl Display for User` from `user.bl` to `user_fmt.bl` in the same package, and every caller that did not import `Display` breaks. Agents do this kind of file split often, and nothing at the edit site shows the break.
> - I rejected A′ in Phase A only because of cost. Sys answers that: "The current §3.6 rule already needs this index." The set is closed and fixed by T's package version, so it does not depend on the load graph (see (2)).

**V2 — does `import m` put `m.Tr` in method-call scope?** Four panelists crossed sides in opposite directions, which left the 3-3 that went to the vote:

- **PLT:**

> **V2, whether a qualified-only `import m` puts `m.Tr` in scope for dot calls: CHANGE my position to No.** sys and devops convinced me. §10 says `import m` gives qualified access only, and bare names come only from a selection. `x.zap()` is an unqualified use of a trait member. So it should need `Tr` selected (or prelude, local, or a bound). `m.Tr.zap(x)` still works with `import m`. This gives one meaning of "in scope" for names and for methods, and lets the lint and the resolver read the same fact.

- **AI/ML:**

> **V2, does qualified-only `import m` put `m.Tr` in scope for dot calls? CHANGE to No.**
> - A dot call uses a trait member with no qualifier, which is a bare use. Under §10, bare names come only from a selective import. "No" keeps one rule for all bare names, with no exception for method names.
> - Under H, the remaining trait-side case is rare (extension traits only), so a stricter form costs few tokens.
> - One form means one hint (`import m.{Tr}`), one UnusedImport fact, and no case where `import m` is load-bearing but the file never writes `m.`. That case is the one that confuses readers and agents.
> - `m.Tr.foo(x)` still works through the qualified path.

- **Systems:**

> **V2 — qualified-only `import m` puts `m.Tr` in scope. CHANGE (No → Yes).**
> - My "No" bought nothing in cost. The lookup is the same either way.
> - "Yes" matches §10: the file can name `m.Tr`, so the trait is in scope. It also makes the measured UnusedImport bug go away in a clean way.
> - One `import m` covers one module, not a whole package, so the ambiguity risk stays small.

- **DevOps:**

> **V2 — does qualified-only `import m` put `m.Tr` in scope? CHANGE: yes.**
> I said no. The majority argument is that the file can already write `m.Tr`, so the trait is in scope. I accept it. From the tooling side:
> - `import ext` is what the user wrote in the measured case. With "yes", the lint and the resolver agree on it: it is used, so there is no warning and no fix that breaks the build.
> - With "no", the fix would have to rewrite `import ext` into `import ext` plus `import ext.{Extra}`, which is two imports of one module. That is a worse fix.
> - Go-to-definition and hover show `ext.Extra.zap`, so a reader can still find the trait.

- **Minimalism:**

> **V2, does qualified-only `import m` put `m.Tr` in scope for dot-calls: keep YES.**
> - §10 already says `import m` gives you `m.Tr`. "The trait is in scope" should mean "this file can name the trait". A "no" adds a new difference between bare and qualified names that exists only for method lookup. That is one more rule, and it makes `import m` mean different things in different places.
> - With "yes", the UnusedImport fix is one rule: an import is used if a name or a resolved method goes through it.

**V5 — the missing-import hint, requirement or quality of implementation.**

- **DevOps:**

> - aiml: "If the impl's module is not loaded, the hint can fall back to 'no method'." I reject this. A plain "no method" for a method that exists is the worst result we can give. That is exactly how the measured case fails today, when `ext` is not loaded. With the V1 index there is no reason to fall back. The hint is a requirement, not a nice-to-have.
> - min: "rule 1 needs the compiler to load the modules of `T`'s package that hold impls for `T`." Close, but the spec should say the set comes from an index. It must not say the compiler loads modules. Loading is how the leak happens today.
> - web: "Search for the hint in every module of every package the build depends on." I agree, if "depends on" means the declared dependencies.

- **Minimalism:**

> This is quality of implementation. The spec should say only: "when the compiler knows an impl whose trait is not in scope, the error names the trait and the import line". How far the search goes (loaded modules, the package index, the LSP workspace) is for tooling to decide. If V1 = package, the package index exists anyway, so the hint gets dependency packages almost free. A spec rule here adds nothing to the language.

#### Phase C — Final vote

Q1 overall rule (H / K / G); Q2 home (PKG / MOD); Q3 does a whole-module `import m` put `m`'s traits in method-call scope (YES / NO); Q4 bounds count and the trait must be visible at the call site (ADOPT / REJECT); Q5 the missing-import hint (REQ / QOI); Q6 a type imported only for its methods (UNUSED / OPTIONAL).

Tally: Q1 H 6-0. Q2 PKG 6-0. Q3 3-3 (YES: Systems, Web/Scripting, AI/ML; NO: PLT, DevOps, Minimalism), to Phase D. Q4 ADOPT 6-0. Q5 REQ 4-2 (QOI: PLT, Minimalism), to Phase D. Q6 UNUSED 6-0. Each ballot, verbatim:

##### Systems

**Q1 — Vote: H.**
Reasoning: Resolution is fixed at check time, so all three options give the same machine code. The question is only whether compile-time work is predictable. H makes the candidate set a function of two things: the receiver type and this file's imports. A transitive load cannot change a call's meaning, which today's compiler allows. K is hermetic too, but it needs imports that exist only to switch on lookup. G's scope depends on the path the value took, so its compile-time closure has no clear bound.
Concern: a new owner trait in a dependency's package can turn a working downstream call into E0522 after a version bump, and nothing in the user's diff shows why.

**Q2 — Vote: PKG.**
Reasoning: The orphan and placement rules use the package as the unit, so the visibility unit must be the same. The per-package type-to-impl index costs the same as the one the current §3.6 rule already needs. It is fixed by the package version and can be cached or precomputed for std. MOD would make a file move inside a dependency a breaking change downstream. That costs more than an index.
Concern: if the index is built by loading and checking whole modules instead of scanning impl headers, cold builds of large packages get slower. The implementation must keep the index headers-only.

**Q3 — Vote: YES.**
Reasoning: The cost is the same either way. §10 already lets the file name `m.Tr`, so "in scope = nameable from this file" is one test that both the resolver and the lint can read. `import m` covers one module, not a package, so the added ambiguity surface is small.
Concern: a module that exports many traits widens the dot-call surface for each `import m`. This gives more E0522 risk than a selective import would.

**Q4 — Vote: ADOPT.**
Reasoning: Generic bodies already resolve only through bounds, and mono keeps that trait, so (a) only states existing semantics. (b) stops a private trait from leaking into a type's public method surface, where `Trait.method(x)` could not be written to fix an ambiguity. Neither part adds compile cost.
Concern: if the text writes (b) as "must be `pub`" instead of "visible at the call site", same-module and intra-package cases may be wrongly excluded.

**Q5 — Vote: REQ.**
Reasoning: The hint runs only on the error path, so it costs nothing when compiles succeed. Under PKG the index it needs already exists, so a lookup over T's package and the declared dependencies is cheap and has a fixed bound. A plain "no method" for a method that exists is the failure we measured today. A requirement makes the compiler and the LSP give the same answer.
Concern: if QOI wins, a minimal compiler can still print a bare "no method" for an impl that exists, and the tools will disagree.

**Q6 — Vote: UNUSED.**
Reasoning: Under H a type name drives no method resolution, so by the one general rule (a name or a resolution goes through the import) it is unused. A "does not warn" case would make the lint encode the old §3.6 rule, and the lint and the resolver would disagree. The import stays legal, because the lint only warns.
Concern: users who learned the old rule will see warnings on existing code and may think methods depend on the import until they delete it once.

##### Web/Scripting

**Q1: H**
- Reasoning: A JS, Python or Go developer expects `udp_bind(addr)?.recv_from(512)` to work when the only import is the factory. The spec's own authors made that mistake in §4.4.6. H makes the obvious code correct. Opt-in imports stay only for extension traits, which Kotlin, C# and Rust users already understand.
- Concern: a library that adds a new type-home trait can make a downstream call ambiguous (E0522) without any change in the caller's file. That error must name both traits and give both rewrites.

**Q2: PKG**
- Reasoning: users think in terms of "the library that gives me `Ctl`", not "the file that declares `Ctl`". With MOD, a library author who splits an impl into another file breaks every downstream caller. Nobody can predict that, and it will produce a stream of confused bug reports. The orphan rule already uses the package, so users learn one boundary.
- Concern: the per-package impl index must be fixed by the package contents alone. If an implementation builds it from what got loaded, the load-graph leak comes back.

**Q3: YES**
- Reasoning: a user who writes `import ext` and then `c.zap()` expects it to work, and §10 already lets them write `ext.Extra`. "You imported it, but not that way" is a gotcha that pays for nothing. YES also gives the lint one simple rule: an import is used when a name or a method resolution goes through it.
- Concern: a module import puts every trait in that module in scope, so a large module can add more chances for ambiguity than a selective import does.

**Q4: ADOPT**
- Reasoning: without the bound clause, generic code does not resolve. Without the visibility clause, a method could be callable while its `Trait.method(x)` fix cannot be written. Both are clarifications that every panelist accepts.
- Concern: none of substance. The wording must say "visible at the call site", not a bare "`pub`", so that it tracks §10.

**Q5: REQ**
- Reasoning: the hint is what makes H bearable. Rust's "trait not in scope" is tolerable only because rustc prints the `use` line. A plain "no method" for a method that exists is a dead end for both humans and agents, and it is exactly how the measured case fails today. With PKG the index already exists, so requiring a search of the declared dependency packages costs almost nothing.
- Concern: if the requirement is worded as a search algorithm and not as an outcome, it ties implementations down for no gain. State the outcome: name the trait and the import line for any impl in T's package or in a declared dependency.

**Q6: UNUSED**
- Reasoning: users trust exactly one lint rule: "unused" means you can delete it and nothing changes. Under H, the type name drives no resolution, so it is unused. Examples must not teach an import that the lint then flags.
- Concern: users who learned the old rule will see a warning on code that used to need the import. The warning text should say "methods of `MockClock` come with the value; this import is not needed".

##### PLT

**Q1. Vote: H**
- Reasoning: H keys method scope on the receiver's type, which method lookup already resolves on. So binding, inlining or wrapping an expression in a generic call cannot change its methods. Under the strict orphan rule and one impl per (Trait, Type), scope only filters which method names take part, so coherence is not at risk. H also forbids resolution that depends on the load graph, which is the real defect we measured.
- Concern: a package that adds a home impl whose method name matches a trait the user selected breaks downstream code with E0522. The spec should call this out as a semver hazard.

**Q2. Vote: PKG**
- Reasoning: the orphan rule makes the package the coherence unit, so the scope unit should be the same. With MOD, a file move inside a package, which the orphan rule allows, would change typing in other packages. That puts file layout into the semantics. The set of impls is closed and fixed by the version of T's package, so PKG is as hermetic as MOD.
- Concern: the spec must state that the set comes from the contents of pkg(H). It must not say it comes from whatever modules got loaded, or the leak returns through the back door.

**Q3. Vote: NO**
- Reasoning: under §10, bare names come only from a selection, and a dot call `x.zap()` uses the trait member's name with no qualifier. Haskell (`import qualified M` gives `M.method`, not `method`) and Rust (`use m;` does not enable `m::Tr` methods) both draw the line here. NO gives one meaning of "in scope" for every bare name, and `m.Tr.zap(x)` still works.
- Concern: if YES wins, one `import m` silently brings every trait of m into dot scope. That widens E0522 exposure to traits the file never names, so the ambiguity diagnostic must name the import that brought each trait in.

**Q4. Vote: ADOPT**
- Reasoning: a bound is an assumption in the typing context, so without (a) generic bodies have no typing rule. Without (b), `x.m()` would work while `Tr.m(x)` fails, which is a visibility hole, and the E0522 fix could not be written.
- Concern: the text must state (b) for home impls too, or a private helper trait in T's package leaks methods onto T.

**Q5. Vote: QOI**
- Reasoning: the hint does not affect what type-checks, so its search scope has no effect on soundness and does not belong in the language rule. The spec should require the form (name the trait and give the import line when known), not the search.
- Concern: under QOI, some implementation may ship a plain "no method" for a method that exists. That would be a quality bug, and the compiler and the LSP should still share the index.

**Q6. Vote: UNUSED**
- Reasoning: under H, a type name drives no resolution, so the one general rule (an import is used when a name or a resolution goes through it) marks it unused. If it did not warn, the lint would encode the old §3.6 rule and disagree with the resolver.
- Concern: users who learned the old rule will see new warnings on `{mock_clock, MockClock}`. The fix (delete the name) is safe, but the release notes should say why.

##### DevOps

**Q1 — H**
Reasoning: Under H, the methods at a call site depend only on the receiver's type and this file's imports. That makes completion, hover and the "missing import" fix deterministic, and an edit in `helper.bl` can no longer change resolution in `main.bl`. K makes every factory import also import a type name only to switch on lookup, so the lint needs a special case or it suggests a fix that breaks the build. G gives an error message the user cannot act on.
Concern: a library that adds a home impl can give downstream code a new E0522 error even though that code did not change. The E0522 text must name both traits with full paths and give both `Trait.method(x)` fixes.

**Q2 — PKG**
Reasoning: I changed from MOD in round 1. Under MOD, splitting an impl into a sibling file in the same package breaks callers in other packages, and they get an error about a refactor they cannot see. The per-package impl index that PKG needs is the index the LSP and the hint need anyway. It is closed and fixed by the package version, so it does not depend on the load graph.
Concern: if the compiler builds that index by loading modules instead of reading impl headers, compile time grows and the leak comes back by another route. The spec text must say the set comes from pkg(H), not from what got loaded.

**Q3 — NO**
Reasoning: I change my round-1 "yes". It rested on "with No, the fix gives two imports of one module", and that is false: under §10 a selective import keeps qualified access, so the fix replaces `import ext` with `import ext.{Extra}` in place, as one line. With NO, every import's effect shows in the text. A reader or an agent who sees `import ext` and no `ext.` in the file can delete it safely. With YES, that import silently drives `.zap()`, and a whole-module import puts all of the module's traits into dot-call scope, which means more E0522 collisions.
Condition: for `import ext` plus `c.zap()`, the error must say "`import ext` does not bring trait methods into dot-call scope; change it to `import ext.{Extra}`", not just "no method".
Concern: users from Python and JS will expect `import ext` to work, so this specific error message carries the whole cost of NO.

**Q4 — ADOPT**
Reasoning: Without (a), generic bodies have no typing rule. Without (b), method syntax could reach a trait the user cannot name, and then neither the `Trait.method(x)` disambiguation nor the import hint could be written. Both rules follow from ordinary visibility, and the spec should state them once.
Concern: "visible" must use the same test in the resolver, the hint and the LSP, or completion will offer methods that do not type-check.

**Q5 — REQ**
Reasoning: The bug we measured is a plain "no method" for a method that exists. That is a dead end for people and agents alike. The PKG index makes the search one lookup per declared dependency, so a hard requirement costs little. If the spec leaves it as quality of implementation, the compiler and the LSP will differ in which hint they give. Wider searches (for example the workspace in the LSP) can stay optional.
Concern: a common method name could list many traits. Show three at most, rank them, and say "and N more".

**Q6 — UNUSED**
Reasoning: The one lint rule users trust is "unused means you can delete it and nothing changes". Under H, removing a type name the code never writes cannot break resolution, so the fix is always safe. OPTIONAL would make the lint encode the old §3.6 rule and disagree with the resolver. That disagreement is the bug we are fixing.
Concern: existing spec examples and stdlib docs that import `MockClock` and similar types must be cleaned up in the same change, or users will copy code that warns.

##### AI/ML

**Q1: H**
- Reasoning: The obvious code (`udp_bind(addr)?` then `sock.recv_from(...)`) becomes correct, and the spec's own authors wrote exactly that code. Each factory import loses one name that a model has no way to predict from the call site. Resolution depends only on the receiver's type and this file's imports, so a model can work out the answer from local text.
- Concern: A library can add a type-home trait whose method name clashes with a trait the user imported, so a dependency bump causes E0522 at call sites that did not change.

**Q2: PKG**
- Reasoning: I changed my vote in round 1. "Package" is the orphan rule's own unit, so a model learns one boundary, not two. Under MOD, an agent that splits a file inside a library breaks downstream callers, and nothing at the edit site shows it.
- Concern: Packages with no precomputed index may give a slower or partial first build, so the compiler and the LSP must read the same index.

**Q3: YES**
- Reasoning: I change my round-1 "No". Min and devops showed that "No" adds a bare-versus-qualified difference that exists only for method lookup. That is one more decision point, and it brings back Rust's "`use ext` but not `use ext::Extra`" error, which models make often. With "Yes", the test is "can this file name the trait?", which §10 already answers. The UnusedImport rule then stays one rule.
- Concern: With `import m` of a large module, a reader cannot see which trait gives `.foo()` without hover, so the ambiguity error must name the full trait path.

**Q4: ADOPT**
- Reasoning: Without (a), generic code has no rule for calling methods through a bound. Without (b), `x.m()` works while `Tr.m(x)` cannot be written, so an ambiguity could not be fixed. Both clarify the rule, and stating them stops a model from inferring the wrong edge cases.
- Concern: None of substance. The wording must say "visible at the call site" and not a bare "pub", so that it follows §10 as it changes.

**Q5: REQ**
- Reasoning: For an agent, a plain "no method" for a method that exists is a dead end. It leads to guesses, hallucinated method names and wasted turns. A required, machine-applicable import line is a one-step fix. Under PKG, the index this needs already exists, so the requirement costs little.
- Concern: If the spec sets the search scope too tightly, an implementation detail (the index format) leaks into the spec. Keep the wording to "T's package and declared dependencies".

**Q6: UNUSED**
- Reasoning: Under H the type import does nothing, so an example that keeps it teaches models a dead import. "Unused means you can delete it with no change" is the only lint rule that agents can apply safely without review.
- Concern: Old examples and existing training data that keep `{mock_clock, MockClock}` will warn. The warning's fix must be a safe automatic deletion.

##### Minimalism

**Q1 — Overall rule: H**
- Reasoning: H replaces the "type imported" condition with a fact the checker already has, the receiver's type. It also closes today's leak through the load graph. So it removes a rule and adds none. K keeps an import that exists only to switch on lookup. G adds a new concept: which types a signature "mentions".
- Concern: a type's package adds an owner trait whose method name matches an extension trait that callers imported, and the callers get a new E0522 they did not cause.

**Q2 — Home: PKG**
- Reasoning: the orphan rule and the placement rule already use the package. One boundary for coherence and for scope is fewer concepts than two. MOD makes file layout inside a package a breaking API change, which is a hidden rule. The index PKG needs is an implementation cost, and the current §3.6 text already needs it.
- Concern: the spec text says "load" where it should say "index", and then implementations bring back load-graph effects.

**Q3 — Qualified-only `import m` counts: NO (changed from my round-1 YES)**
- Reasoning: plt's argument persuaded me. `x.zap()` is a bare use of a trait member, and §10 already says bare names come only from a selection. "No" reuses that rule with no exception. "Yes" gives `import m` a hidden second effect that §10 does not state. `m.Tr.zap(x)` still works, so nothing becomes impossible. The fix-it is one line: change `import ext` to `import ext.{Extra}`.
- Concern: if YES wins, §10 must then say that a qualified import also enables dot-calls, or the two sections will disagree.

**Q4 — Bounds count, trait visible at call site: ADOPT**
- Reasoning: neither is new. Generic code already resolves through bounds, and visibility rules already apply. Writing them down makes the rule complete, and it adds no behavior.
- Concern: none on substance. The wording should cite the existing visibility rules and not restate them.

**Q5 — Hint: QOI**
- Reasoning: the hint is a diagnostic and does not decide what type-checks. A fixed search scope in the spec ties the language to one way to build the compiler. The spec should say that the error names the trait and its import line when the compiler knows one. With PKG the index exists anyway, so a good compiler will find it.
- Concern: under QOI, a weak implementation can still give a bare "no method" for a method that exists.

**Q6 — Type imported only for methods: UNUSED**
- Reasoning: under H a type name drives no resolution, so the one general UnusedImport rule flags it with no special case. Removing it never breaks the build, so the fix-it is safe. Examples must not teach an import that the lint flags.
- Concern: users who learned the old rule see warnings on imports they still think they need, so the warning text should say why.

#### Phase D — Round 2 (Q3 and Q5)

One focused debate round on Q3 and Q5, then a silent re-vote. Debate replies, verbatim:

- **Systems:**

> # Phase D1 — Systems
>
> **Q3: CHANGE to NO.** This was my Phase A position, and the NO side gave the better argument.
> - Devops: "A reader or an agent who sees `import ext` and no `ext.` in the file can delete it safely." That is a property of the text alone, and it costs nothing to check. YES loses it.
> - Plt and min: §10 bare names come only from a selection. NO reuses that rule. YES adds a hidden second effect.
> - My YES rested on "same cost, one test". NO is also one test ("is the trait name bound bare?"), and it gives a smaller dot-call surface, so there are fewer E0522 cases.
> - The fix-it is one in-place edit: `import ext` becomes `import ext.{Extra}`.
> - Condition (same as devops): the error for `import ext` plus `.zap()` must name that exact edit.
>
> **Q5: HOLD REQ, with outcome wording.**
> - Plt and min are right that the spec must not fix a search algorithm.
> - They are wrong that a diagnostic is out of scope. The spec already requires specific help text (E0522 paste-ready lines, §3c).
> - Wording: "When an impl for T with method `foo` exists in T's package or in a declared dependency, and its trait is not in scope, the error names the trait and gives the import line." This is an outcome, not an index format. PKG makes it cheap.
> - A wider search, such as the LSP workspace, stays optional.

- **Web/Scripting:**

> **Q3: HOLD YES.**
> - plt cites Rust `use m;`. That error ("trait not in scope") is among Rust's most-searched errors. Copying the shape that hurts is not a reason.
> - devops is right that the fix is one line in place. Its own concern still stands: "this specific error message carries the whole cost of NO". Under YES, users never see that error.
> - min: "`import m` gets a hidden second effect". It is not hidden. The file can name `m.Tr`, and "in scope = nameable here" is the plain-English meaning.
> - The ambiguity risk is real but small. Under H, trait-side impls are extension traits only, which are rare.
> - If NO wins, I require devops's exact error text as part of the decision.
>
> **Q5: HOLD REQ, worded as an outcome, not an algorithm.**
> - To plt/min: I agree the search mechanism is implementation-defined. The spec need not fix how the compiler searches.
> - The *result* is user-facing, though: "If an impl of a trait with `foo` for `T` exists in T's package or in a declared dependency, the error MUST name the trait and the import line."
> - That names no index or search method, only an outcome every compiler can meet under PKG.
> - Under QOI, "no method" for a method that exists stays legal. That is the exact failure we measured.

- **PLT:**

> PLT, Phase D
>
> Q3: HOLD NO.
> - aiml says "No" adds "a bare-versus-qualified difference that exists only for method lookup". It is the other way round. §10 already draws that line for every name. YES is the exception, because it lets a qualified import supply a name used bare: the `zap` in `x.zap()`.
> - sys and aiml say "in scope = nameable from this file". That holds only if `x.zap()` also counts as naming. It does not: the file names `zap`, not `ext.Extra.zap`.
> - Under NO the fix is one line in place (`import ext` becomes `import ext.{Extra}`), as devops showed. Under YES, an `import ext` that the file never writes `ext.` for can still be load-bearing, which readers and agents cannot see.
> - I support devops' condition: the error must name `import ext` and give the replacement line.
>
> Q5: CHANGE to REQ, if the spec states the outcome and not an algorithm. The wording (web/aiml): "for an impl in T's package or in a declared dependency, the error names the trait and its import line." This requires completeness of a diagnostic. It does not change typing, so it costs soundness nothing. My QOI vote was against fixing the search mechanism, and this wording does not fix it.

- **DevOps:**

> **Q3: I hold NO.**
> aiml says NO "brings back Rust's `use ext` but not `use ext::Extra` error". That error hurts in Rust when the hint is weak. Here the hint is required: "`import ext` does not bring trait methods into dot-call scope; change it to `import ext.{Extra}`". It is a one-line, machine-applicable fix.
> sys says YES gives one test: "nameable from this file". It does, but it hides the effect. Under YES, `import ext` can drive `.zap()` while the file contains no `ext.`. A reader, an agent or a code reviewer sees an import that looks dead and deletes it. Under NO, the trait name `Extra` is written in the file, so grep and review can see why the import is there.
> Both sides name the same concern about YES: more E0522 collisions from traits the file never names.
>
> **Q5: I hold REQ, worded as an outcome (web, aiml).**
> "When an impl for T with that method exists in T's package or in a declared dependency, and its trait is visible, the error names the trait and gives the import line." No search algorithm and no index format go in the spec.
> This meets plt's and min's concern that the spec should not tie down the implementation. It also closes the gap both of them name: under QOI, a bare "no method" for a method that exists stays allowed.

- **AI/ML:**

> # AI/ML, Phase D round 1
>
> **Q3: CHANGE to NO.**
> Devops's point decides it for me. Under NO, "every import's effect shows in the text", so an agent that sees `import ext` with no `ext.` can delete it safely. Agents make that edit with no review. Under YES the import is load-bearing but nothing in the text shows it, which is the defect we measured.
>
> My YES case rested on Rust's "`use m` but not the trait" error. Under H that error is now rare: type-home methods need no import, so it is left only for extension traits. The fix is also a one-line in-place edit, because a selective import keeps qualified access. NO also keeps §10's bare-name rule with no exception, and it gives fewer chances for E0522.
>
> Condition (devops's): for `import ext` plus `c.zap()`, the error says that `import ext` does not enable dot calls and gives `import ext.{Extra}` as a machine-applicable fix.
>
> **Q5: HOLD REQ, worded as an outcome (web).**
> Plt and min are right that the search scope does not affect soundness. But the spec already fixes diagnostic codes and fix forms, and for agents this hint decides whether they make progress. Require the outcome, not an algorithm: "for an impl in T's package or a declared dependency, the error names the trait and its import line." That ties no implementation to an index format.

- **Minimalism:**

> Minimalism, Phase D
>
> Q3: HOLD NO.
> - aiml says NO "adds a bare-versus-qualified difference that exists only for method lookup". That difference already exists in §10. NO reuses it. YES is the exception: it is the only place where a qualified import gives a bare use.
> - sys and web say the test is "can this file name the trait?". Under §10 the real test is "can this file name it bare?", and `x.zap()` is a bare use.
> - devops adds a fact for NO: an `import ext` with no `ext.` in the file can be deleted safely. With YES, it cannot be.
> - YES also widens E0522 exposure to traits the file never names. All three YES voters list this as their own concern.
> - The cost of NO is one error message, and devops already specified it: "change `import ext` to `import ext.{Extra}`".
>
> Q5: CHANGE to REQ, with web's wording.
> - My objection was to a search algorithm in the spec. Web's form states an outcome: "name the trait and the import line for any impl in T's package or a declared dependency". That is a fixed, small set, and the PKG index serves it. It ties down no implementation, and it removes the failure we measured.

Re-vote: **Q3 NO 6-0** (Systems, Web/Scripting and AI/ML switched from YES). **Q5 REQ 6-0** (PLT and Minimalism switched from QOI once the requirement stated an outcome, not a search). Ballots, verbatim:

##### Systems

**Q3 — Vote: NO.**
Reasoning: `x.zap()` is a bare use of a trait member, and §10 gives bare names only through a selection. NO reuses that rule with no exception. Each import's effect then shows in the text, so a tool or a reader can check an import by looking at the file alone. It also keeps the dot-call surface small, which means fewer E0522 cases.
Concern: if the required error text for `import ext` plus `.zap()` is weak, NO repeats Rust's most-searched error. The decision must fix that text: "change `import ext` to `import ext.{Extra}`".

**Q5 — Vote: REQ.**
Reasoning: The hint runs only on the error path, so it costs nothing when compiles succeed. Under PKG the set to check (T's package and the declared dependencies) is fixed and small. Stating the outcome, not a search method, leaves the implementation free and removes the "no method for a method that exists" failure we measured.
Concern: a common method name can match many traits. The rule should allow a capped, ranked list ("and N more") so the error does not flood.

##### Web/Scripting

**Q3: NO (changed from YES)**
- Reasoning: devops's point wins on my own terms. In Python and JS, an import whose name never appears in the file looks dead, and both people and linters delete it. Under YES, that deletion breaks `.zap()`, and nothing in the text warns you. Under H, this case is left only for extension traits, which are rare. The cost of NO is one error with a one-line fix applied in place.
- Concern: the whole cost of NO rests on the error text, so the decision must require it: "`import ext` does not bring trait methods into dot-call scope; change it to `import ext.{Extra}`", as a machine-applicable fix.

**Q5: REQ**
- Reasoning: a plain "no method" for a method that exists is the dead end we measured, for humans and agents alike. The outcome wording fixes no search method and no index format. It requires only that an impl in T's package or in a declared dependency produces the trait name and the import line. Under PKG, every compiler can meet that.
- Concern: a common method name can match many traits, so the error should rank its suggestions and cap the list ("and N more").

##### PLT

Q3. Vote: NO
- Reasoning: `x.zap()` uses `zap` bare, and §10 gives bare names only through a selection. NO reuses that rule with no exception. Every import's effect then shows in the text, and the dot-call surface stays limited to traits the file names, so there are fewer E0522 cases.
- Concern: the whole cost of NO rests on one diagnostic. The decision must include devops' exact text: "`import ext` does not bring trait methods into dot-call scope; change it to `import ext.{Extra}`". It must be a machine-applicable fix.

Q5. Vote: REQ
- Reasoning: the requirement is about the outcome and covers a closed set, T's package plus the declared dependencies. It fixes no search method, so the spec ties down no implementation. It does not change typing, so soundness is unaffected, and it rules out the bare "no method" failure we measured.
- Concern: the wording must say "trait visible at the call site" (Q4). Otherwise the hint could suggest importing a trait that the user cannot import.

##### DevOps

**Q3 — Vote: NO**
Reasoning: Under NO, the text of the file shows what each import does. If a file has `import ext` and never writes `ext.`, a reader, an agent or a lint can delete that import safely. The cost of NO is one error message. It must say that `import ext` does not bring trait methods into dot-call scope, and it must give the in-place fix `import ext.{Extra}`. NO also keeps the §10 bare-name rule with no exception, and fewer traits in dot-call scope means fewer E0522 errors.
Concern: if the compiler ships without that exact error and fix, users from Python and JS will meet a plain "no method" after `import ext`. NO depends on that message to be acceptable.

**Q5 — Vote: REQ**
Reasoning: Under PKG, the spec can require this outcome for a small, fixed set: T's package and the declared dependencies. It names no search method and no index format, so it does not tie down the compiler. It removes the failure we measured, where the compiler gives a plain "no method" for a method that exists. It also makes the compiler and the LSP give the same hint.
Concern: for a common method name the hint can list many traits, so the spec or the tooling chapter should cap the list, for example at three entries plus "and N more".

##### AI/ML

**Q3: NO**
- Reasoning: Under NO, the file text shows the effect of each import. So an agent that sees `import ext` with no `ext.` can delete it safely, and agents make that edit with no review. Under H the remaining cost of NO falls only on extension traits, and a one-line, machine-applicable fix covers it. NO keeps §10's bare-name rule with no exception and gives fewer chances for E0522.
- Concern: Models trained on Python and JS will write `import ext` then `c.zap()`, so devops's exact error text ("`import ext` does not enable dot calls; change it to `import ext.{Extra}`") must be part of the decision.

**Q5: REQ**
- Reasoning: For an agent, a plain "no method" for a method that exists is a dead end that leads to guessed method names. The outcome wording fixes what the error must say and fixes no search method or index format, so it does not tie down an implementation. With PKG, every compiler can meet it at low cost.
- Concern: When a common method name matches many traits, the hint can get long, so it should list a few ranked choices and then say "and N more".

##### Minimalism

Minimalism, Phase D silent re-vote

Q3: NO
- Reasoning: §10 already says a bare name comes only from a selective import, and `x.zap()` uses `zap` bare. NO reuses that rule with no exception. Every import's effect then shows in the text, so a reader or an agent can safely delete an `import ext` that the file never writes `ext.` for. The cost is one error message with a one-line, in-place fix.
- Concern: the decision must require devops's exact error text ("`import ext` does not bring trait methods into dot-call scope; change it to `import ext.{Extra}`"). Without it, NO repeats Rust's worst error.

Q5: REQ
- Reasoning: the wording now states an outcome, not a search method or an index format, so my objection is gone. The set it covers (T's package and the declared dependencies) is small and fixed, and the PKG index already serves it. It makes the failure we measured, a plain "no method" for a method that exists, a spec violation.
- Concern: a common method name can match many traits, so the error needs a cap on the list (devops: three at most, then "and N more"). This should be QOI, not spec.

### Final Spec

```blink
// Package clockm, src/clockm.bl
pub type Ctl { ms: Int }

pub trait CtlOps {
    fn advance(self, ms: Int) -> Ctl
}

impl CtlOps for Ctl {
    fn advance(self, ms: Int) -> Ctl { Ctl { ms: self.ms + ms } }
}

pub fn make() -> Ctl { Ctl { ms: 0 } }

// Package ext, src/ext.bl. It depends on clockm.
import clockm.{Ctl}

pub trait Extra {
    fn zap(self) -> Int
}

impl Extra for Ctl {
    fn zap(self) -> Int { self.ms * 2 }
}

// Package app. It depends on clockm and ext.
import clockm.{make}
import ext.{Extra}

fn run() -> Int {
    let c = make().advance(10)    // OK: the CtlOps impl lives in Ctl's package
    c.zap()                       // OK: the selective import puts Extra in scope
}
```

With `import ext` in place of `import ext.{Extra}`:

```
error[UnresolvedMethod]: no method `zap` in scope for type `Ctl`
 --> app.bl:6:7
  |
6 |     c.zap()
  |       ^^^ `ext.Extra` has `zap` for `Ctl`, but `Extra` is not in scope
  |
  = note: `import ext` does not bring trait methods into method-call scope
  = help: change `import ext` to `import ext.{Extra}`
```

- An impl that lives in the package of the receiver type `T` goes with every value of `T`. No import is needed to call its methods (§3.6).
- Any other impl needs its trait in scope at the call site: declared in the file, selectively imported, in the prelude, or named by a bound on a type parameter in scope.
- The candidate set is fixed by the contents of `T`'s package, never by which modules the build happened to load.
- A whole-module `import m` does not put `m`'s traits in method-call scope. `m.Tr.f(x)` still works through the qualified path.
- Bounds count. A bound's trait must itself be visible at the call site.
- E0505 must name the trait and give the import line when the compiler knows an impl in `T`'s package or a declared dependency. The spec fixes the outcome, not the search; the list may be ranked and capped.
- E0522 names each owner's full path and the import that brought it in.
- A type imported only for its methods is unused (W0602). Examples import the factory only.
- Adding a home impl whose method name clashes with an extension trait in a caller's scope is a breaking change for `T`'s package.
- The rule closes the transitive-load leak, so code the compiler accepts today may stop compiling.
