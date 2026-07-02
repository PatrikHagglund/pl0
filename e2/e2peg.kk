// PL/0 Level 2 interpreter using PEG grammar
// Adds: case, break, comparisons, mul/div/mod

module e2peg

import shared/peg
import shared/pegeval

pub type e2ext
  E2Arm(cond: (penv) -> <div> int, body: (penv) -> <div,console,loop-break> penv)

pub alias e2val = semval<e2ext>

fun exec-case(e: penv, arms: list<e2val>): <div,console,loop-break> penv
  match arms
    Cons(SVExt(E2Arm(cond, body)), rest) -> if cond(e) != 0 then body(e) else exec-case(e, rest)
    _ -> e

fun e2-action(name: string, txt: string, children: list<e2val>, _caps: captures<e2val>): e2val
  if name == "_cons" then match txt
    "StmtArm" -> match children
      Cons(SVExpr(cond), Cons(SVStmt(body), _)) -> SVExt(E2Arm(cond, body))
      _ -> SVList(children)
    "CaseStmt" ->
      val arms = flatten-sv(children).filter(fn(c) match c { SVExt(_) -> True; _ -> False })
      SVStmt(fn(e) exec-case(e, arms))
    _ -> handle-base(name, txt, children).default(SVList(children))
  else handle-base(name, txt, children).default(SVList(children))

fun exec-ext(_x: e2ext, e: penv): <div,console,loop-break> penv
  e

pub fun main()
  run-interpreter("e2", "e2/e2.peg", "e2/example.e2", e2-action, exec-ext,
    "Error: 'break' used outside of loop")
