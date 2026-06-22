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

// quiet swiftlint for now
extension BenchmarkRunner {}

private final class ARCBox {
    let value: Int

    init(_ value: Int) {
        self.value = value
    }
}

let benchmarks: @Sendable () -> Void = {
    var thresholdTolerances: [BenchmarkMetric: BenchmarkThresholds]

    thresholdTolerances = [.wallClock: .relaxed]

    Benchmark.defaultConfiguration = .init(
        warmupIterations: 0,
        maxDuration: .seconds(1),
        maxIterations: Int.max,
        thresholds: thresholdTolerances
    )

    testSetUpTearDown()

    // A way to define custom metrics fairly compact
    enum CustomMetrics {
        static var one: BenchmarkMetric { .custom("CustomMetricOne") }
        static var two: BenchmarkMetric { .custom("CustomMetricTwo", polarity: .prefersLarger, useScalingFactor: true) }
        static var three: BenchmarkMetric {
            .custom("CustomMetricThree", polarity: .prefersLarger, useScalingFactor: false)
        }
    }

    Benchmark(
        "Basic",
        configuration: .init(metrics: [.wallClock, .throughput, .instructions])
    ) { _ in
    }

    Benchmark("Noop", configuration: .init(metrics: [.wallClock, .mallocCountTotal, .instructions])) { _ in
    }

    Benchmark("Noop2", configuration: .init(metrics: [.wallClock, .instructions] + .arc)) { _ in
    }

    Benchmark(
        "ARCBox",
        configuration: .init(
            metrics: .arc + [.wallClock],
            scalingFactor: .kilo
        )
    ) { benchmark in
        for _ in benchmark.scaledIterations {
            var boxes: [ARCBox] = []
            boxes.reserveCapacity(16)
            for value in 0..<16 {
                boxes.append(ARCBox(value))
            }
            blackHole(boxes)
        }
    }

    Benchmark(
        "Scaled metrics One",
        configuration: .init(
            metrics: .all + [CustomMetrics.two, CustomMetrics.one],
            scalingFactor: .one
        )
    ) { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(Int.random(in: 1...1_000))
        }
        benchmark.measurement(CustomMetrics.two, Int.random(in: 1...1_000_000))
        benchmark.measurement(CustomMetrics.one, Int.random(in: 1...1_000))
    }

    Benchmark(
        "Scaled metrics K",
        configuration: .init(
            metrics: .all + [CustomMetrics.two, CustomMetrics.one],
            scalingFactor: .kilo
        )
    ) { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(Int.random(in: 1...1_000))
        }
        benchmark.measurement(CustomMetrics.two, Int.random(in: 1...1_000_000))
        benchmark.measurement(CustomMetrics.one, Int.random(in: 1...1_000))
    }

    Benchmark(
        "Scaled metrics M",
        configuration: .init(
            metrics: .all + [CustomMetrics.two, CustomMetrics.one, CustomMetrics.three],
            scalingFactor: .mega
        )
    ) { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(Int.random(in: benchmark.scaledIterations))
        }
        benchmark.measurement(CustomMetrics.three, Int.random(in: 1...1_000_000_000))
        benchmark.measurement(CustomMetrics.two, Int.random(in: 1...1_000_000))
        benchmark.measurement(CustomMetrics.one, Int.random(in: 1...1_000))
    }

    Benchmark(
        "All metrics",
        configuration: .init(metrics: .all, skip: true)
    ) { _ in
    }

    let stats = Statistics(numberOfSignificantDigits: .four)
    let measurementCount = 8_340

    for measurement in (0..<measurementCount).reversed() {
        stats.add(measurement)
    }

    Benchmark(
        "Statistics",
        configuration: .init(
            metrics: .arc + [.wallClock],
            scalingFactor: .kilo,
            maxDuration: .seconds(1)
        )
    ) { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(stats.percentiles())
        }
    }

    let parameterization = (0...5).map { 1 << $0 } // 1, 2, 4, ...

    parameterization.forEach { count in
        Benchmark("Parameterized", configuration: .init(tags: ["count": count.description])) { benchmark in
            for _ in 0..<count {
                blackHole(Int.random(in: benchmark.scaledIterations))
            }
        }
    }

    @Sendable
    func defaultCounter() -> Int { 10 }

    @Sendable
    func dummyCounter(_ count: Int) {
        for index in 0..<count {
            blackHole(index)
        }
    }

    func concurrentWork(tasks: Int = 4, mallocs: Int = 0) async {
        _ = await withTaskGroup(
            of: Void.self,
            returning: Void.self,
            body: { taskGroup in
                for _ in 0..<tasks {
                    taskGroup.addTask {
                        dummyCounter(defaultCounter() * 1_000)
                        for _ in 0..<mallocs {
                            let something = malloc(1_024 * 1_024)
                            blackHole(something)
                            free(something)
                        }
                        if let fileHandle = FileHandle(forWritingAtPath: "/dev/null") {
                            let data = Data("Data to discard".utf8)
                            fileHandle.write(data)
                            fileHandle.closeFile()
                        }
                    }
                }

                for await _ in taskGroup {}
            }
        )
    }

    Benchmark(
        "InstructionCount",
        configuration: .init(
            metrics: [.instructions],
            warmupIterations: 0,
            scalingFactor: .kilo,
            thresholds: [.instructions: .relaxed]
        )
    ) { _ in
        await concurrentWork(tasks: 15, mallocs: 1_000)
    }
}
