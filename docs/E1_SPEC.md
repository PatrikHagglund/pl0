# e1 Language Specification

## Overview

e1 is a minimal Turing-complete language based on Minsky machine (counter machine) principles:
1. **Unbounded integer variables** (counters)
2. **Increment/decrement** (`+`, `-`)
3. **Conditional zero-test with control flow** (`loop`, `break_ifz`)

## Syntax

### Grammar (PEG)

```peg
program     = _ statement*
statement   = binding / loop_stmt / break_stmt / print_stmt / block

block       = "{" _ (statement ";"? _)* "}" _
loop_stmt   = "loop" _ statement
break_stmt  = "break_ifz" _ expression
print_stmt  = "print" _ expression

binding     = ident _ ":=" _ expression    // assignment
            / ident _ ":"                  // declaration

expression  = sum_expr
sum_expr    = unary (("+" / "-") _ unary)*
unary       = "-"? atom
atom        = int_lit / ident / "(" _ expression ")" _

int_lit     = digit+ _
ident       = !keyword letter idchar* _
keyword     = ("loop" / "break_ifz" / "print") !idchar
idchar      = [a-zA-Z0-9_]
letter      = [a-zA-Z]
digit       = [0-9]

_           = ([ \t\n\r] / comment)*
comment     = "//" [^\n]*
```

### Lexical Elements

- **Identifiers**: Start with letter, followed by alphanumerics/underscores
- **Integers**: Decimal digits (no sign in literal; use unary `-`)
- **Keywords**: `loop`, `break_ifz`, `print`
- **Operators**: `+`, `-`, `:=`, `:`
- **Delimiters**: `{`, `}`, `(`, `)`, `;` (optional)
- **Comments**: `//` to end of line

## Semantics

### Types

Single type: **integers**.

The range of representable integers (minimum and maximum values) is implementation-defined. Examples: unbounded, 0 to 2⁶⁴−1, −2⁶³ to 2⁶³−1, etc.

### Statements

**Declaration** (`x:`): Creates variable. Initial value is implementation-defined (possibly indeterminate).

**Assignment** (`x := expr`): Evaluates `expr`, assigns to `x`. Creates `x` if undeclared.

**Block** (`{ stmt; ... }`): Executes statements sequentially. Semicolons optional.

**Loop** (`loop stmt`): Repeats `stmt` until `break_ifz` breaks out.

**Break** (`break_ifz expr`): If `expr` evaluates to 0, exits innermost loop. Otherwise continues. Using outside any loop is an error.

**Print** (`print expr`): Outputs `expr` value followed by newline.

### Built-in Input Variables

Implementations may provide zero or more `arg<N>` variables (`arg1`, `arg2`, ...) before program execution: assigned from command-line arguments if present, else declared.

### Expressions

**Variables**: Evaluates to current value. Referencing an undeclared variable is an error.

**Literals**: Decimal integers (e.g., `42`, `0`)

**Negation** (`-expr`): Arithmetic negation

**Addition/Subtraction** (`a + b`, `a - b`): Associativity is implementation-defined.

**Parentheses**: Grouping for precedence

Behavior when a literal or arithmetic result exceeds the implementation's integer range is implementation-defined.

### Evaluation

- Expressions: left-to-right
- Statements: sequential within blocks
- Programs: top-to-bottom

Invalid syntax and memory exhaustion are errors.

### Error Handling

Error handling is either implementation-defined (reject at compile-time, terminate at runtime, use default behavior) or undefined.

## Examples

### Conditional (if-then pattern)

```pl0
// if (cond != 0) then action
loop {
  break_ifz cond
  action
  break_ifz 0  // unconditional break
}
```

### Boolean Inversion

```pl0
// is_zero = (n == 0) ? 1 : 0
is_zero := 1
loop {
  break_ifz n
  is_zero := 0
  break_ifz 0
}
```
