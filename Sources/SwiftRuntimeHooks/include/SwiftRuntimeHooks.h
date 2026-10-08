#ifndef PACKAGE_BENCHMARK_SWIFT_RUNTIME_HOOKS_H
#define PACKAGE_BENCHMARK_SWIFT_RUNTIME_HOOKS_H

#include <stdint.h>

typedef void (*swift_runtime_hook_t)(const void *, void *);

void swift_runtime_set_alloc_object_hook(swift_runtime_hook_t hook, void * context);
void swift_runtime_set_retain_hook(swift_runtime_hook_t hook, void * context);
void swift_runtime_set_release_hook(swift_runtime_hook_t hook, void * context);

// Per-thread word used by the allocation-stack hook: its recursion guard and a
// pointer to the thread's recorder. Reading and writing it never allocates —
// the hook runs inside malloc, so an allocating TLS access would re-enter it.
// Call benchmark_allocation_hook_state_initialize() before installing the hook.
void benchmark_allocation_hook_state_initialize(void);
uintptr_t benchmark_allocation_hook_state_get(void);
void benchmark_allocation_hook_state_set(uintptr_t state);

#endif
