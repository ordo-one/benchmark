# Running Benchmarks

Use the SwiftPM package plugin `benchmark` to run your benchmarks

## Overview

The most straightforward way to just run all benchmarks is simply:

```
swift package benchmark
```

To perform additional operations a command verb and/or additional options can be specified:

```
swift package benchmark <command verb> [<options>]
```

### Command verbs

- term `run`: run the benchmarks - default action if none specified
- term `init`: Create a benchmark target, create boilerplate and adds a target to Package.swift
- term `list`: list available benchmarks that can be run per benchmark target
- term `baseline list`: Lists the available baselines stored per benchmark target
- term `baseline read|update|delete|compare|check`: perform the specified subaction on one or more specified benchmark baselines
- term `help`: Display usage help to the terminal

### Options 

- term `--filter <filter>`: Benchmarks matching the regexp filter that should be run
- term `--skip <skip>`: Benchmarks matching the regexp filter that should be skipped
- term `--target <target>`: Benchmark targets matching the regexp filter that should be run
- term `--skip-target <skip-target>`: Benchmark targets matching the regexp filter that should be skipped
- term `--format <format>`: The output format to use, one of: ["text", "markdown", "influx", "percentiles", "tsv", "jmh"], default is 'text'
- term `--metric <metric>`: Specified one or more metrics that should be used instead of the benchmark defined ones. Valid values are string representation of ``BenchmarkMetric``

- term `--path <path>`: The path where exported data is stored, default is the current directory ("."). 
- term `--quiet`: Specifies that output should be suppressed (useful for if you just want to check return code)
- term `--scale`: Show the metrics in the scale of the outer loop only (without applying the inner loop scalingFactor to the output)
- term `--metric`: Specifies that the benchmark run should use a specific metric instead of the ones defined by the benchmarks
- term `--no-progress`: Specifies that benchmark progress information should not be displayed
- term `--check-absolute`: Set to true if thresholds should be checked against an absolute reference point rather than delta between baselines.
- term `--grouping <grouping>`: The grouping to use, one of: ["metric", "benchmark"]. default is 'benchmark'
- term `--benchmark-build-configuration <configuration>`: Build configuration to build the benchmark targets with, one of: ["debug", "release"]. Default is "release".

## Usage

`swift package benchmark help` provides usage notes

