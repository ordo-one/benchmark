//
// Copyright (c) 2026 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

// Symbolicates the raw addresses captured in the freame walking process.
//
// Tools: `atos -i` on macOS (dSYMs sit next to the SwiftPM release
// products), `llvm-symbolizer --inlines` on Linux (part of the Swift
// toolchain). When the tool, the debug info, or a particular address has
// nothing to offer, the frame falls back to the child's dladdr symbol —
// output is then identical to non-DWARF symbolication, never worse.

import Benchmark
import Foundation

/// One physical frame location, host-side key for symbolication results.
private struct FrameKey: Hashable, Codable {
    let image: String
    let offset: UInt64
}

// Codable only because BenchmarkTool (a ParsableCommand, hence Decodable) stores one.
struct DWARFSymbolicator: Codable {
    /// (image, offset) → inline chain, innermost (leaf) first.
    private var resolved: [FrameKey: [String]] = [:]

    /// Expands one report frame into display frames, root-first.
    func displayFrames(for frame: AllocationStacksReport.Frame) -> [String] {
        if let image = frame.image,
            let chain = resolved[FrameKey(image: image, offset: frame.offset)],
            chain.isEmpty == false
        {
            return chain.reversed() // innermost-first → root-first
        }
        return [frame.displayName]
    }

    /// Collects every unique (image, offset) in the reports and symbolicates
    /// them in batches, one symbolizer invocation per image.
    mutating func symbolicate(reports: [AllocationStacksReport]) {
        var perImage: [String: Set<UInt64>] = [:]

        for report in reports {
            for entry in report.entries {
                for frame in entry.frames {
                    if let image = frame.image {
                        perImage[image, default: []].insert(frame.offset)
                    }
                }
            }
        }

        for (image, offsets) in perImage {
            let sorted = offsets.sorted()
            #if os(macOS)
            symbolicateWithAtos(image: image, offsets: sorted)
            #else
            symbolicateWithLLVMSymbolizer(image: image, offsets: sorted)
            #endif
        }
    }

    // MARK: - macOS: atos

    #if os(macOS)
    /// Mach-O executables have their __TEXT segment at 0x100000000 in the
    /// file's address space; dylibs at 0. Frames carry load-relative
    /// offsets, so executable lookups need the rebase.
    private static let machOExecutableBase: UInt64 = 0x1_0000_0000
    private static let machHeaderExecutable: UInt32 = 0x2 // MH_EXECUTE
    private static let machOMagicHeader: UInt32 = 0xFEED_FACF

    private func machOFileAddressBase(image: String) -> UInt64? {
        guard let handle = FileHandle(forReadingAtPath: image),
            let header = try? handle.read(upToCount: 16), header.count == 16
        else {
            return nil
        }
        defer { try? handle.close() }
        let magic = header.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) }
        guard magic == Self.machOMagicHeader else { return nil }
        let filetype = header.withUnsafeBytes { $0.load(fromByteOffset: 12, as: UInt32.self) }
        return filetype == Self.machHeaderExecutable ? Self.machOExecutableBase : 0
    }

    private mutating func symbolicateWithAtos(image: String, offsets: [UInt64]) {
        let dsym = image + ".dSYM"
        guard FileManager.default.fileExists(atPath: dsym),
            let base = machOFileAddressBase(image: image)
        else {
            return // no debug info next to this image — dladdr fallback
        }

        // atos prints, per input address, the inline chain innermost-first
        // (one frame per line) — batching addresses makes the group
        // boundaries ambiguous, so resolve one address per invocation. The
        // few hundred unique frames a report contains keep this in the
        // low seconds, paid once per run, outside any measurement.
        for offset in offsets {
            let address = "0x" + String(base &+ offset, radix: 16)
            guard
                let output = runTool(
                    "/usr/bin/xcrun",
                    arguments: ["atos", "-o", image, "-d", dsym, "-i", address]
                )
            else { continue }

            let chain = output.split(separator: "\n").compactMap { line -> String? in
                let text = String(line).trimmingCharacters(in: .whitespaces)
                guard text.isEmpty == false else { return nil }
                // Unresolved addresses echo back as "0x... (in Image) + N"
                // or a bare address; treat those as no result.
                if text.hasPrefix("0x") { return nil }
                // atos may emit the dSYM path as a diagnostic line.
                if text.hasPrefix("/") && text.contains(" ") == false { return nil }
                return cleanAtosFrame(text)
            }
            if chain.isEmpty == false {
                resolved[FrameKey(image: image, offset: offset)] = chain
            }
        }
    }

    /// "name (in Image) (file.swift:12)" → "name (file.swift:12)"
    private func cleanAtosFrame(_ text: String) -> String {
        text.replacingOccurrences(
            of: #" \(in [^)]+\)"#, with: "", options: .regularExpression
        )
    }
    #endif

    // MARK: - Linux: llvm-symbolizer

    #if os(Linux)
    private mutating func symbolicateWithLLVMSymbolizer(image: String, offsets: [UInt64]) {
        // ELF PIE images are linked at base 0, so load-relative offsets are
        // file virtual addresses directly (verified against swift:6.x).
        let addresses = offsets.map { "0x" + String($0, radix: 16) }
        guard
            let output = runTool(
                "/usr/bin/env",
                arguments: ["llvm-symbolizer", "--obj=\(image)", "--inlines", "--demangle",
                            "--output-style=GNU"] + addresses
            )
        else {
            return
        }

        // GNU output style: for each address, pairs of lines
        // (function, file:line), addresses separated by an empty line.
        let groups = output.components(separatedBy: "\n\n")
        for (offset, group) in zip(offsets, groups) {
            let lines = group.split(separator: "\n").map(String.init)
            var chain: [String] = []
            var index = 0
            while index + 1 < lines.count {
                let function = lines[index]
                let location = lines[index + 1]
                index += 2
                guard function != "??", function.isEmpty == false else { continue }
                let name = demangleIfNeeded(function)
                if location.hasPrefix("??") || location.isEmpty {
                    chain.append(name)
                } else {
                    let short = location.split(separator: "/").last.map(String.init) ?? location
                    chain.append("\(name) (\(short))")
                }
            }
            if chain.isEmpty == false {
                resolved[FrameKey(image: image, offset: offset)] = chain
            }
        }
    }

    /// llvm-symbolizer's demangler handles C++ but not always Swift; run
    /// Swift-mangled leftovers through the runtime demangler.
    private func demangleIfNeeded(_ name: String) -> String {
        guard name.hasPrefix("$s") || name.hasPrefix("_$s") || name.hasPrefix("$S") else {
            return name
        }
        return SymbolDemangler.demangle(name) ?? name
    }
    #endif

    // MARK: - Process plumbing

    private func runTool(_ executable: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        return String(data: data, encoding: .utf8)
    }
}
