// PL/0 Level 3 interpreter using PEG grammar
// Refactored grammar with left-factored rules to avoid backtracking
//
// Note: Does not use pegeval.koka because e3 needs:
// - Multi-type values (int, bool, closure) vs pegeval's int-only
// - AST construction for closures that capture environment at runtime
// - Custom evaluation that threads e3env through function application

module e3peg

import shared/peg
import std/os/file
import std/os/path
import std/os/env

// Runtime values: int, bool, or closure
pub type rval
  VInt(n: int)
  VBool(b: bool)
  VClosure(params: list<string>, body: expr, env: e3env)

pub alias e3env = list<(string, rval)>

pub type expr
  EVal(v: rval)
  EVar(s: string)
  EBinop(op: string, l: expr, r: expr)
  ENot(e: expr)
  ENeg(e: expr)
  EApply(f: expr, a: expr)
  ECase(arms: list<(expr, expr)>)
  EFunc(params: list<string>, body: expr)

pub type stmt
  SExpr(e: expr)
  SAssign(id: string, e: expr)
  SDecl(id: string)
  SPrint(e: expr)
  SLoop(body: stmt)
  SBreak
  SBlock(stmts: list<stmt>)
  SCaseStmt(arms: list<(expr, stmt)>)

// Semantic values - now includes binary operation tails
pub type semval
  SVExpr(e: expr)
  SVStmt(s: stmt)
  SVIdent(s: string)
  SVList(vs: list<semval>)
  SVArm(cond: expr, body: semval)
  SVBinopTail(op: string, rhs: expr)  // For left-factored binary ops

fun env-get(e: e3env, key: string): rval
  match e.filter(fn(p) p.fst == key)
    Cons((_, v), _) -> v
    Nil -> VInt(0)

fun env-set(e: e3env, key: string, v: rval): e3env
  Cons((key, v), e.filter(fn(p) p.fst != key))

effect loop-break
  ctl do-break(e: e3env): a

// Ill-typed operations are runtime type errors, not silent defaults
// (decision 2026-06-11, found by efuzz; see docs/FUZZING.md findings).
// Exception: case guards keep accepting both bools and truthy ints, since
// the e2 default-arm idiom `1 -> { ... }` depends on it.
effect type-error
  ctl do-type-error(msg: string): a

// Erroneous constructs (E3_SPEC.md): incorrect but with a bounded
// consequence — a specified fallback value, or a diagnostic, per the
// handling mode (enforce / observe / fallback / unchecked) selected with
// --enforce, --erroneous=MODE, or --erroneous:KIND=MODE.
// Kinds: div0, unbound, nomatch.
effect violation
  ctl violate(knd: string, msg: string, fb: rval): rval

alias err-modes = list<(string, string)>

fun get-mode(modes: err-modes, knd: string): string
  match modes.filter(fn(p) p.fst == knd)
    Cons((_, m), _) -> m
    Nil -> match modes.filter(fn(p) p.fst == "*")
      Cons((_, m), _) -> m
      Nil -> "fallback"

fun kind(v: rval): string
  match v
    VInt(_) -> "int"
    VBool(_) -> "bool"
    VClosure(_, _, _) -> "closure"

