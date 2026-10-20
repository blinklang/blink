[< All Decisions](../DECISIONS.md)

# Map Index Assignment Re-audit — Design Rationale

A batch of re-audits reopened earlier votes under one principle: "match LLM priors unless the deviation prevents a bug class." This one asked about `m[k] = v`, which is `NoIndexOperator` (E0313). The ticket said: "LLMs write m[k] = v by default. [...] keep only if it prevents a bug class; else allow it as sugar for insert."

Facts before the vote:

- §2.6 (5-0) makes `[T]` generics. §3.4 (6-0) makes a postfix `[...]` that holds a value E0313, decided by name resolution from the bracket contents, never from the receiver's type.
- [Index Assignment Places](index-assignment-place.md) (6-0) made an index not a place. Element writes are `List.set`, `Bytes.set` and `Map.insert`. The store help names one verb from the receiver's type and is machine-applicable when the type is known.
- §2.22: `place = rhs` evaluates `rhs`, then reads the root, then stores. "A feature that adds places must keep that rule."
- gen1 rejects `m["a"] = 1` with `error[NoIndexOperator]` and `help: m.insert("a", 1)`, with a machine-applicable fix.
- `Map.get_or_default` is in the §3 Map table, but gen1 does not resolve it yet. Help texts use `?? 0`.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Quoted text is each panelist's own, verbatim. `[...]` marks a cut, and local ticket IDs are replaced with a short name in square brackets.

In the dedupe, the options were KEEP (E0313 for every index form), STMT (a statement-only bracket write on List, Bytes and Map, as an exact rewrite to `.set` / `.insert`) and MAPONLY (the same, on Map only). The variations under KEEP were K1 (the Map compound note shows the counter idiom), K2 (that note names the default form and the panic form), K3 (the plain-store fix is machine-applicable), K4 (an LSP quick-fix), K5 (E0313 docs lead with the Map store) and K6 (a one-line reason in the E0313 text).

#### Phase A — Independent proposals

Five seats proposed keeping E0313 for every index form as their first choice. Systems proposed a statement-only bracket write on List, Bytes and Map as its first choice, with keep as its fallback. Excerpts:

- **Systems:**

> Under the new principle, the question is narrow: what bug class does a *write* `m[k] = v` cause that `m.insert(k, v)` does not? I looked at what each form compiles to, and I find none for a plain write. The real bug classes in index syntax are all on other paths:
>
> 1. **Read inserts** (C++ `std::map::operator[]` makes a default entry on a read). Blink avoids this only while index *reads* stay E0313.
> 2. **Missing-key compound** (`m[k] += 1` needs a hidden read. It must either panic on a missing key or make up a default value). This is a real bug class.
> 3. **Hidden panic sites in nested places** (`a[i].f[j] = v` holds two bounds checks and two panic sites, and the source shows neither).
>
> A plain statement `m[k] = v` that lowers to exactly `m.insert(k, v)` has none of these. It gives the same C call, the same mono instance and the same allocate/rehash path. A Map insert cannot fail (OOM aside), so it is the *safest* bracket write there is.
>
> [...]
>
> 4. **Evaluation order is the call's order:** receiver, then key, then value, then the call. That differs from §2.22's field rule (rhs first, then the root). I accept the difference because it makes the sugar a pure syntax rewrite. The parser or name resolution rewrites it to a method call, so lowering, IR, E0601 and the C printer see nothing new. The spec states the order in §2.22 next to the field rule.
>
> [...]
>
> From the systems seat, A and B produce the same machine code. A has one surface form. B has fewer round-trips for model-written code. I cannot name a bug class that A prevents and B lets in, so by the ticket's principle I vote B.

- **Web/Scripting:**

> A Python, JS or Kotlin developer writes these four lines first, in this order of frequency:
>
> ```python
> counts[w] += 1          # most common dict write in Python code
> m[k] = v                # plain store
> x = m[k]                # read
> xs[i] = v               # list store
> ```
>
> The ticket asks only about line 2, but the developer does not think in lines. A developer who can write `m[k] = v` tries `m[k]` as a read in the next statement and `m[k] += 1` in the statement after that. Any proposal must say what happens to all four.
>
> [...]
>
> 2. **Write-only sugar does not fix the main prior.** In Python code the most common dict write is `counts[w] += 1`. Compound index assignment stays E0313 under every proposal on the table, so the model still gets the error on the idiom it writes most. Sugar for `=` alone fixes part of the prior and adds a second form next to `.insert`.
>
> [...]
>
> ## Vote intent
>
> **A.** It keeps one rule, it rejects a partial fix that misses `+=`, and it puts the teaching in the diagnostic. I will move to B only if another seat shows that the `=` form alone is a large share of the error rate and that the asymmetry costs less than the extra round.

