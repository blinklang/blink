[< All Decisions](../DECISIONS.md)

# Standard Input (`IO.Read`) — Design Rationale

The spec had no text for reading standard input. `io.read_line()` returned `Str`, with `""` for both a blank line and end of input, so a program could not tell them apart. It had no way to read all input, and `io.read_bytes(n)` had no stated meaning. The decision adds the `IO.Read` sub-effect (§4.4.9).

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds, then a focused round and a re-vote on Q4 and Q9-sub.

Panelist text below is quoted verbatim, each reply whole. Only the heading levels are shifted to fit this file, and the local ticket ID is replaced by `[ticket]`.

Notes for readers of the record:

- The AI/ML Q3 reasoning says a mock that overrides the derived `read_line` has a `read_all` that "falls through to the real-stdin primitive". Under §4.7.1 that is not so: an omitted derived operation runs its body against the innermost handler, so `read_all` runs over the mock's own `read_bytes`, and W0545 fires when the mock omits `read_bytes`. The real risk is a mock whose operations disagree. S7-4, adopted 6-0, makes agreement an obligation on every handler.
- The lead added one rule that the panel did not vote on: a handler for the parent effect (`handler IO { ... }`) counts the operations of a marked sub-effect only if it implements one or more of them. Without it, every `handler IO` that changes only `print` would get W0545. The user approved the tally with this rule shown.
- The `?? ""` help line (Q9-sub) is dropped. The spec text names `?? ""` only to say why the help does not show it.

### Tally

| Question | Result | Vote |
|---|---|---|
| Q1 Error channel for a read failure | a: no `Result`; the operation panics. Q1-sub: the panic names the operation and the errno; `libc.read_bytes(0, n)` is the path for code that must recover | 6-0; Q1-sub 6-0 |
| Q2 Input that is not valid UTF-8 | a: panic; the message names `io.read_bytes` | 6-0 |
| Q3 Operation set | d: one primitive `read_bytes`; `read_line` and `read_all` derived; the default handler answers all three from one buffer | 5-1 (AI/ML dissents for a) |
| Q4 `read_bytes` meaning | a: exactly `n` bytes, fewer only at end of input, empty at end of input | 6-0 in Phase D after 3-3 in Phase C (Systems, DevOps, PLT moved from b) |
| Q4-sub `n <= 0` | panics before the operation runs | 6-0 |
| Q5 `@handle_all` placement | may mark a nested sub-effect and covers only it; the stdlib marks `IO.Read`, not `IO` | 6-0 |
| Q6 Every line | a: no lines helper; the spec names `io.read_all().lines()` and the `loop`/`match` form. Q6-sub: targeted `io.lines()` diagnostic | 6-0; Q6-sub 6-0 |
| Q7 Mock helper | a: `std.testing.stdin_from(text: Str) -> Handler[IO.Read]` | 6-0; name 5-1 (Minimalism dissents for `std.testing.stdin`) |
| Q8 S7-1..S7-5 | all adopted; S7-5 as a `blink test` runner rule | 6-0 each |
| Q9 Migration diagnostic | b: targeted help with the `match` form, not machine-applicable | 6-0 |
| Q9-sub `?? ""` second help line | drop | 6-0 in Phase D after 4-2 drop in Phase C (Web, DevOps moved from adopt) |

**Dissent (Q3, AI/ML, Phase C):** "With three primitives under `@handle_all`, a line-level mock must cover all three ops, and the existing `PartialHandler` warning enforces that. Under `d`, a mock that overrides the derived `read_line` gets no warning, because derived ops do not count."

**Dissent (Q7 name, Minimalism, Phase C):** "One function, in the testing module, with the shortest name that reads well at the `with` site (`with testing.stdin("1\n2\n") { ... }`)."

#### Phase A — Independent proposals

======================================================================
##### SYSTEMS (sys)
======================================================================
SYS Phase A proposal: stdin as a new IO.Read sub-effect, with three handler ops that share one buffer.

**P1 (main). New sub-effect `IO.Read`, three primitive ops, one shared buffer.**

```blink
effect IO {
    effect Print   // stdout
    effect Log
    effect Read    // stdin
}
```

Handler ops (each takes no Display wrapper; these are the ops themselves):

| Effect | Op | Result |
|---|---|---|
| IO.Read | `fn read_line() -> Option[Str]` | next line without `\n` or `\r\n`; `None` at EOF |
| IO.Read | `fn read_all() -> Str` | all of stdin that remains; `""` at EOF |
| IO.Read | `fn read_bytes(n: Int) -> Bytes` | exactly n bytes, or fewer only at EOF (keeps the current compiler meaning) |

```blink
fn main() ! IO {
    let mut sum = 0
    loop {
        match io.read_line() {
            Some(l) => sum = sum + l.to_int().unwrap_or(0),
            None => break,
        }
    }
    io.println(sum)
}

fn word_count() ! IO.Read, IO.Print {
    let text = io.read_all()
    io.println(text.lines().len())
}
```

Rules the spec must state exactly (this is the part that decides correctness):
- `"a\n"` gives `Some("a")`, then `None`. `"a"` (no final newline) gives `Some("a")`, then `None`. `"\n"` gives `Some("")`, then `None`. `""` gives `None`. A line has no length limit. Today's runtime puts each line in a fixed `char buf[4096]` and quietly breaks longer lines into pieces (bootstrap/runtime_stdio.h:13). That is a second latent bug, and the spec has to forbid it.
- All three ops read from one buffered stdin stream, so you can mix them in any order. src/lsp.bl already does this: it reads headers with `read_line`, then the body with `read_bytes`.
- Calling `libc.read_bytes(0, ..)` (or `std.io.read_fully(0, ..)`) after any `io.read_*` call is unspecified, because the io buffer can hold bytes that fd 0 has already given up. One sentence in §9.1.3.3 covers it. Go (bufio over os.Stdin) and C (stdio vs read(2)) have the same trap.
- `Str` must be valid UTF-8 (§3 invariant). If input bytes are not valid UTF-8, or the read fails (EIO on a tty that hung up), `read_line`/`read_all` panic with a message that names `io.read_bytes` as the byte-exact path. They do not use lossy replacement: changing data with no signal goes against the E0301 stance. Stdin read errors almost never happen on pipes, files or ttys, so making every benchmark loop carry `Result[Option[Str], Errno]` costs a lot to cover a nearly empty case. Rust's `println!` panics on EPIPE on the same reasoning.
- Mark IO.Read as handle-all (put `@handle_all` on the sub-effect, or add a rule that says so). If a mock gives `read_line` but forwards `read_all` to real fd 0, you get one logical stream split across two sources. That is the same consistency case as Time and Rand.

What it compiles to: with no handler installed, each op is a direct call into the runtime reader, the same cost model as `io.print`. The per-line cost is one GC `Str` allocation. `read_all` can use `fstat` to size the buffer up front when fd 0 is a regular file, which makes it one allocation and about one `read(2)` for redirected input. That is the fast path for benchmark tasks, and the spec should say so in a sentence.

Mocking, at zero cost to production code:

```blink
fn feed(lines: List[Str]) -> Handler[IO.Read] {
    let mut i = 0
    handler IO.Read {
        fn read_line() -> Option[Str] { ... }
        fn read_all() -> Str { ... }
        fn read_bytes(n: Int) -> Bytes { ... }
    }
}
```
(The moderator should check the exact handler-literal syntax against §4.7. The point here is that there are three ops and all of them are required.)

**P2. No lazy `io.lines()` iterator in v1.** §3c.1 says v1 `Iterator[T]` is pure and names `for line in file.lines() ! IO` as not expressible. `iter.from_fn(fn() { io.read_line() })` would break that rule. The v1 answer is to use `io.read_all().lines()` (eager), or the `loop`/`match` above. That `loop`/`match` is the shape §2.11 already prescribes in place of `while let`. A `read_lines() -> List[Str]` helper would add nothing, because it is the same as `read_all().lines()`. I would bind the lazy form to the deferred effectful-iterator design. Required spec edit: `Str.lines()` drops the empty piece after a final terminator and accepts `\r\n`, so `read_all().lines()` and repeated `read_line()` give the same sequence.

**P3. Migration (no overloading, so this is a breaking signature change).** `io.read_line` changes from `Str` to `Option[Str]`. It is a 3-step dance: src/lsp.bl:34 and the typecheck intrinsic signature at src/typecheck.bl:5546 are the only users in the compiler. Until gen0 is re-pinned, `read_line_opt` lives next to the old form.

**Alternative I rejected:** a single primitive op, `read(max) -> Bytes`, with line and all-of-input logic in a stdlib wrapper. It has the smallest set of ops, but the line buffer would then live in wrapper state outside the handler, and that state leaks across `with` scopes. Mocks would also have to fake bytes, not lines. More work for the AI to write, and a buffer-coherence bug waiting to happen.

How other languages do it: Zig `readUntilDelimiterOrEof` returns `?[]u8`, which is P1's shape. Rust `read_line` returns a byte count where 0 means EOF, a sentinel that is easy to misuse. Python `readline()` keeps the `"\n"` so that `""` can mean EOF, which you must remember to strip. Go `bufio.Scanner` has a 64 KiB token limit that has caught many people, and P1 forbids any limit.

**Vote position:** I can take the `Result` error form only if IoError arrives in v1. With Errno only, it is noise, so I hold panic-on-error.

======================================================================
##### WEB/SCRIPTING (web)
======================================================================
Web/Scripting panelist, Phase A proposal (gap: stdin read_line EOF and read-all)

**My rule for this gap:** a Python, JS or Kotlin dev should be able to write "read every line until EOF" correctly on the first try, without reading docs. Today's `io.read_line() -> Str` fails that test: `""` means both a blank line and EOF. Python has the same trap (`readline()` returns `""` at EOF and keeps the `\n`), and people still ask about it on Stack Overflow. Kotlin got it right with `readLine(): String?`, which returns null at EOF. Blink should do what Kotlin does.

---

###### Proposal W1: sub-effect `IO.Read` with three handle ops

```blink
effect IO {
    effect Print   // stdout
    effect Log
    effect Read    // stdin
}
```

Handler ops (`IO.Read` is `@handle_all`, so a mock that covers only some ops is a compile error and never falls through to the real stdin in a test):

| Op | Returns | Behavior |
|---|---|---|
| `fn read_line() -> Option[Str]` | next line | Removes one trailing `\n` or `\r\n`. A last line with no newline is still `Some`. Returns `None` only at EOF. |
| `fn read_all() -> Str` | rest of stdin | Returns the exact bytes left (no terminators removed); `""` at EOF. |
| `fn read_bytes(n: Int) -> Bytes` | up to `n` bytes | Empty `Bytes` at EOF. |

All three share one buffer. So `read_line()` and then `read_all()` gives the rest of the input, the same as in Python and Go. A stdlib wrapper (not a handler op) adds the streaming form:

```blink
fn lines() -> Iterator[Str] ! IO.Read   // = iter.from_fn(fn() { io.read_line() })
```

This copies the `Channel` precedent exactly (`for v in ch` stops at the first `None`, §3c). It is one-shot, as every `from_fn` iterator is.

**The 90% case:**

```blink
fn main() ! IO {
    for line in io.lines() {
        io.println(line.to_upper())
    }
}
```

**Slurp it all** (most benchmark tasks). Use `Str.lines() -> List[Str]`, which already exists:

```blink
fn main() ! IO {
    let nums = io.read_all().lines().map(fn(l) { l.trim().parse_int() ?? 0 })
    io.println(nums.fold(0, fn(a, n) { a + n }))
}
```

**Manual loop:**

```blink
fn main() ! IO {
    while true {
        match io.read_line() {
            Some(l) => io.println("[{l}]"),
            None => break,
        }
    }
}
```

**Mocking:** `std.testing` ships `stdin(text: Str)`, a handler that serves `text`, so nobody hand-writes the three ops:

```blink
test "sums lines" {
    with testing.stdin("1\n2\n\n3") {
        assert_eq(sum_input(), 6)   // the blank line is Some(""), not EOF
    }
}
```

**Errors: no `Result`.** I/O and decode failures on stdin are very rare in the programs that read it (scripts, filters, benchmark tasks). If `read_line` returned `Result[Option[Str], E]`, every one-liner would need `?` plus a `main` that returns `Result`, or `.unwrap()` everywhere. That is a tax on 100% of users for a <0.1% case. My rule:
- An OS read error panics with a clear message: `stdin read failed: EIO`.
- Invalid UTF-8 panics: `stdin is not valid UTF-8 at byte N; use io.read_bytes`.

The bytes path is the escape hatch for binary input. Programs that need to recover from errors already have `libc.read_bytes(0, n) -> Result[Bytes, Errno]`, which is the second tier that Q8 allows.

**Tradeoffs:**
- (+) Familiar names: Kotlin `readLine()`, Python `sys.stdin.read()`, Node `readFileSync(0)`, Rust/Go line iteration. You can learn it in 5 minutes.
- (+) Fits Q8: each op has a row, a handler can intercept it, and `! IO` still grants it, so existing `fn main() ! IO` programs do not change.
- (−) It is not the same shape as `TcpStream.read_line() -> Result[Option[Str], NetError]`. I accept that. Network errors are routine, stdin errors are not, and the error channel should match how often a domain fails. The `Option` layer, which is the part that matters, is the same.
- (−) Panic on bad UTF-8 is strict. The other choices are worse: silent U+FFFD replacement corrupts data with a green build, which goes against Blink's "no silent guess" stance (E0301).

###### Proposal W2: migrating the existing compiler names

`io.read_line() -> Str` changes to return `Option[Str]`. Blink has no overloading, so old code gets a type mismatch. The compiler should add a specific help line: `read_line now returns Option[Str] (None at EOF); use \`io.read_line() ?? ""\` for the old behavior, or \`for line in io.lines()\``. This should be machine-applicable, because the `?? ""` rewrite keeps the old behavior exactly. `io.read_bytes(n)` keeps its signature and moves under `IO.Read`. Code with only `! IO.Print` that reads stdin now fails with a missing-effect error. That is correct, because it was an untracked side effect.

