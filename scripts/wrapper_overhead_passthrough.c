// wrapper_overhead_passthrough.c — a bare malloc/free interposer that does
// NOTHING beyond what an empty wrapper does. No header, no counters, no
// enable check, no TLS, no atomics. Each replacement_* is a single-
// instruction tail call to libc.
//
// Used by wrapper_overhead.sh to isolate the cost of the wrapper layer
// itself — independent of any bookkeeping you might layer on top.
//
// macOS path: DYLD_INTERPOSE entries route malloc/free through us via
// the standard __DATA,__interpose section. Internal calls to malloc/free
// inside this dylib resolve directly to libsystem.
//
// Linux path: defining `malloc` / `free` in an LD_PRELOAD'd shared object
// overrides the global symbol resolution. We forward to the real libc
// entries via dlsym(RTLD_NEXT, …). The resolve dance is a small one-time
// cost amortised away after warmup, so it doesn't pollute the measurement.

#include <stdlib.h>

#if defined(__APPLE__)

#define DYLD_INTERPOSE(_replacement, _replacee)                                 \
    __attribute__((used)) static struct {                                       \
        const void *replacement;                                                \
        const void *replacee;                                                   \
    } _interpose_##_replacee __attribute__((section("__DATA,__interpose"))) = { \
        (const void *)&_replacement, (const void *)&_replacee                   \
    };

void *replacement_malloc(size_t size)                  { return malloc(size);          }
void  replacement_free(void *p)                        { free(p);                       }
void *replacement_calloc(size_t n, size_t s)           { return calloc(n, s);           }
void *replacement_realloc(void *p, size_t s)           { return realloc(p, s);          }
void *replacement_reallocf(void *p, size_t s)          { return reallocf(p, s);         }
void *replacement_valloc(size_t s)                     { return valloc(s);              }
int   replacement_posix_memalign(void **m, size_t a, size_t s) {
    return posix_memalign(m, a, s);
}

DYLD_INTERPOSE(replacement_malloc,        malloc)
DYLD_INTERPOSE(replacement_free,          free)
DYLD_INTERPOSE(replacement_calloc,        calloc)
DYLD_INTERPOSE(replacement_realloc,       realloc)
DYLD_INTERPOSE(replacement_reallocf,      reallocf)
DYLD_INTERPOSE(replacement_valloc,        valloc)
DYLD_INTERPOSE(replacement_posix_memalign, posix_memalign)

#else  /* Linux */

#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdatomic.h>
#include <string.h>

static _Atomic(void *(*)(size_t))            g_real_malloc;
static _Atomic(void  (*)(void *))            g_real_free;
static _Atomic(void *(*)(size_t, size_t))    g_real_calloc;
static _Atomic(void *(*)(void *, size_t))    g_real_realloc;

// Small recursion buffer for the rare case where dlsym itself allocates
// before we've resolved the real symbols. ~1 MiB is plenty.
static char         g_bootstrap[1024 * 1024];
static _Atomic size_t g_bootstrap_off = 0;
static int          bootstrap_owns(void *p) {
    return (char *)p >= g_bootstrap &&
           (char *)p <  g_bootstrap + sizeof(g_bootstrap);
}
static void *bootstrap_alloc(size_t n) {
    size_t aligned = (n + 15) & ~(size_t)15;
    size_t off = atomic_fetch_add_explicit(&g_bootstrap_off, aligned,
                                           memory_order_relaxed);
    if (off + aligned > sizeof(g_bootstrap)) return NULL;
    return g_bootstrap + off;
}

#define REAL(_fn) ({                                                          \
    typeof(g_real_##_fn) _r = atomic_load_explicit(&g_real_##_fn,             \
                                                   memory_order_relaxed);     \
    if (!_r) {                                                                \
        _r = dlsym(RTLD_NEXT, #_fn);                                          \
        atomic_store_explicit(&g_real_##_fn, _r, memory_order_relaxed);       \
    }                                                                         \
    _r;                                                                       \
})

void *malloc(size_t s) {
    typeof(g_real_malloc) r = atomic_load_explicit(&g_real_malloc,
                                                   memory_order_relaxed);
    if (!r) {
        r = dlsym(RTLD_NEXT, "malloc");
        if (!r) return bootstrap_alloc(s);
        atomic_store_explicit(&g_real_malloc, r, memory_order_relaxed);
    }
    return r(s);
}

void free(void *p) {
    if (!p || bootstrap_owns(p)) return;
    typeof(g_real_free) r = REAL(free);
    if (r) r(p);
}

void *calloc(size_t n, size_t s) {
    typeof(g_real_calloc) r = atomic_load_explicit(&g_real_calloc,
                                                   memory_order_relaxed);
    if (!r) {
        r = dlsym(RTLD_NEXT, "calloc");
        if (!r) {
            void *p = bootstrap_alloc(n * s);
            if (p) memset(p, 0, n * s);
            return p;
        }
        atomic_store_explicit(&g_real_calloc, r, memory_order_relaxed);
    }
    return r(n, s);
}

void *realloc(void *p, size_t s) {
    if (bootstrap_owns(p)) {
        // Can't realloc a bootstrap allocation in place; copy out.
        void *np = malloc(s);
        if (np && p) memcpy(np, p, s);
        return np;
    }
    return REAL(realloc)(p, s);
}

#endif
