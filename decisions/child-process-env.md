[< All Decisions](../DECISIONS.md)

# Per-Child Environment and Working Directory — Design Rationale

### Panel Deliberation

The ticket (verbatim):

> Title: std.process: set environment variables for one spawned child
>
> Desc: std.process can spawn a child only with the parent's whole environment: process_run(cmd, args) and process_spawn(cmd, args) take no env argument. To give one child a variable, a caller must either set it in its own environment (env.set_var), which every later child and the parent then see, or exec /usr/bin/env VAR=val cmd ... . blink test does the second for its build workers (BLINK_MANIFEST_REPORTED, see docs/build/blink-test-build-workers.md).
>
> MVCE (build/gen1/bin/blink run m.bl):
>     fn main() {
>         // want: the child sees FOO=1, the parent and later children do not
>         let r = process_run("sh", ["-c", "echo $FOO"])
>         io.println("child: [{r.out.trim()}]")
>     }
> There is no way to write this without env.set_var (leaks to the parent) or an env wrapper.
>
> Want: a spawn and run form that takes extra variables (and a way to unset one) for that child alone, for example process_run_env(cmd, args, env: Map[Str, Str]) / process_spawn_env, or an options record. The spec owner picks the surface.
>
> Ticket note (owner, 2026-10-13): "panel first. This adds user-visible std.process surface". Blocks a chore that drops the `/usr/bin/env` wrapper in `blink test`.

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in four phases, with one round in Phase B. Phase D took one question (Q3). Quoted text is each panelist's own words. Each quote is a whole paragraph or list item of the panel record, or a line range of one.

Questions:

- Q1: the shape of the parameter. **PLT1:** `env: ChildEnv = ChildEnv.Inherit` with `ChildEnv { Inherit, Change(Map[Str, Str?]), Only(Map[Str, Str]) }`. **PLT1A:** the same with `Inherit` and `Change` only. **DELTA:** `env: Map[Str, Str?]? = None`, a change list. **WEB1:** `ChildEnv { Inherit, Extend(Map[Str, Str]), Exact(Map[Str, Str]) }`. **AIML5:** `ChildEnv { Inherit, Extend, Change, Exact }`.
- Q2: which `PATH` finds a bare `cmd` when the child's environment sets or drops `PATH`. **CHILD:** the child's `PATH`; the search runs in this program before the child starts, so a miss is `Err` with `ENOENT` from the call. **PARENT:** this program's `PATH`.
- Q3: a per-child working directory. **NOW:** add `cwd: Str? = None` on the same ops in this edit. **LATER:** a separate ticket.
- Q4: a NUL in `cmd` or in an argument. **YES:** the same `EINVAL` rule covers it. **NO:** leave `cmd` and arguments out of this edit.

All seats agreed from Phase A or B on these points: keyword parameters on `run`, `spawn` and `exec` and no new op; effect rows do not change; this program's environment does not change; the default is a const value (§2.21); an empty name, a name that holds `=` or NUL, or a value that holds NUL gives `Err` with `EINVAL`; a user `handler Env` or `mock_env` does not change what a real child inherits; the read of the inherited environment is serialized with `env.set_var` and `env.remove_var`; and a handler with too few parameters gets an error that names the missing one and offers a fix.

#### Phase A

Each seat's first proposal and its rule, as quoted from its record.

- **Systems (sys)**

> ## sys-1 (preferred): `env: Option[Map[Str, Option[Str]]] = None` on run, spawn, exec — a change list
>
> **Rule (one sentence for §4.4.8).** The child starts with this program's environment; for each entry of `env`,
> `Some(v)` sets the variable to `v` and `None` removes it. So each map entry says what `env.var(name)` returns in
> the child — the same type, `Option[Str]`, that §4.4.3 `env.var` returns. That symmetry is the reason for the value
> type: one type, read the same way at both ends.

- **Web/Scripting (web)**

> ## web-1 (my pick): one keyword param, a named enum `ChildEnv`
>
> ```blink
> // std.process
> pub type ChildEnv {
>     Inherit                     // the child gets this program's environment, unchanged (the default)
>     Extend(Map[Str, Str])       // this program's environment, plus these variables; a key here wins
>     Exact(Map[Str, Str])        // only these variables, nothing inherited
> }
> ```

- **PLT (plt)**

> ## plt-1 (my pick): a `ChildEnv` sum type as a keyword parameter on `run`, `spawn`, `exec`
>
> ### Types (in `std.process`)
>
> ```blink
> @derive(Eq, Debug)
> pub type ChildEnv {
>     Inherit                         // the child gets this program's environment
>     Change(Map[Str, Option[Str]])   // this program's environment, with each Some(v) name set to v and each None name removed
>     Only(Map[Str, Str])             // exactly these variables, nothing inherited
> }
> ```

- **DevOps/tooling (devops)**

> ## devops-1 (recommended): one keyword `env` overlay on `run`, `spawn` and `exec`
>
> ### Spec text to add to §4.4.8 (new paragraph after **Standard input**)
>
> > **Environment.** A child starts with a copy of this program's environment as it is when the operation
> > starts it. With `env: None`, the default, the child gets that copy unchanged. With `env: Some(m)`, the
> > operation changes the copy before the child starts: for each entry `(name, Some(value))` of `m`, the child
> > sees `name` set to `value`; for each entry `(name, None)`, the child does not see `name`. A name that is
> > not a key of `m` keeps its value from this program. The operation does not change this program's
> > environment: `env.var` and `env.vars()` return the same values after the call as before it, and a later
> > child does not see the change. Variables that the operation does not change go to the child byte for byte,
> > also when they are not UTF-8. `Some(Map.new())` gives the same child as `None`.
> >
> > A name that is empty or contains `=` or a NUL character, or a value that contains a NUL character, makes
> > the operation return `Err` with code `EINVAL`. The operation then starts no child.

