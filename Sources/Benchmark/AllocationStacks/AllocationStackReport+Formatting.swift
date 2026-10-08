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
    /// Renders the report as text (or markdown), stacks sorted by allocation count, highest first.
    ///
    /// - Parameters:
    ///   - title: Heading identifying the benchmark, e.g. `Target:Name`.
    ///   - limit: The maximum number of stacks to show; `nil` shows all.
    ///   - markdown: Whether to render markdown instead of plain text.
    func formatted(title: String, limit: Int? = nil, markdown: Bool = false) -> String {
        let shownStacks = limit.map { Array(stacks.prefix($0)) } ?? stacks
        let total = totalCount
        let summary = "\(Self.grouped(iterations)) iterations, \(Self.allocations(total, iterations: iterations)), "
            + "\(Self.bytes(totalBytes)), \(Self.grouped(stacks.count)) unique stack\(stacks.count == 1 ? "" : "s")"

        var lines: [String] = []
        if markdown {
            lines.append("### Allocations: \(title)")
            lines.append("")
            lines.append(summary)
        } else {
            lines.append("Allocations: \(title) — \(summary)")
        }
        if shownStacks.count < stacks.count {
            lines.append(
                "Showing the top \(shownStacks.count == 1 ? "stack" : "\(shownStacks.count) stacks")"
                    + " (\(Self.percentage(shownStacks.reduce(0) { $0 + $1.count }, of: total)) of allocations)."
            )
        }

        for (index, stack) in shownStacks.enumerated() {
            let heading = "#\(index + 1)  \(Self.allocations(stack.count, iterations: iterations)), "
                + "\(Self.percentage(stack.count, of: total)), \(Self.bytes(stack.bytes))"
            lines.append("")
            lines.append(markdown ? "**\(heading)**" : heading)
            if markdown {
                lines.append("```")
            }
            if stack.frames.isEmpty {
                lines.append("    <no frames outside the benchmark harness>")
            }
            let indexWidth = String(stack.frames.count - 1).count
            for (frameIndex, frame) in stack.frames.enumerated() {
                let number = String(frameIndex).leftPadded(to: indexWidth)
                var line = "    \(number)  \(frame.symbol)"
                if frame.isAsync {
                    line += " [async]"
                }
                if let location = frame.location {
                    line += " at \(location)"
                } else if let image = frame.image {
                    line += " in \(image)"
                }
                lines.append(line)
            }
            if markdown {
                lines.append("```")
            }
        }
        return lines.joined(separator: "\n")
    }

    internal static func allocations(_ count: Int, iterations: Int) -> String {
        let perIteration = iterations > 0 ? Double(count) / Double(iterations) : 0
        return "\(grouped(count)) allocation\(count == 1 ? "" : "s") (\(oneDecimal(perIteration))/iteration)"
    }

    internal static func percentage(_ count: Int, of total: Int) -> String {
        total > 0 ? "\(oneDecimal(100 * Double(count) / Double(total)))%" : "0.0%"
    }

    internal static func bytes(_ bytes: Int) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unit = 0
        while value >= 1_000, unit < units.count - 1 {
            value /= 1_000
            unit += 1
        }
        return unit == 0 ? "\(bytes) B" : "\(oneDecimal(value)) \(units[unit])"
    }

    internal static func oneDecimal(_ value: Double) -> String {
        let tenths = Int((value * 10).rounded())
        return "\(grouped(tenths / 10)).\(abs(tenths % 10))"
    }

    internal static func grouped(_ value: Int) -> String {
        let digits = String(value.magnitude)
        var result = ""
        for (index, digit) in digits.enumerated() {
            if index > 0, (digits.count - index).isMultiple(of: 3) {
                result.append(",")
            }
            result.append(digit)
        }
        return value < 0 ? "-" + result : result
    }
}

private extension String {
    func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }
}
