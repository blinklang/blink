[< All Decisions](../DECISIONS.md)

# A Method Called Through Its Type Name — Design Rationale

**Gap:** §2.12.3 says the `T.` namespace holds variants, type-scoped constants, type-scoped functions and associated functions, and no method that takes `self`. It did not say what the checker does with `Int.abs(-3)`, `Str.len("abc")`, `Ptr.deref(p)`, a derived `P.clone(a)` or a user `Level.shout(u)`. In practice the forms split by type: `Str.len(s)`, `List.len(xs)` and a user `U.shout(u)` compiled and ran, while `Int.abs(-3)`, `Ptr.deref(p)` and a derived `T.clone(a)` passed `blink check` and stopped the build with an internal error, which breaks the promise of a clean check (§6.7).

**Result:** Q1 and Q3 passed 6-0 in Phase C. Q2 (which code) was 4-2 in Phase C and 6-0 in Phase D, after min and plt moved. The package is:

- `T.m(recv, args)`, where `m` takes `self`, is an error on every type: a built-in type, a user type and a type parameter. `Trait.m(recv)` stays legal.
- A new code, `MethodThroughTypeName` (E0567). Its message names the method and never says "unresolved": "`abs` is a method of `Int`, not a function of the type". The message is part of the rule.
- The fix writes `recv.m(rest)`, with parentheses where the receiver needs them: `Int.abs(-3)` becomes `(-3).abs()`. It is machine-applicable only when a first argument exists, its type is `T`, and `recv.m(rest)` finds one owner. A first argument of another type gets a note and no fix.
- A bare `T.m` with no call gets the same code and a closure in the help, and no fix. The closure annotates its parameter when `T` is not generic.
- E0567 and E0505 split every failed lowercase `T.name` with no gap and no overlap. E0567 fires when `name` is exactly a method with `self` that some owner gives `T`; E0505 fires otherwise. An exact method name beats a near name.
- With one owner, the help is the fix, plus a `Trait.m(recv)` line only for a trait that a program can write and that is not sealed. With two or more owners, there is no fix and the help lists `Trait.m(recv)` for every owner, sealed owners too.
- The rollout follows §8.16.1, with the same message and fix at each severity.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal, debate and vote rounds. The excerpts below are verbatim; some are cut to one section. Ticket identifiers are cut from them.

#### Phase A — Independent proposals

All six seats chose: not a call form on any type, one check error, a fix to `recv.method(args)`. Four seats (web, plt, sys, devops) asked for a new code; aiml and min chose E0505. The seats also differed on the conditions of the machine fix, on the `Trait.m(recv)` help line, on a bare `Type.method`, and on the rollout of `Str.len` and `List.len`.

- **Position (sys):**
> Short version: the form gives the hardware nothing. `Str.len(s)`, `s.len()` and `Sized.len(s)` must all compile to the same direct call to the same mono symbol. A spelling that adds no information about *which* code runs and has no cost advantage is pure surface area. Worse, it does not name the owner. So it reopens every E0522 case and gives no way out of it. It also collides with the one `T.` namespace in §2.12.3.

- **Position (web):**
> `Type.name(...)` calls only what lives in the `T.` namespace (§2.12.3): type-scoped functions and
> associated functions (no `self`). An instance method (a trait method with `self`) is not in that
> namespace, for a built-in type or a user type. Calling it through the type name is a check-time
> error with a fix to `recv.method(args)`.
>
> The 90% case already has a spelling (`x.len()`), and the disambiguation case already has one
> (`Sized.len(x)`, `(Trait for T).m(x)`). A third spelling buys nothing but questions about which one
> to use.

- **Position (plt):**
> `Type.method(recv, args)`, where `method` takes `self`, is **not a call form, on any type**: built-in, user, or type parameter. It is an error at check with a machine-applicable fix to `recv.method(args)` when that fix is sound. The same holds for `Type.method` with no call (a function value).

