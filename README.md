# PL/0 Exploration

This project explores the design and implementation of simple programming languages, inspired by Niklaus Wirth's PL/0.

Currently in an initial work-in-progress state.

**Philosophy:**
- Keep languages small
- Progressive complexity — currently seven levels (e0–e6), each a superset of the previous
- Try several implementation approaches

The "e" in e0–e6 may stand for "experiment" or "exploration".

**Current state:**
- e1 (and e0) have two different working interpreters written in Koka, one in C++, and a compiler in C++ targeting LLVM IR.
- Benchmarks for level 1
- e2 through e6 have PEG grammars and example files, but no interpreters yet
- For each level, example code shows how to emulate higher-level features with lower-level primitives

## Quick Start

**Build/test:**
```bash
make              # Auto-detect mode and build
make test         # Run tests
make BUILD_MODE=native    # Force native build
make BUILD_MODE=podman    # Force Podman
make help         # Show all options
```

**Run implementations:**
```bash
make koka-pl0       # Koka interpreter
make koka-peg       # Koka PEG interpreter
make run            # C++ interpreter
make run-compile    # C++ compiler (C++ backend)
make run-llvm       # C++ compiler (LLVM JIT)
```

**Native setup** (optional — alternatively, tools are installed in a container):
```bash
source ./setup.sh
```
Installs Clang/LLVM and Koka on Linux (Fedora, Debian/Ubuntu) or macOS.

## Grammar Levels

| Version | Types | Features |
|---------|-------|----------|
| e0 | ℤ | sequential only, + - (not Turing-complete) |
| e1 | ℤ | + loop, break_ifz (Turing-complete, Minsky machine) |
| e2 | ℤ | + case statements, break, blocks |
| e3 | ℤ, 𝔹, () → T | + booleans, callables, case expressions |
| e4 | ℤ, 𝔹, [T], () → T | + arrays, pattern matching |
| e5 | ℤ, 𝔹, [T], {…}, () → T, unit | + records, unit literal |
| e6 | ℤ, 𝔹, [T], {…}, () → T, unit | + static typing, type definitions |

Each level is a strict superset of the previous.

## Examples

- [example.e0](examples/example.e0) — Sequential computation (e0)
- [example.e1](examples/example.e1) — Emulating e2 features in e1
- [factorial.e1](examples/factorial.e1) — Factorial benchmark
- [collatz.e1](examples/collatz.e1) — Collatz sequence iteration
- [gcd.e1](examples/gcd.e1) — Euclidean algorithm (GCD)

## Implementations

| Approach | Files | Notes |
|----------|-------|-------|
| Koka (hand-written parser) | `e1.koka` | AST used|
| Koka (PEG meta-interpreter) | `peg.koka`, `e1peg.koka` | Single-phase parse+execute, no AST |
| C++ interpreter | `e1.cpp`, `e1.hpp` | Handwritten, AST used |
| Compiler in C++ | `e1_compile.cpp`, `e1.hpp` | C++ or LLVM IR backend |

See [docs/IMPLEMENTATIONS.md](docs/IMPLEMENTATIONS.md) for details on each implementation.

## Benchmarks

```bash
make bench-1                           # default: 2000 iterations of 31!
make bench-1 BENCH_1_ARGS="100 20"     # custom: 100 iterations of 20!
```

Example results for `2000 31` (with bigint, INT_BITS=0):

| Implementation | Time |
|----------------|------|
| C++ backend | 16ms |
| LLVM backend | 15ms |
| LLVM lli (JIT) | 87ms |
| C++ interpreter | 0.73s |
| Koka interpreter | 2.1s |
| Koka PEG interpreter | 2.5s |

## Further Reading

- [docs/E1_SPEC.md](docs/E1_SPEC.md) — e1 language specification
- [docs/DESIGN.md](docs/DESIGN.md) — Language progression rationale, control flow design decisions
- [docs/IMPLEMENTATIONS.md](docs/IMPLEMENTATIONS.md) — Implementation details, integer bit width configuration
- [docs/PEG_SPEC.md](docs/PEG_SPEC.md) — PEG grammar specification
- [docs/minimal_turing_languages.md](docs/minimal_turing_languages.md) — Survey of minimal Turing-complete languages (Minsky machines, λ-calculus, etc.)
- [examples/](examples/) — All example programs for each language level
