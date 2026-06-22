//
// Copyright (c) 2022 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

import XCTest

@testable import Benchmark

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#else
#error("Unsupported Platform")
#endif

final class OperatingSystemAndMallocTests: XCTestCase {
    func testOperatingSystemStatsProducer() throws {
        let operatingSystemStatsProducer = OperatingSystemStatsProducer()
        operatingSystemStatsProducer.startSampling(1)
        let startOperatingSystemStats = operatingSystemStatsProducer.makeOperatingSystemStats()
        for outerloop in 0..<100 {
            for innerloop in 0..<10 {
                blackHole(outerloop * outerloop * outerloop * innerloop * innerloop)
                usleep(1)
                blackHole(malloc(1))
            }
        }
        let stopOperatingSystemStats = operatingSystemStatsProducer.makeOperatingSystemStats()
        operatingSystemStatsProducer.stopSampling()
        XCTAssertGreaterThanOrEqual(stopOperatingSystemStats.cpuTotal, startOperatingSystemStats.cpuTotal)
        XCTAssertGreaterThanOrEqual(stopOperatingSystemStats.cpuUser, startOperatingSystemStats.cpuUser)
        XCTAssertGreaterThanOrEqual(stopOperatingSystemStats.cpuSystem, startOperatingSystemStats.cpuSystem)
        XCTAssertGreaterThanOrEqual(
            stopOperatingSystemStats.peakMemoryResident,
            startOperatingSystemStats.peakMemoryResident
        )
        XCTAssertGreaterThanOrEqual(
            stopOperatingSystemStats.peakMemoryVirtual,
            startOperatingSystemStats.peakMemoryVirtual
        )
    }

    func testOperatingSystemStatsProducerMetricSupported() throws {
        let operatingSystemStatsProducer = OperatingSystemStatsProducer()
        blackHole(operatingSystemStatsProducer.metricSupported(.throughput))
        blackHole(operatingSystemStatsProducer.metricSupported(.syscalls))
        blackHole(operatingSystemStatsProducer.metricSupported(.threadsRunning))
        blackHole(operatingSystemStatsProducer.metricSupported(.threads))
        blackHole(operatingSystemStatsProducer.metricSupported(.writeSyscalls))
        blackHole(operatingSystemStatsProducer.metricSupported(.writeBytesLogical))
        blackHole(operatingSystemStatsProducer.metricSupported(.writeBytesPhysical))
        blackHole(operatingSystemStatsProducer.metricSupported(.instructions))
        blackHole(operatingSystemStatsProducer.metricSupported(.throughput))
    }

    #if canImport(jemalloc)
    func testMallocProducerLeaks() throws {
        let startMallocStats = MallocStatsProducer.makeMallocStats()

        for outerloop in 1...100 {
            blackHole(malloc(outerloop * 1_024))
        }

        let stopMallocStats = MallocStatsProducer.makeMallocStats()

        XCTAssertGreaterThanOrEqual(stopMallocStats.mallocCountTotal - startMallocStats.mallocCountTotal, 100)
        XCTAssertGreaterThanOrEqual(
            stopMallocStats.allocatedResidentMemory - startMallocStats.allocatedResidentMemory,
            100 * 1_024
        )
    }
    #endif

    func testARCStatsProducer() throws {
        let array = [3]
        ARCStatsProducer.hook()

        let startStats = ARCStatsProducer.makeARCStats()

        for outerloop in 1...100 {
            var arrayCopy = array
            arrayCopy.append(outerloop)
            blackHole(array)
            blackHole(arrayCopy)
        }

        let stopStats = ARCStatsProducer.makeARCStats()

        ARCStatsProducer.unhook()

        let allocDelta = stopStats.objectAllocCount - startStats.objectAllocCount
        let releaseDelta = stopStats.releaseCount - startStats.releaseCount

        if ARCStatsProducer.usesPreloadedInterposer, allocDelta == 0, releaseDelta == 0 {
            throw XCTSkip("ARC interposer is inactive in the in-process test harness without loader injection")
        }

        XCTAssertGreaterThanOrEqual(allocDelta, 100)
        XCTAssertGreaterThanOrEqual(releaseDelta, 100)
    }

    func testIOStatProducer() throws {
        let statsProducer = OperatingSystemStatsProducer()

        XCTAssertTrue(statsProducer.metricSupported(.readBytesPhysical))
        XCTAssertTrue(statsProducer.metricSupported(.writeBytesPhysical))
        XCTAssertTrue(statsProducer.metricSupported(.writeSyscalls))

        statsProducer.configureMetrics([.readBytesPhysical, .writeBytesPhysical, .writeSyscalls])

        let startStats = statsProducer.makeOperatingSystemStats()

        let amplificationFactor = 1_000

        let tempFile = tmpfile()
        guard let tempFile else {
            XCTFail("tmpfile() failed: \(errno)")
            return
        }

        let fildes = fileno(tempFile)

        var stat = stat()
        XCTAssertEqual(fstat(fildes, &stat), 0, "fstat() failed: \(errno)")

        var buffer = (0..<stat.st_blksize).map { _ in UInt8.random(in: 0...UInt8.max) }

        for _ in 0..<amplificationFactor {
            buffer.withUnsafeBytes { buffer in
                XCTAssertEqual(
                    write(fildes, buffer.baseAddress, buffer.count),
                    buffer.count,
                    "write() failed: \(errno)"
                )
            }
            XCTAssertEqual(lseek(fildes, 0, SEEK_SET), 0, "lseek() failed: \(errno)")
        }

        // check pwrite()
        buffer.withUnsafeBytes { buffer in
            XCTAssertEqual(pwrite(fildes, buffer.baseAddress, buffer.count, off_t(buffer.count)), buffer.count)
        }

        // and pwritev()
        buffer.withUnsafeMutableBytes { buffer in
            let block = iovec(iov_base: buffer.baseAddress, iov_len: buffer.count)

            [block]
                .withUnsafeBufferPointer { iov in
                    XCTAssertEqual(
                        pwritev(fildes, iov.baseAddress, Int32(iov.count), off_t(buffer.count * 2)),
                        buffer.count
                    )
                }
        }

        XCTAssertEqual(fflush(tempFile), 0, "fflush() failed: \(errno)")
        XCTAssertEqual(fclose(tempFile), 0, "fclose() failed: \(errno)")

        let stopStats = statsProducer.makeOperatingSystemStats()

        let writes = stopStats.writeBytesPhysical - startStats.writeBytesPhysical
        let writeCalls = stopStats.writeSyscalls - startStats.writeSyscalls

        XCTAssertTrue(writeCalls > 100)
        XCTAssertEqual(writes, buffer.count * 3)
    }
}
