[< All Decisions](../DECISIONS.md)

# @ffi Rows for fd-Table and Process-Control Calls — Design Rationale

**Question.** Which effect row do the `@ffi` decls for `pipe`, `dup`, `dup2`, `fcntl`, `close`, `flock`, `setpgid` and `lseek` take?

**Answer.** The row of the call that made the fd. fd 0, 1 and 2 count as made by `IO.Read`, `IO.Print` and `IO.Log`. `pipe`, `memfd_create` and `socketpair` take `State`. `dup2` takes the union of the rows of both fds. `flock` adds `FS.Write`. `setpgid` takes `Process.Spawn`. The `E0538` and `E0802` help name `State` as a choice. No new effect, no new leaf, no new code and no new warning.

### Panel Deliberation

Six seats voted: Systems, Web/Scripting, PLT, DevOps/Tooling, AI/ML and Minimalism. The quotes below come from the seats' own replies. Where a quote has a "[...]", the text there was a ticket reference or was cut. No Phase D ran.

#### Phase A — Independent proposals

- **Systems**: "an fd op takes the row of what the fd names, plus the extra resource the op itself touches"
- **Web/Scripting**: "One rule a JS/Python dev can learn in a minute, and it already matches §4.4.6 (socket close is the socket's row)"
- **PLT**: "A descriptor op's row = (the effect of each outside resource whose state it changes or reveals) + `State` for the process fd table."
- **DevOps/Tooling**: "one rule an author can apply from the audit text alone, plus one help-text change. No new error code; one optional lint."
- **AI/ML**: "one rule, "a descriptor op takes the row of the calls that made its descriptors""
- **Minimalism**: "No new effect, no new leaf, no new diagnostic, no per-C-function table."

The four points all six proposals shared are S1 to S4 in the AG block below.

#### Phase B — Debate highlights

Phase B ran one round. All six seats replied "stable". The points D1 to D6 of that round are Q1, N, Q2, Q3, Q4 and Q5/Q6 below. No seat objected to S1 to S4.

- **Systems** (Q1): "I move from D1-U to D1-T, without the State floor (see D2)."
- **Web/Scripting** (Q1): "I move from D1-P to D1-T (by target fd)"
- **PLT** (Q1): "I accept S1 as written: using a handle charges the handle's row, which is §4.4.6. That moves me on D1, D2 and D3."
- **DevOps/Tooling** (Q1): "I move to the mechanical rule on D1–D4."
- **AI/ML** (Q1): "D1-U adds no rule. It is S1 applied to every fd argument of the call."
- **Minimalism** (Q1): "I am changing three of my Phase A positions (D1, D3, D4). The reason is the same each time: S1, which all six of us signed, already gives those rows."

#### Phase C — Final vote

Every question passed 6-0. A seat marked "round 1" voted otherwise at the end of round 1 and changed.

##### Q1. dup2 — U (6-0)

U: the union of the rows of both fds' makers; fd 0/1/2 count as made by `IO.Read`/`IO.Print`/`IO.Log`. T: by the target fd only.

