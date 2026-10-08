# Exporting Benchmark Results

Export Benchmarks into other formats to analyze or visualize the data.

## Overview

Benchmark supports exporting its results into a variety of formats including text formats, Java Microbenchmark Harness (JMH), Influx, and as a serialized [HDR Histogram](http://hdrhistogram.org).
This allows for tracking performance over time or analyzing/visualizing with other tools such as [JMH visualizer](https://jmh.morethan.io), [Gnuplot](http://www.gnuplot.info), [YouPlot](https://github.com/red-data-tools/YouPlot), [HDR Histogram analyzer](http://hdrhistogram.github.io/HdrHistogram/plotFiles.html) and more.

To export the benchmark information, add the desired format with the `--format` option when running the benchmarks.
For example, to export your benchmarks into JMH format, use the command:

```bash
swift package --allow-writing-to-package-directory benchmark --format jmh
```

It's also possible to use the output and use it with external plotting tools, e.g.:

```bash
swift package benchmark  --filter "Sc.*" --path stdout --format histogramPercentiles --no-progress --metric wallClock | uplot lineplot -H -w 80 -h 30
```

![YouPlot sample](uplot)

### Streaming Text formats

- term `text`: The default output, displaying a textual grid of information for your benchmarks, suitable for use in the console. 
- term `markdown`: The same content as `text`, but extended with explicit markdown support, suitable for use as output from e.g. a GitHub workflow action.

The default text output from Benchmark is oriented around [the five-number summary](https://en.wikipedia.org/wiki/Five-number_summary) percentiles, plus the last decile (`p90`) and the last percentile (`p99`) - it's thus a variation of a [seven-figure summary](https://en.wikipedia.org/wiki/Seven-number_summary) with the focus on the 'bad' end of results (as those are what we typically care about addressing).
The output streams to the terminal, allowing you to easily capture it to write to a file or preserve in an environment variable, which can be useful in continuous integration scenarios.
For more information on using this output within continuous integration, see the examples in <doc:ComparingBenchmarksCI>.

### Saved Formats

- term `histogram`: Each benchmark and metric combination is written to a file with the file name extension `txt`. Each file contains a sequence of percentiles for that metric combination, as well as statistical summary information. This is the standard HDR Histogram text format usable by [the HDR Histogram plotFiles online tool](http://hdrhistogram.github.io/HdrHistogram/plotFiles.html).
- term `histogramEncoded`:  Each benchmark and metric combination is written to a file with the file name extension `json`, containing the serialized [Histogram](https://github.com/ordo-one/package-histogram)) in JSON format (Codable).
- term `histogramSamples`: All samples for each benchmark and metric combination is written to a file with the file name extension `tsv`.
- term `histogramPercentiles`: Each percentiles values between (0-99, 99.9, 99.99, ... 99.99999, 100) inluding a header line for processing by external tools (e.g. Youplot) `tsv`.
- term `influx`: A single file is generated with the file name extension `csv` with the values encoded as metrics using the [Influx Line Protocol](https://docs.influxdata.com/influxdb/v1.8/write_protocols/line_protocol_reference/).
- term `jmh`: A single file is generated with the file name extension `jmh` encoded in the [java microbenchmark harness](https://openjdk.org/projects/code-tools/jmh/) format. You can quickly compare the contained metrics by dropping the file into the [JMH visualizer](https://jmh.morethan.io) using a browser.

### Allocation call stacks (`--allocation-stacks`)

Running with the `--allocation-stacks` flag (independent of `--format`, `run` command only) additionally writes one file per benchmark that allocated, named `<target>.<benchmark>.allocations.folded`, to the export path. Each line is one unique allocation call stack in collapsed/folded format — `frameRoot;frame;frameLeaf count` — sorted by allocation count, containing every allocation made inside the measurement windows. Counts are per iteration and divided by the benchmark's `scalingFactor` unless `--scale` is given, like the `mallocCountTotal` metric, so files from runs with different iteration counts still line up (a stack seen less than once per iteration is reported as 1 rather than disappearing).

The folded format is directly consumable by [flamegraph.pl](https://github.com/brendangregg/FlameGraph) (including differential flamegraphs via `difffolded.pl`) and [speedscope](https://speedscope.app):

```bash
swift package --allow-writing-to-package-directory benchmark run --target MyTarget --allocation-stacks
flamegraph.pl MyTarget.MyBenchmark.allocations.folded > allocations.svg
```

Because the format is line-based, diffing the files from two runs (before/after a change) pinpoints exactly which call path gained or lost allocations. See <doc:RunningBenchmarks#Diagnosing-allocation-regressions-with-allocation-stacks> for the semantics and caveats of the capture mode.


