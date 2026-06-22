//
// Copyright (c) 2023 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

import Benchmark
import Foundation
import SystemPackage

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#else
#error("Unsupported Platform")
#endif

extension BenchmarkTool {
    enum OutputPath {
        case stdout
        case file(FilePath)
    }

    func outputPath(hostIdentifier: String? = nil, fileName: String) -> OutputPath {
        var outputPath: FilePath

        if let path = (thresholdsOperation == nil) ? path : thresholdsPath {
            if path == "stdout" {
                return .stdout
            }

            let subPath = FilePath(path).removingRoot()

            if FilePath(path).root != nil {
                outputPath = FilePath(root: FilePath(path).root)
            } else {
                outputPath = FilePath(".")
            }
            outputPath.createSubPath(subPath)
            outputPath.append(subPath.components)
        } else {
            outputPath = FilePath(".")
        }

        var csvFile = FilePath()
        if let hostIdentifier {
            csvFile.append("\(hostIdentifier).\(fileName)")
        } else {
            csvFile.append(fileName)
        }

        outputPath.append(csvFile.components)

        return .file(outputPath)
    }

    func write(
        exportData: String,
        hostIdentifier: String? = nil,
        fileName: String = "results.txt"
    ) throws {
        // Set up desired output path and create any intermediate directories for structure as required:
        let outputPath: FilePath
        switch self.outputPath(hostIdentifier: hostIdentifier, fileName: fileName) {
        case .stdout:
            print(exportData)
            return
        case .file(let path):
            outputPath = path
        }

        print("Writing to \(outputPath)")

        printFailedBenchmarks()

        do {
            let fd = try FileDescriptor.open(
                outputPath,
                .writeOnly,
                options: [.truncate, .create],
                permissions: .ownerReadWrite
            )

            do {
                try fd.closeAfter {
                    do {
                        var bytes = exportData
                        try bytes.withUTF8 {
                            _ = try fd.write(UnsafeRawBufferPointer($0))
                        }
                    } catch {
                        print("Failed to write to file \(outputPath) [\(String(reflecting: error))]")
                    }
                }
            } catch {
                print("Failed to close fd for \(outputPath) after write [\(String(reflecting: error))].")
            }
        } catch {
            if errno == EPERM {
                print("Lacking permissions to write to \(outputPath)")
                print("Give benchmark plugin permissions by running with e.g.:")
                print("")
                print("swift package --allow-writing-to-package-directory benchmark --format jmh")
                print("")
            } else {
                print("Failed to open file \(outputPath), errno = [\(errno)]")
            }
        }
    }

    /// Writes raw data into a file.
    /// - Parameters:
    ///   - exportData: A buffer in the form of an array of unsigned 8-bit integers.
    ///   - hostIdentifier: The identifier of the host running the benchmarks.
    ///   - fileName: The filename to write into.
    func write(
        exportData: [UInt8],
        hostIdentifier: String? = nil,
        fileName: String = "results.txt"
    ) throws {
        var outputPath = FilePath(".")

        var jsonFile = FilePath()
        if let hostIdentifier {
            jsonFile.append("\(hostIdentifier).\(fileName)")
        } else {
            jsonFile.append(fileName)
        }

        outputPath.append(jsonFile.components)

        print("Writing to \(outputPath)")

        printFailedBenchmarks()

        do {
            let fd = try FileDescriptor.open(
                outputPath,
                .writeOnly,
                options: [.truncate, .create],
                permissions: .ownerReadWrite
            )

            do {
                try fd.closeAfter {
                    do {
                        try exportData.withUnsafeBytes { rawBuffer in
                            _ = try fd.write(rawBuffer)
                        }
                    } catch {
                        print("Failed to write to file \(outputPath) [\(String(reflecting: error))]")
                    }
                }
            } catch {
                print("Failed to close fd for \(outputPath) after write [\(String(reflecting: error))].")
            }
        } catch {
            if errno == EPERM {
                print("Lacking permissions to write to \(outputPath)")
                print("Give benchmark plugin permissions by running with e.g.:")
                print("")
                print("swift package --allow-writing-to-package-directory benchmark --format histogramEncoded")
                print("")
            } else {
                print("Failed to open file \(outputPath), errno = [\(errno)]")
            }
        }
    }

