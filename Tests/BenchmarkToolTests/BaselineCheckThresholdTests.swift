//
// Copyright (c) 2026 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

#if canImport(Testing)
import Benchmark
import Testing

@testable import BenchmarkTool

/// `baseline check <a> <b>` builds no benchmark targets, so the tool has no live benchmarks to take thresholds from.
@Suite
struct BaselineCheckThresholdTests {
    private let identifier = BenchmarkIdentifier(target: "Target", name: "Benchmark")
    private let relaxed = BenchmarkThresholds(relative: [.p25: 25.0, .p50: 25.0, .p75: 25.0])
    private let strict = BenchmarkThresholds(relative: [.p25: 5.0, .p50: 5.0, .p75: 5.0])

    @Test
    func usesTheThresholdsRecordedWithTheCheckedBaseline() {
        let deviations = check(current: 110, recorded: relaxed, reference: 100, recordedInReference: strict)

        #expect(deviations.regressions.isEmpty)
        #expect(deviations.improvements.isEmpty)
    }

    @Test
    func failsBeyondTheRecordedThresholds() throws {
        let deviations = check(current: 130, recorded: relaxed, reference: 100, recordedInReference: strict)

        #expect(deviations.regressions.count == 3)
        let regression = try #require(deviations.regressions.first)
        guard case .relative(_, _, let tolerancePercentage) = regression.deviation else {
            Issue.record("Expected a relative deviation, got \(regression.deviation)")
            return
        }
        #expect(tolerancePercentage == 25.0)
    }

    @Test
    func fallsBackToTheDefaultThresholdsWhenNoneWereRecorded() throws {
        let deviations = check(current: 110, recorded: nil, reference: 100, recordedInReference: relaxed)

        #expect(deviations.regressions.count == 3)
        let regression = try #require(deviations.regressions.first)
        guard case .relative(_, _, let tolerancePercentage) = regression.deviation else {
            Issue.record("Expected a relative deviation, got \(regression.deviation)")
            return
        }
        #expect(tolerancePercentage == 5.0)
    }
}

extension BaselineCheckThresholdTests {
    private func check(
        current: Int,
        recorded: BenchmarkThresholds?,
        reference: Int,
        recordedInReference: BenchmarkThresholds?
    ) -> BenchmarkResult.ThresholdDeviations {
        let checked = baseline("pull_request", value: current, thresholds: recorded)
        let referenceBaseline = baseline("main", value: reference, thresholds: recordedInReference)
        return checked.deviationsComparedToBaseline(referenceBaseline, benchmarks: [])
    }

    private func baseline(_ name: String, value: Int, thresholds: BenchmarkThresholds?) -> BenchmarkBaseline {
        let statistics = Statistics()
        for _ in 0..<10 {
            statistics.add(value)
        }
        let result = BenchmarkResult(
            metric: .peakMemoryResident,
            timeUnits: .nanoseconds,
            scalingFactor: .one,
            warmupIterations: 0,
            thresholds: thresholds,
            statistics: statistics
        )
        let machine = BenchmarkMachine(
            hostname: "host",
            processors: 1,
            processorType: "arm64",
            memory: 1,
            kernelVersion: "1"
        )
        return BenchmarkBaseline(baselineName: name, machine: machine, results: [identifier: [result]])
    }
}
#endif
