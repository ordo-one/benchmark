//
// Copyright (c) 2022 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

// swiftlint: disable file_length identifier_name

@_documentation(visibility: internal)
public extension BenchmarkResult {
    enum Percentile: Int, Codable {
        case p0 = 0
        case p25 = 1
        case p50 = 2
        case p75 = 3
        case p90 = 4
        case p99 = 5
        case p100 = 6
    }
}

/// Time units for cpu/wall clock time
public enum BenchmarkTimeUnits: String, Codable, CustomStringConvertible, CaseIterable {
    case nanoseconds
    case microseconds
    case milliseconds
    case seconds
    case kiloseconds
    case megaseconds
    case automatic // will pick time unit above automatically
    public var factor: Int {
        switch self {
        case .nanoseconds:
            return 1_000_000_000
        case .microseconds:
            return 1_000_000
        case .milliseconds:
            return 1_000
        case .seconds:
            return 1
        case .kiloseconds:
            return 2 // Yeah, not right but we need to refactor to get rid of this, works for now
        case .megaseconds:
            return 3
        case .automatic:
            fatalError("Should never extract scalingFactor for .automatic")
        }
    }
    /// Divisor of raw data to the desired time unit representation
    public var divisor: Int {
        switch self {
        case .nanoseconds:
            return 1
        case .microseconds:
            return 1_000
        case .milliseconds:
            return 1_000_000
        case .seconds:
            return 1_000_000_000
        case .kiloseconds:
            return 1_000_000_000_000
        case .megaseconds:
            return 1_000_000_000_000_000
        case .automatic:
            fatalError("Should never extract scalingFactor for .automatic")
        }
    }

    public var description: String {
        switch self {
        case .nanoseconds:
            return "ns"
        case .microseconds:
            return "μs"
        case .milliseconds:
            return "ms"
        case .seconds:
            return "s"
        case .kiloseconds:
            return "ks"
        case .megaseconds:
            return "Ms"
        case .automatic:
            return "#"
        }
    }
}

/// Units for countable metrics
public enum BenchmarkUnits: Int, Codable, CustomStringConvertible, CaseIterable {
    case count = 1
    case kilo = 1_000
    case mega = 1_000_000
    case giga = 1_000_000_000
    case tera = 1_000_000_000_000
    case peta = 1_000_000_000_000_000
    case automatic // will pick unit above automatically

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
}

public extension Statistics.Units {
    init(_ units: BenchmarkUnits) {
        switch units {
        case .count:
            self = .count
        case .kilo:
            self = .kilo
        case .mega:
            self = .mega
        case .giga:
            self = .giga
        case .tera:
            self = .tera
        case .peta:
            self = .peta
        case .automatic:
            self = .automatic
        }
    }
}

public extension BenchmarkTimeUnits {
    init(_ units: BenchmarkUnits) {
        switch units {
        case .count:
            self = .nanoseconds
        case .kilo:
            self = .microseconds
        case .mega:
            self = .milliseconds
        case .giga:
            self = .seconds
        case .tera:
            self = .kiloseconds
        case .peta:
            self = .megaseconds
        case .automatic:
            self = .automatic
        }
    }
}

/// The scaling factor for benchmark iterations.
///
/// Typically used for very fast-running benchmarks.
/// In those cases, the time to measure the benchmark can impact as much as the time to run the code being benchmarked.
/// Use a scaling factor when running your short benchmarks to provide greater numerical stability to the results.
public enum BenchmarkScalingFactor: Int, Codable {
    /// No scaling factor, the raw count of iterations.
    case one = 1 // e.g. nanoseconds, or count
    /// Scaling factor of 1e03.
    case kilo = 1_000 // microseconds
    /// Scaling factor of 1e06.
    case mega = 1_000_000 // milliseconds
    /// Scaling factor of 1e09.
    case giga = 1_000_000_000 // seconds
    /// Scaling factor of 1e12.
    case tera = 1_000_000_000_000 // 1K seconds
    /// Scaling factor of 1e15.
    case peta = 1_000_000_000_000_000 // 1M

    public var description: String {
        switch self {
        case .one:
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
        }
    }
}

