# Ledger

## Goal

Explore the design and implementation of simple languages. Inspired by PL/0.

## Key decisions
- Keep languages small
- PL/0 grammar variants project (pl0_0 through pl0_6)
- Concepts/grammar should be familiar across variants/level
- Koka-based interpreters, C++ interpreter/compiler, and perhaps also other implementation languages

## Additional decisions/constraints/assumptions
- Currently using PEG grammars
- Each language level/variant should have an code example file.
    - This example file should: 1) Demonstrate new functionality if not done by step 2. 2) Demonstrate how to express/encode features from the next level using only the current level's primitives (if possible).

## Open questions (UNCONFIRMED if needed)
- (none)

## State
- Files organized into `src`, `examples`, `docs`, `test`, and `old`.
- Grammars reside in `src/`.
- pl0_0 has a grammar (13 lines) and minimal interpreter (`pl0peg0.koka`, 99 lines)
- pl0_1 has a grammar and working interpreter (`pl0peg1.koka`, 382 lines)
- pl0_1 has LLVM IR compiler (`pl0_1_llvm.cpp`) with configurable bit width
- C++ interpreter/compiler support arbitrary integer widths via Boost.Multiprecision
  - INT_BITS=0: dynamic bigint (cpp_int)
  - INT_BITS=32/64/128: native types
  - INT_BITS>128: Boost fixed-width (e.g., 256, 512, 1024)
- Factorial benchmark (`bench_1_factorial.pl0`) comparing lli, clang -O0/-O3, koka
- Started exploring semantics using Koka
- Other levels do not have interpreters (or compilers). They are sketched with a PEG grammars and code example files.

## Next
- Can C++ and LLVM IR backend code be shared/merged if the compiler is written in some other style, such as a functional style?
- How to apply the Language Implementation Configuration parameters in pl0_1.hpp to the Koka interpreters?
- Explore examples where parse errors (in dead code) cause different behaviour between the two Koka intepreters.
- Explore (more of a) full embedded action language in PEG (beyond @tag)
- Rename the pl0 languages to "E" or "e" (standing for "explore", but perhaps later for "expressive" and "efficient")?
- Support for "syntactic sugar"?
- Explore papers about efficient interpreters.
  - Test Graal/Truffle
  - Plan some adoptions towards a more efficient implementation
  - Simple JIT?
- Continue with other grammar/interpreter work
- Standard library?
- Support for symbolic expressions (as in computer algebra systems)?
- Testing with a tool like llvm-stress (and llvm-reduce)
- Perhaps a seprate project: "Agent DSL": Use LLMs and tools as operators and add memory and parallel control flow. VALIDATE/RETRY clause. Linda-style parallelism for sharing context information?

## Now

### Working set (current focus only; replace/prune as "Now" changes)
- `LEDGER.md`

## Done (prune when exceeding 30 items)
- Created `docs/DESIGN.md` documenting design decisions:
  - Language Progression: rationale for pl0_0 through pl0_6, why pl0_1 is Turing threshold
  - Control Flow: analyzed `break_ifz` vs `when` loops, decided on `break_ifz` for expressiveness
- Aligned pl0peg0.koka to pl0peg1.koka structure:
  - Same debug output format ("Starting...", "Grammar file read...", etc.)
  - Added arg1/arg2 support
  - Consistent flatten-sv helper
  - Added `koka-peg0` Makefile target
- Optimized LLVM bigint backend: added in-place operations (bi_set, bi_add_to, bi_sub_to)
  - Reduced allocations by modifying destination directly instead of creating new objects
  - clang -O3 improved from 145ms to 64ms (2.3x speedup)
  - Fixed Makefile to use clang++ for LLVM bitcode generation
- Fixed Makefile dependency handling: added `src/pl0_1.hpp` as dependency for C++ targets
- Added `make test` target: verifies 5 examples across 5 implementations (25 tests)
  - Tests: example_0, example_1, factorial, collatz, gcd
  - Implementations: C++ interpreter, C++ backend, LLVM backend, Koka, Koka-PEG
  - Filters numeric output to handle debug messages from koka-peg
- Fixed pl0peg1.koka bugs:
  - `act-ident` didn't include underscores (e.g., `d1_zero` parsed as `d1`)
  - `act-int-lit` failed when trailing comments present (e.g., `4 // x` parsed as 0)
