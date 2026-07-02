// PL/0 Level 5 interpreter using PEG grammar
// Adds arrays and pattern matching to e3

module e5peg

import shared/peg
import std/os/file
import std/os/path
import std/os/env

// Runtime values
pub type rval
  VInt(n: int)
  VBool(b: bool)
  VArray(v: vector<rval>)
  VRec(fields: list<(string, rval)>)
  VClosure(params: list<string>, body: expr, env: e5env)

pub alias e5env = list<(string, rval)>

// Patterns
pub type pattern
  PWild
  PVar(name: string)
  PLit(v: rval)
  PArray(elems: list<pattern>, rest: bool)  // rest=true means prefix match
  // Listed fields must exist and match; extra scrutinee fields are allowed
  PRec(fields: list<(string, pattern)>)

// Expressions
pub type expr
  EVal(v: rval)
  EVar(s: string)
  EBinop(op: string, l: expr, r: expr)
  ENot(e: expr)
  ENeg(e: expr)
  EApply(f: expr, a: expr)
  EIndex(arr: expr, idx: int)
  EField(rec: expr, fld: string)
  ECase(scrut: expr, arms: list<(pattern, expr)>)
  EFunc(params: list<string>, body: expr)
  EArray(elems: list<expr>)
  ERecord(fields: list<(string, expr)>)

// lvalue path selectors (component assignment): array index or record field
pub type lsel
  LIdx(i: int)
  LDyn(e: expr)
  LField(fld: string)

// Statements
pub type stmt
  SExpr(e: expr)
  SAssign(id: string, e: expr)
  SAssignPath(id: string, path: list<lsel>, e: expr)  // a.i / r.f := e (functional update)
  SDecl(id: string)
  SPrint(e: expr)
  SLoop(body: stmt)
  SBreak
  SBlock(stmts: list<stmt>)
  SCaseStmt(scrut: expr, arms: list<(pattern, stmt)>)

// Semantic values for PEG actions
pub type semval
  SVExpr(e: expr)
  SVStmt(s: stmt)
  SVIdent(s: string)
  SVPat(p: pattern)
  SVList(vs: list<semval>)
  SVExprArm(pat: pattern, body: expr)
  SVStmtArm(pat: pattern, body: stmt)
  SVBinopTail(op: string, rhs: expr)
  SVIndex(idx: int)
  SVLSel(sel: lsel)         // lvalue selector for path assignment
  SVFieldSel(fld: string)
  SVField(fld: string, e: expr)
  SVPatField(fld: string, p: pattern)
  SVArr(elems: list<expr>)  // array tail of a paren_expr (elements after the first)

fun env-get(e: e5env, key: string): rval
  match e.filter(fn(p) p.fst == key)
    Cons((_, v), _) -> v
    Nil -> VInt(0)

fun env-set(e: e5env, key: string, v: rval): e5env
  Cons((key, v), e.filter(fn(p) p.fst != key))

fun env-extend(e: e5env, bindings: list<(string, rval)>): e5env
  bindings.foldl(e, fn(acc, b) env-set(acc, b.fst, b.snd))

// Pattern matching - returns bindings on success
fun match-pattern(p: pattern, v: rval): div maybe<list<(string, rval)>>
  match (p, v)
    (PWild, _) -> Just([])
    (PVar(name), _) -> Just([(name, v)])
    (PLit(pv), _) -> if rval-eq(pv, v) then Just([]) else Nothing
    (PArray(elems, rest), VArray(arr)) ->
      val len = arr.length
      val plen = elems.length
      if rest then
        if len < plen then Nothing
        else match-array-elems(elems, arr, 0)
      else
        if len != plen then Nothing
        else match-array-elems(elems, arr, 0)
    (PRec(fps), VRec(fields)) -> match-rec-fields(fps, fields)
    _ -> Nothing

