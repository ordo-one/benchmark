//
// Copyright (c) 2026 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

import ArgumentParser
import Benchmark
import Foundation

enum AllocationStacksExportFormat: String, ExpressibleByArgument {
    case folded
    case json
}

extension BenchmarkTool {
    /// Prints the allocation stack traces recorded with `--allocation-stacks`, per benchmark, stacks
    /// sorted by allocation count. `--export-allocation-stacks` exports the full reports in the chosen
    /// format. With `--allocation-stacks-export-path stdout`, only the exported data is printed.
    func reportAllocationStacks() throws {
        let reports = allocationStackReports.sorted { ($0.key.target, $0.key.name) < ($1.key.target, $1.key.name) }

        if allocationStacksToStdout == false {
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

        guard exportAllocationStacks else {
            return
        }

        let exportFormat = allocationStacksExportFormat ?? .folded
        for (identifier, report) in reports {
            let data: String
            switch exportFormat {
            case .folded:
                data = report.foldedOutput()
                guard data.isEmpty == false else {
                    continue
                }
            case .json:
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                data = String(decoding: try encoder.encode(report), as: UTF8.self)
            }
            try write(
                exportData: data,
                fileName: cleanupStringForShellSafety("\(identifier.target).\(identifier.name).allocations.\(exportFormat.rawValue)"),
                exportPath: allocationStacksExportPath ?? "."
            )
        }
    }
}
