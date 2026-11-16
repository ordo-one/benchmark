//
// Copyright (c) 2022 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

import XCTest

@testable import Benchmark

final class BenchmarkTests: XCTestCase {
    func testBenchmarkRun() throws {
        let benchmark = Benchmark("testBenchmarkRun benchmark") { _ in
        }
        XCTAssertNotNil(benchmark)
        benchmark?.run()
    }

    func testBenchmarkRunAsync() throws {
        func asyncFunc() async {}
        let benchmark = Benchmark("testBenchmarkRunAsync benchmark") { _ in
            await asyncFunc()
        }
        XCTAssertNotNil(benchmark)
        benchmark?.runAsync()
    }

    // The executor must not block the context it runs in while an async benchmark runs. Here the
    // benchmark is run from an actor, and its body awaits that same actor: blocking the actor until
    // the body completes deadlocks, as blocking the last free thread of the cooperative pool does
    // when the body awaits another task or actor.
    func testAsyncBenchmarkAwaitingTheCallingActor() throws {
        let host = BenchmarkHost()
        let benchmark = try XCTUnwrap(
            Benchmark(
                "testAsyncBenchmarkAwaitingTheCallingActor benchmark",
                configuration: .init(metrics: [.wallClock], warmupIterations: 1, maxIterations: 10)
            ) { _ in
                await host.touch()
            }
        )
        let finished = expectation(description: "benchmark finished")
        Task.detached {
            let results = await host.run(benchmark)
            XCTAssertFalse(results.isEmpty)
            finished.fulfill()
        }
        // Fail on a deadlock instead of hanging the test run
        wait(for: [finished], timeout: 30)
    }

    func testBenchmarkRunCustomMetric() throws {
        let benchmark = Benchmark(
            "testBenchmarkRunCustomMetric benchmark",
            configuration: .init(metrics: [.custom("customMetric")])
        ) { benchmark in
            for measurement in 1...100 {
                benchmark.measurement(.custom("customMetric"), measurement)
            }
        }
        XCTAssertNotNil(benchmark)
        benchmark?.run()
    }

    func testBenchmarkEqualityAndDifference() throws {
        let benchmark = Benchmark("testBenchmarkEqualityAndDifference benchmark") { _ in
        }
        let benchmark2 = Benchmark("testBenchmarkEqualityAndDifference benchmark 2") { _ in
        }
        XCTAssertNotEqual(benchmark, benchmark2)
    }

    func testBenchmarkRunFailure() throws {
        let benchmark = Benchmark(
            "testBenchmarkRunFailure benchmark",
            configuration: .init(metrics: [.custom("customMetric")])
        ) { benchmark in
            benchmark.error("Benchmark failed")
        }
        XCTAssertNotNil(benchmark)
        benchmark?.run()
        XCTAssertNotNil(benchmark?.failureReason)
        XCTAssertEqual(benchmark?.failureReason, "Benchmark failed")
    }

    func testBenchmarkRunMoreParameters() throws {
        let benchmark = Benchmark(
            "testBenchmarkRunMoreParameters benchmark",
            configuration: .init(
                metrics: .all,
                timeUnits: .milliseconds,
                warmupIterations: 0,
                scalingFactor: .mega
            )
        ) { benchmark in
            for outerloop in benchmark.scaledIterations {
                blackHole(outerloop)
            }
        }
        XCTAssertNotNil(benchmark)
        benchmark?.run()
    }

    func testBenchmarkParameterizedDescription() throws {
        let benchmark = Benchmark(
            "testBenchmarkParameterizedDescription benchmark",
            configuration: .init(
                tags: [
                    "foo": "bar",
                    "bin": String(42),
                    "pi": String(3.14),
                ]
            )
        ) { _ in }
        XCTAssertNotNil(benchmark)
        XCTAssertEqual(benchmark?.name, "testBenchmarkParameterizedDescription benchmark (bin: 42, foo: bar, pi: 3.14)")
    }
}

// Runs a benchmark from its own isolation, so a body awaiting it needs it to be free.
private actor BenchmarkHost {
    func run(_ benchmark: Benchmark) async -> [BenchmarkResult] {
        await BenchmarkExecutor(quiet: true).run(benchmark)
    }

    func touch() {}
}