- **Position (devops):**
> The spec already points this way. I ask the panel to state it outright, and to make built-in types follow the rule user types follow.
>
> - §2.12.3 *One `T.` namespace*: after `T.` you find variants, type-scoped constants, type-scoped functions, and associated functions from trait impls. Instance methods are not in that list.
> - §2.12.3 *Functions*: "Method syntax `x.name()` never reaches a type-scoped function. Only `T.name(...)` calls it." The other direction (`T.name(x)` never reaches a method) gives the same clean split.
> - §3c.4 *No Inherent Methods*: each method belongs to a trait. So `Trait.method(recv)` already reaches every method that has a receiver, built-in methods included (sealed ops traits too). A third spelling gives you no call that you cannot already write.
> - §3 *Variant Construction*, member case: `K.x` names "a type-scoped function, an associated function, or a type-scoped constant". An instance method does not appear.

- **Position (aiml):**
> `Type.method(recv, args)`, where `method` is an instance method, is **not a call form on any type**, built-in or user. It is an error at check (E0505 UnresolvedMethod), with a specific help and a **machine-applicable** fix to `recv.method(args)`. Where `recv.method(args)` is ambiguous (E0522), the fix is `Trait.method(recv, args)` instead.
>
> Each prefix then reaches one namespace, and an AI can learn this from the spec alone:

- **Position (min):**
> What if we just don't? We already don't. §2.12.3 *Member case* (sections/03_types.md:2564) lists what
> a lowercase `K.x` can name: a type-scoped function `fn K.x`, an associated function from a trait impl,
> or a type-scoped constant. "When `K` has none of these, the site is an unknown member of the type
> path." An instance method is in none of those sets. §3.4 (03_types.md:3349) and §3c (03c_protocols.md:958)
> state the mirror rule: method syntax `x.name()` never reaches the `T.` namespace. Two namespaces, no
> cross-over in either direction. The answer is in the text; the compiler leaks.
>
> The leak is an accident, not a design. I probed gen1:


#### Phase B — Debate highlights

The moderator merged the six proposals into four points of agreement (C1–C4) and five points that differed (V1–V5). Round 1 ran once. All six replies ended `STABLE: ready to vote`.

- C1: `Type.method(recv, args)`, where `method` takes `self`, is not a call form on any type. It is a check error.
- C2: the fix rewrites to `recv.method(rest)`, with parentheses around a receiver that is not a primary or postfix expression.
- C3: `Str.len("abc")` and `List.len(xs)` stop compiling and get the same error and fix. `Trait.method(recv)` stays legal.
- C4: when `recv.method(args)` would be E0522, there is no machine fix, and the help lists `Trait.m(recv)` for each owner.

**V1. Which code.** Four seats asked for a new code in Phase A. In Phase B plt moved to E0505 and min kept it; sys, web, devops and aiml kept the new code and named E0505 as their second choice.

- **V1 (plt (moves to E0505)):**
> Min's argument fits the typing rule I gave in Phase A. The judgment that fails at `Int.abs(-3)` is the lookup of `abs` in the `T.` namespace. That namespace has no receiver members, so by the rule `abs` is an unknown member of `Int.`. A diagnostic code should name the judgment that failed, and the repair goes in the help. So this site and `K.zed` get one code. Two codes for one failed lookup would mean the code depends on what a second lookup in another namespace finds.
>
> What I keep: the message must not say the method does not exist. The message names the method and says it takes a receiver:
>
> ```blink
> fn main() ! IO {
>     let n: Int = Int.abs(-3)
>     io.println("{n}")
> }
> ```
> ```
> error[UnresolvedMethod]: `abs` is a method of `Int`, not a function of the type `Int`
>  --> b1.bl:2:18
>   |
> 2 |     let n: Int = Int.abs(-3)
>   |                  ^^^^^^^^^^^ a method takes its receiver before the dot
>   |
>   = help: call it on the value: `(-3).abs()`
> ```
>
> If the sibling panel picks a code other than E0505, this site follows that code.

- **V1 (min):**
> My Phase A said "the sibling's code". The sibling's six seats all chose E0505, so my position is now
> E0505. I concede the point plt, web and devops make about the **message**: "unresolved method `.abs`
> on type Int" is false when the compiler knows the method exists. Fix the message and the help, not the
> code.
>
> A code is for a class of mistake a tool filters on. "You named a member of `T.` that is not in the
> `T.` namespace" is one class, whether the name is a typo (`K.zed`) or a method (`Int.abs`). The repair
> differs, but repairs differ inside E0505 already: its catalog row carries the effect-handle fix, the
> module-qualifier fix, the removed-names fix, and more. Those are each a help line and a fix on one
> code. A new code here is a second entry in the catalog, a second row in every tool table, and a
> choice the user must learn ("did I get E0505 or MethodThroughTypeName?") for no change in what they
> do: they read the help and take the fix.
>
> ```
> error[UnresolvedMethod]: `abs` is a method of `Int`, not a function of the type `Int`
>   --> b1.bl:2:18
>   |
> 2 |     let n: Int = Int.abs(-3)
>   |                  ^^^^^^^
>   = help: call the method on the value: `(-3).abs()`
> ```
>
> If the panel picks a new code, I will not block on it, but I vote E0505.