- **AI/ML (aiml)**

> ## aiml-1 (preferred): two keyword args, overlay semantics, on run/spawn/exec
>
> - A child starts with a copy of this program's environment at the time of the call.
> - Each name in `env_remove` is removed from that copy. Then each entry of `env` is set in it. The child gets the
>   result. This program's environment does not change, and later children do not see `env`.

- **Minimalism (min)**

> ## min-1 (my pick): `env: Option[Map[Str, Str]] = None` — the child's whole environment
>
> Rule: `env: None` (the default) — the child inherits this program's environment, as today. `env: Some(m)` —
> `m` is the child's whole environment, nothing else. That is all. Add, unset and clear are not three
> features; they are three ordinary `Map` edits the caller already knows.

#### Phase B

One round; all six seats sent "ready to vote". Key shifts:

- **sys, devops and web move to plt-1.**

*sys (B1):*

> ## The shape: I move from sys-1 to plt-1 (ChildEnv with Inherit / Change / Only)
>
> plt-1 keeps every point I made for sys-1 and drops its worst cost.
>
> - `Change(Map[Str, Str?])` is exactly my change list. The runtime still copies `environ` itself under the
>   `set_var` lock, as raw bytes, so non-UTF-8 variables reach the child unchanged and a concurrent `set_var` is
>   wholly in or wholly out. No `Env.Read` in the row.
> - `ChildEnv.Inherit` is a const default (§2.21 "Enum variants"), so there is no outer `?`. The call site loses one
>   wrapper: `env: ChildEnv.Change(m)` in place of `env: Some(m)`, and the mock parameter is `env: ChildEnv`, not
>   `env: Map[Str, Str?]?`. I offered an enum in Phase A; plt-1 is that enum, done right.

*devops (B1):*

> ## Position: I move from devops-1 to plt-1 (`ChildEnv { Inherit, Change, Only }`)
>
> plt-1 `Change(Map[Str, Option[Str]])` has the same meaning as my devops-1 delta. The enum is better tooling for
> the same meaning:
>
> - **The error message.** Under devops-1, a caller who writes `env: Map.from([("FOO", "1")])` gets a mismatch
>   against `Map[Str, Str?]?`, with two `Option` layers wrong. Under plt-1 the mismatch is
>   "expected `ChildEnv`, found `Map[Str, Str]`", and the help can name the variants. One wrong layer, and a
>   name the reader can look up.
> - **Hover and completion.** Hover on `env:` shows `ChildEnv`, and hover on `ChildEnv` shows three variants with
>   one doc line each. Completion after `env: ChildEnv.` lists them. With a nested `Option` type there is nothing
>   to list and no doc to show.
> - **The call site says which meaning.** web-1 is correct that "the call site must SAY which one it is". `Change`
>   and `Only` say it. `Some(m)` does not.
> - **The default is a const.** `ChildEnv.Inherit` is a payload-free variant (§2.21), so no outer `Option`.
> - **The mock.** `@derive(Eq, Debug)` on `ChildEnv` lets a test write `assert_eq(seen, Some(ChildEnv.Change(m)))`.
>   The mock still sees only the delta for `Change`, which was my main reason for an overlay.

*web (B1):*

> I move from web-1 to **plt-1** (`Inherit` / `Change(Map[Str, Str?])` / `Only(Map[Str, Str])`). My new ranking:
> **plt-1 > web-1 > sys-1 = devops-1 > min-1**. aiml-1 is not legal as written (see below).
>
> The cost I accept: the 90% case is `env: ChildEnv.Change(Map.from([("FOO", Some("1"))]))`. The inner `Some` is noise,
> but if a user forgets it they get a type error at the call, not a silent bug. That is the right trade.

- **min drops REPLACE (min-1) for DELTA.**

> ## I drop min-1 (REPLACE). I now back DELTA (sys-1 / devops-1).
>
> The case against my own first choice is better than the case for it. Three separate faults, each enough alone:
>
> 1. **Lossy round trip.** I named it in A; devops makes it decisive: "A replace shape makes the caller ...
>    [round-trip every variable through] `env.vars()`" and non-UTF-8 values change. The overlay passes each
>    variable it does not touch byte for byte.
> 2. **It does not compose with a `handler Env`.** plt rule 2: under `mock_env`, `env.vars()` returns the mock's
>    names, not the OS environment. A REPLACE map built from `env.vars()` then gives the child the mock's
>    environment in a test and the real one in production. That is a semantic bug, not a style point.
> 3. **The footgun web names.** `env: Some(Map.from([("FOO", "1")]))` "LOOKS like add FOO and silently drops
>    `PATH`". The common intent (add one variable) must be the short, safe spelling.
>
> So REPLACE is out from my seat. Minimalism is fewest concepts that are *correct*, not fewest characters.

- **aiml withdraws aiml-1 and aiml-2 over §2.21.**

