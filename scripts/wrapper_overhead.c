// wrapper_overhead.c — measure the cost of "being a wrapper" in isolation,
// and (optionally) the additional cost of the real interposer's bookkeeping.
//
// Run the same malloc/free hot loop two or three times:
//   1. With nothing preloaded → user code → libc allocator.
//   2. With wrapper_overhead_passthrough.dylib preloaded → user code → our
//      one-instruction tail-call wrapper → libc allocator.
//      Delta from #1 = wrapper layer cost (no bookkeeping at all).
//   3. (Optional) With the real malloc-interposer preloaded and counting
//      enabled. Delta from #2 = bookkeeping cost (header + magic check +
//      enable check + TLS pointer load + counter writes).
//
// To enable run #3, set INTERPOSER_DYLIB in the environment to the path of
// the full interposer dylib/so. The harness will dlsym
// `malloc_interposer_enable` and call it at startup so counting is on for
// every measured iteration.
//
// Build + drive: see wrapper_overhead.sh in the same directory.

#include <dlfcn.h>
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

    // If the real malloc-interposer is preloaded, flip its counting on so we
    // measure the full bookkeeping cost (header + magic check + enable check
    // + TLS access + counter writes). dlsym returns NULL for the pass-through
    // wrapper and for the plain libc run, which is exactly what we want.
    void (*enable_fn)(void) = (void (*)(void))dlsym(RTLD_DEFAULT,
                                                    "malloc_interposer_enable");
    void (*reset_fn)(void)  = (void (*)(void))dlsym(RTLD_DEFAULT,
                                                    "malloc_interposer_reset");
    if (enable_fn) {
        if (reset_fn) reset_fn();
        enable_fn();
        fprintf(stderr, "[%s] interposer counting enabled\n", label);
    }

    printf("== %s ==\n", label);
    printf("%-18s %10s %10s %10s\n", "size", "min ns", "median", "max ns");
    printf("%-18s %10s %10s %10s\n", "----", "------", "------", "------");

    measure_pair("malloc(64)+free",       64);
    measure_pair("malloc(256)+free",     256);
    measure_pair("malloc(1024)+free",   1024);
    measure_pair("malloc(4096)+free",   4096);
    return 0;
}
