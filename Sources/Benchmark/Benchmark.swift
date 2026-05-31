//
// Copyright (c) 2022 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

import Foundation

// swiftlint:disable file_length identifier_name

/// Defines a benchmark
public final class Benchmark: Codable, Hashable { // swiftlint:disable:this type_body_length
    @_documentation(visibility: internal)
    public typealias BenchmarkClosure = (_ benchmark: Benchmark) -> Void
    @_documentation(visibility: internal)
    public typealias BenchmarkAsyncClosure = @isolated(any) (_ benchmark: Benchmark) async -> Void
    @_documentation(visibility: internal)
    public typealias BenchmarkThrowingClosure = (_ benchmark: Benchmark) throws -> Void
    @_documentation(visibility: internal)
    public typealias BenchmarkAsyncThrowingClosure = @isolated(any) (_ benchmark: Benchmark) async throws -> Void
    @_documentation(visibility: internal)
    public typealias BenchmarkMeasurementSynchronization = (_ explicitStartStop: Bool) -> Void
    @_documentation(visibility: internal)
    public typealias BenchmarkCustomMetricMeasurement = (BenchmarkMetric, Int) -> Void

    /// Alias for closures used to hook into setup / teardown
    public typealias BenchmarkSetupHook = () async throws -> Void
    public typealias BenchmarkTeardownHook = () async throws -> Void

    private static let setupTeardownLock = NSLock()

    @_documentation(visibility: internal)
    @ThreadSafeProperty(wrappedValue: nil, lock: setupTeardownLock)
    public static var _startupHook: BenchmarkSetupHook? // Should be removed when going to 2.0, just kept for API compatiblity

    @_documentation(visibility: internal)
    @ThreadSafeProperty(wrappedValue: nil, lock: setupTeardownLock)
    public static var _shutdownHook: BenchmarkTeardownHook? // Should be removed when going to 2.0, just kept for API compatiblity

    @_documentation(visibility: internal)
    @ThreadSafeProperty(wrappedValue: nil, lock: setupTeardownLock)
    public static var _setup: BenchmarkSetupHook?

    @_documentation(visibility: internal)
    @ThreadSafeProperty(wrappedValue: nil, lock: setupTeardownLock)
    public static var _teardown: BenchmarkTeardownHook?

    #if swift(<5.10)
    @_documentation(visibility: internal)
    public static var startupHook: BenchmarkSetupHook? {
        get { _startupHook }
        set { _startupHook = newValue }
    }

    @_documentation(visibility: internal)
    public static var shutdownHook: BenchmarkTeardownHook? {
        get { _shutdownHook }
        set { _shutdownHook = newValue }
    }

    /// This closure if set, will be run before a targets benchmarks are run, but after they are registered
    public static var setup: BenchmarkSetupHook? {
        get { _setup }
        set { _setup = newValue }
    }

    /// This closure if set, will be run after a targets benchmarks run, but after they are registered
    public static var teardown: BenchmarkTeardownHook? {
        get { _teardown }
        set { _teardown = newValue }
    }
    #elseif swift(>=5.10)
    @_documentation(visibility: internal)
    nonisolated(unsafe) public static var startupHook: BenchmarkSetupHook? {
        get { _startupHook }
        set { _startupHook = newValue }
    }

    @_documentation(visibility: internal)
    nonisolated(unsafe) public static var shutdownHook: BenchmarkTeardownHook? {
        get { _shutdownHook }
        set { _shutdownHook = newValue }
    }

    /// This closure if set, will be run before a targets benchmarks are run, but after they are registered
    nonisolated(unsafe) public static var setup: BenchmarkSetupHook? {
        get { _setup }
        set { _setup = newValue }
    }

    /// This closure if set, will be run after a targets benchmarks run, but after they are registered
    nonisolated(unsafe) public static var teardown: BenchmarkTeardownHook? {
        get { _teardown }
        set { _teardown = newValue }
    }
    #endif

    /// Set to true if this benchmark results should be compared with an absolute threshold when `--check-absolute` is
    /// specified on the command line. An implementation can then choose to configure thresholds differently for
    /// such comparisons by e.g. reading them in from external storage.
    @available(
        *,
        deprecated,
        message: "The checking of absolute thresholds should now be done using `swift package benchmark thresholds`"
    )
    public static var checkAbsoluteThresholds = false

