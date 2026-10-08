//
// Copyright (c) 2026 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

/// Aggregated, symbolicated allocation call stacks captured during the
/// measurement windows of a single benchmark run with `--allocation-stacks`.
///
/// Produced in the benchmark child process (raw program counters are only
/// meaningful there) and sent to the host over the command channel for
/// output and export.
@_documentation(visibility: internal)
public struct AllocationStacksReport: Codable, Sendable {
    /// One captured physical stack frame. Carries the image-relative offset
    /// (ASLR-independent, so it stays meaningful outside the process that
    /// captured it — the host uses it for DWARF symbolication with inline
    /// expansion) plus the in-process `dladdr` symbol as a fallback.
    public struct Frame: Codable, Sendable {
        /// Path of the image containing the frame, nil if unresolvable.
        public var image: String?

        /// Image-relative offset of the (call-site-adjusted) return address;
        /// when `image` is nil this holds the raw address instead.
        public var offset: UInt64

        /// Raw (mangled) nearest-symbol name from `dladdr`, nil when the
        /// symbol table has no name for the address (common for
        /// Swift-internal functions on Linux). Demangling happens lazily at
        /// display time via ``displayName``.
        public var symbol: String?

        public init(image: String?, offset: UInt64, symbol: String?) {
            self.image = image
            self.offset = offset
            self.symbol = symbol
        }

        /// Best human-readable name without DWARF: the demangled symbol,
        /// else image+offset (stable across runs), else a bare address.
        public var displayName: String {
            if let symbol {
                return SymbolDemangler.demangle(symbol) ?? symbol
            }
            let hex = "0x" + String(offset, radix: 16)
            if let image {
                let baseName = image.split(separator: "/").last.map(String.init) ?? image
                return "\(baseName)+\(hex)"
            }
            return hex
        }
    }

    public struct Entry: Codable, Sendable {
        /// Physical frames, root-first (`main` towards the allocation site).
        public var frames: [Frame]

        /// Number of allocations that produced exactly this stack.
        public var count: Int

        /// Sum of requested allocation sizes for this stack, in bytes.
        public var bytes: Int

        public init(frames: [Frame], count: Int, bytes: Int) {
            self.frames = frames
            self.count = count
            self.bytes = bytes
        }
    }

    /// Unique stacks, sorted by allocation count, descending.
    public var entries: [Entry]

    /// Allocations whose stack could not be captured (frame-pointer walk
    /// failed or the capture table was full). Allocation-count metrics are
    /// exact regardless.
    public var droppedAllocations: Int

    /// Total allocations observed across all measurement windows, including dropped ones.
    public var totalAllocations: Int

    /// Number of measured iterations the stacks were aggregated over. The
    /// other metrics are reported per iteration; dividing by this puts the
    /// stack counts on the same footing (see ``perIteration(_:)``).
    public var iterations: Int

    /// The benchmark's `scalingFactor` (inner-loop multiplier) as a raw
    /// count. The metric tables divide by it unless `--scale` is given;
    /// ``perIteration(_:atLeastOne:scaled:)`` does the same.
    public var scalingFactor: Int

    public init(
        entries: [Entry], droppedAllocations: Int, totalAllocations: Int, iterations: Int = 1, scalingFactor: Int = 1
    ) {
        self.entries = entries
        self.droppedAllocations = droppedAllocations
        self.totalAllocations = totalAllocations
        self.iterations = max(iterations, 1)
        self.scalingFactor = max(scalingFactor, 1)
    }

    /// `true` when nothing was recorded: no stacks and no dropped samples.
    public var isEmpty: Bool {
        entries.isEmpty && droppedAllocations == 0
    }

    /// A run-total converted to a per-iteration figure, matching how the
    /// `mallocCountTotal` metric is reported: divided by the number of
    /// iterations and, when `scaled` (the default, the metric tables'
    /// behavior without `--scale`), by the benchmark's scaling factor too.
    /// Rounded to nearest. With `atLeastOne` (the default, meant for
    /// counts) anything that was observed at all stays at least 1 so rare,
    /// run-once stacks (lazy initialization, caches warming up) remain
    /// visible rather than vanishing into a zero; byte figures should pass
    /// `false`.
    public func perIteration(_ total: Int, atLeastOne: Bool = true, scaled: Bool = true) -> Int {
        guard total > 0 else { return 0 }
        let divisor = Double(iterations) * (scaled ? Double(scalingFactor) : 1)
        let rounded = Int((Double(total) / divisor).rounded())
        return atLeastOne ? max(1, rounded) : rounded
    }

    /// Renders the report in collapsed/folded stack format —
    /// `frameRoot;frame;frameLeaf count`, one unique stack per line — as
    /// consumed by `flamegraph.pl`, speedscope, and friends, and convenient
    /// for line-based diffing of two runs.
    ///
    /// Counts are per iteration (``perIteration(_:atLeastOne:scaled:)``), so
    /// files from two runs line up even when the runs performed different
    /// numbers of iterations, and the totals agree with the
    /// `mallocCountTotal` metric. `scaled` mirrors the metric tables: divide
    /// by the scaling factor unless the user asked for `--scale` output.
    ///
    /// `resolver` maps one physical frame to one or more display frames,
    /// root-first — DWARF symbolication uses it to expand inlined calls.
    /// The default resolver emits the frame's `displayName`.
    ///
    /// Identical frame sequences (possible after symbolication collapses
    /// distinct program counters into the same symbols) are merged.
    public func foldedOutput(scaled: Bool = true, resolver: ((Frame) -> [String])? = nil) -> String {
        var output = ""
        output.reserveCapacity(entries.count * 128)

        for entry in resolvedEntries(resolver: resolver) {
            output += "\(entry.frames.joined(separator: ";")) \(perIteration(entry.count, scaled: scaled))\n"
        }

        return output
    }

    /// One unique stack after symbolication: display frames root-first
    /// (already ";"-escaped) with the merged totals.
    public struct ResolvedEntry: Sendable {
        public let frames: [String]
        public let count: Int
        public let bytes: Int
    }

    /// The entries as display frames, merged wherever symbolication turned
    /// distinct program counters into the same frame sequence, sorted by
    /// count descending. Both the console table and ``foldedOutput`` are
    /// built from this, so they always agree on rows, counts and bytes.
    public func resolvedEntries(resolver: ((Frame) -> [String])? = nil) -> [ResolvedEntry] {
        let resolve = resolver ?? { [$0.displayName] }
        var merged: [[String]: (count: Int, bytes: Int)] = [:]
        var order: [[String]] = []

        for entry in entries {
            // Frames hold demangled symbols which may themselves contain
            // ";" (e.g. in generic parameter lists) — escape to keep the
            // folded format unambiguous.
            let frames = entry.frames
                .flatMap(resolve)
                .map { $0.replacingOccurrences(of: ";", with: ",") }
            if merged[frames] == nil {
                order.append(frames)
            }
            merged[frames, default: (0, 0)].count += entry.count
            merged[frames, default: (0, 0)].bytes += entry.bytes
        }

        return order
            .map { ResolvedEntry(frames: $0, count: merged[$0]!.count, bytes: merged[$0]!.bytes) }
            .sorted { $0.count > $1.count }
    }
}
