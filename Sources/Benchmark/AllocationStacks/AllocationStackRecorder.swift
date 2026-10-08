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
import Atomics
import MallocInterposerSwift
// Weakly linked: Darwin only ships libswiftRuntime from macOS 15.
@_weakLinked import Runtime
import SwiftRuntimeHooks

#if canImport(Darwin)
import Darwin
#endif

// swiftlint:disable prefer_self_in_static_references

/// Records the stack trace of every allocation made while installed, using the malloc
/// interposer's per-allocation hook and Swift's `Backtrace` API (which follows `async` frames).
///
/// The hook runs inside malloc on the allocating thread. Its own allocations (capturing the
/// backtrace, growing the stack table) re-enter the hook; a per-thread guard makes those
/// nested calls return immediately and tallies them so the malloc metrics can subtract them.
///
/// Each thread aggregates into its own ``ThreadRecorder`` so the hot path takes only an
/// uncontended lock.
enum AllocationStackRecorder {
    /// Raw aggregated stacks for one thread, keyed by frame addresses.
    final class ThreadRecorder {
        struct Entry {
            var count: Int
            var bytes: Int
            /// The first backtrace seen for this stack, kept for symbolication.
            var backtrace: Backtrace
        }

        let lock = NIOLock()
        var stacks: [[UInt]: Entry] = [:]
        // Only touched by the owning thread, so it lives outside the lock and keeps its capacity.
        var scratch: [UInt] = []
        /// Allocations made by the hook itself on this thread (count and bytes).
        let nestedCount = ManagedAtomic<Int>(0)
        let nestedBytes = ManagedAtomic<Int>(0)

        init(maxDepth: Int) {
            scratch.reserveCapacity(maxDepth)
        }

        func record(size: Int, maxDepth: Int) {
            // `.fast` walks frame pointers and follows async continuations
            // `top: 0` stops at the limit instead of walking to the outermost frames
            // `offset` skips the recorder's own frames
            guard
                let backtrace = try? Backtrace.capture(
                    algorithm: .fast,
                    limit: maxDepth,
                    offset: AllocationStackRecorder.ownFrameCount,
                    top: 0
                )
            else {
                return
            }

            scratch.removeAll(keepingCapacity: true)
            for frame in backtrace.frames {
                switch frame {
                case .programCounter(let address), .returnAddress(let address):
                    scratch.append(UInt(address) ?? 0)
                case .asyncResumePoint(let address):
                    // Distinguish async resume points from return addresses with the same value.
                    scratch.append((UInt(address) ?? 0) | AllocationStackRecorder.asyncFrameMarker)
                case .omittedFrames, .truncated:
                    break
                @unknown default:
                    break
                }
            }

            lock.withLockVoid {
                if let index = stacks.index(forKey: scratch) {
                    stacks.values[index].count += 1
                    stacks.values[index].bytes += size
                } else {
                    stacks[scratch] = Entry(count: 1, bytes: size, backtrace: backtrace)
                }
            }
        }
    }

    /// A merged, not yet symbolicated stack.
    struct RawStack {
        var count: Int
        var bytes: Int
        var backtrace: Backtrace
    }

    static let asyncFrameMarker: UInt = 1 << (UInt.bitWidth - 1)
    // Low bit of the per-thread state word: set while this thread is inside the hook.
    static let inHookFlag: UInt = 1

    static var maxDepth = 64
    /// The number of innermost frames belonging to the recorder itself, see ``calibrate()``.
    static var ownFrameCount = 0
    static let registryLock = NIOLock()
    static var recorders: [ThreadRecorder] = []
    /// Nested allocations made while a thread was still creating its recorder.
    static let orphanNestedCount = ManagedAtomic<Int>(0)
    static let orphanNestedBytes = ManagedAtomic<Int>(0)

    static let hook: MallocInterposerSwift.AllocationHook = { size in
        AllocationStackRecorder.recordAllocation(size: size)
    }

    /// Whether the Swift Runtime library the recorder needs was loaded.
    static var isAvailable: Bool {
        #if canImport(Darwin)
        return dlopen("/usr/lib/swift/libswiftRuntime.dylib", RTLD_NOLOAD) != nil
        #else
        return true
        #endif
    }

    /// Prepares the recorder; must be called before ``enable()``, outside of any measured region.
    static func configure(maxDepth: Int) {
        self.maxDepth = maxDepth
        benchmark_allocation_hook_state_initialize()
        // Force the lazy globals the hook reads to initialize now, not inside malloc.
        _ = (hook, registryLock, recorders, orphanNestedCount, orphanNestedBytes, asyncFrameMarker, inHookFlag)
        calibrate()
        reset()
    }

