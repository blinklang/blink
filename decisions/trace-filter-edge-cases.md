[< All Decisions](../DECISIONS.md)

# Runtime Trace Filter, the Edge Cases — Design Rationale

**Question.** The runtime trace filter ([runtime-trace-open-points.md](runtime-trace-open-points.md), §8.15.5, §8.15.12, §8.15.13) left four points open. What does `all` mean beside another item? Does `depth:` take a sign? What does a list with no items select, for `--trace=` and for `BLINK_TRACE`? Does `blink run` build a traced program when the shell has `BLINK_TRACE` set and the command has no `--trace`? Two follow-up points came from the discussion: does `blink run` print a note in that last case, and does the error of a bad filter name the source of the value?

**Answer.** (1) `all` beside an item that is not `all` is a bad filter (usage error, exit code 2, no build). A lone `all`, `all,` and `all,all` trace everything. (2) A `depth:` value is ASCII digits only and the number fits in `Int`; `depth:-1`, `depth:+3` and a 20-digit number are bad filters. (3) A list with no items after the item rule (`""`, `" "`, `","`, `" , "`) has zero filters and selects every event, the same as unset, for `--trace=` and for `BLINK_TRACE`; a traced binary reads `BLINK_TRACE=` as trace all. `fn:` stays a bad filter. (4) Only `--trace` makes `blink run` build a traced program; `blink run` does not read `BLINK_TRACE` to decide. (5) When the command has no `--trace` and `BLINK_TRACE` is not empty after the item rule, `blink run` prints one note line on stderr before it builds; the exit code does not change. (6) The error of a bad filter names the source of the value: `--trace` or `BLINK_TRACE`. The words are free.

**Release note.** Four changes are visible to users. `--trace=fn:add,all`, `--trace=all,fn:add`, `--trace=depth:-1` and `--trace=depth:+3` now stop with exit code 2 before the program starts (before, the filter dropped the rest of the list or gave an empty trace). A traced binary with `BLINK_TRACE=` traces every event. `BLINK_TRACE=fn:add blink run p.bl` no longer builds a traced program: it prints `3` and writes no trace event, and `blink run` prints a note. The error of a bad filter says if the value came from `--trace` or from `BLINK_TRACE`.

**Spec.** §8.15.5, §8.15.7 (one sentence), §8.15.12 and §8.15.13 in `sections/06_tooling.md`. No new error code: a usage error of the trace has no code, as a usage error of `blink test` has none (§8.10.7), and [runtime-trace-open-points.md](runtime-trace-open-points.md) set that rule for the trace.

### Decision

| Q | Result | Tally | Dissent |
|---|---|---|---|
| Q1 | `all` beside any item that is not `all` is a bad filter (usage error, exit code 2, no build). A lone `all`, `all,` and `all,all` trace everything. `all,fn:add,all` is a bad filter. | 6-0 (Phase C 4-2) | none |
| Q2 | `depth:` takes ASCII digits only, and the number fits in `Int`. `depth:-1`, `depth:+3` and a 20-digit number are bad filters with one error shape. | 6-0 | none |
| Q3 | No item left after the item rule (`""`, `" "`, `","`, `" , "`) is zero filters and selects every event, the same as unset, for `--trace=` and for `BLINK_TRACE`. A traced binary reads `BLINK_TRACE=` as trace all. `fn:` stays a bad filter. | 6-0 | none |
| Q4 | Only `--trace` makes `blink run` build traced; `blink run` does not read `BLINK_TRACE` to decide. `BLINK_TRACE=fn:add blink run p.bl` prints `3` and writes no trace event. | 6-0 | none |
| Q5 | `blink run` (not the program) prints one note line on stderr, before the build, when `BLINK_TRACE` is not empty after the item rule and `--trace` is absent. The exit code does not change. | 4-2 (Phase C 2-4) | Systems, Minimalism: no note |
| Q6 | The error of a bad filter names the source of the value, `--trace` or `BLINK_TRACE`. The words are free. `blink run` does not relabel a `--trace` value as `BLINK_TRACE`. | 5-1 | Minimalism: not a rule |

**Agreed by all six, not voted.** Any item with no `:` that is not `all` is a bad filter, exit code 2 (before, the parser stopped at the first item with no `:` and dropped the rest with no message). `depth:03` is `depth:3` (leading zeros are digits). `fn:all` is the filter `fn` with the value `all`, not the word `all`. A value with an empty value after the `:` (`fn:`) is a bad filter; the "empty value" of §8.15.12 is that case, not an empty list.

**The writer's conditions.** Devops/Tooling and the others asked for the table rows `all,all` (every event) and `all,fn:add,all` (exit code 2), so that no implementation removes repeats before it checks the list. Both rows are in §8.15.5. Systems and Programming Language Theory asked for the note to have an exact trigger; §8.15.13 states it.

**Dissent on Q5.** Systems and Minimalism voted for no note. Two points carry the dissent. (a) A user who exports `BLINK_TRACE` on purpose for a traced binary that they start by hand gets the note, though they did nothing wrong. (b) Systems probed that a plain `blink run` writes nothing else to stderr today, so the note would be the only line that `blink run` adds. Their reasons, verbatim from the re-vote (Q1 and Q5 were on the ballot):

**Systems (D2)**

> Q1: Q1-A
> Reasoning: The error is there to refuse an item that has two opposite readings in the AND list and the OR list. `all,all` has one reading under both, so an error there saves no user and stops a script that joins two default lists. The check is one test, "is any item not `all`?", and it is not longer than Q1-B's test.
> Concern: an implementation that removes duplicates before the check accepts `all,fn:add,all`, so the spec table must have that row as exit 2.
>
> Q5: Q5-B
> Reasoning: Fact from a probe (gen1, MVCE, [probe path omitted]): a plain `blink run p.bl` writes nothing to stderr, on the first run and on a cached run. So web's "blink run already writes its own build lines to stderr" is not true for a normal run, and the note would be the only line that `blink run` adds to the program's stderr, on every run in a shell that exports the variable. Under Q4-A, an exported `BLINK_TRACE` is also a valid setup for traced binaries that you start by hand, so the note fires for users who made no mistake. Its trigger (set, not empty after the item rule, no flag) is one more rule to spec and test.
> Concern: the first-time user who sets `BLINK_TRACE` and runs `blink run` gets no clue on screen, so §8.15.13 and `blink run --help` must say that only `--trace` builds traced.

