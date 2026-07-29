// bench_malloc.c — standalone wallclock benchmark for malloc/free patterns.
//
// Build once, run twice (with and without jemalloc injected via
// DYLD_INSERT_LIBRARIES on macOS / LD_PRELOAD on Linux). See
// scripts/bench_malloc.sh.
//
// Each benchmark runs an inner loop N times; we run K trials of that and
// report min / median / max ns per op so noise is visible.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define WARMUP_ITERS 1000
#define TRIALS 9   // odd → median is a single sample

// Volatile sink prevents the compiler from optimizing alloc/free pairs away.
static volatile void *sink;

static double now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1e9 + (double)ts.tv_nsec;
}

static int cmp_double(const void *a, const void *b) {
    double da = *(const double *)a, db = *(const double *)b;
    return (da > db) - (da < db);
}

// ---- benchmark bodies ----

#define DEFINE_BENCH(NAME, BODY)                  \
    static void bench_##NAME(int iters) {         \
        for (int _i = 0; _i < iters; _i++) {      \
            BODY                                  \
        }                                         \
    }

DEFINE_BENCH(malloc_64, {
    void *p = malloc(64); sink = p; free(p);
})

DEFINE_BENCH(malloc_2mb, {
    void *p = malloc(2 * 1024 * 1024); sink = p; free(p);
})

DEFINE_BENCH(calloc_8x8, {
    void *p = calloc(8, 8); sink = p; free(p);
})

DEFINE_BENCH(realloc_grow, {
    void *p = malloc(64);
    p = realloc(p, 256);
    sink = p;
    free(p);
})

DEFINE_BENCH(realloc_null, {
    void *p = realloc(NULL, 128); sink = p; free(p);
})

DEFINE_BENCH(posix_memalign_1k, {
    void *p = NULL;
    (void)posix_memalign(&p, 64, 1024);
    sink = p;
    free(p);
})

DEFINE_BENCH(malloc_x16, {
    void *ptrs[16];
    for (int i = 0; i < 16; i++) ptrs[i] = malloc(48);
    sink = ptrs[0]; // defeat clang's malloc/free elision at -O2
    for (int i = 0; i < 16; i++) free(ptrs[i]);
})

// ---- runner ----

typedef void (*bench_fn)(int);

typedef struct {
    const char *name;
    bench_fn    fn;
    int         inner;   // iterations inside one trial
} bench_t;

#define B(NAME, INNER) { #NAME, bench_##NAME, INNER }

static const bench_t benchmarks[] = {
    B(malloc_64,           1000000),
    B(calloc_8x8,          1000000),
    B(realloc_null,        1000000),
    B(realloc_grow,         500000),
    B(posix_memalign_1k,   1000000),
    B(malloc_x16,           200000),
    B(malloc_2mb,            10000),
};

int main(void) {
    const char *label = getenv("BENCH_LABEL");
    if (!label) label = "(no label)";

    printf("== %s ==\n", label);
    printf("%-22s %12s %12s %12s\n", "benchmark", "min ns/op", "median ns/op", "max ns/op");
    printf("%-22s %12s %12s %12s\n", "---------", "---------", "------------", "---------");

    size_t n = sizeof(benchmarks) / sizeof(benchmarks[0]);
    for (size_t i = 0; i < n; i++) {
        const bench_t *b = &benchmarks[i];

        // Warmup
        b->fn(WARMUP_ITERS);

        double trials[TRIALS];
        for (int t = 0; t < TRIALS; t++) {
            double t0 = now_ns();
            b->fn(b->inner);
            double t1 = now_ns();
            trials[t] = (t1 - t0) / (double)b->inner;
        }
        qsort(trials, TRIALS, sizeof(double), cmp_double);

        printf("%-22s %12.2f %12.2f %12.2f\n",
               b->name, trials[0], trials[TRIALS / 2], trials[TRIALS - 1]);
    }
    return 0;
}
