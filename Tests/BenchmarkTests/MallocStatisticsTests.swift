//
// Copyright (c) 2026 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

import XCTest

@testable import Benchmark

/// Unit coverage for the interposer malloc-metric arithmetic and the malloc-metric scaling
/// configuration. These exercise `BenchmarkExecutor.mallocStatistics(...)` directly with
/// synthetic counter deltas, so no live interposer / allocation is required.
final class MallocStatisticsTests: XCTestCase {
    private func value(
        _ metrics: [(metric: BenchmarkMetric, value: Int)],
        _ wanted: BenchmarkMetric
    ) -> Int? {
        metrics.first { $0.metric == wanted }?.value
    }

    func testBalancedAllocFreeReportsNoLeak() {
        let metrics = BenchmarkExecutor.mallocStatistics(
            mallocCountDelta: 10, mallocBytesDelta: 1_024,
            mallocSmallDelta: 8, mallocLargeDelta: 2,
            freeCountDelta: 10, freeBytesDelta: 1_024
        )
        XCTAssertEqual(value(metrics, .mallocCountTotal), 10)
        XCTAssertEqual(value(metrics, .freeCountTotal), 10)
        XCTAssertEqual(value(metrics, .mallocBytesCount), 1_024)
        XCTAssertEqual(value(metrics, .mallocFreeDelta), 0)
        XCTAssertEqual(value(metrics, .memoryLeakedBytes), 0)
        XCTAssertNil(value(metrics, .memoryLeaked), "interposer stats must not emit the legacy jemalloc memoryLeaked metric")
    }

    func testUnbalancedAllocReportsLeak() {
        let metrics = BenchmarkExecutor.mallocStatistics(
            mallocCountDelta: 10, mallocBytesDelta: 2_048,
            mallocSmallDelta: 7, mallocLargeDelta: 3,
            freeCountDelta: 6, freeBytesDelta: 1_024
        )
        XCTAssertEqual(value(metrics, .mallocFreeDelta), 4) // 10 mallocs - 6 frees
        XCTAssertEqual(value(metrics, .memoryLeakedBytes), 1_024) // 2048 - 1024
    }

    /// A window that frees more than it allocates (e.g. freeing a warmup survivor or cross-thread
    /// frees) must clamp the leak to 0 — not go negative (which `Statistics.add` would silently
    /// drop, desyncing the sample count and biasing the average upward).
    func testNetFreeWindowClampsLeakToZero() {
        let metrics = BenchmarkExecutor.mallocStatistics(
            mallocCountDelta: 3, mallocBytesDelta: 256,
            mallocSmallDelta: 3, mallocLargeDelta: 0,
            freeCountDelta: 5, freeBytesDelta: 4_096
        )
        XCTAssertEqual(value(metrics, .mallocFreeDelta), 0)
        XCTAssertEqual(value(metrics, .memoryLeakedBytes), 0)
    }

    /// `mallocStatistics` is a pure mapping: each counter delta must land in its own metric slot
    /// unchanged, so a mis-routing of any single delta fails distinctly. (The `small + large == total`
    /// invariant is a property of the interposer's counters, not of this function, so it cannot be
    /// asserted at this layer.)
    func testDeltasRouteToCorrectMetricSlots() {
        let metrics = BenchmarkExecutor.mallocStatistics(
            mallocCountDelta: 10, mallocBytesDelta: 100,
            mallocSmallDelta: 6, mallocLargeDelta: 4,
            freeCountDelta: 3, freeBytesDelta: 48
        )
        XCTAssertEqual(value(metrics, .mallocCountTotal), 10)
        XCTAssertEqual(value(metrics, .mallocCountSmall), 6)
        XCTAssertEqual(value(metrics, .mallocCountLarge), 4)
        XCTAssertEqual(value(metrics, .mallocBytesCount), 100)
        XCTAssertEqual(value(metrics, .freeCountTotal), 3)
        XCTAssertEqual(value(metrics, .mallocFreeDelta), 7)
    }

    /// The whole per-iteration malloc count/byte family must scale together, otherwise the scaled
    /// output is internally inconsistent (e.g. `small + large != total`, or bytes not comparable
    /// to free) under a non-unit `scalingFactor`.
    func testMallocFamilyScalesConsistently() {
        let scaledFamily: [BenchmarkMetric] = [
            .mallocCountSmall, .mallocCountLarge, .mallocCountTotal,
            .freeCountTotal, .mallocBytesCount, .mallocFreeDelta, .memoryLeakedBytes,
        ]
        for metric in scaledFamily {
            XCTAssertTrue(
                metric.useScalingFactor,
                "\(metric.rawDescription) must scale with the rest of the malloc family"
            )
        }
    }

    func testDefaultMetricsUseBackendSpecificLeakMetrics() {
        #if canImport(MallocInterposerSwift)
        XCTAssertTrue(BenchmarkMetric.default.contains(.mallocFreeDelta))
        XCTAssertTrue(BenchmarkMetric.default.contains(.memoryLeakedBytes))
        XCTAssertFalse(
            BenchmarkMetric.default.contains(.memoryLeaked),
            "interposer defaults must not emit legacy jemalloc memoryLeaked"
        )
        #else
        XCTAssertTrue(BenchmarkMetric.default.contains(.memoryLeaked))
        XCTAssertFalse(BenchmarkMetric.default.contains(.mallocFreeDelta))
        #endif
    }

    /// Metric array slots must be unique so two metrics never collide on the same `statistics` slot.
    func testMetricIndicesAreUnique() {
        let indices = BenchmarkMetric.all.map(\.index)
        XCTAssertEqual(Set(indices).count, indices.count, "metric indices must be unique")
    }

    /// Each backend produces a different malloc-metric family; requesting the other backend's
    /// metric must be surfaced (it would otherwise be a silently-empty column / no-op gate).
    func testUnsupportedBackendMetricsAreReported() {
        #if canImport(MallocInterposerSwift)
        let unsupported = BenchmarkExecutor.metricsUnsupportedByBackend(
            [.wallClock, .allocatedResidentMemory, .memoryLeaked, .mallocBytesCount]
        )
        XCTAssertTrue(unsupported.contains(.allocatedResidentMemory))
        XCTAssertTrue(unsupported.contains(.memoryLeaked))
        XCTAssertFalse(unsupported.contains(.mallocBytesCount), "interposer backend produces mallocBytesCount")
        XCTAssertFalse(unsupported.contains(.wallClock))
        #else
        let unsupported = BenchmarkExecutor.metricsUnsupportedByBackend(
            [.wallClock, .allocatedResidentMemory, .mallocBytesCount, .mallocFreeDelta]
        )
        XCTAssertTrue(unsupported.contains(.mallocBytesCount))
        XCTAssertTrue(unsupported.contains(.mallocFreeDelta))
        XCTAssertFalse(unsupported.contains(.allocatedResidentMemory), "jemalloc backend produces allocatedResidentMemory")
        XCTAssertFalse(unsupported.contains(.wallClock))
        #endif
    }
}