**Minimalism (D2)**

> Q1: Q1-A
> Reasoning: The error exists only to refuse a value with two lawful readings (AND identity vs OR absorb). `all,all` has one reading under both, so an error there is a diagnostic that saves no one, and dropping it is the subtraction. The two rules are the same length ("every item is `all`" vs "`all` is the sole item").
> Concern: An implementation that dedupes before the check accepts `all,fn:add,all`; the spec table must carry that row as exit 2.
>
> Q5: Q5-B
> Reasoning: Sys's point decides it for me: under Q4-A an exported `BLINK_TRACE` is a valid setup (it filters traced binaries started by hand, e.g. from `blink build --trace`), so the note fires on every `blink run` for a user who did nothing wrong. It also puts an env-dependent line ahead of the program's own stderr, and its trigger is one more rule to spec, test and keep. A sentence in §8.15.13 and `blink run --help` covers the confused first-time user at no runtime cost.
> Concern: The first-time user who sets only the var under `blink run` sees nothing on screen and must find the doc sentence.

**Dissent on Q6.** Minimalism voted for Q6-B: the source is a thing for the example text, not a rule. Its ballot, verbatim:

> Q6: Q6-B
> Reasoning: §8.15.12 already says the words are an example; a MUST on error text is surface we then have to keep. The writer can show the source in the example line.
> Concern: An implementation that drops the source leaves a user with a leaked export no clue where the bad value came from.

**Dissent on Q1 (first vote only).** Web/Scripting and Minimalism voted Q1-B (`all,all` is also a bad filter) in Phase C. Both moved to Q1-A in Phase D. See Phase C and Phase D below.

**Where the question comes from.** The panel brief asked: `--trace=all,fn:add` and `--trace=fn:add,all` (an `all` item, a bad filter, or a word only as the whole value); `depth:-1` and `depth:+3` (is a sign part of "a number"); `BLINK_TRACE=""` and `BLINK_TRACE=" , "` (every item is skipped by the item rule); and `blink run p.bl` with `BLINK_TRACE=fn:add` in the shell and no `--trace` (does `blink run` build traced). It ruled out the decisions of [runtime-trace-open-points.md](runtime-trace-open-points.md): the filter keys, AND across `,`, OR across `+`, the item rule, a bad filter as a usage error, and that a traced binary reads only `BLINK_TRACE`.

---

## Phase A: the proposals

Each seat worked alone. Excerpts, verbatim.

### Systems

**Q1, why not make `all` an item**

> Why not make `all` an item: the two lists use different logic. `BLINK_TRACE_CHANNELS` is a
> union, so `mono,all` turns on every channel (§8.15.7). `BLINK_TRACE` is an AND, so `all` as an
> item can only be the identity: `fn:add,all` would mean `fn:add`. The same text would then select
> everything in one variable and a subset in the other. A user who copies the channel rule
> expects all events and gets two. A user who expects the AND reading gets it from the plain
> `fn:add` anyway. Neither reading is worth a silent mismatch. An error costs nothing and shows
> the mistake at once. Today's behavior (stop at the first item with no `:` and drop the rest
> with no message) is the worst case, and the rule must remove it.

**Q3, why an error (changed in Phase B)**

> Why: the common source of an empty value is a script with `--trace=$FILTER` where `FILTER` is
> unset. The person wanted a small trace. "Empty means all" gives the most costly trace with no
> message. "Empty means none" leaves the person with an instrumented binary that writes nothing,
> and a reader again sees "never ran". An error is the only result that does not guess. Also,
> `""`, `" "` and `","` are one case under the item rule, so one rule covers all three, and the
> binary and `blink run` agree. Today they do not: the binary reads `BLINK_TRACE=` as no trace but
> `" "` as all.

**Q4, why the flag selects the build**

> Why: tracing changes what the compiler emits. Each traced fn gets enter/exit code, each `let mut`
> write gets a state hook, each effect call gets an event. That is a different binary, with
> different speed and a different cache key. An ambient variable must not change the codegen. One
> `export` left over from a debug session would make every later `blink run` slow and noisy, and
> the command line would not show why. "The flag selects the build, the variable filters a traced
> binary" is a rule with one source for each decision. It also keeps the §8.15.12 name check
> simple: `blink run` checks the flag value only, never a shell value it did not get on its
> command line.

**Summary**

> | Point | Behavior |
> |-------|----------|
> | (1) `all,fn:add`, `fn:add,all` | bad filter, exit 2; `all` only as the only item |
> | (2) `depth:-1`, `depth:+3` | bad filter, exit 2; digits only, fits in `Int` |
> | (3) `""`, `" "`, `","` | bad filter, exit 2, for `--trace=` and `BLINK_TRACE` |
> | (4) shell `BLINK_TRACE`, no flag | `blink run` builds untraced; no message |

### Web/Scripting

**Q1, why an error and not an item**

> Why an error and not "`all` is an item":
> - `BLINK_TRACE_CHANNELS` (§8.15.7) already says `mono,all` = every channel, because that list is
>   an OR. The trace list is an AND, so `all` as an item would be the AND identity:
>   `fn:add,all` = `fn:add`. Same spelling, opposite result in two env vars that sit next to each
>   other in the same section. A user who learned one will guess wrong on the other. That is the
>   SO question ("why does `fn:add,all` not trace all?"). An error with the fix in the text ends it.
> - No one writes `all,fn:add` on purpose. It comes from a script that joins a default with an
>   extra filter. An error tells them at once; either silent reading hides the bug.
> - It costs nothing to relax later (error → meaning is not a break). The reverse is a break.

**Q4, why the variable alone turns tracing on (changed in Phase B)**

> Why:
> - §8.15.5 says "`BLINK_TRACE` accepts the same filter syntax". A user who reads that WILL try
>   `BLINK_TRACE=fn:add blink run p.bl`. If it prints nothing, it looks broken, and nothing on
>   screen says why. That is the top SO question of this whole ticket.
> - The opposite failure, a stale `export` that traces every run, is loud: the NDJSON on stderr
>   names itself, and `BLINK_TRACE=` clears it for one run. Loud and fixable beats silent.
> - RUST_LOG, DEBUG, PYTHONVERBOSE, NODE_DEBUG: in each, the env var alone turns the output on.
>   That is the model people bring.
> - CI: set `BLINK_TRACE` once in the job env, and every `blink run` step traces. No flag edits.

