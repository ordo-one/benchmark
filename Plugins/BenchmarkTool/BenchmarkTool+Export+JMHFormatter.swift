//
// Copyright (c) 2023 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

// Merge resulting json using jq with
// jq -s add delta-*.json > delta.json

import Benchmark
import Foundation
import Numerics

extension JMHPrimaryMetric {
    init(_ result: BenchmarkResult) {
        let histogram = result.statistics.histogram

        // TODO: Must validate the calculation of scoreError
        // below was cobbled together according to https://stackoverflow.com/a/24725075
        // and https://www.calculator.net/confidence-interval-calculator.html
        let z999 = 3.291
        let error = z999 * histogram.stdDeviation / .sqrt(Double(histogram.totalCount))

        let score = histogram.mean

        let percentiles = [0.0, 50.0, 90.0, 95.0, 99.0, 99.9, 99.99, 99.999, 99.9999, 100.0]
        var percentileValues: [String: Double] = [:]
        var recordedValues: [Double] = []
        //        let factor = 1 // result.metric == .throughput ? 1 : 1_000_000_000 / result.timeUnits.rawValue
        let factor = result.metric.countable == false ? 1_000 : 1

        for p in percentiles {
            percentileValues[String(p)] = Statistics.roundToDecimalPlaces(
                Double(histogram.valueAtPercentile(p)) / Double(factor),
                3
            )
        }

        for value in histogram.recordedValues() {
            for _ in 0..<value.count {
                recordedValues.append(Statistics.roundToDecimalPlaces(Double(value.value) / Double(factor), 3))
            }
        }

        self.score = Statistics.roundToDecimalPlaces(score / Double(factor), 3)
        scoreError = Statistics.roundToDecimalPlaces(error / Double(factor), 3)
        scoreConfidence = [
            Statistics.roundToDecimalPlaces(score - error) / Double(factor),
            Statistics.roundToDecimalPlaces(score + error) / Double(factor),
        ]
        scorePercentiles = percentileValues
        if result.metric.countable {
            scoreUnit = result.metric == .throughput ? "# / s" : "#"
        } else {
            scoreUnit = "μs" // result.timeUnits.description
        }
        rawData = [recordedValues]
    }
}

extension BenchmarkTool {
    func convertToJMH(_ baseline: BenchmarkBaseline) throws -> String {
        var resultString = ""
        var jmhElements: [JMHElement] = []
        var secondaryMetrics: [String: JMHPrimaryMetric] = [:] // could move to OrderedDictionary for consistent output

        baseline.targets.forEach { benchmarkTarget in

            let results = baseline.resultsByTarget(benchmarkTarget)

            results.forEach { key, result in

                guard let primaryResult = result.first(where: { $0.metric == .throughput }) else {
                    print("Throughput metric must be present for JMH export [\(key)]")
                    return
                }

                let primaryMetrics = JMHPrimaryMetric(primaryResult)

                for secondaryResult in result {
                    if secondaryResult.metric != .throughput {
                        let secondaryMetric = JMHPrimaryMetric(secondaryResult)
                        secondaryMetrics[secondaryResult.metric.description] = secondaryMetric
                    }
                }

                // Some of these are a bit unclear how to map, so to the best of our understanding:
                let benchmarkKey = key.replacingOccurrences(of: " ", with: "_")
                let jmh = JMHElement(
                    benchmark: "package.benchmark.\(benchmarkTarget).\(benchmarkKey)",
                    mode: "thrpt",
                    threads: 1,
                    forks: 1,
                    warmupIterations: primaryResult.warmupIterations,
                    warmupTime: "1 s",
                    warmupBatchSize: 1,
                    measurementIterations: primaryResult.statistics.measurementCount,
                    measurementTime: "1 s",
                    measurementBatchSize: 1,
                    primaryMetric: primaryMetrics,
                    secondaryMetrics: secondaryMetrics
                )

                jmhElements.append(jmh)
            }
        }

        let bytesArray = try JSONEncoder().encode(jmhElements)
        resultString = String(bytes: bytesArray, encoding: .utf8)!

        return resultString
    }
}
