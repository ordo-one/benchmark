//
// Copyright (c) 2022 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

// The actual benchmark runner/driver

import ArgumentParser
import Benchmark
import BenchmarkShared
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

enum BenchmarkOperation: String, ExpressibleByArgument {
    case baseline
    case thresholds
    case list
    case run
    case query // query all benchmarks from target, used internally in tool
    case `init`
}

extension Grouping: ExpressibleByArgument {}
extension OutputFormat: ExpressibleByArgument {}
extension BaselineOperation: ExpressibleByArgument {}
extension ThresholdsOperation: ExpressibleByArgument {}
extension BenchmarkMetric: ExpressibleByArgument {}

typealias BenchmarkResults = [BenchmarkIdentifier: [BenchmarkResult]]

private var failedBenchmarkRuns = 0

@main
struct BenchmarkTool: AsyncParsableCommand {
    @Option(name: .long, help: "The paths to the benchmarks to run")
    var benchmarkExecutablePaths: [String] = []

    @Option(name: .long, help: "The targets")
    var targets: [String] = []

    @Option(name: .long, help: "The command to perform")
    var command: BenchmarkOperation

    @Option(name: .long, help: "The export format to use \((OutputFormat.allCases).map { String(describing: $0) })")
    var format: OutputFormat

    @Option(name: .long, help: "The path to baseline directory for storage")
    var baselineStoragePath: String

    @Option(name: .long, help: "The path to export to or read thresholds from")
    var path: String?

    @Option(name: .long, help: "The name of the new benchmark target to create")
    var targetName: String?

    @Option(name: .long, help: "The SPM package identifier under which the benchmark package is depended on (used by `benchmark init`)")
    var benchmarkPackageIdentifier: String = "benchmark"

    @Option(name: .long, help: "The operation to perform on the specified baselines")
    var baselineOperation: BaselineOperation?

    @Option(name: .long, help: "The operation to perform for thresholds")
    var thresholdsOperation: ThresholdsOperation?

    @Flag(name: .long, help: "True if we should suppress output")
    var quiet: Bool = false

    @Flag(name: .long, help: "True if we should suppress progress in benchmark run")
    var noProgress: Bool = false

    @Flag(name: .long, help: "True if we should scale time units, syscall rate, etc to scalingFactor")
    var scale: Bool = false

    @Option(name: .long, help: "Specifies that time related metrics output should be specified units")
    var timeUnits: TimeUnits?

    @Flag(
        name: .long,
        help:
            """
            Set to true if thresholds should be checked against an absolute reference point rather than delta between baselines.
            This is used for CI workflows when you want to validate the thresholds vs. a persisted benchmark baseline
            rather than comparing PR vs main or vs a current run. This is useful to cut down the build matrix needed
            for those wanting to validate performance of e.g. toolchains or OS:s as well (or have other reasons for wanting
            a specific check against a given absolute reference.).
            If this is enabled, zero or one baselines should be specified for the check operation.
            By default, thresholds are checked comparing two baselines, or a baseline and a benchmark run.
            """
    )
    var checkAbsolute = false

    @Option(
        name: .long,
        help:
            """
            The path from which p90 thresholds will be loaded for absolute threshold checks.
            This implicitly sets --check-absolute to true as well.
            """
    )
    var checkAbsolutePath: String?

    @Option(name: .long, help: "The named baseline(s) we should display, update, delete or compare with")
    var baseline: [String] = []

    @Option(name: .long, help: "The metrics to use, overrides whatever the benchmark has specified as desired metrics.")
    var metrics: [BenchmarkMetric] = []

    @Option(name: .long, help: "The grouping to use, 'metric' or 'test'")
    var grouping: Grouping

    @Option(name: .long, help: "Benchmarks matching the regexp filter that should be run")
    var filter: [String] = []

    @Option(name: .long, help: "Benchmarks matching the regexp filter that should be skipped")
    var skip: [String] = []

    var inputFD: CInt = 0
    var outputFD: CInt = 0

    var benchmarks: [Benchmark] = []
    var benchmarkBaselines: [BenchmarkBaseline] = [] // The baselines read from disk, merged + current run if needed
    var comparisonBaseline: BenchmarkBaseline?
    var checkBaseline: BenchmarkBaseline?

    var failedBenchmarkList: [String] = []

    var thresholdsPath: String {
        path ?? "Thresholds"
    }