**Summary**

> | Point | Pick |
> |-------|------|
> | 1 | `all` only as the sole item; with any other item, exit 2 with a fix hint |
> | 2 | `depth:` = ASCII digits only; `-1`, `+3` exit 2 |
> | 3 | No items left = zero filters = every event; empty env = unset; `--trace=` = `--trace` |
> | 4 | Non-empty `BLINK_TRACE` alone makes `blink run` build traced, with the same checks; empty = unset |

### Programming Language Theory

**The model**

> A filter value has a meaning: a predicate on events. The `,` list is a conjunction of its items,
> and an item `k:v1+v2` is a disjunction. So
>
>     [[i1, ..., in]] = [[i1]] AND ... AND [[in]]        [[]] = TRUE (every event)
>
> The item rule (trim, skip empty) already commits us to this: `fn:a,,` means `fn:a` only if an
> empty item adds no conjunct. If dropping an empty item never changes the meaning, then a list
> with only empty items must mean the empty conjunction, TRUE. I take the four points from that
> one equation, so that each point is a consequence and not a new special case.

**Summary**

> | Input | Behavior |
> |---|---|
> | `--trace=all,fn:add`, `fn:add,all` | exit 2, usage error |
> | `--trace=all,all`, `all, ` | every event |
> | `depth:-1`, `depth:+3` | exit 2, not a number |
> | `""`, `" "`, `","`, `" , "` (flag or binary) | every event |
> | `BLINK_TRACE=x blink run p.bl` | untraced build, no events |

### DevOps/Tooling

**Q1, why not make `all` an item**

> Why not "`all` is an item": under AND, an item that selects everything is the identity, so
> `fn:add,all` is `fn:add`. But §8.15.7 says that in `BLINK_TRACE_CHANNELS` the item `all`, in any
> place, turns on EVERY channel. The two vars sit in one section and read the same item rule. A
> user who learned `mono,all` will type `fn:add,all` and expect everything; the identity reading
> gives them only `add`, with no message. One rule says "all wins", the other would say "all does
> nothing". An error is the only answer that cannot mislead in either direction, and it keeps the
> door open if a later panel wants to give `all` a meaning in a list. Today's behavior (silent drop
> of `fn:add` after `all`) is the worst of the three choices.

**Q4, why the build switch is on the command line**

> Why: an `export BLINK_TRACE=...` from an old debug session must not turn every later `blink run`
> in that shell into a different build (slower binary, a cache miss, stderr full of events, and,
> as the probe shows, no name check). The flag also gives `blink run` one place to run the
> §8.15.12 checks, and they always run when the build is traced. `BLINK_TRACE= blink run p.bl` then
> needs no rule: no flag, untraced build. RUST_LOG is a poor model here: Rust logging is always
> compiled in, and the var only filters. Tracing in Blink is a build mode, so the build switch
> belongs on the command line, as `-race` does in `go run -race`, not `GORACE`.

**Summary**

> | Input | Proposal |
> |-------|----------|
> | `--trace=all,fn:add`, `fn:add,all` | usage error, exit 2 |
> | `depth:-1`, `depth:+3` | usage error, exit 2 (digits only, fits in Int) |
> | `""`, `" "`, `","`, `--trace=` | zero filters: every event |
> | `BLINK_TRACE=fn:add blink run p.bl` | untraced build, plus a stderr note |

### AI/ML

**P1, `all` as an item (changed in Phase B)**

> Tradeoffs. (a) The `,` list is an AND, and "every event" is the unit of AND, so the
> result follows from one rule with no special case: an AI that knows AND gets it right.
> (b) It is the same rule as `BLINK_TRACE_CHANNELS`, where §8.15.7 says `all` in any place
> works and that a runtime that reads `all` only as the whole value does not conform. Two
> neighbor variables with opposite rules for the same word is a trap an LLM will fall into.
> (c) Both readings of the user's intent ("all events, and fn:add" or "only fn:add") give
> the same output, so a no-op cannot surprise anyone. An error (exit 2) is the next-best
> pick; the current silent drop is the worst.

**P4, no warning line**

> Tradeoffs. (a) The command line alone says what `blink run` does. An agent's shell
> holds state the agent cannot see (an earlier `export`, a CI env, a parent process). Today
> a leaked `BLINK_TRACE` floods stderr with NDJSON on every run and breaks any check of
> stderr; the agent has no clue in the command why. (b) A real chain: a traced program
> that spawns `blink run other.bl` passes its `BLINK_TRACE` down (blink run set it), so the
> inner program also builds traced. Flag-only cuts that chain. (c) It removes a decision
> point: "trace under blink run = pass `--trace`". The spec text already reads this way
> (§8.15.13 speaks of what the binary reads, and of the flag). (d) Cost: a user of
> `RUST_LOG=... cargo run` habits may expect the env var to work. That habit comes from
> always-compiled logging; Blink tracing needs an instrumented build, so the analogy fails.
> I do not want a warning line: it adds noise to stderr, which is the thing (a) protects.

**Summary**

> | Point | Pick |
> |---|---|
> | 1 | `all` = item, unit of AND, works in any place; other bare word = exit 2 |
> | 2 | digits only; sign or overflow = exit 2 |
> | 3 | empty list ≡ unset ≡ all, for flag and env; empty value after `:` stays exit 2 |
> | 4 | only `--trace` makes `blink run` build traced |

### Minimalism

**P1, `all` only as the whole value**

> Tradeoffs. The other two options each cost more:
> - `all` as an item that selects every event. Under AND it is a no-op: `all,fn:add` = `fn:add`.
>   It is free in the algebra, but it is a trap next to `BLINK_TRACE_CHANNELS`, where `mono,all`
>   is every channel (an OR list). The same word, in the same place, gives the opposite result in
>   the two vars. A person or an agent who copies the habit from one var to the other gets a
>   narrow trace and no message. I will not buy a silent mismatch to save one error case.
> - `all` as an item that means "everything, ignore the rest". That is a second meaning of `,`
>   (AND, except when `all` is there). That is an added rule, with no use case: nobody needs to
>   write a filter and then cancel it.
>
> The error costs nothing new: it is the existing "unknown key" case. Today's silent drop of
> `fn:add` must go in any answer.