fun match-rec-fields(fps: list<(string, pattern)>, fields: list<(string, rval)>): div maybe<list<(string, rval)>>
  match fps
    Nil -> Just([])
    Cons((fld, p), rest) ->
      match fields.filter(fn(f) f.fst == fld)
        Cons((_, v), _) -> match match-pattern(p, v)
          Nothing -> Nothing
          Just(binds) -> match match-rec-fields(rest, fields)
            Nothing -> Nothing
            Just(more) -> Just(binds ++ more)
        Nil -> Nothing  // listed field missing: no match

fun match-array-elems(pats: list<pattern>, arr: vector<rval>, idx: int): div maybe<list<(string, rval)>>
  match pats
    Nil -> Just([])
    Cons(p, rest) ->
      match arr.at(idx)
        Nothing -> Nothing
        Just(v) -> match match-pattern(p, v)
          Nothing -> Nothing
          Just(binds) -> match match-array-elems(rest, arr, idx + 1)
            Nothing -> Nothing
            Just(more) -> Just(binds ++ more)

fun rval-eq(a: rval, b: rval): bool
  match (a, b)
    (VInt(x), VInt(y)) -> x == y
    (VBool(x), VBool(y)) -> x == y
    _ -> False

effect loop-break
  ctl do-break(e: e5env): a

// Ill-typed operations are runtime type errors, not silent defaults
// (decision 2026-06-11, found by efuzz; see docs/FUZZING.md findings).
// Exceptions kept as-is: case guards accept truthy ints (e2 idiom),
// array indexing out of bounds and EIndex on non-arrays still default to 0
// (separate open question, like unbound variables).
effect type-error
  ctl do-type-error(msg: string): a

// Erroneous constructs (E3_SPEC.md): incorrect but with a bounded
// consequence — a specified fallback value, or a diagnostic, per the
// handling mode (enforce / observe / fallback / unchecked) selected with
// --enforce, --erroneous=MODE, or --erroneous:KIND=MODE.
// Kinds: div0, unbound, nomatch, oob.
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
    VArray(_) -> "array"
    VRec(_) -> "record"
    VClosure(_, _, _) -> "closure"

fun eval(ex: expr, e: e5env): <div,type-error,violation> rval
  match ex
    EVal(v) -> v
    EVar(s) -> match e.filter(fn(p) p.fst == s)
      Cons((_, v), _) -> v
      Nil -> violate("unbound", "undeclared variable '" ++ s ++ "'", VInt(0))
    EArray(elems) -> VArray(elems.map(fn(el) eval(el, e)).vector)
    ERecord(fields) -> VRec(fields.map(fn(f) (f.fst, eval(f.snd, e))))
    EField(rec, fld) ->
      match eval(rec, e)
        VRec(fields) -> match fields.filter(fn(f) f.fst == fld)
          Cons((_, v), _) -> v
          Nil -> do-type-error("no field '" ++ fld ++ "' in record")
        v -> do-type-error("field access on " ++ kind(v))
    EIndex(arr, idx) ->
      match eval(arr, e)
        VArray(v) -> match v.at(idx)
          Just(x) -> x
          Nothing -> violate("oob", "index " ++ idx.show ++ " out of bounds (length " ++ v.length.show ++ ")", VInt(0))
        v -> do-type-error("indexing " ++ kind(v))
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
    EApply(f, a) ->
      val fv = eval(f, e)
      val av = eval(a, e)
      match (fv, av)
        (VArray(arr), VInt(idx)) -> match arr.at(idx)
          Just(x) -> x
          Nothing -> violate("oob", "index " ++ idx.show ++ " out of bounds (length " ++ arr.length.show ++ ")", VInt(0))
        (VClosure(params, body, cenv), _) ->
          match params
            Cons(p, rest) ->
              val newenv = env-set(cenv, p, av)
              if rest.is-nil then eval(body, newenv)
              else VClosure(rest, body, newenv)
            Nil -> eval(body, cenv)
        _ -> do-type-error("applying " ++ kind(fv) ++ " to " ++ kind(av))
    ECase(scrut, arms) ->
      val sv = eval(scrut, e)
      eval-case-arms(sv, arms, e)
    EFunc(params, body) -> VClosure(params, body, e)