> ## Concession: aiml-1 is ill-formed as I wrote it
>
> The digest fact is right. §2.21 needs a const keyword default, and `Map()` and `[]` are not const. My aiml-1
> (`env: Map[Str, Str] = Map(), env_remove: List[Str] = []`) does not pass our own spec. To fix it I would have to
> write `env: Map[Str, Str]? = None, env_remove: List[Str]? = None`, and then the 90% call is
> `env: Some(Map.from([("FOO", "1")]))`. That is the REPLACE call shape with the opposite meaning, which is the worst
> case for an LLM: the same text means "add" here and "replace" in Python. I withdraw aiml-1 and aiml-2.

- **sys and plt cross on `PATH`.** sys concedes to the child's `PATH`, with a condition. plt concedes to the parent's `PATH`.

> 2. **Which `PATH` finds `cmd`.** I concede to plt-1 rule 4 (the child's `PATH`), with one condition on the text:
>    the lookup happens **in this program, before the child starts**, so a miss is `Err(ProcessError { code: ENOENT
>    })` from the call and not an exit code from a child that never ran. That is the cost model I care about: a few
>    `stat`/`access` calls in the parent, the same work `execvp` does today, and no allocation after `fork`. With
>    that, plt's argument wins: under `Inherit` and most `Change` uses both rules agree, and under `Only(m)` the
>    program that runs should depend only on what the child sees. Rust does this. My Phase A "parent's PATH" rule
>    followed the syscalls, but a spec should follow the value the user wrote.

> ## Variation 2 — which `PATH` finds `cmd`: I concede to sys-1
>
> sys-1: "`cmd` is found on this program's `PATH`, not on a `PATH` that `changes` sets; give an absolute path to run
> a program from another place." I proposed the child's `PATH`. On reflection both are sound, and sys's rule has a
> cleaner denotation: the program that runs is `lookup(B, cmd)`, the child's environment is `child_env(B, e)`, and
> the two do not interact. With my rule, `e` changes which program runs, which a reader of
> `env: ChildEnv.Change(m)` does not expect. It also matches `posix_spawnp`/`execvpe` and needs no second lookup.
> I withdraw plt-1 rule 4 and support sys's sentence verbatim. The spec should add: under `Only`, the lookup still
> uses this program's `PATH`; give an absolute `cmd` for a fully hermetic start.

#### Phase C

Silent vote on four questions. Each seat gave a vote, reasoning and one concern.

##### Q1: the shape of the parameter

Result: PLT1, 5-1 (Minimalism dissent).

- **Systems (sys): PLT1**

> **Reasoning:** `Change` is the delta I wanted: the runtime copies `environ` itself under the `set_var` lock, as raw
> bytes, before `fork`, so variables that are not valid UTF-8 reach the child unchanged and no `Env.Read` is needed.
> `Only` maps 1:1 to the `envp` of `execve` and is the one race-free hermetic form. `Inherit` is a const default, so
> there is no outer `?`, and the default path costs one tag test over today's code. WEB1 cannot unset a variable
> without an `env.vars()` round trip, and AIML5's `Extend` is a second spelling of `Change`.
>
> **Concern:** a hermetic build step that writes `Only(m)` with no `PATH` gets `ENOENT` for a bare `cmd`, and users
> will meet that before they read the rule.

- **Web/Scripting (web): PLT1**

> **Reasoning:** The call site must say which meaning it uses. `ChildEnv.Change(...)` and `ChildEnv.Only(...)` cannot be
> misread the way `env: Some(map)` can (Python and Node devs read it as replace, Deno and Rust devs read it as add).
> `Change` does set and unset as one delta, so no caller has to rebuild the environment from `env.vars()`. That rebuild
> is lossy for non-UTF-8 values, can race with `set_var`, and is wrong under a `handler Env`. I give up web-1's
> friendlier `Extend(Map[Str, Str])` for that correctness. AIML5 adds a fourth variant that overlaps `Change`, which is
> two ways to say "add FOO".
>
> **Concern:** The 90% case, `env: ChildEnv.Change(Map.from([("FOO", Some("1"))]))`, is long. Users and LLMs will often
> leave out the inner `Some` the first time, so the type-mismatch error must show the fixed call.

- **PLT (plt): PLT1**

> **Reasoning:** `ChildEnv { Inherit, Change(Map[Str, Str?]), Only(Map[Str, Str]) }` names the three distinct
> semantics as the three cases of one total function from the inherited environment B to the child's environment,
> and a `Map` makes `Change` an order-independent update. `Only` is the one form whose result does not depend on B.
> It cannot be built from `Change` without reading B through `env.vars()`, which is lossy for non-UTF-8 values, races
> `set_var`, and returns the mock's names under `mock_env`. DELTA and PLT1A are sound but leave that case out. WEB1's
> `Extend` sends removal back through the same lossy `env.vars()` path. AIML5 adds `Extend` as a second spelling of a
> subset of `Change`, so two variants overlap in meaning.
>
> **Concern:** if `Only` is left out now and added later, it breaks every exhaustive `match` on `ChildEnv` in user
> mocks (or, with DELTA, it needs a second keyword whose overlap with the map needs its own rule).

- **DevOps/tooling (devops): PLT1**

> **Reasoning:** A named enum gives the best diagnostic surface: a wrong argument gets "expected `ChildEnv`", hover
> shows three documented variants, and completion after `ChildEnv.` lists them, where DELTA gives a two-layer
> `Option` mismatch and nothing to list. `Change` keeps what I wanted from DELTA: the mock sees only the delta, and
> derived `Eq` lets a test assert it. `Only` must be in now, because a variant added later breaks every user `match`
> over `ChildEnv`. AIML5's `Extend` is a subset of `Change`, so it gives two ways to write the same call and invites a
> lint to pick one; WEB1 cannot unset without the lossy `env.vars()` copy.
>
> **Concern:** The 90% call `ChildEnv.Change(Map.from([("FOO", Some("1"))]))` is long, and a caller who forgets the
> inner `Some` gets a `Map[Str, Str]` vs `Map[Str, Str?]` mismatch, so the type-mismatch help must show the repaired
> call for this case.

- **AI/ML (aiml): PLT1**

> **Reasoning:** I offered AIML5, but it gives two ways to write "add FOO" (`Extend(m)` and `Change(m)` with
> `Some` values). That is the needless decision point my seat exists to flag, and a model will mix the two forms
> in one codebase. WEB1 keeps the common call cheap, but its only unset is `Exact(env.vars().filter(...))`, which
> races with `set_var`, loses non-UTF-8 values, and reads the mock's names under `mock_env`. That code looks
> right and is wrong, which is the worst case for generated code. PLT1 has one variant per intent, names the
> meaning at the call site, and has a const default. The cost is a `Some("1")` around each value. If a model
> forgets it, it gets a loud type error at the call, not a silent bug.
>
> **Concern:** The 90% call `ChildEnv.Change(Map.from([("FOO", Some("1"))]))` is long and nested. Models will
> leave out the `Some` on the first try, so the type-mismatch error for that map must say "wrap the value in
> `Some(...)`", and the §4.4.8 example must show the one-variable case first.

- **Minimalism (min): DELTA *(dissent)***

> **Reasoning:** DELTA solves the ticket with no new public type: `None` is inherit, `Some(m)` is the change list, and
> `Map[Str, Str?]` already says set-or-remove. PLT1A is the same thing under a new name, and PLT1's one gain, `Only`, is
> for a hermetic child that no consumer in the repo or the ticket needs. A type plus an import at every call site for a
> case nobody has is the addition my seat exists to refuse; `Only` can come with its first real consumer.
>
> **Concern:** If PLT1 wins, `ChildEnv` becomes the template for every later per-child knob (`cwd`, stdio) and grows
> toward a `Command` builder one variant at a time; the decision should state that `ChildEnv` describes the environment
> only.

##### Q2: which `PATH` finds a bare `cmd`

Result: CHILD, 6-0.

- **Systems (sys): CHILD**

> **Reasoning:** The program that runs should depend only on what the caller wrote and the child sees; that is what
> Rust, Python, Node, the shell and the `/usr/bin/env` wrapper this ticket replaces all do. My condition holds in the
> option text: the search runs in this program before the child starts, so a miss is `Err` with `ENOENT` from the
> call, not an exit code from a child that never ran. The cost is a few `access` calls in the parent, the same work
> `execvp` does today, with no allocation after `fork`.
>
> **Concern:** the runtime must own the `PATH` search on every target (it can no longer lean on `execvp`), and a
> second, subtly different search in some code path would make the rule untrue.

- **Web/Scripting (web): CHILD**

> **Reasoning:** This is what every tool a scripting dev already uses does: `env PATH=... tool`, bash
> `PATH=/x cmd`, Python `subprocess`, Node and Rust all search the new `PATH`. The common reason to set `PATH` for a
> child is "prepend my toolchain dir and run the tool from it". Under PARENT that call silently runs the wrong binary.
> Because the search runs in this program before the child starts (sys's condition), a miss is an `Err` with `ENOENT`
> at the call, which is loud and near the cause.
>
> **Concern:** Under `Only` with no `PATH`, a bare `cmd` fails with "No such file or directory" when the program clearly
> exists, so the spec text and the `Display` must make the cause easy to find (a note that the search used the child's
> `PATH`).

- **PLT (plt): CHILD**

> **Reasoning:** In B1 I gave this to sys for a cleaner denotation, but the B1 evidence turned me back. sys itself
> now holds CHILD, provided the search runs in this program before the child starts. The shell (`PATH=/x cmd`),
> the `/usr/bin/env VAR=val cmd` wrapper this ticket replaces, Python, Node and Rust all search the new `PATH`. A call
> that prepends a toolchain directory would silently run the wrong binary under PARENT. With sys's condition, the rule
> stays a function of values the caller wrote: lookup(child_env(B, e), cmd), with a miss reported as `Err` (`ENOENT`)
> from the call.
>
> **Concern:** the text must say that a `Change` that sets `PATH` also changes the search, and that a miss is an
> `Err` from the call, not an exit code from a child, or two runtimes may implement it differently.

- **DevOps/tooling (devops): CHILD**

> **Reasoning:** The error must match what the reader can see in the code: under `Only(m)` with no `PATH`, `run make:
> No such file or directory` is explained by the call itself. It matches the `/usr/bin/env VAR=val cmd` wrapper this
> ticket removes, the shell, Python, Node and Rust. sys's condition (search in this program, a miss is `Err` with
> `ENOENT` from the call, not a child exit code) makes the failure loud and near its cause.
>
> **Concern:** A user who prepends a directory to `PATH` through `Change` and also has the same tool name earlier on the
> parent's `PATH` may be surprised which binary runs, so the spec sentence must state that `Change` of `PATH` changes
> the search too.

- **AI/ML (aiml): CHILD**

> **Reasoning:** Python, Node, Rust, the shell (`PATH=/x cmd`) and the `/usr/bin/env VAR=val cmd` wrapper that this
> ticket replaces all search the new `PATH`. So the child's `PATH` matches the prior a model already has, and code
> that moves from the wrapper to `env:` behaves the same. sys's condition (the search runs in this program, so a
> miss is `Err` with `ENOENT` from the call) keeps the error next to its cause.
>
> **Concern:** plt changed sides to PARENT in B1. If the spec text is not clear that a `Change` that sets `PATH`
> also changes the search, models will assume Go's rule from training data.

