// PL/0 Level 1 interpreter in Koka
// Two-phase: parse to AST, then evaluate with effect handlers

module e1

import std/text/parse
import std/os/file
import std/os/path
import std/os/env
import src/e1-types
import src/e1-parser
import src/e1-eval

// Strip // comments
fun strip-comments(s: string): string
  s.lines.map(fn(line)
    val idx = line.find("//")
    match idx
      Just(sl) -> sl.before.string
      Nothing -> line
  ).join("\n")

// Main
fun run(input: string, init-env: e1-types/env): <console, div> e1-types/env
  match parse(input.strip-comments.slice, pprogram)
    ParseOk(stmts, _) ->
      with ctl do-break(env) env
      exec-all(init-env, stmts)
    ParseError(msg, _) ->
      println("Parse error: " ++ msg)
      []

pub fun main()
  val args = get-args()
  val prog-path = match args
    Cons(p, _) -> p
    Nil -> 
      println("Usage: e1 <file> [arg1] [arg2]")
      return ()
  val arg1 = match args
    Cons(_, Cons(n, _)) -> n.parse-int.default(0)
    _ -> 0
  val arg2 = match args
    Cons(_, Cons(_, Cons(n, _))) -> n.parse-int.default(0)
    _ -> 0
  
  val prog = read-text-file(prog-path.path)
  val init-env = [("arg1", arg1), ("arg2", arg2)]
  run(prog, init-env)
  ()