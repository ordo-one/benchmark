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

struct hook_data_s {
    HeapObject * (*orig)(HeapObject*);
    HeapObject * (*origTry)(HeapObject*);
    HeapObject * (*orig_n)(HeapObject*, uint32_t);
    swift_runtime_hook_t hook;
    void * context;
};

struct hook_data_alloc_s {
    HeapObject * (*orig)(HeapMetadata const *, size_t, size_t);
    swift_runtime_hook_t hook;
    void * context;
};

/*===========================================================================*/

static struct hook_data_alloc_s _swift_alloc_object_hook_data = {NULL, NULL, NULL};

static HeapObject * _swift_alloc_object_hook(HeapMetadata const *metadata,
                                             size_t requiredSize,
                                             size_t requiredAlignmentMask) {
    HeapObject * ret = (*_swift_alloc_object_hook_data.orig)(metadata, requiredSize, requiredAlignmentMask);
    (*_swift_alloc_object_hook_data.hook)(ret, _swift_alloc_object_hook_data.context);
    return ret;
}

void swift_runtime_set_alloc_object_hook(swift_runtime_hook_t hook, void * context) {
    if (hook == NULL) {
        _swift_allocObject = _swift_alloc_object_hook_data.orig;
        struct hook_data_alloc_s hook_data = {NULL, NULL, NULL};
        _swift_alloc_object_hook_data = hook_data;
    } else {
        struct hook_data_alloc_s hook_data = {_swift_allocObject, hook, context};
        _swift_alloc_object_hook_data = hook_data;
        _swift_allocObject = _swift_alloc_object_hook;
    }
}
/*===========================================================================*/

static struct hook_data_s _swift_retain_hook_data = {NULL, NULL, NULL, NULL, NULL};

static HeapObject * _swift_retain_hook(HeapObject * heapObject) {
    HeapObject * ret = (*_swift_retain_hook_data.orig)(heapObject);
    (*_swift_retain_hook_data.hook)(heapObject, _swift_retain_hook_data.context);
    return ret;
}

// This doesn't seem to be called for Apple Silicon at least, but keeping it here
static HeapObject * _swift_tryRetain_hook(HeapObject * heapObject) {
    HeapObject * ret = (*_swift_retain_hook_data.origTry)(heapObject);
    if (ret != NULL) {
        (*_swift_retain_hook_data.hook)(heapObject, _swift_retain_hook_data.context);
    }
    return ret;
}

// This doesn't seem to be called for Apple Silicon at least, but keeping it here
static HeapObject * _swift_retain_n_hook(HeapObject * heapObject, uint32_t n) {
    int i;
    HeapObject * ret = (*_swift_retain_hook_data.orig_n)(heapObject, n);
    for (i = 0; i < n; i++) {
        (*_swift_retain_hook_data.hook)(heapObject, _swift_retain_hook_data.context);
    }
    return ret;
}

void swift_runtime_set_retain_hook(swift_runtime_hook_t hook, void * context) {
    if (hook == NULL) {
        _swift_retain = _swift_retain_hook_data.orig;
        _swift_tryRetain = _swift_retain_hook_data.origTry;
        _swift_retain_n = _swift_retain_hook_data.orig_n;
        struct hook_data_s hook_data = {NULL, NULL, NULL, NULL, NULL};
        _swift_retain_hook_data = hook_data;
    } else {
        struct hook_data_s hook_data = {_swift_retain, _swift_tryRetain, _swift_retain_n, hook, context};
        _swift_retain_hook_data = hook_data;
        _swift_retain = _swift_retain_hook;
        _swift_tryRetain = _swift_tryRetain_hook;
        _swift_retain_n = _swift_retain_n_hook;
    }
}

/*===========================================================================*/

static struct hook_data_s _swift_release_hook_data = {NULL, NULL, NULL, NULL, NULL};

static HeapObject * _swift_release_hook(HeapObject * heapObject) {
    HeapObject * ret = (*_swift_release_hook_data.orig)(heapObject);
    (*_swift_release_hook_data.hook)(heapObject, _swift_release_hook_data.context);
    return ret;
}

// This doesn't seem to be called for Apple Silicon at least, but keeping it here
static HeapObject * _swift_release_n_hook(HeapObject * heapObject, uint32_t n) {
    int i;
    HeapObject * ret = (*_swift_release_hook_data.orig_n)(heapObject, n);
    for (i = 0; i < n; i++) {
        (*_swift_release_hook_data.hook)(heapObject, _swift_release_hook_data.context);
    }
    return ret;
}

void swift_runtime_set_release_hook(swift_runtime_hook_t hook, void * context) {
    if (hook == NULL) {
        _swift_release = _swift_release_hook_data.orig;
        _swift_release_n = _swift_release_hook_data.orig_n;
        struct hook_data_s hook_data = {NULL, NULL, NULL, NULL, NULL};
        _swift_release_hook_data = hook_data;
    } else {
        struct hook_data_s hook_data = {_swift_release, NULL, _swift_release_n, hook, context};
        _swift_release_hook_data = hook_data;
        _swift_release = _swift_release_hook;
        _swift_release_n = _swift_release_n_hook;
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
