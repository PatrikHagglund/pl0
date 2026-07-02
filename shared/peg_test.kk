// Tests for the PEG interpreter
module peg_test

import shared/peg

fun test(name: string, ok: bool): console ()
  println((if ok then "✓ " else "✗ ") ++ name)

pub fun main(): <console, div, exn> ()
  println("=== PEG Parser Tests ===\n")

  // Literal matching
  val g1 = parse-peg("r = \"hello\"")
  test("literal match", peg-parse(g1, "r", "hello").is-just)
  test("literal no match", peg-parse(g1, "r", "world").is-nothing)

  // Any character
  val g2 = parse-peg("r = .")
  test("any matches char", peg-parse(g2, "r", "x").is-just)
  test("any fails empty", peg-parse(g2, "r", "").is-nothing)

  // Character class
  val g3 = parse-peg("r = [a-z]")
  test("class matches", peg-parse(g3, "r", "m").is-just)
  test("class rejects", peg-parse(g3, "r", "5").is-nothing)

  // Negated class
  val g4 = parse-peg("r = [^0-9]")
  test("negated class matches", peg-parse(g4, "r", "x").is-just)
  test("negated class rejects", peg-parse(g4, "r", "5").is-nothing)

  // Sequence
  val g5 = parse-peg("r = \"a\" \"b\"")
  test("sequence matches", peg-parse(g5, "r", "ab").is-just)
  test("sequence partial fails", peg-parse(g5, "r", "a").is-nothing)

  // Choice
  val g6 = parse-peg("r = \"a\" / \"b\"")
  test("choice first", peg-parse(g6, "r", "a").is-just)
  test("choice second", peg-parse(g6, "r", "b").is-just)
  test("choice neither", peg-parse(g6, "r", "c").is-nothing)

  // Star (zero or more)
  val g7 = parse-peg("r = \"a\"*")
  test("star zero", peg-parse(g7, "r", "").is-just)
  test("star many", peg-parse(g7, "r", "aaa").is-just)

  // Plus (one or more)
  val g8 = parse-peg("r = \"a\"+")
  test("plus one", peg-parse(g8, "r", "a").is-just)
  test("plus many", peg-parse(g8, "r", "aaa").is-just)
  test("plus zero fails", peg-parse(g8, "r", "").is-nothing)

  // Optional
  val g9 = parse-peg("r = \"a\"?")
  test("optional present", peg-parse(g9, "r", "a").is-just)
  test("optional absent", peg-parse(g9, "r", "").is-just)

  // Not predicate
  val g10 = parse-peg("r = !\"x\" .")
  test("not predicate pass", peg-parse(g10, "r", "a").is-just)
  test("not predicate fail", peg-parse(g10, "r", "x").is-nothing)

  // And predicate
  val g11 = parse-peg("r = &\"a\" .")
  test("and predicate pass", peg-parse(g11, "r", "a").is-just)
  test("and predicate fail", peg-parse(g11, "r", "b").is-nothing)

  // Rule reference
  val g12 = parse-peg("r = a a\na = \"x\"")
  test("rule reference", peg-parse(g12, "r", "xx").is-just)

  // Comments in grammar
  val g13 = parse-peg("// comment\nr = \"x\"")
  test("grammar comment", peg-parse(g13, "r", "x").is-just)

  // Integer pattern
  val g14 = parse-peg("num = [0-9]+")
  test("integer", peg-parse(g14, "num", "123").is-just)

  // Identifier pattern
  val g15 = parse-peg("id = [a-zA-Z] [a-zA-Z0-9]*")
  test("identifier", peg-parse(g15, "id", "foo42").is-just)

  // Comment pattern (the tricky one)
  val g16 = parse-peg("comment = \"//\" (!\"\\n\" .)*")
  test("comment pattern", peg-parse(g16, "comment", "// hello world").is-just)

  // Whitespace with comments
  val g17 = parse-peg("ws = ([ \\t\\n] / \"//\" (!\"\\n\" .)*)*\nr = ws \"x\" ws")
  test("ws with comment", peg-parse(g17, "r", "// test\nx").is-just)

  // Named captures
  val g18 = parse-peg("r = a:[a-z]+ \"-\" b:[0-9]+")
  val res18 = peg-parse(g18, "r", "foo-123")
  test("named capture parses", res18.is-just)
  match res18
    Just(t) ->
      val a-nodes = ptree-find(t, "a")
      val b-nodes = ptree-find(t, "b")
      test("named capture 'a' found", a-nodes.length == 1)
      test("named capture 'b' found", b-nodes.length == 1)
      test("named capture 'a' text", a-nodes.head.map(ptree-text).maybe/default("") == "foo")
      test("named capture 'b' text", b-nodes.head.map(ptree-text).maybe/default("") == "123")
    Nothing -> ()

  // Inline action parsing
  val g19 = parse-peg("r = [a-z]+ { $0 }")
  test("inline action parses", peg-parse(g19, "r", "hello").is-just)

  println("\n=== Static Analysis Tests ===\n")

  // Common prefix detection
  val g20 = parse-peg("r = \"a\" \"b\" / \"a\" \"c\"")
  val w20 = warn-grammar(g20)
  test("common prefix detected", w20.any(fn(w) w.contains("overlapping")))

  val g21 = parse-peg("r = \"a\" / \"b\"")
  val w21 = warn-grammar(g21)
  test("no common prefix", !w21.any(fn(w) w.contains("overlapping")))

  // Recursive lookahead detection
  val g22 = parse-peg("r = &other \"x\"\nother = \"y\"")
  val w22 = warn-grammar(g22)
  test("recursive lookahead detected", w22.any(fn(w) w.contains("lookahead")))

  val g23 = parse-peg("r = &\"(\" \"x\"")
  val w23 = warn-grammar(g23)
  test("no recursive lookahead", !w23.any(fn(w) w.contains("lookahead")))

  // Right-recursion detection
  val g24 = parse-peg("sum = num \"+\" sum / num\nnum = [0-9]+")
  val w24 = warn-grammar(g24)
  test("right-recursion detected", w24.any(fn(w) w.contains("right-recursive")))

  val g25 = parse-peg("sum = num tail*\ntail = \"+\" num\nnum = [0-9]+")
  val w25 = warn-grammar(g25)
  test("no right-recursion", !w25.any(fn(w) w.contains("right-recursive")))

  // === Exec-path packrat memoization ===
  // A grammar whose two alternatives share the FIRST prefix `p`: matching the
  // first alternative parses `p` (which recurses through nested parens), then
  // the trailing "+" fails, forcing a backtrack that re-parses `p`. Without
  // memoization this re-parse is exponential in the nesting depth; with the
  // packrat memo each (rule, position) is computed once. peg-exec-stats only
  // counts a PRule on a memo *miss*, so the total call count is the direct
  // signal: linear-ish (memoized) vs. thousands (un-memoized).
  val gmemo = parse-peg("e = p \"+\" e / p\np = \"(\" e \")\" / \"z\"")
  val deep = "((((((((((((((z))))))))))))))"  // 14 nested parens, no "+"
  val (mres, mstats) = peg-exec-stats(gmemo, [], fn(_n, _t, _c, _caps) 0, "e", deep)
  val mcalls = mstats.foldl(0, fn(acc, p) acc + p.snd.calls)
  test("memoized parse succeeds", mres.is-just)
  // 2 rules over ~29 positions bounds the distinct (rule,pos) work well under
  // 200; the un-memoized path would record many thousands of calls here.
  test("memoization keeps rule calls linear", mcalls < 200)

  println("\n=== Done ===")
