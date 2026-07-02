# Fuzzing: Adapting llvm-fuzzgen to eN

Status: generator + diff drivers implemented for e1-e6, plus the Phase 4
mutator and reducer. See the per-phase breakdown below.

## Usage

```bash
bazel run //e1:diff                        # e1: 20 seeds, size 20
bazel run //e1:diff -- -- 100 1 40        # e1: 100 seeds starting at 1, size 40
bazel run //e2:diff_e2 -- -- 100 1 30     # e2: e2peg vs e3peg vs expected
bazel run //e6:diff_e6 -- -- 100 1 16 3   # e6: e6peg + type-check oracle, mutated
bazel run //e6:diff_e6_illtyped -- -- 100 1 16  # e6: dual oracle — must reject ill-typed
bazel test //e1:efuzz_smoke //e2:efuzz_e2_smoke   # quick CI checks
bazel run //shared:efuzz -- 42 20 6            # print one generated program (level 6)
```

`//shared:efuzz` prints a random well-defined e1 program with its expected
output as trailing `// expect:` comments (the output is itself a valid e1
program). `//e1:diff` runs each program on the C++ interpreter, the Koka
AST interpreter, the Koka PEG interpreter, and the compiled-LLVM pipeline
(e1_compile --llvm → llvm-link with the bigint runtime → lli JIT), checks
the C++ backend emits without error, and compares every output against the
generator's prediction. Failing programs and outputs are saved to
`fuzz-failures/`.

## Findings so far

- **The level progression is "almost" a strict superset (resolved: claim
  revised).** Differential fuzzing surfaced two deviations, now documented
  as deliberate in [DESIGN.md](DESIGN.md):
  - e2/e3/e4 dropped `break_ifz` (superseded by `case` + `break`), so e1
    programs with loops do not parse at level 2+.
  - e4 `case` requires a scrutinee (for pattern matching), so e2/e3
    guard-style `case { ... }` programs do not parse at level 4.

  Resolution: the README/DESIGN claim was revised to "almost a strict
  superset" rather than changing the grammars (`break_ifz` is effective at
  the e1 level but too ugly to carry into higher levels). Consequence for
  the diff matrix: e1 programs run only on e1 implementations; Phase 2 e2
  programs can additionally run on e3peg (e2 → e3 holds: all e2 examples
  run unchanged) but not on e4peg.

- **e2 → e3 is a syntactic but not semantic superset** (found by Phase 2,
  17/20 first-run seeds diverged). Comparisons yield `1`/`0` at e2 but
  `true`/`false` at e3, so `print (a < b)` or arithmetic on a comparison
  result differs across the two levels. Comparisons used purely as `case`
  guards agree. The generator therefore emits comparisons only in guard
  position; now documented in DESIGN.md "Superset deviations".

- **e3peg evaluated booleans as 0 in arithmetic** instead of raising an
  error: `(3 < 5) + 1` was `2` at e2 but `0` at e3peg. Resolved (decision
  2026-06-11): ill-typed operations in e3peg/e4peg are now runtime type
  errors ("Type error: '+' on bool and int") that halt the program. Bool
  equality (`==`/`!=` on two bools), previously swallowed by the same
  catch-all, now works. Case guards still accept truthy ints (e2 idiom).
  Unbound variables still silently evaluate to 0 — separate open question.

- **e4 had no expression grouping**: `(e)` parsed as a 1-element array, so
  `print (2 + 3) * 4` computed garbage (silently, pre-type-errors). Exposed
  immediately by the type-error change. Fixed in e4.peg: an array literal
  now requires at least one `;` (`(a)` is grouping, `(a;)` a 1-element
  array), matching the grammar's own comment.

## Background

`llvm-fuzzgen` (llvm-project, branch `iso/uabpath/fuzzgen`,
`llvm/tools/llvm-fuzzgen/`) is a target-aware random program generator
for testing LLVM backends. Its core ideas transfer directly to this
repo; its LLVM-specific machinery does not.

### Ideas worth porting

1. **Generation by construction, not grammar inversion.** Programs are
   built from a small model (statements over tracked variables), not by
   randomly expanding the grammar. This makes well-definedness a
   construction invariant instead of a post-hoc filter.