**P4, a cut**

> Tradeoffs.
> - This is a cut. §8.15.13 says the traced binary reads `BLINK_TRACE`. Today `blink run` is a
>   second reader of the same var with a second job (pick the build). One var, two readers, two
>   jobs: that is the kind of coupling I count as cost. The flag is the one switch for the build;
>   the var is the one input to the binary.
> - A stale `export BLINK_TRACE=...` in a shell would, today, make every later `blink run` slower
>   and fill stderr with NDJSON, which breaks any script that reads stderr. With the cut, a stale
>   export does nothing until the user asks for a trace.
> - It makes P3 and P4 agree with no special case: `BLINK_TRACE= blink run p.bl` is untraced because
>   there is no flag, not because "empty is unset" in one reader and "empty is all" in the other.
> - Cost: a user who wants the shell value under `blink run` writes `--trace="$BLINK_TRACE"`. That
>   is one flag, and it states the intent.

**Summary**

> | Point | Pick | New rule? |
> |-------|------|-----------|
> | P1 | `all` only as the whole value; in a list, exit 2 (existing unknown-key error) | no |
> | P2 | digits only; `-1`, `+3`, and a too-large value exit 2 | one clause ("digits") |
> | P3 | empty / all-empty items = zero filters = every event; binary fix for `BLINK_TRACE=` | no |
> | P4 | `blink run` builds traced only with `--trace`; drop its read of `BLINK_TRACE` | a cut |


---

## Phase B: what moved

Each seat read the six proposals. Four seats changed a position. Excerpts, verbatim.

**Systems.**

> **Q3 (empty list): CHANGED, from error to "no filters = every event", the same as unset.** This
> covers `""`, `" "`, `","`, `" , "` and `--trace=`. The traced binary must read `BLINK_TRACE=` as
> trace all, not as no trace. `fn:` stays a bad filter.
> Why I changed: plt's point about composition is correct. `fn:a,` is valid and `,` would be an
> error, and the only difference is an item that the item rule says is not there. That is a
> special case in the parser and in the spec, and I asked for one parse with one meaning for each
> value. My cost argument is weaker than I said. Under Q4 (untraced), an empty or unset shell
> variable never makes `blink run` build traced. So the "trace everything" flood can happen only
> in a binary that someone built traced on purpose, and it writes to stderr only, with stdout
> unchanged. That is loud, not silent.

**Systems.**

> **Q4b (hint when `BLINK_TRACE` is set but `--trace` is not): no.** It would add one stderr line
> on every run in a shell that exports the variable, and an agent that parses stderr would see it
> each time. I do not block it if the majority wants it.

**Web/Scripting.**

> Q4: CHANGE to untraced. `blink run` builds traced only when the command has `--trace`. Why I
> moved: sys and plt are right that the RUST_LOG model I cited is a run-time input only; Rust
> never changes the build from RUST_LOG. An ambient variable that picks the codegen, the cache
> key and a slow mode is a build-from-env trap (CFLAGS-style). My concern was the silent no-op for
> a user who tries `BLINK_TRACE=fn:add blink run p.bl`. Q4b fixes that concern.
>
> Q4b: YES, one hint line from `blink run` (not from the program) on stderr, before the build,
> only when `BLINK_TRACE` is set and non-empty and `--trace` is absent:
>
> ```
> $ BLINK_TRACE=fn:add blink run p.bl
> note: BLINK_TRACE is set, but `blink run` builds traced only with --trace; use --trace=fn:add
> 3
> ```
>
> It shows only in the confused case, and it gives the fix in one line. An agent that parses
> stderr sees it only when the env holds a stale value, which is the time it needs to see it. An
> empty `BLINK_TRACE` gives no hint (consistent with Q3: empty = unset).

**AI/ML.**

> **Q1: CHANGED to bad filter, exit 2.** `all,fn:add` and `fn:add,all` are a usage error before
> `main`; a lone `all` (and `all,` after the trim) traces everything. I accept `all,all` as allowed
> (plt) but do not need it. Why I changed: sys, plt and min showed that `all` as an AND item is the
> identity, while in `BLINK_TRACE_CHANNELS` it absorbs (`mono,all` = every channel). My Phase A claim
> that the item reading "is the same rule as channels" was wrong: same text, opposite result. An LLM
> that learned `mono,all` will write `fn:add,all` and expect everything. An error with a fix hint
> ("drop `all` to trace only `fn:add`") corrects that in one retry; a silent identity never does.

**Programming Language Theory.**

> Q4b: no hint. In Phase A I left it open; sys and aiml show that stderr is the NDJSON channel, and a
> line on every run of a shell with a leftover export is noise. I now say no.

**DevOps/Tooling.**

> Q4b: yes, one line from `blink run` (not from the child), only when `BLINK_TRACE` is set and not empty and `--trace` is absent. On sys's concern: under an untraced Q4, the run has no NDJSON on stderr, so the line cannot corrupt a trace stream, and `blink run` already writes its own lines (build errors, warnings) to stderr. It turns web's silent "looks broken" case into a one-line fix. I accept "no message" if the vote goes that way, but I rank it lower.

**Minimalism.**

> Q4b: no hint. It is an addition: one more stderr line, on every run, for every shell with a stale export,
> on the same stream the program and agents read. The spec already says the flag is the switch; `blink run
> --help` can say so too.

**Minimalism.**

> Error source (`--trace` vs `BLINK_TRACE` in the text): no rule needed. §8.15.12 says the words are an
> example; the writer can show it in the example text. I do not object, but I would not make it a MUST.


---

## Phase C: the silent ballot

Six questions. Results: Q1 4-2 (Q1-A: Systems, PLT, DevOps/Tooling, AI/ML; Q1-B: Web/Scripting, Minimalism). Q2-A 6-0. Q3-A 6-0. Q4-A 6-0. Q5 2-4 (Q5-A: Web/Scripting, DevOps/Tooling; Q5-B: Systems, PLT, AI/ML, Minimalism). Q6-A 5-1 (Q6-B: Minimalism). Q1 and Q5 went to a second round. The ballots of the contested and linked questions, verbatim:

### Q1, `all` beside other items

