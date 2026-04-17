[< All Decisions](../DECISIONS.md)

# Arena Allocation Semantics — Design Rationale

### Problem Statement

Spec §5.2 committed to opt-in arenas as an `! Arena` effect with `with arena { }` syntax and auto-promotion of return values. Four questions blocked implementation: (D1) what promotion actually does, (D2) how escape analysis classifies allocations, (D3) how the arena pointer reaches `blink_alloc`, and (D4) how nested `with arena` blocks compose.

This deliberation fixes those four points so the runtime primitive, escape-analysis pass, and promotion codegen can all be built against a single, consistent spec.

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on each question. Votes:

---

**D1. Promotion semantics at the `with arena { }` boundary.**

**Result: C — per-type compiler-generated walkers (4-1, DevOps dissented).**

Options considered:
- **A:** Deep copy every reachable pointer, cycles globally forbidden.
- **B:** Shallow copy (nested arena pointers = UB).
- **C:** Compiler-generated `blink_promote_<Type>` functions: deep for structs/lists/maps, `GC_MALLOC_ATOMIC` copy for strings, cyclic types rejected as compile error via escape analysis.
- **D:** Promotion only at outermost `with arena`; inner `! Arena` callees share the caller's arena.

Votes:
- **Systems:** C. A generic deep-copy walker is an indirect-branch nightmare on the I-cache. Per-type walkers are monomorphized straight-line code the C compiler can inline; strings hit `GC_MALLOC_ATOMIC` directly with no scan. Shallow (B) is a correctness footgun we'd pay for forever. D still needs a promotion walker somewhere.
- **Web:** C. B silently corrupts memory — #1 DX killer for opt-in perf features. A forbids cycles globally (teaching nightmare). D leaks arena semantics across function boundaries. C is the only option where `return x` behaves the way Python/JS devs expect.
- **PLT:** C. Soundness demands that a value typed `T` outside the `with arena` block have the same denotational meaning after the region closes. B breaks subject reduction. A is too coarse (cycles inside a region are fine). Per-type walkers are type-directed and compositional — analogous to how Koka derives evidence or how OCaml's `Marshal` walks by type.
- **AI/ML:** C. One mental model: "value leaves arena → compiler walks it." No hidden UB trap (kills B), no runtime cycle confusion (A), no lifetimes-in-disguise (D). Cycle-as-compile-error is self-correcting.
- **DevOps:** *(dissent)* D. Option D gives the cleanest diagnostic surface — LSP can answer "which arena owns this value?" by walking up to the nearest enclosing `with arena`. Per-type walkers explode `--emit c` output and make `--blink-trace codegen` unreadable.

---

**D2. Escape rules (compiler enforcement).**

**Result: D — sound-conservative + return-path exception (5-0).**

Options considered:
- **A:** Sound-conservative (any non-return flow = E0700). Over-rejects.
- **B:** Flow-precise interprocedural analysis. Accurate, whole-program.
- **C:** Type-level region variables (`! Arena[a]` — lifetime-style).
- **D:** Sound-conservative with a return-path exception: return expressions are classified as "promoted" (not escaped). Closure capture, field store on non-arena params, and passing to a non-arena-local parameter all trigger E0700.

Votes:
- **Systems:** D. B is a compile-time tax and fragile under separate compilation. C is Rust-grade complexity that blows up monomorphization and poisons every stdlib signature. A defeats the point by rejecting the common case. D matches spec §5.2, is local (per-function), and produces predictable codegen.
- **Web:** D. Matches the spec — consistency between docs and compiler is non-negotiable. B produces errors that reference call chains five hops deep. C is Rust, which Blink explicitly is not. A kills the feature's usefulness.
- **PLT:** D. C (Tofte–Talpin regions) is the theoretically correct answer for PLT grad students — not Blink's audience. B is unsound modulo separate compilation. A over-rejects. D is the minimum viable soundness: conservative everywhere *except* the syntactically-obvious escape path (the block's result expression), which is where §5.2 already committed.
- **DevOps:** D. The only option whose error messages are writable. §5.2 nailed the canonical E0700 phrasing; the return-path carveout is one note line. B's diagnostics collapse under non-locality. C requires teaching a type-system sublanguage before users can read an error.
- **AI/ML:** D. B is unpredictable whole-program analysis. C is lifetimes with a fresh coat of paint — same 30-40% failure mode Blink already rejected. D aligns the LLM's strongest training signal (the spec) with compiler behavior.

---

**D3. Handler plumbing — how does `blink_alloc` find the arena?**

**Result: D — hybrid TLS fast path + BlockHandler lifecycle (5-0 runoff).**

Options considered:
- **A:** New `blink_ev` slot: `arena: blink_arena_t*` field in effect evidence, threaded through `blink_alloc(ev, size)`.
- **B:** BlockHandler piggyback: `enter()` creates arena, `exit()` destroys. `blink_alloc` checks thread-local.
- **C:** Pure thread-local `__blink_current_arena`. `with arena` sets/restores via cleanup attribute. `blink_alloc` branches on TLS. No BlockHandler involvement.
- **D:** Hybrid: TLS fast path for `blink_alloc`, BlockHandler lifecycle for enter/exit/tracing/nesting. `with arena { }` is a `BlockHandler` impl whose `enter()` sets TLS and whose `exit(ok)` restores prior TLS and destroys the arena.

Round 1: A=1 (PLT), C=2 (Systems, AI/ML), D=2 (Web, DevOps). No majority → runoff between C and D (A eliminated).