- **PLT:**

> **1. Two evaluation orders for `=`.** §2.22 says `place = rhs` runs `rhs`, then reads the root, then stores. A method call reads the receiver first, then the arguments in written order. Sugar for `insert` must pick one of these:
>
> - **Insert order (m, k, v).** `=` then has two orders, chosen by the shape of the left side. In `m[key()] = val()`, `key()` runs first. In `s.f = val()`, `val()` runs first.
> - **Assignment order (v, then m, k).** `m[k] = v` is then not the same as `m.insert(k, v)` whenever `k` or `v` has effects. "Sugar for insert" is then false, and the spec must state a third rule.
>
> The LLM prior does not settle this, because it is split. Python runs `v`, then `m`, then `k`. JS runs `m`, then `k`, then `v`. Whatever order we pick, the code is wrong for one prior, and nothing at the call site tells you which order applies. Hidden, order-dependent effects are a real bug class. Today the method-call form makes the order visible.
>
> [...]
>
> **My vote: P1.** P2 can be made sound, but only by giving up the §3.4 rule that name resolution decides what a bracket means, and by giving `=` two evaluation orders. Both costs are larger than the few tokens it saves.

- **DevOps:**

> **Test from the ticket: does the error prevent a bug class?** For a plain `m[k] = v`, no. Its meaning is "insert or update", the same in Python, JS, Go and C++, and the same as `Map.insert`. No program goes wrong at runtime because of that spelling. So the case for keeping E0313 cannot be "it stops a bug". It has to be about the diagnostic surface and how much of the model's prior a change would really meet. Those are my two arguments.
>
> 1. **The prior is a bundle, not one shape.** A model that writes `m[k] = v` also writes `m[k]` reads, `m[k] += 1` and `xs[i] = v`. Reads are far more common than writes. Making one of these shapes legal does not match the prior. It makes the prior look right, so the other shapes then fail more often. I cannot prove this, but we can test it: compare E0313 hit rates in model output with and without the sugar.
> 2. **The error already costs very little.** For a plain store, E0313 has one help that `blink fix` can apply (§3.4 *A store through brackets*). A model fixes it in one round. For a model, the deviation costs one diagnostic, not a bug hunt.
>
> [...]
>
> **Vote intent: Proposal 1.** Fallback is Proposal 2, never Map-only.

- **AI/ML:**

> So the plain write `m[k] = v` by itself prevents no runtime bug. The compound form does, and the compound form comes with the place unless the panel adds a second rule to forbid it.
>
> ## The premise "LLMs write `m[k] = v` by default"
>
> This is true for Python, Go, Kotlin, C# and Swift. It is not true everywhere. JS `Map` uses `.set(k, v)`, Rust `HashMap` uses `.insert(k, v)` (no `IndexMut`), and Java uses `.put(k, v)`. The prior depends on the code around it. Blink code has `[T]` generics, `.get()` reads that return `Option`, and `let mut`. That puts a model nearer to Rust than to Python, and in Rust `.insert` is the prior. The prior for `m[k] = v` in Blink context is weaker than the ticket assumes. I have no Blink-specific benchmark data. The panel should not treat the premise as measured.
>
> [...]
>
> For `m[k] op= v` on a Map, today's help gives only the `.unwrap()` form ("panics when `k` is absent"). That is the right default for a List, where an out-of-bounds index is a bug. For a Map, an absent key is the normal case in a counter loop, and the spec's own idiom uses a default. A model copies the help as written. The note must name both forms, so the author picks the missing-key behavior:
>
> [...]
>
> ## Vote intent
>
> - **A: yes.** Keep E0313. Change the Map compound note to name both the default form and the panic form.
> - **B:** only as a package, never in part.
> - **C: no.**

- **Minimalism:**