**Systems.**

> Q1: Q1-A
> Reasoning: `all,all` leaves only `all`, so it has one clear meaning and the check stays one test: "is any item not `all`?". Q1-B adds a count check that guards against nothing. Q1-C gives `all` opposite results in `BLINK_TRACE` (an AND list) and `BLINK_TRACE_CHANNELS` (an OR list).
> Concern: a script that joins a default `all` with an extra filter now fails with exit 2. The error text must say to drop `all`.

**Web/Scripting.**

> Q1: Q1-B
> Reasoning: "`all` only as the one item left" is one sentence a user can hold in their head and one test to write. `all,all` has no use. Allowing it adds a second clause to the rule that nobody needs and that the docs must explain.
> Concern: if Q1-A wins, the spec text must give the `all,all` case its own example, or readers will guess it is an error.

**Programming Language Theory.**

> Q1: Q1-A
> Reasoning: As an AND item `all` is the unit, but in the sibling OR list `BLINK_TRACE_CHANNELS` it absorbs; two lawful readings with different output must be refused, not picked. `all,all` has one reading under both algebras (TRUE), so rejecting it adds a case with no ambiguity to remove; Q1-B is acceptable but less uniform.
> Concern: Q1-A leaves `BLINK_TRACE` and `BLINK_TRACE_CHANNELS` with different rules for the word `all`, so the spec must show the error example beside the channel table or a reader will assume the channel rule.

**DevOps/Tooling.**

> Q1: Q1-A
> Reasoning: The error exists to stop `fn:add,all` from meaning two opposite things next to the `BLINK_TRACE_CHANNELS` rule. `all,all` cannot mislead anyone: every reading of it is "everything". An error there is a diagnostic with no user to save.
> Concern: An implementer may dedupe the list before the check and accept `all,fn:add,all` by accident, so the spec table needs that row.

**AI/ML.**

> Q1: Q1-A
> Reasoning: `all` beside a filter would be the AND identity here but absorbs in `BLINK_TRACE_CHANNELS`, so an LLM that learned `mono,all` would guess wrong; an error with a fix hint corrects it in one retry. `all,all` holds no conflict of readings, so rejecting it (Q1-B) adds a rule with nothing to protect.
> Concern: a generator that joins a default `all` with user filters gets exit 2 where it hoped for a narrowed trace, so the error text must name the fix.

**Minimalism.**

> Q1: Q1-B
> Reasoning: The shortest rule is "after the item rule, `all` is valid only as the sole item". Q1-A needs a second clause to let `all` sit beside itself, and `all,all` has no use. Q1-C reads the same word as the opposite of `BLINK_TRACE_CHANNELS` (AND list vs OR list) and gives no message.
> Concern: A script that joins filter lists by `,` and gets `all,all` stops with exit 2, which is loud and has a one-word fix.

### Q4, `BLINK_TRACE` set, no `--trace`

**Systems.**

> Q4: Q4-A
> Reasoning: tracing changes the code that the compiler emits and the build cache key. A variable from the environment must not select the build. The flag selects the build, and the variable only filters a binary that is already traced. Q4-B also needs a second name-check path for a value from the shell.
> Concern: users who know `RUST_LOG=x cargo run` will expect the variable alone to work, and will see no trace and no reason why.

**Web/Scripting.**

> Q4: Q4-A
> Reasoning: RUST_LOG and GODEBUG change only the run, never the build; a shell variable that picks the codegen, the cache key and a slow mode is a CFLAGS-style trap. A stale `export` must not slow every later `blink run`.
> Concern: a user who reads "`BLINK_TRACE` accepts the same filter syntax" tries `BLINK_TRACE=fn:add blink run p.bl` and sees nothing, unless Q5-A wins.

**Programming Language Theory.**

> Q4: Q4-A
> Reasoning: `BLINK_TRACE` is a run-time input of an instrumented binary; whether to instrument is a build input and must come from argv. Q4-B lets an ambient var choose codegen, puts the env in the cache key, and passes tracing down to a nested `blink run`.
> Concern: Users with the `RUST_LOG=... cargo run` habit will get a silent untraced run, so §8.15.13 must say in one sentence that only `--trace` builds traced.

**DevOps/Tooling.**

> Q4: Q4-A
> Reasoning: Tracing is a build mode, so the build switch belongs on the command line, where a reader can see it. A leftover `export` must not turn every later `blink run` into a different binary, and my probe shows today's env path also skips the name check.
> Concern: Users who read "`BLINK_TRACE` accepts the same filter syntax" will try the env var alone and see nothing; without Q5-A that looks broken.

**AI/ML.**

> Q4: Q4-A
> Reasoning: the command line alone decides whether `blink run` builds instrumented; an agent cannot see a leaked export or a `BLINK_TRACE` inherited from a traced parent that spawns `blink run`. Today the env path also skips the name check that the flag gets.
> Concern: users with `RUST_LOG=... cargo run` habits set `BLINK_TRACE` and see no trace, and must learn to add `--trace`.

**Minimalism.**

> Q4: Q4-A
> Reasoning: One switch per layer: the flag picks the build, the var filters a traced binary. A second reader of the same var with a second job is coupling, and a stale export would silently change every later build.
> Concern: A user who reads "BLINK_TRACE accepts the same filter syntax" sets only the var under `blink run`, sees no trace, and must find the flag in the docs.

### Q5, a note from `blink run`

**Systems.**

> Q5: Q5-B
> Reasoning: the note would add a line to stderr on every run in a shell that exports the variable, on the same stream as the program's own output. An agent that parses stderr would see it each time.
> Concern: with no note, the Q4-A confusion above has no hint. The docs for §8.15.13 must say clearly that only the flag builds traced.

**Web/Scripting.**

> Q5: Q5-A
> Reasoning: the note shows only in the confused case and gives the fix in one line, so it turns the top "BLINK_TRACE does nothing" question into a non-issue. It comes from `blink run` before the build, so it does not touch the program's stderr stream when tracing is on.
> Concern: a tool that diffs stderr of `blink run` sees one extra line when a stale export is in its env; that is the time it should see it.

**Programming Language Theory.**

