//
// Copyright (c) 2026 Ordo One AB
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0

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
