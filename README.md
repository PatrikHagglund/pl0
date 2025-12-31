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

The project uses a single Podman container (Fedora rawhide) with all tools:
- g++ (C++26)
- LLVM/Clang
- Koka

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

## Files

Grammars in `src/`: `pl0_0.peg` through `pl0_6.peg`

## Implementations

| Approach | Files | Notes |
|----------|-------|-------|
| Koka (hand-written parser) | `pl01.koka` | AST used|
| Koka (PEG meta-interpreter) | `peg.koka`, `pl0peg1.koka` | Single-phase parse+execute, no AST |
| C++ interpreter | `pl0_1.cpp` | Handwritten, AST used |
| Compiler in C++, to LLVM IR | `pl0_1_llvm.cpp` | i128 integers |

### Koka Interpreters

Source code is in `src/`.

**Direct Interpreter (`src/pl01.koka`)** — Hand-written parser:

```bash
make koka-pl0
```

Output: `7`, `1`, `8` (runs `examples/example_0.pl0`)

**PEG-based Interpreter (`src/peg.koka` + `src/pl0peg1.koka`)** — Meta-interpreter that reads grammar from a `.peg` file:

- `src/peg.koka` — Generic PEG parser/interpreter (~270 lines)
- `src/pl0peg1.koka` — PL/0 semantic actions and evaluator (~250 lines)
- `src/pl0_1.peg` — Grammar file compatible with the PEG interpreter

```bash
make koka-peg
```

Output: `7`, `1`, `8` (runs `examples/example_0.pl0`)

### C++ Interpreter

Standalone interpreter for pl0_1 (`src/pl0_1.cpp`):

```bash
make run
```

Output: `7`, `1`, `8` (runs `examples/example_0.pl0`)

Uses a container (Fedora rawhide with g++) for C++26 features (`std::expected`).

### Compiler in C++

Compiler that emits LLVM IR (`src/pl0_1_llvm.cpp`):

- Uses 128-bit integers (`i128`) for extended range
- Supports `arg1` and `arg2` built-in variables for command-line arguments
- Includes `print_i128` helper for full-precision output

```bash
make run-llvm           # run with lli (JIT)
make run-llvm-native    # compile to native with clang -O3
```

Output: `7`, `1`, `8` (runs `examples/example_0.pl0`)

Or manually:
```bash
make pl0_1_llvm
./pl0_1_llvm examples/bench_1_factorial.pl0 > out.ll
lli out.ll 10 33        # 10 iterations of 33!
clang -O3 out.ll -o out && ./out 10 33
```

The container includes LLVM tools (`lli`, `llc`, `clang`).

## Benchmarks

Factorial benchmark (`examples/bench_1_factorial.pl0`):

```bash
make bench-1                           # default: 2000 iterations of 31!
make bench-1 BENCH_1_ARGS="100 20"     # custom: 100 iterations of 20!
```

Compares: `lli` (JIT), `clang -O0`, `clang -O3`, C++ interpreter, and Koka interpreter.

Example results for `2000 31`:

| Implementation | Time |
|----------------|------|
| clang -O3 | 2ms |
| clang -O0 | 4ms |
| lli (JIT) | 37ms |
| C++ interpreter | 0.6s |
| koka -O3 | 2.1s |
| koka -O3 (PEG) | 2.4s |

Note: i128 limits the sum to avoid overflow (max ~19 iterations for 33!).

## Notes

Koka interpreters use effect handlers for clean control flow:
```koka
effect loop-break
  ctl do-break(): a

fun exec-loop(e: env, body: stmt): <loop-break, div> env
  with ctl do-break() e    // handler: break returns current env
  val e1 = exec(e, body)
  exec-loop(e1, body)
```