2. **Co-evaluation (concrete value tracking).** The generator evaluates
   every expression as it emits it, so it always knows each variable's
   value. This gives:
   - UB-freedom: divisors are known non-zero, array indices known
     in-bounds, `break_ifz` conditions known to eventually fire.
   - A free **ground-truth oracle**: the generator knows the expected
     `print` output, so even a single implementation can be checked
     (catches "all implementations wrong the same way", which pure
     differential testing misses).
3. **Self-checking accumulator.** XOR/sum all generated values into one
   accumulator that is printed at the end, so every computation affects
   the observable output.
4. **Feature flags matching development phases.** fuzzgen's
   `--no-control-flow` / `--no-memory` / `--no-calls` map onto something
   we already have: the **language levels themselves**. `--level=eN` is
   the natural restriction flag.
5. **Determinism** (`--seed`), **batch mode** (`--count`, parallel
   workers), **auto-reduction** of failing cases.
6. **Mutator** (semantics-preserving transforms) — later phase.

### What does NOT transfer

- TargetLowering/DataLayout queries (no targets here; levels replace them).
- Fork-isolated in-process codegen (we run separate interpreter binaries).
- nuw/nsw, vectors, atomics, volatile (no such constructs in eN).

## Why this fits pl0e unusually well

- **Many executors per program.** An e1 program can run on the C++
  interpreter, the Koka AST interpreter, e1peg, the compiler's C++ and
  LLVM backends, and the LLVM JIT — and, because each level is a strict
  superset, also on e2peg/e3peg/e4peg. One generated e1 program ⇒ ~9
  independent results to compare. The superset property gives
  cross-level differential testing for free.
- **Arbitrary-precision integers.** Co-evaluation in Koka is exact for
  ℤ (no overflow modelling needed). It also exercises the bigint
  runtime and `INT_BITS` configurations in the compiled backends.
- **PEG performance fuzzing.** Generated programs are adversarial
  inputs for the PEG grammars: running them under `--stats` can flag
  pathological backtracking/fuel consumption that hand-written examples
  never trigger.

## UB surface per level (what the generator must guarantee)

| Level | Hazard | Guarantee by construction |
|-------|--------|---------------------------|
| e0+ | unbound variables | only reference already-assigned names |
| e1+ | non-terminating `loop` | counter-down loop pattern with tracked counter; `break_ifz` guaranteed to reach 0 |
| e2+ | `/` `%` by zero | divisor's tracked value ≠ 0 (else emit literal) |
| e2+ | nested `break` semantics | generate breaks only where the target loop is known |
| e3+ | unbounded recursion via callables | bounded call depth; closures capture tracked values |
| e4+ | out-of-bounds index | index expression's tracked value within tracked array length |
| e4+ | non-exhaustive `case` patterns | always include a catch-all `_` arm or cover the tracked value |

## Tool design: `efuzz`

A Koka program (`shared/efuzz.kk`) plus a small driver (`e1/e1_diff.sh`).

```
efuzz [seed] [size]        # implemented (e1 only)
```

Future flags: `--level=e0..e4`, `--mode=emit|diff`.

- **Generator core**: statement list over an environment of tracked
  variables `(name, concrete value)`. Each step picks a construct legal
  at `--level`, emits source text, and updates tracked values.
  Accumulator variable summed/XORed throughout, `print acc` at the end.
- **emit mode**: print program to stdout; expected output as a trailing
  comment (`// expect: 12345`).
- **diff mode** (driver): run the program on every implementation valid
  for its level (and all higher-level PEG interpreters), compare all
  outputs against each other **and** against the generator's predicted
  value. Report mismatches, crashes, and non-zero exits with the seed.
- **Driver**: shell script or Bazel `sh_binary` (`//e1:diff`)
  following the pattern of `bench/`; takes `--count` and a seed range,
  loops seeds. Parallelism via `xargs -P` is sufficient (interpreter
  runtime dominates, not generation).
- **Reduction**: on mismatch, drop statements one at a time and
  re-co-evaluate (the generator recomputes the expected value for the
  reduced program); keep the drop if the mismatch persists. Far simpler
  than llvm-reduce because programs are flat statement lists with
  block structure.

## Phasing

