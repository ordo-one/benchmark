// swiftlint:disable all
//
// Copyright (c) 2022 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

import Histogram
import Numerics

// A type that provides distribution / percentile calculations of latency measurements
@_documentation(visibility: internal)
public final class Statistics: Codable {
    public static let defaultMaximumMeasurement = 1_000_000_000 // 1 second in nanoseconds
    public static let defaultPercentilesToCalculate = [0.0, 25.0, 50.0, 75.0, 90.0, 99.0, 100.0]
    public static let defaultPercentilesToCalculateP90Index = 4

    public enum Units: Int, Codable, CaseIterable {
        case count = 1 // e.g. nanoseconds
        case kilo = 1_000 // microseconds
        case mega = 1_000_000 // milliseconds
        case giga = 1_000_000_000 // seconds
        case tera = 1_000_000_000_000 // 1K seconds
        case peta = 1_000_000_000_000_000 // 1M seconds
        case automatic = 0 // will pick time unit above automatically

        public var description: String {
            switch self {
            case .count:
                return "#"
            case .kilo:
                return "K"
            case .mega:
                return "M"
            case .giga:
                return "G"
            case .tera:
                return "T"
            case .peta:
                return "P"
            case .automatic:
                return "#"
            }
        }

        public var timeDescription: String {
            switch self {
            case .count:
                return "ns"
            case .kilo:
                return "μs"
            case .mega:
                return "ms"
            case .giga:
                return "s"
            case .tera:
                return "ks"
            case .peta:
                return "Ms"
            case .automatic:
                return "#"
            }
        }

        public init(fromMagnitudeOf value: Double) {
            let magnitude = Double.log10(value)
            switch magnitude {
            case ..<4.0:
                self = .count
            case 4.0..<7.0:
                self = .kilo
            case 7.0..<10.0:
                self = .mega
            case 10.0..<13.0:
                self = .giga
            case 13.0..<16.0:
                self = .tera
            case 16.0...:
                self = .peta
            default:
                self = .kilo
            }
        }
    }

    var _cachedPercentiles: [Int] = []
    var _cacheUnits: Statistics.Units = .automatic
    var _cachedPercentilesHistogramCount: UInt64 = 0

    public func percentiles(for percentilesToCalculate: [Double] = defaultPercentilesToCalculate) -> [Int] {
        if percentilesToCalculate == Self.defaultPercentilesToCalculate {
            if _cachedPercentilesHistogramCount == histogram.totalCount, _cachedPercentiles.count > 0 {
                return _cachedPercentiles
            }
        }

        var percentileResults: [Int] = []

        for var p in percentilesToCalculate {
            if prefersLarger {
                p = 100.0 - p
            }

            let value = histogram.valueAtPercentile(p)
            percentileResults.append(Int(value))
        }

        if percentilesToCalculate == Self.defaultPercentilesToCalculate {
            _cachedPercentilesHistogramCount = histogram.totalCount
            _cachedPercentiles = percentileResults
        }

        return percentileResults
    }

    // Returns the actual units to use (either specified, or automatic)
    public func units() -> Statistics.Units {
        if timeUnits != .automatic {
            return timeUnits
        }

        if onlyZeroMeasurements {
            return .count
        }

        if _cachedPercentilesHistogramCount != histogram.totalCount || _cacheUnits == .automatic {
            _cacheUnits = Statistics.Units(fromMagnitudeOf: histogram.mean)
            _cachedPercentilesHistogramCount = histogram.totalCount
        }

        return _cacheUnits
    }

    public let prefersLarger: Bool
    public let timeUnits: Statistics.Units
    public var histogram: Histogram<UInt>

    public var onlyZeroMeasurements: Bool {
        histogram.countForValue(0) == histogram.totalCount
    }

    public var measurementCount: Int {
        Int(histogram.totalCount)
    }

    public var average: Double {
        histogram.mean
    }

    public init(
        maximumMeasurement: Int = defaultMaximumMeasurement,
        numberOfSignificantDigits: SignificantDigits = .three,
        units: Statistics.Units = .automatic,
        prefersLarger: Bool = false
    ) {
        self.prefersLarger = prefersLarger
        timeUnits = units
        _cacheUnits = timeUnits
        histogram = Histogram(
            highestTrackableValue: UInt64(maximumMeasurement),
            numberOfSignificantValueDigits: numberOfSignificantDigits
        )
        histogram.autoResize = true
    }

    /// Add a measurement for inclusion in statistics
    /// - Parameter measurement: A measurement expressed in nanoseconds
    @inlinable
    @inline(__always)
    public func add(_ measurement: Int) {
        guard measurement >= 0 else {
            return // We sometimes got a <0 measurement, should run with fatalError and try to see how that could occur
            //            fatalError()
        }

        histogram.record(UInt64(measurement))
    }

    // Rounds decimals for display
    public static func roundToDecimalPlaces(
        _ original: Double,
        _ decimals: Int = 2,
        _ rule: FloatingPointRoundingRule = .toNearestOrEven
    ) -> Double {
        let factor: Double = .pow(10.0, Double(decimals))
        var original: Double = original * factor
        original.round(rule)
        return original / factor
    }
}

// swiftlint:enable all
