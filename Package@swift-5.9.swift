// swift-tools-version: 5.9

import PackageDescription

import class Foundation.ProcessInfo

// If the environment variable BENCHMARK_DISABLE_JEMALLOC is set, we'll build the package without Jemalloc support
let disableJemalloc = ProcessInfo.processInfo.environment["BENCHMARK_DISABLE_JEMALLOC"]

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
    dependencies: [
        .package(url: "https://github.com/apple/swift-system.git", .upToNextMajor(from: "1.1.0")),
        .package(url: "https://github.com/apple/swift-argument-parser.git", "1.1.0"..<"1.6.0"),
        .package(url: "https://github.com/ordo-one/TextTable.git", .upToNextMajor(from: "0.0.1")),
        .package(url: "https://github.com/HdrHistogram/hdrhistogram-swift.git", .upToNextMajor(from: "0.1.0")),
        .package(url: "https://github.com/apple/swift-atomics.git", .upToNextMajor(from: "1.0.0")),
    ],
    targets: [
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
            path: "Plugins/BenchmarkTool"
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
            dependencies: ["Benchmark"]
        ),
    ]
)
// Check if this is a SPI build, then we need to disable jemalloc for macOS

let macOSSPIBuild: Bool // Disables jemalloc for macOS SPI builds as the infrastructure doesn't have jemalloc there

#if canImport(Darwin)
if let spiBuildEnvironment = ProcessInfo.processInfo.environment["SPI_BUILD"], spiBuildEnvironment == "1" {
    macOSSPIBuild = true
    print("Building for SPI@macOS, disabling Jemalloc")
} else {
    macOSSPIBuild = false
}
#else
macOSSPIBuild = false
#endif

// Add Benchmark target dynamically

// Shared dependencies
var dependencies: [PackageDescription.Target.Dependency] = [
    .product(name: "Histogram", package: "hdrhistogram-swift"),
    .product(name: "ArgumentParser", package: "swift-argument-parser"),
    .product(name: "SystemPackage", package: "swift-system"),
    .byNameItem(name: "CDarwinOperatingSystemStats", condition: .when(platforms: [.macOS, .iOS])),
    .byNameItem(name: "CLinuxOperatingSystemStats", condition: .when(platforms: [.linux])),
    .product(name: "Atomics", package: "swift-atomics"),
    "SwiftRuntimeHooks",
    "BenchmarkShared",
]

if macOSSPIBuild == false { // jemalloc always disable for macOSSPIBuild
    if let disableJemalloc, disableJemalloc != "false", disableJemalloc != "0" {
        print("Jemalloc disabled through environment variable.")
    } else {
        package.dependencies += [
            .package(url: "https://github.com/ordo-one/package-jemalloc.git", .upToNextMajor(from: "1.0.0"))
        ]
        dependencies += [
            .product(name: "jemalloc", package: "package-jemalloc", condition: .when(platforms: [.macOS, .linux]))
        ]
    }
}

package.targets += [.target(name: "Benchmark", dependencies: dependencies)]