- **Systems** — U (round 1: T). "In round 1 I was for T, on the ground that dup2 does no I/O on the source. plt's leak point beats that. After dup2(logfd, 1), every later print is a write to that file, so the function that set this up must hold FS.Write. Under T, IO.Print alone covers it. U is S1 applied to each fd argument, with no "only the target counts" rule. That rule would need a per-function answer for dup3, splice and sendfile. The over-claim on the source costs callers nothing, because they paid that row at open. Rows are erased, so the codegen is the same." Concern: "wide union rows on shared dup2 decls may push authors to leave rows loose instead of splitting decls per fd kind."
- **Web/Scripting** — U (round 1: T). "I move from T. It is my own Q2 vote that forces it: under M, dup(fd) takes the source fd's maker row, so a T rule for dup2 that ignores the source would be the one fd op exempt from S1. A JS dev learns one sentence: "copy the row of the decl that made each fd you pass; fd 0/1/2 were made by IO.Read/IO.Print/IO.Log". The extra FS row costs callers nothing, because they opened the source fd." Concern: "build_fs callers may see IO.Print, IO.Log appear on fork/exec wrappers, and some will ask why spawning a child "prints". The writer should show the pre-exec child example, so the over-claim reads as intended."
- **PLT** — U. "U and M are the same rule. web takes M because `dup(1)` makes a second handle to stdout, and a write through it is a print. By the same argument, `dup2(logfd, 1)` makes fd 1 a second handle to the log file, so every later print is an FS.Write through that handle. T gives dup the maker's row (Q2 M) but leaves the source maker's row off dup2, so T contradicts the rule the panel is about to pass. sys's "charge at acquisition" argues against S1 itself: close on a read fd does no I/O on the file either. Under T, a function holding only IO.Print can point stdout at any file fd it is handed, and the FS row then stays off the function that set up the writes." Concern: "the FS rows on dup2 spread into every build_fs/daemon caller of the redirect, and authors may answer by writing one wide decl rather than splitting by kind."
- **DevOps/Tooling** — U. "The reviewer's check is one lookup per fd argument: find the decl that made it and copy its row. T needs a second rule ("for dup2 only the target counts"), and it repeats for every two-fd call (dup3, splice, sendfile, copy_file_range). The extra FS row costs callers nothing, because they opened the source fd. U also makes the function that sends prints into a file hold FS.Write, which is what a sandbox reviewer wants to see." Concern: "build_fs rows get wider, and authors may start to treat wide rows as noise and stop reading them."
- **AI/ML** — U. "U is S1 applied to every fd argument, so a model copies each maker's row and adds no rule. T needs one more rule ("for dup2 only the target counts"), and a model then has to learn which argument counts for each two-fd call (dup3, splice, sendfile, copy_file_range). That is the per-name lookup that S1 removed. The extra FS row costs nothing, because the caller already holds it from the open." Concern: "readers may take the FS rows on dup2 to mean that dup2 does file I/O, so the spec example should say they come from the source fd's maker."
- **Minimalism** — U. "dup2 is a dup of `from` plus a close of `to`. If Q2 gives dup its maker's row (M) and S1 gives close its maker's row, the union is just those two rules added together, with nothing extra. T needs one more rule: "for dup2 only the target counts, and the source's charge was paid at open". The same Deno-style argument (charge at acquisition) would also take the row off close, and all six of us rejected that under S1. Callers lose nothing, because whoever opened the source already holds its FS row." Concern: "build_fs callers get wider rows (FS.Read, FS.Write, IO.Print, IO.Log on dup2). Readers may take that union to mean dup2 itself writes files."

##### Q2. `dup` and `fcntl(F_SETFD)` — M (6-0)

M: the maker's row. S: `State`.

- **Systems** — M (round 1: S). "plt showed that my "table-only" split does not hold at the OS level. dup(1) adds a reference to stdout's open file description, so the reader gets no EOF when fd 1 closes. That effect lands on the resource stdout names. Close is "table-only" in the same sense, and all six seats charge close the maker's row. So D3-S was an exception that did not match what the kernel does." Concern: "authors may write the maker's row by habit on a call that really needs a second leaf, and nothing will flag the under-claim."
- **Web/Scripting** — M. "this is S1 as all six signed it. The "table only" carve-out (S) asks every author to sort calls into table-only and touches-the-resource, and sys showed that close does not sort cleanly. One rule gives fewer Stack Overflow questions than a sorted list." Concern: "`daemon_dup ! IO.Print, IO.Log` over-claims for a call that changes no output, and a reader may take it as a sign that dup prints."
- **PLT** — M. "this is S1 applied as written. An op on an fd takes the maker's row, so a decl's row comes only from the fd's origin, which makes rows compose. "Only the table slot" is the State-floor way of thinking I withdrew. It would also exempt close on a read fd, and all six seats agree to charge that. An extra reference is something other code can see: a dup'd stdout keeps the reader's pipe open, so the reader gets no EOF." Concern: "an `fcntl` decl whose audit lists many fd kinds gets a wide union row, unless authors split it per cmd and per kind."
- **DevOps/Tooling** — M. "Under M, S1 holds with no "table-only op" carve-out. Close passes the same table-only test, and all six of us charged it the maker's row. A carve-out is a sort step that the audit text cannot settle without judgment." Concern: "daemon_dup's `IO.Print, IO.Log` over-claims for a call that prints nothing, and a reader may think it writes to stdout."
- **AI/ML** — M. "under S, a model has to sort calls into "table only" and "acts on the resource". sys's Phase A showed that this sort is unreliable, because close looks table-only but is not. Under M, every op on an fd is S1 with no exceptions, so the long tail (fchmod, ftruncate, fstat) has a row a model can derive." Concern: "authors will write the wide fcntl decl ("any cmd") with only the maker's row. The writer notes should say that an fcntl cmd with an effect of its own (F_SETLK) adds that leaf, as flock does."
- **Minimalism** — M. "S1 says "any op on an existing fd". S keeps a split between "table-only" ops and "resource" ops, which is a judgment made per C function, and close fails that test as well. M is S1 as written, so no list of C calls exists that a user or a model must learn. dup(1) makes a second handle to stdout, so `IO.Print, IO.Log` is a true upper bound." Concern: "authors will argue in review over whether a given fcntl cmd "acts on the resource". Under M the answer is always yes, and some will see that as over-claiming."