```
OVERVIEW: Run benchmarks or update, compare or check performance baselines

Performs operations on benchmarks (running or listing them), as well as storing, comparing baselines as well as checking them for threshold deviations.

The init command will create a skeleton benchmark suite for you and add it to Package.swift.

The `thresholds` commands reads/updates/checks benchmark runs vs. static thresholds.

For the 'text' default format, the output is implicitly 'stdout' unless otherwise specified.
For all other formats, the output is to a file in either the current working directory, or
the directory specified by the '--path' option, unless the special 'stdout' path is specified
in which case output will go to stdout (useful for e.g. baseline 'tsv' format export piped to youplot).

To allow writing to the package directory, you may need to pass the appropriate option to swift package:
swift package --allow-writing-to-package-directory benchmark <command> <options>

USAGE: swift package benchmark <command>

swift package benchmark [run] <options>
swift package benchmark init <benchmarkTargetName>
swift package benchmark list
swift package benchmark baseline list
swift package benchmark baseline read <baseline> [<baseline2> ... <baselineN>] [<options>]
swift package benchmark baseline update <baseline> [<options>]
swift package benchmark baseline delete <baseline> [<baseline2> ... <baselineN>] [<options>]
swift package benchmark baseline check <baseline> [<otherBaseline>] [<options>]
swift package benchmark baseline compare <baseline> [<otherBaseline>] [<options>]
swift package benchmark thresholds read [<options>]
swift package benchmark thresholds update [<baseline>] [<options>]
swift package benchmark thresholds check [<baseline>] [<options>]
swift package benchmark help

ARGUMENTS:
<command>               The benchmark command to perform. If not specified, 'run' is implied. (values: run, list, baseline, thresholds, help, init)

OPTIONS:
--filter <filter>       Benchmarks matching the regexp filter that should be run
--skip <skip>           Benchmarks matching the regexp filter that should be skipped
--target <target>       Benchmark targets matching the regexp filter that should be run
--skip-target <skip-target>
Benchmark targets matching the regexp filter that should be skipped
--format <format>       The output format to use, default is 'text' (values: text, markdown, influx, jmh, histogramEncoded, histogram, histogramSamples, histogramPercentiles, metricP90AbsoluteThresholds)
--metric <metric>       Specifies that the benchmark run should use one or more specific metrics instead of the ones defined by the benchmarks. (values: cpuUser, cpuSystem, cpuTotal, wallClock, throughput,
peakMemoryResident, peakMemoryResidentDelta, peakMemoryVirtual, mallocCountSmall, mallocCountLarge, mallocCountTotal, allocatedResidentMemory, memoryLeaked, syscalls, contextSwitches, threads,
threadsRunning, readSyscalls, writeSyscalls, readBytesLogical, writeBytesLogical, readBytesPhysical, writeBytesPhysical, instructions, retainCount, releaseCount, retainReleaseDelta, custom)
--path <path>           The path to operate on for data export or threshold operations, default is the current directory (".") for exports and the ("./Thresholds") directory for thresholds. 
--quiet                 Specifies that output should be suppressed (useful for if you just want to check return code)
--scale                 Specifies that some of the text output should be scaled using the scalingFactor (denoted by '*' in output)
--time-units <time-units>
Specifies that time related metrics output should be specified units (values: nanoseconds, microseconds, milliseconds, seconds, kiloseconds, megaseconds)
--check-absolute        <This is deprecated, use swift package benchmark thresholds updated/check/read instead>
Set to true if thresholds should be checked against an absolute reference point rather than delta between baselines.
This is used for CI workflows when you want to validate the thresholds vs. a persisted benchmark baseline
rather than comparing PR vs main or vs a current run. This is useful to cut down the build matrix needed
for those wanting to validate performance of e.g. toolchains or OS:s as well (or have other reasons for wanting
a specific check against a given absolute reference.).
If this is enabled, zero or one baselines should be specified for the check operation.
By default, thresholds are checked comparing two baselines, or a baseline and a benchmark run.
--check-absolute-path <check-absolute-path>
The path from which p90 thresholds will be loaded for absolute threshold checks.
This implicitly sets --check-absolute to true as well.
--no-progress           Specifies that benchmark progress information should not be displayed
--grouping <grouping>   The grouping to use, one of: ["metric", "benchmark"]. default is 'benchmark' (values: metric, benchmark)
--xswiftc <xswiftc>     Pass an argument to the Swift compiler when building the benchmark
-h, --help              Show help information.
```

## Running benchmarks in Xcode and using Instruments for profiling benchmarks

