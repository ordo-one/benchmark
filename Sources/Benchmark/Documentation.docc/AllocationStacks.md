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
- term `--export-allocation-stacks`: Export the full allocation stack reports. Implies `--allocation-stacks`.
- term `--allocation-stacks-export-format <folded|json>`: Choose the export format, default is `folded`. Requires `--export-allocation-stacks`.
- term `--allocation-stacks-export-path <path>`: The export destination, default is the current directory. Requires `--export-allocation-stacks`. With `--export-allocation-stacks --allocation-stacks-export-path stdout`, only the exported data is printed.
- term `--allocation-stack-depth <depth>`: The maximum number of frames captured per stack, default is 64. Deeper stacks are truncated at the innermost frames.
- term `--allocation-stack-limit <limit>`: The maximum number of stacks printed per benchmark, `0` for all, default is 20.

With `--format markdown` the stacks are printed as markdown. `--allocation-stacks` alone prints reports without exporting them. Export requires `--export-allocation-stacks` and writes only the selected format.

### Folded stack export

With `--export-allocation-stacks`, each benchmark that records allocations writes a `<target>.<benchmark>.allocations.folded` file for flamegraph.pl or speedscope. Use `--allocation-stacks-export-path` to choose the output directory. Grant the command plugin write permission for the destination (`--allow-writing-to-package-directory` for output inside the package, or `--allow-writing-to-directory <path>` for an external directory):

```sh
swift package --allow-writing-to-package-directory benchmark run \
    --export-allocation-stacks --target MyBenchmarks --filter "Encode.*" --allocation-stacks-export-path allocation-stacks
```

The files contain all captured stacks, regardless of `--allocation-stack-limit`. Frames run from the outermost caller to the allocation site, separated by semicolons, with the allocation count at the end:

```
benchmark();encode() at Encoder.swift:33;swift_allocObject in libswiftCore.dylib 2000
benchmark();flush() [async] at Encoder.swift:44;swift_slowAlloc in libswiftCore.dylib 1000
```

Weights are exact allocation totals across all measured iterations, matching the JSON report, independent of `--scale`. Keeping integer run totals preserves rare allocations and compatibility with speedscope. Identical rendered stacks are merged, and equal counts are ordered by their frame labels so output is deterministic. Semicolons inside frame labels become commas and embedded newlines become spaces.

Open the file in [speedscope](https://www.speedscope.app), or render it with [FlameGraph](https://github.com/brendangregg/FlameGraph):

```sh
flamegraph.pl --countname allocations --title "Allocation stacks" allocation-stacks/MyBenchmarks.Encode.allocations.folded > allocations.svg
```

### JSON export

Select `--allocation-stacks-export-format json` to write one `<target>.<benchmark>.allocations.json` file per benchmark, including benchmarks with no allocations:

```sh
swift package --allow-writing-to-package-directory benchmark run \
    --export-allocation-stacks --allocation-stacks-export-format json \
    --target MyBenchmarks --filter "Encode.*" --allocation-stacks-export-path allocation-stacks
```

Both formats export all captured stacks, regardless of `--allocation-stack-limit`. To pipe the selected format to another tool, use `--allocation-stacks-export-path stdout`; filter to one benchmark when a single report is needed.

### Overhead and metrics

Capturing a stack trace makes each allocation several microseconds slower and allocates itself, so this is a diagnostic mode:

- Only the `mallocCountTotal` and `mallocBytesCount` metrics are measured.
- It can only be used with the `run` command not with baseline or threshold operations.

### Requirements

- The `MallocInterposer` trait (enabled by default).
- A toolchain providing the Swift `Runtime` module, and on Apple platforms macOS 26 or later.