- Updated all PEG grammars (pl0_0 through pl0_6) to allow underscores in identifiers
- Fixed pl01.koka interpreter bugs:
  - Parser didn't accept underscores in identifiers (e.g., `is_zero`)
  - `do-break` effect handler returned stale environment instead of current one
  - Updated Makefile `koka-pl0` target to compile library modules and accept FILE variable
- Added ARG_COUNT configuration parameter to `src/pl0_1.hpp`
  - Controls number of built-in arg<N> variables (default 2)
  - Updated interpreter, C++ backend, and LLVM backend to use loops
  - Updated docs/IMPLEMENTATIONS.md with "Language Implementation Configuration" section
- Parameterized integer bit width via `src/pl0_1.hpp` (INT_BITS)
  - Added Boost.Multiprecision for arbitrary widths (256, 512, etc.) and bigint (INT_BITS=0)
  - Compiler emits runtime as string (removed `pl0_1_rt.ll`)
  - Both interpreter and compiler use same config
  - Tested with 64, 128, 256 bits and bigint
- Moved Koka into podman container (no local install needed)
  - Updated Containerfile to install Koka v3.2.2
  - Updated Makefile to run Koka via container
  - Updated module imports to use `src/` prefix for project-root execution
- Added `arg1` and `arg2` built-in variables to LLVM compiler and Koka interpreter
- Added `run-llvm-native` Makefile target (clang -O3 compilation)
- Added `bench-1` Makefile target for factorial benchmark
- Upgraded LLVM compiler to use i128 integers with proper print_i128 helper
- Added LLVM IR compiler (`src/pl0_1_llvm.cpp`) - emits LLVM IR, runs with `lli`
- Renamed `pl0.cpp` to `pl0_1.cpp`, updated Makefile, fixed underscore handling in lexer
- Added `@tag` syntax to PEG grammar for action lookup
  - Rules can have `@tag` suffix: `int_lit = digit+ _ @int`
  - Tag is used for action lookup instead of rule name
  - Allows sharing actions between rules
  - Updated `peg.koka`, `pl0_0.peg`, `pl0_1.peg`, `PEG_SPEC.md`
- Fixed `act-ident` to extract just identifier (was including trailing comments)
- Simplified `pl0_0.peg` (13 lines) and `pl0peg0.koka` (99 lines)
  - Removed: `* / %`, comparisons, unary minus, declaration-only, parentheses
  - Kept: `+ -`, integers, variables, print, line comments
- Created `pl0peg0.koka` - minimal interpreter for pl0_0
- Renumbered grammar levels: pl0_0..pl0_5 → pl0_1..pl0_6
  - Created new pl0_0: sequential only, no control flow (not Turing-complete)
  - Updated all example files, README.md, docs, and source references
- True single-phase interpreter: `pl0peg1.koka` uses semantic actions during parsing (no AST)
  - Added semantic action API to `peg.koka` (`peg-exec-partial`, `action<s>`, `actions<s>`)
  - Thunk-based execution: expressions/statements are closures executed with environment
  - Verified with `example_0.pl0`: result=12, quotient=3, dividend=2
- Created `docs/INTERPRETERS.md` documenting two-phase vs single-phase designs
- Updated `docs/PEG_SPEC.md` with memoized API documentation
- Modularized `pl0.koka` into `pl0-types.koka`, `pl0-parser.koka`, `pl0-eval.koka`
- Added packrat memoization to `peg.koka` (`peg-parse-partial-memo`, `memo-table` type)
- Single-phase parse+execute working in `pl0peg1.koka`
- Added `peg-parse-partial` to `peg.koka` for incremental parsing
- Added `exec-safe` for handling `break_if` outside loops
- Verified `make koka-peg` works with `example_0.pl0`
- Organized project files into `src`, `examples`, `docs` directories
- Updated example files to emulate next-level features
- Added `print` statement to all grammar levels
- Created `peg_test.koka` test suite (30/30 pass)
- Fixed escape sequences in `peg.koka` string literals
- PEG parser specification (`PEG_SPEC.md`)
- Seven levels of grammar variants (pl0_0 through pl0_6)