- **V1 (web):**
> Min's point holds for the letter of the current text: `Int.abs` is an unknown member of the `Int.`
> namespace. But the user's model is "`abs` is a thing on Int". They know it is there, because
> `(-3).abs()` works. If two errors have different causes and different repairs, they need two codes:
>
> ```blink
> type Level { n: Int }
>
> fn main() ! IO {
>     let a = Level.zed(1)            // the member does not exist at all: sibling panel's code
>     let b = Int.abs(-3)             // the member exists, wrong call form: MethodThroughTypeName
> }
> ```
>
> `blink explain` for the first teaches "check the spelling". For the second it teaches "methods go
> on the value". An LLM that reads the code alone (no message) gets the repair right only if the codes
> differ. That is the 5-minute test for tooling.
>
> If the panel picks one code, I accept E0505 on one condition. The message must not say
> "unresolved": it says "`abs` is a method of `Int`, not a function of the type", with the same help
> and fix. The false message is the part I will not vote for. The code number matters less.


**V2. When the fix is machine-applicable.** Min moved the rule from "never" for a wrong receiver type to a condition. Web, devops and aiml moved to it; sys and plt kept it.

- **V2 (min):**
> I add the one-owner condition. The fix is machine-applicable when all of these hold:
>
> 1. there is a first argument;
> 2. its type is `T` (any instance of a generic `T`);
> 3. the rewritten `a.m(rest)` resolves to exactly one method and adds no diagnostic (no E0522).
>
> Else the help shows the form and there is no fix. That is sys's rule plus web's and devops's "resolves
> to one" in one list. aiml's unconditional "machine-applicable" is wrong: `Str.len(xs)` with
> `xs: List[Int]` rewrites to `xs.len()`, which compiles and means something else.
>
> ```blink
> fn main() ! IO {
>     let xs = [1, 2]
>     io.println("{Str.len(xs)}")   // E0505, help shows `xs.len()` but no fix: xs is List[Int], not Str
> }
> ```

- **V2 (devops (moves)):**
> My rule ("when `a0.m(...)` resolves to one method") was too loose. min's example breaks it: the rewrite compiles, and the program then does something different. That is the worst result a machine fix can have.
>
> The rule I now hold: the fix is machine-applicable only when all three of these are true:
> - (a) a first argument exists;
> - (b) its type is `T` (any instance of a generic `T`);
> - (c) one owner gives `T` the method `m`, so the rewritten call has no E0522.
>
> In all other cases the help shows the form and there is no fix.
>
> ```blink
> fn main() {
>     let xs = [1, 2]
>     let n = Str.len(xs)
> }
> ```
>
> ```
> error[MethodThroughTypeName]: `len` is a method of Str, not a function of the type
>   --> c.bl:3:13
>   |
> 3 |     let n = Str.len(xs)
>   |             ^^^^^^^^^^^ `len` takes a receiver of type Str
>   |
>   = note: the first argument `xs` has type List[Int], not Str
>   = help: call the method on a Str value, as `s.len()`
> ```
>
> This diagnostic has no `fix` field. `xs.len()` would compile to List's `len`.

- **V2 (aiml (concedes)):**
> The fix is machine-applicable only when (a) a first argument exists, (b) its type is `T` (any instance of a generic `T`), and (c) `recv.method(rest)` resolves to one owner. My Phase A file left out (b). min's example shows why it matters. A fix that compiles to a different method is the worst output for an agent loop, because nothing tells it the meaning changed:
>
> ```blink
> fn main() {
>     let xs = [1, 2, 3]
>     let n = Str.len(xs)      // error, help shows `xs.len()`, NO fix
> }
> ```
>
> The note names both types ("`xs` is List[Int], not Str"). `Int.abs()` with no argument shows the form `x.abs()` in the help, with no fix.


