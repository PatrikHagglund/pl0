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
- Stack-based bigint: dynamic variable sizing vs stacksave/restore conflict
  - Dynamic sizing (variables as `ptr*`): allows arbitrary growth, but `stackrestore` invalidates buffers → crash (LLVM internal error observed)
  - Fixed buffers + stacksave/restore: works, but limits max integer size (currently 520 bytes = 4096 bits)
  - Is there a way to have both? Possible approaches:
    1. Heap-allocate only variables, stack-allocate only temporaries
    2. Use a separate "bigint stack" managed manually (not via alloca)
    3. Analyze program to determine max size per variable at compile time
  - Need to understand LLVM's stacksave/restore semantics better — does it invalidate *all* allocas after the save point, or only dynamic ones?

## State
- Files organized into `src`, `examples`, `docs`, `test`, and `old`.
- Grammars reside in `src/`.
- pl0_0 has a grammar (13 lines) and minimal interpreter (`pl0peg0.koka`, 99 lines)
- pl0_1 has a grammar and working interpreters/compilers:
  - `pl0peg1.koka` (382 lines) — single-phase PEG interpreter
  - `pl01.koka` — two-phase Koka interpreter
  - `pl0_1.cpp` — C++ interpreter
  - `pl0_1_compile.cpp` (112 lines) — unified C++/LLVM compiler
- Stack-based bigint runtime (`pl0_1_rt_bigint_stack.cpp`) — no heap allocation
- C++ implementations support configurable integer widths via `pl0_1.hpp`
- Factorial benchmark: C++ backend 22ms, LLVM backend 25ms, lli 84ms
- Other levels (pl0_2 through pl0_6) have PEG grammars and examples but no interpreters

## Next
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
- Unified C++/LLVM compiler replacing separate backends:
  - `pl0_1_compile.cpp` (112 lines) + `pl0_1_preamble.hpp` (85 lines)
  - Single `Gen` struct with `L` flag for backend selection
  - Removed old heap-based bigint runtime
  - LLVM backend now nearly as fast as C++ backend (25ms vs 22ms)
- Stack-based bigint runtime (`pl0_1_rt_bigint_stack.cpp`):
  - No heap allocation — all buffers on stack via `alloca`
  - Uses `llvm.stacksave`/`llvm.stackrestore` in loops to prevent stack exhaustion
  - 2.7x faster than old heap-based (25ms vs 67ms for 2000×31!)
- Updated docs/IMPLEMENTATIONS.md and README.md with new benchmarks
- Created `docs/DESIGN.md` documenting design decisions
- Aligned pl0peg0.koka to pl0peg1.koka structure
- Added `make test` target: 25 tests across 5 implementations
- Fixed pl0peg1.koka and pl01.koka bugs
- Added ARG_COUNT and INT_BITS configuration parameters
- Moved Koka into podman container
- Added `arg1` and `arg2` built-in variables
- Added `bench-1` Makefile target
- Added LLVM IR compiler with configurable bit width
- Added `@tag` syntax to PEG grammar
- Simplified `pl0_0.peg` and `pl0peg0.koka`
- Renumbered grammar levels: pl0_0..pl0_5 → pl0_1..pl0_6
- True single-phase interpreter: `pl0peg1.koka`
- Added packrat memoization to `peg.koka`
- Organized project files into `src`, `examples`, `docs` directories
- Created `peg_test.koka` test suite (30/30 pass)
- PEG parser specification (`PEG_SPEC.md`)
- Seven levels of grammar variants (pl0_0 through pl0_6)