1. **Phase 1 — e1 generator + diff driver.** ✅ Done. Ints, `+`/`-`,
   assignment, bounded `loop`/`break_ifz` (counter-down and if-patterns),
   declarations, `print`, self-checking accumulator, fully-parenthesized
   expressions. Smoke target in `bazel test` (10 seeds); large runs via
   `bazel run //e1:diff`. Cross-level diffing blocked on the superset
   finding above.
2. **Phase 2 — e2 constructs.** ✅ Done (`efuzz [seed] [size] 2`,
   `bazel run //e2:diff_e2`). `case` statements (guard arms), `*` `/` `%`
   (Euclidean; `/0`/`%0` erroneous with fallback 0, per E3_SPEC.md),
   comparisons in guard position only (see findings), data-dependent
   early-break loop arms, and magnitude-guarded regeneration (values capped
   at 10^60 since multiplication inside loops can explode; checked during
   co-evaluation — repeated squaring would otherwise hang the generator).
   Diffs e2peg and e3peg against the co-evaluated expected output.

   **Enforce-mode oracle (bidirectional).** The co-evaluation records
   whether an erroneous construct actually fires and emits it as a
   `// violations: none|div0` marker. The driver then asserts both
   directions against `e3peg --enforce`: a clean program must run without
   tripping any violation (a spurious `Violation:` line is a checking-
   machinery bug), and a div0-marked program must halt with
   `Violation (div0)` (a missed violation is too). This tests the
   violation checking itself, not just value agreement.