fun eval-case-arms(scrut: rval, arms: list<(pattern, expr)>, e: e5env): <div,type-error,violation> rval
  match arms
    Nil -> violate("nomatch", "no case arm matched", VInt(0))
    Cons((pat, body), rest) ->
      match match-pattern(pat, scrut)
        Just(binds) -> eval(body, env-extend(e, binds))
        Nothing -> eval-case-arms(scrut, rest, e)

// Functional update along an lvalue path: rebuild the array/record(s) with the
// addressed component replaced. Pure value semantics — no aliasing. OOB array
// assignment is erroneous (kind oob, leaves it unchanged); a missing field or a
// component of the wrong shape is a type error.
fun set-at(arr: vector<rval>, idx: int, v: rval): vector<rval>
  arr.list.map-indexed(fn(i, x) if i == idx then v else x).vector

fun rec-set(fields: list<(string, rval)>, fld: string, v: rval): list<(string, rval)>
  fields.map(fn(p) if p.fst == fld then (fld, v) else p)

fun update-path(v: rval, sels: list<lsel>, newv: rval, e: e5env): <div,type-error,violation> rval
  match sels
    Nil -> newv
    Cons(LField(fld), rest) -> match v
      VRec(fields) -> match fields.filter(fn(p) p.fst == fld)
        Cons((_, cur), _) -> VRec(rec-set(fields, fld, update-path(cur, rest, newv, e)))
        Nil -> do-type-error("no field '" ++ fld ++ "' in record assignment")
      other -> do-type-error("field assignment on " ++ kind(other))
    Cons(sel, rest) ->  // LIdx or LDyn
      val idx = match sel
        LIdx(i) -> i
        LDyn(ix) -> match eval(ix, e)
          VInt(n) -> n
          other -> do-type-error("array index is " ++ kind(other))
        LField(_) -> 0  // unreachable: handled above
      match v
        VArray(arr) -> match arr.at(idx)
          Just(cur) -> VArray(set-at(arr, idx, update-path(cur, rest, newv, e)))
          Nothing -> violate("oob", "assignment index " ++ idx.show ++ " out of bounds (length " ++ arr.length.show ++ ")", v)
        other -> do-type-error("indexing " ++ kind(other) ++ " in assignment")

fun exec(s: stmt, e: e5env): <div,console,loop-break,type-error,violation> e5env
  match s
    SExpr(_) -> e
    SAssign(id, ex) -> env-set(e, id, eval(ex, e))
    SAssignPath(id, path, ex) ->
      match e.filter(fn(p) p.fst == id)
        Nil ->
          val _ = violate("unbound", "assigning to component of undeclared '" ++ id ++ "'", VInt(0))
          e  // unbound base: no-op (in fallback/observe mode)
        Cons((_, cur), _) ->
          val newv = eval(ex, e)  // RHS evaluated before the path indices
          env-set(e, id, update-path(cur, path, newv, e))
    SDecl(id) -> env-set(e, id, VInt(0))
    SPrint(ex) ->
      println(show-rval(eval(ex, e)))
      e
    SLoop(body) ->
      with ctl do-break(e1) e1
      fun go(env: e5env): <div,console,loop-break,type-error,violation> e5env
        go(exec(body, env))
      go(e)
    SBreak -> do-break(e)
    SBlock(stmts) -> stmts.foldl(e, fn(acc, st) exec(st, acc))
    SCaseStmt(scrut, arms) ->
      val sv = eval(scrut, e)
      exec-case-arms(sv, arms, e)

fun exec-case-arms(scrut: rval, arms: list<(pattern, stmt)>, e: e5env): <div,console,loop-break,type-error,violation> e5env
  match arms
    Nil -> e
    Cons((pat, body), rest) ->
      match match-pattern(pat, scrut)
        Just(binds) -> exec(body, env-extend(e, binds))
        Nothing -> exec-case-arms(scrut, rest, e)

