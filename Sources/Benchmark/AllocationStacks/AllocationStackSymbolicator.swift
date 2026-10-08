//
// Copyright (c) 2026 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

#if canImport(MallocInterposerSwift) && canImport(Runtime)
import Foundation
@_weakLinked import Runtime

/// Turns raw recorded stacks into an ``AllocationStackReport``.
///
/// Symbolication runs in the benchmark process (addresses are only meaningful in its address
/// space) once per unique stack, after the measured run. Frames belonging to the allocator,
/// the recorder and the benchmark harness are trimmed so each stack starts at the allocation
/// site and ends at the benchmark closure.
@available(macOS 26, *)
enum AllocationStackSymbolicator {
    static func makeReport(iterations: Int, stacks: [AllocationStackRecorder.RawStack]) -> AllocationStackReport {
        let images = ImageMap.capture()
        let reportStacks = stacks.map { stack in
            let frames = stack.backtrace.symbolicated(with: images)?.frames.map { makeFrame($0, images: images) } ?? []
            return AllocationStackReport.Stack(frames: trim(frames), count: stack.count, bytes: stack.bytes)
        }
        return AllocationStackReport(iterations: iterations, stacks: reportStacks)
    }

    static func makeFrame(_ frame: SymbolicatedBacktrace.Frame, images: ImageMap) -> AllocationStackReport.Frame {
        let isAsync: Bool
        if case .asyncResumePoint = frame.captured {
            isAsync = true
        } else {
            isAsync = false
        }
        guard let symbol = frame.symbol else {
            let address = frame.captured.originalProgramCounter
            let image = images.indexOfImage(at: address).flatMap { images[$0].name }
            return .init(symbol: "\(address)", image: image, isAsync: isAsync)
        }
        return .init(
            symbol: symbol.name,
            location: symbol.sourceLocation.flatMap(location),
            image: symbol.imageName,
            isAsync: isAsync
        )
    }

    /// `file:line`, or `nil` for line 0 / compiler-generated code. Those carry no information and
    /// would otherwise split stacks that differ only in how the optimizer laid out a call site.
    static func location(_ location: SymbolicatedBacktrace.SourceLocation) -> String? {
        guard location.line > 0, location.path.hasPrefix("<compiler-generated>") == false else {
            return nil
        }
        return "\(location.path):\(location.line)"
    }

    /// Drops the allocator/recorder frames above the allocation site and the harness frames
    /// below the benchmark closure. Pure so it can be unit-tested.
    static func trim(_ frames: [AllocationStackReport.Frame]) -> [AllocationStackReport.Frame] {
        var start = frames.startIndex
        while start < frames.endIndex, isRecordingFrame(frames[start]) {
            start += 1
        }
        let end = frames[start...].firstIndex(where: isHarnessFrame) ?? frames.endIndex
        return Array(frames[start..<end])
    }

    /// Frames of the allocator and the stack capture: the interposer, libc's malloc and, should the
    /// calibrated offset not cover them, the Runtime module and our hook.
    static func isRecordingFrame(_ frame: AllocationStackReport.Frame) -> Bool {
        let recordingImages = ["MallocInterposer", "libswiftRuntime", "libsystem_malloc"]
        if let image = frame.image, recordingImages.contains(where: { image.contains($0) }) {
            return true
        }
        return frame.symbol.contains("AllocationStackRecorder") || frame.symbol.hasPrefix("replacement_")
    }

    // Demangled names carry no module prefix, so match the harness by type and member.
    static let harnessSymbols = [
        "Benchmark.run()", "Benchmark.runAsync()", "Benchmark.init(", "BenchmarkExecutor.", "BenchmarkRunner.",
    ]

    /// Frames of the benchmark harness that calls into the benchmark closure.
    static func isHarnessFrame(_ frame: AllocationStackReport.Frame) -> Bool {
        harnessSymbols.contains { containsName(frame.symbol, $0) }
    }

    /// Whether `symbol` contains `name` starting at an identifier boundary, so that
    /// `Benchmark.run()` doesn't match a user's `MyBenchmark.run()`.
    static func containsName(_ symbol: String, _ name: String) -> Bool {
        var searchRange = symbol.startIndex..<symbol.endIndex
        while let range = symbol.range(of: name, range: searchRange) {
            if range.lowerBound == symbol.startIndex {
                return true
            }
            let previous = symbol[symbol.index(before: range.lowerBound)]
            if !(previous.isLetter || previous.isNumber || previous == "_") {
                return true
            }
            searchRange = symbol.index(after: range.lowerBound)..<symbol.endIndex
        }
        return false
    }
}

#endif