> I keep the error. Honest answer to the ticket's test: plain `m[k] = v` prevents no bug class on its own, but the forms that come with it do. A machine fix covers the LLM-prior cost more cheaply than new syntax.
>
> [...]
>
> So the narrow sugar is harmless in itself. But "sugar for insert" never stays narrow. Once `m[k] = v` compiles, the next line an LLM writes is `m[k] += 1` or `io.println("{m[k]}")`, and those forms do carry bug classes. The sugar does not remove the prior. It moves the error one line down, to a form where the priors disagree.
>
> [...]
>
> **Preferred: M1.** Keep the error and make the plain-write fix machine-applicable. Of the forms in the table, only plain `=` has priors that agree, and only that one gets an automatic fix. Every other form stays an error, because there the priors disagree and the error prevents real bugs.


#### Phase B — Debate highlights

One round. Systems moved from STMT to KEEP. PLT corrected its own fallback order and dropped Map-only sugar. Minimalism withdrew its machine-fix variation, because §3.4 already specifies it. All six seats then signalled ready to vote.

- **Systems:**

> **I move from STMT to KEEP.** Three arguments changed my view.
>
> - **PLT, point 1 (two evaluation orders for `=`).** In Phase A I listed this as a cost. PLT is right that it is a bug class, even if a small one. With STMT, `m[key()] = val()` runs `key()` first and `s.f = val()` runs `val()` first. Nothing at the site shows which order applies. Python priors expect `val()` first. The other choice (assignment order) makes "sugar for insert" false. Each choice leaves effects in an order that you cannot see at the site. The method call shows the order in the text. Under the ticket's own test, that counts as a bug class that the error prevents.
>
> [...]
>
> - **Web, DevOps, Min (the prior is a bundle).** I argued that a plain write is safe on its own, and it is. But in Python the most common dict write is `counts[w] += 1`, and STMT keeps that an error. So STMT matches only part of the prior and moves the error down one line. A rule that is mostly true ("brackets write on containers") is harder to learn than "brackets hold types".
>
> [...]
>
> - **K6: yes, but the reason must be true for every receiver.** I propose: "brackets hold type arguments; a write to an element is a method call." Do not use "it allocates", because that is false for `List.set` and `Bytes.set`.

- **PLT:**

> So the spec, voted 6-0, already treats "an `=` that reads its target before `rhs`" as a hazard that it designs fixes around. sys says the sugar is "not a place, only a rewrite". That does not help: the user sees `=`, and the reason for the rule is what `=` means to the reader, not what the IR holds. A STMT with call order gives exactly the split that the `Ptr` section exists to stop:
>
> ```blink
> fn main() {
>     let mut m = Map[Str, Int]()
>     let reset = fn() -> Int {
>         m = Map[Str, Int]()        // rhs changes the root through a closure
>         1
>     }
>     m["a"] = reset()               // call order: m is read first, so the store goes into the old map
>     s.total = reset()              // (field form, §2.22) the root is read after rhs: store kept
> }
> ```
>
> (The second line is a sketch of the contrast with the §2.22 `Stats` example. It is not a complete program.)
>
> [...]
>
> **I correct my own Phase A P2.** There I wrote that the sugar would keep insert's order (m, k, v). That was wrong by the spec's own rule. The only sound STMT runs `rhs` first and then the receiver and key:
>
> `recv[k] = rhs` ≡ `{ let t = rhs; recv.insert(k, t) }` (or `.set` for List/Bytes), with `t` a fresh name.
>
> That is Python's order (v, m, k), not JS's. It keeps one evaluation order for `=`. It is still a pure rewrite before typecheck, so sys's "byte-identical C" point stands. With this order, STMT is sound. My remaining objections to it are about surface and learning, not soundness.
>
> [...]
>
> **To devops and aiml on MAPONLY.** You are right, and I drop MAPONLY as my fallback. MAPONLY decides legality from the receiver's type, and that breaks the 6-0 §3.4 rule ("name resolution decides, never the receiver's type"). devops adds the case I missed: when the receiver has an error type, the compiler cannot pick a code at all.

- **Web/Scripting:**

> **To plt.** Your evaluation-order point is the strongest bug-class argument on the table, and I adopt it. Python runs `v` first, JS runs `k` first, and nothing at the call site tells you which order Blink picked. I also agree with your point 3: allowing part of a prior teaches a rule that is only partly true. That is my Stack Overflow argument in formal terms.
>
> [...]
>
> - **K6: yes, with different words.** Give one line of reason in terms a JS dev already knows, not internals. Proposed text: "Brackets in Blink hold types (`List[Int]`). Read and write elements with methods." I prefer this to "it allocates and has no matching read". The allocation reason is true, but it invites "Python allocates too" and does not help with `xs[i] = v`.

