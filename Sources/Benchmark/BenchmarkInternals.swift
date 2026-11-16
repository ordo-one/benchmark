// swiftlint:disable all
//
// Copyright (c) 2022 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

// Internal Benchmark framework definitions used for communication with host process etc

// Command sent from benchmark runner to the benchmark under measurement

@_documentation(visibility: internal)
public enum BenchmarkCommandRequest: Codable {
    case list
    case run(benchmark: Benchmark)
    case end // exit the benchmark
}

// Replies from benchmark under measure to benchmark runner
@_documentation(visibility: internal)
public enum BenchmarkCommandReply: Codable {
    case list(benchmark: Benchmark)
    case ready
    case result(benchmark: Benchmark, results: [BenchmarkResult]) // receives results from built-in metric collectors
    case allocationStacks(benchmark: Benchmark, report: AllocationStackReport) // sent before `result` with --allocation-stacks
    case run
    case end // end of query for list/result
    case error(_ description: String) // error while performing operation (e.g. 'run')
}

// swiftlint:enable all
