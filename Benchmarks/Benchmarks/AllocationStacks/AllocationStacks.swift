//
// Copyright (c) 2026 Ordo One AB
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Benchmarks exercising `--allocation-stacks`. Each one produces a known
// set of allocation call stacks so the per-benchmark summary and the
// .folded export can be checked by eye:
//
//   swift package --allow-writing-to-package-directory benchmark run \
//       --target AllocationStacksBenchmarks --allocation-stacks
//
// Every benchmark's comment states what the stacks table should show. The
// invariant across all of them: the per-iteration counts in the table sum
// to the mallocCountTotal metric printed just above it.
//
// Allocation sites are @inline(never) functions so each has its own frame
// and therefore its own row. Where a C malloc/free pair is used, the stack
// is just "<site> ; malloc" and the count is exact; the Swift-object
// variants show DWARF inline expansion and runtime frames instead.

import Benchmark

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#else
#error("Unsupported Platform")
#endif

// MARK: - Allocation sites

@inline(never)
func siteA(_ count: Int) {
    for _ in 0..<count {
        let ptr = malloc(32)
        blackHole(ptr)
        free(ptr)
    }
}

@inline(never)
func siteB(_ count: Int) {
    for _ in 0..<count {
        let ptr = malloc(64)
        blackHole(ptr)
        free(ptr)
    }
}

@inline(never)
func setupSite(_ count: Int) {
    for _ in 0..<count {
        let ptr = malloc(128)
        blackHole(ptr)
        free(ptr)
    }
}

@inline(never)
func oncePerOuterIterationSite() {
    let ptr = malloc(256)
    blackHole(ptr)
    free(ptr)
}

/// Allocates once at the bottom of `depth` nested frames. Distinct depths
/// produce distinct stacks; depths beyond the capture cap (64 frames) are
/// truncated leaf-first, so the benchmark closure drops out of the root.
@inline(never)
func allocateAtDepth(_ depth: Int) {
    if depth == 0 {
        let ptr = malloc(16)
        blackHole(ptr)
        free(ptr)
    } else {
        allocateAtDepth(depth - 1)
    }
    recursionSideEffect &+= 1 // defeats tail-call optimization
}

nonisolated(unsafe) var recursionSideEffect = 0

final class Node {
    let value: Int
    init(_ value: Int) { self.value = value }
}

@inline(never)
func makeNodes(_ count: Int) -> [Node] {
    var nodes: [Node] = []
    nodes.reserveCapacity(count)
    for value in 0..<count {
        nodes.append(Node(value))
    }
    return nodes
}

@inline(never)
func appendWithoutReserve(_ count: Int) -> [Int] {
    var values: [Int] = []
    for value in 0..<count {
        values.append(value)
    }
    return values
}

// MARK: - Benchmarks

