[< All Decisions](../DECISIONS.md)

# Runtime Trace, the Open Points — Design Rationale

**Question.** The runtime trace ([trace-ndjson-format.md](trace-ndjson-format.md), §8.15) left ten points open. Which code is a traced frame? How does the trace name a closure, a handler body, a default body and a test? How does a value render, and what does a user see for a type with a hidden field? What do the `effect` and `state` events say, and what is their `op`? How does a filter fail? How does a traced binary read its filter, and what does it do when the trace stream closes?

**Answer.** (1) A fn of the program or of a package, a method, a closure, a handler body, a default body of a user effect operation, and a `test` block that runs traced are frames. A std fn and a derived method are not. (2) A closure is `<enclosing frame>.fn@L:C`, a handler body is `<enclosing frame>.handler@L:C.<EffectPath>.<op>`, a default body is `module.<EffectPath>.<op>`, a test is `module.test@L:C`. A name holds no `<`, `>`, space or quote. (3) A value renders as `Display`, else `Debug`, else `<TypeName>`, for every type, also an opaque type and `Bytes`. (4) The `op` of an `effect` event is the call the program writes (`io.println`). A built-in effect has no module in `effect`; a user effect always has one. Each dispatch writes one event. (5) The `op` of a `state` event is `assign`, or the name of the mutating method. A part write gives one `assign` event with no `path` field. The first `let mut` binding gives no event. (6) A bad filter is a usage error with exit code 2. Under `blink run`, a name that no declaration matches is the same error. (7) A traced binary reads only `BLINK_TRACE`. `--trace-limit` and `BLINK_TRACE_LIMIT` are removed. A trace stream that closes stops the trace and not the program.

**Release note.** Four changes are visible to users. `--trace-limit` and `BLINK_TRACE_LIMIT` no longer exist. `BLINK_TRACE=1` is not a value; `all` is the word. A bad `--trace` filter, or a `blink run --trace` filter that names nothing in the program, now stops with exit code 2 before the program starts. The `fn` of a closure, a handler body, a default body and a test block has a new, stable form.

**Spec.** §8.15.1, §8.15.3, §8.15.4, §8.15.5, and the new §8.15.8 to §8.15.13 in `sections/06_tooling.md`; one sentence after the "Called by" table in §4.4 in `sections/04_effects.md`. No new error code: a usage error of the trace has no code, as a usage error of `blink test` has none (§8.10.7).

### Decision

| Q | Result | Tally | Dissent |
|---|---|---|---|
| Q1 | A `test` block is a frame when it runs traced: `"fn":"main.test@12:1"`, depth 0. | 5-1 | Minimalism: no rule until `blink test --trace` is in the spec |
| Q2a | A closure is `main.main.fn@5:29` (enclosing frame, keyword, line:col). | 6-0 | none |
| Q2b | A handler operation body is `main.main.handler@4:10.Log.emit` (effect and operation in the name). | 6-0 (Phase C 4-2) | none |
| Q2c | The default body of a user effect operation is `main.Log.emit`. | 6-0 | none |
| Q2d | A test block is `main.test@12:1`. | 6-0 | none |
| Q2e | A synthetic name holds no `<`, `>`, space or quote, so `--trace=fn:...` needs no shell quotes. | 6-0 | none |
| Q6a | An opaque type with a derived `Debug`: `Debug` applies as for any type. | 6-0 | none |
| Q6b | `Bytes` takes the normal chain (its own `Debug`). | 6-0 | none |
| Q7a | The `op` of an `effect` event is the call spelling the user writes: `io.println`, `io.print`, `io.print_raw`. | 5-1 | PLT: the handler operation |
| Q7b | One event per dispatch: `io.print_raw("c")` gives `io.print_raw`, then `io.print`. | 6-0 (Phase C 4-2 for the other option) | none |
| Q8 | A user effect is always module-qualified (`"effect":"p.Log"`). A built-in effect is bare (`IO.Print`). `effect:Log` and `effect:p.Log` both select the user effect. `op` is `"log.emit"`. | 5-1 | Minimalism: bare |
| Q9a | `=` and compound assignment give `assign`. A call of a `mut self` method on a `let mut` binding, or on a part of it, gives the method name. The set is open. | 6-0 (Phase C 4-2) | none |
| Q9b | The first `let mut` binding gives no event. | 6-0 | none |
| Q10 | No `path` field on a part write. | 6-0 (Phase C 4-2) | none |
| Q11a | Remove `--trace-limit` and `BLINK_TRACE_LIMIT`. | 6-0 | none |
| Q11b | A trace stream that closes stops tracing. The program runs to its end with its own exit code. | 6-0 | none |
| Q12 | Under `blink run` only, after the typecheck and before the program starts, each `fn:`, `module:`, `effect:` and `state:` value must name a declaration, else the usage error, exit code 2. A declared name that never runs is not an error. A binary that a person starts by hand does not check. | 5-1 | Minimalism: no check |

**Conditions of Q12.** Systems and PLT made their vote depend on two rules, and the spec states both: the check uses the same suffix matcher as the runtime, over the full name table of the program (frames, modules, effects, `let mut` names), synthetic names included; and a name declared in code that the build drops still counts.

**Agreed by all six, not voted.** `effect:` selects by whole dot segment (`effect:FS` selects `FS`, `FS.Write` and `FS.Read`; `effect:F` selects nothing; `effect:FS.Write` does not select `FS.Read`). A std fn is not a frame, and `depth` counts traced frames only. A package fn is a frame. An effect operation anywhere gives an `effect` event, credited to the innermost traced frame. The `args` of an `effect` event hold every parameter of the operation by its declared name (`msg` for `io.println`), and are omitted when there are none. A write to a part (`p.x = 1`) gives one `state` event with `var` = the root and `value` = the whole binding. A bad key, an empty value, a bad `depth:` and an unknown `event:` are a usage error with exit code 2 before `main`, also for `BLINK_TRACE`; `blink run` checks before it builds. A derived method is not a frame, and a method is `module.Type.method`. A closure and a handler body are frames. A `Display` or `Debug` call that the tracer makes writes no events. `fn:X` matches a `fn` that equals `X` or ends in `.X`, on whole segments. A value renders as `Display`, else `Debug`, else `<TypeName>`, and is never left out. The traced binary reads only `BLINK_TRACE`; `blink run --trace[=f]` sets it for the child (bare = `all`) and replaces an inherited value; a binary with `BLINK_TRACE` unset traces all; `BLINK_TRACE=1` is dropped. A call of a mutating method gives one `state` event, also when nothing changes.

**Phase D moves.** Systems and Minimalism moved to Q2b-pos-effect-op. Web/Scripting, DevOps/Tooling, AI/ML and Minimalism moved to Q7b-each. PLT and Minimalism moved to Q9a-method. Systems and DevOps/Tooling moved to Q10-none. Systems and PLT moved to Q12-run-error. Minimalism held Q12-none.

**Dissent.** Each dissent below is the full text of the section of the ballot of the seat, copied without change.

*Minimalism on Q1 (a `test` block gets no frame rule).*

> **Q1. Is a `test` block a frame?**
> **Vote:** Q1-no-rule
> **Reasoning:** No part of the spec has `blink test --trace`, so a rule for test frames constrains a
> flag that does not exist. When someone specs that flag, the frame rule goes in with it, under the
> same naming rule as Q2. Spec text with no flag to use it is dead surface.
> **Concern:** If Q1-frame wins, the frame rule will come before the flag spec, and the flag spec may
> then not fit it.

*PLT on Q7a (the `op` of an `effect` event is the handler operation).*

> **Q7a — Q7a-operation**
> An effect event observes an operation, which is what a handler receives. `io.println` is a generic
> std fn wrapper, and 2a says std fns are not frames. If the call spelling is used, each wrapper needs
> its own spec entry, and the event no longer agrees with what an intercepting handler sees.
> Concern: if the call spelling wins, the spec must list each wrapper's op string and its `args` key,
> and keep that list current.

*Minimalism on Q8 (a user effect is bare in `effect`).*

> **Q8. `effect` for a user effect**
> **Vote:** Q8-bare
> **Reasoning:** Q8-always gives two spelling rules (builtin bare, user qualified) and a filter that
> must accept both names. `module` and `fn` already say where the call ran, and a name collision is
> rare.
> **Concern:** Two `Log` effects in one program read the same in `effect`, and a `jq` script must also
> check `fn` to tell them apart.

*Minimalism on Q12 (no check of filter names), Phase D.*

> **Q12**
> **Vote:** Q12-none
> **Reasoning:** The check is a second copy of the matcher, in the CLI, that must agree with the
> runtime on the V4 suffix rule, every synthetic name, dep modules and dead code. If one rule drifts,
> `blink run` rejects a valid filter, and that is worse than an empty trace, because the user then
> cannot trace at all. The spec can say in one sentence that an empty trace means the filter matched
> nothing.
> **Concern:** A one-character typo in `fn:` gives an empty trace, and an agent reads it as "never
> called".

**Follow-ups, open.** The ruling leaves these to other work. (1) `blink test --trace` and `blink build --trace` are not in the spec, so the spec cannot say how a test run turns tracing on. (2) A trait default body has no frame name in this ruling. (3) The name of a closure inside a closure, and of a closure in a module-level initializer, follows the rule "the enclosing frame"; the panel did not test these two cases.

### Panel Deliberation

Six seats voted: Systems, Web/Scripting, PLT, DevOps/Tooling, AI/ML and Minimalism. Each quote below is the full text of the reply of the seat, copied without change. The only edits: a ticket ID in the heading of a reply is removed, and the directory in front of a scratch file name is removed. The moderator digests are not quoted.

#### Phase A — Proposals

Each seat answered the brief alone.

**Systems**

> # Phase A — sys seat
>
> Ground rule I apply to every point: a traced build (`trace_codegen`, compile time) may cost what it
> likes per frame; an untraced build pays zero. Cost that lands in the shared std archive must be one
> predicted branch on a global flag, and only on paths that are already expensive (an effect dispatch).
>
> ## Two cost rules the spec must carry (they shape points 3, 7, 8)
>
> - **Bounded formatting.** Every value string is written through a sink that stops at 201 bytes. Without
>   this, `state` on `xs.push(i)` in a loop formats the whole list each time: O(n^2). With it, each event
>   is O(1) past the cut. The 200-char cap is a cost rule, not only a size rule.
> - **Muted formatting.** While the tracer formats a value, it writes no events. A user `display()`
>   called by the tracer is not a frame. Else a Display impl recurses into the trace.
>
> ## (1) Frames
>
> A frame is a body the user wrote, compiled in the user build. Name rule: `module.path`, and a
> synthetic frame takes the keyword that opened it in source. Keywords are not identifiers, so these
> names cannot collide with a user fn.
>
> | Body | traced | `fn` |
> |---|---|---|
> | fn | yes | `geom.area` |
> | method / trait impl method / trait default body | yes | `geom.Point.dist` |
> | closure | yes | `main.main.fn@4:20` (line:col of `fn`; exit/state events have no span, so the name must tell two closures apart) |
> | handler op body | yes | `main.handler Log.emit` |
> | effect op default body (user effect) | yes | `main.effect Log.emit` |
> | `test` block | yes, depth 0 | `main.test "adds two"` |
> | `@derive` method | no | — (no body the user wrote; floods sort/Map paths) |
>
> Mono copies share the source name (`main.id`, never the mangled C name). `fn:` short form matches the
> part after the last `.` (`fn:emit`, `fn:dist`), as the runtime does today.
>
> ```blink
> fn apply(xs: List[Int]) -> List[Int] {
>     xs.map(fn(x: Int) -> Int { x * 2 })
> }
> ```
> ```json
> {"ts_us":5,"event":"enter","fn":"main.apply","module":"main","depth":1,"span":{"file":"p.bl","line":1,"col":1},"args":{"xs":"[1, 2]"}}
> {"ts_us":6,"event":"enter","fn":"main.apply.fn@2:12","module":"main","depth":2,"span":{"file":"p.bl","line":2,"col":12},"args":{"x":"1"}}
> {"ts_us":6,"event":"exit","fn":"main.apply.fn@2:12","module":"main","depth":2,"duration_us":0,"return":"2"}
> ```
> Depth counts traced frames only: `List.map` (std) is invisible, so the closure is depth 2, not 3. Say
> so in the spec; depth is not the C stack depth.
>
> ## (2) std and packages
>
> - std fns: no frames. Tracing them needs a second archive (double build and disk) or a branch in
>   every std call in every program (a tax on untraced code). Neither is worth it.
> - Package fns: frames. Packages compile from source in the user build; the bug you hunt is often in
>   a dep. `module:` cuts them out.
> - **Effects: one `effect` event per operation performed, wherever it is performed** (user code, std,
>   a default body). `fn`/`module`/`depth` name the innermost traced frame. The event fires at the
>   dispatch point, before the handler runs, so a handled op also gives an event. Cost in the archive: one
>   branch on a flag that is constant-false in untraced builds, next to an indirect call or a syscall.
>   strace works the same way: it shows syscalls, not libc frames.
>
> ## (4)+(5) Effect `op`, `effect`, `args` — one rule for builtin and user effects
>
> The spec says `io.println` is a std wrapper; the operation is `IO.Print.print(msg: Str)` (§4.4). An
> effect event reports the **operation**, not the wrapper:
> - `op` = handle form of the operation: `io.print`, `fs.write`, `log.emit`, `metrics.counter`.
> - `effect` = the declared (sub-)effect that holds the op: `IO.Print`, `Log`, `Metrics.Emit`. Not
>   module-qualified, same as rows.
> - `args` = every param, keyed by its declared name, each a value string (rule 3). No per-op list to
>   maintain; a new op needs no spec change. `Bytes` gives `<N bytes>` by rule 3.
> - A derived op whose default body performs another op gives two events (`print_raw`, then
>   `print_no_nl`), as strace shows each syscall.
>
> MVCE (`p.bl`):
> ```json
> {"ts_us":0,"event":"enter","fn":"p.main","module":"p","depth":0,"span":{"file":"p.bl","line":2,"col":1}}
> {"ts_us":2,"event":"enter","fn":"p.add","module":"p","depth":1,"span":{"file":"p.bl","line":1,"col":1},"args":{"a":"1","b":"2"}}
> {"ts_us":3,"event":"exit","fn":"p.add","module":"p","depth":1,"duration_us":1,"return":"3"}
> {"ts_us":5,"event":"effect","fn":"p.main","module":"p","depth":0,"effect":"IO.Print","op":"io.print","args":{"msg":"3"}}
> {"ts_us":21,"event":"exit","fn":"p.main","module":"p","depth":0,"duration_us":21,"return":"()"}
> ```
> User effect:
> ```blink
> effect Log { fn emit(s: Str) }
> fn run() ! Log { log.emit("hi") }
> fn main() ! IO {
>     with handler Log { fn emit(s: Str) { io.println(s) } } { run() }
> }
> ```
> gives `effect` `{"effect":"Log","op":"log.emit","args":{"s":"hi"},"fn":"main.run","depth":1}`, then
> `enter` `main.handler Log.emit` at depth 2, then `effect` `io.print` inside it at depth 2.
>
> This changes §8.15.4: `fs.write` shows its content param too (truncated). The writer's question is
> "why does out.c hold the wrong text"; the first 200 chars answer it, at bounded cost. Fix the
> `"op":"io.println"` example in the schema table to `io.print`.
>
> ## (3) No Display impl
>
> Chosen per instantiation at mono time, so no runtime dispatch: Display; else Debug; else
> `<TypeName>` (`<fn(Int) -> Int>`, `<Handler[Log]>`, `<Bytes>` shows as `<N bytes>`). Debug fallback
> is a must: `Result` has no Display, and a `Result` return is the most common thing an agent wants to
> read. Omitting the field loses the key and makes the schema shape depend on the type.
>
> Known limit, same as `trace.log`: a user Display/Debug that panics panics only when traced.
>
> ## (6) `effect:` hierarchy
>
> Yes: `effect:FS` matches `FS`, `FS.Write`, `FS.Read`; match on whole `.` segments (`effect:F` does
> not match `FS`). Same rule as a row. Cost: a prefix compare plus one byte check, set up once at init.
>
> ## (7)+(8) State ops
>
> Rule: `op` = `"assign"` for `=` and compound `+=` etc.; for a `mut self` method call on a `let mut`
> binding, `op` = the method's own name. The spec's `push`/`pop`/`insert`/`remove` are already method
> names (`Map` uses `insert`), so this rule keeps them and covers `clear`, `extend`, `sort`, `set`,
> `truncate`, ... with no mapping table. The op is a static string: zero cost. The compiler emits the
> event at the user call site (it sees the receiver and the `mut self`), so std being untraced does not
> matter. A non-mutating method (`xs.len()`) gives no event.
>
> Field and index writes: an event. `var` = the root binding (`"p"`), so `state:p` keeps working.
> `op` = `"assign"`. Add an optional `path` field: `".x"`, `"[2]"`, `".items[2].name"`. Reason: `value` is
> the whole binding, cut at 200 chars; on a big struct the changed field can sit past the cut, and then
> the event says nothing. A field path is a static string; an index costs one Int format.
>
> ```blink
> fn main() ! IO {
>     let mut p = Point { x: 0, y: 0 }
>     p.x = 5
>     let mut xs = [3, 1, 2]
>     xs.sort()
> }
> ```
> ```json
> {"event":"state","fn":"main.main","var":"p","op":"assign","path":".x","value":"Point { x: 5, y: 0 }",...}
> {"event":"state","fn":"main.main","var":"xs","op":"assign","value":"[3, 1, 2]",...}
> {"event":"state","fn":"main.main","var":"xs","op":"sort","value":"[1, 2, 3]",...}
> ```
>
> ## (9) argv
>
> The traced binary should read no argv. `blink run --trace[=f]` passes the filter to the child as
> `BLINK_TRACE` (bare = `all`), and `env.args()` is untouched. Then nothing to hide, and a program that
> parses its args with `std.args` does not die on an unknown `--trace` under tracing (the observer must
> not change the program). strace and `GODEBUG` take config outside the target's argv for the same
> reason. A traced binary run by hand reads `BLINK_TRACE`; unset means trace all (it was built to trace).
> Cost of a traced child that inherits the var: only a traced build reads it.
>
> If the panel keeps argv: strip `--trace` and `--trace=<f>` items before the first `--` from
> `env.args()`, keep `--` and all after it.
>
> Separately: `--trace-limit` / `BLINK_TRACE_LIMIT` exist in the runtime and not in the spec. Spec them
> or delete them; an unspecced knob is a latent bug.
>
> ## (10) Bad filter
>
> An error, never ignored: the runtime today ignores an unknown key, so `fnx:parse` traces everything,
> which is the worst case (flood, and the user thinks the filter works). Parsing is once at start: free.
> - `blink run`: check before the build. Text to stderr, exit 2 (usage error, as `blink test`).
>   `error: --trace: unknown filter key "fnx" (keys: fn, module, depth, event, effect, state)`;
>   `error: --trace: depth wants a whole number, got "abc"`; `error: --trace: unknown event "exits"`.
> - Traced binary with a bad `BLINK_TRACE`: the same line, exit 2, before `main` runs.
> - A well-formed value that names nothing (`fn:nope`, `effect:FS.Wrte`) is not an error: the binary
>   cannot know every name cheaply, and an empty trace is a correct answer.

**Web/Scripting**