**V3. The `Trait.m(recv)` help line.** Sys held that the help names every owner trait. Plt, min, web, devops and aiml limited it: one owner gets the fix and, for a trait a program can write, one trait line; two or more owners get every owner.

- **V3 (plt (moves)):**
> - **One owner:** one help line, `recv.m(rest)`. Add a second line `Trait.m(recv, rest)` only when the owner is a trait that is not sealed (`Clone.clone(a)`, `Shout.shout(u)`). With one owner, a sealed ops trait (`Sized.len`, `StrOps.trim`) in the help is noise. A user does not need it, and some built-in methods (`Int.abs`, `Ptr.deref`) may have no trait name the user can write.
> - **Two or more owners:** list every owner's `Trait.m(recv)`, sealed ones included, as E0522's help does (§3c.4 shows `StrOps.trim(text)`). There the sealed name is the only way to reach the built-in, so it is not noise.
>
> ```blink
> @derive(Clone)
> type P { v: Int }
>
> fn main() ! IO {
>     let a = P { v: 1 }
>     let b = P.clone(a)
>     io.println("{b.v}")
> }
> ```
> ```
> error[UnresolvedMethod]: `clone` is a method of `P`, not a function of the type `P`
>   = help: call it on the value: `a.clone()`
>   = help: or name the trait: `Clone.clone(a)`
> ```
> The first help line is machine-applicable. The fixed program prints `1`.

- **V3 (sys):**
> Name every owner trait, as E0522's help does, and use the same rule for both diagnostics. The spec writes `StrOps.trim(text)` as the fix in its own E0522 example (§3c.4), and `Sized` appears in user bounds (`[T: Sized]`). These names are in the prelude and users can write them. If E0522 names `StrOps` and this diagnostic hides it, the two diagnostics disagree about one fact. When an owner has no trait name a user can write (Int, Float and Ptr methods today), there is no line. I concede to devops that the `recv.m()` line comes first, and that only that line carries the fix.


**V4. A bare `Type.method` with no call.** Plt, aiml, devops, min, web and sys agreed on the same code, a closure in the help and no machine fix. Sys moved to it. Aiml corrected its closure to Blink syntax, and plt added the annotation when `T` is not generic.

- **V4 (plt):**
> Same code as V1. The help writes a closure in Blink syntax, not `|x| x.abs()`, which Blink does not parse. When `T` is not generic, it annotates the parameter with `T`. Without the annotation the closure alone is E0301.
>
> ```blink
> fn main() ! IO {
>     let f = Str.len
>     io.println("{f("ab")}")
> }
> ```
> ```
> error[UnresolvedMethod]: `len` is a method of `Str`, not a function of the type `Str`
>  --> v.bl:2:13
>   |
> 2 |     let f = Str.len
>   |             ^^^^^^^ a method is not a value through its type
>   |
>   = help: write a closure: `fn(s: Str) { s.len() }`
> ```
> It is a suggestion, not a machine fix. The same precedent applies: E0522's closure help for a bare `T.name` is help only. Whatever this panel decides, today's ICE (NodeCarriesNoType) is a bug, as sys said.

- **V4 (sys (moves)):**
> Same code, help with a closure, no machine fix (the closure needs a parameter name and maybe a type).
>
> ```blink
> fn main() ! IO {
>     let f = Str.len                // error[MethodThroughTypeName]
>                                    // help: use a closure: `fn(s: Str) -> Int { s.len() }`
>     let g = fn(s: Str) -> Int { s.len() }
>     io.println("{g("abc")}")       // 3
> }
> ```
>
> This also closes the NodeCarriesNoType ICE from my probe p3. The closure costs nothing at runtime: the C compiler inlines it to the same direct call as `s.len()`.


**V5. Rollout of `Str.len` and `List.len`.** Sys, plt, min, devops, web and aiml all moved to one position: the §8.16.1 test decides, with the same message and fix at each severity.

- **V5 (sys (moves)):**
> I still prefer the error at once. `Str.len` / `List.len` compile through a special case, not a spec form, and the machine fix covers every site whose receiver has type `T`. But b4 runs on the released 0.60.0. Another panel is setting the rule for when such a break may ship at once. This panel should not decide it again with a different answer. Ballot wording: "b4 becomes this error; its rollout (error at once or one release as a warning) follows §8.16.1 as [the §8.16.1 panel] decides it." If that test allows the break at once, I vote for that.