fun show-rval(v: rval): div string
  match v
    VInt(n) -> n.show
    VBool(b) -> if b then "true" else "false"
    VArray(arr) ->
      if arr.length == 0 then "()"
      else "(" ++ arr.list.map(show-rval).join("; ") ++ ";)"
    VRec(fields) ->
      "{" ++ fields.map(fn(f) f.fst ++ ": " ++ show-rval(f.snd)).join(", ") ++ "}"
    VClosure(_, _, _) -> "<closure>"

// Semantic action helpers
fun flatten-sv(vs: list<semval>): list<semval>
  vs.flatmap(fn(c) match c { SVList(inner) -> inner; _ -> [c] })

fun get-params(vs: list<semval>): list<string>
  flatten-sv(vs).filter-map(fn(v) match v { SVIdent(s) -> Just(s); _ -> Nothing })

fun sv-to-stmt(v: semval): maybe<stmt>
  match v
    SVStmt(s) -> Just(s)
    SVExpr(ex) -> Just(SExpr(ex))
    _ -> Nothing

fun sv-to-expr(v: semval): maybe<expr>
  match v { SVExpr(e) -> Just(e); _ -> Nothing }

fun sv-to-pat(v: semval): maybe<pattern>
  match v { SVPat(p) -> Just(p); _ -> Nothing }

fun sv-to-lsel(v: semval): maybe<lsel>
  match v { SVLSel(s) -> Just(s); _ -> Nothing }

fun fold-binop-tails(base: expr, tails: list<semval>): expr
  tails.foldl(base) fn(acc, tail)
    match tail
      SVBinopTail(op, rhs) -> EBinop(op, acc, rhs)
      _ -> acc

fun ident-str(v: semval): string
  match v
    SVIdent(s) -> s.list.take-while(fn(c) c.is-alpha || c.is-digit || c == '_').string
    _ -> ""

