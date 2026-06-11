//
// Copyright (c) 2023 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

import Benchmark
import Foundation
import SystemPackage

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#else
#error("Unsupported Platform")
#endif

extension BenchmarkTool {
    /// `makeBenchmarkThresholds` is a convenience function for reading p90 static thresholds that previously have been exported with `metricP90AbsoluteThresholds`
    ///
    /// - Parameters:
    ///   - path: The path where the `Thresholds` directory should be located, containing static thresholds files using the naming pattern:
    ///   `moduleName.benchmarkName.p90.json`
    ///   - moduleName: The name of the benchmark module, can be extracted in the benchmark using:
    ///   `String("\(#fileID)".prefix(while: { $0 != "/" }))`
    ///   - benchmarkName: The name of the benchmark
    /// - Returns: A dictionary with static benchmark thresholds per metric or nil if the file could not be found or read
    static func makeBenchmarkThresholds(
        path: String,
        benchmarkIdentifier: BenchmarkIdentifier
    ) -> [BenchmarkMetric: BenchmarkThreshold]? {
        var path = FilePath(path)
        if path.isAbsolute {
            path.append("\(benchmarkIdentifier.target).\(benchmarkIdentifier.name).p90.json")
        } else {
            var cwdPath = FilePath(FileManager.default.currentDirectoryPath)
            cwdPath.append(path.components)
            cwdPath.append("\(benchmarkIdentifier.target).\(benchmarkIdentifier.name).p90.json")
            path = cwdPath
        }

        var p90Thresholds: [BenchmarkMetric: BenchmarkThreshold] = [:]

        do {
            let fileDescriptor = try FileDescriptor.open(path, .readOnly, options: [], permissions: .ownerRead)

            do {
                try fileDescriptor.closeAfter {
                    do {
                        var readBytes = [UInt8]()
                        let bufferSize = 16 * 1_024 * 1_024

                        while true {
                            let nextBytes = try [UInt8](unsafeUninitializedCapacity: bufferSize) { buf, count in
                                count = try fileDescriptor.read(into: UnsafeMutableRawBufferPointer(buf))
                            }
                            if nextBytes.isEmpty {
                                break
                            }
                            readBytes.append(contentsOf: nextBytes)
                        }

                        p90Thresholds = try JSONDecoder()
                            .decode(
                                [BenchmarkMetric: BenchmarkThreshold].self,
                                from: Data(readBytes)
                            )
                    } catch {
                        print(
                            "Failed to read file at \(path) [\(String(reflecting: error))] \(Errno(rawValue: errno).description)"
                        )
                    }
                }
            } catch {
                print("Failed to close fd for \(path) after reading.")
            }
        } catch {
            if errno != ENOENT { // file not found is ok, e.g. no thresholds found, then silently return nil
                print("Failed to open file \(path), errno = [\(errno)] \(Errno(rawValue: errno).description)")
            }
        }
        return p90Thresholds.isEmpty ? nil : p90Thresholds
    }
}
