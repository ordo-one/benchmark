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
import Foundation
import Testing

@testable import Benchmark

@Suite
struct BenchmarkThresholdTests {
    private typealias Thresholds = [BenchmarkMetric: BenchmarkThreshold]
    private typealias Relative = BenchmarkThreshold.RelativeOrRange.Relative
    private typealias ThresholdRange = BenchmarkThreshold.RelativeOrRange.Range

    private let relativeAroundHundred = Relative(base: 100, tolerancePercentage: 5)
    private let rangeAroundHundred = ThresholdRange(min: 90, max: 110)

    // MARK: Decoding

    @Test
    func staticThresholdFilesDecodeAbsoluteRelativeAndRangeValues() throws {
        let json = """
            {
                "mallocCountTotal": 1011,
                "syscalls": {"base": 757, "tolerancePercentage": 0.27},
                "releaseCount": {"min": 4736, "max": 4739},
                "retainCount": {"base": 2369, "tolerancePercentage": 1.5, "min": 2300, "max": 2400}
            }
            """
        let thresholds = try JSONDecoder().decode(Thresholds.self, from: Data(json.utf8))

        guard
            case .absolute(let mallocCountTotal) = thresholds[.mallocCountTotal],
            case .relativeOrRange(let syscalls) = thresholds[.syscalls],
            case .relativeOrRange(let releaseCount) = thresholds[.releaseCount],
            case .relativeOrRange(let retainCount) = thresholds[.retainCount]
        else {
            Issue.record("Unexpected thresholds: \(thresholds)")
            return
        }

        #expect(mallocCountTotal == 1_011)

        #expect(syscalls.relative?.base == 757)
        #expect(syscalls.relative?.tolerancePercentage == 0.27)
        #expect(syscalls.range == nil)

        #expect(releaseCount.relative == nil)
        #expect(releaseCount.range?.min == 4_736)
        #expect(releaseCount.range?.max == 4_739)

        #expect(retainCount.relative?.base == 2_369)
        #expect(retainCount.relative?.tolerancePercentage == 1.5)
        #expect(retainCount.range?.min == 2_300)
        #expect(retainCount.range?.max == 2_400)
    }

    @Test
    func encodingRoundTripPreservesThresholds() throws {
        let original: Thresholds = [
            .mallocCountTotal: .absolute(1_011),
            .retainCount: .relativeOrRange(
                BenchmarkThreshold.RelativeOrRange(
                    relative: Relative(base: 2_369, tolerancePercentage: 1.5),
                    range: ThresholdRange(min: 2_300, max: 2_400)
                )
            ),
        ]

        let decoded = try JSONDecoder().decode(Thresholds.self, from: JSONEncoder().encode(original))

        #expect(decoded.count == 2)

        guard
            case .absolute(let mallocCountTotal) = decoded[.mallocCountTotal],
            case .relativeOrRange(let retainCount) = decoded[.retainCount]
        else {
            Issue.record("Unexpected thresholds: \(decoded)")
            return
        }

        #expect(mallocCountTotal == 1_011)
        #expect(retainCount.relative?.base == 2_369)
        #expect(retainCount.relative?.tolerancePercentage == 1.5)
        #expect(retainCount.range?.min == 2_300)
        #expect(retainCount.range?.max == 2_400)
    }

