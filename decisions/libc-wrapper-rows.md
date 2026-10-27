[< All Decisions](../DECISIONS.md)

# Effect Rows of the std.libc Wrappers and Routing Through Ops — Design Rationale

**Question.** Is `getentropy` `Rand`? Must the std `@ffi` wrappers go through effect ops to stay mockable?

**Answer.** `c_getentropy` takes `! Rand`. The `std.libc` wrappers stay 1:1 calls into C, and no handler intercepts them. `getentropy_bytes` leaves the v1 set; callers use `rand.bytes(n)`. The fd-generic bindings and wrappers take the union of the rows of std's fd makers, in leaves. `poll` also takes `Time.Sleep`. `c_fs_stat` and the stat readers take `! FS.Read`. User code cannot call the default body of a built-in op; a handler reaches it as `default.stat(p)`. Outside `std.libc` and op default bodies, a std function does not call a source-effect, FS or Net binding directly, unless the binding acts only on an fd that already exists. The E0539 hint in a test changes when an effect comes only from foreign code. No new code and no new warning.

### Panel Deliberation

Six seats voted: Systems, Web/Scripting, PLT, DevOps/Tooling, AI/ML and Minimalism. The quotes below come from the seats' own replies. Where a quote has a "[...]", the text there was a ticket reference or a source line number. Phase D ran for Q4 and Q5 only.

#### Phase A — Independent proposals

- **Systems**: "A foreign effect has to go through a Blink effect op when the effect is a **source**"
- **Web/Scripting**: "A handler sees a call if and only if the call is an effect op."
- **PLT**: "Row soundness (static)"
- **DevOps/Tooling**: "A row that invites a `with` it cannot honour is a lie from the toolchain."
- **AI/ML**: "Handlers see every std call except std.libc."
- **Minimalism**: "no new rule. Two existing rulings answer every row"

All six proposals agreed on five points (S1 to S5 in the Phase B digest): `c_getentropy` is `Rand`; the `std.libc` wrappers stay 1:1 and unrouted; `c_fs_stat` and the zero-arg stat readers are `FS.Read`; the `Effect = ! IO` clause changes; the `fs_do_*` default bodies must not be callable from user code.

#### Phase B — Debate highlights

Phase B ran one round. All six seats replied "stable". No seat objected to S1 to S5. Web and devops moved to remove `getentropy_bytes`, so all six seats then agreed on removal. Devops withdrew its `! State` proposal for the fd-generic rows, so all six then agreed on the fd-table union.

- **Systems**: "Inside a handler, the only extra thing getentropy_bytes "does" is escape the mock. That is the bug, not a feature."
- **Web/Scripting**: "A pub fn that holds `! Rand` while `mock_rand` cannot see it is the exact trap the ticket names."
- **PLT**: "A row that drops FS.Write on a call that writes a file breaks the §4.5 upper-bound invariant."
- **DevOps/Tooling**: "`! State` is a capability every root holds and that E0552's machine fix adds without thought."
- **AI/ML**: "A pub name that does not exist cannot be wrapped."
- **Minimalism**: "a row is a capability bound first and a handler signal second."

#### Phase C — Final vote

Q1, Q2, Q3 and Q6 passed 6-0. Q4 and Q5 did not settle and went to Phase D. The AG block passed 6-0. A seat marked "round 1" held another position at the end of Phase B and changed.

##### Q1. poll write side — RW (6-0)

RW: the read union and the write union. R: the read union only.

