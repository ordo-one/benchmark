//
// Copyright (c) 2026 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

import Foundation
import XCTest

@testable import Benchmark

final class AllocationStacksTests: XCTestCase {
    private typealias Frame = AllocationStackReport.Frame
    private typealias Stack = AllocationStackReport.Stack

    private let siteA = Frame(symbol: "a()", location: "A.swift:1")
    private let siteB = Frame(symbol: "b()", location: "B.swift:2")
    private let siteC = Frame(symbol: "c()", image: "libC.dylib", isAsync: true)

    // MARK: Report

    func testStacksAreSortedByCountThenBytes() {
        let report = AllocationStackReport(
            iterations: 10,
            stacks: [
                Stack(frames: [siteA], count: 10, bytes: 100),
                Stack(frames: [siteB], count: 30, bytes: 10),
                Stack(frames: [siteC], count: 10, bytes: 500),
            ]
        )
        XCTAssertEqual(report.stacks.map(\.frames), [[siteB], [siteC], [siteA]])
        XCTAssertEqual(report.totalCount, 50)
        XCTAssertEqual(report.totalBytes, 610)
    }

    func testStacksWithIdenticalFramesAreMerged() {
        let report = AllocationStackReport(
            iterations: 1,
            stacks: [
                Stack(frames: [siteA, siteB], count: 1, bytes: 8),
                Stack(frames: [siteC], count: 2, bytes: 16),
                Stack(frames: [siteA, siteB], count: 3, bytes: 24),
            ]
        )
        XCTAssertEqual(report.stacks.count, 2)
        XCTAssertEqual(report.stacks.first, Stack(frames: [siteA, siteB], count: 4, bytes: 32))
    }

    func testReportRoundTripsThroughJSON() throws {
        let report = AllocationStackReport(iterations: 3, stacks: [Stack(frames: [siteA, siteC], count: 6, bytes: 48)])
        let decoded = try JSONDecoder().decode(AllocationStackReport.self, from: JSONEncoder().encode(report))
        XCTAssertEqual(decoded, report)
    }

    // MARK: Formatting

    func testFormattingShowsCountsPerIterationAndFrames() {
        let report = AllocationStackReport(
            iterations: 4,
            stacks: [
                Stack(frames: [siteA, siteC], count: 3_000, bytes: 1_500_000),
                Stack(frames: [siteB], count: 1_000, bytes: 64),
            ]
        )
        let text = report.formatted(title: "Target:Name")

        XCTAssertTrue(text.hasPrefix("Allocations: Target:Name — 4 iterations, 4,000 allocations (1,000.0/iteration)"))
        XCTAssertTrue(text.contains("#1  3,000 allocations (750.0/iteration), 75.0%, 1.5 MB"))
        XCTAssertTrue(text.contains("#2  1,000 allocations (250.0/iteration), 25.0%, 64 B"))
        XCTAssertTrue(text.contains("0  a() at A.swift:1"))
        XCTAssertTrue(text.contains("1  c() [async] in libC.dylib"))
        // Highest count first.
        XCTAssertLessThan(text.range(of: "a()")!.lowerBound, text.range(of: "b()")!.lowerBound)
    }

    func testFormattingRespectsLimit() {
        let report = AllocationStackReport(
            iterations: 1,
            stacks: [Stack(frames: [siteA], count: 3, bytes: 3), Stack(frames: [siteB], count: 1, bytes: 1)]
        )
        let text = report.formatted(title: "T", limit: 1)
        XCTAssertTrue(text.contains("Showing the top stack (75.0% of allocations)."))
        XCTAssertTrue(text.contains("a()"))
        XCTAssertFalse(text.contains("b()"))
    }

    func testMarkdownFormattingWrapsFramesInCodeBlocks() {
        let report = AllocationStackReport(iterations: 1, stacks: [Stack(frames: [siteA], count: 1, bytes: 1)])
        let text = report.formatted(title: "T", markdown: true)
        XCTAssertTrue(text.hasPrefix("### Allocations: T"))
        XCTAssertTrue(text.contains("**#1  1 allocation (1.0/iteration), 100.0%, 1 B**\n```\n    0  a() at A.swift:1\n```"))
    }

