// swift-tools-version: 6.3

import PackageDescription

import class Foundation.ProcessInfo

// When MALLOC_INTERPOSER_LOCAL_PATH is set, use a local checkout of the
// malloc-interposer package instead of the published GitHub URL. Useful
// when iterating on the interposer alongside this package.
let mallocInterposerDependency: Package.Dependency = {
    if let localPath = ProcessInfo.processInfo.environment["MALLOC_INTERPOSER_LOCAL_PATH"],
        localPath.isEmpty == false
    {
        return .package(path: localPath)
    }
    return .package(
        url: "https://github.com/ordo-one/malloc-interposer.git",
        .upToNextMajor(from: "1.3.0")
    )
}()

// The malloc interposer is enabled by default. Turn off the "MallocInterposer"
// trait (or set BENCHMARK_DISABLE_MALLOC_INTERPOSER) to build without it:
// allocations then avoid the interposer's per-allocation size header, at the
// cost of the interposer-backed malloc metrics on Swift 6.3+.
//
// BENCHMARK_DISABLE_JEMALLOC is honored as a backward-compatible alias: it was
// the opt-out on Swift <= 6.2 (where it dropped the jemalloc backend) and is
// still set by existing CI jobs, the 6.2-vs-6.3 compare script, and downstream
// users' scripts. Without the alias those would silently keep the interposer on.
//
// The "RuntimeInterposer" trait similarly gates the Linux 6.3 ARC runtime
// interposer. It is compiled out by `--disable-default-traits`, which the static
// musl build uses — its strong swift_retain/release overrides otherwise collide
// with the static libswiftCore at link time (duplicate symbols).
let environment = ProcessInfo.processInfo.environment
let disableMallocInterposer = environment["BENCHMARK_DISABLE_MALLOC_INTERPOSER"] != nil
    || environment["BENCHMARK_DISABLE_JEMALLOC"] != nil
var defaultTraits: Set<String> = ["MallocInterposer", "RuntimeInterposer"]
if disableMallocInterposer {
    defaultTraits.remove("MallocInterposer")
}

var packageDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/apple/swift-system.git", .upToNextMajor(from: "1.1.0")),
    .package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMajor(from: "1.6.0")),
    .package(url: "https://github.com/ordo-one/TextTable.git", .upToNextMajor(from: "0.0.1")),
    .package(url: "https://github.com/HdrHistogram/hdrhistogram-swift.git", .upToNextMajor(from: "0.1.4")),
    .package(url: "https://github.com/apple/swift-atomics.git", .upToNextMajor(from: "1.0.0")),
    mallocInterposerDependency,
]

#if os(Linux) && compiler(>=6.3)
packageDependencies += [
    .package(url: "https://github.com/ordo-one/swift-runtime-interposer.git", .upToNextMajor(from: "1.0.0"))
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
    .product(name: "MallocInterposerSwift", package: "malloc-interposer", condition: .when(traits: ["MallocInterposer"])),
]

#if os(Linux) && compiler(>=6.3)
benchmarkDependencies += [
    .product(
        name: "SwiftRuntimeInterposerC",
        package: "swift-runtime-interposer",
        condition: .when(platforms: [.linux], traits: ["RuntimeInterposer"])
    ),
    .product(
        name: "SwiftRuntimeInterposerSwift",
        package: "swift-runtime-interposer",
        condition: .when(platforms: [.linux], traits: ["RuntimeInterposer"])
    ),
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
        .trait(name: "MallocInterposer"),
        .trait(name: "RuntimeInterposer"),
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