- **Systems** — RW. "The fd-table rule gives an op on an fd the row of the call that made the fd, whatever the op is. POLLOUT on an O_WRONLY file fd or on fd 1 acts on an fd that FS.Write or IO.Print made. Readiness is an observation, but it observes that fd's resource, so the write makers belong in the row. The cost is two leaves on a raw call, and rows cost nothing at run time."
- **Web/Scripting** — RW. "POLLOUT on a write-only file fd or a pipe write end acts on an fd that FS.Write or IO.Print made. The fd-table rule gives an op on an fd its maker's row, whatever the op does. A scripting dev reads the row as "what this fn can touch", and poll can touch the write side."
- **PLT** — RW. "The fd-table ruling says an op on an fd takes its maker's row, whatever the op is. Poll with POLLOUT observes the write side of fd 1, a file or a socket. The read union alone would break the upper-bound invariant of §4.5 for those fds."
- **DevOps/Tooling** — RW. "The fd-table rule is literal: an op on an fd takes its maker's row, and POLLOUT readiness on fd 1 or on a file fd is an op on that fd. A read-only union would make `poll` the one wrapper where E0500 stays quiet on a write-only fd. That is an inconsistency an author meets as a surprise, not as an error."
- **AI/ML** — RW (round 1: R). "I move to plt's point. The fd-table rule says an op on an fd takes the row of the call that made it, whatever the op is. A model learns that rule once, with no "unless the op only observes" exception. My read-side carve-out gave the same fd two rows depending on the syscall, and that is a decision point a model gets wrong. A long row costs few tokens, because the E0500 fix line spells it out and models copy it."
- **Minimalism** — RW. "the fd-table rule says an op on an fd takes the row of the call that made the fd, whatever the op is. A POLLOUT check on a write-only file fd or on fd 1 acts on an fd made by FS.Write or IO.Print. "Readiness is an observation" (aiml) would add a carve-out to that rule, and I do not want a second rule for one syscall."

##### Q2. poll and `Time.Sleep` — T (6-0)

T: add `Time.Sleep`. 0: no Time leaf.

- **Systems** — T. "poll's return value depends on the clock. It returns 0 when the timeout runs out, and `poll([], t)` is the C sleep idiom, so without the leaf, "no Time in the row means this fn does not wait on the clock" is false. web and devops say the leaf "invites a mock_clock" that cannot shorten the wait. S2 already says no handler intercepts libc, so the leaf does not promise interception; it only keeps the upper bound true. An under-stated row is the bug class this panel exists to remove."
- **Web/Scripting** — T (round 1: 0). "In B1 I answered devops's D2-S by saying S2 already tells users that handlers do not intercept libc. By that same logic, a `Time.Sleep` leaf on poll invites `mock_clock` no more than `FS.Read` on read_bytes invites `readonly_fs`. My "false invitation" objection fails, and I concede to plt, sys and min. `poll(NULL, 0, ms)` is a sleep, and its result (0 on timeout) depends on the clock. If the row has no Time, "no Time in the row means it does not wait on the clock" is false."
- **PLT** — T. "The case is not "poll blocks" (read blocks too, and gets no Time row). The case is that poll's result is a function of elapsed time: it returns 0 when the timeout runs out. Without a Time leaf, a fn whose row is only FS.Read can tell how much time has passed, so its row is not an upper bound. web and devops say Time.Sleep "invites a `with mock_clock`" the kernel will not honour. That is true, but the FS and Net leaves on the same row invite `readonly_fs` in exactly the same way, and S2 plus the §9.1.3.3 sentence already answer that for the whole libc tier."
- **DevOps/Tooling** — T (round 1: 0). "plt and sys moved me. `poll` returns 0 when the timeout runs out, so its result depends on elapsed time, and `poll([], t)` is the C sleep idiom. Without the leaf, "no Time in the row means no clock dependence" is false. I argued in Phase A that a row is an honest upper bound. Web's false-invite point holds just as well for the FS.Write and Net leaves we already accepted. Only a typed handle fixes it, not a missing leaf."
- **AI/ML** — T (round 1: 0). "I move. Blink's poll accepts an empty list, so `libc.poll([], 500)` is a sleep. Without Time.Sleep, "no Time in the row means it never waits on the clock" is false. Then a model reading rows reasons wrongly about timing, and rows are the part of a signature a model trusts most. web's false-invite worry (a mock clock that cannot shorten the wait) is already answered by S2 plus the §9.1.3.3 sentence: nothing in std.libc is intercepted, by module."
- **Minimalism** — T. "`poll([], t)` is `sleep(t)`. Without Time.Sleep, a fn can wait on the clock with no Time in its row, and that is an under-stated row, the bug class this panel exists to fix. The "false invite to mock_clock" argument (web, devops) proves too much: it would also take Rand off `c_getentropy`, which all six keep. A row is an upper bound (§4.5), not a promise that a handler can intercept the call. I hold this weakly: it is the one leaf that goes beyond the makers' union."