- **Minimalism (min): CHILD**

> **Reasoning:** I leaned PARENT in B1 as "the smallest rule", but aiml's point decides it: the `/usr/bin/env VAR=val
> cmd` wrapper this ticket replaces calls `execvp` with the new `PATH`, and so does the shell. CHILD keeps behaviour the
> same for a caller who drops the wrapper, which is a subtraction of surprise. sys's condition (search in this program,
> a miss is `Err` with `ENOENT` from the call) keeps the error near its cause.
>
> **Concern:** The runtime must do its own `PATH` search instead of `posix_spawnp`, and a subtle difference from libc
> search (empty `PATH` entries, a missing `PATH` default) becomes a latent bug unless the spec states those cases.

##### Q3: per-child working directory

Result: 3-3 (NOW: web, plt, aiml; LATER: sys, devops, min). No majority; Phase D follows.

- **Systems (sys): LATER**

> **Reasoning:** No consumer needs it, and the ticket does not ask for it. It is one `chdir` in the child, cheap and
> async-signal-safe, so it can come in its own ticket with no design debt from this one. The handler break is real,
> but the arity fix-it makes it one machine edit per mock.
>
> **Concern:** a later `cwd` ticket breaks every `handler Process` a second time; that ticket should record the cost.

- **Web/Scripting (web): NOW**

> **Reasoning:** `cwd=` / `{cwd}` is one of the most used options in Python and Node. Since `set_cwd` is banned
> (DECISIONS.md:250), Blink has no way at all today to start a child in another directory. Each later keyword breaks
> every `handler Process` again, so adding `cwd: Str? = None` in this edit makes mocks break once. The shape needs no
> new design: the same ops, the same row, and `ENOENT` for a missing directory.
>
> **Concern:** If LATER wins, the follow-up ticket must record that it breaks every `run`/`spawn`/`exec` mock a second
> time, or that cost gets forgotten.

- **PLT (plt): NOW**

> **Reasoning:** DECISIONS.md:250 refused `set_cwd` as a process-global mutation, so today a Blink program has no
> way at all to run a child in another directory. `cwd: Str? = None` is the per-child form, by the same typing
> argument as `env`: a new value for the child, no mutation of this program, no `Env.Write`. Each later keyword
> breaks every `handler Process` that implements `run`, `spawn` or `exec` again. Adding it in this edit makes that
> break happen once.
>
> **Concern:** if LATER wins, the follow-up ticket must record the second handler break as its cost, or it will
> look free when it is triaged.

- **DevOps/tooling (devops): LATER**

> **Reasoning:** No consumer in the tree or in the ticket needs it; the daemon changes its own cwd through FFI. The
> "mocks break twice" cost is real, but the follow-up arity diagnostic (common ground) turns each break into one
> machine-applicable fix, which is the tooling answer to that cost. The new ticket should record the mock-break cost
> so the owner can weigh it.
>
> **Concern:** If LATER wins and `cwd` lands soon after, every `handler Process` breaks twice in a short time, and
> that is only cheap if the arity fix-it ships first.

- **AI/ML (aiml): NOW**

> **Reasoning:** `cwd=` is one of the options models reach for most often after `env=` in Python and Node. With
> `set_cwd` banned there is no way at all to run a child in another directory, so models will invent
> `sh -c "cd dir && ..."`, which is a shell-injection pattern. Adding it in this edit breaks each `handler Process`
> once, not twice, and teaches one consistent keyword set for the ops that start a program.
>
> **Concern:** If LATER wins, the follow-up ticket must record the second handler-arity break, and the spec should
> not grow a `cd`-via-shell example in the meantime.

- **Minimalism (min): LATER**

> **Reasoning:** No consumer asks for `cwd`, and the ticket does not. "Mocks break once instead of twice" is a reason to
> add speculative parameters, which is the C++ committee path. With the devops arity fix-it, a later break is one
> machine fix per mock.
>
> **Concern:** The follow-up ticket must record the handler-break cost, or the next panel will add `cwd` and stdio
> parameters one at a time without seeing the total.

##### Q4: NUL in `cmd` or an `arg`

Result: YES, 6-0.

- **Systems (sys): YES**

> **Reasoning:** `cmd`, args, names and values all cross the same C boundary as NUL-terminated strings. Today a NUL in
> an argument cuts it short at that boundary with no error, so the child gets an argument the caller did not write.
> One rule for every string that goes to the OS: `Err` with `EINVAL`, no child starts.
>
> **Concern:** the check costs one scan of each string per spawn; negligible, but the runtime must not skip it on a
> fast path.

- **Web/Scripting (web): YES**

> **Reasoning:** One sentence covering every string that goes to the child is easier to learn than a rule for env
> names only. sys reports that a NUL in an arg is silently cut at the C boundary today. That is a latent bug a user
> will find, and the fix costs one clause in text that is already being edited.
>
> **Concern:** The `EINVAL` message (`run x: Invalid argument`) does not say which string had the NUL, so the error is
> hard to trace when args come from data.

- **PLT (plt): YES**

> **Reasoning:** `cmd`, args, names and values all cross the same C string boundary. Today a NUL truncates an arg in
> silence, so a well-typed Blink value means something different from what runs. One rule (`Err` with `EINVAL`, no
> child starts) for every string that goes to the OS is simpler to state and to learn than a rule for `env` alone.
>
> **Concern:** the sentence must say the check runs before any child starts, for every op that takes these
> strings (`run`, `spawn`, `exec`), so that `exec` does not fall back to a partial start.

- **DevOps/tooling (devops): YES**

> **Reasoning:** One rule for every string that crosses to the OS is one sentence to learn and one error to document.
> Today a NUL in an arg truncates it at the C boundary with no error (sys), which is the worst diagnostic there is:
> none. `Err` with `EINVAL` before any child starts makes it visible.
>
> **Concern:** `run make: Invalid argument` does not say which string held the NUL, so a later chore should add a
> `blink check` lint for literal names and args that hold `=` or NUL.

- **AI/ML (aiml): YES**

> **Reasoning:** One rule for every string that crosses to the OS is easier to learn and state than two rules that
> differ only by which parameter the string came from. Today a NUL in an arg truncates at the C boundary with no
> error, which is a latent bug that generated code will hit with data from files.
>
> **Concern:** None from my seat. The sentence must name `cmd`, args, env names and env values together, so that
> nobody reads it as an env-only rule.

- **Minimalism (min): YES**

> **Reasoning:** One rule for every string that crosses to the OS is smaller than two rules plus an unspecified gap.
> Today a NUL silently truncates an argument at the C boundary (sys B1), so this removes a latent bug and costs one
> clause in a sentence the edit already writes.
>
> **Concern:** The implementation must check `cmd` and every arg before any child starts, on `exec` too, or the rule
> holds for `run` and not for the op that never returns.

#### Phase D

Q3 only. The moderator counted `sh -c "cd ..."` sites in tests/ and put sys's two path rules into the NOW option.

> `rg '"cd ' tests/` matches 553 lines in 275 files under tests/ (seats gave 371/772, 291/466 and 273/551 with other
> patterns). No match in src/ or lib/ starts a child in another directory; src/daemon.bl changes its own directory
> (plt D1).

Highlights of the D1 round:

- **web** counts the sites that the NOW option replaces.

> devops: "No consumer in the tree or in the ticket needs it". sys: "No consumer needs it". This is not what the tree
> shows. Run `rg -l '"[^"]*cd \{' src lib tests --glob '*.bl'`: **371 files in tests/** build a string
> `"cd {dir} && ..."` and run it through `sh -c`. That is 772 sites. No file in `src/` or `lib/` does it. Some examples:
>
> *[examples omitted]*
>
> These are the exact consumers of this decision. Each one needs a per-child env (set, `-u` unset, and a changed `PATH`,
> which is Q2) AND a per-child cwd. With env-only, every one of these lines must still go through `sh -c "cd ..."`. So
> it keeps the shell-quoting and injection pattern that §4.4.8 itself warns against ("The shell reads `dir` here, so a
> `dir` from user input can inject commands"). aiml predicted that models would invent `sh -c "cd dir && ..."`. They
> already did: this codebase, the one that will be training data, has 772 copies of it.

- **devops** moves from LATER to NOW.

> ## Position: I move from LATER to NOW
>
> My Phase C reason was a fact claim, and it is wrong. I wrote: "No consumer in the tree or in the ticket needs it."
> I checked the tree this round:
>
> *[examples omitted]*
>
> That is the exact pattern aiml named: "models will invent `sh -c "cd dir && ..."`, which is a shell-injection
> pattern." The tree already did it, 371 times, because no other way exists (`set_cwd` is banned, DECISIONS.md:250).
> The same lines also use `env -u ...`, which the decided `ChildEnv.Change` now replaces. With `env` but not `cwd`,
> those tests still need `sh -c` for the `cd`, so the `env` change cannot remove the shell from them. That is the
> consumer, and it is in this repo.

- **min** moves from LATER to NOW.

> ## I move from LATER to NOW.
>
> My LATER vote, and devops's, rested on one fact: "No consumer in the tree or in the ticket needs it" (devops). I
> checked. The fact is wrong.
>
> `rg -c '"cd \{' --glob '*.bl' src lib tests` gives **551 hits in 273 files**. Examples:
>
> *[examples omitted]*
>
> So the consumer is this repo, hundreds of times over, and the workaround is exactly the one aiml named: "models will
> invent `sh -c "cd dir && ..."`, which is a shell-injection pattern." §4.4.8 itself warns that a `dir` read by the shell
> "can inject commands". Our own code (and our training data) already does what the spec warns against, because there
> is no other way.

- **sys** keeps LATER and names the two path rules that `cwd` needs.

> Q2 decided that the `PATH` search runs **in this program, before the child starts**. A `chdir` for `cwd` runs **in
> the child, after `fork`**. So with `cwd` set, two cases need a rule that nobody has written:
>
> 1. **A relative `cmd` with a `/`** (`process.run("./configure", [], cwd: Some("vendor/x"))`). Is `./configure`
>    relative to this program's directory or to `cwd`? Python on POSIX says `cwd` ("a relative path to the program is
>    interpreted relative to cwd"); Rust documents it as platform-dependent and a known trap. A shell user writing
>    `cd vendor/x && ./configure` expects `cwd`.
> 2. **A relative `PATH` entry** (`.` or `bin` in the child's `PATH`). The parent-side search resolves it against
>    this program's directory, but the child then runs in `cwd`. Either the search must resolve against `cwd` (so the
>    runtime joins paths itself, and must check the directory exists before it forks), or the spec states the
>    mismatch.

The D vote was 6-0 NOW.

- **Systems (sys): NOW**

> **Reasoning:** My LATER vote rested on "No consumer needs it", and the tree proves that wrong: hundreds of
> `sh -c "cd {dir} && ..."` sites in tests/, the shell-injection pattern §4.4.8 warns against, kept alive because no
> other way exists. My second reason, the two undebated path rules, is now answered in the NOW option itself
> (relative `cmd` with `/` and relative `PATH` entries resolve against the new `cwd`, the check runs in this program,
> `Err` from the call), and those are the rules I named as my starting point. The cost to the hardware is one path
> join and `access` check in the parent and one `chdir` in the child, both cheap and async-signal-safe.
>
> **Concern:** the parent-side check and the child's `chdir` are not atomic, so the runtime must still report a
> `chdir` or `exec` failure in the child back to the caller as `Err` (through a close-on-exec error pipe), not as an
> exit code from a child that never ran, or the "no child starts" rule is false in the race.

- **Web/Scripting (web): NOW**

> **Reasoning:** The tree count (553 lines in 275 test files) shows that the only way Blink has today to start a
> child in another directory is `sh -c "cd {dir} && ..."`, the form §4.4.8 says can inject commands. With `env:`
> alone, those lines keep the shell, so this edit would fix half of each command line and the corpus would keep
> teaching the shell string. sys's two path rules are now written into the NOW option. They match what a scripting
> dev expects from `cd dir && ./tool`, and they match Python's `cwd=` on POSIX, so there is nothing new to learn.
>
> **Concern:** A relative `PATH` entry resolved against the new `cwd` (for example `.` in `PATH`) can run a program
> from the target directory that the caller did not mean to run. The spec text should state this rule plainly, not
> only imply it.

- **PLT (plt): NOW**

> **Reasoning:** The D1 counts (hundreds of `sh -c "cd {dir} && ..."` sites in tests/) show that `cwd` has a real
> consumer. It is the other half of the same workaround that `env:` replaces. Adding only half leaves the shell, and
> the injection risk §4.4.8 warns about, on every one of those lines. The typing rule is the one we already accepted
> for `env`: a new value for the child, no mutation of this program, no `Env.Write`, row unchanged. sys's two path
> rules close the one gap I see. With a relative `cwd` resolved against this program's directory, and a relative
> `cmd` with `/` and relative `PATH` entries resolved against the new `cwd`, the program that runs is a function of
> (this program's cwd, `cwd`, the child's environment, `cmd`). That matches what `chdir` then `execvp` would do, so the
> parent-side search and the child agree.
>
> **Concern:** the parent-side check of `cwd` and the child's `chdir` are not atomic. If the directory goes away
> between them, the spec must still require `Err` from the call, with no child exit code. The runtime has to report a
> `chdir` failure in the child back to the parent, as `posix_spawn` does.

- **DevOps/tooling (devops): NOW**

> **Reasoning:** The consumer exists: 275 test files in this repo start a child with `sh -c "cd {dir} && ..."`, and an
> `env`-only change leaves the shell in every one of them. The shell form is also the worst diagnostic surface: a
> missing directory shows up as an exit code and an `sh: cd:` line in `err_out`, not as an `Err` that names the op and
> the command. sys's two path rules are no longer undebated gaps, because the NOW option on this ballot carries them,
> and they match what the replaced `cd dir && ./tool` line already does (Python's choice, which sys named as the
> starting point). One `handler Process` break with one machine fix is cheaper than a second break for a parameter the
> tree needs now.
>
> **Concern:** The parent-side check of a relative `cmd` and relative `PATH` entries against the new `cwd` must give an
> `Err` that names the resolved path. A bare `run ./configure: No such file or directory` hides which directory was
> searched, so the `ProcessError` `Display` (or a later chore) must make that visible.

- **AI/ML (aiml): NOW**

> **Reasoning:** This repo is training data, and it has 553 lines in 275 test files that run `sh -c "cd {dir} && ..."`
> because no other form exists. With `env:` alone, the corpus migration keeps the shell string on every one of those
> lines, so models keep learning the injection pattern that §4.4.8 warns against. With `cwd:` in the same edit, each
> line becomes one op call with no shell. sys's two rules are a real gap. The NOW option states them as Python and
> `execvp`-after-`chdir` do, which matches the `cd dir && ./tool` habit that both models and users bring, so they
> add no surprise for a learner.
>
> **Concern:** The relative-`PATH`-entry rule (resolved against the new `cwd`) is the one rule no seat debated in
> full. The spec example must show a relative `cmd` with `cwd:`, and the runtime test must cover a `.` entry in
> `PATH`, or an implementation can quietly use this program's directory instead.

- **Minimalism (min): NOW**

> **Reasoning:** My LATER vote rested on "no consumer", and the tree shows ~550 `sh -c "cd {x} && ..."` sites in
> tests/ (I correct my D1: the moderator's count is right, none are in src/ or lib/). The panel banned `set_cwd` and gave
> no per-child form, so the only route left is the shell-string pattern §4.4.8 calls unsafe; filling that hole is a
> foundational primitive, not speculation. Shipping `env:` alone leaves every one of those lines on `sh -c`, so the
> `env` change cannot finish its own job.
>
> **Concern:** sys's rule (2), a relative `PATH` entry resolved against the new `cwd`, gets no debate of its own in this
> vote, and a mismatch between the parent-side search and the child's directory is the latent bug most likely to ship.

### Final Spec

```blink
@derive(Eq, Debug)
pub type ChildEnv {
    Inherit                    // this program's environment, as it is when the op runs
    Change(Map[Str, Str?])     // that environment; Some(v) sets a name to v, None removes it
    Only(Map[Str, Str])        // exactly these variables, nothing inherited
}

