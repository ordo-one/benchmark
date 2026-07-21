//
// Copyright (c) 2022 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

// Reading / writing of benchmark baselines

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

struct BenchmarkMachine: Codable, Equatable {
    init(hostname: String, processors: Int, processorType: String, memory: Int, kernelVersion: String) {
        self.hostname = hostname
        self.processors = processors
        self.processorType = processorType
        self.memory = memory
        self.kernelVersion = kernelVersion
    }

    var hostname: String
    var processors: Int
    var processorType: String // e.g. arm64e
    var memory: Int // in GB
    var kernelVersion: String

    public static func == (lhs: BenchmarkMachine, rhs: BenchmarkMachine) -> Bool {
        lhs.processors == rhs.processors && lhs.processorType == rhs.processorType && lhs.memory == rhs.memory
    }
}

struct BenchmarkIdentifier: Codable, Hashable {
    init(target: String, name: String) {
        self.target = target
        self.name = name
    }

    var target: String // The name of the executable benchmark target id
    var name: String // The name of the benchmark

    public func hash(into hasher: inout Hasher) {
        hasher.combine(target)
        hasher.combine(name)
    }

    public static func == (lhs: BenchmarkIdentifier, rhs: BenchmarkIdentifier) -> Bool {
        lhs.name == rhs.name && lhs.target == rhs.target
    }
}

extension Benchmark {
    var benchmarkIdentifier: BenchmarkIdentifier {
        .init(target: self.target, name: self.name)
    }
}

public extension Sequence where Iterator.Element: Hashable {
    func unique() -> [Iterator.Element] {
        var seen: Set<Iterator.Element> = []
        return filter { seen.insert($0).inserted }
    }
}

typealias BenchmarkResultsByIdentifier = [BenchmarkIdentifier: [BenchmarkResult]]
struct BenchmarkBaseline: Codable {
    /// Used for writing to tables/exports
    struct ResultsEntry {
        var description: String
        var metrics: BenchmarkResult
    }

    init(baselineName: String, machine: BenchmarkMachine, results: [BenchmarkIdentifier: [BenchmarkResult]]) {
        self.baselineName = baselineName
        self.machine = machine
        self.results = results
    }

    //    @discardableResult
    mutating func merge(_ otherBaseline: BenchmarkBaseline) -> BenchmarkBaseline {
        if machine != otherBaseline.machine {
            print("Warning: Merging baselines from two different machine configurations")
        }
        results.merge(otherBaseline.results) { first, _ in first }

        return self
    }

    var baselineName: String
    var machine: BenchmarkMachine
    var results: BenchmarkResultsByIdentifier

    var benchmarkIdentifiers: [BenchmarkIdentifier] {
        Array(results.keys).sorted(by: { ($0.target, $0.name) < ($1.target, $1.name) })
    }

    var targets: [String] {
        benchmarkIdentifiers.map(\.target).unique().sorted()
    }

    var benchmarkNames: [String] {
        benchmarkIdentifiers.map(\.name).unique().sorted()
    }

    var benchmarkMetrics: [BenchmarkMetric] {
        var results: [BenchmarkMetric] = []
        self.results.forEach { _, resultVector in
            resultVector.forEach {
                results.append($0.metric)
            }
        }

        return results.unique().sorted(by: { $0.description < $1.description })
    }

    func resultEntriesMatching(_ closure: (BenchmarkIdentifier, BenchmarkResult) -> (Bool, String)) -> [ResultsEntry] {
        var results: [ResultsEntry] = []
        self.results.forEach { identifier, resultVector in
            resultVector.forEach {
                let (include, description) = closure(identifier, $0)
                if include {
                    results.append(ResultsEntry(description: description, metrics: $0))
                }
            }
        }

        return results.sorted(by: { $0.description < $1.description })
    }

    func metricsMatching(_ closure: (BenchmarkIdentifier, BenchmarkResult) -> Bool) -> [BenchmarkMetric] {
        var results: [BenchmarkMetric] = []
        self.results.forEach { identifier, resultVector in
            resultVector.forEach {
                if closure(identifier, $0) {
                    results.append($0.metric)
                }
            }
        }

        return results.sorted(by: { $0.description < $1.description })
    }