> # Phase A — Web seat
>
> My test for each point: a JS or Python dev opens `trace.ndjson` and runs `jq`. Can they guess the
> answer without reading the spec? Each rule below is one I can say in one sentence.
>
> ## P1. Frames: every body of user source code is a frame
>
> Named fns, methods, closures, handler op bodies and `test` blocks each get their own enter/exit and
> add one depth step. Derived methods do not: they have no source the user wrote, and `==` on a
> derived `Eq` would flood the trace.
>
> `fn` names: `module.fn`, `module.Type.method`, and a bracket tag for an unnamed body, the same as
> Python's `<lambda>` and `<module>`. A bracket cannot appear in a Blink name, so the tag never
> collides with one:
>
> | Body | `fn` |
> |---|---|
> | method `norm` on `Point` | `main.Point.norm` |
> | closure in `main.outer` | `main.outer.<closure>` (the `span` tells two closures apart) |
> | handler op `emit` for `Log`, in `main.run` | `main.run.<handler Log.emit>` |
> | `test "adds"` | `main.<test adds>` |
>
> ```blink
> fn main() ! IO {
>     let xs = [1, 2].map(fn(x) { x * 2 })
>     io.println("{xs}")
> }
> ```
> ```json
> {"ts_us":0,"event":"enter","fn":"main.main","module":"main","depth":0,"span":{"file":"p.bl","line":1,"col":1}}
> {"ts_us":3,"event":"enter","fn":"main.main.<closure>","module":"main","depth":1,"span":{"file":"p.bl","line":2,"col":24},"args":{"x":"1"}}
> {"ts_us":4,"event":"exit","fn":"main.main.<closure>","module":"main","depth":1,"duration_us":1,"return":"2"}
> ...
> ```
> `fn:norm` and `fn:Point.norm` both match `main.Point.norm` (a short name matches on a `.` boundary).
>
> **A hard rule:** the tracer does not trace the code that renders a value for the trace. A user
> `impl Display` on an arg type is a traced method when the program calls it, but when the tracer calls
> it to render `args`, it writes no events. Without this rule, each enter writes more enters.
>
> Cross-language: Python `sys.settrace` gets a frame for each lambda and comprehension; Chrome DevTools
> shows `(anonymous)`. Users expect closures in the trace, mostly in `map`/`filter` callbacks.
>
> ## P2. std is not traced; its effects are
>
> std fns write no enter/exit/state. This is "Just My Code" (the VS Code Python debugger default):
> std internals are noise to a user. A closure that a std fn calls back is still traced, and its depth
> is the depth of the nearest traced frame plus 1 (depth counts traced frames only, so there are no
> gaps).
>
> Package code (dependencies built from source) is traced like the user's own code. `module:` removes
> it. One rule to learn: "code compiled from source is traced; the prebuilt std is not."
>
> An effect that a std fn does IS an event. Its `fn`, `module` and `depth` come from the nearest traced
> frame. Effects are what the program does to the world. If `std.json.write_file(path, v)` hides its
> `fs.write`, then `--trace=effect:FS` lies. Cost: the hook sits in the runtime effect ops behind one
> global flag check, so the prebuilt archive does not need a second build.
>
> ## P3. No Display: Debug, then `<TypeName>`
>
> Use Display; if the type has no Display, use the Debug form; if neither, write `"<TypeName>"`
> (`"<Sha256>"`, `"<fn(Int) -> Int>"`, `"<Handler[Log]>"`). Never omit the field. A jq script that
> reads `.args.p` must not get `null` because a type lacks an impl. Python's default repr
> `<Foo object at 0x...>` is the model; drop the address (it is noise and it breaks diffs of two
> traces).
>
> ## P4. Effect `args`: every param, keyed by the op's declared param names
>
> `io.println(x)` performs `IO.Print`'s `fn print(msg: Str)`, so it gives `"args":{"msg":"3"}`.
> `env.var("HOME")` → `{"name":"HOME"}`. `process.run("ls", ["-l"])` → `{"cmd":"ls","args":"[-l]"}` and
> the keyword params too, with their values or defaults. A zero-param op (`time.now()`) omits `args`,
> the same as `enter` does.
>
> The §8.15.4 example drops `content` from `fs.write`. I would change the example and keep the rule
> simple: all params. The 200-character cap already bounds the cost, and "what did my program write?"
> is a common debug question. A table of omitted params per op is a table that people must look up and
> that each new op must update.
>
> MVCE output (the tail):
> ```json
> {"ts_us":9,"event":"effect","fn":"main.main","module":"main","depth":0,"effect":"IO.Print","op":"io.println","args":{"msg":"3"}}
> ```
>
> ## P5. User effect op: the same form as a builtin
>
> `effect` = the effect path as a row names it (`"Log"`, `"Metrics.Emit"`). `op` = the call as the
> user wrote it, handle plus op (`"log.emit"`, `"metrics.counter"`). That is the exact shape of
> `"IO.Print"` / `"io.println"`. The user greps for what they typed.
>
> ```blink
> effect Log { fn emit(s: Str) }
>
> fn run() ! Log { log.emit("hi") }
> ```
> ```json
> {"ts_us":5,"event":"effect","fn":"main.run","module":"main","depth":1,"effect":"Log","op":"log.emit","args":{"s":"hi"}}
> {"ts_us":6,"event":"enter","fn":"main.main.<handler Log.emit>","module":"main","depth":2,"span":{...},"args":{"s":"hi"}}
> ```
> The effect event comes at the call site, before the handler body runs.
>
> ## P6. `effect:FS` selects `FS.Write`: yes
>
> A parent selects its children, on a `.` boundary, the same as in a row. `effect:FS` matches
> `FS.Write` and `FS.Read`; `effect:F` matches neither; `effect:FS.Write` does not match `FS.Read`.
> Users already learned this rule from `! FS`. Two meanings for one name would be a trap.
>
> ## P7. State ops: `op` = the method name, or `assign`
>
> Do not map methods onto five words. `op` is the name of the mutating method that the code called
> (`"push"`, `"set"`, `"clear"`, `"extend"`, `"insert"`, ...). A `=` or a compound assignment
> (`+=`) is `"assign"`. The five names in §8.15.3 become examples, not a closed set.
>
> Why: `xs.clear()` that reads `"op":"assign"` is a Stack Overflow question. A method name needs no
> table, and new std methods need no spec change. `value` is the whole binding after the change (as
> settled), so a jq user who wants only "did it change" ignores `op`.
>
> ## P8. Field and index writes: an event, `var` = the root binding
>
> `p.x = 1` and `xs[i] = v` give a state event with `"var":"p"` / `"var":"xs"`, `"op":"assign"`, and
> the whole binding as `value`. `state:p` then selects every change to `p`, which is what the user
> asked for. A path in `var` (`"p.x"`, `"xs[2]"`) would make `state:p` miss them.
>
> ```blink
> fn main() ! IO {
>     let mut p = Point { x: 0, y: 0 }
>     p.x = 1
> }
> ```
> ```json
> {"ts_us":2,"event":"state","fn":"main.main","module":"main","depth":0,"var":"p","op":"assign","value":"Point { x: 1, y: 0 }"}
> ```
>
> ## P9. Hide `--trace` items from `env.args()`: yes
>
> The runtime removes each `--trace` and `--trace=<f>` item before the first `--` item. `node --inspect
> app.js` and `python -X dev` do not show their own flags to the program either. If we do not hide
> them, every program that uses `std.args` fails under `--trace` with "unknown flag --trace". That is
> the first thing a new user tries, and it breaks.
>
> Only a binary built for tracing reads and removes these items. A normal `blink build` binary passes
> argv to the program without change, so a program that takes its own `--trace` flag still works in
> production.
>
> Side note: the runtime also reads `--trace-limit` and `BLINK_TRACE_LIMIT`, which the spec does not
> have. Spec them or remove them; an unspecified flag that eats argv is a latent bug.
>
> ## P10. A bad filter is a usage error, exit 2, before `main` runs
>
> An unknown key, an empty value (`fn:`), a non-integer `depth:abc`, an unknown `event:` type: the
> program writes one line to stderr and exits with code 2 (the code `blink test` uses for a usage
> error). It does not run.
>
> ```
> error: bad --trace filter `fnx`: unknown key `fnx`; did you mean `fn`?
>   keys: fn, module, depth, event, effect, state
> ```
>
> The same for `BLINK_TRACE`: the user set it for this run, so the same input gets the same answer.
>
> A name that matches nothing (`fn:typo`) is not an error at run time: the binary has no cheap table
> of names, and the output is an empty trace. `blink run` compiled the program and has the table, so
> it can warn `--trace filter fn:typo matches no function` and run anyway. "My trace is empty and I do
> not know why" is the top question that silent-ignore makes; an error for syntax plus a warning for
> names answers it.
>
> Cross-language: `RUST_LOG` ignores bad directives without a sound, and people lose hours to that.
> `strace -e trace=bogus` exits with an error at once. Copy strace.

**PLT**

> # Phase A — PLT seat
>
> Two principles drive every ruling below.
>
> - **P1, non-interference.** A traced run and an untraced run of the same binary have the same
>   stdout, exit code, effect sequence and env.args(). Only extra stderr lines differ.
> - **P2, the trace projects the semantics.** `enter`/`exit` mark function applications that have
>   source text. `effect` marks operations performed. `state` marks store transitions. Each rule must
>   come from this mapping, not from a hand-written list.
>
> ## (1) Frames
>
> Every application of a function the user wrote is a frame: one `enter`, one `exit`, depth + 1.
>
> | Construct | Frame? | `fn` |
> |---|---|---|
> | top-level fn | yes | `main.add` |
> | method | yes | `main.Point.norm` (type in the middle; `fn:norm` and `fn:Point.norm` both match) |
> | closure | yes | `main.outer.{closure}`; the `span` on `enter` tells two closures apart |
> | handler op body | yes | `main.{handler Log}.emit` |
> | `test` block | yes, depth 0 | `main.{test "adds"}` |
> | derived method | no | no source text, so no span; same class as std (point 2) |
>
> ```blink
> fn twice(f: fn(Int) -> Int, x: Int) -> Int { f(f(x)) }
> fn main() ! IO { io.println("{twice(fn(n) { n + 1 }, 1)}") }
> ```
> ```json
> {"event":"enter","fn":"main.main","module":"main","depth":0,...}
> {"event":"enter","fn":"main.twice","module":"main","depth":1,...,"args":{"f":"<fn(Int) -> Int>","x":"1"}}
> {"event":"enter","fn":"main.main.{closure}","module":"main","depth":2,"span":{"file":"p.bl","line":2,"col":34},"args":{"n":"1"}}
> {"event":"exit","fn":"main.main.{closure}","module":"main","depth":2,"duration_us":0,"return":"2"}
> ...
> ```
> The closure's `fn` names the fn that holds its source, not its caller (lexical, not dynamic). The
> `{...}` braces can not occur in an identifier, so no name collides with a user fn. Python's
> `<lambda>` and Rust's `{{closure}}` do the same.
>
> ## (2) std and package fns
>
> - std fns: no frames. The archive has no source a user reads, and P1 forbids a second archive.
> - **Package fns: frames.** A package is user source, compiled per program. Its `module` is its
>   module path, so `module:` filters them out.
> - **An effect performed inside a std fn: an event.** An effect is observable whoever performs it.
>   Its row reaches the user fn. Dropping it would make the trace show an effect sequence that differs
>   from the real one. The event takes `fn`/`module`/`depth` of the nearest traced frame:
>
> ```blink
> import std.fs
> fn save(p: Str) ! FS { fs.write(p, "x") }     // fs.write calls a std helper, which opens the file
> ```
> ```json
> {"event":"effect","fn":"main.save","module":"main","depth":1,"effect":"FS.Write","op":"fs.write","args":{"path":"out","content":"x"}}
> ```
> Cost: one load and a branch on a runtime global per op, in the archive. That is the only trace
> hook the archive needs.
>
> ## (3) A value with no Display
>
> Values stay Display strings (settled). For a type with no Display, the field still appears: an
> omitted key would make `args` change shape with the type, which breaks a consumer. Rule, chosen per
> **instantiated** type at mono time (so a generic fn renders `T` by its actual type):
>
> 1. `Display` impl: Display.
> 2. else `Debug` impl: Debug.
> 3. else `<TypeName>`, the type as Blink writes it: `<Point>`, `<List[Point]>`, `<fn(Int) -> Int>`.
>
> ```blink
> @derive(Debug)
> type Point { x: Int, y: Int }
> type Opaque { n: Int }
> fn f(p: Point, o: Opaque) -> Int { p.x + o.n }
> ```
> `"args":{"p":"Point { x: 1, y: 2 }","o":"<Opaque>"}`
>
> The renderer runs no traced frames and emits no events (a Display impl must not trace itself, or
> the trace recurses). Known limit, as with a lazy `trace.log` msg: a Display impl that panics panics
> only under trace. Cross-language: Go's `%v` falls back the same way; OpenTelemetry drops unknown
> types, which loses data.
>
> ## (4) Effect `args` for builtin ops
>
> Every parameter, keyed by the name in the op's declaration. No list per op; the signature is the
> list. 200-char truncation bounds size already. So `fs.write` gives `{"path","content"}`, and the
> §8.15.4 example must add `content` (the spec is the blueprint; the example is wrong under a uniform
> rule). An op with no params omits `args`, as `enter` does. The keys come from the declarations, so
> the spec needs a table only where a builtin op's param names are not in §4 already
> (`io.println(x)`: key `x`; `env.var(name)`: key `name`).
>
> Tradeoff: secrets in `env.var` values or written content reach stderr. That is true of any tracer
> (strace prints `write` buffers). The user turned trace on; the spec should say so in one note, not
> filter.
>
> ## (5) User effect names
>
> Use the same two forms as builtins, which are already consistent:
> - `effect` = the effect path as a row writes it: `"Log"`, or `"Metrics.Emit"` for a sub-effect op.
> - `op` = the handle call form: `"log.emit"`, `"metrics.counter"`.
>
> ```blink
> effect Log { fn emit(s: Str) }
> fn run() ! Log { log.emit("hi") }
> ```
> `{"event":"effect","fn":"main.run",...,"effect":"Log","op":"log.emit","args":{"s":"hi"}}`
>
> If two modules each declare `Log`, prefix the declaring module: `"effect":"util.Log"`. The `effect:`
> filter then matches the short or the full name, the same rule as `fn:`. The `effect` event comes at
> the perform site, before the handler body's `enter` (point 1). So a reader sees the op, then the
> handler that answered it.
>
> ## (6) `effect:FS` matches `FS.Write`: yes
>
> The filter must mean the same relation as a row: `! FS` grants `FS.Write`, so `effect:FS` selects
> `FS.Write`. Match on whole dot segments: `effect:FS` matches `FS` and `FS.*`, never `FSx`.
> `effect:FS.Write` matches only `FS.Write`. A filter that disagrees with the row lattice would make
> the trace use a second, different meaning for one name.
>
> ## (7) State ops
>
> Keep the closed set of five. `value` is the whole post-state (settled), so `op` is only a label for
> the kind of transition, and every transition is an `assign` of the store in the denotation. Rule:
>
> | op | methods |
> |---|---|
> | `push` | `List.push` |
> | `pop` | `List.pop` |
> | `insert` | `List.insert`, `Map.insert`/`Map.set`, `Set.insert` |
> | `remove` | `List.remove`, `Map.remove`, `Set.remove` |
> | `assign` | `=`, `+=` and the other compound forms, `List.set`, `clear`, `extend`, sort in place, every other mutating method |
>
> One event per call of a mutating method, even when the store does not change (`pop` on an empty
> list): the call is what the reader asks about, and "did it change" needs a compare at run time.
>
> ## (8) Field and index writes
>
> Yes, an event. `var` = the root binding (`"p"`, `"xs"`), `op` = `"assign"`, `value` = the whole
> binding post-write.
>
> ```blink
> fn main() ! IO {
>     let mut p = Point { x: 0, y: 0 }
>     p.x = 1
> }
> ```
> `{"event":"state","fn":"main.main",...,"var":"p","op":"assign","value":"Point { x: 1, y: 0 }"}`
>
> The store location is the binding, so `state:p` must select every write under `p`. `var:"p.x"`
> would make `state:p` miss it, or need a prefix rule. The place is in the value.
>
> ## (9) argv: the runtime must not read argv
>
> Today's runtime reads `--trace` from argv and leaves it there. That breaks P1 both ways: a program
> that parses its args sees an unknown `--trace`, and a program with its own `--trace` flag gets
> traced. Hiding the items fixes the first and not the second. Ruling:
>
> - A traced binary takes its config from `BLINK_TRACE` only. env.args() is never changed.
> - `blink run app.bl --trace[=f]` sets `BLINK_TRACE` for the child (`all` for bare). That flag is
>   `blink run`'s own, not the program's.
> - Running a traced binary by hand: `BLINK_TRACE=fn:add ./app`.
>
> Go does this (`GODEBUG`, `GOTRACEBACK`); the JVM keeps runtime flags out of `main(String[])`.
>
> ## (10) Bad filters: usage error, exit 2
>
> A filter is a predicate. A string with no meaning as a predicate must not run as "all" or "none".
> Errors, checked before `main` runs, nothing on stdout, exit 2 (as `blink test` usage errors):
>
> - unknown key: `trace: unknown filter key 'fnx' (keys: fn, module, depth, event, effect, state)`
> - `depth:abc`, `depth:-1`: `trace: depth takes a non-negative integer, got 'abc'`
> - `event:foo`: `trace: unknown event type 'foo'`
> - empty value (`fn:`), missing `:`: `trace: filter item 'fn' has no value`
>
> `blink run` checks the filter before it builds, so a typo costs no compile. A well-formed filter
> that matches nothing (`fn:nosuch`, `effect:Nope`) is not an error: that fn may not exist in this
> build, and that is a fact about the program, not about the predicate. `fn:a,fn:b` is a valid AND
> that selects nothing; no rule needed.

**DevOps/Tooling**

> # Phase A — DevOps/Tooling seat
>
> My test for every point: when an agent or a person reads an empty or odd trace, can they tell
> "the code did not do it" from "the tracer did not show it"? A trace that is silent by accident
> reads as a false fact. Most of my votes follow from that.
>
> ## (10) Bad filter: usage error, exit 2, before `main` runs
>
> Current runtime: unknown keys are dropped and `depth:abc` is `atoi` = 0. So `--trace=fnx:add`
> traces everything, and `--trace=depth:abc` traces only depth 0. Both look like real data.
>
> Behavior: the trace runtime parses the filter before `main`. On a bad filter it writes one text
> line to stderr and exits 2 (the same code `blink test` uses for a usage error, §8.10). `blink run`
> parses the same filter before it builds, so the user sees the error in under a second, not after a
> link.
>
> ```
> $ blink run p.bl --trace=fnx:add
> error: unknown trace filter key `fnx`; did you mean `fn`?
>   keys: fn, module, depth, event, effect, state
> $ blink run p.bl --trace=depth:abc
> error: trace filter `depth:abc`: depth takes a non-negative integer
> $ blink run p.bl --trace=event:enter+exitt
> error: trace filter `event:exitt`: unknown event type; did you mean `exit`?
> ```
>
> These are errors: an unknown key; a key with no `:value` (except bare `--trace`); a bad `depth`
> value; an `event` value outside the five types; a second `depth` (`depth:2+3`). Not errors: a
> `fn`, `module`, `effect` or `state` value that names nothing. A name can be valid and not fire
> on this run, and the runtime has no full name table. The same rules apply to `BLINK_TRACE`.
> `RUST_LOG` warns and goes on, but a warning line breaks "every stderr line is JSON", so the choice
> is an error or silence, and silence is the bug above.
>
> ## (9) Trace flags leave `env.args()`
>
> A program with its own arg parser sees `--trace`, prints "unknown flag" and exits 2. Then tracing
> changes what the program does, which defeats tracing. The runtime removes `--trace` and
> `--trace=<f>` from argv before `env.args()` sees them. It stops at the first `--`. It keeps that
> `--` and every item after it, so `prog -- --trace` passes the literal flag through. Prior art: GHC
> `+RTS ... -RTS`, JVM `-X` flags, Go test binaries with `-test.*`.
>
> Scope: only a binary built with trace on (`blink run --trace`, `blink build --trace`) reads or
> removes these flags. A plain `blink build` binary has no trace runtime (`blink_trace_init` is
> emitted only under trace today). It passes `--trace` to the program as it does any other argv
> item. Without this rule, a shipped CLI that has its own `--trace` feature would lose that flag.
>
> Side note for the writer, not a vote: `--trace-limit` and `BLINK_TRACE_LIMIT` exist in the runtime
> and not in the spec. Spec them or remove them. If they stay, the strip rule covers them.
>
> ## (1) Frames: each user-written body that runs as a call
>
> Rule: a body that the user wrote and that the program calls is a frame, with its own `enter`,
> `exit` and depth step. A body the compiler made is not a frame. Names have no spaces outside
> test names, so `--trace=fn:...` needs no shell quoting.
>
> | Body | `fn` value | Traced |
> |---|---|---|
> | top-level fn | `main.add` | yes |
> | method (trait impl) | `main.Point.sum` (type, then method; not the trait) | yes |
> | handler op body / default op body | `main.Log.emit` | yes |
> | closure | `main.outer.closure#1` (number = source order in the enclosing fn) | yes |
> | `test "adds two"` block | `main.test(adds two)` | yes, under `blink test --trace` |
> | `@derive` method | none | no |
>
> `fn:<short>` matches the last segment or any dotted suffix: `fn:sum` and `fn:Point.sum` both
> select `main.Point.sum`. The `span` on `enter` tells apart two handlers of the same op and two
> closures.
>
> ```blink
> type Point { x: Int, y: Int }
> trait Total { fn sum(self) -> Int }
> impl Total for Point {
>     fn sum(self) -> Int { self.x + self.y }
> }
> fn main() ! IO {
>     let p = Point { x: 1, y: 2 }
>     let f = fn(n: Int) -> Int { n + p.sum() }
>     io.println("{f(4)}")
> }
> ```
>
> ```json
> {"ts_us":0,"event":"enter","fn":"main.main","module":"main","depth":0,"span":{"file":"p.bl","line":6,"col":1}}
> {"ts_us":3,"event":"enter","fn":"main.main.closure#1","module":"main","depth":1,"span":{"file":"p.bl","line":8,"col":13},"args":{"n":"4"}}
> {"ts_us":4,"event":"enter","fn":"main.Point.sum","module":"main","depth":2,"span":{"file":"p.bl","line":4,"col":5},"args":{"self":"<Point>"}}
> {"ts_us":5,"event":"exit","fn":"main.Point.sum","module":"main","depth":2,"duration_us":1,"return":"3"}
> {"ts_us":6,"event":"exit","fn":"main.main.closure#1","module":"main","depth":1,"duration_us":3,"return":"7"}
> {"ts_us":8,"event":"effect","fn":"main.main","module":"main","depth":0,"effect":"IO.Print","op":"io.println","args":{"msg":"7"}}
> {"ts_us":9,"event":"exit","fn":"main.main","module":"main","depth":0,"duration_us":9,"return":"()"}
> ```
>
> (Probe: this program builds and prints `7` under gen1. `msg` stands for whatever param name
> `io.println` has in its doc signature; see point 4.)
>
> Derived methods are not frames: their span would point at an `@derive` line, and a
> `Debug`/`Eq` call on each compare would flood the trace. A related rule the spec needs: **the
> tracer's own Display calls run untraced.** If a user `Display` impl renders an arg, its frame
> must not show up, or each `enter` nests a fake `enter` and the depth is wrong.
>
> ## (2) std: no frames, but its effects are events
>
> std fns are not frames (one untraced archive, and std frames are noise to a user). Packages built
> from source with the program are frames. They are code the user picked, and `module:` cuts them.
> An effect that a std fn does is an `effect` event. Its `fn`, `module` and `depth` are those of the
> nearest user frame on the stack. This matches strace: the user wants to know which files the
> program touched, not which layer of the library touched them. std frames add no depth, so a closure
> that `list.map` calls has the depth of the caller plus one. Cost: the effect event comes from the
> op itself (runtime or std), behind the trace `active` flag the runtime already has, so the
> untraced archive needs one cheap branch per op and no rebuild.
>
> ## (3) No Display: Debug form, else `<TypeName>`, never omit
>
> Order: `Display` if the type has it, else `Debug`, else `<TypeName>` with type args (`<Box[Int]>`,
> `<fn(Int) -> Int>`). Never omit the field. An agent that runs `jq '.args.p'` and gets `null` cannot
> tell "no such param" from "not shown". Debug output is the most useful string there is when
> Display is missing.
>
> ## (4) Effect args: every param, under its declared name
>
> Every param of the op, keyed by the param name in its signature, the name `blink doc` and the
> LSP hover show. Values are capped at 200 chars like all other values, so `fs.write` content cannot
> blow up the line. No table of chosen keys to keep in sync as std grows. The §8.15.4 example then
> also gets `"content":"..."`. A writer fix, since that example was only a sketch. Secrets: an
> `env.var` event shows `name`, not the value (args are inputs and an effect event has no result).
>
> ## (5) User effect: `effect` = type path, `op` = call spelling
>
> The same shape as the builtins (`IO.Print` / `io.println`): `effect Log { fn emit(s: Str) }`
> called as `log.emit("x")` gives `"effect":"Log","op":"log.emit","args":{"s":"x"}`. A sub-effect
> gives `"effect":"Log.Debug"`. An effect from another module adds the module: `"effect":"obs.Log"`.
> Then comes the handler body frame at depth + 1 (point 1), so the trace shows the call and who
> took it.
>
> ## (6) `effect:FS` selects `FS.Write`: yes
>
> Prefix match on whole dot segments: `FS` matches `FS` and `FS.Write`, not `FSX`. Same reading as
> a row. Users will type `effect:FS` first. If that gives no events, the user reads a false "no FS
> was done".
>
> ## (7) State ops: `op` = the method name
>
> `=` and compound assign give `assign`. A mutating method call gives `op` = the method name:
> `push`, `pop`, `insert`, `remove`, and so on: `set`, `clear`, `extend`, `sort`. The five listed
> names stay exactly right for their methods. One event per mutation. `value` is the whole binding.
> Why: `"op":"assign"` for a `sort` sends the reader to look for an `=` that is not in the source.
> The method name greps straight to the line, and no mapping table exists. Cost: the set of `op`
> values is open. A consumer that switches on all five breaks. Few will switch, because `value`
> holds the post-state anyway.
>
> ## (8) Field and index writes: event, `var` = root binding
>
> `p.x = 1` and `xs[i] = v` each give a state event with `"var":"p"`, `"op":"assign"`, and `value`
> = all of `p`. `state:p` must catch every write to `p`. `"var":"p.x"` would hide it from that
> filter. I also propose one optional field, `"path":".x"` / `"path":"[3]"`, present only on a part
> write, so the reader can see what changed without diffing two 200-char values. If the panel wants
> no new field, drop `path` and keep the rest.

