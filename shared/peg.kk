// Minimal PEG interpreter in Koka
// Reads a .peg grammar file and interprets input against it

module peg

import std/text/parse
import std/os/file
import std/os/path

// === PEG AST ===
pub type peg
  PSeq(ps: list<peg>)
  PChoice(ps: list<peg>)
  PStar(p: peg)
  PPlus(p: peg)
  POpt(p: peg)
  PNot(p: peg)
  PAnd(p: peg)
  PLit(s: string)
  PClass(ranges: list<(char,char)>, negated: bool)
  PRule(name: string)
  PCapture(name: string, p: peg)  // Named capture: name:pattern
  PAction(p: peg, act: iexpr)     // Inline action: pattern { expr }
  PAny

// Inline action expression AST
pub type iexpr
  IVar(name: string)      // $name or $0
  IStr(s: string)         // "literal"
  IInt(n: int)            // 123
  ICall(fname: string, args: list<iexpr>)  // fn(args)
  IField(e: iexpr, fname: string)  // e.field
  ICons(tag: string, args: list<iexpr>)  // Tag(args)

// Rule with optional action tag or inline action
pub alias rule = (string, peg, maybe<string>)
pub alias grammar = list<rule>

// === Parse Result Tree ===
pub type ptree
  PNode(rule: string, children: list<ptree>, text: string)
  PLeaf(text: string)

// === PEG File Parser ===
fun peg-ws(): parse ()
  many { one-of(" \t") }
  ()

fun peg-ws-nl(): parse ()
  many { one-of(" \t\n\r") }
  ()

fun peg-comment(): parse ()
  pstring("//")
  many { none-of("\n") }
  ()

fun peg-skip(): parse ()
  many { choose([{ one-of(" \t\n\r"); () }, { peg-comment() }]) }
  ()

fun peg-ident(): parse string
  val c = choose([alpha, { char('_') }])
  val cs = many { choose([alpha-num, { char('_') }]) }
  (Cons(c, cs)).string


fun peg-char-esc(): parse char
  char('\\')
  val c = none-of("")
  match c
    'n' -> '\n'
    'r' -> '\r'
    't' -> '\t'
    _ -> c

fun peg-char-lit(): parse char
  choose([peg-char-esc, { none-of("") }])

fun peg-string-lit(): parse peg
  char('"')
  val cs = many { choose([peg-char-esc, { none-of("\"\\") }]) }
  char('"')
  PLit(cs.string)

fun peg-class(): parse peg
  char('[')
  val neg = optional(False) { char('^'); True }
  val ranges = many {
    val c1 = choose([peg-char-esc, { none-of("]") }])
    optional((c1, c1)) {
      char('-')
      val c2 = choose([peg-char-esc, { none-of("]") }])
      (c1, c2)
    }
  }
  char(']')
  PClass(ranges, neg)

fun peg-atom(): <parse,div> peg
  peg-ws()
  choose([
    peg-string-lit,
    peg-class,
    { char('.'); PAny },
    { char('('); peg-skip(); val p = peg-choice(); peg-skip(); char(')'); p },
    { PRule(peg-ident()) }
  ])

fun peg-suffix(): <parse,div> peg
  val p = peg-atom()
  peg-ws()
  optional(p) {
    val op = one-of("*+?")
    match op
      '*' -> PStar(p)
      '+' -> PPlus(p)
      '?' -> POpt(p)
      _ -> p
  }

fun peg-prefix(): <parse,div> peg
  peg-ws()
  choose([
    { char('!'); PNot(peg-prefix()) },
    { char('&'); PAnd(peg-prefix()) },
    {
      // Try named capture: name:pattern
      val id = peg-ident()
      peg-ws()
      char(':')
      peg-ws()
      val p = peg-suffix()
      PCapture(id, p)
    },
    peg-suffix
  ])

fun peg-seq(): <parse,div> peg
  val ps = many1(peg-prefix)
  match ps
    Cons(p, Nil) -> p
    _ -> PSeq(ps)

// === Inline Action Expression Parser ===
// Parses expressions like: $0, $name, int($n), Cons($a, $b), "str"

fun iexpr-var(): parse iexpr
  char('$')
  val name = choose([
    { peg-ident() },
    { many1(fn() one-of("0123456789")).string }
  ])
  IVar(name)

fun iexpr-string(): parse iexpr
  char('"')
  val cs = many { choose([peg-char-esc, { none-of("\"\\") }]) }
  char('"')
  IStr(cs.string)

fun iexpr-int(): parse iexpr
  val ds = many1(fn() one-of("0123456789"))
  IInt(ds.string.parse-int.default(0))

fun iexpr-atom(): <parse,div> iexpr
  peg-ws()
  choose([
    iexpr-var,
    iexpr-string,
    iexpr-int,
    {
      // Constructor or function call: Name(args) or Name
      val name = peg-ident()
      peg-ws()
      optional(ICons(name, [])) {
        char('(')
        peg-ws()
        val args = optional([]) {
          val first = iexpr-expr()
          val rest = many { peg-ws(); char(','); peg-ws(); iexpr-expr() }
          Cons(first, rest)
        }
        peg-ws()
        char(')')
        if name.list.list/maybe/head.maybe/default('a').is-upper then ICons(name, args)
        else ICall(name, args)
      }
    }
  ])

fun iexpr-expr(): <parse,div> iexpr
  val e = iexpr-atom()
  // Optional field access: e.field
  peg-ws()
  optional(e) {
    char('.')
    val f = peg-ident()
    IField(e, f)
  }

fun peg-inline-action(): <parse,div> maybe<iexpr>
  optional(Nothing) {
    peg-ws()
    char('{')
    peg-ws()
    val e = iexpr-expr()
    peg-ws()
    char('}')
    Just(e)
  }

// Sequence with optional inline action
fun peg-seq-with-action(): <parse,div> peg
  val ps = many1(peg-prefix)
  val p = match ps
    Cons(p1, Nil) -> p1
    _ -> PSeq(ps)
  match peg-inline-action()
    Just(act) -> PAction(p, act)
    Nothing -> p