fun eval(ex: expr, e: e3env): <div,type-error,violation> rval
  match ex
    EVal(v) -> v
    EVar(s) -> match e.filter(fn(p) p.fst == s)
      Cons((_, v), _) -> v
      Nil -> violate("unbound", "undeclared variable '" ++ s ++ "'", VInt(0))
    EBinop("&&", l, r) ->  // short-circuit: r is not evaluated when l is false
      match eval(l, e)
        VBool(False) -> VBool(False)
        VBool(True) -> match eval(r, e)
          VBool(b) -> VBool(b)
          v -> do-type-error("'&&' on " ++ kind(v))
        v -> do-type-error("'&&' on " ++ kind(v))
    EBinop("||", l, r) ->  // short-circuit: r is not evaluated when l is true
      match eval(l, e)
        VBool(True) -> VBool(True)
        VBool(False) -> match eval(r, e)
          VBool(b) -> VBool(b)
          v -> do-type-error("'||' on " ++ kind(v))
        v -> do-type-error("'||' on " ++ kind(v))
    EBinop(op, l, r) ->
      val lv = eval(l, e)
      val rv = eval(r, e)
      match (op, lv, rv)
        ("+", VInt(a), VInt(b)) -> VInt(a + b)
        ("-", VInt(a), VInt(b)) -> VInt(a - b)
        ("*", VInt(a), VInt(b)) -> VInt(a * b)
        ("/", VInt(a), VInt(b)) ->
          if b == 0 then violate("div0", "division by zero", VInt(0)) else VInt(a / b)
        ("%", VInt(a), VInt(b)) ->
          if b == 0 then violate("div0", "modulo by zero", VInt(0)) else VInt(a % b)
        ("==", VInt(a), VInt(b)) -> VBool(a == b)
        ("!=", VInt(a), VInt(b)) -> VBool(a != b)
        ("==", VBool(a), VBool(b)) -> VBool(a == b)
        ("!=", VBool(a), VBool(b)) -> VBool(a != b)
        ("<", VInt(a), VInt(b)) -> VBool(a < b)
        (">", VInt(a), VInt(b)) -> VBool(a > b)
        ("<=", VInt(a), VInt(b)) -> VBool(a <= b)
        (">=", VInt(a), VInt(b)) -> VBool(a >= b)
        _ -> do-type-error("'" ++ op ++ "' on " ++ kind(lv) ++ " and " ++ kind(rv))
    ENot(inner) -> match eval(inner, e)
      VBool(b) -> VBool(!b)
      v -> do-type-error("'!' on " ++ kind(v))
    ENeg(inner) -> match eval(inner, e)
      VInt(n) -> VInt(0 - n)
      v -> do-type-error("unary '-' on " ++ kind(v))
    EApply(f, a) -> match eval(f, e)
      VClosure(params, body, cenv) ->
        val arg = eval(a, e)
        match params
          Cons(p, rest) ->
            val newenv = env-set(cenv, p, arg)
            if rest.is-nil then eval(body, newenv)
            else VClosure(rest, body, newenv)
          Nil -> eval(body, cenv)
      v -> do-type-error("applying a non-closure (" ++ kind(v) ++ ")")
    ECase(arms) ->
      match arms
        Cons((cond, body), rest) ->
          match eval(cond, e)
            VBool(True) -> eval(body, e)
            VInt(n) | n != 0 -> eval(body, e)
            _ -> eval(ECase(rest), e)
        Nil -> violate("nomatch", "no case arm satisfied", VInt(0))
    EFunc(params, body) -> VClosure(params, body, e)

fun exec(s: stmt, e: e3env): <div,console,loop-break,type-error,violation> e3env
  match s
    SExpr(_) -> e
    SAssign(id, ex) -> env-set(e, id, eval(ex, e))
    SDecl(id) -> env-set(e, id, VInt(0))
    SPrint(ex) ->
      match eval(ex, e)
        VInt(n) -> println(n.show)
        VBool(b) -> println(if b then "true" else "false")
        VClosure(_, _, _) -> println("<closure>")
      e
    SLoop(body) ->
      with ctl do-break(e1) e1
      fun go(env: e3env): <div,console,loop-break,type-error,violation> e3env
        go(exec(body, env))
      go(e)
    SBreak -> do-break(e)
    SBlock(stmts) -> stmts.foldl(e, fn(acc, st) exec(st, acc))
    SCaseStmt(arms) ->
      match arms
        Cons((cond, body), rest) ->
          match eval(cond, e)
            VBool(True) -> exec(body, e)
            VInt(n) | n != 0 -> exec(body, e)
            _ -> exec(SCaseStmt(rest), e)
        Nil -> e

fun flatten-sv(vs: list<semval>): list<semval>
  vs.flatmap(fn(c) match c { SVList(inner) -> inner; _ -> [c] })

fun get-params(vs: list<semval>): list<string>
  flatten-sv(vs).filter-map(fn(v) match v { SVIdent(s) -> Just(s); _ -> Nothing })

fun sv-to-stmt(v: semval): maybe<stmt>
  match v
    SVStmt(s) -> Just(s)
    SVExpr(ex) -> Just(SExpr(ex))
    _ -> Nothing

// Fold binary operation tails: expr [op1 rhs1, op2 rhs2, ...] -> ((expr op1 rhs1) op2 rhs2) ...
fun fold-binop-tails(base: expr, tails: list<semval>): expr
  tails.foldl(base) fn(acc, tail)
    match tail
      SVBinopTail(op, rhs) -> EBinop(op, acc, rhs)
      _ -> acc

// Extract expression from semval
fun sv-to-expr(v: semval): maybe<expr>
  match v
    SVExpr(e) -> Just(e)
    _ -> Nothing

