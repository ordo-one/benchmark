//
// Copyright (c) 2026 Ordo One AB
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0

import Benchmark

@inline(never)
func allocateTwice() {
    // One allocation site, so both allocations share a stack.
    for value in 0..<2 {
        blackHole(Node(value))
    }
}

@inline(never)
func allocateOnce() {
    blackHole(Node(3))
}

@inline(never)
func allocateAfterSuspension() async {
    await Task.yield()
    blackHole(Node(4))
}

@inline(never)
func asyncCaller() async {
    await allocateAfterSuspension()
}

let benchmarks: @Sendable () -> Void = {
    Benchmark.defaultConfiguration = .init(
        metrics: [.mallocCountTotal],
        warmupIterations: 1,
        maxDuration: .seconds(1),
        maxIterations: 100
    )

    Benchmark("Two to one") { _ in
        allocateTwice()
        allocateOnce()
    }

    Benchmark("Async") { _ in
        await asyncCaller()
    }
}
