//
// Copyright (c) 2023 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

/// Definitions of benchmark thresholds per metric
public struct BenchmarkThresholds: Codable {
    public typealias RelativeThreshold = Double
    public typealias AbsoluteThreshold = Int

    public typealias RelativeThresholds = [BenchmarkResult.Percentile: RelativeThreshold]
    public typealias AbsoluteThresholds = [BenchmarkResult.Percentile: AbsoluteThreshold]

    /// Initializing BenchmarkThresholds
    ///  The Benchmark thresholds define the tolerances to use when comparing two baselines/runs or when comparing with static thresholds.
    /// - Parameters:
    ///   - relative: A dictionary with relative thresholds tolerances per percentile (using for delta comparisons)
    ///   - absolute: A dictionary with absolute thresholds tolerances per percentile (used both for delta and absolute comparisons)
    public init(
        relative: RelativeThresholds = Self.Relative.none,
        absolute: AbsoluteThresholds = Self.Absolute.none
    ) {
        self.relative = relative
        self.absolute = absolute
    }

    public let relative: RelativeThresholds
    public let absolute: AbsoluteThresholds
}

extension BenchmarkThresholds {
    public func definitelyContainsUserSpecifiedThresholds(at percentile: BenchmarkResult.Percentile) -> Bool {
        let defaultCodeThresholds = BenchmarkThresholds.default
        let relative = self.relative[percentile]
        let absolute = self.absolute[percentile]
        var relativeNonDefaultThresholdsExist: Bool {
            (relative ?? 0) != 0
                && relative != defaultCodeThresholds.relative[percentile]
        }
        var absoluteNonDefaultThresholdsExist: Bool {
            (absolute ?? 0) != 0
                && absolute != defaultCodeThresholds.absolute[percentile]
        }
        return relativeNonDefaultThresholdsExist || absoluteNonDefaultThresholdsExist
    }
}

public enum BenchmarkThreshold: Codable {
    /// A relative or range threshold. And that is a logical "or", meaning any or both.
    public struct RelativeOrRange: Codable {
        public struct Relative {
            public let base: Int
            public let tolerancePercentage: Double

            public init(base: Int, tolerancePercentage: Double) {
                self.base = base
                self.tolerancePercentage = tolerancePercentage

                if !self.checkValid() {
                    print(
                        """
                        Warning: Got invalid relative threshold values. base: \(self.base), tolerancePercentage: \(self.tolerancePercentage).
                        These must satisfy the following conditions:
                        - base must be non-negative
                        - tolerancePercentage must be finite
                        - tolerancePercentage must be non-negative
                        - tolerancePercentage must be less than or equal to 100
                        """
                    )
                }
            }

            /// Returns whether or not the value satisfies this relative range, as well as the
            /// percentage of the deviation of the value.
            public func contains(_ value: Int) -> (contains: Bool, deviation: Double) {
                let diff = Double(value - base)
                let allowedDiff = (Double(base) * tolerancePercentage / 100)
                let allowedDiffWithPrecision = Statistics.roundToDecimalPlaces(allowedDiff, 6, .up)
                let absDiffWithPrecision = Statistics.roundToDecimalPlaces(abs(diff), 6, .up)
                let contains = absDiffWithPrecision <= allowedDiffWithPrecision
                let deviation = (base == 0) ? 0 : diff / Double(base) * 100
                return (contains, deviation)
            }

            func checkValid() -> Bool {
                self.base >= 0
                    && self.tolerancePercentage.isFinite
                    && self.tolerancePercentage >= 0
                    && self.tolerancePercentage <= 100
            }
        }

        public struct Range {
            public let min: Int
            public let max: Int

            public init(min: Int, max: Int) {
                self.min = min
                self.max = max

                if !self.checkValid() {
                    print(
                        """
                        Warning: Got invalid range threshold values. min: \(self.min), max: \(self.max).
                        These must satisfy the following conditions:
                        - min must be less than or equal to max
                        """
                    )
                }
            }

            public func contains(_ value: Int) -> Bool {
                return value >= min && value <= max
            }

            func checkValid() -> Bool {
                self.min <= self.max
            }
        }

        public let relative: Relative?
        public let range: Range?

        public init(relative: Relative?, range: Range?) {
            self.relative = relative
            self.range = range

            if !self.checkValid() {
                print(
                    """
                    Warning: Got invalid RelativeOrRange threshold values. relative: \(String(describing: self.relative)), range: \(String(describing: self.range)).
                    At least one of the values must be non-nil.
                    """
                )
            }
        }

        func checkValid() -> Bool {
            self.containsAnyValue
        }

        var containsAnyValue: Bool {
            self.relative != nil || self.range != nil
        }

        enum CodingKeys: String, CodingKey {
            case base
            case tolerancePercentage
            case min
            case max
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            let base = try container.decodeIfPresent(Int.self, forKey: .base)
            let tolerancePercentage = try container.decodeIfPresent(Double.self, forKey: .tolerancePercentage)
            let min = try container.decodeIfPresent(Int.self, forKey: .min)
            let max = try container.decodeIfPresent(Int.self, forKey: .max)

            var relative: Relative?
            var range: Range?

            if let base, let tolerancePercentage {
                relative = Relative(base: base, tolerancePercentage: tolerancePercentage)

                guard relative?.checkValid() != false else {
                    throw DecodingError.dataCorrupted(
                        .init(
                            codingPath: decoder.codingPath,
                            debugDescription: """
                                RelativeOrRange thresholds object contains an invalid relative values.
                                base: \(base), tolerancePercentage: \(tolerancePercentage).
                                These must satisfy the following conditions:
                                - base must be non-negative
                                - tolerancePercentage must be finite
                                - tolerancePercentage must be non-negative
                                - tolerancePercentage must be less than or equal to 100
                                """
                        )
                    )
                }
            }
            if let min, let max {
                range = Range(min: min, max: max)

                guard range?.checkValid() != false else {
                    throw DecodingError.dataCorrupted(
                        .init(
                            codingPath: decoder.codingPath,
                            debugDescription: """
                                RelativeOrRange thresholds object contains invalid min-max values.
                                'min' (\(min)) and max ('\(max)') don't satisfy the requirements of min <= max.
                                """
                        )
                    )
                }
            }

            self.relative = relative
            self.range = range

            if !self.containsAnyValue {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: decoder.codingPath,
                        debugDescription: """
                            RelativeOrRange thresholds object does not contain either a valid relative or range.
                            For relative thresholds, both 'base' (Int) and 'tolerancePercentage' (Double) must be present and valid.
                            For range thresholds, both 'min' (Int) and 'max' (Int) must be present and valid.
                            You can declare both relative and range in the same object together, or just one of them.
                            Example: { "min": 90, "max": 110 }
                            Example: { "base": 115, "tolerancePercentage": 5.5 }
                            Example: { "base": 115, "tolerancePercentage": 4.5, "min": 90, "max": 110 }
                            """
                    )
                )
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            if let relative {
                try container.encode(relative.base, forKey: .base)
                try container.encode(relative.tolerancePercentage, forKey: .tolerancePercentage)
            }
            if let range {
                try container.encode(range.min, forKey: .min)
                try container.encode(range.max, forKey: .max)
            }
        }
    }

    case absolute(Int)
    case relativeOrRange(RelativeOrRange)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self = .absolute(value)
        } else {
            let value = try RelativeOrRange(from: decoder)
            self = .relativeOrRange(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .absolute(let value):
            try value.encode(to: encoder)
        case .relativeOrRange(let value):
            try value.encode(to: encoder)
        }
    }
}
