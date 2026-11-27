//
// Copyright (c) 2022 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

#if canImport(Darwin)

import CDarwinOperatingSystemStats
import Darwin
import Dispatch
import Synchronization

/// `@unchecked Sendable`: what the sampling thread shares with the benchmark thread is in
/// `sampling`, behind a `Mutex`. The other properties are set before sampling starts and only
/// used by the benchmark thread.
final class OperatingSystemStatsProducer: @unchecked Sendable {
    var nsPerMachTick: Double
    var nsPerSchedulerTick: Int

    let semaphore = DispatchSemaphore(value: 0)
    /// Written by the sampling thread, read by the benchmark thread.
    let sampling = Mutex(SamplingState())
    var metrics: Set<BenchmarkMetric>?
    var pid = getpid()

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
        var runState: RunState = .running
        var sampleRate: Int = 10_000
    }

    internal
        final class CallbackDataCarrier<T>
    {
        init(_ data: T) {
            self.data = data
        }

        var data: T
    }

    init() {
        var info = mach_timebase_info_data_t()

        mach_timebase_info(&info)

        nsPerMachTick = Double(info.numer) / Double(info.denom)

        let schedulerTicksPerSecond = sysconf(_SC_CLK_TCK)

        nsPerSchedulerTick = 1_000_000_000 / schedulerTicksPerSecond
    }

    #if os(macOS)
    fileprivate
        func getProcInfo() -> proc_taskinfo
    {
        var procTaskInfo = proc_taskinfo()
        let procTaskInfoSize = MemoryLayout<proc_taskinfo>.size

        let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &procTaskInfo, Int32(procTaskInfoSize))

        if result != procTaskInfoSize {
            fatalError("proc_pidinfo returned an error \(errno)")
        }
        return procTaskInfo
    }

    struct IOStats {
        var bytesRead: UInt64 = 0
        var bytesWritten: UInt64 = 0
    }

    private func getRusage() -> rusage_info_current {
        var usage = rusage_info_current()

        let result = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0)
            }
        }

        if result != 0 {
            print("proc_pid_rusage returned an error \(errno)")
        }

        return usage
    }
    #endif

    func startSampling(_: Int = 10_000) { // sample rate in microseconds
        #if os(macOS)
        let sampleSemaphore = DispatchSemaphore(value: 0)

        DispatchQueue.global(qos: .userInitiated)
            .async {
                let rate = self.sampling.withLock { state in
                    state.peakThreads = 0
                    state.peakThreadsRunning = 0
                    state.peakMemoryResident = 0
                    state.peakMemoryVirtual = 0
                    state.runState = .running
                    return state.sampleRate
                }
                var firstEventSampled = false

                while true {
                    let procTaskInfo = self.getProcInfo()

                    let quit = self.sampling.withLock { state in
                        if procTaskInfo.pti_threadnum > state.peakThreads {
                            state.peakThreads = Int(procTaskInfo.pti_threadnum)
                        }

                        if procTaskInfo.pti_numrunning > state.peakThreadsRunning {
                            state.peakThreadsRunning = Int(procTaskInfo.pti_numrunning)
                        }

                        if procTaskInfo.pti_resident_size > state.peakMemoryResident {
                            state.peakMemoryResident = Int(procTaskInfo.pti_resident_size)
                        }

                        if procTaskInfo.pti_virtual_size > state.peakMemoryVirtual {
                            state.peakMemoryVirtual = Int(procTaskInfo.pti_virtual_size)
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
        #endif
    }

    func stopSampling() {
        #if os(macOS)
        sampling.withLock { state in
            state.runState = .shuttingDown
        }
        semaphore.wait()
        #endif
    }

    func configureMetrics(_ metrics: Set<BenchmarkMetric>) {
        self.metrics = metrics
    }

    func makeOperatingSystemStats() -> OperatingSystemStats {
        #if os(macOS)
        guard let metrics else {
            return .init()
        }

        let procTaskInfo = getProcInfo()
        let userTime = Int(nsPerMachTick * Double(procTaskInfo.pti_total_user))
        let systemTime = Int(nsPerMachTick * Double(procTaskInfo.pti_total_system))
        let totalTime = userTime + systemTime
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

        var usage = rusage_info_current()

        if metrics.contains(.writeBytesPhysical) || metrics.contains(.writeBytesPhysical)
            || metrics.contains(.writeSyscalls) || metrics.contains(.instructions)
        {
            usage = getRusage()
        }

        let stats = OperatingSystemStats(
            cpuUser: userTime,
            cpuSystem: systemTime,
            cpuTotal: totalTime,
            peakMemoryResident: peakResident,
            peakMemoryVirtual: peakVirtual,
            syscalls: Int(procTaskInfo.pti_syscalls_unix) + Int(procTaskInfo.pti_syscalls_mach),
            contextSwitches: Int(procTaskInfo.pti_csw),
            threads: threads,
            threadsRunning: threadsRunning,
            readSyscalls: 0,
            writeSyscalls: Int(usage.ri_logical_writes),
            readBytesLogical: 0,
            writeBytesLogical: 0,
            readBytesPhysical: Int(usage.ri_diskio_bytesread),
            writeBytesPhysical: Int(usage.ri_diskio_byteswritten)
        )

        return stats
        #else
        return .init()
        #endif
    }

    func metricSupported(_ metric: BenchmarkMetric) -> Bool {
        #if canImport(Darwin)
        switch metric {
        case .readSyscalls:
            return false
        case .writeBytesLogical:
            return false
        case .readBytesLogical:
            return false
        default:
            return true
        }
        #else
        // No metrics supported due to lack of libproc.h
        return false
        #endif
    }

    func enablePerformanceCounters() {
    }

    func disablePerformanceCounters() {
    }

    func resetPerformanceCounters() {
    }

    func makePerformanceCounters() -> PerformanceCounters {
        #if os(macOS)
        let performanceCounters = getRusage()
        return .init(instructions: performanceCounters.ri_instructions)
        #else
        return .init()
        #endif
    }
}

#endif
