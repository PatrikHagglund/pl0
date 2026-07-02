# TODO

## Next

- lvalue assignment paths (functional update) — DONE across interpreters,
  docs, and the efuzz generator (the latter re-enabled 2026-07-02 on a fork
  Koka toolchain; see last sub-task).
  `arr.i := e` etc. desugar to rebinding the base variable to an updated copy
  (value semantics, no aliasing; root must be a variable); see docs/DESIGN.md
  "lvalue Assignment: Functional Update". Shipped across e4/e5/e6 + docs/
  examples + fuzzer generation.
  - [x] e4 array element assignment (`arr.0 := e`, `arr (i) := e`, chained
        `arr.0 (i) := e`); e4.peg `lpath` rule + `SAssignPath`/`update-path`;
        7 e4_test cases; diff_e4 no-regression.
  - [x] e5 record field assignment (`rec.field := e`) + array assign carried
        into e5; nested + mixed array/record paths (`a.1.x`, `r.xs (0)`);
        `LField` selector; missing field is a type error. 7 e5_test cases;
        diff_e5 no-regression.
  - [x] e6: runtime (same functional update) + static checker. `check-lpath`
        walks the base variable's type along the path (array→elem, record→
        field, dynamic index must be int) and requires the addressed
        component's type == RHS type; base keeps its type. 4 well-typed + 5
        static-error e6_test cases; diff_e6 and diff_e6_illtyped no-regression.
  - [x] efuzz generation: RE-ENABLED (2026-07-02) on a fork Koka toolchain.
        Generates array/record component assignment with a read-back print;
        co-eval `fupdate`; `mut-path`; 650 diff seeds across e4/e5/e6 +mutated
        +ill-typed, 0 fails. (Had been reverted 2026-06-22 — code preserved at
        f46cd20 — because it tipped efuzz's Koka compile over the CI build
        budget; now restored verbatim.)

        ROOT CAUSE was two independent Koka optimizer bugs (both root-caused and
        fixed by a Koka-side session; analysis in
        ../koka/EFUZZ-COMPILE-EXPLOSION-REPORT.md, SPECIALIZER-LOOP-REPORT.md,
        efuzz-explosion-repro/):
          1. specializer infinite loop at -O1+ on the effect-polymorphic
             co-evaluator (this is why efuzz used to pass `--fno-specialize`).
             Fix: koka-lang/koka PR #899.
          2. core simplifier case-of-case rule duplicates ~2^n on `if/elif`
             chains whose guards use `&&`/`||`; the generator is full of these,
             so one ~75-line fn blew up to ~300k core nodes → ~90 MB / 928k-
             line C. NOT dodged by `--fno-specialize`. Fix: koka-lang/koka
             PR #902. (With both fixes, full efuzz compiles at -O3 in ~60s,
             output identical to -O0.)

        HOW IT'S ENABLED NOW: the hermetic toolchain points at an unofficial
        fork build carrying both fixes — koka dev 3.2.7 + #899/#902, tag
        `v3.2.7-pl0e-efuzz` in PatrikHagglund/koka, built by that repo's
        .github/workflows/bundle-pl0e.yaml (bundle layout identical to an
        upstream release). rules_koka/koka/private/repo.bzl fetches it by URL
        +sha256 (KOKA_VERSION = "3.2.7-pl0e-efuzz"); `--fno-specialize` dropped
        from the //src:efuzz target. CI stays hermetic; no source hacks.

        FOLLOW-UP: once #899 AND #902 ship in an OFFICIAL koka release, revert
        the toolchain to upstream — bump KOKA_VERSION and restore the
        koka-lang/koka release URL/sha in repo.bzl (efuzz.kk and BUILD.bazel
        need no further change).
  - [x] docs/examples: DESIGN.md "lvalue Assignment" section, FUZZING.md e4
        note, README grammar-levels + example list, and lvalue.e4/e5/e6
        example programs (output verified against their inline comments).
