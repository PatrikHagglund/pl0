# PL/0 Implementations

Interpreters and compilers for PL/0 level 1.

## Overview

| Implementation | Language | Type | Integer Support |
|----------------|----------|------|-----------------|
| `pl01.koka` | Koka | Interpreter | Koka bigint |
| `pl0peg1.koka` | Koka | Interpreter | Koka bigint |
| `pl0_1.cpp` | C++ | Interpreter | Configurable |
| `pl0_1_compile.cpp` | C++ | Compiler | Configurable |

**Compiler requirement:** clang++ 18+ (uses `_BitInt`; g++ not supported).

## Interpreters

### Koka Interpreters

**`pl01.koka` — Two-Phase:**
Traditional parse-then-execute with AST.

```bash
make koka-pl0
```

**`pl0peg1.koka` — Single-Phase:**
No AST — semantic actions during parsing produce thunks. Uses packrat memoization.

```bash
make koka-peg
```

Both use algebraic effects for `break`:
```koka
effect loop-break
  ctl do-break(e: env): a
```

### C++ Interpreter (`pl0_1.cpp`)

Hand-written lexer and recursive descent parser, AST-based execution.

```bash
make run
```

## Compiler (`pl0_1_compile.cpp`)

Two backends from a single code generator:

| Backend | Output | Command |
|---------|--------|---------|
| C++ (default) | `.cpp` file | `./pl0_1_compile prog.pl0` |
| LLVM IR | `.ll` file | `./pl0_1_compile --llvm prog.pl0` |

```bash
make run-compile      # C++ backend
make run-llvm         # LLVM JIT
make run-llvm-native  # LLVM native
```

## Integer Configuration

Configured in `src/pl0_1.hpp`:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `INT_BITS` | 0 | 0 = bigint (unlimited), >0 = `_BitInt(N)` |
| `ARG_COUNT` | 2 | Number of `arg<N>` variables |

### Fixed-Width (`INT_BITS > 0`)

Uses C23 `_BitInt(N)` for any bit width.
- 32/64/128 bits: native CPU operations
- >128 bits: software emulation (slow for division/printing)

### Bigint (`INT_BITS = 0`)

Header-only library (`pl0_1_bigint.hpp`) with unlimited precision.

**Architecture:**
```
pl0_1_bigint.hpp     — Core implementation (used by all C++ code)
pl0_1_rt_bigint.cpp  — extern "C" wrappers for LLVM backend
```

**Memory layout:**
```cpp
struct Raw {
    Size size;      // limb count
    bool neg;       // sign
    Limb limbs[];   // flexible array (64-bit limbs)
};
```

**Memory strategy:**
- Variables: heap-allocated `(Raw*, Size cap)` pairs with `realloc()` doubling
- Temporaries: stack-allocated VLAs (C++) or `alloca` (LLVM)

**Limb arithmetic:** Uses Clang multiprecision builtins (`__builtin_addcl`/`__builtin_subcl`) for carry/borrow propagation. The `addc()`/`subc()` helpers auto-select builtin based on limb size.

## Unified Runtime Interface

The C++ backend generates identical code for both integer types using macros:

| Macro | Purpose |
|-------|---------|
| `VAR(name)` | Declare variable |
| `ARG(name, idx)` | Declare from command line |
| `ASSIGN(name, val)` | Assign value |
| `LIT(name, v)` | Create literal |
| `ADD/SUB/NEG(name, ...)` | Arithmetic |
| `IS_ZERO(x)` | Test zero |
| `PRINT(x)` | Output |

**Shared primitives** (used by interpreter, C++ backend, LLVM runtime):

| Function | Purpose |
|----------|---------|
| `var_init` | Initialize variable |
| `assign` | Assign with realloc |
| `arg_init` | Parse command-line arg |
| `add`, `sub`, `neg` | Arithmetic |
| `is_zero`, `print` | Test and output |

## Source Files

```
src/
  pl0_1.hpp           — Shared lexer, parser, AST, configuration
  pl0_1.cpp           — C++ interpreter
  pl0_1_compile.cpp   — Unified compiler
  pl0_1_preamble.hpp  — Runtime preambles (macros for both backends)
  pl0_1_bigint.hpp    — Bigint implementation
  pl0_1_rt_bigint.cpp — LLVM runtime wrappers
  pl01*.koka          — Koka interpreter
  pl0peg1.koka        — Koka PEG interpreter
  peg.koka            — Generic PEG parser
```

## Benchmarks

```bash
make bench-1                        # 2000 iterations of 31!
make bench-1 BENCH_1_ARGS="100 20"  # custom
```

Results for `2000 31` (bigint):

| Implementation | Time |
|----------------|------|
| C++ backend | 16ms |
| LLVM backend | 15ms |
| LLVM JIT | 89ms |
| C++ interpreter | 0.72s |
| Koka interpreter | 2.1s |
| Koka PEG | 2.5s |

C++ and LLVM backends have similar performance when compiled to native.

## Code Style

- clang-format with LLVM base, 100 columns, 4-space indent
- `std::print` with explicit `\n`
- Short aliases `p()`/`f()` in compiler
