// PL/0 Level 1 interpreter using PEG grammar
// Adds: loop, break_ifz (Turing-complete)

module e1peg

import src/peg
import src/pegeval

pub alias e1val = semval<void>

fun e1-action(name: string, txt: string, children: list<e1val>, _caps: captures<e1val>): e1val
  handle-base(name, txt, children).default(SVList(children))

fun exec-ext(_x: void, e: penv): <div,console,loop-break> penv
  e

pub fun main()
  run-interpreter("e1", "src/e1.peg", "examples/example.e1", e1-action, exec-ext,
    "Error: 'break_ifz' used outside of loop")