##### Q3. `flock` — MW (6-0)

MW: the maker's row plus `FS.Write`. W: `FS.Write` only.

- **Systems** — MW (round 1: W). "FS.Write is the part that matters: other processes see the lock, and a read-only capability must not be able to stall writers. All options keep it. Adding the maker's row costs nothing, because the caller opened the fd with FS.Read, and it keeps flock inside S1 with no carve-out." Concern: "none of substance. In src the row is the same in practice."
- **Web/Scripting** — MW. "this is S1 plus the op's own leaf, with no special case. The FS.Read is free, because the caller opened the fd. FS.Write is the line that matters: a read-only capability must not be able to stall other processes." Concern: "none of substance. Authors may drop the FS.Read by habit, which is a harmless under-statement of an already-held row."
- **PLT** — MW. "S1 gives the maker's row, and FS.Write accounts for the lock that other processes see. The rule needs no exception. W makes flock the one fd op outside S1. MW costs callers nothing, since they already hold FS.Read from the open." Concern: "none of substance. W would also be sound, only less regular."
- **DevOps/Tooling** — MW. "MW is S1 plus the op's own leaf, the same formula as U, with no exception. FS.Write is the part that matters: a read-only sandbox must not be able to stall another build. Every variant keeps it, and the FS.Read is free." Concern: "none in practice. The rows of src callers do not change."
- **AI/ML** — MW. "one formula covers flock and dup2: the makers' rows plus the op's own leaf. W needs a "replaces" clause that applies to no other op. The FS.Read changes nothing for callers in src." Concern: "none of substance. FS.Write, the part that matters, wins either way."
- **Minimalism** — MW. "this is S1 plus the one leaf flock adds (a lock other processes see is a write). Callers pay nothing for it, because FS.Read was already held at open. W would need a rule that says the op's own leaf replaces the maker's row, and nothing else in the ruling works that way." Concern: "none of substance. The row is one leaf wider than sys's W, and both are sound."

##### Q4. `setpgid` — SP (6-0)

SP: `Process.Spawn`. SG: `Process.Signal`.

