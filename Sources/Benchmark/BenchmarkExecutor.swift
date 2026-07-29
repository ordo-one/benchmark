//
// Copyright (c) 2022 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

#if canImport(MallocInterposerSwift)
import MallocInterposerSwift
#endif

#if canImport(OSLog)
import OSLog
#endif

// swiftlint:disable file_length

struct BenchmarkExecutor { // swiftlint:disable:this type_body_length
    init(quiet: Bool = false) {
        self.quiet = quiet
    }

    var quiet: Bool
    let operatingSystemStatsProducer = OperatingSystemStatsProducer()

    // swiftlint:disable cyclomatic_complexity function_body_length
    //
    // The measurement loop runs isolated to the benchmark's desired actor (passed in by the
    // caller from the closure's own `@isolated(any)` isolation).  For a `@MainActor` benchmark this
    // means the entire loop — and each `await benchmark.run()` below — executes on the main actor
    // with no per-iteration actor hop; for an unisolated benchmark `isolation` is `nil` and the loop
    // runs on the generic executor.
    func run(_ benchmark: Benchmark, isolation: isolated (any Actor)? = #isolation) async -> [BenchmarkResult] {
        var wallClockDuration: Duration = .zero
        #if canImport(MallocInterposerSwift)
        var startMallocStats = MallocInterposerSwift.Statistics()
        var stopMallocStats = MallocInterposerSwift.Statistics()
        #else
        var startMallocStats = MallocStats()
        var stopMallocStats = MallocStats()
        #endif
        var startOperatingSystemStats = OperatingSystemStats()
        var stopOperatingSystemStats = OperatingSystemStats()
        var startPerformanceCounters = PerformanceCounters()
        var stopPerformanceCounters = PerformanceCounters()
        var startARCStats = ARCStats()
        var stopARCStats = ARCStats()
        var startTime = BenchmarkClock.now
        var stopTime = BenchmarkClock.now

        // optionally run a few warmup iterations by default to clean out outliers due to cacheing etc.

        #if canImport(OSLog)
        let logHandler = OSLog(subsystem: "one.ordo.benchmark", category: .pointsOfInterest)
        let signPost = OSSignposter(logHandle: logHandler)
        let signpostID = OSSignpostID(log: logHandler)
        var warmupInterval: OSSignpostIntervalState?
        var explicitStartStopInterval: OSSignpostIntervalState?

        if benchmark.configuration.warmupIterations > 0 {
            warmupInterval = signPost.beginInterval("Benchmark", id: signpostID, "\(benchmark.name) warmup")
        }
        #endif

        for iterations in 0..<benchmark.configuration.warmupIterations {
            benchmark.currentIteration = iterations
            await benchmark.run()
        }

        #if canImport(OSLog)
        if let warmupInterval {
            signPost.endInterval("Benchmark", warmupInterval, "\(benchmark.configuration.warmupIterations)")
        }
        #endif

        var statistics: [Statistics] = .init(repeating: Statistics(), count: BenchmarkMetric.maxIndex + 1)
        var customStatistics: [BenchmarkMetric: Statistics] = [:]
        var performanceCountersRequested = false
        var operatingSystemStatsRequested = false
        var mallocStatsRequested = false
        var arcStatsRequested = false
        var operatingSystemMetricsRequested: Set<BenchmarkMetric> = []

        // Create metric statistics as needed
        benchmark.configuration.metrics.forEach { metric in
            switch metric {
            case .custom:
                customStatistics[metric] = Statistics(prefersLarger: metric.polarity == .prefersLarger)
            case .wallClock, .cpuUser, .cpuTotal, .cpuSystem:
                let units = Statistics.Units(benchmark.configuration.timeUnits)
                statistics[metric.index] = Statistics(units: units)
            default:
                if operatingSystemStatsProducer.metricSupported(metric) == true {
                    statistics[metric.index] = Statistics(prefersLarger: metric.polarity == .prefersLarger)
                }
            }

            if mallocStatsProducerNeeded(metric) {
                mallocStatsRequested = true
            }

            if operatingSystemsStatsProducerNeeded(metric), operatingSystemStatsProducer.metricSupported(metric) {
                operatingSystemMetricsRequested.insert(metric)
                operatingSystemStatsRequested = true
            }

            if arcStatsProducerNeeded(metric) {
                arcStatsRequested = true
            }

            if performanceCountersNeeded(metric) {
                performanceCountersRequested = true
            }
        }

        operatingSystemStatsProducer.configureMetrics(operatingSystemMetricsRequested)

        var iterations = 0
        let initialStartTime = BenchmarkClock.now

        // Calculate typical sys call check overhead and deduct that to get 'clean' stats for the actual benchmark
        var operatingSystemStatsOverhead = OperatingSystemStats()
        var baselinePeakMemoryResidentDelta = 0
        if operatingSystemStatsRequested {
            let statsOne = operatingSystemStatsProducer.makeOperatingSystemStats()
            let statsTwo = operatingSystemStatsProducer.makeOperatingSystemStats()

            operatingSystemStatsOverhead.syscalls = statsTwo.syscalls - statsOne.syscalls
            operatingSystemStatsOverhead.readSyscalls = statsTwo.readSyscalls - statsOne.readSyscalls
            operatingSystemStatsOverhead.readBytesLogical = statsTwo.readBytesLogical - statsOne.readBytesLogical
            operatingSystemStatsOverhead.readBytesPhysical = statsTwo.readBytesPhysical - statsOne.readBytesPhysical
        }

        var timingOverheadInInstructions: UInt64 = 0
        if performanceCountersRequested {
            let numberOfMeasurements: UInt64 = 5
            operatingSystemStatsProducer.enablePerformanceCounters()
            for _ in 0..<numberOfMeasurements {
                blackHole(BenchmarkClock.now)
                let statsOne = operatingSystemStatsProducer.makePerformanceCounters()
                blackHole(BenchmarkClock.now) // must be as close to last in closure as possible
                let statsTwo = operatingSystemStatsProducer.makePerformanceCounters()
                timingOverheadInInstructions += max((statsTwo.instructions - statsOne.instructions), 0)
            }
            timingOverheadInInstructions /= numberOfMeasurements
            operatingSystemStatsProducer.disablePerformanceCounters()
        }

        // Hook that is called before the actual benchmark closure run, so we can capture metrics here
        // NB this code may be called twice if the user calls startMeasurement() manually and should
        // then reset to a new starting state.
        // NB that the order is important, as we will get leaked
        // ARC measurements if initializing it before malloc etc.
        benchmark.measurementPreSynchronization = { explicitStartStop in
            #if canImport(OSLog)
            if explicitStartStop {
                explicitStartStopInterval = signPost.beginInterval(
                    "Benchmark",
                    id: signpostID,
                    "\(benchmark.name) startMeasurement()"
                )
            }
            #endif

            if mallocStatsRequested {
                #if canImport(MallocInterposerSwift)
                startMallocStats = MallocInterposerSwift.getStatistics()
                #else
                startMallocStats = MallocStatsProducer.makeMallocStats()
                #endif
            }

            if arcStatsRequested {
                startARCStats = ARCStatsProducer.makeARCStats()
            }

            if operatingSystemStatsRequested {
                startOperatingSystemStats = operatingSystemStatsProducer.makeOperatingSystemStats()
            }

            if performanceCountersRequested {
                operatingSystemStatsProducer.resetPerformanceCounters()
                startPerformanceCounters = operatingSystemStatsProducer.makePerformanceCounters()
            }

            startTime = BenchmarkClock.now // must be as close to last in closure as possible
        }

        // And corresponding hook for then the benchmark has finished and capture finishing metrics here
        // This closure will only be called once for a given run though.
        benchmark.measurementPostSynchronization = { _ in
            if performanceCountersRequested {
                stopPerformanceCounters = operatingSystemStatsProducer.makePerformanceCounters()
            }

            stopTime = BenchmarkClock.now // must be as close to first in closure as possible (perf events only before)

            if operatingSystemStatsRequested {
                stopOperatingSystemStats = operatingSystemStatsProducer.makeOperatingSystemStats()
            }

            if arcStatsRequested {
                stopARCStats = ARCStatsProducer.makeARCStats()
            }

            if mallocStatsRequested {
                #if canImport(MallocInterposerSwift)
                stopMallocStats = MallocInterposerSwift.getStatistics()
                #else
                stopMallocStats = MallocStatsProducer.makeMallocStats()
                #endif
            }

            #if canImport(OSLog)
            if let explicitStartStopInterval {
                signPost.endInterval("Benchmark", explicitStartStopInterval, "\(benchmark.name) stopMeasurement()")
            }
            #endif

            var delta = 0
            let runningTime: Duration = startTime.duration(to: stopTime)

            wallClockDuration = initialStartTime.duration(to: stopTime)

            statistics.withUnsafeMutableBufferPointer { statistics in
                if runningTime > .zero { // macOS sometimes gives us identical timestamps so let's skip those.
                    let nanoSeconds = runningTime.nanoseconds()
                    statistics[BenchmarkMetric.wallClock.index].add(Int(nanoSeconds))

                    // We should eventually move the computation of the throughput to the
                    // post processing instead
                    var roundedThroughput = Double(1_000_000_000) / Double(nanoSeconds)
                    roundedThroughput.round(.toNearestOrEven)

                    let throughput = Int(roundedThroughput)

                    if throughput > 0 {
                        statistics[BenchmarkMetric.throughput.index].add(throughput)
                    }
                } else {
                    //  fatalError("Zero running time \(self.startTime), \(self.stopTime), \(runningTime)")
                }

                if arcStatsRequested {
                    let objectAllocDelta = stopARCStats.objectAllocCount - startARCStats.objectAllocCount
                    statistics[BenchmarkMetric.objectAllocCount.index].add(Int(objectAllocDelta))

                    let retainDelta = stopARCStats.retainCount - startARCStats.retainCount - 1 // due to some ARC traffic in the path
                    statistics[BenchmarkMetric.retainCount.index].add(Int(retainDelta))

                    let releaseDelta = stopARCStats.releaseCount - startARCStats.releaseCount - 1 // due to some ARC traffic in the path
                    statistics[BenchmarkMetric.releaseCount.index].add(Int(releaseDelta))

                    statistics[BenchmarkMetric.retainReleaseDelta.index]
                        .add(Int(abs(objectAllocDelta + retainDelta - releaseDelta)))
                }

                if mallocStatsRequested {
                    #if canImport(MallocInterposerSwift)
                    // allocatedResidentMemory and the legacy memoryLeaked metric are intentionally
                    // not populated on the interposer path: the interposer cannot measure the
                    // allocator's resident set. Use mallocBytesCount / memoryLeakedBytes for
                    // requested-byte accounting, mallocFreeDelta for allocation-count delta, or
                    // peakMemoryResident for OS-sampled resident memory. The leak/scaling arithmetic
                    // lives in BenchmarkExecutor.mallocStatistics(...) so it can be unit-tested
                    // without a live interposer.
                    let mallocMetrics = BenchmarkExecutor.mallocStatistics(
                        mallocCountDelta: stopMallocStats.mallocCount - startMallocStats.mallocCount,
                        mallocBytesDelta: stopMallocStats.mallocBytesCount - startMallocStats.mallocBytesCount,
                        mallocSmallDelta: stopMallocStats.mallocSmallCount - startMallocStats.mallocSmallCount,
                        mallocLargeDelta: stopMallocStats.mallocLargeCount - startMallocStats.mallocLargeCount,
                        freeCountDelta: stopMallocStats.freeCount - startMallocStats.freeCount,
                        freeBytesDelta: stopMallocStats.freeBytesCount - startMallocStats.freeBytesCount
                    )
                    for (metric, value) in mallocMetrics {
                        statistics[metric.index].add(value)
                    }
                    #else
                    let mallocCountTotal = stopMallocStats.mallocCountTotal - startMallocStats.mallocCountTotal
                    statistics[BenchmarkMetric.mallocCountTotal.index].add(mallocCountTotal)

                    let allocatedResidentMemory = stopMallocStats.allocatedResidentMemory - startMallocStats.allocatedResidentMemory
                    statistics[BenchmarkMetric.allocatedResidentMemory.index].add(allocatedResidentMemory)

                    // jemalloc has no free counter, so memoryLeaked keeps the legacy resident-byte
                    // growth definition. The interposer backend uses mallocFreeDelta for
                    // malloc-minus-free count and memoryLeakedBytes for requested-byte delta.
                    statistics[BenchmarkMetric.memoryLeaked.index].add(max(0, allocatedResidentMemory))

                    let mallocSmallCount = stopMallocStats.mallocCountSmall - startMallocStats.mallocCountSmall
                    statistics[BenchmarkMetric.mallocCountSmall.index].add(mallocSmallCount)

                    let mallocLargeCount = stopMallocStats.mallocCountLarge - startMallocStats.mallocCountLarge
                    statistics[BenchmarkMetric.mallocCountLarge.index].add(mallocLargeCount)
                    #endif
                }

                if operatingSystemStatsRequested {
                    delta = stopOperatingSystemStats.cpuUser - startOperatingSystemStats.cpuUser
                    statistics[BenchmarkMetric.cpuUser.index].add(Int(delta))

                    delta = stopOperatingSystemStats.cpuSystem - startOperatingSystemStats.cpuSystem
                    statistics[BenchmarkMetric.cpuSystem.index].add(Int(delta))

                    delta = stopOperatingSystemStats.cpuTotal - startOperatingSystemStats.cpuTotal
                    statistics[BenchmarkMetric.cpuTotal.index].add(Int(delta))

                    delta = stopOperatingSystemStats.peakMemoryResident
                    statistics[BenchmarkMetric.peakMemoryResident.index].add(Int(delta))

                    delta = stopOperatingSystemStats.peakMemoryResident - baselinePeakMemoryResidentDelta
                    statistics[BenchmarkMetric.peakMemoryResidentDelta.index].add(Int(delta))

                    delta = stopOperatingSystemStats.peakMemoryVirtual
                    statistics[BenchmarkMetric.peakMemoryVirtual.index].add(Int(delta))

                    delta =
                        stopOperatingSystemStats.syscalls - startOperatingSystemStats.syscalls
                        - operatingSystemStatsOverhead.syscalls
                    statistics[BenchmarkMetric.syscalls.index].add(Int(max(0, delta)))

                    delta = stopOperatingSystemStats.contextSwitches - startOperatingSystemStats.contextSwitches
                    statistics[BenchmarkMetric.contextSwitches.index].add(Int(delta))

                    delta = stopOperatingSystemStats.threads
                    statistics[BenchmarkMetric.threads.index].add(Int(delta))

                    delta = stopOperatingSystemStats.threadsRunning
                    statistics[BenchmarkMetric.threadsRunning.index].add(Int(delta))

                    delta =
                        stopOperatingSystemStats.readSyscalls - startOperatingSystemStats.readSyscalls
                        - operatingSystemStatsOverhead.readSyscalls
                    statistics[BenchmarkMetric.readSyscalls.index].add(Int(max(0, delta)))

                    delta = stopOperatingSystemStats.writeSyscalls - startOperatingSystemStats.writeSyscalls
                    statistics[BenchmarkMetric.writeSyscalls.index].add(Int(delta))

                    delta =
                        stopOperatingSystemStats.readBytesLogical - startOperatingSystemStats.readBytesLogical
                        - operatingSystemStatsOverhead.readBytesLogical
                    statistics[BenchmarkMetric.readBytesLogical.index].add(Int(max(0, delta)))

                    delta = stopOperatingSystemStats.writeBytesLogical - startOperatingSystemStats.writeBytesLogical
                    statistics[BenchmarkMetric.writeBytesLogical.index].add(Int(delta))

                    delta =
                        stopOperatingSystemStats.readBytesPhysical - startOperatingSystemStats.readBytesPhysical
                        - operatingSystemStatsOverhead.readBytesPhysical
                    statistics[BenchmarkMetric.readBytesPhysical.index].add(Int(max(0, delta)))

                    delta = stopOperatingSystemStats.writeBytesPhysical - startOperatingSystemStats.writeBytesPhysical
                    statistics[BenchmarkMetric.writeBytesPhysical.index].add(Int(delta))
                }

                if performanceCountersRequested {
                    delta = Int(stopPerformanceCounters.instructions - startPerformanceCounters.instructions)
                    // remove overhead of startTime = BenchmarkClock.now, later we should measure dummy void benchmark
                    if delta > timingOverheadInInstructions {
                        delta -= Int(timingOverheadInInstructions)
                    }
                    if delta > 0 {
                        statistics[BenchmarkMetric.instructions.index].add(Int(delta))
                    }
                }
            }
        }

        benchmark.customMetricMeasurement = { metric, value in
            customStatistics[metric]?.add(value)
        }

        if arcStatsRequested {
            ARCStatsProducer.hook()
        }

        if mallocStatsRequested {
            #if canImport(MallocInterposerSwift)
            MallocInterposerSwift.hook()
            #endif
        }

        if benchmark.configuration.metrics.contains(.threads)
            || benchmark.configuration.metrics.contains(.threadsRunning)
            || benchmark.configuration.metrics.contains(.peakMemoryResident)
            || benchmark.configuration.metrics.contains(.peakMemoryResidentDelta)
            || benchmark.configuration.metrics.contains(.peakMemoryVirtual)
        {
            operatingSystemStatsProducer.startSampling(5_000) // ~5 ms

            if benchmark.configuration.metrics.contains(.peakMemoryResidentDelta) {
                baselinePeakMemoryResidentDelta =
                    operatingSystemStatsProducer.makeOperatingSystemStats().peakMemoryResident
            }
        }

        var progressBar: ProgressBar?

        if quiet == false {
            let progressString = "| \(benchmark.target):\(benchmark.name)"

            progressBar = ProgressBar(
                count: 100,
                configuration: [
                    ProgressPercent(),
                    ProgressBarLine(barLength: 60),
                    ProgressTimeEstimates(),
                    ProgressString(string: progressString),
                ]
            )
            if var progressBar {
                progressBar.setValue(0)
            }
        }

        var nextPercentageToUpdateProgressBar = 0

        #if canImport(OSLog)
        let benchmarkInterval = signPost.beginInterval("Benchmark", id: signpostID, "\(benchmark.name)")
        #endif

        if performanceCountersRequested {
            operatingSystemStatsProducer.enablePerformanceCounters()
        }

        // Run the benchmark at a minimum the desired iterations/runtime --
        while iterations <= benchmark.configuration.maxIterations
            || wallClockDuration <= benchmark.configuration.maxDuration
        {
            // and at a maximum the same...
            guard wallClockDuration < benchmark.configuration.maxDuration,
                iterations < benchmark.configuration.maxIterations
            else {
                break
            }

            if benchmark.failureReason != nil {
                return []
            }

            benchmark.currentIteration = iterations + benchmark.configuration.warmupIterations

            await benchmark.run()

            iterations += 1

            if iterations < 1_000 || iterations.isMultiple(of: 500) { // only update for low iteration count benchmarks, else 1/500
                if var progressBar {
                    let iterationsPercentage =
                        100.0 * Double(iterations) / Double(benchmark.configuration.maxIterations)

                    let timePercentage = 100.0 * (wallClockDuration / benchmark.configuration.maxDuration)

                    let maxPercentage = max(iterationsPercentage, timePercentage)

                    // Small optimization to not update every single percentage point
                    if Int(maxPercentage) > nextPercentageToUpdateProgressBar {
                        progressBar.setValue(Int(maxPercentage))
                        nextPercentageToUpdateProgressBar = Int(maxPercentage) + Int.random(in: 3...9)
                    }
                }
            }
        }

        if performanceCountersRequested {
            operatingSystemStatsProducer.disablePerformanceCounters()
        }

        if arcStatsRequested {
            ARCStatsProducer.unhook()
        }

        if mallocStatsRequested {
            #if canImport(MallocInterposerSwift)
            MallocInterposerSwift.unhook()
            #endif
        }

        #if canImport(OSLog)
        signPost.endInterval("Benchmark", benchmarkInterval, "\(iterations)")
        #endif

        if var progressBar {
            progressBar.setValue(100)
        }

        if benchmark.configuration.metrics.contains(.threads)
            || benchmark.configuration.metrics.contains(.threadsRunning)
            || benchmark.configuration.metrics.contains(.peakMemoryResident)
            || benchmark.configuration.metrics.contains(.peakMemoryResidentDelta)
            || benchmark.configuration.metrics.contains(.peakMemoryVirtual)
        {
            operatingSystemStatsProducer.stopSampling()
        }

        // construct metric result array
        var results: [BenchmarkResult] = []

        benchmark.configuration.metrics.forEach { metric in
            switch metric {
            case .custom:
                if let value = customStatistics[metric] {
                    if value.measurementCount > 0 {
                        var units = BenchmarkTimeUnits(value.timeUnits)

                        if let overriddenUnits = benchmark.configuration.units[metric] {
                            units = .init(overriddenUnits)
                        }

                        let result = BenchmarkResult(
                            metric: metric,
                            timeUnits: units,
                            scalingFactor: benchmark.configuration.scalingFactor,
                            warmupIterations: benchmark.configuration.warmupIterations,
                            thresholds: benchmark.configuration.thresholds?[metric],
                            tags: benchmark.configuration.tags,
                            statistics: value
                        )
                        results.append(result)
                    }
                }
            default:
                if operatingSystemsStatsProducerNeeded(metric) == false
                    || operatingSystemStatsProducer.metricSupported(metric)
                {
                    let value = statistics[metric.index]
                    if value.measurementCount > 0 {
                        var units = BenchmarkTimeUnits(value.timeUnits)

                        if let overriddenUnits = benchmark.configuration.units[metric] {
                            units = BenchmarkTimeUnits(overriddenUnits)
                        }

                        let result = BenchmarkResult(
                            metric: metric,
                            timeUnits: units,
                            scalingFactor: benchmark.configuration.scalingFactor,
                            warmupIterations: benchmark.configuration.warmupIterations,
                            thresholds: benchmark.configuration.thresholds?[metric],
                            tags: benchmark.configuration.tags,
                            statistics: value
                        )
                        results.append(result)
                    }
                }
            }
        }

        // sort on metric descriptions for now to get predicatable output on screen
        results.sort(by: { $0.metric.description > $1.metric.description })

        return results
    }
}

// swiftlint:enable cyclomatic_complexity function_body_length
