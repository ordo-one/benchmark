//
// Copyright (c) 2026 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

/// The unique stack traces of all allocations made in the measured region of a benchmark.
@_documentation(visibility: internal)
public struct AllocationStackReport: Codable, Equatable {
    /// A symbolicated stack frame.
    public struct Frame: Codable, Hashable {
        /// The demangled symbol name, or the raw address if it could not be symbolicated.
        public var symbol: String
        /// `file:line` of the frame, if debug information was available.
        public var location: String?
        /// The name of the image (executable or library) containing the frame.
        public var image: String?
        /// Whether this frame is an `async` resume point rather than a regular return address.
        public var isAsync: Bool

        public init(symbol: String, location: String? = nil, image: String? = nil, isAsync: Bool = false) {
            self.symbol = symbol
            self.location = location
            self.image = image
            self.isAsync = isAsync
        }
    }

    /// A unique allocation stack trace, innermost frame first.
    public struct Stack: Codable, Equatable {
        public var frames: [Frame]
        /// The number of allocations made with this stack trace.
        public var count: Int
        /// The number of bytes allocated with this stack trace.
        public var bytes: Int

        public init(frames: [Frame], count: Int, bytes: Int) {
            self.frames = frames
            self.count = count
            self.bytes = bytes
        }
    }

    /// The number of measured iterations the stacks were captured over.
    public var iterations: Int
    /// The unique stacks, sorted by allocation count, highest first.
    public var stacks: [Stack]

    public var totalCount: Int { stacks.reduce(0) { $0 + $1.count } }
    public var totalBytes: Int { stacks.reduce(0) { $0 + $1.bytes } }

    /// Creates a report, merging stacks with identical frames and sorting them by count
    /// (highest first), then bytes, then frames for a stable order.
    public init(iterations: Int, stacks: [Stack]) {
        self.iterations = iterations

        var merged: [[Frame]: Stack] = [:]
        for stack in stacks {
            merged[stack.frames, default: Stack(frames: stack.frames, count: 0, bytes: 0)].count += stack.count
            merged[stack.frames]!.bytes += stack.bytes
        }
        self.stacks = merged.values.sorted { lhs, rhs in
            if lhs.count != rhs.count {
                return lhs.count > rhs.count
            }
            if lhs.bytes != rhs.bytes {
                return lhs.bytes > rhs.bytes
            }
            return lhs.frames.map(\.symbol).lexicographicallyPrecedes(rhs.frames.map(\.symbol))
        }
    }
}