    @_documentation(visibility: internal)
    public static var benchmarks: [Benchmark] = [] // Bookkeeping of all registered benchmarks

    /// The name of the benchmark without any of the tags appended
    public var baseName: String

    /// The name used for display purposes of the benchmark (also used for matching when comparing to baselines)
    public var name: String {
        get {
            guard configuration.tags.isEmpty else {
                return baseName
                    + " ("
                    + configuration.tags
                    .sorted(by: { $0.key < $1.key })
                    .map({ "\($0.key): \($0.value)" })
                    .joined(separator: ", ")
                    + ")"
            }
            return baseName
        }
        set {
            baseName = newValue
        }
    }

    /// The reason for a benchmark failure, not set if successful
    public var failureReason: String?
    /// The current benchmark iteration (also includes warmup iterations), can be useful when
    /// e.g. unique keys will be needed for different iterations
    public var currentIteration: Int = 0

    /// Convenience range to iterate over for benchmarks
    public var scaledIterations: Range<Int> { 0..<configuration.scalingFactor.rawValue }

    /// Some internal state for display purposes of the benchmark by the BenchmarkTool
    @_documentation(visibility: internal)
    public var target: String
    @_documentation(visibility: internal)
    public var executablePath: String?
    /// closure: The actual benchmark closure that will be measured
    var closure: BenchmarkClosure? // The actual benchmark to run
    /// asyncClosure: The actual benchmark (async) closure that will be measured.
    /// Stored as the throwing variant so both throwing and non-throwing async closures can be held
    /// while preserving the closure's actor isolation (captured via `@isolated(any)`), which lets the
    /// executor run the measurement loop *on* that isolation hop-free (e.g. `@MainActor` benchmarks).
    var asyncClosure: BenchmarkAsyncThrowingClosure? // The actual benchmark to run
    // setup/teardown hooks for the instance
    var setup: BenchmarkSetupHook?
    var teardown: BenchmarkTeardownHook?

    /// The state returned from setup, if any - need to be cast as required
    public var setupState: Any?

    // Hooks for benchmark infrastructure to capture metrics of actual measurement() block without preamble:
    @_documentation(visibility: internal)
    public var measurementPreSynchronization: BenchmarkMeasurementSynchronization?
    @_documentation(visibility: internal)
    public var measurementPostSynchronization: BenchmarkMeasurementSynchronization?

    // Hook for custom metrics capturing
    public var customMetricMeasurement: BenchmarkCustomMetricMeasurement?

    /// The configuration to use for this benchmark
    public var configuration: Configuration = .init()

    /// Hook for setting defaults for a whole benchmark suite
    private static let configurationLock = NSLock()
    @ThreadSafeProperty(
        wrappedValue: .init(
            metrics: BenchmarkMetric.default,
            tags: [:],
            timeUnits: .automatic,
            units: [:],
            warmupIterations: 1,
            scalingFactor: .one,
            maxDuration: .seconds(1),
            maxIterations: 10_000,
            skip: false,
            thresholds: nil
        ),
        lock: configurationLock
    )
    private static var _defaultConfiguration: Configuration

    #if swift(<5.10)
    public static var defaultConfiguration: Configuration {
        get { _defaultConfiguration }
        set { _defaultConfiguration = newValue }
    }
    #elseif swift(>=5.10)
    nonisolated(unsafe)
        public static var defaultConfiguration: Configuration
    {
        get { _defaultConfiguration }
        set { _defaultConfiguration = newValue }
    }
    #endif

    static var testSkipBenchmarkRegistrations = false // true in test to avoid bench registration fail
    var measurementCompleted = false // Keep track so we skip multiple 'end of measurement'

    enum CodingKeys: String, CodingKey {
        case baseName = "name"
        case target
        case executablePath
        case configuration
        case failureReason
    }

