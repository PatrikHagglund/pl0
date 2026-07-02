# Agent Notes

Project overview, goals, and philosophy: [README.md](README.md).
Language-design decisions and rationale: [docs/DESIGN.md](docs/DESIGN.md)
and the specs ([docs/E1_SPEC.md](docs/E1_SPEC.md),
[docs/E3_SPEC.md](docs/E3_SPEC.md)).
Backlog and open questions: [TODO.md](TODO.md).

## Commands

```bash
bazel test //...                 # full test suite
bazel run //e1:e1 -- e1/factorial.e1      # run an interpreter
bazel run //e1:diff -- -- 100 1 30             # differential fuzzing (e1)
bazel run //e2:diff_e2 -- -- 100 1 30          # differential fuzzing (e2)
bazel run //bench:bench                          # benchmarks
```

## Conventions

- Run the test suite before committing.
- Durable state lives in the repo, not in chat: record language-design
  decisions in docs/DESIGN.md or the relevant spec, keep README's feature
  list current, and maintain TODO.md (add follow-ups, prune finished
  items). History belongs in commit messages.
- On memory-constrained machines, parallel Koka compiles can get
  OOM-killed (observed once in a small dev container; the compiler peaks
  at ~0.8 GB per module) — if so, build with `--jobs=2`. GitHub CI does
  NOT need this: verified by a cold full-parallelism build on a standard
  runner (16 GB, 4 cores).
