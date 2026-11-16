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
    func write(
        exportData: String,
        hostIdentifier: String? = nil,
        fileName: String = "results.txt",
        exportPath: String? = nil
    ) throws {
        // Set up desired output path and create any intermediate directories for structure as required:
        var outputPath: FilePath

        if let path = exportPath ?? (thresholdsOperation == nil ? self.path : thresholdsPath) {
            if path == "stdout" {
                print(exportData)
                return
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
            try baseline.results.forEach { key, results in
                let jsonEncoder = JSONEncoder()
                jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]

                var outputResults: [String: BenchmarkThresholds.AbsoluteThreshold] = [:]
                results.forEach { values in
                    outputResults[values.metric.rawDescription] = Int(
                        values.statistics.histogram.valueAtPercentile(90.0)
                    )
                }

                let jsonResultData = try jsonEncoder.encode(outputResults)

                if let stringOutput = String(data: jsonResultData, encoding: .utf8) {
                    try write(
                        exportData: stringOutput,
                        fileName: cleanupStringForShellSafety("\(key.target).\(key.name).p90.json")
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
