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
inline Limb addc(Limb a, Limb b, Limb carry_in, Limb* carry_out) {
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

inline Limb subc(Limb a, Limb b, Limb borrow_in, Limb* borrow_out) {
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
// BIGINT_TMP(name, limbs) - declare stack-allocated Raw* with given limb capacity
// BIGINT_LIT(name)        - declare stack-allocated Raw* for a literal (1 limb)
#define BIGINT_TMP(name, limbs) \
    alignas(8) char name##_buf[bigint::Raw::buf_size(limbs)]; \
    auto* name = reinterpret_cast<bigint::Raw*>(name##_buf)
#define BIGINT_LIT(name) BIGINT_TMP(name, 1)

// --- Core operations (all inline) ---

inline void init(Raw* out, SLimb v) {
    out->neg = v < 0;
    auto uv = static_cast<Limb>(v < 0 ? -v : v);
    out->size = uv ? (out->limbs[0] = uv, 1) : 0;
}

inline void copy(Raw* dst, const Raw* src) {
    dst->size = src->size;
    dst->neg = src->neg;
    std::memcpy(dst->limbs, src->limbs, src->size * sizeof(Limb));
}

inline int cmp_mag(const Raw* a, const Raw* b) {
    if (a->size != b->size) return a->size > b->size ? 1 : -1;
    for (Size i = a->size; i-- > 0; )
        if (a->limbs[i] != b->limbs[i]) return a->limbs[i] > b->limbs[i] ? 1 : -1;
    return 0;
}

inline void add_mag(Raw* out, const Raw* a, const Raw* b) {
    auto n = std::max(a->size, b->size);
    Limb carry = 0;
    for (Size i = 0; i < n; i++) {
        auto av = i < a->size ? a->limbs[i] : Limb0;
        auto bv = i < b->size ? b->limbs[i] : Limb0;
        out->limbs[i] = addc(av, bv, carry, &carry);
    }
    out->size = carry ? (out->limbs[n] = carry, n + 1) : n;
}

inline void sub_mag(Raw* out, const Raw* a, const Raw* b) {
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

inline Size add_size(const Raw* a, const Raw* b) { return std::max(a->size, b->size) + 1; }
inline Size sub_size(const Raw* a, const Raw* b) { return std::max(a->size, b->size) + 1; }

inline void add(Raw* out, const Raw* a, const Raw* b) {
    if (a->neg == b->neg) { add_mag(out, a, b); out->neg = a->neg; }
    else if (cmp_mag(a, b) >= 0) { sub_mag(out, a, b); out->neg = a->neg; }
    else { sub_mag(out, b, a); out->neg = b->neg; }
    if (out->size == 0) out->neg = false;
}

inline void sub(Raw* out, const Raw* a, const Raw* b) {
    if (a->neg != b->neg) { add_mag(out, a, b); out->neg = a->neg; }
    else if (cmp_mag(a, b) >= 0) { sub_mag(out, a, b); out->neg = a->neg; }
    else { sub_mag(out, b, a); out->neg = !a->neg; }
    if (out->size == 0) out->neg = false;
}

inline void neg(Raw* out, const Raw* a) {
    copy(out, a);
    if (out->size > 0) out->neg = !out->neg;
}

inline bool is_zero(const Raw* a) { return a->size == 0; }

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

inline void from_str(Raw* out, const char* s) {
    out->size = 0;
    out->neg = (*s == '-') ? (s++, true) : (*s == '+' ? (s++, false) : false);
    while (*s) {
        Limb carry = *s++ - '0';
        for (Size i = 0; i < out->size; i++) {
            carry = mul10_add(out->limbs[i], carry, &out->limbs[i]);
        }
        if (carry) out->limbs[out->size++] = carry;
    }
    if (out->size == 0) out->neg = false;
}

// Divide (rem:limb) by 10, return quotient and update rem
inline Limb div10(Limb hi, Limb lo, Limb* rem_out) {
    // Use 128-bit division - no portable builtin alternative
    auto cur = (static_cast<DLimb>(hi) << LimbBits) | lo;
    *rem_out = cur % 10;
    return static_cast<Limb>(cur / 10);
}

inline void print(const Raw* v) {
    if (v->size == 0) { puts("0"); return; }
    auto* tmp = static_cast<Limb*>(std::malloc(v->size * sizeof(Limb)));
    Size n = v->size;
    std::memcpy(tmp, v->limbs, n * sizeof(Limb));
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
    if (v->neg) putchar('-');
    while (pos > 0) putchar(buf[--pos]);
    putchar('\n');
    std::free(buf);
    std::free(tmp);
}

// --- Heap allocation helpers (for compiled code with unlimited size) ---

inline void var_init(Raw** var_ptr, Size* cap_ptr) {
    Size cap = Raw::buf_size(1);  // space for at least 1 limb
    auto* p = static_cast<Raw*>(std::malloc(cap));
    *var_ptr = p;
    *cap_ptr = cap;
    p->size = 0;
    p->neg = false;
}

inline void assign(Raw** var_ptr, Size* cap_ptr, const Raw* value) {
    Size needed = Raw::buf_size(value->size);
    Size cap = *cap_ptr;
    Raw* var = *var_ptr;
    if (needed > cap) {
        Size newcap = cap * 2 > needed ? cap * 2 : needed;
        var = static_cast<Raw*>(std::realloc(var, newcap));
        *var_ptr = var;
        *cap_ptr = newcap;
    }
    copy(var, value);
}

inline void arg_init(Raw** var_ptr, Size* cap_ptr, int argc, char** argv, int idx) {
    *var_ptr = nullptr;
    *cap_ptr = 0;
    if (idx < argc) {
        Size limbs_needed = std::strlen(argv[idx]) / 19 + 2;  // ~19 digits per limb + margin
        auto* buf = static_cast<char*>(std::malloc(Raw::buf_size(limbs_needed)));
        auto* tmp = reinterpret_cast<Raw*>(buf);
        from_str(tmp, argv[idx]);
        assign(var_ptr, cap_ptr, tmp);
        std::free(buf);
    } else {
        var_init(var_ptr, cap_ptr);
    }
}

// --- C++ wrapper class using shared assign() ---
// Used by interpreter. Wraps Raw* with RAII.

class Int {
    Raw* ptr_ = nullptr;
    Size cap_ = 0;  // capacity in bytes

    Raw* p() { return ptr_; }
    const Raw* p() const { return ptr_; }
public:
    Int() { var_init(&ptr_, &cap_); }
    Int(int v) { var_init(&ptr_, &cap_); init(ptr_, v); }
    Int(long long v) { var_init(&ptr_, &cap_); init(ptr_, v); }
    explicit Int(const char* s) {
        Size limbs = std::strlen(s) / 18 + 2;
        ptr_ = static_cast<Raw*>(std::malloc(Raw::buf_size(limbs)));
        cap_ = Raw::buf_size(limbs);
        from_str(ptr_, s);
    }
    ~Int() { std::free(ptr_); }

    Int(const Int& o) { var_init(&ptr_, &cap_); assign(&ptr_, &cap_, o.ptr_); }
    Int(Int&& o) noexcept : ptr_(o.ptr_), cap_(o.cap_) { o.ptr_ = nullptr; o.cap_ = 0; }
    Int& operator=(const Int& o) {
        if (this != &o) assign(&ptr_, &cap_, o.ptr_);
        return *this;
    }
    Int& operator=(Int&& o) noexcept {
        if (this != &o) { std::free(ptr_); ptr_ = o.ptr_; cap_ = o.cap_; o.ptr_ = nullptr; o.cap_ = 0; }
        return *this;
    }

    Int operator+(const Int& o) const {
        Int r;
        Size sz = add_size(p(), o.p());
        char buf[Raw::buf_size(sz)];
        auto* tmp = reinterpret_cast<Raw*>(buf);
        add(tmp, p(), o.p());
        assign(&r.ptr_, &r.cap_, tmp);
        return r;
    }
    Int operator-(const Int& o) const {
        Int r;
        Size sz = sub_size(p(), o.p());
        char buf[Raw::buf_size(sz)];
        auto* tmp = reinterpret_cast<Raw*>(buf);
        sub(tmp, p(), o.p());
        assign(&r.ptr_, &r.cap_, tmp);
        return r;
    }
    Int operator-() const {
        Int r;
        char buf[Raw::buf_size(p()->size)];
        auto* tmp = reinterpret_cast<Raw*>(buf);
        neg(tmp, p());
        assign(&r.ptr_, &r.cap_, tmp);
        return r;
    }

    bool operator==(const Int& o) const { return cmp_mag(p(), o.p()) == 0 && p()->neg == o.p()->neg; }
    bool operator==(int v) const { Int t(v); return *this == t; }
    bool operator<(int) const { return p()->neg && !is_zero(p()); }
    explicit operator bool() const { return !is_zero(p()); }

    std::string str() const { print(p()); return ""; }
};

} // namespace bigint