- **DevOps:**

> **sys (B): "a pure syntax rewrite before typecheck".** This is not correct, and it changes the tooling cost. Name resolution cannot choose between `.set` and `.insert`, because the choice needs the receiver's type. So the rewrite must happen in typecheck, after inference. That means:
> - The error code for `t[k] = v` with `t` of type `Foo` (no write method) is chosen at typecheck, not at name resolution. §3.4 now chooses every bracket code at name resolution. STMT makes stores the one exception.
> - When the receiver is an error type, the compiler cannot say whether the statement is legal. §3.1 rule 3 then has to drop the diagnostic. A model gets no signal on exactly the line it got wrong.
> - The LSP must keep a desugar map so that hover, go-to-definition and find-references on `[...] =` reach `insert` or `set`. rust-analyzer carries this for `IndexMut`, and it has bugs there.
>
> The C output can be byte-identical, as sys says. The front-end and tooling cost is not zero.
>
> [...]
>
> **web (most common Python write is `counts[w] += 1`).** This is the key fact. STMT leaves the most common idiom as an error. So STMT gives a second spelling and still leaves most of the prior unmatched.

- **AI/ML:**

> - **The sugar captures the smaller part of the prior.** web's point 2 is the strongest LLM argument on the table. In Python training data the most common dict write is `counts[w] += 1`. Every option on the table keeps compound E0313. So under STMT the model still fails on the idiom it writes most, and it now also has to learn "plain `=` works, `+=` does not". STMT does not remove the round trip for the common case; it moves it.
>
> [...]
>
> - devops's claim "legal writes raise the read-error rate" is testable. I support that test as a follow-up, not as a blocker. If a measured eval (model given `blink llms --full`, Blink tasks, count first-compile errors by form) shows plain `=` writes are a large share of errors and the read rate does not rise under sugar, the panel can reopen this. Without data, the default is the one-rule surface.

- **Minimalism:**

> **I withdraw K3.** The moderator's fact shows that §3.4 *A store through brackets* already gives a one-verb, machine-applicable fix when the compiler knows the receiver type, and gen1 already prints it. When the type is not known, the help names both methods and gives no fix. That is correct: a fix that guesses `.insert` on a List would shift elements. So K3 asks for something we already have. I proposed it without checking the spec text first, so I remove it. Under KEEP, the plain write needs no change.
>
> [...]
>
> **Web's strongest point decides it for me.** The most common Python dict write is `counts[w] += 1`, and every proposal keeps that form E0313. So STMT does not meet the main prior. It meets a smaller one, and it adds a second spelling to do so. Partial sugar moves the error one line down, and the model learns a rule ("brackets work on the left of `=`") that is only partly true. PLT (point 3), devops (point 1) and aiml all make the same point.


#### Phase C — Final vote