// How we should scale a result for a given time unit (all results counted in nanos)
public extension BenchmarkScalingFactor {
    init(_ units: BenchmarkTimeUnits) {
        switch units {
        case .automatic, .nanoseconds:
            self = .one
        case .microseconds:
            self = .kilo
        case .milliseconds:
            self = .mega
        case .seconds:
            self = .giga
        case .kiloseconds:
            self = .tera
        case .megaseconds:
            self = .peta
        }
    }
}

// swiftlint:disable type_body_length

@_documentation(visibility: internal)
public struct BenchmarkResult: Codable, Comparable, Equatable {
    public init(
        metric: BenchmarkMetric,
        timeUnits: BenchmarkTimeUnits,
        scalingFactor: BenchmarkScalingFactor,
        warmupIterations: Int,
        thresholds: BenchmarkThresholds? = nil,
        tags: [String: String] = [:],
        statistics: Statistics
    ) {
        self.metric = metric
        self.timeUnits = timeUnits == .automatic ? BenchmarkTimeUnits(statistics.units()) : timeUnits
        self.scalingFactor = scalingFactor
        self.warmupIterations = warmupIterations
        self.thresholds = thresholds
        self.tags = tags
        self.statistics = statistics
    }

    public var metric: BenchmarkMetric
    public var timeUnits: BenchmarkTimeUnits
    public var scalingFactor: BenchmarkScalingFactor
    public var warmupIterations: Int
    public var thresholds: BenchmarkThresholds?
    public var tags: [String: String]
    public var statistics: Statistics

    public var scaledTimeUnits: BenchmarkTimeUnits {
        switch timeUnits {
        case .nanoseconds:
            return .nanoseconds
        case .microseconds:
            switch scalingFactor {
            case .one:
                return .microseconds
            default:
                return .nanoseconds
            }
        case .milliseconds:
            switch scalingFactor {
            case .one:
                return .milliseconds
            case .kilo:
                return .microseconds
            default:
                return .nanoseconds
            }
        case .seconds:
            switch scalingFactor {
            case .one:
                return .seconds
            case .kilo:
                return .milliseconds
            case .mega:
                return .microseconds
            case .giga:
                return .nanoseconds
            case .tera, .peta: // shouldn't be possible as tera is only used internally to present scaled up throughput
                break
            }
        default:
            break
        }

        fatalError("scaledTimeUnits: \(scalingFactor), \(timeUnits)")
    }

    public var scaledScalingFactor: BenchmarkScalingFactor {
        guard metric == .throughput else {
            return scalingFactor
        }

        let timeUnitsMagnitude = Int(Double.log10(Double(timeUnits.divisor)))
        let scalingFactorMagnitude = Int(Double.log10(Double(scalingFactor.rawValue)))
        let totalMagnitude = timeUnitsMagnitude + scalingFactorMagnitude
        let newScale = pow(10, totalMagnitude)

        return BenchmarkScalingFactor(rawValue: newScale)!
    }

    // from SO to avoid Foundation/Numerics
    func pow<T: BinaryInteger>(_ base: T, _ power: T) -> T {
        func expBySq(_ y: T, _ x: T, _ n: T) -> T {
            precondition(n >= 0)
            if n == 0 {
                return y
            } else if n == 1 {
                return y * x
            } else if n.isMultiple(of: 2) {
                return expBySq(y, x * x, n / 2)
            } else { // n is odd
                return expBySq(y * x, x * x, (n - 1) / 2)
            }
        }

        return expBySq(1, base, power)
    }

    var remainingScalingFactor: BenchmarkScalingFactor {
        guard statistics.timeUnits == .automatic else {
            return scalingFactor
        }
        guard timeUnits != scaledTimeUnits else {
            return scalingFactor
        }
        let timeUnitsMagnitude = Int(Double.log10(Double(timeUnits.factor)))
        let scaledTimeUnitsMagnitude = Int(Double.log10(Double(scaledTimeUnits.factor)))
        let scalingFactorMagnitude = Int(Double.log10(Double(scalingFactor.rawValue)))
        let magnitudeDelta = scalingFactorMagnitude - (scaledTimeUnitsMagnitude - timeUnitsMagnitude)

        guard magnitudeDelta >= 0 else {
            fatalError("\(magnitudeDelta) \(scalingFactorMagnitude) \(scaledTimeUnitsMagnitude) \(timeUnitsMagnitude)")
        }
        let newScale = pow(10, magnitudeDelta)

        return BenchmarkScalingFactor(rawValue: newScale)!
    }

