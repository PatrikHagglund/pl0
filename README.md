# PL/0 Exploration

This project explores the design and implementation of simple programming languages, inspired by Niklaus Wirth's PL/0.

Currently in an initial work-in-progress state.

**Philosophy:**
- Keep languages small
- Progressive complexity — currently seven levels, each a superset of the previous
- Try several implementation approaches

**Current state:**
- pl0_1 (and pl0_0) have two different working interpreters written in Koka, one in C++, and a compiler in C++ targeting LLVM IR.
- Benchmarks for level 1
- pl0_2 through pl0_6 have PEG grammars and example files, but no interpreters yet
- For each level, example code shows how to emulate higher-level features with lower-level primitives

## Setup

The project uses a single Podman container (Fedora Rawhide) with all tools:
- g++ (C++26)
- LLVM/Clang
- Koka
- Boost (Multiprecision)

Rebuild the container after changes to `Containerfile`:
```bash
rm .image && make .image
```

## Grammar Levels

| Version | Types | Features |
|---------|-------|----------|
| pl0_0 | ℤ | sequential only, + - (not Turing-complete) |
| pl0_1 | ℤ | + loop, break_ifz (Turing-complete, Minsky machine) |
| pl0_2 | ℤ | + case statements, break, blocks |
| pl0_3 | ℤ, 𝔹, () → T | + booleans, callables, case expressions |
| pl0_4 | ℤ, 𝔹, [T], () → T | + arrays, pattern matching |
| pl0_5 | ℤ, 𝔹, [T], {…}, () → T, unit | + records, unit literal |
| pl0_6 | ℤ, 𝔹, [T], {…}, () → T, unit | + static typing, type definitions |

Each level is a strict superset of the previous.

## Syntax Overview

### Bindings
```
x:              // declaration
x := 5          // declaration with init / reassignment
x: int = 5      // typed declaration (pl0_6 only)
arr.0 := 5      // indexed assignment (pl0_4+)
```

### Built-in Input Variables
```
arg1            // first command-line argument (integer, default 0)
arg2            // second command-line argument (integer, default 0)
```

Usage: `./program <arg1> <arg2>`

### Control Flow
```
loop statement
break_ifz expr      // break if zero (pl0_1)
break               // unconditional break (pl0_2+)
case { guard -> statement ... }
print expr          // output value
```

### Expressions
```
case { guard -> expr, ... }     // case expression (pl0_3+)
(x) -> expr                     // function literal
()                              // unit value (pl0_5+)
```

### Operators
- Arithmetic: `+ - * / %`
- Comparison: `== != < <= > >=`
- Boolean: `&& || !` (pl0_3+)

### Application and Access

Two forms of application/access:

```
f x             // function call (juxtaposition, evaluated)
arr i           // array access (evaluated index)
rec key         // record field (evaluated key)

arr.0           // array access (literal index)
rec.field       // record field (literal name)
```

Juxtaposition evaluates the argument; dot access uses the literal index/field name.

## Examples

Located in `examples/`:
- `example_0.pl0` — Sequential computation (pl0_0)
- `example_1.pl0` — Emulating pl0_2 features in pl0_1
- `bench_1_factorial.pl0` — Factorial benchmark

## Implementations

| Approach | Files | Notes |
|----------|-------|-------|
| Koka (hand-written parser) | `pl01.koka` | AST used|
| Koka (PEG meta-interpreter) | `peg.koka`, `pl0peg1.koka` | Single-phase parse+execute, no AST |
| C++ interpreter | `pl0_1.cpp`, `pl0_1.hpp` | Handwritten, AST used |
| Compiler in C++ | `pl0_1_compile.cpp`, `pl0_1.hpp` | C++ or LLVM IR backend |

See [docs/IMPLEMENTATIONS.md](docs/IMPLEMENTATIONS.md) for details on each implementation.

### Quick Start

```bash
make koka-pl0       # Koka interpreter
make koka-peg       # Koka PEG interpreter
make run            # C++ interpreter
make run-compile    # C++ compiler (C++ backend)
make run-llvm       # C++ compiler (LLVM JIT)
```

## Benchmarks

```bash
make bench-1                           # default: 2000 iterations of 31!
make bench-1 BENCH_1_ARGS="100 20"     # custom: 100 iterations of 20!
```

Example results for `2000 31` (with bigint, INT_BITS=0):

| Implementation | Time |
|----------------|------|
| C++ backend -O3 | 18ms |
| LLVM IR backend -O3 | 149ms |
| LLVM IR backend -O0 | 186ms |
| LLVM IR backend lli (JIT) | 288ms |
| C++ interpreter | 0.7s |
| Koka interpreter | 2.2s |
| Koka interpreter (PEG) | 2.4s |

## Further Reading

- [docs/IMPLEMENTATIONS.md](docs/IMPLEMENTATIONS.md) — Implementation details, integer bit width configuration
- [docs/PEG_SPEC.md](docs/PEG_SPEC.md) — PEG grammar specification
- [docs/minimal_turing_languages.md](docs/minimal_turing_languages.md) — Survey of minimal Turing-complete languages (Minsky machines, λ-calculus, etc.)