let benchmarks: @Sendable () -> Void = {
    Benchmark.defaultConfiguration = .init(
        metrics: [.wallClock, .mallocCountTotal],
        warmupIterations: 1,
        scalingFactor: .kilo,
        maxDuration: .seconds(1),
        maxIterations: 100
    )

    // Nothing allocates: the benchmark must be omitted from the stacks
    // summary and get no .folded file (it is counted in the "N benchmark(s)
    // made no allocations" line instead).
    Benchmark("Noop") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(0)
        }
    }

    // Two call sites with different counts.
    //   Expected rows per iteration: siteB 5 (62.5 %), siteA 3 (37.5 %).
    //   Sum 8 == mallocCountTotal.
    Benchmark("Two sites: siteA x3 + siteB x5") { benchmark in
        for _ in benchmark.scaledIterations {
            siteA(3)
            siteB(5)
        }
    }

    // The same site reached through two different callers aggregates into
    // two rows because the full stack differs, not just the leaf.
    //   Expected rows per iteration: siteA via callerOne 2, siteA via
    //   callerTwo 4 (the leaf frame is identical, the folded lines differ).
    Benchmark("Same site, two callers: 2 + 4") { benchmark in
        @inline(never) func callerOne() { siteA(2) }
        @inline(never) func callerTwo() { siteA(4) }
        for _ in benchmark.scaledIterations {
            callerOne()
            callerTwo()
        }
    }

    // Setup before an explicit startMeasurement() is outside the window.
    //   Expected: siteA 2 per iteration only. setupSite must NOT appear,
    //   even though it allocates 1000 times per outer iteration.
    Benchmark("Explicit start excludes setup") { benchmark in
        setupSite(1_000)
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            siteA(2)
        }
        benchmark.stopMeasurement()
    }

    // One allocation per OUTER iteration, outside the scaled inner loop.
    // Per inner iteration that is 0.001, below the per-iteration
    // threshold, so it must print as a run total: "<iterations> /run".
    //   Expected rows: siteA 1 per iteration; oncePerOuterIterationSite
    //   N /run where N == the Samples column of the metric table.
    Benchmark("Once per outer iteration + siteA x1") { benchmark in
        oncePerOuterIterationSite()
        for _ in benchmark.scaledIterations {
            siteA(1)
        }
    }

    // 48 distinct stacks (one per recursion depth), one allocation each
    // per iteration. Checks the top-10 truncation in the console and that
    // the .folded file holds every stack. 48 keeps the deepest stack under
    // the 64-frame capture cap; beyond it the deepest stacks truncate to
    // identical frame sequences and merge.
    //   Expected: mallocCountTotal 48; table shows 10 rows of 1 (2.1 %)
    //   and the folded file has 48 lines, all with count 1.
    Benchmark("48 distinct stacks x1") { benchmark in
        for _ in benchmark.scaledIterations {
            for depth in 0..<48 {
                allocateAtDepth(depth)
            }
        }
    }

    // One allocation 100 frames deep. The capture keeps the 64 leaf-most
    // frames, so the folded line starts inside the recursion and never
    // reaches the benchmark closure: documented truncation, not a bug.
    //   Expected: 1 row, count 1; the folded line has 63 frames (64
    //   captured, minus the interposer's own frame which is stripped;
    //   count them with: tr ';' '\n' | wc -l).
    Benchmark("Deep recursion, 100 frames") { benchmark in
        for _ in benchmark.scaledIterations {
            allocateAtDepth(100)
        }
    }

    // Swift objects instead of raw malloc, to see DWARF inline expansion.
    //   Expected per iteration: Node.__allocating_init 8 (the 8 objects),
    //   plus 1 for the array buffer from reserveCapacity (shown under
    //   _ArrayBuffer._consumeAndCreateNew / _createNewBuffer). Sum 9.
    Benchmark("Swift objects: 8 nodes in a reserved array") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(makeNodes(8))
        }
    }

    // Array growth without reserveCapacity: every doubling reallocates,
    // so one append site produces about log2(N) allocations.
    //   Expected: 10 per iteration for 1000 appends, as two
    //   _ContiguousArrayBuffer.init rows: 9 for the doublings and 1 for the
    //   initial buffer (exact split depends on the stdlib's growth policy).
    Benchmark("Array growth: 1000 appends, no reserve") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(appendWithoutReserve(1_000))
        }
    }

    // Allocations made on other threads are captured too (the capture
    // table is process-global). Each of 4 child tasks runs siteA x4.
    //   Expected: siteA 16 per iteration under the task closure, plus the
    //   task-creation machinery (swift_task_create, TaskGroup.addTask, ...)
    //   at 4 per iteration each. No scaling factor here so the numbers are
    //   per outer iteration and the run stays short.
    Benchmark(
        "Concurrent: 4 tasks x siteA x4",
        configuration: .init(scalingFactor: .one, maxIterations: 50)
    ) { _ in
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                group.addTask { siteA(4) }
            }
            await group.waitForAll()
        }
    }
}