    // Scale a value according to timeunit/scaling factors in play
    public func scale(_ value: Int) -> Int {
        if metric == .throughput {
            return normalize(value)
        }

        var roundedValue = ((Double(normalize(value)) * 1_000.0) / Double(remainingScalingFactor.rawValue)) / 1_000.0
        roundedValue.round(.toNearestOrEven)
        return Int(roundedValue)
    }

    // Scale a value to the appropriate unit (from ns/count -> )
    public func normalize(_ value: Int) -> Int {
        var roundedValue = ((Double(value) * 1_000.0) / Double(timeUnits.divisor)) / 1_000.0
        roundedValue.round(.toNearestOrEven)
        return Int(roundedValue)
    }

    public func normalizeCompare(_ value: Int) -> Int {
        var roundedValue = ((Double(value) * 1_000.0) / Double(timeUnits.factor)) / 1_000.0
        roundedValue.round(.toNearestOrEven)
        return Int(roundedValue)
    }

    public var unitDescription: String {
        if metric.countable {
            let statisticsUnit = Statistics.Units(timeUnits)
            if statisticsUnit == .count {
                return ""
            }
            return statisticsUnit.description
        }
        return timeUnits.description
    }

    public var unitDescriptionPretty: String {
        if metric == .throughput {
            return "(\(scaledScalingFactor.description))"
        }
        if metric.countable {
            let statisticsUnit = Statistics.Units(timeUnits)
            if statisticsUnit == .count {
                return ""
            }
            return "(\(statisticsUnit.description))"
        }
        return "(\(timeUnits.description))"
    }

    public var scaledUnitDescriptionPretty: String {
        if metric == .throughput {
            if scalingFactor == .one {
                return "*"
            }
            return "(\(scaledScalingFactor.description)) *"
        }
        if metric.countable {
            let statisticsUnit = Statistics.Units(scaledTimeUnits)
            if statisticsUnit == .count {
                return "*"
            }
            return "(\(statisticsUnit.description)) *"
        }
        return statistics.timeUnits == .automatic
            ? "(\(scaledTimeUnits.description)) *" : "(\(timeUnits.description)) *"
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.metric == rhs.metric else {
            return false
        }

        if lhs.statistics.measurementCount != rhs.statistics.measurementCount {
            return false
        }

        let lhsPercentiles = lhs.statistics.percentiles()
        let rhsPercentiles = rhs.statistics.percentiles()

        for percentile in 0..<lhsPercentiles.count
        where
            lhs.normalizeCompare(lhsPercentiles[percentile]) != rhs.normalizeCompare(rhsPercentiles[percentile])
        {
            return false
        }

        return true
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        let reversedComparison = lhs.metric.polarity == .prefersLarger

        guard lhs.metric == rhs.metric else {
            return false
        }

        let lhsPercentiles = lhs.statistics.percentiles()
        let rhsPercentiles = rhs.statistics.percentiles()

        if reversedComparison {
            for percentile in 0..<lhsPercentiles.count
            where
                lhs.normalizeCompare(lhsPercentiles[percentile]) < rhs.normalizeCompare(rhsPercentiles[percentile])
            {
                return false
            }
        } else {
            for percentile in 0..<lhsPercentiles.count
            where
                lhs.normalizeCompare(lhsPercentiles[percentile]) > rhs.normalizeCompare(rhsPercentiles[percentile])
            {
                return false
            }
        }

        return true
    }

    public struct ThresholdDeviation {
        public enum Deviation {
            case absolute(comparedTo: Int, difference: Int, tolerance: Int)
            case relative(comparedTo: Int, differencePercentage: Double, tolerancePercentage: Double)
            case range(min: Int, max: Int)

            public var isRelative: Bool {
                switch self {
                case .relative:
                    return true
                default:
                    return false
                }
            }

            public var uxPriority: Int {
                switch self {
                case .range:
                    return 2
                case .absolute:
                    return 1
                case .relative:
                    return 0
                }
            }
        }

