//
// Copyright (c) 2023 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

import Foundation
import XCTest

@testable import Benchmark

final class AdditionalTests: XCTestCase {
    // Disabled for now as it breaks when run on the public CI
    /*
    func testBlackhole() throws { // due to https://github.com/ordo-one/benchmark/issues/178
        func runWork(_ testIterations: Int) -> ContinuousClock.Duration {
            let clock = ContinuousClock()
            return clock.measure {
                for idx in 1 ... testIterations {
                    Benchmark.blackHole(idx)
                }
            }
        }

        var results: [ContinuousClock.Duration] = []
        var testIterations = 100_000
        for _ in 0 ..< 3 {
            results.append(runWork(testIterations))
            testIterations *= 10
        }

        var comparisonValue = 0
        results.forEach { result in
            let microseconds = result.components.seconds * 1_000_000 + result.components.attoseconds / 1_000_000_000_000
            let logValue = log10(Double(microseconds)).rounded()

            XCTAssertFalse(logValue.isNaN, "blackHole seems broken, runtime is too fast")
            XCTAssertFalse(logValue.isInfinite, "blackHole seems broken, runtime is too fast")

            let newValue = Int(logValue)
            XCTAssert(newValue > comparisonValue, "blackHole should take 10x longer for each iteration")
            comparisonValue = newValue
//            print("result \(result), microseconds = \(microseconds), log = \(newValue)")
        }
    }
     */
}