3. **Phase 3 — e3/e4.**
   - **e3** ✅ Done (`efuzz [seed] [size] 3`, `bazel run //e3:diff_e3`).
     Typed generation (int/bool/closure variables — programs are
     well-typed by construction since type errors halt), booleans with
     short-circuit `&&`/`||`, comparisons as first-class bool values,
     closures (1-2 int params, capture-at-creation, applications;
     closures never flow as arguments, so self-application — the only
     route to divergence without loops — is impossible), and guard-style
     case expressions, which can fail to match: the `nomatch` violation
     kind joins `div0` in the marker and the bidirectional enforce
     oracle. Found an efuzz printer bug via 10/300 parse failures:
     comparison operands are `sum_expr`, so `a != !b` is ungrammatical
     (now noted in E3_SPEC.md).
   - **e4** ✅ Done (`efuzz [seed] [size] 4`, `bazel run //e4:diff_e4`).
     Arrays (literals, dot and dynamic indexing — out-of-bounds deliberately
     generated: `oob` joins the violation kinds), pattern-case statements
     and expressions (exact, prefix, literal, binder patterns; bindings
     persist after statement arms, mirroring e4peg). Level-4 emission uses
     scrutinee cases for loops/ifs since guard-style case is not e4 syntax.
     **Component assignment** (functional update, level 4+: `a.i := e`,
     `r.f := e`) is implemented and tested in the e4/e5/e6 interpreters (see
     docs/DESIGN.md "lvalue Assignment" and the per-level `*_test.sh`), but is
     *not yet generated by efuzz*: the generator + co-eval support was written
     and validated (650 diff seeds, 0 fails) but reverted because compiling
     the larger efuzz under the `--fno-specialize` workaround blew past the
     CI build budget. It returns once the Koka specializer fix ships in a
     hermetic release and `--fno-specialize` is dropped (see TODO.md).
     Findings:
     - **e4 grammar bug (fixed):** `paren_expr` consumed trailing
       whitespace although `atom_raw` must not, so multi-argument
       application with parenthesized arguments (`f (3) (5)`) silently
       split into two statements, and `(f (3) (5))` failed to parse.
     - **Pattern quirk (documented):** e4peg reads *any* trailing
       wildcard element as the prefix marker — `(_;)` matches every
       array, and "exact pattern ignoring the last element" is
       inexpressible. The generator avoids emitting trailing `_` in
       exact patterns.
     - **Performance (fixed):** e4peg showed exponential PEG backtracking
       — ~37s on a 174-line size-20 program (CI run #21, seed 100528).
       Root cause: the action-executing PEG path (`peg-exec-*`) is not
       memoized, and `paren_expr`'s three alternatives (unit / array /
       grouped) each re-parsed the inner expression, so a paren nested k
       deep was parsed 3^k times. Fixed by left-factoring `paren_expr` to
       parse the inner expression once with an optional array tail (e4/e5/
       e6 grammars + their `Paren`/`ArrTail` actions): seed 100528 dropped
       37s -> 117ms, and 100 size-30 seeds run in ~24s with 0 skips.
       Belt-and-suspenders: the e4 driver still treats a >90s timeout as a
       logged SKIP (not a failure), since efuzz programs are terminating by
       construction and output that never finished cannot be diffed.
       (General exec-path memoization remains future work — see TODO.)
     - **Koka 3.2.2/3.2.3 specializer loop:** compiling efuzz's
       effect-polymorphic co-evaluator at `-O1`+ sends Koka's
       specializer into a core-dumping loop (hundreds of MB of
       `specInnerCalls` traces). Worked around with a new
       `koka_opts = ["--fno-specialize"]` attribute in rules_koka;
       reproduces in Koka v3.2.3 — worth reporting upstream.
   - **e5** ✅ Done (`efuzz [seed] [size] 5`, `bazel run //e5:diff_e5`).
     Records: literals `{f0: e, ...}` with int, bool, **and nested-record**
     fields, field access (routed to the right context by the field's
     type, descending into nested records — `FField`'s base is an
     expression, so chained access `r.f0.f1` works), and record
     pattern-cases `case r { {f0: p, ...} -> ... }` with width subtyping
     (a pattern lists a subset of fields; extras allowed), reusing the
     level-4 scrutinee-case machinery. A field binder is typed by its field
     (int → int var, bool → bool var, record → record var, so its own
     fields stay accessible); bool and record fields take binder/wildcard
     sub-patterns only (there is no bool/record literal pattern). Field
     types are tracked per record as an `ftype` tree (`FTInt`/`FTBool`/
     `FTRec`); nesting is bounded to one level deep. Co-evaluator gains
     `RRec`; the mutator and reducer handle the new nodes. Validated:
     250 e5 seeds (pure + mutated), 0 failures.
   - **e6** ✅ Done (`efuzz [seed] [size] 6`, `bazel run //e6:diff_e6`).
     Typed bindings (`x : int = e`, `x : bool = e`, `xs : [int] = (...)`,
     `r : {f0: int, f1: bool, ...} = {...}`) and typed declarations (`x : int`),
     emitted by reusing the e5 generator with a level-6 syntax switch
     (`FTBind`). Closures carry typed params at e6 (`\p: int -> ...`) and
     are bound by plain assignment — e6's checker infers the function type
     from the RHS, so no binding annotation is needed; closure applications
     (`f (a) (b)`) exercise the checker's apply path. `if`/`case` conditions
     are restricted to `int` scrutinees so the int-only
     `case cond { 0 -> {} _ -> {...} }` lowering stays well-typed. **New oracle — the type-check oracle:**
     generated programs are well-typed by construction, so e6peg's static
     checker must accept them; the driver fails on any `Static error`
     (a wrongly-rejected valid program is a checker bug; an ill-typed
     emission is a generator bug). This cross-checks the generator's type
     discipline against an independent checker, and immediately found two
     discrepancies, both fixed in the generator:
     - **int patterns against array scrutinees:** the array pattern-case
       emitted int-literal patterns (`PLitP`) against `[int]` scrutinees —
       harmless dynamically at e4/e5 but rejected by e6's static checker
       (`expected int, got [int]`). Fixed by threading the level into
       `gen-pat` and gating literal patterns to `lvl <= 5`.
     - **mixed int+bool case arms:** the `if`-lowering emitted
       `case acc { 0 -> {} false -> {} _ -> {...} }`, mixing `int` and
       `bool` patterns against one scrutinee. Fixed by restricting the
       level-6 `if` condition to `int` and emitting an int-only `case`.
     Validated: 300 e6 seeds (150 pure + 150 mutated), 0 failures,
     0 static-errors.

     **Ill-typed mutator (the dual oracle)** ✅ Done
     (`efuzz [seed] [size] 6 -1`, `bazel run //e6:diff_e6_illtyped`). A
     negative `mutate` arg selects ill-typed mode: efuzz generates a
     well-typed e6 program and injects exactly ONE guaranteed type error,
     marked `// expect-static-error: yes`. e6peg's static checker must then
     reject it with `Static error`; a clean run with no such line means the
     checker accepted an ill-typed program (a hole). Two complementary,
     always-static strategies (chosen by RNG): retype an existing typed
     binding so its annotation contradicts its initializer (int↔bool,
     int↔`[int]`, int↔record), or — when there is no binding to retype —
     inject a poison `print` whose argument is ill-typed (`!0`, `-true`,
     `true + 1`, `1 && 2`, `1 == true`), each hitting a distinct
     `check-expr` path. Poisoned programs are deliberately NOT co-evaluated
     (they are ill-typed; the co-evaluator assumes well-typedness). Since
     e6peg checks statements one at a time, the well-typed prefix may run
     and print before the poisoned statement trips the checker — the oracle
     only requires the `Static error` line to appear. Validated: 100 seeds,
     0 failures; ~10 distinct checker messages exercised; negative control
     confirmed (the un-poisoned program emits no `Static error`).