fun peg-choice(): <parse,div> peg
  val first = peg-seq-with-action()
  val rest = many {
    peg-ws(); peg-skip(); char('/'); peg-skip()
    peg-seq-with-action()
  }
  match rest
    Nil -> first
    _ -> PChoice(Cons(first, rest))

fun peg-action-tag(): parse maybe<string>
  optional(Nothing) {
    peg-ws()
    char('@')
    Just(peg-ident())
  }

fun peg-rule(): <parse,div> rule
  peg-skip()
  val name = peg-ident()
  peg-ws()
  char('=')
  peg-skip()
  val body = peg-choice()
  val tag = peg-action-tag()
  (name, body, tag)

pub fun parse-peg(input: string): <div,exn> grammar
  match parse(input.slice, { many(peg-rule) })
    ParseOk(g, _) -> validate-grammar(g)
    ParseError(msg, _) -> throw("PEG parse error: " ++ msg)

// Validate grammar and check for common issues
fun validate-grammar(g: grammar): <div,exn> grammar
  val rule-names = g.map(fn(r) r.fst)
  val refs = g.flatmap(fn(r) collect-refs(r.snd))
  val undefined = refs.filter(fn(r) !rule-names.any(fn(n) n == r))
  if !undefined.is-empty then
    throw("Undefined rules: " ++ undefined.join(", "))
  // Check for left recursion
  val left-rec = g.filter-map(fn(r) if is-left-recursive(g, r.fst, r.snd) then Just(r.fst) else Nothing)
  if !left-rec.is-empty then
    throw("Left-recursive rules (will cause infinite loop): " ++ left-rec.join(", "))
  // Check for nullable loops (e* or e+ where e can match empty)
  val nulls = compute-nullable(g)
  val nullable-loops = g.flatmap(fn(r) find-nullable-loops(nulls, r.fst, r.snd))
  if !nullable-loops.is-empty then
    throw("Nullable loops (e*/e+ where e can match empty): " ++ nullable-loops.join(", "))
  g

// Nullable set: rules that can match empty string
pub alias nullable-set = list<string>

// Compute nullable set using fixed-point iteration
fun compute-nullable(g: grammar): div nullable-set
  fun iterate(nulls: nullable-set): div nullable-set
    val new-nulls = g.filter-map fn(r)
      if nulls.any(fn(n) n == r.fst) then Nothing  // Already known nullable
      elif is-nullable-with(nulls, r.snd) then Just(r.fst)
      else Nothing
    if new-nulls.is-empty then nulls
    else iterate(nulls ++ new-nulls)
  iterate([])

// Check if pattern is nullable given current nullable set (no recursion into rules)
fun is-nullable-with(nulls: nullable-set, p: peg): div bool
  match p
    PLit(s) -> s == ""
    PAny -> False
    PClass(_, _) -> False
    PSeq(ps) -> ps.all(fn(p1) is-nullable-with(nulls, p1))
    PChoice(ps) -> ps.any(fn(p1) is-nullable-with(nulls, p1))
    PStar(_) -> True
    PPlus(p1) -> is-nullable-with(nulls, p1)
    POpt(_) -> True
    PNot(_) -> True
    PAnd(_) -> True
    PRule(n) -> nulls.any(fn(x) x == n)
    PCapture(_, p1) -> is-nullable-with(nulls, p1)
    PAction(p1, _) -> is-nullable-with(nulls, p1)

// Find nullable loops in a pattern using pre-computed nullable set
fun find-nullable-loops(nulls: nullable-set, rule-name: string, p: peg): div list<string>
  match p
    PStar(p1) ->
      val inner = find-nullable-loops(nulls, rule-name, p1)
      if is-nullable-with(nulls, p1) then Cons(rule-name ++ ": e* where e is nullable", inner) else inner
    PPlus(p1) ->
      val inner = find-nullable-loops(nulls, rule-name, p1)
      if is-nullable-with(nulls, p1) then Cons(rule-name ++ ": e+ where e is nullable", inner) else inner
    PSeq(ps) -> ps.flatmap(fn(p1) find-nullable-loops(nulls, rule-name, p1))
    PChoice(ps) -> ps.flatmap(fn(p1) find-nullable-loops(nulls, rule-name, p1))
    POpt(p1) -> find-nullable-loops(nulls, rule-name, p1)
    PNot(p1) -> find-nullable-loops(nulls, rule-name, p1)
    PAnd(p1) -> find-nullable-loops(nulls, rule-name, p1)
    PCapture(_, p1) -> find-nullable-loops(nulls, rule-name, p1)
    PAction(p1, _) -> find-nullable-loops(nulls, rule-name, p1)
    _ -> []

// Check if a rule is directly left-recursive (rule appears as first element)
fun is-left-recursive(g: grammar, name: string, p: peg): div bool
  match p
    PRule(n) -> n == name || (match grammar-lookup-maybe(g, n) { Just((body, _)) -> is-left-recursive(g, name, body); Nothing -> False })
    PSeq(Cons(first, _)) -> is-left-recursive(g, name, first)
    PChoice(ps) -> ps.any(fn(p1) is-left-recursive(g, name, p1))
    PCapture(_, p1) -> is-left-recursive(g, name, p1)
    PAction(p1, _) -> is-left-recursive(g, name, p1)
    POpt(p1) -> is-left-recursive(g, name, p1)  // Optional can be skipped, check what follows
    _ -> False

fun grammar-lookup-maybe(g: grammar, name: string): maybe<(peg, maybe<string>)>
  match g.filter(fn(r) r.fst == name)
    Cons((_, body, tag), _) -> Just((body, tag))
    Nil -> Nothing

pub fun show-grammar(g: grammar): div string
  g.map(fn(r) r.fst ++ " = " ++ show-peg(r.snd)).join("\n")

fun show-peg(p: peg): div string
  match p
    PLit(s) -> "\"" ++ s ++ "\""
    PAny -> "."
    PClass(_) -> "[...]"
    PRule(n) -> n
    PSeq(ps) -> "(" ++ ps.map(show-peg).join(" ") ++ ")"
    PChoice(ps) -> "(" ++ ps.map(show-peg).join(" / ") ++ ")"
    PStar(p1) -> show-peg(p1) ++ "*"
    PPlus(p1) -> show-peg(p1) ++ "+"
    POpt(p1) -> show-peg(p1) ++ "?"
    PNot(p1) -> "!" ++ show-peg(p1)
    PAnd(p1) -> "&" ++ show-peg(p1)
    PCapture(n, p1) -> n ++ ":" ++ show-peg(p1)
    PAction(p1, _) -> show-peg(p1) ++ " {action}"

