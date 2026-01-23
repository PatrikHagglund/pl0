// PL/0 Level 1 Compiler - C++ and LLVM IR backends
//
// Two backends:
//   - C++ backend (default): emits C++ using pl0_1_bigint.hpp or _BitInt
//   - LLVM backend (--llvm): emits LLVM IR, links with pl0_1_rt_bigint.ll
//
// Bigint memory management (LLVM backend, INT_BITS=0):
//   - Variables: heap-allocated via bi_assign() with realloc() and doubling strategy
//     Each var has a (ptr, cap) pair; starts as (null, 0), first assignment allocates
//   - Temporaries: stack-allocated (alloca), reclaimed via stacksave/restore
//   This gives unlimited integer size with minimal allocation overhead.
//
#include "pl0_1.hpp"
#include "pl0_1_preamble.hpp"
#include <cstring>
#include <unordered_set>

template <class... Args> void p(std::format_string<Args...> fmt, Args &&...args) {
    std::print(fmt, std::forward<Args>(args)...);
}
template <class... Args> std::string f(std::format_string<Args...> fmt, Args &&...args) {
    return std::format(fmt, std::forward<Args>(args)...);
}

auto collect_vars(std::vector<StmtPtr> &prog) {
    std::unordered_set<std::string> vars;
    auto go = [&](auto &&go, Stmt *s) -> void {
        if (auto *d = dynamic_cast<DeclStmt *>(s))
            vars.insert(d->name);
        else if (auto *a = dynamic_cast<AssignStmt *>(s))
            vars.insert(a->name);
        else if (auto *b = dynamic_cast<BlockStmt *>(s))
            for (auto &x : b->stmts)
                go(go, x.get());
        else if (auto *l = dynamic_cast<LoopStmt *>(s))
            go(go, l->body.get());
    };
    for (auto &s : prog)
        go(go, s.get());
    for (int i = 1; i <= ARG_COUNT; ++i)
        vars.erase(f("arg{}", i));
    return vars;
}

// C++ backend - unified code generation using runtime macros
struct GenCpp {
    int lbl = 0, tmp = 0;
    std::vector<int> ex = {};

    // Expression codegen - emits temp declaration, returns variable name
    std::string e(Expr *x) {
        if (auto *n = dynamic_cast<NumberExpr *>(x)) {
            auto t = f("t{}", tmp++);
            p("  LIT({}, {});\n", t, n->val);
            return t;
        }
        if (auto *v = dynamic_cast<VarExpr *>(x))
            return v->name;
        if (auto *u = dynamic_cast<NegExpr *>(x)) {
            auto a = e(u->e.get()), t = f("t{}", tmp++);
            p("  NEG({}, {});\n", t, a);
            return t;
        }
        if (auto *b = dynamic_cast<BinExpr *>(x)) {
            auto l = e(b->l.get()), r = e(b->r.get()), t = f("t{}", tmp++);
            p("  {}({}, {}, {});\n", b->op == '+' ? "ADD" : "SUB", t, l, r);
            return t;
        }
        return "0";
    }

    void s(Stmt *x, int d = 1) {
        auto ind = [&] { for (int i = 0; i < d; i++) std::print("  "); };
        if (auto *a = dynamic_cast<AssignStmt *>(x)) {
            ind(); p("{{\n");
            auto t = e(a->e.get());
            ind(); p("ASSIGN({}, {}); }}\n", a->name, t);
        } else if (auto *b = dynamic_cast<BlockStmt *>(x)) {
            for (auto &y : b->stmts) s(y.get(), d);
        } else if (auto *l = dynamic_cast<LoopStmt *>(x)) {
            int z = lbl++;
            ex.push_back(z);
            ind(); p("for(;;) {{\n");
            s(l->body.get(), d + 1);
            ind(); p("}} L{}:;\n", z);
            ex.pop_back();
        } else if (auto *b = dynamic_cast<BreakIfzStmt *>(x)) {
            ind(); p("{{\n");
            auto t = e(b->cond.get());
            ind(); p("if (IS_ZERO({})) goto L{}; }}\n", t, ex.back());
        } else if (auto *pr = dynamic_cast<PrintStmt *>(x)) {
            ind(); p("{{\n");
            auto t = e(pr->e.get());
            ind(); p("PRINT({}); }}\n", t);
        }
    }

    void gen(std::vector<StmtPtr> &prog) {
        auto vars = collect_vars(prog);
        cpp_preamble();
        p("int main(int argc, char** argv) {{\n");
        for (auto &v : vars)
            p("  VAR({});\n", v);
        for (int i = 1; i <= ARG_COUNT; ++i)
            p("  ARG(arg{0}, {0});\n", i);
        for (auto &x : prog)
            s(x.get());
        p("}}\n");
    }
};

// LLVM backend
struct GenLLVM {
    int t = 0, lbl = 0;
    std::vector<int> ex;
    bool bi = (INT_BITS == 0);
    std::string I = bi ? "ptr" : f("i{}", INT_BITS);

    std::string tmp() { return f("%t{}", t++); }