    @_documentation(visibility: internal)
    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }

    @_documentation(visibility: internal)
    public static func == (lhs: Benchmark, rhs: Benchmark) -> Bool {
        lhs.name == rhs.name
    }

    /// Definition of a Benchmark
    /// - Parameters:
    ///   - name: The name used for display purposes of the benchmark (also used for
    ///   matching when comparing to baselines)
    ///   - configuration: Defines the settings that should be used for this benchmark
    ///   - closure: The actual benchmark closure that will be measured
    ///   - setup: A closure that will be run once before the benchmark iterations are run
    ///   - teardown: A closure that will be run once after the benchmark iterations are done
    @discardableResult
    public init?(
        _ name: String,
        configuration: Benchmark.Configuration = Benchmark.defaultConfiguration,
        closure: @escaping BenchmarkClosure,
        setup: BenchmarkSetupHook? = nil,
        teardown: BenchmarkTeardownHook? = nil
    ) {
        if configuration.skip {
            return nil
        }
        target = ""
        self.baseName = name
        self.configuration = configuration
        self.closure = closure
        self.setup = setup
        self.teardown = teardown

        benchmarkRegistration()
    }

    /// Definition of a Benchmark
    /// - Parameters:
    ///   - name: The name used for display purposes of the benchmark (also used for
    ///   matching when comparing to baselines)
    ///   - configuration: Defines the settings that should be used for this benchmark
    ///   - closure: The actual `async` benchmark closure that will be measured
    ///   - setup: A closure that will be run once before the benchmark iterations are run
    ///   - teardown: A closure that will be run once after the benchmark iterations are done
    @discardableResult
    public init?(
        _ name: String,
        configuration: Benchmark.Configuration = Benchmark.defaultConfiguration,
        closure: @escaping BenchmarkAsyncClosure,
        setup: BenchmarkSetupHook? = nil,
        teardown: BenchmarkTeardownHook? = nil
    ) {
        if configuration.skip {
            return nil
        }
        target = ""
        self.baseName = name
        self.configuration = configuration
        asyncClosure = closure
        self.setup = setup
        self.teardown = teardown

        benchmarkRegistration()
    }

    /// Definition of a throwing Benchmark
    /// - Parameters:
    ///   - name: The name used for display purposes of the benchmark (also used for
    ///   matching when comparing to baselines)
    ///   - configuration: Defines the settings that should be used for this benchmark
    ///   - closure: The actual throwing benchmark closure that will be measured
    ///   - setup: A closure that will be run once before the benchmark iterations are run
    ///   - teardown: A closure that will be run once after the benchmark iterations are done
    @discardableResult
    public convenience init?(
        _ name: String,
        configuration: Benchmark.Configuration = Benchmark.defaultConfiguration,
        closure: @escaping BenchmarkThrowingClosure,
        setup: BenchmarkSetupHook? = nil,
        teardown: BenchmarkTeardownHook? = nil
    ) {
        self.init(
            name,
            configuration: configuration,
            closure: { benchmark in
                do {
                    try closure(benchmark)
                } catch {
                    benchmark.error("Benchmark \(name) failed with \(String(reflecting: error))")
                }
            },
            setup: setup,
            teardown: teardown
        )
    }

    /// Definition of an async throwing Benchmark
    /// - Parameters:
    ///   - name: The name used for display purposes of the benchmark (also used for
    ///   matching when comparing to baselines)
    ///   - configuration: Defines the settings that should be used for this benchmark
    ///   - closure: The actual async throwing benchmark closure that will be measured
    ///   - setup: A closure that will be run once before the benchmark iterations are run
    ///   - teardown: A closure that will be run once after the benchmark iterations are done
    @discardableResult
    public init?(
        _ name: String,
        configuration: Benchmark.Configuration = Benchmark.defaultConfiguration,
        closure: @escaping BenchmarkAsyncThrowingClosure,
        setup: BenchmarkSetupHook? = nil,
        teardown: BenchmarkTeardownHook? = nil
    ) {
        if configuration.skip {
            return nil
        }
        target = ""
        self.baseName = name
        self.configuration = configuration
        // Stored directly (rather than wrapped in an error-handling closure) so the closure's actor
        // isolation is preserved; any thrown error is caught in `run()`.
        asyncClosure = closure
        self.setup = setup
        self.teardown = teardown

        benchmarkRegistration()
    }

    // Shared between sync/async actual benchmark registration
    func benchmarkRegistration() {
        if Self.testSkipBenchmarkRegistrations == false {
            guard Self.benchmarks.contains(self) == false else {
                fatalError("Duplicate registration of benchmark '\(name)', name must be unique.")
            }

            Self.benchmarks.append(self)
        }

        configuration.thresholds?
            .forEach { thresholdMetric, _ in
                if self.configuration.metrics.contains(thresholdMetric) == false {
                    print(
                        "Warning: Custom threshold tolerance defined for metric `\(thresholdMetric)` "
                            + "which isn't used by benchmark `\(name)`"
                    )
                }
            }
    }

    /// `measurement` registers custom metric measurements
    ///
    ///
    /// - Parameters:
    ///   - metric: A `.custom()` metric to register a value for
    ///   - value: The value to register for the metric.
    public func measurement(_ metric: BenchmarkMetric, _ value: Int) {
        if let customMetricMeasurement {
            switch metric {
            case .custom:
                customMetricMeasurement(metric, value)
            default:
                return
            }
        }
    }

    /// If the benchmark contains a preamble setup that should not be part of the measurement
    /// `startMeasurement` can be called explicitly to define when measurement should begin.
    /// Otherwise the whole benchmark will be measured.
    public func startMeasurement() {
        _startMeasurement(true)
    }

    private func _startMeasurement(_ explicitStartStop: Bool) {
        if let measurementPreSynchronization {
            measurementPreSynchronization(explicitStartStop)
        }
        measurementCompleted = false
    }

    /// If the benchmark contains a postample that should not be part of the measurement
    /// `stopMeasurement` can be called explicitly to define when measurement should stop.
    /// Otherwise the whole benchmark will be measured.
    public func stopMeasurement() {
        _stopMeasurement(true)
    }

    private func _stopMeasurement(_ explicitStartStop: Bool) {
        guard measurementCompleted == false else { // This is to skip the implicit stop if we did an explicit before
            return
        }

        if let measurementPostSynchronization {
            measurementCompleted = true
            measurementPostSynchronization(explicitStartStop)
        }
    }

    /// Used to signify that a given benchmark have failed for some reason
    /// - Parameter description: An explanation why a given benchmark failed which will be reported to the end user.
    public func error(_ description: String) {
        failureReason = description
    }

    // The rest is intenral supporting infrastructure that should only
    // be used by the BenchmarkRunner

    // Public but should only be used by BenchmarkRunner
    //
    // The `isolation` parameter defaults to the caller's isolation (`#isolation`), so when the
    // executor runs the measurement loop on a benchmark's desired actor (e.g. `@MainActor`), the
    // async closure below is invoked on that same isolation with no actor hop. There is no longer
    // any thread-blocking bridge (the old `DispatchSemaphore`), so benchmarks may freely run on the
    // main actor / main thread without deadlocking.
    @_documentation(visibility: internal)
    public func run(isolation: isolated (any Actor)? = #isolation) async {
        if let closure {
            _startMeasurement(false)
            closure(self)
            _stopMeasurement(false)
        } else if let asyncClosure {
            _startMeasurement(false)
            do {
                try await asyncClosure(self)
            } catch {
                self.error("Benchmark \(name) failed with \(String(reflecting: error))")
            }
            _stopMeasurement(false)
        }
    }
}

