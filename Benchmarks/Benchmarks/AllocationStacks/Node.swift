//
// Copyright (c) 2026 Ordo One AB
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//

/// A class instance, so each allocation goes through `swift_allocObject`.
final class Node {
    var value: Int

    init(_ value: Int) {
        self.value = value
    }
}