- **V5 (plt (moves)):**
> When a breaking error ships at once and when it ships first as a warning is a general policy, and [the §8.16.1 panel] is deciding it now. This panel should not make a one-off rule for one diagnostic. So: b4 and user `U.shout(u)` get the treatment that rule gives, with the same message and the same machine fix at each level. If [the §8.16.1 panel] lands nothing before this ships, I prefer the error at once: the form was never in the spec, it worked only for some types, and the machine fix migrates every call that is sound to migrate.
>
> STABLE: ready to vote


#### Phase C — Votes

Q1 (adopt the package): 6-0 A. Q3 (the help line for one owner): 6-0 A; sys conceded its Phase B position. Q2 (which code): A 4-2 (web, sys, devops, aiml for a new code; min and plt for E0505), so Phase D ran on Q2 only. The moderator's fact for Phase D: the sibling panel on an unknown member of a type or module path finished 6-0 and kept E0505 and its name `UnresolvedMethod`, with the head "no member `x` on type `K`".

- **Q2 (plt (B)):**
> **Vote:** B
>
> **Reasoning:** A code should name the judgment that failed. Here that judgment is the lookup of the name in the `T.` namespace, and it fails the same way for `Int.abs` as for `K.zed`. Under A, the code depends on what a second lookup in another namespace finds, so one failed judgment gets two codes. The message and the help carry the difference ("is a method of `Int`" and the receiver fix), and that is where the difference belongs.
>
> **Concern:** If the sibling panel's code keeps its generic header text, a user or tool that reads only the code name sees "UnresolvedMethod" for a method that exists. The writer must make the site-specific message mandatory, not optional.

- **Q2 (min (B)):**
> **Vote:** B
>
> **Reasoning:** The site is an unknown member of a type path by the current text, so it belongs to the
> class the sibling panel codes. The repair differs, but E0505 already carries many repairs, each as a
> help line and fix on one code. A second code adds a catalog row, a tool-table entry and a fact users
> must learn, for no change in what they do. The new message, not a new code, removes the false word
> "unresolved".
>
> **Concern:** If A wins, the catalog must state clearly where the new code ends and the sibling's code
> begins. A member that is both an instance method and a near-name of a type-scoped function must get
> one code, not two.

- **Q2 (sys (A)):**
> **Vote:** A
>
> **Reasoning:** The checker knows the method exists, and it knows a repair (move the receiver) that the unknown-member site does not have. A code is the key that `--json` consumers and `blink fix` switch on, so a site with a different repair needs a different key. One catalog row costs very little next to tools that must parse the message text to tell the two cases apart.
>
> **Concern:** If the sibling panel later widens E0505's help to cover this case anyway, two codes could end up with overlapping text. The catalog rows must say which code covers which case.

- **Q2 (web (A)):**
> **Vote:** A
>
> **Reasoning:** "Does not exist" (`Level.zed`) and "exists, wrong call form" (`Int.abs(-3)`) have
> different causes and different repairs. `blink explain`, search, and an LLM that reads only the code
> all need to tell them apart. The `UnresolvedMethod` name in option B contradicts its own message
> ("unresolved" next to "`abs` is a method of `Int`"), and the user reads the code name first.
>
> **Concern:** One more code in the method-resolution family. Users may confuse it with E0505 unless
> the catalog row and `blink explain` text show both forms side by side.

- **Q2 (devops (A)):**
> **Vote:** A
>
> **Reasoning:** A separate code gets its own `blink explain` page ("the name is real; move the receiver"), apart from the typo/nearest-name page. It also gets a clean `--json` filter, so users can run `blink fix` on the b4 migration without touching unrelated E0505 sites. "UnresolvedMethod" in the header contradicts the message under it. That mismatch is the kind of thing users report as a compiler bug.
>
> **Concern:** The catalog gets one more row, and a later panel may find this code and the unknown-member code drifting apart in severity or in how they suggest names. Keep their help formats in step.

- **Q2 (aiml (A)):**
> **Vote:** A
>
> **Reasoning:** An agent dispatches on the code and runs `blink explain <code>`. A new code gives a short explain whose one example is the exact repair (move the receiver). The E0505 entry is a long paragraph about effect handles, module qualifiers and removed names, so the model has to search it for the one case that applies. A model also takes "UnresolvedMethod" to mean "wrong name" and goes looking for another name, which is the wrong fix.
>
> **Concern:** One more code in the catalog, and the writer must keep it apart from the unknown-member code (where the member does not exist) so that the two never overlap at one site.

