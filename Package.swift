// swift-tools-version: 6.3

import PackageDescription

import class Foundation.ProcessInfo

// If the environment variable BENCHMARK_DISABLE_JEMALLOC is set disable Jemalloc trait (backward compatibility)
let disableJemalloc = ProcessInfo.processInfo.environment["BENCHMARK_DISABLE_JEMALLOC"] != nil

let defaultTraits: Set<String>

if disableJemalloc {
    defaultTraits = []
} else {
    defaultTraits = ["Jemalloc"]
}

// When MALLOC_INTERPOSER_LOCAL_PATH is set, use a local checkout of the
// malloc-interposer package instead of the published GitHub URL. Useful
// when iterating on the interposer alongside this package.
let mallocInterposerDependency: Package.Dependency = {
    if let localPath = ProcessInfo.processInfo.environment["MALLOC_INTERPOSER_LOCAL_PATH"],
       localPath.isEmpty == false {
        return .package(path: localPath)
    }
    return .package(
        url: "https://github.com/ordo-one/malloc-interposer.git",
        .upToNextMajor(from: "1.0.0")
    )
}()

var packageDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/apple/swift-system.git", .upToNextMajor(from: "1.1.0")),
    .package(url: "https://github.com/apple/swift-argument-parser.git", "1.1.0"..<"1.6.0"),
    .package(url: "https://github.com/ordo-one/TextTable.git", .upToNextMajor(from: "0.0.1")),
    .package(url: "https://github.com/HdrHistogram/hdrhistogram-swift.git", .upToNextMajor(from: "0.1.4")),
    .package(url: "https://github.com/apple/swift-atomics.git", .upToNextMajor(from: "1.0.0")),
    .package(url: "https://github.com/ordo-one/package-jemalloc.git", .upToNextMajor(from: "1.0.0")),
    mallocInterposerDependency,
]

#if os(Linux) && compiler(>=6.3)
packageDependencies += [
    .package(url: "https://github.com/ordo-one/swift-runtime-interposer.git", .upToNextMajor(from: "1.2.0")),
]
#endif

var benchmarkDependencies: [Target.Dependency] = [
    .product(name: "Histogram", package: "hdrhistogram-swift"),
    .product(name: "ArgumentParser", package: "swift-argument-parser"),
    .product(name: "SystemPackage", package: "swift-system"),
    .byNameItem(name: "CDarwinOperatingSystemStats", condition: .when(platforms: [.macOS, .iOS])),
    .byNameItem(name: "CLinuxOperatingSystemStats", condition: .when(platforms: [.linux])),
    .product(name: "Atomics", package: "swift-atomics"),
    "SwiftRuntimeHooks",
    "BenchmarkShared",
    // Gated on the `Jemalloc` trait so that `--disable-default-traits` /
    // BENCHMARK_DISABLE_JEMALLOC removes the malloc-stats backend entirely (needed for e.g.
    // fully-static musl builds and sanitizer runs). On Swift 6.3+ this trait selects the
    // interposer backend; on Swift <=6.2 (see Package@swift-6.2.swift) it selects jemalloc.
    // When the trait is off, BenchmarkExecutor falls back to the no-op MallocStatsProducer stub.
    .product(name: "MallocInterposerSwift", package: "malloc-interposer", condition: .when(traits: ["Jemalloc"])),
]

#if os(Linux) && compiler(>=6.3)
benchmarkDependencies += [
    .product(name: "SwiftRuntimeInterposerC", package: "swift-runtime-interposer", condition: .when(platforms: [.linux])),
    .product(name: "SwiftRuntimeInterposerSwift", package: "swift-runtime-interposer", condition: .when(platforms: [.linux])),
]
#endif

let package = Package(
    name: "Benchmark",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .plugin(name: "BenchmarkCommandPlugin", targets: ["BenchmarkCommandPlugin"]),
        .plugin(name: "BenchmarkPlugin", targets: ["BenchmarkPlugin"]),
        .library(
            name: "Benchmark",
            targets: ["Benchmark"]
        ),
    ],
    traits: [
        .trait(name: "Jemalloc"),
        .default(enabledTraits: defaultTraits),
    ],
    dependencies: packageDependencies,
    targets: [
        .target(
            name: "Benchmark",
            dependencies: benchmarkDependencies,
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Plugins used by users of the package

        // The actual 'benchmark' command plugin
        .plugin(
            name: "BenchmarkCommandPlugin",
            capability: .command(
                intent: .custom(
                    verb: "benchmark",
                    description: "Run the Benchmark performance test suite."
                )
            ),
            dependencies: [
                "BenchmarkTool"
            ],
            path: "Plugins/BenchmarkCommandPlugin"
        ),

        // Plugin that generates the boilerplate needed to interface with the Benchmark infrastructure
        .plugin(
            name: "BenchmarkPlugin",
            capability: .buildTool(),
            dependencies: [
                "BenchmarkBoilerplateGenerator"
            ],
            path: "Plugins/BenchmarkPlugin"
        ),

        // Tool that the plugin executes to perform the actual work, the real benchmark driver
        .executableTarget(
            name: "BenchmarkTool",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SystemPackage", package: "swift-system"),
                .product(name: "TextTable", package: "TextTable"),
                "Benchmark",
                "BenchmarkShared",
            ],
            path: "Plugins/BenchmarkTool",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        // Tool that generates the boilerplate
        .executableTarget(
            name: "BenchmarkBoilerplateGenerator",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SystemPackage", package: "swift-system"),
            ],
            path: "Plugins/BenchmarkBoilerplateGenerator"
        ),

        // Tool that simply generates the man page for the BenchmarkPlugin as we can't use SAP in it... :-/
        .executableTarget(
            name: "BenchmarkHelpGenerator",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "BenchmarkShared",
            ],
            path: "Plugins/BenchmarkHelpGenerator"
        ),

        // Getting OS specific information
        .target(
            name: "CDarwinOperatingSystemStats",
            dependencies: [],
            path: "Platform/CDarwinOperatingSystemStats"
        ),

        // Getting OS specific information
        .target(
            name: "CLinuxOperatingSystemStats",
            dependencies: [],
            path: "Platform/CLinuxOperatingSystemStats"
        ),

        // Hooks for ARC
        .target(name: "SwiftRuntimeHooks"),

        // Shared definitions
        .target(name: "BenchmarkShared"),

        .testTarget(
            name: "BenchmarkTests",
            dependencies: ["Benchmark"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
