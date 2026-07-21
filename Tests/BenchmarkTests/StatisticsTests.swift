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

final class StatisticsTests: XCTestCase {
    func testStatisticsResults() throws {
        let stats = Statistics(numberOfSignificantDigits: .four)
        let measurementCount = 8_340

        // Add 2*measurementCount measurements, one 0, one max
        for measurement in (0..<measurementCount).reversed() {
            stats.add(measurement)
        }

        for measurement in 1...measurementCount {
            stats.add(measurement)
        }

        XCTAssertEqual(Statistics.roundToDecimalPlaces(123.4567898972239487234), 123.46)
        XCTAssertEqual(stats.measurementCount, measurementCount * 2)
        XCTAssertEqual(stats.units(), .count)
        XCTAssertEqual(round(stats.histogram.mean), round(Double(measurementCount / 2)))

        let percentiles = stats.percentiles()

        XCTAssertEqual(percentiles[0], 0)
        XCTAssertEqual(percentiles[1], Int(round(Double(measurementCount) * 0.25)))
        XCTAssertEqual(percentiles[2], Int(round(Double(measurementCount) * 0.5)))
        XCTAssertEqual(percentiles[3], Int(round(Double(measurementCount) * 0.75)))
        XCTAssertEqual(percentiles[4], Int(round(Double(measurementCount) * 0.9)))
        XCTAssertEqual(percentiles[5], Int(round(Double(measurementCount) * 0.99)))
        XCTAssertEqual(percentiles[6], Int(measurementCount))
    }

    func testOnlyZeroMeasurements() throws {
        let stats = Statistics()
        let measurementCount = 100
        let range = 0..<measurementCount

        for _ in range {
            stats.add(0)
        }

        XCTAssertEqual(stats.measurementCount, range.count)
        XCTAssertEqual(stats.histogram.mean, 0.0)

        XCTAssert(stats.onlyZeroMeasurements)

        let percentiles = stats.percentiles()

        XCTAssert(stats.onlyZeroMeasurements)
        XCTAssertEqual(stats.units(), .count)
        XCTAssertEqual(percentiles[0], 0)
        XCTAssertEqual(percentiles[1], 0)
        XCTAssertEqual(percentiles[2], 0)
        XCTAssertEqual(percentiles[3], 0)
        XCTAssertEqual(percentiles[4], 0)
        XCTAssertEqual(percentiles[5], 0)
        XCTAssertEqual(percentiles[6], 0)
    }

    func testFewerMeasurementsThanPercentiles() throws {
        let stats = Statistics()
        let measurementCount = 5
        let range = 1..<measurementCount
        var accumulatedMeasurement = 0

        for measurement in range {
            stats.add(measurement)
            accumulatedMeasurement += measurement
        }

        XCTAssertEqual(stats.measurementCount, range.count)
        XCTAssertEqual(stats.units(), .count)
        XCTAssertEqual(round(stats.histogram.mean), round(Double(accumulatedMeasurement) / Double(range.count)))

        let percentiles = stats.percentiles()

        XCTAssertEqual(percentiles[0], 1)
        XCTAssertEqual(percentiles[1], Int(round(Double(range.count) * 0.25)))
        XCTAssertEqual(percentiles[2], Int(round(Double(range.count) * 0.5)))
        XCTAssertEqual(percentiles[3], Int(round(Double(range.count) * 0.75)))
        XCTAssertEqual(percentiles[4], Int(round(Double(range.count) * 0.9)))
        XCTAssertEqual(percentiles[5], Int(round(Double(range.count) * 0.99)))
        XCTAssertEqual(percentiles[6], Int(range.count))
    }

    func testAutomaticUnits() throws {
        typealias Case = (value: Int, units: Statistics.Units)

        let cases = [
            Case(value: 0, units: .count),
            Case(value: 1, units: .count),
            Case(value: 9_999, units: .count),
            Case(value: 10_000, units: .kilo),
            Case(value: 100_000, units: .kilo),
            Case(value: 1_000_000, units: .kilo),
            Case(value: 9_999_999, units: .kilo),
            Case(value: 10_000_000, units: .mega),
            Case(value: 9_999_999_999, units: .mega),
            Case(value: 10_000_000_000, units: .giga),
        ]

        for (value, expectedUnits) in cases {
            let units = Statistics.Units(fromMagnitudeOf: Double(value))
            XCTAssertEqual(units, expectedUnits, "Expected units for \(value) are \(expectedUnits)")
        }
    }

    func testHistograms() throws {
        let measurementCount = 300
        let stats = Statistics(prefersLarger: true)

        for measurement in 1...measurementCount {
            stats.add(measurement)
        }

        XCTAssert(Int(stats.average) > (measurementCount / 3))
        XCTAssertGreaterThan(stats.histogram.totalCount, 100)
    }
}