    @Test
    func decodingRejectsInvalidThresholds() {
        let documents = [
            #"{"syscalls": {"base": 100}}"#,
            #"{"syscalls": {}}"#,
            #"{"syscalls": {"min": 10, "max": 5}}"#,
            #"{"syscalls": {"base": -1, "tolerancePercentage": 5}}"#,
            #"{"syscalls": {"base": 100, "tolerancePercentage": 101}}"#,
        ]

        let decoder = JSONDecoder()
        for document in documents {
            #expect(throws: DecodingError.self, "\(document)") {
                try decoder.decode(Thresholds.self, from: Data(document.utf8))
            }
        }
    }

    // MARK: Relative and range

    @Test
    func relativeContainsValuesWithinTolerance() {
        #expect(relativeAroundHundred.contains(95).contains)
        #expect(relativeAroundHundred.contains(105).contains)
        #expect(!relativeAroundHundred.contains(94).contains)
        #expect(!relativeAroundHundred.contains(106).contains)
        #expect(relativeAroundHundred.contains(106).deviation == 6.0)
        #expect(relativeAroundHundred.contains(94).deviation == -6.0)
    }

    @Test
    func rangeContainsValuesWithinBounds() {
        #expect(rangeAroundHundred.contains(90))
        #expect(rangeAroundHundred.contains(110))
        #expect(!rangeAroundHundred.contains(89))
        #expect(!rangeAroundHundred.contains(111))
    }

    @Test
    func relativeCoveringRoundsBaseAndToleranceToCoverBounds() {
        let covering = Relative(covering: 100...103)

        #expect(covering.base == 102)
        #expect(covering.tolerancePercentage == 1.97)
        #expect(covering.contains(100).contains)
        #expect(covering.contains(103).contains)

        let truncated = Relative(base: 101, tolerancePercentage: 1.48)
        #expect(!truncated.contains(103).contains)
    }

    @Test
    func relativeCoveringContainsBothBoundsForEveryRange() {
        for lower in 0...200 {
            for width in 1...40 {
                let upper = lower + width
                let covering = Relative(covering: Double(lower)...Double(upper))
                let bounds = "\(lower)...\(upper)"

                #expect(covering.contains(lower).contains, "lower bound of \(bounds)")
                #expect(covering.contains(upper).contains, "upper bound of \(bounds)")
                #expect(covering.checkValid(), "validity of \(bounds)")
            }
        }
    }

    @Test
    func userSpecifiedThresholdsAreDetected() {
        #expect(!BenchmarkThresholds.default.definitelyContainsUserSpecifiedThresholds(at: .p90))
        #expect(!BenchmarkThresholds.default.definitelyContainsUserSpecifiedThresholds(at: .p50))

        let relative = BenchmarkThresholds(relative: [.p90: 7.0])
        #expect(relative.definitelyContainsUserSpecifiedThresholds(at: .p90))
        #expect(!relative.definitelyContainsUserSpecifiedThresholds(at: .p50))

        #expect(!BenchmarkThresholds(absolute: [.p90: 0]).definitelyContainsUserSpecifiedThresholds(at: .p90))
        #expect(BenchmarkThresholds(absolute: [.p90: 3]).definitelyContainsUserSpecifiedThresholds(at: .p90))
    }

    // MARK: Deviations

    @Test
    func codeRelativeThresholdFlagsComparisonsForSmallerPreferringMetrics() throws {
        let regressed = comparisonDeviations(.mallocCountTotal, current: 106)
        #expect(regressed.regressions.count == 1)
        #expect(regressed.improvements.isEmpty)
        let regression = try #require(regressed.regressions.first)
        #expect(regression.percentile == .p50)
        guard case .relative(_, let differencePercentage, let tolerancePercentage) = regression.deviation else {
            Issue.record("Expected a relative deviation, got \(regression.deviation)")
            return
        }
        #expect(differencePercentage == 6.0)
        #expect(tolerancePercentage == 5.0)

        let withinTolerance = comparisonDeviations(.mallocCountTotal, current: 104)
        #expect(withinTolerance.regressions.isEmpty)
        #expect(withinTolerance.improvements.isEmpty)

        let improved = comparisonDeviations(.mallocCountTotal, current: 94)
        #expect(improved.regressions.isEmpty)
        #expect(improved.improvements.count == 1)
    }

    @Test
    func codeRelativeThresholdFlagsComparisonsForLargerPreferringMetrics() {
        let regressed = comparisonDeviations(.throughput, current: 94)
        #expect(regressed.regressions.count == 1)
        #expect(regressed.improvements.isEmpty)

        let improved = comparisonDeviations(.throughput, current: 106)
        #expect(improved.regressions.isEmpty)
        #expect(improved.improvements.count == 1)
    }

    @Test
    func staticRelativeThresholdFlagsDeviationsBeyondTolerance() throws {
        let regressed = staticDeviations(.mallocCountTotal, value: 106, relative: relativeAroundHundred)
        #expect(regressed.regressions.count == 1)
        #expect(regressed.improvements.isEmpty)
        let regression = try #require(regressed.regressions.first)
        guard case .relative(_, let differencePercentage, let tolerancePercentage) = regression.deviation else {
            Issue.record("Expected a relative deviation, got \(regression.deviation)")
            return
        }
        #expect(differencePercentage == 6.0)
        #expect(tolerancePercentage == 5.0)

        let withinTolerance = staticDeviations(.mallocCountTotal, value: 104, relative: relativeAroundHundred)
        #expect(withinTolerance.regressions.isEmpty)
        #expect(withinTolerance.improvements.isEmpty)

        let improved = staticDeviations(.mallocCountTotal, value: 94, relative: relativeAroundHundred)
        #expect(improved.regressions.isEmpty)
        #expect(improved.improvements.count == 1)
    }

    @Test
    func staticRangeThresholdFlagsDeviationsOutsideBounds() throws {
        let regressed = staticDeviations(.mallocCountTotal, value: 111, range: rangeAroundHundred)
        #expect(regressed.regressions.count == 1)
        #expect(regressed.improvements.isEmpty)
        let regression = try #require(regressed.regressions.first)
        #expect(regression.deviation.isRange)

        let improved = staticDeviations(.mallocCountTotal, value: 89, range: rangeAroundHundred)
        #expect(improved.regressions.isEmpty)
        #expect(improved.improvements.count == 1)

        let atLowerBound = staticDeviations(.mallocCountTotal, value: 90, range: rangeAroundHundred)
        #expect(atLowerBound.regressions.isEmpty)
        #expect(atLowerBound.improvements.isEmpty)

        let atUpperBound = staticDeviations(.mallocCountTotal, value: 110, range: rangeAroundHundred)
        #expect(atUpperBound.regressions.isEmpty)
        #expect(atUpperBound.improvements.isEmpty)
    }

    @Test
    func staticRangeIsCheckedAlongsideWideRelativeThreshold() throws {
        let wideRelative = Relative(base: 100, tolerancePercentage: 20)
        let narrowRange = ThresholdRange(min: 95, max: 105)

        let deviations = staticDeviations(.mallocCountTotal, value: 110, relative: wideRelative, range: narrowRange)

        #expect(deviations.regressions.count == 1)
        #expect(deviations.improvements.isEmpty)
        let regression = try #require(deviations.regressions.first)
        #expect(regression.deviation.isRange)
    }

    @Test
    func staticRangeOutcomesInvertForLargerPreferringMetrics() {
        let improved = staticDeviations(.throughput, value: 111, range: rangeAroundHundred)
        #expect(improved.regressions.isEmpty)
        #expect(improved.improvements.count == 1)

        let regressed = staticDeviations(.throughput, value: 89, range: rangeAroundHundred)
        #expect(regressed.regressions.count == 1)
        #expect(regressed.improvements.isEmpty)
    }

    @Test
    func staticThresholdsIgnoreCodeThresholds() throws {
        let deviations = staticDeviations(
            .mallocCountTotal,
            value: 111,
            range: rangeAroundHundred,
            codeThresholds: BenchmarkThresholds(relative: [.p90: 50.0])
        )

        #expect(deviations.regressions.count == 1)
        #expect(deviations.improvements.isEmpty)
        let regression = try #require(deviations.regressions.first)
        #expect(regression.deviation.isRange)
    }
}

