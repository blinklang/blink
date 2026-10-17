[< All Decisions](../DECISIONS.md)

# Assignment-Place Diagnostics — Design Rationale

**Question:** §2.22 *Assignment places* says what a place is, but not which error a non-place gets. Measured with gen1 before this vote: `let a = 5` then `a = 6` gave a raw C error; `xs = [7, 8, 9]` on a plain `let` compiled and ran; `t.0 = 5` on a plain `let`, a write to a module-level `let`, and `mk().x = 5` all passed `blink check`; `x += 1` on a plain `let` gave only an unused-value warning; `p.iov_len = 4` through a `Ptr` gave an internal compiler error at build. `ParamAssign` (§3.6) was decided but had no code and no implementation. The question was how many diagnostics there are, which case gets which, the order when more than one applies, and when each fix is machine-applicable.

**Decision:**

- An immutable root on the left of `=`/`op=` is `MutationRequiresMut` (E0610). Its rule widens to "a mutation needs a mutable root". A `mut` parameter is a mutable root only for a call: an assignment to a parameter is `ParamAssign`.
- A new `NotAPlace` (E0611) covers a step through a `Ptr` (at the root or mid-path) and a temporary root such as `mk().x = 5`.
- `ParamAssign` gets E0612 now. Its code does not change when it moves from warning to error.
- Order, first that applies wins: a `Ptr` step, a temporary root, a parameter root, an immutable binding.
- `p.f = rhs` through a `Ptr`: the direct fix `p.f.write(rhs)` is machine-applicable when `rhs` is a literal, a name or a field path of names (no operators). Any other `rhs` in a block statement gets a machine-applicable fix that binds `rhs` to a new name first. Otherwise help only. `op=` through a `Ptr` is help only, with a note that it is not atomic.
- "Insert `mut`" is machine-applicable for a local plain-name `let` only. A module-level `let` gets help only, because `mut` adds `State` to rows far from the edit (§4.16). An imported `pub let` gets help naming E1013. A destructuring `let`, a `for` variable and a `match` binding get help only. *(Amended by [`mut` in Patterns](mut-in-patterns.md): a local pattern binder now gets a machine-applicable fix.)*
- Every new case is an error at once. `ParamAssign` keeps its warn-first rollout.
- A closure's assignment to a captured immutable binding is E0610, with a label at the capture and the fix at the `let`. `blink fix` applies an identical edit once (§8.6).

This decision amends the E0601 field-path ruling's Q3b ("the spec does not mark `p.f.write(v)` machine-applicable"): the direct form is now machine-applicable for an inert `rhs`, and the two-line form keeps §2.22 order for every other `rhs`.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Phase B ran one round. Phase D ran on Q4 only.

#### Phase A — Independent proposals

The opening line of each seat's proposal, verbatim. The full text of each proposal follows.

- **Systems:** Systems (Sys) Phase A proposal, full text: one NotAPlace code (E0611) with a `kind` field.
- **Web/Scripting:** Web Phase A proposal ([the spec ticket]): two codes with names a user will search for, not one "NotAPlace".
- **PLT:** PLT Phase A proposal ([the spec ticket]): I recommend two codes, chosen by which premise of the place rule fails first. The shape check runs before the binding-mode check.
- **DevOps:** DevOps Phase A proposal for [the spec ticket]: several names in one E061x family, one diagnostic per mistake, fixes gated by a syntactic test.
- **AI/ML:** AI/ML Phase A proposal (full resend) for the "not an assignment place" diagnostic ([the spec ticket]).
- **Minimalism:** **Minimalism (Min) — Phase A**

<details><summary>Systems — full Phase A proposal</summary>

> Systems (Sys) Phase A proposal, full text: one NotAPlace code (E0611) with a `kind` field.
>
> POSITION
> Use one code with a `kind` field in the diagnostic data, not two codes. The catalog already does this for MissingReturn (E0311): "The tail kind is carried as diagnostic data, not a separate code." All the cases here have one root cause: the left side does not name storage that this statement may write. The fix shape is different for each kind, and the `help` and `fix` fields already carry that difference. Tools that match on the code get one stable key.
>
> P1. error[NotAPlace] E0611 (E06xx: scoping, next to E0610)
>
> The `kind` field takes one of four values:
> - ImmutableRoot: the root is a local `let` (scalar, List, tuple or struct; `=` and `op=`). Help: "declare it `let mut x`". Machine fix: insert `mut ` at the declaration, only when the declaration is a plain local `let x` in the same file. For a destructuring pattern, a `for` variable or a match binding, give the help with no fix.
> - ImmutableModuleRoot: the root is a module-level `let`. Same help, no fix. A module-level `let mut` is module state and changes the effect row of each writer.
> - ThroughPtr: a step of the path is a `Ptr`. Help: "use `p.f.write(v)`". Machine fix under the conditions below.
> - NotABinding: the root is a call result or other temporary (`mk().x = 5`). Help: "bind it first: `let mut t = mk()`". No fix.
>
> A parameter root stays ParamAssign. Its help is different ("copy it to a new name") and it has its own rollout. Give ParamAssign the next code, E0612, in the same edit, so that the whole "write to a non-place" family has codes in one range.
>
> Example 1: error[NotAPlace]: cannot assign to `total`: it is not `let mut` ... declared here without `mut` ... not an assignment place ... help: declare it `let mut total`
> Example 2: error[NotAPlace]: cannot assign through a `Ptr`: `p.iov_len` is not a place ... path goes through `p: Ptr[IoVec]` ... note: a write through a pointer is a memory effect, not a binding store ... help: use `p.iov_len.write(n)`
>
> WHEN THE ThroughPtr FIX IS MACHINE-APPLICABLE (plain `=` only)
> (a) The rhs is a literal, a name, or a field path of names. It has no call, closure, `?` or block. The edit is `p.f.write(rhs)` with nothing moved. Nothing in the rhs can write the root, so the order is the same.
> (b) In all other cases, while the assignment is in statement position, the edit is `let tmp = rhs` followed by `p.f.write(tmp)`. `tmp` is a fresh name that does not clash with any name in scope. This keeps the §2.22 order (rhs, then root read, then store). The C output is the same as before: the C compiler already puts the rhs into a temporary, so the hoist costs nothing at run time.
> - `op=` through a Ptr has a plain help with no fix: `p.f.write(p.f.read() + v)`. Add a note that this is two separate memory operations and is not atomic, the same as C `p->f += v`.
>
> REQUIRED TESTS
> - An rhs closure that reassigns the root. With `let mut p` and `p.f = { p = q; 5 }()`, the store must land in `q.f`, and the hoisted fix must also land in `q.f`.
> - A Ptr step in the middle of the path: `s.p.f = v` gives the help `s.p.f.write(v)`.
> - `op=` through a Ptr: help only.
> - One test for each `kind` above.
>
> P2. ALTERNATIVE: TWO CODES
> Use AssignToImmutable (E0611) for the ImmutableRoot, ModuleRoot and NotABinding kinds, and AssignThroughPtr (E0612) for ThroughPtr, with ParamAssign at E0613. The case for it: the two errors have different causes. One is binding mutability, the other is the memory model. The fix also edits a different line: the declaration in one case, the use site in the other. I rank this second. The catalog precedent favours a `kind` field, and two codes would split one rule of §2.22 ("is this a place?") across two catalog rows.
>
> ROLLOUT
> - These cases fail today with a raw C error or an ICE: scalar `let`, struct field, and `Ptr[@ffi.struct]`. Make them a hard error at once. The build already fails, so no working code can break.
> - These cases compile today with no error: List reassign, tuple field, module global, `x += 1`. Ship one release as a warning with the `let mut` fix that `blink fix` applies, then make them an error. This is the same rule as ParamAssign. They are latent miscompiles (a silent store to storage the user marked immutable), so do not stay on a warning for more than one release.
>
> TRADEOFFS (SYSTEMS)
> - The checker can find the place at name resolution, from the root binding's mutability and the static type of each step. There is no run-time cost, and codegen can then assume an assignment's target is always writable C storage. That removes the ICE and the C `const` leak at the source.
> - The `kind` field costs one enum in the diagnostic JSON. Two codes would cost one more catalog row and one more name to keep stable.
> - The hoist fix is safe for all rhs shapes, so case (a) is only a smaller edit, not a correctness rule. It is valid to apply (b) in all cases. Keep (a) because people read the output.
>
> CROSS-LANGUAGE
> - Rust splits this into E0384 and E0594. Users often confuse the two.
> - Go uses one message, "cannot assign to X (neither addressable nor a map index expression)", and gives the reason as text.
> - Zig uses one error, "cannot assign to constant".
> - C only says "assignment of read-only variable", which is the error that leaks to Blink users today.
> The Go and Zig model (one error, the reason as data) matches P1.

</details>

<details><summary>Web/Scripting — full Phase A proposal</summary>

> Web Phase A proposal ([the spec ticket]): two codes with names a user will search for, not one "NotAPlace".
>
> ## Proposal W1 (preferred): two codes, named for the fix
>
> The case people hit most is `let x = 1` then `x = 2`. Every JS, Kotlin and Python-with-types developer hits it in the first hour. It needs its own short name, so a search gives one answer. "Place" is compiler jargon: nobody types "NotAPlace blink" into a search box. The Ptr case is rare and only FFI users see it. Its fix is different, so it gets a separate code.
>
> **E0611 `AssignToImmutable`**: the root is a plain `let` (local or module level), or the root is not a binding at all (a call result).
>
> [example: `let count = 0; count += 1` → error[AssignToImmutable]: cannot assign to `count`; it is not `let mut` ... help: declare it as `let mut count` at line 2]
>
> I use the same help words as E0610, so the user learns one fix for both. The fix is machine-applicable (insert `mut`) when the binding is a local `let` in the same file. It is NOT machine-applicable for a module-level `let`, because a module `let mut` changes the effect row (State). The help stays and the user decides. The same rule applies to `s.a = 2`, `t.0 = 5`, and `xs = [7, 8, 9]`. The label names the root, and the span covers the full path.
>
> A temporary root uses the same code with a different message:
> error[AssignToImmutable]: cannot assign to a field of a temporary value ... `mk().x = 5` ... this value is dropped after the statement ... help: bind it first: `let mut p = mk()`
> No machine fix here. Python says "cannot assign to function call", and users understand that at once.
>
> **E0612 `AssignThroughPtr`**: error[AssignThroughPtr]: cannot assign to a field through a `Ptr` ... `p` is a `Ptr[IoVec]`; a write through a pointer is a call ... note: a write to `Ptr` memory is an effect, so it uses a method, not `=` ... help: use `p.iov_len.write(4)`
>
> Machine-applicable fix, plain `=` only:
> - The rhs has no call and no closure (literal, name, field path of names): rewrite directly to `p.iov_len.write(rhs)`.
> - Any other rhs, when the assignment is a statement: hoist it, `let value = rhs` then `p.f.write(value)`. Use a fresh name that is not in scope. This keeps the order: rhs first, then root.
> - The assignment is not in statement position: help only.
>
> `blink fix` must fix the common case without a second step. A fix that skips half the cases feels broken. A hoist with a temp name looks a little worse, but it is correct and still one keystroke.
>
> `op=` through a Ptr: help only, `p.f.write(p.f.read() + v)`, as decided.
>
> **Precedence** (one diagnostic per assignment, never two):
> 1. Path goes through a Ptr → E0612. Adding `mut` cannot fix it, so do not suggest that.
> 2. Root is a parameter → ParamAssign.
> 3. Otherwise → E0611.
>
> **ParamAssign:** give it a code now, E0613, next to these two. The three are the "left side of =" family. ERROR_CATALOG lists them together, and `blink explain E0611` cross-links them.
>
> **Rollout:**
> - Cases that leak a raw C error today (`a = 6`, `p.x = 5`, the Ptr ICE) are already broken builds. Make them errors at once.
> - Cases that compile today (`xs = [...]`, `t.0 = 5`, module `let`, `x += 1`, `mk().x = 5`): ship as a warning with the machine fix for one release, then make them errors. This matches the §3.6 rollout rule, so the language has one rule and nobody has to remember two.
>
> **Tests:** each case, plus the closure-in-rhs case. Check that the hoisted fix gives the same result as the spec order.
>
> ## Proposal W2 (fallback): one code, per-case messages
> E0611 `InvalidAssignTarget`, with the message and help changed per case. ... I would vote W1 over W2. Never call it `NotAPlace`.
>
> ## Cross-language
> - Kotlin: "Val cannot be reassigned". This is the best model: short, and it names the keyword.
> - Rust: E0594/E0384 with "consider changing this to be mutable" plus a machine fix. Two codes for two causes. That works.
> - JS: `const` reassign is a runtime TypeError. Blink must do better and catch it at compile time with a span.
> - Python: "cannot assign to function call" is the model for the temporary case.
>
> ## Tradeoffs (DX)
> - W1: two more names to learn. But each name says what is wrong, and each help says what to type.
> - The hoist fix adds a line and a temp name. I accept that, because a fix that sometimes refuses causes more Stack Overflow questions than a fix that adds a line.

