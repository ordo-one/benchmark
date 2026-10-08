//
// Copyright (c) 2026 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

import Benchmark
import XCTest

private func frame(_ symbol: String) -> AllocationStacksReport.Frame {
    .init(image: nil, offset: 0, symbol: symbol)
}

final class AllocationStacksTests: XCTestCase {
    func testFoldedOutputFormatAndOrdering() {
        let report = AllocationStacksReport(
            entries: [
                .init(frames: [frame("main"), frame("runner"), frame("smallSite")], count: 5, bytes: 500),
                .init(frames: [frame("main"), frame("runner"), frame("hotSite")], count: 100, bytes: 6400),
            ],
            droppedAllocations: 0,
            totalAllocations: 105
        )

        let folded = report.foldedOutput()
        let lines = folded.split(separator: "\n")

        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0], "main;runner;hotSite 100", "highest count must come first")
        XCTAssertEqual(lines[1], "main;runner;smallSite 5")
        XCTAssertTrue(folded.hasSuffix("\n"))
    }

    func testFoldedOutputEscapesSemicolonsInFrames() {
        let report = AllocationStacksReport(
            entries: [
                .init(frames: [frame("main"), frame("generic<A; B>(x:)")], count: 1, bytes: 16)
            ],
            droppedAllocations: 0,
            totalAllocations: 1
        )

        XCTAssertEqual(report.foldedOutput(), "main;generic<A, B>(x:) 1\n")
    }

    func testFoldedOutputMergesIdenticalFrameSequences() {
        // Distinct program counters can symbolicate to identical frames;
        // the folded output must merge them into one line.
        let report = AllocationStacksReport(
            entries: [
                .init(frames: [frame("main"), frame("site")], count: 3, bytes: 300),
                .init(frames: [frame("main"), frame("site")], count: 4, bytes: 400),
            ],
            droppedAllocations: 0,
            totalAllocations: 7
        )

        XCTAssertEqual(report.foldedOutput(), "main;site 7\n")
    }

    func testFoldedOutputExpandsInlineChainsViaResolver() {
        // A DWARF resolver can expand one physical frame into several
        // logical (inlined) frames, root-first.
        let report = AllocationStacksReport(
            entries: [
                .init(frames: [frame("main"), .init(image: "/x/Basic", offset: 0x100, symbol: "closure")], count: 2, bytes: 32)
            ],
            droppedAllocations: 0,
            totalAllocations: 2
        )

        let folded = report.foldedOutput { frame in
            if frame.offset == 0x100 {
                return ["closure (a.swift:9)", "reserveCapacity", "_createNewBuffer"]
            }
            return [frame.displayName]
        }

        XCTAssertEqual(folded, "main;closure (a.swift:9);reserveCapacity;_createNewBuffer 2\n")
    }

    func testPerIterationNormalization() {
        let report = AllocationStacksReport(
            entries: [
                .init(frames: [frame("main"), frame("hot")], count: 1000, bytes: 16000),
                .init(frames: [frame("main"), frame("rounded")], count: 25, bytes: 250),
                .init(frames: [frame("main"), frame("once")], count: 1, bytes: 8),
            ],
            droppedAllocations: 0,
            totalAllocations: 1026,
            iterations: 10
        )

        XCTAssertEqual(report.perIteration(1000), 100)
        XCTAssertEqual(report.perIteration(25), 3, "rounds to nearest")
        XCTAssertEqual(report.perIteration(1), 1, "run-once stacks stay visible")
        XCTAssertEqual(report.perIteration(0), 0)
        XCTAssertEqual(report.foldedOutput(), "main;hot 100\nmain;rounded 3\nmain;once 1\n")
        XCTAssertFalse(report.isEmpty)

        // scalingFactor divides too unless the caller asks for outer-loop figures (--scale).
        let scaledReport = AllocationStacksReport(
            entries: [.init(frames: [frame("main"), frame("hot")], count: 170_000, bytes: 1_700_000)],
            droppedAllocations: 0,
            totalAllocations: 170_000,
            iterations: 10,
            scalingFactor: 1000
        )
        XCTAssertEqual(scaledReport.perIteration(170_000), 17)
        XCTAssertEqual(scaledReport.perIteration(170_000, scaled: false), 17_000)
        XCTAssertEqual(scaledReport.foldedOutput(), "main;hot 17\n")
        XCTAssertEqual(scaledReport.foldedOutput(scaled: false), "main;hot 17000\n")
        XCTAssertTrue(
            AllocationStacksReport(entries: [], droppedAllocations: 0, totalAllocations: 0).isEmpty
        )
    }

    func testFrameDisplayName() {
        XCTAssertEqual(frame("named").displayName, "named")
        XCTAssertEqual(
            AllocationStacksReport.Frame(image: "/a/b/libFoo.so", offset: 0x1465e4, symbol: nil).displayName,
            "libFoo.so+0x1465e4"
        )
        XCTAssertEqual(
            AllocationStacksReport.Frame(image: nil, offset: 0xdead, symbol: nil).displayName,
            "0xdead"
        )
    }

    func testReportCodableRoundTrip() throws {
        let report = AllocationStacksReport(
            entries: [.init(frames: [frame("main"), .init(image: "/x/img", offset: 66, symbol: "site")], count: 3, bytes: 300)],
            droppedAllocations: 2,
            totalAllocations: 5
        )

        let decoded = try JSONDecoder().decode(
            AllocationStacksReport.self, from: JSONEncoder().encode(report)
        )

        XCTAssertEqual(decoded.entries.count, 1)
        XCTAssertEqual(decoded.entries[0].frames.map(\.symbol), ["main", "site"])
        XCTAssertEqual(decoded.entries[0].frames[1].image, "/x/img")
        XCTAssertEqual(decoded.entries[0].frames[1].offset, 66)
        XCTAssertEqual(decoded.entries[0].count, 3)
        XCTAssertEqual(decoded.entries[0].bytes, 300)
        XCTAssertEqual(decoded.droppedAllocations, 2)
        XCTAssertEqual(decoded.totalAllocations, 5)
    }
}