- **Q3 (sys):**
> **Vote:** A (I concede my Phase B position)
>
> **Reasoning:** In the one-owner case the rewrite `"abc".len()` resolves with no choice to make, so a `Sized.len(...)` line tells the user nothing they need. The facts still agree with E0522: in the two-owner case, A lists every owner, sealed ones too, so the two diagnostics never contradict each other where it matters. It makes no codegen difference, so I defer to the seats that care about the text.
>
> **Concern:** A user may meet `Sized.len` for the first time in an E0522 help with no prior hint that the sealed traits exist. The spec's §3c.4 example has to carry that teaching.

- **Q3 (plt):**
> **Vote:** A
>
> **Reasoning:** With one owner, `recv.m()` and `Trait.m(recv)` elaborate to the same node, so a second line adds no information. A sealed trait name is an implementation surface that the user never needs in that case. With two or more owners, the sealed name is the only term that reaches the built-in, so listing it there, as E0522 does, carries information.
>
> **Concern:** If one release adds a user-writable non-sealed trait that owns a built-in method, the one-owner help changes shape from one line to two. That is harmless, but tests that pin the exact help text will churn.


#### Phase D — Q2 only

Min and plt moved from B to A. The six seats then revoted 6-0 A. All six concerns named one condition: the two codes must split every failed `T.name` site with no gap and no overlap.

- **D1 (min (moves to A)):**
> **Response**
>
> The strongest A argument is devops's tool point, and the sibling result makes it stronger. The
> sibling kept the name `UnresolvedMethod` and gave its site the head "no member `x` on type `K`". Under
> B, `Int.abs(-3)` would print `error[UnresolvedMethod]` over a message that says the method exists.
> That header is false. The only ways to remove it are to rename E0505, which the sibling declined, or
> to give this site its own code. Devops's filter point also holds: `blink check --json` then
> `blink fix` on the b4 migration (`Str.len(s)` to `s.len()`) can select one code. Under B, the same
> run would also take any machine-applicable nearest-name fix on unrelated E0505 sites, such as
> `K.zed` to `K.Zed`. My test for an addition is whether it carries a distinct action. Here it does:
> the cause, the repair and the fix filter all differ. plt's point that the failed lookup is the same
> is true, but users and tools act on the repair, not on the judgment that failed.
>
> My Phase C concern stays as a condition. The two codes must never both fire at one site. If `x` is
> an instance method of `K`, the site gets the new code only, even when `x` is also a near-name of
> something in the `T.` namespace.
>
> **Position**
>
> A. Changed from B.

- **D1 (plt (moves to A)):**
> **Response**
>
> The strongest case for A is the one sys and aiml make. A code is the key that tools switch on, and this site has a repair that the unknown-member site does not have. My Phase C argument, "one failed judgment, one code", does not hold up against the catalog. E0505 already spans several judgments: receiver lookup, effect-handle ops, module qualifiers, and removed names. The catalog also already splits "the thing exists but is written in the wrong form" from "the thing does not exist". `UnqualifiedVariant` (E0554, a real variant with no enum prefix) is a separate code from `NoSuchVariant` (E0547, no such variant). `TypeArgsWithoutCall` (E0314) is another form error with its own code. `Int.abs(-3)` is exactly that kind of error: the name resolves to a real method and the call form is wrong. So A follows the catalog's own precedent, and B does not.
>
> The sibling panel's fact settles my own Phase C concern. The code name stays `UnresolvedMethod`, so under B the header would say "unresolved" next to a message saying the method exists. Min's overlap worry is answered by a strict split, so no site gets both codes:
> - E0505: the name is not in the `T.` namespace, and no owner gives `T` a receiver method of that name.
> - The new code: the name is not in the `T.` namespace, and at least one owner does give `T` that receiver method. This includes the E0522 case of two or more owners.
>
> ```blink
> type Level { lo: Int }
>
> fn main() {
>     let n = Int.abs(-3)   // new code: `abs` is a receiver method of Int
>     let k = Level.zed()   // E0505: no member `zed` on type `Level`
> }
> ```
>
> **Position**
>
> A. Changed from B.

