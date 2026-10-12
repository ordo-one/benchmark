//
// Copyright (c) 2026 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

@_documentation(visibility: internal)
public extension AllocationStackReport {
    /// Renders all allocation stacks in the collapsed format accepted by flamegraph.pl and speedscope.
    ///
    /// Each line contains semicolon-separated frames, outermost first, followed by a space and the
    /// total allocation count across all measured iterations. Counts are exact integers, including
    /// allocations seen only once during the run; they are not normalized by iterations or scaling.
    ///
    /// Frame labels include source locations (or image names) and async markers. Semicolons and
    /// newlines inside labels are replaced to preserve the format. Stacks with identical rendered
    /// labels are merged, then sorted by count descending and label ascending for deterministic output.
    /// An empty report produces an empty string.
    func foldedOutput() -> String {
        var counts: [String: Int] = [:]
        for stack in stacks where stack.count >= 1 {
            let frames = stack.frames.reversed().map(\.foldedName)
            let label = frames.isEmpty ? "<no frames outside the benchmark harness>" : frames.joined(separator: ";")
            counts[label, default: 0] += stack.count
        }

        return counts.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
        }.map { "\($0.key) \($0.value)\n" }.joined()
    }
}

private extension AllocationStackReport.Frame {
    var foldedName: String {
        var label = symbol.isEmpty ? "<unknown>" : symbol
        if isAsync {
            label += " [async]"
        }
        if let location {
            label += " at \(location)"
        } else if let image {
            label += " in \(image)"
        }
        return String(label.map { character in
            if character == ";" {
                return ","
            }
            return character.isNewline ? " " : character
        })
    }
}
