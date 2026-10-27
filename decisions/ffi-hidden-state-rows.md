[< All Decisions](../DECISIONS.md)

# @ffi Rows for Hidden C State — Design Rationale

**Question.** May an `@ffi` binding that reads C hidden state (`errno`, a thread-local stat buffer) claim `! ()`?

**Answer.** No. `! ()` on an `@ffi` decl claims that the result depends only on the arguments and on data they reach. Hidden state that no argument reaches and that a later call can see needs a row. The first fix is to make the producer return the data. Then use the effect that names the resource. `State` is the fallback.

### Panel Deliberation

Six seats voted: Systems, Web/Scripting, PLT, DevOps/Tooling, AI/ML and Minimalism. The quotes below come from the seats' own replies. Where a quote has a "[...]", the text there was a source line number or a ticket reference.

#### Phase A — Independent proposals

All six seats rejected the option "thread-local C state is not a Blink effect". All six gave the same test: the result depends only on the arguments and on data they reach.

**Systems:** "`! ()` means GCC `__attribute__((const))` over the arguments and the cells they reach. Hidden per-thread C state disqualifies a binding. Fix the API (producer returns the data); where the state cannot leave, the binding takes the row of the effect that owns it. No new effect, no new rule surface beyond one sentence of definition."

**Web/Scripting:** "one rule a Python/JS dev learns in 5 minutes, plus an API fix so std needs no rule at all."

**PLT:** "`! ()` needs a typing rule you can check. None of the four zero-arg readers passes it. Fix the API. Do not stretch the meaning of `! ()`."

**DevOps/Tooling:** "`! ()` must mean "safe to CSE, hoist, memoize, reorder". Today nothing in the toolchain uses that, but the first optimizer pass or LSP "pure, safe to inline" hint that trusts it will miscompile `c_errno()` (hoisted above the failing `c_read`) and `c_fs_stat_size()` (CSE'd across two stats). So the rule must be one a lint can check in part. Hidden state that carries a value from one call to a later call is NOT `! ()`. My order of fixes: (c) change the API first; else `State`; never the producer's row."

**AI/ML:** "An AI must get each @ffi row right from the spec alone, and the compiler cannot check it (§9.1). So the rule has to be one yes/no question, not a list of cases".

**Minimalism:** "no new effect and no new syntax. §4.16.3 already answers the question. Apply it to @ffi, then change two stdlib APIs so that the hard cases go away."

#### Phase B — Debate highlights

Round 1 confirmed eight shared points: the rejected option, the test, the `-errno` shims, the unobservable `errno` write, the constant C locale, `! ()` allocators, `! Arena` for the arena counters, and the stat readers leaving `! ()`. Three questions stayed open: the interim row of the stat readers, the producer's row for a user binding, and the home of foreign state.

On foreign state, five seats reached one position through PLT's order of choice.

**Systems:** "a named built-in effect first (current arena -> Arena, file metadata -> FS.Read), State only as the fallback for foreign state that no argument reaches and no built-in effect names. That precedence answers my "garbage bin" objection, and State costs nothing at run time and blocks CSE, which is all the systems seat needs."

**Systems, on GC switches:** "GC_gcollect: `! State`. A Void `! ()` call with no `mut` param is dead code by definition; a compiler may delete it. min's `! ()` is wrong for exactly that reason."

**Minimalism:** "**GC_gcollect: I change to `! State`.** plt is right: a `! ()` call with no result is dead code that a compiler may delete. My "nothing observable" argument proves the opposite of what I wanted it to."

**DevOps/Tooling:** "State means "mutable state no argument reaches, and no named effect covers it". The tooling already works: E0552 names the binding, and its fix is machine-applicable."

**Web/Scripting:** "One familiar word for "state that is not in your arguments" beats a new `Runtime` leaf or an `@runtime` path that users of curl/sqlite globals cannot use."

On the producer's row, the seats split:

**PLT:** "the producer's row is sound, because §4.5 says an assumed row is an upper bound. So the spec cannot forbid it without contradicting §4.5, and it should not try."

**DevOps/Tooling:** "That was my real objection: "missing FS.Read" on code that only reads errno is a lying diagnostic."

