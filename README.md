[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fordo-one%2Fpackage-benchmark%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/ordo-one/package-benchmark)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fordo-one%2Fpackage-benchmark%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/ordo-one/package-benchmark)
[![codecov](https://codecov.io/gh/ordo-one/package-benchmark/branch/main/graph/badge.svg?token=hXHmhEG1iF)](https://codecov.io/gh/ordo-one/package-benchmark)<br>
[![Swift address sanitizer](https://github.com/ordo-one/package-benchmark/actions/workflows/swift-sanitizer-address.yml/badge.svg)](https://github.com/ordo-one/package-benchmark/actions/workflows/swift-sanitizer-address.yml)
[![Swift thread sanitizer](https://github.com/ordo-one/package-benchmark/actions/workflows/swift-sanitizer-thread.yml/badge.svg)](https://github.com/ordo-one/package-benchmark/actions/workflows/swift-sanitizer-thread.yml)
[![Swift Linux build](https://github.com/ordo-one/package-benchmark/actions/workflows/swift-linux-build.yml/badge.svg)](https://github.com/ordo-one/package-benchmark/actions/workflows/swift-linux-build.yml)
[![Swift macOS build](https://github.com/ordo-one/package-benchmark/actions/workflows/swift-macos-build.yml/badge.svg)](https://github.com/ordo-one/package-benchmark/actions/workflows/swift-macos-build.yml)

# Benchmark 

The Benchmark package allows you to easily create sophisticated Swift performance benchmarks for a wide variety of metrics.

This README provides a quick overview of the Benchmark package. For more detailed information, please [see the documentation](https://swiftpackageindex.com/ordo-one/package-benchmark/documentation/benchmark).

## Overview

Performance is a key feature for many apps and frameworks. Benchmark helps make it easy to measure and track [many different metrics](https://swiftpackageindex.com/ordo-one/package-benchmark/documentation/benchmark/metrics) that affects performance, such as CPU usage, ARC traffic, memory/malloc usage and use of operating system resources such as threads and system calls, as well as completely custom metric counters.

Benchmark works on both macOS and Linux and supports several key workflows for performance measurements:

* **[Automated Pull Request performance regression checks](https://swiftpackageindex.com/ordo-one/package-benchmark/documentation/benchmark/comparingbenchmarksci)** by comparing the performance metrics of a pull request with the main branch and having the PR workflow check fail if there is a regression according to absolute or relative threshold tolerances specified per benchmark
* **[Manual comparison of multiple performance baselines](https://swiftpackageindex.com/ordo-one/package-benchmark/documentation/benchmark/creatingandcomparingbaselines)** for iterative or A/B performance work by an individual developer
* **[Export of benchmark results in several formats](https://swiftpackageindex.com/ordo-one/package-benchmark/documentation/benchmark/exportingbenchmarks)** for analysis or visualization

Benchmark provides a quick way for measuring and validating of performance metrics, while other more specialized tools such as Instruments, DTrace, Heaptrack, Leaks, Sample and more can be used for attributing performance problems or for finding root causes for any deviations found.

Benchmark is suitable for both smaller ad-hoc benchmarks focusing on execution time and more extensive benchmarks that care about several additional metrics such as memory allocations, syscalls, thread usage, context switches, ARC traffic, and more. Using [Histogram](https://github.com/ordo-one/package-histogram) it’s especially suitable for capturing latency statistics for large number of samples.

## Documentation

Documentation on how to use Benchmark in your Swift package can be [viewed online](https://swiftpackageindex.com/ordo-one/package-benchmark/documentation/benchmark) or inside Xcode using `Build Documentation`. 

Additionally the command plugin provides help information if you run `swift package benchmark help` from the command line.

## Adding dependencies and getting started

There are just a few steps required to get started benchmarking:
1. Add a dependency to the Benchmark project
2. Add benchmark executable targets with `swift package benchmark init`
3. Add the snippet or code you want to benchmark
4. Run `swift package benchmark`

The steps in some detail:
### Step 1: Add a package dependency to Package.swift
To add the dependency on Benchmark, add the dependency to your package:
```swift
.package(url: "https://github.com/ordo-one/package-benchmark", .upToNextMajor(from: "1.4.0")),
```

### Step 2: Add benchmark exectuable targets using `benchmark init`
The absolutely easiest way to add new benchmark executable targets to your project is by using:
```bash
swift package --allow-writing-to-package-directory benchmark init MyNewBenchmarkTarget
```

This will perform the following steps for you:
* Create a Benchmarks/MyNewBenchmarkTarget directory
* Create a Benchmarks/MyNewBenchmarkTarget/MyNewBenchmarkTarget.swift benchmark target with the required boilerplate
* Add a new executable target for the benchmark to the end of your Package.swift file

The init command validates that the name you specify isn’t used by any existing target and will not overwrite any existing file with that name in the Benchmarks/ location. 

After you’ve created the new target, you can directly run it with e.g.:
```bash
swift package benchmark --target MyNewBenchmarkTarget
```

### Step 2 (optional approach): Add benchmark exectuable targets manually
Alternatively if you don't want the plugin to modify your project directory, you can do the same steps manually:
Create an executable target in Package.swift for each benchmark suite you want to measure.
The source for all benchmarks must reside in a directory named `Benchmarks` in the root of your swift package.
The benchmark plugin uses this directory combined with the executable target information to automatically discover and run your benchmarks.
For each executable target, include dependencies on both `Benchmark` (supporting framework) and `BenchmarkPlugin` (boilerplate generator) from package-benchmark.
The following example shows an benchmark suite named `My-Benchmark` with the required dependency on `Benchmark` and the source files for the benchmark that reside in the directory `Benchmarks/My-Benchmark`:
```swift
.executableTarget(
      name: "My-Benchmark",
      dependencies: [
          .product(name: "Benchmark", package: "package-benchmark"),
      ],
      path: "Benchmarks/My-Benchmark",
      plugins: [
          .plugin(name: "BenchmarkPlugin", package: "package-benchmark"),
      ]
),
```

## Step 3: Writing benchmarks
There are [documentation available](https://swiftpackageindex.com/ordo-one/package-benchmark/documentation/benchmark/writingbenchmarks) as well as a [a sample project](https://github.com/ordo-one/package-benchmark-samples) using various aspects of this package in practice.

## Sample benchmark code
```swift
import Benchmark

let benchmarks : @Sendable () -> Void = {
    Benchmark("Minimal benchmark") { benchmark in
      // measure something here
    }

    func defaultCounter() -> Int {
        10
    }
    
    func dummyCounter(_ count: Int) {
        for index in 0 ..< count {
            blackHole(index)
        }
    }
    
    Benchmark("All metrics, full concurrency, async",
              configuration: .init(metrics: BenchmarkMetric.all,
                                   maxDuration: .seconds(10))) { benchmark in
        let _ = await withTaskGroup(of: Void.self, returning: Void.self, body: { taskGroup in
            for _ in 0..<80  {
                taskGroup.addTask {
                    dummyCounter(defaultCounter()*1000)
                }
            }
            for await _ in taskGroup {
            }
        })
    }     
}
```

### Step 4: Running benchmarks
To execute all defined benchmarks, simply run:

```swift package benchmark```

Please see the [documentation](https://swiftpackageindex.com/ordo-one/benchmark/documentation/benchmark/runningbenchmarks) for more detail on all options.

### Sample output benchmark run
<img width="1005" alt="image" src="https://user-images.githubusercontent.com/8501048/225311258-1247f8e9-c1fd-4598-a4b8-2b41a9b9a8e7.png">

### Sample output benchmark grouped by metric 
<img width="1089" alt="image" src="https://user-images.githubusercontent.com/8501048/225281786-411530de-25c2-47b5-b99f-0d7bac3209a7.png">

### Sample output delta comparison
<img width="1173" alt="image" src="https://user-images.githubusercontent.com/8501048/225282373-e7ba9fa1-1a2a-4028-b053-9f3aa82361b0.png">

### Sample output threshold deviation check
<img width="956" alt="image" src="https://user-images.githubusercontent.com/8501048/225282982-95c9c641-9455-4df2-81bc-6aee43721223.png">

### Sample usage of YouPlot
Install [YouPlot](https://github.com/red-data-tools/YouPlot)

```bash
swift package benchmark run --filter InternalUTCClock-now --metric wallClock --format histogramPercentiles --path stdout --no-progress | uplot lineplot -H
```

<img width="523" alt="image" src="https://user-images.githubusercontent.com/8501048/225284254-c1349494-2323-4460-b18a-7bc2896b5dc4.png">

### JMH Visualization

Using [jmh.morethan.io](https://jmh.morethan.io)

<img width="1262" alt="image" src="https://user-images.githubusercontent.com/8501048/225313246-4369da1f-0890-4856-8fd8-b28d56d842aa.png">

<img width="1482" alt="image" src="https://user-images.githubusercontent.com/8501048/225313559-33014755-797f-4ddf-b536-24c1a618f271.png">

## Swift 6 support
The package supports Swift 6.0 benchmark targets as well as Swift 5.10 targets (for Swift 5.9 support, need to use version 1.28.0 exactly).

For Swift 6 targets, use the following signature for the benchmarks closure:
```swift
let benchmarks : @Sendable () -> Void = {
```

## Output

The default text output from Benchmark is oriented around [the five-number summary](https://en.wikipedia.org/wiki/Five-number_summary) percentiles, plus the last decile (`p90`) and the last percentile (`p99`) - it's thus a variation of a [seven-figure summary](https://en.wikipedia.org/wiki/Seven-number_summary) with the focus on the 'bad' end of results (as those are what we typically care about addressing).
We've found that focusing on percentiles rather than average or standard deviations, is more useful for a wider range of benchmark measurements and gives a deeper understanding of the results.
Percentiles allows for a consistent way of expressing benchmark results of both throughput and latency measurements (which typically do **not** have a standardized distribution, being almost always multi-modal in nature).
This multi-modal nature of the latency measurements leads to the common statistical measures of mean and standard deviation being potentially misleading.

Please see the [documentation for further details on percentiles](https://swiftpackageindex.com/ordo-one/benchmark/documentation/benchmark/aboutpercentiles).

## API and file format stability
The API will be deemed stable as of `1.0.0` and follows semantical versioning for future releases. 

The export file formats that are externally defined (e.g. JMH or HDR Histogram formats) will follow the upstream definitions if they change, but have been quite stable for several years. 

The Histogram codable representation is not stable and may change if the Histogram implementation changes.

The benchmark internal baseline representation (stored in `.benchmarkBaselines`) is not stable and is not viewed as public API and may break over time.

For those wanting to save benchmark data over time, it's recommended to export data in e.g. HDR Histogram representations (percentiles, average, stddev etc) or simply post processing the histogramSamples format (which is raw data) to your desired representation.

PR:s for additional standardized formats are welcome, as the export formats are the intended stable interface for saving such data.