Runoff votes (5-0 for D):
- **Systems (switched C→D):** Hot path is identical in both — `blink_alloc` is TLS load + bump pointer either way, so C buys nothing on perf. BlockHandler is already the load-bearing mechanism for `with expr as x { }`. Making arena the *one* `with`-block that bypasses it creates a special case in codegen. `enter()/exit(ok)` gives correct TLS save/restore on nested blocks for free and handles panic-path destruction like `with db.transaction`.
- **Web:** D. Web handlers live and die by observability — `--trace all` must see arena lifecycle events. Consistency with `with db.transaction { }` means scripters build one mental model for scoped resources, not two. Fast-path concern (C's single TLS load) is irrelevant at scripting scale.
- **PLT (switched A→D):** Least-bad of the two after A's elimination. Both demote `! Arena` to a marker effect, but D at least routes lifecycle through the same `BlockHandler` protocol as `db.transaction`, preserving compositional reasoning: one mental model for scoped resources, not two. C's bespoke codegen is a special case where soundness bugs breed.
- **DevOps:** D. Observability is the deciding factor. Pure TLS (C) is invisible to `--blink-trace` and `--trace all`; leaks and double-frees would be debugged by staring at emitted C with no lifecycle events to grep. BlockHandler enter/exit slot into existing NDJSON filter syntax.
- **AI/ML (switched C→D):** `with arena.scoped { ... }` mirroring `with db.transaction { ... }` gives LLMs one structural pattern to learn and reuse. Pure TLS makes the arena boundary disappear from the AST — observability is both a debugging and training-signal win.

Key constraint for implementation: `enter()` must capture the prior TLS value into the handler struct; `exit(ok)` must restore unconditionally. The invariant "BlockHandler stack top == TLS arena" is load-bearing and must be tested.

---

**D4. Nested `with arena { }` blocks.**

**Result: A — independent arenas per nesting (5-0).**

Options considered:
- **A:** Independent arenas. Each nested `with arena` creates a fresh arena; inner allocations freed on inner `exit()`. Values promoted out of inner → outer arena (if one exists) or GC heap.
- **B:** Inner inherits outer (no-op inside outer).
- **C:** Compile error on nesting.

Votes:
- **Systems:** A. Independent arenas give predictable, composable lifetime stories: inner = inner chunks, freed at inner `exit()`. B makes lifetimes depend on dynamic nesting depth, breaking local reasoning. C is a usability disaster — parsers and request handlers legitimately nest.
- **Web:** A. Matches every scoped-resource primitive a scripting dev already knows: nested `with open()` in Python, nested `try-with-resources` in Java. B is spooky action — syntax says one thing, semantics do another. C is hostile to library authors who can't know whether callers already opened an arena.
- **PLT:** A. Lexical scoping of handlers is the defining property of algebraic effects. Inner `with arena` shadows the outer handler — exactly how `handle` works in Koka, how `dynamic-wind` works in Scheme. B breaks this. C is cowardice dressed as safety.
- **DevOps:** A. One teachable rule: "each `with arena` is its own scope, values promoted at its `}`." B produces a tooling mess — which arena does a hover tooltip show? C is hostile in library contexts.
- **AI/ML:** A. Matches Zig/Odin semantics — LLMs' strongest arena prior from training data. B is a classic LLM footgun (syntax vs semantics mismatch). C bans legitimate scoped-temp-arena patterns.

Consequence for D1's walker: since the target of promotion depends on the outer context (another arena or the GC heap), `blink_promote_<Type>` signatures must accept a target allocator parameter, not hardcode `GC_MALLOC`.

---

### AI-First Review

All five panelists returned PASS on all five criteria (Learnability, Consistency, Generability, Debuggability, Token Efficiency). Highlights:

- `with arena { }` reuses existing BlockHandler surface — no new syntax to learn.
- One escape rule + one exception (return-path) fits on a single `blink llms --topic arena` page.
- E0700 with the §5.2 canonical phrasing is predictable and self-correcting.
- BlockHandler lifecycle makes arena enter/exit visible in `--blink-trace` and `--trace all` without new tracing machinery.
- No region variables, no lifetime annotations — `! Arena` is one token of effect syntax.

No criteria failed, no reconsideration needed.

---

### Concerns & Follow-ups

Collected from panelist dissents and concerns; these become implementation constraints for the runtime + codegen tasks:

1. **Walker code size (D1-C):** Only emit `blink_promote_<Type>` for types actually returned across a `with arena` boundary. Recursive/self-referential types get E0701 at codegen.
2. **Walker target allocator (D4-A × D1-C):** Walker signature is `blink_promote_<T>(value, target_allocator)`. Do *not* bake `GC_MALLOC` into the ABI.
3. **Escape analysis reach (D2-D):** "Passed to fn whose param isn't arena-local" requires the callee's `! Arena` signature to be visible; without that we over-reject helpers or silently miss escapes. Infer arena-transparency from `! Arena` in callee signatures.
4. **Flow through `if`/`match` (D2-D):** The return-path typing rule covers the final expression of the block *and* any expression flowing to it via `if` / `match` / early `return`. Nail this in the typechecker test suite.
5. **TLS + green threads (D3-D):** If Blink ever adds M:N scheduling, the arena pointer must be saved/restored on task switch. Document as an invariant for the future scheduler.
6. **TLS/handler drift (D3-D):** In `--debug` builds, assert that the BlockHandler stack top matches `__blink_current_arena` at every effect boundary. A trace-replay test should confirm enter/exit events match across Gen1 and Gen2 before landing D3-D.
7. **Per-iteration nested arena overhead (D4-A):** Nested `with arena` in hot inner loops pays two `enter()/exit()` costs per iteration. A perf lint or benchmark harness for deep nesting should precede any claim of "arena is faster than GC."
8. **`! Arena` is a marker effect (D3-D consequence):** `! Arena` in the effect row does *not* mean algebraic-effect dispatch — it only drives escape analysis. The spec must call this out explicitly or a future contributor will assume the effect row means something it does not.