    /// Measures how many innermost frames of a capture belong to the recorder (the capture, the
    /// hook and its helpers), so they can be skipped without relying on symbols or inlining.
    static func calibrate() {
        let configuredDepth = maxDepth
        defer { maxDepth = configuredDepth }
        maxDepth = 64
        ownFrameCount = 0
        reset()

        calibrationCall(depth: 0)
        let shallow = rawStackKeys()
        reset()
        calibrationCall(depth: 1)
        let deep = rawStackKeys()

        guard shallow.count == 1, deep.count == 1,
            let divergence = zip(shallow[0], deep[0]).enumerated().first(where: { $0.element.0 != $0.element.1 })?.offset,
            divergence > 0
        else {
            writeToStandardError("Warning: could not determine the allocation stack recorder's own frames.")
            return
        }
        ownFrameCount = divergence - 1
    }

    @inline(never)
    private static func calibrationCall(depth: Int) {
        if depth == 0 {
            hook(0)
        } else {
            calibrationCall(depth: depth - 1)
        }
        // Keeps both calls out of tail position, so each depth has its own frame.
        blackHole(depth)
    }

    private static func rawStackKeys() -> [[UInt]] {
        registryLock.withLock {
            recorders.flatMap { recorder in
                recorder.lock.withLock { Array(recorder.stacks.keys) }
            }
        }
    }

    /// Starts recording allocations. Allocations are only seen while malloc counting is hooked.
    static func enable() {
        MallocInterposerSwift.setAllocationHook(hook)
    }

    static func disable() {
        MallocInterposerSwift.setAllocationHook(nil)
    }

    /// Clears all recorded stacks and nested-allocation tallies.
    static func reset() {
        registryLock.withLockVoid {
            for recorder in recorders {
                recorder.lock.withLockVoid {
                    recorder.stacks.removeAll()
                }
                recorder.nestedCount.store(0, ordering: .relaxed)
                recorder.nestedBytes.store(0, ordering: .relaxed)
            }
        }
        orphanNestedCount.store(0, ordering: .relaxed)
        orphanNestedBytes.store(0, ordering: .relaxed)
    }

    /// The total count and bytes of allocations made by the hook itself, which the interposer
    /// counted but which do not belong to the benchmark.
    ///
    /// Called inside the measured window, so it must not allocate itself even unoptimized. That's
    /// why we use explicit lock/unlock and index loop instead of closures and iterators.
    static func nestedAllocations() -> (count: Int, bytes: Int) {
        registryLock.lock()
        defer { registryLock.unlock() }
        var count = orphanNestedCount.load(ordering: .relaxed)
        var bytes = orphanNestedBytes.load(ordering: .relaxed)
        var index = 0
        while index < recorders.count {
            count += recorders[index].nestedCount.load(ordering: .relaxed)
            bytes += recorders[index].nestedBytes.load(ordering: .relaxed)
            index += 1
        }
        return (count, bytes)
    }

    /// All recorded stacks merged across threads. Call after ``disable()``.
    static func snapshot() -> [RawStack] {
        var merged: [[UInt]: RawStack] = [:]
        registryLock.withLockVoid {
            for recorder in recorders {
                recorder.lock.withLockVoid {
                    for (key, entry) in recorder.stacks {
                        if let index = merged.index(forKey: key) {
                            merged.values[index].count += entry.count
                            merged.values[index].bytes += entry.bytes
                        } else {
                            merged[key] = RawStack(count: entry.count, bytes: entry.bytes, backtrace: entry.backtrace)
                        }
                    }
                }
            }
        }
        return Array(merged.values)
    }

    @inline(__always)
    private static func recordAllocation(size: Int) {
        let state = UInt(benchmark_allocation_hook_state_get())

        if state & inHookFlag != 0 {
            // An allocation made by the hook itself: don't record it, but tally it for subtraction.
            if let recorder = recorder(from: state) {
                recorder.nestedCount.wrappingIncrement(ordering: .relaxed)
                recorder.nestedBytes.wrappingIncrement(by: size, ordering: .relaxed)
            } else {
                orphanNestedCount.wrappingIncrement(ordering: .relaxed)
                orphanNestedBytes.wrappingIncrement(by: size, ordering: .relaxed)
            }
            return
        }

        benchmark_allocation_hook_state_set(UInt(state | inHookFlag))
        let recorder = recorder(from: state) ?? makeThreadRecorder()
        recorder.record(size: size, maxDepth: maxDepth)
        benchmark_allocation_hook_state_set(UInt(bitPattern: Unmanaged.passUnretained(recorder).toOpaque()))
    }

    private static func recorder(from state: UInt) -> ThreadRecorder? {
        guard let pointer = UnsafeRawPointer(bitPattern: state & ~inHookFlag) else {
            return nil
        }
        return Unmanaged<ThreadRecorder>.fromOpaque(pointer).takeUnretainedValue()
    }

    private static func makeThreadRecorder() -> ThreadRecorder {
        let recorder = ThreadRecorder(maxDepth: maxDepth)
        registryLock.withLockVoid {
            recorders.append(recorder)
        }
        // Keep the guard set; the caller clears it once recording is done.
        benchmark_allocation_hook_state_set(UInt(bitPattern: Unmanaged.passUnretained(recorder).toOpaque()) | inHookFlag)
        return recorder
    }
}

// swiftlint:enable prefer_self_in_static_references
#endif