</details>

<details><summary>PLT — full Phase A proposal</summary>

> PLT Phase A proposal ([the spec ticket]): I recommend two codes, chosen by which premise of the place rule fails first. The shape check runs before the binding-mode check.
>
> **The judgment.** Read §2.22 as two premises. (S) Shape: the left side is a binding, or a path of struct or tuple field steps whose root is a binding. No step goes through a Ptr. (M) Mode: that root binding is `let mut`. An error must name the first premise that fails. Then its help is a full fix, and the user never gets a second error after applying it. Example: `let p: Ptr[S]` with `p.f = v` fails S. If we report M first ("declare it let mut"), the user follows that help and then gets a second error. So S goes first.
>
> **Proposal 1 (recommended): two codes, plus a code for ParamAssign**
> 1. `NotAPlace` (E0603): S fails. The cases are a step through a Ptr, and a root that is not a binding (`mk().x = 5`).
> 2. `AssignToImmutable` (E0604): S holds and M fails. The root is a local or module-level `let`. This covers `=` and `op=`.
> 3. `ParamAssign` (E0605): S holds and the root is a parameter. The name and text stay as §3.6 gives them. This change only gives it a code.
>
> The order is S, then param, then let. A Ptr parameter `p.f = v` is `NotAPlace` with the write help, not `ParamAssign`, because the write through the Ptr is the legal thing the user meant.
>
> error[AssignToImmutable]: cannot assign to `total`, a `let` binding / note: `total` is declared without `mut` at line 2 / help: declare it as `let mut total` at line 2
> Fix: machine-applicable for a local `let`. For a module-level `let` it is help only, because `let mut` adds `State` to the effect row of each function that reads it. That changes types far from the edit.
>
> error[NotAPlace]: `p.iov_len` is not an assignment place: the path goes through `p: Ptr[IoVec]` / note: a field path that goes through a `Ptr` is a pointer to memory, not a place (§2.22) / help: write through the pointer: `p.iov_len.write(n)`
> error[NotAPlace]: `mk().x` is not an assignment place: its root is a call result / note: the value is a temporary, so the store would be lost / help: bind it first: `let mut t = mk()`
> The fix for the call-root case is never machine-applicable, because the user's intent is not clear.
>
> **When the Ptr rewrite is machine-applicable.** The rewrite `p.f = rhs` -> `p.f.write(rhs)` changes order. It reads the receiver before rhs, but §2.22 reads the root after rhs. That matters only if rhs can change a value the receiver path reads. So the rewrite is sound when both of these are true:
> - (a) The root binding is not `let mut`. That covers a `let` or a parameter. Nothing can write such a root, and this diagnostic family enforces that. So the safety argument comes from the type rules and needs no effect analysis.
> - (b) Each step of the receiver path is address arithmetic, with no load from memory. If a step loads, rhs can write that memory through the Ptr effect.
>
> When (a) or (b) fails, the fix is still machine-applicable, but it uses the hoist form: `let tmp = rhs` / `p.f.write(tmp)`. The hoist form uses a fresh name and applies only in statement position. In expression position, such as a braceless match arm tail, the fix is help only. The extra rule "rhs is a literal or a name" adds nothing once (a) is in place, so I would drop it. `op=` through a Ptr stays plain help, `p.f.write(p.f.read() op v)`, as decided.
>
> The required test: `let mut p` with a closure in rhs that reassigns `p`. Check that the fix uses the hoist form and that the result keeps the order (the new `p` gets the write). Also add a negative test: for `let p` with the same rhs shape, the fix uses the direct form.
>
> **Proposal 2 (fallback): one code, `NotAPlace`, with a subcase for each label** ... I rank this second.
>
> **Rollout.** The §3.6 rule (warning first, then error) protects programs the spec allowed before. These programs were never valid. Also, accepting a write to an immutable `let` is unsound against capture-by-copy: a closure keeps an old copy that the spec says cannot go out of date. The current behavior is already a C error, a silent mutation, or an ICE. Ship both codes as errors at once. ParamAssign keeps its own warning-first rollout.
>
> **Cross-language note.** Rust has E0594/E0384 for the mode failure and E0070 for an invalid left side, and it marks "make this binding mutable" MachineApplicable. OCaml rejects `x <- v` on a field that is not mutable at the type level. Blink puts mutability on the binding, so our M premise maps to Rust's binding check, not to OCaml's field check.

</details>

<details><summary>DevOps — full Phase A proposal</summary>

> DevOps Phase A proposal for [the spec ticket]: several names in one E061x family, one diagnostic per mistake, fixes gated by a syntactic test.
>
> ## Proposal D1 (recommended): one name per fix shape, E0611–E0614
>
> The `name` decides which code action the LSP shows and what `blink fix --only <Name>` selects. Cases that need different fixes need different names. Put them next to E0610 so that "mutability of a place" is one block in ERROR_CATALOG.md.
>
> | Name | Code | Fires when | Fix |
> |---|---|---|---|
> | ImmutableAssign | E0611 | root is an immutable local `let` (any path, `=` or `op=`) | insert `mut` |
> | AssignThroughPtr | E0612 | a step of the path goes through a `Ptr` | `.write(...)` |
> | NotAPlace | E0613 | root is not a binding (`mk().x = 5`) | bind it first |
> | ParamAssign | E0614 | root is a parameter (already decided, gets a code) | `let mut x = a` |
>
> All four share one headline form, `cannot assign to ...`, so that a user who greps finds all of them.
>
> **Precedence (one mistake gives one diagnostic):** AssignThroughPtr > NotAPlace > ParamAssign > ImmutableAssign. With `fn f(p: Ptr[S]) { p.f = 1 }`, adding `mut` does not help, but `p.f.write(1)` is legal with a plain `p`. So the Ptr case must win.
>
> ```blink
> fn main() {
>     let x = 1
>     x += 1
> }
> ```
> ```
> error[ImmutableAssign]: cannot assign to `x`, which is not `let mut`
>  --> main.bl:3:5
>   |
> 2 |     let x = 1
>   |         - declared here
> 3 |     x += 1
>   |     ^^^^^^ assignment to an immutable binding
>   = help: declare it `let mut x` (line 2)
> ```
> The help uses the same words as E0610 today ("declare it as `let mut x` at line N"); use one template for both. **Machine-applicable** when the root is a local `let` with a plain name pattern. The edit inserts `mut ` at that span. N assignments to one root give N diagnostics with the same edit. `blink fix` must merge identical edits (state this in §8.6). It is a **suggestion only** for: a module-level `let` (the change adds `State` to every writer, and `pub let mut` is E1013), destructured patterns, `for` variables and match bindings.
>
> ```blink
> @ffi.struct type IoVec { iov_base: Ptr[U8], iov_len: Int }
>
> fn set_len(p: Ptr[IoVec], n: Int) {
>     p.iov_len = n
> }
> ```
> ```
> error[AssignThroughPtr]: cannot assign to `p.iov_len`, which goes through a `Ptr`
>  --> io.bl:4:5
>   |
> 4 |     p.iov_len = n
>   |     ^^^^^^^^^ `p` is `Ptr[IoVec]`; memory behind a `Ptr` is not a place
>   = note: a store through a pointer is an effect; use `write`
>   = help: `p.iov_len.write(n)`
> ```
> **When the fix is machine-applicable (meets Q3b):**
> 1. rhs is *inert*: a literal, a local name, a field path of names, or unary or binary operators over those. It has no call, no closure, no `?`, no method and no `await`. Then the direct rewrite is machine-applicable, because inert rhs cannot write the root.
> 2. Any other rhs, when the assignment is a statement in a `{ }` block: the fix hoists rhs, `let v = rhs` then `p.f.write(v)`. This is machine-applicable, because rhs still runs before the root is read. The fixer picks a fresh name (`value`, `value1`, ...) that is not in scope.
> 3. The assignment is a braceless match arm, or the hoist is not possible: suggestion only.
>
> `op=` through a Ptr: help `p.f.write(p.f.read() + n)`, suggestion only, as decided.
>
> Required tests: a closure in rhs that reassigns `p` (`p.f = { p = q; 1 }`-shape via a closure call) must get the hoist fix and never the direct one. An integration test must run `blink fix` and check that the program prints the same value as the hand-written hoist.
>
> ```
> error[NotAPlace]: cannot assign to a field of `mk()`, which is a temporary value
>   = note: the store would change a copy that is dropped at once
>   = help: bind it first: `let mut t = mk()`
> ```
> Suggestion only.
>
> **Rollout:** E0611–E0613 are errors at once. Each case today gives a raw C error, an ICE, or a silent wrong program (`let xs; xs = [...]` runs). A warning cycle would keep the wrong behaviour live. ParamAssign keeps its §3.6 rule (warning first, then error). The JSON `name` stays stable across that change, so fix scripts keep working.
>
> ## Proposal D2 (fallback): one code, `NotAPlace` E0611, with a `reason` field
>
> Use one name, plus `reason: immutable_root | through_ptr | temporary_root` in the JSON. It has fewer catalog rows. Cost: `--only` and the LSP code-action filter must look inside the payload. Every tool that already keys on `name` (§8.6) gets a second key. rustc tried this: E0594 covers several cases and its help text varies a lot, and rust-analyzer has to work again to tell them apart. I recommend against it.
>
> ## Cross-language
> - rustc: E0384 (assign twice to immutable) is separate from E0594/E0596. Its machine-applicable "make this binding mutable" fix applies only to simple patterns. D1 copies that limit.
> - TypeScript: a single 2588 "Cannot assign to 'x' because it is a constant" covers this case, with a quick fix to change `const` to `let`.
> - Go: "cannot assign to x (neither addressable nor a map index expression)" is one message for many causes. It is a known source of user confusion and shows why D2 reads worse.
>
> ## Open point for others
> Is a closure capture in the root (`let x` captured and assigned in a lambda) ImmutableAssign with the span at the capture? I say yes, with the label "captured here", and the fix still applies at the `let`.

</details>

<details><summary>AI/ML — full Phase A proposal</summary>