- **Q1: The rule for `m[k] = v` and `xs[i] = v`** (6-0 KEEP)

  - **Systems:**

    > **Q1. Vote: KEEP.**
    >
    > Reasoning: KEEP and STMT compile to the same C call, so the choice does not change runtime cost. STMT does give `=` a second evaluation order that the code does not show, which is a small bug class that the error prevents. It also leaves `m[k] += 1`, the most common write, as an error, so the sugar buys too little. The help on a plain store already gives one exact verb from the receiver type, so the cost of the error is about one round trip.
    >
    > Concern: if the plain-store help ever falls back to a guess (for example, `.insert` on a List, which shifts elements), the low-cost repair argument for KEEP fails, so the regression suite must lock in the one-verb rule.

  - **Web/Scripting:**

    > **Q1. Vote: KEEP.**
    >
    > Reasoning: "Brackets hold types; elements use methods" is one rule with no exceptions, and a JS or Python dev learns it in one minute. With STMT, the rule becomes "writes work, but not reads, not `+=`, not nested writes", and the developer hits those exceptions on the next line. The machine fix already in §3.4 makes the plain store cost one automatic edit, so STMT saves almost nothing and adds the asymmetry.
    >
    > Concern: models trained on Python and Go keep writing `m[k] = v` at first contact, so the help and the machine fix must stay exact and fast, or the friction looks like a language defect.

  - **PLT:**

    > **Q1. Vote: KEEP.**
    >
    > Reasoning: A place is a get/put pair. Blink has no total index get, so a bracket write is a put with no matching read. The bracket write also adds a second spelling of `insert`/`set`, and it still fails on `+=`, the most common prior. A STMT with rhs first is sound, but it buys one round trip at the cost of a position-dependent namespace rule (S4) and a bracket that writes but cannot read. KEEP keeps one rule: brackets hold types, methods touch elements.
    >
    > Concern: if a later audit allows List writes or Map reads, the case for KEEP must be argued again for all forms together, not one form at a time. Piecemeal sugar is how C++ got `operator[]` that inserts on a read.

  - **DevOps:**

    > **Q1. Vote: KEEP.**
    >
    > Reasoning: The plain-store error already has a one-verb fix that `blink fix` can apply, so the prior costs one round trip. STMT needs the receiver type to choose `.set` or `.insert`. That moves a bracket code out of name resolution, makes the result uncertain on an error-typed receiver, and makes the LSP map `[...] =` back to a method. STMT also leaves `counts[w] += 1`, the most common prior, as an error, so it adds a second spelling and most of the prior still fails.
    >
    > Concern: If models hit E0313 on plain stores much more often than we expect, KEEP costs real tokens, so we must measure that rate and not assume it.

  - **AI/ML:**

    > **Q1. Vote: KEEP**
    >
    > Reasoning: "Brackets hold types; methods touch elements" is one rule with no exceptions, so a model can learn it from the spec alone. STMT matches only the plain `=` prior, and compound `counts[w] += 1`, the most common Python dict write, stays E0313 under every option. So the sugar adds an exception and a second spelling of `insert` but does not remove the round trip for the common case. The plain-store fix is already machine-applicable, so the cost of KEEP is one cheap round trip.
    >
    > Concern: a model that does not read the spec keeps writing `m[k] = v` and burns one compile per session, and we have no measured data on how often that happens.

  - **Minimalism:**

    > **Q1. Vote: KEEP.**
    >
    > Reasoning: plain `m[k] = v` adds no runtime bug, but it adds a second spelling of `insert` and two exceptions to §3.4 (a value on the left of `=`, and value-namespace resolution there). It also gives `=` a second evaluation order. It does not meet the main prior, because `counts[w] += 1` stays E0313 under every option. The current error already gives a one-verb machine fix, so the deviation costs one round trip, while the sugar costs surface forever.
    >
    > Concern: if the premise "LLMs write `m[k] = v`" turns out to be strong in Blink context, the round trips add up. Someone should measure E0313 hit rates in model output rather than assume them.