fn run(cmd: Str, args: List[Str], *, stdin: Str? = None, env: ChildEnv = ChildEnv.Inherit, cwd: Str? = None) -> Result[ProcessResult, ProcessError]
fn spawn(cmd: Str, args: List[Str], *, env: ChildEnv = ChildEnv.Inherit, cwd: Str? = None) -> Result[Child, ProcessError]
fn exec(cmd: Str, args: List[Str], *, env: ChildEnv = ChildEnv.Inherit, cwd: Str? = None) -> Result[Never, ProcessError]
```

```blink
process.run("make", ["test"], env: ChildEnv.Change(Map.from([("CI", Some("1"))])))
```

Locked points:

- `env` and `cwd` are keyword parameters of `run`, `spawn` and `exec`. No op is new. Effect rows do not change: no `Env.Read` and no `Env.Write`.
- `ChildEnv` describes the environment of the child only. It is not a template for other per-child options.
- This program's environment does not change, and later children do not see the change.
- The inherited environment is read when the op runs. The read does not interleave with `env.set_var` and `env.remove_var`.
- A user `handler Env` or `mock_env` changes what `env.var` returns to Blink code. It does not change what a real child inherits.
- A bare `cmd` is found on the `PATH` of the child (the `PATH` after `env` applies). The search happens before the child starts. A miss is `Err` with `ENOENT` from the call. Under `Only(m)` with no `PATH` in `m`, a bare `cmd` gives `ENOENT`.
- A relative `cwd` is relative to the working directory of this program. A relative `cmd` that holds `/`, and a relative `PATH` entry, are resolved against `cwd`. A relative `PATH` entry such as `.` can then run a program from `cwd`, and the spec says so.
- A missing or invalid directory, or a missing program, gives `Err` with `ENOENT` (or the code the operating system gives). No child starts. This also holds when the directory goes away just before the child starts.
- An empty env name, an env name that holds `=` or NUL, a NUL in an env value, and a NUL in `cmd` or in any argument give `Err` with `EINVAL`. No child starts. This holds for `run`, `spawn` and `exec`.
- A `handler Process` implements each op with all its parameters. A default applies at the call site only. A handler with too few parameters gets an error that names the missing parameter and offers a fix that adds it.
- When a `Change` map has `Str` values where `Str?` is expected, the type error shows the call with each value wrapped in `Some(...)`.
- `stdin: Option[Str]` is respelled `stdin: Str?`.

### Implementation notes

These notes are not part of the spec.

- The runtime does its own `PATH` search, in this program before `fork`, with the `PATH` of the child and the new working directory. It cannot rely on `execvp`, which uses the `PATH` of this program.
- The runtime copies `environ` as raw bytes under the `env.set_var` lock, applies the `Change` or `Only` map, and releases the lock before `fork`. Variables that are not valid UTF-8 reach the child unchanged. All allocation happens in the parent.
- The child calls `chdir` after `fork`. The runtime opens a close-on-exec error pipe, so a `chdir` or `exec` failure in the child comes back to the caller as `Err`, never as an exit code. The parent-side check of `cwd` and the child-side `chdir` are not one step.
- The runtime scans `cmd`, every argument, every env name and every env value for NUL before any child starts, on `exec` too. It checks env names for the empty string and for `=`.
- Existing `handler Process` mocks gain the parameters `env` and `cwd` on `run`, and `env` and `cwd` on `spawn` and `exec`.
- Tests for each rule: `Inherit`, `Change` with `Some` and `None`, `Only`; `.` in `PATH` with a `cwd`; `Only` without `PATH` and a bare `cmd`; a `Change` that sets `PATH`; a missing `cwd`; a `cwd` that goes away before the child starts; a relative `cmd` with `/` and `cwd`; NUL in an argument and in `cmd`; `exec` with each rule; no change to the environment of this program after the call; a mock `Env` that does not reach a real child.

### Known gaps and follow-ups

1. Chore: the §4.1 `Request` example (`headers: ... = Map.new()`) breaks §2.21.
2. Friction: empty collections as const keyword defaults.
3. `PATH` search edge cases: empty `PATH` entries, and a child environment with no `PATH` beyond the `ENOENT` rule.
4. The `EINVAL` message does not say which string held the NUL. A `blink check` lint for literal names and arguments that hold `=` or NUL.
5. A handler-arity diagnostic with a fix-it (implementation).
6. Chore: move the `sh -c "cd {dir} && ..."` sites in tests/ to `cwd:` and `env:` once the ops exist.
7. Then the blocked chore that drops the `/usr/bin/env` wrapper in `blink test`.
8. The `Err` for a missing `cwd` or program names the resolved path (devops, Phase D concern). Not in the spec text.