fun collect-refs(p: peg): div list<string>
  match p
    PRule(name) -> [name]
    PSeq(ps) -> ps.flatmap(collect-refs)
    PChoice(ps) -> ps.flatmap(collect-refs)
    PStar(p1) -> collect-refs(p1)
    PPlus(p1) -> collect-refs(p1)
    POpt(p1) -> collect-refs(p1)
    PNot(p1) -> collect-refs(p1)
    PAnd(p1) -> collect-refs(p1)
    PCapture(_, p1) -> collect-refs(p1)
    PAction(p1, _) -> collect-refs(p1)
    _ -> []

// === Static Analysis (Warnings) ===

// FIRST set element: what a pattern can start with
pub type first-elem
  FLit(s: string)
  FClass(ranges: list<(char,char)>, negated: bool)
  FAny

pub alias first-set = list<first-elem>
pub alias first-sets = list<(string, first-set)>

// Check if two FIRST elements can overlap
fun first-overlap(a: first-elem, b: first-elem): div bool
  match a
    FAny -> True
    FLit(s1) -> match b
      FAny -> True
      FLit(s2) -> s1 != "" && s2 != "" && s1.list.head == s2.list.head
      FClass(ranges, neg) -> match s1.list.head { Just(c) -> in-class(c, ranges, neg); Nothing -> False }
    FClass(ranges, neg) -> match b
      FAny -> True
      FLit(s) -> match s.list.head { Just(c) -> in-class(c, ranges, neg); Nothing -> False }
      FClass(_, _) -> True  // Conservative: assume character classes can overlap

fun first-sets-overlap(a: first-set, b: first-set): div bool
  a.any(fn(x) b.any(fn(y) first-overlap(x, y)))

// Compute FIRST set for a pattern
fun compute-first(nulls: nullable-set, firsts: first-sets, p: peg): div first-set
  match p
    PLit(s) -> if s == "" then [] else [FLit(s)]
    PAny -> [FAny]
    PClass(ranges, neg) -> [FClass(ranges, neg)]
    PRule(n) -> firsts.filter(fn(x) x.fst == n).head.map(snd).default([])
    PSeq(Nil) -> []
    PSeq(Cons(first, rest)) ->
      val f = compute-first(nulls, firsts, first)
      if is-nullable-with(nulls, first) then f ++ compute-first(nulls, firsts, PSeq(rest)) else f
    PChoice(ps) -> ps.flatmap(fn(p1) compute-first(nulls, firsts, p1))
    PStar(p1) -> compute-first(nulls, firsts, p1)
    PPlus(p1) -> compute-first(nulls, firsts, p1)
    POpt(p1) -> compute-first(nulls, firsts, p1)
    PNot(_) -> []
    PAnd(p1) -> compute-first(nulls, firsts, p1)
    PCapture(_, p1) -> compute-first(nulls, firsts, p1)
    PAction(p1, _) -> compute-first(nulls, firsts, p1)

// Compute FIRST sets for all rules using fixed-point iteration
fun compute-first-sets(g: grammar, nulls: nullable-set): div first-sets
  fun iterate(firsts: first-sets): div first-sets
    val new-firsts = g.map fn(r)
      (r.fst, compute-first(nulls, firsts, r.snd))
    if new-firsts.all(fn(nf) firsts.any(fn(of) of.fst == nf.fst && of.snd.length == nf.snd.length))
    then firsts else iterate(new-firsts)
  iterate(g.map(fn(r) (r.fst, [])))

// Check if pattern contains rule references
fun has-rule-ref(p: peg): div bool
  match p
    PRule(_) -> True
    PSeq(ps) -> ps.any(has-rule-ref)
    PChoice(ps) -> ps.any(has-rule-ref)
    PStar(p1) -> has-rule-ref(p1)
    PPlus(p1) -> has-rule-ref(p1)
    POpt(p1) -> has-rule-ref(p1)
    PNot(p1) -> has-rule-ref(p1)
    PAnd(p1) -> has-rule-ref(p1)
    PCapture(_, p1) -> has-rule-ref(p1)
    PAction(p1, _) -> has-rule-ref(p1)
    _ -> False

// Find recursive lookahead patterns
fun find-recursive-lookahead(rule-name: string, p: peg): div list<string>
  match p
    PAnd(p1) ->
      if has-rule-ref(p1) then [rule-name ++ ": lookahead contains rule reference"]
      else find-recursive-lookahead(rule-name, p1)
    PNot(p1) ->
      if has-rule-ref(p1) then [rule-name ++ ": negative lookahead contains rule reference"]
      else find-recursive-lookahead(rule-name, p1)
    PSeq(ps) -> ps.flatmap(fn(p1) find-recursive-lookahead(rule-name, p1))
    PChoice(ps) -> ps.flatmap(fn(p1) find-recursive-lookahead(rule-name, p1))
    PStar(p1) -> find-recursive-lookahead(rule-name, p1)
    PPlus(p1) -> find-recursive-lookahead(rule-name, p1)
    POpt(p1) -> find-recursive-lookahead(rule-name, p1)
    PCapture(_, p1) -> find-recursive-lookahead(rule-name, p1)
    PAction(p1, _) -> find-recursive-lookahead(rule-name, p1)
    _ -> []