- ~~efuzz e6 oracle: well-typed-by-construction programs must pass e6peg's
  static checker~~ DONE (2026-06-15): //fuzz:diff_e6 fails on any
  "Static error". Found+fixed two generator/checker discrepancies
  (int-pattern-vs-array scrutinee; mixed int+bool case arms). 300 seeds
  (pure+mutated), 0 fails, 0 static-errors.
- ~~efuzz e6 ill-typed mutator (the dual oracle)~~ DONE (2026-06-20):
  `efuzz ... 6 -1` emits a well-typed program with one injected type
  error (marked "// expect-static-error: yes"); e6peg must reject it with
  "Static error". //fuzz:diff_e6_illtyped + smoke + rolling CI step. Two
  strategies (retype an existing binding; or inject a poison print with an
  ill-typed argument), ~10 distinct checker messages, negative control
  verified. 100 seeds, 0 fails.
- ~~typed closures at e6~~ DONE (2026-06-20): closures generate at e6 with
  typed params (`\p: int -> ...`, via a `typed` flag on FLam) and are bound
  by plain assignment (e6 infers the function type from the RHS); the
  `lvl <= 5` gate is removed. Applications (`f (a) (b)`) exercise the
  checker's apply path. Validated across all three e6 oracles (value+type
  / mutated / ill-typed), 0 fails; 55/60 seeds define a closure, 35/60
  apply one.
- ~~efuzz e5/e6: bool record fields~~ DONE (2026-06-21): record literals
  carry int and bool fields (`{f0: int, f1: bool}`); field access is routed
  to int or bool context by the field's type (`gen-field`/`gen-bfield`);
  record-pattern field binders are typed per field (int field → int var,
  bool field → bool var) and bool fields take binder/wildcard sub-patterns
  only (no bool literal pattern). Field types tracked per record in
  `rvars`. The mutator stays type-preserving (recurses by node) and the
  ill-typed mutator's int↔bool flip still rejects. Validated across e5,
  e5-mutated, e6, e6-mutated, e6-ill-typed (600 seeds), 0 fails.
- ~~efuzz e5/e6: nested (record-valued) record fields~~ DONE (2026-06-21):
  `FField`'s base is now an expression, so chained access `r.f0.f1` works;
  field types are tracked per record as an `ftype` tree
  (`FTInt`/`FTBool`/`FTRec`), nesting bounded to one level. Field access
  walks the tree to an int/bool leaf (`int-paths`/`bool-paths` +
  `build-access`); record-type strings recurse (`rec-type-str`/
  `ftype-str`); a record-typed pattern binder is tracked as a record var
  so its own fields stay accessible. Validated across e5, e5-mutated, e6,
  e6-mutated, e6-ill-typed (600 seeds), 0 fails; all 13 fuzz smokes pass.
  e6 record fields are now feature-complete (int/bool/nested).
- e6 design notes to revisit: no recursive types (so the Y combinator does
  not type-check — recursion is loops-only at e6); record types are
  invariant (no width subtyping in expressions, though record *patterns*
  still match extra fields); checker scoping is conservative (variables
  first bound inside loop/case/block bodies are not visible afterwards)
- e5 deferred design questions (from the pre-implementation e5.peg draft,
  saved decisions for later): tuples `(a, b)`, optional case scrutinee,
  block-as-expression (trailing expression value). (lvalue assignment paths —
  `rec.field := e`, `arr.0 := e` — are now DONE, see the top item.)
- ~~efuzz Phase 3c: extend the generator to e5~~ DONE (2026-06-14):
  records (int-field literals, field access, record pattern-cases with
  width subtyping), RRec in the co-evaluator, mutator+reducer support,
  //fuzz:diff_e5 + smokes + reduce_e5 + CI rolling. 300 seeds, 0 fails.
  Follow-up: done — bool + nested record fields both landed 2026-06-21
  (see the two DONE items above).
- ~~efuzz e6: extend the generator to e6 (typed bindings, type decls)~~
  DONE (2026-06-15): typed bindings (FTBind: int/bool/[int]/record),
  typed decls, closures gated out of e6, int-only if/case lowering.
  Typed lambda params at e6 still TODO (see oracle item above).