> Q5: Q5-B
> Reasoning: stderr carries the NDJSON stream and the program's own stderr; an unconditional note on every run under a leftover export is noise that a tool must filter. The rule in §8.15.13 is enough to explain the silence.
> Concern: A user who sets the var and sees no events gets no clue on screen and must find the sentence in the spec.

**DevOps/Tooling.**

> Q5: Q5-A
> Reasoning: Q4-A creates a silent "I set the variable and nothing happened" case, and a one-line note that names the fix (`--trace=fn:add`) removes it. The build is untraced, so there is no NDJSON stream for the line to corrupt, and `blink run` already writes its own lines to stderr.
> Concern: A user with a permanent `export` sees the note on every run; that is the price of not guessing, and the fix (unset it) is obvious.

**AI/ML.**

> Q5: Q5-B
> Reasoning: `blink run`'s stderr is where an agent reads the program's stderr; a line on every run in a leaked env breaks stderr checks, which Q4-A exists to protect. The rule is short enough for the docs to carry.
> Concern: the habit user of Q4's concern gets no clue on the first run.

**Minimalism.**

> Q5: Q5-B
> Reasoning: The note is an addition: one more stderr line on every run in every shell with a stale export, on the stream that the program and agents read. The spec and `--help` already name the flag as the switch.
> Concern: Under Q4-A the confused user from the Q4 concern gets no hint on screen.

### Q6, the source of the value

**Systems.**

> Q6: Q6-A
> Reasoning: it costs nothing. `blink run` finds a bad flag value before it builds, and a binary run by hand reads only `BLINK_TRACE`, so each path always knows the source. The user then knows which input to fix (for example, a variable left set in a CI job).
> Concern: this makes one part of the error text normative, while §8.15.12 says the words are only an example. The writer must require only the source, not the exact words.

**Web/Scripting.**

> Q6: Q6-A
> Reasoning: with a stale `export BLINK_TRACE`, a hand-run traced binary that fails with a bare "bad trace value" leaves the user looking at a command line that has no `--trace`. Naming the source is the only clue they get, and it costs one word.
> Concern: if Q6-B wins, an implementation may print one generic text for both, and the leaked-export case gets hard to debug.

**Programming Language Theory.**

> Q6: Q6-A
> Reasoning: The source of the value is information, not wording, so a rule on it does not break "the words are an example". For a traced binary run by hand with an inherited value, the source is the only clue to the cause.
> Concern: The writer must state it as content ("the text names the source") and keep the exact words free, or it becomes a wording rule.

**DevOps/Tooling.**

> Q6: Q6-A
> Reasoning: With a leaked export, the source of the value is the only clue the user has, and the program cannot show it any other way. It is a fact in the message, not wording, so it fits a rule while the rest of the text stays example.
> Concern: A traced binary started by hand only ever sees `BLINK_TRACE`, so the rule must not force `blink run` to relabel a flag value as `BLINK_TRACE` after it passes the value to the child.

**AI/ML.**

> Q6: Q6-A
> Reasoning: with two inputs (flag and env) that share one syntax, naming the source tells an agent which input to fix with zero extra probing. It constrains content, not words, so it does not freeze the message text.
> Concern: one more required item in the error text that an implementation can forget; a corpus test should pin it.

**Minimalism.**

> Q6: Q6-B
> Reasoning: §8.15.12 already says the words are an example; a MUST on error text is surface we then have to keep. The writer can show the source in the example line.
> Concern: An implementation that drops the source leaves a user with a leaked export no clue where the bad value came from.


---

## Phase D: the focused round (Q1 and Q5)

The seats answered the strongest point of the other side. Verbatim.

Moves: on Q1, Web/Scripting and Minimalism moved to Q1-A, and AI/ML moved to Q1-B (and back to Q1-A in the re-vote). On Q5, Programming Language Theory and AI/ML moved to Q5-A. Systems and Minimalism held Q5-B; Web/Scripting and DevOps/Tooling held Q5-A.

**Systems**

> **Q1: hold Q1-A (weakly).** The strongest point for Q1-B (web, min): "`all` only as the sole item" is the shortest rule. But Q1-A is also one sentence: "if the list holds `all`, every item is `all`". Both rules are one check of the same size. The purpose of the error is to stop `fn:add,all` from having two opposite readings (devops). `all,all` has only one reading, so an error there helps no user, and it stops a script that joins two default lists. The stakes are small, and I will not object if Q1-B wins. devops's concern is valid for both options: the spec table needs the row `all,fn:add,all` (bad filter), so that an implementation does not remove duplicates before the check.
>
> **Q5: hold Q5-B.** The strongest point for Q5-A (devops): the build is untraced, so the note cannot corrupt an NDJSON stream, and it names the fix. My answer: under Q4-A, an exported `BLINK_TRACE` is a valid setup. It filters each traced binary that you start by hand (for example, one from `blink build --trace`), and it changes nothing for `blink run`, as the spec says. The note then fires on every `blink run` for a user who did nothing wrong. Also, the program's own stderr comes after the note on the same stream, and an agent or a test that compares stderr sees a line that depends on the environment. The confused case is better fixed in the docs: §8.15.13 says that only the flag builds traced, and `blink run --help` can say it too.
>
> No change on either question.

**Web/Scripting**

> Q1: I MOVE to Q1-A. Sys's point wins: the Q1-A check is "is any item not `all`?", which is one
> test and no count, so it is no longer than Q1-B. `all,all` has one reading under either list, so
> an error there saves no user. I ask that the table have a row for `all,fn:add,all` (devops's
> dedupe concern), so an implementer cannot dedupe first and accept it.
>
> Q5: I HOLD Q5-A. The strongest point against it: with a permanent `export`, every `blink run`
> writes one more stderr line, on the stream that agents read. My answer: the note comes only from
> an untraced build, so it never sits in an NDJSON stream. It comes from `blink run`, which already
> writes its own build lines to stderr, so an agent that reads `blink run` stderr already has to
> filter out lines that are not from the program. And an `export BLINK_TRACE` with no `--trace` in
> the command is a mistake in nearly every case, so the note is right nearly every time it shows.
> On the other side: under Q5-B the first-time user who reads "BLINK_TRACE accepts the same filter
> syntax" (§8.15.5), sets it, and sees nothing has no clue on screen. Four of the Q5-B ballots name
> that exact case as their own concern. A rule whose winners all list the same hole is a weak rule.
> A doc sentence does not reach the user at the moment they are confused; one line of text does.