> AI/ML Phase A proposal (full resend) for the "not an assignment place" diagnostic ([the spec ticket]).
>
> ## Proposal A (preferred): two names, split by which fix works
>
> An AI agent fixes an error by mapping its name to a repair. If one name has two unrelated repairs, the agent must read the help text to know which one applies. With one name per repair, the name alone tells the agent what to do. Both names are also good search keys in training data.
>
> | Name | Code | Root cause | Fix shape |
> |---|---|---|---|
> | ImmutableAssign | E0611 | The root is a binding that is not `let mut`: a local `let`, a module `let`, a `for` variable or a match binding | Change the declaration |
> | NotAPlace | E0612 | The left side is not a place: a step goes through a `Ptr`, or the root is a call result or another temporary | Rewrite the statement |
>
> `NotAPlace` uses the same word as §2.22 ("place"), so an agent can learn it from the spec alone. Do not reuse E0313. `ParamAssign` gets code E0613 in the same group, so all three left-side errors sit together in ERROR_CATALOG.md.
>
> Which error wins. Each site gets exactly one diagnostic, chosen in this order:
> 1. NotAPlace (Ptr step). It wins because the fix makes the code legal even if the root is a parameter or a plain `let`: `write` takes plain `self`.
> 2. ParamAssign.
> 3. ImmutableAssign.
>
> error[ImmutableAssign]: cannot assign to `total`, it is not declared `let mut` ... declared here without `mut` ... assignment to an immutable binding ... help: declare it `let mut total`
>
> Fix: insert `mut`. It is machine-applicable only for a local `let` in the same function. For a module `let`, a `for` variable or a match binding it is help only:
> - A module write changes the function's effect row (State).
> - A `for` variable or a match binding has no `let` to edit.
>
> error[NotAPlace]: `p.iov_len` is not an assignment place: the path goes through `Ptr[IoVec]` ... a field reached through a `Ptr` is memory, not a place ... note: a `Ptr` write is an effect; use the field's `write` method (§9.1.1) ... help: write it as `p.iov_len.write(n)`
>
> When the Ptr fix is machine-applicable (plain `=` only):
> - Simple rhs (a literal, a name, or a field path of names, with no call, closure or `?`): rewrite to `p.f.write(rhs)`.
> - Any other rhs: hoist it, then write: `let v = rhs` on the line above, then `p.f.write(v)`. The tool picks a name that is not already in scope. This keeps the §2.22 order (rhs first, then read the root), because an assignment is a statement.
>
> So the fix is always machine-applicable, but in one of two shapes. `op=` stays help only, as decided: help: write it as `p.f.write(p.f.read() + n)`.
>
> For a call-result root (`mk().x = 5`), the help is "bind it first: `let mut t = mk()`, then `t.x = 5`". No machine fix, because the new code would discard the store.
>
> Required test: a closure in rhs that reassigns the root (let mut p = a; swap closure sets p = b; p.f = swap()).
> - The hoisted fix stores into `b.f`, the same as the §2.22 order.
> - The naive rewrite `p.f.write(swap())` reads `p` first, so it would store into `a.f`.
>
> Rollout:
> - Error at once: the cases that already fail today with a raw C error (`let a`, then `a = 6`; `p.x = 5`; `p.iov_len` crashing the compiler). Users get nothing useful from a warning phase here.
> - Warning for one release, then error: the cases that compile today (`xs = [...]`, `t.0 = 5`, a module `let`, `x += 1`). This follows the §3.6 rule, and `blink fix` applies the fix in that release.
>
> Tradeoffs:
> - For: the name tells the agent the fix, and the JSON `fix` is usable without guessing. Every help line is valid Blink code an agent can copy as-is.
> - Against: an agent must learn two names. I think this costs little, because they map to two different edits (the declaration or the statement). Also, the Ptr fix has two shapes. The tool applies them, so agents do not need to choose.
>
> ## Proposal B (fallback): one name, NotAPlace (E0611), with help per case
> The cost: in the JSON output, `name` no longer tells the agent the repair. It must branch on `labels` or `help`, which adds a decision point at the moment it self-corrects. Also, "immutable" is the word every model already uses for this error, and A keeps it.
>
> ## Cross-language note
> - Rust uses two codes: E0384 and E0594/E0070. The two-way split is familiar to models.
> - Swift uses one message ("cannot assign to value: 'x' is a 'let' constant"). Its fix-it is reliable, but the many "cannot assign" variants are hard for models to tell apart.
>
> My one firm point: any fix marked machine-applicable must keep the program's behaviour exactly the same. Models learn from what `blink fix` writes, so a fix that changes the order things run in would teach them a wrong rewrite.

</details>

<details><summary>Minimalism — full Phase A proposal</summary>

> **Minimalism (Min) — Phase A**
>
> Lens: one rule per concept. The brief puts two different faults under one name. An immutable root is a place that lacks `mut`. A path through a `Ptr`, or a call-result root, is not a place. The fix for the first is one word at the declaration. The fix for the second is a different operation. One shared code would need a help switch inside it. That is two codes in disguise.
>
> ## Proposal M1 (preferred): widen E0610, add one code
>
> **1. Immutable root → E0610 MutationRequiresMut (no new code).** §3.2.2 already defines "mutable root" for mutating calls. `x = v`, `s.a = v`, `t.0 = v` and `x op= v` are mutations of the same root. Change the rule from "a call to a mutating method needs a mutable root" to "a mutation (a `mut self` call, `=`, or `op=`) needs a mutable root". One rule and one code. A user who learned E0610 from `xs.push` already knows the fix.
>
> ```blink
> fn main() {
>     let t = (1, 2)
>     t.0 = 5
> }
> ```
> ```
> error[MutationRequiresMut]: cannot assign to `t.0`: `t` is not mutable
>  --> main.bl:3:5
>   |
> 2 |     let t = (1, 2)
>   |         - declared here without `mut`
> 3 |     t.0 = 5
>   |     ^^^^^^^ assignment through immutable root `t`
>   = help: declare it as `let mut t`
> ```
> Fix: insert `mut ` after `let`. Machine-applicable when the declaration is in the same file. The edit cannot change meaning.
>
> Sub-cases:
> - Module-level `let g`: same text and fix (`let mut g` is legal at module level).
> - Imported `pub let g`: no fix. Help: "`g` is an immutable export of `m`; `pub let mut` is not allowed (E1013). Add a function in `m` that sets it."
> - Parameter root: ParamAssign wins, as decided. E0610 does not fire.
>
> **2. Not a place → one new code, `NotAPlace` (E0611).** It covers each left side that no `mut` can fix: a step through `Ptr`, and a root that is not a binding (`mk().x = 5`, `(a).b` from a call, a literal).
>
> ```blink
> fn set_len(p: Ptr[IoVec]) {
>     p.iov_len = 4
> }
> ```
> ```
> error[NotAPlace]: `p.iov_len` is not an assignment place
>  --> io.bl:2:5
>   |
> 2 |     p.iov_len = 4
>   |     ^^^^^^^^^ this path goes through `p: Ptr[IoVec]`
>   = note: a store through a pointer is a call, not an assignment (§9.1.1)
>   = help: use `p.iov_len.write(4)`
> ```
> `op=`: help `p.iov_len.write(p.iov_len.read() + 4)`, never machine-applicable.
> Call root: note "`mk()` makes a temporary value; a store to it has no effect", help "bind it first: `let mut v = mk()`". No fix.
>
> **Fix rule for `p.f = rhs`.** Machine-applicable only when `rhs` is inert: a literal, a name, or a field path of names. Nothing that can call code, so nothing that can write `p`. Every other `rhs` gets a plain help. No hoist. A hoist needs a fresh-name generator, a scope check, and a two-statement edit, for FFI code that is rare. If the inert subset proves too narrow, add the hoist later as a pure extension. The rule stays the same.
>
> Required test: `p.f = { p = q; 1 }` style rhs via a closure call (`p.f = reset()` where `reset` reassigns `p`). It must get help with no `fix`.
>
> ## Rollout
>
> Ship both as errors now, not warn-first. §2.22 already makes these programs illegal. Today they give raw C errors, an ICE, or silent miscompiles (`xs = [...]` on a plain `let`). The §3.6 warn-first rule protects code that the spec allowed before. None of this code was allowed. A warning phase would keep a known-wrong program compiling for one more release, and would add a temporary diagnostic state that we must later delete.
>
> ## Proposal M2 (fallback): one code for all
>
> If the panel wants one code for "bad left side of `=`", use `NotAPlace` for both, with help chosen per case. Cost: E0610 and NotAPlace then both report "immutable root", for `xs.push` versus `xs = ...`. Two codes for one fault is worse than one code with two cases. I vote against M2.
>
> ## Rejected
>
> - A separate code per sub-case (ImmutableAssign, PtrFieldStore, TemporaryAssign): three names for one table lookup.
> - Reuse E0313: decided, no.
> - A blanket machine-applicable `.write` fix: decided, no.
>
> ## Cross-language
>
> Rust uses E0384 (reassign immutable) and E0594 (assign through `&`) and E0070 (invalid left side). That is three codes, and users mix them up. Go has one message, "cannot assign to X", with a reason in the text. M1 sits between: two codes, split on "add `mut`" against "this is not a place", which is the only split that changes what the user does.
>
> **Combinatorial cost of M1:** one rule widened, one code added, zero new fix machinery.

</details>

#### Phase B — Debate highlights

One round. Five of six seats said STABLE after it. Each seat's opening line, verbatim:

