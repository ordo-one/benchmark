#include <stdatomic.h>
#include <stdint.h>
#include <stddef.h>

#include "SwiftRuntimeHooks.h"

typedef struct HeapObject_s HeapObject;
typedef struct HeapMetadata_s HeapMetadata;

extern HeapObject * (*_swift_allocObject)(HeapMetadata const *metadata,
                                          size_t requiredSize,
                                          size_t requiredAlignmentMask);

extern HeapObject * (*_swift_retain)(HeapObject*);
extern HeapObject * (*_swift_release)(HeapObject*);

extern HeapObject * (*_swift_tryRetain)(HeapObject*);

// unclear if the following two needs hooking and they don't seem to be called on Apple Silicon
extern HeapObject * (*_swift_retain_n)(HeapObject *object, uint32_t n);
extern HeapObject * (*_swift_release_n)(HeapObject *object, uint32_t n);

// The runtime's function pointers are read by every thread in the process, so a
// thread can be inside a shim while another thread removes the hook. The shims
// must therefore stay callable after removal:
//
//  - the saved originals are captured on first install and never cleared, so a
//    straggler calls the real runtime function;
//  - `hook` is never NULL: removal swaps in a no-op instead of clearing it;
//  - `context` is stored before `hook` (release) and read after it (acquire),
//    so a shim never pairs a hook with the wrong context;
//  - the runtime's pointer is published last on install and restored first on
//    removal, with release ordering.
//
// The runtime pointer variables are plain globals declared by the runtime, so
// they are stored through the __atomic builtins rather than being _Atomic.

// Since Swift 6.1 the runtime's swift_retain/swift_release (and their variants)
// only dispatch through the overridable pointers while this flag is set. The
// runtime sets it itself the first time swift_allocObject sees an overridden
// pointer, so retains made before the first allocation after hooking were not
// counted. Setting it on install closes that gap and clearing it on removal
// restores the runtime's fast path. Allocation is not gated.
//
// The symbol is absent from older runtimes. On Linux a weak reference resolves
// to NULL there. On Darwin a weak_import still needs the symbol in the SDK's
// stub library, which pre-6.1 SDKs lack, so look it up at runtime instead.
#if __APPLE__
#include <dlfcn.h>

static _Bool * _swift_refcount_swizzling_flag(void) {
    static _Bool * flag = NULL;
    static _Bool resolved = 0;
    if (!resolved) {
        flag = dlsym(RTLD_DEFAULT, "_swift_enableSwizzlingOfAllocationAndRefCountingFunctions_forInstrumentsOnly");
        resolved = 1;
    }
    return flag;
}
#else
extern _Bool _swift_enableSwizzlingOfAllocationAndRefCountingFunctions_forInstrumentsOnly __attribute__((weak));

static _Bool * _swift_refcount_swizzling_flag(void) {
    return &_swift_enableSwizzlingOfAllocationAndRefCountingFunctions_forInstrumentsOnly;
}
#endif

// Number of installed hooks that need the flag (retain and release). The set_*
// functions are only called from the benchmark thread, so a plain counter is
// enough; the flag itself is read by every thread.
static int _swift_refcount_hook_users = 0;

static void _swift_refcount_hooks_set_enabled(_Bool enabled) {
    _Bool * flag = _swift_refcount_swizzling_flag();
    if (flag != NULL) {
        __atomic_store_n(flag, enabled, __ATOMIC_RELEASE);
    }
}

int swift_runtime_refcount_swizzling_state(void) {
    _Bool * flag = _swift_refcount_swizzling_flag();
    if (flag == NULL) {
        return -1;
    }
    return __atomic_load_n(flag, __ATOMIC_ACQUIRE) ? 1 : 0;
}

static void _swift_refcount_hooks_add_user(void) {
    if (_swift_refcount_hook_users++ == 0) {
        _swift_refcount_hooks_set_enabled(1);
    }
}

static void _swift_refcount_hooks_remove_user(void) {
    if (_swift_refcount_hook_users > 0 && --_swift_refcount_hook_users == 0) {
        _swift_refcount_hooks_set_enabled(0);
    }
}

