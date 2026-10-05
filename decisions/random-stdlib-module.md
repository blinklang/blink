[< All Decisions](../DECISIONS.md)

# `Rand` Operations and `std.random` — Design Rationale

The `Rand` effect (§4.3) listed `rand.int`, `rand.float` and `rand.bytes` with no signatures, ranges or semantics. The stdlib had no random module. The test-seed decision ([test-seed-determinism.md](test-seed-determinism.md)) rested on an assumption that `Rand` gets no seeding op. This panel fixed the ops, the user surface, the helper module, seeding and secrets. The spec text is §4.4.7 *Rand Operations*; §8.10.4 changed to match.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Phase D re-debated Q2, Q7a and Q7c. Panelist text below is verbatim; headings inside it are shown as bold lines, and ticket IDs are replaced by bracketed descriptions.

**Codebase facts given to the panel (moderator, no position):**

- F1. The spec gives `Range[T]` no way to read its bounds. §2.10 says only: "Ranges are lazy iterables of type `Range[T: Ord]` which implements `IntoIterator`."
- F2. §4.7.1 *Completeness and auto-delegation* governs what happens to ops a handler omits.
- F3. §4.4 IO precedent: "Handler operations take `Str`. The generic surface is a stdlib wrapper, not a generic effect operation."
- F4. The §8.10.4 example called a bare `shuffle([1, 2, 3, 4, 5])` after `import std.testing.{mock_rand, MockRand}` only.

#### Phase A — Independent proposals

##### Systems

**Proposal S1: three primitive ops on `Rand`, helpers as plain functions in `std.random`**

**What the hardware sees**

Each `rand.*` call goes through the handler lookup: an indirect call through whichever handler is installed. That fixed cost is about 2 to 5 ns. The generator does far less work than that. So the op set must have two properties:

- **Few ops, each one primitive.** Each handler, and `MockRand`, implements only the ops. Nobody re-implements the algorithms.
- **Ops coarse enough that one call does useful work.** `rand.bytes(n)` fills a whole buffer in one dispatch.

Helpers such as `shuffle` and `choice` are ordinary generic functions with a `! Rand` row. They monomorphize per `T`, they make no handler call of their own, and they reach the RNG only through ops. This keeps the existing contract that one op call is one draw: `shuffle` of 5 elements makes 4 `rand.int` calls, which matches the 4 draws asserted in §8.10.4.

**The effect**

```blink
effect Rand {
    fn int(range: Range[Int]) -> Int    // uniform, unbiased; empty range panics
    fn float() -> Float                 // uniform in [0.0, 1.0), 53 random mantissa bits
    fn bytes(n: Int) -> Bytes           // n uniform bytes; n < 0 panics
}
```

Semantics I want written into the spec:

- **`rand.int(lo..hi)` and `rand.int(lo..=hi)` must give an exactly uniform result.** No modulo bias. The spec states that the result is uniform. It does not name an algorithm (Lemire's method is the obvious choice). `rand.int(Int.MIN..=Int.MAX)` is valid and returns one full 64-bit word.
- **An empty range panics.** The return type `Int` cannot say "absent", so the point-read rule applies: panic, never make up a value. The diagnostic gives the range.
- **`rand.float()` is `(w >> 11) * 2^-53`.** That is one multiply. It can never return 1.0.
- **No `reseed` op and no `fork` op.** The stated assumption in §8.10.4 holds unchanged: seeding is something you do when you install a handler. This is the cheap answer to [the MockRand-body ticket]: `MockRand` has nothing to trap. A `reseed` op would also force every production handler to carry mutable state that user code can change, which breaks the per-thread buffer design below.

**The default handler (§4.7): a CSPRNG, not a fast PRNG**

The production handler is **ChaCha8 (or ChaCha12)**:

- per-thread state, so there are no locks
- a buffered keystream: refill 256 to 512 bytes at a time, with fast key erasure
- seeded from `getentropy`, the call that `libc.getentropy_bytes` already wraps
- after `fork`, the child reseeds (check the PID on refill, or `pthread_atfork`)

The cost argument: ChaCha8 with SIMD runs at about 1 cycle per byte, so the refill costs about 1 ns per draw. The handler dispatch already costs more than that. Making the default secure is therefore almost free, and it removes a real hazard: someone builds session tokens with `rand.bytes(32)`, and the default turns out to be xoshiro. Go 1.22 made the same trade (the `math/rand/v2` global source is ChaCha8), and so does Rust (`ThreadRng` is ChaCha12). I do not want a separate `Crypto.Rand` effect. One effect with one secure default is simpler, and `Crypto` stays scoped to keys and primitives.

The spec does **not** promise that the default handler's stream is reproducible. Reproducibility comes from `mock_rand(seed)`, and the test PRNG stays implementation-defined (xoshiro256**). That already fits §8.10.4.

**`std.random`: helpers**

```blink
import std.random.{shuffle, choice, float_in, sample}

pub fn shuffle[T](xs: List[T]) -> List[T] ! Rand {
    let mut out = xs
    let mut i = out.len() - 1
    while i > 0 {
        let j = rand.int(0..=i)
        out.swap(i, j)
        i = i - 1
    }
    out
}

pub fn choice[T](xs: List[T]) -> Option[T] ! Rand {
    if xs.len() == 0 { return None }
    xs.get(rand.int(0..xs.len()))
}

pub fn float_in(lo: Float, hi: Float) -> Float ! Rand {
    lo + rand.float() * (hi - lo)
}
```

- `choice` returns `Option` because its return type can say "absent". An empty list is not a crash. This matches `.get()`.
- `shuffle(xs)` makes n − 1 draws, as Fisher-Yates must.
- **Module name:** `std.random`. The effect stays `Rand` and the handle stays `rand`. Users never write `random.int`, so the handle and the module name never collide.
- **Not in the MVP:** `random_int` and `random_range` as free functions. They duplicate `rand.int(range)`, and two spellings of one thing cost more than they give. Bool: `rand.int(0..2) == 1`. I would not object to a `coin()` helper later.

**Proposal S2 (optional, I support it but do not insist): `Xoshiro256`, a value type with no effect**

Some code has a hot inner loop: Monte Carlo, procedural generation, benchmarks, 10^9 draws. A handler dispatch on every draw costs about 5 times the generator. Rust, Zig (`std.Random.Xoshiro256`) and Go (`rand.New(rand.NewPCG(...))`) all ship an explicit generator value for this case.

```blink
import std.random.{Xoshiro256}

fn estimate_pi(seed: U64, n: Int) -> Float {
    let mut g = Xoshiro256.new(seed)
    let mut hits = 0
    for _ in 0..n {
        let x = g.float()
        let y = g.float()
        if x * x + y * y < 1.0 { hits = hits + 1 }
    }
    4.0 * hits.to_float() / n.to_float()
}
```

- The methods take `mut self`. It is a 32-byte struct, the four words stay in registers, and the code inlines.
- **It is pure.** It is deterministic given the seed, and the function has no effect row. That is honest: it reads no outside entropy.
- To seed it from real entropy: `Xoshiro256.new(rand.int(Int.MIN..=Int.MAX).to_u64())`. That call needs `! Rand`, so the capability boundary holds.

Tradeoff: this is a second surface, and min will say so. It is not the rejected `seeded_rng`. `seeded_rng` was a second way to mock `Rand`. This is a way to not use `Rand` at all where the effect is the wrong abstraction. If the panel wants a strict MVP, defer S2 and file it. Do not reject it.

**Summary of my votes going in**

| Question | My position |
|---|---|
| Module | `std.random` (helpers). Effect is `Rand`, handle is `rand`, both unchanged. |
| Ops | `int(Range[Int])`, `float()`, `bytes(Int)` only. No `reseed`, no `fork`. |
| Uniformity | `int` is exactly uniform (spec guarantee). `float` is in [0, 1) with 53 bits. |
| Edge cases | Empty range panics. `choice` returns `Option`. |
| Default handler | Per-thread ChaCha CSPRNG, entropy-seeded, fork-safe. Its stream is not reproducible. |
| Seeding | Done by installing a handler (`mock_rand`, `--seed`). It is not an op. |
| Helpers | `shuffle`, `choice`, `float_in`, `sample`, as generic functions that use ops only. |
| Fast PRNG | `Xoshiro256` pure value type: S2, deferrable. |

Cross-language: the op shape follows Rust's `Rng::gen_range` (unbiased, range-typed). The default handler copies Go 1.22's ChaCha8 global. The value-type generator follows Zig's `std.Random`.

##### Web/Scripting

The test is simple: someone who has written Python's `random` or Kotlin's `(1..6).random()` should be able to roll a die in Blink without opening the docs. Most questions about random APIs come from three problems: off-by-one ranges (`randint` vs `randrange`), an insecure default (`Math.random()` used for tokens), and API sprawl (`random` vs `secrets` vs `crypto`). I propose one fix for each.

---

**Proposal W1: give the three ops real signatures, and take the bounds as a range literal**

```blink
effect Rand {
    fn int(range: Range[Int]) -> Int
    fn float() -> Float
    fn bytes(n: Int) -> Bytes
}
```

- `rand.int(1..=6)` gives a die roll, 1 to 6 inclusive. `rand.int(0..xs.len())` gives a valid index. You can see the bound type in the literal, so nobody has to remember an argument convention.
- An empty range (`rand.int(5..5)`) panics. Under the point-read rule, `Int` cannot say "absent", and an empty range is a programmer error, the same as `1 / 0`.
- `rand.float()` returns a value in `[0.0, 1.0)`. Every language uses this contract, and it is the one people already expect.
- `rand.bytes(n)` returns `n` bytes. `n < 0` panics.

```blink
fn roll_dice() -> Int ! Rand {
    rand.int(1..=6) + rand.int(1..=6)
}

fn jitter_ms(base: Int) -> Int ! Rand {
    base + rand.int(0..base / 2)
}
```

**Tradeoffs:** `int(lo, hi)` is what everyone reaches for first, but every language that ships it then has to explain whether `hi` is inclusive. Python has both `randint` (inclusive) and `randrange` (exclusive), and that is a classic source of confusion. Blink already has `..` and `..=` and both are `Range[Int]`, so this costs nothing new to learn. The ticket's separate `random_range` goes away because `int` already takes a range.

**Rejected: `random_int` / `random_float` free functions.** They would sit beside `rand.int` and give two names for one thing. The handle is the API.

**Proposal W2: a small `std.random` module with helpers only**

The module name is `std.random`, as in Python and Rust's `rand` crate, so people find it by guessing. It defines no new effect and no types, just free functions written on top of the ops:

```blink
pub fn shuffle[T](xs: List[T]) -> List[T] ! Rand
pub fn choice[T](xs: List[T]) -> Option[T] ! Rand
pub fn chance(p: Float) -> Bool ! Rand
```

```blink
import std.random.{shuffle, choice}

fn deal() -> List[Card] ! Rand {
    shuffle(new_deck())
}

fn greeting() -> Str ! Rand {
    choice(["hi", "hello", "hey"]).unwrap_or("hi")
}
```

- `shuffle` returns a new list and leaves the input unchanged. It runs Fisher-Yates with one `rand.int` per swap, so 5 elements cost 4 draws, which matches the §8.10.4 example exactly.
- `choice` returns `Option` because an empty list has nothing to pick. That follows the point-read rule and how `.get()` already works.
- `chance(0.25)` covers "do X 25% of the time", which is the most common one-line use of `rand.float() < p`. If the minimalism seat objects, I would drop it before the other two.

`sample(xs, k)`, weighted choice, and distributions (gaussian and so on) wait until someone asks for them.

**Tradeoffs:** I chose free functions over List methods (`xs.shuffle()`) because a method with an effect makes it hard to see where `! Rand` comes from at the call site, and because the existing spec example already calls `shuffle(...)` as a free function. Kotlin uses methods. Python's `random.shuffle(xs)` uses a free function, and JS/Python developers will recognise that form.

**Proposal W3: secure by default, with no reseed op**

- **The default handler (§4.7) is a CSPRNG**, seeded from OS entropy (`getentropy`) and implementation-defined internally (ChaCha-based or similar). `rand.bytes(32)` from the default handler is safe for session tokens.
  - Why: in JS (`Math.random`) and Python (`random` vs `secrets`), splitting secure and fast randomness has caused a steady stream of weak-token CVEs. Most users never benchmark their RNG. The few who need millions of draws per second can install a faster handler themselves. Go moved `math/rand` toward ChaCha8 in 1.22 for this reason.
- **No `rand.reseed` and no `rand.fork` op.** Seeding stays a handler-installation concern. This keeps the "stated assumption" in §8.10.4 true, leaves `MockRand` unchanged, and unblocks the [the MockRand-body ticket] and [the `--seed` + MockRand implementation ticket] tickets with no follow-up.
- **Optional W3b, which I vote for but do not insist on:** a production seeded handler, `random.seeded(seed: U64) -> Handler[Rand]`, for games and procedural generation ("share your world seed").

```blink
import std.random

fn gen_world(seed: U64) -> World {
    with random.seeded(seed) {
        build_terrain()
    }
}
```

  I am explicitly reopening the "why not `seeded_rng`" reasoning here, and only partly. That rejection protected a single *test* surface. Production code should not import `std.testing` to get a reproducible world. The catch: world seeds only work if the stream stays stable across compiler versions, and §8.10.4 refuses that guarantee for `MockRand`. If the panel will not promise stream stability for `seeded`, drop W3b, because a seed that changes across versions is worse than having no seeded handler.

**Effect question: already settled, and it is the right call**

`! Rand` in a signature is the one point where a JS developer will hesitate. In return, nobody needs a dependency-injection framework to test code that uses randomness: `with mock_rand(7).as_handler() { ... }` and you are done. Do not soften it.

**Summary of my votes**

| Question | Position |
|---|---|
| Module | `std.random`, helpers only |
| Ops | `int(Range[Int])`, `float()` in `[0,1)`, `bytes(n)`. Invalid input panics |
| MVP helpers | `shuffle`, `choice -> Option`, `chance` |
| Default handler | CSPRNG |
| Seeding | Install a handler; no reseed or fork op |
| Production seeded handler | Yes, but only if the stream is stable across versions |

##### PLT

**Core principle**
An effect's operations are its **algebraic signature**. A handler supplies the meaning. Two rules follow:

1. **Op signatures stay monomorphic and total.** §4.4 already set this for IO ("Handler operations take `Str`. The generic surface is a stdlib wrapper"). Rand should follow the same rule. Generic helpers (`shuffle[T]`, `choice[T]`) are *derived* from the ops. They are never ops themselves. If ops were generic, every user handler would have to be parametric over `T`. That needs rank-2 handler types, which Blink does not have and should not get for this.
2. **The wrapper checks each handler's postcondition.** `Handler[Rand]` is a value that users can write. The type system cannot prove that a user handler returns a value inside the range it was asked for. So the stdlib wrapper checks the result and panics with "Rand handler contract violated" when the check fails. Without this check, `shuffle` would be unsound under a buggy mock. It would index out of bounds, or worse, quietly drop elements.

**Proposal A (primary): ops, wrappers, handle-resident helpers**

**Handler operations.** This is the whole effect signature, and it fills the §4.3 table:

```blink
effect Rand {
    fn int(lo: Int, hi: Int) -> Int     // closed interval [lo, hi], lo <= hi
    fn float() -> Float                 // half-open [0.0, 1.0)
    fn bytes(n: Int) -> Bytes           // n >= 0, result.len() == n
}
```

The op takes a **closed interval**, not a `Range`. A closed interval is never empty when `lo <= hi`, so the op is total on its domain. It can also express the full `Int` range, which `..` cannot. The user-facing wrapper takes `Range[Int]`. Both `..` and `..=` already produce `Range[Int]`, so one wrapper covers both:

```blink
fn roll() -> Int ! Rand {
    rand.int(1..=6)
}

fn pick_index(xs: List[Str]) -> Int ! Rand {
    rand.int(0..xs.len())        // panics if xs is empty: empty range is a precondition violation
}
```

The wrapper's typing rule is `rand.int(r: Range[Int]) -> Int`. It normalizes `r` to `[lo, hi]` and panics on an empty range, the same way division by zero panics. It then performs the op and checks `lo <= v && v <= hi`. `rand.float()` checks `0.0 <= v && v < 1.0`. `rand.bytes(n)` checks `n >= 0` before the op and `.len() == n` after it.

**Derived helpers live on the handle.** They are wrappers in the same sense as `io.println`:

```blink
fn deal(deck: List[Card]) -> List[Card] ! Rand {
    rand.shuffle(deck)                       // returns a new list; Fisher-Yates
}

fn greet(names: List[Str]) -> Str ! Rand {
    match rand.choice(names) {               // Option: absent when names is empty
        Some(n) => "hi {n}"
        None => "nobody here"
    }
}
```

- `rand.shuffle[T](xs: List[T]) -> List[T]`. It is pure in, pure out, with no in-place mutation, so it composes. It makes exactly `xs.len() - 1` calls to `int`. For 5 elements that is 4 draws, which matches the §8.10.4 example. That example's free `shuffle(...)` becomes `rand.shuffle(...)`.
- `rand.choice[T](xs: List[T]) -> Option[T]` follows the point-read rule. The return type can say absent, so it returns `Option` and does not panic.
- No `random_*` free functions and no new module for the MVP. The capability shows at the call site (`rand.`), the same discipline as "no global `print`". The brief's names (`random_int`, `random_range`) fold into `rand.int(range)`. Keeping a separate `random_range` would give one operation two names.

**Seeding is handler installation, not an op.** I keep the stated assumption from §8.10.4. Adding `rand.reseed` would make the op set stateful and break *handler parametricity*. Code typed `! Rand` could then observe and corrupt the stream that its caller installed. That is a covert channel through an effect that is meant to be a pure capability. Seeding stays where Koka and Eff put it, in the handler:

```blink
import std.random

fn simulate() -> Report ! Rand {
    let n = rand.int(1..=100)
    Report { steps: n }
}

fn main() ! IO {
    let report = with random.seeded(42) { simulate() }   // production determinism, no std.testing import
    io.println(report)
}
```

`std.random` holds only handler factories: `random.seeded(seed: U64) -> Handler[Rand]` and `random.system() -> Handler[Rand]`, where `system` is the default. I put `seeded` here, not in `std.testing`, because a simulation or procedural generator that imports a *testing* module is a category error. This is not the `seeded_rng` that §8.10.4 rejected. That rejection was about a second *test* primitive. `seeded` is a production handler with no audit hook. `mock_rand` stays the test controller. Its body can be written as `seeded` plus a draw counter, so the two cannot drift apart.

**Default handler: CSPRNG.** The default `random.system()` uses a ChaCha-family generator seeded from OS entropy (`getentropy`). `UUID.random() ! Rand` is already decided. v4 UUIDs get used as unguessable identifiers, so a predictable default would make an already-decided API insecure in practice. Speed is a handler concern: a fast PRNG is one `with random.seeded(s)` away. The spec should name the property ("unpredictable, OS-seeded"), not the algorithm. The test-seed decision did the same.

**Proposal B (secondary, separate vote): secrets are not `Rand`**
Here is the type-theoretic problem. **A security property of a handler cannot be seen in the type `! Rand`.** Any caller can wrap a call in `with random.seeded(0)`, and the callee cannot tell. For simulations, shuffles, and tests, that interposability is the *point*. For key material it is a vulnerability. The principled split:

```blink
fn new_session_key() -> Bytes ! Crypto.Random {
    crypto.random_bytes(32)          // not interceptable by a Rand handler
}
```

This adds a `Crypto.Random` sub-effect under the existing Crypto tree and keeps it out of the Rand surface. The MVP does not depend on it. I flag it so that nobody later "fixes" the CSPRNG default by making `Rand` uninterceptable. That would break mock_rand and all of §8.10.4.

**Deferred, but kept open**
- **`fork`/split for concurrency.** Deterministic replay across spawned tasks needs splittable generators (SplitMix, JAX keys). Without a reseed op, a handler-level `random.split()` can come later without changing the effect signature. If `fork` *were* an op, MockRand would have to say whether it traps or honors it, which is exactly what [the MockRand-body ticket] fears. My proposal keeps MockRand's body equal to the final op set: `int`, `float`, `bytes`.
- **Sized ints and float ranges.** Use `rand.int(0..=255).to_u8()` for now. Add a generic `rand.int[T: Integer]` wrapper only when it is needed.

**Tradeoffs**
- (+) The op set is minimal and monomorphic, so user handlers are easy to write and MockRand is fully specified.
- (+) Postcondition checks make every derived helper sound under any handler.
- (+) There is no stateful op, so `! Rand` code cannot interfere with its caller's stream.
- (−) Each draw pays one range check. That is negligible next to the cost of handler dispatch.
- (−) `rand.shuffle` on the handle widens the handle surface beyond ops. The `io.println` precedent already allows this.
- (−) The closed-interval op leaks one detail of the wrapper into handler authors' view. It is simple and documented.

**Cross-language note**
Haskell's `random` exposes `uniformR (lo, hi)` with closed bounds, for the same totality reason. Koka's and Eff's canonical examples seed through handlers, never through ops. Rust's `rand` crate separates `thread_rng` (CSPRNG default) from `OsRng`, and that split informs Proposal B. Python's `random` vs `secrets` is the same split, learned through CVEs.

##### DevOps/Tooling

I propose a module named `std.rand`. The `Rand` effect keeps three ops, each with a fixed signature that is easy to read in a diagnostic. Helpers come in only by import, and the default handler is a CSPRNG. Most of this proposal is about what the user sees when they get it wrong.

**Proposal A: three ops with exact signatures (main proposal)**

```blink
effect Rand {
    fn int(range: Range[Int]) -> Int    // uniform over range; panics if range is empty
    fn float() -> Float                 // uniform in [0.0, 1.0)
    fn bytes(n: Int) -> Bytes           // n uniform bytes; panics if n < 0
}
```

```blink
fn roll() -> Int ! Rand {
    rand.int(1..=6)
}

fn jitter(base: Duration) -> Duration ! Rand {
    base.mul_float(1.0 + rand.float() * 0.1)
}
```

**Why `int` takes a `Range` and not `(lo, hi)`.** "Is `hi` included?" is the oldest bug in random APIs. Python's `randint` includes `hi`, `randrange` does not, and Go's `Intn(n)` does not. With a `Range`, the answer is in the source text (`..` or `..=`), and LSP signature help shows `range: Range[Int]`. It also gives the compiler a specific mistake to catch. People and LLMs who come from Python will write `rand.int(0, 10)`, and the diagnostic can fix it:

```
error[ArgCount]: `rand.int` takes 1 argument (a Range), found 2
 --> sim.bl:4:14
  |
4 |     let n = rand.int(0, 10)
  |             ^^^^^^^^^^^^^^^
  = fix: rand.int(0..10)
  = note: use `0..=10` to include 10 (Python's randint includes the upper bound)
```

`rand.int(10)` gets the same treatment: `expected Range[Int], found Int; fix: rand.int(0..10)`. Full-width draws need no extra op, because `rand.int(Int.MIN..=Int.MAX)` covers every value.

**Empty range.** An empty range panics. This follows the point-read rule: an `Int` return cannot say "absent", so the call panics and never makes up a value. The panic message names the op and the range (`rand.int: empty range 5..5`), so `assert_panics(matching: "rand.int")` works. When both range ends are literals, `typecheck` reports an error, because a literal empty range means the call always panics.

**No reseed op.** I agree with the current assumption in §8.10.4: seeding happens when you install a handler, so `MockRand` stays as it is.

**Helpers: free functions in `std.rand`, imported by name only**

```blink
import std.rand.{shuffle, choice}

fn deal(deck: List[Card]) -> List[Card] ! Rand {
    shuffle(deck)
}

fn pick_host(hosts: List[Str]) -> Option[Str] ! Rand {
    choice(hosts)
}
```

- `shuffle[T](xs: List[T]) -> List[T] ! Rand` is Fisher-Yates and returns a new list. It makes `xs.len() - 1` calls to `rand.int`, which fits the "5 elements = 4 draws" example already in §8.10.4. A spec example that agrees with itself is a test we get for free.
- `choice[T](xs: List[T]) -> Option[T] ! Rand` returns `None` when the list is empty, because the return type can say "absent".
- Do not add `random_int`, `random_float` or `random_range`. The ops already do those jobs. Two names for one job gives two completion entries and makes every reviewer ask which one is correct.

**The diagnostic hazard I want the spec to close.** `rand` is a reserved handle. If users write `import std.rand` and then `rand.shuffle(xs)`, the call is ambiguous with the handle namespace. We already hit this with `fs` and `net`, where a stdlib free fn with the same bare name as an intrinsic captured calls. The rule I propose:

- `rand.<name>` always resolves to the effect handle.
- A helper call through the handle gets a targeted error:

```
error[UnknownEffectOp]: `shuffle` is not an operation of effect `Rand`
 --> deal.bl:7:5
  |
7 |     rand.shuffle(deck)
  |     ^^^^^^^^^^^^
  = note: `Rand` operations are `int`, `float`, `bytes`
  = help: `shuffle` is a function in `std.rand`
  = fix: add `import std.rand.{shuffle}` and call `shuffle(deck)`
```

LSP completion after `rand.` shows the three ops and the helpers, each marked "auto-import". Accepting a helper rewrites the call to `shuffle(...)` and adds the import, the same way rust-analyzer inserts `use` lines.

**Default handler: CSPRNG, with no second generator in the stdlib**

The §4.7 default handler gets its seed from OS entropy (`getentropy`), runs a ChaCha-based CSPRNG per thread, and is fork-safe. My argument comes from tooling: Go's split between `math/rand` and `crypto/rand` created a whole linter category (gosec G404, Python's bandit B311) to flag "you used the weak one". If `std` has one generator, that category of lint never needs to exist, and code completion never asks the user to choose. A PRNG would be faster, but you can get that speed by installing a handler later. The default only has to be safe.

