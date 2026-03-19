[< All Decisions](../DECISIONS.md)

# Set[T] Builtin Type — Implement or Remove

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on whether to implement `Set[T]` as a full builtin type, defer implementation, or remove the declaration.

**Q1: Set[T] implementation fate — implement now vs defer vs remove (4-1 for implement now)**

- **Systems:** Implement now. Set is Map minus the values array — cache-friendlier, avoids `Map[T, Bool]` runtime waste. The ~150 LOC C runtime is largely copy-paste from proven Map implementation. Deferring means users reach for `Map[T, Bool]` — the same antipattern Go developers universally hate.
- **Web/Scripting:** Implement now. Every major scripting language ships Set as a builtin. Having `SetOps[T]` declared but no working `Set[T]` is a DX trap: users see the trait, try to use Set, and hit a cryptic compile error. At ~300 LOC following the Map pattern, closing this gap is trivial.
- **PLT:** Defer. The orphan trait is vacuously sound (uninhabited type = no unsound programs possible). Deferral is acceptable if the gap is explicitly marked with a "not yet implemented" error. Risk: spec drift if trait system evolves without Set exercising generic code paths. *(dissent)*
- **DevOps:** Implement now. A declared trait in completions plus a spec'd type that errors is actively misleading tooling. This isn't "not implemented yet" — it's false advertising. The effort-to-tooling-quality ratio is excellent at ~300 LOC.
- **AI/ML:** Implement now. A spec'd-but-unimplemented type is the worst state for LLM code generation — a hallucination trap. LLMs reading the spec will confidently generate Set code that fails to compile, with no useful error recovery path.