public extension Benchmark {
    /// The configuration settings for running a benchmark.
    struct Configuration: Codable {
        /// Defines the metrics that should be measured for the benchmark
        public var metrics: [BenchmarkMetric]
        /// Specifies the parameters used to define the benchmark.
        public var tags: [String: String]
        /// Override the automatic detection of timeunits for metrics related to time to a specific
        /// one (auto should work for most use cases).
        public var timeUnits: BenchmarkTimeUnits
        /// Override the automatic detection of units for metrics not related to time to a specific one
        public var units: [BenchmarkMetric: BenchmarkUnits]
        /// Specifies a number of warmup iterations should be performed before the measurement to
        /// reduce outliers due to e.g. cache population
        public var warmupIterations: Int
        /// Specifies the number of logical subiterations being done, supporting scaling of metrics accordingly.
        /// E.g. `.kilo` will scale results with 1000. Any subiteration done in the benchmark should use
        /// `for _ in benchmark.scaledIterations` for the number of iterations.
        public var scalingFactor: BenchmarkScalingFactor
        /// The maximum wall clock runtime for the benchmark, currenty defaults to `.seconds(1)` if not set
        public var maxDuration: Duration
        /// The maximum number of iterations for the benchmark., currently defaults to 10K iterations if not set
        public var maxIterations: Int
        /// Whether to skip this test (convenience for not having to comment out tests that have issues)
        public var skip = false
        /// Customized threshold tolerances for a given metric for the Benchmark used for checking for regressions/improvements/equality.
        public var thresholds: [BenchmarkMetric: BenchmarkThresholds]?
        /// Optional per-benchmark specific setup done before warmup and all iterations
        public var setup: BenchmarkSetupHook?
        /// Optional per-benchmark specific teardown done after final run is done
        public var teardown: BenchmarkTeardownHook?