##### Q3. A std-only gate on routing through ops — G (6-0)

G: a check in the repo's own gate, invisible to users. 0: no check, one sentence in §9.1.3.3.

- **Systems** — G. "the original concern was "until someone audits them", and three panels in a row found std bypasses by hand. A per-body check with known callee rows is cheap and local, and users never see it. `task ci` catches a bypass in the commit that adds it."
- **Web/Scripting** — G. "three panels in a row found a bypass by hand, so a hand audit goes stale. The check binds only std authors, so users meet no new concept. It belongs in `task ci` so it fails on the commit that adds the bypass."
- **PLT** — G. "The 6-0 ruling "mockable goes through an op" is a property of std as a whole. A hand audit goes stale, and a gate in `task ci` does not. The check is invisible to users, so it adds no language surface."
- **DevOps/Tooling** — G. "The original concern was "silently escape until someone audits them". A gate is an audit that cannot go stale, and nothing changes for users. A one-sentence rule alone stops holding the first time a std author forgets it, and no tool tells them."
- **AI/ML** — G. "the gate costs users zero decision points, and it makes the §9.1.3.3 sentence stay true for every later std change. fs_do_* shows that hand audits miss this class. Run it in `task ci` so the commit that adds a bypass fails."
- **Minimalism** — G (round 1: 0). "my objection was to new language surface, and this check has none, because users never see it. aiml's evidence moved me. Three panels in a row found a std bypass (fs_do_*) by hand, so "the sentence stays true" depends on someone auditing again. A check in ci is that audit, done by machine at no cost to users."

##### Q4. Scope of the Q3 check — SM 4, E 1, S 1; sent to Phase D

E: every built-in effect that has ops, with a named allowlist. C: where an op covers the same action. S: source effects only. SM: source effects plus bindings that make an fd.

- **Systems** — SM (round 1: C). "I move from C to SM. web, devops and min are right that "covers" needs a human ruling per pair, and a gate that needs judgment goes stale. SM is mechanical from the binding's row plus a list of makers. It also matches "mock the source, not the handle": sandbox authority lives where the resource is made, so `readonly_fs` stays complete only if every maker in std goes through an FS or Net op. Plain S misses that, because FS is a handle effect."
- **Web/Scripting** — SM (round 1: E). "min and plt are right that E flags `read_fully` on day one and would ban a typed `File.write_bytes ! FS.Write` over a split binding. A gate that starts with exceptions is a bad start. SM is mechanical from the binding's row plus a maker list. It also matches the fd-table model we already passed: the maker is where a test or sandbox intercepts. That matters for §4.7: `with readonly_fs` must see every open, and S alone does not check opens."
- **PLT** — SM (round 1: S). "I move from S to SM. devops' maker clause is my own Phase A provenance argument made mechanical. A sandbox around ops on existing fds holds only if the maker is interceptable: `readonly_fs` decides which file fds exist only when open goes through an FS op. S alone leaves a std fn free to call `open` directly under `! FS.Write` and escape `readonly_fs` with no gate failure. C needs a human judgement for each op pair, so the gate would go stale."
- **DevOps/Tooling** — SM. "Under "mock the source, not the handle", the maker is where a test intercepts. So a std fn that opens an fd by a direct binding, and not through `fs.*`/`net.*` ops, defeats `readonly_fs` just as `fs_do_*` does. S leaves that hole open. C needs a human judgment per pair, and a gate that needs judgment goes stale. SM follows mechanically from the binding's row plus a short maker list."
- **AI/ML** — E. "this is my Phase A scope, and it is the only option that catches fs_do_* by itself, because FS has ops and is not a source. S and SM both miss a pub stat/read helper over an FS binding. C needs a human to judge "covers", and judged lints go stale. E is mechanical. Its exceptions (std.libc, read_fully, a future typed File.write_bytes) live in a named allowlist, so each new hole is a reviewed diff, not silence. A gate that starts with a 2-entry allowlist is fine; the visible list is the audit."
- **Minimalism** — S. "S is the narrowest scope that catches the bug class: Time, Rand, Env and io ops, where a mock is what tests rely on. C needs a human ruling for each pair on what "covers" means. E needs an allowlist on day one. SM adds a list of fd makers. Sys left S because it misses fs_do_*, but AG item D closes fs_do_* directly, so the check does not need to."

