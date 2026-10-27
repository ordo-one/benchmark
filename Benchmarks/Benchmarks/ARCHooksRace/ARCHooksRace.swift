//
// Copyright (c) 2026 Ordo One AB
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0

// Reproducer for the ARC hook teardown race: a thread that keeps releasing
// objects while the benchmark removes the retain/release hooks after the
// measurement. A thread already inside `_swift_release_hook` then calls the
// cleared `orig` pointer and the process dies with SIGSEGV at address 0.

import Benchmark
import Foundation
import Synchronization

final class Box {}

@inline(never)
func makeBox() -> Box {
    Box()
}

@inline(never)
func drop(_ box: Box) {
    withExtendedLifetime(box) {}
}

/// A thread that allocates and releases an object on every pass of its loop,
/// started in `setup` and stopped in `teardown`, so it is still running when
/// the hooks are removed.
final class Spinner: @unchecked Sendable {
    private let stop = Atomic<Bool>(false)
    private var thread: Thread?

    func start() {
        stop.store(false, ordering: .relaxed)
        let thread = Thread { [self] in
            while !stop.load(ordering: .relaxed) {
                drop(makeBox())
            }
        }
        thread.start()
        self.thread = thread
    }

    func finish() {
        stop.store(true, ordering: .relaxed)
    }
}

let benchmarks: @Sendable () -> Void = {
    let spinner = Spinner()

    Benchmark(
        "ARC hooks with a busy thread",
        configuration: .init(
            metrics: [.wallClock] + .arc,
            maxDuration: .milliseconds(200),
            setup: { spinner.start() },
            teardown: { spinner.finish() }
        )
    ) { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(1)
        }
    }
}