extension BenchmarkThresholdTests {
    private func makeResult(_ metric: BenchmarkMetric, value: Int) -> BenchmarkResult {
        let statistics = Statistics()
        for _ in 0..<10 {
            statistics.add(value)
        }
        return BenchmarkResult(
            metric: metric,
            timeUnits: .nanoseconds,
            scalingFactor: .one,
            warmupIterations: 0,
            thresholds: .default,
            statistics: statistics
        )
    }

    private func comparisonDeviations(_ metric: BenchmarkMetric, current: Int) -> BenchmarkResult.ThresholdDeviations {
        makeResult(metric, value: current).deviationsComparedWith(
            makeResult(metric, value: 100),
            thresholds: BenchmarkThresholds(relative: [.p50: 5.0])
        )
    }

    private func staticDeviations(
        _ metric: BenchmarkMetric,
        value: Int,
        relative: Relative? = nil,
        range: ThresholdRange? = nil,
        codeThresholds: BenchmarkThresholds = .default
    ) -> BenchmarkResult.ThresholdDeviations {
        makeResult(metric, value: value).deviationsAgainstAbsoluteThresholds(
            thresholds: codeThresholds,
            p90Threshold: .relativeOrRange(BenchmarkThreshold.RelativeOrRange(relative: relative, range: range))
        )
    }
}
#endif