##### Q5. The E0539 hint for an effect that comes only from foreign code — H 4, 0 2; sent to Phase D

H: change the hint. 0: no change.

- **Systems** — 0. "after R and D, no std path reaches a test through foreign code, so today's hint is right for every std case. "Comes only from foreign code" needs per-effect provenance carried across calls, and closures make that partial. A hint that is right only sometimes is worse than a plain one. Log it as a follow-up ticket for user @ffi with a Rand or Time row."
- **Web/Scripting** — H. "a hint is the line developers (and models) copy word for word. Today it tells them to write a `with` that cannot work, and that produces the flaky test. It can be conservative: change the text only when the unhandled effect provably comes only from @ffi callees, and keep the current hint otherwise. That needs no complete escape analysis."
- **PLT** — H. "Today the hint is false for a user `@ffi` with a Rand or Time row: it tells the author to install a mock that cannot work. The escape data is partial through closures. But a partial answer here can only fall back to today's text, never to a wrong one, so H is a strict gain."
- **DevOps/Tooling** — H (round 1: 0). "aiml's point decides it from my own seat: models and people follow a hint word for word, so today's hint writes the flaky test. Unlike a warning, a hint does not need complete data. When the compiler can trace the effect to a foreign callee, it gives the corrected hint. Otherwise it keeps the generic hint. A partial hint misleads no one, while a partial warning does. I withdrew it in B1 by bundling it with D4-W, and that was wrong."
- **AI/ML** — H. "models apply diagnostic hints word for word. A hint that says "wrap in `with mock_rand(...)`" for an effect that comes only from foreign code makes the model write the flaky test itself. After D1-R the case is user @ffi only, but a false hint is a diagnostic bug at any frequency. A first cut that is local is enough: if no op of E is reachable in the test body's direct callees and only an @ffi row supplies E, say so. It does not need the full with-site escape set."
- **Minimalism** — 0. "the check "comes only from foreign code" needs the escape-set analysis that devops withdrew. With D1-R and the Q3 gate, no std path triggers the bad hint. What is left is user @ffi with a source row, which is rare and audited. Log it as a follow-up ticket (sys)."

##### Q6. A new warning for a handler bypass — 0 (6-0)

0: no new warning, one doc line. F: a warning at the fn definition.

- **Systems** — 0. "I withdrew F. With R, D and the G gate, std has no bypass left. On user code, F warns deliberate wrappers until they add `@trusted`, which is noise on correct code (min). The ffi-topic doc line states the §4.5 contract where users meet it."
- **Web/Scripting** — 0. "after R, D and the gate, std has no bypass left. A new W-code would fire only on user @ffi, where the author wrote the row and the §4.5 contract is stated. sys's D4-F would warn on a correct, deliberate libsodium wrapper until it gets `@trusted`, which is noise. The doc line is enough for v1."
- **PLT** — 0. "After R, D and the Q3 gate, std has no bypass left. A user-code warning would fire on code that is raw on purpose and that §4.5 already describes. YAGNI. Revisit on friction."
- **DevOps/Tooling** — 0. "After R and G, no std path triggers it, and on user @ffi the author wrote the row themselves under §4.5. min is right that a definition-site warning on a correct libsodium wrapper is noise until `@trusted` silences it. A new W-code for a case that is rare today does not pay for itself."
- **AI/ML** — 0. "with R, U, D and the Q3 gate, std has no bypass left. A definition-site warning would fire mainly on user @ffi wrappers that are raw on purpose, which teaches models to add @trusted reflexively. That is a worse habit than the bug. The ffi-topic doc line states the contract where a model reading `blink llms --topic ffi` meets it."
- **Minimalism** — 0. "after D1-R, D and the gate, std has no bypass left for a warning to catch. The with-site form is partial through closures, so a clean result reads as proof it is not (plt). The definition-site form fires on code that is raw on purpose. The doc line is enough for v1."