// Find common prefixes in choice alternatives
fun find-common-prefixes(nulls: nullable-set, firsts: first-sets, rule-name: string, p: peg): div list<string>
  match p
    PChoice(ps) ->
      val alt-firsts = ps.map(fn(p1) compute-first(nulls, firsts, p1))
      val overlaps = check-pairwise-overlap(alt-firsts, 0)
      val inner = ps.flatmap(fn(p1) find-common-prefixes(nulls, firsts, rule-name, p1))
      if overlaps then Cons(rule-name ++ ": alternatives have overlapping FIRST sets", inner) else inner
    PSeq(ps) -> ps.flatmap(fn(p1) find-common-prefixes(nulls, firsts, rule-name, p1))
    PStar(p1) -> find-common-prefixes(nulls, firsts, rule-name, p1)
    PPlus(p1) -> find-common-prefixes(nulls, firsts, rule-name, p1)
    POpt(p1) -> find-common-prefixes(nulls, firsts, rule-name, p1)
    PNot(p1) -> find-common-prefixes(nulls, firsts, rule-name, p1)
    PAnd(p1) -> find-common-prefixes(nulls, firsts, rule-name, p1)
    PCapture(_, p1) -> find-common-prefixes(nulls, firsts, rule-name, p1)
    PAction(p1, _) -> find-common-prefixes(nulls, firsts, rule-name, p1)
    _ -> []

fun check-pairwise-overlap(sets: list<first-set>, idx: int): div bool
  match sets
    Nil -> False
    Cons(_, Nil) -> False
    Cons(a, rest) -> rest.any(fn(b) first-sets-overlap(a, b)) || check-pairwise-overlap(rest, idx + 1)

// Find right-recursive rules that could be left-factored
fun find-right-recursion(rule-name: string, p: peg): div list<string>
  match p
    PChoice(ps) ->
      val inner = ps.flatmap(fn(p1) find-right-recursion(rule-name, p1))
      // Check if any alternative ends with self-recursion while another is a prefix
      val has-self-rec = ps.any(fn(p1) ends-with-rule(p1, rule-name))
      val has-prefix = ps.any(fn(p1) !ends-with-rule(p1, rule-name))
      if has-self-rec && has-prefix
      then Cons(rule-name ++ ": right-recursive, consider left-factoring", inner)
      else inner
    PSeq(ps) -> ps.flatmap(fn(p1) find-right-recursion(rule-name, p1))
    PStar(p1) -> find-right-recursion(rule-name, p1)
    PPlus(p1) -> find-right-recursion(rule-name, p1)
    POpt(p1) -> find-right-recursion(rule-name, p1)
    PCapture(_, p1) -> find-right-recursion(rule-name, p1)
    PAction(p1, _) -> find-right-recursion(rule-name, p1)
    _ -> []

fun ends-with-rule(p: peg, name: string): div bool
  match p
    PRule(n) -> n == name
    PSeq(ps) -> match ps.reverse { Cons(last, _) -> ends-with-rule(last, name); Nil -> False }
    PCapture(_, p1) -> ends-with-rule(p1, name)
    PAction(p1, _) -> ends-with-rule(p1, name)
    _ -> False

// Public API: collect all warnings for a grammar
pub fun warn-grammar(g: grammar): div list<string>
  val nulls = compute-nullable(g)
  val firsts = compute-first-sets(g, nulls)
  val prefix-warns = g.flatmap(fn(r) find-common-prefixes(nulls, firsts, r.fst, r.snd))
  val lookahead-warns = g.flatmap(fn(r) find-recursive-lookahead(r.fst, r.snd))
  val rightrec-warns = g.flatmap(fn(r) find-right-recursion(r.fst, r.snd))
  prefix-warns ++ lookahead-warns ++ rightrec-warns

// === PEG Interpreter ===
alias pstate = sslice

effect peg-fail
  ctl fail(): a

// Fuel effect for preventing infinite loops
effect peg-fuel
  fun burn(): bool  // Consume one unit of fuel, returns false if exhausted
  fun enter-rule(name: string): int  // Returns current fuel for delta calculation
  fun exit-rule(name: string, success: bool, fuel-start: int): ()

pub val default-fuel = 50000000  // Default fuel limit (50M)

// === Runtime Statistics ===
pub struct rule-stats
  calls: int
  fuel: int
  backtracks: int

pub alias parse-stats = list<(string, rule-stats)>

pub fun show-stats(stats: parse-stats): div string
  val sorted = stats.filter(fn(s) s.snd.calls > 0)
  if sorted.is-nil then "No rule calls recorded.\n"
  else
    val header = "Rule                     Calls       Fuel  Backtracks  Success%\n"
    val lines = sorted.map fn((name, st))
      val success-pct = if st.calls == 0 then 100 else ((st.calls - st.backtracks) * 100) / st.calls
      name.pad-right(20) ++ st.calls.show.pad-left(10) ++ st.fuel.show.pad-left(11) ++ 
        st.backtracks.show.pad-left(12) ++ (success-pct.show ++ "%").pad-left(10)
    header ++ lines.join("\n") ++ "\n"

fun stats-update(stats: parse-stats, name: string, fuel-delta: int, backtrack: bool): parse-stats
  match stats
    Nil -> [(name, Rule-stats(1, fuel-delta, if backtrack then 1 else 0))]
    Cons((n, st), rest) | n == name ->
      Cons((n, Rule-stats(st.calls + 1, st.fuel + fuel-delta, st.backtracks + (if backtrack then 1 else 0))), rest)
    Cons(x, rest) -> Cons(x, stats-update(rest, name, fuel-delta, backtrack))

// === Memoization for Packrat Parsing ===
// Key: (rule_name, position), Value: parse result or failure
pub alias memo-key = (string, int)
pub alias memo-result = maybe<(pstate, ptree)>
pub alias memo-table = list<(memo-key, memo-result)>

// Memoization for semantic actions (polymorphic value type)
pub alias exec-memo-result<s> = maybe<(pstate, s)>
pub alias exec-memo-table<s> = list<(memo-key, exec-memo-result<s>)>

// Packrat memo for the action-executing path, as a *mutable* effect rather
// than a threaded value. The table lives in the with-memo handler, which is
// installed outside (above) all the peg-fail handlers, so both positive and
// negative entries written before a fail() survive the backtrack unwind —
// the property the old threaded memo could not provide. memo-get returns
// Nothing on a miss, Just(entry) on a hit (entry is itself maybe: a cached
// success or a cached failure).
pub effect peg-memo<s>
  fun memo-get(key: memo-key): maybe<exec-memo-result<s>>
  fun memo-put(key: memo-key, v: exec-memo-result<s>): ()

