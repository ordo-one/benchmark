//
// Copyright (c) 2026 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

// Output for --allocation-stacks: one collapsed/folded stack file per
// benchmark (consumable by flamegraph.pl / speedscope and line-diffable
// between runs) plus a compact per-benchmark console table.
// Full stacks live in the .folded files.

import Benchmark
import TextTable

extension BenchmarkTool {
    /// Runs DWARF symbolication (with inline expansion) over every collected
    /// report once; frames without debug info keep their dladdr fallback.
    func makeAllocationStacksSymbolicator() -> DWARFSymbolicator {
        var symbolicator = DWARFSymbolicator()
        symbolicator.symbolicate(reports: Array(allocationStacksReports.values))
        return symbolicator
    }

    /// Reports that actually recorded something, in stable output order.
    /// Benchmarks that made no allocations are summarized in one line by
    /// the console output and get no (empty) export file.
    private var nonEmptyAllocationStacksReports: [(BenchmarkIdentifier, AllocationStacksReport)] {
        allocationStacksReports
            .filter { $0.value.isEmpty == false }
            .sorted { $0.key.target + $0.key.name < $1.key.target + $1.key.name }
    }

    /// Writes each benchmark's aggregated allocation stacks in folded format,
    /// honoring `--path` exactly like the other exporters.
    func exportAllocationStacks(symbolicator: DWARFSymbolicator) throws {
        for (identifier, report) in nonEmptyAllocationStacksReports {
            try write(
                exportData: report.foldedOutput(scaled: scale == false, resolver: symbolicator.displayFrames(for:)),
                fileName: cleanupStringForShellSafety("\(identifier.target).\(identifier.name).allocations.folded")
            )
        }
    }

    /// One table row: a unique allocation stack, labeled by its site.
    private struct AllocationStackRow {
        let site: String
        let count: String
        let share: String
        let bytes: String
    }

    /// Frames that are pure allocator plumbing and appear at the leaf end of
    /// every stack — never useful as a row label.
    private static let allocatorMachineryPrefixes = [
        "_malloc_type_", "malloc_type_",
        "swift_slowAlloc", "swift::swift_slowAlloc",
        "swift_allocObject", "_swift_allocObject_", "swift::swift_allocObject",
        "_swift_alloc_object_hook",
        "swift_slowDealloc",
    ]

    /// The leaf-most frame that isn't allocator machinery — the closest thing
    /// to "the line that allocated".
    private func allocationSite(frames: [String]) -> String {
        for frame in frames.reversed() {
            let isMachinery = Self.allocatorMachineryPrefixes.contains { frame.hasPrefix($0) }
            if isMachinery == false {
                return frame
            }
        }
        return frames.last ?? "?"
    }

    // Matches the (file-private) formatter the metric tables use.
    private func formatAllocationCount(_ value: Int) -> String {
        if abs(value) >= 10_000_000 {
            return String(format: "%.2e", Double(value))
        }
        return "\(value)"
    }

    /// Whether a stack is too rare for a per-iteration figure to mean
    /// anything: seen less than once every other iteration, typically
    /// one-time runtime warm-up such as class realization or metadata
    /// caching. Such rows show their run totals instead, suffixed "per run".
    private func isRunTotalRow(count: Int, report: AllocationStacksReport, scaled: Bool) -> Bool {
        let divisor = Double(report.iterations) * (scaled ? Double(report.scalingFactor) : 1)
        return Double(count) / divisor < 0.5
    }

    private func formatPerIteration(_ total: Int, report: AllocationStacksReport, scaled: Bool, runTotal: Bool) -> String {
        if runTotal {
            return "\(formatAllocationCount(total)) per run"
        }
        return formatAllocationCount(report.perIteration(total, atLeastOne: false, scaled: scaled))
    }

    /// Prints a benchmark's stacks table right under its metric table
    /// (per-benchmark grouping, text/markdown). The metric-grouped layout
    /// has no per-benchmark block, so it gets the trailing section from
    /// ``printAllocationStacksSummary(symbolicator:topEntries:)`` instead.
    func printAllocationStacks(for identifier: BenchmarkIdentifier) {
        guard quiet == false, format == .text || format == .markdown, grouping == .benchmark,
            let symbolicator = allocationStacksSymbolicator,
            let report = allocationStacksReports[identifier], report.isEmpty == false
        else {
            return
        }
        printAllocationStacksTable(identifier: identifier, report: report, symbolicator: symbolicator, standalone: false)
    }