##### AG block. S1, S2, S3, R, U and D (6-0)

- S1: `fn c_getentropy(buf: Ptr[U8], buflen: U64) -> I32 ! Rand {}`.
- S2: the `std.libc` wrappers stay 1:1 calls into C; no handler intercepts them (§4.5).
- S3: `c_fs_stat` and the zero-arg stat readers take `! FS.Read`.
- R: remove `getentropy_bytes` from the v1 set; callers use `rand.bytes(n)`.
- U: the fd-generic bindings and wrappers take the union of the rows of std's fd makers, in leaves.
- D: user code cannot call the default body of a built-in op; a handler reaches it as `default.stat(p)`. No "pub + doc line" fallback.

- **Systems**: "AG: yes"
- **Web/Scripting**: "AG: yes"
- **PLT**: "AG: yes"
- **DevOps/Tooling**: "AG: yes"
- **AI/ML**: "AG: yes"
- **Minimalism**: "AG: yes"

#### Phase D — Round 2

Phase D took Q4 and Q5 only. The digest gave every seat's Phase C text. All six seats had named SM for Q4 and H for Q5 in their D1 replies; the open points were how the gate fails on a binding nobody classified (Q4) and how far the hint traces (Q5).

##### Q4. Which way does the gate fail on an unclassified binding? — FC (6-0)

W: the gate checks source-effect bindings plus every FS/Net binding that names a resource by path or address. FC: the gate checks every binding with a source, FS or Net row; only ops on an existing fd are exempt.

D1 positions:

- **Systems**: "This is SM's behavior with E's fail-closed default and none of E's allowlist."
- **Web/Scripting**: "with sys's widening, SM does catch the stat helper, because stat names a path."
- **PLT**: "In this fail-closed form, no. A pub helper over `c_fs_stat` or any path binding is flagged, because stat is not an fd op."
- **DevOps/Tooling**: "It becomes a property of the binding's signature (a path or address parameter, plus an FS/Net row), so web's and my "list goes stale" concern mostly goes away."
- **AI/ML**: "With the list on the fd-op side, a missing entry fails closed."
- **Minimalism**: "the gate can derive the list from the binding's row and parameter types."

D2 revote:

- **Systems** — FC (Phase C: SM). "W classifies a binding by its parameters, a path or an address. That lets anything with an FS or Net row and an odd parameter shape through without a check. Examples: an fd-returning call with no path, such as memfd_create under an FS row, an `ioctl`, or a future `fanotify_init`. Failing closed turns a missed classification into a red gate and a one-line reviewed diff, not silence. Both options give the same result on every current std site, so FC costs nothing today."
- **Web/Scripting** — FC (Phase C: SM). "my own C-phase concern was that a new maker left off the list escapes the gate silently. FC removes that failure. Under FC, a new FS/Net binding nobody classified turns the gate red, and the fix is a one-line reviewed diff. For contributors, a red gate that names the binding and the fix is easier to act on than a list they never knew to update. Both options flag and pass the same known cases, so the only difference is what happens with the unknown one, and failing loudly is the better default."
- **PLT** — FC (Phase C: SM). "The question is which way a gate fails on a case nobody classified. W finds its set from a property of the signature (a path or address parameter). A future FS/Net binding that reaches a resource some other way (an fd it got from a hidden handle table, a struct that carries a path) has neither, so W passes it in silence. FC flags it by default, and the fix is a reviewed one-line add to the fd-op list. For a soundness check the gate should fail closed: a false red costs one diff, and a false green costs a sandbox escape."
- **DevOps/Tooling** — FC (Phase C: SM). "For a gate, fail-closed is the only safe default. An unclassified binding should turn the gate red, never pass in silence. My own W reading has a hole that proves it: `accept(listen_fd)` makes an fd but takes no path or address, only an existing fd. A signature rule would class it as "an op on an existing fd" and exempt a maker. Under FC, that binding fails until someone puts it on the reviewed fd-op list, so every exemption is a reviewed one-line diff."
- **AI/ML** — FC (Phase C: E). "the two options agree on every binding in today's tree. They differ only on a binding nobody thought about, and that is the case the gate exists for. Under W, a new FS/Net binding whose signature does not fit the path-or-address pattern passes silently: an fd passed as an Int, a struct holding the path, an ioctl. Under FC it turns the gate red, and the fix is a reviewed one-line exemption. A gate that fails closed is one rule a model can learn: "every std binding with a source, FS or Net row is checked unless it is a listed fd op". W's signature heuristic is a second rule with edge cases."
- **Minimalism** — FC (Phase C: S). "FC is the shorter rule. Every binding with a source, FS or Net row is checked, and the one exemption is ops on an existing fd. W needs a second test, "names a resource by path or address", and any binding that test misreads passes the gate with no signal, which is the silent hole the gate exists to close. Under FC the only list is the fd ops (read, write, recv, send, poll and their kin). That set is small and stable, and adding to it is a reviewed one-line diff (aiml)."

##### Q5. How far does the E0539 hint trace? — NC (6-0)

DC: direct callees only. NC: through named calls. 0: no hint change. Under DC and NC alike, a closure, a `! _` row or any op of E keeps today's hint.

D1 positions:

- **Systems**: "That holds for a warning, whose silence reads as "no bypass". It does not hold for a hint, where the fallback is simply today's text."
- **Web/Scripting**: "this hint is never wrong."
- **PLT**: "under that trigger, the new hint is never wrong."
- **DevOps/Tooling**: "And here "partial" can only mean "falls back to today's text", never "says something false"."
- **AI/ML**: "the plain hint is the one that is wrong."
- **Minimalism**: "I said H needs the full escape-set analysis, and it does not."

D2 revote:

- **Systems** — NC (Phase C: 0). "the case left after D1-R is exactly a user wrapper (`my_token() ! Rand` over libsodium) called from a test. DC keeps today's misleading hint for that case, so DC fixes almost nothing. The walk runs only when E0539 fires and uses rows already computed, so following named calls costs nothing at compile time. The safety comes from the fallback rule (any closure, `! _` row or op of E keeps today's hint), not from a shallow depth."
- **Web/Scripting** — NC. "the case that writes the flaky test is the common one: a test calls a small user wrapper (`make_token() ! Rand`) over @ffi. DC keeps today's wrong hint in exactly that case, so it fixes almost nothing a user meets. NC traces through named calls and still falls back to today's text on any closure, `! _` row or op of E, so it never claims more than it checked. The depth stays the implementer's knob."
- **PLT** — NC (D1: DC). "I move from DC. With the stop conditions both options share (a closure, a `! _` row, or any op of E keeps today's hint), each named callee the walk visits has a known body and known callee rows. So the walk ends either at an @ffi decl, or at an opaque or mockable point that brings back today's text. The new hint stays never-wrong at any depth. NC only adds coverage, and it covers exactly the user-wrapper case (`make_token` over libsodium) that DC left for a follow-up."
- **DevOps/Tooling** — NC. "The case that matters is the one DC drops: a user's `make_token() ! Rand` over a libsodium `@ffi`, called from a test. That is the exact flaky-test path aiml described, so a hint that skips it fixes almost nothing. NC keeps the safety property all six agree on: any closure, `! _` row or op of E seen falls back to today's text, so the new text is never false. It names the chain it walked, so the author can check the claim."
- **AI/ML** — NC. "the case that matters most in practice is a test calling a user wrapper (`make_token() ! Rand` over `@ffi randombytes`). DC keeps the wrong hint there, so a model still writes the `with mock_rand(...)` that cannot work. NC follows named calls, whose rows and bodies typecheck already knows, and falls back to today's text at any closure, `! _` row or op of E. So it can never print the new text for a path it has not traced. The printed chain (`via make_token`) lets the reader check the claim."
- **Minimalism** — NC (Phase C: 0). "the case that matters is a test calling a user wrapper (`make_token() ! Rand` over libsodium). DC keeps the false hint in exactly that case, so it fixes almost nothing in practice. NC keeps the guard: the new text prints only when every supplier ends at @ffi and no op of E is seen. Anything unsure (a closure, a `! _` row) falls back to today's hint, so a deeper walk can only add correct cases."

