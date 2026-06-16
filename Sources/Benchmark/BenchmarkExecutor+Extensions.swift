//
// Copyright (c) 2022 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//
// swiftlint:disable cyclomatic_complexity

extension BenchmarkExecutor {
    func performanceCountersNeeded(_ metric: BenchmarkMetric) -> Bool {
        switch metric {
        case .instructions:
            return true
        default:
            return false
        }
    }
}

extension BenchmarkExecutor {
    func mallocStatsProducerNeeded(_ metric: BenchmarkMetric) -> Bool {
        switch metric {
        case .memoryLeaked:
            return true
        case .memoryLeakedBytes:
            return true
        case .mallocCountTotal:
            return true
        case .mallocCountSmall:
            return true
        case .mallocCountLarge:
            return true
        case .mallocBytesCount:
            return true
        case .allocatedResidentMemory:
            return true
        case .freeCountTotal:
            return true
        default:
            return false
        }
    }
}

extension BenchmarkExecutor {
    /// Maps a measured window's interposer counter deltas to the `(metric, value)` pairs to record.
    ///
    /// Extracted as a pure function so the leak/scaling arithmetic can be unit-tested without a live
    /// interposer. `memoryLeaked` / `memoryLeakedBytes` are clamped to `0`: a net-negative window
    /// (more frees than mallocs — e.g. freeing a warmup survivor, or cross-thread frees) is not a
    /// leak, and clamping records a `0` sample rather than letting `Statistics.add` drop it, which
    /// would desync the column's sample count and bias the average upward.
    static func mallocStatistics(
        mallocCountDelta: Int,
        mallocBytesDelta: Int,
        mallocSmallDelta: Int,
        mallocLargeDelta: Int,
        freeCountDelta: Int,
        freeBytesDelta: Int
    ) -> [(metric: BenchmarkMetric, value: Int)] {
        [
            (.mallocCountTotal, mallocCountDelta),
            (.mallocBytesCount, mallocBytesDelta),
            (.mallocCountSmall, mallocSmallDelta),
            (.mallocCountLarge, mallocLargeDelta),
            (.freeCountTotal, freeCountDelta),
            (.memoryLeaked, max(0, mallocCountDelta - freeCountDelta)),
            (.memoryLeakedBytes, max(0, mallocBytesDelta - freeBytesDelta)),
        ]
    }
}

extension BenchmarkExecutor {
    func operatingSystemsStatsProducerNeeded(_ metric: BenchmarkMetric) -> Bool {
        switch metric {
        case .cpuUser:
            return true
        case .cpuSystem:
            return true
        case .cpuTotal:
            return true
        case .peakMemoryResident:
            return true
        case .peakMemoryResidentDelta:
            return true
        case .peakMemoryVirtual:
            return true
        case .syscalls:
            return true
        case .contextSwitches:
            return true
        case .threads:
            return true
        case .threadsRunning:
            return true
        case .readSyscalls:
            return true
        case .writeSyscalls:
            return true
        case .readBytesLogical:
            return true
        case .writeBytesLogical:
            return true
        case .readBytesPhysical:
            return true
        case .writeBytesPhysical:
            return true
        case .instructions:
            return true
        default:
            return false
        }
    }
}

extension BenchmarkExecutor {
    func arcStatsProducerNeeded(_ metric: BenchmarkMetric) -> Bool {
        switch metric {
        case .objectAllocCount, .retainCount, .releaseCount, .retainReleaseDelta:
            return true
        default:
            return false
        }
    }
}

// swiftlint:enable cyclomatic_complexity
