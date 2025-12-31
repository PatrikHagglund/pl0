# Koka Interpreters

Two PL/0 interpreters implemented in Koka with different phase designs.

## Overview

| Interpreter | Phases | Parser | Grammar Source | Memoization |
|-------------|--------|--------|----------------|-------------|
| `pl0.koka` | 2 | Hand-written | Hardcoded | N/A |
| `pl0peg1.koka` | 1 | PEG meta-interpreter | External `.peg` file | Packrat |

## `pl0.koka` — Two-Phase Interpreter

Traditional architecture: parse entire program, then execute.

### Structure

```
src/
  pl0.koka        — Main entry, orchestrates parse+exec
  pl0-types.koka  — AST types (expr, stmt), environment
  pl0-parser.koka — Recursive descent parser (std/text/parse)
  pl0-eval.koka   — Evaluator with effect handlers
```

### Flow

```
Source → [Parse All] → AST (list<stmt>) → [Execute All] → Result
```

### Characteristics

- **Phase 1 (Parse):** Converts entire source to AST upfront
- **Phase 2 (Execute):** Walks AST with environment threading
- **Error handling:** Parse errors reported before execution begins
- **Use case:** Batch execution, static analysis possible between phases

### Build

```bash
make koka-pl0
```

## `pl0peg1.koka` — Single-Phase Interpreter

True single-phase: semantic actions execute during parsing, no AST intermediate.

### Structure

```
src/
  pl0peg1.koka — Semantic actions that build/execute thunks
  peg.koka     — Generic PEG parser with semantic action API
  pl0_1.peg    — Grammar file (external, loaded at runtime)
```

### Flow

```
Source → [Parse with Actions] → Thunk (closure) → [Execute] → ┐
           ↑                                                   │
           └──────────── [Advance Input] ──────────────────────┘
```

No AST is built. Semantic actions construct closures that capture parsed values:

- `SVExpr(f: env → int)` — Expression thunk
- `SVStmt(f: env → env)` — Statement thunk

### Characteristics

- **No AST:** Parsing directly produces executable thunks
- **Thunk-based:** Closures capture structure, deferred until environment is ready
- **Dynamic grammar:** Reads `.peg` file at runtime
- **Incremental:** Parse and execute one statement at a time
- **Use case:** REPLs, streaming input, studying PEG with semantic actions

### Memoization

The PEG parser uses packrat memoization to avoid redundant parsing:

```koka
// Memo table: (rule_name, position) → parse_result
alias memo-table = list<(memo-key, memo-result)>

// Memoized partial parse
peg-parse-partial-memo(g, rule, input, memo, orig)
  → (updated_memo, maybe<(rest, tree)>)
```

The memo table is threaded through all parse calls, caching results at each `(rule, position)` pair. This prevents exponential backtracking in ambiguous grammars.

### Build

```bash
make koka-peg
```

## Comparison

### When to use `pl0.koka`

- Need to analyze entire program before execution
- Want fastest execution (no runtime grammar interpretation)
- Grammar is fixed and won't change

### When to use `pl0peg1.koka`

- Experimenting with grammar changes (edit `.peg` file)
- Building a REPL or incremental evaluator
- Need immediate per-statement feedback
- Want to study PEG parsing with semantic actions
- Exploring AST-free interpreter design

## Effect Handlers

Both interpreters use Koka's algebraic effects for control flow:

```koka
effect loop-break
  ctl do-break(e: env): a

fun exec-loop(e: env, body: stmt): <loop-break, div> env
  with ctl do-break(e1) e1   // Handler: break returns env
  val e2 = exec(e, body)
  exec-loop(e2, body)        // Tail-recursive loop
```

This provides clean `break` semantics without exceptions or flags.

## Module Dependencies

### `pl0.koka`

```
pl0.koka
  ├── pl0-types.koka
  ├── pl0-parser.koka → pl0-types.koka
  └── pl0-eval.koka   → pl0-types.koka
```

### `pl0peg.koka`

```
pl0peg.koka
  └── peg.koka
```

Note: `pl0peg.koka` uses `semval` thunks instead of an AST. No syntax tree is built.