static void _swift_runtime_noop_hook(const void * object, void * context) {
    (void)object;
    (void)context;
}

struct hook_data_s {
    HeapObject * (*orig)(HeapObject*);
    HeapObject * (*origTry)(HeapObject*);
    HeapObject * (*orig_n)(HeapObject*, uint32_t);
    _Atomic(swift_runtime_hook_t) hook;
    _Atomic(void *) context;
};

struct hook_data_alloc_s {
    HeapObject * (*orig)(HeapMetadata const *, size_t, size_t);
    _Atomic(swift_runtime_hook_t) hook;
    _Atomic(void *) context;
};

#define SET_HOOK_DATA(data, hook_fn, ctx)                                           \
    do {                                                                            \
        atomic_store_explicit(&(data).context, (ctx), memory_order_relaxed);        \
        atomic_store_explicit(&(data).hook, (hook_fn), memory_order_release);       \
    } while (0)

#define CALL_HOOK(data, object)                                                     \
    do {                                                                            \
        swift_runtime_hook_t hook_ = atomic_load_explicit(&(data).hook, memory_order_acquire); \
        void * context_ = atomic_load_explicit(&(data).context, memory_order_relaxed); \
        (*hook_)((object), context_);                                               \
    } while (0)

#define PUBLISH(runtime_pointer, fn) __atomic_store_n(&(runtime_pointer), (fn), __ATOMIC_RELEASE)

/*===========================================================================*/

static struct hook_data_alloc_s _swift_alloc_object_hook_data = {NULL, _swift_runtime_noop_hook, NULL};

static HeapObject * _swift_alloc_object_hook(HeapMetadata const *metadata,
                                             size_t requiredSize,
                                             size_t requiredAlignmentMask) {
    HeapObject * ret = (*_swift_alloc_object_hook_data.orig)(metadata, requiredSize, requiredAlignmentMask);
    CALL_HOOK(_swift_alloc_object_hook_data, ret);
    return ret;
}

void swift_runtime_set_alloc_object_hook(swift_runtime_hook_t hook, void * context) {
    if (hook == NULL) {
        if (_swift_alloc_object_hook_data.orig != NULL) {
            PUBLISH(_swift_allocObject, _swift_alloc_object_hook_data.orig);
        }
        SET_HOOK_DATA(_swift_alloc_object_hook_data, _swift_runtime_noop_hook, NULL);
    } else {
        if (_swift_alloc_object_hook_data.orig == NULL) {
            _swift_alloc_object_hook_data.orig = _swift_allocObject;
        }
        SET_HOOK_DATA(_swift_alloc_object_hook_data, hook, context);
        PUBLISH(_swift_allocObject, _swift_alloc_object_hook);
    }
}
/*===========================================================================*/

static struct hook_data_s _swift_retain_hook_data = {NULL, NULL, NULL, _swift_runtime_noop_hook, NULL};

static HeapObject * _swift_retain_hook(HeapObject * heapObject) {
    HeapObject * ret = (*_swift_retain_hook_data.orig)(heapObject);
    CALL_HOOK(_swift_retain_hook_data, heapObject);
    return ret;
}

// This doesn't seem to be called for Apple Silicon at least, but keeping it here
static HeapObject * _swift_tryRetain_hook(HeapObject * heapObject) {
    HeapObject * ret = (*_swift_retain_hook_data.origTry)(heapObject);
    if (ret != NULL) {
        CALL_HOOK(_swift_retain_hook_data, heapObject);
    }
    return ret;
}

// This doesn't seem to be called for Apple Silicon at least, but keeping it here
static HeapObject * _swift_retain_n_hook(HeapObject * heapObject, uint32_t n) {
    uint32_t i;
    HeapObject * ret = (*_swift_retain_hook_data.orig_n)(heapObject, n);
    for (i = 0; i < n; i++) {
        CALL_HOOK(_swift_retain_hook_data, heapObject);
    }
    return ret;
}

