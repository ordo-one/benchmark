//
// Copyright (c) 2023 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

let help =
    """
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
    --format <format>       The output format to use, default is 'text' (values: text, markdown, influx, jmh, jsonSmallerIsBetter, jsonBiggerIsBetter, histogramEncoded, histogram, histogramSamples, histogramPercentiles, metricP90AbsoluteThresholds)
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
    --benchmark-build-configuration <configuration>
                            Build configuration to build the benchmark targets with, one of: ["debug", "release"]. Default is "release". (values: debug, release)
    --xswiftc <xswiftc>     Pass an argument to the Swift compiler when building the benchmark
    -h, --help              Show help information.
    """
