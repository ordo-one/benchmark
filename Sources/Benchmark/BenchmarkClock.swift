// Copyright 2002 Ordo One AB
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0

// An implementation of a clock suitable for benchmarking using clock_gettime_nsec_np() on macOS
// which is ~2-3 x less overhead.

// swiftlint:disable identifier_name

// Largely adopted by Swift's ContinuousClock
// https://github.com/apple/swift/blob/48987de3d3ab228eed4867949795c188759df234/stdlib/public/Concurrency/ContinuousClock.swift#L49

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#else
#error("Unsupported Platform")
#endif

@_documentation(visibility: internal)
public struct BenchmarkClock {
    /// A continuous point in time used for `BenchmarkClock`.
    public struct Instant: Codable, Sendable {
        internal var _value: Swift.Duration

        //        internal init(_value: Swift.Duration) {
        //            self._value = _value
        //        }
    }

    public init() {}
}

@_documentation(visibility: internal)
public extension Clock where Self == BenchmarkClock {
    /// A clock that measures time that always increments but does not stop
    /// incrementing while the system is asleep.
    ///
    ///       try await Task.sleep(until: .now + .seconds(3), clock: .continuous)
    ///
    static var internalUTC: BenchmarkClock { BenchmarkClock() }
}

@_documentation(visibility: internal)
extension BenchmarkClock: Clock {
    /// The current continuous instant.
    public var now: BenchmarkClock.Instant {
        BenchmarkClock.now
    }

    /// The minimum non-zero resolution between any two calls to `now`.
    public var minimumResolution: Swift.Duration {
        #if canImport(Darwin)
        return Duration.nanoseconds(1)
        #elseif os(Linux)
        var resolution = timespec()

        let result = clock_getres(CLOCK_BOOTTIME, &resolution)

        guard result == 0 else {
            fatalError("Failed to get clock resolution in clock_getres(), errno = \(errno)")
        }

        let seconds = Int64(resolution.tv_sec)
        let attoseconds = Int64(resolution.tv_nsec) * 1_000_000_000

        return Duration(secondsComponent: seconds, attosecondsComponent: attoseconds)
        #else
        #error("Unsupported Platform")
        #endif
    }

    /// The current continuous instant.
    public static var now: BenchmarkClock.Instant {
        #if canImport(Darwin)
        let nanos = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) // to get ns resolution on macOS

        let seconds: UInt64 = nanos / 1_000_000_000
        let attoseconds: UInt64 = (nanos % 1_000_000_000) * 1_000_000_000
        return BenchmarkClock.Instant(
            _value: Duration(
                secondsComponent: Int64(seconds),
                attosecondsComponent: Int64(attoseconds)
            )
        )
        #elseif os(Linux)
        var timespec = timespec()
        let result = clock_gettime(CLOCK_BOOTTIME, &timespec)

        guard result == 0 else {
            fatalError("Failed to get current time in clock_gettime(), errno = \(errno)")
        }
        let seconds = Int64(timespec.tv_sec)
        let attoseconds = Int64(timespec.tv_nsec) * 1_000_000_000

        return BenchmarkClock.Instant(
            _value: Duration(
                secondsComponent: Int64(seconds),
                attosecondsComponent: Int64(attoseconds)
            )
        )
        #else
        #error("Unsupported Platform")
        #endif
    }

    /// Suspend task execution until a given deadline within a tolerance.
    /// If no tolerance is specified then the system may adjust the deadline
    /// to coalesce CPU wake-ups to more efficiently process the wake-ups in
    /// a more power efficient manner.
    ///
    /// If the task is canceled before the time ends, this function throws
    /// `CancellationError`.
    ///
    /// This function doesn't block the underlying thread.
    public func sleep(
        until deadline: Instant,
        tolerance: Swift.Duration? = nil
    ) async throws {
        try await Task.sleep(until: deadline, tolerance: tolerance, clock: .internalUTC)
    }
}

@_documentation(visibility: internal)
extension BenchmarkClock.Instant: InstantProtocol {
    public static var now: BenchmarkClock.Instant { BenchmarkClock.now }

    public func advanced(by duration: Swift.Duration) -> BenchmarkClock.Instant {
        BenchmarkClock.Instant(_value: _value + duration)
    }

    public func duration(to other: BenchmarkClock.Instant) -> Swift.Duration {
        other._value - _value
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(_value)
    }

    public static func == (
        _ lhs: BenchmarkClock.Instant,
        _ rhs: BenchmarkClock.Instant
    ) -> Bool {
        lhs._value == rhs._value
    }

    public static func < (
        _ lhs: BenchmarkClock.Instant,
        _ rhs: BenchmarkClock.Instant
    ) -> Bool {
        lhs._value < rhs._value
    }

    @inlinable
    public static func + (
        _ lhs: BenchmarkClock.Instant,
        _ rhs: Swift.Duration
    ) -> BenchmarkClock.Instant {
        lhs.advanced(by: rhs)
    }

    @inlinable
    public static func += (
        _ lhs: inout BenchmarkClock.Instant,
        _ rhs: Swift.Duration
    ) {
        lhs = lhs.advanced(by: rhs)
    }

    @inlinable
    public static func - (
        _ lhs: BenchmarkClock.Instant,
        _ rhs: Swift.Duration
    ) -> BenchmarkClock.Instant {
        lhs.advanced(by: .zero - rhs)
    }

    @inlinable
    public static func -= (
        _ lhs: inout BenchmarkClock.Instant,
        _ rhs: Swift.Duration
    ) {
        lhs = lhs.advanced(by: .zero - rhs)
    }

    @inlinable
    public static func - (
        _ lhs: BenchmarkClock.Instant,
        _ rhs: BenchmarkClock.Instant
    ) -> Swift.Duration {
        rhs.duration(to: lhs)
    }
}

@_documentation(visibility: internal)
public extension Duration {
    func nanoseconds() -> Int64 {
        (components.seconds * 1_000_000_000) + (components.attoseconds / 1_000_000_000)
    }
}
// swiftlint:enable identifier_name
