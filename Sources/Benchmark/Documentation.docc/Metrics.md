# Metrics and Thresholds

Benchmarks supports a wide range of benchmark metrics and also allows you to create custom benchmark metrics.

## Overview

A fairly wide range of metrics can be captured by the benchmarks - most metrics are avilable on both macOS and Linux, but a few are not easily obtained and will thus not yield results on that platform, even if specified.

### Metrics

Currently supported metrics are:

- term `cpuUser`: CPU user space time spent for running the test
- term `cpuSystem`: CPU system time spent for running the test
- term `cpuTotal`: CPU total time spent for running the test (system + user)
- term `wallClock`: Wall clock time for running the test
- term `throughput`: The throughput in operations / second
- term `peakMemoryResident`: The resident memory usage - sampled during runtime
- term `peakMemoryResidentDelta`: The resident memory usage - sampled during runtime (excluding start of benchmark baseline) 
- term `peakMemoryVirtual`:  The virtual memory usage - sampled during runtime
- term `mallocCountSmall`: The number of small malloc calls according to the active malloc backend
- term `mallocCountLarge`: The number of large malloc calls according to the active malloc backend
- term `mallocCountTotal`: The total number of malloc calls according to the active malloc backend
- term `freeCountTotal`: The total number of free calls according to the interposer backend
- term `mallocBytesCount`: The total requested bytes allocated through malloc calls according to the interposer backend
- term `mallocFreeDelta`: The number of malloc calls minus free calls according to the interposer backend
- term `allocatedResidentMemory`: The amount of allocated resident memory by the application (not including allocator metadata overhead etc) according to jemalloc
- term `memoryLeaked`: Legacy jemalloc resident-byte growth within the measured region
- term `memoryLeakedBytes`: The requested bytes allocated minus requested bytes freed according to the interposer backend
- term `syscalls`: The number of syscalls made during the test -- macOS only
- term `contextSwitches`: The number of context switches made during the test -- macOS only
- term `threads`: The maximum number of threads in the process under the test (not exact, sampled)
- term `threadsRunning`: The maximum number of threads actually running under the test (not exact, sampled) -- macOS only
- term `readSyscalls`: The number of I/O read syscalls performed e.g. read(2) / pread(2) -- Linux only
- term `writeSyscalls`: The number of I/O write syscalls performed e.g. write(2) / pwrite(2) -- Linux only
- term `readBytesLogical`: The number of bytes read from storage (but may be satisfied by pagecache!) -- Linux only
- term `writeBytesLogical`: The number bytes written to storage (but may be cached) -- Linux only
- term `readBytesPhysical`: The number of bytes physically read from a block device (i.e. disk) -- Linux only
- term `writeBytesPhysical`: The number of bytes physicall written to a block device (i.e. disk) -- Linux only
- term `instructions`: The number of instructions executed -- on Linux using perf_events, for macOS using rusage()
- term `retainCount`: The number of retain calls (ARC)
- term `releaseCount`: The number of release calls (ARC)
- term `retainReleaseDelta`: abs(retainCount - releaseCount) - if this is non-zero, it would typically mean the benchmark has a retain cycle (use Memory Graph Debugger to troubleshoot)

Additionally, _custom metrics_ are supported `custom(_ name: String, polarity: Polarity = .prefersSmaller, useScalingFactor: Bool = true)` as outlined in the writing benchmarks documentation.

### Thresholds

For comparison (`swift package benchmark baseline compare` or `swift package benchmark baseline check`) operations, there's a set of default thresholds that are used which are strict. It is also possible to define both absolute and relative thresholds, _per metric_, that will be used for such comparisons (or that a given metric should be skipped completely).

In addition to comparing the delta between e.g. a `PR` and `main`, there's also an option to compare against an absolute threshold which is useful for more complex projects that may want to reduce the size of the build matrix required to validate all thresholds. 

Absolute thresholds are usually setup with e.g. `.mega(10)` or `.milliseconds(600)`.

See <doc:WritingBenchmarks> or look at the sample code to see how custom thresholds can be set up.