**Programming Language Theory**

> Q1. web and min: "`all` only as the sole item" is the shorter rule, and `all,all` has no use. Q1-A is also one clause: "`all` beside an item that is not `all` is a bad filter". It is not longer; it names the actual hazard (an item whose meaning differs between the AND and the OR list) and nothing more. Q1-B adds a rejection with no ambiguity behind it, so the error text must invent a reason. A joined list like `$DEFAULT,$EXTRA` with both `all` is a real script shape, and every reading of it is "everything". devops's row `all,fn:add,all` -> exit 2 must be in the table under either option. I hold A, but this is low stakes; B is sound too.
>
> Q5. devops answers my Phase C reason directly: under Q4-A the build is untraced, so there is no NDJSON stream for the note to corrupt. My reason was wrong. What is left on the other side is min's point: one more stderr line under a stale export. But that line appears exactly when an input the user set is being ignored, which is the case a diagnostic exists for; Q4-A made `BLINK_TRACE` a silent no-op for `blink run`, and the note is the cheap way to make that rule visible on screen. It comes from `blink run` before the build, so it never mixes with the child's stderr order. I move to Q5-A. Condition: the note fires only when `BLINK_TRACE` is non-empty after the item rule and `--trace` is absent, and it does not change the exit code.

**DevOps/Tooling**

> Q1 (stay on Q1-A). The strongest Q1-B point (web, min) is that "`all` only as the sole item" is one short rule and Q1-A needs a second clause. It does not. Q1-A is also one test, as sys put it: "is any item not `all`?" A Q1-B implementation must count the items after the trim and dedupe nothing. That is not shorter. The words differ ("only item" against "every item is `all`"), but neither needs a second sentence. My test for an error is whether it catches a real mistake. `all,all` has one reading under the AND rule and under the channel rule, so an error there saves no user. It only breaks a script that joins two default lists. I agree with web's concern: the spec table must show `all,all` and `all,fn:add,all` as rows.
>
> Q5 (stay on Q5-A, but I accept Q5-B). The strongest Q5-B point (sys, plt, aiml, min) is that the line appears on every run under a stale export, on the stderr that agents and harnesses parse. That is a fair cost. My answer: the line appears only when the user's setup conflicts with the rule, and that is when a tool should see it. With no line, the one failure that Q4-A creates ("I set BLINK_TRACE and nothing happened") gives no clue on screen. That is the silent wrong result that I judge every diagnostic by. If the panel keeps Q5-B, I ask that the §8.15.13 text and `blink run --help` say that only the flag builds traced, as sys and plt already note. I do not move. Q5-B is acceptable and I will not dissent against it in the record.

**AI/ML**

