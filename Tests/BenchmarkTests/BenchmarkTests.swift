//
// Copyright (c) 2022 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

import Dispatch
import XCTest

@testable import Benchmark

final class BenchmarkTests: XCTestCase {
    func testBenchmarkRun() async throws {
        let benchmark = Benchmark("testBenchmarkRun benchmark") { _ in
        }
        XCTAssertNotNil(benchmark)
        await benchmark?.run()
    }

    func testBenchmarkRunAsync() async throws {
        func asyncFunc() async {}
        let benchmark = Benchmark("testBenchmarkRunAsync benchmark") { _ in
            await asyncFunc()
        }
        XCTAssertNotNil(benchmark)
        await benchmark?.run()
    }

    func testBenchmarkRunAsyncThrowingFailure() async throws {
        // Error handling for async throwing closures moved from an init-time wrapper into run();
        // a thrown error must still be surfaced as a failureReason.
        struct Boom: Error {}
        let benchmark = Benchmark("testBenchmarkRunAsyncThrowingFailure benchmark") { _ in
            await Task.yield()
            throw Boom()
        }
        XCTAssertNotNil(benchmark)
        await benchmark?.run()
        XCTAssertNotNil(benchmark?.failureReason)
    }

    func testBenchmarkRunMainActor() async throws {
        // An async benchmark whose closure is isolated to the main actor must carry that isolation,
        // run on the main actor, and do so without deadlocking (the old semaphore bridge deadlocked).
        let benchmark = Benchmark("testBenchmarkRunMainActor benchmark") { @MainActor _ in
            await Task.yield()
            MainActor.assertIsolated()
        }
        XCTAssertNotNil(benchmark)
        let isolation: (any Actor)?
        if let asyncClosure = benchmark?.asyncClosure {
            isolation = asyncClosure.isolation
        } else {
            isolation = nil
        }
        XCTAssertIdentical(isolation, MainActor.shared)
        await benchmark?.run(isolation: isolation)
    }

    func testBenchmarkRunCustomMetric() async throws {
        let benchmark = Benchmark(
            "testBenchmarkRunCustomMetric benchmark",
            configuration: .init(metrics: [.custom("customMetric")])
        ) { benchmark in
            for measurement in 1...100 {
                benchmark.measurement(.custom("customMetric"), measurement)
            }
        }
        XCTAssertNotNil(benchmark)
        await benchmark?.run()
    }

    func testBenchmarkEqualityAndDifference() throws {
        let benchmark = Benchmark("testBenchmarkEqualityAndDifference benchmark") { _ in
        }
        let benchmark2 = Benchmark("testBenchmarkEqualityAndDifference benchmark 2") { _ in
        }
        XCTAssertNotEqual(benchmark, benchmark2)
    }

    func testBenchmarkRunFailure() async throws {
        let benchmark = Benchmark(
            "testBenchmarkRunFailure benchmark",
            configuration: .init(metrics: [.custom("customMetric")])
        ) { benchmark in
            benchmark.error("Benchmark failed")
        }
        XCTAssertNotNil(benchmark)
        await benchmark?.run()
        XCTAssertNotNil(benchmark?.failureReason)
        XCTAssertEqual(benchmark?.failureReason, "Benchmark failed")
    }

    func testBenchmarkRunMoreParameters() async throws {
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
        await benchmark?.run()
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

    func testExecutorRunsMainActorBenchmarkWithoutDeadlock() async throws {
        // End-to-end through the real measurement loop: a main-actor-isolated async benchmark must
        // complete (the old DispatchSemaphore bridge deadlocked here) and actually run on the main actor.
        Benchmark.testSkipBenchmarkRegistrations = true
        defer { Benchmark.testSkipBenchmarkRegistrations = false }

        final class Counter: @unchecked Sendable { var count = 0 }
        let counter = Counter()

        let benchmark = Benchmark(
            "MainActor executor benchmark",
            configuration: .init(metrics: [.wallClock], warmupIterations: 1, maxDuration: .seconds(10), maxIterations: 3)
        ) { @MainActor _ in
            await Task.yield()
            MainActor.assertIsolated()
            counter.count += 1
        }
        XCTAssertNotNil(benchmark)

        let results = await BenchmarkExecutor().run(benchmark!, isolation: MainActor.shared)
        XCTAssertFalse(results.isEmpty)
        XCTAssertGreaterThan(counter.count, 0)
    }

    func testUnisolatedAsyncBenchmarkHoppingToMainActor() async throws {
        // A *nominally unisolated* async benchmark that hops to the main actor itself (via MainActor.run)
        // must complete without deadlocking.  This is one of the scenarios the old DispatchSemaphore
        // bridge could deadlock on.  The closure carries no isolation, so the executor runs unisolated
        // (isolation == nil) — exactly as BenchmarkRunner drives it — and the hop happens inside.
        Benchmark.testSkipBenchmarkRegistrations = true
        defer { Benchmark.testSkipBenchmarkRegistrations = false }

        final class Flag: @unchecked Sendable { var ran = false }
        let flag = Flag()

        let benchmark = Benchmark(
            "unisolated async hops to MainActor",
            configuration: .init(metrics: [.wallClock], warmupIterations: 1, maxDuration: .seconds(10), maxIterations: 3)
        ) { _ in
            await MainActor.run {
                MainActor.assertIsolated()
                flag.ran = true
            }
        }
        XCTAssertNotNil(benchmark)

        // An unisolated async closure carries no isolation.
        let isolation: (any Actor)?
        if let asyncClosure = benchmark?.asyncClosure {
            isolation = asyncClosure.isolation
        } else {
            isolation = nil
        }
        XCTAssertNil(isolation)

        let results = await BenchmarkExecutor().run(benchmark!, isolation: isolation)
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(flag.ran)
    }

    func testUnisolatedSyncBenchmarkCallingMainSync() {
        // A *synchronous* benchmark that bounces to the main queue (DispatchQueue.main.sync) must run
        // off the main thread and not deadlock.  Driven from a detached task (off-main) while the main
        // thread drains the main queue in wait(for:).  An expectation+timeout means that, should this
        // ever regress to a deadlock, the test eventually fails outright rather than hanging the whole
        // suite.
        Benchmark.testSkipBenchmarkRegistrations = true
        defer { Benchmark.testSkipBenchmarkRegistrations = false }

        final class Flag: @unchecked Sendable { var ran = false }
        let flag = Flag()

        let benchmark = Benchmark(
            "unisolated sync calls DispatchQueue.main.sync",
            configuration: .init(metrics: [.wallClock], warmupIterations: 1, maxDuration: .seconds(10), maxIterations: 3)
        ) { _ in
            DispatchQueue.main.sync {
                // NB: we only record that the block ran, not the thread identity — on Linux the main
                // queue is drained off the main thread, so Thread.isMainThread would not be reliable.
                flag.ran = true
            }
        }
        XCTAssertNotNil(benchmark)

        let completed = expectation(description: "benchmark completed without deadlocking")
        Task.detached {
            _ = await BenchmarkExecutor().run(benchmark!, isolation: nil)
            completed.fulfill()
        }
        wait(for: [completed], timeout: 30)
        XCTAssertTrue(flag.ran)
    }
}