    func resultsMatching(_ closure: (BenchmarkIdentifier, BenchmarkResult) -> Bool) -> [BenchmarkResult] {
        var results: [BenchmarkResult] = []
        self.results.forEach { identifier, resultVector in
            resultVector.forEach {
                if closure(identifier, $0) {
                    results.append($0)
                }
            }
        }

        return results.sorted(by: { $0.metric.description < $1.metric.description })
    }

    func resultsByTarget(_ target: String) -> [String: [BenchmarkResult]] {
        let filteredResults = results.filter { $0.key.target == target }.sorted(by: { $0.key.name < $1.key.name })
        let resultsPerTarget = Dictionary(uniqueKeysWithValues: filteredResults.map { key, value in (key.name, value) })

        return resultsPerTarget
    }
}

let baselinesDirectory: String = ".benchmarkBaselines"

extension BenchmarkTool {
    func printAllBaselines() {
        var storagePath = FilePath(baselineStoragePath)
        storagePath.append(baselinesDirectory) // package/.benchmarkBaselines
        for file in storagePath.directoryEntries {
            if file.ends(with: ".") == false,
                file.ends(with: "..") == false
            {
                var subDirectory = storagePath
                if let directoryName = file.lastComponent {
                    subDirectory.append(directoryName)
                    "Baselines for \(directoryName.description)".printAsHeader()
                    for file in subDirectory.directoryEntries {
                        if let subdirectoryName = file.lastComponent {
                            if file.ends(with: ".") == false,
                                file.ends(with: "..") == false
                            {
                                print("\(subdirectoryName.description)")
                            }
                        }
                    }
                    print("")
                }
            }
        }
    }