    std::string e(Expr *x) {
        if (auto *n = dynamic_cast<NumberExpr *>(x)) {
            if (bi) {
                auto buf = tmp();
                p("  {} = alloca [24 x i8]\n", buf);
                p("  call void @bi_init(ptr {}, i64 {})\n", buf, n->val);
                return buf;
            }
            return std::to_string(n->val);
        }
        if (auto *v = dynamic_cast<VarExpr *>(x)) {
            auto r = tmp();
            if (bi)
                p("  {} = load ptr, ptr %{}\n", r, v->name);
            else
                p("  {} = load {}, ptr %{}\n", r, I, v->name);
            return r;
        }
        if (auto *u = dynamic_cast<NegExpr *>(x)) {
            auto v = e(u->e.get());
            if (bi) {
                auto sz = tmp(), bytes = tmp(), buf = tmp();
                p("  {} = call i32 @bi_neg_size(ptr {})\n", sz, v);
                p("  {} = call i32 @bi_buf_size(i32 {})\n", bytes, sz);
                p("  {} = alloca i8, i32 {}\n", buf, bytes);
                p("  call void @bi_neg(ptr {}, ptr {})\n", buf, v);
                return buf;
            }
            auto r = tmp();
            p("  {} = sub {} 0, {}\n", r, I, v);
            return r;
        }
        if (auto *b = dynamic_cast<BinExpr *>(x)) {
            auto lv = e(b->l.get()), rv = e(b->r.get());
            const char *op = b->op == '+' ? "add" : "sub";
            if (bi) {
                auto sz = tmp(), bytes = tmp(), buf = tmp();
                p("  {} = call i32 @bi_{}_size(ptr {}, ptr {})\n", sz, op, lv, rv);
                p("  {} = call i32 @bi_buf_size(i32 {})\n", bytes, sz);
                p("  {} = alloca i8, i32 {}\n", buf, bytes);
                p("  call void @bi_{}(ptr {}, ptr {}, ptr {})\n", op, buf, lv, rv);
                return buf;
            }
            auto r = tmp();
            p("  {} = {} {} {}, {}\n", r, op, I, lv, rv);
            return r;
        }
        return bi ? "null" : "0";
    }

    void s(Stmt *x) {
        if (auto *a = dynamic_cast<AssignStmt *>(x)) {
            if (bi) {
                auto sp = tmp();
                p("  {} = call ptr @llvm.stacksave.p0()\n", sp);
                auto v = e(a->e.get());
                p("  call void @bi_assign(ptr %{}, ptr %{}_cap, ptr {})\n", a->name, a->name, v);
                p("  call void @llvm.stackrestore.p0(ptr {})\n", sp);
            } else {
                auto v = e(a->e.get());
                p("  store {} {}, ptr %{}\n", I, v, a->name);
            }
        } else if (auto *b = dynamic_cast<BlockStmt *>(x)) {
            for (auto &y : b->stmts) s(y.get());
        } else if (auto *l = dynamic_cast<LoopStmt *>(x)) {
            int h = lbl++, z = lbl++;
            ex.push_back(z);
            p("  br label %L{}\nL{}:\n", h, h);
            s(l->body.get());
            p("  br label %L{}\nL{}:\n", h, z);
            ex.pop_back();
        } else if (auto *b = dynamic_cast<BreakIfzStmt *>(x)) {
            auto c = e(b->cond.get());
            auto r = tmp();
            int n = lbl++;
            if (bi)
                p("  {} = call i1 @bi_is_zero(ptr {})\n", r, c);
            else
                p("  {} = icmp eq {} {}, 0\n", r, I, c);
            p("  br i1 {}, label %L{}, label %L{}\nL{}:\n", r, ex.back(), n, n);
        } else if (auto *pr = dynamic_cast<PrintStmt *>(x)) {
            auto v = e(pr->e.get());
            if (bi)
                p("  call void @bi_print(ptr {})\n", v);
            else
                p("  call void @print_int({} {})\n", I, v);
        }
    }

    void gen(std::vector<StmtPtr> &prog) {
        auto vars = collect_vars(prog);
        if (bi) {
            p("{}\n", LLVM_BIGINT_PREAMBLE);
            for (auto &v : vars) {
                p("  %{} = alloca ptr\n", v);
                p("  %{}_cap = alloca i32\n", v);
                p("  call void @bi_var_init(ptr %{}, ptr %{}_cap)\n", v, v);
            }
            emit_args_llvm_bigint();
        } else {
            std::print("{}", llvm_int_preamble(I));
            for (auto &v : vars)
                p("  %{} = alloca {}\n  store {} 0, ptr %{}\n", v, I, I, v);
            emit_args_llvm_int(I);
        }
        for (auto &x : prog)
            s(x.get());
        p("  ret i32 0\n}}\n");
    }
};

int main(int argc, char **argv) {
    bool llvm = false;
    const char *file = nullptr;
    for (int i = 1; i < argc; i++)
        if (!strcmp(argv[i], "--llvm"))
            llvm = true;
        else
            file = argv[i];
    if (!file) {
        std::print(stderr, "Usage: {} [--llvm] <file>\n", argv[0]);
        return 1;
    }
    auto prog = parse_program(read_file(file));
    if (!prog) {
        std::print(stderr, "Error: {}\n", prog.error());
        return 1;
    }
    if (llvm)
        GenLLVM{}.gen(*prog);
    else
        GenCpp{}.gen(*prog);
}
