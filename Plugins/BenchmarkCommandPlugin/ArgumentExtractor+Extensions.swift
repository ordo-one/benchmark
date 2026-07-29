//
// Copyright (c) 2023 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

#if swift(>=6.0)
import Foundation
#endif
import PackagePlugin

enum ArgumentParsingError: Error, CustomStringConvertible {
    case noMatchingTargetsForRegex

    var description: String {
        "no target matching regex for target/skip-target"
    }

    var errorDescription: String? {
        description
    }
}

@available(macOS 13.0, *)
extension ArgumentExtractor {
    mutating func extractSpecifiedTargets(
        in package: Package,
        withOption option: String
    ) throws -> [SwiftSourceModuleTarget] {
        let specifiedTargets = extractOption(named: option)
        var targets: [SwiftSourceModuleTarget] = []
        var anyMatching = false

        try package.targets.forEach { target in
            #if swift(>=6.0)
            let isBenchmarkTarget = target.directoryURL.deletingLastPathComponent().lastPathComponent == "Benchmarks"
            #else
            let isBenchmarkTarget = target.directory.removingLastComponent().lastComponent == "Benchmarks"
            #endif
            if isBenchmarkTarget {
                for specifiedTarget in specifiedTargets {
                    let regex = try Regex(specifiedTarget)

                    if target.name.wholeMatch(of: regex) != nil {
                        if let swiftSourceModuleTarget = target as? SwiftSourceModuleTarget {
                            if swiftSourceModuleTarget.kind != .test {
                                targets.append(swiftSourceModuleTarget)
                                anyMatching = true
                                break
                            }
                        }
                    }
                }
            }
        }

        if !specifiedTargets.isEmpty, !anyMatching {
            throw ArgumentParsingError.noMatchingTargetsForRegex
        }

        return targets
    }
}