4. **Phase 4 — mutator.** ✅ Done (`efuzz [seed] [size] [level] [mutate]`,
   4th arg = mutation passes; drivers take a 4th `MUTATE` arg). The
   mutator applies semantics- AND type-preserving rewrites to a generated
   program so the co-evaluated output is unchanged, reaching edge cases
   pure generation misses:
   - commute commutative binops (`a+b`, `a*b`, `a&&b`, `a||b`, `a==b`,
     `a!=b`);
   - flip ordering comparisons (`a<b` → `b>a`, `a<=b` → `b>=a`, mirror);
   - rewrite int literals (`n` → `a+b` with `a+b=n`, `n+0`, `-(-n)`).
   It is **self-validating**: `generate` co-evaluates before and after and
   throws if the output changed (a non-semantics-preserving mutation = a
   mutator bug). Level-safety comes for free — literal rewrites use only
   `+`/unary-`-` (valid at e1+), and commute/flip only *rewrite* existing
   nodes, which by construction exist only at the level that produced
   them. Validated: 750 mutated seeds across e1–e4, 0 failures.
   CI: `bazel test //...` gates both pure and mutated smokes; the
   rolling per-level campaigns now run mutated with fresh per-run seeds.

   **Reducer** ✅ Done (`bazel run //e4:reduce_e4 -- <seed> <size>
   <mutate>`, also `reduce_e3`). Delta-debugging: efuzz takes a 5th `keep`
   mask arg ("all" | "none" | "0,2,5") that keeps only those top-level
   body statements and RE-CO-EVALUATES, so the `// expect:` oracle stays
   correct for the reduced program (no stale expectations). `reduce.sh`
   greedily drops statements while the failure persists — interestingness
   is "interpreter output != co-evaluated expect, or timeout/crash".
   Validated: a passing seed reports "nothing to reduce"; via the
   `REDUCE_GREP` self-test predicate the ddmin loop shrank a 14-statement
   program to the 1 statement responsible for a target output line.
   Still open: the PEG `--stats` fuel-regression mode (its original
   motivating case, e4 paren backtracking, is already fixed); finer
   (nested) reduction granularity; reducing against the enforce oracle.
5. **Phase 5 — records/unit (e5) and static typing (e6).** ✅ Done
   (see the e5/e6 entries under Phase 3). e6 added both halves of the
   type oracle: well-typed-by-construction programs must pass e6peg's
   static checker, and the ill-typed mutator's poisoned programs must be
   rejected with `Static error`. Typed closures are generated at e6
   (`\p: int -> ...`, applications included), and records carry int, bool,
   and nested-record fields (`{f0: int, f1: {f0: bool}}`, chained access
   `r.f1.f0`) at both e5 and e6.

Note (superset deviations, see above): per-level diff matrices are
e1 → {e1, e1_koka, e1peg, LLVM JIT, cpp-emit}, e2 → {e2peg, e3peg},
e3 → {e3peg}, e4 → {e4peg}, e5 → {e5peg}, e6 → {e6peg + static-checker
oracle}.

## Open questions

- Exact accumulator scheme (sum vs XOR-like mixing in ℤ — sum is
  simplest and sufficient since values are exact).
- Whether the driver compares full stdout or only the final printed
  value (full stdout preferred; programs may print multiple times).
- UNCONFIRMED: whether the Koka AST interpreter (`e1.kk`) and PEG
  interpreters agree on `print` formatting (verify in Phase 1).
