[< All Decisions](../DECISIONS.md)

# Stderr Row and Dispatch — Design Rationale

This ruling settles the open case named in [Escape-Hatch List and `_raw` Dispatch](escape-hatch-list-and-raw-dispatch.md): the row and the dispatch of `io.eprint`, `io.eprintln` and `io.eprint_raw`.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Panelist text below is verbatim; "[...]" marks a cut.

Options. **Q1**: **E** `IO.Eprint` is a real sub-effect of `IO`; **L** the three operations join `IO.Log`; **N** stderr has no row and no handler, and `capture_eprint` goes. **Q2**: **R-off** runtime stderr writes stay off the handler; **R-on** they go through it.

#### Phase A — Independent proposals

##### Systems

> "So stderr is ALREADY dispatched. The only thing missing is the static row. A row is pure typecheck work: it adds zero instructions, because evidence lives in a global and is not a hidden parameter." — Systems

##### Web/Scripting

> "**The 5-minute test passes.** `io.println` → `IO.Print`, `io.eprintln` → `IO.Eprint`, `io.log` → `IO.Log`. Each effect has the name of the call you typed. Nothing to learn beyond what Print already taught." — Web/Scripting

##### PLT

> "That breaks the one property rows are for: an empty row means the call is observationally pure." — PLT

##### DevOps/Tooling

> "The row rule is the same as for io.println: private fns get it inferred, pub fns declare it, `! IO` grants it. When E0500 starts to cover builtin calls, stderr and stdout start together, with no exemption." — DevOps/Tooling

##### AI/ML

> "The compiler does not row-check a direct handle-op call at all. That is the open bug [...] (P1). So the "many call sites with no row" count covers println, not only eprint." — AI/ML

##### Minimalism

> "IO.Log already exists, and it already writes to stderr. The eprint ops join it." — Minimalism

#### Phase B — Debate highlights

Every seat reported "stable, ready to vote" after round 1. No seat dissented on the final shape.

##### Minimalism moves from L to E

> "I proposed L to keep the effect tree from growing. That argument was weaker than I said:" — Minimalism

> "One new name that follows the rule costs less than zero new names plus an exception." — Minimalism

##### The claim that `capture_log` would see eprint text

The claim under correction (Systems, S4, as quoted in the debate): "changes what capture_log sees (it would receive eprint text)".

> "Dispatch goes per op, so the two capture helpers stay apart under both E and L." — DevOps/Tooling

> "So S4's capture argument fails as stated." — AI/ML

> "To sys S4 ("capture_log would receive eprint text"): that is not true of min-1 as min wrote it." — PLT

##### A later split is not additive

The claim under correction (Minimalism, as quoted in the debate): "If structured logging ever moves `io.log` off stderr, splitting the effect then is an additive change."

> "It is not additive. A later split narrows what `! IO.Log` grants." — PLT

> "It is not additive. Under L, every fn that calls io.eprintln declares `! IO.Log`. Split Eprint out later, and each of those fns loses permission for its own eprintln and gets E0500." — Systems

> "I disagree: it is breaking. Under L, a fn that only reports errors declares `! IO.Log`. If eprint later moves to its own `IO.Eprint`, that row stops covering the fn's calls and every such fn fails E0500." — Web/Scripting

No dissent: Q1 and Q2 both passed 6-0.

#### Phase C — Final vote

##### Q1 The row and dispatch of `io.eprint`, `io.eprint_raw` and `io.eprintln`

**Q1: E 6-0.**

- **Systems**: E
  **Reasoning:** "The runtime already dispatches eprint and eprint_no_nl through their own vtable slots and userdata words, and evidence sits in a global. So the row is pure typecheck work, with zero new instructions and no runtime ABI change except the eprint_raw slot. A separate sub-effect keeps "log channel" and "operator stderr" as two grants a host can give or redirect on their own. Splitting them later, after L, would break every `! IO.Log` caller of eprintln, so the split costs one name now or a breaking change later. N saves one indirect call next to a syscall, and the price is §4.1's purity claim."
  **Concern:** "io.* row enforcement (E0500 on builtin namespace calls) is not done yet, so IO.Eprint stays a row on paper until that bug lands, and the 550-site migration falls on that change."
- **Web/Scripting**: E
  **Reasoning:** "The row name matches the call the user typed: io.println goes with IO.Print, io.eprintln with IO.Eprint, io.log with IO.Log. A JS or Python dev learns that in 5 minutes. Users can still capture stderr in tests (as with Jest console.error spies or pytest capsys), and there is no rowless exception to explain. L puts a "logging" name on error output and turns a later split into a breaking change. N leaves stderr impossible to test and breaks @pure."
  **Concern:** "The required row lands only when the open P1 bug for builtin namespace row checks gets fixed. The ~500 call sites in rowless fns then all fail at once, so the migration needs the machine-applicable E0500 fix ready before it ships."
