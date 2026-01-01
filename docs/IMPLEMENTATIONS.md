# PL/0 Implementations

Interpreters and compilers for PL/0 level 1.

## Overview

| Implementation | Language | Type | Phases | Integer Support |
|----------------|----------|------|--------|-----------------|
| `pl01.koka` | Koka | Interpreter | 2 | Koka bigint |
| `pl0peg1.koka` | Koka | Interpreter | 1 | Koka bigint |
| `pl0_1.cpp` | C++ | Interpreter | 2 | Configurable (INT_BITS) |
| `pl0_1_compile.cpp` | C++ | Compiler | 2 | Configurable (INT_BITS) |

## Interpreters

### `pl01.koka` — Two-Phase Koka Interpreter

Traditional architecture: parse entire program, then execute.

```
src/
  pl01.koka        — Main entry
  pl01-types.koka  — AST types, environment
  pl01-parser.koka — Recursive descent parser
  pl01-eval.koka   — Evaluator with effect handlers
```

**Flow:** `Source → [Parse] → AST → [Execute] → Result`

```bash
make koka-pl0
```

### `pl0peg1.koka` — Single-Phase Koka Interpreter

No AST — semantic actions execute during parsing, producing thunks.

```
src/
  pl0peg1.koka — Semantic actions
  peg.koka     — Generic PEG parser
  pl0_1.peg    — Grammar file (loaded at runtime)
```

**Flow:** `Source → [Parse+Actions] → Thunks → [Execute] → Result`

Uses packrat memoization to avoid exponential backtracking.

```bash
make koka-peg
```

### `pl0_1.cpp` — C++ Interpreter

Hand-written lexer and recursive descent parser, AST-based execution.

```bash
make run
```

## Compilers

### `pl0_1_compile.cpp` — C++ Compiler

Two backends from a single compiler:

| Backend | Output | Bigint Support |
|---------|--------|----------------|
| C++ (default) | `.cpp` file | Via Boost headers |
| LLVM IR (`--llvm`) | `.ll` file | Via `pl0_1_rt_bigint.bc` |

**C++ backend:**
```bash
./pl0_1_compile prog.pl0 > out.cpp
g++ -std=gnu++26 -O3 out.cpp -o out
```

**LLVM backend:**
```bash
./pl0_1_compile --llvm prog.pl0 > prog.ll
llvm-link prog.ll src/pl0_1_rt_bigint.bc -S -o out.ll
clang++ -O3 out.ll -o out        # native
lli -load /lib64/libstdc++.so.6 out.ll  # JIT
```

```bash
make run-compile      # C++ backend
make run-llvm         # LLVM JIT
make run-llvm-native  # LLVM native
```

## Integer Bit Width

Configured via `INT_BITS` in `src/pl0_1.hpp`:

| INT_BITS | Type | Notes |
|----------|------|-------|
| 0 (default) | Boost cpp_int | Arbitrary precision |
| 32, 64, 128 | Native | `int32_t`, `int64_t`, `__int128` |
| 256+ | Boost fixed | Fixed-width multiprecision |

Bigint and fixed-width have similar performance. Bigint is default to avoid overflow.

## Koka Effect Handlers

Both Koka interpreters use algebraic effects for `break`:

```koka
effect loop-break
  ctl do-break(e: env): a

fun exec-loop(e: env, body: stmt): <loop-break, div> env
  with ctl do-break(e1) e1
  val e2 = exec(e, body)
  exec-loop(e2, body)
```

## Benchmarks

```bash
make bench-1                        # default: 2000 iterations of 31!
make bench-1 BENCH_1_ARGS="100 20"  # custom args
```

Example results for `2000 31` (bigint):

| Implementation | Time |
|----------------|------|
| C++ backend -O3 | 18ms |
| LLVM IR backend -O3 | 149ms |
| LLVM IR backend -O0 | 186ms |
| LLVM IR backend lli (JIT) | 288ms |
| C++ interpreter | 0.7s |
| Koka interpreter | 2.2s |
| Koka interpreter (PEG) | 2.4s |
