//
// Copyright (c) 2024 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

import Benchmark
import SystemPackage
import TextTable

private let percentileWidth = 20
private let maxDescriptionWidth = 40

private struct ThresholdsTableEntry {
    enum Values {
        case absolute(p90: Int, absoluteTolerance: Int, relativeTolerance: Double)
        case relativeOrRange(BenchmarkThreshold.RelativeOrRange)
    }

    var description: String
    var value: Values
}

extension BenchmarkTool {
    func printThresholds(_ staticThresholdsPerBenchmark: [BenchmarkIdentifier: [BenchmarkMetric: BenchmarkThreshold]]) {

        guard !staticThresholdsPerBenchmark.isEmpty else {
            print("No thresholds defined.")
            return
        }

        print("")

        var tableEntries: [ThresholdsTableEntry] = []
        let table = TextTable<ThresholdsTableEntry> { entry in
            var columns: [Column] = []
            columns.reserveCapacity(4)

            columns.append(
                Column(title: "Metric", value: entry.description, width: maxDescriptionWidth, align: .left),
            )

            switch entry.value {
            case .absolute(let p90, let absoluteTolerance, let relativeTolerance):
                columns.append(contentsOf: [
                    Column(title: "Threshold .p90", value: p90, width: percentileWidth, align: .right),
                    Column(title: "Allowed %", value: relativeTolerance, width: percentileWidth, align: .right),
                    Column(title: "Allowed Δ", value: absoluteTolerance, width: percentileWidth, align: .right),
                ])
            case .relativeOrRange(let relativeOrRange):
                if let relative = relativeOrRange.relative {
                    let tolerancePercentage = Statistics.roundToDecimalPlaces(relative.tolerancePercentage, 2)
                    columns.append(contentsOf: [
                        Column(
                            title: "Allowed %",
                            value: "\(relative.base) ± \(tolerancePercentage)%",
                            width: percentileWidth,
                            align: .right
                        )
                    ])
                }
                if let range = relativeOrRange.range {
                    columns.append(contentsOf: [
                        Column(title: "Allowed min", value: "\(range.min)", width: percentileWidth, align: .right),
                        Column(title: "Allowed max", value: "\(range.max)", width: percentileWidth, align: .right),
                    ])
                }
            }

            return columns
        }

        staticThresholdsPerBenchmark.forEach { benchmarkIdentifier, staticThresholds in
            print("\(benchmarkIdentifier.name)")

            let thresholdDeviations =
                benchmarks.first(where: {
                    benchmarkIdentifier
                        == .init(target: $0.target, name: $0.name)
                })?
                .configuration.thresholds ?? .init()

            staticThresholds.forEach { threshold in
                switch threshold.value {
                case .absolute(let value):
                    let absoluteThreshold = thresholdDeviations[threshold.key]?.absolute[.p90] ?? 0
                    let relativeThreshold = thresholdDeviations[threshold.key]?.relative[.p90] ?? 0

                    tableEntries.append(
                        .init(
                            description: threshold.key.description,
                            value: .absolute(
                                p90: value,
                                absoluteTolerance: absoluteThreshold,
                                relativeTolerance: relativeThreshold
                            )
                        )
                    )
                case .relativeOrRange(let relativeOrRange):
                    tableEntries.append(
                        .init(
                            description: threshold.key.description,
                            value: .relativeOrRange(relativeOrRange)
                        )
                    )
                }
            }
            table.print(tableEntries, style: format.tableStyle)
            tableEntries = []
        }
    }
}
