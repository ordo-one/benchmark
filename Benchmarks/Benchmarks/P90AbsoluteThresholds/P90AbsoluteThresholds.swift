//
// Copyright (c) 2023 Ordo One AB
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0

import Benchmark
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#else
#error("Unsupported Platform")
#endif

let benchmarks: @Sendable () -> Void = {
    var thresholdTolerances: [BenchmarkMetric: BenchmarkThresholds]
    let relative: BenchmarkThresholds.RelativeThresholds = [
        .p25: 25.0, .p50: 50.0, .p75: 75.0, .p90: 100.0, .p99: 101.0, .p100: 201.0,
    ]
    let absolute: BenchmarkThresholds.AbsoluteThresholds = [.p75: 999, .p90: 1_000, .p99: 1_001, .p100: 2_001]
    thresholdTolerances = [
        .mallocCountTotal: .init(relative: relative, absolute: absolute),
        .syscalls: .init(relative: [.p90: 23.0], absolute: [.p90: 123]),
    ]

    Benchmark.defaultConfiguration = .init(
        metrics: [.mallocCountTotal, .syscalls] + .arc,
        warmupIterations: 1,
        scalingFactor: .kilo,
        maxDuration: .seconds(2),
        maxIterations: .kilo(100),
        thresholds: thresholdTolerances
    )

    Benchmark("P90Date") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(Foundation.Date())
        }
    }

    Benchmark("P90Malloc") { benchmark in
        var array: [Int] = []

        for _ in benchmark.scaledIterations {
            var temporaryAllocation = malloc(1)
            blackHole(temporaryAllocation)
            free(temporaryAllocation)
            array.append(contentsOf: 1...1_000)
            blackHole(array)
        }
    }

    func concurrentWork(tasks: Int) async {
        _ = await withTaskGroup(
            of: Void.self,
            returning: Void.self,
            body: { taskGroup in
                for _ in 0..<tasks {
                    taskGroup.addTask {}
                }

                for await _ in taskGroup {}
            }
        )
    }

    Benchmark("Retain/release deviation") { _ in
        await concurrentWork(tasks: 789)
    }
}