**AI/ML:** "A row has to name what the call itself does. If a reader can take its producer's row, a model learns that "a row describes nearby calls", and it will repeat that everywhere."

**Web/Scripting:** "A row says which capability the caller needs."

On handles, PLT corrected its own proposal:

**PLT:** "§3.6 [...] (*What `mut self` covers*) says: "A change to state outside the language — memory behind a `Ptr`, a socket, a file, a database — is an effect, tracked by the effect row ... not by `mut`." `Ptr.write` takes plain `self` for that reason. I proposed `mut h: TcpHandle`, and that contradicts the spec. I withdraw it."

#### Phase C — Final vote

| Question | Systems | Web/Scripting | PLT | DevOps/Tooling | AI/ML | Minimalism | Result |
|----------|---------|---------------|-----|----------------|-------|------------|--------|
| Q2a: row of the stat readers if an interim ships | FS | ST | FS | FS | ST | FS | FS 4-2 |
| Q2b: user reader takes the producer's row | N | N | Y1 | N | N | N | N 5-1 |
| Q4: handle ops | S | P | P | P | P | P | P 5-1 |
| Q5: `mut` on `@ffi` params | A | B | B | B | B | B | B 5-1 |
| Q6: lint for a zero-arg `! ()` decl | AL | NO | AL | AL | AL | NO | AL 4-2 |
| AG block | yes | yes | yes | yes | yes | yes | 6-0 |

Q2a: FS means the interim row is `! FS.Read`. ST means `! State`. Q2b: Y1 allows the producer's row for one producer. Q4: P gives `! ()`; S gives the Net row. Q5: A puts `mut` on handles too; B puts it on Blink values only. Q6: AL is a warning that `@allow` suppresses; NO is no new code.

##### Q2a — the interim row of the zero-arg stat readers

- **Systems (FS):** "Any non-empty row blocks the CSE and deletion that `! ()` licenses, so `! FS.Read` is sound for the interim. The only caller already holds FS.Read, so it costs nothing, and the row goes away when AG2 lands."
- **Web/Scripting (ST):** "Users copy std, even its private bindings, and git history keeps the interim. `! FS.Read` on code that reads a buffer would be a std example of the habit we refuse users in Q2b. `! State` costs nothing here: the only caller is in std, and the row goes away with AG2."
- **PLT (FS):** "Both rows are sound upper bounds, but FS.Read is the tighter one. [...] FS.Read also keeps State out of `fs_do_stat`'s body, where E0552 would push it into the public row the moment the wrapper sees it."
- **DevOps/Tooling (FS):** "ST would make the fs_do_stat body charge State, and E0552 fires only on pub fns that touch State, so ST could push State into the public row of fs_do_stat for the length of the slice. FS changes no public row. It goes away when AG2 lands."
- **AI/ML (ST):** "Each row in lib/std is an example a model will copy. `! FS.Read` on a function that does no FS work teaches that a row may describe a nearby call. `! State` is the fallback AG3 already sets, it is honest about what the getter does, and it gives the same result for the one caller, which already holds FS.Read."
- **Minimalism (FS):** "The row only has to last until AG2 deletes these readers. `FS.Read` is a sound upper bound that the only caller (`fs_do_stat`) already holds, so the interim needs no change at the call sites. `State` would trigger E0552 on a pub wrapper and add a row for a few weeks, and then AG2 would remove it again: churn for no lasting gain."

##### Q2b — a user reader of hidden state with one producer

