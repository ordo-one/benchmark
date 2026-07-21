//
// Copyright (c) 2022 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

import XCTest

@testable import Benchmark

// swiftlint:disable function_body_length type_body_length file_length
final class BenchmarkResultTests: XCTestCase {
    func testBenchmarkResultEqual() throws {
        let firstStatistics = Statistics()
        firstStatistics.add(125_000_000_000)
        firstStatistics.add(150_000_000_000)
        firstStatistics.add(175_000_000_000)
        firstStatistics.add(190_000_000_000)

        let firstResult = BenchmarkResult(
            metric: .cpuUser,
            timeUnits: .nanoseconds,
            scalingFactor: .one,
            warmupIterations: 0,
            thresholds: .default,
            statistics: firstStatistics
        )

        let secondResult = BenchmarkResult(
            metric: .cpuUser,
            timeUnits: .nanoseconds,
            scalingFactor: .giga,
            warmupIterations: 20,
            thresholds: .default,
            statistics: firstStatistics
        )

        XCTAssertEqual(firstResult, secondResult)
    }

    func testBenchmarkResultLessThan() throws {
        let firstStatistics = Statistics()
        firstStatistics.add(125_000_000_000)
        firstStatistics.add(150_000_000_000)
        firstStatistics.add(175_000_000_000)
        firstStatistics.add(190_000_000_000)

        let secondStatistics = Statistics()
        secondStatistics.add(125_000_000_000)
        secondStatistics.add(151_000_000_000)
        secondStatistics.add(175_000_000_000)

        let thirdStatistics = Statistics()
        thirdStatistics.add(225_000_000_000)
        thirdStatistics.add(251_000_000_000)
        thirdStatistics.add(275_000_000_000)

        let firstResult = BenchmarkResult(
            metric: .cpuUser,
            timeUnits: .nanoseconds,
            scalingFactor: .one,
            warmupIterations: 0,
            thresholds: .default,
            statistics: firstStatistics
        )

        var secondResult = BenchmarkResult(
            metric: .cpuUser,
            timeUnits: .microseconds,
            scalingFactor: .one,
            warmupIterations: 0,
            thresholds: .default,
            statistics: secondStatistics
        )

        var thirdResult = BenchmarkResult(
            metric: .cpuUser,
            timeUnits: .microseconds,
            scalingFactor: .one,
            warmupIterations: 0,
            thresholds: .default,
            statistics: thirdStatistics
        )

        XCTAssertLessThan(firstResult, secondResult)
        XCTAssertGreaterThan(thirdResult, secondResult)

        secondResult = BenchmarkResult(
            metric: .throughput,
            timeUnits: .microseconds,
            scalingFactor: .one,
            warmupIterations: 0,
            thresholds: .default,
            statistics: secondStatistics
        )

        thirdResult = BenchmarkResult(
            metric: .throughput,
            timeUnits: .microseconds,
            scalingFactor: .one,
            warmupIterations: 0,
            thresholds: .default,
            statistics: thirdStatistics
        )

        // Should be reversed for throughput measurements
        XCTAssertLessThan(thirdResult, secondResult)
    }

    func testBenchmarkResultLessThanFailure() throws {
        let firstStatistics = Statistics()
        firstStatistics.add(125_000_000_000)
        firstStatistics.add(150_000_000_000)
        firstStatistics.add(175_000_000_000)
        firstStatistics.add(190_000_000_000)
        firstStatistics.add(198_000_000_000)
        firstStatistics.add(200_000_000_000)

        let firstResult = BenchmarkResult(
            metric: .cpuUser,
            timeUnits: .microseconds,
            scalingFactor: .one,
            warmupIterations: 0,
            thresholds: .default,
            statistics: firstStatistics
        )

        let secondResult = BenchmarkResult(
            metric: .cpuSystem,
            timeUnits: .microseconds,
            scalingFactor: .one,
            warmupIterations: 0,
            thresholds: .default,
            statistics: firstStatistics
        )

        XCTAssertNotEqual(firstResult, secondResult)
        XCTAssertFalse(firstResult > secondResult)
        XCTAssertFalse(firstResult < secondResult)
        XCTAssertNotEqual(firstResult, secondResult)
    }

    func testBenchmarkResultBetterOrEqualWithDefaultThresholds() throws {
        let firstStatistics = Statistics()
        firstStatistics.add(0)
        firstStatistics.add(125_000_000)
        firstStatistics.add(150_000_000)
        firstStatistics.add(175_000_000)
        firstStatistics.add(190_000_000)
        firstStatistics.add(199_000_000)
        firstStatistics.add(200_000_000)

        let secondStatistics = Statistics()
        secondStatistics.add(2)
        secondStatistics.add(124_999)
        secondStatistics.add(149_999)
        secondStatistics.add(175_001)
        secondStatistics.add(189_999)
        secondStatistics.add(199_001)
        secondStatistics.add(200_004)

        let firstResult = BenchmarkResult(
            metric: .cpuUser,
            timeUnits: .milliseconds,
            scalingFactor: .one,
            warmupIterations: 0,
            thresholds: .default,
            statistics: firstStatistics
        )

        let secondResult = BenchmarkResult(
            metric: .cpuUser,
            timeUnits: .microseconds,
            scalingFactor: .one,
            warmupIterations: 0,
            thresholds: .default,
            statistics: secondStatistics
        )

        XCTAssert(secondResult.deviationsComparedWith(firstResult).regressions.isEmpty)
    }