fun memo-lookup(tbl: memo-table, key: memo-key): maybe<memo-result>
  match tbl.filter(fn(e) e.fst == key)
    Cons((_, v), _) -> Just(v)
    Nil -> Nothing

fun memo-store(tbl: memo-table, key: memo-key, v: memo-result): memo-table
  Cons((key, v), tbl)

// Position in the input (character offset from start)
fun sslice-pos(s: sslice, original: sslice): int
  original.count - s.count

fun grammar-lookup(g: grammar, name: string): (peg, maybe<string>)
  match g.filter(fn(r) r.fst == name)
    Cons((_, p, tag), _) -> (p, tag)
    Nil -> (PLit(""), Nothing)  // undefined rule = empty match

fun in-class(c: char, ranges: list<(char,char)>, neg: bool): bool
  val found = ranges.any(fn((lo, hi)) c >= lo && c <= hi)
  if neg then !found else found

fun peg-try(g: grammar, p: peg, s: pstate): <div> maybe<(pstate, ptree)>
  with ctl fail() Nothing
  Just(peg-match(g, p, s))

// Memoized version - takes and returns memo table for pure functional memoization
fun peg-try-memo(g: grammar, p: peg, s: pstate, memo: memo-table, orig: pstate): <div> (memo-table, maybe<(pstate, ptree)>)
  with ctl fail() (memo, Nothing)
  val (memo2, result) = peg-match-memo(g, p, s, memo, orig)
  (memo2, Just(result))

fun peg-match(g: grammar, p: peg, s: pstate): <peg-fail, div> (pstate, ptree)
  match p
    PLit(lit) ->
      if s.string.sslice/starts-with(lit).bool then
        (s.advance(lit.count), PLeaf(lit))
      else fail()
    
    PAny ->
      match s.next
        Just((c, rest)) -> (rest, PLeaf(c.string))
        Nothing -> fail()
    
    PClass(ranges, neg) ->
      match s.next
        Just((c, rest)) | in-class(c, ranges, neg) -> (rest, PLeaf(c.string))
        _ -> fail()
    
    PSeq(ps) ->
      var cur := s
      var children := []
      ps.foreach fn(p1)
        val (s1, t1) = peg-match(g, p1, cur)
        cur := s1
        children := Cons(t1, children)
      (cur, PNode("seq", children.reverse, s.string.first(s.count - cur.count).string))
    
    PChoice(ps) ->
      peg-choice-match(g, ps, s)
    
    PStar(p1) ->
      var cur := s
      var children := []
      var done := False
      while { !done } fn()
        match peg-try(g, p1, cur)
          Just((s1, t1)) ->
            if s1.count == cur.count then done := True
            else { cur := s1; children := Cons(t1, children) }
          Nothing -> done := True
      (cur, PNode("star", children.reverse, s.string.first(s.count - cur.count).string))
    
    PPlus(p1) ->
      val (s1, t1) = peg-match(g, p1, s)
      val (s2, t2) = peg-match(g, PStar(p1), s1)
      val ts = match t2
        PNode(_, cs, _) -> cs
        _ -> []
      (s2, PNode("plus", Cons(t1, ts), s.string.first(s.count - s2.count).string))
    
    POpt(p1) ->
      match peg-try(g, p1, s)
        Just(r) -> r
        Nothing -> (s, PNode("opt", [], ""))
    
    PNot(p1) ->
      match peg-try(g, p1, s)
        Just(_) -> fail()
        Nothing -> (s, PLeaf(""))
    
    PAnd(p1) ->
      val _ = peg-match(g, p1, s)
      (s, PLeaf(""))
    
    PRule(name) ->
      val (body, _) = grammar-lookup(g, name)
      val (s1, t1) = peg-match(g, body, s)
      (s1, PNode(name, match t1 { PNode(_, cs, _) -> cs; _ -> [t1] }, s.string.first(s.count - s1.count).string))

    PCapture(name, p1) ->
      val (s1, t1) = peg-match(g, p1, s)
      (s1, PNode(name, [t1], s.string.first(s.count - s1.count).string))

    PAction(p1, _) ->
      // For tree-building, just match the pattern (action is for semantic execution)
      peg-match(g, p1, s)

fun peg-choice-match(g: grammar, ps: list<peg>, s: pstate): <peg-fail, div> (pstate, ptree)
  match ps
    Nil -> fail()
    Cons(p, rest) ->
      match peg-try(g, p, s)
        Just(r) -> r
        Nothing -> peg-choice-match(g, rest, s)