> **Q1: I move to Q1-B.** web and min's point holds: "after the item rule, `all` is valid only as
> the sole item" is the shortest rule and the one an LLM learns from a single sentence. Q1-A needs
> an extra clause ("or beside itself") that guards a value no one writes. devops's own concern
> also argues for B: under A an implementer can dedupe before the check and accept
> `all,fn:add,all` by mistake; under B the check is "one item, and it is `all`", with no dedupe to
> get wrong. The cost of B is exit 2 on `all,all`, which is loud and has a one-word fix. My Phase C
> reason for A ("rejecting it adds a rule with nothing to protect") was wrong: A is the rule with
> the extra clause, not B.
>
> **Q5: I move to Q5-A.** devops's point answers mine: under Q4-A the build is untraced, so there is
> no NDJSON stream for the note to corrupt, and the line comes from `blink run` before the build,
> not from the program. My concern was stderr checks in a leaked env; but in that env the note is
> exactly the clue an agent lacks ("why is BLINK_TRACE ignored?" or "where did this export come
> from?"). Under Q4-A a set, non-empty `BLINK_TRACE` with no `--trace` is always either a mistake or
> a stale export, and a one-line fix (`use --trace=fn:add`) beats a silent no-op for debuggability.
> Remaining cost: a user who keeps a permanent export for hand-run binaries sees the note each run;
> `unset` ends it.

**Minimalism**

> Q1: I move to Q1-A. The strongest point (devops, aiml, sys): the error exists only to refuse a value with two lawful readings, and `all,all` has one reading under both algebras. My B vote rested on "shorter rule", but "every item is `all`" and "`all` is the sole item" are the same length, so that point is a wash. Then the error on `all,all` is a diagnostic that saves no one, and cutting it is the subtraction. I keep devops's ask: the spec table needs the row `all,fn:add,all` -> exit 2, so a dedupe before the check is not read as allowed.
>
> Q5: I hold Q5-B. The strongest point (devops): the build is untraced, so there is no NDJSON stream for the note to corrupt. True, but the program's own stderr is still on that stream, and an agent or test that checks `blink run`'s stderr sees one more line on every run in a shell with a stale export: the case Q4-A was chosen to keep quiet. The note also becomes surface: its trigger (set, not empty, flag absent) is one more rule we must spec, test and keep. The fix is a sentence in §8.15.13 and in `blink run --help`, which costs no runtime line. If the panel wants a hint, I would take it only behind `--verbose`, not by default.


---

## Phase D: the silent re-vote (Q1 and Q5)

Q1-A 6-0. Q5-A 4-2 (Web/Scripting, PLT, DevOps/Tooling, AI/ML; Systems and Minimalism for Q5-B). Verbatim.

**Systems**

> Q1: Q1-A
> Reasoning: The error is there to refuse an item that has two opposite readings in the AND list and the OR list. `all,all` has one reading under both, so an error there saves no user and stops a script that joins two default lists. The check is one test, "is any item not `all`?", and it is not longer than Q1-B's test.
> Concern: an implementation that removes duplicates before the check accepts `all,fn:add,all`, so the spec table must have that row as exit 2.
>
> Q5: Q5-B
> Reasoning: Fact from a probe (gen1, MVCE, [probe path omitted]): a plain `blink run p.bl` writes nothing to stderr, on the first run and on a cached run. So web's "blink run already writes its own build lines to stderr" is not true for a normal run, and the note would be the only line that `blink run` adds to the program's stderr, on every run in a shell that exports the variable. Under Q4-A, an exported `BLINK_TRACE` is also a valid setup for traced binaries that you start by hand, so the note fires for users who made no mistake. Its trigger (set, not empty after the item rule, no flag) is one more rule to spec and test.
> Concern: the first-time user who sets `BLINK_TRACE` and runs `blink run` gets no clue on screen, so §8.15.13 and `blink run --help` must say that only `--trace` builds traced.

**Web/Scripting**

> Q1: Q1-A
> Reasoning: "is any item not `all`?" is one check, the same size as "`all` is the sole item", so my Phase C reason for B (the shorter rule) does not hold. The error exists to refuse a value with two opposite readings, and `all,all` has one reading under the AND list and under the channel list. An error there saves no user and breaks a script that joins two default lists.
> Concern: an implementation may remove duplicates before the check and accept `all,fn:add,all`, so the spec table needs that row (exit 2) and an `all,all` row.
>
> Q5: Q5-A
> Reasoning: Q4-A makes a set `BLINK_TRACE` a silent no-op for `blink run`, and a user who reads "BLINK_TRACE accepts the same filter syntax" (§8.15.5) will hit it on the first try; one line that names the fix (`use --trace=fn:add`) reaches them at that moment, which a doc sentence does not. The build is untraced, so the note never sits in an NDJSON stream, and it comes from `blink run` before the build. Sys's case (a permanent export for hand-run traced binaries) is real but rare, and the note then says only true things; `unset` ends it.
> Concern: a test or agent that compares `blink run` stderr in a shell with a stale export sees one line that depends on the environment, so the trigger (non-empty after the item rule, no `--trace`, exit code unchanged) must be exact in the spec.

**Programming Language Theory**

> Q1: Q1-A
> Reasoning: The error exists to refuse a value with two lawful readings that differ (the AND unit against the OR absorber). `all,all` has one reading under both, so an error there protects no one and breaks a script that joins two default lists. "Every item is `all`" and "`all` is the sole item" are checks of the same size, so B has no simplicity gain.
> Concern: An implementer may dedupe before the check and accept `all,fn:add,all`, so the spec table must hold that row (exit 2) and the row `all,all` (every event).
>
> Q5: Q5-A
> Reasoning: Under Q4-A, a non-empty `BLINK_TRACE` is an input the user set that `blink run` ignores; a diagnostic at that point turns a silent no-op into one line with the fix. The build is untraced, so no NDJSON stream exists for the line to break, and it comes from `blink run` before the build. sys's case (an export kept for hand-run traced binaries) is real but rare, and the note is true and harmless there.
> Concern: The trigger (non-empty after the item rule, `--trace` absent) is one more rule to spec and test, and a test that compares the stderr of `blink run` in a leaked env will see the extra line.

**DevOps/Tooling**

> Q1: Q1-A
> Reasoning: The error exists only to refuse a value with two lawful readings, and `all,all` has one reading under the AND list and under the channel list. "Every item is `all`" is one check, the same size as "`all` is the only item", so Q1-B adds an error that saves no user and breaks a `$DEFAULT,$EXTRA` script. aiml's dedupe point holds for both options and is fixed by the table row, not by the option.
> Concern: An implementer dedupes before the check and accepts `all,fn:add,all`, so the spec table must have that row as exit 2.
>
> Q5: Q5-A
> Reasoning: Under Q4-A, a set `BLINK_TRACE` with no flag is an input that `blink run` ignores, and a tool that ignores an input the user set should say so once, at the moment it does. The line comes from `blink run` before the build, not from the program, and there is no NDJSON stream for it to corrupt. sys's case (a permanent export for hand-run traced binaries) is real but rare, and `unset` or the flag ends the note.
> Concern: A test or agent that compares `blink run` stderr in a shell with a stale export sees one extra line, so the trigger must stay narrow (non-empty after the item rule, `--trace` absent, exit code unchanged).

**AI/ML**

> Q1: Q1-A
> Reasoning: sys showed that the Q1-A check ("every item is `all`") is one sentence and one test, the same length as Q1-B, so my Phase D reason for B (B is shorter) falls. The error exists to refuse a value with two readings; `all,all` has one reading under the AND rule and the channel rule, so an error there teaches an LLM nothing and only breaks a script that joins two default lists. devops's dedupe hazard is closed by a table row under either option.
> Concern: an implementation dedupes before the check and accepts `all,fn:add,all`, so the spec table must hold the rows `all,all` (every event) and `all,fn:add,all` (exit 2).
>
> Q5: Q5-A
> Reasoning: under Q4-A, a set `BLINK_TRACE` with no `--trace` is an input that `blink run` ignores, and an agent cannot learn that from the screen without the note; a doc sentence does not reach it at the moment it is confused. The note comes from `blink run` before an untraced build, so it never sits in an NDJSON stream, and it names the fix in one line. sys's case (a deliberate export for hand-run binaries) is real but rare, and the note is still true there.
> Concern: a harness that diffs `blink run` stderr in a shell with a deliberate export sees one extra line per run, so the spec must fix the trigger exactly (non-empty after the item rule, flag absent, exit code unchanged).

**Minimalism**

> Q1: Q1-A
> Reasoning: The error exists only to refuse a value with two lawful readings (AND identity vs OR absorb). `all,all` has one reading under both, so an error there is a diagnostic that saves no one, and dropping it is the subtraction. The two rules are the same length ("every item is `all`" vs "`all` is the sole item").
> Concern: An implementation that dedupes before the check accepts `all,fn:add,all`; the spec table must carry that row as exit 2.
>
> Q5: Q5-B
> Reasoning: Sys's point decides it for me: under Q4-A an exported `BLINK_TRACE` is a valid setup (it filters traced binaries started by hand, e.g. from `blink build --trace`), so the note fires on every `blink run` for a user who did nothing wrong. It also puts an env-dependent line ahead of the program's own stderr, and its trigger is one more rule to spec, test and keep. A sentence in §8.15.13 and `blink run --help` covers the confused first-time user at no runtime cost.
> Concern: The first-time user who sets only the var under `blink run` sees nothing on screen and must find the doc sentence.


---

See also: [runtime-trace-open-points.md](runtime-trace-open-points.md) (the rulings this extends), [trace-ndjson-format.md](trace-ndjson-format.md) (the filter syntax), [panic-hook-and-dev-trace-open-points.md](panic-hook-and-dev-trace-open-points.md) (the item rule).