- **Systems** — SP. "setpgid sends no signal. §4.4.8 defines Signal as sending. It is process-tree setup, and POSIX (posix_spawnattr_setpgroup), Go (SysProcAttr.Setpgid) and Rust (process_group) all model it as a spawn attribute. The later kill pays Process.Signal itself." Concern: "a reader may expect setpgid to be gated with kill, because its only purpose here is to let kill reach the group."
- **Web/Scripting** — SP. "setpgid sends no signal, so Signal would claim something it does not do. Python's Popen(process_group=), Rust's process_group and POSIX posix_spawnattr_setpgroup all present it as spawn configuration, which is what devs already expect." Concern: "a worker's setpgid(0,0) on itself, long after the fork, reads oddly as "Spawn". The writer should say that Spawn covers changes to the process tree, not only exec."
- **PLT** — SP. "setpgid sends no signal, and §4.4.8 defines Signal as sending. A Signal row would claim an action the call never does. setpgid configures the process tree, the same attribute posix_spawn, Go, Rust and Python treat as part of spawn. The later kill pays Signal itself, so SP opens no hole." Concern: "a program that calls setpgid(0,0) without ever forking carries a Spawn row for something that is not spawning."
- **DevOps/Tooling** — SP. "I withdrew SG in round 1. §4.4.8 defines Signal as sending a signal, and setpgid sends none. Every spawn API (posix_spawnattr_setpgroup, Popen(process_group=), CommandExt::process_group) treats the process group as a spawn attribute, so users and tools see the row they expect." Concern: "a worker's (0, 0) call on itself, long after any fork, still reads as Spawn, and that tells a reader less than it should."
- **AI/ML** — SP. "the test is mechanical: Signal means the call delivers a signal, and setpgid delivers none. Taken literally, §4.4.8 gives Spawn, and POSIX, Python and Rust all put the process group in spawn config, so the spec and the APIs models have seen agree." Concern: "a model may extend "Spawn = process-tree setup" to setsid or prctl calls with no ruling. The example should name setpgid only."
- **Minimalism** — SP. "setpgid sends no signal. It arranges the process tree, and every peer API treats it as spawn configuration. The later kill already pays Process.Signal, so the capability to signal stays where it belongs." Concern: "the worker's setpgid(0, 0) on itself reads less like "spawn" than the router's call. A future reader may file a friction ticket over it."

##### Q5. Help text for E0538 (`! FFI`) and E0802 — H (6-0)

H: the help names `State` as a choice. 0: no help change.

- **Systems** — H. "The moderator's fact settles it. The hidden-state writer's E0802 line does not name State, so without H the E0538 help sends every migrator of these ~30 decls to "effects or `! ()`", and both are wrong for pipe, memfd and socketpair. It is help text only, with no runtime, codegen or compile-time cost." Concern: "help that lists choices can be read as a menu, so authors may pick State where a named effect applies. The text must keep "no argument reaches" in it."
- **Web/Scripting** — H. "the E0538 help is the first text every migrator of the ~30 held decls reads. Today it offers two answers, and both are wrong for pipe, memfd and socketpair. The fact you added confirms that the hidden-state writer does not cover this, so it needs its own vote and its own change." Concern: "the help may grow into a mini-tutorial. Keep it to one line, with the § link doing the rest."
- **PLT** — H. "the current help offers two choices, and both are wrong for pipe/dup/fcntl. The fact note confirms that no other work names State there. H names the effect the hidden-state ruling makes the fallback, at no cost." Concern: "users may read "State" as a catch-all and write it where a named effect applies, against the N rule. Examples in §9.1 must show the named effect first."
- **DevOps/Tooling** — H. "The hidden-state writer's E0802 line ("`! ()` also claims no hidden state") warns but names no choice to make. E0538 on `! FFI` is the first text every migrator of the held decls reads, and today both choices it offers are wrong for pipe, memfd and the fallback cases. Naming State there fixes the most likely mistake where it happens, with no new code." Concern: "the help can over-steer authors to State where a named effect fits (e.g. close on a file fd). So the text must keep "the effects the foreign code has" first."
- **AI/ML** — H. "the help is the first text a model reads when it migrates a `! FFI` decl. Today it offers two choices, and both are wrong for pipe, dup and fcntl, so a model picks `! ()`. The planned E0802 line ("`! ()` also claims no hidden state") says what is wrong, but not what to write. Naming State says what to write." Concern: "if the help lists State without the "no argument reaches" condition, models may add State to every @ffi decl out of habit. Keep devops's condition word for word."
- **Minimalism** — H. "this changes help text only: no new code and no new mechanism. The help that ships today, together with the one line the writer for the hidden-state ruling is adding, still offers only "effects or `! ()`". Both answers are wrong for pipe, dup and fcntl, and every migrator lands on E0538 first. Fixing advice that misleads takes nothing away from the language surface." Concern: "the parenthetical list (fd table, errno, C global) can read as complete. Authors may then miss other hidden C state, for example a thread-local buffer."