fun e5-action(name: string, txt: string, children: list<semval>, caps: captures<semval>): semval
  val cs = flatten-sv(children)
  if name == "_text" then SVIdent(txt)
  // Binary expression rules
  elif name == "or_expr" || name == "and_expr" || name == "sum_expr" || name == "product" then
    match cs
      Cons(SVExpr(base), rest) -> SVExpr(fold-binop-tails(base, rest))
      _ -> SVList(cs)
  elif name == "cmp_expr" then
    match cs
      Cons(SVExpr(base), Cons(SVBinopTail(op, rhs), _)) -> SVExpr(EBinop(op, base, rhs))
      Cons(SVExpr(base), _) -> SVExpr(base)
      _ -> SVList(cs)
  elif name == "or_tail" then
    match cs { Cons(SVExpr(rhs), _) -> SVBinopTail("||", rhs); _ -> SVList(cs) }
  elif name == "and_tail" then
    match cs { Cons(SVExpr(rhs), _) -> SVBinopTail("&&", rhs); _ -> SVList(cs) }
  elif name == "sum_tail" then
    match cs
      Cons(SVExpr(rhs), _) -> SVBinopTail(if txt.starts-with("+").bool then "+" else "-", rhs)
      _ -> SVList(cs)
  elif name == "product_tail" then
    val op = if txt.starts-with("*").bool then "*" elif txt.starts-with("/").bool then "/" else "%"
    match cs { Cons(SVExpr(rhs), _) -> SVBinopTail(op, rhs); _ -> SVList(cs) }
  elif name == "cmp_tail" then
    val op = if txt.starts-with("==").bool then "=="
             elif txt.starts-with("!=").bool then "!="
             elif txt.starts-with("<=").bool then "<="
             elif txt.starts-with(">=").bool then ">="
             elif txt.starts-with("<").bool then "<"
             else ">"
    match cs { Cons(SVExpr(rhs), _) -> SVBinopTail(op, rhs); _ -> SVList(cs) }
  // Apply expression with indexing
  elif name == "apply_expr" then
    cs.foldl(SVList([]): semval) fn(acc, c)
      match (acc, c)
        (SVList([]), SVExpr(e)) -> SVExpr(e)
        (SVExpr(base), SVIndex(idx)) -> SVExpr(EIndex(base, idx))
        (SVExpr(base), SVFieldSel(fld)) -> SVExpr(EField(base, fld))
        (SVExpr(base), SVExpr(arg)) -> SVExpr(EApply(base, arg))
        _ -> acc
  elif name == "array_items" then
    SVList(cs)
  elif name == "array_pat_items" then
    SVList(cs)
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
    "LIdx" -> match cs
      Cons(SVExpr(EVal(VInt(i))), _) -> SVLSel(LIdx(i))
      _ -> SVList(cs)
    "LDyn" -> match cs
      Cons(SVExpr(ix), _) -> SVLSel(LDyn(ix))
      _ -> SVList(cs)
    "LField" -> SVLSel(LField(cs.head.default(SVIdent("")).ident-str))
    "AssignPath" -> match cs  // [SVIdent base, SVLSel.., SVExpr rhs]
      Cons(SVIdent(base), rest) -> match rest.reverse
        Cons(SVExpr(rhs), sels-rev) -> SVStmt(SAssignPath(base, sels-rev.reverse.filter-map(sv-to-lsel), rhs))
        _ -> SVList(cs)
      _ -> SVList(cs)
    "Not" -> match cs { Cons(SVExpr(e), _) -> SVExpr(ENot(e)); _ -> SVExpr(EVal(VBool(False))) }
    "Neg" -> match cs { Cons(SVExpr(e), _) -> SVExpr(ENeg(e)); _ -> SVExpr(EVal(VInt(0))) }
    "Decl" -> match cs { Cons(SVIdent(id), _) -> SVStmt(SDecl(id)); _ -> SVList(cs) }
    "Print" -> match cs { Cons(SVExpr(e), _) -> SVStmt(SPrint(e)); _ -> SVList(cs) }
    "Loop" -> match cs { Cons(SVStmt(s), _) -> SVStmt(SLoop(s)); _ -> SVList(cs) }
    "Break" -> SVStmt(SBreak)
    "Block" -> SVStmt(SBlock(flatten-sv(cs).filter-map(sv-to-stmt)))
    "Params" -> SVList(cs)
    "Func" ->
      val params = get-params(cs.init)
      match cs.last { Just(SVExpr(body)) -> SVExpr(EFunc(params, body)); _ -> SVList(cs) }
    "Unit" -> SVExpr(EVal(VArray([].vector)))
    "ArrTail" -> SVArr(flatten-sv(cs).filter-map(sv-to-expr))
    "Paren" -> match cs
      Cons(SVExpr(e), Cons(SVArr(rest), _)) -> SVExpr(EArray(Cons(e, rest)))
      Cons(SVExpr(e), _) -> SVExpr(e)
      _ -> SVList(cs)
    "DotIndex" -> match cs
      Cons(SVExpr(EVal(VInt(idx))), _) -> SVIndex(idx)
      _ -> SVList(cs)
    "DotField" -> SVFieldSel(cs.head.default(SVIdent("")).ident-str)
    "Apply" -> match cs { Cons(SVExpr(e), _) -> SVExpr(e); _ -> SVList(cs) }
    "FieldInit" -> match cs
      Cons(SVIdent(fld), Cons(SVExpr(e), _)) -> SVField(fld, e)
      _ -> SVList(cs)
    "Record" ->
      val fields = flatten-sv(cs).filter-map fn(v)
        match v { SVField(fld, e) -> Just((fld, e)); _ -> Nothing }
      SVExpr(ERecord(fields))
    // Patterns
    "PWild" -> SVPat(PWild)
    "PVar" -> SVPat(PVar(cs.head.default(SVIdent("")).ident-str))
    "PLit" -> match cs
      Cons(SVExpr(EVal(v)), _) -> SVPat(PLit(v))
      _ -> SVPat(PWild)
    "PLitTrue" -> SVPat(PLit(VBool(True)))
    "PLitFalse" -> SVPat(PLit(VBool(False)))
    "PUnit" -> SVPat(PArray([], False))
    "PField" -> match cs
      Cons(SVIdent(fld), Cons(SVPat(p), _)) -> SVPatField(fld, p)
      _ -> SVList(cs)
    "PRecord" ->
      val fps = flatten-sv(cs).filter-map fn(v)
        match v { SVPatField(fld, p) -> Just((fld, p)); _ -> Nothing }
      SVPat(PRec(fps))
    "PArray" ->
      val pats = flatten-sv(cs).filter-map(sv-to-pat)
      // Check if last pattern is wildcard -> rest match
      val (elems, rest) = match pats.reverse
        Cons(PWild, rrest) -> (rrest.reverse, True)
        _ -> (pats, False)
      SVPat(PArray(elems, rest))
    // Case arms
    "ExprArm" -> match cs
      Cons(SVPat(pat), Cons(SVExpr(body), _)) -> SVExprArm(pat, body)
      _ -> SVList(cs)
    "StmtArm" -> match cs
      Cons(SVPat(pat), Cons(SVStmt(body), _)) -> SVStmtArm(pat, body)
      _ -> SVList(cs)
    "CaseExpr" ->
      // First child is scrutinee, rest are arms
      val (scrut, arm-children) = match cs
        Cons(SVExpr(e), rest) -> (e, rest)
        _ -> (EVal(VBool(True)), cs)
      val arms = flatten-sv(arm-children).filter-map fn(v)
        match v { SVExprArm(p, b) -> Just((p, b)); _ -> Nothing }
      SVExpr(ECase(scrut, arms))
    "CaseStmt" ->
      // First child is scrutinee, rest are arms
      val (scrut, arm-children) = match cs
        Cons(SVExpr(e), rest) -> (e, rest)
        _ -> (EVal(VBool(True)), cs)
      val arms = flatten-sv(arm-children).filter-map fn(v)
        match v { SVStmtArm(p, b) -> Just((p, b)); _ -> Nothing }
      SVStmt(SCaseStmt(scrut, arms))
    _ -> SVList(cs)
  else match cs
    Cons(c, Nil) -> c
    _ -> SVList(cs)