        public let name: String
        public let target: String
        public let metric: BenchmarkMetric
        public let percentile: BenchmarkResult.Percentile
        public let baseValue: Int
        public let deviation: Deviation
        public let units: Statistics.Units

        public var uxPriority: Int {
            return deviation.uxPriority
        }
    }

    public struct ThresholdDeviations {
        public init(regressions: [ThresholdDeviation] = [], improvements: [ThresholdDeviation] = []) {
            self.regressions = regressions
            self.improvements = improvements
        }

        public var regressions: [ThresholdDeviation] = []
        public var improvements: [ThresholdDeviation] = []

        public mutating func append(_ otherDeviations: Self) {
            improvements.append(contentsOf: otherDeviations.improvements)
            regressions.append(contentsOf: otherDeviations.regressions)
        }
    }

    // swiftlint:disable function_parameter_count
    func appendDeviationResultsFor(
        _ metric: BenchmarkMetric,
        _ lhs: Int,
        /// Either absolute values or thresholds from static threshold files.
        _ rhs: BenchmarkThreshold,
        _ percentile: Self.Percentile,
        /// Thresholds from 'configuration.thresholds' in the benchmark code.
        _ thresholdsFromCode: BenchmarkThresholds,
        _ thresholdResults: inout ThresholdDeviations,
        _ name: String = "unknown name",
        _ target: String = "unknown target"
    ) {
        let reverseComparison = metric.polarity == .prefersLarger
        switch rhs {
        case .absolute(let rhs):
            let absoluteDifference = (reverseComparison ? -1 : 1) * (lhs - rhs)
            let relativeDifference =
                (reverseComparison ? 1 : -1) * (rhs != 0 ? (100 - (100.0 * Double(lhs) / Double(rhs))) : 0.0)

            if let threshold = thresholdsFromCode.relative[percentile],
                !(-threshold...threshold).contains(relativeDifference)
            {
                let deviation = ThresholdDeviation(
                    name: name,
                    target: target,
                    metric: metric,
                    percentile: percentile,
                    baseValue: normalize(lhs),
                    deviation: .relative(
                        comparedTo: normalize(rhs),
                        differencePercentage: Statistics.roundToDecimalPlaces(relativeDifference, 1),
                        tolerancePercentage: Statistics.roundToDecimalPlaces(threshold, 1)
                    ),
                    units: Statistics.Units(timeUnits)
                )
                if relativeDifference > threshold {
                    thresholdResults.regressions.append(deviation)
                } else if relativeDifference < -threshold {
                    thresholdResults.improvements.append(deviation)
                }
            }

            if let threshold = thresholdsFromCode.absolute[percentile],
                !(-threshold...threshold).contains(absoluteDifference)
            {
                let deviation = ThresholdDeviation(
                    name: name,
                    target: target,
                    metric: metric,
                    percentile: percentile,
                    baseValue: normalize(lhs),
                    deviation: .absolute(
                        comparedTo: normalize(rhs),
                        difference: normalize(absoluteDifference),
                        tolerance: normalize(threshold)
                    ),
                    units: Statistics.Units(timeUnits)
                )
                if absoluteDifference > threshold {
                    thresholdResults.regressions.append(deviation)
                } else if absoluteDifference < -threshold {
                    thresholdResults.improvements.append(deviation)
                }
            }

        case .relativeOrRange(let rhs):
            if thresholdsFromCode.definitelyContainsUserSpecifiedThresholds(at: percentile) {
                print(
                    """
                    Warning: Static threshold files contain relative or range thresholds for metric '\(metric)' at
                    percentile '\(percentile)', but 'configuration.thresholds' also contains threshold tolerance for this metric.
                    Will ignore 'configuration.thresholds'.
                    To silence this warning, remove 'configuration.thresholds' from your benchmark code of this benchmark.

                    """
                )
            }

            if let relative = rhs.relative {
                let relativeComparison = relative.contains(lhs)
                if !relativeComparison.contains {
                    let relativeDifference = (reverseComparison ? 1 : -1) * relativeComparison.deviation
                    let deviation = ThresholdDeviation(
                        name: name,
                        target: target,
                        metric: metric,
                        percentile: percentile,
                        baseValue: normalize(lhs),
                        deviation: .relative(
                            comparedTo: normalize(relative.base),
                            differencePercentage: Statistics.roundToDecimalPlaces(relativeDifference, 1),
                            tolerancePercentage: Statistics.roundToDecimalPlaces(
                                relative.tolerancePercentage,
                                1
                            )
                        ),
                        units: Statistics.Units(timeUnits)
                    )
                    if relativeDifference > relative.tolerancePercentage {
                        thresholdResults.regressions.append(deviation)
                    } else if relativeDifference < -relative.tolerancePercentage {
                        thresholdResults.improvements.append(deviation)
                    }
                }
            }

            if let range = rhs.range, !range.contains(lhs) {
                let deviation = ThresholdDeviation(
                    name: name,
                    target: target,
                    metric: metric,
                    percentile: percentile,
                    baseValue: normalize(lhs),
                    deviation: .range(
                        min: normalize(range.min),
                        max: normalize(range.max)
                    ),
                    units: Statistics.Units(timeUnits)
                )
                if lhs < range.min {
                    thresholdResults.regressions.append(deviation)
                } else if lhs > range.max {
                    thresholdResults.improvements.append(deviation)
                }
            }
        }
    }