- **PLT**: E
  **Reasoning:** "The algebra gets an effect that `Handler[IO.Eprint]` already assumes, so the row, the dispatch and the handler type agree, and §4.5 holds with no stderr exception. An effect names a capability ("may emit diagnostics"), not a file descriptor. Log, with its `[LOG]` structured-subsystem meaning, is a different capability. E can be widened later (Log grants Eprint) without breaking code, while L can only be split later by narrowing what `! IO.Log` grants, which breaks code. N makes `@pure` and the empty row false by design."
  **Concern:** "The rows mean nothing until the open P1 bug is fixed (direct `io.*` handle-op calls are not row-checked). If eprint enforcement does not land together with println/log enforcement, the spec promises a proof the compiler does not make."
- **DevOps/Tooling**: E
  **Reasoning:** "The E0500 help and fix name the effect the user called: "needs IO.Eprint" for an `io.eprintln` call. It does not name IO.Log, which §4.3 calls the logging subsystem. Op names keep a one-to-one map to sub-effects (print→Print, eprint→Eprint, log→Log, read→Read), so hover, completion and the help text stay one table lookup. A split cannot change later without breaking someone, so we should split by subsystem now, not by file descriptor. E also turns two bad diagnostics into good ones: E0538 on a type that the stdlib exports goes away, and typecheck.bl:8340 starts to reject `handler IO.Print { fn eprint ... }`, which it passes in silence today."
  **Concern:** "When builtin io.* calls become row-checked, every public fn that calls eprint and declares only `! IO.Print` or `! IO.Log` gets a new E0500. Unless `blink fix` applies "add effect IO.Eprint" at those direct builtin call sites as it does for user fn calls, the migration will feel like a flood of errors and not a one-command fix."
- **AI/ML**: E
  **Reasoning:** "Under E every io.* op has a row that follows from its name (print→Print, eprint→Eprint, log→Log, read_*→Read), so a model writes the right row from the spec alone with no lookup. testing.bl, the runtime and §6 already use `IO.Eprint`, so the name a model is most likely to guess is also the right one. L makes the row something to memorize, and N keeps a side effect with no row in "pure" fns and loses stderr capture in tests."
  **Concern:** "the row migration (159 src + test sites) must land with the fix for unchecked direct handle-op calls, or the spec will say a row is needed while the compiler still accepts a rowless eprintln, and models will learn the gap from code that compiles."
- **Minimalism**: E
  **Reasoning:** "The spec gets one new name that follows the rule users already learn (the op prefix names the leaf: print→Print, eprint→Eprint, log→Log, read→Read). L would need an exception for eprint. testing.bl, the runtime vtable and the typecheck comments already use IO.Eprint, so E is the smallest change to the whole system, not only to the spec. N keeps a side effect with no row and breaks §4.1, and my @pure probe shows that hole is real today."
  **Concern:** "Some sites will migrate to `! IO.Eprint` while others still have no row-check error, until the direct io.* row-check bug lands. Turn on the eprint row check in the same change as that fix, not as a separate, earlier break."

##### Q2 Runtime writes to stderr

**Q2: R-off 6-0.**

- **Systems**: R-off
  **Reasoning:** "Panic, abort, assert, test-report and trace writes are runtime writes, not Blink operations, so §4.5 does not cover them. If a user handler sat on this path, a broken capture handler could hide a panic, a panic in an eprint op could recurse, and trace output would depend on the code being traced. The runtime should keep writing these to fd 2 directly."
  **Concern:** "a later "cleanup" could route the runtime panic path through io.eprintln. The spec needs one sentence that forbids it, and a test that panics inside `with capture_eprint` and checks the terminal output."
- **Web/Scripting**: R-off
  **Reasoning:** "Users expect a crash to stay visible even while they mock stderr, the same as mocking console.error in Jest does not hide a crash and pytest still prints its failure report. If a capture handler swallowed a panic, the test would fail with no message, which is the worst debugging experience we could ship. Panics, assert failures, the runner report and trace are not Blink ops, so the handler does not own them."
  **Concern:** "Users may be surprised that a panic message does not show up in the List that capture_eprint fills, so the spec and the llms docs for capture_eprint must say so in one plain sentence."
- **PLT**: R-off
  **Reasoning:** "§4.5 constrains Blink operations, and a panic or assert report, the runner report or trace NDJSON is a runtime write that no effect owns. So keeping these off the handler is sound. It is also the right semantics: a capturing or buggy handler must never hide a panic."
  **Concern:** "The writer must limit the exemption to runtime writes. Stdlib Blink code that calls `io.eprintln` is an ordinary op, and it escapes a user's `with` only by running outside its dynamic scope. If the spec text blurs that line, someone will read it as "stdlib stderr skips handlers"."