fun e3-action(name: string, txt: string, children: list<semval>, _caps: captures<semval>): semval
  val cs = flatten-sv(children)
  if name == "_text" then SVIdent(txt)
  // Handle left-factored binary expression rules: base tail*
  elif name == "or_expr" || name == "and_expr" || name == "sum_expr" || name == "product" then
    match cs
      Cons(SVExpr(base), rest) -> SVExpr(fold-binop-tails(base, rest))
      _ -> SVList(cs)
  // Handle comparison: base tail?
  elif name == "cmp_expr" then
    match cs
      Cons(SVExpr(base), Cons(SVBinopTail(op, rhs), _)) -> SVExpr(EBinop(op, base, rhs))
      Cons(SVExpr(base), _) -> SVExpr(base)
      _ -> SVList(cs)
  // Handle binary operation tails
  elif name == "or_tail" then
    match cs
      Cons(SVExpr(rhs), _) -> SVBinopTail("||", rhs)
      _ -> SVList(cs)
  elif name == "and_tail" then
    match cs
      Cons(SVExpr(rhs), _) -> SVBinopTail("&&", rhs)
      _ -> SVList(cs)
  elif name == "sum_tail" then
    match cs
      Cons(SVExpr(rhs), _) -> SVBinopTail(if txt.starts-with("+").bool then "+" else "-", rhs)
      _ -> SVList(cs)
  elif name == "product_tail" then
    val op = if txt.starts-with("*").bool then "*" elif txt.starts-with("/").bool then "/" else "%"
    match cs
      Cons(SVExpr(rhs), _) -> SVBinopTail(op, rhs)
      _ -> SVList(cs)
  elif name == "cmp_tail" then
    val op = if txt.starts-with("==").bool then "=="
             elif txt.starts-with("!=").bool then "!="
             elif txt.starts-with("<=").bool then "<="
             elif txt.starts-with(">=").bool then ">="
             elif txt.starts-with("<").bool then "<"
             else ">"
    match cs
      Cons(SVExpr(rhs), _) -> SVBinopTail(op, rhs)
      _ -> SVList(cs)
  elif name == "apply_expr" then
    val exprs = cs.filter-map(sv-to-expr)
    match exprs
      Nil -> SVList(cs)
      Cons(first, rest) -> SVExpr(rest.foldl(first, fn(acc, arg) EApply(acc, arg)))
  elif name == "_cons" then match txt
    "Int" -> match cs
      Cons(SVIdent(s), _) -> SVExpr(EVal(VInt(s.list.take-while(is-digit).string.parse-int.default(0))))
      _ -> SVExpr(EVal(VInt(0)))
    "True" -> SVExpr(EVal(VBool(True)))
    "False" -> SVExpr(EVal(VBool(False)))
    "Ident" -> SVIdent(cs.head.default(SVIdent("")).ident-str)
    "Var" -> SVExpr(EVar(cs.head.default(SVIdent("")).ident-str))
    "Assign" -> match cs
      Cons(SVIdent(id), Cons(SVExpr(e), _)) -> SVStmt(SAssign(id, e))
      _ -> SVList(cs)
    "Not" -> match cs { Cons(SVExpr(e), _) -> SVExpr(ENot(e)); _ -> SVExpr(EVal(VBool(False))) }
    "Neg" -> match cs { Cons(SVExpr(e), _) -> SVExpr(ENeg(e)); _ -> SVExpr(EVal(VInt(0))) }
    "Decl" -> match cs { Cons(SVIdent(id), _) -> SVStmt(SDecl(id)); _ -> SVList(cs) }
    "Print" -> match cs { Cons(SVExpr(e), _) -> SVStmt(SPrint(e)); _ -> SVList(cs) }
    "Loop" -> match cs { Cons(SVStmt(s), _) -> SVStmt(SLoop(s)); _ -> SVList(cs) }
    "Break" -> SVStmt(SBreak)
    "Block" ->
      val stmts = flatten-sv(cs).filter-map(sv-to-stmt)
      SVStmt(SBlock(stmts))
    "Params" -> SVList(cs)
    "Func" ->
      val params = get-params(cs.init)
      match cs.last
        Just(SVExpr(body)) -> SVExpr(EFunc(params, body))
        _ -> SVList(cs)
    "StmtArm" -> match cs
      Cons(SVExpr(cond), Cons(SVStmt(body), _)) -> SVArm(cond, SVStmt(body))
      _ -> SVList(cs)
    "ExprArm" -> match cs
      Cons(SVExpr(cond), Cons(SVExpr(body), _)) -> SVArm(cond, SVExpr(body))
      _ -> SVList(cs)
    "CaseStmt" ->
      val arms = flatten-sv(cs).filter-map fn(v)
        match v { SVArm(cond, SVStmt(body)) -> Just((cond, body)); _ -> Nothing }
      SVStmt(SCaseStmt(arms))
    "CaseExpr" ->
      val arms = flatten-sv(cs).filter-map fn(v)
        match v { SVArm(cond, SVExpr(body)) -> Just((cond, body)); _ -> Nothing }
      SVExpr(ECase(arms))
    _ -> SVList(cs)
  else match cs
    Cons(c, Nil) -> c
    _ -> SVList(cs)

