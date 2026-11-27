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
import Synchronization

/// `@unchecked Sendable`: what the sampling thread shares with the benchmark thread is in
/// `sampling`, behind a `Mutex`. The other properties are set before sampling starts and only
/// used by the benchmark thread.
final class OperatingSystemStatsProducer: @unchecked Sendable {
    var nsPerSchedulerTick: Int
    var pageSize: Int

    let semaphore = DispatchSemaphore(value: 0)
    /// Written by the sampling thread, read by the benchmark thread.
    let sampling = Mutex(SamplingState())
    var metrics: Set<BenchmarkMetric>?

    enum RunState {
        case running
        case shuttingDown
        case done
    }

    struct SamplingState {
        var peakThreads: Int = 0
        var peakThreadsRunning: Int = 0
        var peakMemoryResident: Int = 0
        var peakMemoryVirtual: Int = 0
        var sampleRate: Int = 10_000
        var runState: RunState = .running
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
            let state = sampling.withLock { $0 }
            threads = state.peakThreads
            threadsRunning = state.peakThreadsRunning
            peakResident = state.peakMemoryResident
            peakVirtual = state.peakMemoryVirtual
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
                let rate = self.sampling.withLock { state in
                    state.peakThreads = 0
                    state.peakMemoryResident = 0
                    state.peakMemoryVirtual = 0
                    state.runState = .running
                    return state.sampleRate
                }
                var firstEventSampled = false

                while true {
                    let processStats = self.readProcessStats()

                    let quit = self.sampling.withLock { state in
                        if processStats.threads > state.peakThreads {
                            state.peakThreads = processStats.threads
                        }

                        if processStats.peakMemoryResident > state.peakMemoryResident {
                            state.peakMemoryResident = processStats.peakMemoryResident
                        }

                        if processStats.peakMemoryVirtual > state.peakMemoryVirtual {
                            state.peakMemoryVirtual = processStats.peakMemoryVirtual
                        }

                        if state.runState == .shuttingDown {
                            state.runState = .done
                            self.semaphore.signal()
                        }

                        return state.runState
                    }

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
        sampling.withLock { state in
            state.runState = .shuttingDown
        }

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