### Final Spec

```blink
@ffi("getentropy", header: "sys/random.h")
fn c_getentropy(buf: Ptr[U8], buflen: U64) -> I32 ! Rand {}

pub fn read_bytes(fd: Int, max: Int) -> Result[Bytes, Errno] ! IO.Read, FS.Read, Net.Connect, Net.Listen, State
pub fn write_bytes(fd: Int, data: Bytes) -> Result[Int, Errno] ! IO.Print, IO.Log, FS.Write, Net.Connect, Net.Listen, State

let entropy = rand.bytes(32)    // 32 CSPRNG bytes; mock_rand makes it fixed in a test
```

- `c_getentropy` takes `! Rand`. `getentropy_bytes` leaves the v1 set, which now holds four wrappers. Callers use `rand.bytes(n)`.
- The `std.libc` wrappers stay 1:1 calls into C. No handler intercepts them.
- A wrapper over an fd-generic call takes the union of the rows of the calls that can make its fd, in leaves. `recv_bytes` and `send_bytes` take `Net.Connect, Net.Listen, State`. `std.io.read_fully` takes the row of `read_bytes`. A std author may split a binding by maker; this is allowed and not required.
- `poll` takes the read union, the write union and `Time.Sleep`. The wait is real: a mock clock does not shorten it.
- `c_fs_stat` and the zero-arg stat readers take `! FS.Read`.
- User code cannot call the default body of a built-in op. A handler reaches it as `default.stat(p)`.
- Outside `std.libc` and op default bodies, a std function reaches a source-effect, FS or Net binding only through an op of that effect. The one exemption is a binding that acts only on an fd that already exists.
- In a test, E0539 for an effect that comes only from foreign code says so, names the chain it checked and points to the real handler or to `rand.bytes(n)`. A closure, a `! _` row or any op of the effect keeps the old hint.
- No new warning. One sentence in the ffi text: a handler does not intercept your `@ffi` calls; to make one mockable, declare your own effect and call the binding from its default handler.
- Spec: §9.1.3.3, §9.1.3.2, §4.5, §4.6, §4.7, §2.20.

### Implementation notes

- Order for R: land the CSPRNG default body of `Rand` first (it is still seeded with `srand(42)`). Then move the compiler's own temp-dir name to `rand.bytes(6)`. Then remove the wrapper, with the usual bootstrap steps.
- The routing gate runs in `task ci`. It fails closed: a new FS or Net binding that nobody classified turns the gate red. The exempt list holds only bindings that act on an existing fd, and it gets the same review as an allowlist. The gate message must say what an entry claims ("this binding acts only on an fd that already exists") and name the binding. The gate walks whole bodies, closures included, not only named calls. `fs_do_*` becomes non-pub or otherwise unnameable from user code; until then the gate lists those sites by name.
- The E0539 walk follows named calls and falls back to today's hint at any closure, `! _` row or op of the effect. It must reach at least test, wrapper, wrapper, `@ffi`, and a test with two levels must cover it. The hint names the chain it walked.
- Follow-ups: typed fd handles (`Fd[E]` and kin) as the long-term fix; `-errno` shims for `c_read` and `c_write`, which read errno after the call; E0500 does not yet check the declared row of an `@ffi` callee, so the rows of split private bindings bind only at the callers of the pub wrapper.