- ~~efuzz Phase 4 mutator~~ DONE (2026-06-14): semantics+type-preserving
  rewrites, self-validating, level-safe. `efuzz ... [mutate]` + drivers'
  4th MUTATE arg; pure+mutated smokes gated, rolling CI campaigns mutated.
- ~~efuzz Phase 4 reducer~~ DONE (2026-06-14): //fuzz:reduce_e4 /
  reduce_e3. efuzz 5th `keep` mask arg keeps a subset of body statements
  and re-co-evaluates (oracle stays correct); reduce.sh greedily drops
  statements while the failure persists. Self-tested via REDUCE_GREP
  (14 stmts -> 1). Remaining Phase 4: PEG `--stats` fuel-regression mode
  (motivating case already fixed); finer nested reduction; reduce against
  the enforce oracle.
- ~~PEG engine: packrat-memoize the action-executing path~~ DONE
  (2026-06-21): the exec path (peg-exec*) now memoizes at rule boundaries
  via a *mutable* memo handler (peg-memo effect / with-memo) installed
  above the peg-fail handlers, so positive AND negative (cached-failure)
  entries survive backtrack unwinding — the property the old dead/threaded
  memo could not provide (its fail handler discarded the table). Always on,
  a fresh table per statement parse; transparent to callers (the leading
  maybe<memo> in peg-exec-partial's result is now always Nothing). Removed
  the dead threaded exec-*-memo functions. Validated byte-identical to the
  oracle over 1000 fuzz seeds across e1-e6 (+mutated/ill-typed), all 19
  tests pass; added a peg_test stress case (14 nested parens through an
  overlapping-FIRST grammar) asserting rule calls stay linear (<200 vs.
  thousands un-memoized). The action-less tree matcher (peg-parse, test-
  only) keeps its older opt-in *-memo variants, untouched.
- ~~Koka specializer loop~~ fixed in ../koka (dev branch, see
  SPECIALIZER-LOOP-REPORT.md there) and now SHIPPED into pl0e's hermetic
  toolchain via the fork build (see the efuzz sub-task above): KOKA_VERSION
  bumped to 3.2.7-pl0e-efuzz, `--fno-specialize` dropped from //src:efuzz.
  `--config=koka-local` (NON-HERMETIC, KOKA_LOCAL_PATH in .bazelrc) remains
  available for testing future compiler builds. Still open: get #899/#902
  merged and released upstream, then revert the toolchain to koka-lang/koka.
- ~~Koka-next compatibility~~ resolved: the issue was the `.koka` file
  extension, not module headers — koka 3.2.3+ resolves imports only as
  `.kk`. All Koka sources renamed to the official `.kk`; hermetic
  toolchain bumped to 3.2.3; --config=koka-local now covers all targets
- ~~Make rules_koka more bazel-native~~ DONE (2026-06-13): koka_library
  now compiles to a build-dir artifact reused by dependents, so the
  shared peg/pegeval (and stdlib) compile once instead of per target.
  Interpreter rebuild ~3min -> ~1m7s once its library is cached.
  (Investigated stdlib-only reuse first; too small — ~8%/target — and
  reverted, since the per-dependent library recompile was the real cost.)
- Restructure directories by language level (e0/, e1/, ... + shared/)
- rules_cc pinned at 0.2.16 (latest compatible): 0.2.17+ removed targets
  toolchains_llvm_bootstrapped 0.5.9 still references. Bump it when the
  bootstrapped toolchain bumps its own rules_cc dependency.
- Decide: e4 trailing-wildcard pattern quirk — `(_;)` matches any array
  and "exact pattern ignoring the last element" is inexpressible
  (docs/FUZZING.md findings); fine as-is or change pattern syntax?

## Exploration ideas

- Efficient interpreters (Graal/Truffle, simple JIT)
- Standard library?
- Symbolic expressions (computer algebra)?
- Zig/Koru and OCaml as implementation languages
- Rascal and/or K Framework for specifications
- Syntactic sugar via rewrite rules in the PEG eval
- Beads for task tracking
- BuildStream/BuildGrid

## Open questions

(none currently)
