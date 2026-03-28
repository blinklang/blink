[< All Decisions](../DECISIONS.md)

# io.print Vtable Dispatch — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently. Resolves spec gap: "`io.print` and `io.eprint` lack vtable dispatch and trace effects, unlike `println`/`eprintln`/`log`."

**Vote: 4-1 for Option C (Explicit raw escape hatch)**

### Problem

The spec (§4.4) claimed `io.print(...)` was the `IO.Print` operation, but the implementation mapped `io.println` to the vtable and `io.print` to a direct `printf` call. This caused:

1. **Silent test coverage gap** — `capture_print` could not intercept `io.print` output
2. **Observability hole** — `io.print` and `io.eprint` emitted no trace effects
3. **Inconsistency** — `io.eprintln` emitted traces but not `io.eprint`
4. **Spec-implementation mismatch** — spec said `io.print` was the IO.Print operation, but it wasn't

### Options Considered

- **A: Full alignment** — All io.* operations through vtable. Rejected: expands vtable unnecessarily, stderr operations don't need interception for v1.
- **B: Newline variants only** — Only `io.eprintln` gets vtable dispatch via new `IO.Eprint` sub-effect. PLT expert's preference (1 vote). Defers `io.print` alignment.
- **C: Explicit raw escape hatch** — Make `io.print` vtable-dispatched, add `io.print_raw`/`io.eprint_raw` as direct-to-C escape hatches. **Winner (4 votes).**
- **D: Status quo + spec fix** — Just update docs. Rejected: doesn't fix the testing gap.

### Decision

1. `io.print(x)` dispatches through the IO vtable's `print_no_nl` entry (no newline). Interceptable by `capture_print`. Emits trace effects.
2. `io.println(x)` continues dispatching through the IO vtable's `print` entry (with newline). No change.
3. `io.log(x)` continues dispatching through the IO vtable's `log` entry. No change.
4. `io.print_raw(x)` / `io.eprint_raw(x)` are direct-to-C escape hatches (`printf`/`fprintf`). No vtable, no trace. For streaming JSON, progress indicators, and other cases where interception is harmful.
5. `io.eprint(x)` and `io.eprintln(x)` remain direct (no vtable) but now emit trace effects.
6. `IO.Eprint` sub-effect deferred to future work.

### Dissent (PLT Expert)

The PLT expert argued that `io.print` (no newline) and `io.println` (with newline) have different algebraic properties — message-oriented vs stream-oriented. A handler receiving incomplete fragments from `io.print` cannot meaningfully process them without buffering. The expert preferred Option B, deferring `io.print` vtable dispatch until a proper stream-vs-message distinction could be formalized. The majority considered this a valid theoretical concern but not blocking for v1 — practical testability outweighs the semantic purity argument.

### Implementation

- `bootstrap/runtime_core.h`: Added `print_no_nl` entry to `pact_io_vtable`
- `src/codegen_methods.bl`: `io.print` → vtable dispatch; added `io.print_raw`/`io.eprint_raw`; added trace effects to `io.print`/`io.eprint`
- `lib/std/testing.bl`: `capture_print` handler intercepts both `print` and `print_no_nl`
- `src/cli.bl`: Raw output calls migrated to `io.print_raw`/`io.eprint_raw`
- `sections/04_effects.md`: Updated §4.4 to document all IO operations and their dispatch modes
