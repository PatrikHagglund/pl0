# Design Decisions

## Language Progression (e0 through e6)

### Philosophy
Each level is *almost* a strict superset of the previous. This allows:
- Studying what each feature adds to expressiveness
- Demonstrating how higher-level features can be emulated with lower-level primitives
- Incremental implementation complexity

A strict superset was the original rule. It is deliberately broken in a few
places where keeping a low-level construct would be too ugly at higher
levels (see "Superset deviations" below).

### Superset deviations

Pragmatic, deliberate breaks of the superset rule (surfaced by the
differential-fuzzing work, see [FUZZING.md](FUZZING.md)):

| Levels | Deviation | Rationale |
|--------|-----------|-----------|
| e1 → e2 | `break_ifz` dropped | Effective as e1's minimal conditional primitive (Minsky machine), but too ugly once `case` + `break` exist |
| e2 → e3 | Comparisons yield `true`/`false` instead of `1`/`0` | e3 introduces a proper boolean type; comparison results stop being integers |
| e3 → e4 | `case` requires a scrutinee | e4's pattern matching needs `case expr { pattern -> ... }`; the guard form `case { cond -> ... }` no longer parses |

Consequences:
- e1 programs that use loops do not parse at level 2+ (e.g. `e1/factorial.e1`).
- e2 → e3 is a *syntactic* superset (all e2 examples parse and run on e3peg)
  but not a *semantic* one: an e2 program that uses a comparison result as an
  integer (`x := (a < b)`, `print (a < b)`, arithmetic on it) behaves
  differently at e3. Comparisons used only as `case` guards behave
  identically. At e3/e4, ill-typed operations (bool in arithmetic, `!` on an
  int, applying a non-closure, mixed-type `==`) are runtime type errors: the
  interpreter prints `Type error: ...` and halts. Case guards are the
  deliberate exception — they accept both bools and truthy ints, since the
  e2 default-arm idiom `1 -> { ... }` depends on it.
- e2/e3 programs that use `case` do not parse at level 4.

### Level Rationale

| Level | Adds | Why Here |
|-------|------|----------|
| e0 | Sequential only (`+`, `-`) | Baseline: not Turing-complete, no control flow |
| e1 | `loop`, `break_ifz` | Minimal Turing-completeness (Minsky machine) |
| e2 | `case`, `break`, `* / %`, comparisons | Practical imperative programming |
| e3 | Booleans, callables, case expressions | First-class functions, proper boolean type |
| e4 | Arrays, pattern matching | Compound data, destructuring |
| e5 | Records, unit | Named fields, void/unit value |
| e6 | Static typing, type definitions | Type safety, user-defined types |

### Why e0 is Not Turing-Complete
Intentionally excludes loops to show the jump from "calculator" to "computer." Demonstrates that arithmetic alone (without unbounded iteration) cannot express general computation.

### Why e1 is the Turing Threshold
The combination of:
1. Unbounded integers (counters)
2. Increment/decrement (`+`, `-`)
3. Zero-test with conditional jump (`break_ifz`)

This is exactly a 2-counter Minsky machine, proven Turing-complete by Minsky (1967).

### Emulation Principle
Each level's example file demonstrates encoding the *next* level's features using only current primitives:
- e1 emulates `case`, `break`, `*`, `/`, `<` from e2
- e2 emulates booleans and simple callables from e3
- etc.

This shows the features are conveniences, not fundamental extensions to computational power (after e1).

## Control Flow: `break_ifz` vs `when` loops

### The Question
Should e1 use `break_ifz expr` (break if zero) or `when expr stmt` (loop while non-zero)?

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

## Type System: Algebraic Structure

The operator set isn't ad hoc — each type carries a standard algebraic
structure, and the operators are exactly the structure-preserving operations on
it. This was the original motivation for the integer/boolean operator choices
(it predates the level split; it informs e2's arithmetic/comparisons and e3's
booleans) and is recorded here so the rationale isn't lost.

### Integers (ℤ): a Euclidean domain

- `(ℤ, +, ×)` is a commutative ring with unity. Unary `-` is the additive
  inverse.
- `/` and `%` provide *Euclidean division*: `a = b × (a/b) + (a%b)`. (Division
  by zero is outside the domain; the implementations treat `/0` and `%0` as
  erroneous with a fallback of 0 — see [E3_SPEC.md](E3_SPEC.md).)
- Being a Euclidean domain is what makes the classic integer algorithms
  expressible: GCD via the Euclidean algorithm, Bézout's identity, and unique
  factorization. The `gcd` examples at each level exercise exactly this.

### Booleans (𝔹): a Boolean algebra

- `(𝔹, ||, &&, !)` is a complemented distributive lattice. Unary `!` is the
  complement.
- It satisfies De Morgan's laws — `!(a && b) == !a || !b` — and the usual
  distributive/absorption identities.

### The type bridge: relational operators

Relational operators are predicates `ℤ × ℤ → 𝔹` — the only place the two
structures meet. This keeps the type discipline clean: `+ - * / %` require
integer operands and yield integers; `&& || !` require boolean operands and
yield booleans; `== < >` (and friends) are the bridge that turns integers into
booleans. e6's static checker enforces exactly this separation.

## lvalue Assignment: Functional Update

Compound values (arrays at e4+, records at e5+) support in-place-looking
assignment to a component: `arr.0 := e`, `arr (i) := e`, `rec.field := e`, and
chained paths like `arr.0 (i) := e` / `rec.f0.f1 := e`.

**Semantics: functional update, not mutation.** `arr.i := e` is *sugar* for
rebinding the base variable to an updated copy — conceptually
`arr := <arr with index i replaced by e>`. There is no aliasing and no heap:
```
a := (1; 2; 3;)
b := a
a.0 := 9      // a == (9; 2; 3;),  b == (1; 2; 3;)   (b is untouched)
```
This was a deliberate choice (2026-06-21). The whole language is value-oriented
— the environment maps names to immutable values and there are no
references/pointers anywhere — so reference semantics (where `a.0 := 9` would
also change `b`) would require introducing a mutable heap and aliasing model
that exists nowhere else. Functional update keeps the language small and
referentially transparent, and stays a local change to each interpreter's
assignment handler.

**Consequences:**
- The lvalue root must be a *variable*. `f().x := e` or `(a; b;).0 := e` are not
  expressible — there is no storage location, only a named binding to rebind.
- Evaluation order: the right-hand side is evaluated first, then the path's
  (dynamic) indices left to right. (Matters only for which *erroneous construct*
  — `div0`, `oob` — is reported first under `--enforce`.)
- Out-of-bounds element assignment is erroneous (kind `oob`, like out-of-bounds
  reads); the fallback leaves the container unchanged. Assigning through a
  non-array/non-record component is a type error and halts.
- At e6 the static checker requires the assigned value's type to match the
  component's type; the base variable's type is unchanged (an update can't
  change a structure's shape).
