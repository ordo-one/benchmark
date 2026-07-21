//
// Copyright (c) 2022 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

import Benchmark
import BenchmarkShared
import SystemPackage
import TextTable

private let percentileWidth = 9
private let maxDescriptionWidth = 100

extension OutputFormat {
    var tableStyle: TextTableStyle.Type {
        if case .markdown = self {
            return Style.pipe
        }
        return Style.fancy
    }
}

extension BenchmarkTool {
    private func printMarkdown(_ markdown: String, terminator: String = "\n") {
        if format == .markdown {
            print(markdown, terminator: terminator)
        }
    }

    private func printText(_ markdown: String, terminator: String = "\n") {
        if format == .text {
            print(markdown, terminator: terminator)
        }
    }

    private func formatLargeNumber(_ value: Int) -> String {
        if abs(value) >= 10_000_000 { // 8 digits or more
            let doubleValue = Double(value)
            return String(format: "%.2e", doubleValue)
        }
        return "\(value)"
    }

    private func formatTableEntry(_ base: Int, _ comparison: Int, _ reversePolarity: Bool = false) -> Int {
        guard comparison != 0, base != 0 else {
            return 0
        }
        var roundedDiff = 100.0 - (100.0 * Double(comparison) / Double(base))
        roundedDiff.round(.toNearestOrEven)
        let diff = Int(roundedDiff)

        if reversePolarity {
            return -1 * diff
        }
        return diff
    }

    private func printMachine(_ machine: BenchmarkMachine, _ header: String) {
        let separator = String(repeating: "=", count: machine.kernelVersion.count)
        print("")
        printMarkdown("## ", terminator: "")
        printText(separator)
        print(header)
        printText(separator)
        print("")
        printMarkdown("```")
        print(
            "Host '\(machine.hostname)' with \(machine.processors) '\(machine.processorType)' processors with \(machine.memory) GB memory, running:"
        )
        print("\(machine.kernelVersion)")
        printMarkdown("```")
        printText("")
    }

    fileprivate struct ScaledResults {
        fileprivate struct Percentiles {
            var p0: Int = 0
            var p25: Int = 0
            var p50: Int = 0
            var p75: Int = 0
            var p90: Int = 0
            var p99: Int = 0
            var p100: Int = 0
        }

        var description: String
        var percentiles: Percentiles
        var samples: Int
    }

    private func _prettyPrint(
        title: String,
        key: String,
        results: [BenchmarkBaseline.ResultsEntry],
        width: Int = 30,
        useGroupingDescription: Bool = false
    ) {
        let table = TextTable<ScaledResults> {
            [
                Column(title: title, value: "\($0.description)", width: width, align: .left),
                Column(title: "p0", value: formatLargeNumber($0.percentiles.p0), width: percentileWidth, align: .right),
                Column(
                    title: "p25",
                    value: formatLargeNumber($0.percentiles.p25),
                    width: percentileWidth,
                    align: .right
                ),
                Column(
                    title: "p50",
                    value: formatLargeNumber($0.percentiles.p50),
                    width: percentileWidth,
                    align: .right
                ),
                Column(
                    title: "p75",
                    value: formatLargeNumber($0.percentiles.p75),
                    width: percentileWidth,
                    align: .right
                ),
                Column(
                    title: "p90",
                    value: formatLargeNumber($0.percentiles.p90),
                    width: percentileWidth,
                    align: .right
                ),
                Column(
                    title: "p99",
                    value: formatLargeNumber($0.percentiles.p99),
                    width: percentileWidth,
                    align: .right
                ),
                Column(
                    title: "p100",
                    value: formatLargeNumber($0.percentiles.p100),
                    width: percentileWidth,
                    align: .right
                ),
                Column(title: "Samples", value: formatLargeNumber($0.samples), width: percentileWidth, align: .right),
            ]
        }
        var scaledResults: [ScaledResults] = []
        results.forEach { result in
            var resultPercentiles = ScaledResults.Percentiles()

            let metrics = result.metrics
            let percentiles = metrics.statistics.percentiles()
            let shouldScale = self.scale == false && result.metrics.metric.useScalingFactor
            let adjustmentFunction: (Int) -> Int
            let description: String

            if shouldScale {
                description =
                    useGroupingDescription
                    ? "\(result.description) \(result.metrics.scaledUnitDescriptionPretty)"
                    : "\(result.metrics.metric.description) \(result.metrics.scaledUnitDescriptionPretty)"
                adjustmentFunction = result.metrics.scale
            } else {
                description =
                    useGroupingDescription
                    ? "\(result.description) \(result.metrics.unitDescriptionPretty)"
                    : "\(result.metrics.metric.description) \(result.metrics.unitDescriptionPretty)"
                adjustmentFunction = result.metrics.normalize
            }

            resultPercentiles.p0 = adjustmentFunction(percentiles[0])
            resultPercentiles.p25 = adjustmentFunction(percentiles[1])
            resultPercentiles.p50 = adjustmentFunction(percentiles[2])
            resultPercentiles.p75 = adjustmentFunction(percentiles[3])
            resultPercentiles.p90 = adjustmentFunction(percentiles[4])
            resultPercentiles.p99 = adjustmentFunction(percentiles[5])
            resultPercentiles.p100 = adjustmentFunction(percentiles[6])

            scaledResults.append(
                ScaledResults(
                    description: description,
                    percentiles: resultPercentiles,
                    samples: result.metrics.statistics.measurementCount
                )
            )
        }

        printMarkdown("### ", terminator: "")
        print("\(key)")
        printMarkdown("")

        table.print(scaledResults, style: format.tableStyle)
    }

