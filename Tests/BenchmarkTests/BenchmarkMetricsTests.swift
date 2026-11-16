//
// Copyright (c) 2023 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
///

import XCTest

@testable import Benchmark

final class BenchmarkMetricsTests: XCTestCase {
    private let metrics: [BenchmarkMetric] = [
        .cpuUser,
        .cpuSystem,
        .cpuTotal,
        .wallClock,
        .throughput,
        .peakMemoryResident,
        .peakMemoryResidentDelta,
        .peakMemoryVirtual,
        .mallocCountTotal,
        .mallocBytesCount,
        .freeCountTotal,
        .mallocFreeDelta,
        .allocatedResidentMemory,
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
        .objectAllocCount,
        .retainCount,
        .releaseCount,
        .retainReleaseDelta,
        .custom("test", polarity: .prefersSmaller, useScalingFactor: false),
        .custom("test2", polarity: .prefersLarger, useScalingFactor: true),
    ]

    private let textualMetrics: [String] = [
        "cpuUser",
        "cpuSystem",
        "cpuTotal",
        "wallClock",
        "throughput",
        "peakMemoryResident",
        "peakMemoryResidentDelta",
        "peakMemoryVirtual",
        "mallocCountTotal",
        "mallocBytesCount",
        "freeCountTotal",
        "mallocFreeDelta",
        "allocatedResidentMemory",
        "memoryLeaked",
        "memoryLeakedBytes",
        "syscalls",
        "contextSwitches",
        "threads",
        "threadsRunning",
        "readSyscalls",
        "writeSyscalls",
        "readBytesLogical",
        "writeBytesLogical",
        "readBytesPhysical",
        "writeBytesPhysical",
        "instructions",
        "objectAllocCount",
        "retainCount",
        "releaseCount",
        "retainReleaseDelta",
    ]

    func testBenchmarkMetrics() throws {
        var description = ""
        var rawValues = 0
        metrics.forEach { metric in
            description += metric.description
            rawValues += metric.useScalingFactor ? 0 : 1
            rawValues += metric.countable ? 0 : 1
            rawValues += metric.polarity == .prefersLarger ? 0 : 1
        }

        XCTAssert(rawValues > 10)
        XCTAssert(description.count > 10)
    }

    func testBenchmarkTextualMetrics() throws {
        var description = ""

        for metricIndex in 0..<textualMetrics.count {
            if let metric = BenchmarkMetric(argument: textualMetrics[metricIndex]) {
                description += metric.description
                XCTAssertEqual(metrics[metricIndex], metric)
            } else {
                XCTFail("Could not extract metric \(textualMetrics[metricIndex])")
            }
        }

        XCTAssert(description.count > 10)
    }
}