- **Systems (N):** "For users, one fallback row (State) is simpler guidance than a producer's-row exception with a "one producer only" condition the compiler cannot check. Both block the optimizer equally; State just doesn't claim a capability the call does not use."
- **Web/Scripting (N):** ""A row is what the call itself needs" is a rule a JS/Python dev learns once and applies everywhere. "A producer's row is fine if there is one producer, but not with errno" is a conditional rule that brings Stack Overflow questions: how do I count producers, and what if my C lib adds a second?"
- **PLT (Y1, dissent):** "§4.5 defines an assumed row as an upper bound on the foreign call's behaviour. A one-producer reader holds `FS.Read` as a sound bound, so forbidding it would contradict §4.5. The rule to write down is soundness: an upper bound that misses a producer is a false row, so errno never qualifies. Preferring "return the data from the shim" belongs in guidance, not in the typing rule."
- **DevOps/Tooling (N):** "The user-facing rule must give one answer an LSP quick-fix and a help line can state: "add `State`, or have the shim return the value". Y1 needs the author to know whether a producer is unique, which no tool can check [...]. I accept plt's point that the compiler cannot reject a sound upper bound. N only fixes what the spec, the help text and the examples teach." Concern: "a user who writes the producer's row anyway gets no diagnostic, so the rule is guidance only. The spec should say so plainly, so nobody reads it as an error that is not enforced."
- **AI/ML (N):** "Y1 adds a decision point a model cannot check: "is there exactly one producer?" errno shows that a model will get this wrong, since errno looks like it has one producer at each call site. One rule ("the row names what this call does; hidden state is State") covers every case with no count to make."
- **Minimalism (N):** "A single rule for users is the smallest surface: the row names what the call itself does, and when nothing names it, use `State`. Y1 adds a second path with an exception ("one producer only, not errno") that every reader and auditor has to remember."

##### Q4 — handle operations such as `tcp_handle_fd` and `tcp_handle_take`

- **Systems (S, dissent):** "Q4 and Q5 interact. If handles carry no `mut` (Q5-B, the likely winner), then under P `tcp_handle_take(h) ! ()` looks to an optimizer exactly like a const read of `h`, and `tcp_handle_fd(h)` can be CSE'd or moved across it; W2's rule has nothing to see. Either A+P or B+S is sound; B+P is not."
- **Web/Scripting (P):** "closing or taking a handle you hold is normal method behavior in every web/scripting language (socket.end(), f.close()). What changes is reached through `h`. Putting a Net leaf on take but not on fd makes two calls on the same handle differ in a way nobody would guess." Concern: "a copy of a handle sees the take through aliasing that no row or `mut` shows".
- **PLT (P, moved from S):** "`Ptr.write` writes through its argument under that boundary without any row, and a handle slot is the same case. S, applied consistently, would put a row on every Ptr write, which nobody proposed". Concern: "the optimizer premise in W2 must count any `! ()` call that takes a Ptr or `@ffi.opaque` argument as possibly writing what it reaches. Otherwise `tcp_handle_fd(h)` can be CSE'd across `tcp_handle_take(h)`."
- **DevOps/Tooling (P):** "S2 counts data the arguments reach, and the handle is the argument. Under S, tcp_handle_take would say Net.* while it does no socket I/O, so "missing Net.Close" on a caller that only takes the fd is the same lying-diagnostic class I rejected for errno."
- **AI/ML (P):** "Both ops read or write only a slot the argument reaches. That is the S2 test, and it is the same shape as List.push. [...] Socket I/O itself keeps its Net row." Concern: "a later handle op that does close the fd could be written `! ()` by mistake. The spec example should show that line."
- **Minimalism (P):** "Both calls change or read only what their argument reaches. That is the S2 test that all six of us confirmed". Concern: "The prose must say that handle copies alias one object."

##### Q5 — `mut` on `@ffi` params

- **Systems (A, dissent):** "`mut` marks where a mutation starts (§3.6), and List copies also share cells, so the "copies share one object" objection holds for List too. It is also the cheapest signal codegen gets that a call writes through its argument."
- **Web/Scripting (B):** "Blink values follow the same rule as Blink fns, so `bytes_push(mut b, ...)` reads like `list.push` and E0610 works as users expect. On opaque handles `mut` would promise protection that copies do not give". Concern: "the line between "Blink value" and "handle" must be clear in the spec text, or authors will guess differently for Ptr-backed wrapper types."
- **PLT (B):** "§3.6 defines `mut` as covering state Blink holds as a value, so an @ffi decl that changes a List/Set/Bytes/StringBuilder param must show it, or Bytes' value semantics break with nothing in the signature to show it. Handles and Ptrs are outside the language and use plain `self` (the `Ptr.write` and `TcpConn.write` precedent), so `mut h` would contradict existing spec."
- **DevOps/Tooling (B):** "E0610 on Blink value params gives a true signal at the caller, the same as List.push. On opaque handles it would fire on every plain-`let` handle holder and promise an exclusive access that copies break."
- **AI/ML (B):** "One rule for Blink and @ffi signatures is easier to learn than an exception for @ffi." Concern: "authors may forget `mut` on an @ffi Bytes param, and the compiler cannot catch it, because the foreign body is not checked. Only an audit catches it."
- **Minimalism (B):** "`mut` on an aliased opaque handle would claim a local root that does not exist, which is worse than leaving it off."