// Returns Nothing on a type error or enforced violation: the program halts.
fun exec-safe(sv: semval, e: e5env, modes: err-modes): <div,console> maybe<e5env>
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

  val prog-path = match rest-args { Cons(p, _) -> p; Nil -> "e5/example.e5" }
  val arg1-val = match rest-args { Cons(_, Cons(n, _)) -> n.parse-int.default(0); _ -> 0 }
  val arg2-val = match rest-args { Cons(_, Cons(_, Cons(n, _))) -> n.parse-int.default(0); _ -> 0 }

  println("loading grammar...")
  val g = parse-peg(read-text-file("e5/e5.peg".path))
  if do-dump then
    println("loaded " ++ g.length.show ++ " rules")
    println(show-grammar(g))
    return ()
  if do-warn then
    val warnings = warn-grammar(g)
    if warnings.is-empty then println("No warnings")
    else warnings.foreach(fn(w) println("Warning: " ++ w))
  val prog = read-text-file(prog-path.path)
  println("e5: " ++ prog-path ++ " (" ++ prog.count.int/show ++ " chars)")

  if do-stats then
    val (result, stats) = peg-exec-stats(g, [], e5-action, "program", prog)
    match result
      Just(_) -> ()
      Nothing -> println("Parse failed")
    println(show-stats(stats))
  else
    var input := prog.slice
    var current-env: e5env := [("arg1", VInt(arg1-val)), ("arg2", VInt(arg2-val))]

    match peg-exec-partial(g, [], e5-action, "_", input)
      (_, Just((rest, _))) -> input := rest
      _ -> ()

    while { !input.is-empty }
      match peg-exec-partial(g, [], e5-action, "statement", input)
        (_, Just((rest, sv))) ->
          match exec-safe(sv, current-env, err-flags)
            Just(e2) ->
              current-env := e2
              match peg-exec-partial(g, [], e5-action, "_", rest)
                (_, Just((rest2, _))) -> input := rest2
                _ -> input := rest
            Nothing ->  // type error: halt
              input := "".slice
        _ ->
          if !input.is-empty then println("Parse failed at: " ++ input.string.first(20).string ++ "...")
          input := "".slice
    println("")
