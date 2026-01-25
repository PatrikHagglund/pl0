// PL/0 Level 1 — Shared lexer, AST, and parser (C++23)
#pragma once

#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <string_view>
#include <vector>
#include <memory>
#include <expected>
#include <print>
#include <format>

// ---------- Language Implementation Configuration ----------

// Integer bit width: 0 = bigint (dynamic), >0 = _BitInt(N) fixed-width
// LLVM backend: bigint requires linking with e1_rt_bigint.bc (see Makefile).
#ifndef INT_BITS
constexpr int INT_BITS = 0;
#endif

// Number of built-in arg<N> variables (arg1, arg2, ..., argN)
constexpr int ARG_COUNT = 2;

// Integer type selection
#include "e1_bigint.hpp"

template<int Bits> struct IntType;
template<> struct IntType<0> { using type = bigint::Int; };  // bigint via header-only lib
template<int Bits> requires (Bits > 0) struct IntType<Bits> { using type = _BitInt(Bits); };

using Int = typename IntType<INT_BITS>::type;

// ---------- Tokens ----------

enum class Tok { NUM, ID, ASSIGN, COLON, PLUS, MINUS, LPAREN, RPAREN, LBRACE, RBRACE, LOOP, BREAK_IFZ, PRINT, SEMI, END };

struct Token { Tok type; std::string val; };

// ---------- Lexer ----------

struct Lexer {
    std::string_view src;
    size_t pos = 0;

    char peek() const { return pos < src.size() ? src[pos] : '\0'; }
    char get() { return pos < src.size() ? src[pos++] : '\0'; }

    void skip_ws() {
        while (true) {
            while (isspace(peek())) get();
            if (peek() == '/' && pos + 1 < src.size() && src[pos+1] == '/') {
                while (peek() != '\n' && peek() != '\0') get();
            } else break;
        }
    }

    std::expected<Token, std::string> next() {
        skip_ws();
        char c = peek();
        if (c == '\0') return Token{Tok::END, ""};
        if (isdigit(c)) {
            size_t start = pos;
            while (isdigit(peek())) get();
            return Token{Tok::NUM, std::string(src.substr(start, pos - start))};
        }
        if (isalpha(c) || c == '_') {
            size_t start = pos;
            while (isalnum(peek()) || peek() == '_') get();
            auto id = std::string(src.substr(start, pos - start));
            if (id == "loop") return Token{Tok::LOOP, id};
            if (id == "break_ifz") return Token{Tok::BREAK_IFZ, id};
            if (id == "print") return Token{Tok::PRINT, id};
            return Token{Tok::ID, id};
        }
        get();
        switch (c) {
            case ':': if (peek() == '=') { get(); return Token{Tok::ASSIGN, ":="}; }
                      return Token{Tok::COLON, ":"};
            case '+': return Token{Tok::PLUS, "+"};
            case '-': return Token{Tok::MINUS, "-"};
            case '(': return Token{Tok::LPAREN, "("};
            case ')': return Token{Tok::RPAREN, ")"};
            case '{': return Token{Tok::LBRACE, "{"};
            case '}': return Token{Tok::RBRACE, "}"};
            case ';': return Token{Tok::SEMI, ";"};
        }
        return std::unexpected(std::format("Unknown char: {}", c));
    }
};

inline auto tokenize(std::string_view src) {
    Lexer l{src};
    std::vector<Token> toks;
    while (true) {
        auto t = l.next();
        if (!t) return std::expected<std::vector<Token>, std::string>(std::unexpected(t.error()));
        toks.push_back(*t);
        if (t->type == Tok::END) break;
    }
    return std::expected<std::vector<Token>, std::string>(std::move(toks));
}

// ---------- AST ----------

struct Expr { virtual ~Expr() = default; };
struct Stmt { virtual ~Stmt() = default; };

using ExprPtr = std::unique_ptr<Expr>;
using StmtPtr = std::unique_ptr<Stmt>;

struct NumberExpr : Expr { int val; NumberExpr(int v) : val(v) {} };
struct VarExpr : Expr { std::string name; VarExpr(std::string n) : name(std::move(n)) {} };
struct NegExpr : Expr { ExprPtr e; NegExpr(ExprPtr x) : e(std::move(x)) {} };
struct BinExpr : Expr {
    char op; ExprPtr l, r;
    BinExpr(char o, ExprPtr a, ExprPtr b) : op(o), l(std::move(a)), r(std::move(b)) {}
};