##### Q6 — a warning for a zero-arg, non-Void, `! ()` `@ffi` decl

- **Systems (AL):** "I withdraw TR. devops's fact is right: every @ffi decl carries @trusted, so TR never fires. The zero-arg non-Void `! ()` shape is a strong smell, and real constants (getpagesize) are rare enough for an explicit @allow."
- **Web/Scripting (NO):** "AL makes real constants carry a second annotation and teaches people to add `@allow` without reading. AG7's help line plus the hover covers the author at the point where they write the row."
- **PLT (AL):** "The zero-arg, non-Void `! ()` shape is the syntactic sign of a hidden-state reader (the temporal protocol in AG2's case), and an explicit `@allow` on a real constant is a claim a reviewer can grep. No V shape: after Q4/Q5, Void `! ()` with no `mut` is legitimate for Ptr and handle writes." Concern: "authors may read a clean lint run as proof of purity."
- **DevOps/Tooling (AL):** "The lint has to be able to fire. §7 requires `@trusted` on every @ffi binding, so TR is a lint that the required annotation always suppresses, which is dead code in the compiler."
- **AI/ML (AL):** "The zero-arg "call, then read the side channel" shape is the most common C pattern that models will copy into bindings. A warning at the decl catches it for the cost of one line."
- **Minimalism (NO):** "AL adds a code that misfires on real constants (`getpagesize`, `sysconf` values) and misses hidden state behind arguments (the cursor of `strtok(NULL, …)`), all to check a claim that §4.5 says the compiler cannot verify. The AG7 help line delivers the teaching value at zero surface cost."

##### AG block — agreed points

All six seats voted yes. The block holds the `! ()` test (AG1), the producer-returns-the-data fix (AG2), `State` as the fallback row (AG3), `! State` for the GC switches (AG4), `! State` for raw `strerror` (AG5), `free(p)` as `! ()` (AG6), and the extra E0802 help line (AG7).

- **Systems:** "AG5 yes on the row."
- **DevOps/Tooling (Phase B):** "free(p) = `! ()`."

#### Phase D — Round 2

The Phase C splits on Q2a (4-2) and Q6 (4-2) went to a silent second vote. PLT had raised that Q2a is a private exception to the rule Q2b sets. Three seats (DevOps/Tooling, AI/ML and Minimalism) argued for Q6 that the AG7 help fires only on a missing row.

All six seats then voted FS on Q2a and AL on Q6. Four seats named a preferred order: land AG2 in the same slice, so no interim row ships. That order goes to the implementation notes.

##### Q2a — result FS 6-0

- **Systems (FS):** "plt's consistency point with Q2b is fair, but it weighs a private binding against a public signature. ST would put `State` into the public row of `fs_do_stat`, where users copy it and every caller's hover shows it; FS changes nothing outside fs_ops.bl. Both rows block reordering and deletion equally, so the only difference is the leak. First choice remains landing AG2 in the same slice, so no interim row ships."
- **Web/Scripting (FS, changed):** "Under E0552, ST puts `State` in the public row of `fs_do_stat`. Users read and copy that row in hovers and docs far more than a private binding, so ST makes the bad example worse, not better."
- **PLT (FS):** "Under E0552, ST puts `State` into the public row of `fs.stat`. That is an artifact of the implementation surfacing in a public signature, and it is a worse breach of "the row names what the call does" (the Q2b principle) than a wide row on a private binding with one caller. FS keeps the Q2b rule's damage private and temporary."
- **DevOps/Tooling (FS):** "ST puts a false `State` into the PUBLIC row of `pub fn fs_do_stat`, where every hover, every caller's row and every E0552 note shows it. A wrong row in a public signature is the worse diagnostic outcome, and users copy public signatures far more than private bindings."
- **AI/ML (FS, changed):** "under E0552, ST makes fs.stat show `! FS.Read, State` in a public signature. Every user, every hover and every model trained on std would see that row, and it tells them "stat touches State", which is false."
- **Minimalism (FS):** "under ST, `State` lands in the public row of `pub fn fs_do_stat`, and a wrong public signature is the example users and models copy most. FS stays inside fs_ops.bl, it is a sound upper bound, and it ends when AG2 lands."

