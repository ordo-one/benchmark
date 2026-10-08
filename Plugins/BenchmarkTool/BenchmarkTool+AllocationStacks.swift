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
import Foundation

extension BenchmarkTool {
    /// Prints the allocation stack traces recorded with `--allocation-stacks`, per benchmark, stacks
    /// sorted by allocation count. With `--path` the full reports are written as JSON and non-empty
    /// reports as folded stacks (only the JSON, to stdout, for `--path stdout`).
    func reportAllocationStacks() throws {
        let reports = allocationStackReports.sorted { ($0.key.target, $0.key.name) < ($1.key.target, $1.key.name) }

        if path != "stdout" {
            if quiet == false, format != .markdown {
                "Allocation stacks".printAsHeader()
            }
            for (identifier, report) in reports {
                print(
                    report.formatted(
                        title: "\(identifier.target):\(identifier.name)",
                        limit: allocationStackLimit > 0 ? allocationStackLimit : nil,
                        markdown: format == .markdown
                    )
                )
                print("")
            }
        }

        if path != nil {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            for (identifier, report) in reports {
                try write(
                    exportData: String(decoding: try encoder.encode(report), as: UTF8.self),
                    fileName: cleanupStringForShellSafety("\(identifier.target).\(identifier.name).allocations.json")
                )
                if path != "stdout" {
                    let folded = report.foldedOutput()
                    if folded.isEmpty == false {
                        try write(
                            exportData: folded,
                            fileName: cleanupStringForShellSafety("\(identifier.target).\(identifier.name).allocations.folded")
                        )
                    }
                }
            }
        }
    }
}