    func prettyPrint(
        _ baseline: BenchmarkBaseline,
        header: String, // = "Benchmark results",
        hostIdentifier _: String? = nil
    ) {
        guard quiet == false else { return }

        printMachine(baseline.machine, header)

        switch grouping {
        case .benchmark:
            var width = 10
            let metrics = baseline.metricsMatching { _, _ in true }
            metrics.forEach { metric in
                width = max(width, metric.description.count)
            }
            width = min(maxDescriptionWidth, width + " (ms) *".count)

            baseline.targets.forEach { target in
                let separator = String(repeating: "=", count: "\(target)".count)
                var firstOutput = true

                baseline.benchmarkNames.forEach { benchmarkName in
                    let results = baseline.resultEntriesMatching { identifier, result in
                        (identifier.name == benchmarkName && identifier.target == target, result.metric.description)
                    }
                    if results.count > 0 {
                        if firstOutput {
                            printMarkdown("## ", terminator: "")
                            printText(separator)
                            print("\(target)")
                            printText(separator)
                            print("")
                            firstOutput = false
                        }
                        _prettyPrint(title: "Metric", key: benchmarkName, results: results, width: width)
                    }
                }
            }
        case .metric:
            var width = 10
            baseline.benchmarkIdentifiers.forEach { identifier in
                width = max(width, "\(identifier.target):\(identifier.name)".count)
            }
            width = min(maxDescriptionWidth, width + " (ms) *".count)

            baseline.benchmarkMetrics.forEach { metric in

                let results = baseline.resultEntriesMatching { identifier, result in
                    (result.metric == metric, "\(identifier.target):\(identifier.name)")
                }

                _prettyPrint(
                    title: "Test",
                    key: metric.description,
                    results: results,
                    width: width,
                    useGroupingDescription: true
                )
            }
        }
    }

