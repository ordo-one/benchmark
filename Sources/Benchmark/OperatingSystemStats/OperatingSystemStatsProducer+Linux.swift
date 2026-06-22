//
// Copyright (c) 2022 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

#if os(Linux)

import CLinuxOperatingSystemStats
import Dispatch
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
import SystemPackage

final class OperatingSystemStatsProducer {
    var nsPerSchedulerTick: Int
    var pageSize: Int

    let lock = NIOLock()
    let semaphore = DispatchSemaphore(value: 0)
    var peakThreads: Int = 0
    var peakThreadsRunning: Int = 0
    var peakMemoryResident: Int = 0
    var peakMemoryVirtual: Int = 0
    var sampleRate: Int = 10_000
    var runState: RunState = .running
    var metrics: Set<BenchmarkMetric>?

    enum RunState {
        case running
        case shuttingDown
        case done
    }

    init() {
        let schedulerTicksPerSecond = sysconf(Int32(_SC_CLK_TCK))

        nsPerSchedulerTick = 1_000_000_000 / schedulerTicksPerSecond
        pageSize = sysconf(Int32(_SC_PAGESIZE))
    }

    deinit {}

    // We should cache the open file(s) and just read from file offset 0 to reduce overhead
    func read(path: FilePath) -> String {
        var string = ""
        let maxReadBuffer = 8_192

        do {
            let fileDescriptor = try FileDescriptor.open(path, .readOnly, options: [], permissions: .ownerRead)
            do {
                try fileDescriptor.closeAfter {
                    do {
                        let fileData = try [UInt8](unsafeUninitializedCapacity: maxReadBuffer) { buf, count in
                            count = try fileDescriptor.read(into: UnsafeMutableRawBufferPointer(buf))
                            // Add null byte to end of read data as it's used as the cString initializer below.
                            buf.initializeElement(at: min(count, maxReadBuffer - 1), to: 0)
                            precondition(
                                count < maxReadBuffer,
                                "\(#function) read unexpectedly filled the buffer completely"
                            )
                        }

                        fileData.withUnsafeBufferPointer {
                            string = String(cString: $0.baseAddress!)
                        }
                    } catch {
                        print("Failed to open file for reading \(path)")
                    }
                }
            } catch {
                print("Failed to close fileDescriptor for \(path) after reading.")
            }
        } catch {
            if errno != ENOENT { // file not found is ok, e.g. when no baselines exist
                print("Failed to open file \(path), errno = [\(errno)]")
            }
        }

        return string
    }

    func readIOStats() -> ioStats {
        let stats = read(path: FilePath("/proc/self/io"))
        var ioStats: ioStats = .init()
        CLinuxIOStats(stats, &ioStats)
        return ioStats
    }

    func readProcessStats() -> processStats {
        let statsRead = read(path: FilePath("/proc/self/stat"))

        var stats: processStats = .init()
        CLinuxProcessStats(statsRead, &stats)
        stats.cpuUser *= nsPerSchedulerTick
        stats.cpuSystem *= nsPerSchedulerTick
        stats.cpuTotal *= nsPerSchedulerTick
        stats.peakMemoryResident *= pageSize

        return stats
    }

    func configureMetrics(_ metrics: Set<BenchmarkMetric>) {
        self.metrics = metrics
    }

    func makeOperatingSystemStats() -> OperatingSystemStats {
        guard let metrics else {
            return .init()
        }

        let ioStats = readIOStats()
        let processStats = readProcessStats()

        var threads = 0
        var threadsRunning = 0
        var peakResident = 0
        var peakVirtual = 0

        if metrics.contains(.threads) || metrics.contains(.threadsRunning) || metrics.contains(.peakMemoryResident)
            || metrics.contains(.peakMemoryResidentDelta) || metrics.contains(.peakMemoryVirtual)
        {
            lock.lock()
            threads = peakThreads
            threadsRunning = peakThreadsRunning
            peakResident = peakMemoryResident
            peakVirtual = peakMemoryVirtual
            lock.unlock()
        }

        return OperatingSystemStats(
            cpuUser: Int(processStats.cpuUser),
            cpuSystem: Int(processStats.cpuSystem),
            cpuTotal: Int(processStats.cpuTotal),
            peakMemoryResident: peakResident,
            peakMemoryVirtual: peakVirtual,
            syscalls: 0,
            contextSwitches: 0,
            threads: threads,
            threadsRunning: threadsRunning, // we can go dig in /proc/self/task/ later if want this
            readSyscalls: Int(ioStats.readSyscalls),
            writeSyscalls: Int(ioStats.writeSyscalls),
            readBytesLogical: Int(ioStats.readBytesLogical),
            writeBytesLogical: Int(ioStats.writeBytesLogical),
            readBytesPhysical: Int(ioStats.readBytesPhysical),
            writeBytesPhysical: Int(ioStats.writeBytesPhysical)
        )
    }

    func metricSupported(_ metric: BenchmarkMetric) -> Bool {
        switch metric {
        case .syscalls:
            return false
        case .contextSwitches:
            return false
        case .threadsRunning:
            return false
        default:
            return true
        }
    }

    func startSampling(_: Int = 10_000) { // sample rate in microseconds
        let sampleSemaphore = DispatchSemaphore(value: 0)

        DispatchQueue.global(qos: .userInitiated)
            .async {
                self.lock.lock()

                let rate = self.sampleRate
                self.peakThreads = 0
                self.peakMemoryResident = 0
                self.peakMemoryVirtual = 0
                self.runState = .running
                var firstEventSampled = false

                self.lock.unlock()

                while true {
                    let processStats = self.readProcessStats()

                    self.lock.lock()

                    if processStats.threads > self.peakThreads {
                        self.peakThreads = processStats.threads
                    }

                    if processStats.peakMemoryResident > self.peakMemoryResident {
                        self.peakMemoryResident = processStats.peakMemoryResident
                    }

                    if processStats.peakMemoryVirtual > self.peakMemoryVirtual {
                        self.peakMemoryVirtual = processStats.peakMemoryVirtual
                    }

                    if self.runState == .shuttingDown {
                        self.runState = .done
                        self.semaphore.signal()
                    }

                    let quit = self.runState

                    self.lock.unlock()

                    if firstEventSampled == false { // allow calling thread to continue when we have captured a sample
                        firstEventSampled = true
                        sampleSemaphore.signal()
                    }

                    if quit == .done {
                        return
                    }

                    usleep(UInt32.random(in: UInt32(Double(rate) * 0.9)...UInt32(Double(rate) * 1.1)))
                }
            }
        // We'll need to wait for a single sample from the so we don't get 0 samples
        sampleSemaphore.wait()
    }

    func stopSampling() {
        lock.lock()
        runState = .shuttingDown
        lock.unlock()

        semaphore.wait()
    }

    func enablePerformanceCounters() {
        CLinuxPerformanceCountersEnable()
    }

    func disablePerformanceCounters() {
        CLinuxPerformanceCountersDisable()
    }

    func resetPerformanceCounters() {
        CLinuxPerformanceCountersReset()
    }

    func makePerformanceCounters() -> PerformanceCounters {
        var performanceCounters: performanceCounters = .init()
        CLinuxPerformanceCountersCurrent(&performanceCounters)
        return .init(instructions: performanceCounters.instructions)
    }
}
#endif