- **Systems:** Sys Phase B round 1: I drop Q1-A and back Q1-B, then Q1-C; I move to Q6-A (all errors at once). STABLE.
- **Web/Scripting:** Web Phase B round 1: I move to Q1-B (Min's M1), take PLT's order and fix condition, and change to errors at once (Q6-A).
- **PLT:** PLT Phase B round 1: I move to Q1-B (Min M1), with Q1-C second. Q6-A, errors at once. Q4 is the union of A and C, with hoist.
- **DevOps:** DevOps Phase B round 1: I drop D1 (four names) and move to Q1-B, with Q1-C as my second choice. Votes: Q2 yes, Q3 shape first, Q4-A with PLT's condition added, Q5 help only for a module `let`, Q6-A.
- **AI/ML:** AI/ML Phase B round 1: I move to Q1-B (Min's M1) and to Q6-A. My other positions stay as in Phase A.
- **Minimalism:** **Min — Phase B round 1**

Key shifts, quoted:

- **Systems:** "I withdraw Q1-A. Min, AI/ML and DevOps make a better point than my MissingReturn precedent. The MissingReturn kinds share one fix. My four kinds need two different edits, at two different lines."
- **Minimalism** (round 1, later reversed in Phase C): "E0610 accepts a `mut` parameter as a mutable root, and §3.6 rejects every assignment to a parameter. So "mutable root" would mean one thing for calls and another for `=`. That is two rules under one code, which is the opposite of what I wanted."
- **Minimalism** (Phase C): "PLT and AI/ML showed that the Q3 order fixes this. ParamAssign is checked before E0610, so E0610 on `=`/`op=` can only fire on a `let` root."

<details><summary>Systems — full round 1 reply</summary>

> Sys Phase B round 1: I drop Q1-A and back Q1-B, then Q1-C; I move to Q6-A (all errors at once). STABLE.
>
> Q1. I withdraw Q1-A. Min, AI/ML and DevOps make a better point than my MissingReturn precedent. The MissingReturn kinds share one fix. My four kinds need two different edits, at two different lines. The `kind` field was a second code with a different name.
> - First choice: Q1-B (Min). Seen from the machine, `xs = [7]`, `t.0 = 5` and `xs.push(7)` are the same operation: a store into the storage of a binding that the user marked immutable. The compiler runs one check, the root binding's mutability, for all three. One rule ("a mutation needs a mutable root") and one code is the honest model. E0610's help text is already the fix we want.
> - Second choice: Q1-C (PLT / AI/ML). It has the same split, but uses a new immutable code. Web's search argument is the only thing it gains over Q1-B.
> - Against Q1-D (Web). Putting `mk().x = 5` with the immutable cases is wrong. `mut` cannot fix a temporary, because there is no declaration to edit. PLT's shape-vs-mode test gets this right.
> - Against Q1-E (DevOps). Ptr and temporary both mean "rewrite the statement". Two names for one premise failure is too many.
>
> Q2. Yes. ParamAssign gets a code in the same block. Use contiguous numbers after E0610 (E0611, E0612), not PLT's E0603–E0605, so that the family reads as one run in ERROR_CATALOG.md.
>
> Q3. PLT's order: shape (Ptr, temporary), then parameter, then let. Report the first premise that fails, so that the help is a full fix.
>
> Q4. I accept PLT's condition as a second route to the direct form. The machine-applicable rule then has three steps:
> 1. Use the direct form when the rhs is inert, or when PLT's (a) and (b) both hold: the root is not `let mut`, and no step of the path loads from memory.
> 2. Otherwise, in statement position, hoist the rhs to a temporary. At run time this costs nothing: the C compiler already puts the rhs into a temporary. This answers Min's concern. The cost is a fresh-name check, not a runtime cost, and it gets rid of a fix that refuses for no reason the user can see. Web is right about that.
> 3. Otherwise, give help only.
> - Against DevOps's "binary operators over inert operands". A `+` on a user type dispatches to an ops-trait impl, and that impl is arbitrary code that can write Ptr memory. Allow an operator only when its operands are primitive.
> - If the panel picks Q4-B, I can accept it as an MVP floor.
>
> Q5. Module-level `let`: help only. I disagree with Min here. A module `let mut` adds State to the effect row of every writer, and that can set off E0651 at an `async.spawn` far from the edit. A machine-applicable fix must never create new errors somewhere else. Imported `pub let`: help only, with the E1013 note (Min, DevOps).
>
> Q6. I change to Q6-A. PLT and DevOps convinced me:
> - §2.22 never allowed these programs.
> - `xs = [...]` running today is a silent miscompile.
> - A closure that captures by copy depends on immutability. A module `let` written from a spawned task is a data race.
> A warning release would keep wrong codegen live on purpose. ParamAssign keeps its own warning-first rule, because that rule covers code the spec allowed before.
>
> Other points:
> - DevOps: a captured immutable `let` assigned inside a closure gets the immutable-root diagnostic, labelled "captured here", with the fix at the `let`. Yes.
> - DevOps: `blink fix` merges identical edits. Yes.
> - I keep my note on `op=` through a Ptr: two memory operations, not atomic.
> - I keep my test for a Ptr step in the middle of the path, and I add PLT's negative test (plain `let p` gets the direct form).
>
> STABLE, ready to vote.

</details>

<details><summary>Web/Scripting — full round 1 reply</summary>

> Web Phase B round 1: I move to Q1-B (Min's M1), take PLT's order and fix condition, and change to errors at once (Q6-A).
>
> **Q1: Q1-B.** Min convinced me. To a JS dev, `xs.push(1)` and `xs = [1]` on a plain `let` are the same mistake with the same fix, "add `mut`". With one code they learn it once and search one page. With two codes (my W1, and PLT's/AI/ML's AssignToImmutable), the 90% case is split in two for no gain in what the user does. The message text must still name the action: "cannot assign to `t.0`: `t` is not mutable". The name `MutationRequiresMut` is fine because users read the message, not the name.
>
> The temporary root (`mk().x = 5`) goes with the Ptr case, as PLT and Min say. Its fix is "bind it first", not "add `mut`". My W1 had it in the wrong place.
>
> On the name `NotAPlace`, I withdraw my "never" because §2.22 already defines "place". My condition: the message leads with the concrete reason, as PLT's text does ("the path goes through `p: Ptr[IoVec]`", "its root is a call result"), and the help gives the code to type. With that, the jargon costs little. Against Q1-A (Sys): a `kind` field does not help a human reading the terminal. Against Q1-E (DevOps): four names for one table lookup.
>
> **Q2:** Yes. ParamAssign gets a code in the same block.
>
> **Q3:** PLT's order: shape (Ptr, temporary), then parameter, then let. PLT's argument is the DX argument: never give a help that leads straight to a second error. A Ptr parameter `p.f = v` gets NotAPlace with `.write`, not ParamAssign.
>
> **Q4: Q4-C (PLT), against Q4-B.** Min's inert-only rule refuses the fix for `p.f = compute()`. That is the common FFI line, and a fix that refuses it generates the forum question "why won't blink fix fix this?". PLT's condition gives the direct form for a `let p` or parameter root, which is nearly all real Ptr code. So users rarely see the ugly temp, and the hoist covers the rest. Before I accept it, the implementer must be able to say in one sentence when the hoist form appears ("only when the root is `let mut` or the path loads through memory"). If the panel finds Q4-C too subtle, my second choice is Q4-A.
>
> **Q5:** A module-level `let` gets help only, no fix (PLT's reason: `let mut` there changes effect rows in far-off functions). An imported `pub let` gets help with no fix (Min, DevOps).
>
> **Q6: I change to Q6-A.** PLT and Min are right: this code was never valid, and today it either fails with a raw C error or silently does the wrong thing. A warning phase keeps a known miscompile alive for one more release, and adds a temporary state that we must delete later. My condition: the error ships with its machine-applicable fix, so `blink fix` repairs `let`-root code in one command. The cost to users is then one command, not a migration. ParamAssign keeps its decided warn-first rollout.
>
> **Other points:**
> - I support DevOps's capture case: a write inside a closure to a captured immutable `let` gets the same code, the label "captured here", and the fix at the `let`.
> - I support DevOps's rule that `blink fix` merges identical edits (one `mut` insert for N assignments). Without it, `blink fix` makes duplicate edits and users see that as a bug.
> - I support Sys's "not atomic" note on `op=` through a Ptr. Keep it to one line.
> - I support all the proposed tests: a Ptr step mid-path, the closure-reassigns-root test (hoist form), PLT's negative test (direct form), and a `blink fix` round-trip test.
> - E-code numbers: no strong view. I prefer adjacent codes after E0610 (E0611 onward) so they appear next to each other in the catalog.
>
> STABLE, ready to vote.

</details>

<details><summary>PLT — full round 1 reply</summary>

> PLT Phase B round 1: I move to Q1-B (Min M1), with Q1-C second. Q6-A, errors at once. Q4 is the union of A and C, with hoist.
>
> **Q1. Q1-B first, Q1-C second. Against Q1-A and Q1-D.**
> Min is right. The mode premise of §2.22, "the root is `let mut`", is the same premise as E0610's "mutable root". Two codes for one premise is worse than one rule made wider. That is the compositional choice, and it is cleaner than my own Q1-C.
> - The wider E0610 text must say that a `mut` parameter is a mutable root for a `mut self` call only. For `=` and `op=`, a parameter root is ParamAssign. With the order in Q3 this works.
> - Against Sys Q1-A: a `kind` field puts two different premises under one name. MissingReturn is not a precedent here, because its tail kinds all fail the same premise.
> - Against Web Q1-D: a temporary root has no binding, so it cannot fail the mode premise. Its fix ("bind it first") is not "insert `mut`". Putting it under AssignToImmutable files it under the wrong rule.
> - I do not object strongly to DevOps Q1-E. But a Ptr step and a call root fail the same shape premise, and neither has one uniform fix. So a separate name for each does not buy `--only` much.
> - On Web's point that "place" is jargon: the word is in §2.22, and the spec must use one word for one concept. Also, Q1-B gives users the name "MutationRequiresMut" for the common case, which Web wanted.
>
> **Q2.** Yes, ParamAssign gets a code now. I drop my E0603–E0605 and take the E0611+ range the other panelists proposed.
>
> **Q3.** Shape (Ptr step or temporary), then parameter, then let. All six agree on the important part: the Ptr step wins.
>
> **Q4. The union of Q4-A and Q4-C, with hoist otherwise. Against Q4-B.**
> The direct rewrite is sound when either of these is true:
> - (1) The rhs is inert: a literal, a name, or a field path of names.
> - (2) The root is not `let mut`, and no step of the path loads from memory.
>
> Against DevOps's widening of "inert": unary and binary operators are not inert. On a user type, `a + b` calls an ops-trait impl, and that call can write Ptr memory. Keep "inert" syntactic and free of calls. In all other cases, hoist in statement position, and give help only elsewhere.
> - Against Min Q4-B: the hoist is trivially sound. It writes out the exact order §2.22 already gives, so it is not new fix machinery that needs trust. A narrow `blink fix` teaches agents nothing (AI/ML's point).
> - I accept Q4-A alone as a fallback. It is sound too.
>
> **Q5. Module-level `let` is help only. I disagree with Min here, and this is a soundness point.**
> §4.16 makes each reader of a module `let mut` carry `State`:
> - A `pub` reader then fails with E0552.
> - A closure that reads it no longer fits `fn() -> T`.
>
> So adding `mut` at module level can break type checks in other places. A machine-applicable fix must not do that. Imported `pub let` gets help only, per E1013 (Min and DevOps). For a local `let`, the fix is machine-applicable with a plain name pattern only.
>
> **Q6. Q6-A, errors at once. Against Sys, Web and AI/ML on Q6-B.**
> A warning phase means the compiler must give these programs a meaning for one release.
> - For a module `let g` with `g = 2` in a function, the function's row has no `State`. A warning would accept a function that writes module state with no `State` in its row. That is a hole in the effect system, not a style issue. The same function also hides from the write set.
> - For a local `let`, an immutable capture is a copy, so the closure keeps the old value. The program then sees two values for one immutable binding.
>
> The §3.6 warn-first rule protects code that was valid before. These programs never were.
>
> **Other points.**
> - DevOps: yes. A closure that assigns to a captured immutable `let` gets the same code, the label "captured here", and the fix at the `let`.
> - DevOps: `blink fix` merges identical edits. Agreed.
> - Sys: a note that `op=` through a Ptr is not atomic. Agreed.
> - Tests: keep my negative test (a plain `let p` root with a closure rhs gets the direct form under (2)) and Sys's test for a Ptr step in the middle of a path.
>
> STABLE, ready to vote.

</details>

<details><summary>DevOps — full round 1 reply</summary>

> DevOps Phase B round 1: I drop D1 (four names) and move to Q1-B, with Q1-C as my second choice. Votes: Q2 yes, Q3 shape first, Q4-A with PLT's condition added, Q5 help only for a module `let`, Q6-A.
>
> **Q1: Q1-B first, Q1-C second; against Q1-A and Q1-D.** My Phase A test was "one name per fix shape", and Min applies it better than I did. E0610 already has the fix "insert `mut` at line N", with a help template and a code action. `x = 2` on a plain `let` needs the same edit at the same place. With Q1-B, the LSP has one quick-fix provider and `blink fix --only MutationRequiresMut` catches `xs.push` and `xs = ...` in one pass. Two names with one identical edit (Q1-C) add a name and give nothing to tools. I also fold the temporary case into NotAPlace, as Min, PLT and AI/ML do. It has no machine fix, so a separate name gives tools nothing to act on.
>
> - **Sys (Q1-A):** the MissingReturn precedent fits when every kind has the same repair class. Here `kind` would pick between an edit at the declaration and an edit at the statement. Then every consumer of the JSON must branch on the payload, which AI/ML also calls out. Against.
> - **Web (Q1-D):** I agree the *message* must not say "place" alone. PLT's message already explains it: "the path goes through `p: Ptr[IoVec]`". The *name* should match the §2.22 word, so that `blink explain` and the spec index agree. Putting the temporary case under AssignToImmutable is wrong: `let mut t = mk()` is a new binding, not a `mut` on an existing one. Against.
>
> **Q2: yes.** ParamAssign gets the next code in the same block now. A diagnostic with no code cannot be set under `[lints]` while it is a warning.
>
> **Q3: shape first (PLT).** The order is Ptr or temporary, then parameter, then immutable root. The reason is about tools: the first fix applied must be the last one needed. If the user follows a "declare it `let mut`" help and then gets a second error, `blink fix` fails its one-pass promise.
>
> **Q4: Q4-A, with PLT's condition added as a second way to get the direct form.**
> - The direct form applies when the rhs is inert, OR when PLT's (a)+(b) holds: the root is not `let mut` and no path step loads from memory.
> - Otherwise use the hoist in statement position. Elsewhere it is help only.
>
> PLT's rule comes from the type rules and is sound, and it gives the cleaner edit more often. Against Min's Q4-B: the fresh-name machinery is not new cost. NotAPlace's own help ("bind it first: `let mut t = mk()`") already needs a fresh name, and the LSP rename already checks scope. A fix that is present for `p.f = 4` and missing for `p.f = len(x)` looks random to users and teaches agents nothing.
>
> **Q5: module `let` is help only (against Min).** Adding `mut` there makes every writer need `State`. That can fail to compile in other files, so the edit does not keep the program compiling. A machine-applicable fix must never cause new errors elsewhere.
>
> **Q6: Q6-A, all errors at once.**
> - **Web, AI/ML, Sys:** a warning tier has a cost to tools. It is a state the compiler must still build code for. For `xs = [...]` that means keeping a miscompile live on purpose, and for scalars C rejects it anyway.
> - PLT's capture-by-copy point shows that the "works today" cases are unsound, not just strict.
> - `blink fix` has the same fixes in both options, so a warning release adds nothing for migration.
> - I will move to Q6-B if it is the price of a majority. It is my lowest-stakes point.
>
> **Other points:**
> - **Sys's not-atomic note on `op=` through a Ptr:** yes.
> - **Merging identical edits in `blink fix` (§8.6):** still required. With Q1-B it matters more, because a `push` and an `=` on one root both emit the same `mut` insert.
> - **Closure-capture case:** it goes to the same immutable-root code, with a "captured here" label. I ask PLT to confirm.
> - **Tests:** I keep the `blink fix` integration test (output equals the hand-written hoist) and add PLT's negative test.
>
> STABLE, ready to vote.

</details>

<details><summary>AI/ML — full round 1 reply</summary>

> AI/ML Phase B round 1: I move to Q1-B (Min's M1) and to Q6-A. My other positions stay as in Phase A.
>
> Q1: Q1-B first, Q1-C second. Against A, D and E.
> - I change my vote. Min is right: `xs.push(1)` and `xs = [1]` on a plain `let` have one fix (add `mut`). With two names for one fix, an agent must learn two keys that lead to the same edit. Q1-B gives one name, MutationRequiresMut (E0610), for every "root needs `mut`" error. Agents already see E0610 on `push`, so the training data stays consistent. This also uses fewer names than my own A.
> - NotAPlace covers the step through a `Ptr` and the temporary root. Both mean "rewrite the statement", and "place" is the word §2.22 uses, so an agent can learn it from the spec alone. Web says "place" is jargon. That is true for humans, but the message text says "cannot assign through a Ptr", and the name is a key, not the explanation.
> - Against Q1-D (Web, Sys P2): it puts `mk().x = 5` under AssignToImmutable, but adding `mut` cannot fix it. The name then leads to the wrong fix. That is the worst outcome for self-correction.
> - Against Q1-A (Sys): agents and tools key on `name`. A `kind` field adds a second lookup. DevOps makes the same point for `--only` and LSP.
> - Against Q1-E (DevOps): it uses four names, and one of them (temporary root) is rare.
>
> Q2: Yes. Give ParamAssign a code now. Under Q1-B that is E0612 (E0611 = NotAPlace).
>
> Q3: Shape first, as PLT argues: Ptr step, then temporary root, then parameter, then immutable root (E0610). With this order, each help is a complete fix and never leads to a second error.
>
> Q4: Q4-A. Against Q4-B (Min). My main argument: if a complex rhs gets help only, the agent writes the rewrite by hand, and the naive hand rewrite `p.f.write(rhs)` is exactly the wrong-order bug. Help-only pushes models to the unsafe form. The hoist must be the fix, and help text that shows only the direct form is not enough. Against Q4-C (PLT): it is sound, but its condition depends on the binding mode and on whether a path step loads from memory, so neither a reader nor a model can tell from the code which form the fixer will write. The "inert rhs" rule is syntactic and visible. Same output for the same text gives clean training data. I accept DevOps's widening (unary or binary operators over inert terms).
>
> Q5: Agree with the majority. Module `let` is help only (it changes effect rows far from the edit). Imported `pub let` is help with no fix (E1013), per Min and DevOps. Where E0610 already gives "declare it as `let mut x` at line N", reuse that one template.
>
> Q6: I change to Q6-A (all errors at once). PLT, Min and DevOps convinced me. The code was never valid, `xs = [...]` is a silent miscompile today, and agents ignore warnings, so a warning release leaves wrong code in circulation for one more cycle. ParamAssign keeps its own §3.6 rule.
>
> Other points: I support
> - DevOps: a capture assigned inside a closure gets the immutable-root error with the label "captured here", and the fix goes at the `let`.
> - DevOps: `blink fix` merges identical edits.
> - Sys: the "not atomic" note on the `op=` help.
> - All the extra tests (Sys: Ptr step mid-path; PLT: negative direct-form test; DevOps: run-and-compare integration test).
> - E-codes E0611 and up.
>
> One item for Min to confirm: widening E0610 changes the wording of the §3.2.2 rule. The new text must say that a `mut` parameter is a mutable root for a `mut self` call only. For `=`, ParamAssign still wins.
>
> STABLE, ready to vote.

</details>

<details><summary>Minimalism — full round 1 reply</summary>

> **Min — Phase B round 1**
>
> **Q1: I change to Q1-C and drop my own M1.** PLT's two-premise reading (shape, then mode) is the same split I made: "add `mut`" against "not a place". But widening E0610 fails on one point I missed. E0610 accepts a `mut` parameter as a mutable root, and §3.6 rejects every assignment to a parameter. So "mutable root" would mean one thing for calls and another for `=`. That is two rules under one code, which is the opposite of what I wanted. A new code is cleaner.
> - Against **Q1-A** (Sys, one code with a `kind` field): DevOps is right. `name` is the key that `--only` and the LSP use (§8.6). A `kind` field adds a second key.
> - Against **Q1-D** (Web, temporary goes with immutable): `let mut` does not fix `mk().x = 5`. PLT's test applies: the help must be a full fix.
> - Against **Q1-E** (DevOps, four names): a temporary root and a `Ptr` step both mean "rewrite the statement", and neither gives a reason to filter them apart. The extra name buys no tool behavior.
> - **Names:** `NotAPlace` for the shape failure. It is the §2.22 word, and AI/ML is right that an agent learns it from the spec. Web's "jargon" point is fair, but the spec owns this term. For the mode failure I take `AssignToImmutable`. It reads as a sentence and is easy to search for (Web). I do not object hard to `ImmutableAssign`.
>
> **Q2: Yes.** ParamAssign already has a name. A code costs one catalog row. Put all three in one block after E0610.
>
> **Q3: PLT's order.** Shape (`Ptr` step or temporary) wins, then parameter, then `let`. With this order, the first help is always the last fix the user needs.
>
> **Q4: I change to Q4-A, with a narrow inert set.** Sys shows that the hoist is always correct, so I no longer see it as extra cost. It is the general rule, and the direct form is only a shorter edit. Two limits:
> - Against **DevOps's operators**: Blink operators can dispatch to user trait impls, and user code can write the root. Inert means literal, name, or field path of names. Nothing else.
> - Against **Q4-C** (PLT): the "no step loads memory" check is a second analysis. It saves only a temp line in a rare FFI case, and the hoist is already correct there. PLT's negative test (plain `let p`, direct form) still holds under Q4-A when rhs is inert. Keep it.
>
> **Q5: I change to help-only for a module-level `let`.** Sys, PLT and AI/ML are right: adding `mut` adds `State` to every writer's effect row, far from the edit. Imported `pub let`: help with no fix, naming E1013 (DevOps). Destructured patterns, `for` variables and match bindings: help only.
>
> **Q6: I hold Q6-A, all errors at once.** In reply to Web, AI/ML and Sys:
> - The §3.6 rule exists so that programs the spec allowed keep working for one release. None of these programs was allowed.
> - A warning phase means codegen must keep emitting a write to an immutable binding for one more release. That is the miscompile PLT names: a closure's captured copy goes out of date, against the spec. We would maintain a known-wrong code path to protect code that was already wrong.
> - `mk().x = 5` silently drops the store today. A warning keeps a silent wrong result live.
> - `blink fix` is available on day one either way, so the error costs the user one command.
>
> **Other points:**
> - DevOps capture case: yes. A write inside a closure to a captured `let` is `AssignToImmutable`, with the label "captured here" and the fix at the `let`.
> - `blink fix` merges identical edits: yes, but put that as one line in the §8.6 tool rules, not in this decision.
> - Sys's non-atomic note on `op=`: accept. It costs one line and prevents a real FFI bug.
> - Tests: Sys's mid-path `s.p.f = v`, PLT's negative test, and DevOps's run-and-compare check for the hoist fix. All three.
> - Codes: E0611 to E0613, after E0610. PLT's E0603 to E0605 leaves a gap that gives no benefit.
>
> NOT STABLE. Only Q6 is still open (errors at once against warn-first). I am STABLE on Q1 to Q5 as stated above.

</details>

#### Phase C — Final vote

| Question | Result | Tally |
|---|---|---|
| Q1: how many codes, and which | Q1-B: widen E0610, add `NotAPlace` | 6-0 |
| Q2: ParamAssign gets a code now | Yes | 6-0 |
| Q3: order when more than one case applies | Shape first: `Ptr` step, temporary root, parameter, immutable binding | 6-0 |
| Q4: when the `.write` fix is machine-applicable | Q4-AC (Sys, Web, PLT, DevOps) vs Q4-A (AI/ML, Min) | 4-2 → Phase D |
| Q4 sub-vote: the inert set | inert-1 (DevOps: inert-2) | 5-1 |
| Q5: "add `mut`" on a module-level `let` | Help only | 6-0 |
| Q6: rollout | Q6-A: errors at once | 6-0 |
| Q7a–e: capture label, merge rule in §8.6, not-atomic note, tests, E0611 onward | Yes on each | 6-0 |

Each seat's ballot, verbatim:

##### Systems

> Sys Phase C ballot: Q1-B, Q2 Yes, Q3 shape-first, Q4-AC with inert-1, Q5-help, Q6-A, Q7a-e Yes.
>
> Q1. Vote: Q1-B. (If Q1-B loses, my preference is Q1-C with `AssignToImmutable`.)
> Reasoning: `xs.push(7)` and `xs = [7]` on a plain `let` are the same machine operation, a store into an immutable binding's storage. The compiler makes one check, root-binding mutability, and the user makes one fix, insert `mut`. Min's late objection is about `mut` parameters: E0610 accepts them for `mut self` calls, but `=` on any parameter is ParamAssign. The Q3 order handles this, because ParamAssign is decided before the mode check runs. So E0610 never sees a parameter root for `=`, and the rule text needs only one sentence that says so.
> Concern: if the widened §3.2.2 text does not state the parameter exception explicitly, an implementer can accept `a = 1` on a `mut` parameter as "mutable root".
>
> Q2. Vote: Yes.
> Reasoning: one catalog row, and a code lets `[lints]` set its level during its warn-first release (DevOps). The family should sit together in one run.
> Concern: none of substance.
>
> Q3. Vote: Q3-shape-first (Ptr step, then temporary root, then parameter, then immutable `let`).
> Reasoning: report the first premise that fails, so the help is a full fix. A `Ptr` write is legal with a plain `let` or a parameter, so "add `mut`" would only lead to a second error.
> Concern: a path with a `Ptr` step and a temporary root (`mk().p.f = v`) needs one fixed choice. Ptr wins, and the help is `mk().p.f.write(v)`, which is legal.
>
> Q4. Vote: Q4-AC, with inert-1.
> Reasoning: both the direct form and the hoist are exactly the §2.22 order, and at run time the hoist costs nothing (the C compiler already puts the rhs into a temporary). PLT's "no step loads memory" condition comes from the static type of each step: a field projection through a `Ptr` is address arithmetic, and a `Ptr`-typed field read is a load. It needs no second analysis. I drop my inert-2. With the hoist always available, a type-dependent inert set only buys a shorter edit, and Min and PLT are right that "inert" should be a purely syntactic, call-free test.
> Concern: AI/ML is right that under Q4-C a reader cannot always predict which form `blink fix` writes. If the panel picks Q4-A alone, the output is still correct.
>
> Q5. Vote: Q5-help. I agree with help-only, naming E1013, for imported `pub let`.
> Reasoning: a module `let mut` adds State to the effect rows of distant functions and can cause E0552 or E0651 errors far from the edit. A machine-applicable fix must never break code somewhere else.
> Concern: users may see help-only as the fixer being lazy, so the help text should say why: "this adds `State` to each function that writes it".
>
> Q6. Vote: Q6-A.
> Reasoning: today `xs = [...]` on a `let` and `mk().x = 5` produce wrong code without any error, and a module-`let` write from a function with no `State` in its row is a hole in the effect system. A warning release would keep that codegen path alive on purpose. `blink fix` ships the same fixes on day one either way.
> Concern: a downstream package that relied on the silent acceptance breaks in one step. The error must ship with its machine fix in the same release.
>
> Q7a. Yes. A captured copy is still the same binding, so the fix belongs at the `let`.
> Q7b. Yes. Put it as one line in the §8.6 tool rules (Min), because it applies to all fixes, not only these.
> Q7c. Yes. `p.f.write(p.f.read() + v)` is a load and a store, and FFI users who share memory with C threads need to know that.
> Q7d. Yes to all four tests.
> Q7e. Yes: E0611 onward, as one run.
> Concern for Q7: none of substance.

##### Web/Scripting

> Web Phase C ballot: Q1-B, Q2 Yes, Q3 shape-first, Q4-AC with inert-1, Q5-help, Q6-A, Q7a-e all Yes.
>
> **Q1. Vote: Q1-B.**
> Reasoning: For a JS or Python developer, `xs.push(1)` and `xs = [1]` on a plain `let` are the same mistake, and both have the same fix: add `mut`. With one name they get one search result and one quick fix. Min's objection is real: a `mut` parameter counts as a mutable root for a call but not for `=`. But the user never sees that difference, because a parameter root always reaches ParamAssign first (Q3). The temporary root and the Ptr step go to NotAPlace, as PLT argued. That corrects my Phase A placement.
> Concern: The widened §3.2.2 text must say that a `mut` parameter is a mutable root for `mut self` calls only. If it does not, readers will think `mut p: T` then `p = v` is legal.
>
> **Q2. Vote: Yes.**
> Reasoning: A diagnostic with no code cannot be searched for, filtered with `--only`, or set in `[lints]` during its warning release. One catalog row is a small cost.
> Concern: ParamAssign's warn-first rollout runs beside the errors-at-once rollout of its neighbors. That can confuse readers of the changelog unless the changelog says why.
>
> **Q3. Vote: Q3-shape-first.**
> Reasoning: A help must be the last fix the user needs. If we say "add `mut`" for `p.f = v` on a Ptr, the user's next build shows a second error, and that is the forum post we want to prevent.
> Concern: None that matters. All six agree that the Ptr step wins.
>
> **Q4. Vote: Q4-AC, with inert-1.**
> Reasoning: Q4-AC gives the clean direct form in the most cases. Real FFI code has a `let` or parameter Ptr root, so users seldom see a temp line. The hoist means `blink fix` never refuses for a reason the user cannot see. AI/ML is right that the syntactic inert test is easy to predict, and Q4-AC keeps that test as one of its two routes. For the inert set, I side with Sys, PLT and Min: `+` on a user type can run arbitrary code, so operators are not inert.
> Concern: Users and agents may not be able to predict when the hoist form appears. The docs need one sentence: "the fix uses a temp only when rhs can run code and the root is `let mut` or the path reads memory".
>
> **Q5. Vote: Q5-help.** No objection to help-only with E1013 for an imported `pub let`.
> Reasoning: A fix that breaks compilation in another file costs users more trust than a fix that is missing. Adding `mut` to a module `let` can add `State` to effect rows far from the edit.
> Concern: Users will ask why `blink fix` fixes a local `let` but not a module `let`, so the help must say why in one clause.
>
> **Q6. Vote: Q6-A.**
> Reasoning: This code was never valid, and today it gives raw C errors, an ICE, or silent wrong results. A warning release would keep those wrong results alive on purpose. Because every `let`-root case ships with a machine-applicable fix, migration costs one `blink fix` command.
> Concern: Users whose programs compile today, such as `xs = [...]` or `x += 1` on a `let`, will see a hard break with no warning. The release notes must tell them to run `blink fix`.
>
> **Q7a. Vote: Yes.**
> Reasoning: A write in a closure to a captured `let` is the same mistake, and the fix goes at the same `let`. The "captured here" label shows the user where the binding comes from.
> Concern: The label must point at the `let` line, not at the closure. Otherwise users add `mut` in the wrong place.
>
> **Q7b. Vote: Yes, as one line in the §8.6 tool rules (Min).**
> Reasoning: Duplicate `mut` inserts look like a bug to users. The rule applies to every fix, so it belongs with the general tool rules, not in this decision.
> Concern: The ticket for this decision must still test the merge, or the merge rule will go untested.
>
> **Q7c. Vote: Yes.**
> Reasoning: One line prevents a real concurrency bug in FFI code at no cost.
> Concern: The note must stay one line, or the help gets noisy.
>
> **Q7d. Vote: Yes, all four tests.**
> Reasoning: The order bug is easy to miss in review, and the run-and-compare test is the only one that proves `blink fix` keeps the program's behavior.
> Concern: None.
>
> **Q7e. Vote: Yes.**
> Reasoning: Adjacent numbers put the "left side of `=`" family next to each other in the catalog.
> Concern: None.

##### PLT

> PLT ballot, Phase C. Votes: Q1-B, Q2 Yes, Q3-shape-first, Q4-AC with inert-1, Q5-help, Q6-A, Q7a–e Yes (Q7b in §8.6).
>
> **Q1. Vote: Q1-B.**
> Reasoning: The mode premise of §2.22 ("the root is `let mut`") is the same judgment as E0610's "mutable root". So one widened rule gives one premise one code. Min's objection in round 1 does not break this. ParamAssign is a separate premise: "no assignment to a parameter". It holds whether or not the parameter is `mut`. A `mut` parameter root satisfies E0610, and ParamAssign rejects `=` on it on its own terms. The two rules compose, and "mutable root" keeps one meaning. The shape premise goes to `NotAPlace`.
> Concern: The widened §3.2.2 text could change the meaning of "mutable root" instead of stating ParamAssign as its own rule. The text must keep the two rules apart.
>
> **Q2. Vote: Yes.**
> Reasoning: ParamAssign is a named judgment that fails at compile time. A diagnostic with no code cannot be set under `[lints]` while it is a warning, and it breaks §8.6's `name`/`code` pair. One catalog row closes that gap.
> Concern: Its warning-first rollout must not leak into the codes in this decision, which are errors at once.
>
> **Q3. Vote: Q3-shape-first.**
> Reasoning: Report the first premise that fails, in the order shape, then parameter, then mode. Then each help is a full fix and never leads to a second error. Example: a `Ptr` parameter with `p.f = v` must get `.write`, not "copy it to a new name".
> Concern: An implementation that checks binding mode during name resolution, before it walks the path, will reverse this order without anyone seeing it. A test must pin it: a `let p: Ptr[S]` root and a `Ptr` parameter root must each give `NotAPlace`.
>
> **Q4. Vote: Q4-AC, inert set inert-1.**
> Reasoning: Each of the two conditions is enough on its own for the direct rewrite to keep §2.22 order:
> - inert-1: nothing in rhs can run code.
> - Root not `let mut` and no load in the path: nothing can change what the receiver reads. This follows from the binding rules this decision enforces.
> The hoist always writes out §2.22 order, so it is sound for any rhs in statement position. Against inert-2 and inert-3: an operator on a user type is an ops-trait call, and a "primitive operand" test makes "inert" depend on types. Keep "inert" syntactic.
> Concern: The "no step loads from memory" test is the subtle part. If an implementer misjudges a `Ptr`-typed field mid-path as address arithmetic, the direct form becomes unsound. So the test set must include a path that loads.
>
> **Q5. Vote: Q5-help.**
> Reasoning: §4.16 puts `State` in the row of each reader of a module `let mut`. Adding `mut` can therefore cause E0552 on a `pub` reader, E0651 at a spawn, or a closure that no longer fits `fn() -> T`, all far from the edit. A machine-applicable fix must keep the program well-typed everywhere else. I agree that an imported `pub let` gets help only, naming E1013.
> Concern: Users may see that the fix is missing at module level and add `mut` by hand. They then get the errors somewhere else, and the help text does not warn them.
>
> **Q6. Vote: Q6-A.**
> Reasoning: A warning release must give these programs a meaning, and that meaning is unsound:
> - A module write with no `State` in the row is a hole in the effect system and a hidden write set.
> - An immutable capture copied by value goes out of date, against the spec.
> The §3.6 warn-first rule protects only programs the spec allowed. ParamAssign keeps its own rollout.
> Concern: Code in the wild that relies on `xs = [...]` running today breaks in one release. The machine-applicable `mut` fix must ship in the same release.
>
> **Q7.**
> - Q7a: Yes. A closure's write to a captured immutable `let` fails the same mode premise. Label it at the capture and put the fix at the `let`.
> - Q7b: Yes. Put it as one line in the §8.6 tool rules. Merging identical edits is a property of `blink fix`, not of this diagnostic.
> - Q7c: Yes. `p.f.write(p.f.read() op v)` is a load and then a store, and the note costs one line.
> - Q7d: Yes, all four tests. The closure that reassigns the root must get the hoist form, and the plain `let p` root with the same rhs must get the direct form. Also add a path that loads mid-path, which must get the hoist form.
> - Q7e: Yes. E0611 onward, as one run.
> Concern: Q7d does not yet require a test for the Q3 order when a `Ptr` parameter is the root. Add that test.

##### DevOps

> DevOps Phase C ballot: Q1-B, Q2 Yes, Q3 shape first, Q4-AC with inert-2, Q5 help only, Q6-A, Q7a–e all Yes (Q7b goes in §8.6).
>
> **Q1. Vote: Q1-B.**
> Reasoning: The name is the key for `blink fix --only` and for LSP code actions. `xs.push(1)` and `xs = [1]` on a plain `let` give the same edit at the same span ("insert `mut` at line N"). One name gives one quick-fix provider, and one `--only` pass repairs both. Min's objection (a `mut` parameter is a mutable root for calls but not for `=`) never reaches the user. By the Q3 order, ParamAssign fires before E0610 on any parameter root, so E0610 for `=` only ever sees `let` roots. If Q1-B loses, my second choice is Q1-C with `AssignToImmutable`.
> Concern: the widened §3.2.2 text must say plainly that a `mut` parameter is a mutable root only for a `mut self` call, or the catalog row will read as two rules.
>
> **Q2. Vote: Yes.**
> Reasoning: ParamAssign ships first as a warning. A warning with no code cannot be set under `[lints]` or filtered by code in CI, so it needs its code now.
> Concern: the code must stay stable when the warning becomes an error. The JSON `name`/`code` must not change at that step.
>
> **Q3. Vote: Q3-shape-first** (Ptr step, then temporary root, then parameter root, then immutable `let`).
> Reasoning: The first fix that `blink fix` applies must be the last fix needed. Under any other order, a Ptr parameter gets "copy it to a new name" or "add `mut`", and the next run gives a second error.
> Concern: the checker must find all the failing premises before it picks one, or a fast path will report the mode error first.
>
> **Q4. Vote: Q4-AC, with inert-2.**
> Reasoning: I withdraw inert-3. Sys and PLT are right that `+` on a user type dispatches to an ops-trait impl that can write Ptr memory, so inert-3 is not sound. inert-2 keeps `p.len = n + 1` on the direct form, and that is the common FFI line. PLT's route gives the direct form for nearly all `let p`/parameter code. Both routes are sound, and the hoist stays as the general fallback. Against Q4-B: help-only for complex rhs pushes humans and agents to the naive hand rewrite, which is the wrong-order bug (AI/ML).
> Concern: users and agents cannot see from the text which form the fixer will write (AI/ML's point). The spec must give the rule as a short list, and the tests must pin each route.
>
> **Q5. Vote: Q5-help.** I agree with the imported `pub let` rule: help only, naming E1013.
> Reasoning: Adding `mut` at module level adds `State` to every writer's effect row and can break type checks in other files (E0552, closure types, E0651 at a spawn). A machine-applicable fix must never cause new errors outside its own edit.
> Concern: the help must say why there is no fix, or users will think the tool is broken.
>
> **Q6. Vote: Q6-A.**
> Reasoning: These programs were never valid. A warning release means keeping wrong codegen live on purpose: a stale captured copy, writes to module state with no `State` in the row, and silently lost stores to temporaries. `blink fix` has the `mut` fix on day one, so the migration cost is one command.
> Concern: a user who upgrades gets errors in code that "worked". The CHANGELOG must name the change and say "run `blink fix`".
>
> **Q7a. Vote: Yes.**
> Reasoning: The capture is a write to the same immutable root. The "captured here" label shows why the closure body is involved, and the fix goes at the one `let`.
> Concern: the label span must point at the capture use, not the closure head, or the LSP highlight is confusing.
>
> **Q7b. Vote: Yes. The rule goes as one line in §8.6 (Min).**
> Reasoning: Merging identical edits is a property of every machine-applicable fix, not only this one. Under Q1-B, a `push` and an `=` on one root both emit the same insert, so the general rule is needed.
> Concern: two different edits that overlap must still be reported as a conflict, not merged.
>
> **Q7c. Vote: Yes.**
> Reasoning: It costs one line, and it stops a real FFI bug (a read-modify-write on shared memory).
> Concern: the note must stay one line and must not imply that Blink offers an atomic form it lacks.
>
> **Q7d. Vote: Yes, all four.**
> Reasoning: The run-and-compare `blink fix` test is the only one that proves the fix keeps behaviour. The others check which fix form is chosen. Each Q4 route needs its own test.
> Concern: the round-trip test must run the fixed program and compare its output; checking only the edited text is not enough.
>
> **Q7e. Vote: Yes.**
> Reasoning: A contiguous run after E0610 puts the family in one place in ERROR_CATALOG.md and in `blink explain` listings.
> Concern: none of note. Under Q1-B the run is only two codes (NotAPlace, ParamAssign).

##### AI/ML

> AI/ML Phase C ballot.
>
> Q1: Vote Q1-B.
> Reasoning: Agents fix errors by mapping the name to an edit. `xs.push(1)` and `xs = [1]` on a plain `let` have the same edit, so one name (E0610) is the cleanest key, and agents already meet E0610 on `push`. Min's objection is real: a `mut` parameter is a mutable root for calls but never for `=`. But with shape-first precedence, ParamAssign takes every parameter root before E0610 runs, so the agent still gets one name per fix. NotAPlace covers the Ptr step and the temporary root, which both mean "rewrite the statement". If Q1-C wins, I pick `AssignToImmutable` (it reads as a sentence, and models search for it).
> Concern: The widened §3.2.2 text must say plainly that a `mut` parameter is a mutable root only for a `mut self` call, or models will learn that `fn f(mut a) { a = 1 }` is legal.
>
> Q2: Vote Yes.
> Reasoning: With a stable code, an agent can match on the JSON `name`/`code` with no special case, and `[lints]` can name it during its warning release. One catalog row is a small cost.
> Concern: The code must not change when ParamAssign moves from warning to error, or fix scripts break.
>
> Q3: Vote Q3-shape-first (Ptr step, then temporary root, then parameter, then immutable `let`).
> Reasoning: An agent applies the help, then compiles again. If the first help is not a complete fix, the agent loops. Shape-first means the first help is always the last fix needed, for example `fn f(p: Ptr[S]) { p.f = 1 }` gets `.write`, not "copy the parameter".
> Concern: An implementation that checks binding mode during name resolution, before it knows the path types, can report the wrong error first, so we need a test for each pair of overlapping cases.
>
> Q4: Vote Q4-A. Sub-vote inert-1.
> Reasoning: The choice between the direct form and the hoist must be visible in the source text, so that a model reading `blink fix` output can learn the rule. Q4-C/AC make the choice depend on the binding mode and on memory loads, which a reader cannot see from the line. I withdraw my round 1 support for operators (inert-3): Sys, PLT and Min are right that `+` on a user type dispatches to code that can write the root. Inert-1 is purely syntactic. Any other rhs gets the hoist, which is always correct and is the form an agent should copy when it writes the code by hand.
> Concern: The hoist will appear for common lines such as `p.f = n + 1`, and users may see that as noise. I accept that cost to keep the rule easy to predict.
>
> Q5: Vote Q5-help. I do not object to imported `pub let` being help only with the E1013 note.
> Reasoning: A machine-applicable fix must never create errors in other places. At module level, `mut` adds `State` to effect rows far from the edit, which can set off E0552 or E0651. Agents trust `fix` edits without checking them, so the fix must be safe to apply blindly.
> Concern: Agents may still copy "declare it `let mut g`" from the help without reading the State note, so the help must name the effect-row cost in one line.
>
> Q6: Vote Q6-A.
> Reasoning: These programs were never valid. Some are silent miscompiles today (`xs = [...]`, the store to `mk().x` that gets dropped). Agents ignore warnings, so a warning release keeps wrong code in circulation and in training data for one more cycle. `blink fix` ships on day one, so the cost to users is one command.
> Concern: Users whose builds break on upgrade will not know about `blink fix`, so the CHANGELOG entry must name the command.
>
> Q7a: Yes. A captured `let` is still the same binding, and the fix goes at the same `let`, so the same name keeps one name per fix.
> Q7b: Yes. Put it as one line in the §8.6 tool rules, because merging identical edits is a general `blink fix` rule, not specific to this decision.
> Q7c: Yes. One line stops agents from treating `op=` through a Ptr as atomic in concurrent FFI code.
> Q7d: Yes to all four tests. The `blink fix` round-trip test is the most important one from my side: it proves the output we train on keeps the program's behaviour the same.
> Q7e: Yes. The codes take E0611 onward, in one run.
> Concern for Q7: none beyond the one I give under Q1.

##### Minimalism

> **Min — Phase C ballot**
>
> **Q1: Q1-B** (widen E0610, and add `NotAPlace` for a Ptr step and a temporary root)
> Reasoning: In round 1 I left M1 because E0610 accepts a `mut` parameter as a root and `=` never does. PLT and AI/ML showed that the Q3 order fixes this. ParamAssign is checked before E0610, so E0610 on `=`/`op=` can only fire on a `let` root. The widened text needs one clause, "for `=` and `op=`, a parameter root is ParamAssign". Then "a mutation needs a mutable root" is one rule with one fix, `push` and `=` share one name, and that name already exists. Fewer codes and no new concept is the subtraction result.
> Concern: E0610's current message ("cannot call mutating method") and its `blink explain` text speak only of method calls, so both must be rewritten. If they are not, users who hit `x = 2` will see wrong text.
>
> **Q2: Yes**
> Reasoning: The name already exists, and a code costs one catalog row. DevOps is right that a warning without a code cannot be set under `[lints]` during its warn-first release.
> Concern: Its number lands after `NotAPlace`, so the catalog order does not follow precedence order. This is cosmetic.
>
> **Q3: Q3-shape-first** (Ptr step, then temporary root, then parameter, then immutable `let`)
> Reasoning: The first help must be the last fix. Any other order can tell the user "add `mut`" for a line that `mut` does not fix. This order is also what makes Q1-B sound.
> Concern: An implementer can check mode before shape for speed, which can give two diagnostics or the wrong one. Tests must pin each pair of failures.
>
> **Q4: Q4-A, with inert-1**
> Reasoning: The hoist is always sound and the direct form is only a shorter edit, so one syntactic test is enough. The test must be visible in the source (AI/ML's point). Q4-C/AC adds a second analysis ("does any step load memory?") only to drop one temp line in rare FFI code. Operators (inert-2, inert-3) can dispatch to user trait impls. inert-2's "primitive operands" needs type facts inside a test that should be pure syntax.
> Concern: A `let p` root with a call rhs gets a hoist line that a reader thinks is not needed. That is ugly, but it is correct.
>
> **Q5: Q5-help.** I agree with help only for an imported `pub let`, naming E1013.
> Reasoning: Adding `mut` at module level adds `State` to every writer and can break type checks in other files (PLT: E0552, closure types). A machine-applicable fix must never create errors far from the edit.
> Concern: Users can see help-only as inconsistent next to the local `let` case, so the note must say why.
>
> **Q6: Q6-A**
> Reasoning: The §3.6 warn-first rule protects code the spec allowed, and none of this code was allowed. A warning release would force codegen to keep giving meaning to writes that break capture-by-copy and effect rows (PLT) for one more release. That means maintaining a known-wrong path that we must then delete.
> Concern: Some user code that runs today stops building on upgrade. The release notes must say that `blink fix` repairs it in one command.
>
> **Q7**
> - **Q7a: Yes.** A capture is still the same root and needs the same fix. The "captured here" label costs one label. Concern: none of weight.
> - **Q7b: Yes, as one line in the §8.6 tool rules.** It is a general `blink fix` property, not a rule of this diagnostic. Concern: if the rule lives only in this decision, other diagnostics will not follow it.
> - **Q7c: Yes.** One line that prevents a real FFI race. Concern: none of weight.
> - **Q7d: Yes, all four.** Each one checks a different claim this decision makes. Concern: the round-trip test needs the `blink fix` machinery to exist, so it can lag behind the diagnostic.
> - **Q7e: Yes.** One run in the catalog. Concern: none of weight.

#### Phase D — Round 2 (Q4 only)

Q4 split 4-2 in Phase C, so the panel ran one focused round on it. In the debate, Systems and PLT moved to Q4-A; Web and DevOps held Q4-AC, which made it 3-3. In the final silent vote all six chose Q4-A with inert-1.

##### Debate replies, verbatim

- **Systems:**

> Sys Phase D, Q4: I move to Q4-A (inert-1).
>
> Q4-A's strongest point comes from AI/ML and Min: the choice of form must show in the source text. PLT's own concern makes it stronger. The "no step loads memory" test is the only part of the rule that can be unsound, because one misjudged Ptr-typed field in the middle of a path gives a wrong-order direct rewrite. The gain from Q4-AC is one fewer source line. From the machine's view the gain is zero: I argued myself that the C output and the run-time cost of the hoist are the same. A second analysis that only changes how the edit looks, and adds a way to be unsound, does not pay for itself. Q4-A cannot be wrong. Its worst case is an extra `let`.
>
> I hold one point: tests still pin the direct form for an inert rhs and the hoist for a closure rhs that reassigns the root.

- **Web/Scripting:**

> Web Phase D on Q4: I hold Q4-AC.
>
> The strongest point for Q4-A (AI/ML, Min) is that a reader can see from the source line which form the fix will write. My answer: users read the fix output, not the rule. Under Q4-A, the most common FFI line, `p.len = n + 1` on a parameter, becomes two lines with a temp name. Every user sees that noise. Only a few users ever ask why. The "root" half of Q4-AC is visible too: `let p` or a parameter, against `let mut p`. The only part a reader cannot see is "does a path step load memory?". That part is rare, and when it is in doubt the fix falls back to the hoist, which is always correct. Both options are sound, so the choice is about output quality, and Q4-AC writes the shorter correct edit more often.
>
> I would accept Q4-A without objection, but I vote Q4-AC.

- **PLT:**

> PLT, Phase D on Q4: I move to Q4-A with inert-1.
>
> The strongest point for Q4-A is the one from AI/ML and Min: the choice of form must be visible in the source. I add a soundness reason for the same answer. Under Q4-AC, only the second route ("root not `let mut`, no load in the path") can produce an unsound fix. It depends on type facts (is this `Ptr`-typed step a load?), and my own Phase C concern was that an implementer can get that wrong. Under Q4-A, an error in the gate has a worst case of one extra line from the hoist. It can never change evaluation order.
>
> A gate for a machine-applicable fix should depend on as little as possible. Inert-1 is purely syntactic, and the hoist is the §2.22 order written out. The cost is one temp line on lines like `p.f = compute()`, and correctness costs nothing more. Route (b) saves only that line, and it adds the one way the fix could go wrong.
>
> I move to Q4-A.

- **DevOps:**

> DevOps Phase D, Q4: I hold Q4-AC.
>
> The strongest Q4-A point (AI/ML, Min) is that the reader cannot predict the form from the line alone. My answer:
> 1. The output is deterministic in both options, so golden tests and agents see the same text for the same program.
> 2. Under Q4-AC, each direct-form edit is one where the naive rewrite really is correct. Agents learn no wrong rewrite. They learn "hoist unless the root cannot change", which is the true rule.
> 3. The input is not hidden. "Root is `let mut`" is visible at the declaration, and the LSP hover shows it. The load test comes from the static type of each step (Sys).
> 4. Now that inert-1 has won, `p.len = n + 1` on a plain `let p` gets a temp line under Q4-A. That is the most common FFI store. A fix that adds a line users think is useless gets reverted by hand, and that is where the order bug comes back.
>
> Q4-A is still sound. I will accept it if it wins.

- **AI/ML:**

> AI/ML Q4: I move to Q4-AC, with inert-1.
>
> The other side's strongest point is Web's and PLT's. Real FFI code almost always has a `let` or parameter `Ptr` root. Under Q4-A, `p.f.write(v)` gets a hoist line in front for every call rhs, so the hoist form fills `blink fix` output and, in time, training data. Models would learn the hoist as a habit. Under Q4-AC, most code is the idiomatic direct form.
>
> My predictability objection is weaker than I said. The second route depends on two facts. The root's mode is in the `let` or in the signature. Whether a path step loads follows from field types. Both are in the source, and a model can learn them.
>
> My condition for moving: the spec gives the rule as a two-item list, and tests pin each route. That includes PLT's path that loads through a `Ptr`-typed field mid-path, so that an implementer error cannot make the direct form unsound.

- **Minimalism:**

> **Min — Phase D, Q4: I hold Q4-A.**
>
> The strongest point for AC is from Sys and Web. The load test reads only the static type of each step. Real FFI code has a `let` or parameter root, so users seldom see a temp line.
>
> My answer: the cost is not compute time, it is risk. Under Q4-A, the worst bug the fixer can have is an extra line, and the output is still correct. Q4-AC adds a second soundness argument. PLT's own concern names how it fails: if the fixer judges a `Ptr`-typed field in the middle of a path as address arithmetic, it writes the wrong-order store. That is the exact bug this decision exists to prevent, and `blink fix` would write it silently. That is not a fair trade for one less temp line.
>
> AC also makes the output depend on facts a reader cannot see in the line (AI/ML).
>
> If AC wins, I accept it, on one condition: a test that pins a path that loads.

##### Final votes, verbatim (6-0 Q4-A, inert-1)

- **Systems:**

> Sys final Q4 vote: Q4-A, inert-1.
>
> Reasoning: The fix gate should rest on the smallest thing that cannot go wrong. Under Q4-A, any bug in that gate costs one extra line. Under Q4-AC, a misjudged load in the middle of a path silently writes the wrong-order store this decision exists to prevent. DevOps argues that users will revert the hoist by hand, but that does no harm here: on a `let p` or parameter root, which is the case they name, the hand-reverted direct form is still correct, so the revert does not bring the bug back. The run-time cost and the C output are the same either way, so the only thing Q4-AC buys is how the edit looks.
>
> Concern: the hoist line on common `p.len = n + 1` stores (now that inert-1 has won) may read as noise, and that adds pressure to widen the gate later without the same care.

- **Web/Scripting:**

> Web Phase D Q4 final vote: Q4-A, inert-1. I move.
>
> Reasoning: PLT and Sys changed my mind. The author of route (b) and the systems panelist both say the "no step loads memory" test is the one place where the fixer can be wrong. If it is wrong, `blink fix` silently writes the wrong-order store that this decision exists to prevent. From the DX view, a fix that is silently wrong does much more harm than a fix that adds one line, because users trust machine-applicable edits and do not review them. Under Q4-A the worst case is an extra `let`. The extra line is a real cost, but it costs readability, not correctness.
>
> Concern: DevOps is right that users may hand-revert the temp line to `p.f.write(compute())` and so bring the order bug back. The help or the §2.22 docs must give the reason in one sentence: "rhs runs before the root is read".

- **PLT:**

> PLT, final Q4 re-vote. Vote: Q4-A, inert-1.
>
> Reasoning: A gate for a machine-applicable fix should hold on the smallest base it can. Under Q4-A, a bug in the gate can only add one line, and it can never write a store in the wrong order. Q4-AC adds a second argument for the direct form, and that argument relies on the fixer judging each Ptr-typed step correctly. If that judgment is wrong, `blink fix` silently writes the exact bug this decision exists to prevent. DevOps says users will undo the temp line by hand. That is a real point, but it is a style cost that sits with the user. The other option is a soundness failure inside the tool, which the user cannot see.
>
> Concern: The hoist line on common FFI stores (`p.len = n + 1` on a plain `let p`) may read as noise, and people may undo it by hand. The note on the fix should say in one line why the temp is there: "the right side runs before `p` is read".

- **DevOps:**

> DevOps Phase D final, Q4. Vote: Q4-A (inert-1). I move.
>
> Reasoning: PLT's and Min's risk argument decides it for me as the tooling voice. The worst failure of a tool is a machine-applicable fix that silently changes behaviour, because after one such fix users stop running `blink fix` unattended. Under Q4-A, any bug in the gate costs one extra line. Under Q4-AC, a misjudged `Ptr`-typed step writes the exact wrong-order store this decision exists to stop. Q4-A is also the safe direction to grow in: route (b) can be added later, after tests and real use, as a pure relaxation. Removing it later would change `blink fix` output that people already rely on.
>
> Concern: the hoist line on common FFI stores (`p.len = n + 1` on a plain `let p`) will look like noise, and some users will collapse it by hand into the naive form. The help text should show the hoist and not the bare direct form.

- **AI/ML:**

> AI/ML final Q4 vote: Q4-A (inert-1).
>
> Reasoning: Sys and PLT, who wrote the route (b) condition, now say it is the only part of the rule that can be unsound. Their reason is new to me: one misjudged `Ptr`-typed step mid-path makes `blink fix` silently write the wrong-order store. A silently wrong fix is the worst output for training data, because models copy it as correct, and no test from the user's side shows it. An extra hoist line is noise, but it is always correct, and I weigh correctness above how the output looks. So I move back to Q4-A.
>
> Concern: Common lines such as `p.len = n + 1` on a parameter get a temp line, so users and agents may undo the hoist by hand. The §2.22 docs should say in one sentence when the direct form is also safe.

- **Minimalism:**

> **Min — Phase D re-vote, Q4**
>
> **Vote:** Q4-A, inert set inert-1.
>
> **Reasoning:** A machine-applicable gate should rest on the fewest facts that can be wrong. Inert-1 is pure syntax. Every other rhs gets the hoist, which is the §2.22 order written out. So the worst bug the fixer can have under Q4-A is one extra line. It can never change evaluation order. DevOps says users will undo the hoist by hand. That edit is the user's own choice, and its risk is the same under either option. It does not justify a second route that lets the tool itself write an unsound store.
>
> **Concern:** The temp line on common FFI stores such as `p.len = n + 1` may read as noise. The `blink explain` text must say in one line why the fix keeps it.

### Final Spec

```blink
@trusted(audit: "POLL-1")
fn demo(p: Ptr[PollFd], c: Ptr[Counter]) {
    let n = 0
    n = 1                    // error[MutationRequiresMut] (E0610): fix inserts `mut` at `let n`
    p.revents = 0            // error[NotAPlace] (E0611): fix `p.revents.write(0)`
    p.events = next()        // error[NotAPlace] (E0611): fix `let events = next()`, then `p.events.write(events)`
    c.hits += 1              // error[NotAPlace] (E0611): help `c.hits.write(c.hits.read() + 1)`, not atomic
    mk().count = 5           // error[NotAPlace] (E0611): help, bind it first
}

fn bump(n: Int) {
    n = n + 1                // error[ParamAssign] (E0612)
}
```

- One diagnostic per assignment. Order: `Ptr` step, temporary root, parameter root, immutable binding.
- `NotAPlace` covers the shape cases; E0610 covers the mode case for calls and assignments alike.
- The direct `.write` fix needs an inert `rhs` (literal, name, field path of names). Otherwise the fix binds `rhs` first, because a method call reads its receiver before its arguments.
- A machine-applicable fix never edits a module-level binding.
- Errors at once; `ParamAssign` warns first, and keeps E0612 when it becomes an error.
- Spec: §2.22 *Writes that are not to a place*, §3.2.2 *Construction and Mutability*, §3.6 *Mutable Parameters*, §8.6 *Applying fixes*, §9.1.3 *Field access on `Ptr[@ffi.struct T]`*, ERROR_CATALOG.md.
