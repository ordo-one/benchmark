# ``Benchmark``

Benchmark allows you to easily create sophisticated Swift performance benchmarks

## Overview

Performance is a key feature for many apps and frameworks. 
Benchmark helps make it easy to measure and track many different metrics that affects performance, such as CPU usage, memory usage and use of operating system resources such as threads and system calls.
Benchmark provides a quick way for validation of performance metrics, while other more specialized tools such as Instruments, DTrace, Heaptrack, Leaks, Sample, etc support finding root causes for any deviations found.

Benchmark is suitable both for smaller benchmarks focusing on execution time of small code snippets as well as for more extensive benchmarks that care about several additional metrics such as memory allocations, syscalls, thread usage, context switches, ARC traffic, and more. 

Thanks to the use of [Histogram](https://github.com/ordo-one/package-histogram) it's especially suitable for capturing latency statistics for large number of samples.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:AboutPercentiles>

### Workflows

- <doc:CreatingAndComparingBaselines>
- <doc:ComparingBenchmarksCI>
- <doc:ExportingBenchmarks>

### Benchmarks

- <doc:WritingBenchmarks>
- <doc:Metrics>
- <doc:RunningBenchmarks>
- <doc:AllocationStacks>
- <doc:CreatingAndComparingBaselines>
- <doc:ComparingBenchmarksCI>
- <doc:ExportingBenchmarks>

### Defining a Benchmark

- ``Benchmark/Benchmark``

### Configuring Benchmarks

- ``Benchmark/Configuration-swift.struct``
- ``BenchmarkMetric``
- ``BenchmarkTimeUnits``
- ``BenchmarkUnits``
- ``BenchmarkScalingFactor``

### Supporting Functions

- ``Benchmark/blackHole(_:)``