    mutating func failBenchmark(
        _ reason: String? = nil,
        exitCode: BenchmarkShared.ExitCode = .genericFailure,
        _ failedBenchmark: String? = nil
    ) {
        if let reason {
            print(reason)
            print("")
        }

        // check what failed and react accordingly
        switch exitCode {
        case .benchmarkJobFailed:
            // We need to fail with exit code for the baseline checks such that CI fails properly
            if let operation = baselineOperation, [.compare, .check, .update].contains(operation) {
                exitBenchmark(exitCode: .thresholdRegression)
            }
            if let failedBenchmark {
                failedBenchmarkList.append(failedBenchmark)
            }
        default:
            exitBenchmark(exitCode: exitCode)
        }
    }

    func exitBenchmark(exitCode: BenchmarkShared.ExitCode) {
        #if canImport(Darwin)
        Darwin.exit(exitCode.rawValue)
        #elseif canImport(Glibc)
        Glibc.exit(exitCode.rawValue)
        #endif
    }

    func printChildRunError(error: Int32, benchmarkExecutablePath: String) {
        failedBenchmarkRuns += 1
        print("Failed to run '\(command)' for \(benchmarkExecutablePath), error code [\(error)]")
        print("Likely your benchmark crashed, try running the tool in the debugger, e.g.")
        print("lldb \(benchmarkExecutablePath)")
        print("Or check Console.app for a backtrace if on macOS.")
        // We need to fail with exit code for the baseline checks such that CI fails properly
        if let operation = baselineOperation, [.compare, .check, .update].contains(operation) {
            exitBenchmark(exitCode: .thresholdRegression)
        }
    }

    func shouldIncludeBenchmark(_ name: String) throws -> Bool {
        if try skip.contains(where: { try name.wholeMatch(of: Regex($0)) != nil }) {
            return false
        }
        return try filter.isEmpty || filter.contains(where: { try name.wholeMatch(of: Regex($0)) != nil })
    }

    mutating func readBaselines() throws {
        func readBaseline(_ baselineName: String) throws -> BenchmarkBaseline? {
            // read all specified baselines
            var readBaselines: [BenchmarkBaseline] = [] // The baselines read from disk

            try targets.forEach { target in // read from all the targets (baselines are stored separately)
                let currentBaseline = try read(target: target, baselineIdentifier: baselineName)

                if let currentBaseline {
                    readBaselines.append(currentBaseline)
                }
            }

            // Merge baselines read
            if readBaselines.isEmpty == false {
                var aggregatedBaseline = readBaselines.first!
                for baseline in 1..<readBaselines.count {
                    aggregatedBaseline = aggregatedBaseline.merge(readBaselines[baseline])
                }
                return aggregatedBaseline
            }

            return nil
        }

        try baseline.forEach { baselineName in // for all specified baselines at command line
            if let baseline = try readBaseline(baselineName) {
                benchmarkBaselines.append(baseline)
            } else {
                failBenchmark("Failed to load specified baseline '\(baselineName)'.", exitCode: .baselineNotFound)
            }
        }
    }

    mutating func run() async throws {
        // Flush stdout so we see any failures clearly
        setbuf(stdout, nil)

        guard command != .`init` else {
            createBenchmarkTarget()
            return
        }

        // Skip reading baselines for baseline operations not needing them
        if let operation = baselineOperation, [.delete, .list, .update].contains(operation) == false {
            try readBaselines()
            if [.compare, .check].contains(operation), benchmarkBaselines.count < 1, checkAbsolute == false {
                print("Failed to read at least one benchmark baseline for compare/check operations.")
                return
            }
        }

        // Skip reading baselines for threshold operations not needing them
        if let operation = thresholdsOperation, [.read].contains(operation) == false {
            try readBaselines()
        }

        // First get a list of all benchmarks
        try benchmarkExecutablePaths.forEach { benchmarkExecutablePath in
            try runChild(
                benchmarkPath: benchmarkExecutablePath,
                benchmarkCommand: .query
            ) { [self] result in
                if result != 0 {
                    printChildRunError(error: result, benchmarkExecutablePath: benchmarkExecutablePath)
                }
            }
        }

        guard command != .list else {
            try listBenchmarks()
            return
        }

        // If we just need data from disk, skip running benchmarks
        if let operation = thresholdsOperation, [.read].contains(operation) {
            try postProcessBenchmarkResults()
            return
        }

        if let operation = thresholdsOperation, [.update].contains(operation),
            let baselineName = benchmarkBaselines.first?.baselineName
        {
            print("Updating thresholds at \"\(thresholdsPath)\" from baseline \"\(baselineName)\"")
            try postProcessBenchmarkResults()
            return
        }

        if let operation = thresholdsOperation, [.check].contains(operation), benchmarkBaselines.count > 0 {
            try postProcessBenchmarkResults()
            return
        }

        if let operation = baselineOperation, [.delete, .list, .read].contains(operation) {
            try postProcessBenchmarkResults()
            return
        }

        if let operation = baselineOperation, [.compare, .check].contains(operation) {
            if checkAbsolute {
                if benchmarkBaselines.count > 0 {
                    try postProcessBenchmarkResults()
                    return
                }
            } else {
                if benchmarkBaselines.count > 1 {
                    try postProcessBenchmarkResults()
                    return
                }
            }
        }

        guard command != .query else {
            fatalError("Query command should never be specified to the BenchmarkTool")
        }

        if quiet == false, format == .text {
            "Running Benchmarks".printAsHeader()
        }

        var benchmarkResults: BenchmarkResults = [:]

        benchmarks.sort { ($0.target, $0.name) < ($1.target, $1.name) }

        // run each benchmark for the target as a separate process
        try benchmarks.forEach { benchmark in
            if try shouldIncludeBenchmark(benchmark.baseName) {
                let results = try runChild(
                    benchmarkPath: benchmark.executablePath!,
                    benchmarkCommand: command,
                    benchmark: benchmark
                ) { [self] result in
                    if result != 0 {
                        printChildRunError(error: result, benchmarkExecutablePath: benchmark.executablePath!)
                    }
                }

                benchmarkResults = benchmarkResults.merging(results) { _, new in new }
            }
        }

        // Insert benchmark run at first position of baselines
        baseline.append("Current_run")
        benchmarkBaselines.append(
            BenchmarkBaseline(
                baselineName: "Current_run",
                machine: benchmarkMachine(),
                results: benchmarkResults
            )
        )

        try postProcessBenchmarkResults()

        if failedBenchmarkRuns > 0 {
            exitBenchmark(exitCode: .benchmarkJobFailed)
        }
    }