// === Memoized PEG Matcher ===
// Only memoizes at rule boundaries (PRule) for packrat-style parsing
// Returns (updated_memo_table, parse_result)
fun peg-match-memo(g: grammar, p: peg, s: pstate, memo: memo-table, orig: pstate): <peg-fail, div> (memo-table, (pstate, ptree))
  match p
    PLit(lit) ->
      if s.string.sslice/starts-with(lit).bool then
        (memo, (s.advance(lit.count), PLeaf(lit)))
      else fail()

    PAny ->
      match s.next
        Just((c, rest)) -> (memo, (rest, PLeaf(c.string)))
        Nothing -> fail()

    PClass(ranges, neg) ->
      match s.next
        Just((c, rest)) | in-class(c, ranges, neg) -> (memo, (rest, PLeaf(c.string)))
        _ -> fail()

    PSeq(ps) ->
      var cur := s
      var children := []
      var m := memo
      ps.foreach fn(p1)
        val (m1, (s1, t1)) = peg-match-memo(g, p1, cur, m, orig)
        m := m1
        cur := s1
        children := Cons(t1, children)
      (m, (cur, PNode("seq", children.reverse, s.string.first(s.count - cur.count).string)))

    PChoice(ps) ->
      peg-choice-match-memo(g, ps, s, memo, orig)

    PStar(p1) ->
      var cur := s
      var children := []
      var m := memo
      var done := False
      while { !done } fn()
        val (m2, res) = peg-try-memo(g, p1, cur, m, orig)
        match res
          Just((s1, t1)) ->
            if s1.count == cur.count then done := True // no progress, stop
            else
              cur := s1
              children := Cons(t1, children)
              m := m2
          Nothing -> done := True
      (m, (cur, PNode("star", children.reverse, s.string.first(s.count - cur.count).string)))

    PPlus(p1) ->
      val (m1, (s1, t1)) = peg-match-memo(g, p1, s, memo, orig)
      val (m2, (s2, t2)) = peg-match-memo(g, PStar(p1), s1, m1, orig)
      val ts = match t2
        PNode(_, cs, _) -> cs
        _ -> []
      (m2, (s2, PNode("plus", Cons(t1, ts), s.string.first(s.count - s2.count).string)))

    POpt(p1) ->
      val (m1, res) = peg-try-memo(g, p1, s, memo, orig)
      match res
        Just(r) -> (m1, r)
        Nothing -> (m1, (s, PNode("opt", [], "")))

    PNot(p1) ->
      val (m1, res) = peg-try-memo(g, p1, s, memo, orig)
      match res
        Just(_) -> fail()
        Nothing -> (m1, (s, PLeaf("")))

    PAnd(p1) ->
      val (m1, _) = peg-match-memo(g, p1, s, memo, orig)
      (m1, (s, PLeaf("")))

    PRule(name) ->
      // Check memo table first
      val pos = sslice-pos(s, orig)
      val key = (name, pos)
      match memo-lookup(memo, key)
        Just(Just(result)) -> (memo, result)  // Cache hit: success
        Just(Nothing) -> fail()               // Cache hit: failure
        Nothing ->
          // Cache miss: parse and store result
          val (body, _) = grammar-lookup(g, name)
          val (m1, result) = peg-try-memo(g, body, s, memo, orig)
          val m2 = memo-store(m1, key, result)
          match result
            Just((s1, t1)) ->
              (m2, (s1, PNode(name, match t1 { PNode(_, cs, _) -> cs; _ -> [t1] }, s.string.first(s.count - s1.count).string)))
            Nothing -> fail()

    PCapture(name, p1) ->
      val (m1, (s1, t1)) = peg-match-memo(g, p1, s, memo, orig)
      (m1, (s1, PNode(name, [t1], s.string.first(s.count - s1.count).string)))

    PAction(p1, _) ->
      peg-match-memo(g, p1, s, memo, orig)

fun peg-choice-match-memo(g: grammar, ps: list<peg>, s: pstate, memo: memo-table, orig: pstate): <peg-fail, div> (memo-table, (pstate, ptree))
  match ps
    Nil -> fail()
    Cons(p, rest) ->
      val (m1, res) = peg-try-memo(g, p, s, memo, orig)
      match res
        Just(r) -> (m1, r)
        Nothing -> peg-choice-match-memo(g, rest, s, m1, orig)

pub fun peg-parse(g: grammar, start: string, input: string): <div> maybe<ptree>
  match peg-try(g, PRule(start), input.slice)
    Just((_, tree)) -> Just(tree)
    Nothing -> Nothing

pub fun peg-parse-partial(g: grammar, start: string, input: sslice): <div> maybe<(sslice, ptree)>
  peg-try(g, PRule(start), input)

// === Memoized Public API ===
// Creates a memo table for packrat parsing, enabling efficient backtracking

pub fun peg-parse-memo(g: grammar, start: string, input: string): <div> maybe<ptree>
  val inp = input.slice
  val (_, result) = peg-try-memo(g, PRule(start), inp, [], inp)
  match result
    Just((_, tree)) -> Just(tree)
    Nothing -> Nothing

// Memoized partial parse with persistent memo table
// Returns (updated_memo_table, parse_result) for chaining
pub fun peg-parse-partial-memo(g: grammar, start: string, input: sslice, memo: memo-table, orig: sslice): <div> (memo-table, maybe<(sslice, ptree)>)
  peg-try-memo(g, PRule(start), input, memo, orig)

// Create a new empty memo table
pub fun memo-new(): memo-table
  []

// === Utilities ===
pub fun ptree-text(t: ptree): string
  match t
    PNode(_, _, txt) -> txt
    PLeaf(txt) -> txt

pub fun ptree-children(t: ptree): list<ptree>
  match t
    PNode(_, cs, _) -> cs
    PLeaf(_) -> []

pub fun ptree-find(t: ptree, name: string): div list<ptree>
  match t
    PNode(n, cs, _) ->
      val here = if n == name then [t] else []
      here ++ cs.flatmap(fn(c) ptree-find(c, name))
    PLeaf(_) -> []

pub fun ptree-show(t: ptree, indent: int = 0): <console, div> ()
  val pad = replicate(" ", indent).join
  match t
    PNode(name, cs, txt) ->
      println(pad ++ name ++ ": \"" ++ txt.slice.sslice/take(30).string ++ "\"")
      cs.foreach(fn(c) ptree-show(c, indent + 2))
    PLeaf(txt) ->
      if txt.count > 0 then println(pad ++ "leaf: \"" ++ txt ++ "\"")


// === Semantic Actions API ===
// Execute grammar with callbacks instead of building parse trees

// Semantic value: polymorphic, defined by the user
// Action: called when a rule matches, receives (rule_name, matched_text, child_values, named_captures) -> value
// Named captures: list of (name, value) pairs from n:pattern syntax
pub alias captures<s> = list<(string, s)>
pub alias action<s> = (string, string, list<s>, captures<s>) -> s

// Action table: maps rule names to actions
pub alias actions<s> = list<(string, action<s>)>

// Helper to lookup a capture by name
pub fun capture-get(caps: captures<s>, name: string): maybe<s>
  match caps.filter(fn(p) p.fst == name)
    Cons((_, v), _) -> Just(v)
    Nil -> Nothing

fun action-lookup(acts: actions<s>, name: string, default-action: action<s>): action<s>
  match acts.filter(fn(a) a.fst == name)
    Cons((_, act), _) -> act
    Nil -> default-action

// Internal: value with optional capture name
type captured<s>
  Captured(cname: maybe<string>, cval: s)

fun captured-val(c: captured<s>): s
  c.cval

fun to-captures(cs: list<captured<s>>): captures<s>
  cs.filter-map fn(c)
    match c
      Captured(Just(n), v) -> Just((n, v))
      _ -> Nothing

