// PL/0 Level 1 Compiler - Unified C++ and LLVM IR backend
#include "pl0_1.hpp"
#include "pl0_1_preamble.hpp"
#include <unordered_set>
#include <cstring>

auto collect_vars(std::vector<StmtPtr>& prog) {
    std::unordered_set<std::string> vars;
    auto go = [&](auto&& go, Stmt* s) -> void {
        if (auto* d = dynamic_cast<DeclStmt*>(s)) vars.insert(d->name);
        else if (auto* a = dynamic_cast<AssignStmt*>(s)) vars.insert(a->name);
        else if (auto* b = dynamic_cast<BlockStmt*>(s)) for (auto& x : b->stmts) go(go, x.get());
        else if (auto* l = dynamic_cast<LoopStmt*>(s)) go(go, l->body.get());
    };
    for (auto& s : prog) go(go, s.get());
    for (int i = 1; i <= ARG_COUNT; ++i) vars.erase(std::format("arg{}", i));
    return vars;
}

struct Gen {
    bool L;  // true = LLVM, false = C++
    int t = 0, lbl = 0;
    std::vector<int> ex;
    bool bi = (INT_BITS == 0);
    std::string I = bi ? "ptr" : std::format("i{}", INT_BITS);

    std::string tmp() { return std::format("%t{}", t++); }

    std::string e(Expr* x) {
        if (auto* n = dynamic_cast<NumberExpr*>(x)) {
            if (!L) return std::format("Int({})", n->val);
            if (bi) { auto buf = tmp(); std::println("  {} = alloca [24 x i8]", buf); std::println("  call void @bi_init(ptr {}, i64 {})", buf, n->val); return buf; }
            return std::to_string(n->val);
        }
        if (auto* v = dynamic_cast<VarExpr*>(x)) {
            if (!L) return v->name;
            if (bi) return std::format("%{}", v->name);
            auto r = tmp(); std::println("  {} = load {}, ptr %{}", r, I, v->name); return r;
        }
        if (auto* u = dynamic_cast<NegExpr*>(x)) {
            auto v = e(u->e.get());
            if (!L) return std::format("-({})", v);
            if (bi) { auto sz = tmp(), bytes = tmp(), buf = tmp(); std::println("  {} = call i32 @bi_neg_size(ptr {})", sz, v); std::println("  {} = call i32 @bi_buf_size(i32 {})", bytes, sz); std::println("  {} = alloca i8, i32 {}", buf, bytes); std::println("  call void @bi_neg(ptr {}, ptr {})", buf, v); return buf; }
            auto r = tmp(); std::println("  {} = sub {} 0, {}", r, I, v); return r;
        }
        if (auto* b = dynamic_cast<BinExpr*>(x)) {
            auto lv = e(b->l.get()), rv = e(b->r.get()); const char* op = b->op == '+' ? "add" : "sub";
            if (!L) return std::format("({} {} {})", lv, b->op, rv);
            if (bi) { auto sz = tmp(), bytes = tmp(), buf = tmp(); std::println("  {} = call i32 @bi_{}_size(ptr {}, ptr {})", sz, op, lv, rv); std::println("  {} = call i32 @bi_buf_size(i32 {})", bytes, sz); std::println("  {} = alloca i8, i32 {}", buf, bytes); std::println("  call void @bi_{}(ptr {}, ptr {}, ptr {})", op, buf, lv, rv); return buf; }
            auto r = tmp(); std::println("  {} = {} {} {}, {}", r, op, I, lv, rv); return r;
        }
        return L ? (bi ? "null" : "0") : "Int(0)";
    }

