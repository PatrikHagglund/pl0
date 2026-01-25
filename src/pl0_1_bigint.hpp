// Header-only bigint implementation
// Used directly by C++ backend, compiled to .o for LLVM backend
#pragma once
#include <cstdint>
#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <string>
#include <print>

namespace bigint {

// --- Limb abstraction ---
// Configure via LIMB_BITS macro (default 64). DLimb must be 2x Limb width.
// Note: LIMB_BITS=256+ has very slow runtime for LLVM IR backend.
#ifndef LIMB_BITS
#define LIMB_BITS 64
#endif

using Limb = unsigned _BitInt(LIMB_BITS);
using SLimb = signed _BitInt(LIMB_BITS);
using DLimb = unsigned _BitInt(LIMB_BITS * 2);

inline constexpr int LimbBits = LIMB_BITS;
inline constexpr Limb Limb0 = 0;
using Size = uint32_t;

// --- Limb-width dependent carry/borrow operations ---
[[gnu::hot]] inline Limb addc(Limb a, Limb b, Limb carry_in, Limb* carry_out) {
    if constexpr (LIMB_BITS == 64) {
        unsigned long co;
        auto r = __builtin_addcl(static_cast<unsigned long>(a), static_cast<unsigned long>(b), carry_in, &co);
        *carry_out = co;
        return r;
    } else if constexpr (LIMB_BITS == 32) {
        unsigned co;
        auto r = __builtin_addc(static_cast<unsigned>(a), static_cast<unsigned>(b), carry_in, &co);
        *carry_out = co;
        return r;
    } else {
        auto sum = static_cast<DLimb>(a) + b + carry_in;
        *carry_out = static_cast<Limb>(sum >> LimbBits);
        return static_cast<Limb>(sum);
    }
}

[[gnu::hot]] inline Limb subc(Limb a, Limb b, Limb borrow_in, Limb* borrow_out) {
    if constexpr (LIMB_BITS == 64) {
        unsigned long bo;
        auto r = __builtin_subcl(static_cast<unsigned long>(a), static_cast<unsigned long>(b), borrow_in, &bo);
        *borrow_out = bo;
        return r;
    } else if constexpr (LIMB_BITS == 32) {
        unsigned bo;
        auto r = __builtin_subc(static_cast<unsigned>(a), static_cast<unsigned>(b), borrow_in, &bo);
        *borrow_out = bo;
        return r;
    } else {
        *borrow_out = a < b + borrow_in;
        return a - b - borrow_in;
    }
}

struct Raw {
    Size size;
    bool neg;
    Limb limbs[];

