# PL/0 Implementations

Interpreters and compilers for PL/0 level 1.

## Overview

| Implementation | Language | Type | Phases | Integer Support |
|----------------|----------|------|--------|-----------------|
| `pl01.koka` | Koka | Interpreter | 2 | Koka bigint |
| `pl0peg1.koka` | Koka | Interpreter | 1 | Koka bigint |
| `pl0_1.cpp` | C++ | Interpreter | 2 | Configurable |
| `pl0_1_compile.cpp` | C++ | Compiler | 2 | Configurable |

**Compiler requirement:** clang++ 18+ (uses `_BitInt` for all fixed-width integers; g++ not supported).

## Language Implementation Configuration

Configured in `src/pl0_1.hpp` (C++ implementations only):

| Parameter | Default | Description |
|-----------|---------|-------------|
| `INT_BITS` | 0 | Integer bit width: 0=bigint, >0=`_BitInt(N)` |
| `ARG_COUNT` | 2 | Number of built-in `arg<N>` variables (arg1, arg2, ...) |

### Integer Types

**Bigint (INT_BITS=0):** Header-only library (`pl0_1_bigint.hpp`) with no external dependencies. Uses 64-bit limbs. Replaced Boost.Multiprecision for ~2x better performance.

- Variables: heap-allocated with `realloc()`, unlimited size
- Temporaries: VLAs (C++ backend) or stack alloca (LLVM backend), dynamic size

**Fixed-width (INT_BITS>0):** Uses `_BitInt(N)` for any bit width.

- 32/64/128 bits: native CPU operations, fast
- >128 bits: software emulation for division/modulo, slow for printing

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
| C++ (default) | `.cpp` file | Header-only (`pl0_1_bigint.hpp`) |
| LLVM IR (`--llvm`) | `.ll` file | Via `pl0_1_rt_bigint.ll` |

```
src/
  pl0_1_compile.cpp   — Unified code generator
  pl0_1_preamble.hpp  — Runtime preambles for both backends
  pl0_1_bigint.hpp    — Header-only bigint implementation
  pl0_1_rt_bigint.cpp — LLVM runtime (extern C wrappers)
```

**C++ backend:**
```bash
./pl0_1_compile prog.pl0 > out.cpp
clang++ -std=gnu++26 -Wno-vla-cxx-extension -O3 -I src out.cpp -o out
```

**LLVM backend:**
```bash
./pl0_1_compile --llvm prog.pl0 > prog.ll
llvm-link prog.ll src/pl0_1_rt_bigint.ll -S -o out.ll
clang -O3 out.ll -o out   # native
lli out.ll                 # JIT
```

### Bigint Memory Management

Both backends use the same strategy when `INT_BITS=0` (bigint):
- **Heap allocation for variables** — unlimited integer size, persists across loop iterations
- **Stack allocation for temporaries** — dynamic size, reclaimed after each statement
  - C++ backend: VLAs with block scope (requires `gnu++26`)
  - LLVM backend: `alloca` with `stacksave`/`stackrestore`

**Memory management strategy:**

Each variable has a (pointer, capacity) pair. In LLVM IR:
```llvm
%x = alloca ptr       ; pointer to current buffer
%x_cap = alloca i32   ; capacity in bytes
```

All assignment and reallocation is handled by `assign()` (C++) / `bi_assign()` (LLVM):
1. Evaluate expression (temporaries on stack)
2. Call `bi_assign(ptr %x, ptr %x_cap, ptr value)`
3. Restore stack (reclaims temporaries)

The `bi_assign()` function uses `realloc()` with exponential growth (capacity = max(cap*2, needed)):
- `realloc(NULL, size)` handles initial allocation (acts like `malloc`)
- `realloc()` can extend buffers in-place when possible, avoiding copies
- Doubling strategy amortizes allocation costs on repeated growing assignments

**Key functions:**

| Function | Purpose |
|----------|---------|
| `bi_assign(ptr*, ptr*, ptr)` | Assign value to variable (realloc if needed) |
| `bi_init(ptr, i64)` | Initialize buffer with i64 value |
| `bi_copy(ptr, ptr)` | Copy value between buffers |
| `bi_add(ptr, ptr, ptr)` | out = a + b |
| `bi_sub(ptr, ptr, ptr)` | out = a - b |
| `bi_neg(ptr, ptr)` | out = -a |
| `bi_size(ptr) → i32` | Current limb count |
| `bi_add_size(ptr, ptr) → i32` | Limbs needed for a + b |
| `bi_sub_size(ptr, ptr) → i32` | Limbs needed for a - b |
| `bi_buf_size(i32) → i32` | Bytes needed for N limbs |
| `bi_is_zero(ptr) → i1` | Test if zero |
| `bi_print(ptr)` | Print to stdout |
| `bi_from_str(ptr, ptr)` | Parse string into buffer |

**LLVM runtime linkage:** The runtime (`pl0_1_rt_bigint.cpp`) wraps bigint operations with `extern "C"` linkage for LLVM IR compatibility. Uses only C-compatible I/O (`putchar`, `puts`) and memory (`malloc`, `realloc`, `free`).

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
| C++ backend | 9ms |
| LLVM backend | 27ms |
| LLVM lli (JIT) | 90ms |
| C++ interpreter | 0.6s |
| Koka interpreter | 1.9s |
| Koka PEG interpreter | 2.3s |

The C++ backend is fastest due to header-only bigint with full inlining. Memory management via `bi_assign()` with `realloc()` enables potential in-place buffer extension.

## Code Style

C++ code uses `clang-format` with the following conventions (see `.clang-format`):

- Based on LLVM style
- 100 column limit
- 4-space indentation
- Short functions allowed on single line

Additional conventions:
- Use `std::print` with explicit `\n` in format strings (not `std::println`)
- Short aliases `p()` for print and `f()` for format in compiler code

```bash
# Format a file
clang-format -i src/pl0_1_compile.cpp
```