        public init(
            metrics: [BenchmarkMetric] = defaultConfiguration.metrics,
            tags: [String: String] = defaultConfiguration.tags,
            timeUnits: BenchmarkTimeUnits = defaultConfiguration.timeUnits,
            units: [BenchmarkMetric: BenchmarkUnits] = defaultConfiguration.units,
            warmupIterations: Int = defaultConfiguration.warmupIterations,
            scalingFactor: BenchmarkScalingFactor = defaultConfiguration.scalingFactor,
            maxDuration: Duration = defaultConfiguration.maxDuration,
            maxIterations: Int = defaultConfiguration.maxIterations,
            skip: Bool = defaultConfiguration.skip,
            thresholds: [BenchmarkMetric: BenchmarkThresholds]? =
                defaultConfiguration.thresholds,
            setup: BenchmarkSetupHook? = nil,
            teardown: BenchmarkTeardownHook? = nil
        ) {
            self.metrics = metrics
            self.tags = tags
            self.timeUnits = timeUnits
            self.units = units
            self.warmupIterations = warmupIterations
            self.scalingFactor = scalingFactor
            self.maxDuration = maxDuration
            self.maxIterations = maxIterations
            self.skip = skip
            self.thresholds = thresholds
            self.setup = setup
            self.teardown = teardown
        }

        // swiftlint:disable nesting
        enum CodingKeys: String, CodingKey {
            case metrics
            case tags
            case timeUnits
            case units
            case warmupIterations
            case scalingFactor
            case maxDuration
            case maxIterations
            case thresholds
        }
        // swiftlint:enable nesting
    }
}

// This is an additional convenience duplicating the free standing function blackHole() for those cases where
// another module happens to define it, as we have a type clash between module name and type name and otherwise
// the user would need to do `import func Benchmark.blackHole` which isn't that obvious - thus this duplication.
public extension Benchmark {
    /// A function to foil compiler optimizations that would otherwise optimize out code you want to benchmark.
    ///
    /// The function wraps another object or function, does nothing, and returns.
    /// If you want to benchmark the time is takes to create an instance and you don't maintain a reference to it, the compiler may optimize it out entirely, thinking it is unused.
    /// To prevent the compiler from removing the code you want to measure, wrap the creation of the instance with `blackHole`.
    /// For example, the following code benchmarks the time it takes to create an instance of `Date`, and wraps the creation of the instance to prevent the compiler from optimizing it away:
    ///
    /// ```swift
    /// Benchmark("Foundation Date()",
    ///     configuration: .init(
    ///         metrics: [.throughput, .wallClock],
    ///         scalingFactor: .mega)
    /// ) { benchmark in
    ///     for _ in benchmark.scaledIterations {
    ///         Benchmark.blackHole(Date())
    ///     }
    /// }
    /// ```
    @_optimize(none) // Used after tip here: https://forums.swift.org/t/compiler-swallows-blackhole/64305/10 - see also https://github.com/apple/swift/commit/1fceeab71e79dc96f1b6f560bf745b016d7fcdcf
    static func blackHole(_: some Any) {}
}

// Wrapper for static properties for Swift 6 mode compatibility
@propertyWrapper
public struct ThreadSafeProperty<T> {
    private var value: T
    private let lock: NSLock

    public init(wrappedValue: T, lock: NSLock) {
        self.value = wrappedValue
        self.lock = lock
    }

    public var wrappedValue: T {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            value = newValue
        }
    }
}

// swiftlint:enable file_length identifier_name
