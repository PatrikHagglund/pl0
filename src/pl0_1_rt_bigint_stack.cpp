// Stack-based bigint runtime for PL/0
// Variables hold ptr to current buffer; reassignment may change the pointer.
// All buffers allocated via alloca (no heap).
#include <cstdint>
#include <cstring>
#include <cstdio>
#include <cstdlib>

struct BigInt {
    int32_t size;   // number of limbs in use
    int32_t neg;    // 1 if negative, 0 otherwise
    uint64_t limbs[];  // flexible array member
};

extern "C" {

// Initialize a bigint buffer with a small value
void bi_init(BigInt* out, int64_t v) {
    out->neg = v < 0 ? 1 : 0;
    uint64_t uv = v < 0 ? -v : v;
    if (uv == 0) { out->size = 0; }
    else { out->size = 1; out->limbs[0] = uv; }
}

// Copy src to dst (dst must have enough space)
void bi_copy(BigInt* dst, const BigInt* src) {
    dst->size = src->size;
    dst->neg = src->neg;
    memcpy(dst->limbs, src->limbs, src->size * sizeof(uint64_t));
}

// Return number of limbs needed for result of a + b
int32_t bi_add_size(const BigInt* a, const BigInt* b) {
    return (a->size > b->size ? a->size : b->size) + 1;
}

// Return number of limbs needed for result of a - b
int32_t bi_sub_size(const BigInt* a, const BigInt* b) {
    return (a->size > b->size ? a->size : b->size) + 1;
}

// Return number of limbs needed for negation
int32_t bi_neg_size(const BigInt* a) { return a->size; }

// Helper: add magnitudes, result in out (assumes out has enough space)
static void add_mag(BigInt* out, const BigInt* a, const BigInt* b) {
    int32_t n = a->size > b->size ? a->size : b->size;
    uint64_t carry = 0;
    for (int32_t i = 0; i < n; i++) {
        uint64_t av = i < a->size ? a->limbs[i] : 0;
        uint64_t bv = i < b->size ? b->limbs[i] : 0;
        __uint128_t sum = (__uint128_t)av + bv + carry;
        out->limbs[i] = (uint64_t)sum;
        carry = sum >> 64;
    }
    if (carry) { out->limbs[n] = carry; out->size = n + 1; }
    else out->size = n;
}

// Helper: compare magnitudes, return -1/0/1
static int cmp_mag(const BigInt* a, const BigInt* b) {
    if (a->size != b->size) return a->size > b->size ? 1 : -1;
    for (int32_t i = a->size - 1; i >= 0; i--)
        if (a->limbs[i] != b->limbs[i]) return a->limbs[i] > b->limbs[i] ? 1 : -1;
    return 0;
}

// Helper: subtract magnitudes (|a| >= |b|), result in out
static void sub_mag(BigInt* out, const BigInt* a, const BigInt* b) {
    int32_t n = a->size;
    uint64_t borrow = 0;
    for (int32_t i = 0; i < n; i++) {
        uint64_t av = a->limbs[i];
        uint64_t bv = i < b->size ? b->limbs[i] : 0;
        uint64_t diff = av - bv - borrow;
        borrow = (av < bv + borrow) ? 1 : 0;
        out->limbs[i] = diff;
    }
    // Normalize: remove leading zeros
    while (n > 0 && out->limbs[n-1] == 0) n--;
    out->size = n;
}

// out = a + b (out must have bi_add_size(a,b) limbs allocated)
void bi_add(BigInt* out, const BigInt* a, const BigInt* b) {
    if (a->neg == b->neg) {
        add_mag(out, a, b);
        out->neg = a->neg;
    } else {
        int c = cmp_mag(a, b);
        if (c >= 0) { sub_mag(out, a, b); out->neg = a->neg; }
        else { sub_mag(out, b, a); out->neg = b->neg; }
    }
    if (out->size == 0) out->neg = 0;  // normalize -0 to 0
}

// out = a - b
void bi_sub(BigInt* out, const BigInt* a, const BigInt* b) {
    // a - b = a + (-b)
    BigInt tmp = { b->size, b->neg ^ 1 };  // flip sign (limbs shared)
    // Can't use tmp directly since limbs isn't copied; inline the logic
    if (a->neg != b->neg) {  // a - b where signs differ = a + |b| or -|a| - |b|
        add_mag(out, a, b);
        out->neg = a->neg;
    } else {
        int c = cmp_mag(a, b);
        if (c >= 0) { sub_mag(out, a, b); out->neg = a->neg; }
        else { sub_mag(out, b, a); out->neg = a->neg ^ 1; }
    }
    if (out->size == 0) out->neg = 0;
}

// out = -a
void bi_neg(BigInt* out, const BigInt* a) {
    bi_copy(out, a);
    if (out->size > 0) out->neg ^= 1;
}

// Return 1 if zero, 0 otherwise
int32_t bi_is_zero(const BigInt* a) { return a->size == 0 ? 1 : 0; }

// Print bigint to stdout
void bi_print(const BigInt* v) {
    if (v->size == 0) { putchar('0'); putchar('\n'); return; }
    // Convert to decimal (simple but slow)
    uint64_t tmp[256];
    int32_t n = v->size;
    memcpy(tmp, v->limbs, n * sizeof(uint64_t));
    char buf[1024]; int pos = 0;
    while (n > 0) {
        __uint128_t rem = 0;
        for (int32_t i = n - 1; i >= 0; i--) {
            __uint128_t cur = (rem << 64) | tmp[i];
            tmp[i] = cur / 10;
            rem = cur % 10;
        }
        buf[pos++] = '0' + rem;
        while (n > 0 && tmp[n-1] == 0) n--;
    }
    if (v->neg) putchar('-');
    while (pos > 0) putchar(buf[--pos]);
    putchar('\n');
}

// Parse string to bigint (out must have enough space)
void bi_from_str(BigInt* out, const char* s) {
    out->size = 0; out->neg = 0;
    if (*s == '-') { out->neg = 1; s++; }
    else if (*s == '+') s++;
    while (*s) {
        // Multiply by 10 and add digit
        uint64_t carry = *s++ - '0';
        for (int32_t i = 0; i < out->size; i++) {
            __uint128_t p = (__uint128_t)out->limbs[i] * 10 + carry;
            out->limbs[i] = (uint64_t)p;
            carry = p >> 64;
        }
        if (carry) out->limbs[out->size++] = carry;
    }
    if (out->size == 0) out->neg = 0;
}

// Estimate limbs needed for a decimal string
int32_t bi_str_size(const char* s) {
    if (*s == '-' || *s == '+') s++;
    int len = strlen(s);
    return (len * 4 + 63) / 64 + 1;  // ~3.32 bits per digit, round up
}

// Buffer size in bytes for n limbs
int32_t bi_buf_size(int32_t limbs) {
    return sizeof(BigInt) + limbs * sizeof(uint64_t);
}

}