    func testNumberFormatting() {
        XCTAssertEqual(AllocationStackReport.grouped(0), "0")
        XCTAssertEqual(AllocationStackReport.grouped(999), "999")
        XCTAssertEqual(AllocationStackReport.grouped(1_234_567), "1,234,567")
        XCTAssertEqual(AllocationStackReport.bytes(999), "999 B")
        XCTAssertEqual(AllocationStackReport.bytes(2_500), "2.5 KB")
        XCTAssertEqual(AllocationStackReport.oneDecimal(0.05), "0.1")
    }

    #if canImport(MallocInterposerSwift) && canImport(Runtime)
    // MARK: Trimming

    func testTrimDropsRecordingFramesAndHarness() {
        let frames = [
            Frame(symbol: "closure #1 in AllocationStackRecorder.hook", image: "Benchmark"),
            Frame(symbol: "replacement_malloc", image: "libMallocInterposerSwift.dylib"),
            Frame(symbol: "_malloc_type_malloc_outlined", image: "libsystem_malloc.dylib"),
            Frame(symbol: "swift_allocObject", image: "libswiftCore.dylib"),
            siteA,
            Frame(symbol: "closure #1 in closure #1 in variable initialization expression of benchmarks"),
            Frame(symbol: "Benchmark.run()"),
            Frame(symbol: "BenchmarkExecutor.run(_:)"),
            Frame(symbol: "main"),
        ]
        XCTAssertEqual(
            AllocationStackSymbolicator.trim(frames).map(\.symbol),
            ["swift_allocObject", "a()", "closure #1 in closure #1 in variable initialization expression of benchmarks"]
        )
    }

    func testTrimCutsAtAsyncHarnessFrames() {
        let frames = [siteA, Frame(symbol: "closure #1 in closure #1 in Benchmark.runAsync()", isAsync: true), siteB]
        XCTAssertEqual(AllocationStackSymbolicator.trim(frames), [siteA])
    }

    func testHarnessMatchingRequiresIdentifierBoundary() {
        XCTAssertFalse(AllocationStackSymbolicator.isHarnessFrame(Frame(symbol: "MyBenchmark.run()")))
        XCTAssertFalse(AllocationStackSymbolicator.isHarnessFrame(Frame(symbol: "closure in My_BenchmarkRunner.go()")))
        XCTAssertTrue(AllocationStackSymbolicator.isHarnessFrame(Frame(symbol: "closure #1 in Benchmark.init(_:)")))
        XCTAssertTrue(AllocationStackSymbolicator.isHarnessFrame(Frame(symbol: "BenchmarkRunner.run()")))
    }

    // MARK: Recorder

    @inline(never)
    private func allocateFromSiteOne(_ count: Int) {
        for _ in 0..<count {
            AllocationStackRecorder.hook(16)
        }
    }

    @inline(never)
    private func allocateFromSiteTwo(_ count: Int) {
        for _ in 0..<count {
            AllocationStackRecorder.hook(32)
        }
    }

    /// Drives the hook directly (no live interposer needed) and checks that stacks are captured,
    /// aggregated per call site and symbolicated.
    func testRecorderAggregatesStacksPerCallSite() throws {
        try XCTSkipUnless(AllocationStackRecorder.isAvailable, "Swift Runtime library not available")

        AllocationStackRecorder.configure(maxDepth: 64)
        allocateFromSiteOne(3)
        allocateFromSiteTwo(6)
        let report = AllocationStackSymbolicator.makeReport(iterations: 1, stacks: AllocationStackRecorder.snapshot())
        AllocationStackRecorder.reset()

        XCTAssertEqual(report.totalCount, 9)
        XCTAssertEqual(report.totalBytes, 3 * 16 + 6 * 32)
        XCTAssertEqual(report.stacks.map(\.count), [6, 3])
        // The recorder's own frames are skipped, so each stack starts at its call site.
        let topSymbols = report.stacks.map { $0.frames.first?.symbol ?? "" }
        XCTAssertNotEqual(topSymbols[0], topSymbols[1])
        // Private test symbols can't always be resolved (e.g. Linux, where the test bundle is loaded
        // like a shared library); check names only where they were.
        if topSymbols.allSatisfy({ $0.hasPrefix("0x") == false }) {
            XCTAssertTrue(topSymbols[0].contains("allocateFromSiteTwo"), "\(topSymbols)")
            XCTAssertTrue(topSymbols[1].contains("allocateFromSiteOne"), "\(topSymbols)")
        }
    }
    #endif
}