##### Q6 — result AL 6-0

- **Systems (AL):** "The AG7 help line fires only when a row is missing (E0802), so it never reaches the author who writes `! ()` on purpose, and that author is the bug. The lint shape has zero false positives in lib/std today, true constants opt out with one greppable `@allow`, and `[lints]` lets a project turn it off or make it an error."
- **Web/Scripting (AL, changed):** "the AG7 help fires only when the row is missing, so it never reaches the author who writes `! ()` on purpose, and that author is the one with the bug. With no lint, nothing at that site warns."
- **PLT (AL):** "The AG7 help reaches only an author who leaves the row out (E0802). The author who writes `! ()` with confidence is the one this lint catches, and nothing else does."
- **DevOps/Tooling (AL):** "The false positives are only true constants (none in lib/std today), each with one greppable `@allow`, and `[lints]` lets a project set it to off or error."
- **AI/ML (AL):** "The bug this lint targets is an author who writes `! ()` and is wrong, and AG7 never reaches that author, because E0802 fires only on a missing row."
- **Minimalism (AL, changed):** "devops and aiml showed that my main argument was wrong. AG7 sits on E0802, which fires only on a MISSING row, so it never reaches the author who writes `! ()` on purpose, and that author is the bug case. [...] The help names the fix first ("add `State`, or have the producer return the value") and the `@allow` second, and the lint docs say a clean run is not proof of purity."

### Final Spec

```blink
@ffi("blink_read")
fn c_read(fd: I32, p: Ptr[U8], n: U64) -> I64 ! FS.Read {}   // <0 means -errno

@ffi("blink_arena_bytes_used") fn arena_bytes_used_ffi() -> Int ! Arena {}
@ffi("GC_gcollect") fn gc_collect() ! State {}

@ffi("blink_tcp_handle_take") fn tcp_handle_take(h: TcpHandle) -> Int ! () {}
@ffi("blink_bytes_push") fn bytes_push(mut b: Bytes, byte: Int) ! () {}

@ffi("blink_fs_stat_size") fn c_fs_stat_size() -> Int ! () {}   // warning[ZeroArgPureForeign]
```

- `! ()` on an `@ffi` decl claims that the result depends only on the arguments and on data they reach, and that no later call can see a change except through those arguments (§9.1).
- A `! ()` call may not move across another call that can write what its arguments reach. A call with a non-empty row, a `mut` argument, or a `Ptr` or `@ffi.opaque` argument counts as writing everything that argument reaches.
- Shims return `-errno`, and no binding reads `errno`. The C locale is constant, because Blink never calls `setlocale`. Allocators and `free(p)` are `! ()`.
- Fix order for hidden state: the producer returns the data; then the effect that names the resource (`Arena`, `FS.*`, `Net.*`); then `State` (§4.16.1).
- A `pub` wrapper of a `! State` binding declares `State` (E0552).
- GC switches and raw `strerror` take `! State`.
- A std binding may carry the producer's row as an interim upper bound. A user binding does not; this is guidance, because the compiler cannot check a foreign body.
- Handle ops reached through the argument are `! ()`. An op that closes the OS file descriptor keeps its Net row. Copies of a handle alias one object.
- `mut` goes on an `@ffi` param of a Blink value type, not on a `Ptr` or `@ffi.opaque` param. A missing `mut` is an audit defect, not a compile error.
- `ZeroArgPureForeign` (W0817) warns on an `@ffi` decl with no params, a non-Void return type and `! ()`. `@allow(ZeroArgPureForeign)` suppresses it; `@trusted` does not. A clean run does not prove purity.
- E0802 help adds: "`! ()` also claims no hidden state between calls".