    public func deviationsComparedWith(
        _ rhs: Self,
        thresholds: BenchmarkThresholds = .default,
        name: String = "unknown name",
        target: String = "unknown target"
    ) -> ThresholdDeviations {
        let lhs = self

        guard lhs.metric == rhs.metric else {
            fatalError("Tried to compare two different metrics \(lhs.metric) - \(rhs.metric)")
        }

        var thresholdResults = ThresholdDeviations()
        let lhsPercentiles = lhs.statistics.percentiles()
        let rhsPercentiles = rhs.statistics.percentiles()

        for percentile in 0..<lhsPercentiles.count {
            appendDeviationResultsFor(
                lhs.metric,
                lhsPercentiles[percentile],
                .absolute(rhsPercentiles[percentile]),
                Self.Percentile(rawValue: percentile)!,
                thresholds,
                &thresholdResults,
                name,
                target
            )
        }

        return thresholdResults
    }

    // Absolute checks for --check-absolute, just check p90
    public func deviationsAgainstAbsoluteThresholds(
        thresholds: BenchmarkThresholds,
        p90Threshold: BenchmarkThreshold,
        name: String = "test",
        target: String = "test"
    ) -> ThresholdDeviations {
        var thresholdResults = ThresholdDeviations()
        let percentiles = statistics.percentiles()

        appendDeviationResultsFor(
            metric,
            percentiles[Statistics.defaultPercentilesToCalculateP90Index],
            p90Threshold,
            .p90,
            thresholds,
            &thresholdResults,
            name,
            target
        )

        return thresholdResults
    }
}

public extension Statistics.Units {
    init(_ timeUnits: BenchmarkTimeUnits) {
        switch timeUnits {
        case .nanoseconds:
            self = .count
        case .microseconds:
            self = .kilo
        case .milliseconds:
            self = .mega
        case .seconds:
            self = .giga
        case .kiloseconds:
            self = .tera
        case .megaseconds:
            self = .peta
        case .automatic:
            self = .automatic
        }
    }
}

public extension Statistics.Units {
    init(_ timeUnits: BenchmarkTimeUnits?) {
        switch timeUnits {
        case .nanoseconds:
            self = .count
        case .microseconds:
            self = .kilo
        case .milliseconds:
            self = .mega
        case .seconds:
            self = .giga
        case .kiloseconds:
            self = .tera
        case .megaseconds:
            self = .peta
        case .automatic:
            self = .automatic
        case .none:
            self = .count
        }
    }
}

public extension BenchmarkTimeUnits {
    init(_ timeUnits: Statistics.Units) {
        switch timeUnits {
        case .count:
            self = .nanoseconds
        case .kilo:
            self = .microseconds
        case .mega:
            self = .milliseconds
        case .giga:
            self = .seconds
        case .tera:
            self = .kiloseconds
        case .peta:
            self = .megaseconds
        case .automatic:
            self = .automatic
        }
    }
}

// swiftlint:enable file_length identifier_name function_parameter_count type_body_length