Profiling benchmarks or building the benchmarks in release mode in Xcode with jemalloc is currently not supported (as Xcode currently doesn't support interposition of the malloc library) and requires disabling jemalloc.

The `Jemalloc` support is controlled via a Swift Package Manager trait. To open Xcode with jemalloc disabled, make sure Xcode is closed and then open it from the CLI passing the `BENCHMARK_DISABLE_JEMALLOC` environment variable (supported by the Swift 5.x `Package@swift-5.9.swift` manifest):

```bash
open --env BENCHMARK_DISABLE_JEMALLOC=true Package.swift
```

For Swift 6.1+ toolchains, use `--disable-default-traits` when building or testing from the command line instead:

```bash
swift build --disable-default-traits
swift test --disable-default-traits
```

This will disable the jemalloc dependency and you can simply build in Xcode for profiling and use Instruments as normal - including signpost information for the benchmark run.

## Troubleshooting problems
If you have a benchmark that crashes, it's possible to run that specific benchmark in the debugger easily.

E.g. for the target `BenchmarkDateTime`, you can run it manually with
```
.build/arm64-apple-macosx/release/BenchmarkDateTime
```

There are some additional options too that can be displayed with `--help`:
```
hassila@max ~/G/benchmark (various-fixes)> .build/arm64-apple-macosx/release/BenchmarkDateTime --help
USAGE: benchmark-runner [--quiet <quiet>] [--input-fd <input-fd>] [--output-fd <output-fd>] [--filter <filter> ...] [--skip <skip> ...] [--check-absolute]

OPTIONS:
-q, --quiet <quiet>     Whether to suppress progress output. (default: false)
-i, --input-fd <input-fd>
The input pipe filedescriptor used for communication with host process.
-o, --output-fd <output-fd>
The output pipe filedescriptor used for communication with host process.
--filter <filter>       Benchmarks matching the regexp filter that should be run
--skip <skip>           Benchmarks matching the regexp filter that should be skipped
--check-absolute        Set to true if thresholds should be checked against an absolute reference point rather than delta between baselines.
This is used for CI workflows when you want to validate the thresholds vs. a persisted benchmark baseline
rather than comparing PR vs main or vs a current run. This is useful to cut down the build matrix needed
for those wanting to validate performance of e.g. toolchains or OS:s as well (or have other reasons for wanting
a specific check against a given absolute reference.).
If this is enabled, zero or one baselines should be specified for the check operation.
By default, thresholds are checked comparing two baselines, or a baseline and a benchmark run.
-h, --help              Show help information.
```

So to run a specific troubling benchmark target you can run it with:
```
.build/arm64-apple-macosx/release/BenchmarkDateTime --filter Foundation-Date
```

And use standard troubleshooting tools like LLDB etc on that binary, it simply runs the benchmark code.

Additionally, if there would be any internal failure in the benchmark plugin, please run your failed
command and append `--debug` to the end for instructions on how to run it with a debugger to generate
a backtrace for a bug report. E.g:
```
> swift package benchmark --debug
...
To debug, start BenchmarkTool in LLDB using:
lldb /Users/hassila/GitHub/benchmark/.build/arm64-apple-macosx/debug/BenchmarkTool

Then launch BenchmarkTool with:
run --command run --baseline-storage-path /Users/hassila/GitHub/benchmark --format text --grouping benchmark --benchmark-executable-paths /Users/hassila/GitHub/benchmark/.build/arm64-apple-macosx/release/HistogramBenchmark --benchmark-executable-paths /Users/hassila/GitHub/benchmark/.build/arm64-apple-macosx/release/BenchmarkDateTime --benchmark-executable-paths /Users/hassila/GitHub/benchmark/.build/arm64-apple-macosx/release/Basic
```


## Network or disk permissions failures

We've seen one instance of strange permissioning failures for disk writes for tests that use LMDB (where only the lock file can be created, but the actual data file fails - even when specifying `--allow-writing-to-package-directory`).

To workaround such issues if needed, disable running in the sandbox with:

```
swift package --disable-sandbox benchmark
```

This is also required for e.g. benchmarks that uses the network.

## Specifying specific flags to swiftc

It is possible to pass arbitrary flags to swiftc using the `Xswiftc` option, e.g.:

```
swift package benchmark --Xswiftc lto=llvm-full --Xswiftc experimental-hermetic-seal-at-link
```

## Sample usage

### Run all benchmark targets:
```
swift package benchmark
```

### Run all benchmark targets, but display by metric instead of by test:
```
swift package benchmark --grouping metric
```

### Run targets / benchmarks with regex matching
```
swift package benchmark --target ".*Time" --filter ".*k\." --skip ".*UTC.*" --skip-target ".*Time"
```

### List available benchmark targets:
```
swift package benchmark list
```

### Run specific benchmark target:
```
swift package benchmark run --target Frostflake
```

### Compare a stored baseline with a benchmark run
```
swift package benchmark baseline compare baseline1
```

### Compare two named baselines
```
swift package benchmark baseline compare alpha beta
```

### Check a stored baseline with a benchmark run for deviations
```
swift package benchmark baseline check baseline1
```

### Check two name baselines for deviations
```
swift package benchmark baseline check alpha beta
```

### Update a named benchmark baseline for all targets
```
swift package --allow-writing-to-package-directory benchmark baseline update alpha
```

### Update benchmark baseline for a specific target
```
swift package --allow-writing-to-package-directory benchmark baseline update --target Frostflake-Benchmark
```

### Export benchmark data
```
swift package --allow-writing-to-package-directory benchmark --format jmh 
```

### Export benchmark data to a specific location
```
swift package --allow-writing-to-package-directory benchmark --format jmh --path xyz
```
