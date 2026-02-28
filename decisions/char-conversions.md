[< All Decisions](../DECISIONS.md)

# Char Conversions — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 3 questions. Resolves gap: "Int-to-char string conversion".

**Q1: Char → Int — how to extract codepoint value (4-1 for `.to_int()` + `From[Char] for Int`)**

- **Systems:** `.to_int()` is a zero-cost widening — single register mov at the C level. Consistent with the existing `.to_int()` pattern across all sized integer types in §3c.3. `From[Char] for Int` enables generic code.
- **Web/Scripting:** `.to_int()` shows up in LSP autocomplete when you type `c.to_`. Developers already know the `.to_X()` pattern. `code_point()` adds vocabulary burden.
- **PLT:** `code_point()` only — no `From` impl. `Char` is not numeric; `From[Char] for Int` puts Char into the numeric conversion lattice, creating a false conceptual model. Named method `code_point()` names the domain correctly. *(dissent)*
- **DevOps:** `.to_int()` is already in the LSP autocomplete pattern. `From[Char] for Int` enables compiler fix-it suggestions for type mismatches. No new error message templates needed.
- **AI/ML:** `.to_int()` follows the existing pattern — zero new rules for AI to learn. `code_point()` introduces a naming exception that forces models to remember a special case.

**Q2: Int → Char — how to construct Char from codepoint (4-1 for `TryFrom[Int] for Char` + `Char.from_code_point()`)**

- **Systems:** `Char.from_code_point(n)` is a range check + branch — cheap. Constructor belongs on the target type. `Int.to_char()` makes Int carry Unicode knowledge, which is a layering inversion.
- **Web/Scripting:** `Int.to_char()` mirrors `Char.to_int()` symmetrically and is discoverable when you have an `Int` in hand. Python's `chr(n)` is the closest analog. *(dissent)*
- **PLT:** `TryFrom[Int] for Char` is the only principled choice for a partial function. `Char.from_code_point()` follows the constructor pattern. `Int.to_char()` puts the dependency arrow backward.
- **DevOps:** `Char.from_code_point(n)` triggers LSP autocomplete from the destination type namespace. Error messages can suggest `Char.from_code_point(n)?` with the `?` operator visible.
- **AI/ML:** `Char.from_code_point()` mirrors the `TargetType.from()` convention. `Int.to_char()` makes a fallible conversion look like a normal widening method call.

**Q3: Char → Str — how to create single-char string (5-0 for `From[Char] for Str` + `.to_str()`)**

- **Systems:** Allocation cost is unavoidable regardless of API surface. `From[Char] for Str` is infallible and follows existing patterns. `.to_str()` enables method chaining.
- **Web/Scripting:** `c.to_str()` is the obvious name given `c.to_int()`. Interpolation-only isn't discoverable — devs type `c.` in LSP and need to see something useful.
- **PLT:** `Char → Str` is a total function within the text domain — `From[Char] for Str` models this correctly. Unlike `Char → Int`, this doesn't cross an abstraction boundary.
- **DevOps:** `From[Char] for Str` gives the compiler a hook to emit fix-it suggestions for type mismatches. `.to_str()` enables method chaining like `char_at(i)??.to_str()`.
- **AI/ML:** `c.to_str()` is the lowest-decision-point answer. Interpolation-only fails the "can AI write this from spec" test in programmatic contexts (map/collect).
