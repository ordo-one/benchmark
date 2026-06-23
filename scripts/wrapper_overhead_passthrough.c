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

// On Linux we resolve the real libc functions via dlsym(RTLD_NEXT, …) and
// cache the function pointers. The wrinkle: dlsym itself can call calloc
// internally during symbol resolution, which would recurse back into our
// hooks. We guard against that with a thread-local "in dlsym" flag and a
// small static bootstrap buffer that absorbs any allocations made while
// resolving.
//
// After resolution completes (which happens during the constructor, before
// the bench's hot loop runs), the steady-state hot path is just:
//     ldr  x_real_fn
//     blr  x_real_fn
// — one load, one indirect call. Same shape as glibc's own PLT stub, so
// the wrapper-layer cost is just the extra branch.

#define _GNU_SOURCE
#include <dlfcn.h>
#include <string.h>

static void *(*real_malloc)(size_t)         = NULL;
static void  (*real_free)(void *)           = NULL;
static void *(*real_calloc)(size_t, size_t) = NULL;
static void *(*real_realloc)(void *, size_t)= NULL;

// TLS guard: set while we're inside dlsym so any reentrant malloc/calloc/
// realloc/free calls go to the bootstrap path instead of recursing.
static __thread int g_in_resolve = 0;

// Small static buffer for allocations made during dlsym resolution.
// 64 KiB is more than enough — dlsym typically allocates only a handful of
// small objects during the first call.
static char   g_boot_mem[64 * 1024];
static size_t g_boot_off = 0;

static int boot_owns(const void *p) {
    return (const char *)p >= g_boot_mem &&
           (const char *)p <  g_boot_mem + sizeof(g_boot_mem);
}

static void *boot_alloc(size_t n) {
    size_t aligned = (n + 15) & ~(size_t)15;
    if (g_boot_off + aligned > sizeof(g_boot_mem)) return NULL;
    void *p = g_boot_mem + g_boot_off;
    g_boot_off += aligned;
    return p;
}

static void resolve_real(void) {
    g_in_resolve = 1;
    real_malloc  = dlsym(RTLD_NEXT, "malloc");
    real_free    = dlsym(RTLD_NEXT, "free");
    real_calloc  = dlsym(RTLD_NEXT, "calloc");
    real_realloc = dlsym(RTLD_NEXT, "realloc");
    g_in_resolve = 0;
}

__attribute__((constructor)) static void preresolve(void) {
    resolve_real();
}

void *malloc(size_t s) {
    if (__builtin_expect(real_malloc != NULL, 1)) return real_malloc(s);
    if (g_in_resolve) return boot_alloc(s);
    resolve_real();
    return real_malloc ? real_malloc(s) : boot_alloc(s);
}

void free(void *p) {
    if (!p) return;
    if (boot_owns(p)) return;       // bootstrap blocks have no underlying chunk
    if (__builtin_expect(real_free != NULL, 1)) { real_free(p); return; }
    if (g_in_resolve) return;
    resolve_real();
    if (real_free) real_free(p);
}

void *calloc(size_t n, size_t s) {
    if (__builtin_expect(real_calloc != NULL, 1)) return real_calloc(n, s);
    if (g_in_resolve) {
        void *p = boot_alloc(n * s);
        if (p) memset(p, 0, n * s);
        return p;
    }
    resolve_real();
    if (real_calloc) return real_calloc(n, s);
    void *p = boot_alloc(n * s);
    if (p) memset(p, 0, n * s);
    return p;
}

void *realloc(void *p, size_t s) {
    if (boot_owns(p)) {
        // Can't realloc a bootstrap allocation in place; copy out via malloc.
        void *np = malloc(s);
        if (np && p) memcpy(np, p, s);
        return np;
    }
    if (__builtin_expect(real_realloc != NULL, 1)) return real_realloc(p, s);
    if (g_in_resolve) return boot_alloc(s);
    resolve_real();
    return real_realloc ? real_realloc(p, s) : boot_alloc(s);
}

#endif
