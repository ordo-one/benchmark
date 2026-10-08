//
// Copyright (c) 2026 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

#if canImport(MallocInterposerSwift)

import MallocInterposerSwift

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

#if canImport(Darwin)
private typealias SymbolInfo = Dl_info

private func symbolInfo(for address: UnsafeRawPointer) -> SymbolInfo? {
    var info = SymbolInfo()
    return dladdr(address, &info) != 0 ? info : nil
}
#else
// Glibc/Musl gate dladdr and Dl_info behind _GNU_SOURCE, so the Swift
// overlays don't declare them — declare a layout-compatible mirror struct
// (identical on glibc and musl) and resolve the function via dlsym, calling
// it through a proper C-convention pointer (same pattern as SymbolDemangler).
private struct SymbolInfo {
    var dli_fname: UnsafePointer<CChar>?
    var dli_fbase: UnsafeMutableRawPointer?
    var dli_sname: UnsafePointer<CChar>?
    var dli_saddr: UnsafeMutableRawPointer?
}

// The info parameter is a raw pointer in the C-convention type: on Linux,
// @convention(c) signatures may not reference Swift struct types (Darwin
// happens to accept them). The struct view is applied on the Swift side.
private typealias DladdrFunction = @convention(c) (
    UnsafeRawPointer?, UnsafeMutableRawPointer?
) -> CInt

private let dladdrFunction: DladdrFunction? = {
    guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "dladdr") else {
        return nil
    }
    return unsafeBitCast(symbol, to: DladdrFunction.self)
}()

private func symbolInfo(for address: UnsafeRawPointer) -> SymbolInfo? {
    guard let dladdrFunction else {
        return nil
    }
    var info = SymbolInfo()
    let found = withUnsafeMutablePointer(to: &info) {
        dladdrFunction(address, UnsafeMutableRawPointer($0)) != 0
    }
    return found ? info : nil
}
#endif


/// Turns the raw program counters captured by the malloc interposer into
/// human-readable frames. Runs in the benchmark child process, strictly
/// after capture is disabled (symbolication allocates freely).
struct AllocationStackSymbolicator {
    /// Each unique program counter is resolved at most once per benchmark.
    private var cache: [UInt: AllocationStacksReport.Frame?] = [:]

    /// Image base of the interposer library, used to strip the interposer's
    /// own leading frames (the recorder, count_malloc remnants, and the
    /// replacement functions) robustly regardless of inlining.
    private static let interposerImageBase: UnsafeMutableRawPointer? = {
        // dlopen(nil) yields the global namespace handle portably (avoids
        // the per-platform RTLD_DEFAULT constant).
        guard let anchor = dlsym(dlopen(nil, RTLD_NOW), "malloc_interposer_enable") else {
            return nil
        }
        return symbolInfo(for: anchor)?.dli_fbase
    }()

    /// Resolves one captured return address to a structured frame, or nil if
    /// the frame belongs to the interposer image and should be stripped.
    ///
    /// Only classification happens in-process: image path, image-relative
    /// offset (ASLR-independent, so the host can feed it to DWARF
    /// symbolication with inline expansion), plus the nearest-symbol name
    /// from dladdr as a fallback for frames without debug info.
    private mutating func resolve(_ programCounter: UInt) -> AllocationStacksReport.Frame? {
        if let cached = cache[programCounter] {
            return cached
        }

        var resolved: AllocationStacksReport.Frame?
        // Captured frames are return addresses: the address *after* the
        // call. Back up one byte so the call site's own symbol/line wins.
        // The stored offset keeps that adjustment so the host-side DWARF
        // lookup attributes the call site correctly too.
        if let address = UnsafeRawPointer(bitPattern: programCounter &- 1) {
            if let info = symbolInfo(for: address) {
                if let interposerImageBase = Self.interposerImageBase, info.dli_fbase == interposerImageBase {
                    resolved = nil // interposer-internal frame — strip
                } else {
                    let image = info.dli_fname.map { String(cString: $0) }
                    let offset: UInt64
                    if let imageBase = info.dli_fbase, image != nil {
                        offset = UInt64(programCounter &- UInt(bitPattern: imageBase) &- 1)
                    } else {
                        offset = UInt64(programCounter)
                    }
                    // Raw symbol only — demangling is presentation, done
                    // lazily in the host via Frame.displayName.
                    let symbol = info.dli_sname.map { String(cString: $0) }
                    resolved = AllocationStacksReport.Frame(
                        image: info.dli_fbase != nil ? image : nil,
                        offset: offset,
                        symbol: symbol
                    )
                }
            } else {
                resolved = AllocationStacksReport.Frame(image: nil, offset: UInt64(programCounter), symbol: nil)
            }
        }

        cache[programCounter] = resolved
        return resolved
    }

    /// Classifies a snapshot into a report, dropping the interposer's
    /// leading frames and reordering each stack root-first. `iterations` is
    /// the number of measured iterations the snapshot spans and
    /// `scalingFactor` the benchmark's inner-loop multiplier, so consumers
    /// can present per-iteration figures like the other metrics.
    mutating func makeReport(
        from snapshot: MallocInterposerSwift.AllocationStackSnapshot, iterations: Int, scalingFactor: Int
    ) -> AllocationStacksReport {
        var entries: [AllocationStacksReport.Entry] = []
        entries.reserveCapacity(snapshot.stacks.count)

        for stack in snapshot.stacks {
            // Iterate an independent copy of the captured program counters. The
            // snapshot's frames buffers can be reclaimed out of band (at the
            // allocator level, not via ARC — pinning the snapshot does not
            // prevent it) while this loop runs; resolve() then allocates
            // heavily (dladdr image-path Strings, demangle buffers) and one of
            // those reuses the reclaimed block, so iterating stack.frames
            // directly reads freed-and-reused memory. A fresh, independently
            // allocated buffer is immune. See issue notes for the full
            // investigation; the underlying out-of-band free is tracked
            // separately.
            let programCounters = Array(stack.frames)
            var frames: [AllocationStacksReport.Frame] = []
            frames.reserveCapacity(programCounters.count)
            // Captured leaf-first; interposer frames form a leading run.
            var pastInterposerFrames = false
            for programCounter in programCounters {
                if let frame = resolve(programCounter) {
                    pastInterposerFrames = true
                    frames.append(frame)
                } else if pastInterposerFrames {
                    // An interposer frame *below* user frames shouldn't
                    // happen; keep a marker rather than silently dropping it.
                    frames.append(.init(image: nil, offset: 0, symbol: "<interposer>"))
                }
            }
            guard frames.isEmpty == false else { continue }
            frames.reverse() // root-first
            entries.append(.init(frames: frames, count: stack.count, bytes: stack.bytes))
        }

        entries.sort { $0.count > $1.count }

        let recorded = entries.reduce(0) { $0 + $1.count }
        return AllocationStacksReport(
            entries: entries,
            droppedAllocations: snapshot.droppedAllocations,
            totalAllocations: recorded + snapshot.droppedAllocations,
            iterations: iterations,
            scalingFactor: scalingFactor
        )
    }
}

#endif
