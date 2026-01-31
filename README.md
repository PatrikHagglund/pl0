# PL/0 Exploration

This project explores the design and implementation of simple programming languages, inspired by Niklaus Wirth's PL/0.

Currently in an initial work-in-progress state.

**Philosophy:**
- Keep languages small
- Progressive complexity — currently seven levels (e0–e6), each a superset of the previous
- Try several implementation approaches

The "e" in e0–e6 may stand for "experiment" or "exploration".

**Current state:**
- e1 has a [language specification](docs/E1_SPEC.md), two Koka interpreters (AST-based and PEG), a C++ interpreter, and a C++ compiler (with C++ and LLVM IR backends)
- e0, e2, and e3 have PEG interpreters in Koka
- e3 has known limitations: no nested loop break, no recursive closures
- Benchmarks for levels 1, 2, and 3
- e4 through e6 have PEG grammars and example files, but no interpreters yet
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
make koka-e1        # Koka interpreter (e1)
make koka-peg-e0    # Koka PEG interpreter (e0)
make koka-peg-e1    # Koka PEG interpreter (e1)
make koka-peg-e2    # Koka PEG interpreter (e2)
make koka-peg-e3    # Koka PEG interpreter (e3)
make cpp-e1         # C++ interpreter
make cpp-e1-cpp     # C++ compiler (C++ backend)
make cpp-e1-llvm    # C++ compiler (LLVM native)
make cpp-e1-llvmjit # C++ compiler (LLVM JIT)
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
| e2 | ℤ | + case statements, break, blocks, comparisons, `*` `/` `%` |
| e3 | ℤ, 𝔹, () → T | + booleans, callables, case expressions |
| e4 | ℤ, 𝔹, [T], () → T | + arrays, pattern matching |
| e5 | ℤ, 𝔹, [T], {…}, () → T, unit | + records, unit literal |
| e6 | ℤ, 𝔹, [T], {…}, () → T, unit | + static typing, type definitions |

Each level is a strict superset of the previous.

## Examples

- [example.e0](examples/example.e0) — Sequential computation (e0)
- [factorial.e1](examples/factorial.e1) — Factorial benchmark (e1)
- [collatz.e1](examples/collatz.e1) — Collatz sequence iteration (e1)
- [gcd.e1](examples/gcd.e1) — Euclidean algorithm (e1)
- [example.e1](examples/example.e1) — Emulating e2 features in e1
- [factorial.e2](examples/factorial.e2) — Factorial benchmark (e2)
- [collatz.e2](examples/collatz.e2) — Collatz sequence (e2)
- [gcd.e2](examples/gcd.e2) — Euclidean algorithm (e2)

## Implementations

| Approach | Files | Notes |
|----------|-------|-------|
| Koka (hand-written parser) | `e1.koka` | AST used|
| Koka (PEG meta-interpreter) | `peg.koka`, `e1peg.koka` | Single-phase parse+execute, no AST |
| Koka (PEG, e2) | `peg.koka`, `e2peg.koka` | e2 with case/comparisons/mul-div |
| Koka (PEG, e3) | `peg.koka`, `e3peg.koka` | e3 with booleans/closures (limited) |
| C++ interpreter | `e1.cpp`, `e1.hpp` | Handwritten, AST used |
| Compiler in C++ | `e1_compile.cpp`, `e1.hpp` | C++ or LLVM IR backend |

See [docs/IMPLEMENTATIONS.md](docs/IMPLEMENTATIONS.md) for details on each implementation.

## Benchmarks

```bash
make bench                         # default: 2000 iterations of 31!
make bench BENCH_ARGS="100 20"     # custom: 100 iterations of 20!
```

Example results for `2000 31` (with bigint, INT_BITS=0):

| Implementation | Time |
|----------------|------|
| LLVM backend | 2ms |
| C++ backend | 17ms |
| LLVM lli (JIT) | 93ms |
| C++ interpreter | 0.60s |
| Koka PEG e2 | 1.1s |
| Koka PEG e3 | 1.7s |
| Koka interpreter | 2.1s |
| Koka PEG e1 | 2.5s |

## Further Reading

- [docs/DESIGN.md](docs/DESIGN.md) — Language progression rationale, control flow design decisions
- [docs/IMPLEMENTATIONS.md](docs/IMPLEMENTATIONS.md) — Implementation details, integer bit width configuration
- [docs/PEG_SPEC.md](docs/PEG_SPEC.md) — PEG grammar specification
- [docs/minimal_turing_languages.md](docs/minimal_turing_languages.md) — Survey of minimal Turing-complete languages (Minsky machines, λ-calculus, etc.)
- [examples/](examples/) — All example programs for each language level
