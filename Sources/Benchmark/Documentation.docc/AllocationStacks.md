# Finding Allocation Sites

Record the stack trace of every allocation a benchmark makes and list the call sites by allocation count.

## Overview

The malloc metrics tell you *how many* allocations a benchmark makes; `--allocation-stacks` tells you *where* they come from:

```
swift package benchmark run --allocation-stacks --target MyBenchmarks --filter "Encode.*"
```

After the regular results, each benchmark's unique allocation stacks are printed, highest count first:

```
Allocations: MyBenchmarks:Encode - 1,000 iterations, 3,000 allocations (3.0/iteration), 72.0 KB, 2 unique stacks

#1  2,000 allocations (2.0/iteration), 66.7%, 48.0 KB
    0  swift_allocObject in libswiftCore.dylib
    1  Node.__allocating_init(_:) in MyBenchmarks
    2  Encoder.makeNode() at Sources/MyLib/Encoder.swift:33
    3  closure #1 in closure #1 in variable initialization expression of benchmarks at Benchmarks/MyBenchmarks/MyBenchmarks.swift:62

#2  1,000 allocations (1.0/iteration), 33.3%, 24.0 KB
    0  swift_slowAlloc in libswiftCore.dylib
    1  swift_task_createNullaryContinuationJob in libswift_Concurrency.dylib
    2  static Task<>.yield() in libswift_Concurrency.dylib
    3  Encoder.flush() [async] at Sources/MyLib/Encoder.swift:44
    4  closure #2 in closure #1 in variable initialization expression of benchmarks [async] at Benchmarks/MyBenchmarks/MyBenchmarks.swift:67
```

Only the measured region is recorded. Warmup iterations and anything before `startMeasurement()` / after `stopMeasurement()` are excluded.

### Options

- term `--allocation-stacks`: Record and print the allocation stacks.
- term `--allocation-stack-depth <depth>`: The maximum number of frames captured per stack, default is 64. Deeper stacks are truncated at the innermost frames.
- term `--allocation-stack-limit <limit>`: The maximum number of stacks printed per benchmark, `0` for all, default is 20.

With `--format markdown` the stacks are printed as markdown. With `--path <path>` the full reports are also written as JSON, one `<target>.<benchmark>.allocations.json` file per benchmark (with `--path stdout`, only the JSON is printed).

### Overhead and metrics

Capturing a stack trace makes each allocation several microseconds slower and allocates itself, so this is a diagnostic mode:

- Only the `mallocCountTotal` and `mallocBytesCount` metrics are measured.
- It can only be used with the `run` command not with baseline or threshold operations.

### Requirements

- The `MallocInterposer` trait (enabled by default).
- A toolchain providing the Swift `Runtime` module, and on Apple platforms macOS 26 or later.

### Getting useful stacks

- Stacks are walked using frame pointers, which Swift code keeps by default. C or C++ dependencies built without frame pointers can cut stacks short.
- File and line information needs debug info; the default release build of benchmarks includes it. Frames without it show the image name instead.
- Inlining merges frames: an allocation in an inlined function is attributed to its caller.
