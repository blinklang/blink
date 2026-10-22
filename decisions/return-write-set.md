[< All Decisions](../DECISIONS.md)

# Mutation Lints: the Return Write Set — Design Rationale

W0550 and W0551 read the write set of the callee (§4.16.4). The write set holds a write that only a path ending the
process can reach, such as `err = msg` before `exit(101)`. The caller never sees that value, because its restore does
not run either. The lints fired on these writes. This ruling defines a smaller set, the return write set, and says
which paths cut a write out of it.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | A write in a callee declared `()` that has no path to the normal return of the callee | P: the write is out. One path rule applies in every body, so `die` has an empty return write set with no `-> Never` on it, and so does an inline `err = "neg"` before `env.exit(101)`. A write on a path that reaches the return (`count`) stays | 6-0 |
| Q2 | Help line when the warning still fires | H1: a note that names the write site and the call chain, and `help: save and restore `err` around the call, or end that path in a call to a `-> Never` function`. No "declare it `-> Never`" line | 6-0 |
| Q3 | Where the return write set is defined | S4: §4.16.4, next to the write set; §4.16.7 says the two lints read it | 6-0 |

Agreed by all six, without a vote: the §4.16.4 write set stays as it is, and tools and other diagnostics keep reading
it; a path ends only at an expression of type `Never` (§3.3), and no `-> Never` is inferred from a body; a callee
declared `-> Never` adds nothing; no exception for an `Env.Exit` handler (§4.4.3: the handler body for a `-> Never`
op must diverge); test-runner and `assert_panics` paths are out of scope for these lints.

**Prerequisite.** Bare `exit(c)` must have type `Never`, as §4.4.3 maps it to `env.exit(c)`. The compiler types it
`()`. That is a compiler bug, filed separately; until it is fixed, the example in the Final Spec does not
compile with a bare `exit`.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in
independent-proposal, debate, vote rounds. The text below is excerpted from each panelist's own text. A quote is cut
at a sentence end, and line breaks in the source files are joined.

#### Phase A — Independent proposals

All six seats proposed a smaller set for the lints to read and kept the §4.16.4 write set whole. All six opposed
"do nothing, declare `-> Never` and suppress with `@allow`".

- **Systems** (`A/sys.md`):

> sys-1 (recommended): return-visible write set, divergence by declared `Never` only

> Keep the 4.16.4 write set as it is. Add a subset, the **return-visible write set**, and make W0550/W0551 read only that subset.

> A fn that always diverges but does not declare `-> Never` still counts its writes.

- **Web/Scripting** (`A/web.md`):

> web-1 (my pick): the lints read the writes that can reach a normal return

> If every path in `die` ends in `exit`, then no path reaches `die`'s return, and its return write set is empty.

- **PLT** (`A/plt.md`):

> plt-1 — Returning write set, cut only by `Never`-typed calls (recommend)

> That is a property of the normal-return edge of the call.

> Using the gross set is not "conservative", it checks a different property.

- **DevOps/Tooling** (`A/devops.md`):

> devops-1 (main): the lints read a "return write set"; only the declared `Never` type cuts a path

> §4.16.4 keeps the write set as it is (every write, on any path). Tools keep showing it: when a user debugs a crash, hover must still say that `die` writes `err`.

- **AI/ML** (`A/aiml.md`):

> aiml-1 (recommended): return write set, divergence by declared type only

> The model already learns §3.3 to type `-> Never` callees; the write-set rule reuses it word for word.

- **Minimalism** (`A/min.md`):

> min-1 (preferred): one sentence in 4.16.7, keyed on the declared `-> Never`; no inference, no new set name

> That is all. The 4.16.4 write set stays as it is (gross, every write).

> Inferring `Never` from "a body that always ends in exit/panic" is a new analysis with its own edge cases (loops, handlers, `process.exec(...)?`), and it would make the lint disagree with the type checker.


##### Phase A options

- **P — path cut inside the callee** (plt, web): a write counts only when some path from it reaches the normal return; a path ends at any §3.3 `Never` expression.
- **D — declared callee cut** (sys, aiml, devops): the same set, but a callee declared `()` that always diverges keeps its writes, and a help line says to declare it `-> Never`.
- **M — declared `-> Never` only** (min): a call to a fn declared `-> Never` adds nothing; no cut inside a body.

#### Phase B — Debate, round 1

Four seats moved to P, and two dropped an exception for an `Env.Exit` handler. Quotes from `B1/`:

- **Systems** moved from D to P:

> My sys-1 text contradicts itself.

> That is option P (plt-1, web-1).

> I withdraw it and support **P**.

- **AI/ML** moved from D to P:

> My own Phase A text did not hold together.

> plt's point stands: one rule applied the same way at every level gives R(die) = {} with no annotation, and no `-> Never` inference either.

- **DevOps/Tooling** moved from D to P:

> My own Phase A definition already gives P's result, and my text contradicted it.

> I withdraw "declare `-> Never`" as the main help line.

- **Minimalism** moved from M to D in Phase B, and to P in Phase C:

> I opposed path analysis because I took it to be a new analysis.

> It is not: the set D needs is "writes before a §3.3 `Never` expression", and the type checker already computes §3.3 divergence for body completeness.

- **PLT** held P and showed that D needs a second clause:

> To keep `err` (as D's prose says), D needs one more clause: "the cut applies only in the caller's body, and an undeclared callee adds its full set".

> I oppose that clause, and with it removed, D is P.

- **Web/Scripting** held P and dropped its handler exception:

> My exception has no case to cover.

> I drop it and join plt, devops and min.

- **Systems** dropped its handler exception (the V2 exception):

> I withdraw my exception, and I oppose web's for the same reason.

All six seats ended Phase B stable and ready to vote.

#### Phase C — Votes

##### Q1 — A write in a callee declared `()` that has no path to the normal return

| Seat | Vote |
|---|---|
| Systems | P |
| Web/Scripting | P |
| PLT | P |
| DevOps/Tooling | P |
| AI/ML | P |
| Minimalism | P |

- **Systems** (`C/sys.md`), vote P:

> P is the cheapest rule that is also correct. It uses one reachability bit per write and the same SCC fixpoint that the write set already uses, with no special case at the call site for a declared `-> Never`, because that case falls out of the rule. D runs the same body pass but then adds the writes back for a callee declared `()`, which makes the analysis do more work to give a less precise answer. The write set is already inferred from bodies across calls, so P adds no new kind of change at a distance.

> Concern: with P the lint no longer pushes anyone to declare `-> Never`, so the codegen benefit (`noreturn` in the C output, cold paths moved out of the hot path) may go unclaimed unless a separate lint or the codegen notes asks for the annotation.

- **Web/Scripting** (`C/web.md`), vote P:

> The accessor that dies on a bad id is the most common shape, and under P it gets no warning with zero edits. The rule is one rule, used the same way in every body: a path ends at a `Never` expression. A JS or Python dev can predict it without reading about a "declared vs. body" split. Under D the compiler proves `die` cannot return and then warns anyway, so users read the lint as noise and reach for `@allow`.

> Concern: If the spec text is loose about "a call to a `()` fn is taken to return", users may read P as "the compiler infers `-> Never`" and expect that inference in other places, such as unreachable-code checks, where the language does not give it.

- **PLT** (`C/plt.md`), vote P:

> P is one rule applied in every body: a write counts only when a path from it reaches a normal return, and a path ends at a `Never` expression (§3.3). The callee's set is the set its own body gives under that rule, so the fixpoint is compositional. D makes the set of a callee depend on whether it is computed for the callee or for its caller. Like the write set it refines, P comes from bodies and infers no type. It never drops a write that can be seen after a return, so it is sound.

> Concern: P is sound only once bare `exit(c)` types as `Never`. Until the compiler bug is fixed, the MVCE keeps firing and users may read that as P failing.

- **DevOps/Tooling** (`C/devops.md`), vote P:

> Every body gets the same path rule, so the analysis has one rule to explain. Hover can show `writes {err} · on return {}`, and the user sees why `err` was dropped without having to edit `die`. D makes the user add `-> Never` to helpers only so that the lint goes quiet, and that edit does not change what the program does. Write sets are already inferred from bodies, so P adds no new kind of action at a distance.

> Concern: If hover and `blink query --fn` do not show the return write set beside the write set, a user who adds an early `return` to `die` gets new warnings in far callers and has no visible cause.

- **AI/ML** (`C/aiml.md`), vote P:

> One rule, "a write counts only if it can reach a normal return", applies the same way in every body, and a model that knows §3.3 needs no second fact to predict the lint. D adds a fact the model must hold apart ("but a `()` callee keeps its writes"). That fact also contradicts the path rule inside that same callee's body. The write set was never in the signature anyway, so D's appeal to the signature buys a model nothing.

> Concern: Someone edits a diverging helper so that one path returns, and warnings appear in far callers. A model cannot see the cause from the call site, so the note must name the write site and the path.

- **Minimalism** (`C/min.md`), vote P:

> I move from D to P. plt showed that D, as written, needs an extra clause ("an undeclared callee adds its full set"), so a callee's set changes with the place you compute it from. That is a second rule, and P is one rule used at every level. My "action at a distance" argument fails, because §4.16.4 write sets already come from bodies, transitively. P adds no annotation, no type change and no new divergence notion. It is the smallest correct rule.

> Concern: Path cuts at each level could grow into ad-hoc refinements, such as branch conditions or per-handler scopes. The spec text must state that §3.3 `Never` is the only cut.

##### Q2 — Help line when the warning still fires

| Seat | Vote |
|---|---|
| Systems | H1 |
| Web/Scripting | H1 |
| PLT | H1 |
| DevOps/Tooling | H1 |
| AI/ML | H1 |
| Minimalism | H1 |

- **Systems** (`C/sys.md`), vote H1:

> under P, a callee whose every path ends in a `Never` expression already has an empty return write set, so H2's extra condition can never be true on a warning that fires. H2 then adds a check that never fires, plus a code path to keep in step with it. When P fires, the write really does reach a return, and H1 gives the two fixes that are true.

> Concern: if the call-chain note does not give the write's file:line, users with deep accessor chains (such as `checked_node_id` to `node_die`) will search by hand for the write site.

- **Web/Scripting** (`C/web.md`), vote H1:

> Under P, H2's trigger never leads to a warning: a callee whose every path diverges already has an empty return write set. That makes H2's extra line dead text in the spec. A warning that still fires is a real write that can reach the return, so the useful fix is to save/restore it or cut that path. A note that names the write site and the call chain answers "why did this fire?", which today's `item writes {err}` does not.

> Concern: If the note does not show the full call chain (accessor → `node_die` → `diag_ice_abort`), users will still have to hunt for which branch reaches the return.

- **PLT** (`C/plt.md`), vote H1:

> Under P, a callee whose every path ends in a `Never` expression already adds nothing. So H2's extra line names a fn that is not the cause of the warning, and declaring it `-> Never` removes nothing from the set. A help line must name an edit that makes the warning stop. Otherwise it teaches a false model of the rule. The one real case is a write placed after a call to such a fn in the caller's own branch. H1's "end that path in a call to a `-> Never` function" already covers that case.

> Concern: If H2 wins, its condition must be "declaring this fn `-> Never` removes the reported write". The condition "some fn on the chain always diverges" makes the line wrong in most cases where it shows.

- **DevOps/Tooling** (`C/devops.md`), vote H1:

> Under P, H2's condition can never hold: a callee whose every path ends in `Never` has an empty return write set, so the warning cannot fire through it. The extra line would be dead code in the diagnostic engine and a false hint in the spec. H1 names the write site and the call chain, and that is the information the user needs to find the write that really returns.

> Concern: A chain note through deep accessors (`register_trait` → `node_name` → ...) can grow long, so the renderer needs a cap on the shown chain (for example the first and last hop plus a count).

- **AI/ML** (`C/aiml.md`), vote H1:

> Under P, a callee whose every path ends in a `Never` expression already has an empty return write set, so H2's extra line has no case to fire on. A help line that never fires is dead text in the spec, and a model may imitate it. H1 names the write site and the chain, which gives a model the one-shot fix.

> Concern: "end that path in a call to a `-> Never` function" may lead models to add `-> Never` helpers where a save/restore is the correct fix.

- **Minimalism** (`C/min.md`), vote H1:

> Under P, a callee declared `()` whose every path ends in `Never` has an empty return write set, so it never causes the warning. H2's extra line only covers a rare case, where the caller writes after such a call on the same path. YAGNI: one help line that is always true is better than a second line with its own trigger condition to specify and test.

> Concern: Without the `-> Never` hint, users may not learn that the annotation also tightens analysis after the call. That costs little and doc text can cover it.

##### Q3 — Where the return write set is defined

| Seat | Vote |
|---|---|
| Systems | S4 |
| Web/Scripting | S4 |
| PLT | S4 |
| DevOps/Tooling | S4 |
| AI/ML | S4 |
| Minimalism | S4 |

- **Systems** (`C/sys.md`), vote S4:

> the return write set is a property of the callee, computed by the same pass as the write set, so its definition belongs next to it. Other tools and later work (the exit-path check for binding spans, gross-vs-net) will read it, and §4.16.7 is about lints, not about sets. If §4.16.4 is its only home, the binding-pair text and any later diagnostic can point to one definition.

> Concern: readers of §4.16.4 may take the return write set to replace the write set, so the text must say plainly that the two lints are its only readers today.

- **Web/Scripting** (`C/web.md`), vote S4:

> Hover and tools will show both sets side by side (`writes {err} · on return {}`), so the reader looks for the definition next to the write set. §4.16.7 then only says which set the lints read, which keeps the lint text short. The binding-pair rule and the gross-vs-net follow-up can then refer to one defined term, with no second definition.

> Concern: A reader who jumps straight to §4.16.7 from the warning code may miss the definition unless §4.16.7 links back to §4.16.4 by name.

- **PLT** (`C/plt.md`), vote S4:

> The return write set is a property of a function, like the write set. The binding-pair rule, gross-vs-net and the exit-path check will each need it, so it must have one definition next to the set it refines. §4.16.7 then says only that the two lints read it.

> Concern: §4.16.4 must then say plainly that tools and other diagnostics still read the full write set. If it does not, a reader may take the subset as the new meaning of "write set".

- **DevOps/Tooling** (`C/devops.md`), vote S4:

> The set is something that tools print (hover, `blink query --fn`, diagnostic notes), and the exit-path follow-up reads W \ R. So it belongs next to the write set it filters, not inside one lint's section. §4.16.7 then needs one sentence that says the two lints read it.

> Concern: If §4.16.4 defines the set but the tooling note there does not list it, LSP and `blink query` may ship without it, and the drop stays invisible.

- **AI/ML** (`C/aiml.md`), vote S4:

> The binding-pair rule, the exit-path follow-up (W \ R) and gross-vs-net (net ⊆ R) all refer to this set. One definition next to the write set is what a model retrieving §4.16.4 will find. A definition kept only in §4.16.7 gets missed when the later rules cite it.

> Concern: Readers of §4.16.4 may take the return write set as the one tools report; the text must say that tools and hover keep the full write set.

- **Minimalism** (`C/min.md`), vote S4:

> The return write set is a property of the callee, like the write set. The binding-pair rule, gross-vs-net and the exit-path check (W \ R) will all refer to it. One definition next to its parent is less text than paraphrases in several places. I drop my S7 preference.

> Concern: Once the set is named in §4.16.4, tools and later diagnostics may start to read R where they need W. Each new reader must say which set it uses.

Result: Q1 P 6-0, Q2 H1 6-0, Q3 S4 6-0. No Phase D was needed.

## Final Spec

§4.16.4 keeps the write set and adds the return write set next to it. §4.16.7 says W0550 and W0551 read it.

```blink
let mut pos = 0
let mut err = ""
let mut count = 0
let mut items: List[Int] = [1, 2, 3]

fn die(msg: Str) ! Env.Exit {                   // writes {err}, on return {}
    err = msg
    env.exit(101)
}

fn item(i: Int) -> Int ! Env.Exit {             // writes {err}, on return {}
    if i < 0 || i >= items.len() { die("bad index") }
    items.get(i).unwrap()
}

fn step(n: Int) -> Int ! Env.Exit {             // writes {err, count}, on return {count}
    if n < 0 {
        err = "neg"
        env.exit(101)
    }
    count = count + 1
    n
}

fn peek() -> Int ! Env.Exit {
    let saved = pos
    let v = item(pos)                           // no warning
    pos = saved
    v
}
```

Locked points:

1. The write set (§4.16.4) does not change. Tools, hover and other diagnostics read it.
2. The return write set of a function holds the writes in its write set that lie on some path that reaches the normal return of the function.
3. A path ends only at an expression of type `Never` (§3.3). Nothing else ends a path.
4. A call adds the return write set of the callee, and only on paths of the caller that reach that call and go on.
5. A callee declared `-> Never` adds nothing. No `-> Never` is inferred from a body; the type of a function does not change. A `()` function whose every path ends in a `Never` expression has an empty return write set and is still `()` for typing and reachability.
6. No exception for an `Env.Exit` handler (§4.4.3).
7. Test-runner and `assert_panics` paths are out of scope for these lints.
8. A warning that still fires has a note that names the write site (`file:line`) and the call chain, and the line `help: save and restore `err` around the call, or end that path in a call to a `-> Never` function`. There is no "declare it `-> Never`" help line.
9. Prerequisite: bare `exit(c)` has type `Never`.