fun to-values(cs: list<captured<s>>): list<s>
  cs.map(captured-val)

// Execute PEG with semantic actions
// Returns (remaining_input, semantic_value) or fails
// `orig` is the slice the current parse started from; (rule, pos-in-orig)
// keys the packrat memo. Memoization happens at rule boundaries (PRule).
fun peg-exec-match(g: grammar, acts: actions<s>, def: action<s>, p: peg, s: pstate, orig: pstate): <peg-fail,peg-fuel,peg-memo<s>,div> (pstate, captured<s>)
  if !burn() then fail()
  match p
    PLit(lit) ->
      if s.string.sslice/starts-with(lit).bool then
        (s.advance(lit.count), Captured(Nothing, def("_lit", lit, [], [])))
      else fail()

    PAny ->
      match s.next
        Just((c, rest)) -> (rest, Captured(Nothing, def("_any", c.string, [], [])))
        Nothing -> fail()

    PClass(ranges, neg) ->
      match s.next
        Just((c, rest)) | in-class(c, ranges, neg) -> (rest, Captured(Nothing, def("_class", c.string, [], [])))
        _ -> fail()

    PSeq(ps) ->
      var cur := s
      var vals := []
      ps.foreach fn(p1)
        val (s1, v1) = peg-exec-match(g, acts, def, p1, cur, orig)
        cur := s1
        vals := Cons(v1, vals)
      val children = vals.reverse
      // Single child: pass through without wrapping
      match children
        Cons(v, Nil) -> (cur, v)
        _ ->
          val caps = to-captures(children)
          val vs = to-values(children)
          (cur, Captured(Nothing, def("_seq", s.string.first(s.count - cur.count).string, vs, caps)))

    PChoice(ps) ->
      peg-exec-choice(g, acts, def, ps, s, orig)

    PStar(p1) ->
      var cur := s
      var vals := []
      var done := False
      while { !done } fn()
        match peg-exec-try(g, acts, def, p1, cur, orig)
          Just((s1, v1)) ->
            if s1.count == cur.count then done := True
            else { cur := s1; vals := Cons(v1, vals) }
          Nothing -> done := True
      val children = vals.reverse
      (cur, Captured(Nothing, def("_star", s.string.first(s.count - cur.count).string, to-values(children), to-captures(children))))

    PPlus(p1) ->
      val (s1, v1) = peg-exec-match(g, acts, def, p1, s, orig)
      var cur := s1
      var vals := [v1]
      var done := False
      while { !done } fn()
        match peg-exec-try(g, acts, def, p1, cur, orig)
          Just((s2, v2)) ->
            if s2.count == cur.count then done := True
            else { cur := s2; vals := Cons(v2, vals) }
          Nothing -> done := True
      val children = vals.reverse
      (cur, Captured(Nothing, def("_plus", s.string.first(s.count - cur.count).string, to-values(children), to-captures(children))))

    POpt(p1) ->
      match peg-exec-try(g, acts, def, p1, s, orig)
        Just((s1, v1)) -> (s1, Captured(Nothing, def("_opt", s.string.first(s.count - s1.count).string, [v1.cval], [])))
        Nothing -> (s, Captured(Nothing, def("_opt", "", [], [])))

    PNot(p1) ->
      match peg-exec-try(g, acts, def, p1, s, orig)
        Just(_) -> fail()
        Nothing -> (s, Captured(Nothing, def("_not", "", [], [])))

    PAnd(p1) ->
      val _ = peg-exec-match(g, acts, def, p1, s, orig)
      (s, Captured(Nothing, def("_and", "", [], [])))

    PRule(name) ->
      val key = (name, sslice-pos(s, orig))
      match memo-get(key)
        Just(Just((s1, v))) -> (s1, Captured(Nothing, v))  // cached success
        Just(Nothing) -> fail()                            // cached failure
        Nothing ->
          val (body, tag) = grammar-lookup(g, name)
          val fuel-start = enter-rule(name)
          val result = peg-exec-try(g, acts, def, body, s, orig)
          match result
            Nothing ->
              exit-rule(name, False, fuel-start)
              memo-put(key, Nothing)
              fail()
            Just((s1, v1)) ->
              exit-rule(name, True, fuel-start)
              val txt = s.string.first(s.count - s1.count).string
              val action-name = tag.default(name)
              val act = action-lookup(acts, action-name, def)
              val caps = match v1 { Captured(_, _) -> [] }
              val rv = act(action-name, txt, [v1.cval], caps)
              memo-put(key, Just((s1, rv)))
              (s1, Captured(Nothing, rv))

    PCapture(cname, p1) ->
      val (s1, v1) = peg-exec-match(g, acts, def, p1, s, orig)
      // Mark this value with the capture name
      (s1, Captured(Just(cname), v1.cval))

    PAction(p1, iact) ->
      // For inline actions, we need to collect captures from the pattern
      // Match the pattern and collect all captured values
      val (s1, caps, result) = peg-exec-match-with-caps(g, acts, def, p1, s, orig)
      val n = s.count - s1.count
      val txt = s.string.first(n).string
      // Evaluate inline action with captures and text
      // For bare constructors like { Block }, pass result as single child
      val evaled = match iact
        ICons(tag, Nil) -> def("_cons", tag, [result], [])
        _ -> eval-iexpr(iact, txt, caps, def)
      (s1, Captured(Nothing, evaled))

// Match and collect captures (for inline actions)
fun peg-exec-match-with-caps(g: grammar, acts: actions<s>, def: action<s>, p: peg, s: pstate, orig: pstate): <peg-fail,peg-fuel,peg-memo<s>,div> (pstate, captures<s>, s)
  if !burn() then fail()
  match p
    PSeq(ps) ->
      var cur := s
      var vals := []
      ps.foreach fn(p1)
        val (s1, v1) = peg-exec-match(g, acts, def, p1, cur, orig)
        cur := s1
        vals := Cons(v1, vals)
      val children = vals.reverse
      // Single child: pass through without wrapping
      match children
        Cons(v, Nil) -> (cur, to-captures(children), v.cval)
        _ ->
          val caps = to-captures(children)
          val vs = to-values(children)
          (cur, caps, def("_seq", s.string.first(s.count - cur.count).string, vs, caps))
    PStar(p1) ->
      var cur := s
      var vals := [Captured(Nothing, def("_nil", "", [], []))]
      var done := False
      while { !done } fn()
        match peg-exec-try(g, acts, def, p1, cur, orig)
          Just((s1, v1)) ->
            if s1.count == cur.count then done := True // no progress, stop
            else { cur := s1; vals := Cons(v1, vals) }
          Nothing -> done := True
      val children = vals.reverse.drop(1)
      val vs = to-values(children)
      (cur, [], def("_list", "", vs, []))
    _ ->
      val (s1, v1) = peg-exec-match(g, acts, def, p, s, orig)
      val caps = match v1.cname { Just(n) -> [(n, v1.cval)]; Nothing -> [] }
      (s1, caps, v1.cval)