struct DeclStmt : Stmt { std::string name; DeclStmt(std::string n) : name(std::move(n)) {} };
struct AssignStmt : Stmt { std::string name; ExprPtr e; AssignStmt(std::string n, ExprPtr x) : name(std::move(n)), e(std::move(x)) {} };
struct BlockStmt : Stmt { std::vector<StmtPtr> stmts; };
struct LoopStmt : Stmt { StmtPtr body; LoopStmt(StmtPtr b) : body(std::move(b)) {} };
struct BreakIfzStmt : Stmt { ExprPtr cond; BreakIfzStmt(ExprPtr c) : cond(std::move(c)) {} };
struct PrintStmt : Stmt { ExprPtr e; PrintStmt(ExprPtr x) : e(std::move(x)) {} };

// ---------- Parser ----------

struct Parser {
    std::vector<Token> toks;
    size_t pos = 0;

    Tok type() const { return pos < toks.size() ? toks[pos].type : Tok::END; }
    const std::string& val() const { static std::string empty; return pos < toks.size() ? toks[pos].val : empty; }
    void advance() { if (pos < toks.size()) pos++; }
    bool match(Tok t) { if (type() == t) { advance(); return true; } return false; }

    std::expected<ExprPtr, std::string> parse_atom() {
        if (type() == Tok::NUM) { int v = std::stoi(val()); advance(); return std::make_unique<NumberExpr>(v); }
        if (type() == Tok::ID) { auto n = val(); advance(); return std::make_unique<VarExpr>(n); }
        if (match(Tok::LPAREN)) {
            auto e = parse_sum();
            if (!e) return e;
            if (!match(Tok::RPAREN)) return std::unexpected("Expected ')'");
            return e;
        }
        return std::unexpected("Expected atom");
    }

    std::expected<ExprPtr, std::string> parse_unary() {
        if (match(Tok::MINUS)) {
            auto e = parse_atom();
            if (!e) return e;
            return std::make_unique<NegExpr>(std::move(*e));
        }
        return parse_atom();
    }

    std::expected<ExprPtr, std::string> parse_sum() {
        auto left = parse_unary();
        if (!left) return left;
        while (type() == Tok::PLUS || type() == Tok::MINUS) {
            char op = val()[0]; advance();
            auto right = parse_unary();
            if (!right) return right;
            left = std::make_unique<BinExpr>(op, std::move(*left), std::move(*right));
        }
        return left;
    }

    std::expected<StmtPtr, std::string> parse_stmt() {
        if (type() == Tok::ID) {
            auto name = val(); advance();
            if (match(Tok::ASSIGN)) {
                auto e = parse_sum();
                if (!e) return std::unexpected(e.error());
                return std::make_unique<AssignStmt>(name, std::move(*e));
            }
            if (match(Tok::COLON)) return std::make_unique<DeclStmt>(name);
            return std::unexpected("Expected ':=' or ':'");
        }
        if (match(Tok::LOOP)) {
            auto body = parse_stmt();
            if (!body) return body;
            return std::make_unique<LoopStmt>(std::move(*body));
        }
        if (match(Tok::BREAK_IFZ)) {
            auto c = parse_sum();
            if (!c) return std::unexpected(c.error());
            return std::make_unique<BreakIfzStmt>(std::move(*c));
        }
        if (match(Tok::PRINT)) {
            auto e = parse_sum();
            if (!e) return std::unexpected(e.error());
            return std::make_unique<PrintStmt>(std::move(*e));
        }
        if (match(Tok::LBRACE)) {
            auto block = std::make_unique<BlockStmt>();
            while (!match(Tok::RBRACE)) {
                auto s = parse_stmt();
                if (!s) return s;
                block->stmts.push_back(std::move(*s));
                match(Tok::SEMI);
            }
            return block;
        }
        return std::unexpected("Expected statement");
    }
};

// ---------- Utilities ----------

inline std::string read_file(const char* path) {
    std::ifstream f(path);
    std::stringstream ss; ss << f.rdbuf();
    return ss.str();
}

inline auto parse_program(std::string_view src) {
    auto toks = tokenize(src);
    if (!toks) return std::expected<std::vector<StmtPtr>, std::string>(std::unexpected(toks.error()));
    Parser p{std::move(*toks)};
    std::vector<StmtPtr> prog;
    while (p.type() != Tok::END) {
        auto s = p.parse_stmt();
        if (!s) return std::expected<std::vector<StmtPtr>, std::string>(std::unexpected(s.error()));
        prog.push_back(std::move(*s));
    }
    return std::expected<std::vector<StmtPtr>, std::string>(std::move(prog));
}
