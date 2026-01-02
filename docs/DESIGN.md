# Design Decisions

## Language Progression (pl0_0 through pl0_6)

### Philosophy
Each level is a strict superset of the previous. This allows:
- Studying what each feature adds to expressiveness
- Demonstrating how higher-level features can be emulated with lower-level primitives
- Incremental implementation complexity

### Level Rationale

| Level | Adds | Why Here |
|-------|------|----------|
| pl0_0 | Sequential only (`+`, `-`) | Baseline: not Turing-complete, no control flow |
| pl0_1 | `loop`, `break_ifz` | Minimal Turing-completeness (Minsky machine) |
| pl0_2 | `case`, `break`, `* / %`, comparisons | Practical imperative programming |
| pl0_3 | Booleans, callables, case expressions | First-class functions, proper boolean type |
| pl0_4 | Arrays, pattern matching | Compound data, destructuring |
| pl0_5 | Records, unit | Named fields, void/unit value |
| pl0_6 | Static typing, type definitions | Type safety, user-defined types |

### Why pl0_0 is Not Turing-Complete
Intentionally excludes loops to show the jump from "calculator" to "computer." Demonstrates that arithmetic alone (without unbounded iteration) cannot express general computation.

### Why pl0_1 is the Turing Threshold
The combination of:
1. Unbounded integers (counters)
2. Increment/decrement (`+`, `-`)
3. Zero-test with conditional jump (`break_ifz`)

This is exactly a 2-counter Minsky machine, proven Turing-complete by Minsky (1967).

### Emulation Principle
Each level's example file demonstrates encoding the *next* level's features using only current primitives:
- pl0_1 emulates `case`, `break`, `*`, `/`, `<` from pl0_2
- pl0_2 emulates booleans and simple callables from pl0_3
- etc.

This shows the features are conveniences, not fundamental extensions to computational power (after pl0_1).

## Control Flow: `break_ifz` vs `when` loops

### The Question
Should pl0_1 use `break_ifz expr` (break if zero) or `when expr stmt` (loop while non-zero)?

### Comparison

| Pattern | `break_ifz` | `when` |
|---------|-------------|--------|
| Loop while n>0 | `loop { break_ifz n; body }` | `when n { body }` |
| If-then | `loop { break_ifz c; action; break_ifz 0 }` | `when c { action; c := 0 }` |
| Unconditional break | `break_ifz 0` | (not expressible) |
| Multi-condition exit | `break_ifz a; break_ifz b` | (not expressible) |

### Decision: `break_ifz`

Reasons:
1. **More primitive** — `loop` + `break_ifz` are orthogonal; `when` combines them
2. **More expressive** — supports early exit, multi-condition exits, and if-then without mutation
3. **Aligns with Minsky machines** — the zero-test is the fundamental conditional primitive

The `when` construct would save ~1 line per simple loop but loses expressiveness for complex control flow (e.g., GCD's triple exit: `break_ifz a; break_ifz b; break_ifz a - b`).

### Trade-off
The "if-then" idiom is verbose:
```
loop {
  break_ifz condition
  action
  break_ifz 0
}
```
But it doesn't require mutating the condition variable, unlike `when`.