    static constexpr Size buf_size(Size n) { return sizeof(Raw) + n * sizeof(Limb); }
};

// --- Stack allocation macros for C++ backend ---
// BIGINT_TMP(name, limbs) - declare stack-allocated Raw& with given limb capacity
// BIGINT_LIT(name)        - declare stack-allocated Raw& for a literal (1 limb)
#define BIGINT_TMP(name, limbs) \
    alignas(8) char name##_buf[bigint::Raw::buf_size(limbs)]; \
    auto& name = *reinterpret_cast<bigint::Raw*>(name##_buf)
#define BIGINT_LIT(name) BIGINT_TMP(name, 1)

// --- Core operations (all inline, reference-based) ---

inline void init(Raw& __restrict out, SLimb v) {
    out.neg = v < 0;
    auto uv = static_cast<Limb>(v < 0 ? -v : v);
    out.size = uv ? (out.limbs[0] = uv, 1) : 0;
}

inline void copy(Raw& __restrict dst, const Raw& __restrict src) {
    dst.size = src.size;
    dst.neg = src.neg;
    std::memcpy(dst.limbs, src.limbs, src.size * sizeof(Limb));
}

[[nodiscard]] inline int cmp_mag(const Raw& __restrict a, const Raw& __restrict b) {
    if (a.size != b.size) return a.size > b.size ? 1 : -1;
    for (Size i = a.size; i-- > 0; )
        if (a.limbs[i] != b.limbs[i]) return a.limbs[i] > b.limbs[i] ? 1 : -1;
    return 0;
}

[[gnu::hot]] inline void add_mag(Raw* __restrict out, const Raw* __restrict a, const Raw* __restrict b) {
    auto n = std::max(a->size, b->size);
    Limb carry = 0;
    for (Size i = 0; i < n; i++) {
        auto av = i < a->size ? a->limbs[i] : Limb0;
        auto bv = i < b->size ? b->limbs[i] : Limb0;
        out->limbs[i] = addc(av, bv, carry, &carry);
    }
    out->size = carry ? (out->limbs[n] = carry, n + 1) : n;
}

[[gnu::hot]] inline void sub_mag(Raw* __restrict out, const Raw* __restrict a, const Raw* __restrict b) {
    auto n = a->size;
    Limb borrow = 0;
    for (Size i = 0; i < n; i++) {
        auto av = a->limbs[i];
        auto bv = i < b->size ? b->limbs[i] : Limb0;
        out->limbs[i] = subc(av, bv, borrow, &borrow);
    }
    while (n > 0 && out->limbs[n-1] == 0) n--;
    out->size = n;
}

[[nodiscard]] inline Size add_size(const Raw& __restrict a, const Raw& __restrict b) { return std::max(a.size, b.size) + 1; }
[[nodiscard]] inline Size sub_size(const Raw& __restrict a, const Raw& __restrict b) { return std::max(a.size, b.size) + 1; }

// Public API uses references; internally calls pointer-based *_mag for __restrict optimization
inline void add(Raw& __restrict out, const Raw& __restrict a, const Raw& __restrict b) {
    if (a.neg == b.neg) { add_mag(&out, &a, &b); out.neg = a.neg; }
    else if (cmp_mag(a, b) >= 0) { sub_mag(&out, &a, &b); out.neg = a.neg; }
    else { sub_mag(&out, &b, &a); out.neg = b.neg; }
    if (out.size == 0) out.neg = false;
}

inline void sub(Raw& __restrict out, const Raw& __restrict a, const Raw& __restrict b) {
    if (a.neg != b.neg) { add_mag(&out, &a, &b); out.neg = a.neg; }
    else if (cmp_mag(a, b) >= 0) { sub_mag(&out, &a, &b); out.neg = a.neg; }
    else { sub_mag(&out, &b, &a); out.neg = !a.neg; }
    if (out.size == 0) out.neg = false;
}

inline void neg(Raw& __restrict out, const Raw& __restrict a) {
    copy(out, a);
    if (out.size > 0) out.neg = !out.neg;
}

[[nodiscard]] inline bool is_zero(const Raw& __restrict a) { return a.size == 0; }

// Multiply limb by 10, add carry, return new carry (high part)
inline Limb mul10_add(Limb a, Limb carry_in, Limb* lo) {
    // a * 10 = a * 8 + a * 2
    Limb a8, a2, sum;
    Limb c1 = a >> (LimbBits - 3);  // high 3 bits of a*8
    a8 = a << 3;
    Limb c2 = a >> (LimbBits - 1);  // high bit of a*2
    a2 = a << 1;
    Limb c3 = __builtin_add_overflow(a8, a2, &sum);
    Limb c4 = __builtin_add_overflow(sum, carry_in, lo);
    return c1 + c2 + c3 + c4;
}

[[gnu::cold]] inline void from_str(Raw& __restrict out, const char* __restrict s) {
    out.size = 0;
    out.neg = (*s == '-') ? (s++, true) : (*s == '+' ? (s++, false) : false);
    while (*s) {
        Limb carry = *s++ - '0';
        for (Size i = 0; i < out.size; i++) {
            carry = mul10_add(out.limbs[i], carry, &out.limbs[i]);
        }
        if (carry) out.limbs[out.size++] = carry;
    }
    if (out.size == 0) out.neg = false;
}

// Divide (rem:limb) by 10, return quotient and update rem
inline Limb div10(Limb hi, Limb lo, Limb* __restrict rem_out) {
    // Use 128-bit division - no portable builtin alternative
    auto cur = (static_cast<DLimb>(hi) << LimbBits) | lo;
    *rem_out = cur % 10;
    return static_cast<Limb>(cur / 10);
}

[[gnu::cold]] inline void print(const Raw& __restrict v) {
    if (v.size == 0) { puts("0"); return; }
    auto* tmp = static_cast<Limb*>(std::malloc(v.size * sizeof(Limb)));
    Size n = v.size;
    std::memcpy(tmp, v.limbs, n * sizeof(Limb));
    // ~0.302 decimal digits per bit (log10(2)), round up to 0.31
    Size buf_cap = (n * LimbBits * 31 + 99) / 100 + 1;
    auto* buf = static_cast<char*>(std::malloc(buf_cap));
    Size pos = 0;
    while (n > 0) {
        Limb rem = 0;
        for (Size i = n; i-- > 0; )
            tmp[i] = div10(rem, tmp[i], &rem);
        buf[pos++] = '0' + static_cast<int>(rem);
        while (n > 0 && tmp[n-1] == 0) n--;
    }
    if (v.neg) putchar('-');
    while (pos > 0) putchar(buf[--pos]);
    putchar('\n');
    std::free(buf);
    std::free(tmp);
}

// --- Heap allocation helpers (for compiled code with unlimited size) ---

struct Var { Raw* ptr; Size cap; };

[[nodiscard]] inline Var var_init() {
    Size cap = Raw::buf_size(1);
    auto* p = static_cast<Raw*>(std::malloc(cap));
    p->size = 0;
    p->neg = false;
    return {p, cap};
}

inline void assign(Var& v, const Raw& value) {
    Size needed = Raw::buf_size(value.size);
    if (needed > v.cap) {
        v.cap = v.cap * 2 > needed ? v.cap * 2 : needed;
        v.ptr = static_cast<Raw*>(std::realloc(v.ptr, v.cap));
    }
    copy(*v.ptr, value);
}

[[nodiscard]] inline Var arg_init(int argc, char** argv, int idx) {
    if (idx < argc) {
        Size limbs_needed = std::strlen(argv[idx]) / 19 + 2;
        auto* tmp = static_cast<Raw*>(std::malloc(Raw::buf_size(limbs_needed)));
        from_str(*tmp, argv[idx]);
        auto v = var_init();
        assign(v, *tmp);
        std::free(tmp);
        return v;
    }
    return var_init();
}

// --- C++ wrapper class using shared assign() ---
// Used by interpreter. Wraps Raw* with RAII.

class Int {
    Var v_ = {};

    Raw& r() { return *v_.ptr; }
    const Raw& r() const { return *v_.ptr; }
public:
    Int() : v_(var_init()) {}
    Int(int val) : v_(var_init()) { init(r(), val); }
    Int(long long val) : v_(var_init()) { init(r(), val); }
    explicit Int(const char* s) {
        Size limbs = std::strlen(s) / 18 + 2;
        v_.ptr = static_cast<Raw*>(std::malloc(Raw::buf_size(limbs)));
        v_.cap = Raw::buf_size(limbs);
        from_str(r(), s);
    }
    ~Int() { std::free(v_.ptr); }

    Int(const Int& o) : v_(var_init()) { assign(v_, o.r()); }
    Int(Int&& o) noexcept : v_(o.v_) { o.v_ = {}; }
    Int& operator=(const Int& o) {
        if (this != &o) assign(v_, o.r());
        return *this;
    }
    Int& operator=(Int&& o) noexcept {
        if (this != &o) { std::free(v_.ptr); v_ = o.v_; o.v_ = {}; }
        return *this;
    }

    Int operator+(const Int& o) const {
        Int res;
        BIGINT_TMP(tmp, add_size(r(), o.r()));
        add(tmp, r(), o.r());
        assign(res.v_, tmp);
        return res;
    }
    Int operator-(const Int& o) const {
        Int res;
        BIGINT_TMP(tmp, sub_size(r(), o.r()));
        sub(tmp, r(), o.r());
        assign(res.v_, tmp);
        return res;
    }
    Int operator-() const {
        Int res;
        BIGINT_TMP(tmp, r().size);
        neg(tmp, r());
        assign(res.v_, tmp);
        return res;
    }

    bool operator==(const Int& o) const { return cmp_mag(r(), o.r()) == 0 && r().neg == o.r().neg; }
    bool operator==(int val) const { Int t(val); return *this == t; }
    bool operator<(int) const { return r().neg && !is_zero(r()); }
    explicit operator bool() const { return !is_zero(r()); }

    std::string str() const { print(r()); return ""; }
};

} // namespace bigint