###### Rejected alternatives
- **Sentinel `""` plus `io.eof() -> Bool`.** That is C's `feof` footgun: you check after the read, get the order wrong, and process a phantom empty last line.
- **Eager `io.read_lines() -> List[Str]` as a fourth op.** It duplicates `read_all().lines()`. One way to do it.
- **A separate `Stdin` top-level effect / `stdin` handle.** Every newcomer types `io.` first, and a second handle for one stream adds names for no gain. Python, Kotlin and Node all put it under the I/O namespace.

======================================================================
##### PLT (plt)
======================================================================
**PLT panelist: Phase A proposal (spec gap: stdin)**

**Typing principle.** Stdin is one byte stream that gets consumed as you read it. Every read operation is a view of that one resource. So the effect should have **one primitive op**, and every other read should be a **derived op** over it. That gives the same shape as `Net.Connect` (`request` is primitive, the verbs are derived, §4.7.1). A mock that answers the primitive then answers every view the same way, because a derived body runs at the call site against the innermost handler. A mock that answers some views and forwards the rest would read from two streams. That is the `@handle_all` case, so the effect gets that mark.

###### P1: the `IO.Read` sub-effect, one primitive op

```blink
effect IO {
    effect Print
    effect Log
    @handle_all
    effect Read {
        // Primitive: up to `max` bytes (max > 0). An empty Bytes means end of input.
        fn read_bytes(max: Int) -> Result[Bytes, Errno]

        // Derived: the next line without its terminator ("\n" or "\r\n"), or None at end of input.
        // Bytes that are not valid UTF-8 give Err(Errno(EILSEQ)).
        fn read_line() -> Result[Option[Str], Errno] { ... }
        // Derived: all remaining input, byte-exact (keeps the trailing newline and any CR).
        fn read_all() -> Result[Str, Errno] { ... }
        fn read_all_bytes() -> Result[Bytes, Errno] { ... }
        // Derived: read_all, then split on line terminators; a final terminator gives no empty last line.
        fn read_lines() -> Result[List[Str], Errno] { ... }
    }
}
```

- The handle stays `io` (§4.4 naming rule). `! IO.Read` gates only the read ops, and `! IO` grants them as the parent does. The stdin op lands as a sibling of Print in the tree.
- The primitive is lossless, so `read_all` is byte-exact. A `read_line` primitive would lose the line terminators, so `read_all` could not be derived from it. That would also break the composition law `read_all() == concat of read_line() + terminator`, which the spec should state.
- The default runtime handler implements every derived op natively over one shared buffer. A handler may answer a derived op, and doing so is an optimisation, not a change in meaning. The reference bodies define the meaning. The `read_line` body may read one byte at a time, which is correct and slow only under a mock.
- **Errors.** A read can fail (EIO, EAGAIN, EISDIR when stdin is a directory, bad UTF-8). A function that hides those failures misstates its type. `Errno` matches `libc.read_bytes` and the decision that rich `IoError` waits until after v1, and `EILSEQ` is a real errno. When `IoError` arrives, it replaces `Errno` in one place.
- **EOF signal.** `Option` inside `Result`, the same shape as `TcpStream.read_line` (§4.4.6). That is one shape for "line stream" across the language.

```blink
fn main() -> Result[(), Errno] ! IO {
    let mut total = 0
    loop {
        match io.read_line()? {
            Some(l) => total = total + l.len()
            None => break
        }
    }
    io.println("{total}")
    Ok(())
}
```

A benchmark task needs only one line: `let text = io.read_all()?` or `for l in io.read_lines()? { ... }`.

###### P2: no lazy `io.lines()` iterator in v1, and no effectful `Iterator`

§3c fixes `Iterator[T]` as pure and restartable: a recipe you can run again, not a cursor. A stdin iterator would break both rules. Running it twice would read different data, or block, and an effect would hide inside a pure type. That is unsound. The eager `read_lines() -> List[Str]` composes with every existing List method. Streaming input stays as a `loop`/`match` over `read_line`, which is also the documented v1 pattern (§3c). When effectful iteration comes in v2, `io.lines()` can be added as a conservative extension.

###### P3: mocking falls out of the semantics

A handler captures a `let mut` as a shared cell (§4.7), so a user can write a mock that answers only the primitive:

```blink
fn stdin_from(text: Str) -> Handler[IO.Read] {
    let mut rest = text.to_bytes()
    handler IO.Read {
        fn read_bytes(max: Int) -> Result[Bytes, Errno] {
            let n = if max < rest.len() { max } else { rest.len() }
            let chunk = rest.slice(0, n)
            rest = rest.slice(n, rest.len())
            Ok(chunk)
        }
    }
}
```

`read_line`, `read_all` and `read_lines` all run their derived bodies against this mock, so the views cannot disagree. std should ship this as `std.testing.stdin_from(Str)`. A handler that answers only `read_line` triggers W0545 for the missing primitive. That is the correct warning: the real-stdin primitive would still answer `read_all`.

###### P4: migrate the compiler-only names

`io.read_line() -> Str` moves to the new signature. It conflates a blank line with EOF, so it is a soundness bug, not just a style problem. A 3-step dance with a fix-it: `-> Str` becomes `-> Result[Option[Str], Errno]`. The old `read_bytes(n)` read exactly n bytes. Its meaning becomes "at most max bytes" (short reads allowed), and std keeps `read_fully` for the exact read. Rule 3 does not apply because these ops return plain values, not handles.

###### Tradeoffs

- **Against:** `Result` makes the common line verbose (`io.read_line()?`), and `main` must return `Result`. I accept this. A panic would hide an effect the row does not show, and `?` is one token.
- `@handle_all` on a nested sub-effect: §4.7.1 only shows the mark on a top-level effect, so the spec must say that a sub-effect can carry it.
- Adding `Read` under `IO` widens what an existing `! IO` grants. That widening is monotone and source-compatible, but capability budgets (§4.8) that grant `IO` will now also grant stdin. A separate top-level `Stdin` effect would avoid that, but it would break the `io` handle and the "console = IO" model, so I reject it.

###### Other languages

Koka and OCaml 5 effect libraries model input as one `read` op with derived combinators. Haskell's `getLine`, which throws `isEOFError`, is the mistake to avoid: EOF there is an exception, not a value. Rust's `read_line -> io::Result<usize>`, which returns 0 at EOF, uses a sentinel, and P1 replaces the sentinel with a type.

======================================================================
##### DEVOPS/TOOLING (devops)
======================================================================
###### DevOps/Tooling proposal: stdin as `IO.Read`

I judge each choice below by three questions. What error does old code get? What does `io.` complete to? How do you mock it in a test?

###### P1. A new sub-effect, `IO.Read`, with three handler ops

```blink
effect IO {
    @handle_all
    effect Read       // stdin
    effect Print      // stdout
    effect Log
}
```

| Handle op | Signature | Default handler |
|---|---|---|
| `io.read_line()` | `-> Option[Str]` | next line without its `\n` / `\r\n`; `None` at EOF. If the last line has no newline, it still comes back as `Some` |
| `io.read_all()` | `-> Str` | the rest of stdin; `""` if already at EOF |
| `io.read_bytes(max: Int)` | `-> Option[Bytes]` | 1..max bytes; `None` at EOF. It never returns an empty `Some` |

```blink
fn main() ! IO.Read, IO.Print {
    loop {
        match io.read_line() {
            Some(l) => io.println("[{l}] {l.len()}"),
            None => break,
        }
    }
}

fn sum_stdin() -> Int ! IO.Read {
    io.read_all().lines().map(fn(l) { l.trim().to_int().unwrap_or(0) }).sum()
}
```

**Why the three ops share one handler and `@handle_all`.** If a handler mocks `read_line` and forwards `read_all`, a test reads half from the fake stream and half from the real one, and that bug is silent. Under `@handle_all`, the existing `PartialHandler` warning (§4.7.1) catches it at the `with` site with no new diagnostic. `read_bytes` must be a handler op too, not second tier. If it were second tier, it would bypass a mock that every other read respects. `Time` and `Rand` set the same precedent.

**Mocking with no handler boilerplate.** The stdlib ships `std.io.stdin_from(text: Str) -> Handler[IO.Read]`, which implements all three ops over a single cursor:

```blink
test "sums lines" {
    with stdin_from("1\n2\n\n3") {
        assert_eq(sum_stdin(), 6)
    }
}
```

Under `blink test`, an unhandled `IO.Read` reads the null device (EOF at once), so a test never hangs on a terminal. This matches `process.run`'s child-stdin rule (§4.4.8).

**LSP and errors.** `io.read_` completes only when the row grants `IO.Read`. `! IO` already grants it, so existing `! IO` code still compiles. A missing row reuses `UndeclaredEffect`, with the machine-applicable fix `add IO.Read`. Nothing new is needed in the formatter.

###### P2. Old code breaks loudly, with a targeted help line

Changing `read_line` to return `Option[Str]` is a breaking change. That is the point: today's `if l == "" { break }` is a latent bug, and a type error is the right signal. Two help lines turn the break into a one-step fix:

```
error[TypeError]: mismatched types
 --> f.bl:3:12
  |
3 |     if l == "" { break }
  |        ^^^^^^^ `l` is `Option[Str]`, compared with `Str`
  |
  = help: `io.read_line()` returns `None` at end of input; a blank line is `Some("")`
  = fix:  match io.read_line() { Some(l) => ..., None => break }
```

The same help fires on `l.len()` / `l.trim()` when `l` came from `io.read_line()` (no method on `Option[Str]`). The trigger is narrow: the receiver's type origin is the `IO.Read` op. I would not use `@deprecated`/W2000 here. A deprecation warning on a function whose name does not change cannot tell the old meaning from the new one.

###### P3. Error policy: no `Result` on the stdin ops

`io.println` does not return `Result`, and the stdin ops should not either. stdin belongs to the process. It is not a resource the program opened. An OS read failure on fd 0 (EIO, EISDIR from `< somedir`) is rare and fatal for these programs. A `Result` wrapper would add a `?` to every line of every benchmark solution, and agents would write `.unwrap()` there anyway.

- An OS error panics with `stdin read failed: <strerror> (errno N)`, and the panic output names the op.
- Invalid UTF-8 in `read_line`/`read_all` panics with `stdin is not valid UTF-8 at byte offset K; use io.read_bytes`. The help names the escape hatch, and the panic never decodes lossily without saying so.
- A program that needs to recover from errors already has `libc.read_bytes(0, n) -> Result[Bytes, Errno]` (§9.1.3.3).

**Tradeoff.** Panic-on-error is less pure than the §4.4.6 socket form (`Result[Option[Str], NetError]`). The difference is principled: a socket fails often and needs recovery, while stdin almost never fails. If the panel wants `Result`, it should wait for the post-v1 `IoError` and not use `Errno`. A bare `Errno(5)` in a diagnostic tells the user nothing.

###### P4. No lines iterator in v1; say so in the spec

v1's `Iterator[T]` is pure (§3c.1), and Blink has no `while let`. So `for l in io.lines()` cannot be typed. The spec should name two shapes:

1. Eager: `io.read_all().lines()`, which is `List[Str]`, pure afterwards, and fine for every benchmark-sized input.
2. Streaming: the `loop { match io.read_line() { ... } }` form above.

`io.lines()` stays reserved for v2 effectful iteration. If someone writes `for l in io.lines()`, the error is `error[E0505]: lines is not an operation of IO.Read`, with help `use io.read_all().lines() or a read_line loop (§3c.1)`. That points the agent to a working form and not into a guess loop. A wrapper like `read_lines()` would only spell `read_all().lines()` a second way, so I reject it (YAGNI).

###### Cross-language note

| Language | Stdin surface | What P1 takes or avoids |
|---|---|---|
| Rust | `stdin().lines()` yields `io::Result<String>` | every caller writes `.unwrap()`; P3 avoids that |
| Go | `bufio.Scanner` returns `Scan() bool` with a separate `Err()` | callers often forget to check `Err()` |
| Python | `sys.stdin.read()` / `for line in sys.stdin` | not mockable without monkeypatching; `stdin_from` fixes that |
| Rust | `read_line` returns `Ok(0)` at EOF | the same `""` ambiguity this ticket reports |

Blink's handler model is the reason to put stdin under an effect at all, so mocking stdin should be one line.

**Summary vote:** P1 + P2 + P3 + P4 together. P1 is a hard requirement. On P3, I would accept `Result`, but only with a real `IoError`, never with a bare `Errno`.

======================================================================
##### AI/ML (aiml)
======================================================================
##### AI/ML panelist — Phase A proposal (stdin, [ticket])

###### Proposal 1 (primary): `IO.Read` sub-effect, one handler op, three derived wrappers

```blink
effect IO {
    effect Print   // stdout
    effect Log
    effect Read    // stdin
}
```

Handle surface (all `! IO.Read`):

| Call | Returns | Notes |
|---|---|---|
| `io.read_line()` | `Option[Str]` | Next line without `\n` / `\r\n`; `None` at EOF. A final line with no `\n` is still `Some`. |
| `io.read_lines()` | `List[Str]` | Eager: reads to EOF, splits as `read_line` does. |
| `io.read_all()` | `Str` | Everything to EOF; `""` only for empty input. |
| `io.read_bytes(n)` | `Bytes` | Up to `n` bytes; empty `Bytes` at EOF. |

Handler ops (Str-shaped, like Print):

| Effect | Operation |
|---|---|
| `IO.Read` | `fn read_line() -> Option[Str]` |
| `IO.Read` | `fn read_bytes(n: Int) -> Bytes` |