##### Q6. A new warning for fd-table calls marked pure — 0 (6-0)

L: new warning `FfiFdTableCallPure`. 0: no new warning.

- **Systems** — 0. "A fixed list of C names catches only `! ()` on literal libc symbols. Shims (blinkrt_socketpair_packed), pipe2, dup3, eventfd and the rest escape it, so silence does not mean the row is correct. It is a per-name table in the compiler that will need upkeep forever, and H already fixes the advice at the point where the mistake is made." Concern: "models and authors may still write `! ()` on close or isatty, and nothing catches it before review."
- **Web/Scripting** — 0. "a name list catches only `! ()` on 13 names. It misses shims, pipe2/dup3/eventfd and wrong non-empty rows, so silence starts to look like "checked". With H in place, the help already steers people away from `! ()` at the moment they choose." Concern: "models may still write `! ()` on isatty/close and nothing flags it before review (aiml's point)."
- **PLT** — 0. "a fixed list of C names in the compiler is a per-name table, and the rule just rejected per-name tables. It does not compose with shims (`blinkrt_socketpair_packed`), with `pipe2`/`dup3`/`close_range`, or with C calls made inside larger C functions. It catches only `! ()`, so a wrong non-empty row passes with no warning and gives false assurance." Concern: "without a lint, `! ()` on an fd call still compiles with no warning, so the help text and review are the only guard."
- **DevOps/Tooling** — 0 (round 1: L). "plt's and min's points win on diagnostic grounds. A lint keyed to 13 C names says nothing on shims (`blinkrt_socketpair_packed`), on pipe2/dup3/eventfd and the rest of the long tail, or on a wrong non-empty row. A diagnostic that is silent on most of its space teaches users that silence means correct, and that does more harm than its zero false positives do good. With H in, the corrected help covers most of the benefit." Concern: "models and users will still write `close ... ! ()` by default, and nothing will catch it before review."
- **AI/ML** — 0 (round 1: L). "web and plt showed that the lint is silent off its 13 names (shims, pipe2, dup3, eventfd). For model training, a lint that is silent on most of the space teaches that silence means correct, which is worse than no lint. H covers most of the benefit, at the point where the error is made." Concern: "models will still write `! ()` on new decls like close or isatty, which help text alone does not catch, so the spec examples must show close with a non-empty row."
- **Minimalism** — 0. "a fixed list of 13 C names in the compiler needs upkeep forever, and the list it misses never ends (pipe2 variants, dup3, close_range, eventfd, timerfd, shims such as blinkrt_socketpair_packed). It only catches `! ()`, so a wrong non-empty row passes in silence, and users get a false sense that rows are checked. Once H is in, the help already teaches the rule. If someone still wants this, it belongs in an external lint, not in the language toolchain." Concern: "without the lint, an author who never reads the help can still write `! ()` on close. Only review catches that."

After the vote the moderator gave one fact: an open low-priority ticket plans a known-symbol table that warns when the row of an `@ffi` decl disagrees with a well-known libc symbol. Q6-L would be one case of that table. The seats replied:

- **Systems**: "No change: 0. The fact strengthens my vote. A known-symbol table already has a home in that open ticket. Adding 13 fd names now as their own warning code would build one part of that table early, under its own diagnostic, before the general design exists. It would also have to be reworked once the table lands. Add those names to that ticket as entries. Do not make a separate lint."
- **Web/Scripting**: "No change: 0. The fact makes my case stronger. If we want a known-symbol table, there is already a ticket for it. Shipping Q6-L now would fix one piece of that table with its own warning name, and later the general table would have to take it over or sit next to it. I suggest the moderator note the 13 fd names on the existing known-symbol ticket as seed entries. They can land there, under one design with one code, if that ticket is ever built."
- **PLT**: "No change: 0. The fact makes the case for 0 stronger. A known-symbol table is already a ticket of its own. If we ship L now, we make one narrow case of that table under its own warning name before the general design exists. The general table must then fold L in or keep two rules side by side. Better to add the fd symbols (pipe, dup, dup2, fcntl, close, lseek, flock, setpgid, memfd_create, socketpair, isatty) to that ticket as a case to cover, and design the table once."
- **DevOps/Tooling**: "No change: Q6 = 0. Reasoning: the fact strengthens 0. A separate `FfiFdTableCallPure` would be a second, narrower copy of the known-symbol table that the open ticket already plans. It would also check only `! ()`, while that ticket checks any row that disagrees. One table with one diagnostic is the better tooling surface. I suggest a note on the open ticket: seed its table with the 13 fd-table names from Q6-L, flagged "never `! ()`". Concern: that ticket is low priority, so `close ... ! ()` may stay uncaught for a long time."
- **AI/ML**: "No change: still 0. The fact makes the case for 0 stronger. If fd calls get their own lint now, models see two ways to check claims, and an fd list that will not match the general known-symbol table. One table that covers all libc symbols and checks claimed rows in both directions (strlen pure, getpid not, close not) is the right home for this, and it would fix the "silent off the list" problem in a single place. Please put this ruling's fd rows on that ticket as data, so that work starts with them."
- **Minimalism**: "No change: I still vote 0. The fact makes my case for 0 stronger. If a known-symbol table is ever built, the general ticket is where it belongs: one mechanism with one data format that covers every libc symbol. Q6-L would ship one fixed case of that table first, under its own warning name. That splits the design before anyone has chosen it, and when the general table lands we would have two ways to say the same thing. Leave the fd-table names as data for that ticket, which can mention [...] as a use case, and keep this ruling free of diagnostics beyond the help-text change (Q5-H)."

##### AG block. S1, S2, S3, S4 and N (6-0)

- S1: an op on an existing fd takes the row of the call(s) that made the fd.
- S2: `pipe`, `memfd_create` and `socketpair` are `! State`.
- S3: `lseek` takes the row of the maker of the fd.
- S4: no new effect and no new leaf.
- N: a built-in effect that names the resource replaces `State`.

- **Systems**: "AG: yes"
- **Web/Scripting**: "AG: yes"
- **PLT**: "AG: yes"
- **DevOps/Tooling**: "AG: yes"
- **AI/ML**: "AG: yes"
- **Minimalism**: "AG: yes"

### Final Spec

```blink
@ffi("pipe", header: "unistd.h")
fn bfs_pipe(fds: Ptr[I32]) -> I32 ! State {}

@ffi("close", header: "unistd.h")       // fds from open_read, open_write and bfs_pipe
fn bfs_close(fd: I32) -> I32 ! FS.Read, FS.Write, State {}

@ffi("close", header: "unistd.h")       // fds from open on a path for reading
fn sha256_close(fd: I32) -> I32 ! FS.Read {}

@ffi("dup2", header: "unistd.h")        // from: open_write fds; to: 1 or 2
fn bfs_dup2(from: I32, to: I32) -> I32 ! FS.Read, FS.Write, IO.Print, IO.Log {}

@ffi("flock", header: "sys/file.h")
fn bfs_flock(fd: I32, op: I32) -> I32 ! FS.Read, FS.Write {}

@ffi("setpgid", header: "unistd.h")
fn daemon_setpgid(pid: I32, pgid: I32) -> I32 ! Process.Spawn {}
```

- An op on an existing fd takes the row of the call that made it. A decl with several makers takes the union of their rows, or the author splits it. One decl per fd kind is better.
- `pipe`, `memfd_create` and `socketpair` take `State`. A built-in effect that names the resource replaces `State`.
- `dup2` takes the union of the rows of both fds. The `FS` rows come from the maker of the source fd.
- `dup` and `fcntl(F_SETFD)` take the row of the maker. A `cmd` with an effect of its own, such as `F_SETLK`, adds that leaf.
- `flock` takes the row of the maker and `FS.Write`. `lseek` takes the row of the maker.
- `setpgid` takes `Process.Spawn`. The later `kill` pays `Process.Signal`.
- The `E0538` help for `! FFI` and the `E0802` help name `State` as a choice. No new code.
- No new warning.
- Spec: §9.1 *fd-Table and Process-Control Calls — Which Row*, §4.4.6, §4.4.8, §4.16.1.
