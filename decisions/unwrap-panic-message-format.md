[< All Decisions](../DECISIONS.md)

# `unwrap()` / `unwrap_err()` Panic Message Format — Design Rationale

### Status

Additive implementation decision (no panel, no spec edit). Recorded here because
it pins a user-observable runtime string; see "No spec contract" below for why
this is a decision rather than a spec change.

### Decision

When `.unwrap()` or `.unwrap_err()` panics, the emitted message embeds the
Display-rendered value of the arm that was actually present:

- `.unwrap()` on `Err(e)`:
  `panic: unwrap called on Err: <rendered> at <file>:<line>`
- `.unwrap_err()` on `Ok(v)`:
  `panic: unwrap_err called on Ok: <rendered> at <file>:<line>`

`<rendered>` is the Display rendering of the panicked-on arm value:

- Builtin scalars (`Str`, `Int`, `Float`, `Bool`, `Char`) render directly.
- Struct/enum arms with an `impl Display` render through the synthesized sealed
  `{T}_display`.
- An arm type with **no usable Display** falls back to the literal `<TypeName>`
  (e.g. `<MyErr>`). This is intentionally non-fatal: `.unwrap()`/`.unwrap_err()`
  have **no Display gate** (unlike a test-body `?`, whose E0514 guarantees a
  Display impl upstream). Emitting a panic that omits the value is strictly
  better than rejecting valid code, so no diagnostic is raised.

`Option.unwrap()` on `None` is **unchanged**: `unwrap called on None`. `None`
carries no payload, so there is nothing to render. The Option/None path keeps
the payload-free guard; only the Result path gained the rendered variant.

The `<file>:<line>` location suffix is preserved exactly as before (synthesized
nodes still render their line as `<synthesized>`).

### Rationale

A bare `unwrap called on Err` forces the user back to a debugger to discover
*which* error tripped the unwrap. Embedding the rendered value turns a panic
into a self-describing diagnostic — the dominant ergonomic win other languages
(Rust's `Result::unwrap` printing the `Debug` of the error) have long shipped.

The rendering machinery already existed: test-body `?` propagation renders its
error through Display via `render_result_arm_value` (shared in
`codegen_types.bl`). The unwrap panic path now routes through the same helper,
so there is a single source of truth for "render a Result arm via Display."

### No spec contract

The language spec does **not** pin the text of an unwrap panic message. The only
normative contract over panic message contents is `assert_panics matching:`
(see `decisions/assert-panics-semantics.md` and the `sections/` reference),
which matches a caller-supplied **substring** and explicitly treats the rest of
the message as volatile. Because no spec clause constrains this string, adding
the rendered value is purely additive and does not change any guarantee Blink
makes to its users. It is therefore recorded as an implementation decision, not
a `type:spec` change.

### Edge cases

- **Scalar render emits an `snprintf` setup before the guard.** This is a
  harmless inactive-union read on the success path (the value is only formatted
  into a stack buffer; the guard then decides whether to print). This mirrors
  the existing test-body `?` behavior and is left as-is.
- **No double evaluation.** The receiver is snapshotted into a `tmp` before the
  guard; the rendered expression reads `tmp.err` / `tmp.ok`, never re-evaluating
  the original expression.
