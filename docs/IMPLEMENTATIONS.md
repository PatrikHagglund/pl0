# PL/0 Implementations

Interpreters and compilers for e0–e3.

## Overview

| Implementation | Language | Type | Level | Integer Support |
|----------------|----------|------|-------|-----------------|
| `e1.koka` | Koka | Interpreter | e1 | Koka bigint |
| `e1peg.koka` | Koka | Interpreter | e1 | Koka bigint |
| `e2peg.koka` | Koka | Interpreter | e2 | Koka bigint |
| `e3peg.koka` | Koka | Interpreter | e3 | Koka bigint |
| `e1.cpp` | C++ | Interpreter | e1 | Configurable |
| `e1_compile.cpp` | C++ | Compiler | e1 | Configurable |

**Compiler requirement:** clang++ 18+ (uses `_BitInt`; g++ not supported).

## Interpreters

### Koka Interpreters

**`e1.koka` — Two-Phase:**
Traditional parse-then-execute with AST.

```bash
make koka-e1
```

**`e1peg.koka` — Single-Phase (e1):**
No AST — semantic actions during parsing produce thunks. Uses shared `pegeval.koka` runtime.

```bash
make koka-peg-e1
```

**`e2peg.koka` — Single-Phase (e2):**
Extends e1peg with case statements, comparisons, and multiplication/division.

```bash
make koka-peg-e2
```

**`e3peg.koka` — Single-Phase (e3):**
Extends e2 with booleans, closures, and case expressions. Uses a separate interpreter (not `pegeval.koka`) with its own AST types for `rval` (int/bool/closure).

```bash
make koka-peg-e3
```

**Known limitations:**
- Nested loop `break` bug: `break` in an inner loop also exits outer loops (effect handler escapes)
- No recursive closures: closures capture the environment at definition time, so self-references fail

**Future work:**
- Fix nested break by using a unique effect tag per loop, or switch to explicit continuation-passing
- Support recursion via late-binding or Y-combinator
- Consider requiring explicit grouping for inline actions in PEG grammars (see `ACTION_SCOPE_RECOMMENDATION.md` in parent directory)

**`pegeval.koka` — Shared Runtime:**
Parameterized `semval<x>` type allows level-specific extensions while sharing:
- Environment operations (`env-get`, `env-set`)
- Loop control (`loop-break` effect, `exec-loop`)
- Base constructor handling (`handle-base`)
- Generic interpreter loop (`run-interpreter`)

Both use algebraic effects for `break`:
```koka
effect loop-break
  ctl do-break(e: env): a
```

### C++ Interpreter (`e1.cpp`)

Hand-written lexer and recursive descent parser, AST-based execution.

```bash
make cpp-e1
```

## Compiler (`e1_compile.cpp`)

Two backends from a single code generator:

| Backend | Output | Command |
|---------|--------|---------|
| C++ (default) | `.cpp` file | `./e1_compile prog.e1` |
| LLVM IR | `.ll` file | `./e1_compile --llvm prog.e1` |

```bash
make cpp-e1-cpp     # C++ backend
make cpp-e1-llvmjit # LLVM JIT
make cpp-e1-llvm    # LLVM native
```

## Integer Configuration

Configured via macros in `src/e1.hpp`:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `INT_BITS` | 0 | 0 = bigint (unlimited), >0 = `_BitInt(N)` |
| `ARG_COUNT` | 2 | Number of `arg<N>` variables |
| `LIMB_BITS` | 64 | Bigint limb width (32, 64, or larger) |

### Configuration Flexibility

The flexibility of these settings varies by implementation:

| Setting | Interpreter | C++ Backend | LLVM Backend |
|---------|-------------|-------------|--------------|
| `INT_BITS` | Compile-time only | Runtime (`-DINT_BITS=N`) | Compile-time only |
| `ARG_COUNT` | Compile-time only | Compile-time only | Compile-time only |
| `LIMB_BITS` | Compile-time only | Compile-time only | Compile-time only |

**C++ backend `INT_BITS` flexibility:**

The generated C++ code uses `#ifndef INT_BITS` guards, allowing override when compiling the output:

```bash
# Generate C++ code (uses default INT_BITS=0)
./e1_compile prog.e1 > out.cpp

# Compile with different INT_BITS
clang++ -DINT_BITS=64 out.cpp -o out    # 64-bit integers
clang++ -DINT_BITS=128 out.cpp -o out   # 128-bit integers
clang++ out.cpp -o out                   # bigint (default)
```

