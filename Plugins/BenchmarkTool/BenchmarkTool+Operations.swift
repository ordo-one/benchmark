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
import Foundation
import SystemPackage
import TextTable

// run/list benchmarks by talking to controlled process
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
    mutating func queryBenchmarks(_ benchmarkPath: String) throws {
        try write(.list)
        outerloop: while true {
            let benchmarkReply = try read()

            switch benchmarkReply {
            case .list(let benchmark):
                benchmark.executablePath = benchmarkPath
                benchmark.target = FilePath(benchmarkPath).lastComponent!.description
                if metrics.isEmpty == false {
                    benchmark.configuration.metrics = metrics
                }
                benchmarks.append(benchmark)
            case .end:
                break outerloop
            case .error(let description):
                failBenchmark(description)
                break outerloop
            default:
                print("Unexpected reply \(benchmarkReply)")
            }
        }
    }

    mutating func runBenchmark(target: String, benchmark: Benchmark) throws -> BenchmarkResults {
        var benchmarkResults: BenchmarkResults = [:]
        try write(.run(benchmark: benchmark))

        outerloop: while true {
            let benchmarkReply = try read()

            switch benchmarkReply {
            case .result(benchmark: let benchmark, results: let results):
                let filteredResults = results.filter { benchmark.configuration.metrics.contains($0.metric) }
                benchmarkResults[BenchmarkIdentifier(target: target, name: benchmark.name)] = filteredResults
            case .end:
                break outerloop
            case .error(let description):
                failBenchmark(description, exitCode: .benchmarkJobFailed, "\(target)/\(benchmark.name)")

                benchmarkResults[BenchmarkIdentifier(target: target, name: benchmark.name)] = []
                break outerloop
            default:
                print("Unexpected reply \(benchmarkReply)")
            }
        }

        return benchmarkResults
    }

    func cleanupStringForShellSafety(_ string: String) -> String {
        var cleanedString = string.replacingOccurrences(of: "/", with: "_")
        cleanedString = cleanedString.replacingOccurrences(of: " ", with: "_")
        return cleanedString
    }

    struct NameAndTarget: Hashable {
        let name: String
        let target: String
    }

    mutating func postProcessBenchmarkResults() throws {
        // Turn on buffering again for output
        setvbuf(stdout, nil, _IOFBF, Int(BUFSIZ))

        switch command {
        case .`init`:
            return
        case .thresholds:
            guard let thresholdsOperation else {
                fatalError("Thresholds command without specifying a thresholds operation, internal error in Benchmark")
            }

            switch thresholdsOperation {
            case .read:
                print("Reading thresholds from \"\(thresholdsPath)\"")

                var p90Thresholds: [BenchmarkIdentifier: [BenchmarkMetric: BenchmarkThresholds.AbsoluteThreshold]] = [:]
                try benchmarks.forEach { benchmark in
                    if try shouldIncludeBenchmark(benchmark.baseName) {
                        if let thresholds = BenchmarkTool.makeBenchmarkThresholds(
                            path: thresholdsPath,
                            benchmarkIdentifier: benchmark.benchmarkIdentifier
                        ) {
                            p90Thresholds[benchmark.benchmarkIdentifier] = thresholds
                        }
                    }
                }
                printThresholds(p90Thresholds)
            case .update:
                "Writing Thresholds".printAsHeader()
                format = .metricP90AbsoluteThresholds
                try benchmarkBaselines.forEach { baseline in
                    try exportResults(baseline: baseline)
                }
            case .check:
                guard benchmarkBaselines.count == 1,
                    let currentBaseline = benchmarkBaselines.first,
                    let baselineName = baseline.first
                else {
                    print(
                        "Can only do absolute threshold violation checks for a single benchmark baseline, got: \(benchmarkBaselines.count) baselines. \(benchmarkBaselines.map { $0.baselineName })"
                    )
                    return
                }

                if benchmarks.isEmpty { // if we read from baseline and didn't run them, we put in some fake entries for the compare
                    currentBaseline.results.keys.forEach { baselineKey in
                        if let benchmark: Benchmark = .init(baselineKey.name, closure: { _ in }) {
                            benchmark.target = baselineKey.target
                            benchmarks.append(benchmark)
                        }
                    }
                }

                benchmarks = benchmarks.filter {
                    do {
                        return try shouldIncludeBenchmark($0.name)
                    } catch {
                        return false
                    }
                }

                var p90Thresholds: [BenchmarkIdentifier: [BenchmarkMetric: BenchmarkThresholds.AbsoluteThreshold]] = [:]

                if noProgress == false {
                    print("")
                    print("Reading thresholds from \"\(thresholdsPath)\"")
                }

                benchmarks.forEach { benchmark in
                    if let thresholds = BenchmarkTool.makeBenchmarkThresholds(
                        path: thresholdsPath,
                        benchmarkIdentifier: benchmark.benchmarkIdentifier
                    ) {
                        p90Thresholds[benchmark.benchmarkIdentifier] = thresholds
                    }
                }

                if p90Thresholds.isEmpty {
                    if benchmarks.count == 0 {
                        failBenchmark(
                            "No benchmarks matching filter selection, failing threshold check.",
                            exitCode: .thresholdRegression
                        )
                    }
                    failBenchmark(
                        "Could not find any matching absolute thresholds at path [\(thresholdsPath)], failing threshold check.",
                        exitCode: .thresholdRegression
                    )
                }

                if noProgress == false {
                    print("")
                    print("Checking \(benchmarks.map { $0.target + ":" + $0.name })")
                    print("")
                }

                let deviationResults = currentBaseline.failsAbsoluteThresholdChecks(
                    benchmarks: benchmarks,
                    p90Thresholds: p90Thresholds
                )

                if deviationResults.regressions.isEmpty && deviationResults.improvements.isEmpty {
                    print("The baseline '\(baselineName)' is EQUAL to the defined thresholds.")
                } else {
                    if !deviationResults.regressions.isEmpty {
                        prettyPrintDeviation(
                            baselineName: "p90 threshold",
                            comparingBaselineName: baselineName,
                            deviationResults: deviationResults.regressions,
                            deviationTitle: "Deviations worse than threshold"
                        )
                    }
                    if !deviationResults.improvements.isEmpty {
                        prettyPrintDeviation(
                            baselineName: "p90 threshold",
                            comparingBaselineName: baselineName,
                            deviationResults: deviationResults.improvements,
                            deviationTitle: "Deviations better than threshold"
                        )
                    }
                    if !deviationResults.regressions.isEmpty {
                        failBenchmark(
                            "The baseline '\(baselineName)' is WORSE than the defined thresholds.",
                            exitCode: .thresholdRegression
                        )
                    } else {
                        failBenchmark(
                            "The baseline '\(baselineName)' is BETTER than the defined thresholds.",
                            exitCode: .thresholdImprovement
                        )
                    }
                }
            }
        case .baseline:
            guard let baselineOperation else {
                fatalError("Baseline command without specifying a baseline operation, internal error in Benchmark")
            }

            switch baselineOperation {
            case .delete:
                targets.forEach { target in
                    baseline.forEach {
                        removeBaselinesNamed(target: target, baselineName: $0)
                    }
                }
                return
            case .list:
                printAllBaselines()
            case .compare:
                guard benchmarkBaselines.count == 2 else {
                    print("Can only compare exactly 2 benchmark baselines, got: \(benchmarkBaselines.count) baselines.")
                    return
                }

                prettyPrintDelta(currentBaseline: benchmarkBaselines[0], baseline: benchmarkBaselines[1])
            case .update:
                guard benchmarkBaselines.count == 1 else {
                    print("Can only update a single benchmark baseline, got: \(benchmarkBaselines.count) baselines.")
                    return
                }

                let baseline = benchmarkBaselines[0]
                if let baselineName = self.baseline.first {
                    try baseline.targets.forEach { target in
                        let results = baseline.results.filter { $0.key.target == target }
                        let subset = BenchmarkBaseline(
                            baselineName: baselineName,
                            machine: baseline.machine,
                            results: results
                        )
                        try write(
                            baseline: subset,
                            baselineName: baselineName,
                            target: target
                        )
                    }

                    if quiet == false {
                        print("")
                        print("Updated baseline '\(baselineName)'")
                    }
                } else {
                    failBenchmark("Could not get first baselinename.", exitCode: .baselineNotFound)
                }

            case .check:
                if checkAbsolute {
                    guard benchmarkBaselines.count == 1,
                        let currentBaseline = benchmarkBaselines.first,
                        let baselineName = baseline.first
                    else {
                        print(
                            "Can only do absolute threshold violation checks for a single benchmark baseline, got: \(benchmarkBaselines.count) baselines. \(benchmarkBaselines.map { $0.baselineName })"
                        )
                        return
                    }

                    if benchmarks.isEmpty { // if we read from baseline and didn't run them, we put in some fake entries for the compare
                        currentBaseline.results.keys.forEach { baselineKey in
                            if let benchmark: Benchmark = .init(baselineKey.name, closure: { _ in }) {
                                benchmark.target = baselineKey.target
                                benchmarks.append(benchmark)
                            }
                        }
                    }

                    benchmarks = benchmarks.filter {
                        do {
                            return try shouldIncludeBenchmark($0.name)
                        } catch {
                            return false
                        }
                    }

                    var p90Thresholds: [BenchmarkIdentifier: [BenchmarkMetric: BenchmarkThresholds.AbsoluteThreshold]] =
                        [:]

                    if let benchmarkPath = checkAbsolutePath { // load statically defined thresholds for .p90
                        benchmarks.forEach { benchmark in
                            if let thresholds = BenchmarkTool.makeBenchmarkThresholds(
                                path: benchmarkPath,
                                benchmarkIdentifier: benchmark.benchmarkIdentifier
                            ) {
                                p90Thresholds[benchmark.benchmarkIdentifier] = thresholds
                            }
                        }

                        if p90Thresholds.isEmpty {
                            if benchmarks.count == 0 {
                                failBenchmark(
                                    "No benchmarks matching filter selection, failing threshold check.",
                                    exitCode: .thresholdRegression
                                )
                            }
                            failBenchmark(
                                "Could not find any matching absolute thresholds at path [\(benchmarkPath)], failing threshold check.",
                                exitCode: .thresholdRegression
                            )
                        }
                    }
                    print("")

                    let deviationResults = currentBaseline.failsAbsoluteThresholdChecks(
                        benchmarks: benchmarks,
                        p90Thresholds: p90Thresholds
                    )

                    if deviationResults.regressions.isEmpty && deviationResults.improvements.isEmpty {
                        print(
                            "Baseline '\(baselineName)' is EQUAL to the defined absolute baseline thresholds. (--check-absolute)"
                        )
                    } else {
                        if !deviationResults.regressions.isEmpty {
                            prettyPrintDeviation(
                                baselineName: "p90 threshold",
                                comparingBaselineName: baselineName,
                                deviationResults: deviationResults.regressions,
                                deviationTitle: "Deviations worse than threshold"
                            )
                        }
                        if !deviationResults.improvements.isEmpty {
                            prettyPrintDeviation(
                                baselineName: "p90 threshold",
                                comparingBaselineName: baselineName,
                                deviationResults: deviationResults.improvements,
                                deviationTitle: "Deviations better than threshold"
                            )
                        }
                        if !deviationResults.regressions.isEmpty {
                            failBenchmark(
                                "New baseline '\(baselineName)' is WORSE than the defined absolute baseline thresholds. (--check-absolute)",
                                exitCode: .thresholdRegression
                            )
                        } else {
                            failBenchmark(
                                "New baseline '\(baselineName)' is BETTER than the defined absolute baseline thresholds. (--check-absolute)",
                                exitCode: .thresholdImprovement
                            )
                        }
                    }
                } else {
                    guard benchmarkBaselines.count == 2 else {
                        print(
                            "Can only do threshold violation checks for exactly 2 benchmark baselines, got: \(benchmarkBaselines.count) baselines."
                        )
                        return
                    }

                    let currentBaseline = benchmarkBaselines[0]
                    let checkBaseline = benchmarkBaselines[1]
                    let baselineName = baseline[0]
                    let checkBaselineName = baseline[1]
                    let deviationResults = checkBaseline.deviationsComparedToBaseline(
                        currentBaseline,
                        benchmarks: benchmarks
                    )

                    print("")
                    if deviationResults.regressions.isEmpty {
                        if deviationResults.improvements.isEmpty {
                            print(
                                "New baseline '\(checkBaselineName)' is WITHIN the '\(baselineName)' baseline thresholds."
                            )
                        } else {
                            prettyPrintDeviation(
                                baselineName: baselineName,
                                comparingBaselineName: checkBaselineName,
                                deviationResults: deviationResults.improvements
                            )
                            failBenchmark(
                                "New baseline '\(checkBaselineName)' is BETTER than the '\(baselineName)' baseline thresholds.",
                                exitCode: .thresholdImprovement
                            )
                        }
                    } else {
                        prettyPrintDeviation(
                            baselineName: baselineName,
                            comparingBaselineName: checkBaselineName,
                            deviationResults: deviationResults.regressions
                        )
                        failBenchmark(
                            "New baseline '\(checkBaselineName)' is WORSE than the '\(baselineName)' baseline thresholds.",
                            exitCode: .thresholdRegression
                        )
                    }
                }
            case .read:
                if benchmarkBaselines.isEmpty {
                    print("No baseline found.")
                } else {
                    try benchmarkBaselines.forEach { baseline in
                        try exportResults(baseline: baseline)
                    }
                }
            }
        case .run:
            guard let baseline = benchmarkBaselines.first else {
                fatalError("Internal error, no baseline data after benchmark run.")
            }

            try exportResults(baseline: baseline)
        case .query:
            break
        case .list:
            break
        }
    }

    func listBenchmarks() throws {
        print("")
        benchmarkExecutablePaths.forEach { benchmarkExecutablePath in
            print("Target '\(FilePath(benchmarkExecutablePath).lastComponent!)' available benchmarks:")
            benchmarks.forEach { benchmark in
                if benchmark.executablePath == benchmarkExecutablePath {
                    print("\(benchmark.name)")
                }
            }
            print("")
        }
    }
}