    func prettyPrintDelta(
        currentBaseline: BenchmarkBaseline,
        baseline: BenchmarkBaseline,
        hostIdentifier _: String? = nil
    ) {
        printMachine(
            baseline.machine,
            "Comparing results between '\(currentBaseline.baselineName)' and '\(baseline.baselineName)'"
        )
        if currentBaseline.machine != baseline.machine {
            print("Warning: Machine configuration is different when comparing baselines, other config:")
            printMachine(currentBaseline.machine, "")
        }

        baseline.targets.forEach { target in
            let baseBaselineName = currentBaseline.baselineName
            let comparisonBaselineName = baseline.baselineName

            var keys = baseline.results.keys.sorted(by: { $0.name < $1.name })

            keys.removeAll(where: { $0.target != target })

            var firstOutput = true

            keys.forEach { key in
                if let value = baseline.results[key] {
                    guard let baselineComparison = currentBaseline.results[key] else {
                        //       print("No baseline to compare with for `\(key.target):\(key.name)`.")
                        return
                    }

                    if firstOutput {
                        printMarkdown("## ", terminator: "")
                        print("\(target)")
                        printText(
                            "============================================================================================================================"
                        )
                        print("")
                        firstOutput = false
                    }

                    printMarkdown("### ", terminator: "")
                    printText(
                        "----------------------------------------------------------------------------------------------------------------------------"
                    )
                    print("\(key.name) metrics")
                    printText(
                        "----------------------------------------------------------------------------------------------------------------------------"
                    )
                    print("")

                    value.forEach { currentResult in
                        var result = currentResult
                        if let base = baselineComparison.first(where: { $0.metric == result.metric }) {
                            let hideResults =
                                result.deviationsComparedWith(
                                    base,
                                    thresholds: result.thresholds ?? BenchmarkThresholds.none
                                )
                                .regressions.isEmpty

                            // We hide the markdown results if they are better than baseline to cut down noise
                            if format == .markdown {
                                if hideResults {
                                    print(
                                        "<details><summary>\(result.metric): results within specified thresholds, fold down for details.</summary>"
                                    )
                                    print("<p>")
                                    print("")
                                }
                            }

                            let displayBaseScaled = self.scale == false && base.metric.useScalingFactor
                            let displayResultScaled = self.scale == false && result.metric.useScalingFactor
                            let title =
                                displayBaseScaled
                                ? "\(result.metric.description) \(result.scaledUnitDescriptionPretty)"
                                : "\(result.metric.description) \(result.unitDescriptionPretty)"

                            let width = 40
                            let table = TextTable<ScaledResults> {
                                [
                                    Column(title: title, value: "\($0.description)", width: width, align: .center),
                                    Column(
                                        title: "p0",
                                        value: formatLargeNumber($0.percentiles.p0),
                                        width: percentileWidth,
                                        align: .right
                                    ),
                                    Column(
                                        title: "p25",
                                        value: formatLargeNumber($0.percentiles.p25),
                                        width: percentileWidth,
                                        align: .right
                                    ),
                                    Column(
                                        title: "p50",
                                        value: formatLargeNumber($0.percentiles.p50),
                                        width: percentileWidth,
                                        align: .right
                                    ),
                                    Column(
                                        title: "p75",
                                        value: formatLargeNumber($0.percentiles.p75),
                                        width: percentileWidth,
                                        align: .right
                                    ),
                                    Column(
                                        title: "p90",
                                        value: formatLargeNumber($0.percentiles.p90),
                                        width: percentileWidth,
                                        align: .right
                                    ),
                                    Column(
                                        title: "p99",
                                        value: formatLargeNumber($0.percentiles.p99),
                                        width: percentileWidth,
                                        align: .right
                                    ),
                                    Column(
                                        title: "p100",
                                        value: formatLargeNumber($0.percentiles.p100),
                                        width: percentileWidth,
                                        align: .right
                                    ),
                                    Column(
                                        title: "Samples",
                                        value: formatLargeNumber($0.samples),
                                        width: percentileWidth,
                                        align: .right
                                    ),
                                ]
                            }

                            // Rescale result to base if needed
                            result.timeUnits = base.timeUnits

                            var scaledResults: [ScaledResults] = []

                            let percentiles = result.statistics.percentiles()
                            let percentilesBase = base.statistics.percentiles()

                            var resultPercentiles = ScaledResults.Percentiles()
                            var basePercentiles = ScaledResults.Percentiles()
                            var adjustmentFunction: (Int) -> Int
                            let samples = result.statistics.measurementCount - base.statistics.measurementCount

                            if displayBaseScaled {
                                adjustmentFunction = base.scale
                            } else {
                                adjustmentFunction = base.normalize
                            }

                            basePercentiles.p0 = adjustmentFunction(percentilesBase[0])
                            basePercentiles.p25 = adjustmentFunction(percentilesBase[1])
                            basePercentiles.p50 = adjustmentFunction(percentilesBase[2])
                            basePercentiles.p75 = adjustmentFunction(percentilesBase[3])
                            basePercentiles.p90 = adjustmentFunction(percentilesBase[4])
                            basePercentiles.p99 = adjustmentFunction(percentilesBase[5])
                            basePercentiles.p100 = adjustmentFunction(percentilesBase[6])

                            scaledResults.append(
                                ScaledResults(
                                    description: baseBaselineName,
                                    percentiles: basePercentiles,
                                    samples: base.statistics.measurementCount
                                )
                            )

                            if displayResultScaled {
                                adjustmentFunction = result.scale
                            } else {
                                adjustmentFunction = result.normalize
                            }

                            resultPercentiles.p0 = adjustmentFunction(percentiles[0])
                            resultPercentiles.p25 = adjustmentFunction(percentiles[1])
                            resultPercentiles.p50 = adjustmentFunction(percentiles[2])
                            resultPercentiles.p75 = adjustmentFunction(percentiles[3])
                            resultPercentiles.p90 = adjustmentFunction(percentiles[4])
                            resultPercentiles.p99 = adjustmentFunction(percentiles[5])
                            resultPercentiles.p100 = adjustmentFunction(percentiles[6])

                            scaledResults.append(
                                ScaledResults(
                                    description: comparisonBaselineName,
                                    percentiles: resultPercentiles,
                                    samples: result.statistics.measurementCount
                                )
                            )

                            var deltaPercentiles = ScaledResults.Percentiles()

                            deltaPercentiles.p0 = resultPercentiles.p0 - basePercentiles.p0
                            deltaPercentiles.p25 = resultPercentiles.p25 - basePercentiles.p25
                            deltaPercentiles.p50 = resultPercentiles.p50 - basePercentiles.p50
                            deltaPercentiles.p75 = resultPercentiles.p75 - basePercentiles.p75
                            deltaPercentiles.p90 = resultPercentiles.p90 - basePercentiles.p90
                            deltaPercentiles.p99 = resultPercentiles.p99 - basePercentiles.p99
                            deltaPercentiles.p100 = resultPercentiles.p100 - basePercentiles.p100

                            scaledResults.append(
                                ScaledResults(
                                    description: BenchmarkMetric.delta.description,
                                    percentiles: deltaPercentiles,
                                    samples: samples
                                )
                            )

                            let reversedPolarity = base.metric.polarity == .prefersLarger

                            var percentageDeltaPercentiles = ScaledResults.Percentiles()

                            percentageDeltaPercentiles.p0 = formatTableEntry(
                                basePercentiles.p0,
                                resultPercentiles.p0,
                                reversedPolarity
                            )
                            percentageDeltaPercentiles.p25 = formatTableEntry(
                                basePercentiles.p25,
                                resultPercentiles.p25,
                                reversedPolarity
                            )
                            percentageDeltaPercentiles.p50 = formatTableEntry(
                                basePercentiles.p50,
                                resultPercentiles.p50,
                                reversedPolarity
                            )
                            percentageDeltaPercentiles.p75 = formatTableEntry(
                                basePercentiles.p75,
                                resultPercentiles.p75,
                                reversedPolarity
                            )
                            percentageDeltaPercentiles.p90 = formatTableEntry(
                                basePercentiles.p90,
                                resultPercentiles.p90,
                                reversedPolarity
                            )
                            percentageDeltaPercentiles.p99 = formatTableEntry(
                                basePercentiles.p99,
                                resultPercentiles.p99,
                                reversedPolarity
                            )
                            percentageDeltaPercentiles.p100 = formatTableEntry(
                                basePercentiles.p100,
                                resultPercentiles.p100,
                                reversedPolarity
                            )

                            scaledResults.append(
                                ScaledResults(
                                    description: "Improvement %",
                                    percentiles: percentageDeltaPercentiles,
                                    samples: samples
                                )
                            )

                            table.print(scaledResults, style: format.tableStyle)

                            if format == .markdown {
                                if hideResults {
                                    print("<p>")
                                    print("</details>")
                                    print("")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func prettyPrintDeviation(
        baselineName: String,
        comparingBaselineName: String,
        deviationResults: [BenchmarkResult.ThresholdDeviation],
        deviationTitle: String = "Threshold deviations"
    ) {
        guard quiet == false else { return }

        let metrics = deviationResults.map(\.metric).unique()

        var groupedDeviations = [NameAndTarget: [BenchmarkResult.ThresholdDeviation]]()
        groupedDeviations.reserveCapacity(deviationResults.count)
        for result in deviationResults {
            let nameAndTarget = NameAndTarget(name: result.name, target: result.target)
            groupedDeviations[nameAndTarget, default: []].append(result)
        }
        let sortedGroupedDeviations = groupedDeviations.sorted(by: { $0.key < $1.key })

        for (nameAndTarget, deviationResults) in sortedGroupedDeviations {
            printMarkdown("```")
            "\(deviationTitle) for \(nameAndTarget.target):\(nameAndTarget.name)".printAsHeader(addWhiteSpace: false)
            printMarkdown("```")

            metrics.forEach { metric in
                let filteredDeviations = deviationResults.filter { $0.metric == metric }

                let width = 40
                let percentileWidth = 15

                let table = TextTable<BenchmarkResult.ThresholdDeviation> {
                    var columns: [Column] = []
                    columns.reserveCapacity(4)

                    let sign =
                        switch $0.deviation {
                        case .absolute: "Δ"
                        case .relative: "%"
                        case .range: "↔"
                        }
                    let diffSign =
                        switch $0.deviation {
                        case .absolute, .range: "Δ"
                        case .relative: "%"
                        }
                    let unitDescription = metric.countable ? $0.units.description : $0.units.timeDescription
                    columns.append(
                        Column(
                            title: "\(metric.description) (\(unitDescription), \(sign))",
                            value: $0.percentile,
                            width: width,
                            align: .left
                        )
                    )

                    let baseValue = $0.baseValue

                    // If absolute or relative, we can calculate their columns together
                    let comparisonValue: String
                    let difference: String
                    let tolerance: String?
                    switch $0.deviation {
                    case .absolute(let compareTo, let diff, let tol):
                        comparisonValue = "\(compareTo)"
                        difference = diff.description
                        tolerance = tol.description
                    case .relative(let compareTo, let diff, let tol):
                        comparisonValue = "\(compareTo)"
                        difference = Statistics.roundToDecimalPlaces(diff, 2).description
                        tolerance = Statistics.roundToDecimalPlaces(tol, 2).description
                    case .range(let min, let max):
                        comparisonValue = "\(min) ... \(max)"
                        let diff = baseValue >= max ? baseValue - max : baseValue - min
                        difference = "\(diff)"
                        tolerance = nil
                    }

                    columns.append(contentsOf: [
                        Column(
                            title: baselineName,
                            value: comparisonValue,
                            width: percentileWidth,
                            align: .right
                        ),
                        Column(
                            title: comparingBaselineName,
                            value: baseValue,
                            width: percentileWidth,
                            align: .right
                        ),
                        Column(
                            title: "Difference \(diffSign)",
                            value: difference,
                            width: percentileWidth,
                            align: .right
                        ),
                    ])

                    if let tolerance = tolerance {
                        columns.append(
                            Column(
                                title: "Tolerance \(diffSign)",
                                value: tolerance,
                                width: percentileWidth,
                                align: .right
                            )
                        )
                    }

                    return columns
                }

                table.print(filteredDeviations.filter(\.deviation.isRange), style: format.tableStyle)
                table.print(filteredDeviations.filter(\.deviation.isAbsolute), style: format.tableStyle)
                table.print(filteredDeviations.filter(\.deviation.isRelative), style: format.tableStyle)
            }
        }
    }
}
