# Getting Started

Before creating your own benchmarks, you must install the required prerequisites and add a dependency on Benchmark to your package.

## Overview

There are three steps that needs to be performed to get up and running with your own benchmarks:

* Install prerequisite dependencies if needed (currently that's only `jemalloc`) 
* Add a dependency on Benchmark to your `Package.swift` file
* Add one or more benchmark executable targets to the top level `Benchmarks/` directory for auto discovery

After having done those, running your benchmarks are as simple as running `swift package benchmark`.

### Installing Prerequisites and Platform Support

Benchmark requires Swift 5.7 support as it uses Regex and Duration types introduced with the `macOS 13` runtime, most versions of Linux will work as long as Swift 5.7+ is used. 

Benchmark also by default depends on and uses the [jemalloc](https://jemalloc.net) memory allocation library, which is used by the Benchmark infrastructure to capture memory allocation statistics. This is controlled via a Swift Package Manager trait named `Jemalloc`, which is **enabled by default**.

The Benchmark package requires you to install jemalloc on any machine used for benchmarking if you want malloc statistics.

#### Disabling jemalloc (Swift 6.1+)

For platforms where `jemalloc` isn't available (e.g. musl/static SDK builds, sanitizer builds, or Xcode profiling), disable the `Jemalloc` trait by passing `--disable-default-traits` to the Swift build, test, or package command:

```bash
swift build --disable-default-traits
swift test --disable-default-traits
swift package --disable-default-traits benchmark
```

If you depend on `benchmark` in your own package and want to disable jemalloc, you can opt out of the trait in your `Package.swift`:

```swift
.package(url: "https://github.com/ordo-one/benchmark.git", from: "...", traits: [])
```

#### Disabling jemalloc (Swift 5.x legacy)

When using Swift 5.x toolchains (which use the `Package@swift-5.9.swift` manifest), jemalloc can still be disabled via the `BENCHMARK_DISABLE_JEMALLOC` environment variable:

```bash
BENCHMARK_DISABLE_JEMALLOC=true swift package benchmark
```

If you want to avoid adding the `jemalloc` dependency to your main project while still getting malloc statistics when benchmarking, the recommended approach is to embed a separate Swift project in a subdirectory that uses your project, then the dependency on `jemalloc` is contained to that subproject only.

#### Installing `jemalloc` on macOS

```
brew install jemalloc
````

#### Installing `jemalloc` on Ubuntu

```
sudo apt-get install -y libjemalloc-dev
```

#### Installing `jemalloc` on Amazon Linux 2 
For Amazon Linux 2 users have reported that the following works:

Docker file configuration
```dockerfile
RUN sudo yum -y install bzip2 make
RUN curl https://github.com/jemalloc/jemalloc/releases/download/5.3.0/jemalloc-5.3.0.tar.bz2 -L -o jemalloc-5.3.0.tar.bz2
RUN tar -xf jemalloc-5.3.0.tar.bz2
RUN cd jemalloc-5.3.0 && ./configure && make && sudo make install
```

`make install` installs the libraries in `/usr/local/lib`, which the plugin can’t find, so you also have to do:

```
$ sudo ldconfig /usr/local/lib
```

Alternatively:
```
echo /usr/local/lib > /etc/ld.so.conf.d/local_lib.conf && ldconfig
```

### Adding dependencies

To add the dependency on Benchmark, add a dependency to your package:

```swift
.package(url: "https://github.com/ordo-one/benchmark", .upToNextMajor(from: "1.0.0")),
```

### Add benchmark exectuable targets using `benchmark init`
The absolutely easiest way to add new benchmark executable targets to your project is by using:
```bash
swift package --allow-writing-to-package-directory benchmark init MyNewBenchmarkTarget
```

This will perform the following steps for you:

* Create a `Benchmarks/MyNewBenchmarkTarget` directory
* Create a `Benchmarks/MyNewBenchmarkTarget/MyNewBenchmarkTarget.swift` benchmark target with the required boilerplate
* Add a new executable target for the benchmark to the end of your `Package.swift` file

The `init` command validates that the name you specify isn't used by any existing target and will not overwrite any existing file with that name in the Benchmarks/ location. 

After you've created the new target, you can directly run it with e.g.:
```bash
swift package benchmark --target MyNewBenchmarkTarget
```

### Add benchmark exectuable targets manually
Optionally if you don't want the plugin to modify your project for you, you can do those steps manually.

First create an executable target in `Package.swift` for each benchmark suite you want to measure.

The source for all benchmarks *must reside in a directory named `Benchmarks`* in the root of your swift package.

The benchmark plugin uses this directory combined with the executable target information to automatically discover and run your benchmarks.

For each executable target, include dependencies on both `Benchmark` (supporting framework) and `BenchmarkPlugin` (boilerplate generator) from `benchmark`.

The following example shows an benchmark suite named `My-Benchmark` with the required dependency on `Benchmark` and the source files for the benchmark that reside in the directory `Benchmarks/My-Benchmark`:

```
.executableTarget(
    name: "My-Benchmark",
    dependencies: [
        .product(name: "Benchmark", package: "benchmark"),
        .product(name: "BenchmarkPlugin", package: "benchmark"),
    ],
    path: "Benchmarks/My-Benchmark"
),
```

### Run benchmark plugin in release mode
If you find that the runtime for e.g. baseline processing is long, it's recommended to try running the benchmark
plugin in release mode configuration, e.g.

```
swift package -c release benchmark baseline read myBaseLine
```

### Dedicated GitHub runner instances

For reproducible and good comparable results, it is *highly* recommended to set up a private GitHub runner that is completely dedicated for performance benchmark runs, as the standard GitHub CI runners are deployed on a shared infrastructure the deviations between runs can be significant and difficult to assess.

### Sample Project

There's a [sample project](https://github.com/ordo-one/package-benchmark-samples) showing usage of the basic API which can be a good starting point if you want to look at how a project can be setup.
