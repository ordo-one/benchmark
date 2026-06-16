//
// Copyright (c) 2022 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

// Convenience sets of metrics
public extension BenchmarkMetric {
    /// A small collection of metrics used for microbenchmarks only interested in CPU
    ///
    /// The defaults include ``wallClock`` and  ``throughput``.
    ///
    /// There is also an convenience extension on Array defined such that you can write just `.microbenchmark` rather than `BenchmarkMetric.microbenchmark`
    ///
    static var microbenchmark: [BenchmarkMetric] {
        [
            .wallClock,
            .throughput,
        ]
    }

    /// The default collection of metrics used for a benchmark.
    ///
    /// The defaults include ``wallClock``, ``cpuTotal``, ``mallocCountTotal``, ``throughput``, and ``peakMemoryResident``.
    ///
    /// There is also an convenience extension on Array defined such that you can write just `.default` rather than `BenchmarkMetric.default`
    ///
    static var `default`: [BenchmarkMetric] {
        [
            .wallClock,
            .cpuTotal,
            .mallocCountTotal,
            .freeCountTotal,
            .mallocBytesCount,
            .memoryLeaked,
            .memoryLeakedBytes,
            .throughput,
            .instructions,
            .peakMemoryResident,
        ]
    }

    /// A collection of extended system benchmarks.
    static var extended: [BenchmarkMetric] {
        [
            .wallClock,
            .cpuUser,
            .cpuTotal,
            .mallocCountTotal,
            .freeCountTotal,
            .mallocBytesCount,
            .throughput,
            .peakMemoryResident,
            .memoryLeaked,
            .memoryLeakedBytes,
            .syscalls,
            .instructions,
        ]
    }

    /// A collection of memory benchmarks.
    static var memory: [BenchmarkMetric] {
        [
            .peakMemoryResident,
            .peakMemoryResidentDelta,
            .peakMemoryVirtual,
            .mallocCountSmall,
            .mallocCountLarge,
            .mallocCountTotal,
            .mallocBytesCount,
            .freeCountTotal,
            .memoryLeaked,
            .memoryLeakedBytes,
            .allocatedResidentMemory,
        ]
    }

    /// A collection of ARC metrics
    static var arc: [BenchmarkMetric] {
        [
            .objectAllocCount,
            .retainCount,
            .releaseCount,
            .retainReleaseDelta,
        ]
    }

    /// A collection of system benchmarks.
    static var system: [BenchmarkMetric] {
        [
            .wallClock,
            .syscalls,
            .contextSwitches,
            .threads,
            .threadsRunning,
            .cpuSystem,
        ]
    }

    /// A collection of disk benchmarks.
    static var disk: [BenchmarkMetric] {
        [
            .readSyscalls,
            .writeSyscalls,
            .readBytesLogical,
            .writeBytesLogical,
            .readBytesPhysical,
            .writeBytesPhysical,
        ]
    }

    /// A collection of all benchmarks supported by this library.
    static var all: [BenchmarkMetric] {
        [
            .cpuUser,
            .cpuSystem,
            .cpuTotal,
            .wallClock,
            .throughput,
            .peakMemoryResident,
            .peakMemoryResidentDelta,
            .peakMemoryVirtual,
            .mallocCountSmall,
            .mallocCountLarge,
            .mallocCountTotal,
            .freeCountTotal,
            .mallocBytesCount,
            .memoryLeaked,
            .memoryLeakedBytes,
            .syscalls,
            .contextSwitches,
            .threads,
            .threadsRunning,
            .readSyscalls,
            .writeSyscalls,
            .readBytesLogical,
            .writeBytesLogical,
            .readBytesPhysical,
            .writeBytesPhysical,
            .instructions,
            .allocatedResidentMemory,
            .objectAllocCount,
            .retainCount,
            .releaseCount,
            .retainReleaseDelta,
        ]
    }
}

// Nicer convenience extension for Array so one can write `.extended` instead of `BenchmarkMetric.extended`
public extension [BenchmarkMetric] {
    /// A suitable set of metrics for microbenchmarks that are CPU-oriented only.
    ///
    /// The defaults include ``BenchmarkMetric/wallClock`` and ``BenchmarkMetric/throughput``
    static var microbenchmark: [BenchmarkMetric] {
        BenchmarkMetric.microbenchmark
    }

    /// The default collection of metrics used for a benchmark.
    ///
    /// The defaults include ``BenchmarkMetric/wallClock``, ``BenchmarkMetric/cpuTotal``, ``BenchmarkMetric/mallocCountTotal``, ``BenchmarkMetric/throughput``, and ``BenchmarkMetric/peakMemoryResident``.
    static var `default`: [BenchmarkMetric] {
        BenchmarkMetric.default
    }

    /// A collection of extended system benchmarks.
    static var extended: [BenchmarkMetric] {
        BenchmarkMetric.extended
    }

    /// A collection of memory benchmarks.
    static var memory: [BenchmarkMetric] {
        BenchmarkMetric.memory
    }

    /// A collection of ARC metrics
    static var arc: [BenchmarkMetric] {
        BenchmarkMetric.arc
    }

    /// A collection of system benchmarks.
    static var system: [BenchmarkMetric] {
        BenchmarkMetric.system
    }

    /// A collection of disk benchmarks.
    static var disk: [BenchmarkMetric] {
        BenchmarkMetric.disk
    }

    /// A collection of all benchmarks supported by this library.
    static var all: [BenchmarkMetric] {
        BenchmarkMetric.all
    }
}
