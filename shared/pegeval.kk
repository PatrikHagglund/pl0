// Shared runtime for PEG-based e0/e1/e2 interpreters

module pegeval

import shared/peg
import std/os/file
import std/os/path
import std/os/env

// Environment
pub alias penv = list<(string, int)>

pub fun env-get(e: penv, key: string): int
  match e.filter(fn(p) p.fst == key)
    Cons((_, v), _) -> v
    Nil -> 0

pub fun env-set(e: penv, key: string, v: int): penv
  Cons((key, v), e.filter(fn(p) p.fst != key))

// Loop control
pub effect loop-break
  ctl do-break(e: penv): a

pub fun exec-loop(e: penv, body: (penv) -> <div,console,loop-break> penv): <div,console,loop-break> penv
  with ctl do-break(e1) e1
  exec-loop(body(e), body)

// Extensible semantic value type
pub type semval<x>
  SVExpr(f: (penv) -> <div> int)
  SVStmt(f: (penv) -> <div,console,loop-break> penv)
  SVIdent(s: string)
  SVList(vs: list<semval<x>>)
  SVExt(ext: x)
  SVBinopTail(op: string, rhs: (penv) -> <div> int)

// Flatten nested SVList wrappers (2 levels needed for grammar rules like
// `(statement ";"? _)*` which nest: repetition wraps group wraps elements).
// Fixed iterations avoid stack overflow that recursive flattening causes.
// If deeper grammar nesting is added, increase iterations - insufficient
// flattening causes pattern match failures (statements not recognized).
pub fun flatten-sv(vs: list<semval<x>>): list<semval<x>>
  vs.flatmap(fn(c) match c { SVList(inner) -> inner; _ -> [c] })
    .flatmap(fn(c) match c { SVList(inner) -> inner; _ -> [c] })

// Fold binary operation tails: base op1 rhs1 op2 rhs2 ... -> ((base op1 rhs1) op2 rhs2) ...
fun fold-binop-tails(base, tails: list<semval<x>>)
  match tails
    Nil -> base
    Cons(SVBinopTail(op, rhs), rest) ->
      fold-binop-tails(fn(e) apply-binop(op, base(e), rhs(e)), rest)
    Cons(_, rest) -> fold-binop-tails(base, rest)

fun apply-binop(op: string, l: int, r: int): int
  match op
    "+" -> l + r
    "-" -> l - r
    "*" -> l * r
    "/" -> if r == 0 then 0 else l / r
    "%" -> if r == 0 then 0 else l % r
    "==" -> if l == r then 1 else 0
    "!=" -> if l != r then 1 else 0
    "<" -> if l < r then 1 else 0
    ">" -> if l > r then 1 else 0
    "<=" -> if l <= r then 1 else 0
    ">=" -> if l >= r then 1 else 0
    _ -> 0

// Base constructor handling - call from your action handler
pub fun handle-base(name: string, txt: string, children: list<semval<x>>): maybe<semval<x>>
  if name == "_text" then Just(SVIdent(txt))
  elif name == "_int" || name == "int" then
    Just(SVExpr(fn(_) txt.list.take-while(fn(c) c.is-digit || c == '-').string.parse-int.default(0)))
  elif name == "_str" then Just(SVIdent(txt))
  elif name == "_cons" then handle-cons(txt, children)
  elif name == "_lit" then Just(SVList(children))
  // Handle left-factored rules: base tail*
  elif name == "sum_expr" || name == "product" then
    val flat = flatten-sv(children)
    match flat
      Cons(SVExpr(base), rest) -> Just(SVExpr(fold-binop-tails(base, rest)))
      _ -> Just(SVList(flat))
  // Handle comparison: base tail?
  elif name == "cmp_expr" then
    val flat = flatten-sv(children)
    match flat
      Cons(SVExpr(base), Cons(SVBinopTail(op, rhs), _)) -> Just(SVExpr(fn(e) apply-binop(op, base(e), rhs(e))))
      Cons(SVExpr(base), _) -> Just(SVExpr(base))
      _ -> Just(SVList(flat))
  else match children
    Cons(c, Nil) -> Just(c)
    _ -> Just(SVList(children))