- **Q1b: Evaluation order of `r[k()] = v()`, counted only if STMT won** (moot; 5-1 CALL, PLT dissent for RHS)

  - **Systems:**

    > **Q1b. Vote: CALL** (counts only if STMT wins).
    >
    > Reasoning: an exact rewrite to `.insert`/`.set` keeps lowering, IR and the C printer unchanged and makes "sugar for insert" literally true. RHS order would need a special lowering that evaluates the arguments out of written order.
    >
    > Concern: §2.22 then has an exception to "rhs first", and the spec must state it in the same paragraph as the field rule, or someone will miss it.

  - **Web/Scripting:**

    > **Q1b. Vote: CALL** (counts only if STMT wins).
    >
    > Reasoning: only call order makes "exact sugar for `.insert` / `.set`" true, and that is the one sentence a developer can keep in mind. RHS order makes `m[k] = v` differ from the method it claims to be whenever `k` or `v` has effects. JS also uses this order, so one large prior agrees with it.
    >
    > Concern: `=` then has two evaluation orders chosen by the shape of the left side, and the §2.22 text must state the exception plainly or it becomes a hidden-order bug.

  - **PLT:** *(dissent)*

    > **Q1b (only if STMT wins). Vote: RHS.**
    >
    > Reasoning: §2.22 says "A feature that adds places must keep that rule". Its `Ptr` section shows that an `=` that reads its target before `rhs` "stores to different memory" when `rhs` changes the root through a closure. The reader sees `=`, so `=` must have one evaluation order whether the IR holds a place or a call. The rewrite stays pure: `{ let t = rhs; recv.insert(k, t) }`.
    >
    > Concern: with CALL, `m[k] = f()` and `s.f = f()` order effects differently with no visible sign. That is the lost-write case the 6-0 vote closed.

  - **DevOps:**

    > **Q1b. Vote: CALL** (counts only if STMT wins).
    >
    > Reasoning: Only call order makes "exact rewrite of `.insert`/`.set`" true, so hover and the docs can say "same as `m.insert(k, v)`" and be correct. RHS order gives a sugar that differs from its own expansion when `k` or `v` has effects, and no tool can show that difference.
    >
    > Concern: `=` then has two orders, chosen by the shape of the left side, and the spec must state this next to the §2.22 field rule.

  - **AI/ML:**

    > **Q1b. Vote: CALL** (counts only if STMT wins)
    >
    > Reasoning: the spec's sentence would say `r[k] = v` "means exactly" `r.insert(k, v)`, and a model predicts call order from that sentence. RHS makes the sentence false whenever `k` or `v` has effects, and the model cannot see that from the text.
    >
    > Concern: `=` then has two evaluation orders chosen by the shape of the left side, and a Python-primed model gets `m[k()] = v()` silently wrong.

  - **Minimalism:**

    > **Q1b. Vote: CALL** (counts only if STMT wins).
    >
    > Reasoning: call order is the only order where "an exact rewrite to `.insert`/`.set`" is literally true. With RHS order the sugar is no longer a rewrite: it needs its own lowering and a third rule. One rewrite rule is smaller than a new place kind.
    >
    > Concern: `=` then has two evaluation orders, chosen by the shape of the left side, and the spec must say so next to the §2.22 field rule.

- **Q2: E0313 note for a Map compound write `m[k] op= v`** (6-0 BOTH-LIT; Web moved from BOTH)

  - **Systems:**

    > **Q2. Vote: BOTH-LIT.**
    >
    > Reasoning: a literal `0` is the right default only for additive operators on numbers. For `*=`, `?? 0` silently gives a product of 0, and for `Str` it does not type-check. A model copies help text exactly, so a wrong default in the note becomes a silent wrong value at runtime. A placeholder for the other cases makes the author pick the identity value.
    >
    > Concern: the placeholder must not compile (or must clearly read as a hole), or someone will paste it as-is.

  - **Web/Scripting:**

    > **Q2. Vote: BOTH-LIT.**
    >
    > Reasoning: a model copies help text as written. `?? 0` is correct for a `+=` counter on `Int`, but for `*=`, for a `Float`, or for a non-numeric value it is wrong or does not compile, so the help would teach a bad fix. BOTH-LIT keeps the 90% counter case concrete and does not guess elsewhere. I move from BOTH to BOTH-LIT for this reason.
    >
    > Concern: the placeholder for other cases must read as an obvious slot (for example `<default>`) so that a model does not paste it in as code.

  - **PLT:**

    > **Q2. Vote: BOTH-LIT.**
    >
    > Reasoning: The default for a missing key is a semantic choice, so the note must show it as one. A literal `0` is the identity only for `+` and `-` on numbers. For `*=` it gives a silent wrong result, and for other types it may not typecheck. A model copies help text as written, so a placeholder outside the `+=`/`-=` Int/Float case keeps the help correct for every operator.
    >
    > Concern: the placeholder text must be clearly not code, or a model pastes it as-is and gets a confusing parse error.

  - **DevOps:**

    > **Q2. Vote: BOTH-LIT.**
    >
    > Reasoning: A help text that a model copies must be correct for the operator it gets. `?? 0` is the right default for `+=`/`-=` on a number, but it is wrong for `*=` (the result is always 0) and has no meaning for a `Str` or a struct `V`. A placeholder in those cases forces the author to choose, and this matches the decided "no machine fix" rule. The panic form comes second in every case.
    >
    > Concern: A placeholder such as `<default>` in help text can be copied as-is, so the text must be clearly not valid Blink, so that it fails to compile and does not run with a wrong value.

  - **AI/ML:**

    > **Q2. Vote: BOTH-LIT**
    >
    > Reasoning: models copy help text verbatim. The literal `?? 0` is correct only for `+=`/`-=` on a numeric value; for `m[k] *= 2` the copied help gives 0 every time, a silent wrong program that the help itself made. A placeholder for other operators or value types makes the model or author choose the default, which is the whole point of naming both forms. If BOTH wins, I accept it, but the risk above remains for `*=` and similar.
    >
    > Concern: a placeholder such as `<default>` that a model copies verbatim gives a compile error, which costs one more round trip (but fails loudly, not silently).

  - **Minimalism:**

    > **Q2. Vote: BOTH-LIT.**
    >
    > Reasoning: BOTH is correct for `+=`, but a literal `?? 0` for `m[k] *= 2`, or for a `Str` value, is a wrong default that a model copies as written. `0 * 2` stays `0` and nothing signals it. A placeholder for the other operators and types costs one rule in the diagnostic and adds nothing to the language. Correctness wins over a one-line-simpler help.
    >
    > Concern: a placeholder the model does not fill in must not compile into something that runs. It must stay an obvious hole (for example, a name that fails to resolve), not a value.

