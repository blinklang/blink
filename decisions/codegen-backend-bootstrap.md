[< All Decisions](../DECISIONS.md)

# Codegen Backend & Bootstrap — Design Rationale

### Problem Statement

Pact compiles AOT to native binaries (§5.1, §6.1). The compiler will be self-hosted (written in Pact). Three questions:
1. What does the compiler emit to produce native code?
2. How does the self-hosted compiler bootstrap?
3. How are algebraic effects compiled?

### Options Considered

| Backend | Pros | Cons | Used by |
|---------|------|------|---------|
| **Emit C → cc** | Simplest, cross-compile for free, WASM via emscripten, every platform C supports | Two-phase compilation slower, no native stack maps | Nim, Chicken Scheme, Zig (stage1), Vala |
| **LLVM IR → llc** | Best optimization, wide targets | 500MB+ dep, SSA complex to emit, version churn, slow compilation | Rust, Swift, Julia, Crystal |
| **Cranelift (FFI)** | Fast compilation, self-contained | Fewer targets, no WASM output, FFI from Pact to Rust lib, less mature | Wasmtime, rustc (experimental) |

### Decision: Emit C (4-1)

**Phase 1 (v1.0):** Emit C, shell out to system cc/gcc/clang.
**Release builds:** `clang -O2` gives LLVM optimization without a separate backend.
**Phase 2 (optional, post-v1):** Evaluate Cranelift for self-contained builds if "needs cc installed" becomes a real user complaint.
**LLVM as standalone backend: rejected.** Massive dependency, version churn, no panel support.

### Algebraic Effects: Evidence-Passing Translation (Koka model)

Effects are compiled away *before* codegen via Koka-style evidence-passing (Leijen, ICFP 2021):
- Each effect type → slot in evidence vector (vtable of function pointers)
- Evidence vector threaded as hidden parameter
- **Tail-resumptive handlers** (common case in Pact) → direct function pointer call, zero overhead
- **Non-resumptive handlers** → return from handler function
- **One-shot resumptive handlers** → yield bubbling (heap-allocated continuation, rare)
- Backend never sees effects — just structs and function calls

Pact restricts to **one-shot continuations** (like OCaml 5). Multi-shot not required by spec.

### GC Integration: Shadow Stack (v1)

Generated C uses shadow stack for GC root tracking:
- Function prologue/epilogue registers/deregisters GC roots
- ~5-10% overhead on pointer-heavy code
- Escape analysis (§5.3) eliminates most roots (stack-allocated values skip shadow stack)
- Precedent: Go used shadow stack through v1.4 at production scale
- Upgrade path: LLVM backend could use statepoints for zero-overhead precise scanning

### Green Threads: Runtime Library (C)

M:N scheduling is a runtime concern, not codegen:
- C runtime library handles stack allocation/switching (ucontext/platform fibers)
- Compiler inserts cooperative preemption checks in function prologues
- Same model as Go

### Bootstrap Path (COMPLETE)

All three stages verified. Fixed-point proven across 6 generations.

```
Stage 0: Python compiler (legacy/py_bootstrap/pact/) ✓ [DEPRECATED]
         → compiles src/pactc.pact (Pact compiler written in Pact)
         → emits C → cc → gen1 native binary

Stage 1: gen1 (compiled by Stage 0, checked in at bootstrap/pactc_bootstrap.c) ✓
         → compiles src/pactc.pact → C → gen2 native binary

Stage 2: gen1 C output == gen2 C output → fixed point ✓
         → verified identical through gen6
         → bootstrap complete, Python interpreter no longer required
```

Self-hosting compiler: `src/pactc.pact` (amalgamated lexer + parser + codegen + driver). Uses parallel arrays instead of structs-in-lists (C backend limitation). Compiles hello, fizzbuzz, and itself.

### Panel Votes

- **Systems:** C primary. Shadow stack for GC. CPS + stack switching for effects. Optional LLVM later. Cranelift rejected (FFI coupling, insufficient targets).
- **PLT:** C primary. Evidence-passing makes backend irrelevant for effects. Koka proves it at scale. One-shot continuations only.
- **Web/DX:** Cranelift primary *(dissent)*. Wants Go-like zero-dep toolchain. Concedes C for bootstrap. Compilation speed concerns.
- **DevOps:** C primary. Ubiquitous toolchain. LLVM hard no. Optional Cranelift v1.x for self-contained builds.
- **AI/ML:** C primary. AI can write/debug/maintain C codegen easiest. Most training data. `clang -O2` for release = free LLVM optimization.

### Cross-Compilation & WASM

C backend delegates entirely to C compiler ecosystem:
- `CC=aarch64-linux-gnu-gcc pact build` → ARM64
- `CC=emcc pact build --target wasm32` → WASM
- `CC=x86_64-w64-mingw32-gcc pact build` → Windows
- `CC=musl-gcc pact build` → static musl binary

### References

- Leijen, "Type Directed Compilation of Row-Typed Algebraic Effects" (ICFP 2021) — evidence-passing
- Koka language (github.com/koka-lang/koka) — production evidence-passing to C
- Chicken Scheme — continuations in C via "Cheney on the MTA"
- Nim — production self-hosted compiler emitting C