- **D2 (sys):**
> **Vote:** A
>
> **Reasoning:** This site has a different repair from an unknown member (move the receiver, not fix the name), so it gets its own code. That follows the catalog's existing splits: E0554 against E0547, and E0522 against E0505. The sibling panel kept E0505's head "no member `x` on type `K`", so under B the header would be false at this site. A separate code also lets `blink fix` apply the b4 migration without touching E0505 typo sites. Plt's strict split decides every site: the new code fires when at least one owner gives `T` a receiver method of that name (this includes the E0522 case), and E0505 fires otherwise. So no site gets both codes.
>
> **Concern:** If the writer leaves out the precedence rule (an exact instance method beats a nearest-name suggestion), an implementation could emit both codes at one site, or E0505 with a wrong-name fix.

- **D2 (web):**
> **Vote:** A
>
> **Reasoning:** The user reads the code name first and searches on it. `UnresolvedMethod` over a
> method that exists sends them to the wrong repair ("check the spelling"). The catalog already
> splits "exists, wrong form" from "does not exist" (E0554 against E0547), so A follows its own
> precedent. A single code also lets `blink fix` run the b4 migration without touching typo sites.
>
> **Concern:** The split must be strict: an exact instance-method match always gets the new code and
> never also E0505, or users see two codes for one mistake.

- **D2 (plt):**
> **Vote:** A
>
> **Reasoning:** At this site the name resolves to a real receiver method, and the call form is wrong. The catalog already gives that class its own code, apart from "does not exist": E0554 against E0547 for variants, and E0314 for type arguments with no call. Under B, E0505's fixed head "no member `x` on type `K`" would be false here, because `Int` has a member `abs`. A code must never contradict the fact the checker has proved.
>
> **Concern:** The two codes must partition every failed `T.name` site, with no gap and no overlap. If the new code fires only when the exact name is a receiver method that some owner gives `T`, including the E0522 case of two or more owners, then E0505 covers every other site. If the catalog rows state this rule loosely, one site could get both codes, or a near-name case could fall between them.

- **D2 (devops):**
> **Vote:** A
>
> **Reasoning:** This site has a different cause, a different repair and a different machine-fix filter from the unknown-member site. A code is the key that `blink explain`, `--json` consumers and `blink fix --code` switch on. The catalog already splits "exists but in the wrong form" from "does not exist" (E0554 against E0547, E0314). The sibling panel kept the name `UnresolvedMethod` with the head "no member `x` on type `K`". So under B the header and the head would both be false at `Int.abs(-3)`.
>
> **Concern:** If the writer leaves out the strict split (an exact instance-method match on `T` wins, and E0505 with its nearest-name search runs only when no owner gives `T` that receiver method), one site could fire both codes, or `blink fix` could apply a nearest-name guess where the receiver should move.

- **D2 (aiml):**
> **Vote:** A
>
> **Reasoning:** A model or tool that reads only the code must get the right repair from it. Under B, the head `UnresolvedMethod` / "no member" says "fix the name", which is wrong when the name is right and only the call form is wrong. The catalog already gives "exists but written in the wrong form" its own code (E0554 against E0547). With a separate code, `blink check --json` can select the `Str.len(s)` → `s.len()` migration without also taking the nearest-name guesses that E0505 makes.
>
> **Concern:** If the precedence rule is not written down (an exact instance-method match fires the new code, and only when there is none does E0505 run its nearest-name search), one site could get both codes, or an implementation could pick by the order it searches.

- **D2 (min):**
> **Vote:** A
>
> **Reasoning:** The sibling panel kept the code name `UnresolvedMethod` with the head "no member `x` on
> type `K`". Under B that header would be false at `Int.abs(-3)`, where the member exists. The
> catalog already gives "real name, wrong form" its own code (E0554 against E0547), and this site has its
> own repair and its own safe fix filter for the b4 migration. An addition that carries a distinct
> action clears my bar.
>
> **Concern:** The split must stay strict. An exact instance-method match of `T` gets the new code, and
> the nearest-name search runs only when no such method exists. Without that rule, a site could get
> both codes, or the two codes' help formats could drift apart.


### Out of Scope

- The rollout test of §8.16.1 itself, which a separate decision sets. This decision cites it and does not restate it.
- The wording of `blink explain` pages and of the help lines beyond the rules above.
