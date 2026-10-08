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
import Testing

@testable import Benchmark

@Suite
struct AllocationStacksTests {
    private typealias Frame = AllocationStackReport.Frame
    private typealias Stack = AllocationStackReport.Stack

    private let siteA = Frame(symbol: "a()", location: "A.swift:1")
    private let siteB = Frame(symbol: "b()", location: "B.swift:2")
    private let siteC = Frame(symbol: "c()", image: "libC.dylib", isAsync: true)

    // MARK: Report

    @Test
    func stacksAreSortedByCountThenBytes() {
        let report = AllocationStackReport(
            iterations: 10,
            stacks: [
                Stack(frames: [siteA], count: 10, bytes: 100),
                Stack(frames: [siteB], count: 30, bytes: 10),
                Stack(frames: [siteC], count: 10, bytes: 500),
            ]
        )
        #expect(report.stacks.map(\.frames) == [[siteB], [siteC], [siteA]])
        #expect(report.totalCount == 50)
        #expect(report.totalBytes == 610)
    }

    @Test
    func stacksWithIdenticalFramesAreMerged() {
        let report = AllocationStackReport(
            iterations: 1,
            stacks: [
                Stack(frames: [siteA, siteB], count: 1, bytes: 8),
                Stack(frames: [siteC], count: 2, bytes: 16),
                Stack(frames: [siteA, siteB], count: 3, bytes: 24),
            ]
        )
        #expect(report.stacks.count == 2)
        #expect(report.stacks.first == Stack(frames: [siteA, siteB], count: 4, bytes: 32))
    }

    @Test
    func reportRoundTripsThroughJSON() throws {
        let report = AllocationStackReport(iterations: 3, stacks: [Stack(frames: [siteA, siteC], count: 6, bytes: 48)])
        let decoded = try JSONDecoder().decode(AllocationStackReport.self, from: JSONEncoder().encode(report))
        #expect(decoded == report)
    }

    // MARK: Formatting

    @Test
    func formattingShowsCountsPerIterationAndFrames() throws {
        let report = AllocationStackReport(
            iterations: 4,
            stacks: [
                Stack(frames: [siteA, siteC], count: 3_000, bytes: 1_500_000),
                Stack(frames: [siteB], count: 1_000, bytes: 64),
            ]
        )
        let text = report.formatted(title: "Target:Name")

        #expect(text.hasPrefix("Allocations: Target:Name — 4 iterations, 4,000 allocations (1,000.0/iteration)"))
        #expect(text.contains("#1  3,000 allocations (750.0/iteration), 75.0%, 1.5 MB"))
        #expect(text.contains("#2  1,000 allocations (250.0/iteration), 25.0%, 64 B"))
        #expect(text.contains("0  a() at A.swift:1"))
        #expect(text.contains("1  c() [async] in libC.dylib"))
        // Highest count first.
        let first = try #require(text.range(of: "a()"))
        let second = try #require(text.range(of: "b()"))
        #expect(first.lowerBound < second.lowerBound)
    }

    @Test
    func formattingRespectsLimit() {
        let report = AllocationStackReport(
            iterations: 1,
            stacks: [Stack(frames: [siteA], count: 3, bytes: 3), Stack(frames: [siteB], count: 1, bytes: 1)]
        )
        let text = report.formatted(title: "T", limit: 1)
        #expect(text.contains("Showing the top stack (75.0% of allocations)."))
        #expect(text.contains("a()"))
        #expect(!text.contains("b()"))
    }

    @Test
    func markdownFormattingWrapsFramesInCodeBlocks() {
        let report = AllocationStackReport(iterations: 1, stacks: [Stack(frames: [siteA], count: 1, bytes: 1)])
        let text = report.formatted(title: "T", markdown: true)
        #expect(text.hasPrefix("### Allocations: T"))
        #expect(text.contains("**#1  1 allocation (1.0/iteration), 100.0%, 1 B**\n```\n    0  a() at A.swift:1\n```"))
    }

    @Test
    func numberFormatting() {
        #expect(AllocationStackReport.grouped(0) == "0")
        #expect(AllocationStackReport.grouped(999) == "999")
        #expect(AllocationStackReport.grouped(1_234_567) == "1,234,567")
        #expect(AllocationStackReport.bytes(999) == "999 B")
        #expect(AllocationStackReport.bytes(2_500) == "2.5 KB")
        #expect(AllocationStackReport.oneDecimal(0.05) == "0.1")
    }

    #if canImport(MallocInterposerSwift) && canImport(Runtime)
    // MARK: Trimming

    @available(macOS 26, *)
    @Test
    func trimDropsRecordingFramesAndHarness() {
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
        #expect(
            AllocationStackSymbolicator.trim(frames).map(\.symbol)
                == ["swift_allocObject", "a()", "closure #1 in closure #1 in variable initialization expression of benchmarks"]
        )
    }

    @available(macOS 26, *)
    @Test
    func trimCutsAtAsyncHarnessFrames() {
        let frames = [siteA, Frame(symbol: "closure #1 in closure #1 in Benchmark.runAsync()", isAsync: true), siteB]
        #expect(AllocationStackSymbolicator.trim(frames) == [siteA])
    }

    @available(macOS 26, *)
    @Test
    func harnessMatchingRequiresIdentifierBoundary() {
        #expect(!AllocationStackSymbolicator.isHarnessFrame(Frame(symbol: "MyBenchmark.run()")))
        #expect(!AllocationStackSymbolicator.isHarnessFrame(Frame(symbol: "closure in My_BenchmarkRunner.go()")))
        #expect(AllocationStackSymbolicator.isHarnessFrame(Frame(symbol: "closure #1 in Benchmark.init(_:)")))
        #expect(AllocationStackSymbolicator.isHarnessFrame(Frame(symbol: "BenchmarkRunner.run()")))
    }

    // MARK: Recorder

    @available(macOS 26, *)
    @inline(never)
    private func allocateFromSiteOne(_ count: Int) {
        for _ in 0..<count {
            AllocationStackRecorder.hook(16)
        }
    }

    @available(macOS 26, *)
    @inline(never)
    private func allocateFromSiteTwo(_ count: Int) {
        for _ in 0..<count {
            AllocationStackRecorder.hook(32)
        }
    }

    /// Drives the hook directly (no live interposer needed) and checks that stacks are captured,
    /// aggregated per call site and symbolicated.
    @available(macOS 26, *)
    @Test
    func recorderAggregatesStacksPerCallSite() {
        AllocationStackRecorder.configure(maxDepth: 64)
        allocateFromSiteOne(3)
        allocateFromSiteTwo(6)
        let report = AllocationStackSymbolicator.makeReport(iterations: 1, stacks: AllocationStackRecorder.snapshot())
        AllocationStackRecorder.reset()

        #expect(report.totalCount == 9)
        #expect(report.totalBytes == 3 * 16 + 6 * 32)
        #expect(report.stacks.map(\.count) == [6, 3])
        // The recorder's own frames are skipped, so each stack starts at its call site.
        let topSymbols = report.stacks.map { $0.frames.first?.symbol ?? "" }
        #expect(topSymbols[0] != topSymbols[1])
        // Private test symbols can't always be resolved (e.g. Linux, where the test bundle is loaded
        // like a shared library); check names only where they were.
        if topSymbols.allSatisfy({ $0.hasPrefix("0x") == false }) {
            #expect(topSymbols[0].contains("allocateFromSiteTwo"), "\(topSymbols)")
            #expect(topSymbols[1].contains("allocateFromSiteOne"), "\(topSymbols)")
        }
    }
    #endif
}
