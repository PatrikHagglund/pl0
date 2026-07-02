// PL/0 Level 0 interpreter using PEG grammar
// Sequential only - no loops (NOT Turing-complete)

module e0peg

import shared/peg
import shared/pegeval

pub alias e0val = semval<void>

fun e0-action(name: string, txt: string, children: list<e0val>, _caps: captures<e0val>): e0val
  handle-base(name, txt, children).default(SVList(children))

fun exec-ext(_x: void, e: penv): <div,console,loop-break> penv
  e

pub fun main()
  run-interpreter("e0", "e0/e0.peg", "e0/example.e0", e0-action, exec-ext, "")
