// wrapper_overhead.c — measure the cost of "being a wrapper" in isolation.
//
// Run the same malloc/free hot loop twice:
//   1. With nothing preloaded → user code → libc allocator.
//   2. With wrapper_overhead_passthrough.dylib preloaded → user code → our
//      one-instruction tail-call wrapper → libc allocator.
//
// The wrapper does no bookkeeping at all — its `replacement_malloc` is a
// single `b _malloc` and `replacement_free` is a single `b _free`. So the
// delta between the two runs is purely the cost of inserting one extra
// PLT stub + branch into the call path. Nothing else changes.
//
// Build + drive: see wrapper_overhead.sh in the same directory.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define WARMUP_ITERS   10000
#define INNER_ITERS  2000000
#define TRIALS             9

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

static void measure_pair(const char *name, size_t size) {
    // Warmup primes tcache and lets dyld bind any lazy stubs.
    for (int i = 0; i < WARMUP_ITERS; i++) {
        void *p = malloc(size);
        sink = p;
        free(p);
    }

    double trials[TRIALS];
    for (int t = 0; t < TRIALS; t++) {
        double t0 = now_ns();
        for (int i = 0; i < INNER_ITERS; i++) {
            void *p = malloc(size);
            sink = p;
            free(p);
        }
        trials[t] = (now_ns() - t0) / (double)INNER_ITERS;
    }
    qsort(trials, TRIALS, sizeof(double), cmp_double);

    printf("%-18s %10.2f %10.2f %10.2f\n",
           name, trials[0], trials[TRIALS / 2], trials[TRIALS - 1]);
}

int main(void) {
    const char *label = getenv("BENCH_LABEL");
    if (!label) label = "(no label)";
    printf("== %s ==\n", label);
    printf("%-18s %10s %10s %10s\n", "size", "min ns", "median", "max ns");
    printf("%-18s %10s %10s %10s\n", "----", "------", "------", "------");

    measure_pair("malloc(64)+free",       64);
    measure_pair("malloc(256)+free",     256);
    measure_pair("malloc(1024)+free",   1024);
    measure_pair("malloc(4096)+free",   4096);
    return 0;
}