**Why other settings are compile-time only:**

- `ARG_COUNT`: Determines variable declarations. Could be made flexible with array-based args, but adds complexity for little benefit.
- `LIMB_BITS`: Affects bigint `Raw` struct layout. Runtime flexibility would require runtime dispatch or multiple code paths.
- LLVM backend `INT_BITS`: The IR type (`i64`, `i128`, `ptr`) is baked into every instruction. Would require `--int-bits` CLI option to generate different IR.

**Potential future enhancements:**

- `--int-bits=N` and `--arg-count=N` CLI options for the compiler (both backends)
- `--arg-count=N` for the interpreter (straightforward, no performance impact)
- `--int-bits=N` for the interpreter would require runtime dispatch via `std::variant` (adds overhead)

### Fixed-Width (`INT_BITS > 0`)

Uses C23 `_BitInt(N)` for any bit width.
- 32/64/128 bits: native CPU operations
- >128 bits: software emulation (slow for division/printing)

### Bigint (`INT_BITS = 0`)

Header-only library (`e1_bigint.hpp`) with unlimited precision.

**Architecture:**
```
e1_bigint.hpp     — Core implementation (used by all C++ code)
e1_rt_bigint.cpp  — extern "C" wrappers for LLVM backend
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
| `var_init()` | Initialize variable, returns `Var{ptr, cap}` |
| `assign(Var&, Raw&)` | Assign with realloc |
| `arg_init(argc, argv, idx)` | Parse command-line arg, returns `Var` |
| `add`, `sub`, `neg` | Arithmetic (reference-based API) |
| `is_zero`, `print` | Test and output |

The bigint API uses references internally for safety, with `__restrict` hints for alias optimization. The LLVM runtime (`e1_rt_bigint.cpp`) provides `extern "C"` wrappers that bridge to the pointer-based ABI.

## Source Files

```
src/
  e1.hpp           — Shared lexer, parser, AST, configuration
  e1.cpp           — C++ interpreter
  e1_compile.cpp   — Unified compiler
  e1_preamble.hpp  — Runtime preambles (macros for both backends)
  e1_bigint.hpp    — Bigint implementation
  e1_rt_bigint.cpp — LLVM runtime wrappers
  e1.koka          — Koka interpreter (e1)
  e1peg.koka       — Koka PEG interpreter (e1, ~20 lines)
  e2peg.koka       — Koka PEG interpreter (e2, ~50 lines)
  e3peg.koka       — Koka PEG interpreter (e3, closures/booleans)
  e0peg.koka       — Koka PEG interpreter (e0, ~20 lines)
  pegeval.koka     — Shared PEG interpreter runtime
  peg.koka         — Generic PEG parser
```

## Benchmarks

```bash
make bench                        # 2000 iterations of 31!
make bench BENCH_ARGS="100 20"    # custom
```

Results for `2000 31` (bigint):

| Implementation | Time |
|----------------|------|
| LLVM backend | 2ms |
| C++ backend | 17ms |
| LLVM JIT | 93ms |
| C++ interpreter | 0.60s |
| Koka PEG e2 | 1.1s |
| Koka PEG e3 | 1.7s |
| Koka interpreter | 2.1s |
| Koka PEG e1 | 2.5s |

The e2 PEG interpreter is ~2× faster than e1 PEG for factorial because e2 has native multiplication while e1 must emulate it with nested loops. The e3 interpreter is slower than e2 due to closure/boolean support overhead.

## Code Style

- clang-format with LLVM base, 100 columns, 4-space indent
- `std::print` with explicit `\n`
- Short aliases `p()`/`f()` in compiler

## Error Handling

Implementations differ in strictness for invalid syntax:

| Implementation | Behavior |
|----------------|----------|
| C++ | **Strict** — tokenizes all → parses all → executes. Fails on any invalid character. |
| e1 (Koka) | **Lenient** — `many(pstmt)` stops on parse failure, ignores trailing garbage. |
| e1peg (Koka) | **Lenient** — parses statement-by-statement, reports failure but tolerates garbage. |

Example (`print 1` followed by `@@@ invalid`):
- C++: Error before execution ("Unknown char: @")
- Koka: Prints `1`, then stops/reports

See `examples/test_dead_code*.e1` for test cases.