**AI/ML**

> # Phase A — AI/ML seat
>
> My test for each point: can an agent predict the line from the source and the spec alone, with no lookup table? A trace that is silently empty or partial is the worst case: the agent concludes "never called" and debugs the wrong thing.
>
> MVCE (`p.bl`), my proposed output for `blink run p.bl --trace`:
>
> ```json
> {"ts_us":0,"event":"enter","fn":"p.main","module":"p","depth":0,"span":{"file":"p.bl","line":2,"col":1}}
> {"ts_us":3,"event":"enter","fn":"p.add","module":"p","depth":1,"span":{"file":"p.bl","line":1,"col":1},"args":{"a":"1","b":"2"}}
> {"ts_us":4,"event":"exit","fn":"p.add","module":"p","depth":1,"duration_us":1,"return":"3"}
> {"ts_us":9,"event":"effect","fn":"p.main","module":"p","depth":0,"effect":"IO.Print","op":"io.println","args":{"msg":"3"}}
> {"ts_us":12,"event":"exit","fn":"p.main","module":"p","depth":0,"duration_us":12,"return":"()"}
> ```
>
> ## (1) Frames
>
> Rule: **every body the user wrote in source is a frame**; generated code is not.
>
> | Construct | Frame? | `fn` value |
> |---|---|---|
> | top-level fn | yes | `p.add` |
> | method (`impl`) | yes | `p.Point.norm` — the spelling of a static call, and what `blink query` names |
> | closure | yes | `p.main.<closure@4>` (enclosing fn + line) |
> | handler op body | yes | `p.main.<handler@6>.emit` (op name stays the last segment, so `fn:emit` matches) |
> | `test` block | yes | `p.<test@12>` |
> | derived method (`@derive`) | **no** | — no source, no span; `eq`/`hash` would flood a trace |
>
> Angle brackets mark a name no user can write, so it cannot collide with a real fn (Python's `<lambda>`, `<locals>` qualnames are the same idea).
>
> Also required: **calls the tracer makes to render a value give no events.** A user `impl Display` fn that the tracer calls to make an `args` string must not write enter/exit lines, or every traced call recurses into noise.
>
> ```blink
> fn main() ! IO {
>     let xs = [1, 2].map(fn(x: Int) -> Int { x * 2 })
>     io.println("{xs.len()}")
> }
> ```
> gives `enter p.main` d0, `enter p.main.<closure@2>` d1 args `{"x":"1"}`, exit, the same for `x:"2"`, the effect, `exit p.main`. `List.map` (std) is not a frame, so the closure is at depth 1, not 2.
>
> ## (2) std and package fns
>
> - `std.*` fns: never frames (the archive is built once; also they are noise to the user).
> - Fns of other packages (deps): frames. Filter them out with `module:`. The rule "std no, everything else yes" is one bit an agent can learn; "fns compiled in this build" depends on build details it cannot see.
> - `depth` counts traced frames only.
> - **An effect operation always gives an event, whoever performs it** — user code, std code, a dep. `fn`/`module`/`depth` are those of the innermost traced frame. Without this rule `io.println` itself gives no event, because the `IO.Print` operation is done inside the std wrapper. Effects are the highest-value events; the user fn's row already promises them.
>
> strace precedent: it reports every syscall, whatever library made it.
>
> ## (3) No Display impl
>
> Fallback chain: **Display → Debug → `<TypeName>`** (the type as written in source: `<Point>`, `<List[Point]>`, `<fn(Int) -> Int>`). Never omit the field. An omitted key makes `jq .args.p` yield `null`, which reads as "the arg was null/none"; a placeholder reads as "no Display". Debug is better than a placeholder when it exists (`Point { x: 1, y: 2 }` is what an agent needs). Truncation at 200 applies the same.
>
> ## (4) Effect `args`
>
> **Every param of the operation, keyed by its declared name**, Display strings, 200-char cap. The key set is then derivable from the op's signature in the spec tables; no per-op list to learn. Token cost is bounded by the cap. Change the §8.15.4 example to `"args":{"path":"out.c","content":"..."}` (content truncated, `"truncated":true`).
>
> - `io.println(x)` → `{"msg":"<x rendered>"}` (the handler op `print(msg: Str)`)
> - `env.var(name)` → `{"name":"HOME"}`
> - `fs.write` → `{"path":..,"content":..}`
> - `process.run` → `{"cmd":..,"args":..,"stdin":..,"env":..,"cwd":..,"limits":..}` — named-with-default params appear too, with their effective value
> - a zero-param op (`time.now()`) → omit `args`, as `enter` does
>
> `op` is the call spelling the user writes: `io.println`, not the handler op `io.print` (which would collide with the `io.print` wrapper). Each operation dispatch is one event; an op performed by another op's body gives its own event too (honest, and order shows the nesting).
>
> ## (5) User effects
>
> ```blink
> effect Log {
>     fn emit(s: Str)
> }
> fn run() ! Log {
>     log.emit("hi")
> }
> ```
> → `"effect":"p.Log","op":"log.emit","args":{"s":"hi"}`
>
> - `op` = handle call spelling (`log.emit`), same rule as `io.println`. An agent greps the source for it.
> - `effect` = effect path of the sub-effect that declares the op, module-qualified for user effects (`p.Log`, `p.Metrics.Emit`); builtins stay bare (`IO.Print`). Two modules can each declare `Log`; identity needs the module, as `fn` has it.
> - `effect:` filter takes short or qualified names, as `fn:` does: `effect:Log` matches `p.Log`.
>
> ## (6) Parent selects children
>
> **Yes.** `effect:FS` matches `FS.Write`, `FS.Read`, ... The same rule as a row (`! FS` grants `FS.Write`), so the agent learns one model. Match by path segment, not string prefix: `effect:F` does not match `FS.Write`. (Today's runtime uses `strcmp`; it must change.)
>
> ## (7) State ops
>
> Replace the closed enum with one rule: **`op` is `"assign"` for `=` and compound assignment; else it is the name of the mutating method called.** `push`/`pop`/`insert`/`remove` are already method names, so the existing values stay valid.
>
> ```blink
> fn main() ! IO {
>     let mut xs = [3, 1]
>     xs.sort()
>     xs.set(0, 9)
>     xs.clear()
> }
> ```
> → three `state` lines, `var` `"xs"`: `op` `"sort"` value `[1, 3]`; `op` `"set"` value `[9, 3]`; `op` `"clear"` value `[]`.
>
> No mapping table to memorize; the agent reads `xs.extend(ys)` and predicts `"op":"extend"`. A user method that takes a mutable receiver gives its own name the same way. `value` already carries the full post-state, so a precise label costs nothing extra. Note: I propose the `let mut` initial binding gives no event (it is not a mutation); I hold that loosely.
>
> ## (8) Field and index writes
>
> **Yes, an event.** `var` = the root binding (`"p"`), `op` = `"assign"`, `value` = whole binding. Then `state:p` catches every change to `p`; with `var:"p.x"` an agent filtering `state:p` misses field writes, which is the silent-gap hazard again. The changed part is visible from the value diff.
>
> ```blink
> let mut p = Point { x: 0, y: 0 }
> p.x = 1   // {"var":"p","op":"assign","value":"Point { x: 1, y: 0 }"}  (Debug fallback)
> ```
>
> ## (9) argv
>
> The traced program must see the same `env.args()` as the untraced one; else a program that uses `std.args` rejects `--trace` and the trace changes the bug under study (heisenbug). Best fix: **the binary reads only `BLINK_TRACE`**; `blink run --trace[=f]` sets `BLINK_TRACE` in the child's env and passes nothing in argv. No argv stripping, and no collision with a program's own `--trace` flag. Bare `--trace` maps to `BLINK_TRACE=all`, the same word `BLINK_TRACE_CHANNELS` uses (§8.15.7). Fallback if the panel keeps argv: strip exactly the items the runtime consumed. `--trace-limit`/`BLINK_TRACE_LIMIT` must be specced or removed; an unspecced knob is a thing an agent cannot learn.
>
> ## (10) Bad filters
>
> **Usage error before `main` runs, exit 2**, one plain line on stderr:
>
> ```
> error: --trace: unknown filter key `fnx` in `fnx:add`; keys are fn, module, depth, event, effect, state
> error: --trace: `depth:abc`: depth takes an integer
> error: --trace: `event:enters`: events are enter, exit, state, effect, note
> ```
>
> Closed sets (keys, event names, depth integers) error. Open sets (fn, module, effect, state names) do not: an unknown name may just be a fn that did not run. Ignoring a bad filter gives an empty or full trace with exit 0, and the agent reasons from false data; a warning line breaks "every stderr line is JSON" under `--trace`. An error the agent sees once and fixes in one retry. Same for `BLINK_TRACE` (message says `BLINK_TRACE:`).
>
> ## Summary
>
> 1 user-written bodies only, synthetic `<kind@line>` names, tracer-made calls silent · 2 std no / deps yes; effects always · 3 Display→Debug→`<Type>` · 4 all params by declared name · 5 `p.Log` / `log.emit` · 6 yes, by segment · 7 `assign` or method name · 8 yes, `var` = root · 9 env only, args untouched · 10 exit 2 on closed-set errors.

**Minimalism**

> # Phase A — Min seat (runtime `--trace`)
>
> My one test for every point: a rule must be one line that a reader can apply without a table. Each new
> op name, frame kind or key grammar is a cost that every later effect, collection method and stdlib
> module must pay. Where a closed set already exists, keep it closed.
>
> MVCE base used below: `fn add(a: Int, b: Int) -> Int { a + b }` / `fn main() ! IO { io.println("{add(1, 2)}") }`, entry module `p`.
>
> ```json
> {"ts_us":0,"event":"enter","fn":"p.main","module":"p","depth":0,"span":{"file":"p.bl","line":2,"col":1}}
> {"ts_us":3,"event":"enter","fn":"p.add","module":"p","depth":1,"span":{"file":"p.bl","line":1,"col":1},"args":{"a":"1","b":"2"}}
> {"ts_us":4,"event":"exit","fn":"p.add","module":"p","depth":1,"duration_us":1,"return":"3"}
> {"ts_us":6,"event":"effect","fn":"p.main","module":"p","depth":0,"effect":"IO.Print","op":"io.println","args":{"<param name of io.println>":"3"}}
> {"ts_us":9,"event":"exit","fn":"p.main","module":"p","depth":0,"duration_us":9,"return":"()"}
> ```
>
> ## (1) Frames — only declared, named fns of the program's own source
>
> Frame = a `fn` the user wrote with a name: top-level fns and methods (in an `impl` or type body).
> Nothing else gets enter/exit or a depth step.
>
> - Method name: `module.Type.method` (`p.Point.norm`). This is the only spelling that is unique and
>   that `fn:norm` still matches as a short name.
> - Closure: no frame. Its state/effect events carry the `fn` and `depth` of the innermost frame on the
>   call stack (the dynamic caller). Depth is already the call stack (settled), so this needs no new
>   concept.
> - Handler op body: no frame, same attribution rule. The `effect` event at the perform site already
>   marks the jump.
> - Derived method: no frame. The user wrote no body and there is no span to point at.
> - `test` block: no rule. `--trace` is a `blink run` feature; extend it to `blink test` when someone
>   asks for it.
>
> ```blink
> fn twice(f: Fn(Int) -> Int, x: Int) -> Int { f(f(x)) }
> fn main() ! IO {
>     let mut n = 0
>     io.println("{twice(fn(v) { v + 1 }, 1)}")
> }
> ```
> Gives enter/exit for `p.main` and `p.twice` only; no line for the closure.
>
> Tradeoff: an agent loses closure granularity, but closures are short and anonymous; a frame named
> `p.main.<closure#2>` invents a naming grammar we must keep stable. Python `sys.settrace` gives lambdas
> frames, and its output is notorious for the noise.
>
> ## (2) std and packages — not traced as frames; effects always traced
>
> - Frames: only the root package. std is not traced (built once). Dependency packages are not traced
>   either: one boundary ("your code") is easier to state than "std no, packages yes".
> - Effects: an effect op writes its event wherever it runs, also inside a std fn. `fn`/`depth` = the
>   innermost traced frame (the user fn that called into std). The hook sits in the builtin op and tests
>   one runtime flag, so the untraced archive still writes it.
>
> Why: an effect trace that hides a write because a helper did it is wrong, not small. strace reports
> the syscall no matter which library made it; that is the right model.
>
> ## (3) No Display impl — `<TypeName>`
>
> The string is `<` + the type as written in source, instantiated + `>`: `<Point>`, `<List[Point]>`.
>
> - Not Debug: §2 says derived Debug on an opaque type shows hidden fields; a trace must not print a
>   secret that the type author hid. Debug can also be unbounded work before truncation.
> - Not omit: then a missing key means either "no arg" or "no Display", and the key set of a fn changes
>   with its types. Keys stay = param names, always.
>
> ## (4) Effect args — every param, by declared name
>
> One rule, no per-op table: `args` holds each param of the op, keyed by its declared param name, with
> the same Display/placeholder/200-char rules as `enter`. `fs.write` gives `path` and the content
> (truncated). The §8.15.4 example line must then add the content key; that is a writer fix.
>
> Tradeoff: big payloads cost up to 200 chars per line. That is already the bound for every value. A
> curated table (path yes, content no) needs a decision for every op we add, forever, and each one is a
> place to forget a key.
>
> ## (5) User effect names — same shape as builtins
>
> `effect` = the effect type that grants the op, as a row writes it: `"Log"`. `op` = the call
> spelling, handle + op: `"log.emit"`. That mirrors `"IO.Print"` / `"io.println"` exactly.
>
> ```blink
> effect Log { fn emit(s: Str) }
> fn work() ! Log { log.emit("hi") }
> ```
> ```json
> {"ts_us":5,"event":"effect","fn":"p.work","module":"p","depth":1,"effect":"Log","op":"log.emit","args":{"s":"hi"}}
> ```
>
> Not module-qualified: `module` already tells where the call ran, and a collision of two `Log`s in one
> program is rare enough to not shape the schema.
>
> ## (6) `effect:FS` matches `FS.Write` — yes, by dot segment
>
> A filter value selects that effect and its children, as a row does. `effect:FS` matches `FS.Write` and
> `FS.Read`; `effect:FS.Write` does not match `FS.Read`; `effect:F` matches nothing (segment, not
> string prefix). No new idea: the user already knows `! FS` grants `FS.Write`.
>
> ## (7) State ops — keep the five; everything else is `assign`
>
> `op` is the method name when the method is `push`, `pop`, `insert` or `remove`; every other mutation
> (`List.set`, `clear`, `extend`, in-place sort, `Map.set`, a whole-binding `=`) gives `"assign"`.
> `value` is the whole binding after the change (settled), so the op name is only a hint; the value
> carries the truth.
>
> ```blink
> fn main() ! IO {
>     let mut xs = [3, 1]
>     xs.push(2)
>     xs.sort()
> }
> ```
> ```json
> {"event":"state","var":"xs","op":"push","value":"[3, 1, 2]",...}
> {"event":"state","var":"xs","op":"assign","value":"[1, 2, 3]",...}
> ```
>
> Tradeoff: no `"sort"` op. Anyone who needs it reads the value diff. An open op set grows with each
> collection method and breaks every `jq` switch on `op`.
>
> ## (8) Field and index writes — event, `var` = root binding
>
> `p.x = 1` and `xs[i] = v` each write one `state` event: `var` = the root name (`"p"`, `"xs"`), `op` =
> `"assign"`, `value` = the whole binding after the write.
>
> Not `"p.x"`: a path grammar (`xs[3].y`, runtime indices) is a new mini-language to spec and to escape,
> and `state:p` would then need prefix rules. No event at all would hide real mutations; that is worse.
>
> ## (9) argv — subtract it: the binary does not read argv
>
> The built binary reads only `BLINK_TRACE`. `blink run app.bl --trace[=f]` sets `BLINK_TRACE` for the
> child (`all` for bare `--trace`, else `f`) and passes no extra argv. Then `env.args()` needs no
> hiding rule, and a program whose own parser takes `--trace` still works under tracing. A traced run
> that changes argv changes program behavior, which defeats the tool.
>
> - Direct use: `BLINK_TRACE=fn:add ./p`. `BLINK_TRACE=all` = everything (same word as
>   `BLINK_TRACE_CHANNELS`); drop the `1` spelling.
> - `blink run --trace` overrides an inherited `BLINK_TRACE`.
> - `--trace-limit` / `BLINK_TRACE_LIMIT`: not in the spec, remove them (YAGNI); `head -n` does it.
>
> Fallback if the panel keeps argv: strip `--trace` and `--trace=<f>` before `env.args()` sees them.
> Go's runtime/trace and `GODEBUG` take env, not argv, for this reason.
>
> ## (10) Bad filter — usage error, exit 2, program does not run
>
> Unknown key, empty value after a colon, or a `depth:` value that is not a non-negative Int:
>
> ```
> $ blink run p.bl --trace=fnx:add
> error: --trace: unknown filter key `fnx` (keys: fn, module, depth, event, effect, state)
> $ echo $?
> 2
> ```
>
> `blink run` checks the string before it builds. A binary started with a bad `BLINK_TRACE` writes the
> same line (with `BLINK_TRACE:` as prefix) and exits 2 before `main`. An unknown `event:` value is the
> same error. `effect:`/`state:`/`fn:`/`module:` values are not checked against the program (a name
> that matches nothing gives an empty trace; that is a legit answer).
>
> Why not ignore: today `atoi("abc")` makes `depth:abc` mean `depth:0`; a typo silently changes the
> answer and an agent cannot tell. Why not warn: a warning is a non-JSON line in an NDJSON stream.
> Exit 2 matches `blink test`'s usage exits.
>
> ## Summary of what I subtract
>
> No closure/handler/derived frames, no package frames, no new state op names, no field paths, no argv
> parsing in the binary, no `--trace-limit`, no `1` spelling. What I add is only what a correct trace
> needs: effect events from inside std, a placeholder string, and a hard error on a bad filter.

#### Phase B — Replies to the moderator digest

The digest listed each option with its proposers. Each seat replied to the options that it wanted to argue.

**Systems**

> # Phase B round 1 — sys seat
>
> Moves: **V4** (to dotted suffix), **V7** (to V7-call), **V8** (to V8-always). The rest unchanged.
>
> ## V1. Frames — V1-frames
>
> To min: "closure events carry the innermost frame" makes the trace lie about where code is.
> `xs.map(fn(x) { fs.write(...) })`: under V1-named-only the write shows as `fn` = the caller, at the
> caller's depth, so an agent reads it as a direct call in the caller's body. A frame costs two
> calls and two clock reads in a traced build only; untraced builds pay nothing. Python's noise comes
> from tracing every line and the std lib; we trace neither. `test` blocks: a frame at depth 0 when a
> test runs traced. If `blink test --trace` does not exist yet, the rule costs nothing until it does.
>
> ## V2. Synthetic names — put the location in the name
>
> I hold the sub-point: the name must tell two closures apart without the `enter` span. `event:effect`
> and `event:state` (both in §8.15.1 examples) drop every `enter` line, so then the span is gone and
> two closures in one fn give identical lines. Line:col is a static string: zero cost. Bracket style I
> do not care about. I accept aiml's angle form with line:col (two closures can share a line):
>
> ```blink
> fn main() ! IO {
>     let a = [1].map(fn(x: Int) -> Int { x + 1 })
>     let b = [1].map(fn(x: Int) -> Int { x * 2 })
> }
> ```
> `main.main.<closure@2:21>`, `main.main.<closure@3:21>`; handler op body `main.main.<handler@6>.emit`
> (op stays last, `fn:emit` matches); test `main.<test@12>`. A user effect default body:
> `main.<effect Log>.emit` or plt's `{}` form, same idea. Not devops's `closure#1` index: inserting
> a closure above renames every later one, and an index cannot be found in the source without counting.
>
> ## V3. Muted formatting — yes (unchanged)
>
> ## V4. `fn:` match — move to dotted suffix
>
> `fn:norm` and `fn:Point.norm` both match `main.Point.norm`; match on `.` boundaries only. Cost is the
> same segment compare as `effect:`, set up once. I had only described today's runtime.
>
> ## V5. Packages — V5-frames
>
> To min: "your code" is not one boundary in practice: a workspace path dep is "your code" and a
> registry dep is not, so root-only needs a package-kind rule. "Compiled from source in this build"
> is the line the compiler already draws (std is the one prebuilt archive). `module:` cuts deps out.
>
> ## V6. No Display — V6-chain
>
> To min's secret point: Debug on an opaque type is a choice the type author made by writing
> `@derive(Debug)`; a trace is a dev tool, as `dbg`/`{x:?}` is. strace prints write buffers too; plt's
> one-line note covers it. The cost point ("unbounded work before truncation") the 201-byte sink
> answers. The placeholder-only rule renders every `Result` return as `<Result[Int, Str]>`, which is
> the value an agent most needs. Chosen per instantiation at mono time.
>
> ## V7. `io.println` — move to V7-call
>
> aiml is right: under my rule the user's `io.print(x)` shows as `io.print_no_nl` and `io.println(x)`
> shows as `io.print`. An agent greps the source for `io.print` and finds the wrong line. That is worse
> than a one-to-one name map. Rule: `op` = the call spelling of the op (`io.println` for `print`,
> `io.print` for `print_no_nl`, `log.emit` for a user op, where the two are the same). Each op has
> exactly one call spelling (the §4.4 table), so the name is a static string per op: zero cost. Key =
> the op's declared param name: `{"msg":"3"}`, not plt's `x` (the wrapper's param is gone by the time
> the op runs; the op's param is what the handler sees).
>
> I keep my sub-point: a derived op whose default body performs another op gives a second event, with
> that op's call spelling. `io.print_raw("a")` gives `io.print_raw` then `io.print`. That is the true
> op sequence, and a handler that intercepts `print_no_nl` sees that second call.
>
> ## V8. User effect name — move to V8-always
>
> V8-on-collision is the worst choice: adding a dep that declares its own `Log` renames the `effect`
> field in lines that did not change. Always-qualified is one static string per op, and matches `fn`.
> So `"effect":"p.Log"`, `"effect":"p.Metrics.Emit"`; builtins bare (`IO.Print`). `effect:Log` matches
> `p.Log` by the same dotted-suffix rule as V4, so a filter written as a row writes it still works.
>
> ## V9. State op — V9-method-name
>
> To min's jq point: a jq switch on `op` needs a default arm in both designs, since `assign` already
> means "some other change". The closed set loses data (`sort` vs `clear` vs `set` all read `assign`)
> and needs a mapping for each user method that takes a mutable receiver; the method-name rule needs no
> table, and the op is a static string. I agree with plt: one event per call of a mutating method,
> even when the store does not change (no compare cost, predictable count). I agree with aiml: the
> `let mut` initial binding gives no event.
>
> ## V10. `path` — V10-path, not a hill
>
> min's grammar cost is real but small: `.field` and `[Int]` only, field names need no escape, and a
> `Map` key write goes through `insert`, so no key ever enters a path. The data loss is also real: for
> a struct whose Display is longer than 200 chars, the change after the cut gives an event whose
> `value` is the same as the one before. I vote path; I accept none if it loses.
>
> ## V11. argv — V11-env-only
>
> I agree with min: drop `BLINK_TRACE=1`; `all` is the word. `blink run --trace` overrides an inherited
> `BLINK_TRACE`. My sub-point stands: a traced binary with `BLINK_TRACE` unset traces all, since it was
> built only to trace (`blink build --trace`); an unset var that gave no output would look like a
> broken build. `--trace-limit`/`BLINK_TRACE_LIMIT`: remove (`head -n` does it, and the runtime check
> on each event is pure cost).
>
> ## V12. `fn:typo` — no warning
>
> A warning line from `blink run` lands in the same `2>trace.ndjson` file and breaks `jq`. An empty
> trace for a name that never ran is a correct answer. If the panel wants help here, put it in `blink
> check`, not in the stream.
>
> STABLE

**Web/Scripting**

> # Phase B round 1 — Web seat
>
> I change my position on three items: V2 (the name form), V11 (argv) and V12 (I withdraw the warning).
>
> ## V1. Closures, handler op bodies, test blocks: **V1-frames** (stay)
>
> To min: in a JS or Python codebase, the bug is in the callback most of the time
> (`xs.map(fn(x) { ... })`, `filter`, `fold`). With V1-named-only, a closure's args and return value do
> not appear in the trace at all. Its state events would also come under the caller's name, so a user
> who reads `"fn":"p.twice"` looks for the mutation in `twice` and does not find it. The cost min names
> is a name form that we must keep stable. One small rule settles that (V2 below). It costs less than a
> trace that does not show the place where the bug is.
>
> ## V2. Names: **a new label, V2-kind@pos**. I move away from `<closure>`.
>
> Two arguments from the other seats change my position:
> - sys: `exit` and `state` lines have no `span`, so two closures in one fn must have different names. My
>   "the span tells them apart" works only on `enter`.
> - devops: a user types the name in a shell. A `<` or `>` in `--trace=fn:main.<closure>` is a shell
>   redirect, and a space needs quotes. That costs a Stack Overflow question on the first day.
>
> Rule: a synthetic frame is `<enclosing path>.<keyword>@<line>:<col>`. `<keyword>` is the keyword that
> opens the body (`fn` for a closure, as sys proposed; `handler`; `test`). The position is where that
> keyword starts. A handler op appends `.<Effect>.<op>`, so `fn:emit` and `fn:Log.emit` still match
> (aiml's point). An identifier cannot contain `@`, so these names cannot collide with a user fn, and
> they have no shell metacharacters.
>
> | Body | `fn` |
> |---|---|
> | closure | `main.apply.fn@2:12` |
> | handler op | `main.main.handler@4:10.Log.emit` |
> | user effect default body | `main.effect@1:1.Log.emit` |
> | test block | `main.test@12:1` |
>
> I take line:col, not line only, so two closures on one line also get two names. I do not take
> devops's `#1`: an index changes when a closure is added above it, and the user cannot work it out from
> the editor, which shows a line and a column.
>
> ## V3. The tracer mutes a Display impl that it calls: yes (stay)
>
> ## V4. `fn:` short name: **any dotted suffix** (stay)
>
> To sys: last-segment matching makes `fn:new` match every `Type.new` in the program, and no filter can
> pick one of them. A suffix on a whole segment includes sys's case (`fn:dist` still matches) and adds
> `fn:Point.dist`.
>
> ## V5. Package fns: **V5-frames** (stay)
>
> "Std is not traced" is easy to explain: the user did not write std and does not ship it. A dependency
> is code that the user's build compiles and that the user can open, and when it has a bug, the user
> must see it. `module:` removes the noise. VS Code's justMyCode hides deps, and "how do I step into a
> library" is one of its most common questions.
>
> ## V6. No Display: **V6-chain** (stay)
>
> `Result` has no Display (§3.6). With V6-placeholder, every fn that returns `Result` writes
> `"return":"<Result[Int, ParseError]>"` in place of `Ok(3)`. Users will call that a broken tracer.
>
> To min's point about secrets: a type has a Debug form only when its author writes or derives Debug.
> A failed `assert_eq` or `.unwrap()` already prints that Debug form to stderr. The trace shows nothing
> that a panic would not show. A writer note is enough: "a trace prints values; do not ship traced
> builds".
>
> ## V7. **V7-call**: `"op":"io.println"`, key `msg` (stay)
>
> To sys: with V7-operation, `io.println` writes `"op":"io.print"` and `io.print(x)` writes
> `"op":"io.print_no_nl"`. The user greps for `io.print` and finds the wrong call. That is a trap, not a
> small cost. The rule: `op` is the handle call that the source text holds. For user effects, the call
> and the op are the same (`log.emit`), so a difference exists only for the std IO wrappers.
>
> On sys's derived-op point: one call gives one event. A wrapper that is built from other ops writes no
> second event, because the user wrote one call.
>
> Key: `msg`, the op's declared param, as V4a says (keys = the op's declared names). plt's `x` would
> mean that the key changes with the name of the caller's variable.
>
> ## V8. User `effect`: **V8-bare** (stay)
>
> With V8-on-collision, a new module that declares its own `Log` changes the effect name in every old
> trace, and a diff of two traces then breaks. With V8-always, the name differs from what the user wrote
> in `! Log`. The `module` field and `fn` already say where the call was made. Two effects named `Log`
> in one program is rare, and `module:` separates them.
>
> ## V9. State `op`: **V9-method-name** (stay)
>
> To min ("breaks every jq switch"): a user type can have its own `mut self` methods
> (`p.move_by(1)`), so the set of mutations is open in any case. With a closed set, `move_by` must give
> `assign`, and that is the Stack Overflow question I named in Phase A. A jq script that matches on
> `op` needs a default branch in every case. I agree with plt: a mutating call gives one event even when
> the value does not change. I agree with aiml: the first `let mut` binding gives no event.
>
> ## V10. `path`: **V10-none** (stay, weakly)
>
> sys's case is real: a change past the 200-char cut is not visible. But a path syntax with runtime
> indexes is a new mini-language for 1% of events. Add it later if users ask for it. I would not block
> V10-path.
>
> ## V11. argv: **I move to V11-env-only**
>
> min, plt, aiml and sys are right, and their way is simpler than mine. If the binary does not read
> argv, there is nothing to remove, the program sees the same argv with tracing and without it, and a
> program that takes its own `--trace` flag still works. The rules:
> - `blink run --trace[=f]` sets `BLINK_TRACE` for the child (`all` for bare `--trace`). It overrides a
>   `BLINK_TRACE` that the shell already has.
> - A traced binary with `BLINK_TRACE` unset traces all (sys). It was built to trace, and an empty trace
>   on the first try is the worst result.
> - Drop the `1` spelling; `all` is the only word, the same as `BLINK_TRACE_CHANNELS`.
> - Remove `--trace-limit` and `BLINK_TRACE_LIMIT` (min). `head -n` does the same job.
>
> ## V12. `fn:typo` warning: I withdraw it
>
> A text line on stderr breaks "every stderr line is JSON", even when `blink run` writes it before the
> program starts. A name that matches nothing gives an empty trace and exit 0, as V10a says.
>
> STABLE

**PLT**

> # B r1 — PLT seat
>
> I move on V2 (name has a location), V7 (op = the operation), V8 (always qualify) and V9 (min's
> rule). Reasons below.
>
> ## V1 — V1-frames (hold)
>
> Reply to min ("closure events carry the `fn` and `depth` of ... the dynamic caller"): a closure's
> `state` events name a `var` that lives in the closure's **lexical** scope. Credit them to the
> dynamic caller and `"fn":"p.sort_by","var":"count"` names a var that `sort_by` does not have. When the
> caller is std (`xs.map(fn(x) { ... })`), the "innermost traced frame" is the enclosing fn by luck, not
> by rule. A frame per closure makes `fn` + `var` always name a real binding.
>
> `test` block: a frame at depth 0. `blink test` runs the same compiled code; one rule, no exception.
>
> ## V2 — move: the closure name holds its line:col
>
> sys is right: `exit` and `state` have no span, so `{closure}` makes two closures in one fn the same
> string on those lines, and `fn:` can not select one of them. Required behavior (spelling to the
> writer):
> - closure: `<enclosing fn>.` + a form that holds line:col and can not be an identifier, e.g. sys's
>   `main.apply.fn@2:12`;
> - handler op body: the **last** segment is the op name (aiml), so `fn:emit` matches it, e.g.
>   `main.handler Log.emit`;
> - `test` block: `main.test "adds two"`.
>
> I prefer line:col to devops's `closure#1` index: an index changes when an earlier closure is added,
> so names in an old trace stop matching the source. Line:col points at the source directly.
>
> ## V3 — no events from a tracer-called Display/Debug (hold)
>
> ## V4 — dotted-suffix match (hold)
>
> `fn:X` matches a `fn` that equals `X` or ends in `.X`, by whole segment. It includes sys's
> last-segment form (`fn:dist`) and adds `fn:Point.dist`, which tells `Point.dist` from `Line.dist`.
> It is the mirror of the V6 segment rule (prefix for effects, suffix for fns).
>
> ## V5 — V5-frames (hold)
>
> The std line is a build fact (one prebuilt archive), not a "your code" line. Packages compile from
> source in the user build, so they cost nothing extra to trace, and `module:` cuts them out. min's rule
> would hide a bug in a dep, which is often the bug you hunt.
>
> ## V6 — V6-chain (hold); reply to min on secrets
>
> §2 line 1424 settles it: "`@derive(Debug)` on an opaque type ... shows the hidden fields. To hide a
> field, such as a secret, write `impl Debug` by hand." So Debug is the type author's declared
> developer view; `assert_eq` failures and `.unwrap()` panics print it already. The trace prints
> nothing a panic would not. And without Debug, `Result` (no Display) returns `<Result[Int, Str]>`,
> the value an agent most wants.
>
> ## V7 — move to V7-operation, key `msg`
>
> An `effect` event observes an operation: the thing a handler receives. `io.println` is a generic std
> wrapper (not a frame, by 2a). Its op is `IO.Print.print(msg: Str)`. So:
>
> ```blink
> fn main() ! IO { io.println("{add(1, 2)}") }
> ```
> `{"event":"effect","fn":"p.main",...,"effect":"IO.Print","op":"io.print","args":{"msg":"3"}}`
>
> Why: (a) a handler author intercepts `print`, so the trace must say what the handler sees, or the
> event and the handler disagree; (b) the wrapper's param is `x: T`, not a Str, and each wrapper would
> need its own spec line forever; (c) a user effect has no wrapper, so the user and builtin rules are the
> same only if both name the operation. aiml's collision point is real (`io.print(x)` gives
> `"op":"io.print_no_nl"`), but that is the spec's op names, and the trace should show them as they
> are. Fix the schema example `"op":"io.println"` to `io.print`. With a derived op, each op performed
> gives its own event (sys).
>
> ## V8 — move to V8-always
>
> My Phase A "prefix on collision" is not compositional: adding a dep that also declares `Log` would
> change the `effect` string of every existing `Log` event. A field's value must not depend on code
> that does not touch it. So: user effects always carry their module (`"effect":"p.Log"`,
> `"p.Metrics.Emit"`); builtins stay bare (they live in no module). The `effect:` filter takes the bare
> or the full name: `effect:Log` and `effect:p.Log` both match, and by V6 `effect:p.Metrics` matches
> `p.Metrics.Emit`. `op` stays `"log.emit"`.
>
> ## V9 — move to V9-five+assign (min)
>
> min's rule is one line with no table; my `Map.set` -> `insert` mapping was a table. I keep my sub-point:
> one event per mutating call, even when the store does not change.
>
> Against V9-method-name: the schema gives `op` as a closed sum of five. A closed set lets a consumer
> match on every case; an open set (`sort`, `set`, `truncate`, ...) grows with every collection method,
> and each new std method is then a schema change. `value` already carries the post-state, so the method
> name adds no information about the store.
>
> aiml's initial binding: agree, no event. `let mut x = 0` binds; it does not change a store.
>
> ## V10 — V10-none (hold)
>
> sys's cut point is real, but a path holds runtime parts: `m[k] = v` puts the key's Display string
> inside the path, which then needs escaping and its own 200-char rule. If the panel wants the field,
> I accept it only for static field paths (`.x`, `.a.b`) and no index part.
>
> ## V11 — V11-env-only (hold), with sys's and min's sub-points
>
> - Traced binary, `BLINK_TRACE` unset: trace all (sys). It was built to trace.
> - `blink run --trace` overrides an inherited `BLINK_TRACE` (min). Drop `BLINK_TRACE=1`; `all` is the
>   word.
> - `--trace-limit`: no strong position. One fact for the vote: `2>&1 | head -n` closes the pipe, and
>   the next trace write gets SIGPIPE and kills the program. So `head` is not a limit that keeps
>   behavior the same. If the panel removes the limit, the spec should say that a closed trace stream
>   stops tracing and does not end the program.
>
> Reply to web/devops (strip): strip still breaks a program whose own parser takes `--trace`: it loses
> its flag. Env-only has no such case.
>
> ## V12 — no warning (hold)
>
> A warning from `blink run` lands in the same stderr stream as the NDJSON and breaks "each line is
> JSON". A filter that names nothing gives an empty trace, which is a correct answer.
>
> STABLE

**DevOps/Tooling**

> # Phase B round 1 — devops
>
> I have read all six. I move on V2, V6, V8 and V11. My test is the same as in Phase A: a trace
> must not be silent or wrong by accident.
>
> ## V1 — V1-frames (stay)
>
> Min: a closure frame "invents a naming grammar". But with no frame, a closure's state and effect
> events carry the caller's `fn`. Then `"fn":"p.main","var":"n"` names a fn whose body never writes
> `n`, and the reader looks in the wrong place. A small name grammar costs less than that. `test`
> blocks: frames under `blink test --trace` only. No other rule.
>
> ## V2 — move to a new label, V2-kw@pos
>
> Sys is right: `exit` and `state` have no span, so the name alone must tell two closures apart. My
> `closure#1` does that, but a reader must count closures to find the right one. Line:col goes
> straight to the source. My new rule: an anonymous body gets one segment, `<keyword>@<line>:<col>`.
> A keyword cannot be an identifier, so this cannot collide with a user fn. A handler op keeps the op
> name as the last segment, so `fn:emit` still matches (aiml). No spaces anywhere, so the filter
> needs no shell quotes.
>
> | Body | `fn` |
> |---|---|
> | closure | `main.apply.fn@2:12` |
> | handler op body | `main.main.handler@4:10.emit` |
> | default op body in `effect Log` | `main.Log.emit` |
> | `test "adds two"` | `main.test@12:1` |
>
> ```blink
> effect Log { fn emit(s: Str) }
> fn run() ! Log { log.emit("hi") }
> fn main() ! IO {
>     with handler Log { fn emit(s: Str) { io.println(s) } } { run() }
> }
> ```
> ```json
> {"event":"effect","fn":"main.run","depth":1,"effect":"main.Log","op":"log.emit","args":{"s":"hi"},...}
> {"event":"enter","fn":"main.main.handler@4:10.emit","depth":2,"span":{"file":"p.bl","line":4,"col":24},"args":{"s":"hi"},...}
> {"event":"effect","fn":"main.main.handler@4:10.emit","depth":2,"effect":"IO.Print","op":"io.println","args":{"msg":"hi"},...}
> ```
> (Here the `@` position is the `handler` keyword. The span points at the op's own `fn`.) A test's
> name string is in the `blink test` JSON output. The trace takes the position, so test names need no
> escape rules.
>
> ## V3 — muted formatting (stay, all five agree)
>
> ## V4 — dotted suffix, on whole segments
>
> `fn:sum` and `fn:Point.sum` match `main.Point.sum`. `fn:um` does not. Note for whoever restores
> the runtime: today `blink_trace_match` compares a raw string suffix, so `fn:add` also matches
> `main.xadd`. Under any label the match must stop on a `.` boundary. That holds for sys's
> last-segment form too.
>
> ## V5 — V5-frames (stay)
>
> Min's "one boundary" is shorter to state. But the boundary a user feels is "what I compile from
> source", and dep packages are on that side. A bug in a dep with no frames shows up as effects
> charged to the user fn that called it.
>
> ## V6 — move to V6-chain-opaque
>
> Min's secret point is real. Traces get pasted into tickets and agent prompts. Rule: use Display;
> else Debug, but not for an opaque type; else `<TypeName>`. So an opaque `Token` with no Display
> gives `<Token>`, and a plain `Point` with derived Debug gives `Point { x: 1, y: 2 }`. The author
> who hid the fields decides, not the tracer. Bytes: `<N bytes>` (sys) is fine with me.
>
> ## V7 — V7-call (stay); keys from the called signature
>
> Sys's V7-operation has a trap. Under it, a user who writes `io.print(x)` sees `"op":"io.print_no_nl"`,
> and a user who writes `io.println(x)` sees `"op":"io.print"`. Each trace line then names a call that
> the source does not have at that site. `grep io.print` finds the wrong line. One user call gives one
> event, spelled as written. The `args` keys are the param names of the fn that `op` names. A writer
> reads them from the signature that `blink doc` shows. For `io.println` that is `msg` if the doc shows
> `msg`. A user handler that overrides `IO.Print.print` is a frame (V1), so you can still see the op
> level.
>
> ## V8 — move to V8-always (aiml)
>
> My "other module" form, and plt's "on collision" form, make one effect's name depend on where the
> call sits or on what else is in the program. A saved `jq` query then breaks when someone adds a dep.
> So a user effect is always qualified (`main.Log`, `obs.Log`). Builtins stay bare, since their names
> are reserved (E0559) and cannot collide. `effect:Log` and `effect:main.Log` both select it (whole
> segments, same as V4).
>
> ## V9 — V9-method-name (stay)
>
> Min: an open set "breaks every jq switch on op". But the closed sets lie: plt's `Map.set` gives
> `insert` on an overwrite, and `sort` gives `assign`. A reader who greps for the `=` that `assign`
> claims finds none. I take plt's sub-point: one event per call, even when the store does not change.
> On aiml's sub-point I agree: the initial `let mut` gives no event.
>
> ## V10 — V10-path (stay, weak)
>
> Sys's case: on a struct past 200 chars, the changed field can sit past the cut. I will not block on
> it. If V10-none wins, the event still has `var` and `op`.
>
> ## V11 — move to V11-env-only
>
> Min and sys win this. If the binary never reads argv, there is nothing to strip, and the program's own
> parser keeps its `--trace`. My strip rule had an edge (`--`) that the env form does not. Details I back:
> - `blink run --trace[=f]` sets `BLINK_TRACE` for the child (bare gives `all`). It overrides an
>   inherited value.
> - A traced binary run by hand with `BLINK_TRACE` unset traces all (sys). It was built to trace. Silence
>   there reads as "the program did nothing".
> - Drop the `1` spelling. `all` matches `BLINK_TRACE_CHANNELS`.
> - `--trace-limit` / `BLINK_TRACE_LIMIT`: remove them. Nobody specced them. `head -n` covers it.
> - A bad `BLINK_TRACE` gives the 10a error with a `BLINK_TRACE:` prefix.
>
> ## V12 — new label, V12-run-error
>
> Web is right that `blink run` has the name table. But a warning line breaks the NDJSON stream (min,
> aiml, me), and a run that goes on reads as data. So: under `blink run`, after typecheck and before
> the program starts, each `fn:`, `module:`, `effect:` and `state:` value must name a declaration in the
> built program. If it does not, it is the same usage error, exit 2, with a hint:
>
> ```
> $ blink run p.bl --trace=fn:ad
> error: --trace: `fn:ad` names no fn in this program; did you mean `add`?
> $ blink run p.bl --trace=fn:split
> error: --trace: `fn:split` is a std fn; std fns are not traced
> ```
>
> A name that is declared but not called on this run is not an error. The trace is just empty. A binary
> run by hand with `BLINK_TRACE` has no table and does not check names (10a stands). This catches the
> most common empty trace, a fn-name typo, with no non-JSON line in the stream.
>
> OPEN: V12 (new; I want the other seats to react to the error-in-run form). All else STABLE.

**AI/ML**

> # Phase B r1 — aiml
>
> Same test as Phase A: can an agent predict each line from the source alone, and does a silent gap make it reason from false data?
>
> ## V1 — V1-frames (hold)
>
> To min: if a closure is not a frame, a `state` write inside `xs.map(fn(x) { ... })` reads as a write by the enclosing fn, at its depth. The agent then looks for the write in the wrong body. Closures passed to `map`/`filter`/`sort_by` are where a lot of agent-written bugs sit. Python's noise comes from comprehensions and generator frames, which Blink does not have.
>
> ## V2 — I move: drop `<...>` and use sys's keyword form with line:col
>
> devops is right that a name must work in `--trace=fn:...` with no shell quoting. `<closure@4>` holds `<` and `>`, which the shell reads as redirection. So I drop my form. I also take sys's point that `exit` and `state` lines have no `span`. If two closures in one fn share a name, `jq 'group_by(.fn)'` and `fn:` cannot tell them apart. A line alone also fails for `xs.map(fn ...).filter(fn ...)` on one line. My proposal:
>
> | Body | `fn` |
> |---|---|
> | closure | `main.apply.fn@2:12` (sys) |
> | handler op body | `main.run.handler@5:10.Log.emit` (position of `handler`, then effect path, then op) |
> | user effect default body | `main.Log.emit` (it has a unique declared place) |
> | `test` block | `main.test@12:1` |
>
> None of these names has a space, `<`, `>` or quote. `fn` and `handler` are keywords, so they cannot collide with a user name. With V4's dotted suffix, `fn:emit` and `fn:Log.emit` both select the handler body. A test name is a free string that holds spaces and quotes, so I keep it out of `fn`. If the panel wants it, sys's `main.test "adds two"` is my second choice.
>
> ```blink
> fn run() ! Log {
>     log.emit("hi")
> }
> fn main() ! IO {
>     with handler Log {
>         fn emit(s: Str) { io.println(s) }
>     } {
>         run()
>     }
> }
> ```
> ```json
> {"event":"effect","fn":"main.run","depth":1,"effect":"Log","op":"log.emit","args":{"s":"hi"}}
> {"event":"enter","fn":"main.main.handler@5:10.Log.emit","depth":2,"args":{"s":"hi"}}
> {"event":"effect","fn":"main.main.handler@5:10.Log.emit","depth":2,"effect":"IO.Print","op":"io.println","args":{"msg":"hi"}}
> ```
>
> ## V3 — the tracer's render calls write no events (hold)
>
> ## V4 — dotted suffix (web, plt, devops)
>
> It matches everything sys's last-segment rule matches, and `fn:Point.norm` too.
>
> ## V5 — V5-frames (hold)
>
> To min: "std no, everything else yes" is also one line, and it is as easy to state as "root package only". The bug an agent hunts is often in a dependency. The `module:` filter removes a dependency in one item. Root-only leaves no way to see dependency frames at all.
>
> ## V6 — V6-chain (hold)
>
> To min: the spec already takes this position. §2.x *Derived impls* (02_syntax.md:1424) says that derived Debug on an opaque type shows the hidden fields, and that an author who wants to hide one writes `impl Debug` by hand. Panic messages from `unwrap` and `assert_eq` already print Debug to stderr. So the trace prints nothing that the program's own panics would not print. Without Debug, every `Result` and `Option` arg or return reads as `<Result[Int, Str]>`. Those are the values an agent most needs to read.
>
> ## V7 — V7-call, key `msg` (hold); sub-point on derived ops
>
> To sys: under V7-operation, `io.println(x)` reads `"op":"io.print"`, and `io.print(x)` reads `"op":"io.print_no_nl"`. The first is the name of a different call that exists. An agent that greps for `io.print(` lands on the wrong lines. The "Called by" column in §4.4 already maps each op to its call spelling, so no new table is needed. A user effect gives the same string under both rules.
>
> Key `msg`: the value is the rendered `Str` that the handler gets, so the key is the handler op's param name. To plt: `x` is the wrapper's generic param, and its value is not what the event holds.
>
> Sub-point: an op that a **builtin** op's default body performs (`print_raw` → `print_no_nl`) gives no second event. One user call gives one event. A second event would carry a call spelling (`io.print`) that the user did not write. A user-written default body or handler body is a frame (V1), so the ops it performs still give events.
>
> ## V8 — V8-always first, V8-bare second; against V8-on-collision and V8-other-module
>
> V8-on-collision makes the string for one effect change when an unrelated module adds its own `Log`. Then a diff of two traces from two versions breaks, and nobody can predict the string from the local source. V8-other-module depends on where the effect is declared compared with the call site, which also cannot be read locally. If the panel prefers bare names (3 seats), I accept bare names: it is one rule.
>
> ## V9 — V9-method-name (hold); sub-points
>
> To min: a `jq` switch on `op` needs a default branch anyway, because `value` holds the full post-state. The cost of a closed set is the one devops named: `"op":"assign"` on a `sort` sends the reader to look for an `=` that is not in the source.
>
> I agree with plt that each call of a mutating method gives one event, even when nothing changes (`pop` on an empty list).
>
> `let mut` initial binding: I move to **an `assign` event** (sys's example shows one). It gives the start value, so the first mutation reads as a change, and `state:n` shows a binding that was set and never changed again. One line per `let mut` is cheap. I hold this loosely; the vote should settle it on its own.
>
> ## V10 — V10-none (hold, loosely)
>
> sys's case is real: on a big struct, the changed field can sit past the 200-char cut. But a path grammar with runtime indices needs a spec and escape rules. I would vote for `path` only if it is limited to static field names (`".x"`, `".a.b"`) and omitted when an index is part of the path. Without that limit, none.
>
> ## V11 — V11-env-only (hold); sub-points
>
> To web and devops: if argv is stripped, a program's own `--trace` flag still disappears under tracing. The env-only rule avoids both problems.
>
> - Agree with sys: a traced binary with `BLINK_TRACE` unset traces everything. It was built to trace. A binary run by hand that writes nothing would look like a broken tracer.
> - Agree with min: drop the `1` spelling; `all` means everything; `blink run --trace` overrides an inherited `BLINK_TRACE`.
> - `--trace-limit` / `BLINK_TRACE_LIMIT`: I move to **remove** (min). `head -n` covers it, and every knob is one more thing to learn.
>
> ## V12 — new: V12-error-at-run (against web's warning)
>
> A warning line breaks `2>trace.ndjson | jq`, because jq stops at the first line that is not JSON. But web's point holds: `blink run` built the program, so it has the complete static table of fn, module, effect and `let mut` names. In that table, a name that matches nothing is a typo for certain. So under `blink run`: exit 2, `error: --trace: fn:ad matches no function; did you mean add?`. A binary run by hand does not check, and an empty trace is its answer. If the panel rejects this, I prefer no check over a warning.
>
> OPEN — V7 (op spelling for the IO wrappers, and the derived-op second event), V12.

**Minimalism**

> # Phase B r1 — Min seat
>
> I move on three items: V1 (closures, handler bodies), V5 (packages) and V6 (Debug). On each one the
> other seats showed a real loss that my cut would cause. On the other items I hold.
>
> ## V1 — MOVE to V1-frames for closures and handler op bodies; `test` blocks still need no rule
>
> The `map`/`filter` callback case wins. Under my rule the closure's args are lost, and those are the
> values an agent wants. Attribution to the dynamic caller also gives a wrong `fn` for a closure stored
> and called later. A frame costs only a naming rule (V2). `test` blocks: `blink test --trace` is not
> in the spec. Add the frame when someone specs that flag. If the panel specs it now, I take the same
> form as V2 (`main.{test "adds"}`).
>
> ## V2 — plt's form, no position in the name
>
> `main.outer.{closure}`, `main.{handler Log}.emit`. Reasons:
> - No line, no col, no index. The `enter` span tells two closures apart, and enter/exit pair by
>   nesting, so `exit` does not need a unique name. A `#1` index or `@4:20` suffix is one more thing to
>   spec (what counts in the order, what if a reformat moves the line) and it changes the name under
>   an edit that does not change the code.
> - `{` `}` cannot occur in an identifier, so no collision with a user fn. `<...>` is already the
>   no-Display placeholder (V6); one bracket form per meaning.
> - The op stays the last segment, so `fn:emit` matches the handler body (aiml's point).
>
> ```blink
> fn main() ! IO {
>     let ys = [1, 2].map(fn(x) { x + 1 })
>     io.println("{ys}")
> }
> ```
> ```json
> {"event":"enter","fn":"main.main.{closure}","module":"main","depth":1,"span":{"file":"p.bl","line":2,"col":25},"args":{"x":"1"},...}
> {"event":"exit","fn":"main.main.{closure}","module":"main","depth":1,"return":"2",...}
> ```
> (`List.map` is std, so no frame and no depth step.)
>
> ## V3 — agree: a Display/Debug call made by the tracer writes no events
>
> Otherwise each `enter` nests a fake frame and depth lies. Same class as "the tracer must not change
> the program".
>
> ## V4 — dotted suffix on a `.` boundary
>
> `fn:norm`, `fn:Point.norm` and `fn:main.Point.norm` all match `main.Point.norm`. One rule, and it
> covers sys's last-segment form as a case. `fn:oint.norm` matches nothing.
>
> ## V5 — MOVE to V5-frames
>
> aiml is right: "fns compiled in this build" depends on details that a reader cannot see, and "the
> prebuilt std is not traced, all else is" is one bit. The bug is often in a dep, and `module:` cuts
> it out. My "your code" boundary needed a definition of "root package" that the trace rule should
> not depend on.
>
> ## V6 — MOVE to V6-chain: Display, else Debug, else `<TypeName>`
>
> My secrets objection does not hold up. §2 already gives the type author the control: to hide a field
> from Debug, "write `impl Debug` by hand". A derived Debug is an opt-in to show the fields. And sys is
> right that `Result` has no Display: a `<Result[Int, ParseError]>` return value tells the agent
> nothing. The pick is made per instantiation at mono time, so the chain costs no runtime work.
>
> Still reject: sys's `Bytes` as `<N bytes>`. That is a special case for one type. `Bytes` takes the
> chain like any type. If it should print shorter, change `Bytes`'s Debug, not the tracer.
>
> ## V7 — hold V7-call: `"op":"io.println"`
>
> The op is what the user wrote. sys's `io.print` (the handler op name) collides with the user call
> `io.print`, which reaches a different op (`print_no_nl`). The trace would then say `io.print` for a
> `io.println` call. That is wrong for the most common op in every program. sys's "a derived op gives
> two events" also doubles every `println` line.
>
> Key name: the declared param name of the call that `op` names, as the stdlib signature writes it. No
> extra rule. If that name is `msg`, the key is `msg`.
>
> ## V8 — hold V8-bare
>
> - V8-on-collision (plt): the string for `Log` changes when someone adds an unrelated module that also
>   declares `Log`. A trace key that depends on the whole program breaks saved `jq` scripts.
> - V8-always (aiml): two rules (builtins bare, user effects qualified) where one does.
> - V8-other-module (devops): the same string changes with the module that calls it.
> `module` already says where the call ran. A collision is rare, and `fn` resolves it.
>
> ## V9 — hold V9-five+assign; my second choice is V9-method-name, not plt's mapping
>
> The schema lists a closed enum today. With an open set, that row of the schema becomes "any method
> name", and every new mutating method in std changes trace output. plt's mapping (`Map.set` →
> `insert`) keeps the set closed but needs a table, and each new method needs an entry. If the panel
> wants a richer op, the method name as-is is one rule with no table. I prefer that over a mapping.
>
> Sub-points: agree with plt that each mutating call gives one event even when the store does not
> change (a `pop` on an empty list), because "did it run" is the question. Agree with aiml that the
> `let mut` initial binding gives no event.
>
> ## V10 — hold V10-none
>
> sys's case (the changed field past the 200-char cut) is real, but it is a truncation problem, not a
> path problem. A `path` field brings a grammar (`.x`, `[2]`, `[i].y`, a map key with a `]` in it) and
> its escaping. The `var` + whole value rule already holds.
>
> ## V11 — hold V11-env-only
>
> - Agree with sys: a traced build run by hand with `BLINK_TRACE` unset traces everything. It was
>   built to trace, and that rule makes the hand run match `blink run --trace`.
> - Hold: drop the `BLINK_TRACE=1` spelling; `all` (as in `BLINK_TRACE_CHANNELS`) is the one word for
>   everything. `blink run --trace` overrides an inherited value.
> - `--trace-limit` / `BLINK_TRACE_LIMIT`: remove. Nobody gave a case that `head -n` does not cover.
>   Since four seats said "spec or remove", put it on the ballot as remove vs spec.
> - To web/devops (strip): stripping needs a rule for `--`, for a program that takes its own
>   `--trace`, and for `env.args()` length. With env-only, none of those rules exist.
>
> ## V12 — no warning from `blink run`
>
> web's warning is a text line on the same stderr as the NDJSON, even if the CLI writes it before the
> program starts. `fn:typo` gives an empty trace. That is the right answer to the filter you wrote,
> and (10a) already says it is not an error.
>
> STABLE

#### Phase C — Silent vote

Each seat voted alone on the ballot.

**Systems**

> # Phase C ballot — sys seat
>
> ## Q1. Q1-frame
> Reasoning: one rule, "a body the user wrote is a frame", with no exception to state or remove later. It
> costs nothing until a traced test runs, and a test block has the same enter/exit shape as any body.
> Concern: we spec a frame for a flag (`blink test --trace`) that the spec does not have yet, so the rule
> waits for that flag before anything checks it.
>
> ## Q2a. Q2a-pos
> Reasoning: `event:effect` and `event:state` drop every `enter` line and its span, so the name is the
> only thing left that tells two closures apart. The position is a static string: zero cost.
> Concern: an edit above a closure renames it, so a saved filter goes stale.
>
> ## Q2b. Q2b-pos-op
> Reasoning: the position finds the `with handler` site; the op last keeps `fn:emit` working. The effect
> name is already in the `effect` event just before, so repeating it in `fn` only adds bytes per line.
> Concern: two handler bodies for different effects with the same op name on one line can only be told
> apart by col.
>
> ## Q2c. Q2c-plain
> Reasoning: a default body has one declared place per module, so `main.Log.emit` is unique, needs no
> position, and is shell-safe. I drop my Phase A keyword form for Q2e.
> Concern: if an effect name can equal a type name in a module, `main.Log.emit` could read as a method.
>
> ## Q2d. Q2d-pos
> Reasoning: the position needs no escape rules, and the test name is already in `blink test` output.
> A name string brings quotes and spaces into every filter.
> Concern: a reader must map `test@12:1` back to the test name by hand.
>
> ## Q2e. Q2e-shell-safe
> Reasoning: agents and scripts build `--trace=fn:...` on a command line. A form that needs no shell
> quotes removes one class of failed filter, at no runtime cost. I move from "any".
> Concern: `@` and `:` in a name are now reserved in the `fn:` value grammar; the writer must keep the
> filter's `:` split on the first colon only.
>
> ## Q6a. Q6a-debug
> Reasoning: Debug is the view the type author chose to write; `assert_eq` and `unwrap` panics print it
> already. A trace is a dev tool, the same as strace showing write buffers.
> Concern: a trace file sent to a bug tracker carries a secret that a derived Debug shows.
>
> ## Q6b. Q6b-chain
> Reasoning: I move. The 201-byte sink already bounds the cost, so no special case is needed for size,
> and one rule with no per-type table in the tracer is better. If `Bytes` prints badly, fix its Debug.
> Concern: if `Bytes` Debug does not show the length, a cut value hides how big the payload was.
>
> ## Q7a. Q7a-call
> Reasoning: the user greps the source for the `op` string; the handler op name would make `io.print(x)`
> look like `io.println`. One static name per op, zero cost.
> Concern: a handler author who intercepts `print_no_nl` must map it to `io.print` by the §4.4 table.
>
> ## Q7b. Q7b-each
> Reasoning: the agreed (2b) says an op performed anywhere, a default body included, gives an event;
> Q7b-one would make builtin default bodies the one exception. Each event is a real dispatch, and a
> handler that intercepts the inner op does see the second call.
> Concern: one `io.print_raw` line in source gives two events, which a reader may take for a double write.
>
> ## Q8. Q8-always
> Reasoning: the name must not depend on what else is in the program; on-collision and bare both break
> when a dep adds its own `Log`. Same form as `fn`, and the suffix match keeps `effect:Log` working.
> Concern: `effect` for a user effect no longer reads as the row the user wrote.
>
> ## Q9a. Q9a-method
> Reasoning: the method name is a static string with no mapping table, user methods with a mutable
> receiver need no rule, and `sort` versus `clear` versus `set` is data the closed set throws away.
> Concern: the `op` set is open, so a consumer must keep a default arm for names it does not know.
>
> ## Q9b. Q9b-none
> Reasoning: a binding is not a mutation, and the first `state` event then marks the first change.
> Concern: a consumer that rebuilds a variable's history must take the first value from the source, not
> from the trace.
>
> ## Q10. Q10-path
> Reasoning: with a `value` over 200 chars, a change past the cut gives two identical events; `path` is the
> only field that says what changed. A field path is static, and an index costs one Int format.
> Concern: the grammar (`.field`, `[Int]`) must stay closed; a later Map index write would bring key
> escaping in.
>
> ## Q11a. Q11a-remove
> Reasoning: `head -n` does it, and the check on every event is pure cost.
> Concern: a trace into a file (no pipe) has no cap, so a runaway loop can fill the disk.
>
> ## Q11b. Q11b-stop
> Reasoning: the tracer must not change the program; dying of SIGPIPE on a stream the program never
> wrote is the worst kind of observer effect. On the first failed trace write, set the trace flag off
> and continue.
> Concern: SIGPIPE is process-wide. Ignoring it changes the program's own stdout behavior, and masking it
> around each write costs two syscalls per event. The implementation must find a cheap, local way (for
> example check the stream once and block the signal only on the trace thread write path).
>
> ## Q12. Q12-none
> Reasoning: no lookup table in the binary, no extra phase in `blink run`, and an empty trace for a name
> that never ran is a correct answer. A check that only `blink run` does gives two behaviors for one
> filter string.
> Concern: a user with a typo sees an empty trace and may not know why.

**Web/Scripting**

> # Phase C ballot — Web seat
>
> ## Q1. **Q1-frame**
> A test with a bug is where a user most often turns on a trace. If the test frame is missing, its
> events attach to nothing at depth 0 and look like top-level code. The frame costs one name rule, and
> Q2d supplies it.
> Concern: if `blink test --trace` stays unspecced, the rule describes a flag that nobody can use.
>
> ## Q2a. **Q2a-pos**
> `exit` and `state` lines have no span, so with `{closure}` two callbacks in one fn give lines that
> cannot be told apart. The line:col is what the editor shows, so the user can find the source at once.
> Concern: the name changes each time the user edits a line above it, so a saved filter goes stale.
>
> ## Q2b. **Q2b-pos-effect-op**
> `fn:Log.emit` and `fn:emit` both select it under V4, and a reader sees which effect the body
> handles without opening the source. With only `.emit`, two handlers of different effects that each
> have an `emit` op look alike.
> Concern: the name is long; that costs some tokens, but it is no problem for a reader.
>
> ## Q2c. **Q2c-plain**
> I move away from my own option. A default body has one declared place, the same as a method, so
> `main.Log.emit` is unique and needs no position. It also reads like a method name, so a user does not
> have to learn a new form for it.
> Concern: a reader can take `main.Log.emit` for a method on a type named `Log`.
>
> ## Q2d. **Q2d-pos**
> This is the same form as Q2a and needs no escape rules for quotes or spaces in test names. The
> `blink test` JSON output maps a position to a test name.
> Concern: a user who knows the test only by its name must find its line before they can filter on it.
>
> ## Q2e. **Q2e-shell-safe**
> A user who types `--trace=fn:main.{closure}` and gets a shell error or a glob match asks about it on
> Stack Overflow on the first day. Names that need no quotes copy and paste from the trace into the
> next command.
> Concern: none worth naming.
>
> ## Q6a. **Q6a-debug**
> The author opted into Debug, and panics and failed asserts print the same string already. Special
> cases for opaque types add one more thing to learn and do not hide secrets in practice.
> Concern: a user who derives Debug on a type that holds a secret sees the secret in the trace and
> blames the tracer.
>
> ## Q6b. **Q6b-chain**
> "Why does my file contain the wrong bytes" is the question, and `<5 bytes>` cannot answer it. The
> first 200 characters of the Debug form can. One rule for every type is easier to learn.
> Concern: a large `Bytes` value costs format time up to the cut on each event.
>
> ## Q7a. **Q7a-call**
> The user greps for what they wrote. `io.print(x)` showing as `io.print_no_nl` while `io.println`
> shows as `io.print` is a trap.
> Concern: a handler author who intercepts `print` must map call spellings to ops in their head.
>
> ## Q7b. **Q7b-one**
> One call in the source gives one line in the trace. That is the result a user expects, and a
> second event from a std-internal default body is noise. A user-written body is a frame, so its own
> ops still show.
> Concern: a user who handles `print_no_nl` and calls `io.print_raw` sees no event that names the op
> their handler got.
>
> ## Q8. **Q8-always**
> I move. A name that always carries the module is unique and stable: adding a module does not change
> old traces, which was my objection to on-collision. `effect:Log` still selects it, so the user types
> what they wrote in `! Log`.
> Concern: the output (`p.Log`) differs from the row spelling, and this makes one small
> "why the prefix?" question.
>
> ## Q9a. **Q9a-method**
> `xs.sort()` that writes `"op":"assign"` gives a confused reader. User types have their own mutating
> methods, so the set is open in any case.
> Concern: jq scripts that switch on `op` need a default branch, and some users will forget it.
>
> ## Q9b. **Q9b-none**
> A declaration is not a mutation, and a JS dev does not expect `let` to show as a state change.
> Concern: a reader who wants the start value must read it from the source or the first change.
>
> ## Q10. **Q10-none**
> It covers a rare case and adds a field with a small grammar. The value shows the change in most
> cases. Add `path` if users ask for it.
> Concern: a change past the 200-character cut on a large struct is not visible.
>
> ## Q11a. **Q11a-remove**
> `head -n` does the job. A knob that is not in the spec is one that users find by accident.
> Concern: a program that writes millions of events still pays for each one up to the pipe; `head`
> alone does not stop that cost (Q11b helps).
>
> ## Q11b. **Q11b-stop**
> `blink run p.bl --trace 2>&1 | head` is the first thing a web dev types. If it kills the program with
> SIGPIPE, the trace changes the behavior under study, which is a heisenbug.
> Concern: the program keeps running after the reader has gone, and that can be slow for a long job.
>
> ## Q12. **Q12-run-error**
> I move. In Phase A I wanted a check at this point, and I withdrew it only because a warning line
> breaks the NDJSON stream. A usage error before the program starts breaks nothing, and it answers
> "why is my trace empty" (the typo, or the std fn) in one line. A binary run by hand stays unchecked,
> which is fine.
> Concern: the check must know every synthetic name (`fn@5:29`) and the V4 suffix rule exactly, or it
> rejects a valid filter.

**PLT**

> # Phase C ballot — PLT seat
>
> ## Q1 — Q1-frame
> A `test` block is a body the user wrote and applies like any fn. V1 already makes every user body a
> frame. An exception for tests would be a second rule with no semantic reason.
> Concern: until `blink test --trace` is in the spec, the frame rule has no specified way to run.
>
> ## Q2a — Q2a-pos
> `exit` and `state` have no span. Without a position, two closures in one fn give the same `fn`
> string, so `fn` is not a function of the frame. A name must identify its frame on every event.
> Concern: a line:col shifts when code above it changes, so names in an old trace go stale.
>
> ## Q2b — Q2b-pos-effect-op (I move from nopos)
> The Q2a reason applies here as well: one fn can install two handlers for `Log`, and without a
> position their bodies get the same name. The effect segment keeps the name complete when two
> effects have an op with the same name. The op stays last, so `fn:emit` still matches under V4.
> Concern: the names get long; the writer must give the full grammar in one place.
>
> ## Q2c — Q2c-plain
> A default body has exactly one declared place: the effect declaration. `main.Log.emit` follows the
> `module.Type.method` shape. With Q8-always it lines up with `"effect":"main.Log"`.
> Concern: a reader may take `main.Log.emit` for a method of a type `Log`. The rule must make sure no
> type and effect in one module share a name.
>
> ## Q2d — Q2d-pos
> This is the same shape as the closure and handler names. It also needs no escape rules for any
> character a test name string can hold.
> Concern: the name does not say which test it is, so a reader has to look up the line.
>
> ## Q2e — Q2e-shell-safe
> With the positional forms above, no synthetic segment needs brackets or a space, so the filter
> needs no shell quotes. That makes it easy for an agent to build the flag.
> Concern: `@` and `:` must stay free of meaning in the filter grammar; the key/value split must be at
> the first `:` only.
>
> ## Q6a — Q6a-debug
> §2 makes a hand-written `impl Debug` the way to hide a field. Panics and `assert_eq` already print
> Debug. If the tracer skipped opaque types, a type's render would depend on its visibility as well
> as its impls, which is a second, irregular rule.
> Concern: authors who never read §2 will leak secrets into traces that someone shares.
>
> ## Q6b — Q6b-chain
> The tracer has one rendering function for all types. A special case for `Bytes` breaks that. If
> `Bytes` Debug is bad for traces, fix it where it is defined, and every consumer gets the fix.
> Concern: until that Debug changes, a large `Bytes` arg costs a format up to the 200-char cut on
> each event.
>
> ## Q7a — Q7a-operation
> An effect event observes an operation, which is what a handler receives. `io.println` is a generic
> std fn wrapper, and 2a says std fns are not frames. If the call spelling is used, each wrapper needs
> its own spec entry, and the event no longer agrees with what an intercepting handler sees.
> Concern: if the call spelling wins, the spec must list each wrapper's op string and its `args` key,
> and keep that list current.
>
> ## Q7b — Q7b-each
> The trace must show the operations that actually happened. A handler for `print_no_nl` does see the
> second call, so the trace must too. This also matches 2b: an effect op performed anywhere gives an
> event.
> Concern: if Q7b-one wins, the trace and a handler disagree about how many operations ran.
>
> ## Q8 — Q8-always
> A field's value must not depend on code that does not touch it. Only a value that always has the
> qualifier meets this; a bare name can collide. The filter takes the short or the full name, so
> users lose nothing.
> Concern: under Q8-bare, two modules that each declare `Log` give events that no field tells apart.
>
> ## Q9a — Q9a-five
> The schema gives `op` as a closed set of five values, so a consumer can match all of them. `value`
> holds the full post-state, so a method name adds no information about the store. An open set makes
> each new std method a schema change.
> Concern: if Q9a-method wins, the spec must still say which methods count as "mutating" and how a
> user `mut self` method is named.
>
> ## Q9b — Q9b-none
> A binding is not a transition of the store. The `enter` args and later events already show the
> start state where it matters.
> Concern: a var whose first event is a `pop` makes the reader work out the state before it.
>
> ## Q10 — Q10-none
> The full binding is in `value`. A path with runtime parts (index or map key) needs its own escape
> and cut rules.
> Concern: on a large struct, the changed field can lie past the 200-char cut, and then the event
> does not show it.
>
> ## Q11a — Q11a-remove
> An option that is not in the spec is a latent contract, so remove it. A limit can come back
> through the panel if Q11b's rule does not cover the use case.
> Concern: users who rely on `--trace-limit` in scripts will lose it with no warning.
>
> ## Q11b — Q11b-stop
> Tracing must not change what the program does. A trace write that kills the program with SIGPIPE
> breaks that. With Q11a-remove, `head -n` becomes the main limit tool. The rule is then needed, not
> optional.
> Concern: stdout and stderr can share one pipe (`2>&1`). The rule must stop trace writes only, and
> must leave the SIGPIPE behavior for the program's own writes as it is.
>
> ## Q12 — Q12-none
> A filter is a predicate. A well-formed predicate that matches nothing has a meaning: its result is
> empty. With Q12-run-error, the same `BLINK_TRACE` string would be valid by hand and an error under
> `blink run`, so one string would have two meanings.
> Concern: a typo in `fn:` gives a silent empty trace, and an agent may read that as "never called".

**DevOps/Tooling**

> # Phase C ballot — devops
>
> ## Q1 — Q1-frame
> Reasoning: a test is the most common place an agent wants a trace: "why did this assert fail?" If
> the test body is not a frame, its state and effect events carry no frame of their own, and the
> depth-0 events have no `fn` to name. The rule costs one line now. Adding it later means a second
> pass over the frame rules.
> Concern: `blink test --trace` is not specced, so the frame rule ships with no way to turn it on.
> The writer must spec the flag in the same change, or the rule is dead text.
>
> ## Q2a — Q2a-pos
> Reasoning: `exit` and `state` lines have no span. Without a position, two closures in one fn give
> the same `fn` on their `exit`, and a reader cannot pair them except by depth and order. Line:col
> leads straight to the source.
> Concern: the name changes when a line above it moves, so a saved `fn:` filter on a closure breaks
> after an edit. That is fine for a debug tool, but the spec should say so.
>
> ## Q2b — Q2b-pos-effect-op
> Reasoning: I move from Q2b-pos-op. With the effect in the name, `fn:Log.emit` selects every
> handler body and the default body (Q2c-plain) of that op, under V4. A reader also sees which
> effect a handler serves without the `enter` span.
> Concern: the names get long (`main.main.handler@4:10.Log.emit`), and they cost tokens on every
> event.
>
> ## Q2c — Q2c-plain
> Reasoning: the default body has one declared place, as a method does, so it needs no synthetic
> segment. `main.Log.emit` matches the method form `module.Type.method`.
> Concern: an effect and a type with the same name in one module would collide, but only if the
> namespace allows that, and I believe it does not.
>
> ## Q2d — Q2d-pos
> Reasoning: a test name is free text with spaces and quotes. In `fn` it needs JSON escapes, and
> in a filter it needs shell quotes. The position is safe, and `blink test --json` already maps a
> position to a name.
> Concern: a reader of the trace alone cannot see the test's name, and must look it up.
>
> ## Q2e — Q2e-shell-safe
> Reasoning: users and agents write `--trace=fn:...` in a shell. A form that needs quotes fails in
> a way that is hard to see: the shell eats `<` as a redirect, or splits on the space. The filter
> then turns into a different command.
> Concern: `@` and `:` must stay free of meaning in the filter grammar for good. The writer must
> note that the filter parser splits on the first `:` only.
>
> ## Q6a — Q6a-debug (I move)
> Reasoning: plt's point decides it. `assert_eq` failures and `.unwrap()` panics already print Debug,
> so a trace that hides it protects nothing. An author who wants to hide the fields writes a Display
> impl, and Display comes first. One chain with no exception is easier to explain in an error doc.
> Concern: traces get pasted into tickets, so a secret in a derived Debug leaks. The spec should
> carry one note that a trace shows Debug output.
>
> ## Q6b — Q6b-chain
> Reasoning: one rule for every type. The content of a Bytes value, capped at 200 chars, is what
> you need to debug a protocol, and `<5 bytes>` throws it away. If Bytes Debug reads badly, fix it
> in one place.
> Concern: a large Bytes value formats in full before the cut, unless the sink stops at 201 bytes as
> sys asks. The writer should keep that cost rule.
>
> ## Q7a — Q7a-call
> Reasoning: the trace line must name a call that is in the source at that site. Otherwise
> `grep io.print` finds the wrong line, and `io.println` shows up as `io.print`. A handler author who
> wants the op level has the handler body frame (V1).
> Concern: a user who writes an `IO.Print` handler sees `op:"io.println"` in the trace but writes
> `fn print` in the handler, so the two names differ. One sentence in the spec covers it.
>
> ## Q7b — Q7b-one
> Reasoning: one user call gives one event, so you can count events against call sites. The extra
> event from a builtin default body is runtime detail that the user did not write.
> Concern: a user handler that intercepts `print_no_nl` sees a call that the trace does not show.
> That handler's body is a frame, so its `enter` shows up anyway.
>
> ## Q8 — Q8-always
> Reasoning: one effect has one name, wherever it is called and whatever else is in the program. A
> saved `jq` query does not break when a dep adds its own `Log`. The `effect:Log` short form keeps
> the filter as short as before.
> Concern: `p.Log` next to a bare `IO.Print` looks odd. The writer must say why builtins are bare
> (reserved names, E0559).
>
> ## Q9a — Q9a-method
> Reasoning: `"op":"assign"` on a `sort` sends the reader to look for an `=` that is not there. The
> method name greps straight to the line. `value` carries the state either way, so a consumer that
> switches on `op` loses nothing it needs.
> Concern: the set is open, so a schema doc cannot list it. The spec must say "the method name", not
> a table that goes stale.
>
> ## Q9b — Q9b-none
> Reasoning: the binding is not a mutation, and `state` means a store change. The first value is in
> the source.
> Concern: a `let mut` set from a call result shows no starting value until the first mutation.
>
> ## Q10 — Q10-path
> Reasoning: on a struct over 200 chars, the field that changed can sit past the cut, and then the
> event shows a write but not what it wrote. `.field` and `[Int]` only is a small grammar.
> Concern: it is a new field and a small grammar that tools must parse. If Q10-none wins, an agent
> must diff two cut values.
>
> ## Q11a — Q11a-remove
> Reasoning: both flags are unspecced and unused, and `head -n` covers the need. Fewer flags mean
> fewer flags to explain in `--help`.
> Concern: `head -n` does not stop a hot loop from making events. A user who traces a long run pays
> the event cost to the end.
>
> ## Q11b — Q11b-stop
> Reasoning: `2>&1 | head` is the way people take a trace. If the tracer kills the program, the
> tool changes what it observes, the same failure as an argv change. When a trace write fails, set
> tracing off and go on.
> Concern: with `2>&1`, the program's own stderr writes go to the same closed pipe and can still
> die of SIGPIPE. The rule fixes only the tracer's share.
>
> ## Q12 — Q12-run-error
> Reasoning: a typo in `fn:` is the most common way to get an empty trace, and an empty trace reads
> as "add never ran". `blink run` has the name table after typecheck. Using it costs nothing and
> writes no non-JSON line into the stream, because the program never starts. "An empty trace for a
> name that never ran is a correct answer" holds for a declared name, and this option keeps that.
> Concern: a name that is declared only in a dep the build drops as dead code must still count as
> declared, or the check gives a false error.

**AI/ML**

> # Phase C ballot — aiml
>
> ## Q1 — Q1-frame
> Reasoning: an agent that debugs a failing test needs the test body to be a root frame. Without it, the test's effect and state events have no frame to credit, and depth 0 means nothing. One rule covers every body the user wrote, so the agent need not learn an exception.
> Concern: `blink test --trace` is not in the spec yet, so the rule has no flag to reach it until the writer specs one.
>
> ## Q2a — Q2a-pos
> Reasoning: `exit` and `state` lines have no span, so with `{closure}` two closures in one fn give the same `fn`. Then `group_by(.fn)` merges them and `fn:` cannot pick one out. Line:col also splits two closures on one line in a `.map(...).filter(...)` chain.
> Concern: the name changes when lines above it move, so a saved filter or a diff of two traces breaks after an edit.
>
> ## Q2b — Q2b-pos-effect-op
> Reasoning: the effect path in the name lets `fn:Log.emit` select the body without the agent knowing the position. The position tells apart two handlers of the same effect in one fn. Under V4, `fn:emit` also still works.
> Concern: the name is long, and it costs tokens on every enter and exit line of a busy handler.
>
> ## Q2c — Q2c-plain
> Reasoning: the default body has one declared place in the effect declaration, the same as a method has in a type. So `main.Log.emit` is unique and needs no synthetic segment. It reads as the agent would guess it from the source.
> Concern: a type and an effect that share a name in one module could give the same string. I believe the shared namespace stops that, but the writer should check.
>
> ## Q2d — Q2d-pos
> Reasoning: a test name is a free string that can hold spaces and quotes, so `fn` would need escape rules, and every `fn:` filter would need shell quoting. The position form keeps the same grammar as Q2a and Q2b. An agent maps it to the test through the `enter` span.
> Concern: a person who reads the trace sees `test@12:1`, not "adds two", and must open the file to know which test it is.
>
> ## Q2e — Q2e-shell-safe
> Reasoning: agents build `--trace=fn:...` strings and run them in a shell. A name that holds `<`, `>`, a space or a quote breaks without quotes, and a broken command fails in a way that is hard to explain. A name that is safe in the shell can be pasted from the trace into the filter unchanged.
> Concern: none of note. The keyword plus `@line:col` form has to stay free of these characters as new synthetic kinds are added.
>
> ## Q6a — Q6a-debug
> Reasoning: Debug is the view the type author declared for developers, and the spec says to hide a secret with a hand-written `impl Debug`. Panics already print Debug. An opaque exception would add a decision point that the agent cannot see from the call site.
> Concern: an author who did not read the §2 note leaks a secret into a trace file that someone later shares.
>
> ## Q6b — Q6b-chain
> Reasoning: one rendering rule with no special case per type. The first 200 chars of the bytes are often the answer to the question (a protocol header, a magic number). If `<5 bytes>` is the better form, change the Debug form of `Bytes` and every other surface gains too.
> Concern: if `Bytes` Debug is verbose, the 200-char cap fills with very little real data.
>
> ## Q7a — Q7a-call
> Reasoning: an agent greps for the `op` string to find the call. `"op":"io.print"` for an `io.println` line points it at a different call that exists. The §4.4 "Called by" column already maps each op to its call, so this rule needs no new table.
> Concern: a handler author who intercepts `print_no_nl` must map `io.print` to that op through §4.4.
>
> ## Q7b — Q7b-one
> Reasoning: one user call gives one event, so the agent can predict the count from the source. A second event would carry a call spelling the user never wrote. Ops that user-written default or handler bodies perform still give events, because those bodies are frames.
> Concern: a user handler that intercepts `print_no_nl` under `print_raw` runs with no matching effect line. The agent then sees the handler's frame without the op that reached it.
>
> ## Q8 — Q8-always
> Reasoning: the declaring module is part of an effect's identity, and an agent can predict the string from the declaration alone. It does not depend on import spelling, on the call site, or on whether another `Log` exists. The `effect:Log` filter keeps the short form.
> Concern: user effect strings and builtin strings (`IO.Print`) take two shapes, and an agent may expect `std.IO.Print` by analogy.
>
> ## Q9a — Q9a-method
> Reasoning: `"op":"sort"` greps straight to the line, and `"op":"assign"` on a `sort` sends the reader to look for an `=` that is not in the source. With no mapping table, a new collection method needs no spec change. `value` holds the post-state, so a consumer that only wants "did it change" ignores `op`.
> Concern: a consumer that switches on a closed set of `op` values breaks without a default branch.
>
> ## Q9b — Q9b-none (I move)
> Reasoning: §8.15.2 defines `state` as a mutation, and a binding that is first created is not one. The first mutation event already holds the whole value. I held Q9b-assign loosely, and the case for the extra line per `let mut` is weak.
> Concern: a `let mut` that is never changed leaves no trace, so `state:n` shows nothing and does not say what the start value was.
>
> ## Q10 — Q10-none
> Reasoning: Q10-static makes a field that is present only sometimes, so the agent cannot predict whether `path` appears without parsing the place. With Q10-path, runtime indices need an escape grammar. The value holds the place, as plt says.
> Concern: on a big struct the changed field can sit past the 200-char cut, so the event cannot show what changed (sys's case).
>
> ## Q11a — Q11a-remove
> Reasoning: a knob that is not in the spec cannot be learned, and `head -n` does the same job. Fewer flags means fewer names an agent can get wrong.
> Concern: a program that writes millions of events runs with the full trace cost, where a limit could have stopped early.
>
> ## Q11b — Q11b-stop
> Reasoning: the observer must not change the program. `2>&1 | head` is a common pattern for agents, and a program that dies of SIGPIPE only under trace makes the agent chase a bug that does not exist. The spec already says a traced run differs from an untraced one only in stderr.
> Concern: the runtime must ignore EPIPE on the trace stream without changing how the program itself sees SIGPIPE on its own writes to stderr.
>
> ## Q12 — Q12-run-error
> Reasoning: an empty trace for `fn:ad` is the silent-gap case, and the agent concludes "add never ran" and debugs the wrong thing. `blink run` has the full table of declared names, so a name in no declaration is a typo for certain. A declared name that does not run gives an empty trace, which is correct. The `std fns are not traced` error also answers a likely agent mistake.
> Concern: a binary run by hand accepts the same filter and does not check it, so the two paths act differently.

**Minimalism**

> # Phase C ballot — Min seat
>
> ## Q1. Is a `test` block a frame?
> **Vote:** Q1-no-rule
> **Reasoning:** No part of the spec has `blink test --trace`, so a rule for test frames constrains a
> flag that does not exist. When someone specs that flag, the frame rule goes in with it, under the
> same naming rule as Q2. Spec text with no flag to use it is dead surface.
> **Concern:** If Q1-frame wins, the frame rule will come before the flag spec, and the flag spec may
> then not fit it.
>
> ## Q2a. A closure
> **Vote:** Q2a-pos (I move)
> **Reasoning:** The position lets `fn:` select one closure out of two in the same fn, and it keeps
> apart the `state` events of two closures, which have no span. My nesting argument covers only
> enter/exit pairing, not those two uses. Both forms are one naming rule, so the cost is equal and the
> position gives more.
> **Concern:** The name changes when a reformat moves the keyword, so a saved filter breaks after an
> edit that does not change the code.
>
> ## Q2b. A handler op body
> **Vote:** Q2b-pos-op
> **Reasoning:** This is the shortest form that is still unique. The `effect` field of the event at the
> perform site already names `Log`. The position tells two handlers apart, so the effect name in the
> segment adds nothing.
> **Concern:** A reader who sees only the enter line of the body must look up which effect the handler
> at 4:10 is for.
>
> ## Q2c. Default body of a user effect op
> **Vote:** Q2c-plain
> **Reasoning:** The default body has one declared place, as a method has, so it takes the method form
> `module.Effect.op`. No synthetic segment is needed where a real name exists.
> **Concern:** `main.Log.emit` can look like a method of a type `Log`. The `effect` events around it
> clear that up.
>
> ## Q2d. A test block (if Q1-frame wins)
> **Vote:** Q2d-pos
> **Reasoning:** This is the same rule as Q2a/Q2b: keyword plus line:col, with no string escaping.
> **Concern:** The test name, which a user knows better than the line, is not in the trace.
>
> ## Q2e. Delimiter
> **Vote:** Q2e-shell-safe
> **Reasoning:** A filter that needs shell quotes fails in a way that is easy to miss: the shell eats a
> `<` or a space with no error. A name with no shell metacharacters also needs no escaping in JSON or
> in `jq`.
> **Concern:** None from my view.
>
> ## Q6a. Opaque type with derived Debug
> **Vote:** Q6a-debug
> **Reasoning:** A special case for opaque types adds a branch to a chain that was one line. The author
> already controls this: a hand-written `impl Debug` hides the field. Panics and `assert_eq` already
> print Debug.
> **Concern:** A user who did not read §2's note will see a secret in a trace that they then paste into
> a bug report.
>
> ## Q6b. `Bytes`
> **Vote:** Q6b-chain
> **Reasoning:** A tracer case for one type is the start of a list of cases. If `Bytes` Debug output is
> too long, the 200-char cut bounds it, and `Bytes` can change its own Debug.
> **Concern:** The first 200 chars of a byte dump tell an agent less than the length would.
>
> ## Q7a. `op` string for a std IO wrapper
> **Vote:** Q7a-call
> **Reasoning:** The trace reports what the user wrote. Under the operation form, `io.println` reads as
> `io.print`, which is a different user call. That is a wrong answer for the most common op in every
> program.
> **Concern:** A handler author who intercepts `print` must know which wrapper calls give that op.
>
> ## Q7b. A builtin op whose default body does another op
> **Vote:** Q7b-one
> **Reasoning:** One user call gives one event, so the trace size tracks the user's code and not std
> internals. A user-written body is a frame anyway, so the ops it does still show.
> **Concern:** A user handler for `print_no_nl` sees a call that the trace does not list under that
> name.
>
> ## Q8. `effect` for a user effect
> **Vote:** Q8-bare
> **Reasoning:** Q8-always gives two spelling rules (builtin bare, user qualified) and a filter that
> must accept both names. `module` and `fn` already say where the call ran, and a name collision is
> rare.
> **Concern:** Two `Log` effects in one program read the same in `effect`, and a `jq` script must also
> check `fn` to tell them apart.
>
> ## Q9a. State `op` values
> **Vote:** Q9a-five
> **Reasoning:** The schema lists a closed set. An open set means every new mutating method in std
> changes trace output, and `op` becomes "any name". The value after the change carries the truth.
> **Concern:** `"op":"assign"` for a `sort` hides the method name. An agent must diff the values to see
> what the call did.
>
> ## Q9b. Initial `let mut` binding
> **Vote:** Q9b-none
> **Reasoning:** A binding is not a mutation, and the `state` type observes store transitions only.
> **Concern:** The first value of a binding shows only after its first change.
>
> ## Q10. `path` field
> **Vote:** Q10-none
> **Reasoning:** A path brings a grammar and its escaping. Q10-static makes the field present or absent
> by how the place was written, so the key set varies again. The whole value already shows the change.
> **Concern:** On a large struct, the changed field can sit past the 200-char cut.
>
> ## Q11a. `--trace-limit` / `BLINK_TRACE_LIMIT`
> **Vote:** Q11a-remove
> **Reasoning:** No seat gave a case that `head -n` does not cover. Two knobs fewer.
> **Concern:** A long-running program writes events until the user stops it. Disk use is on the user.
>
> ## Q11b. Closed trace stream
> **Vote:** Q11b-stop
> **Reasoning:** The tracer must not change what the program does, and death by SIGPIPE from a trace
> write breaks that. `| head` is the common way an agent reads a trace, which makes this the common
> case. The rule is one sentence and costs one write-error check.
> **Concern:** With `2>&1`, the program's own stdout writes still meet the closed pipe. A reader may
> think this rule covers them too.
>
> ## Q12. Filter name that matches nothing, under `blink run`
> **Vote:** Q12-none
> **Reasoning:** An empty trace is the true answer to the filter. A check would make `blink run` and a
> hand-run binary act in different ways on the same filter. It also brings name-lookup and
> "is it std" rules into the CLI.
> **Concern:** A typo like `fn:ad` gives an empty trace, and the user may read that as "never called".

#### Phase D, debate — Replies on the five open points

Five points stayed open after Phase C (Q2b, Q7b, Q9a, Q10 and Q12). Each seat replied to the digest of the Phase C result.

**Systems**

> # Phase D — sys seat
>
> Moves: **Q2b** to Q2b-pos-effect-op, **Q10** to Q10-none. Hold: Q7b-each, Q9a-method, Q12-none.
>
> ## Q2b — move to Q2b-pos-effect-op
>
> devops's point decides it for me: with the effect in the name, `fn:Log.emit` selects every handler
> body and the default body (Q2c-plain `main.Log.emit`) of that op with one filter, under V4. My
> "bytes per line" point is weak: the name is a static string, and 4 more bytes per line is noise
> next to `ts_us`. min's point (the `effect` event names `Log`) fails under `event:enter`, which drops
> that line.
>
> ## Q7b — hold Q7b-each
>
> To "one user call gives one event": the agreed (2b) does not count user calls. It counts ops
> performed, "a default body included". Q7b-one carves out one case: a builtin default body. Then the
> spec needs a list of which bodies count as builtin.
>
> aiml's and web's own concern is the strongest point for Q7b-each: under Q7b-one, a user handler for
> `print_no_nl` gives an `enter` line for `main.main.handler@4:10.IO.Print.print_no_nl` with no effect
> line that reached it. The trace then shows a frame with no cause. Under Q7b-each:
>
> ```json
> {"event":"effect","fn":"main.main","effect":"IO.Print","op":"io.print_raw","args":{"s":"c"},...}
> {"event":"effect","fn":"main.main","effect":"IO.Print","op":"io.print","args":{"msg":"c"},...}
> {"event":"enter","fn":"main.main.handler@4:10.IO.Print.print_no_nl","depth":1,...}
> ```
>
> Each frame has its cause, and the count equals the number of dispatches a handler can see. On the
> "double write" reading: `op` differs on the two lines, so no reader takes them for one op twice.
>
> ## Q9a — hold Q9a-method
>
> To plt: "which methods count as mutating" is a fact the compiler already has: a method with a `mut
> self` receiver, called on a `let mut` binding. The name is the method name as written, the same for a
> user method. That is one sentence, with no table. A new std method is not a schema change under this
> rule; the rule stays the same and the new name follows from it. Under Q9a-five, by contrast, every
> new method needs a ruling ("is `retain` an `assign` or a `remove`?"). To min: "the value carries the
> truth" is true only below the 200-char cut; above it, `op` is the only hint left, and `assign`
> destroys it.
>
> ## Q10 — move to Q10-none
>
> I said in round 1 this was not a hill. The case (a change past the cut) is real but rare, and four
> seats prefer no new field. With Q9a-method, a method write past the cut still shows its op; the gap is
> only for `p.field = v` on a large struct. That is the cost I accept. Add `path` if users report it.
>
> ## Q12 — hold Q12-none
>
> To devops ("costs nothing"): the check is a second filter matcher, in the CLI, that must agree with
> the runtime on the V4 suffix rule, every synthetic name (`fn@5:29`, `handler@4:10.Log.emit`,
> `test@12:1`), module names of deps, and dead code that the build drops. web names the same risk.
> Each mismatch rejects a valid filter, and a valid filter that `blink run` rejects is worse than an
> empty trace: the user cannot trace at all. Two implementations of one predicate is the cost.
>
> To aiml's "an empty trace reads as never called": that holds for a declared name that does not run
> too, which all seats accept as correct output. The fix for the typo case belongs in tooling that does
> not gate the run (`blink query --fn ad` already tells a user the name does not exist).
> plt's point stands: one `BLINK_TRACE` string should have one meaning.

**Web/Scripting**

> # Phase D — Web seat
>
> I do not move on any of the five.
>
> ## Q2b: stay Q2b-pos-effect-op
>
> To sys and min ("the `effect` event just before already names `Log`"): that is true only when the
> reader has the line before it. A reader who filters with `--trace=event:enter+exit`, or with
> `fn:emit`, does not see the effect line. A name must make sense on its own line. Also, a
> `--trace=fn:Log.emit` filter that selects every body for that op (each handler and the default body,
> Q2c-plain) works only if the effect is in the name. A few bytes per line is a small cost for a filter
> that a user can guess.
>
> ## Q7b: stay Q7b-one
>
> To sys ("2b says an op anywhere gives an event; Q7b-one makes builtin default bodies the one
> exception"): 2b exists so that effects in std do not disappear. Under Q7b-one, no effect
> disappears: the user's one call gives one event, and that event names the call. What Q7b-each adds is
> a second line with a spelling the user never wrote (`io.print` for a line that says `io.print_raw`).
> A JS dev who sees two lines for one call reads it as a double write, which is sys's own concern.
>
> To plt ("the trace and a handler disagree about how many operations ran"): when a user handler
> handles the inner op, its body is a frame (V1), so its `enter` line appears, with its name
> (`handler@...IO.Print.print_no_nl`) and its args. Nothing that runs user code is hidden. What is
> hidden is a std-internal dispatch that runs only std code, and the "std is not traced" rule already
> hides that kind of detail.
>
> ## Q9a: stay Q9a-method
>
> To plt and min ("the schema gives a closed set"): today the schema lists five words, and nothing in
> it ever covered `sort`, `set`, `clear` or a user's `mut self` method. That gap is the reason this
> ticket exists. A closed set must then put a user's `account.deposit(5)` under `assign`. That hides the
> one fact the reader wants (which call changed the value) and sends them to look for an `=`.
>
> On "each new std method is a schema change": with Q9a-method, it is not. The rule is "the method
> name", so a new method needs no spec text. The closed set needs a mapping decision for each new
> method.
>
> On plt's concern: the rule must say what "mutating" means. My answer: a call of a method that takes
> `mut self`, on a `let mut` binding or on a part of one, gives one event with `op` = that method's
> name, for std and user methods alike. That is one sentence, not a table.
>
> ## Q10: stay Q10-none
>
> sys and devops are right about the case: past the cut, two events can look alike. But it happens only
> on a struct whose Display or Debug form is over 200 characters and whose changed field comes after
> character 200. A `path` field brings a grammar that every consumer must parse, and for that one case
> YAGNI wins. If users report it, we add `path` later as a new field, and old consumers ignore it.
> Adding it later breaks no one; removing it would.
>
> ## Q12: stay Q12-run-error
>
> To plt ("one string, two meanings"): the meaning does not change. Under both paths, the filter
> selects the same events. `blink run` adds a check before the run, in the same way that `tsc` rejects
> a typo that plain JS runs without complaint. The check never changes what a valid filter does. It
> stops a run whose answer is almost sure to be wrong, and it makes the user retype.
>
> To sys and min ("an empty trace is a correct answer"): it is correct for a name that exists and did
> not run, and Q12-run-error keeps that case. For `fn:ad`, an empty trace is correct and useless. Its
> cost lands on the most common path: a dev who typed one character wrong, or who asked for a std fn,
> and who then reads "add never ran". sys's own concern says so. A cheap error at the one place that has
> the name table is the fix.
>
> On the concerns for my side (devops: a dep fn that the build drops as dead code; my own: synthetic
> names): the check must test names against all declarations after typecheck, before dead code goes,
> and against the synthetic-name grammar plus the V4 suffix rule. If the writer cannot state that
> check in a short paragraph, I would sooner take Q12-none than a check with false errors.

**PLT**

> # D1 — PLT seat
>
> I move on Q12. I hold on Q2b, Q7b, Q9a and Q10.
>
> ## Q2b — hold Q2b-pos-effect-op
>
> sys and min say the `effect` event just before the body already names `Log`. With Q7a-call settled,
> that is not always true. Under `io.print_raw`, a handler for `print_no_nl` runs, and (under Q7b-one)
> no effect line names the op it got. A filter such as `event:enter` or `fn:emit` also cuts the
> effect line. The `fn` of a frame must then say what it is by itself. sys's own concern (two
> handlers on one line, told apart only by col) is a case that the effect segment fixes.
>
> ## Q7b — hold Q7b-each
>
> All four Q7b-one seats say "one user call gives one event". But agreed 2b says an op performed
> **anywhere**, std included, gives an event. Q7b-one needs an exception clause in 2b: "except a
> dispatch from a builtin op's default body". Nothing marks that body as different from a std helper
> that calls `fs.write`, which 2b does trace. So one of two things happens. The rule names each
> builtin default body (a list that grows), or the trace drops ops depending on where std happens to
> put the code (a change inside std then changes the trace).
>
> The concern all four seats wrote down (a handler frame that runs with no effect line) is the result
> of that exception, not of Q7b-each. Under Q7b-each:
>
> ```blink
> fn main() ! IO { io.print_raw("c") }
> ```
> ```json
> {"event":"effect","fn":"p.main",...,"effect":"IO.Print","op":"io.print_raw","args":{"msg":"c"}}
> {"event":"effect","fn":"p.main",...,"effect":"IO.Print","op":"io.print","args":{"msg":"c"}}
> ```
>
> sys's concern (it looks like a double write) gets a writer note: one event per dispatch.
>
> ## Q9a — hold Q9a-five
>
> The strongest point for Q9a-method: a state event has no span, so `"op":"sort"` points to the line.
> I grant it. But under Q9a-method the spec must still define "mutating method" (a method with
> `mut self`, called on a `let mut` root or a part of one) and say what a user method on a user type
> gives. "It is open in any case" is true only under Q9a-method: under five, a user `mut self` method
> gives `assign`, so the set stays closed. I hold because the schema table promises a sum of five,
> and Q9a-method makes that table false. If Q9a-method wins, the schema row must read "`assign`, or
> the name of the mutating method", with no list.
>
> ## Q10 — hold Q10-none
>
> sys's case is real: a change past the 200-char cut gives two events that look the same. But
> Q10-path adds a second grammar for places, and Map index writes later bring key escaping. The cheap
> fix lives elsewhere: an agent that hits the cut filters with `state:p` and reads `enter` args, or
> adds `trace.log`. I would take a static `.field` path before an index grammar. The panel did not want
> a field that comes and goes, so none.
>
> ## Q12 — move to Q12-run-error
>
> My reason for Q12-none was "one string, two meanings". That was a category error. The filter means
> the same in both paths. `blink run` adds a static check because it has the scope. The analogy is a
> query language: SQL rejects an unknown column name, but `WHERE x = 'nosuch'` returns an empty
> result. `fn:ad` is a reference to a declaration, not a value. An unbound reference is an error
> wherever the scope is known. A binary run by hand has no scope, so it cannot check, the same way a
> dynamic path cannot typecheck. The check must be exact to be sound:
> - it uses the V4 suffix rule on every frame name, synthetic names (`fn@5:29`, `handler@4:10.Log.emit`)
>   included;
> - a name declared in code that the build drops as dead code still counts (devops);
> - `effect:` checks against declared effects by the V6 segment rule; `state:` checks against every
>   `let mut` name and module `let mut` name;
> - a name that is declared and never runs gives an empty trace, no error.

**DevOps/Tooling**

> # Phase D — devops
>
> ## Q2b — stay on Q2b-pos-effect-op
>
> Sys and min say the `effect` event just before the body already names `Log`. That holds only when
> both lines survive the filter. With `--trace=fn:emit` or `module:obs`, the event at the perform
> site sits in a different fn or module and is filtered out. Then the handler's `enter`, `exit` and
> `state` lines are all the reader has. Sys's own concern, two handlers on one line told apart only by
> col, is the case the effect segment fixes. A few bytes per line is a fair price.
>
> ## Q7b — stay on Q7b-one, with a rule the writer must state
>
> Sys's point is fair: (2b) says "an op performed anywhere gives an event", so Q7b-one makes builtin
> wrapper bodies an exception. I accept that and want it written as one: a std op's default body is
> std code, std is not traced (2a), and so one call gives one event. Under Q7a-call (settled), Q7b-each
> would also need a spelling for the inner op that the user never wrote. Plt's "the trace and a
> handler disagree" is real, but only for a user handler of `print_no_nl` reached by `print_raw`. That
> handler body is a frame, so its `enter` still shows that the op ran. A rare, visible gap costs less
> than doubled events on every `print_raw`, which readers will take for a double write (sys's own
> concern).
>
> ## Q9a — stay on Q9a-method
>
> Plt's concern asks which methods count and how a user `mut self` method is named. The answer is one
> line: a call of a method that takes a mutable receiver gives one event, and `op` is the method name
> as written at the call, for std and user types alike. The closed five has no answer for a user type's
> `mut self` method at all, except `assign`, which points at an `=` that is not there. Plt says "a
> method name adds no information about the store". That is right about the store, but the reader's
> question is which line did it, and the name answers that. A consumer that switches on `op` needs a
> default arm. That is normal for any JSON stream that adds fields over time.
>
> ## Q10 — move to Q10-none
>
> Min and aiml convince me with the key-set argument. A field that is present or not by how the place
> was written breaks the "fixed keys per event type" property that makes `jq` scripts simple. A later
> Map index write would also bring key escaping in (sys's own concern). The cut-off case is real but
> rare, and it is a value-rendering problem, not a reason to add a second place grammar. The spec can
> note it as a known limit.
>
> ## Q12 — stay on Q12-run-error
>
> Plt: "one string would have two meanings". It does not. The filter means the same predicate in both
> paths. `blink run` adds a pre-flight check that it can do because it holds the build, as `blink
> check` rejects code that a C compiler would take. Min: "an empty trace is the true answer". It is
> true but useless for `fn:ad`. No fn by that name exists, so the empty trace is about the filter, not
> about the program. Saying so in one line before the run is the whole job of a tool.
>
> Web's concern is the real risk: the check must not drift from the runtime matcher. The fix is
> mechanical. The check runs the same V4 matcher over the list of frame names that the build emits,
> synthetic names included, so a valid filter cannot fail it. Min's "is it std" rule is a hint, not the
> check. If it costs too much, drop the hint and keep the error:
>
> ```
> $ blink run p.bl --trace=fn:ad
> error: --trace: `fn:ad` matches no fn in this program; did you mean `add`?
> $ echo $?
> 2
> ```
>
> A hand-run binary does not check, as today. That split is the same as `blink run` versus `./p` for
> every other build-time check.

**AI/ML**

> # Phase D d1 — aiml
>
> ## Q2b — hold Q2b-pos-effect-op
>
> To sys and min: the effect name is in the `effect` event before the body, but only in that event. The handler body's `exit` line, and every `state` and `effect` line inside it, carry only `fn`. An agent that reads one line, or that filters `--trace=fn:emit` and so drops the perform-site event, cannot tell a `Log` handler from a `Metrics` handler. The effect segment makes each line stand alone. That is worth the extra bytes. sys's concern (two handlers on one line, told apart only by col) also gets weaker: the effect segment separates them too.
>
> ## Q7b — I move to Q7b-each
>
> sys and plt are right on two counts. First, (2b), which all six agreed, says an op performed anywhere, a default body included, gives an event. Q7b-one makes builtin default bodies the one exception, and an agent that learned (2b) would not predict that exception. Second, my own test from Phase A was "a silent gap is worse than noise". Under Q7b-one, a handler for `print_no_nl` runs, and the trace shows no op that reached it: that is a silent gap. Under Q7b-each, the trace shows one extra event, and the spec can explain it in one sentence: the default body of `print_raw` performs `print_no_nl`. A reader can check an extra event against §4.4. A missing event gives the reader nothing to check.
>
> ```blink
> fn main() ! IO {
>     io.print_raw("c")
> }
> ```
> ```json
> {"event":"effect","fn":"main.main","depth":0,"effect":"IO.Print","op":"io.print_raw","args":{"s":"c"}}
> {"event":"effect","fn":"main.main","depth":0,"effect":"IO.Print","op":"io.print","args":{"msg":"c"}}
> ```
> Under Q7a-call the second `op` is `io.print`, the call spelling of `print_no_nl` in the §4.4 "Called by" column. The writer should state that pairing in the §8.15 example.
>
> ## Q9a — hold Q9a-method
>
> To plt and min: "a consumer can match all five" is not true now. User types have their own `mut self` methods (web), so with Q9a-five, every one of those maps to `assign`, and the label tells the reader nothing. "`value` carries the truth" holds only up to the 200-char cut. Past the cut, the method name is the only thing that says the event was a `sort` and not a `clear`. On plt's concern: the rule is one line, "a call of a method whose receiver is mutable gives the method's name". The writer states it once, and it needs no list of methods.
>
> ## Q10 — hold Q10-none
>
> sys's case is real, but the fix it brings is a grammar that only part writes use, and a `Map` index write would later bring key escaping (sys's own concern). A trace format gains users by being stable. A field that we add later, if users ask, breaks no consumer. A grammar we must widen later breaks parsers. So none now.
>
> ## Q12 — hold Q12-run-error
>
> To plt's "one string, two meanings": the predicate means the same thing on both paths. `blink run` adds a check before it starts the program, in the same way as `blink check` reports an unused name that `cc` would accept. The binary run by hand still computes the same empty result. So the string does not get a second meaning; the user gets an extra check.
>
> To sys: "an empty trace is a correct answer" holds only when the name exists. For `fn:ad` with no `ad` in the program, the empty trace answers a question the user did not mean to ask. The agent reads it as "add never ran", and that is false.
>
> To web's concern about synthetic names: the check needs only the declared names (fns, methods, modules, effects, `let mut` bindings) and the V4 suffix rule. A synthetic name has a declared prefix and a keyword segment that the compiler made, so the check can accept any value that has a declared prefix and a well-formed `fn@L:C`, `handler@L:C` or `test@L:C` segment. devops's dead-code concern: the check reads the typecheck table, which runs before code is dropped, so a dropped dependency fn is still declared.

**Minimalism**

> # Phase D — Min seat
>
> I move on Q2b and Q9a. I hold on Q7b, Q10 and Q12.
>
> ## Q2b — MOVE to Q2b-pos-effect-op
>
> devops showed that this form matches Q2c-plain, which won 6-0. The default body is `main.Log.emit`,
> and a handler body is `main.main.handler@4:10.Log.emit`. Then the one filter `fn:Log.emit` selects
> every body of that op under V4. With my form, `fn:emit` also selects the `emit` bodies of other
> effects. My "the effect field already says it" argument covers a reader, not a filter. The cost is
> some bytes per line, and that does not outweigh a filter that selects the right set.
>
> ## Q7b — hold Q7b-one
>
> To sys and plt ("2b says an op performed anywhere gives an event"): (2b) answers *who* performs the
> op (user code, std, a dep). Q7a-call, which won 5-1, sets the *unit* of an event: the call spelling,
> `io.print_raw`. The inner `print_no_nl` is not a call that anyone wrote. It is how the builtin's
> default body is built. Q7b-each gives an event with an `op` that no source line has, and two lines
> per call. That is the reader's "double write" that sys names as a concern.
>
> plt's concern (the trace and a handler disagree on the count) is real only for a user handler of
> `print_no_nl`. That handler's body is a frame (V1). Its `enter` line, `...handler@L:C.IO.Print.print_no_nl`,
> shows the dispatch. So nothing is hidden. The fact sits in the frame, not in a second effect line.
>
> ## Q9a — MOVE to Q9a-method
>
> sys's point wins on my own test (a rule, not a list). A user type with a `mut self` method needs a
> rule under either option. Q9a-five sends `p.bump()` to `assign`, which is a fourth special case
> beside push/pop/insert/remove. Q9a-method says one thing: "`=` and compound assignment give `assign`;
> a call of a method with a `mut` receiver gives the method's name". That rule needs no table, and a
> new std method changes nothing in the spec. My "closed enum" argument guarded a list that the spec
> would then have to keep up with each new method. The open rule is the smaller surface.
>
> ```blink
> fn main() {
>     let mut xs = [3, 1]
>     xs.sort()
> }
> ```
> `{"event":"state","var":"xs","op":"sort","value":"[1, 3]",...}`
>
> To plt's concern ("which methods count as mutating"): a method whose receiver is `mut self`, called
> on a `let mut` binding. That is the same test the typecheck already makes.
>
> ## Q10 — hold Q10-none
>
> To sys ("two identical events past the cut"): that is a truncation fault, and `path` patches one
> case of it. A change past the cut in a `push` onto a long list, or an `assign` to a big Map, gives
> the same two identical events, and `path` does nothing there. If the cut hides changes, change the
> cut rule for all events. Do not add a field for part writes only. devops's own fallback was "drop
> `path`". A `.field`/`[Int]` grammar stays closed only until a Map index write comes, as sys says.
>
> ## Q12 — hold Q12-none
>
> To devops and aiml ("an empty trace reads as add never ran"): the check needs a copy, in the CLI, of
> the V4 suffix match, the synthetic names (`fn@5:29`, `handler@4:10.Log.emit`, `test@12:1`), the
> "is it std" table and the dead-code rule that devops names. That is four rule sets that must agree
> with the runtime matcher, or it rejects a valid filter (web's concern). Then the same `BLINK_TRACE`
> string is valid by hand and an error under `blink run` (plt). A filter is a predicate, and an empty
> result is its answer. A typo is the user's to find, as with any `grep` that matches nothing.
>
> If the panel wants the help, the cheaper way is the doc: one spec sentence that an empty trace means
> the filter matched nothing, and that std fns are never frames. That needs no lookup.

#### Phase D, re-vote — Ballot on the five points

Each seat voted alone again.

**Systems**

> # Phase D ballot — sys seat
>
> ## Q2b
> **Vote:** Q2b-pos-effect-op
> **Reasoning:** With the effect in the name, `fn:Log.emit` selects every handler body and the default
> body (`main.Log.emit`) of that op with one filter. Each line names its frame without the perform-site
> line, which `event:enter` or `fn:emit` filters drop. The name is a static string, so the extra bytes
> cost nothing at run time.
> **Concern:** long names on every enter/exit line of a busy handler make the trace larger.
>
> ## Q7b
> **Vote:** Q7b-each
> **Reasoning:** The agreed (2b) counts ops performed, a default body included. Q7b-one needs an
> exception for builtin default bodies, and nothing in the program marks those bodies as different
> from a std helper that calls `fs.write`. Under Q7b-one, a user handler for `print_no_nl` gives an
> `enter` with no effect line that caused it. aiml's move to each makes the same point.
> **Concern:** a reader can take the two lines for a double write, so the writer must say "one event
> per dispatch" and show the `print_raw` pair in the example.
>
> ## Q9a
> **Vote:** Q9a-method
> **Reasoning:** One rule with no table: `=` and compound assignment give `assign`, and a call of a
> `mut self` method on a `let mut` binding (or a part of one) gives the method's name, for std and user
> methods alike. The op is a static string. Above the 200-char cut, `op` is the only hint left.
> **Concern:** the schema row must read "`assign` or the method name", not a list, and consumers need a
> default arm.
>
> ## Q10
> **Vote:** Q10-none
> **Reasoning:** I move, as I said in round 1 I would. The case past the cut is real but rare, and min
> is right that it is a fault of truncation in general. `path` fixes only one case of it. A field added
> later breaks no consumer; a grammar widened later does.
> **Concern:** a field write past the 200-char cut on a large struct gives an event whose `value` looks
> the same as the one before.
>
> ## Q12
> **Vote:** Q12-run-error
> **Reasoning:** I move. My objection was a second matcher in the CLI that drifts from the runtime.
> devops's fix answers it: run the same V4 matcher over the list of frame, module, effect and
> `let mut` names that the build already emits as static strings (synthetic names included, before
> dead code is dropped). Then a valid filter cannot fail the check. plt's point also holds: `fn:ad` is a
> reference to a declaration, and an unbound reference is an error where the scope is known. Cost:
> one pass over a name table, once, before the program starts.
> **Concern:** if the check uses its own name rules and not the runtime matcher over the emitted table,
> it rejects valid filters. The writer must tie the check to that one matcher and that one table.

**Web/Scripting**

> # Phase D re-vote — Web seat
>
> ## Q2b
>
> **Vote:** Q2b-pos-effect-op
>
> **Reasoning:** Each line must make sense alone: `exit` and `state` lines in a handler body carry only
> `fn`, and a `fn:` or `event:` filter can drop the perform-site line. With the effect in the name,
> `fn:Log.emit` selects every body of that op, the default body (Q2c-plain) included.
>
> **Concern:** the names are long, so a busy handler costs some extra bytes on each line.
>
> ## Q7b
>
> **Vote:** Q7b-each
>
> **Reasoning:** I move. Agreed (2b) says that an effect op inside std gives an event, and a builtin
> default body is std code, so Q7b-one is an exception that the user must learn. aiml's point decides it
> for me: under Q7b-one, a user handler for `print_no_nl` runs, and no line in the trace shows what
> reached it. An extra line that the reader can check against §4.4 costs less than a missing one that
> they cannot find.
>
> **Concern:** a JS dev sees `io.print_raw` and then `io.print` for one source line and suspects a
> double write. The §8.15 example must show this pair, with one sentence that explains it.
>
> ## Q9a
>
> **Vote:** Q9a-method
>
> **Reasoning:** The rule is one sentence: "a call of a method with a `mut self` receiver gives the
> method's name; `=` and compound assignment give `assign`". It needs no table and covers user types.
> `"op":"sort"` sends the reader to the right line. `"op":"assign"` sends them to look for an `=` that is
> not there.
>
> **Concern:** a jq script that switches on `op` and has no default branch misses names it does not
> know. The schema row must say "the method name", not a list.
>
> ## Q10
>
> **Vote:** Q10-none
>
> **Reasoning:** The case is rare (a change past the 200-character cut). A `path` grammar would later
> need escape rules for Map keys. A field added later breaks no consumer, and a field removed later
> would.
>
> **Concern:** a write to a field past the cut of a large struct gives an event that does not show what
> changed.
>
> ## Q12
>
> **Vote:** Q12-run-error
>
> **Reasoning:** The predicate means the same on both paths, and `blink run` only adds a check before
> the run because it has the names. For `fn:ad`, the empty trace is the true answer to a question that
> the user did not mean to ask, and they then debug "add never ran". devops's form stops the check from
> drifting away from the runtime: it runs the same V4 matcher over the list of frame names that the
> build emits, synthetic names included. Then a valid filter cannot fail.
>
> **Concern:** if the check has its own copy of the match rules and does not reuse the runtime
> matcher, it can drift and reject a valid filter. That is worse than an empty trace.

**PLT**

> # Phase D re-vote — PLT seat
>
> ## Q2b
>
> **Vote:** Q2b-pos-effect-op
>
> **Reasoning:** A frame's `fn` must identify the frame on every line, including when a filter drops
> the line where the op was performed. With the effect in the name, one `fn:Log.emit` filter selects
> the default body (Q2c-plain) and every handler body of that op, by the V4 rule. All six seats now
> agree on this form.
>
> **Concern:** The names get long. The writer must give the whole synthetic-name grammar in one place.
>
> ## Q7b
>
> **Vote:** Q7b-each
>
> **Reasoning:** The agreed rule 2b counts ops performed, and names no exceptions. Q7b-one needs an
> exception for "builtin default bodies", and that exception would be a list. Under Q7b-one, a user
> handler for `print_no_nl` gives an `enter` line with no effect line that caused it. That is a frame
> with no cause, a gap that a reader cannot check. Under Q7b-each, the two `op` strings differ, so no
> reader takes them for one op written twice.
>
> **Concern:** Under Q7a-call the second event spells `io.print`, a call the user did not write. The
> spec example must show the pairing with the §4.4 "Called by" column.
>
> ## Q9a
>
> **Vote:** Q9a-method (I move)
>
> **Reasoning:** Q9a-five matches `push`/`pop`/`insert`/`remove` by method name. So a user type's
> `mut self` method named `push`, which may do anything, gets `"op":"push"`, and every other user
> method gets `assign`. That rule is not semantic; it only looks at the name, and only for four names.
> Q9a-method states the same thing for all methods: the event gives the name of the method that ran.
> That is honest, needs no table, and keeps the one hint left past the 200-char cut. The schema row
> must change from a sum of five values to the rule.
>
> **Concern:** If the spec defines "mutating method" in a loose way (for example, by its name and not
> by a `mut self` receiver on a `let mut` root or a part of one), the event set will drift from what
> the typechecker knows.
>
> ## Q10
>
> **Vote:** Q10-none
>
> **Reasoning:** The full binding is in `value`. A path grammar would cover only part writes, and Map
> key writes later would bring escaping. A field added later breaks no consumer; a grammar that must
> grow later does. Five seats now agree.
>
> **Concern:** A change to a field past the 200-char cut gives two events that look the same, and only
> a value diff below the cut, or a `trace.log`, shows it.
>
> ## Q12
>
> **Vote:** Q12-run-error
>
> **Reasoning:** `fn:ad` refers to a declaration. Where the scope is known, a reference that names no
> declaration is an error. A well-formed reference to a declared fn that never runs stays a correct
> empty result. The predicate means the same in both paths. `blink run` only adds a check, since it
> has the names; a binary run by hand does not. sys's risk of two matchers is real. So the check must
> use the same V4 matcher code over the declared names after typecheck (synthetic names and code
> dropped as dead included), not a second copy of the rules.
>
> **Concern:** If the CLI check and the runtime matcher drift apart, a valid filter gets an error and
> the user cannot trace at all, which is worse than an empty trace.

**DevOps/Tooling**

> # Phase D re-vote — devops
>
> ## Q2b
> **Vote:** Q2b-pos-effect-op
> Reasoning: the effect segment lets a line make sense alone. That matters under `event:enter` or
> `fn:emit`, which drop the effect line at the perform site. With Q2c-plain, `fn:Log.emit` then selects
> every body of that op, and no other effect's `emit`.
> Concern: the grammar for these names (keyword@L:C, effect path, op) must be written once, in full,
> or tools will parse it in different ways.
>
> ## Q7b
> **Vote:** Q7b-each (I move)
> Reasoning: plt's point decides it for me. Under (2b), a std helper that calls `fs.write` already
> gives an `fs.write` event that no user line spells. So "an op spelling the user never wrote" is
> normal under (2b), and Q7b-one would need an exception that nothing in the code marks. My own test
> also applies (aiml): a handler frame with no effect line that reached it is a silent gap. An extra
> line that §4.4 explains is not.
> Concern: readers will take the pair for a double write. The §8.15 example must show the
> `print_raw` → `print` pair and say "one event per dispatch".
>
> ## Q9a
> **Vote:** Q9a-method
> Reasoning: one sentence with no table. A call of a method with a `mut` receiver gives its own name,
> and `=` / compound assignment gives `assign`. That covers user types, and a new std method needs no
> spec text. The name greps straight to the line, even past the 200-char cut.
> Concern: the schema row must read "`assign` or the mutating method's name". A leftover five-value
> list in any doc would mislead consumers.
>
> ## Q10
> **Vote:** Q10-none
> Reasoning: min is right that the cut is a fault of truncation, and `path` patches only one case of
> it. A fixed key set per event type keeps consumers simple. Adding a field later breaks no one, but a
> place grammar that must widen later breaks parsers.
> Concern: a field write past the cut on a large struct gives two events that look the same, and the
> spec should say so as a known limit.
>
> ## Q12
> **Vote:** Q12-run-error
> Reasoning: `fn:ad` refers to a declaration, and plt's SQL analogy fits: an unknown column is an
> error, an empty match is not. `blink run` has the typecheck table, so it can reject a reference that
> binds nothing before the program starts, and no non-JSON line enters the stream. As aiml says, the
> check needs only the declared names, the V4 rule and the well-formed synthetic segments. It does not
> need a second runtime matcher.
> Concern: if the check and the runtime ever disagree on a synthetic name, `blink run` rejects a valid
> filter. The check must have a test for each name form (fn, method, closure, handler, default body,
> test, dep fn dropped as dead code).

**AI/ML**

> # Phase D re-vote — aiml
>
> ## Q2b
> **Vote:** Q2b-pos-effect-op
> Reasoning: each line names its own body, so a line still makes sense when the filter drops the effect event at the call site. One filter, `fn:Log.emit`, then selects every body of that op, the handler bodies and the default body (Q2c-plain), and selects no `emit` of another effect. The extra bytes are a static string.
> Concern: the names are long, and the writer must give the full grammar of a synthetic name in one place, or agents will guess a wrong form.
>
> ## Q7b
> **Vote:** Q7b-each
> Reasoning: the agreed (2b) counts ops performed, not calls. Under Q7b-one, a user handler for `print_no_nl` gets an `enter` line with no effect line before it, which is a frame with no cause in the trace. plt's point is the one that decides it for me: under Q7b-one, the trace would change when std moves code between a default body and a helper. A trace that follows a stable rule (one event per dispatch) is easier to predict than one that depends on where std put the code.
> Concern: an agent that sees two events for one `io.print_raw` line reads them as a double write. The spec example must show the pair and say why.
>
> ## Q9a
> **Vote:** Q9a-method
> Reasoning: one sentence, "a call of a method with a `mut` receiver gives the method's name", covers std and user methods with no table. `"op":"sort"` points to the line, and an `assign` points the reader at an `=` that is not there. Past the 200-char cut, the name is the only clue that is left.
> Concern: the schema row must change from a list of five values to that rule. If an old list stays anywhere, agents will treat the set as closed.
>
> ## Q10
> **Vote:** Q10-none
> Reasoning: the key set per event type stays fixed. A grammar for places, with key escaping added later for Map index writes, would cost more than the rare case it covers. A field added later breaks no consumer.
> Concern: a field write past the 200-char cut on a big struct gives two events that look the same, and the spec should note it as a known limit.
>
> ## Q12
> **Vote:** Q12-run-error
> Reasoning: plt's move states it: `fn:ad` refers to a declaration, and where the scope is known, a reference to nothing is an error. A declared name that does not run still gives an empty trace. Without the check, the most common typo reads to an agent as "add never ran", which is false. The check must run the same V4 matcher over the frame names that the build emits, synthetic names and dead code included, so a valid filter cannot fail.
> Concern: if the CLI check and the runtime matcher drift apart, `blink run` rejects a valid filter, and then the user cannot trace at all.

**Minimalism**

> # Phase D re-vote — Min seat
>
> ## Q2b
> **Vote:** Q2b-pos-effect-op
> **Reasoning:** One filter, `fn:Log.emit`, selects every body of that op, the handler bodies and the
> Q2c-plain default body together. web, devops and sys also showed that `event:enter` or `fn:emit` cuts
> out the perform-site line, so each name must stand alone. The extra bytes are static and small.
> **Concern:** The names get long, and the writer must give the full name grammar in one place, or
> readers will guess it.
>
> ## Q7b
> **Vote:** Q7b-each (I move)
> **Reasoning:** plt's point decides it on my own test (fewer rules). Nothing marks a builtin default
> body as different from a std helper that calls `fs.write`, which agreed rule (2b) traces. So
> Q7b-one needs an exception clause and a list of which bodies are "builtin". Q7b-each is (2b) with no
> exception: one event per dispatch. It also removes the handler frame that runs with no cause, which
> all four Q7b-one seats named as their concern.
> **Concern:** Readers will take the two lines for one `io.print_raw` call as a double write, unless
> the §8.15 example shows the pair and says "one event per dispatch".
>
> ## Q9a
> **Vote:** Q9a-method
> **Reasoning:** One sentence and no table: `=` and compound assignment give `assign`, and a call of a
> `mut self` method on a `let mut` binding (or a part of one) gives the method's name. The same rule
> covers user methods, and a new std method needs no ruling. Past the 200-char cut, `op` is the only
> hint left, and `assign` would throw it away.
> **Concern:** A consumer that switches on `op` with no default arm breaks the first time it meets a
> user method name.
>
> ## Q10
> **Vote:** Q10-none
> **Reasoning:** A `path` field brings a place grammar that only part writes use, and Map index writes
> would later bring key escaping. A change hidden past the cut is a truncation fault for every event,
> not a part-write fault. If users ask for `path`, we can add it later without breaking any consumer.
> **Concern:** On a large struct, a `p.field = v` past the cut gives two events that look the same.
>
> ## Q12
> **Vote:** Q12-none
> **Reasoning:** The check is a second copy of the matcher, in the CLI, that must agree with the
> runtime on the V4 suffix rule, every synthetic name, dep modules and dead code. If one rule drifts,
> `blink run` rejects a valid filter, and that is worse than an empty trace, because the user then
> cannot trace at all. The spec can say in one sentence that an empty trace means the filter matched
> nothing.
> **Concern:** A one-character typo in `fn:` gives an empty trace, and an agent reads it as "never
> called".
