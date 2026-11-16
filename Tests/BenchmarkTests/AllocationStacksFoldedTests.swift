//
// Copyright (c) 2026 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

#if canImport(Testing)
import Testing

@testable import Benchmark

@Suite
struct AllocationStacksFoldedTests {
    private typealias Frame = AllocationStackReport.Frame
    private typealias Stack = AllocationStackReport.Stack

    @Test
    func framesAreRootFirstAndStacksAreSortedByCount() {
        let root = Frame(symbol: "benchmark()")
        let report = AllocationStackReport(iterations: 10, stacks: [
            Stack(frames: [Frame(symbol: "small()"), root], count: 5, bytes: 500),
            Stack(frames: [Frame(symbol: "hot()"), root], count: 100, bytes: 100),
        ])

        #expect(report.foldedOutput() == "benchmark();hot() 100\nbenchmark();small() 5\n")
    }

    @Test
    func labelsPreserveSourceLocationsImagesAndAsyncCallers() {
        let report = AllocationStackReport(iterations: 1, stacks: [
            Stack(frames: [
                Frame(symbol: "malloc", image: "libc.so"),
                Frame(symbol: "allocate()", location: "A.swift:2", image: "App"),
                Frame(symbol: "caller()", location: "A.swift:1", isAsync: true),
            ], count: 3, bytes: 96)
        ])

        #expect(report.foldedOutput() == "caller() [async] at A.swift:1;allocate() at A.swift:2;malloc in libc.so 3\n")
    }

    @Test
    func separatorsInsideLabelsAreEscaped() {
        let report = AllocationStackReport(iterations: 1, stacks: [
            Stack(frames: [Frame(symbol: "generic<A; B>\ncall\r\nnext", location: "A;B.swift:2")], count: 1, bytes: 8)
        ])

        #expect(report.foldedOutput() == "generic<A, B> call next at A,B.swift:2 1\n")
    }

    @Test
    func identicalRenderedStacksAreMerged() {
        // Image metadata distinguishes these report frames, but their rendered source labels match.
        let report = AllocationStackReport(iterations: 1, stacks: [
            Stack(frames: [Frame(symbol: "site()", location: "A.swift:1", image: "One")], count: 3, bytes: 24),
            Stack(frames: [Frame(symbol: "site()", location: "A.swift:1", image: "Two")], count: 4, bytes: 32),
        ])

        #expect(report.foldedOutput() == "site() at A.swift:1 7\n")
    }

    @Test
    func equalCountsHaveDeterministicOrder() {
        let stacks = [
            Stack(frames: [Frame(symbol: "site()", location: "B.swift:1")], count: 2, bytes: 64),
            Stack(frames: [Frame(symbol: "site()", location: "A.swift:1")], count: 2, bytes: 8),
        ]
        let expected = "site() at A.swift:1 2\nsite() at B.swift:1 2\n"
        #expect(AllocationStackReport(iterations: 1, stacks: stacks).foldedOutput() == expected)
        #expect(AllocationStackReport(iterations: 1, stacks: stacks.reversed()).foldedOutput() == expected)
    }

    @Test
    func runTotalsPreserveRareAllocations() {
        let report = AllocationStackReport(iterations: 10_000, stacks: [
            Stack(frames: [Frame(symbol: "hot()")], count: 25_000, bytes: 200_000),
            Stack(frames: [Frame(symbol: "once()")], count: 1, bytes: 8),
        ])

        #expect(report.foldedOutput() == "hot() 25000\nonce() 1\n")
    }

    @Test
    func emptyReportsAndZeroCountsProduceNoLines() {
        #expect(AllocationStackReport(iterations: 0, stacks: []).foldedOutput().isEmpty)
        let report = AllocationStackReport(iterations: 1, stacks: [
            Stack(frames: [Frame(symbol: "unused()")], count: 0, bytes: 0)
        ])
        #expect(report.foldedOutput().isEmpty)
    }

    @Test
    func missingFramesRetainTheirAllocationCounts() {
        let report = AllocationStackReport(iterations: 1, stacks: [
            Stack(frames: [], count: 3, bytes: 24),
            Stack(frames: [Frame(symbol: "")], count: 1, bytes: 8),
        ])

        #expect(report.foldedOutput() == "<no frames outside the benchmark harness> 3\n<unknown> 1\n")
    }
}
#endif
