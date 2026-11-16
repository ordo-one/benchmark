# ``Benchmark/BenchmarkMetric``

## Topics

### Metric Collections

- ``BenchmarkMetric/default``
- ``BenchmarkMetric/microbenchmark``
- ``BenchmarkMetric/system``
- ``BenchmarkMetric/extended``
- ``BenchmarkMetric/memory``
- ``BenchmarkMetric/disk``
- ``BenchmarkMetric/all``

### System Metrics

- ``BenchmarkMetric/wallClock``
- ``BenchmarkMetric/syscalls``
- ``BenchmarkMetric/contextSwitches``
- ``BenchmarkMetric/threads``
- ``BenchmarkMetric/threadsRunning``
- ``BenchmarkMetric/cpuSystem``
- ``BenchmarkMetric/cpuUser``

### Extended System Metrics

- ``BenchmarkMetric/wallClock``
- ``BenchmarkMetric/cpuTotal``
- ``BenchmarkMetric/mallocCountTotal``
- ``BenchmarkMetric/freeCountTotal``
- ``BenchmarkMetric/mallocBytesCount``
- ``BenchmarkMetric/mallocFreeDelta``
- ``BenchmarkMetric/memoryLeakedBytes``
- ``BenchmarkMetric/throughput``
- ``BenchmarkMetric/peakMemoryResident``
- ``BenchmarkMetric/memoryLeaked``
- ``BenchmarkMetric/allocatedResidentMemory``
- ``BenchmarkMetric/instructions``

### Memory Metrics

- ``BenchmarkMetric/peakMemoryResident``
- ``BenchmarkMetric/peakMemoryResidentDelta``
- ``BenchmarkMetric/peakMemoryVirtual``
- ``BenchmarkMetric/mallocCountSmall``
- ``BenchmarkMetric/mallocCountLarge``
- ``BenchmarkMetric/mallocCountTotal``
- ``BenchmarkMetric/freeCountTotal``
- ``BenchmarkMetric/mallocBytesCount``
- ``BenchmarkMetric/mallocFreeDelta``
- ``BenchmarkMetric/memoryLeaked``
- ``BenchmarkMetric/memoryLeakedBytes``
- ``BenchmarkMetric/allocatedResidentMemory``

### Reference Counting (retain/release)

- ``BenchmarkMetric/retainCount``
- ``BenchmarkMetric/releaseCount``
- ``BenchmarkMetric/retainReleaseDelta``

### Disk Metrics

- ``BenchmarkMetric/readSyscalls``
- ``BenchmarkMetric/writeSyscalls``
- ``BenchmarkMetric/readBytesLogical``
- ``BenchmarkMetric/writeBytesLogical``
- ``BenchmarkMetric/readBytesPhysical``
- ``BenchmarkMetric/writeBytesPhysical``

### Custom Metrics

- ``BenchmarkMetric/custom(_:polarity:useScalingFactor:)``
- ``BenchmarkMetric/polarity-swift.property``
- ``BenchmarkMetric/Polarity-swift.enum``

### Inspecting Metrics

- ``BenchmarkMetric/description``
- ``BenchmarkMetric/countable``

### Decoding a Metric

- ``BenchmarkMetric/init(from:)``
