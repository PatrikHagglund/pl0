// PL/0 Level 1 Interpreter (C++23)
#include "pl0_1.hpp"
#include <unordered_map>

using Env = std::unordered_map<std::string, Int>;

Int eval(Expr* e, Env& env) {
    if (auto* n = dynamic_cast<NumberExpr*>(e)) return n->val;
    if (auto* v = dynamic_cast<VarExpr*>(e)) return env[v->name];
    if (auto* u = dynamic_cast<NegExpr*>(e)) return -eval(u->e.get(), env);
    if (auto* b = dynamic_cast<BinExpr*>(e)) {
        Int l = eval(b->l.get(), env), r = eval(b->r.get(), env);
        if (b->op == '+') return Int(l + r);
        return Int(l - r);
    }
    return 0;
}

struct Break {};

template<typename T> void print_int_impl(T v) {
    if constexpr (requires { v.str(); }) {
        v.str();  // bigint::print via str()
    } else {
        if (v == 0) { std::println("0"); return; }
        std::string s; bool neg = v < 0; if (neg) v = -v;
        while (v) { s = char('0' + int(v % 10)) + s; v /= 10; }
        std::println("{}", neg ? "-" + s : s);
    }
}

void print_int(Int v) { print_int_impl(v); }

void exec(Stmt* s, Env& env) {
    if (auto* d = dynamic_cast<DeclStmt*>(s)) env.try_emplace(d->name, 0);
    else if (auto* a = dynamic_cast<AssignStmt*>(s)) env[a->name] = eval(a->e.get(), env);
    else if (auto* b = dynamic_cast<BlockStmt*>(s)) for (auto& st : b->stmts) exec(st.get(), env);
    else if (auto* l = dynamic_cast<LoopStmt*>(s)) {
        try { while (true) exec(l->body.get(), env); } catch (Break) {}
    }
    else if (auto* b = dynamic_cast<BreakIfzStmt*>(s)) { if (eval(b->cond.get(), env) == 0) throw Break{}; }
    else if (auto* pr = dynamic_cast<PrintStmt*>(s)) print_int(eval(pr->e.get(), env));
}

int main(int argc, char** argv) {
    if (argc < 2) { std::println(stderr, "Usage: {} <file> [arg1..arg{}]", argv[0], ARG_COUNT); return 1; }
    auto prog = parse_program(read_file(argv[1]));
    if (!prog) { std::println(stderr, "Error: {}", prog.error()); return 1; }

    Env env;
    for (int i = 1; i <= ARG_COUNT; ++i) {
        auto name = std::format("arg{}", i);
        if constexpr (INT_BITS > 0 && INT_BITS <= 128)
            env[name] = argc > i + 1 ? std::atoll(argv[i + 1]) : 0;
        else
            env[name] = argc > i + 1 ? Int(argv[i + 1]) : Int(0);
    }

    for (auto& s : *prog) {
        try { exec(s.get(), env); }
        catch (Break) { std::println(stderr, "Error: break_ifz outside loop"); break; }
    }
}
