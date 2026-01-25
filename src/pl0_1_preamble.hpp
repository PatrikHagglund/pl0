// PL/0 Level 1 Compiler - Runtime preambles for code generation
#pragma once
#include "pl0_1.hpp"

// LLVM IR preamble for bigint (INT_BITS=0)
constexpr auto LLVM_BIGINT_PREAMBLE = R"(; Bigint runtime (heap vars, stack temps)
declare void @bi_init(ptr, i64)
declare void @bi_copy(ptr, ptr)
declare void @bi_add(ptr, ptr, ptr)
declare void @bi_sub(ptr, ptr, ptr)
declare void @bi_neg(ptr, ptr)
declare i32 @bi_size(ptr)
declare i32 @bi_add_size(ptr, ptr)
declare i32 @bi_sub_size(ptr, ptr)
declare i32 @bi_neg_size(ptr)
declare i32 @bi_buf_size(i32)
declare i1 @bi_is_zero(ptr)
declare void @bi_print(ptr)
declare void @bi_from_str(ptr, ptr)
declare void @bi_assign(ptr, ptr, ptr)
declare void @bi_var_init(ptr, ptr)
declare void @bi_arg_init(ptr, ptr, i32, ptr, i32)
declare ptr @llvm.stacksave.p0()
declare void @llvm.stackrestore.p0(ptr)

define i32 @main(i32 %argc, ptr %argv) {
entry:)";

// LLVM IR preamble for fixed-width integers
inline std::string llvm_int_preamble(const std::string& I) {
    auto ret = INT_BITS <= 32 ? "  %v = trunc i64 %v64 to i32\n  ret i32 %v"
             : INT_BITS <= 64 ? "  ret i64 %v64"
             : std::format("  %v = sext i64 %v64 to {0}\n  ret {0} %v", I);
    auto dig = INT_BITS <= 32 ? "  %c = add i32 %rem, 48"
             : std::format("  %d = trunc {} %rem to i32\n  %c = add i32 %d, 48", I);
    return std::format(R"(declare i32 @putchar(i32)
declare i64 @strtol(ptr, ptr, i32)

define void @print_int_rec({0} %v) {{ %z = icmp eq {0} %v, 0  br i1 %z, label %done, label %print
print: %div = sdiv {0} %v, 10  %rem = srem {0} %v, 10  call void @print_int_rec({0} %div)
{2}  call i32 @putchar(i32 %c)  br label %done
done: ret void }}

define void @print_int({0} %v) {{ %z = icmp eq {0} %v, 0  br i1 %z, label %zero, label %nonzero
zero: call i32 @putchar(i32 48)  br label %done
nonzero: call void @print_int_rec({0} %v)  br label %done
done: call i32 @putchar(i32 10)  ret void }}

define {0} @parse_arg(i32 %argc, ptr %argv, i32 %idx) {{ %has = icmp sgt i32 %argc, %idx  br i1 %has, label %read, label %default
read: %i = sext i32 %idx to i64  %p = getelementptr ptr, ptr %argv, i64 %i  %s = load ptr, ptr %p  %v64 = call i64 @strtol(ptr %s, ptr null, i32 10)
{1}
default: ret {0} 0 }}

define i32 @main(i32 %argc, ptr %argv) {{
entry:)", I, ret, dig);
}

// C++ preamble - unified runtime interface
// INT_BITS can be overridden via -D on the clang++ line
inline void cpp_preamble(bool = false) {
    std::puts(R"(#ifndef INT_BITS
#define INT_BITS 0
#endif

#if INT_BITS == 0
#include "pl0_1_bigint.hpp"
#define VAR(name) auto name##_v = bigint::var_init()
#define ARG(name, idx) auto name##_v = bigint::arg_init(argc, argv, idx)
#define REF(name) (*name##_v.ptr)
#define ASSIGN(name, val) bigint::assign(name##_v, val)
#define IS_ZERO(x) bigint::is_zero(x)
#define PRINT(x) bigint::print(x)
#define LIT(name, v) BIGINT_LIT(name); bigint::init(name, v)
#define NEG(name, a) BIGINT_TMP(name, (a).size); bigint::neg(name, a)
#define ADD(name, a, b) BIGINT_TMP(name, bigint::add_size(a, b)); bigint::add(name, a, b)
#define SUB(name, a, b) BIGINT_TMP(name, bigint::sub_size(a, b)); bigint::sub(name, a, b)
#else
#include <print>
#include <cstdlib>
using Int = _BitInt(INT_BITS);
inline std::string to_string(Int v) { if (!v) return "0"; std::string s; bool n = v < 0; if (n) v = -v; while (v) { s = char('0' + v % 10) + s; v /= 10; } return n ? "-" + s : s; }
#define VAR(name) Int name = 0
#define ARG(name, idx) Int name = argc > idx ? std::atoll(argv[idx]) : 0
#define REF(name) (name)
#define ASSIGN(name, val) name = (val)
#define IS_ZERO(x) ((x) == 0)
#define PRINT(x) std::print("{}\n", to_string(x))
#define LIT(name, v) Int name = (v)
#define NEG(name, a) Int name = -(a)
#define ADD(name, a, b) Int name = (a) + (b)
#define SUB(name, a, b) Int name = (a) - (b)
#endif)");
}

// Emit argument parsing
inline void emit_args_llvm_bigint() {
    for (int i = 1; i <= ARG_COUNT; ++i) {
        std::print("  %arg{0} = alloca ptr\n", i);
        std::print("  %arg{0}_cap = alloca i32\n", i);
        std::print("  call void @bi_arg_init(ptr %arg{0}, ptr %arg{0}_cap, i32 %argc, ptr %argv, i32 {0})\n", i);
    }
}

inline void emit_args_llvm_int(const std::string& I) {
    for (int i = 1; i <= ARG_COUNT; ++i)
        std::print("  %arg{0} = alloca {1}\n  %a{0} = call {1} @parse_arg(i32 %argc, ptr %argv, i32 {0})\n  store {1} %a{0}, ptr %arg{0}\n", i, I);
}

inline void emit_args_cpp() {
    for (int i = 1; i <= ARG_COUNT; ++i)
        std::print("  Int arg{0} = argc > {0} ? std::atoll(argv[{0}]) : 0;\n", i);
}