**Risk I am flagging.** The type of a `Handler[Rand]` does not say whether it is cryptographically secure. A key generator that is `! Rand` will quietly accept a seeded handler. My answer is that the `Crypto` key APIs should draw entropy through `! Crypto` and not through `! Rand`. Then `mock_rand` can never weaken a real key, and the effect signature makes that clear to a reviewer.

**A production seeded handler** (`std.rand.seeded(seed)`) is deferred under YAGNI. The test panel already rejected a second seeding surface (`seeded_rng`), and `mock_rand` covers determinism in tests.

**Proposal B: one primitive op (alternative; it reopens decision #1, so I state why)**

Auto-delegation of partial handlers (§4.7.1) is a hole in determinism. Suppose a user writes `handler Rand { fn int(r: Range[Int]) -> Int { 4 } }`. Every `rand.float()` and `rand.bytes()` call then falls through to the OS CSPRNG, the test is flaky, and nothing warns about it. One fix is a single op, `fn u64() -> U64`, with `int`, `float` and `bytes` as non-overridable derived handle methods. Then a mock can only replace everything or nothing.

The cost: this changes the op list in §4.3, and `rand.bytes(64)` would no longer count as one draw. If the panel keeps Proposal A, I want a lint in its place:

```
warning[PartialRandHandler]: handler for `Rand` omits `float`, `bytes`
  = note: omitted ops auto-delegate to the enclosing handler (non-deterministic in tests)
  = fix: implement all three ops, or use `std.testing.mock_rand(seed)`
```

**Formatter**

`blink fmt` needs no new rules. All of this is ordinary call and range syntax, which is part of the case for it.

**Vote position:** A, plus the `PartialRandHandler` lint, plus the handle-resolution rule and the CSPRNG default. B is my second choice.

##### AI/ML

The question I ask of each choice: can a model learn it from the spec alone and get it right on the first try? Random APIs are a known source of two LLM bugs. The first is off-by-one bounds: Python's `randint` includes both ends, `randrange` excludes the top, and JS code uses `Math.floor(Math.random()*n)`. The second is weak randomness in security code (CWE-338): a model writes `random.choice` where it should write `secrets.choice`. My proposals target both bugs and add as few decision points as I can.

**Proposal 1: three effect ops whose bounds show at the call site**

Keep the three ops that §4.3 already lists. Fix their signatures and add no more ops:

```blink
effect Rand {
    fn int(range: Range[Int]) -> Int   // uniform and unbiased over range; an empty range panics
    fn float() -> Float                // uniform in [0.0, 1.0), 53-bit resolution
    fn bytes(n: Int) -> Bytes          // n uniform bytes; n < 0 panics
}
```

```blink
fn roll_die() -> Int ! Rand {
    rand.int(1..=6)
}

fn pick_index(xs: List[Str]) -> Int ! Rand {
    rand.int(0..xs.len())
}
```

**Why a `Range` argument and not `(lo, hi)`:** with `(lo, hi)`, the model must remember one hidden convention, inclusive or exclusive, and it learned both conventions from other languages. With a range, the syntax states the convention: `1..=6` and `0..n` are clear without docs, and `..`/`..=` already exist in Blink. The decision moves from memory to syntax. The token cost is the same as `rand.int(1, 6)`.

**Why an empty range panics:** this follows the point-read rule. `Int` cannot say "absent", and an empty range is a bug in the program, not data.

**Dependency:** handler authors must read the bounds, so `Range[T]` needs public `.start`, `.end` and `.is_inclusive()` (or an equivalent). The spec does not say this today, so it needs a small follow-up. If the panel rejects that, my fallback is `fn int(lo: Int, hi: Int) -> Int` with **half-open** bounds, the same as `..`. A wrong guess there causes silent off-by-one bugs, which is why I prefer the range form.

**No `reseed`, `fork` or `u64` op.** This confirms the assumption in §8.10.4: seeding is a concern of handler installation. Every op a handler author must write is extra work, and each one is another chance for a mock to drift from the spec ([the MockRand-body ticket]). For a full 64-bit value, use `rand.bytes(8)`. With three ops, `MockRand` has nothing to trap.

**Proposal 2: `std.random` holds only what the ops cannot do in one line**

```blink
import std.random.{shuffle, choice}

fn deal(deck: List[Card]) -> List[Card] ! Rand {
    shuffle(deck)
}

fn greet() -> Str ! Rand {
    match choice(["hi", "hello", "hey"]) {
        Some(g) -> g
        None -> "hi"
    }
}
```

```blink
pub fn shuffle[T](xs: List[T]) -> List[T] ! Rand    // new list; Fisher-Yates; len-1 draws of rand.int
pub fn choice[T](xs: List[T]) -> Option[T] ! Rand   // None if empty; one draw
```

- `choice` returns `Option` because of the point-read rule: the return type can say "absent".
- The spec states the draw counts (`shuffle` of n items uses n-1 draws), so the existing `assert_eq(r.draws(), 4)` example has a basis.
- **Reject `random_int`, `random_float` and `random_range`.** They repeat `rand.int` and `rand.float`. Two names for one operation is the worst case for an LLM: it uses both at random and code review has to settle the style. One way to do each thing.
- **Module name `std.random`.** It is the most common name in training data (Python `random`, Rust `rand`, Go `math/rand`), and it does not collide with the reserved `rand` handle. Calling the module `rand` would make `rand.int` ambiguous between a module path and an effect handle, which is a trap for readers and models.

**Proposal 3: the default handler is a CSPRNG, with no "secure" variant**

The stdlib default handler for `Rand` uses a ChaCha-based CSPRNG, seeded from `getentropy` and reseeded on fork. There is no separate `secure_rand` or `Crypto.Random`.

- **AI argument:** when a model writes `rand.bytes(32)` for a session token, the code is safe by construction. A split like Python's `random`/`secrets` is a decision point that models get wrong at a measurable rate. Removing the choice removes that class of bug.
- **Cost:** ChaCha8 or ChaCha12 in user space is fast enough for general code. Go 1.22 `math/rand/v2` defaults to ChaCha8, and Rust's `StdRng` is ChaCha12. Hot simulation loops that need more speed install their own handler.
- The spec says only that the default "is a cryptographically secure generator". It names no algorithm.

**Proposal 4 (secondary, split vote OK): seeded handler for production**

Games, procedural generation and simulations need reproducible streams outside tests. Importing `std.testing` into production code to get `mock_rand` is the wrong signal. I propose:

```blink
import std.random

fn generate_world(seed: U64) -> World {
    with random.seeded(seed) {
        build_terrain()
    }
}
```

`random.seeded(seed: U64) -> Handler[Rand]` is a production handler, not a mock, so the controller-struct rule does not apply to it. It gives no draw counts. **Its algorithm is named in the spec** (xoshiro256** with splitmix64 seed expansion) and stays stable across versions, because stored world seeds must keep working. `MockRand` may share the generator. I know the test-seed panel rejected `seeded_rng` as a second name for the mock. My answer: this is a different primitive with a different contract (stable across versions, no introspection). If the panel disagrees, I drop this proposal before I drop Proposals 1 to 3.

**Decision-point count**

| Shape | Decision points per random call | Notes |
|---|---|---|
| Mine | 0 (bounds in syntax), 0 (security), 0 (which name) | 3 ops plus 2 helpers to learn |
| Python-style split | 3 | randint or randrange, random or secrets, method or function |

**Cross-language note:** Rust's `rng.gen_range(1..=6)` already proved that range arguments work, and models write it correctly. Go v2's switch to a ChaCha8 default shows that a secure default is affordable.

##### Minimalism

**My position:** the effect is already there, and so are its three op names. The gap is the signatures, not features. Spec the three ops as tightly as possible, ship one helper module with two functions, add no seeding op, and ship one default generator. Every other item in the ticket's list either repeats an op or is not needed yet.

**Proposal M1: three ops, each with one meaning**

```blink
effect Rand {
    fn int(below: Int) -> Int     // uniform in [0, below); below <= 0 panics
    fn float() -> Float           // uniform in [0.0, 1.0), 53 random mantissa bits
    fn bytes(n: Int) -> Bytes     // n uniform bytes; n < 0 panics, n == 0 gives empty
}
```

- **`rand.int(below)` with one bound, not a `Range[Int]`.** I looked at the Range option and rejected it. §2.10 gives `Range[T]` no way to read its bounds, so a user handler (`handler Rand { fn int(r: Range[Int]) ... }`) could not see `lo`, `hi` or whether the range is inclusive. A Range op would quietly force a new Range accessor API into the language. It would also need its own rule for `Int.MIN..=Int.MAX`, where the length overflows checked `Int`. One bound has none of these problems, and the panic follows the point-read rule: `Int` cannot say "absent", so an empty interval panics. Go's `rand.IntN(n)` works the same way.
- **The result must be unbiased** (the default handler uses rejection sampling). Callers need an offset for any other interval: `lo + rand.int(hi - lo)`. One idiom, so nobody has to ask "is it `randint` or `randrange`?"
- **Handlers must stay in range.** A handler that returns a value outside `[0, below)` breaks the op contract, the same as a handler that breaks any other op's type. Std helpers may index without checks, and debug builds `debug_assert` the bound. This matches how MockRand already reads: it honors the ops.
- **Sized ints, gaussian, bool and float ranges are left out.** `rand.int(2) == 0` is a bool. `U64` comes from `rand.bytes(8)`. A distributions library can live in a package until someone shows a real need.

**Proposal M2: `std.random` with exactly `shuffle` and `choice`**

The module name is forced. `import std.rand` would bind `rand`, which collides with the reserved effect handle (§3.6). So the module is **`std.random`**.

```blink
import std.random.{shuffle, choice}

pub fn shuffle[T](xs: List[T]) -> List[T] ! Rand {
    let mut out = xs
    let mut i = out.len() - 1
    while i > 0 {
        let j = rand.int(i + 1)
        out.swap(i, j)
        i = i - 1
    }
    out
}

pub fn choice[T](xs: List[T]) -> Option[T] ! Rand {
    if xs.len() == 0 { return None }
    xs.get(rand.int(xs.len()))
}
```

- **`shuffle` is worth shipping.** Fisher-Yates is a well-known source of off-by-one and bias bugs, and §8.10.4 already depends on it. It makes n−1 op calls, so `shuffle([1, 2, 3, 4, 5])` gives `r.draws() == 4` as the spec asserts. Note that the spec example needs the `import std.random.{shuffle}` line added.
- **`choice` is the borderline case.** I accept it because the empty list is exactly where the point-read rule applies (`Option[T]`), and LLM users will write `xs[rand.int(xs.len())]` and panic on `[]` otherwise.
- **I reject `random_int`, `random_float` and `random_range`.** They repeat the ops with a different spelling, which puts two names on one primitive, the same reason `seeded_rng` lost.
- **I reject `sample`, `weighted_choice` and `xs.shuffle()` as a List method.** An effectful method on List would couple a core type to `Rand`.

**Proposal M3: seeding is a handler concern, with no op (an explicit **no**)**

`Rand` gets **no `rand.reseed`, `rand.seed` or `rand.fork`.** This keeps the assumption that the test-seed decision rests on, so [the MockRand-pattern ticket], [the MockRand-body ticket] and [the `--seed` + MockRand implementation ticket] unblock without rework: MockRand has nothing to trap or honor. Determinism comes from the handler you install:

```blink
import std.testing.{mock_rand, MockRand}
import std.random.{choice}

test "deal is stable for a seed" {
    let names = ["a", "b", "c"]
    let first = with mock_rand(0x1234).as_handler() { choice(names) }
    let again = with mock_rand(0x1234).as_handler() { choice(names) }
    assert_eq(first, again)
}
```

**Production seeded PRNG (games, simulations): defer it.** Using `mock_rand` from `std.testing` in production code is an odd fit, and I admit that. But a `std.random.seeded(seed) -> Handler[Rand]` would be a second name for the same generator. I would add it when a real user asks, and the handler API means adding it later breaks no one.

**Proposal M4: one default handler, a CSPRNG**

The stdlib default handler for `Rand` is **unpredictable and seeded from OS entropy**. The spec states that property and leaves the algorithm open (for example ChaCha12 seeded through `libc.getentropy_bytes`, re-keyed as it needs to be). §4.7 already lets built-in default handlers do real I/O internally.

**One generator with no user choice removes a whole class of mistakes.** It also means `UUID.random()` and `rand.bytes(32)` used for tokens and keys are safe by default, with no separate "secure random" API. That keeps `Crypto` out of randomness altogether.

**The speed cost is small.** Go 1.22 moved `math/rand/v2`'s default to ChaCha8, and Rust's `ThreadRng` is ChaCha12. Users who need maximum throughput write a handler; that is what handlers are for.

**Tradeoffs from a minimalism view**

| | Cost | Saved |
|---|---|---|
| `int(below)` over Range | `lo + rand.int(hi - lo)` at call sites | Range accessor API, inclusive/exclusive ambiguity, MIN..=MAX overflow rule, harder handler bodies |
| 2 helpers | Users write their own sampling and weighting | No doubled names, small doc surface |
| No seed op | Production seeded PRNG needs a handler or a later addition | Three blocked tickets stay valid, MockRand stays simple, no stateful op inside an effect |
| CSPRNG-only default | Some throughput loss | No API for choosing a generator, no insecure-default bugs |

**Other languages:** Go has `IntN` with a ChaCha8 default and panics on n ≤ 0. Python's `randint` (inclusive) vs `randrange` (exclusive) is the confusion M1 avoids. Lua's single `math.random` shows how little surface people need. C++ `<random>` is the cautionary tale: engines × distributions × seed sequences, a combinatorial surface that few users get right.

**What I am asking the panel to vote on:** three ops with the signatures above, `std.random.{shuffle, choice}` and nothing more, no seeding op, and a CSPRNG default specified by its property only.

#### Phase A.5 — Points with no competing option

All six proposals shared these, so they were not on the ballot:

- P1. No `rand.reseed` / `rand.seed` / `rand.fork` op. Seeding is handler installation.
- P2. `fn float() -> Float`, uniform in [0.0, 1.0).
- P3. `fn bytes(n: Int) -> Bytes`; `n < 0` panics.
- P4. No `random_int` / `random_float` / `random_range` free functions.
- P5. `shuffle` returns a new list, Fisher-Yates, exactly n-1 `int` draws; `choice` returns `Option[T]` (None on empty).

#### Phase B — Debate (round 1; all six marked stable)

##### Systems

**Q1: I shift from 1a to 1b (plt).** F1 decides it. A user handler that receives `Range[Int]` cannot read the bounds, so 1a quietly adds a Range accessor API to the language just so people can write mocks. plt's split fixes this and gives better codegen. The op is `int(lo: Int, hi: Int)` on a closed interval: two words in registers, no struct to unpack, and it is total whenever `lo <= hi`. It also covers `Int.MIN..=Int.MAX`, which no half-open form can express. Users still write `rand.int(1..=6)`, the handle-level wrapper normalizes the range, and aiml, web and devops keep their "the bound is in the syntax" win. Handler authors get the simplest possible signature.

Against 1c (min): `lo + rand.int(hi - lo)` overflows checked `Int` once the span exceeds `Int.MAX`. Take `rand.int` over `-5..Int.MAX`: it panics on an overflow the user never wrote. It also puts the offset arithmetic at every call site, which is where off-by-one bugs live. A closed interval has neither problem.

One honest gap remains: the stdlib wrapper also has to read Range bounds. Fix that with a separate, general Range accessor ticket, or with a compiler-known wrapper. The op shape does not depend on which one. **Exact uniformity stays a spec guarantee** (Lemire or rejection sampling, no algorithm named). Bias is a correctness bug, and it costs about one multiply to avoid.

**Q2: 2a, `std.random`.** min and aiml are right: `import std.rand` binds `rand` over a reserved handle. That rules out 2b's module name, but I back devops's resolution rule and diagnostic (`rand.shuffle` gets an error with a fix to `import std.random.{shuffle}`). Against 2c: generic helpers on the handle make the handle's surface open-ended, and F4 already calls a bare `shuffle`. The handle should expose the op names only. `rand.int(Range)` is acceptable because it is the op under the same name.

**Q3: concede to 3a.** I withdraw `float_in` and `sample`. Each is one line over the ops. `chance` stays out for the same reason.

**Q4: 4e, defer.** I withdraw S2 (`Xoshiro256`) for this ticket and file it as a follow-up. web's point stands for any seeded generator outside tests: a world seed that changes across compiler versions is worse than none. So a future `seeded` must name its algorithm and freeze its stream. That is a separate decision, and the MVP needs neither.

**Q5: 5a for the MVP.** plt's `Crypto.Random` costs nothing at runtime, since it is a type-level capability split, and I am sympathetic. It belongs in the Crypto spec, not this ticket. File it, don't vote it down.

**Q6: 6a, wrapper checks in release builds.** The check is one predicted compare-and-branch, about 0.3 ns against 2 to 5 ns of handler dispatch. The panic blames the handler that broke the contract, not a `List.swap` three frames down. Put the check in the handle wrapper, once, not in every helper.

**Q7:**
- 7a: yes, as a warning. Writing `default.float()` explicitly silences it, so a logging handler that delegates on purpose stays clean.
- 7b: strong no. It changes the decided rule that one op call is one draw. Worse for my seat, `rand.bytes(4096)` becomes 512 dispatches where today it is one bulk fill. The op set exists to amortize dispatch.
- 7c and 7d: yes. Both cost nothing at runtime.

**P6: concede.** The spec names properties, not ChaCha. The properties must include more than "CSPRNG, OS-seeded":
- **fork-safe**: parent and child never produce the same stream
- **safe under concurrent tasks**: no shared stream between threads

Both are observable security properties, not implementation details. ChaCha8 or ChaCha12 per thread goes in the implementation notes.

**My vote set:** 1b + uniformity guarantee, 2a + devops's diagnostic, 3a, 4e, 5a (file 5b), 6a, 7a/7c/7d, no to 7b. P6 states properties, with fork safety and thread safety written out.

STABLE: yes

##### Web/Scripting

The 5-minute test still decides it for me: a Python developer types `rand.` and gets a correct dice roll, a correct shuffle and a safe token, with no docs and no import puzzle. Here is where I move.

**Q1: integer op. I shift to 1b, and keep the Range at the call site**

F1 is a real fact, and aiml and min are right that it breaks 1a as stated: a user handler cannot read a `Range`. But F1 also breaks *any* Range-taking API, including a stdlib wrapper, so the language needs public bounds on `Range` regardless. Python's `range` has `.start`/`.stop`. A JS or Python developer expects to be able to ask a range for its ends. That should be a follow-up ticket, not a reason to drop ranges.

So I take plt's split, which follows the §4.4 IO model (F3) exactly:
- Handler op: `fn int(lo: Int, hi: Int) -> Int`, closed `[lo, hi]`. It is total and handler authors find it trivial.
- User surface: `rand.int(r: Range[Int]) -> Int`. An empty range panics.

Users write `rand.int(1..=6)` and never see the op. Only handler authors, the 10% case, see `lo, hi`.

**Against 1c (min):** `lo + rand.int(hi - lo)` puts the off-by-one arithmetic back on every call site. A die roll becomes `1 + rand.int(6)`, and "is it 6 or 7?" is exactly the question we set out to remove. Go has this shape, and Go users write wrong `IntN` offsets all the time.

**Uniformity:** yes, make it a spec guarantee (sys, aiml, min). Every user already assumes it, and it costs nothing to promise.

**Q2: where the helpers live. I shift to 2c, with 2a as my fallback**

I argued for free functions, but once 1b makes the handle the user surface, plt's design reads better. Python's `random.shuffle(xs)` maps to `rand.shuffle(xs)`: one character of difference, no import, and `rand.` autocomplete shows everything. 2a makes newcomers learn two names (module `random`, handle `rand`) for one concept. That will be a recurring Stack Overflow question ("why does `random.int` not exist?"). F4 already calls a bare `shuffle(...)` with no import, so the spec example needs editing under any option.

**To devops:** your `UnknownEffectOp` fix-it is excellent, but under 2c it is not needed. If the panel picks 2a, I want devops's rule and fix-it as part of it. 2b's `std.rand` binding `rand` is a trap (min and aiml are right about that), so I am against 2b.

**Q3: helper set. I concede `chance`, and pick 3a**

`rand.float() < 0.25` is clear enough. I am against `float_in` and `sample` until someone asks for them.

**Q4: production seeded handler. I hold 4b, which becomes 4e unless stability is promised**

aiml says the same thing I do: a world seed that changes when you upgrade the compiler is a bug report, not a feature. plt's 4c does not promise stability, so in that form I vote against it. 4d (`Xoshiro256`) is a reasonable later package or ticket, but it is not MVP. If nobody will name the algorithm and freeze the stream, defer it (min, devops).

**Q5: secrets. I hold 5a for the MVP**

One safe default with no choice to make. I do not object to plt's `Crypto.Random` as a separate, later decision, and devops's point that `Crypto` key APIs should draw entropy internally is an implementation detail I agree with. Neither should block this ticket.

**Q6: handler contract. I support 6a**

A buggy mock that makes `shuffle` quietly drop an element costs someone an afternoon of debugging. A panic that says "Rand handler contract violated: int(0, 4) returned 7" costs a few nanoseconds per call. The checks give users a clear error at the point the contract breaks, which matters more to me than those nanoseconds.

**Q7: diagnostics**
- 7a `PartialRandHandler`: yes. An unseeded fall-through inside a "deterministic" test is the worst kind of flaky test.
- 7b single `u64` op: no. It reopens §4.3 and the draw-count rule for little gain.
- 7c literal empty range is an error: yes, it is cheap.
- 7d `rand.int(0, 10)` fix-it: strong yes. Every Python developer will type exactly this on day one.

**P6: algorithm naming**

The spec states properties only: unpredictable, OS-seeded, fork-safe (a child never repeats its parent's stream). It does not name ChaCha. That keeps sys's guarantees without locking in an algorithm.

STABLE: yes

##### PLT

**Q1 (op signature): I keep 1b. F1 is the reason.**
1a and 1b look the same to callers: `rand.int(1..=6)` in both. They differ only in what a handler author must implement, and here F1 decides it. Under 1a, every handler (MockRand, every user mock) must take apart a `Range[Int]` that the spec gives no way to read. It must also handle inclusive vs exclusive, the empty case, and the `Int.MIN..=Int.MAX` length overflow. That makes the op partial and puts the hardest code in the most places. Under 1b, the op domain is `{(lo, hi) | lo <= hi}`: total, one case, full `Int` range included. One stdlib wrapper reads the Range, and that read can stay stdlib-internal, so F1 does not force a public Range accessor API.

min's 1c is total too, but it is not closed under intervals. `lo + rand.int(hi - lo)` overflows when `hi - lo` exceeds `Int.MAX` (for example `-5..Int.MAX`), and it cannot produce the full range at all. It moves the overflow into user code, which is worse.

If the panel wants the op to take a Range anyway, aiml's condition must hold: spec Range accessors first. Otherwise 1a is not implementable by users.

**Uniformity:** yes, spec it as exactly uniform. It is a contract obligation on every handler; the default handler meets it by construction.

**Q2: I shift to 2a (`std.random` free functions)**
devops makes the stronger structural point. If `rand.` lists exactly the effect signature plus the op wrappers, then the handle's interface *is* the effect, and nothing else lives there. `shuffle[T]` is an ordinary generic function with row `! Rand`. Effect polymorphism composes through it with no new handle mechanism. The module must be `std.random`: `std.rand` collides with the reserved handle (min, aiml). I support devops's 7-style rule: `rand.<name>` always resolves to the handle, and `rand.shuffle` gets a targeted error.

**Q3: 3a, `shuffle` and `choice` only**
I oppose sys's `float_in` on correctness grounds. `lo + rand.float() * (hi - lo)` can round up to exactly `hi`, so a half-open `[lo, hi)` claim would be false for some inputs. A helper whose stated range is wrong is worse than no helper. `chance`: harmless, but YAGNI.

**Q4: I shift away from 4c, to 4e (defer), with 4a as the only acceptable alternative**
web and aiml are right. A seeded handler's meaning *is* its stream. If the stream can change between compiler versions, then `seeded(42)` has no meaning across versions, and I let it go unstated. So either name and freeze the algorithm (4a), or defer. Deferring breaks nobody: a handler factory is a pure addition. sys's `Xoshiro256` value type is sound because it is pure, but it is a second surface. Defer it as well.

**Q5: I concede 5a for this ticket**
The interposability hazard is real, but the fix belongs in the Crypto spec, not in Rand. I fold my Proposal B into devops's wording, as a note for the Crypto work: "Crypto key APIs draw entropy under `! Crypto`, not `! Rand`." `Rand` stays one effect with a CSPRNG default.

**Q6: I keep 6a, narrowed**
min is right that Blink bounds-checks, so safety is not at stake. But under 6b, `choice` on a non-empty list returns `None` under a bad handler (because `xs.get` returns `None`), and the result is silently wrong in release builds. One compare per op is free next to handler dispatch. Check at the op wrapper, always on, not `debug_assert`.

**Q7**
- 7a `PartialRandHandler` warning: yes. Auto-delegation of omitted ops breaks the determinism a mock exists to provide.
- 7b single `u64` op: no. It reopens the "one op = one draw" decision and makes `bytes(n)` cost about n/8 draws.
- 7c literal empty range is an error: yes, but only when both ends are literals.
- 7d ArgCount fix-it: yes.

**P6**
Name properties, not an algorithm: "unpredictable; seeded from OS entropy; distinct streams across threads and after `fork`". sys's fork-safety belongs in that list.

STABLE: yes

##### DevOps/Tooling

**F1 changes my Q1 vote. I shift from 1a to 1b (plt).** Min is right: with `fn int(range: Range[Int])` as the op, a user handler cannot read the bounds, because `Range` has no accessors. A mock author who writes `handler Rand { fn int(r: Range[Int]) -> Int { ... } }` cannot even return `lo`. That design breaks tooling at its root: hover and docs would show a parameter that nobody can use. 1b gives each audience what it needs:
- Callers write `rand.int(1..=6)`. They get the `..` vs `..=` clarity, signature help, and my fix-its (`rand.int(0, 10)` → `rand.int(0..10)`, `rand.int(10)` → `rand.int(0..10)`).
- Handler authors see `fn int(lo: Int, hi: Int) -> Int`, a closed interval, total when `lo <= hi`, and able to express `Int.MIN..=Int.MAX`. That also answers min's overflow point.
- The wrapper reads the bounds as a compiler intrinsic, the way `io.println` handles its argument (F3). We add no public `Range` accessor API in this ticket.

Against 1c (`int(below)`): `lo + rand.int(hi - lo)` is exactly the hand-written arithmetic that produces off-by-one bugs, and no diagnostic can catch it, because it is valid code. A `Range` argument at the call site lets the compiler check things. Arithmetic does not.

**Q1 uniformity: state "unbiased" as a spec guarantee.** It is testable (a chi-square test in the stdlib suite), and it stops a future "fast path" that uses modulo.

**Q2: I drop `std.rand` and shift to 2c (helpers on the handle), with 2a as my second choice.** Min and aiml are right: `import std.rand` binds `rand`, which collides with the reserved handle. The handle-resolution rule I proposed was a workaround for a name we should not choose. Between 2a and 2c, 2c has the better tooling story:
- `rand.` completion lists every random operation. No auto-import step, no "unknown function `shuffle`" for new users.
- F4 becomes self-consistent. The §8.10.4 example works as `rand.shuffle(...)` with no missing import.
- The capability shows at the call site, the same as `io.println`.

The one diagnostic 2c needs: a handler that tries to override a wrapper.
```
error[NotAnEffectOp]: `shuffle` is not an operation of effect `Rand`
  = note: `Rand` operations are `int`, `float`, `bytes`; `rand.shuffle` is built on `int`
```
`std.random` then holds handler factories only.

**Q3: 3a, `shuffle` and `choice` only.** `chance` is `rand.float() < p`. `float_in` and `sample` can wait for real demand.

**Q4: stay on 4e (defer), with one condition if the panel ships `seeded`.** I accept plt's point that importing `std.testing` in production is a category error. But a seed that users keep in config files and bug reports must give the same stream after a compiler upgrade, or "reproduce with seed 42" turns into a support ticket on every release. So if it ships, it must come with web's 4b promise: algorithm named, stream stable across versions. Otherwise do not ship it. 4d (`Xoshiro256` value type) is a second generator API with no effect, so `--seed` and `mock_rand` cannot reach it. I reject it.

**Q5: 5b stays secondary, and it is weak.** I keep my flag: `! Rand` cannot show whether the installed handler is secure. The MVP does not depend on it.

**Q6: 6a (plt).** A checked postcondition turns "index out of bounds in `std.random` line 40" into "Rand handler contract violated: `int(0, 4)` returned 9". That message points at the user's buggy mock, not at the stdlib. One compare per draw is cheap next to handler dispatch. 6b's `debug_assert` gives release users the bad message.

**Q7:**
- 7a, the `PartialRandHandler` warning: I keep it. 2c does not close the auto-delegation leak.
- 7b: I withdraw it. It reopens §4.3 and the "one op call = one draw" rule for a problem the lint already covers.
- 7c, literal empty range as a compile error: I keep it. It still applies to the 1b wrapper.
- 7d, the fix-it: I keep it.

**P6: name the property in the spec, not the algorithm.** Sys's ChaCha and fork-safety details are good implementation notes. If they go in the spec, swapping the algorithm becomes a spec change and adds nothing a user can rely on. The exception is the Q4 `seeded` handler, if it ships, because there the stream itself is the contract.

**My vote package:** 1b + unbiased guarantee, 2c (2a second), 3a, 4e (4b condition), 5a for the MVP with 5b recorded, 6a, P6 property-only, 7a + 7c + 7d.

STABLE: yes

##### AI/ML

**Q1: I shift from 1a to 1b (plt), with one condition**

F1 settles it for me. min is right that a `Range` op forces a Range accessor API into the language before any handler can be written. plt's split keeps what I care about and drops that cost:

- **Users and models write `rand.int(1..=6)` and `rand.int(0..xs.len())`.** The bound kind still shows in the syntax, so the off-by-one decision stays out of memory. That was my whole case for 1a.
- **Handler authors see `fn int(lo: Int, hi: Int) -> Int`, closed interval.** Two plain Ints, total on `lo <= hi`, and `Int.MIN..=Int.MAX` works. §4.4 IO already uses this pattern (F3): a monomorphic op with the user surface as a wrapper.

**My condition:** the handle exposes only the wrapper `rand.int(r: Range[Int])`. A two-Int `rand.int(0, 10)` must not reach the raw op from user code. If it did, Python-trained code would compile with closed-interval meaning, and a model reading `randrange`-style code would get a silent off-by-one. The two-arg form exists only inside `handler Rand { ... }` bodies. That also lets devops's 7d fix-it fire.

Against 1c (`int(below)`): `lo + rand.int(hi - lo)` brings back the exact off-by-one site we want gone. An inclusive die needs `1 + rand.int(6)`, and models will write `rand.int(6) + 1` or `rand.int(1, 6)` in about equal measure. 1c also moves the `MIN..=MAX` overflow problem into user code. The cost is low for min and high for every call site.

**Uniformity:** state it as a guarantee (exactly uniform, no modulo bias), and name no algorithm.

**Q2: 2a, `std.random`**

I reject 2b: `import std.rand` collides with the reserved handle, and devops's own fix needs a new resolution rule plus a diagnostic to patch a problem the name creates. Choose the name that has no collision. I reject 2c too: generic helpers on the handle blur which `rand.*` names a handler overrides and which it does not. When a model writes a mock, it cannot tell from `rand.shuffle` that shuffle is not an op. The §8.10.4 example needs `import std.random.{shuffle}` added (F4).

**Q3: 3a, `shuffle` and `choice` only**

Models already write `rand.float() < p` without help, so `chance` saves nothing. `float_in` is a one-liner. `sample` has a k > len edge case and is not needed yet.

**Q4: 4a > 4e > 4c > 4d**

I agree with web: a seeded production handler is worth it only if its stream stays stable across versions. Without that promise, drop it (4e). 4c has no stability promise, so it gives a world seed that silently changes on upgrade, which is worse than nothing. 4d (`Xoshiro256`) gives a second way to draw an int, with different method names than the handle. Defer it and file it.

**Q5: 5a**

plt's point holds: `! Rand` cannot show whether the handler is secure. But a `Crypto.Random` sub-effect puts the Python `random`/`secrets` choice back, and models choose wrong. I accept devops's narrower rule as an implementation note: std's own Crypto key APIs get entropy from the OS directly, not through `Rand`. No new user op.

**Q6: 6a**

Under 1b the wrapper exists anyway, so the postcondition check is one compare. "Rand handler contract violated: int(0, 4) returned 7" can be repaired. An index-out-of-bounds deep in `shuffle` cannot. Debug-only checks (6b) hide the bug in release, which is where a buggy mock in a fixture lands.

**Q7**

- 7a `PartialRandHandler` warning: **yes**. A partial mock that is silently nondeterministic is a trap that models will fall into.
- 7b single `u64` op: **no**. It breaks the "rand.bytes(64) = one draw" rule.
- 7c error on a literal empty range: **yes**, it costs little.
- 7d `ArgCount` fix-it `rand.int(0, 10)` → `rand.int(0..10)`, with a note about `..=`: **strong yes**. This is the most common error that models trained on other languages will make here.

**P6**

Spec the default by its property only (CSPRNG, OS-seeded, fork-safe). Name an algorithm only for `seeded`, if 4a passes.

STABLE: yes

##### Minimalism

**Q1: I move from 1c to 1b (plt)**
F1 confirms my Phase A point: 1a (op takes `Range[Int]`) quietly needs a public Range accessor API (`.start`, `.end`, `.is_inclusive()`). aiml says so openly; web, sys and devops do not price it in. That is new surface on a core type, added to fill one effect op.

But devops and aiml win on the call site. Bounds that show in syntax (`1..=6`) beat my `lo + rand.int(hi - lo)` idiom, and four seats agree. plt's 1b gives us both:
- The handler op is `fn int(lo: Int, hi: Int) -> Int` over the closed interval `[lo, hi]`. It is total and covers `Int.MIN..=Int.MAX`, and handler authors need no Range API.
- The user-facing `rand.int(r: Range[Int])` is a stdlib wrapper. This is the F3 IO precedent exactly: a monomorphic op with a wrapper on top. The wrapper reads range internals privately, so no public accessor is added.
- `shuffle` with `rand.int(0..=i)` is still one op call, so 4 draws still holds.

1b is the only option that adds no public surface and keeps the clear call site. I vote 1b. My fallback is 1c. I oppose 1a unless the accessor API is voted on as part of it, in the open.

**Uniformity:** yes, make "exactly uniform, no modulo bias" a spec guarantee. It costs one sentence, and a biased `int` is a latent bug that users will find.

**Wrinkle:** with 1b, the handler op `int` takes 2 args and the call `rand.int` takes 1. I accept devops' 7d fix-it for `rand.int(0, 10)` because it adds no language surface.

**Q2: 2a, `std.random`**
2b creates the collision and then adds a resolution rule plus a diagnostic to cover it. Choosing the other name costs nothing. 2c puts generic algorithms in the reserved handle namespace. `io.println` wraps one op. `rand.shuffle` is an algorithm, and every later helper (`sample`, `weighted`) would land in a namespace users cannot extend. Free functions keep the handle equal to the capability. The F4 example needs one import line under 2a, and it needs a rewrite under 2c either way.

**Q3: 3a, `shuffle` and `choice` only**
`chance(p)` is the same as `rand.float() < p`, so it is a second name. sys's `float_in` makes my case for me: `lo + rand.float() * (hi - lo)` can round up to `hi`, so the "trivial" helper has a bug. Defer it until someone specs it properly. Defer `sample` too.

**Q4: 4e, defer**
web has the key point. A production `seeded` only has value if its stream stays stable across versions, which means naming the algorithm in the spec forever (aiml's 4a). That is a large, permanent commitment, and nothing that blocks on this ticket needs it. File it as its own ticket. If it ever ships, 4a (named and stable) is the only honest form. I reject 4c (seeded without a stability promise: a world seed that drifts is worse than none) and defer 4d (a second RNG API outside the effect).

**P6: name the property, not the algorithm**
The spec text says the default is unpredictable, seeded from OS entropy, and that a forked child does not repeat its parent's stream. ChaCha8/12, per-thread buffers and fast key erasure are implementation detail and stay out of sections/.

**Q5: 5a for this ticket**
plt's point is real: `! Rand` cannot show whether a handler is secure. But where Crypto key APIs get entropy belongs in the Crypto spec. Adding `Crypto.Random` here grows a second tree to answer a question this ticket does not ask. Log it against the Crypto spec.

**Q6: I concede to 6a (plt)**
I proposed `debug_assert` only. Under the correctness bar, a buggy mock that makes `shuffle` silently drop elements in release builds is not acceptable. Under 1b the wrapper exists anyway, so the check costs one compare next to an indirect call. 6a is correct, and I vote 6a.

**Q7**
- **7a: reject a Rand-only lint.** §8.10.4 says the runner seeds every handler installation, so an omitted op that delegates inside a test is still deterministic, and the hazard is smaller than claimed. If partial handlers are a hazard, that is a general lint across all effects. File it separately.
- **7b: reject.** It reopens decided item 1 and breaks "one op call = one draw".
- **7c: reject.** It special-cases one op. A general constant-empty-range lint can come later if wanted.
- **7d: accept.** It is a diagnostic only, with no spec surface.

**What I will vote for**
1b with a uniformity guarantee, 2a, 3a, 4e, P6 as a property only, 5a, 6a, and from Q7 only 7d.

STABLE: yes

#### Phase C — Final vote

Ballot: Q1 integer op (1a `int(range: Range[Int])` · 1b `int(lo: Int, hi: Int)` closed, plus a Range wrapper · 1c `int(below: Int)`); Q1-U exact uniformity; Q2 helpers (2a `std.random` · 2b `std.rand` · 2c on the handle); Q2-R resolution rule plus targeted error; Q3 helper set (3a `shuffle`, `choice` · 3b + `chance` · 3c + `float_in`, `sample`); Q4 production seeded generator (4a algorithm named, stream stable · 4b only if stability promised · 4c `seeded` + `system`, no promise · 4d `Xoshiro256` value type · 4e defer); Q5 secrets (5a one effect · 5b `Crypto.Random`); Q6 out-of-range handler result (6a wrapper checks always · 6b `debug_assert` only); Q7a `PartialRandHandler` warning; Q7b single `u64()` op; Q7c literal empty range is a compile error; Q7d fix-it for `rand.int(0, 10)`; P6 default handler wording (properties only · name the algorithm).

**Tally:**

- **Q1:** 1b, 6-0
- **Q1-U:** yes, 6-0
- **Q2:** 2a, 4-2 (web, devops: 2c) → Phase D
- **Q2-R:** yes, 6-0
- **Q3:** 3a, 6-0
- **Q4:** 4e, 5-1 (web dissent: 4b)
- **Q5:** 5a, 6-0
- **Q6:** 6a, 6-0
- **Q7a:** yes, 4-2 (plt, min: no) → Phase D
- **Q7b:** no, 6-0
- **Q7c:** yes, 4-2 (plt, min: no) → Phase D
- **Q7d:** yes, 6-0
- **P6:** properties only, 6-0

##### Systems

**Q1. Integer op**
**Vote:** 1b
**Reasoning:** The op passes two `Int`s in registers, with no `Range` struct to unpack inside each handler. It is total whenever `lo <= hi`, and it covers `Int.MIN..=Int.MAX`, which no half-open or `below` form can express. 1c overflows checked `Int` for spans wider than `Int.MAX`. 1a needs a public Range accessor API before anyone can write a handler for it (F1).
**Concern:** The wrapper's Range read could be built as a one-off compiler intrinsic that never becomes a general Range accessor, so the next Range-taking API hits F1 again.

**Q1-U. Exact uniformity**
**Vote:** yes
**Reasoning:** Modulo bias is a silent correctness bug. Lemire's method costs one widening multiply and almost never rejects. A guarantee that names no algorithm forbids a future modulo "fast path" and leaves the implementation free.
**Concern:** Users who write their own handlers may not know the guarantee binds them too, so the docs must state it on the op, not only on the default handler.

**Q2. Helpers**
**Vote:** 2a
**Reasoning:** The handle should expose exactly the effect's ops (plus the same-name `int` wrapper), so the cost of a `rand.*` call is always one dispatch. Generic helpers are ordinary monomorphized functions with a `! Rand` row. 2b's module name collides with the reserved handle, and 2c makes the handle surface open-ended.
**Concern:** New users try `rand.shuffle` and hit an error, which Q2-R has to fix.

**Q2-R. Resolution rule plus targeted error**
**Vote:** yes
**Reasoning:** It costs nothing at runtime and turns the likeliest mistake under 2a into a one-step fix. It also locks in the handle-only resolution, so a free fn can never capture a handle call. We already hit that bug with `fs` and `net`.
**Concern:** The fix-it must name `std.random`, and it must keep doing so if helpers move or grow.

**Q3. Helper set**
**Vote:** 3a
**Reasoning:** I withdraw `float_in` and `sample`. plt and min are right that `lo + rand.float() * (hi - lo)` can round up to `hi`, so my own helper had a bug. `shuffle` and `choice` are the two where hand-rolled code goes wrong (Fisher-Yates bounds, an empty list).
**Concern:** None worth noting. Users will add `chance` themselves.

**Q4. Production seeded generator**
**Vote:** 4e
**Reasoning:** A seeded generator's contract is its stream, so it must name and freeze an algorithm. That is a separate, permanent decision this ticket does not need. My `Xoshiro256` value type (4d) is the zero-dispatch path for hot loops. I file it as a follow-up with the seeded question.
**Concern:** Simulation and game users will import `std.testing.mock_rand` into production code in the meantime.

**Q5. Secrets**
**Vote:** 5a
**Reasoning:** One effect with a CSPRNG default costs about 1 ns per draw on top of dispatch, and it removes the weak-default class of bug. plt's `Crypto.Random` is a type-level split with zero runtime cost, but it belongs in the Crypto spec. File it there.
**Concern:** A key-generation API typed `! Rand` would accept `mock_rand`, until the Crypto spec settles where key entropy comes from.

**Q6. Out-of-range handler result**
**Vote:** 6a
**Reasoning:** One predicted compare-and-branch, about 0.3 ns, against 2 to 5 ns of indirect dispatch. It blames the broken handler at the point of the break, not a wrong `None` from `choice` in a release build. Check once in the wrapper, never in each helper.
**Concern:** The check must not leak into the default handler's own hot path twice: the wrapper checks, and the default handler does not check again.

**Q7a. PartialRandHandler warning**
**Vote:** yes
**Reasoning:** A user-written seeded handler in production code that implements only `int` silently draws `float` and `bytes` from the CSPRNG. The runner's per-installation seeding does not cover that case. Writing `default.float()` explicitly silences the warning, so delegating on purpose stays clean.
**Concern:** min may be right that this belongs in a general partial-handler lint, and a Rand-only version may need to widen later.

**Q7b. Single primitive op `u64()`**
**Vote:** no
**Reasoning:** It breaks the decided "one op call = one draw" rule. It also turns `rand.bytes(4096)` from one bulk fill into 512 indirect dispatches. The op set exists to amortize dispatch.
**Concern:** None. This option has been withdrawn.

**Q7c. Literal empty range is a compile error**
**Vote:** yes
**Reasoning:** When both ends are literals, the call is a certain panic. Reporting it at compile time costs nothing at runtime, and the check is a constant fold over two literals.
**Concern:** Scope creep, from people asking for the same check on every Range-taking API. Keep it limited to both-ends-literal.

**Q7d. Fix-it for `rand.int(0, 10)`**
**Vote:** yes
**Reasoning:** It is diagnostic only, with no runtime or spec surface. It catches the likeliest call-site mistake under 1b, where the op has two args and the call takes one.
**Concern:** The fix-it must suggest `0..10` and mention `..=`, so Python-trained users do not lose the top value without noticing.

**P6. Default handler wording**
**Vote:** P6-prop
**Reasoning:** Name properties, not ChaCha, so the algorithm can change without a spec change. The property list must include two items: a forked child never repeats its parent's stream, and threads never share one stream. Both are observable security properties.
**Concern:** If the property list drops fork safety or thread separation, a conforming implementation could leak the same stream into two processes.

##### Web/Scripting

**Q1. Vote: 1b**
Reasoning: Users write `rand.int(1..=6)`, so the bound type shows in the syntax, and Python's randint-vs-randrange confusion never starts. Handler authors, the 10% case, get two plain Ints with no Range accessor needed. This copies the §4.4 IO pattern, which people already know.
Concern: If the raw two-Int form ever leaks to user code, `rand.int(0, 10)` would compile with closed-interval meaning and cause silent off-by-one bugs. The handle must expose only the Range wrapper.

**Q1-U. Vote: yes**
Reasoning: Every user already assumes `rand.int` is fair. Promising it costs one sentence and stops a future "fast" modulo path.
Concern: User handlers may ignore the promise, and nothing can check it at runtime.

**Q2. Vote: 2c**
Reasoning: Python's `random.shuffle(xs)` becomes `rand.shuffle(xs)` with no import, and `rand.` autocomplete shows all of it. 2a makes newcomers learn two names (module `random`, handle `rand`) for one concept, which will be a recurring Stack Overflow question.
Concern (2a expected to win): New users will type `rand.shuffle` or `random.int` on day one. Without the Q2-R fix-it, they hit a dead end.

**Q2-R. Vote: yes**
Reasoning: If 2a wins, this diagnostic is what makes it work for newcomers. It turns the most common first mistake into a one-keystroke fix.
Concern: The error must name the exact import line, or it is just a longer way to say "unknown".

**Q3. Vote: 3a**
Reasoning: I drop `chance`, since `rand.float() < p` reads clearly. `float_in` has a rounding bug (min and plt), and `sample` has an unspecified edge case. Ship the two that people get wrong by hand.
Concern: Users will ask for `sample` and weighted choice soon, so file them so they do not get lost.

**Q4. Vote: 4b**
Reasoning: Games and procedural generation are a real web/scripting use case ("share your world seed"), and production code should not import `std.testing`. But the seed is the contract, so it ships only if the algorithm is named and the stream stays the same across versions.
Concern (4e expected to win): Users who want reproducible worlds will import `mock_rand` into production code because nothing else exists. The follow-up ticket must not rot.

**Q5. Vote: 5a**
Reasoning: One effect with a safe default means nobody has to choose, and Python's random/secrets split is a CVE generator. Crypto key entropy belongs in the Crypto spec.
Concern: A seeded handler installed around key-generating code makes keys predictable, and `! Rand` gives no warning.

**Q6. Vote: 6a**
Reasoning: "Rand handler contract violated: int(0, 4) returned 7" points at the user's buggy mock. An index error inside `shuffle` points at the stdlib and costs an afternoon. One compare per draw is cheap.
Concern: The message must name the op and its arguments, or users will still blame the stdlib.

**Q7a. Vote: yes**
Reasoning: A partial mock that silently falls through to the OS RNG makes a "deterministic" test flaky with no hint why.
Concern: Handlers that delegate on purpose need an obvious way to silence the warning, for example an explicit delegate call.

**Q7b. Vote: no**
Reasoning: It reopens §4.3 and the one-op-one-draw rule, and the 7a lint covers the hazard.
Concern: None for "no". The lint must carry the load.

**Q7c. Vote: yes**
Reasoning: `rand.int(5..5)` with literal ends always panics, so catching it at compile time is free.
Concern: It must fire only when both ends are literals, or it will flag valid computed ranges.

**Q7d. Vote: yes**
Reasoning: Every Python and JS developer will type `rand.int(0, 10)` on day one. A fix-it that also explains `..=` removes the single most common question.
Concern: The note must say clearly that `..` excludes the top and `..=` includes it, or the fix just moves the off-by-one.

**P6. Vote: P6-prop**
Reasoning: Users rely on properties (unpredictable, OS-seeded, distinct across threads and after fork), not on ChaCha. If the algorithm stays out of the spec, it can change without a spec change.
Concern: "Unpredictable" is hard to test, so the stdlib suite should at least check the fork and thread properties.

##### PLT

**Q1. Vote: 1b**
Reasoning: The op domain `{(lo, hi) | lo <= hi}` is total, has one case, and includes the full `Int` range. Handler authors need no Range API (F1). The user surface `rand.int(r: Range[Int])` follows the F3 pattern: a monomorphic op with a wrapper over it. 1a makes the op partial and needs a public Range accessor API first. 1c is not closed under intervals, because `lo + rand.int(hi - lo)` overflows.
Concern: the wrapper must still read Range bounds privately (an intrinsic or a stdlib-internal accessor). That gap must be closed explicitly, and it must not become an ad hoc one-off that leaks into user code.

**Q1-U. Vote: yes**
Reasoning: Uniformity is part of the op's meaning. Without it, `rand.int` has no specified distribution, and `shuffle` has no claim to produce uniform permutations. Naming no algorithm keeps the guarantee semantic, not operational.
Concern: no one can check this for user handlers, so the spec must call it a contract obligation on the handler, not something the wrapper checks.

**Q2. Vote: 2a**
Reasoning: With 2a, the handle's interface is the effect signature plus op wrappers, and nothing else. `shuffle[T]` is an ordinary generic function with row `! Rand`, and effect polymorphism composes through it with no new mechanism. `std.rand` would bind `rand` over a reserved handle.
Concern: users will write `rand.shuffle` by analogy with `io.println`, so Q2-R's diagnostic is required, not optional.

**Q2-R. Vote: yes**
Reasoning: Name resolution must not depend on what has been imported: `rand.<name>` always means the handle. The targeted error turns the 2a analogy trap into a one-step fix.
Concern: the rule must be written for all handles, not as a special case for `rand`.

**Q3. Vote: 3a**
Reasoning: `float_in`'s naive form `lo + f * (hi - lo)` can round to `hi`, so a half-open `[lo, hi)` claim would be false. A helper whose stated range is wrong is unsound. `chance` gives a second name to `rand.float() < p`.
Concern: none of substance. Later helpers must come with exact range and draw-count specs.

**Q4. Vote: 4e**
Reasoning: A seeded handler's meaning is its stream. Without a frozen algorithm, `seeded(42)` has no meaning across versions, so 4c is unsound and I withdraw it. Freezing an algorithm forever (4a) is a separate, permanent commitment that no blocked ticket needs. Deferring is safe because adding a handler factory later is a pure addition.
Concern: users will reach for `std.testing.mock_rand` in production in the meantime. The filed ticket should say so.

**Q5. Vote: 5a**
Reasoning: The interposability hazard is real (`! Rand` cannot show whether a handler is secure), but it belongs in the Crypto spec. Record this note there: "Crypto key APIs draw entropy under `! Crypto`, not `! Rand`".
Concern: without that Crypto follow-up, a future key API typed `! Rand` would accept `mock_rand` as a key source.

**Q6. Vote: 6a**
Reasoning: Handlers are user values whose postconditions the type system cannot prove, so the boundary must check them. Otherwise a derived helper (`choice` returning `None` on a non-empty list) is silently wrong in release builds. The check is one compare, it lives in the wrapper that 1b creates anyway, and it blames the right party.
Concern: the panic message must name the op, its arguments and the bad result, or the blame is lost.

**Q7a. Vote: no**
Reasoning: min is right on uniformity. Partial-handler auto-delegation (§4.7.1) is a property of every effect, so a Rand-only warning is an ad hoc rule. The principled fix is one general partial-handler lint, filed separately, which then covers Rand.
Concern: if the general lint never ships, partial Rand mocks stay silently nondeterministic outside a runner-seeded context.

**Q7b. Vote: no**
Reasoning: It reopens the decided §4.3 op list and the "one op call = one draw" rule. It also makes `bytes(n)` cost a number of draws that depends on n.
Concern: none if it is rejected.

**Q7c. Vote: no**
Reasoning: A compile error tied to one op's argument is a non-uniform special case. A general constant-empty-range lint, or refinement typing later, is the principled form.
Concern: a literal empty range will panic at runtime until the general lint exists. The panic message covers it.

**Q7d. Vote: yes**
Reasoning: It is a diagnostic only, with no change to the typing rules. It catches the most likely cross-language mistake.
Concern: the fix-it must suggest `..` and mention `..=`, not guess which one the user meant.

**P6. Vote: P6-prop**
Reasoning: The spec should state observable properties: unpredictable, seeded from OS entropy, distinct streams across threads and after fork. Naming an algorithm adds no guarantee a program can rely on, and it would freeze the implementation.
Concern: "distinct streams after fork" must be stated precisely enough to test.

##### DevOps/Tooling

**Q1. Integer op**
**Vote:** 1b
**Reasoning:** Callers keep `rand.int(1..=6)`, so the `..`/`..=` choice is in the source text, signature help shows a `Range[Int]`, and the 7c/7d diagnostics have something to check. Handler authors get two plain Ints, a closed interval, total when `lo <= hi`, and able to express the full `Int` range. Hover and docs never show a parameter that the user cannot read (F1).
**Concern:** The op takes 2 args and the call takes 1. Unless the LSP shows the wrapper signature at call sites and the op signature only inside `handler Rand { }`, users will see the wrong signature in hover and completion.

**Q1-U. Exact uniformity as a spec guarantee**
**Vote:** yes
**Reasoning:** The stdlib suite can test it (chi-square), and it blocks a future modulo "fast path". The spec states the property and names no algorithm.
**Concern:** The rule binds every handler, but no tool can check a user handler for bias, so for user mocks the promise is documentation only.

**Q2. Helpers**
**Vote:** 2c
**Reasoning:** `rand.` completion shows every random operation with no import step, the capability shows at the call site, and new users never hit "unknown function `shuffle`". F4 then works as written, with `rand.` in front.
**Concern:** I expect 2a to win. Its first-day experience depends on Q2-R: the targeted fix-it for `rand.shuffle` and an LSP auto-import for `shuffle`. Without both, users get a bare "unknown method".

**Q2-R. `rand.<name>` resolves to the handle; `rand.shuffle` gets targeted fix-it**
**Vote:** yes
**Reasoning:** Under 2a, `rand.shuffle(xs)` is the most likely mistake from Python habit and from completion muscle memory. The error must list the real ops (`int`, `float`, `bytes`) and give the exact `import std.random.{shuffle}` line. It also stops a stdlib free fn from capturing an intrinsic call, which we already hit with `fs` and `net`.
**Concern:** The resolution rule needs a test, or a later helper whose name matches an op will reopen the capture bug.

**Q3. Helper set**
**Vote:** 3a
**Reasoning:** Fewer names means fewer completion entries and fewer docs pages. `chance` is `rand.float() < p`. As plt and min showed, a naive `float_in` can round up to `hi` and break its own stated range.
**Concern:** Users will write their own `sample` with an off-by-one, and no diagnostic will catch it.

**Q4. Production seeded generator**
**Vote:** 4e
**Reasoning:** Users keep seeds in config files and bug reports. A stream that changes on a compiler upgrade turns every release into a support ticket, so `seeded` ships only with a named, frozen algorithm (4a), and that is its own decision. Deferring breaks nobody.
**Concern:** Until it ships, production code will import `std.testing.mock_rand` to get a seed. We should file the follow-up ticket now, and maybe add a lint for `std.testing` imports outside tests.

**Q5. Secrets**
**Vote:** 5a
**Reasoning:** One generator and a safe default means no "you used the weak one" lint category. I keep my note for the Crypto spec: std's key APIs draw entropy under `! Crypto` or from the OS, never through `! Rand`.
**Concern:** If the Crypto spec never picks up that note, a `with mock_rand(0)` around key generation silently weakens keys, and no warning will fire.

**Q6. Out-of-range handler result**
**Vote:** 6a
**Reasoning:** "Rand handler contract violated: `int(0, 4)` returned 9" points at the user's mock. An index-out-of-bounds three frames into `std.random` points at the stdlib. One compare per op costs nothing next to handler dispatch.
**Concern:** The panic text must name the op, the arguments and the value returned. A generic "contract violated" message throws away the diagnostic benefit.

**Q7a. `PartialRandHandler` warning**
**Vote:** yes
**Reasoning:** A mock that overrides only `int` silently sends `float` and `bytes` to whatever handler encloses it. That breaks the independence that `mock_rand(seed)` promises, because the output now depends on the suite seed or the OS. Writing `default.float()` explicitly silences it, so a handler that delegates on purpose stays clean.
**Concern:** Min is right that the hazard applies to every effect. If we ship a lint for Rand only, other effects will each grow their own, so a general rule may be needed later.

**Q7b. Single primitive op `u64()`**
**Vote:** no
**Reasoning:** I withdrew it. It reopens §4.3 and the "one op call = one draw" rule, and 7a covers the same hazard.
**Concern:** None. I do not expect it to win.

**Q7c. Literal empty range → compile error**
**Vote:** yes
**Reasoning:** `rand.int(5..5)` always panics. If the compiler can see that, the error belongs at compile time with a caret on the range, not as a runtime panic.
**Concern:** A Rand-only special case may duplicate a later general constant-empty-range lint, so it should share that lint's diagnostic code when one exists.

**Q7d. Fix-it `rand.int(0, 10)` → `rand.int(0..10)`**
**Vote:** yes
**Reasoning:** Every Python-trained developer and model will type this on day one. The fix-it, plus a note that `0..=10` includes 10, turns an arity error into a one-keystroke repair.
**Concern:** If the raw two-Int op is reachable from user code, this call compiles with closed-interval meaning, so the handle must expose the wrapper only (aiml's condition).

**P6. Default handler wording**
**Vote:** P6-prop
**Reasoning:** Users can rely on the properties: unpredictable, seeded from OS entropy, distinct streams across threads and after fork. If the spec names the algorithm, swapping it becomes a spec change and gives users nothing they can check.
**Concern:** "Distinct after fork" must be testable in the stdlib suite. Otherwise the property is documentation only.

##### AI/ML

**Q1. Vote: 1b**
Reasoning: Callers and models write `rand.int(1..=6)`, so the bound kind is in the syntax and the off-by-one decision never reaches memory. Handler authors, including models writing mocks, implement two plain Ints on a closed interval, and need no Range API that the spec lacks (F1). It follows the §4.4 IO op-plus-wrapper pattern, so a model has one pattern to learn.
Concern: The handle must expose only the one-arg wrapper; if `rand.int(0, 10)` ever reaches the raw two-arg op from user code, Python-trained code compiles with closed-interval meaning and the 7d fix-it cannot fire.

**Q1-U. Vote: yes**
Reasoning: Every model and user already assumes `rand.int` is uniform, so the spec should promise what code will rely on. Naming no algorithm keeps it one sentence.
Concern: A user handler can still break it silently, and no check catches bias; the doc must say plainly that this is a handler obligation.

**Q2. Vote: 2a**
Reasoning: The handle lists exactly the effect's ops, so a model writing a mock can tell from `rand.` what it must override. `std.random` matches training data (Python `random`) and does not collide with the reserved `rand` handle. Generic algorithms on the handle (2c) blur ops and helpers.
Concern: Models will still write `rand.shuffle(xs)` by analogy with `random.shuffle(xs)`, so 2a without Q2-R costs a round trip.

**Q2-R. Vote: yes**
Reasoning: `rand.shuffle(xs)` is the most likely first guess from any model trained on Python. A targeted error with a machine-applicable import fix makes that guess a one-step repair rather than a dead end.
Concern: The rule must stay a diagnostic and never turn into silent resolution to the free function, or there will be two spellings in the wild.

**Q3. Vote: 3a**
Reasoning: Models already write `rand.float() < p` without help. `float_in` is wrong at the edge (it can round to `hi`, as plt and min showed), and `sample` has an unspecified k > len case. Fewer names, fewer wrong choices.
Concern: Users will hand-write `float_in` with the same rounding bug; the docs should show the correct idiom.

**Q4. Vote: 4e**
Reasoning: A seeded production handler has value only if its stream stays stable across versions, which is a permanent spec commitment that nothing blocked on this ticket needs. If it ships later, 4a (algorithm named, stream frozen) is the only acceptable form; 4c would give world seeds that silently drift.
Concern: Until it ships, models will reach for `mock_rand` from `std.testing` in production code for games and simulations.

**Q5. Vote: 5a**
Reasoning: One effect with a secure default removes the `random`/`secrets` decision that models get wrong (CWE-338). The interposability point belongs in the Crypto spec: std Crypto key APIs should read OS entropy under `! Crypto`.
Concern: Until the Crypto spec says that, a key generator typed `! Rand` accepts a seeded mock with no warning.

**Q6. Vote: 6a**
Reasoning: "Rand handler contract violated: int(0, 4) returned 7" is an error a model can repair from the message alone. An index error deep inside `shuffle`, or a silently wrong `choice` in release builds, is not. Under 1b the wrapper exists anyway, so the cost is one compare.
Concern: The check must stay in the one wrapper and not get copied into each helper.

**Q7a. Vote: yes**
Reasoning: Without `--seed`, the runner picks a fresh seed each run, so an op a partial mock leaves out delegates to a stream that changes between runs, and the test is flaky. Models that write a mock for only the op they see in the code will hit this.
Concern: The warning must have an explicit silencer (call `default.*` explicitly) so a handler that delegates on purpose stays clean.

**Q7b. Vote: no**
Reasoning: It breaks the decided "rand.bytes(64) = one draw" rule and changes the §4.3 op list. 7a covers the same hazard for less.
Concern: (n/a — I expect it to lose.)

**Q7c. Vote: yes**
Reasoning: `rand.int(5..5)` always panics, so a compile error is the earlier, cheaper report of the same bug. It costs little.
Concern: It must fire only when both ends are literals, or it starts rejecting code that depends on the values.

**Q7d. Vote: yes**
Reasoning: `rand.int(0, 10)` is the most common error that models trained on Python or Go will make with this API. A fix-it to `0..10`, with a note to use `..=` to include the top, makes the error a one-step repair.
Concern: The note must not suggest that the two-arg form exists anywhere users can call it.

**P6. Vote: P6-prop**
Reasoning: Users and models depend on the properties (unpredictable, OS-seeded, distinct streams across threads and after fork), not on ChaCha. Naming the algorithm would make a swap into a spec change, and users gain nothing from it.
Concern: "Distinct streams across threads and after fork" must stay in the spec text; it is a security property, not an implementation note.

##### Minimalism

**Q1. Vote: 1b**
Reasoning: Of the three, only 1b adds no public surface and keeps the bounds visible at the call site. Handlers implement a total two-Int op, and users write `rand.int(1..=6)` through a wrapper, the same as the IO precedent (F3). sys and plt also showed that my 1c moves the `hi - lo` overflow into user code, which settles it against 1c.
Concern: the wrapper must read Range bounds through a stdlib-private or compiler-known path. If that path leaks into a public Range accessor API "for consistency", we will have added surface on a core type with no vote.

**Q1-U. Vote: yes**
Reasoning: One sentence of spec guards against a latent bias bug and against a future modulo "fast path". It names no algorithm, so it adds no lock-in.
Concern: user handlers cannot be checked for uniformity, so the spec must word this as a contract obligation, not as something the wrapper enforces.

**Q2. Vote: 2a**
Reasoning: Free functions keep the handle equal to the capability, and the handle namespace stays closed to open-ended growth. `std.random` avoids the reserved-handle collision at no cost. The F4 example gains one import line.
Concern: newcomers will try `random.int(...)`. The docs and the Q2-R diagnostic must point them to `rand.int`.

**Q2-R. Vote: yes**
Reasoning: Under 2a no module binds `rand`, so the rule only states what is already true. Its real content is one targeted diagnostic, which adds nothing to the language.
Concern: none of substance. It must not grow into an auto-import mechanism that blurs ops and helpers.

**Q3. Vote: 3a**
Reasoning: `shuffle` is a known source of bias bugs, and `choice` is where the point-read rule matters, so both earn a place. `chance` is a second name for `rand.float() < p`. `float_in` showed its own rounding bug, which proves "trivial" helpers need a real spec.
Concern: pressure to add `sample` or `weighted_choice` one by one, each without a spec of its edge cases.

**Q4. Vote: 4e**
Reasoning: A seeded handler only has value if it promises the stream forever, and that is a large permanent commitment that nothing blocked on this ticket needs. A handler factory is a pure addition, so deferring breaks no one. File it with 4a's form as the only acceptable shape.
Concern: users will import `std.testing.mock_rand` into production code in the meantime. The follow-up ticket should note this misuse.

**Q5. Vote: 5a**
Reasoning: One effect with one safe default removes the `random` vs `secrets` decision entirely. Where Crypto key APIs get their entropy is a Crypto-spec question. Record plt's interposability note against that spec.
Concern: until the Crypto spec settles it, someone may build key generation on `! Rand`, and a seeded handler would weaken it without warning.

**Q6. Vote: 6a**
Reasoning: I conceded in the debate. A buggy mock that silently corrupts `choice` or `shuffle` in release builds fails the correctness bar. Under 1b the wrapper exists anyway, so the check is one compare.
Concern: the check must sit in the one op wrapper, not be duplicated in every helper.

**Q7a. Vote: no**
Reasoning: Partial handlers with auto-delegation are a general §4.7.1 mechanism. A lint that fires for one effect special-cases the language. A handler that delegates on purpose (logging, counting) would also need a silencing idiom. If the hazard is real, file a general partial-handler lint for all effects.
Concern: if it passes, expect pressure for `PartialTimeHandler`, `PartialEnvHandler` and so on, one lint per effect.

**Q7b. Vote: no**
Reasoning: It reopens decided item 1 and breaks "one op call = one draw". It also turns bulk `bytes(n)` into n/8 dispatches. Every seat, devops included, has dropped it.
Concern: none.

**Q7c. Vote: no**
Reasoning: It is a typecheck rule for one op's argument shape. A literal empty range is dead or buggy code in any position (loops included), so if it deserves a check, that is a general lint, not a `rand.int` special case.
Concern: if it passes, the rule must be specified for the wrapper only, with exact "both ends literal" wording, so it does not grow into constant folding through `let` bindings.

**Q7d. Vote: yes**
Reasoning: A diagnostic with a fix, and no language surface. It also enforces aiml's condition that the two-Int op form is not reachable from user code.
Concern: the fix must offer both `0..10` and `0..=10` so it does not assume which one Python-trained users meant.

**P6. Vote: P6-prop**
Reasoning: The spec states observable properties: unpredictable, OS-entropy seeded, distinct streams across threads and after fork. The algorithm is an implementation note. Naming ChaCha would make every algorithm change a spec change, with no user benefit.
Concern: "unpredictable" needs a precise enough wording (cryptographically secure) that an implementation cannot satisfy it with a weak PRNG seeded from entropy.

#### Phase D — Round 2 (Q2, Q7a, Q7c)

The focused debate covered only Q2, Q7a and Q7c. Every other question stayed decided.

**Debate:**

##### Systems

**Q2: holds at 2a**
**Strongest argument for 2c (web, devops):** `rand.shuffle(xs)` needs no import, and `rand.` completion shows everything.
**Answer:** Under 2c, the reserved handle namespace takes generic functions that no handler can override, and its surface grows with every helper. A reader can then no longer tell from `rand.x` whether the call is one dispatch to the installed handler or a stdlib algorithm making n − 1 dispatches. Under 2a, every `rand.*` call is one op and has one cost, and `shuffle` is a plain monomorphized function you can read. Q2-R already passed. With it and LSP auto-import, devops's first-day experience costs one accepted fix, not a dead end. Position holds.

**Q7a: changes from yes to no**
**Strongest argument for no (plt, min), now backed by F5:** partial handlers that auto-delegate are a decided, supported feature (5-0). §4.4 shows an Http handler that overrides only `get` as the intended pattern. The hazard, a partial mock falling through to a nondeterministic outer handler, exists in the same form for `Time`, `Env`, `Net` and every user effect.
**Answer:** I can't refute it. My production case (a seeded game handler that implements only `int`) is real, but it is the same bug as a partial `Time` mock reading the wall clock. A Rand-only warning puts a special case in the language and warns on a pattern the spec endorses. It also starts the one-lint-per-effect drift min predicts. The right tool is one general partial-handler lint with one silencing idiom (explicit `default.op`), filed as its own ticket. I change to **no**, on the condition that the general lint is filed.

**Q7c: changes from yes to no**
**Strongest argument for no (plt, min):** a constant empty range is a general property of the code, not a property of `rand.int`.
**Answer:** I checked for precedent. The spec does not make `7 / 0` or `7 % 0` with a literal zero a compile error. §3.4 lists it as a RUNTIME PANIC. Blink has no rule today that turns a certain panic from literals into a compile error (F6). Adding the first one for one wrapper's argument is a one-off rule that a user cannot predict from anything else in the language. The runtime panic message already names the op and the range. If certain-panic literals deserve compile-time errors, that is one general rule covering `/ 0`, `% 0` and empty ranges, filed separately. I change to **no**.

**Summary**
2a holds. Q7a: no. Q7c: no. Both on the condition that general lint tickets are filed (partial handlers; constant certain-panic expressions).

STABLE: yes

##### Web/Scripting

**Q2: I change from 2c to 2a**

The strongest argument against me is aiml's: when the handle lists exactly the effect's ops, a mock author (person or model) can read `rand.` and know what to override. Under 2c, `rand.shuffle` looks like an op, and the first mock someone writes tries to override it. That is a Stack Overflow question too, and a worse one than "where is shuffle", because the second has a one-line answer: the Q2-R fix-it. My real goal was that nobody hits a dead end on day one. 2a plus Q2-R plus LSP auto-import gets there. I move to 2a, provided that Q2-R ships with it, as every 2a voter's own concern already says.

**Q7a: I hold yes, but narrowly**

The strongest argument against me is F5 together with min and plt. Partial handlers are a decided, supported mechanism (Http overriding only `get`), so a lint that targets one effect is a special case. My answer: in general, partiality is the point of a handler. Rand is different: a Rand handler is almost always written for determinism, and partiality silently defeats that. The Http pattern is safe because a delegated `post` is still a correct `post`. A delegated `rand.float()` is a correct number from the wrong stream. A general lint would fire on the legitimate Http case and teach users to ignore it, which is worse than having none. The silencer (call `default.float()` explicitly) costs one line and states the intent. If a general lint ever lands, this one folds into it. Hold.

**Q7c: I change from yes to no**

The strongest argument against me is min's: a literal empty range is buggy code in any position, `for i in 5..5` included, so a check tied to one op is the wrong scope. My own seat's rule applies too: champion the 90% case. Nobody writes `rand.int(5..5)` with literal ends. Real empty ranges come from computed values (`0..xs.len()` on an empty list), and this rule cannot see those. The runtime panic already names the op and the range. One general "constant empty range" warning, filed separately, would help more users and give them one rule to learn instead of a special case. Change to no.

STABLE: yes

##### PLT

**Q2: holds at 2a**
**Strongest other argument (web):** with 2a, newcomers must learn two names, module `random` and handle `rand`, for one concept.
**Answer:** they are two concepts, and the language should keep them apart. `rand` is a *capability*: its members are exactly what a handler must or may interpret. `std.random` is *library code*: ordinary functions whose row includes `Rand`. Under 2c, `rand.` would mix the two, and every helper would read as overridable even though it is not. aiml made this point about mock authors, and it is a soundness-of-reading point too. IO already draws this line: `io.println` wraps an op, and nothing algorithmic lives on `io`. The newcomer cost is real, and Q2-R plus an LSP auto-import pays it. A blurred handle interface would be a cost forever.

**Q7a: holds at no; F5 strengthens it**
**Strongest other argument (devops, sys):** a mock that overrides only `int` silently sends `float`/`bytes` to the enclosing handler, which breaks the independence that `mock_rand(seed)` promises. An explicit `default.float()` silences the warning.
**Answer:** F5 settles the framing. The panel chose, 5-0, that partial handlers auto-delegate, and §4.7.1 says the type system "does not distinguish partial from total handlers". §4.4 presents a partial Http handler as a *supported use*. A warning that fires for `Rand` alone makes one effect's partiality suspect while every other effect's partiality stays endorsed. That is a non-uniform rule layered over a decided uniform one. The hazard is not Rand-specific either: a partial `Time` mock that overrides `now` and delegates `sleep` breaks determinism the same way. The `default.op()` silencer is a good idea, and it is exactly the shape a *general* "implicit delegation" lint would take. File that lint (F6: none exists) and let Rand get it for free. sys and devops already named this as their own Concern.

**Q7c: holds at no; the spec gives a principled form**
**Strongest other argument (sys, devops):** both ends are literals, so the call is a certain panic, and compile time is the cheaper place to report it.
**Answer:** the spec has already ruled on this pattern in two places.
1. **Literal precondition violations are runtime panics.** §2 uses `assert_panics { let _ = 10 / 0 }` as its canonical example. A literal division by zero is *not* a compile error. Under Q7c, `assert_panics { rand.int(5..5) }` would fail to compile, so the empty-range panic, which is now spec behavior, could not be tested with literals. Two literal precondition violations, `/` and `rand.int`, would get opposite treatment.
2. **The language already has a mechanism for "this argument violates a precondition, known statically": contracts.** §3b: `@requires` predicates are "checked by an SMT solver at compile time when possible". The principled form is a `@requires` on the `rand.int` wrapper that says the range is non-empty. The existing contract checker then reports literal violations with no new typecheck rule, and the same holds for any other Range consumer. Q7c re-implements a small, worse version of that machinery for one call.

I would vote yes on "the `rand.int` wrapper declares its non-empty precondition as a contract". I vote no on a bespoke error.

STABLE: yes

##### DevOps/Tooling

**Q2: I change my vote to 2a.**
**Strongest argument on the other side** (aiml, plt): under 2a, the list that `rand.` completion shows is exactly the list of ops a handler must override. Under 2c, a user who writes a mock sees `shuffle` in completion and cannot tell from it whether `shuffle` is an op. That is a tooling argument, and it beats mine. My "everything shows under `rand.`" benefit costs a confusing mock-authoring surface, and mocks are where tooling matters most for this effect. Q2-R gives the 2a newcomer path the same quality: a targeted error that names the ops and gives the import line, plus an LSP auto-import. **Changes: 2c → 2a.**

**Q7a: my position holds (yes). F5 changes the reason, not the vote.**
**Strongest argument on the other side** (plt, min): auto-delegation is a general §4.7.1 mechanism, so a lint for Rand only is an ad hoc rule. The fix should be one general partial-handler lint.

**Answer:** F5 rules out the general lint. Partial handlers are a supported idiom chosen 5-0, and §4.4 shows an Http handler that overrides only `get`. A lint that fired on every partial handler would fire on the documented, correct pattern. Users would learn to ignore it, and an ignored warning is worse than none. So the hazard is not "partial handler". It is "partial handler on an effect whose results the user mocks for determinism", and Rand is the clearest such effect. For Http, delegating to the real network is the point. For Rand, delegating to the OS or the suite seed breaks the independence that `mock_rand(seed)` promises, and it shows up as a flaky test with no hint why.

If the panel wants this to be uniform, the uniform form is an opt-in marker on the effect declaration, not a lint on every effect. That is new language surface and out of scope here. Until it exists, the Rand warning is the right scope. Writing `default.float()` explicitly silences it, so code that delegates on purpose stays clean. **Holds: yes.**

**Q7c: my position holds (yes), with the scope written down.**
**Strongest argument on the other side** (min): a literal empty range is dead or buggy code in any position, so the check should be a general lint, not a `rand.int` special case.

**Answer:** in other positions, an empty range is not a bug. `for i in 5..5 { }` runs zero times and is correct. The Str byte-slice decision makes range reads clamp, so `s.byte_slice(5..3)` is defined too. The case that is certainly a bug is "an empty range passed where empty panics", and today that set contains only `rand.int`. A "general" lint would therefore have exactly one member, so the special case and the general rule are the same thing.

I accept min's scope condition as the spec wording: the rule fires only when both ends are integer literals written directly in the argument, with no constant folding through `let` bindings. When a general "constant empty range to a panicking consumer" diagnostic exists, it reuses that rule's code. **Holds: yes.**

STABLE: yes

##### AI/ML

**Q2: I hold 2a**

**Strongest argument against (web, devops):** "With 2c there is no import, and `rand.` lists everything. 2a makes newcomers learn two names, `random` and `rand`, for one concept."

**Answer:** The two names stand for two things: a module of algorithms and a capability handle. For a model, the important question at `rand.` is which names a handler must implement. Under 2c, `rand.` lists 3 ops, the `int` wrapper and the generic helpers mixed together. A model writing a mock can no longer read the op set from the handle, and devops's own 2c needs a new `NotAnEffectOp` error to catch the confusion. Under 2a, the failure mode is `rand.shuffle(xs)`, and the Q2-R fix-it turns it into a one-step repair. One machine-applicable fix is cheaper than an open handle namespace that grows with every helper. **Position holds: 2a.**

**Q7a: I change to **no****

**Strongest argument against (plt, min), now backed by F5:** auto-delegation is a decided 5-0 mechanism. The spec says the type system does not distinguish partial from total handlers, and §4.4 shows a partial `Http` handler as a supported use.

**Answer:** I accept it. From my seat the deciding cost is consistency. A model learns from §4.4 that partial handlers are normal and supported. A warning that fires for `Rand` only teaches the opposite for one effect, and the model cannot work out that exception from the general rule. That is the kind of decision point I said I would flag. The hazard is real (without `--seed`, a delegated op reads a stream that changes between runs), but it is just as real for a partial `mock_clock`-style `Time` handler. File it as one general ticket: a partial-handler lint scoped to test or mock contexts, or a doc rule for `with handler` in tests. Do not ship a Rand-only rule. **Position changes: no.**

**Q7c: I change to **no****

**Strongest argument against (plt, min):** it is a special case for one op's argument shape. A general constant-empty-range lint is the principled form.

**Answer:** Two facts settle it for me:

1. **The spec already treats a literal certain panic as a runtime panic.** `10 / 0` is a runtime panic, and §2 has a test for it (sections/02_syntax.md:1498-1500). A model that learned "literal division by zero compiles and panics" would be wrong about `rand.int(5..5)` if 7c passed.
2. **7c makes the empty-range rule hard to test.** `assert_panics { rand.int(5..5) }` would not compile. To test a decided behavior, the stdlib suite and users would need a `let` to hide the literal. A rule that you can only test by working around it is a bad rule to teach.

A literal empty range is a rare error with a clear panic message. If a general constant-panic lint ever ships, it should cover `/ 0` and `rand.int(5..5)` together, as a warning. **Position changes: no.**

STABLE: yes

##### Minimalism

**Q2: I hold 2a**
**Strongest case for 2c (web, devops):** `rand.shuffle(xs)` needs no import, `rand.` completion shows everything, and newcomers learn one name instead of two.

**My answer:** that discoverability is a tooling problem, and Q2-R plus LSP auto-import solve it without changing the language. 2c changes what the handle *is*. Today the handle shows exactly what a handler must or may implement (§4.4: "the handle is a visual anchor that traces directly back to the capability"). Once generic algorithms live there, every reader and every mock author must learn which `rand.*` names are ops and which are not, and devops's own 2c needs a new `NotAnEffectOp` error to police that. The `io.println` precedent is a wrapper over one op, not a library of algorithms. 2c also has no end point: every later helper (`sample`, `weighted_choice`) goes into a reserved namespace that users and packages cannot extend, so third-party helpers would look second-class beside std ones. 2a keeps one rule: handle = ops, functions = functions. **Holds.**

**Q7a: I hold no**
**Strongest case for yes (sys, devops):** a partial mock or seeded handler that overrides only `int` silently draws `float` and `bytes` from an outer stream. That breaks the independence `mock_rand(seed)` promises, and explicitly writing `default.float()` silences the warning cheaply.

**My answer:** F5 settles the frame. Partial handlers with auto-delegation are a 5-0 decision. §4.4 presents overriding one op as a *supported* use, and §4.7.1 says the type system does not distinguish partial from total handlers. A Rand-only warning reverses that decision for one effect. It tells users "partial handlers are fine, except here", and forces a `default.x()` boilerplate idiom that exists nowhere else. The hazard is also smaller than claimed. Under `blink test`, the outer handler is runner-seeded and the seed is printed on failure (§8.10.4), so the failure reproduces with `--seed`. It is not a mystery flake. `mock_clock` has exactly the same exposure, and nobody proposed `PartialTimeHandler`. If the panel believes partial handlers are a hazard, that belongs in its own spec ticket that reconsiders F5 for every effect. That ticket should exist, and I will support filing it. **Holds.**

**Q7c: I hold no**
**Strongest case for yes (sys, web, aiml):** `rand.int(5..5)` with both ends literal is a certain panic, the check is a two-literal fold, and a compile error is the earliest report.

**My answer:** "certain panic" is only true if the line runs. A compile *error* rejects a whole program over a line in a dead branch or a generated table. The language does not do this elsewhere. §3.x shows integer division by zero as a runtime panic, F6 confirms no constant-empty-range check exists anywhere, and `for i in 5..5` is legal and empty. One op becomes the only place in Blink where a literal argument value is a type error. That is a special case that both users and spec readers must learn, and it buys nothing: the runtime panic already names `rand.int` and the range. If it is worth catching, a general *warning* for literal empty ranges in any position is the honest form, filed separately. If the panel passes 7c anyway, it should be a warning, not an error, so it does not reject programs. **Holds.**

STABLE: yes

**Vote:**

- **Q2:** 2a, 6-0 (was 4-2)
- **Q7a:** no, 5-1 (was 4-2 yes; devops dissent)
- **Q7c:** no, 6-0 (was 4-2 yes)

##### Systems

**Q2**
**Vote:** 2a
**Reasoning:** Every `rand.*` call stays one dispatch to the installed handler with one known cost, and helpers are ordinary monomorphized functions whose cost you can read. The handle namespace stays closed and equal to the op set, which mock authors and readers both depend on. Q2-R plus LSP auto-import covers the newcomer path.
**Concern:** Q2-R must ship together with this, or `rand.shuffle` is a dead end on day one.

**Q7a**
**Vote:** no
**Reasoning:** Auto-delegation is a decided 5-0 mechanism that §4.4 presents as supported (F5). The determinism hazard is the same for a partial `Time` mock, so a Rand-only warning is a non-uniform special case. Web and devops answer that a general lint would also fire on the legitimate Http pattern. That is an argument for an opt-in marker on the effect or a test-context lint, filed as its own ticket, not for hard-coding one effect now.
**Concern:** If no general ticket gets filed, partial Rand mocks stay silently nondeterministic outside runner-seeded contexts.

**Q7c**
**Vote:** 7c-none
**Reasoning:** F8: a literal `10 / 0` is a runtime panic and is tested with `assert_panics`. 7c-err or 7c-warn would treat `rand.int(5..5)` the opposite way, and 7c-err would make the decided panic impossible to test with literals. 7c-req is the right principle but cannot be written today. F1 means a `@requires` predicate on a `Range[Int]` has no accessor to name. Under F7, the default Unknown outcome is "won't compile", so without an explicit `fallback: "runtime"` the contract would reject every computed-range call such as `rand.int(0..xs.len())` that the solver cannot prove. It would also put a solver query on every call site, a compile-time cost a two-literal fold avoids. Revisit 7c-req once Range has accessors, as part of a general certain-panic ticket.
**Concern:** If 7c-req wins, the spec must state `@verify(fallback: "runtime")` on the wrapper and depend on the Range accessor ticket, or it does not compile.

##### Web/Scripting

**Q2. Vote: 2a**
Reasoning: I changed my vote in the debate, and the other replies confirm the change. If `rand.` lists only the ops, a mock author can see exactly what to override. Under 2c, `rand.shuffle` looks overridable, and that is a confusing question with no one-line answer. Q2-R plus LSP auto-import turns the newcomer's `rand.shuffle(xs)` into a one-step fix, which was my real goal.
Concern: If the Q2-R fix-it or the auto-import slips from the first release, every Python developer's first `rand.shuffle` hits a bare error.

**Q7a. Vote: no** (changed from yes)
Reasoning: Two points in this round moved me. First, min showed that under `blink test` the outer handler is runner-seeded and the seed is printed, so a partial mock gives a reproducible failure, not a mystery flake. That removes most of my argument. Second, aiml showed that "partial handlers are fine, except for Rand" is an exception nobody can work out from §4.4, and exceptions like that generate forum questions. The `mock_clock` exposure is the same, so this needs one general ticket, not a Rand-only rule.
Concern: The general partial-handler ticket must actually be filed. Outside the test runner (a seeded production handler that implements only `int`), the fall-through stays silent until it lands.

**Q7c. Vote: 7c-none**
Reasoning: F8 decides it for users: literal `10 / 0` compiles and panics, so `rand.int(5..5)` should do the same, or the language teaches two rules for one kind of mistake. Nobody writes a literal empty range in practice; real empty ranges come from computed values. I reject 7c-req for now. F1 means the precondition cannot be written yet, and under F7 the default for an unknown contract is "won't compile". Ordinary calls such as `rand.int(0..xs.len())` could then fail to compile, which is a far worse first-day experience than a runtime panic.
Concern: If 7c-req wins, the wrapper must set `@verify(fallback: "runtime")`, or common computed-range calls stop compiling.

##### PLT

**Q2. Vote: 2a**
Reasoning: The handle's interface must equal the effect's interpretable signature: ops plus same-name op wrappers. Then `rand.x` always means "the installed handler decides this". Generic algorithms are ordinary functions with row `! Rand`, and effect polymorphism composes through them with no new mechanism. All six seats now accept this distinction, web and devops through the mock-authoring argument.
Concern: Q2-R's fix-it and an LSP auto-import must ship with 2a, or the `rand.shuffle` analogy becomes a dead end.

**Q7a. Vote: no**
Reasoning: F5 is a uniform decision. Partial handlers auto-delegate, and the type system does not tell partial from total. A warning keyed to one effect's name reverses that for `Rand` alone. devops is right that a blanket partial-handler lint would fire on the endorsed Http pattern. That argues for a principled *opt-in* (devops's own idea: a marker on the effect declaration saying "results are mocked for determinism") as its own spec ticket. It does not argue for hard-coding `Rand` into the checker. `Time` has exactly the same exposure.
Concern: if yes wins, the spec should word it so a later general mechanism can absorb it, and should not promise per-effect lints.

**Q7c. Vote: 7c-none**
Reasoning: I withdraw my own 7c-req. F1 means the `@requires` predicate has no spec'd accessor to name. F7 makes it worse. Under the default fallback, an **unknown** verdict "won't compile", so every computed call such as `rand.int(0..xs.len())` would be rejected unless the wrapper sets `fallback: "runtime"`, and then every computed call emits a warning. A **disproven** literal call becomes a compile error, so `assert_panics { rand.int(5..5) }` fails to compile. That is the same F8 inconsistency I raised against 7c-err. With the contract option gone, the uniform answer is the one the spec already gives `10 / 0`: a runtime panic. Any static check should be a general certain-panic lint covering `/ 0` and empty ranges together.
Concern: a general certain-panic lint must be filed as a ticket. Otherwise "separate general ticket" means nothing gets built.

##### DevOps/Tooling

**Q2. Helpers**
**Vote:** 2a
**Reasoning:** Under 2a, the list that `rand.` completion shows is the list of ops a mock must override, so the handle stays a clear surface for tooling. Under 2c, my own design needed a `NotAnEffectOp` error just to fix the confusion it created. Q2-R plus an LSP auto-import handles the newcomer case with one machine-applicable fix.
**Concern:** If Q2-R or the auto-import code action slips past the first release, `rand.shuffle(xs)` gives a bare "unknown method" on day one. Both must ship with `std.random`.

**Q7a. `PartialRandHandler` warning**
**Vote:** yes
**Reasoning:** F5 makes partial handlers a supported idiom, so a general lint would fire on the correct Http pattern and teach users to ignore warnings. But for Rand, a delegated op gives a correct value from the wrong stream. Min says the runner seed makes the failure reproducible, but that does not answer the problem. `mock_rand(seed)` promises a stream that does not depend on the suite seed, and without `--seed` the test still flakes from run to run. The one-line `default.float()` silencer states the intent and costs almost nothing.
**Concern:** If "no" wins, the follow-up general ticket must exist before [the `--seed` + MockRand implementation ticket] ships MockRand. Otherwise the first flaky partial mock reaches users with no diagnostic and no plan.

**Q7c. Empty literal range passed to `rand.int`**
**Vote:** 7c-none
**Reasoning:** I change my vote. F8 and aiml's testability point beat my diagnostic argument. A literal `10 / 0` is a runtime panic in the spec, and a compile error on `rand.int(5..5)` would make `assert_panics { rand.int(5..5) }` impossible to write, so the empty-range rule could only be tested by hiding the literal behind a `let`. That is an unpredictable diagnostic, and an unpredictable diagnostic is worse than none. 7c-warn has the same noise problem inside `assert_panics`. 7c-req fails F1, because no accessor exists to name the bounds. F7 makes it worse: under the default **Unknown** → won't-compile outcome, every computed range would be rejected unless a fallback is set. The runtime panic already names `rand.int` and the range.
**Concern:** The general "certain-panic literal" warning (covering `/ 0`, `% 0` and empty ranges, and suppressed inside `assert_panics`) has to be filed as its own ticket, or this class of bug never gets a static check.

##### AI/ML

**Q2. Vote: 2a**
Reasoning: The handle lists exactly the ops a handler implements, so a model writing a mock reads the op set from `rand.` and never tries to override `shuffle`. The likely first error, `rand.shuffle(xs)`, gets the Q2-R fix-it and is a one-step repair. One rule to learn: handle = ops, functions = functions.
Concern: Q2-R and LSP auto-import must ship with the module, or the first-day error is a bare "unknown method" with no path forward.

**Q7a. Vote: no**
Reasoning: F5 makes partial handlers a supported, uniform mechanism, and a warning on one effect teaches models an exception they cannot work out from the general rule. The hazard is the same for a partial `Time` mock, and under `blink test` the outer stream is runner-seeded with the seed printed, so the failure reproduces. devops's opt-in marker on the effect is the uniform form; it belongs in its own ticket.
Concern: If yes wins, the `default.op()` silencer becomes boilerplate that exists for one effect only, and models will add it to other effects' handlers by mistake.

**Q7c. Vote: 7c-none**
Reasoning: F8 sets the precedent: a literal `10 / 0` is a runtime panic tested with `assert_panics`, and `rand.int(5..5)` should behave the same so the empty-range panic stays testable with literals. 7c-req fails on F1 and F7: `@requires` has no Range accessor to name, and under the default contract fallback an unknown verdict is "won't compile", which would reject every computed range unless the wrapper also picks `runtime`. Even then, a literal empty range is a disproven contract and a compile error, so it breaks the same `assert_panics` test. Any static check belongs in one general ticket that also covers `/ 0`.
Concern: If 7c-err or 7c-warn wins, the spec must state that `assert_panics` blocks still compile a literal empty range, or the decided panic cannot be tested as written.

##### Minimalism

**Q2. Vote: 2a**
Reasoning: The handle stays equal to the capability: `rand.` lists exactly what a handler may interpret, and functions stay functions. devops and web moved for the mock-authoring reason, which is the same line IO already draws (`io.println` wraps one op, and nothing algorithmic lives on `io`). Discoverability goes through Q2-R and LSP auto-import, not through language surface.
Concern: 2a only works if Q2-R's fix-it ships together with it. If the diagnostic slips, newcomers hit a bare "unknown method" on `rand.shuffle`.

**Q7a. Vote: no**
Reasoning: F5 is a 5-0 decision that partial handlers auto-delegate as a supported use. A Rand-only warning makes one effect's partiality suspect against a uniform rule. devops's "Rand is the effect people mock for determinism" applies equally to `Time` under `mock_clock`. The honest scope is one general ticket, for example an opt-in marker or a test-context lint, that covers every mocked effect.
Concern: if yes wins, the spec must state why `Rand` alone gets the warning, or every mocked effect will ask for its own.

**Q7c. Vote: 7c-none**
Reasoning: F8 shows that the spec treats a literal certain panic (`10 / 0`) as a runtime panic tested with `assert_panics`. 7c-err breaks that, and so does 7c-req, because a disproven contract is also a compile error (F7). 7c-req also depends on F1: the predicate has no spec'd Range accessor to name, so it cannot be written today, and it would pull contract machinery into one op. 7c-warn is the least bad static form, but it is still a one-member rule, and the right home is a general constant-certain-panic warning covering `/ 0` and empty ranges together, filed separately.
Concern: if 7c-none wins and the general ticket is never filed, the idea dies quietly. The decision record should name the follow-up ticket.

### Final Spec

```blink
effect Rand {
    fn int(lo: Int, hi: Int) -> Int     // closed interval [lo, hi], lo <= hi
    fn float() -> Float                 // half-open [0.0, 1.0)
    fn bytes(n: Int) -> Bytes           // n >= 0, result length n
}

// std.random
pub fn shuffle[T](xs: List[T]) -> List[T] ! Rand
pub fn choice[T](xs: List[T]) -> Option[T] ! Rand
```

- User code calls wrappers only: `rand.int(r: Range[Int])`, `rand.float()`, `rand.bytes(n)`. `rand.int` maps `a..b` to `int(a, b - 1)` and `a..=b` to `int(a, b)`. An empty range panics with a message that names `rand.int` and the range. `bytes` with `n < 0` panics.
- Every handler must give exactly uniform results, with no modulo bias. No algorithm is named.
- Each wrapper checks every result in every build mode. A failed check panics with `Rand handler contract violated`, the op, its arguments and the value.
- `shuffle` returns a new list with exactly `xs.len() - 1` draws. `choice` returns `None` on an empty list. `std.random` holds nothing else.
- `rand.<name>` always means the handle. `rand.shuffle` is E0505 with a note listing the ops and a fix to import `std.random.{shuffle}`.
- `rand.int(0, 10)` and `rand.int(10)` get the fix `rand.int(0..10)` and a note that `0..=10` includes 10.
- No seed, reseed or fork op. No production seeded handler for now; a later one must name its algorithm and freeze its stream.
- One `Rand` effect. The default handler is a CSPRNG, described by properties only: unpredictable, seeded from OS entropy, no stream shared between threads, no stream repeated after a fork. It is fit for secrets, but an installed `with` handler replaces it.
- Rejected: a `PartialRandHandler` warning (a general partial-handler lint is a follow-up), a single `u64()` op, and a compile error for a literal empty range (a general constant-empty-range lint is a follow-up).