fun handle-cons(txt: string, children: list<semval<x>>): maybe<semval<x>>
  match txt
    "Assign" -> match children
      Cons(SVIdent(id), Cons(SVExpr(f), _)) -> Just(SVStmt(fn(e) env-set(e, id, f(e))))
      _ -> Nothing
    "Decl" -> match children
      Cons(SVIdent(id), _) -> Just(SVStmt(fn(e) env-set(e, id, 0)))
      _ -> Nothing
    "Int" -> match children
      Cons(SVIdent(s), _) -> Just(SVExpr(fn(_) s.list.take-while(fn(c) c.is-digit).string.parse-int.default(0)))
      _ -> Just(SVExpr(fn(_) 0))
    "Ident" -> match children
      Cons(SVIdent(s), _) -> Just(SVIdent(s.list.take-while(fn(c) c.is-alpha || c.is-digit || c == '_').string))
      _ -> Just(SVIdent(""))
    "Print" -> match children
      Cons(SVExpr(f), _) -> Just(SVStmt(fn(e) { println(f(e).show); e }))
      _ -> Just(SVStmt(fn(e) e))
    "Var" -> match children
      Cons(SVIdent(id), _) -> Just(SVExpr(fn(e) env-get(e, id)))
      _ -> Just(SVExpr(fn(_) 0))
    // Binop tails for left-factored rules
    "Add" -> make-binop-tail("+", children)
    "Sub" -> make-binop-tail("-", children)
    "Mul" -> make-binop-tail("*", children)
    "Div" -> make-binop-tail("/", children)
    "Mod" -> make-binop-tail("%", children)
    "Eq" -> make-binop-tail("==", children)
    "Ne" -> make-binop-tail("!=", children)
    "Lt" -> make-binop-tail("<", children)
    "Gt" -> make-binop-tail(">", children)
    "Le" -> make-binop-tail("<=", children)
    "Ge" -> make-binop-tail(">=", children)
    "Neg" -> match children
      Cons(SVExpr(f), _) -> Just(SVExpr(fn(e) 0 - f(e)))
      _ -> Just(SVExpr(fn(_) 0))
    "BreakIfz" -> match children
      Cons(SVExpr(f), _) -> Just(SVStmt(fn(e) if f(e) == 0 then do-break(e) else e))
      _ -> Just(SVStmt(fn(e) e))
    "Break" -> Just(SVStmt(fn(e) do-break(e)))
    "Loop" -> match children
      Cons(SVStmt(body), _) -> Just(SVStmt(fn(e) exec-loop(e, body)))
      _ -> Just(SVStmt(fn(e) e))
    "Block" ->
      val stmts = flatten-sv(match children { Cons(SVList(vs), _) -> vs; _ -> children })
        .filter(fn(c) match c { SVStmt(_) -> True; _ -> False })
      Just(SVStmt(fn(e) stmts.foldl(e, fn(acc, s) match s { SVStmt(f) -> f(acc); _ -> acc })))
    _ -> Nothing

fun make-binop-tail(op: string, children: list<semval<x>>): maybe<semval<x>>
  val flat = flatten-sv(children)
  match flat
    Cons(SVExpr(rhs), _) -> Just(SVBinopTail(op, rhs))
    _ -> Nothing

// Generic exec-safe
pub fun exec-safe(
  v: semval<x>, 
  e: penv,
  exec-ext: (x, penv) -> <div,console,loop-break> penv,
  break-msg: string
): <div,console> penv
  with ctl do-break(e1)
    if break-msg != "" then println(break-msg)
    e1
  exec-safe-inner(v, e, exec-ext)

fun exec-safe-inner(v: semval<x>, e: penv, exec-ext: (x, penv) -> <div,console,loop-break> penv): <div,console,loop-break> penv
  match v
    SVStmt(f) -> f(e)
    SVList(Cons(x, _)) -> exec-safe-inner(x, e, exec-ext)
    SVExt(x) -> exec-ext(x, e)
    _ -> e

// Parse flags from args, returns (do-warn, do-stats, remaining-args)
fun parse-flags(args: list<string>): div (bool, bool, list<string>)
  match args
    Cons("--warn", rest) ->
      val (_, s, r) = parse-flags(rest)
      (True, s, r)
    Cons("--stats", rest) ->
      val (w, _, r) = parse-flags(rest)
      (w, True, r)
    Cons(x, rest) ->
      val (w, s, r) = parse-flags(rest)
      (w, s, Cons(x, r))
    Nil -> (False, False, [])

// Generic interpreter runner
pub fun run-interpreter(
  level: string,
  grammar-file: string,
  default-file: string,
  make-action: (string, string, list<semval<x>>, captures<semval<x>>) -> semval<x>,
  exec-ext: (x, penv) -> <div,console,loop-break> penv,
  break-msg: string
): <console,div,exn,fsys,ndet> ()
  val args = get-args()
  val (do-warn, do-stats, rest-args) = parse-flags(args)
  val prog-path = match rest-args { Cons(p, _) -> p; Nil -> default-file }
  val arg1-val = match rest-args { Cons(_, Cons(n, _)) -> n.parse-int.default(0); _ -> 0 }
  val arg2-val = match rest-args { Cons(_, Cons(_, Cons(n, _))) -> n.parse-int.default(0); _ -> 0 }

  val g = parse-peg(read-text-file(grammar-file.path))
  if do-warn then
    val warnings = warn-grammar(g)
    if warnings.is-empty then println("No warnings")
    else warnings.foreach(fn(w) println("Warning: " ++ w))
  val prog = read-text-file(prog-path.path)
  println(level ++ ": " ++ prog-path ++ " (" ++ prog.count.int/show ++ " chars)")

  if do-stats then
    val (result, stats) = peg-exec-stats(g, [], make-action, "program", prog)
    match result
      Just(_) -> ()
      Nothing -> println("Parse failed")
    println(show-stats(stats))
  else
    var input := prog.slice
    var current-env: penv := [("arg1", arg1-val), ("arg2", arg2-val)]

    match peg-exec-partial(g, [], make-action, "_", input)
      (_, Just((rest, _))) -> input := rest
      _ -> ()

    while { !input.is-empty }
      match peg-exec-partial(g, [], make-action, "statement", input)
        (_, Just((rest, sv))) ->
          current-env := exec-safe(sv, current-env, exec-ext, break-msg)
          match peg-exec-partial(g, [], make-action, "_", rest)
            (_, Just((rest2, _))) -> input := rest2
            _ -> input := rest
        _ ->
          if !input.is-empty then println("Parse failed at: " ++ input.string.first(20).string ++ "...")
          input := "".slice
    println("")

pub fun main(): console ()
  ()