- **Q3: A one-line reason note on E0313** (5-1 YES-FREE, AI/ML dissent for YES-TEXT with web's text)

  - **Systems:**

    > **Q3. Vote: YES-FREE.**
    >
    > Reasoning: the spec should require that a reason is given. Exact diagnostic text is a tooling detail that changes with style passes. Tests should pin the code and the help verb, not prose. Any of the three texts meets the need. I prefer the ones that do not claim "it allocates".
    >
    > Concern: free wording can drift into a false reason (such as "it allocates", which is false for `List.set`), so review should check that the reason holds for every receiver type.

  - **Web/Scripting:**

    > **Q3. Vote: YES-FREE.**
    >
    > Reasoning: the reason note helps a developer generalize from one fix to `+=` and to reads, so the spec should require it. Diagnostic wording is a tooling detail that we will change after we see what models do with it, so the spec should not lock it in. My preferred text is still "Brackets in Blink hold types (`List[Int]`). Read and write elements with methods."
    >
    > Concern: free wording can drift into internals ("allocates", "no matching read") that a JS dev does not need, so review should keep it in user terms.

  - **PLT:**

    > **Q3. Vote: YES-FREE.**
    >
    > Reasoning: The normative content is the reason ("brackets hold types; elements use methods"), not the exact words. If the spec fixes the wording, a later tweak to the text becomes a spec change. Any of the three texts meets the rule. I lean to aiml's, because it is the shortest.
    >
    > Concern: free wording can drift until the reason is gone. The spec sentence must name both halves: brackets hold types, and elements use methods.

  - **DevOps:**

    > **Q3. Vote: YES-FREE.**
    >
    > Reasoning: The reason note helps a model generalize from one error to reads, `op=` and nesting. The wording should not be normative: tools and tests key on the code and the headline, not on note text, and we need to be free to improve the wording without a panel vote. Of the three texts, I lean to aiml's because it is the shortest.
    >
    > Concern: Without fixed text, the implementation can drift into wording that names only one container, so the spec must require that the reason holds for every container and every position.

  - **AI/ML:** *(dissent)*

    > **Q3. Vote: YES-TEXT, web's text**: "Brackets in Blink hold types (`List[Int]`). Read and write elements with methods."
    >
    > Reasoning: a stable diagnostic text gives one consistent signal in every log, every transcript and future training data, so models learn it as a fixed phrase. web's text names both reads and writes, so it covers the generalization from `=` to `+=` and to reads in one line. It is nearly the same as mine, and the "read and write" words make it slightly better.
    >
    > Concern: fixed wording in the spec makes a later wording fix a spec change, not a tooling change.

  - **Minimalism:**

    > **Q3. Vote: YES-FREE.**
    >
    > Reasoning: the spec should require that the note exists and gives the reason, but it should not freeze diagnostic prose. Fixed wording is surface that every later diagnostic change must respect. If someone needs a reference wording, aiml's text is the shortest.
    >
    > Concern: without fixed text, the note can grow over time. Keep it to one line.

- **Q4: LSP quick-fix action and docs that lead with the Map store** (6-0 CHORE)

  - **Systems:**

    > **Q4. Vote: CHORE.**
    >
    > Reasoning: an LSP code action and the order of examples in the docs do not change what the language accepts or how it behaves. They belong in tooling and docs tickets, not in sections/.
    >
    > Concern: chores without an owner get stale, so the K4 chore should depend on the `blink fix` edit source, which already exists.

  - **Web/Scripting:**

    > **Q4. Vote: CHORE.**
    >
    > Reasoning: an LSP code action and the order of examples in the docs are tooling and docs work, not language semantics. They belong in br chores, not in sections/ text. Both are worth doing, because K4 is what makes KEEP cost zero in an editor.
    >
    > Concern: chores with no owner stay unwired, so file them with a dependency on this decision so that they reach the ready queue.

  - **PLT:**

    > **Q4. Vote: CHORE.**
    >
    > Reasoning: An LSP code action and the order of examples in docs are tooling and docs behaviour, not language semantics. Spec text should define what a program means, not how an editor shows a fix. The spec already says the fix is machine-applicable, so tools can act on it with no new text.
    >
    > Concern: chores without an owner get lost. Link both chores to this decision so they stay visible.

  - **DevOps:**

    > **Q4. Vote: CHORE.**
    >
    > Reasoning: An LSP code action and the order of examples in the docs are tooling behavior, not language. The spec describes Blink, not its editor integration. Two chores (LSP quick-fix uses the same fix record as `blink fix`; E0313 `diag_explain` and `blink llms` lead with the Map store) give the result with no spec text to maintain.
    >
    > Concern: Chores can sit unworked, so they should be filed with this decision and linked to it.

  - **AI/ML:**

    > **Q4. Vote: CHORE**
    >
    > Reasoning: an LSP code action and the order of examples in `blink llms` are tooling and docs, not language rules, and they do not change what a Blink program means. Both still help models a lot (K5 most), so they must be filed as chores, not dropped.
    >
    > Concern: a chore with no gate can slip, so the `blink llms` E0313 entry may not lead with the Map store example for a long time.

  - **Minimalism:**

    > **Q4. Vote: CHORE.**
    >
    > Reasoning: an LSP code action and a docs ordering are tooling and docs, not language. The LSP action reuses the same machine-applicable edit, so it adds no spec surface. Putting them in sections/ would mix implementation details into the language blueprint.
    >
    > Concern: chores without an owner rot. Link both to the E0313 diagnostic ticket so they land together.


No Phase D: every result was 5-1 or 6-0.

#### AI-First review

- Learnability: pass. One rule with no exceptions: brackets hold types, elements use methods.
- Consistency: pass. No change to §2.6, §2.22 or §3.4.
- Generability: pass. One write verb per container.
- Debuggability: pass. The plain store has a machine-applicable fix, the reason note helps a model generalize to reads and `op=`, and the Map compound note shows both forms.
- Token efficiency: borderline. `m.insert(k, v)` costs about two tokens more than `m[k] = v`. The `xs[i] += 1` cost on a List belongs to the `List.update` ticket.

4/5 pass, so the decision is not flagged.

### Final Spec

```blink
fn main() {
    let mut ages: Map[Str, Int] = Map()

    ages["bob"] = 41       // error[NoIndexOperator]: Blink has no index operator
                           // help: `ages.insert("bob", 41)`
                           // note: brackets hold types (`List[Int]`); elements use methods
    ages["bob"] += 1       // error[NoIndexOperator]: Blink has no index operator
                           // note: `ages.insert("bob", (ages.get("bob") ?? 0) + 1)` when a missing key starts at 0,
                           //       or `ages.insert("bob", ages.get("bob").unwrap() + 1)` when it is a bug
}
```

- `m[k] = v`, `xs[i] = v` and every other index form stay E0313. There is no bracket write sugar.
- Every store diagnostic carries a one-line reason `note:`: brackets hold types, and elements use methods. The content is normative and the words are not. The reason holds for every receiver type and position, so it never names allocation. The headline does not change.
- A Map compound write `m[k] op= v` gets a `note:` with the default form first and the `.unwrap()` form second. The literal `0` or `0.0` appears only for `+=` and `-=` on `Int` or `Float`. Any other case gets a placeholder that does not parse. There is no machine-applicable fix. A key that is not a literal, a local or a `const` keeps the let-bind note.
- The LSP quick-fix and the order of the E0313 docs are chores, not spec text.

### Follow-ups the panel asked for

- Measure E0313 hit rates by form in model output (DevOps, AI/ML, Minimalism). With data, the panel can reopen this.
- A regression test locks in the one-verb store help, never `.insert` for a List (Systems).
- A later audit must argue for all bracket forms together, never one form at a time (PLT).
