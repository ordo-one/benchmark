//
// Copyright (c) 2026 Ordo One AB
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Regression benchmarks for the malloc interposer. Each benchmark performs
// a known, fixed number of allocations per iteration so the reported
// per-iteration counts (mallocCountTotal / freeCountTotal / etc.) line up
// with the expected values noted in the benchmark name. Drift between the
// jemalloc and interposer code paths — or between branches — shows up
// immediately as a count mismatch.
//
// Counts are scaled per iteration: with .kilo scaling, one malloc inside
// the body produces "1" in the count column, not "1000".

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

let mallocMetrics: [BenchmarkMetric] = [
    .wallClock,
    .mallocCountSmall,
    .mallocCountLarge,
    .mallocCountTotal,
    .freeCountTotal,
    .mallocBytesCount,
    .mallocFreeDelta,
    .memoryLeakedBytes,
]

let benchmarks: @Sendable () -> Void = {
    Benchmark.defaultConfiguration = .init(
        metrics: mallocMetrics,
        warmupIterations: 1,
        scalingFactor: .kilo,
        maxDuration: .seconds(1),
        maxIterations: 100
    )

    // Sanity floor: an empty body should report (close to) zero allocations.
    // Whatever the framework's per-iteration overhead is, it shows up here
    // and is the reference for what "no allocations" looks like.
    Benchmark("Noop") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(0)
        }
    }

    // Bread-and-butter malloc/free pair, sub-page size — should land in
    // mallocCountSmall, not mallocCountLarge.
    //   Expected per iter: malloc=1 (small=1, large=0), free=1, leaked=0.
    Benchmark("Malloc 64B + free") { benchmark in
        for _ in benchmark.scaledIterations {
            let ptr = malloc(64)
            blackHole(ptr)
            free(ptr)
        }
    }

    // Larger-than-page allocation — should land in mallocCountLarge.
    //   Expected per iter: malloc=1 (small=0, large=1), free=1.
    Benchmark("Malloc 2 MiB + free") { benchmark in
        for _ in benchmark.scaledIterations {
            let ptr = malloc(2 * 1_024 * 1_024)
            blackHole(ptr)
            free(ptr)
        }
    }

    // calloc must be counted exactly like malloc + memset.
    //   Expected per iter: malloc=1, free=1.
    Benchmark("Calloc 8x8 + free") { benchmark in
        for _ in benchmark.scaledIterations {
            let ptr = calloc(8, 8)
            blackHole(ptr)
            free(ptr)
        }
    }

    // realloc(grow) on success: implicit free of old + alloc of new.
    //   Expected per iter: malloc=2, free=2.
    Benchmark("Realloc grow 64→256 + free") { benchmark in
        for _ in benchmark.scaledIterations {
            let original = malloc(64)
            let grown = realloc(original, 256)
            blackHole(grown)
            free(grown)
        }
    }

    // realloc(NULL, size) is a pure malloc — no implicit free.
    //   Expected per iter: malloc=1, free=1.
    Benchmark("Realloc(NULL, 128) + free") { benchmark in
        for _ in benchmark.scaledIterations {
            let ptr = realloc(nil, 128)
            blackHole(ptr)
            free(ptr)
        }
    }

    // realloc(p, 0) frees p and returns NULL — pure free, no second malloc.
    //   Expected per iter: malloc=1, free=1.
    Benchmark("Malloc + realloc(p, 0)") { benchmark in
        for _ in benchmark.scaledIterations {
            let ptr = malloc(64)
            let resized = realloc(ptr, 0)
            blackHole(resized) // expected nil
        }
    }

    // posix_memalign — separate code path that's easy to forget to count.
    //   Expected per iter: malloc=1, free=1.
    Benchmark("posix_memalign(64, 1024) + free") { benchmark in
        var ptr: UnsafeMutableRawPointer?
        for _ in benchmark.scaledIterations {
            _ = posix_memalign(&ptr, 64, 1_024)
            blackHole(ptr)
            free(ptr)
        }
    }

    // C11 aligned_alloc — currently only intercepted on Linux. On Darwin the
    // count drops because the symbol isn't in the DYLD_INTERPOSE list. Useful
    // signal for that gap.
    //   Expected per iter (Linux): malloc=1, free=1.
    //   Expected per iter (Darwin): malloc=0 (not interposed), free=1.
    #if !canImport(Darwin)
    Benchmark("aligned_alloc(64, 1024) + free") { benchmark in
        for _ in benchmark.scaledIterations {
            let ptr = aligned_alloc(64, 1_024)
            blackHole(ptr)
            free(ptr)
        }
    }
    #endif

    // Batched mallocs in a single iteration — verifies the counter scales
    // linearly and isn't accidentally collapsed/de-duplicated.
    //   Expected per iter: malloc=16, free=16.
    Benchmark("Malloc x16 + free x16") { benchmark in
        let count = 16
        let buf = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: count)
        defer { buf.deallocate() }
        buf.update(repeating: nil, count: count)

        for _ in benchmark.scaledIterations {
            for i in 0..<count {
                buf[i] = malloc(48)
            }
            for i in 0..<count {
                free(buf[i])
            }
        }
    }

    // Deliberate leak: malloc without free. Confirms mallocFreeDelta /
    // memoryLeakedBytes track unbalanced flow correctly.
    //   Expected per iter: malloc=1, free=0, leaked=1, leakedBytes≈128.
    // The accumulated leak across the run is bounded:
    //   <= maxIterations * scalingFactor * 128 = 100 * 1000 * 128 = ~12.5 MiB.
    Benchmark("Leak: malloc 128B (no free)") { benchmark in
        for _ in benchmark.scaledIterations {
            let ptr = malloc(128)
            blackHole(ptr)
        }
    }

    // Swift stdlib path: Array(repeating:count:) goes through swift_allocObject
    // which (on supported platforms) lowers to malloc. The exact count per
    // iter depends on stdlib internals, but it must be > 0 and stable
    // between runs.
    Benchmark("Swift Array<Int>(repeating:0, count:128)") { benchmark in
        for _ in benchmark.scaledIterations {
            var arr = [Int](repeating: 0, count: 128)
            arr.withUnsafeMutableBufferPointer { buf in
                blackHole(buf.baseAddress)
            }
        }
    }

    // Heap-allocated String (must exceed the small-string inline limit of
    // 15 bytes). Same caveat as Array — count is stdlib-dependent but must
    // be stable.
    Benchmark("Swift String (long, heap)") { benchmark in
        for _ in benchmark.scaledIterations {
            let str = String(repeating: "x", count: 256)
            blackHole(str)
        }
    }
}