// === Inline Action Evaluator ===
// Evaluates iexpr with access to $0 (text), $name (captures), and built-ins

fun eval-iexpr(e: iexpr, txt: string, caps: captures<s>, def: action<s>): <div> s
  match e
    IVar(name) ->
      if name == "0" then def("_text", txt, [], [])
      else match capture-get(caps, name)
        Just(v) -> v
        Nothing -> def("_undefined", name, [], [])
    IStr(s) -> def("_str", s, [], [])
    IInt(n) -> def("_int", n.show, [], [])
    ICall(fname, args) ->
      val evaled = args.map(fn(a) eval-iexpr(a, txt, caps, def))
      def(fname, txt, evaled, [])
    ICons(tag, args) ->
      val evaled = args.map(fn(a) eval-iexpr(a, txt, caps, def))
      def("_cons", tag, evaled, [])
    IField(expr, f) ->
      val v = eval-iexpr(expr, txt, caps, def)
      def("_field", f, [v], [])

fun peg-exec-try(g: grammar, acts: actions<s>, def: action<s>, p: peg, s: pstate, orig: pstate): <peg-fuel,peg-memo<s>,div> maybe<(pstate, captured<s>)>
  with ctl fail() Nothing
  Just(peg-exec-match(g, acts, def, p, s, orig))

fun peg-exec-choice(g: grammar, acts: actions<s>, def: action<s>, ps: list<peg>, s: pstate, orig: pstate): <peg-fail,peg-fuel,peg-memo<s>,div> (pstate, captured<s>)
  match ps
    Nil -> fail()
    Cons(p, rest) ->
      match peg-exec-try(g, acts, def, p, s, orig)
        Just(r) -> r
        Nothing -> peg-exec-choice(g, acts, def, rest, s, orig)

fun with-fuel(max-fuel: int, action: () -> <peg-fuel|e> a): e a
  var fuel := max-fuel
  with handler
    fun burn()
      if fuel <= 0 then False
      else { fuel := fuel - 1; True }
    fun enter-rule(_name) fuel
    fun exit-rule(_name, _success, _fuel-start) ()
  action()

fun with-fuel-stats(max-fuel: int, action: () -> <peg-fuel|e> a): e (a, parse-stats)
  var fuel := max-fuel
  var stats : parse-stats := []
  with handler
    fun burn()
      if fuel <= 0 then False
      else { fuel := fuel - 1; True }
    fun enter-rule(_name) fuel
    fun exit-rule(name, success, fuel-start)
      stats := stats-update(stats, name, fuel-start - fuel, !success)
  (action(), stats)

// Packrat memo handler: a mutable (rule,pos) -> result table scoped to a
// single parse. Installed above the per-attempt fail handlers, so entries
// written before a backtrack survive it. A fresh table per parse keeps
// positions (keyed against `orig`) consistent.
fun with-memo(action: () -> <peg-memo<s>|e> a): e a
  var tbl := exec-memo-new()
  with handler
    fun memo-get(key) exec-memo-lookup(tbl, key)
    fun memo-put(key, v) tbl := exec-memo-store(tbl, key, v)
  action()

// Public API for semantic action execution
pub fun peg-exec(g: grammar, acts: actions<s>, def: action<s>, start: string, input: string, max-fuel: int = default-fuel): <div> maybe<s>
  val inp = input.slice
  with-fuel(max-fuel) fn()
    with-memo fn()
      match peg-exec-try(g, acts, def, PRule(start), inp, inp)
        Just((_, v)) -> Just(v.cval)
        Nothing -> Nothing

pub fun peg-exec-stats(g: grammar, acts: actions<s>, def: action<s>, start: string, input: string, max-fuel: int = default-fuel): <div> (maybe<s>, parse-stats)
  val inp = input.slice
  with-fuel-stats(max-fuel) fn()
    with-memo fn()
      match peg-exec-try(g, acts, def, PRule(start), inp, inp)
        Just((_, v)) -> Just(v.cval)
        Nothing -> Nothing

// Partial parse with packrat memoization (always on). The leading
// maybe<exec-memo-table> in the result is retained for call-site
// compatibility and is always Nothing — the memo lives in the with-memo
// handler now, not threaded out.
pub fun peg-exec-partial(g: grammar, acts: actions<s>, def: action<s>, start: string, input: sslice, max-fuel: int = default-fuel, orig: sslice = input): <div> (maybe<exec-memo-table<s>>, maybe<(sslice, s)>)
  with-fuel(max-fuel) fn()
    with-memo fn()
      match peg-exec-try(g, acts, def, PRule(start), input, orig)
        Just((rest, v)) -> (Nothing, Just((rest, v.cval)))
        Nothing -> (Nothing, Nothing)

// === Packrat Memo Table (backing store for the peg-memo handler) ===

fun exec-memo-new(): exec-memo-table<s>
  []

fun exec-memo-lookup(tbl: exec-memo-table<s>, key: memo-key): maybe<exec-memo-result<s>>
  match tbl.filter(fn(e) e.fst == key)
    Cons((_, v), _) -> Just(v)
    Nil -> Nothing

fun exec-memo-store(tbl: exec-memo-table<s>, key: memo-key, v: exec-memo-result<s>): exec-memo-table<s>
  Cons((key, v), tbl)

// Dummy main for standalone compilation
pub fun main(): console ()
  "PEG module loaded".println