void swift_runtime_set_retain_hook(swift_runtime_hook_t hook, void * context) {
    if (hook == NULL) {
        _swift_refcount_hooks_remove_user();
        if (_swift_retain_hook_data.orig != NULL) {
            PUBLISH(_swift_retain, _swift_retain_hook_data.orig);
            PUBLISH(_swift_tryRetain, _swift_retain_hook_data.origTry);
            PUBLISH(_swift_retain_n, _swift_retain_hook_data.orig_n);
        }
        SET_HOOK_DATA(_swift_retain_hook_data, _swift_runtime_noop_hook, NULL);
    } else {
        if (_swift_retain_hook_data.orig == NULL) {
            _swift_retain_hook_data.orig = _swift_retain;
            _swift_retain_hook_data.origTry = _swift_tryRetain;
            _swift_retain_hook_data.orig_n = _swift_retain_n;
        }
        SET_HOOK_DATA(_swift_retain_hook_data, hook, context);
        PUBLISH(_swift_retain, _swift_retain_hook);
        PUBLISH(_swift_tryRetain, _swift_tryRetain_hook);
        PUBLISH(_swift_retain_n, _swift_retain_n_hook);
        _swift_refcount_hooks_add_user();
    }
}

/*===========================================================================*/

static struct hook_data_s _swift_release_hook_data = {NULL, NULL, NULL, _swift_runtime_noop_hook, NULL};

static HeapObject * _swift_release_hook(HeapObject * heapObject) {
    HeapObject * ret = (*_swift_release_hook_data.orig)(heapObject);
    CALL_HOOK(_swift_release_hook_data, heapObject);
    return ret;
}

// This doesn't seem to be called for Apple Silicon at least, but keeping it here
static HeapObject * _swift_release_n_hook(HeapObject * heapObject, uint32_t n) {
    uint32_t i;
    HeapObject * ret = (*_swift_release_hook_data.orig_n)(heapObject, n);
    for (i = 0; i < n; i++) {
        CALL_HOOK(_swift_release_hook_data, heapObject);
    }
    return ret;
}

void swift_runtime_set_release_hook(swift_runtime_hook_t hook, void * context) {
    if (hook == NULL) {
        _swift_refcount_hooks_remove_user();
        if (_swift_release_hook_data.orig != NULL) {
            PUBLISH(_swift_release, _swift_release_hook_data.orig);
            PUBLISH(_swift_release_n, _swift_release_hook_data.orig_n);
        }
        SET_HOOK_DATA(_swift_release_hook_data, _swift_runtime_noop_hook, NULL);
    } else {
        if (_swift_release_hook_data.orig == NULL) {
            _swift_release_hook_data.orig = _swift_release;
            _swift_release_hook_data.orig_n = _swift_release_n;
        }
        SET_HOOK_DATA(_swift_release_hook_data, hook, context);
        PUBLISH(_swift_release, _swift_release_hook);
        PUBLISH(_swift_release_n, _swift_release_n_hook);
        _swift_refcount_hooks_add_user();
    }
}

/*===========================================================================*/

// Darwin lazily allocates _Thread_local storage with malloc on a thread's first
// access, which would re-enter the allocation hook before its guard is set, so
// use a pthread key there (pthread_getspecific/setspecific use static slots).
// On Linux __thread in the executable is static TLS and never allocates.
#if __APPLE__
#include <pthread.h>

static pthread_key_t _allocation_hook_state_key;
static pthread_once_t _allocation_hook_state_once = PTHREAD_ONCE_INIT;

static void _allocation_hook_state_create_key(void) {
    pthread_key_create(&_allocation_hook_state_key, NULL);
}

void benchmark_allocation_hook_state_initialize(void) {
    pthread_once(&_allocation_hook_state_once, _allocation_hook_state_create_key);
}

uintptr_t benchmark_allocation_hook_state_get(void) {
    return (uintptr_t)pthread_getspecific(_allocation_hook_state_key);
}

void benchmark_allocation_hook_state_set(uintptr_t state) {
    pthread_setspecific(_allocation_hook_state_key, (const void *)state);
}
#else
static __thread uintptr_t _allocation_hook_state = 0;

void benchmark_allocation_hook_state_initialize(void) {}

uintptr_t benchmark_allocation_hook_state_get(void) {
    return _allocation_hook_state;
}

void benchmark_allocation_hook_state_set(uintptr_t state) {
    _allocation_hook_state = state;
}
#endif