    func testBenchmarkResultBetterOrEqualWithCustomThresholds() throws {
        let firstStatistics = Statistics()
        firstStatistics.add(0)
        firstStatistics.add(125)
        firstStatistics.add(150)
        firstStatistics.add(175)
        firstStatistics.add(190)
        firstStatistics.add(199)
        firstStatistics.add(200)

        let secondStatistics = Statistics()
        secondStatistics.add(5)
        secondStatistics.add(136)
        secondStatistics.add(160)
        secondStatistics.add(175)
        secondStatistics.add(190)
        secondStatistics.add(199)
        secondStatistics.add(210)

        let relative: BenchmarkThresholds.RelativeThresholds = [
            .p0: 0.0,
            .p25: 0.0,
            .p50: 0.0,
            .p75: 0.0,
            .p90: 0.0,
            .p99: 0.0,
            .p100: 0.0,
        ]

        let relativeRelaxed: BenchmarkThresholds.RelativeThresholds = [
            .p0: 10.0,
            .p25: 10.0,
            .p50: 10.0,
            .p75: 10.0,
            .p90: 10.0,
            .p99: 10.0,
            .p100: 10.0,
        ]

        let absolute: BenchmarkThresholds.AbsoluteThresholds = [
            .p0: 1,
            .p25: 1,
            .p50: 1,
            .p75: 0,
            .p90: 0,
            .p99: 0,
            .p100: 0,
        ]

        let bothThresholds = BenchmarkThresholds(relative: relative, absolute: absolute)
        let absoluteThresholds = BenchmarkThresholds(absolute: absolute)
        let relativeThresholds = BenchmarkThresholds(relative: relative)
        let relativeRelaxedThresholds = BenchmarkThresholds(relative: relativeRelaxed)

        let firstResult = BenchmarkResult(
            metric: .cpuUser,
            timeUnits: .nanoseconds,
            scalingFactor: .one,
            warmupIterations: 0,
            thresholds: .default,
            statistics: firstStatistics
        )

        let secondResult = BenchmarkResult(
            metric: .cpuUser,
            timeUnits: .nanoseconds,
            scalingFactor: .one,
            warmupIterations: 0,
            thresholds: .default,
            statistics: secondStatistics
        )

        var betterOrEqual = secondResult.deviationsComparedWith(firstResult, thresholds: bothThresholds).regressions
            .isEmpty
        XCTAssertFalse(betterOrEqual)

        betterOrEqual =
            secondResult.deviationsComparedWith(firstResult, thresholds: relativeRelaxedThresholds).regressions.isEmpty
        XCTAssert(betterOrEqual)

        betterOrEqual =
            secondResult.deviationsComparedWith(firstResult, thresholds: relativeThresholds).regressions.isEmpty
        XCTAssertFalse(betterOrEqual)

        betterOrEqual =
            secondResult.deviationsComparedWith(firstResult, thresholds: absoluteThresholds).regressions.isEmpty
        XCTAssertFalse(betterOrEqual)

        betterOrEqual = firstResult.deviationsComparedWith(secondResult, thresholds: bothThresholds).regressions.isEmpty
        XCTAssert(betterOrEqual)

        betterOrEqual =
            firstResult.deviationsComparedWith(secondResult, thresholds: relativeRelaxedThresholds).regressions.isEmpty
        XCTAssert(betterOrEqual)

        betterOrEqual =
            firstResult.deviationsComparedWith(secondResult, thresholds: relativeThresholds).regressions.isEmpty
        XCTAssert(betterOrEqual)

        betterOrEqual =
            firstResult.deviationsComparedWith(secondResult, thresholds: absoluteThresholds).regressions.isEmpty
        XCTAssert(betterOrEqual)
    }