    func withCStrings(_ strings: [String], scoped: ([UnsafeMutablePointer<CChar>?]) throws -> Void) rethrows {
        let cStrings = strings.map { strdup($0) }
        try scoped(cStrings + [nil])
        cStrings.forEach { free($0) }
    }

    enum RunCommandError: Error {
        case WaitPIDError
        case POSIXSpawnError(Int32)
    }

    @discardableResult
    mutating func runChild(
        benchmarkPath: String,
        benchmarkCommand: BenchmarkOperation,
        benchmark: Benchmark? = nil,
        completion: ((Int32) -> Void)? = nil
    ) throws -> BenchmarkResults {
        var pid: pid_t = 0

        var benchmarkResults: BenchmarkResults = [:]
        let fromChild = try FileDescriptor.pipe()
        let toChild = try FileDescriptor.pipe()

        // Close the parent-side ends of the pipes whenever we return, regardless of how we exit, so we don't
        // leak two file descriptors for every benchmark we run. (The child-side ends are closed separately,
        // right after spawning, so the parent's reads see EOF when the child exits.)
        defer {
            try? toChild.writeEnd.close()
            try? fromChild.readEnd.close()
        }

        let path = FilePath(benchmarkPath)
        var args: [String] = [
            path.lastComponent!.description,
            "--input-fd", toChild.readEnd.rawValue.description,
            "--output-fd", fromChild.writeEnd.rawValue.description,
            "--quiet", noProgress.description,
        ]

        if checkAbsolute {
            args.append("--check-absolute")
        }

        if let timeUnits {
            args.append(contentsOf: ["--time-units", timeUnits.rawValue])
        }

        inputFD = fromChild.readEnd.rawValue
        outputFD = toChild.writeEnd.rawValue

        try withCStrings(args) { cArgs in
            var status = posix_spawn(&pid, path.string, nil, nil, cArgs, environ)

            // Close child ends of the pipes (independently, so a failure closing one still closes the other)
            try? toChild.readEnd.close()
            try? fromChild.writeEnd.close()

            do {
                switch benchmarkCommand {
                case .`init`:
                    fatalError("Should never come here")
                case .query:
                    try queryBenchmarks(benchmarkPath) // Get all available benchmarks first
                case .list:
                    try listBenchmarks()
                case .baseline, .thresholds, .run:
                    guard let benchmark else {
                        fatalError("No benchmark specified for update/export/run/compare operation")
                    }
                    benchmarkResults = try runBenchmark(target: path.lastComponent!.description, benchmark: benchmark)
                }

                try write(.end)
            } catch {
                print("Process failed: \(String(reflecting: error))")
            }

            guard status == 0 else {
                throw RunCommandError.POSIXSpawnError(status)
            }
            guard waitpid(pid, &status, 0) != -1 else {
                print("waitpiderror")
                throw RunCommandError.WaitPIDError
            }
            completion?(status)
        }

        return benchmarkResults
    }

    struct FailedBenchmark: Codable {
        let benchmarkName: String
        let failureReason: String
    }
}