    /// Trailing output after all results: the per-benchmark tables when the
    /// results were grouped by metric (nowhere else to put them), then the
    /// one-line notes that apply to the whole run. Full stacks are written
    /// to the .folded files, never to the console.
    func printAllocationStacksSummary(symbolicator: DWARFSymbolicator, topEntries: Int = 10) {
        guard quiet == false, format == .text || format == .markdown, allocationStacksReports.isEmpty == false else {
            return
        }

        let reports = nonEmptyAllocationStacksReports
        let unit = scale == false ? "per iteration *" : "per iteration"

        if grouping == .metric, reports.isEmpty == false {
            "Allocation call stacks (top \(topEntries) by allocation count, \(unit))".printAsHeader()
            for (identifier, report) in reports {
                printAllocationStacksTable(
                    identifier: identifier, report: report, symbolicator: symbolicator,
                    standalone: true, topEntries: topEntries
                )
            }
        }

        let silentBenchmarks = allocationStacksReports.count - reports.count
        if silentBenchmarks > 0 {
            print("\(silentBenchmarks) benchmark(s) made no allocations inside the measurement windows and have no allocation stacks.")
        }
        print(
            "Allocation stacks: counts are \(unit), top \(topEntries) by allocation count; "
                + "rows marked per run were seen less than once per iteration and show totals for the whole run. "
                + "Full call stacks are in the .allocations.folded file per benchmark "
                + "(flamegraph.pl/speedscope compatible, counts \(unit))."
        )
        print("")
    }

    /// One benchmark's block: a title line with the totals, then a row per
    /// unique allocation stack, top-N by allocation count, in the metric
    /// tables' style. Counts and bytes are per iteration and, unless
    /// `--scale` was given, divided by the benchmark's scaling factor,
    /// exactly like the malloc metrics (`*` marks scaled figures there and
    /// here), so a row can be read against `mallocCountTotal` directly.
    /// `standalone` titles the block with the benchmark name (trailing
    /// section); otherwise it sits under the benchmark's own metric table.
    private func printAllocationStacksTable(
        identifier: BenchmarkIdentifier,
        report: AllocationStacksReport,
        symbolicator: DWARFSymbolicator,
        standalone: Bool,
        topEntries: Int = 10
    ) {
        let scaled = scale == false
        let unit = scaled ? "per iteration *" : "per iteration"
        let total = max(report.totalAllocations, 1)

        // Same merged, symbolicated list the .folded file is written from,
        // so the table's rows and counts match the file line for line.
        let resolved = report.resolvedEntries(resolver: symbolicator.displayFrames(for:))
        var siteWidth = "Allocation site".count
        let rows = resolved.prefix(topEntries).map { entry -> AllocationStackRow in
            let site = allocationSite(frames: entry.frames)
            siteWidth = max(siteWidth, site.count)
            let runTotal = isRunTotalRow(count: entry.count, report: report, scaled: scaled)
            return AllocationStackRow(
                site: site,
                count: formatPerIteration(entry.count, report: report, scaled: scaled, runTotal: runTotal),
                share: String(format: "%.1f", 100.0 * Double(entry.count) / Double(total)),
                bytes: formatPerIteration(entry.bytes, report: report, scaled: scaled, runTotal: runTotal)
            )
        }
        siteWidth = min(siteWidth, 80)

        let table = TextTable<AllocationStackRow> {
            [
                Column(title: "Allocation site", value: $0.site, width: siteWidth, align: .left),
                Column(title: "Count", value: $0.count, width: 14, align: .right),
                Column(title: "%", value: $0.share, width: 6, align: .right),
                Column(title: "Bytes", value: $0.bytes, width: 14, align: .right),
            ]
        }

        // The total follows the same rule as the rows: per iteration unless the
        // whole benchmark allocates less than once every other iteration, in
        // which case the run total is shown ("198 allocations per run").
        let totalText: String
        if isRunTotalRow(count: report.totalAllocations, report: report, scaled: scaled) {
            totalText = "\(formatAllocationCount(report.totalAllocations)) allocations per run"
        } else {
            let perIteration = formatPerIteration(report.totalAllocations, report: report, scaled: scaled, runTotal: false)
            totalText = "\(perIteration) allocations \(unit)"
        }
        let scaling = scaled && report.scalingFactor > 1 ? " × \(report.scalingFactor) (scaled)" : ""
        let summary =
            "\(totalText), \(resolved.count) unique stacks over \(report.iterations) iterations\(scaling)"
        let title = standalone ? "\(identifier.name)" : "Allocation call stacks"

        if format == .markdown {
            print(standalone ? "### \(title)" : "#### \(title)")
            print("")
            print(summary)
            print("")
        } else {
            print("\(title) (\(summary))")
        }

        if report.droppedAllocations > 0 {
            print(
                "Warning: \(report.droppedAllocations) allocation sample(s) were dropped "
                    + "(stack capture table full or frame-pointer walk failed); "
                    + "allocation count metrics remain exact."
            )
        }

        table.print(Array(rows), style: format.tableStyle)
    }
}