    func testBenchmarkAbsoluteThresholds() throws {
        let firstStatistics = Statistics()
        firstStatistics.add(0)
        firstStatistics.add(125)
        firstStatistics.add(150)
        firstStatistics.add(175)
        firstStatistics.add(190)
        firstStatistics.add(199)
        firstStatistics.add(200)

        let secondStatistics = Statistics()
        secondStatistics.add(5)
        secondStatistics.add(136)
        secondStatistics.add(160)
        secondStatistics.add(175)
        secondStatistics.add(190)
        secondStatistics.add(199)
        secondStatistics.add(210)

        let thirdStatistics = Statistics()
        thirdStatistics.add(1_501)
        thirdStatistics.add(1_501)
        thirdStatistics.add(1_501)
        thirdStatistics.add(1_501)
        thirdStatistics.add(1_501)

        let fourthStatistics = Statistics()
        fourthStatistics.add(1_499)
        fourthStatistics.add(1_500)
        fourthStatistics.add(1_501)
        fourthStatistics.add(1_501)
        fourthStatistics.add(1_501)
        fourthStatistics.add(1_501)

        let absolute: BenchmarkThresholds.AbsoluteThresholds = [
            .p0: 1,
            .p25: 1,
            .p50: 1,
            .p75: 1,
            .p90: 1,
            .p99: 1,
        ]

        let absoluteThresholds = BenchmarkThresholds(absolute: absolute)

        let absoluteP90: BenchmarkThresholds.AbsoluteThresholds = [.p90: 3]

        let absoluteThresholdsP90 = BenchmarkThresholds(absolute: absoluteP90)

        let firstResult = BenchmarkResult(
            metric: .cpuUser,
            timeUnits: .nanoseconds,
            scalingFactor: .one,
            warmupIterations: 0,
            thresholds: .default,
            statistics: firstStatistics
        )

        let secondResult = BenchmarkResult(
            metric: .cpuUser,
            timeUnits: .nanoseconds,
            scalingFactor: .one,
            warmupIterations: 0,
            thresholds: .default,
            statistics: secondStatistics
        )

        let thirdResult = BenchmarkResult(
            metric: .cpuUser,
            timeUnits: .nanoseconds,
            scalingFactor: .one,
            warmupIterations: 0,
            thresholds: .default,
            statistics: thirdStatistics
        )

        var deviations = secondResult.deviationsComparedWith(
            firstResult,
            thresholds: absoluteThresholds
        )
        XCTAssertFalse(deviations.regressions.isEmpty, "Regressions: \(deviations.regressions)")

        deviations = firstResult.deviationsComparedWith(
            secondResult,
            thresholds: absoluteThresholds
        )
        XCTAssert(deviations.regressions.isEmpty)

        Benchmark.checkAbsoluteThresholds = true
        deviations = thirdResult.deviationsAgainstAbsoluteThresholds(
            thresholds: absoluteThresholdsP90,
            p90Threshold: .absolute(1_497)
        )
        XCTAssertFalse(deviations.regressions.isEmpty)

        Benchmark.checkAbsoluteThresholds = true
        deviations = thirdResult.deviationsAgainstAbsoluteThresholds(
            thresholds: absoluteThresholdsP90,
            p90Threshold: .absolute(1_505)
        )
        XCTAssertFalse(deviations.improvements.isEmpty)

        Benchmark.checkAbsoluteThresholds = true
        deviations = thirdResult.deviationsAgainstAbsoluteThresholds(
            thresholds: absoluteThresholdsP90,
            p90Threshold: .absolute(1_501)
        )
        XCTAssertTrue(deviations.improvements.isEmpty && deviations.regressions.isEmpty)
    }

    func testBenchmarkResultDescriptions() throws {
        let firstStatistics = Statistics()
        firstStatistics.add(0)
        firstStatistics.add(125)
        firstStatistics.add(150)
        firstStatistics.add(175)
        firstStatistics.add(190)
        firstStatistics.add(199)
        firstStatistics.add(200)

        let firstResult = BenchmarkResult(
            metric: .cpuUser,
            timeUnits: .nanoseconds,
            scalingFactor: .one,
            warmupIterations: 0,
            thresholds: .default,
            statistics: firstStatistics
        )

        XCTAssertGreaterThan((firstResult.unitDescription + firstResult.unitDescriptionPretty).count, 5)
    }

    func testBenchmarkResultScalingAndNormalization() throws {
        let firstStatistics = Statistics()
        firstStatistics.add(125_000_000_000)

        var result = BenchmarkResult(
            metric: .cpuUser,
            timeUnits: .milliseconds,
            scalingFactor: .giga,
            warmupIterations: 0,
            thresholds: .default,
            statistics: firstStatistics
        )

        XCTAssertEqual(result.normalize(125_000_000), result.scale(125_000_000_000))

        result = BenchmarkResult(
            metric: .cpuUser,
            timeUnits: .microseconds,
            scalingFactor: .mega,
            warmupIterations: 0,
            thresholds: .default,
            statistics: firstStatistics
        )

        XCTAssertEqual(result.normalize(125_000_000), result.scale(125_000_000_000))

        result = BenchmarkResult(
            metric: .cpuUser,
            timeUnits: .nanoseconds,
            scalingFactor: .kilo,
            warmupIterations: 0,
            thresholds: .default,
            statistics: firstStatistics
        )

        XCTAssertEqual(result.normalize(125_000_000), result.scale(125_000_000_000))
    }

    func testBenchmarkResultEnumerations() throws {
        var scalingFactor: BenchmarkScalingFactor = .one
        var description = ""
        description += scalingFactor.description
        scalingFactor = .kilo
        description += scalingFactor.description
        scalingFactor = .mega
        description += scalingFactor.description
        scalingFactor = .giga
        description += scalingFactor.description
        scalingFactor = .tera
        description += scalingFactor.description
        XCTAssert(description.count > 4)
    }
}

// swiftlint:enable function_body_length type_body_length