fun ident-str(v: semval): string
  match v
    SVIdent(s) -> s.list.take-while(fn(c) c.is-alpha || c.is-digit || c == '_').string
    _ -> ""

// Returns Nothing on a type error or enforced violation: the program halts.
fun exec-safe(sv: semval, e: e3env, modes: err-modes): <div,console> maybe<e3env>
  with ctl violate(knd, msg, fb)
    val m = get-mode(modes, knd)
    if m == "enforce" then
      println("Violation (" ++ knd ++ "): " ++ msg)
      Nothing
    elif m == "observe" then
      println("Violation (" ++ knd ++ "): " ++ msg)
      resume(fb)
    else  // fallback / unchecked: the fallback value is the cheapest
          // behavior an interpreter has; unchecked matters for compilers
      resume(fb)
  with ctl do-type-error(msg)
    println("Type error: " ++ msg)
    Nothing
  with ctl do-break(e1)
    println("Error: 'break' used outside of loop")
    Just(e1)
  match sv
    SVStmt(s) -> Just(exec(s, e))
    SVList(Cons(SVStmt(s), _)) -> Just(exec(s, e))
    _ -> Just(e)

// --enforce | --erroneous=MODE | --erroneous:KIND=MODE (see E3_SPEC.md)
fun parse-err-flag(arg: string): maybe<(string, string)>
  if arg == "--enforce" then Just(("*", "enforce"))
  elif arg.starts-with("--erroneous=").bool then
    Just(("*", arg.replace-all("--erroneous=", "")))
  elif arg.starts-with("--erroneous:").bool then
    match arg.replace-all("--erroneous:", "").split("=")
      Cons(k, Cons(m, _)) -> Just((k, m))
      _ -> Nothing
  else Nothing

fun parse-flags(args: list<string>): div (bool, bool, bool, err-modes, list<string>)
  match args
    Cons("--dump", rest) ->
      val (_, w, s, em, r) = parse-flags(rest)
      (True, w, s, em, r)
    Cons("--warn", rest) ->
      val (d, _, s, em, r) = parse-flags(rest)
      (d, True, s, em, r)
    Cons("--stats", rest) ->
      val (d, w, _, em, r) = parse-flags(rest)
      (d, w, True, em, r)
    Cons(x, rest) ->
      val (d, w, s, em, r) = parse-flags(rest)
      match parse-err-flag(x)
        Just(km) -> (d, w, s, Cons(km, em), r)
        Nothing -> (d, w, s, em, Cons(x, r))
    Nil -> (False, False, False, [], [])

pub fun main()
  val args = get-args()
  val (do-dump, do-warn, do-stats, err-flags, rest-args) = parse-flags(args)

  val prog-path = match rest-args { Cons(p, _) -> p; Nil -> "e3/example.e3" }
  val arg1-val = match rest-args { Cons(_, Cons(n, _)) -> n.parse-int.default(0); _ -> 0 }
  val arg2-val = match rest-args { Cons(_, Cons(_, Cons(n, _))) -> n.parse-int.default(0); _ -> 0 }

  println("loading grammar...")
  val g = parse-peg(read-text-file("e3/e3.peg".path))
  if do-dump then
    println("loaded " ++ g.length.show ++ " rules")
    println(show-grammar(g))
    return ()
  if do-warn then
    val warnings = warn-grammar(g)
    if warnings.is-empty then println("No warnings")
    else warnings.foreach(fn(w) println("Warning: " ++ w))
  val prog = read-text-file(prog-path.path)
  println("e3: " ++ prog-path ++ " (" ++ prog.count.int/show ++ " chars)")

  if do-stats then
    val (result, stats) = peg-exec-stats(g, [], e3-action, "program", prog)
    match result
      Just(_) -> ()
      Nothing -> println("Parse failed")
    println(show-stats(stats))
  else
    var input := prog.slice
    var current-env: e3env := [("arg1", VInt(arg1-val)), ("arg2", VInt(arg2-val))]

    match peg-exec-partial(g, [], e3-action, "_", input)
      (_, Just((rest, _))) -> input := rest
      _ -> ()

    while { !input.is-empty }
      match peg-exec-partial(g, [], e3-action, "statement", input)
        (_, Just((rest, sv))) ->
          match exec-safe(sv, current-env, err-flags)
            Just(e2) ->
              current-env := e2
              match peg-exec-partial(g, [], e3-action, "_", rest)
                (_, Just((rest2, _))) -> input := rest2
                _ -> input := rest
            Nothing ->  // type error: halt
              input := "".slice
        _ ->
          if !input.is-empty then println("Parse failed at: " ++ input.string.first(20).string ++ "...")
          input := "".slice
    println("")