`read_lines` and `read_all` are stdlib wrappers that loop on the op (rule 3: an op consuming a handle op's output is the same effect), so a handler that mocks `read_line` mocks all of them. Mark `IO.Read` `@handle_all` so a mock that omits `read_bytes` gets `PartialHandler`.

Common benchmark shapes:

```blink
fn main() ! IO {
    let n = io.read_line().unwrap().to_int().unwrap()
    let mut sum = 0
    for line in io.read_lines() {
        sum = sum + line.to_int().unwrap()
    }
    io.println(sum)
}
```

```blink
fn main() ! IO {
    let words = io.read_all().split_whitespace()
    io.println(words.len())
}
```

Streaming (unbounded input):

```blink
fn main() ! IO {
    loop {
        match io.read_line() {
            Some(l) => io.println(l.to_upper()),
            None => break,
        }
    }
}
```

Test mock:

```blink
fn fake_stdin(lines: List[Str]) -> Handler[IO.Read] {
    let mut i = 0
    handler IO.Read {
        fn read_line() -> Option[Str] {
            if i >= lines.len() { return None }
            i = i + 1
            Some(lines[i - 1])
        }
        fn read_bytes(n: Int) -> Bytes { Bytes.new() }
    }
}
```

**Errors: no `Result`.** An OS read error (EIO, closed fd 0) panics with `io.read_line: <errno name>`; invalid UTF-8 panics and points to `io.read_bytes`. This matches `io.println`, which returns no `Result` on EPIPE. The token cost is decisive: `Result[Option[Str], E]` forces `io.read_line()?` or a double match on every call, and `main` cannot `?` without returning `Result`. In benchmarks the error path never fires, yet every solution pays ~5-10 tokens, and models often get Option/Result nesting order wrong. Code that must recover from read errors already has `libc.read_bytes(0, n) -> Result[Bytes, Errno]`.

###### Domain reasoning

- **Learnability.** `Option[Str]`/`None` at EOF is the same contract as `TcpStream.read_line` (§4.4.6) minus the `Result`. One rule covers both: "read_line gives None at end". Python (`readline()` gives `""` at EOF vs `"\n"` for a blank line), Rust (`Ok(0)`), Go (`Scanner.Scan()==false`) all tell EOF from a blank line; models expect it. The current `""`-for-both is a trap no prior teaches.
- **Decision points.** The 95% case has two choices: `read_lines()` (line input) or `read_all()` (token input). That is the same split as Python's `sys.stdin.read()` vs `for line in sys.stdin`, which LLMs produce with high reliability.
- **Why `read_lines` is eager, not an `io.lines()` iterator.** v1 `Iterator[T]` is pure (§3c.1). A lazy stdin iterator would be the first effectful iterator and would reopen the deferred v2 vote. Eager `List[Str]` gives `for line in io.read_lines()` today, with zero new concepts and ~6 tokens. Interactive/unbounded input uses the `loop`/`match` form (~15 tokens more, because Blink has no `while let`). When v2 effectful iteration lands, `io.lines()` can be added without breaking anything.
- **Token cost.** The current workaround (an fd-0 `read_fully` loop plus manual split) is ~60-80 tokens; `io.read_all()` is 4.
- **Debuggability.** Read ops are handler-dispatched, so `--trace` records them, and a failing test can print the exact lines it was fed.

###### Proposal 2 (fallback if the panel rejects a new sub-effect)

Put the read ops directly under `IO` (granted by `! IO`, no `IO.Read`). Fewer names, but a print-only function would be allowed to read stdin, which weakens the row as documentation. Not recommended: the sub-effect costs nothing at the call site, because `! IO` still grants all.

###### Explicitly rejected

- `read_line() -> Str` plus `io.at_eof() -> Bool`: a second decision point and a TOCTOU-shaped pattern; models forget the check.
- `io.stdin()` handle object: an extra type and call, and it depends on the open method-syntax-on-handle-op ticket. Defer to the post-v1 file handles, then align `file.read_line()` with this contract.
- `read_all` returning `Result`: same reasoning as `read_line`.

###### Migration

`io.read_line()` changes `Str` to `Option[Str]`, which breaks callers. Use the 3-step dance (add alongside, migrate, remove). Callers that compare to `""` get a type error at compile time, not wrong behavior at run time, which suits AI repair loops.

======================================================================
##### MINIMALISM (min)
======================================================================
###### MIN (Minimalism) — Phase A proposal

###### M1 (recommended): one sub-effect, two handler ops, no iterator, no new error type

```blink
effect IO {
    effect Print   // stdout
    effect Log
    @handle_all
    effect Read    // stdin
}
```

| Effect | Handler op | Surface |
|---|---|---|
| `IO.Read` | `fn read_line() -> Option[Str]` | `io.read_line()` |
| `IO.Read` | `fn read_all() -> Str` | `io.read_all()` |

The rules:
- **`read_line`** returns the next line without its terminator. It strips `\n`, or `\r\n` as one terminator, the same as `TcpStream.read_line` in §4.4.6. It returns `None` only at EOF. A final line with no newline comes back as `Some(...)`, and a blank line is `Some("")`.
- **`read_all`** returns the rest of stdin byte-for-byte as `Str`, terminators kept. At EOF it returns `""`. That is not ambiguous: "nothing left" is the correct answer, and no loop depends on it.
- **No `Result`.** A read error such as `EIO` or a closed fd 0 panics with the errno text. Blink has no `IoError` in v1, and `print` has no error channel either, so stdin matches stdout. Wrapping every benchmark line in `?` against an error type that does not exist yet costs more than it gives back. Programs that need errno-level control already have `libc.read_bytes(0, n)`.
- **Invalid UTF-8** is converted lossily to U+FFFD, as §4.4 already does for env values. Raw bytes go through `libc.read_bytes` and `std.io.read_fully`, which exist today.
- **`@handle_all`**: if a test mock handled `read_line` but not `read_all`, the unhandled op would fall through and read real stdin under the mock. That is a silent mismatch, so the handler must cover both ops.
- **The parent grants the child.** `fn main() ! IO` gets stdin, so existing programs keep working.

Usage, for every pattern the benchmark needs:

```blink
fn main() ! IO {
    // line loop: EOF ends it, a blank line does not
    loop {
        match io.read_line() {
            Some(l) => io.println("[{l}] {l.len()}"),
            None => break,
        }
    }
}

fn sum_all() ! IO {
    // whole input; Str.lines() -> List[Str] already exists (§3)
    let mut total = 0
    for l in io.read_all().lines() {
        total = total + l.to_int().unwrap_or(0)
    }
    io.println(total)
}

test "mock stdin" {
    handler Feed for IO.Read {
        fn read_line() -> Option[Str] { None }
        fn read_all() -> Str { "1\n2\n" }
    }
    with Feed { sum_all() }   // prints 3
}
```

###### What I reject, and why

1. **No `io.lines()` iterator.** §3c.1 makes the v1 `Iterator[T]` pure, and it says outright that `for line in file.lines() ! IO` cannot be expressed in v1. A stdin lines iterator would need a special case that breaks that vote, or would have to read everything eagerly behind a lazy-looking name. `io.read_all().lines()` does the eager version honestly, using a method that already exists. The streaming loop is the `loop { match }` shape that §2.11 already prescribes in place of `while let`. When v2 adds effectful iteration, `io.lines()` becomes a pure stdlib addition. Nothing here blocks it.
2. **Remove `io.read_bytes(n)`** from the compiler surface (today it exists only in llms-full). `libc.read_bytes` and `std.io.read_fully` already cover byte reads with a sound row and a real error type. Keeping a third byte path adds surface and no new capability.
3. **No `read_line_or_empty` and no default-argument variant.** One way to read a line.
4. **No `IO.Stdin` name.** `Read` follows `FS.Read`, and the handle is still `io`. Also no separate `IO.ReadAll` sub-effect: one capability, one grant.

###### Interaction cost (the part people forget)

- **Buffering.** `io.read_*` buffers fd 0. The spec must say that mixing `io.read_*` with `libc.read_bytes(0, ...)` in one program gives unspecified ordering. C's stdio and Go's `bufio`-vs-`os.Stdin` have the same hazard. One sentence covers it, and it beats a design that tries to make the two coherent.
- **Breaking change.** `io.read_line()` changes from `Str` to `Option[Str]`. That is a compile error at each call site, not a silent change, so the fix is mechanical: `.unwrap_or("")` keeps the old behaviour with its known flaw. Per the bootstrap protocol this is the 3-step dance if src uses it.
- **`process.run` default.** Child stdin is the null device, so a child's `read_line()` returns `None` at once. This needs no extra spec beyond the EOF rule.

###### Cross-language note

- Python's `input()` raises `EOFError`, and `sys.stdin.read()` is the read-all form.
- Rust's `read_line` returns `Ok(0)` at EOF, which is the same blank-line trap this ticket describes. Avoid that.
- Go's `bufio.Scanner` gives a loop plus a separate error check.

Lua's `io.read("l")` returning `nil` at EOF and `io.read("a")` for everything is the closest match to M1: two forms, and that covers it.

###### M2 (fallback if the panel insists on `Result`)

`read_line() -> Result[Option[Str], Errno]` and `read_all() -> Result[Str, Errno]`. These mirror `libc.read_bytes`, and the error type can be widened to `IoError` after v1. I vote against it for v1: it doubles the call-site noise in the benchmark use case to handle failures that almost never happen, and a sound panic already meets the "every side effect has a row" rule.

**Summary vote stance:** yes to M1, which adds 1 sub-effect and 2 ops and removes 1 surface op. No to iterators, byte variants and new error types in v1.

#### Phase B — Debate

##### Lead broadcast: deduped option-space

##### Phase B — Round 1 broadcast: deduped option-space (mechanical)

Full Phase A texts, verbatim, are in the same directory: phaseA_sys.md, phaseA_web.md, phaseA_plt.md,
phaseA_devops.md, phaseA_aiml.md, phaseA_min.md. Read them all.

###### Shared by all six proposals (not listed as options)
- New sub-effect `IO.Read` under `effect IO`; handle stays `io`; `! IO` grants it.
- `read_line` gives the next line without its terminator (`\n` or `\r\n`); a final line with no
  newline is still returned; a blank line is an empty line, distinct from end of input.
- `@handle_all` applies to the stdin ops (placement varies; see facts).
- `io.read_line()`'s return type changes (breaking); old callers get a compile error.

###### Sub-questions with distinct proposals

**S1. Error channel for an OS read failure**
- S1-a: no `Result`; the op panics with a message naming the op/errno — Sys, Web, DevOps, AI/ML, Min (Min M1)
- S1-b: `Result[_, Errno]` on every read op (`read_line() -> Result[Option[Str], Errno]`) — PLT (Min M2 fallback)
- Variation: Sys and DevOps say they would accept `Result` only with a rich `IoError`, never bare `Errno`.

**S2. Input that is not valid UTF-8 (line/all reads)**
- S2-a: panic, message names the byte path — Sys, Web, DevOps, AI/ML
- S2-b: lossy conversion to U+FFFD — Min
- S2-c: `Err(Errno(EILSEQ))` — PLT (tied to S1-b)

**S3. Op set and which ops are handler primitives**
- S3-a: three primitive ops `read_line() -> Option[Str]`, `read_all() -> Str`, `read_bytes(n) -> ...` over one shared buffer — Sys, Web, DevOps
- S3-b: two primitive ops `read_line`, `read_all`; no `io.read_bytes` (bytes via `libc.read_bytes(0, n)` / `std.io.read_fully`) — Min
- S3-c: two primitive ops `read_line`, `read_bytes`; `read_all` and `read_lines` are stdlib wrappers looping on them — AI/ML
- S3-d: one primitive `read_bytes(max)`; `read_line`, `read_all`, `read_all_bytes`, `read_lines` are derived ops (bodies in the effect declaration) — PLT

**S4. `read_bytes` meaning (if kept)**
- S4-a: exactly `n` bytes, fewer only at end of input (today's compiler meaning) -> `Bytes` — Sys
- S4-b: up to `n` bytes, empty `Bytes` at end of input — Web, AI/ML; PLT same but `Result[Bytes, Errno]`
- S4-c: `Option[Bytes]`, 1..max bytes, `None` at end of input, never empty `Some` — DevOps
- S4-d: not an `io` op (removed) — Min

**S5. Reading every line**
- S5-a: no lines helper; spec names `io.read_all().lines()` (eager) and the `loop { match io.read_line() }` form — Sys, DevOps, Min
- S5-b: eager `io.read_lines() -> List[Str]` — AI/ML, PLT
- S5-c: lazy `io.lines() -> Iterator[Str] ! IO.Read` built as `iter.from_fn(fn() { io.read_line() })` — Web
- Variation (DevOps): a targeted diagnostic for `io.lines()` pointing to the two v1 forms.

**S6. Mock helper**
- S6-a: std ships a text-fed `Handler[IO.Read]` — Web (`std.testing.stdin(text)`), DevOps (`std.io.stdin_from(text)`), PLT (`std.testing.stdin_from(text)`)
- S6-b: no helper; users write the handler — Sys, AI/ML, Min (examples only)
- Variation: name and module.

**S7. Extra normative rules proposed (each by the named panelist; adopt or drop)**
- S7-1 No line-length limit (today's runtime splits lines at 4096 bytes) — Sys
- S7-2 Mixing `io.read_*` with `libc.read_bytes(0, ..)` / `std.io.read_fully(0, ..)` gives unspecified order — Sys, Min
- S7-3 `Str.lines()` is specified to match repeated `read_line` (accepts `\r\n`, no empty last item after a final terminator) — Sys; PLT states the same for `read_lines`
- S7-4 Composition law: `read_all()` == concatenation of each `read_line()` plus its terminator — PLT
- S7-5 Under `blink test`, an unhandled `IO.Read` reads the null device (immediate end of input) — DevOps
- S7-6 `read_all` may size its buffer with `fstat` on a regular file (performance note) — Sys

**S8. Migration diagnostic for old `read_line` callers**
- S8-a: plain type error (no special help) — Sys, AI/ML, PLT (PLT mentions a fix-it)
- S8-b: targeted help + fix `match io.read_line() { Some(l) => ..., None => break }` when the value comes from `io.read_line()` — DevOps
- S8-c: machine-applicable fix `io.read_line() ?? ""` (keeps old behaviour) — Web; Min suggests `.unwrap_or("")` as the manual fix

###### Facts from the codebase (moderator-surfaced, no position implied)
- F1 §3c.1 (sections/03c_protocols.md:199): "The v1 iterator is pure — an adapter closure that performs
  effects is a v1 error ... `for line in file.lines() ! IO` is not expressible through the iterator protocol in v1."
- F2 §3c (03c_protocols.md:139): "`for v in ch { ... }` is exactly `for v in iter.from_fn(fn() { ch.recv() }) { ... }`
  — one `recv()` per iteration, and the loop ends on the first `None`." `from_fn` iterators are one-shot (:169).
- F3 §4.7.1 (04_effects.md:2075-2077): "`@handle_all` attaches to an effect declaration. It covers the
  sub-effects of the effect too. The stdlib marks `Rand` (§4.4.7) and `Time` (§4.3), and no other effect."
  "A derived operation never counts ... A handler for a sub-effect counts only the operations of that
  sub-effect." The spec does not say whether `@handle_all` may sit on a nested sub-effect alone. Marking
  `IO` itself would also cover `Print` and `Log`.
- F4 §4.7.1 (04_effects.md:1919,1935): primitive op = no body in the effect declaration; derived op = has a
  body; an omitted derived op's body runs at the call site against the innermost handler.
- F5 §3 (03_types.md:161) `fn lines(self) -> List[Str]` exists; its treatment of `\r\n` and a trailing
  terminator is not stated there (llms-full.md:554 says "Split by newlines").
- F6 §4.4.3 env (04_effects.md:791): "Non-UTF-8 values are lossy-converted to UTF-8 or returned as None."
- F7 src/lsp.bl reads headers with `io.read_line` then the body with `io.read_bytes` (mixed use, one stream).

###### Instructions for this round
Respond to the option-space: which options you support, which you oppose and why, and any concession
or merge you accept. You may revise your own position. Do not invent a new option unless needed to
resolve a conflict; if you do, state it concretely. Keep it under ~400 words. End with either
"STABLE, ready to vote" or "NOT STABLE" plus what you still need debated.

======================================================================
##### SYSTEMS (sys)
======================================================================
##### SYS: Phase B round 1

**S1: a (panic).** This is a hard line until IoError exists. stdout has no error channel either. Bare `Errno` in a benchmark loop adds a `?` and makes `main` return `Result`. Every agent then writes `.unwrap()`, which panics anyway with less context. Code that needs to recover already has `libc.read_bytes(0, n) -> Result[Bytes, Errno]`.

**S2: a (panic).** I oppose b. F6 (env) covers small config values. Stdin is bulk data, and lossy decoding there corrupts payloads with no signal. That is the silent-wrong-result class this language rejects (E0301 stance). The panic message names the byte path.

**S3: I change to d (PLT's shape) and drop the Result.** One primitive `read_bytes(max: Int) -> Bytes` plus derived `read_line() -> Option[Str]` and `read_all() -> Str`. This is stronger than my three-primitive S3-a:
- A mock that answers only the primitive makes every view agree, by construction (F4). My S3-a depended on `@handle_all` to get that.
- My earlier objection, a line buffer living in wrapper state, does not apply. The derived bodies need no carried state: they may pull 1 byte at a time, which is slow only under a mock. The default runtime handler answers every derived op natively over one shared buffer, so production code pays nothing.
- Keep `@handle_all` on the nested `Read` (the spec must allow that placement, F3). Do not put it on `IO`: that would make every existing Print-only handler also implement `print_no_nl`, which is collateral breakage.
- Drop `read_all_bytes` and `read_lines` as derived ops (YAGNI). I accept `read_lines` if the vote wants it, since it costs one body.

I oppose b (removing `io.read_bytes`). Binary stdin must go through the same buffer as the line reads. If it does not, S7-2 turns from an edge case into the common case, and src/lsp.bl (F7) shows that mixed use is real. I oppose c because two primitives bring back the partial-mock split.

**S4: b (up to n, empty at EOF).** This follows from S3-d: the primitive is read(2)-shaped, so "exactly n" becomes `std.io.read_fully`'s job. I accept c (`Option[Bytes]`) as a close second. a is gone with S3-d.

**S5: a. I oppose c strongly.** `iter.from_fn(fn() { io.read_line() })` is an adapter closure that performs effects, which F1 calls a v1 error. It would be the first effectful iterator, under a type that promises re-traversal, and it would decide the deferred v2 vote by accident. b is acceptable but redundant.

**S6: a.** I change sides. Under S3-d the helper answers one op and is correct by construction. Name it `std.testing.stdin_from(text: Str)`.

**S7:**
- 1, 2, 3 and 4: adopt. S7-4 holds by construction under S3-d.
- 5: adopt. A test that blocks on a tty is a hang in CI.
- 6: I withdraw it. It is an implementation note, not spec text.

**S8: b. I oppose c.** A machine-applicable `?? ""` re-installs the exact bug this ticket reports, under a fix label that agents apply without reading.

STABLE, ready to vote

======================================================================
##### WEB/SCRIPTING (web)
======================================================================
##### Web/Scripting, Phase B round 1

**S1: support S1-a (panic), oppose S1-b.** `Result[Option[Str], Errno]` makes every benchmark one-liner need `main -> Result` plus `?`, and agents will just write `.unwrap()`, which is a panic with more steps. A bare `Errno(5)` also tells a JS/Python dev nothing. If `Result` ever comes, it should come with a real `IoError` (I agree with Sys/DevOps).

**S2: support S2-a (panic that names `io.read_bytes`), oppose S2-b.** F6 (env lossy) is a weak precedent. An env var is metadata, while stdin is the program's data. Silently writing U+FFFD into it gives a green build with a wrong answer. That is the E0301 failure mode.

**S5: I concede. I drop S5-c (`io.lines()`) and move to S5-a.** F1 settles it: v1 iterators are pure, and my `from_fn` form would be the first effectful iterator. I also add DevOps's targeted diagnostic for `io.lines()`, because that is exactly what a Python dev (`for line in sys.stdin`) will type first. The help must show both v1 forms. I don't object to S5-b, but `read_all().lines()` is the same thing with no new name, so I lean against it.

**S3 + S4: I keep S3-a, and change S4 to S4-a (exact `n`, fewer only at EOF).** F7 decides it. LSP-style "header line, then a body of Content-Length bytes" is the real use of mixed reads. With "up to n", every caller has to write a short-read loop, a classic Node `data`-event bug. With exact-n, the obvious code is correct. I oppose S3-b and S4-d. Under S7-2, `libc.read_bytes(0, ..)` after `io.read_line()` is unspecified, so removing `io.read_bytes` leaves a mixed text+bytes reader with no correct path. S3-d (one byte primitive, derived views) is principled. Without its `Result`, I would accept it as a second choice, but only if S6-a ships. Otherwise every hand-written mock has to slice bytes when it wants to feed lines.

**S6: support S6-a strongly.** "Mock stdin in one line" is the selling point of putting stdin under an effect. Under S3-a with `@handle_all`, a hand-written mock has three ops of boilerplate, so the helper is not optional. I have no strong view on the name: `std.testing.stdin_from(text)` is fine.

**S7:** adopt S7-1 (no line limit; the 4096 split is a real bug), S7-2, S7-3 (so the two idioms agree), and S7-5 (a test that hangs on a tty is the worst DX there is). Adopt S7-4 as a stated law. S7-6 should be a non-normative note.

**S8: I concede to S8-b and drop my machine-applicable `?? ""`.** That fix restores exactly the bug the ticket reports, and auto-applying it would keep the bug in every migrated program. Show `?? ""` at most as a second help line, and don't make it machine-applicable.

**@handle_all placement (F3):** the spec should allow `@handle_all` on a nested sub-effect, which is what Min, DevOps and PLT wrote. Marking `IO` itself would wrongly force print mocks to implement `log`.

STABLE, ready to vote.

======================================================================
##### PLT (plt)
======================================================================
##### PLT — Phase B round 1

**S1 (error channel): I concede S1-a (panic), with conditions.** A panic is sound because it diverges, so the op's type does not lie about the values it returns. `io.println` already panics on a write failure, so stdin matches stdout. I agree that a bare `Errno` is a weak type. Conditions: the spec states the panic exactly (it names the op and the errno), and it names `libc.read_bytes(0, n) -> Result[Bytes, Errno]` as the path for code that must recover. I withdraw S1-b and S2-c.

**S2 (invalid UTF-8): S2-a (panic).** I oppose S2-b. A lossy conversion changes data with no signal, so the build is green and the output is wrong. F6 (env) is a lookup of one value. A stream should not copy that rule.

**S3 (op set): I accept S3-a, merged with S6-a and S7-4.** Three primitive ops plus `@handle_all` is sound: a mock must answer every view, so no view can fall through to the real fd 0. The remaining risk is a mock whose views disagree. Two items close it. (1) S7-4 is a stated law that every `IO.Read` handler must keep. (2) The std helper (S6-a) keeps the law, so most users never write the three ops. I drop my single-primitive design. It is minimal, but S3-a plus the helper gives the same safety and lets the default handler read lines natively.
- **Oppose S3-b.** F7: src/lsp.bl reads lines and then bytes from one stream. S7-2 makes `libc.read_bytes(0, ..)` after a buffered `io.read_*` unspecified. With no `io.read_bytes`, the LSP pattern has no specified form. S3-b and S7-2 cannot both hold.
- **Oppose S3-c as written.** If `read_all` loops over `read_line`, it loses the terminators (`\r\n` versus `\n`, and whether the input ends with a newline), so `read_all` is not byte-exact. That is acceptable only if `read_all` is built from `read_bytes`.

**S4 (`read_bytes`): S4-c first, S4-b also acceptable.** With `Option[Bytes]`, the type carries the end-of-input signal, the same rule as `read_line`. S4-a (exact n) belongs in `std.io.read_fully`. Whichever form wins, the spec must say what `n <= 0` does (I propose a panic).

**S5 (every line): S5-a.** I drop my `read_lines`; it duplicates `read_all().lines()` once S7-3 holds. **I strongly oppose S5-c.** It breaks F1: `Iterator[T]` would carry a hidden `IO.Read` effect, and copying or re-running the iterator reads different data. F2 does not support it, because the Channel form is a `for`-loop desugar that never escapes as a first-class value, and `io.lines()` returns one. I support DevOps's targeted diagnostic for `io.lines()`.

**S6: S6-a.** I do not mind the name. `std.testing.stdin(text)` is fine.

**S7:** I support 1, 2, 3, 4 (as a handler obligation), and 5. S7-5 is the same test-isolation argument as the null device for `process.run` children. I oppose S7-6 as normative text. It is a detail of how the runtime works and belongs in docs/build/, not in sections/.

**S8: S8-b.** I oppose making S8-c machine-applicable. `?? ""` brings back the exact bug this ticket reports, an infinite loop or a stop at the first blank line. A fix-it must not insert a known bug. It may appear as a help line, but not as the applied fix.

**One spec gap remains (F3).** `@handle_all` on a nested sub-effect needs a sentence. Marking `IO` itself would wrongly cover Print and Log. I propose: "`@handle_all` may mark a sub-effect; it then covers only that sub-effect."

STABLE, ready to vote. The F3 sentence should be on the ballot.

======================================================================
##### DEVOPS/TOOLING (devops)
======================================================================
##### DevOps/Tooling — Phase B round 1

**S1: support a (panic); oppose b.** PLT says a panic "hides an effect the row does not show". It does not hide one. The row still says `IO.Read`, and a panic is not an effect in Blink: `unwrap` and index-out-of-bounds are not in rows either. `Result[_, Errno]` gives the error output `Err(Errno(5))`, which tells the user nothing. I hold my Phase A position: I accept `Result` only with a real `IoError`.

**S2: support a; oppose b.** The env precedent (F6) is about metadata. Stdin is the program's input data. A U+FFFD swap is a green build that gives wrong output, with no diagnostic anywhere. The panic text names `io.read_bytes`, so the user knows the fix.

**S3: support a or d; oppose b and c.**
- **Oppose b (drop `io.read_bytes`).** F7: `src/lsp.bl` reads headers with `io.read_line` and then the body with `io.read_bytes`, on one stream. Under S3-b, the LSP must switch to `libc.read_bytes(0, ..)` after `io.read_line`, and S7-2 (which Min also proposes) makes that order unspecified. Our own language server would rest on unspecified behaviour.
- **Oppose c.** `read_all` built from `read_line` loses each terminator (`\r\n` versus `\n`, final newline or none), so it cannot be byte-exact.
- **Merge I accept: S3-d without S1-b.** One primitive `read_bytes(max)` and derived `read_line` / `read_all` gives one consistent stream by construction. Under a hand mock, the W0545 warning for an omitted primitive is the correct diagnostic. S6's helper means users never fake bytes by hand. Cost: under a mock, `--trace` shows byte-sized `read_bytes` calls, which is noisy but correct. If the panel ties S3-d to `Result`, I go back to S3-a.

**S4: c first, b acceptable.** `max > 0` makes empty `Bytes` an unambiguous end-of-input signal, so b is not the blank-line trap. c still matches `read_line`'s `None`. Oppose a: the exact-n read is `std.io.read_fully`, and the primitive must allow short reads.

**S5: a; oppose c; b only as sugar.** S5-c puts an `IO.Read` call inside a pure `Iterator` closure, which F1 rules out. Its first user would get a v1 effect error from inside the stdlib. If the majority wants `read_lines`, define it as exactly `read_all().lines()` under S7-3, so the two forms cannot drift. Keep my targeted help for `io.lines()`.

**S6: a.** Name: `std.testing.stdin_from(text: Str)` (PLT's). Test helpers belong in `std.testing`.

**S7: adopt 1, 2, 3, 4, 5; drop 6.** S7-6 describes how the runtime is built, not what a program sees, so it belongs in a codegen note, not in `sections/`. S7-5 keeps `blink test` from hanging on a terminal, and CI depends on that.

**S8: b; oppose c as machine-applicable.** `io.read_line() ?? ""` keeps the bug exactly: the loop still stops at the first blank line, or never ends at end of input. `blink migrate` must not apply a fix that keeps a known bug in place. Show `?? ""` as a manual note under the S8-b help, never as an automatic fix.

STABLE, ready to vote.

======================================================================
##### AI/ML (aiml)
======================================================================
##### AI/ML — Phase B round 1

**S1: support S1-a (panic).** Oppose S1-b. With bare `Errno`, every benchmark line pays a `?` and `main` must return `Result`, and models will write `.unwrap()` there anyway. Five of six panelists agree. If `IoError` arrives later, a `try_read_*` family can be added without breaking anything.

**S2: support S2-a (panic that names `io.read_bytes`).** Oppose S2-b. Lossy U+FFFD decoding gives a green run with wrong output, which is the worst case for an agent's debug loop because nothing points at the cause. A panic names the byte offset and the fix. The env precedent (F6) covers values the program does not own. Stdin is data, and there corrupting it silently costs more.

**S3: I concede to S3-a (three primitive ops over one shared buffer, `@handle_all`).** PLT is right that deriving `read_all` from `read_line` loses `\r\n` and breaks byte-exactness. My S3-c has that flaw, so I drop it. Oppose S3-d: a mock author has to fake byte chunks and the `Result` plumbing, which is far more tokens than a line-level mock, and it is tied to S1-b. Also needed: a spec sentence that `@handle_all` may sit on a nested sub-effect (F3).

**S4: I move to S4-a (exactly `n` bytes, fewer only at EOF, empty at EOF).** It keeps the compiler's current meaning, it is what src/lsp.bl needs for a Content-Length body (F7), and it matches Python's buffered `sys.stdin.buffer.read(n)`, the prior models carry. Oppose S4-c: an `Option` layer over a value that already has an empty state is a second EOF signal.

**S5: I concede to S5-a (no helper).** `io.read_all().lines()` costs about 3 tokens more than `io.read_lines()` and avoids two ways to do one thing. This depends on S7-3. Without it, `read_all().lines()` and a `read_line` loop could give different sequences, and that trap is worse. Strongly support DevOps's targeted diagnostic for `io.lines()`: models will try that name first (Rust, Python), and a help line pointing at the two v1 forms turns a guess loop into one repair. Oppose S5-c: it overturns the §3c.1 pure-iterator vote (F1) through a side door.

**S6: I move to S6-a (std ships a text-fed handler).** One call, `with stdin_from("1\n2\n") { ... }`, against a 3-op `@handle_all` handler of about 15 lines. Under S3-a, a hand mock has to keep three ops coherent over one cursor, which is easy to get wrong. I have no strong view on the name. My preference is `std.testing.stdin_from(text)`.

**S7:** adopt 1, 2, 3 (required), 4 and 5. S7-5 matters a lot for agents: a test that blocks on a tty hangs the harness with no output. Drop S7-6 from normative text. It is an implementation note, and the spec does not carry those.

**S8: support S8-b (targeted help, not machine-applicable).** Oppose S8-c as a machine-applicable fix: `?? ""` silently brings back the exact bug this ticket fixes, and an auto-fixer would apply it everywhere. It can stay as a second, manual help line at most.

STABLE, ready to vote.

======================================================================
##### MINIMALISM (min)
======================================================================
###### MIN — Phase B round 1

**S1 error channel: S1-a (panic).** Unchanged. I drop my M2 fallback. If the panel wants `Result`, it should wait for a real `IoError`, as Sys and DevOps say. A bare `Errno` adds `?` to every line and gives a worse message than the panic text.

**S2 invalid UTF-8: I concede to S2-a (panic).** My U+FFFD rule leaned on the env rule (F6), but env values come from outside and are read-only metadata. Stdin is the program's data. Silent replacement gives a green build and corrupt data, which goes against E0301. The panic message must name `io.read_bytes`.

**S3 op set: I concede to S3-a (three primitive ops, one buffer).** F7 breaks my S3-b. src/lsp.bl reads headers with `read_line`, then a Content-Length body, from one stream. Under S3-b, that body read would have to be `libc.read_bytes(0, ..)` after a buffered `io.read_line`, and my own S7-2 makes that unspecified. A byte op over the shared buffer is therefore foundational: the language cannot do this today. I oppose two alternatives:
- S3-c: `read_all` built from `read_line` loses `\r` and the final terminator, so `read_all` is no longer byte-exact.
- S3-d: it fixes `Result` in the primitive, and every mock must fake bytes. Sys's point holds: mocks want lines. PLT's composition goal comes for free under S3-a if S7-4 is a normative rule.

**S4 `read_bytes` meaning: S4-a (exactly n, fewer only at EOF), with S4-b acceptable.** S4-a is today's meaning, so `read_bytes` needs no migration, and it is what a Content-Length read needs, with no short-read loop in user code. I oppose S4-c: `Option[Bytes]` adds a third EOF convention to a three-op effect.

**S5 every line: S5-a.**
- I oppose S5-c. It breaks §3c.1 (F1), and it is the exact case that rule names. The Channel precedent (F2) is not an IO effect inside a pure carrier.
- I oppose S5-b. `read_lines()` is `read_all().lines()` spelled a second way.
- I support DevOps's targeted diagnostic for `io.lines()`. It costs a diagnostic, not surface.

**S6 mock helper: I accept S6-a, as one stdlib function.** With three `@handle_all` ops and a shared cursor, a correct hand mock is about 25 lines, and getting the cursor right is the hard part. This is library code, not language surface. One name only; I lean to `std.testing.stdin(text)`.

**S7 extra rules:**
- S7-1 adopt. A silent 4096-byte split is a correctness bug.
- S7-2 adopt.
- S7-3 adopt. It is needed so the two v1 line forms agree.
- S7-4 adopt.
- S7-5 adopt, but as a `blink test` runner rule, not effect semantics.
- S7-6 drop. It is an implementation note, not spec text.

**S8 migration: S8-b (help line, no machine-applicable fix).** I oppose S8-c and withdraw my own `.unwrap_or("")` advice. A machine fix that keeps the old behaviour puts the blank-line bug back into every caller automatically. The help should teach the `match`, and a person should apply it.

**Placement fact (F3):** the spec must allow `@handle_all` on a sub-effect and put it on `IO.Read` only. Marking `IO` would wrongly force Print and Log handlers to implement every op.

Net change from my Phase A: I now support S3-a, S4-a and S2-a. The remaining splits (S1 PLT alone, S4-a vs S4-b, S6) can be decided by a vote.

STABLE, ready to vote

#### Phase C — Silent vote

##### Lead broadcast: ballot

##### Phase C — Silent vote ballot ([ticket] stdin)

Final positions are frozen. All six round-1 replies are in this directory (phaseB_r1_<name>.md).
Vote alone; do not message other panelists. Options below are those still held by at least one
panelist after round 1. Options their proposers withdrew are listed as withdrawn.

For EACH question give:
1. **Vote** — option label (or adopt/drop)
2. **Reasoning** — 2-4 sentences from your domain
3. **Concern** — one sentence on what could go wrong with the option you expect to win

Write your full ballot to `phaseC_<yourname>.md` in this directory, then reply "saved" to team-lead.

---

**Q1. Error channel for an OS read failure (S1)**
- a: no `Result`; the op panics
- b: `Result[_, Errno]` on every read op
- Q1-sub (PLT condition): the spec states the panic exactly (names the op and the errno) and names
  `libc.read_bytes(0, n) -> Result[Bytes, Errno]` as the path for code that must recover — adopt/drop

**Q2. Input that is not valid UTF-8 on line/all reads (S2)**
- a: panic, message names `io.read_bytes`
- b: lossy conversion to U+FFFD
- (c `Err(EILSEQ)` withdrawn by PLT)

**Q3. Op set (S3)**
- a: three primitive ops `read_line() -> Option[Str]`, `read_all() -> Str`, `read_bytes(n) -> Bytes`
  over one shared buffer
- d: one primitive `read_bytes(max: Int) -> Bytes` (no `Result`); `read_line() -> Option[Str]` and
  `read_all() -> Str` are derived ops (bodies in the effect declaration); the default runtime handler
  answers each derived op natively over one shared buffer (Sys's statement)
- (b withdrawn by Min; c withdrawn by AI/ML)

**Q4. `read_bytes` meaning (S4)**
- a: exactly `n` bytes, fewer only at end of input, empty `Bytes` at end of input
- b: up to `n` bytes, empty `Bytes` at end of input
- c: `Option[Bytes]`, 1..n bytes, `None` at end of input, never an empty `Some`
- Q4-sub (PLT): `n <= 0` panics — adopt/drop

**Q5. `@handle_all` placement (F3)**
- Sentence (PLT): "`@handle_all` may mark a sub-effect; it then covers only that sub-effect." The stdlib
  marks `IO.Read`, not `IO`. — adopt/reject

**Q6. Reading every line (S5)**
- a: no lines helper; the spec names `io.read_all().lines()` and the `loop { match io.read_line() }` form
- b: eager `io.read_lines() -> List[Str]`
- c: lazy `io.lines()` iterator
- Q6-sub (DevOps): a targeted diagnostic for `io.lines()` whose help shows both v1 forms — adopt/drop

**Q7. Mock helper (S6)**
- a: std ships a text-fed `Handler[IO.Read]`
- b: no helper
- Q7-name (if a): `std.testing.stdin_from(text: Str)` / `std.testing.stdin(text: Str)` /
  `std.io.stdin_from(text: Str)`

**Q8. Extra normative rules (S7) — adopt/drop each**
- S7-1 No line-length limit
- S7-2 Mixing `io.read_*` with `libc.read_bytes(0, ..)` / `std.io.read_fully(0, ..)` gives unspecified order
- S7-3 `Str.lines()` matches repeated `read_line` (accepts `\r\n`, no empty last item after a final terminator)
- S7-4 Composition law: `read_all()` equals the concatenation of each `read_line()` plus its terminator,
  as an obligation on every `IO.Read` handler
- S7-5 Under `blink test`, an unhandled `IO.Read` reads the null device (immediate end of input)
  (Min: as a `blink test` runner rule, not effect semantics — say which placement you want)
- (S7-6 withdrawn by Sys)

**Q9. Migration diagnostic for old `read_line` callers (S8)**
- a: plain type error
- b: targeted help with the `match io.read_line() { Some(l) => ..., None => break }` form, not
  machine-applicable
- c: machine-applicable fix `io.read_line() ?? ""`
- Q9-sub: `?? ""` may appear as a second, manual (not machine-applicable) help line — adopt/drop

======================================================================
##### SYSTEMS (sys)
======================================================================
##### Phase C ballot: SYS

**Q1: a. Q1-sub: adopt.**
Reasoning: stdin read failures (EIO on a tty that hung up, EISDIR) almost never happen. A bare `Errno` makes every benchmark loop pay a `?` and forces `main` to return `Result`, and agents then write `.unwrap()`, which panics with less context than a spec'd panic. stdout has no error channel, and stdin should match it. The sub-clause gives code that must recover a clear, already-specified path.
Concern: a long-running filter that should survive a transient error has to drop down to `libc.read_bytes`, and so loses the shared buffer (see S7-2).

**Q2: a.**
Reasoning: F6 (lossy env) covers small config values. Stdin is bulk payload, and changing it silently is the silent-wrong-result class that the E0301 stance rejects. A panic that names `io.read_bytes` points to a byte-exact path with zero cost.
Concern: a tool that runs on mixed-encoding logs crashes where Python would carry on. The message must give the byte offset so that the fix is obvious.

**Q3: d.**
Reasoning: one primitive makes every view consistent under a mock by construction (F4). That is a type-level guarantee, not a warning. In production, the default handler answers each derived op natively over one buffer, so the cost model is the same as a, a direct runtime call per op. A slow 1-byte-pull derived body runs only under a mock.
Concern: a user handler that overrides `read_line` natively but not `read_all` can break the composition law. S7-4 must make that an explicit obligation.

**Q4: b. Q4-sub: adopt.**
Reasoning: under d the primitive matches read(2), and "exactly n" belongs to `std.io.read_fully`. An empty `Bytes` at EOF is the convention every systems programmer already knows. `n <= 0` must panic. Otherwise `read_bytes(0)` returns empty `Bytes`, which reads as EOF, and a loop on a computed length exits early with no signal.
Concern: callers who expect today's "exactly n" meaning (src/lsp.bl:52) get short reads on pipes. The migration must move them to `read_fully`.

**Q5: adopt.**
Reasoning: marking `IO` would force every existing Print-only handler to also implement `print_no_nl`, which is collateral breakage. Scoping the mark to the sub-effect states exactly the consistency requirement and nothing more.
Concern: none of substance. The checker must count only the sub-effect's primitives.

**Q6: a. Q6-sub: adopt.**
Reasoning: c is an effectful `from_fn` closure, which F1 calls a v1 error, and it would decide the deferred v2 vote by accident. b is the same as `read_all().lines()` under a second name. A targeted diagnostic is cheap and keeps agents out of a guess loop.
Concern: if b wins, the spec must define `read_lines` as exactly `read_all().lines()`, so that S7-3 governs both.

**Q7: a. Name: `std.testing.stdin_from(text: Str)`.**
Reasoning: under d the helper answers one primitive and is correct by construction. It belongs with test tooling, not production io.
Concern: if users read the helper's byte-slicing body as the reference for the semantics, the copy cost per read is O(n²) on large fixtures. That is fine for tests; just don't copy it into production code.

**Q8:**
- S7-1: adopt. Today's 4096-byte split is a silent corruption bug.
- S7-2: adopt. It is the honest statement of a buffered fd, the same as C stdio and Go bufio.
- S7-3: adopt. One line-splitting rule across the language.
- S7-4: adopt, as an obligation on every handler. It holds by construction for derived bodies.
- S7-5: adopt, as a `blink test` runner rule. It belongs to the runner's process setup, not to effect semantics.

Concern: S7-2 leaves byte-exact code that also needs to recover from errors with no good path until IoError arrives.

**Q9: b. Q9-sub: drop.**
Reasoning: `?? ""` brings back the exact blank-line/EOF bug this ticket exists to remove. Even as a manual help line, agents copy the shortest fix they are shown. The targeted `match` help is the correct one-step fix.
Concern: the targeted trigger (type origin is the `IO.Read` op) may miss cases where the value is passed through a `let` and a function call first. In those cases the plain type error must still read clearly.

======================================================================
##### WEB/SCRIPTING (web)
======================================================================
##### Phase C ballot: Web/Scripting

**Q1. Vote: a (panic). Q1-sub: adopt.**
Reasoning: In a script, a read error on stdin is fatal anyway. A `Result` adds `?`, a `main -> Result` and a nested Option/Result on 100% of calls to cover a case that almost never fires, and agents will paper over it with `.unwrap()`. The sub-rule gives anyone who needs recovery a documented door, so nobody has to go looking for it.
Concern: if the docs do not show `libc.read_bytes(0, n)` next to the panic rule, people will write long-running daemons that panic on EIO.

**Q2. Vote: a (panic, names `io.read_bytes`).**
Reasoning: Silent U+FFFD gives a green build with wrong output, which is the worst kind of bug for a newcomer to chase. A loud panic that names the fix is a 30-second detour.
Concern: CSV/log inputs that are mostly UTF-8 with a stray Latin-1 byte will panic. Users must learn the bytes path, so the message has to give the byte offset.

**Q3. Vote: d (one byte primitive, derived `read_line`/`read_all`, native default handler).**
Reasoning: In round 1 I took d as my second choice if the `Result` was dropped, and it now is. With a native default handler there is no speed cost, and a hand-written mock needs one op, not three, which beats a's boilerplate. Views of one stream cannot disagree, so the composition law holds by construction. With the Q7 helper, almost nobody writes a byte-level mock by hand.
Concern: a user who writes a line-based mock by hand (overriding only `read_line`) gets surprising results from `read_all`. The W0545/PartialHandler message must explain the primitive clearly.

**Q4. Vote: a (exactly `n`, fewer only at EOF). Q4-sub: adopt.**
Reasoning: Read a header line, then read exactly Content-Length bytes: with a, the obvious code is correct. With b, everyone has to write a short-read loop. Panicking on `n <= 0` keeps "empty `Bytes` means EOF" unambiguous.
Concern: under d, the primitive is exact-n, so a hand-written mock must also honor exact-n. The helper should do it right, so people copy a correct example.

**Q5. Adopt.**
Reasoning: marking `IO` would force every print-capture mock to also implement stdin and log, which is pure boilerplate. Scoping the mark to `IO.Read` is what any reader expects.
Concern: none of note. The spec just needs to say what happens when both a parent and a child carry the mark.

**Q6. Vote: a. Q6-sub: adopt.**
Reasoning: v1 iterators are pure (F1), so `io.lines()` is out. `read_all().lines()` covers the benchmark case with no new name. The diagnostic matters, because `for line in io.lines()` is the first thing a Python dev types.
Concern: newcomers may not find the streaming `loop { match }` form, so the spec and `blink llms` must show it next to `read_line`.

**Q7. Vote: a. Name: `std.testing.stdin_from(text: Str)`.**
Reasoning: one-line stdin mocking is the reason to put stdin under an effect. It belongs in `std.testing` with the other mock controllers, and `_from` reads clearly as "fed from this text".
Concern: the helper must implement exact-n `read_bytes` and the `\r\n` rules exactly, or tests will pass against a mock that behaves unlike real stdin.

**Q8.**
- S7-1: adopt. The 4096-byte line split is a silent data-corruption bug.
- S7-2: adopt. One sentence prevents a classic buffered-vs-raw ordering trap.
- S7-3: adopt. The two idioms in Q6-a must give the same lines, or users will get off-by-one-empty-line bugs.
- S7-4: adopt. Under d it holds for the derived ops by construction. As an obligation, it binds handlers that override a derived op.
- S7-5: adopt, as a `blink test` runner rule (Min's placement). It is tooling behavior, not effect semantics, and a test that hangs waiting on a tty is the worst DX there is.
Concern: S7-5 can hide a missing mock. A test that forgot `stdin_from` sees empty input and may pass by accident.

**Q9. Vote: b. Q9-sub: adopt.**
Reasoning: the targeted help teaches the correct EOF pattern at the moment of breakage. `?? ""` restores the reported bug, so it may appear only as a manual second line, for people who knowingly want the old behavior.
Concern: agents in repair loops may pick the `?? ""` line because it is the shorter edit, and keep the bug. The `match` line must come first.

======================================================================
##### PLT (plt)
======================================================================
##### PLT — Phase C ballot

**Q1. Vote: a (panic). Q1-sub: adopt.**
Reasoning: A panic diverges, so the op's return type stays true. Every value it returns is a real line or a real `None`. This matches `io.println`, which has no error channel either. The condition makes sure the panic is documented and that a typed path to recover exists (`libc.read_bytes`), so the choice to panic is honest and not hidden.
Concern: When `IoError` arrives after v1, people will want a `Result` form, and because Blink has no overloading, adding it means a second name (or a breaking change).

**Q2. Vote: a (panic).**
Reasoning: `Str` must be valid UTF-8. A lossy conversion meets that by quietly changing the data, which produces a green build with wrong output. A panic that names `io.read_bytes` makes the program fail loudly and points to the exact path.
Concern: The panic message must give the byte offset, or it will be hard to debug on large input.

**Q3. Vote: d (one primitive, derived line/all ops). I also accept a.**
Reasoning: With d, all views agree by construction. A mock that answers only `read_bytes` answers `read_line` and `read_all` through the same stream (§4.7.1 derived-op rule), so the S7-4 rule is a theorem, not an obligation that each handler author must keep. `@handle_all` then needs only one primitive, so a partial handler cannot exist. The default handler still answers each derived op natively, so there is no runtime cost. Option a is sound only together with S7-4 and the std helper, and I accept it on those terms.
Concern: If a wins, a hand-written mock can give views that disagree and still compile clean. S7-4 then exists only as text in the spec.

**Q4. Vote: b (up to n, empty `Bytes` at end of input). Q4-sub: adopt (`n <= 0` panics).**
Reasoning: b matches `libc.read_bytes` and the primitive signature in Q3-d, which gives the smallest primitive contract a mock must meet. Once `n > 0` is required, an empty result means only end of input, so the sentinel cannot be read two ways. I would also accept c, which puts the same fact in the type.
Concern: A caller who expects option a's "exactly n" will treat a short read as a full one. The spec must point to `std.io.read_fully` for that case.

**Q5. Vote: adopt.**
Reasoning: Without the sentence, the only spec-legal mark is on `IO`, which would wrongly force every Print/Log handler to be total. The rule is a conservative extension: it changes no existing program, and the mark stays scoped to exactly one resource.
Concern: The compiler must check sub-effect marks when a handler is written for the parent `IO`. That is, it must count the `Read` ops in a `handler IO { ... }`.

**Q6. Vote: a. Q6-sub: adopt.**
Reasoning: c puts a hidden effect inside the pure, restartable `Iterator` (§3c.1), so it is unsound in v1, and the Channel `for` desugar is not a value that escapes. b duplicates `read_all().lines()` once S7-3 holds. The diagnostic turns the most likely wrong guess into a fix.
Concern: Agents will still write `io.lines()` often until v2. The quality of the diagnostic carries the whole load.

**Q7. Vote: a. Name: `std.testing.stdin_from(text: Str)`.**
Reasoning: A mock should not have to restate the stream semantics by hand. The helper is the reference handler that keeps S7-4. It belongs in `std.testing`, because it is a test fixture and not part of the I/O surface.
Concern: If the helper takes only `Str`, binary stdin tests need a `Bytes` form later.

**Q8.**
- S7-1: **adopt.** A line limit makes `read_line` not total over valid input, and the S7-4 rule breaks for long lines.
- S7-2: **adopt.** It states plainly what two independent buffers cannot promise. That beats behaviour no rule defines.
- S7-3: **adopt.** It makes `read_all().lines()` and the `read_line` loop the same sequence, which Q6-a depends on.
- S7-4: **adopt.** Under d it is a theorem to state, and under a it is an obligation each handler must keep.
- S7-5: **adopt, as a `blink test` runner rule** (the runner gives the test process the null device as fd 0). It is not effect semantics. The effect means the same thing everywhere, and only the environment changes.
Concern: Under S7-5, a test that forgot to mock stdin passes on empty input and does not fail. The runner should at least report that the test read stdin with no handler.

**Q9. Vote: b. Q9-sub: drop.**
Reasoning: `?? ""` brings back the exact blank-line/EOF bug the ticket reports. A help line that suggests it, even one you apply by hand, teaches the bug. The `match` form is the correct fix and costs a few tokens.
Concern: Agents in a repair loop may still write `.unwrap_or("")` on their own, and only the targeted help text stands against that.

======================================================================
##### DEVOPS/TOOLING (devops)
======================================================================
##### Phase C ballot — DevOps/Tooling

**Q1. Vote: a. Q1-sub: adopt.**
Reasoning: The row already shows `IO.Read`. A `Result[_, Errno]` gives the error output `Err(Errno(5))`, which tells the user nothing, and every benchmark line pays `?` for a path that almost never runs. The sub-rule turns the panic into a real diagnostic: it names the op and the errno, and it names the `libc.read_bytes` path for code that must recover.
Concern: When `IoError` arrives after v1, the panic-only surface may need a second, `Result`-returning set of ops, and those names must be chosen with care.

**Q2. Vote: a.**
Reasoning: A U+FFFD swap gives a green build and wrong output, and no tool shows it. A panic that names `io.read_bytes` tells the user the fix in one line.
Concern: A program fed Latin-1 text will crash where Python would not. The panic text has to make the cause obvious.

**Q3. Vote: d.**
Reasoning: With one primitive, every view reads one stream by construction. A hand mock that answers only `read_bytes` keeps `read_line` and `read_all` consistent, and a mock that omits the primitive gets the existing W0545. Under a, the S7-4 composition law is an obligation that the compiler cannot check, so a three-op hand mock can break it silently. The cost under d is `--trace` noise (many small `read_bytes` calls) under a mock, which is acceptable, and the `stdin_from` helper hides it.
Concern: Under a mock, the derived `read_line` reads one byte per call, and a large mocked input in a test could run slowly enough that people take it for a hang.

**Q4. Vote: b. Q4-sub: adopt.**
Reasoning: I preferred c, but b matches Q3-d's `-> Bytes` primitive. Once `n <= 0` panics, an empty `Bytes` can only mean end of input, so b has no blank-line trap. Exact-n stays `std.io.read_fully`.
Concern: Users may assume b fills the whole buffer (C `fread` habits). The doc line must say "short reads are normal; use `read_fully` for exactly n".

**Q5. Vote: adopt.**
Reasoning: Marking `IO` would put `Print`/`Log` handlers under `@handle_all`, and existing print-capture handlers would get new warnings. Scoping the mark to the sub-effect keeps the diagnostic where the risk is.
Concern: `PartialHandler` text must name the sub-effect (`IO.Read is marked @handle_all`), not `IO`, or users will think every IO handler is affected.

**Q6. Vote: a. Q6-sub: adopt.**
Reasoning: v1 iterators are pure (§3c.1), so c cannot be typed, and b is a second spelling of `read_all().lines()`. Agents will still type `for l in io.lines()`. The targeted help sends them to a form that works, so they do not guess again.
Concern: Without a named helper, agents that remember `read_lines` from other proposals or languages will hit errors, so the help must also fire for `io.read_lines`.

**Q7. Vote: a. Name: `std.testing.stdin_from(text: Str)`.**
Reasoning: Mocking stdin is the main reason stdin is an effect at all. A one-line helper makes that work in practice, and test helpers belong in `std.testing`. `stdin_from` reads as "stdin from this text". The bare `stdin` reads as the real stream.
Concern: Users may try to use it outside tests. It should still work there, because it is an ordinary handler.

**Q8.**
- S7-1: adopt. Today's 4096-byte line split is a silent data bug, and no diagnostic can catch it.
- S7-2: adopt. One sentence beats a mixed-buffer guarantee nobody can test. `src/lsp.bl` stays safe because it uses only `io.read_*`.
- S7-3: adopt. `read_all().lines()` and the `read_line` loop must give the same sequence, or the "two v1 forms" help (Q6-sub) points at two forms that give different results.
- S7-4: adopt. Under Q3-d the law holds by construction. As an obligation, it binds handlers that override a derived op.
- S7-5: adopt, **as a `blink test` runner rule** (Min's placement). This is a tool default, not effect semantics.

Concern: S7-5 placed in the runner must also cover `blink test --parallel` workers, or one test can block on an inherited terminal.

**Q9. Vote: b. Q9-sub: adopt.**
Reasoning: The help says the true fact (`None` at end of input, a blank line is `Some("")`) and shows the correct `match`. `?? ""` keeps the old bug, so it may appear only as a manual second line, never as a fix that `blink migrate` applies.
Concern: The targeted trigger, "the value came from `io.read_line()`", must survive a `let` binding and a function return, or most old code gets only the plain type error.

======================================================================
##### AI/ML (aiml)
======================================================================
##### Phase C ballot — AI/ML

**Q1. Vote: a. Q1-sub: adopt.**
Reasoning: Option `a` gives one call shape (`io.read_line()`) with no `?` and no `Result`-returning `main`. That suits the 100% case and matches `io.println`. If the panic is specified and the recovery path is named, an agent that hits it gets one exact repair, not a guess.
Concern: authors may copy the stdin shape onto later stream APIs (file handles), where failures are common and a `Result` belongs.

**Q2. Vote: a.**
Reasoning: Lossy decoding yields a green run with wrong output, the hardest failure for an agent to trace. A panic that names the byte offset and `io.read_bytes` points to the fix.
Concern: tools that pipe mixed-encoding logs into Blink will panic where Python 3 would also raise. That case needs a documented bytes recipe.

**Q3. Vote: a.**
Reasoning: With three primitives under `@handle_all`, a line-level mock must cover all three ops, and the existing `PartialHandler` warning enforces that. Under `d`, a mock that overrides the derived `read_line` gets no warning, because derived ops do not count. Its `read_all` then falls through to the real-stdin primitive, which is the split-stream bug. Line-level ops also match how models write mocks: lines, not byte chunks.
Concern: S7-4 is an obligation on each handler, and only the helper from Q7 makes it easy to meet. A hand mock can still break it.

**Q4. Vote: a. Q4-sub: adopt.**
Reasoning: "Exactly n, fewer only at EOF" is the prior models carry from Python's buffered `read(n)`. It is also what the LSP body read needs, so callers never write a read-until-n loop. Panicking on `n <= 0` keeps "empty Bytes" as a single, unambiguous EOF signal.
Concern: a caller that wants "whatever is ready now" (interactive or streaming protocols) has no op for it, and must drop to `libc.read_bytes`.

**Q5. Vote: adopt.**
Reasoning: Marking `IO` would force every Print/Log handler to implement the stdin ops, which is pointless boilerplate in each logging mock. The sentence is short and learnable.
Concern: none of substance. The spec text must also say how a handler for the parent `IO` is counted.

**Q6. Vote: a. Q6-sub: adopt.**
Reasoning: Two forms with one meaning each, and no second spelling of `read_all().lines()`. Models will try `io.lines()` first, so a targeted help line that shows both v1 forms turns a guess loop into a single repair.
Concern: if S7-3 is not adopted with this, `read_all().lines()` and a `read_line` loop can disagree. That would be a silent trap.

**Q7. Vote: a. Name: `std.testing.stdin_from(text: Str)`.**
Reasoning: One call replaces a ~15-line three-op handler that must keep a shared cursor correct. `std.testing` is where a test author looks, and `stdin_from` reads as what it does.
Concern: users may expect it to accept `List[Str]` lines. The doc example should show `"a\nb\n"`.

**Q8.**
- S7-1: adopt. A silent 4096-byte split is a latent bug no test corpus catches.
- S7-2: adopt. One sentence; the same hazard as C stdio and Go bufio.
- S7-3: adopt. Required for Q6-a to be safe.
- S7-4: adopt. It defines what a correct mock means and makes Q7's helper testable.
- S7-5: adopt, placed as a `blink test` runner rule (Min's placement). A test that blocks on a tty hangs an agent harness with no output.

Concern: S7-5 under the runner only. `blink run` on a tty still blocks, which is the expected behavior.

**Q9. Vote: b. Q9-sub: drop.**
Reasoning: The targeted help teaches the correct new form at the exact site of the break. Any appearance of `?? ""`, even as a manual hint, invites agents to restore the blank-line-is-EOF bug with the least effort.
Concern: the help trigger must stay narrow (value comes from `io.read_line()`), or it fires on unrelated `Option[Str]` mismatches.

======================================================================
##### MINIMALISM (min)
======================================================================
##### Phase C ballot — MIN (Minimalism)

**Q1. Vote: a (panic). Q1-sub: adopt.**
Reasoning: a stdin read error almost never happens, and `print` has no error channel either. `Result[_, Errno]` would add `?` and a `Result`-returning `main` to every stdin program, to cover a case that a sound panic already handles. The second tier (`libc.read_bytes(0, n)`) already exists for code that must recover, so the spec should name it once rather than add a second path to the handle.
Concern: when `IoError` arrives after v1, people will ask for `Result` again, and a second signature change will cost a second migration.

**Q2. Vote: a (panic, message names `io.read_bytes`).**
Reasoning: I withdrew U+FFFD. Silent replacement turns bad input into a green build with corrupt data, which goes against E0301. One escape hatch, named in the message, is enough.
Concern: a program fed Latin-1 text panics where Python 3 also fails but Go would pass, and users from Go may call that hostile.

**Q3. Vote: d (one primitive `read_bytes`; `read_line` and `read_all` derived).**
Reasoning: this changes my round-1 position, because the final d drops `Result`, and that was my main objection. One primitive means a mock has exactly one obligation, and every view of stdin agrees with every other by construction. S3-a makes that agreement a law (S7-4) that each handler must keep by hand. My other objection, that mocks must fake bytes, goes away with the Q7 helper. The default runtime still answers each derived op natively, so production code pays no cost. Fewer handler obligations means less surface, and it removes a class of bugs instead of only documenting it.
Concern: a hand-written mock that overrides `read_line` as a derived op, but whose `read_bytes` serves different data, can still split the stream. S7-4 must bind such overrides.

**Q4. Vote: a (exactly n, fewer only at end of input). Q4-sub: adopt.**
Reasoning: it is today's meaning, so no migration. It is the read that a Content-Length body (src/lsp.bl) needs with no short-read loop. Under d it also lets the derived `read_line` body call `read_bytes(1)` with no ambiguity. Panicking on `n <= 0` removes the only case where empty `Bytes` would not mean end of input.
Concern: an interactive program that wants "whatever bytes are ready" cannot express it. YAGNI for v1, but someone will hit it.

**Q5. Adopt.**
Reasoning: marking `IO` would force every Print or Log mock to implement the read ops. A sub-effect mark is the smallest rule that gives the right scope.
Concern: none of substance. The spec must also say how a handler for the parent `IO` is counted.

**Q6. Vote: a. Q6-sub: adopt.**
Reasoning: §3c.1 names this exact case as not expressible in v1, and `read_lines()` would only spell `read_all().lines()` a second way. A diagnostic costs no surface and sends agents to a working form.
Concern: agents trained on Python will keep writing `for l in io.lines()`, so the diagnostic must be good, or the benchmark score drops.

**Q7. Vote: a. Name: `std.testing.stdin(text: Str)`.**
Reasoning: this is library code, not language surface. One function, in the testing module, with the shortest name that reads well at the `with` site (`with testing.stdin("1\n2\n") { ... }`).
Concern: if the helper is written against S3-a, or Q3 goes the other way, its op set must follow the final effect declaration exactly.

**Q8.**
- S7-1: adopt. A silent 4096-byte split is a latent correctness bug.
- S7-2: adopt. One sentence prevents a buffering trap that C and Go users already know.
- S7-3: adopt. Needed so that the two named v1 line forms give the same sequence.
- S7-4: adopt, as an obligation on any handler that answers a derived op (under d) or every op (under a).
- S7-5: adopt, as a `blink test` runner rule, not effect semantics. Effect semantics should not change with the runner.

**Q9. Vote: b. Q9-sub: drop.**
Reasoning: a fix, manual or not, that keeps the old behaviour puts the blank-line bug back exactly where the type error found it, and agents copy whatever help line the compiler shows. The help should teach the `match` form only.
Concern: callers who really do want "" at end of input must work out `?? ""` themselves, which is a small cost.

#### Phase D — Focused round on Q4 and Q9-sub

##### Lead broadcast: focused round

##### Phase D — focused round (two items only)

Phase C results. These are decided and are not reopened:
- Q1 a (panic), Q1-sub adopt: 6-0
- Q2 a (panic): 6-0
- Q3 d (one primitive `read_bytes(max) -> Bytes`; `read_line`, `read_all` derived): 5-1 (AI/ML dissent)
- Q4-sub `n <= 0` panics: 6-0
- Q5 `@handle_all` on a sub-effect: 6-0
- Q6 a, Q6-sub adopt: 6-0
- Q7 a: 6-0; name `std.testing.stdin_from`: 5-1 (Min: `std.testing.stdin`)
- Q8 S7-1..S7-5 adopt: 6-0; S7-5 as a `blink test` runner rule: 6-0
- Q9 b: 6-0

Still split (one focused round each, then a silent re-vote):

**Q4. `read_bytes` meaning** — 3-3
- a (exactly n, fewer only at end of input): Web, AI/ML, Min
- b (up to n, empty at end of input): Sys, DevOps, PLT

**Q9-sub. `?? ""` as a second, manual (not machine-applicable) help line** — 4-2
- adopt: Web, DevOps
- drop: Sys, AI/ML, PLT, Min

Every Phase C ballot is in this directory, verbatim: phaseC_sys.md, phaseC_web.md, phaseC_plt.md,
phaseC_devops.md, phaseC_aiml.md, phaseC_min.md. Read the Q4 and Q9 parts of all six.

Facts from the codebase (no position implied):
- G1 `std.io.read_fully(fd: Int, n: Int) -> Result[Bytes, Errno] ! IO` (lib/std/io.bl:21) takes a file
  descriptor and loops on `libc.read_bytes(fd, ..)`. S7-2 (adopted 6-0) makes a call on fd 0 after any
  `io.read_*` call unspecified.
- G2 src/lsp.bl:52 reads the Content-Length body with `let bytes = io.read_bytes(cl)`, after header
  lines read with `io.read_line`, and treats the result as the whole body.
- G3 `libc.read_bytes(fd, max)` (§9.1.3.3) returns up to `max` bytes.

###### Step 1 (now)
Write a focused argument, at most ~250 words, covering Q4 and Q9-sub only, to `phaseD_arg_<yourname>.md`
in this directory. You may keep or change your position. Reply "saved" to team-lead.
Do not vote yet. After all six are saved you will get a re-vote request.

======================================================================
##### SYSTEMS (sys) — argument
======================================================================
##### Phase D argument: SYS

###### Q4: I switch to a (exactly n, fewer only at end of input)

My Phase C vote for b rested on "exact n is `std.io.read_fully`'s job". G1 breaks that. `read_fully` takes a raw fd and calls `libc.read_bytes(fd, ..)`, which bypasses the io buffer. After any `io.read_line`, S7-2 (adopted 6-0) makes `read_fully(0, n)` unspecified. So under b, the LSP shape (G2: header lines, then a Content-Length body) has no correct one-call form. Every user writes their own short-read loop over `io.read_bytes`, and the ones who forget get a body truncated on pipes, though it works on files and small inputs. That is the worst failure profile: green in tests, wrong in production.

Under a, the obvious code is correct and src/lsp.bl:52 needs no migration. The cost model is the same: the default handler loops on read(2) inside the runtime, one call from Blink. The derived `read_line` body calls `read_bytes(1)` either way. The mock contract grows only slightly ("return n bytes unless input ends"), and `stdin_from` meets it trivially.

What a gives up is "whatever bytes are ready now" (proxies, interactive byte streams). That is YAGNI for v1, and it can arrive later as a separate primitive (`read_some(max)`) without changing a's meaning. Q4-sub (`n <= 0` panics) keeps empty `Bytes` as an unambiguous end-of-input signal under a.

###### Q9-sub: keep drop

`?? ""` is the reported bug written as a help line. Agents in repair loops pick the shortest edit they are shown, and ordering the lines does not prevent that. A caller who truly wants `""` at end of input can write it. The compiler should not suggest it.

======================================================================
##### WEB/SCRIPTING (web) — argument
======================================================================
##### Phase D argument: Web/Scripting

**Q4: I keep a (exactly n, fewer only at end of input).**

The b side's answer to "I need exactly n" is "use `std.io.read_fully`". G1 plus S7-2 (adopted 6-0) rules that out for the case that matters. `read_fully` takes an fd. On fd 0 after any `io.read_line`, its order is unspecified, because the io buffer may already hold the body bytes. So a mixed reader, where header lines are followed by a Content-Length body (G2, and every LSP/JSON-RPC/HTTP-ish tool), has no correct exact-n path under b. Each such user must hand-write a short-read loop over `io.read_bytes`:

```blink
let mut body = Bytes.new()
while body.len() < cl {
    let chunk = io.read_bytes(cl - body.len())
    if chunk.len() == 0 { break }
    body = body.concat(chunk)
}
```

That loop is the Node `data`-event bug factory, and the obvious one-liner `io.read_bytes(cl)` silently breaks on pipes. Today it is correct (G2). b changes the meaning without changing the name, and Blink has no overloading. Old code keeps compiling and gets truncated bodies only under load. That is the "green build, wrong answer" failure we rejected in Q2.

A merge I would accept if the b side wants read(2) semantics on the primitive: the primitive stays "up to max" and we add a derived op `io.read_exact(n) -> Bytes` (exactly n, fewer only at EOF), with `io.read_bytes` renamed so old callers get a compile error instead of a silent meaning change. Without a rename plus a derived exact-n op, I stay on a.

**Q9-sub: I change to drop.**

Sys, AI/ML, PLT and Min are right: agents copy the shortest line the compiler shows, and `?? ""` puts the reported bug back in the program. Anyone who really wants `""` at end of input can write it themselves. The help should teach `match` only.

======================================================================
##### PLT (plt) — argument
======================================================================
##### PLT — Phase D argument

###### Q4: I change to a (exactly n, fewer only at end of input)

G1 and G2 change my view. My Phase C reason for b was "point exact reads to `std.io.read_fully`". But S7-2, adopted 6-0, makes `read_fully(0, ..)` after any `io.read_*` call unspecified. So under b, nothing in the spec gives a defined way to read "exactly n bytes from stdin after a header line". That is the LSP pattern (G2), and under b the compiler's own `lsp.bl` would become a latent bug, because it treats one read as the whole body. A design that makes the compiler's own correct code wrong is not a good sign.

There is also a type-theory reason. Option a gives the stronger, total postcondition: `r.len() < n` holds exactly when the input ended. Under b, a short result is ambiguous (end of input, or just "not ready yet?"), and only an empty result has a meaning. A stronger contract on the one primitive makes the derived bodies (Q3-d) easier to prove: `read_all` loops until `len < n`, and `read_line` uses `read_bytes(1)`. A mock must meet the stronger contract, and `stdin_from` does so, so most users never meet the obligation. "Whatever bytes are ready" is the interactive case, and v1 does not need it. If it comes later, it can arrive as a new op, which is a conservative extension.

###### Q9-sub: keep drop

`?? ""` makes the blank-line/EOF bug the ticket reports compile again. A help line is something agents copy, and the shorter edit wins in a repair loop. Web's concern says the same thing. A program that really wants `""` at the end has a one-token idiom it can find for itself. The compiler should not suggest a fix it knows is wrong.

======================================================================
##### DEVOPS/TOOLING (devops) — argument
======================================================================
##### DevOps — Phase D argument (Q4, Q9-sub)

###### Q4: I change my vote from b to a (exactly n, fewer only at end of input)

My Phase C reasoning was "exact-n stays `std.io.read_fully`". G1 shows that is wrong. `read_fully` takes an fd and loops on `libc.read_bytes`, and S7-2 (adopted 6-0) makes any fd-0 read after an `io.read_*` call unspecified. Under b, then, no exact-n read over the `io` stream is specified. The one real program that mixes the two calls, our own language server (G2: header lines, then the Content-Length body), would have to write its own short-read loop over `io.read_bytes`. If it forgets the loop, the body comes back truncated on a pipe, with no diagnostic. That bug shows up only under load, in the tool users debug everything else with.

Under a, the obvious code is correct, `src/lsp.bl` needs no change, and the meaning matches today's compiler, so no migration is needed. Under d, the derived `read_line` calls `read_bytes(1)` in both cases, so a costs nothing there. A mock must honour exact-n, and `stdin_from` does that for free.

What a gives up is a "whatever is ready now" read for interactive protocols. That is YAGNI for v1, and a program that does not mix calls can still use `libc.read_bytes(0, n)`. The doc line should say: "blocks until n bytes or end of input".

###### Q9-sub: I change my vote from adopt to drop

My argument for adopt was "manual, never machine-applicable". Sys, PLT, AI/ML and Min are right that this does not matter to an agent in a repair loop: it applies the shortest help line it is shown, by hand or not. A diagnostic should show only the fix we want people to apply. A user who really wants `""` can still write `?? ""` without the compiler's help.

======================================================================
##### AI/ML (aiml) — argument
======================================================================
##### Phase D argument — AI/ML

**Q4: I keep a (exactly n, fewer only at end of input).**

Several b votes say "exact-n belongs to `std.io.read_fully`". G1 and S7-2 together rule that out. `read_fully` takes an fd and loops on `libc.read_bytes(0, ..)`. S7-2, adopted 6-0, makes that call unspecified after any `io.read_*` call. The case that needs exact-n is "read header lines, then read Content-Length bytes" (G2, src/lsp.bl). That case always calls `io.read_line` first, so it can never use `read_fully` legally. Under b, the only correct code is a hand-written loop:

```blink
let mut body = Bytes.new()
loop {
    if body.len() >= cl { break }
    let chunk = io.read_bytes(cl - body.len())
    if chunk.len() == 0 { break }
    body = body.concat(chunk)
}
```

That is about 40 tokens. The obvious line, `io.read_bytes(cl)`, compiles, passes on small test input, and truncates on a slow pipe. That is a latent bug that no mock or corpus run catches, and models will write the obvious line. Under a, the obvious line is correct and src/lsp.bl needs no migration.

The cost of a falls on the handler, not on callers. The default handler and `std.testing.stdin_from` honor exact-n once, and hand mocks are rare. The derived bodies (`read_line` reading `read_bytes(1)`, `read_all` looping until empty) work the same under a and b. "Whatever is ready now" stays at the `libc` tier, which is YAGNI for v1.

If the panel picks b anyway, it must add a stdin-buffer-aware `io.read_exact(n)`. Otherwise G2's pattern has no specified short form.

**Q9-sub: drop.** No change. Agents in a repair loop take the shortest edit shown, and `?? ""` is shorter than the `match`. Showing it at all reinstalls the ticket's bug. A user who really wants `""` can write `?? ""` without the compiler suggesting it.

======================================================================
##### MINIMALISM (min) — argument
======================================================================
##### Phase D argument — MIN

###### Q4: keep a (exactly n, fewer only at end of input)

All three b ballots say "exact-n stays `std.io.read_fully`". G1 makes that false for stdin. `read_fully` takes an fd and loops on `libc.read_bytes(0, ..)`. After any `io.read_line`, S7-2 (adopted 6-0) makes that call unspecified, because the header bytes and part of the body may sit in the `io` buffer. So under b, the Content-Length case (G2) has two outcomes. Each caller writes its own short-read loop over `io.read_bytes`, or we add a fourth surface name, such as `io.read_exact`. Both cost more than a: one loop copied into every program, or one more op. Under a, the obvious one-line code is correct.

b's other benefit is matching read(2). But the handle op is not a syscall wrapper; `libc.read_bytes` is that tier, and it stays "up to max" (G3). The two tiers may differ, and they should, because they serve different callers.

Mock cost is equal. An exact-n mock over text is `rest.slice(0, min(n, rest.len()))`, the same line as an up-to mock. The derived bodies get simpler under a: `read_all` can stop at the first short read, with no extra call to confirm end of input.

What a gives up is "whatever bytes are ready" on an interactive tty. That is YAGNI for v1, and `libc.read_bytes(0, n)` covers it for a program that does not mix in `io.read_*`.

###### Q9-sub: keep drop

A help line is an instruction to agents, and they take the shortest edit shown. `?? ""` is shorter than the `match`, and it puts back exactly the bug the ticket reports. A person who really wants `""` at end of input can write `?? ""` without the compiler suggesting it.

##### Lead broadcast: re-vote

##### Phase D — silent re-vote (Q4 and Q9-sub only)

All six Phase D arguments are saved in this directory, verbatim: phaseD_arg_sys.md, phaseD_arg_web.md,
phaseD_arg_plt.md, phaseD_arg_devops.md, phaseD_arg_aiml.md, phaseD_arg_min.md. Read them all.

Vote alone. Format per question: Vote / Reasoning (2-4 sentences) / Concern (one sentence).

**Q4. `read_bytes` meaning:** a (exactly n, fewer only at end of input, empty at end of input) /
b (up to n, empty at end of input)

**Q9-sub. `?? ""` as a second, manual (not machine-applicable) help line:** adopt / drop

Write to `phaseD_vote_<yourname>.md` in this directory, then reply "saved" to team-lead.

======================================================================
##### SYSTEMS (sys) — vote
======================================================================
##### Phase D vote: SYS

**Q4: a (exactly n, fewer only at end of input, empty at end of input).**
Reasoning: G1 plus S7-2 leave no specified exact-n read over the io buffer under b. The Content-Length pattern (G2) would then depend on a short-read loop that every caller writes by hand, and the obvious one-liner truncates silently on pipes. Under a, the default handler loops on read(2) inside the runtime: one Blink call, the same cost as b. a also gives the total postcondition `len < n` if and only if input ended, which makes the derived `read_all` cheaper, since no extra call is needed to confirm end of input.
Concern: a program that proxies stdin byte by byte blocks until n bytes arrive. The spec doc line must say "blocks until n bytes or end of input" and name `libc.read_bytes` as the non-mixed escape.

**Q9-sub: drop.**
Reasoning: `?? ""` is the reported bug written as a help line. In a repair loop, "manual" means nothing: the shortest shown edit wins. The diagnostic should show only the `match` fix.
Concern: agents may still invent `.unwrap_or("")` on their own. Only the targeted help text stands against that.

======================================================================
##### WEB/SCRIPTING (web) — vote
======================================================================
##### Phase D re-vote: Web/Scripting

**Q4. Vote: a (exactly n, fewer only at end of input, empty at end of input).**
Reasoning: With a, the obvious one-liner `io.read_bytes(cl)` is correct. Under b, that line compiles, passes tests on small input and truncates on a slow pipe, and S7-2 leaves no other correct exact-n path once `io.read_line` has run. a also keeps today's meaning under the same name, so `src/lsp.bl` and user code need no silent change in meaning.
Concern: someone will later need a "whatever bytes are ready" read for an interactive or proxy stream. It must arrive as a new, separately named op (such as Sys's `read_some(max)`), never as a change to `read_bytes`.

**Q9-sub. Vote: drop.**
Reasoning: agents in a repair loop apply the shortest help line shown, and `?? ""` is the reported blank-line/EOF bug written as a suggestion. The targeted `match` help is the only fix the compiler should teach. A user who really wants `""` can write it unprompted.
Concern: with no shortcut shown, some agents will write `.unwrap()` on `io.read_line()` and panic at end of input, so the `match` help line must be prominent and copy-pasteable.

======================================================================
##### PLT (plt) — vote
======================================================================
##### PLT — Phase D vote

**Q4. Vote: a (exactly n, fewer only at end of input, empty at end of input).**
Reasoning: Under S7-2, b leaves no specified exact-n read on the `io` stream. The obvious `io.read_bytes(cl)` would then compile and silently truncate the body on a pipe (G2). a gives the one primitive (Q3-d) a total, stronger postcondition: `r.len() < n` holds exactly when the input ended. That makes the derived `read_all` and `read_line` bodies easy to prove, and the S7-4 rule follows from them. The `libc.read_bytes` tier keeps the read(2) "up to max" meaning, so the two tiers stay distinct on purpose. "Whatever is ready" can arrive later as a new op, which is a conservative extension.
Concern: A hand-written mock that returns short chunks breaks the exact-n contract, and the derived `read_all` would then stop early with no error. The spec should state the contract on the primitive in plain words.

**Q9-sub. Vote: drop.**
Reasoning: `?? ""` puts back the exact blank-line/end-of-input bug the ticket reports. Agents apply the shortest edit they are shown, whether it is machine-applicable or manual. A diagnostic should show only the fix the language means you to apply.
Concern: A caller who really wants `""` at end of input gets no hint, which is a small, accepted cost.

======================================================================
##### DEVOPS/TOOLING (devops) — vote
======================================================================
##### DevOps — Phase D vote

**Q4. Vote: a (exactly n, fewer only at end of input, empty at end of input).**
Reasoning: G1 plus S7-2 leave b with no specified exact-n read over the `io` stream. The header-then-body pattern (G2, our own language server) would then need a short-read loop. If that loop is missing, the result is a truncated body on a pipe, with no diagnostic. That failure passes every test and shows up only under load. Under a, the obvious one-line code is correct, `src/lsp.bl` needs no change, and the meaning does not change under the same name, which matters because Blink has no overloading.
Concern: A hand mock written before this rule, or by an agent, may return short `Bytes` mid-stream. The derived `read_all` then stops early, so the `IO.Read` docs and `stdin_from` must show the exact-n obligation plainly.

**Q9-sub. Vote: drop.**
Reasoning: An agent in a repair loop applies the shortest help line it is shown, whether the fix is automatic or not. `?? ""` would put back the exact bug this ticket reports. The diagnostic should show only the `match` fix.
Concern: Without a narrow trigger (the value comes from `io.read_line()`), the targeted help may not fire after a `let` and a function call, and the user sees only a bare type error.

======================================================================
##### AI/ML (aiml) — vote
======================================================================
##### Phase D re-vote — AI/ML

**Q4. Vote: a (exactly n, fewer only at end of input, empty at end of input).**
Reasoning: With option a, the line a model writes first, `io.read_bytes(cl)`, is the correct one. Under b, it is a truncation bug that passes every small-input test. G1 plus S7-2 leave b with no specified exact-n path on stdin after a line read. The stronger postcondition (`len < n` means end of input) also makes the derived `read_all` body simpler and makes mock behavior easier to state.
Concern: someone will later need "whatever bytes are ready". It must arrive as a separate op (such as `read_some`), never as a quiet change to `read_bytes`.

**Q9-sub. Vote: drop.**
Reasoning: Agents in a repair loop apply the shortest help line shown, manual or not. `?? ""` puts back the exact blank-line/EOF bug this ticket fixes. The help should show only the `match` form.
Concern: old code that passes the `read_line` value through a `let` or a function return may miss the targeted help and get only the plain type error, so that error must still read clearly.

======================================================================
##### MINIMALISM (min) — vote
======================================================================
##### Phase D vote — MIN

**Q4. Vote: a (exactly n, fewer only at end of input, empty at end of input).**
Reasoning: by G1 and S7-2, `read_fully(0, ..)` is unspecified after `io.read_line`, so under b the Content-Length case needs a short-read loop in every caller, or a fourth op (`read_exact`). Option a needs neither. It keeps today's meaning, so src/lsp.bl needs no migration, and the obvious one-line code is correct. If a "whatever is ready" read is ever needed, it can come later as a separate op without changing a.
Concern: a hand-written mock that returns short chunks breaks a's contract with no diagnostic, so the spec and `stdin_from` must state the exact-n obligation plainly.

**Q9-sub. Vote: drop.**
Reasoning: agents apply the shortest help line they are shown, and `?? ""` puts back exactly the bug the ticket reports. The compiler should suggest only the fix it wants applied. A user who really wants `""` at end of input can write it without help.
Concern: agents may still reach for `.unwrap_or("")` on their own, so the `match` help line must be clear and come first.

### Final Spec

```blink
effect IO {
    effect Print
    effect Log

    @handle_all
    effect Read {
        fn read_bytes(n: Int) -> Bytes      // primitive
        fn read_line() -> Option[Str] { ... }  // derived, body in §4.4.9
        fn read_all() -> Str { ... }           // derived, body in §4.4.9
    }
}
```

- `read_bytes(n)` gives exactly `n` bytes, fewer only at end of input, and empty `Bytes` at end of input. `io.read_bytes(n)` with `n <= 0` panics before the operation runs.
- `read_line` removes a `\n` or `\r\n` terminator. A last line with no terminator is a line. A blank line is `Some("")`; end of input is `None`. A line has no length limit.
- A read failure panics and names the operation and the errno. Input that is not valid UTF-8 panics and names `io.read_bytes`. Code that must recover uses `libc.read_bytes(0, n)`.
- Every `IO.Read` handler keeps the contract: `read_bytes` returns short only at end of input, and an implemented derived operation agrees with its body. So `read_all()` equals the lines from repeated `read_line()` calls, each one followed by its terminator.
- `@handle_all` marks `IO.Read` only. A parent `handler IO` counts its operations only if it implements one or more of them.
- After an `io.read_*` call, reads of file descriptor 0 have unspecified order (§9.1.3.3).
- `Str.lines()` uses the `read_line` rules (§3).
- No `io.lines()`. A call to it is E0505 with help that shows `io.read_all().lines()` and the `loop`/`match` form.
- Old `Str` callers get a type error with help that shows the `match` form. No machine-applicable fix.
- `std.testing.stdin_from(text)` supplies input in tests; `blink test` gives each test process the null device as standard input (§8.10.1).