    void s(Stmt* x, int d = 1) {
        auto ind = [&]{ if (!L) for (int i = 0; i < d; i++) std::print("  "); };
        if (auto* a = dynamic_cast<AssignStmt*>(x)) {
            auto v = e(a->e.get()); ind();
            if (L && bi) std::println("  call void @bi_copy(ptr %{}, ptr {})", a->name, v);
            else L ? std::println("  store {} {}, ptr %{}", I, v, a->name) : std::println("{} = {};", a->name, v);
        }
        else if (auto* b = dynamic_cast<BlockStmt*>(x)) for (auto& y : b->stmts) s(y.get(), d);
        else if (auto* l = dynamic_cast<LoopStmt*>(x)) {
            int h = lbl++, z = lbl++; ex.push_back(z);
            if (L && bi) { auto sp = tmp(); std::println("  {} = call ptr @llvm.stacksave.p0()", sp); std::println("  br label %L{}\nL{}:", h, h); s(l->body.get(), d); std::println("  call void @llvm.stackrestore.p0(ptr {})", sp); std::println("  br label %L{}\nL{}:", h, z); }
            else if (L) { std::println("  br label %L{}\nL{}:", h, h); s(l->body.get(), d); std::println("  br label %L{}\nL{}:", h, z); }
            else { ind(); std::println("for(;;) {{"); s(l->body.get(), d + 1); ind(); std::println("}} L{}:;", z); }
            ex.pop_back();
        }
        else if (auto* b = dynamic_cast<BreakIfzStmt*>(x)) {
            auto c = e(b->cond.get());
            if (L) { auto r = tmp(); int n = lbl++; bi ? std::println("  {} = call i32 @bi_is_zero(ptr {})", r, c) : std::println("  {} = icmp eq {} {}, 0", r, I, c); if (bi) std::println("  %cmp{} = icmp ne i32 {}, 0", n, r); std::println("  br i1 {}, label %L{}, label %L{}\nL{}:", bi ? std::format("%cmp{}", n) : r, ex.back(), n, n); }
            else { ind(); std::println("if ({} == 0) goto L{};", c, ex.back()); }
        }
        else if (auto* p = dynamic_cast<PrintStmt*>(x)) {
            auto v = e(p->e.get());
            if (L) bi ? std::println("  call void @bi_print(ptr {})", v) : std::println("  call void @print_int({} {})", I, v);
            else { ind(); (INT_BITS > 0 && INT_BITS <= 128) ? std::println("std::println(\"{{}}\", to_string({}));", v) : std::println("std::println(\"{{}}\", ({}).str());", v); }
        }
    }

    void gen(std::vector<StmtPtr>& prog) {
        auto vars = collect_vars(prog);
        if (L) {
            if (bi) {
                std::println("{}", LLVM_BIGINT_PREAMBLE);
                for (auto& v : vars) { std::println("  %{} = alloca [520 x i8]", v); std::println("  call void @bi_init(ptr %{}, i64 0)", v); }
                emit_args_llvm_bigint();
            } else {
                std::print("{}", llvm_int_preamble(I));
                for (auto& v : vars) std::println("  %{} = alloca {}\n  store {} 0, ptr %{}", v, I, I, v);
                emit_args_llvm_int(I);
            }
        } else {
            cpp_preamble();
            std::println("int main(int argc, char** argv) {{");
            for (auto& v : vars) std::println("  Int {} = 0;", v);
            emit_args_cpp();
        }
        for (auto& x : prog) s(x.get());
        L ? std::println("  ret i32 0\n}}") : std::println("}}");
    }
};

int main(int argc, char** argv) {
    bool llvm = false; const char* file = nullptr;
    for (int i = 1; i < argc; i++) if (!strcmp(argv[i], "--llvm")) llvm = true; else file = argv[i];
    if (!file) { std::println(stderr, "Usage: {} [--llvm] <file>", argv[0]); return 1; }
    auto prog = parse_program(read_file(file));
    if (!prog) { std::println(stderr, "Error: {}", prog.error()); return 1; }
    Gen{llvm, 0, 0, {}, (INT_BITS == 0), (INT_BITS == 0) ? "ptr" : std::format("i{}", INT_BITS)}.gen(*prog);
}