    func exportResults(baseline: BenchmarkBaseline) throws {
        let baselineName = baseline.baselineName
        switch format {
        case .text, .markdown:
            prettyPrint(baseline, header: "Baseline '\(baselineName)'")
        case .influx:
            try write(
                exportData: "\(convertToInflux(baseline))",
                fileName: "\(baselineName).influx.csv"
            )
        case .histogram:
            try baseline.results.forEach { key, results in
                try results.forEach { values in
                    let outputString = values.statistics.histogram
                    let description = values.metric.rawDescription
                    try write(
                        exportData: "\(outputString)",
                        fileName: cleanupStringForShellSafety(
                            "\(baselineName).\(key.target).\(key.name).\(description).histogram.txt"
                        )
                    )
                }
            }
        case .jmh:
            try write(
                exportData: "\(convertToJMH(baseline))",
                fileName: cleanupStringForShellSafety("\(baselineName).jmh.json")
            )
        case .histogramSamples:
            try baseline.results.forEach { key, results in
                var outputString = ""

                try results.forEach { values in
                    let histogram = values.statistics.histogram

                    outputString += "\(values.metric.description) \(values.unitDescriptionPretty)\n"

                    histogram.recordedValues()
                        .forEach { value in
                            for _ in 0..<value.count {
                                outputString += "\(values.normalize(Int(value.value)))\n"
                            }
                        }
                    let description = values.metric.rawDescription
                    try write(
                        exportData: "\(outputString)",
                        fileName: cleanupStringForShellSafety(
                            "\(baselineName).\(key.target).\(key.name).\(description).histogram.samples.tsv"
                        )
                    )
                    outputString = ""
                }
            }
        case .histogramEncoded:
            try baseline.results.forEach { key, results in
                let encoder = JSONEncoder()

                try results.forEach { values in
                    let histogram = values.statistics.histogram
                    let jsonData = try encoder.encode(histogram)
                    let description = values.metric.rawDescription
                    if let encodedData = String(data: jsonData, encoding: .utf8) {
                        try write(
                            exportData: encodedData,
                            fileName: cleanupStringForShellSafety(
                                "\(baselineName).\(key.target).\(key.name).\(description).histogram.json"
                            )
                        )
                    } else {
                        fatalError("Failed to encode histogram data \(jsonData.debugDescription)")
                    }
                }
            }
        case .histogramPercentiles:
            var outputString = ""

            try baseline.results.forEach { key, results in
                try results.forEach { values in
                    let histogram = values.statistics.histogram

                    outputString += "Percentile\t" + "\(values.metric.description) \(values.scaledUnitDescriptionPretty)\n"

                    for percentile in 0...100 {
                        outputString +=
                            "\(percentile)\t"
                            + "\(values.scale(Int(histogram.valueAtPercentile(Double(percentile)))))\n"
                    }

                    let description = values.metric.rawDescription
                    try write(
                        exportData: "\(outputString)",
                        fileName: cleanupStringForShellSafety(
                            "\(baselineName).\(key.target).\(key.name).\(description).histogram.percentiles.tsv"
                        )
                    )
                    outputString = ""
                }
            }
        case .metricP90AbsoluteThresholds:
            let jsonEncoder = JSONEncoder()
            jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            try baseline.results.forEach { key, results in
                let fileName = cleanupStringForShellSafety("\(key.target).\(key.name).p90.json")

                var outputResults: [BenchmarkMetric: BenchmarkThreshold] = [:]

                let wantsRelative = self.wantsRelativeThresholds
                let wantsRange = self.wantsRangeThresholds
                let wantsRelativeOrRange = wantsRelative || wantsRange

                /// If it's the first run or if relative/range are not specified, then
                /// override the thresholds file with the new results we have.
                /// If runNumber is zero that'd mean this is not part of a multi-run benchmark,
                /// so we'll still try to update thresholds instead of overriding them.
                if runNumber == 1 || !wantsRelativeOrRange {
                    for values in results {
                        outputResults[values.metric] = .absolute(
                            Int(values.statistics.histogram.valueAtPercentile(90.0))
                        )
                    }

                } else {
                    /// If it's not the first run and any of relative/range are specified, then
                    /// merge the new results with the existing thresholds.

                    var currentThresholds: [BenchmarkMetric: BenchmarkThreshold]?

                    switch self.outputPath(fileName: fileName) {
                    case .stdout:
                        currentThresholds = nil
                    case .file(let path):
                        currentThresholds = Self.makeBenchmarkThresholds(
                            path: path,
                            benchmarkIdentifier: key
                        )
                    }

                    outputResults = currentThresholds ?? [:]

                    for values in results {
                        let metric = values.metric
                        let newValue = values.statistics.histogram.valueAtPercentile(90.0)

                        var relativeResult: BenchmarkThreshold.RelativeOrRange.Relative?
                        var rangeResult: BenchmarkThreshold.RelativeOrRange.Range?
                        if wantsRelativeOrRange {
                            let newValue = Double(Int(truncatingIfNeeded: newValue))
                            /// Prefer Double to keep precision
                            var min = Double(newValue)
                            var max = Double(newValue)

                            /// Load current min/max values from static thresholds file
                            switch currentThresholds?[metric] {
                            case .absolute(let value):
                                min = Double(value)
                                max = Double(value)
                            case .relativeOrRange(let relativeOrRange):
                                /// If for "wantsRelative", we prefer to use the min/max
                                if let range = relativeOrRange.range {
                                    min = Double(range.min)
                                    max = Double(range.max)
                                } else if let relative = relativeOrRange.relative {
                                    let base = Double(relative.base)
                                    let diff = (base / 100) * relative.tolerancePercentage
                                    min = base - diff
                                    max = base + diff
                                }
                            case .none: break
                            }

                            /// Update the min/max values
                            min = Swift.min(min, Double(newValue))
                            max = Swift.max(max, Double(newValue))

                            /// If min == max, it won't make a difference than using .absolute
                            if min != max {
                                if wantsRange {
                                    rangeResult = .init(min: Int(min), max: Int(max))
                                }

                                if wantsRelative {
                                    /// Calculate base and tolerancePercentage
                                    let base = (min + max) / 2
                                    let diff = max - base
                                    let diffPercentage = (base == 0) ? 0 : (diff / base * 100)
                                    let tolerancePercentage = Statistics.roundToDecimalPlaces(diffPercentage, 2, .up)

                                    relativeResult = .init(
                                        base: Int(base),
                                        tolerancePercentage: tolerancePercentage
                                    )
                                }
                            }
                        }

                        if relativeResult == nil && rangeResult == nil {
                            outputResults[metric] = .absolute(Int(truncatingIfNeeded: newValue))
                        } else {
                            /// If we have a relative/range threshold but it's not specified in the command for
                            /// this run to update it, we still would like to keep the non-updated existing threshold.
                            switch currentThresholds?[metric] {
                            case .relativeOrRange(let currentRelativeOrRange):
                                relativeResult = relativeResult ?? currentRelativeOrRange.relative
                                rangeResult = rangeResult ?? currentRelativeOrRange.range
                            case .absolute, .none:
                                break
                            }

                            outputResults[metric] = .relativeOrRange(
                                BenchmarkThreshold.RelativeOrRange(
                                    relative: relativeResult,
                                    range: rangeResult
                                )
                            )
                        }
                    }
                }

                let jsonResultData = try jsonEncoder.encode(outputResults)

                if let stringOutput = String(data: jsonResultData, encoding: .utf8) {
                    try write(
                        exportData: stringOutput,
                        fileName: fileName
                    )
                } else {
                    print("Failed to encode json for \(outputResults)")
                }
            }
        case .jsonSmallerIsBetter:
            try write(
                exportData: "\(convertToJSON(baseline, polarity: .prefersSmaller))",
                fileName: cleanupStringForShellSafety("\(baselineName).json")
            )
        case .jsonBiggerIsBetter:
            try write(
                exportData: "\(convertToJSON(baseline, polarity: .prefersLarger))",
                fileName: cleanupStringForShellSafety("\(baselineName)-bigger-is-better.json")
            )
        }
    }

    func printFailedBenchmarks() {
        if !failedBenchmarkList.isEmpty {
            print("The following benchmarks failed: \n")
            for benchmark in failedBenchmarkList {
                print(benchmark)
            }
        }
    }
}
