# PL/0 Exploration

[![CI](https://github.com/PatrikHagglund/pl0e/actions/workflows/ci.yml/badge.svg)](https://github.com/PatrikHagglund/pl0e/actions/workflows/ci.yml)

This project explores the design and implementation of simple programming languages, inspired by Niklaus Wirth's [PL/0](https://en.wikipedia.org/wiki/PL/0).

**Current state:**

Currently in an initial work-in-progress state.
- e1 has a [language specification](docs/E1_SPEC.md), two [Koka](https://koka-lang.github.io/) interpreters (AST-based and [PEG](https://en.wikipedia.org/wiki/Parsing_expression_grammar) with actions), a C++ interpreter, and a C++ compiler (with C++ and LLVM IR backends)
- e0 and e2-e6 have PEG interpreters in Koka; e3 has a [language specification](docs/E3_SPEC.md); e6 adds static type checking
- Benchmarks for levels 1, 2, and 3
- For each level, example code shows how to emulate higher-level features with lower-level primitives
- `efuzz`: differential fuzzer for e1-e6 — generates random well-defined programs with known output and diffs implementations against a co-evaluated oracle, including violation checking (see [docs/FUZZING.md](docs/FUZZING.md))

**Philosophy:**
- Keep languages small
- Progressive complexity — currently seven levels (e0–e6), each almost a strict superset of the previous
- Try several implementation approaches

The "e" in e0–e6 may stand for "experiment" or "exploration".

## Quick Start

```bash
./setup.sh        # Install Bazelisk

bazel run //e1:e1 -- e1/factorial.e1      # C++ interpreter
bazel run //e1:e1peg -- e1/factorial.e1   # Koka PEG interpreter
bazel run //e1:factorial_cpp               # C++ backend
bazel run //e1:factorial_llvm              # LLVM backend
bazel test //...                            # Run tests
bazel run //bench:bench                          # Run benchmarks
bazel run //e1:diff -- -- 100 1 30             # Differential fuzzing (e1)
bazel run //e2:diff_e2 -- -- 100 1 30          # Differential fuzzing (e2: e2peg vs e3peg)
```

Uses hermetic LLVM and Koka toolchains. See [docs/BAZEL.md](docs/BAZEL.md) for details.

## Grammar Levels

| Version | Types | Features |
|---------|-------|----------|
| e0 | ℤ | sequential only, + - (not Turing-complete) |
| e1 | ℤ | + loop, break_ifz (Turing-complete, Minsky machine) |
| e2 | ℤ | + case statements, break, blocks, comparisons, `*` `/` `%` |
| e3 | ℤ, 𝔹, () → T | + booleans, callables, case expressions |
| e4 | ℤ, 𝔹, [T], () → T | + arrays, pattern matching, component assignment (`a.i := e`) |
| e5 | ℤ, 𝔹, [T], {…}, () → T, unit | + records, unit literal, field assignment (`r.f := e`) |
| e6 | ℤ, 𝔹, [T], {…}, () → T, unit | + static typing, type definitions |

Each level is almost a strict superset of the previous — the deliberate deviations (e.g. `break_ifz` dropped at e2+) are documented in [docs/DESIGN.md](docs/DESIGN.md).

## Examples

- [example.e0](e0/example.e0) — Sequential computation (e0)
- [factorial.e1](e1/factorial.e1) — Factorial benchmark (e1)
- [collatz.e1](e1/collatz.e1) — Collatz sequence iteration (e1)
- [gcd.e1](e1/gcd.e1) — Euclidean algorithm (e1)
- [example.e1](e1/example.e1) — Emulating e2 features in e1
- [factorial.e2](e2/factorial.e2) — Factorial benchmark (e2)
- [collatz.e2](e2/collatz.e2) — Collatz sequence (e2)
- [gcd.e2](e2/gcd.e2) — Euclidean algorithm (e2)
- [factorial.e3](e3/factorial.e3) — Factorial benchmark (e3)
- [collatz.e3](e3/collatz.e3) — Collatz sequence (e3)
- [gcd.e3](e3/gcd.e3) — Euclidean algorithm (e3)
- [example.e4](e4/example.e4) — Arrays and pattern matching (e4)
- [factorial.e4](e4/factorial.e4) — Factorial benchmark (e4)
- [collatz.e4](e4/collatz.e4) — Collatz sequence (e4)
- [gcd.e4](e4/gcd.e4) — Euclidean algorithm with arrays (e4)
- [lvalue.e4](e4/lvalue.e4) — Array element assignment, functional update (e4)
- [lvalue.e5](e5/lvalue.e5) — Record field + nested/mixed component assignment (e5)
- [lvalue.e6](e6/lvalue.e6) — Component assignment, statically type-checked (e6)

## Implementations

| Approach | Files | Notes |
|----------|-------|-------|
| Koka (hand-written parser) | `e1.kk` | AST used|
| Koka (PEG meta-interpreter) | `peg.kk`, `e1peg.kk` | Single-phase parse+execute, no AST |
| Koka (PEG, e2) | `peg.kk`, `e2peg.kk` | e2 with case/comparisons/mul-div |
| Koka (PEG, e3) | `peg.kk`, `e3peg.kk` | e3 with booleans/closures |
| Koka (PEG, e4) | `peg.kk`, `e4peg.kk` | e4 with arrays/pattern matching |
| Koka (PEG, e5) | `peg.kk`, `e5peg.kk` | e5 with records/unit/field access |
| Koka (PEG, e6) | `peg.kk`, `e6peg.kk` | e6 with static type checking before execution |
| C++ interpreter | `e1.cpp`, `e1.hpp` | Handwritten, AST used |
| Compiler in C++ | `e1_compile.cpp`, `e1.hpp` | C++ or LLVM IR backend |

See [docs/IMPLEMENTATIONS.md](docs/IMPLEMENTATIONS.md) for details on each implementation.

## Benchmarks

```bash
bazel run //bench:bench                          # default: 2000 iterations of 31!
bazel run //bench:bench -- 100 20                # custom: 100 iterations of 20!
```

Example results for `2000 31` (with bigint, INT_BITS=0):

| Implementation | Time |
|----------------|------|
| LLVM backend | 16ms |
| C++ backend | 18ms |
| LLVM JIT | 80ms |
| Koka PEG e2 | 0.18s |
| C++ interpreter | 0.97s |
| Koka interpreter | 1.75s |
| Koka PEG e1 | 1.95s |

## Further Reading

- [docs/DESIGN.md](docs/DESIGN.md) — Language progression rationale, control flow design decisions, type-system algebraic structure
- [docs/E1_SPEC.md](docs/E1_SPEC.md), [docs/E3_SPEC.md](docs/E3_SPEC.md) — Language specifications (e1: minimal; e3: introduces behavior categories)
- [docs/IMPLEMENTATIONS.md](docs/IMPLEMENTATIONS.md) — Implementation details, integer bit width configuration
- [docs/PEG_SPEC.md](docs/PEG_SPEC.md) — PEG grammar specification, static analysis (`--warn` flag)
- [docs/FUZZING.md](docs/FUZZING.md) — `efuzz`, a differential fuzzing tool adapted from llvm-fuzzgen (levels e1-e6; mutator, reducer, e6 type-check oracle)
- [docs/minimal_turing_languages.md](docs/minimal_turing_languages.md) — Survey of minimal Turing-complete languages (Minsky machines, λ-calculus, etc.)
- Example programs live in each level directory (`e0/` … `e6/`), listed above