- **DevOps/Tooling**: R-off
  **Reasoning:** "Panic, assert, test-runner and trace output is how a user debugs a failure. If a handler could catch it, a panic inside `with capture_eprint(got) { ... }` would vanish into a List and the user would see a silent exit, which is the worst case for a tool. These writes are runtime behavior, not Blink operations, so §4.5 does not reach them."
  **Concern:** "Without one explicit spec sentence, a later contributor may "fix" the panic path to call the eprint vtable slot because it sits next to the others, so the spec should say it and a test should pin it."
- **AI/ML**: R-off
  **Reasoning:** "A panic or assert failure must always reach the terminal; if a capture handler can hide it, debugging an agent's failing test turns into guesswork. Runtime writes are not Blink ops, so routing them through a handler would also break the rule "an op needs its row" for code that never calls one."
  **Concern:** "if the spec does not state R-off in one plain sentence next to the op table, a later contributor or model may "make it consistent" by routing panics through io.eprintln."
- **Minimalism**: R-off
  **Reasoning:** "The runtime's panic and abort messages, assert failures, the test-runner report and the trace output are not Blink ops, so they need no row, no handler and no new rule. If a capture handler could hide a panic message, a debugging aid would turn into a trap. Say this in one sentence in the spec, so nobody routes the panic path through io.eprintln later."
  **Concern:** "The sentence must name the runtime writes as a closed list, so it does not become a loophole for stdlib code that writes to fd 2 with no row."

### Final Spec

```blink
effect IO { effect Print  effect Eprint  effect Log  @handle_all effect Read }

import std.testing.{capture_eprint}

fn warn(msg: Str) ! IO.Eprint {
    io.eprintln("warn: {msg}")
}

fn quiet() ! IO.Print {
    warn("x")        // error[UndeclaredEffect] E0500: `warn` requires `IO.Eprint`
}

fn main() ! IO {
    let got: List[Str] = []
    with capture_eprint(got) { warn("a") }
    io.println("captured {got.len()}")   // stdout: captured 1
    warn("b")                            // stderr: warn: b
}
```

- `io.eprintln(x)`, `io.eprint(x)` and `io.eprint_raw(s)` are `IO.Eprint` operations: they have a row, a handler can intercept them, and they emit trace records.
- The handler operations mirror `IO.Print`: `fn eprint(msg: Str)`, `fn eprint_no_nl(msg: Str)` and `fn eprint_raw(s: Str)`. `eprint_raw` is derived: its default body calls `eprint_no_nl(s)`. The default handler keeps the byte and flush contract of the `_raw` operations. `IO.Eprint` is not `@handle_all`. There is no `eprint_raw_bytes`.
- Argument types do not change: `io.eprint` and `io.eprintln` take `T: Display`, the operation gets `msg: Str`, and `io.eprint_raw` takes `Str`.
- `! IO` grants `IO.Eprint`. The sub-effects are independent: `! IO.Print` and `! IO.Log` do not grant it.
- `capture_eprint` stays `Handler[IO.Eprint]`. `capture_log` and `capture_eprint` see none of each other's text.
- A handler gets `msg` with no newline: `warn: a` for both `io.eprintln("warn: a")` and `io.eprint_raw("warn: a")`.
- Runtime writes to stderr are a closed list: panic and abort messages, assert failures, the test runner report, and trace output. They are not Blink operations and never reach the `IO.Eprint` handler. A panic inside `with capture_eprint(got) { ... }` reaches the terminal, and its text does not land in `got`.
- The runtime exemption covers runtime writes only. Blink-level stdlib code that calls `io.eprintln`, the test runner's own Blink code included, calls an ordinary operation. It escapes a user's `with` only when it runs outside the dynamic scope of that `with`.
- The ruling adds no row-free debug primitive.

### Implementation notes

- The row check for `io.eprint*` lands together with the fix for unchecked direct `io.*` handle-op calls, so call sites migrate once (about 550 sites). The add-effect fix must be machine-applicable at direct builtin call sites.
- `@pure` must reject `io.eprintln` and `io.log`. A probe shows that both pass today.
- `eprint_raw` needs its own runtime handler slot. Add it in the same ABI change as the missing `print_raw` and `print_raw_bytes` slots, and route `io.print_raw` through the handler: a direct call skips it today.
- typecheck: add `Eprint` to the `IO` sub-effect table. A `handler IO.Print { fn eprint ... }` must then be rejected.
- Add a test that panics inside `with capture_eprint` and checks the terminal output.
- Keep the E0500 note that a builtin namespace call is not yet checked: it is still true of the compiler.
- The libc fd rule in §9.1 says that fd 2 counts as made by `IO.Log`. It needs a follow-up edit to say `IO.Eprint`.