    func removeBaselinesNamed(target: String, baselineName: String) {
        var storagePath = FilePath(baselineStoragePath)
        let filemanager = FileManager.default

        storagePath.append(baselinesDirectory) // package/.benchmarkBaselines
        for file in storagePath.directoryEntries {
            if file.ends(with: ".") == false,
                file.ends(with: "..") == false
            {
                if target == file.lastComponent!.description {
                    var subDirectory = storagePath
                    if let directoryName = file.lastComponent {
                        subDirectory.append(directoryName)
                        for file in subDirectory.directoryEntries {
                            if let subdirectoryName = file.lastComponent {
                                if file.ends(with: ".") == false,
                                    file.ends(with: "..") == false
                                {
                                    if subdirectoryName.description == baselineName {
                                        do {
                                            print("Removing baseline '\(baselineName)' for \(target)")
                                            try filemanager.removeItem(atPath: file.description)
                                        } catch {
                                            print("Failed to remove file \(file), error \(String(reflecting: error))")
                                            print(
                                                "Give benchmark plugin permissions to delete files by running with e.g.:"
                                            )
                                            print("")
                                            print(
                                                "swift package --allow-writing-to-package-directory benchmark baseline delete"
                                            )
                                            print("")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func write(
        baseline: BenchmarkBaseline,
        baselineName: String,
        target: String,
        hostIdentifier: String? = nil
    ) throws {
        // Set up desired output path and create any intermediate directories for structure as required:

        /*
         We store the baselines in a .benchmarkBaselines directory, by default in the package root path
         unless otherwise specified.
        
         The 'default' folder is used when no specific named baseline have been specified with the
         command line. Specified 'named' baselines is useful for convenient A/B/C testing and comparisons.
         Unless a host identifier have been specified on the command line (or in an environment variable),
         we by default store results in 'results.json', otherwise we will use the environment variable
         or command line to optionally specify a 'hostIdentifier' that allow for separation between
         different hosts if checking in baselines in repos.
        
         .benchmarkBaselines
         ├── target1
         │   ├── default
         │   │   ├── results.json
         │   │   ├── hostIdentifier1.results.json
         │   │   ├── hostIdentifier2.results.json
         │   │   └── hostIdentifier3.results.json
         │   ├── named1
         │   │   ├── results.json
         │   │   ├── hostIdentifier1.results.json
         │   │   ├── hostIdentifier2.results.json
         │   │   └── hostIdentifier3.results.json
         │   ├── named2
         │   │   └── ...
         │   └── ...
         ├── target2
         │   └── default
         │       └── ...
         └── ...
         */
        var outputPath = FilePath(baselineStoragePath) // package
        var subPath = FilePath() // subpath rooted in package used for directory creation

        subPath.append(baselinesDirectory) // package/.benchmarkBaselines
        subPath.append("\(target)") // package/.benchmarkBaselines/myTarget1
        subPath.append(baselineName) // package/.benchmarkBaselines/myTarget1/named1

        outputPath.createSubPath(subPath) // Create destination subpath if needed

        outputPath.append(subPath.components)

        if let hostIdentifier {
            outputPath.append("\(hostIdentifier).results.json")
        } else {
            outputPath.append("results.json")
        }

        // Write out benchmark baselines
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
                        let bytesArray = try JSONEncoder().encode(baseline)

                        try bytesArray.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                            _ = try fd.write(bytes)
                        }
                    } catch {
                        print("Failed to write to file \(outputPath)")
                    }
                }
            } catch {
                print("Failed to close fd for \(outputPath) after write.")
            }

        } catch {
            if errno == EPERM {
                print("Lacking permissions to write to \(outputPath)")
                print("Give benchmark plugin permissions by running with e.g.:")
                print("")
                print("swift package --allow-writing-to-package-directory benchmark baseline update")
                print("")
                if let operation = baselineOperation, [.compare, .check, .update].contains(operation) {
                    exitBenchmark(exitCode: .noPermissions)
                }
            } else {
                print("Failed to open file \(outputPath), errno = [\(errno)]")
            }
        }
    }

    func read(
        hostIdentifier: String? = nil,
        target: String,
        baselineIdentifier: String? = nil
    ) throws -> BenchmarkBaseline? {
        var path = FilePath(baselineStoragePath)
        path.append(baselinesDirectory) // package/.benchmarkBaselines
        path.append(FilePath.Component(target)!) // package/.benchmarkBaselines/myTarget1

        if let baselineIdentifier {
            path.append(baselineIdentifier) // package/.benchmarkBaselines/myTarget1/named1
        } else {
            path.append("default") // // package/.benchmarkBaselines/myTarget1/default
        }

        if let hostIdentifier {
            path.append("\(hostIdentifier).results.json")
        } else {
            path.append("results.json")
        }

        var baseline: BenchmarkBaseline?

        // Read from the file
        do {
            let fd = try FileDescriptor.open(path, .readOnly, options: [], permissions: .ownerRead)

            do {
                try fd.closeAfter {
                    do {
                        var readBytes = [UInt8]()
                        let bufferSize = 16 * 1_024 * 1_024
                        var done = false

                        while done == false { // readBytes.count < bufferLength {
                            let nextBytes = try [UInt8](unsafeUninitializedCapacity: bufferSize) { buf, count in
                                count = try fd.read(into: UnsafeMutableRawBufferPointer(buf))
                                if count == 0 {
                                    done = true
                                }
                            }
                            readBytes.append(contentsOf: nextBytes)
                        }

                        baseline = try JSONDecoder().decode(BenchmarkBaseline.self, from: Data(readBytes))

                    } catch {
                        print("Failed to open file for reading \(path) [\(String(reflecting: error))]")
                    }
                }
            } catch {
                print("Failed to close fd for \(path) after reading.")
            }
        } catch {
            if errno != ENOENT { // file not found is ok, e.g. when no baselines exist
                print("Failed to open file \(path), errno = [\(errno)]")
            }
        }
        return baseline
    }
}

extension BenchmarkBaseline {
    func thresholdsForBenchmarks(
        _ benchmarks: [Benchmark],
        name: String,
        target: String,
        metric: BenchmarkMetric,
        defaultThresholds: BenchmarkThresholds = BenchmarkThresholds.default
    ) -> BenchmarkThresholds {
        let benchmark = benchmarks.filter { $0.name == name && $0.target == target }.first

        guard let benchmark else {
            return defaultThresholds
        }

        guard let thresholds = benchmark.configuration.thresholds else {
            return defaultThresholds
        }

        guard let threshold = thresholds[metric] else {
            return defaultThresholds
        }

        return threshold
    }
}

extension BenchmarkBaseline: Equatable {
    public func deviationsComparedToBaseline(
        _ rhs: BenchmarkBaseline,
        benchmarks: [Benchmark]
    ) -> BenchmarkResult.ThresholdDeviations {
        let lhs = self
        var warningPrintedForMetric: Set<BenchmarkMetric> = []
        var warningPrinted = false
        var allDeviationResults = BenchmarkResult.ThresholdDeviations()

        for (lhsBenchmarkIdentifier, lhsBenchmarkResults) in lhs.results {
            for lhsBenchmarkResult in lhsBenchmarkResults {
                if let rhsResults = rhs.results.first(where: { $0.key == lhsBenchmarkIdentifier }) {
                    if let rhsBenchmarkResult = rhsResults.value.first(where: { $0.metric == lhsBenchmarkResult.metric }
                    ) {
                        let thresholds = thresholdsForBenchmarks(
                            benchmarks,
                            name: lhsBenchmarkIdentifier.name,
                            target: lhsBenchmarkIdentifier.target,
                            metric: lhsBenchmarkResult.metric
                        )

                        let deviationResults = lhsBenchmarkResult.deviationsComparedWith(
                            rhsBenchmarkResult,
                            thresholds: thresholds,
                            name: lhsBenchmarkIdentifier.name,
                            target: lhsBenchmarkIdentifier.target
                        )
                        allDeviationResults.append(deviationResults)
                    } else {
                        if warningPrintedForMetric.contains(lhsBenchmarkResult.metric) == false {
                            print("`\(lhsBenchmarkResult.metric)` not found in both baselines, skipping it.")
                            warningPrintedForMetric.insert(lhsBenchmarkResult.metric)
                        }
                    }
                } else {
                    if warningPrinted == false {
                        print(
                            "One or more benchmarks, including `\(lhsBenchmarkIdentifier.target):\(lhsBenchmarkIdentifier.name)` was not found in one of the baselines."
                        )
                        warningPrinted = true
                    }
                }
            }
        }

        return allDeviationResults
    }

    public func failsAbsoluteThresholdChecks(
        benchmarks: [Benchmark],
        p90Thresholds: [BenchmarkIdentifier:
            [BenchmarkMetric: BenchmarkThreshold]]
    ) -> BenchmarkResult.ThresholdDeviations {
        var allDeviationResults = BenchmarkResult.ThresholdDeviations()

        for (lhsBenchmarkIdentifier, lhsBenchmarkResults) in results {
            for lhsBenchmarkResult in lhsBenchmarkResults {
                let thresholds = thresholdsForBenchmarks(
                    benchmarks,
                    name: lhsBenchmarkIdentifier.name,
                    target: lhsBenchmarkIdentifier.target,
                    metric: lhsBenchmarkResult.metric,
                    defaultThresholds: BenchmarkThresholds.strict
                )

                if let p90Thresholds = p90Thresholds[lhsBenchmarkIdentifier] {
                    if let p90Thresholds = p90Thresholds[lhsBenchmarkResult.metric] {
                        let deviationResults = lhsBenchmarkResult.deviationsAgainstAbsoluteThresholds(
                            thresholds: thresholds,
                            p90Threshold: p90Thresholds,
                            name: lhsBenchmarkIdentifier.name,
                            target: lhsBenchmarkIdentifier.target
                        )
                        allDeviationResults.append(deviationResults)
                    }
                }
            }
        }

        return allDeviationResults
    }

    static func == (lhs: BenchmarkBaseline, rhs: BenchmarkBaseline) -> Bool {
        if lhs.machine.memory != rhs.machine.memory || lhs.machine.processors != rhs.machine.processors
            || lhs.machine.processorType != rhs.machine.processorType
        {
            return false
        }

        for (lhsBenchmarkIdentifier, lhsBenchmarkResults) in lhs.results {
            for lhsBenchmarkResult in lhsBenchmarkResults {
                guard let rhsResults = rhs.results.first(where: { $0.key == lhsBenchmarkIdentifier }) else { // We couldn't find a result for one of the tests
                    return false
                }
                guard let rhsBenchmarkResult = rhsResults.value.first(where: { $0.metric == lhsBenchmarkResult.metric })
                else { // We couldn't find the specific metric
                    return false
                }
                if lhsBenchmarkResult != rhsBenchmarkResult {
                    return false
                }
            }
        }
        return true
    }
}
