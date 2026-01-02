# PL/0 Implementations

Interpreters and compilers for PL/0 level 1.

## Overview

| Implementation | Language | Type | Phases | Integer Support |
|----------------|----------|------|--------|-----------------|
| `pl01.koka` | Koka | Interpreter | 2 | Koka bigint |
| `pl0peg1.koka` | Koka | Interpreter | 1 | Koka bigint |
| `pl0_1.cpp` | C++ | Interpreter | 2 | Configurable |
| `pl0_1_compile.cpp` | C++ | Compiler | 2 | Configurable |

## Language Implementation Configuration

Configured in `src/pl0_1.hpp` (C++ implementations only):

| Parameter | Default | Description |
|-----------|---------|-------------|
| `INT_BITS` | 0 | Integer bit width (0=bigint, 32/64/128=native, >128=Boost fixed) |
| `ARG_COUNT` | 2 | Number of built-in `arg<N>` variables (arg1, arg2, ...) |

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

### `pl0_1_compile.cpp` — Unified C++/LLVM Compiler

Two backends from a single unified code generator:

| Backend | Output | Bigint Support |
|---------|--------|----------------|
| C++ (default) | `.cpp` file | Via Boost headers |
| LLVM IR (`--llvm`) | `.ll` file | Via `pl0_1_rt_bigint_stack.ll` |

```
src/
  pl0_1_compile.cpp   — Unified code generator (112 lines)
  pl0_1_preamble.hpp  — Runtime preambles for both backends
```

**C++ backend:**
```bash
./pl0_1_compile prog.pl0 > out.cpp
g++ -std=gnu++26 -O3 out.cpp -o out
```

**LLVM backend:**
```bash
./pl0_1_compile --llvm prog.pl0 > prog.ll
llvm-link prog.ll src/pl0_1_rt_bigint_stack.ll -S -o out.ll
clang -O3 out.ll -o out   # native
lli out.ll                 # JIT
```

### Stack-Based Bigint Runtime (`src/pl0_1_rt_bigint_stack.ll`)

When `INT_BITS=0` (bigint), the LLVM backend uses a stack-based runtime — no heap allocation. All bigint buffers are allocated via `alloca`.

**Key functions:**

| Function | Purpose |
|----------|---------|
| `bi_init(ptr, i64)` | Initialize buffer with i64 value |
| `bi_copy(ptr, ptr)` | Copy value between buffers |
| `bi_add(ptr, ptr, ptr)` | out = a + b |
| `bi_sub(ptr, ptr, ptr)` | out = a - b |
| `bi_neg(ptr, ptr)` | out = -a |
| `bi_add_size(ptr, ptr) → i32` | Limbs needed for a + b |
| `bi_sub_size(ptr, ptr) → i32` | Limbs needed for a - b |
| `bi_buf_size(i32) → i32` | Bytes needed for N limbs |
| `bi_is_zero(ptr) → i32` | Test if zero |
| `bi_print(ptr)` | Print to stdout |
| `bi_from_str(ptr, ptr)` | Parse string into buffer |

**Stack management:** The compiler uses `llvm.stacksave`/`llvm.stackrestore` around loops to prevent stack exhaustion from temporary allocations.

**No external dependencies:** The runtime uses only C-style I/O (`putchar`), no C++ stdlib.

```bash
make run-compile      # C++ backend
make run-llvm         # LLVM JIT
make run-llvm-native  # LLVM native
```

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

Example results for `2000 31` (bigint, INT_BITS=0):

| Implementation | Time |
|----------------|------|
| C++ backend | 22ms |
| LLVM backend | 25ms |
| LLVM lli (JIT) | 84ms |
| C++ interpreter | 0.7s |
| Koka interpreter | 1.9s |
| Koka PEG interpreter | 2.3s |

All compiled code uses `-O3` optimization.
