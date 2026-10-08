//
// Copyright (c) 2026 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
@preconcurrency import Glibc
#elseif canImport(Musl)
@preconcurrency import Musl
#endif

/// Symbol demangler for Swift and C++ (Itanium) manglings, resolved
/// dynamically at first use.
///
/// `swift_demangle` is an unofficial runtime entry point and
/// `__cxa_demangle` lives in libc++abi/libstdc++: resolving both via `dlsym`
/// (rather than declaring them with `@_silgen_name`) calls them through
/// proper C-convention function pointers and turns "this process doesn't
/// export it" (static-musl configurations, future runtimes) into a graceful
/// fallback instead of a link failure.
@_documentation(visibility: internal)
public enum SymbolDemangler {
    private typealias SwiftDemangleFunction = @convention(c) (
        _ mangledName: UnsafePointer<UInt8>?,
        _ mangledNameLength: Int,
        _ outputBuffer: UnsafeMutablePointer<UInt8>?,
        _ outputBufferSize: UnsafeMutablePointer<Int>?,
        _ flags: UInt32
    ) -> UnsafeMutablePointer<CChar>?

    private typealias CxaDemangleFunction = @convention(c) (
        _ mangledName: UnsafePointer<CChar>?,
        _ outputBuffer: UnsafeMutablePointer<CChar>?,
        _ length: UnsafeMutablePointer<Int>?,
        _ status: UnsafeMutablePointer<Int32>?
    ) -> UnsafeMutablePointer<CChar>?

    private static let swiftDemangleFunction: SwiftDemangleFunction? = {
        guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "swift_demangle") else {
            return nil
        }
        return unsafeBitCast(symbol, to: SwiftDemangleFunction.self)
    }()

    private static let cxaDemangleFunction: CxaDemangleFunction? = {
        guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "__cxa_demangle") else {
            return nil
        }
        return unsafeBitCast(symbol, to: CxaDemangleFunction.self)
    }()

    /// Returns the demangled form of a Swift- or C++-mangled name, or nil
    /// when the name is no known mangling or the demangler for it is
    /// unavailable in this process.
    public static func demangle(_ mangled: String) -> String? {
        // Itanium C++ mangling ("_Z...", or "__Z..." with the extra
        // assembler underscore) — libswiftCore's C++ internals and libobjc
        // show up like this; swift_demangle refuses them.
        if mangled.hasPrefix("_Z") {
            return cxaDemangle(mangled)
        }
        if mangled.hasPrefix("__Z") {
            return cxaDemangle(String(mangled.dropFirst()))
        }
        return swiftDemangle(mangled)
    }

    private static func swiftDemangle(_ mangled: String) -> String? {
        guard let swiftDemangleFunction else {
            return nil
        }
        return mangled.withCString { cString in
            let length = strlen(cString)
            let bytes = UnsafeRawPointer(cString).assumingMemoryBound(to: UInt8.self)
            guard let demangled = swiftDemangleFunction(bytes, length, nil, nil, 0) else {
                return nil
            }
            // The runtime allocates the buffer with malloc when no output
            // buffer is supplied; releasing it with free keeps the
            // allocator pairing exact.
            defer { free(demangled) }
            return String(cString: demangled)
        }
    }

    private static func cxaDemangle(_ mangled: String) -> String? {
        guard let cxaDemangleFunction else {
            return nil
        }
        return mangled.withCString { cString in
            var status: Int32 = 0
            guard let demangled = cxaDemangleFunction(cString, nil, nil, &status), status == 0 else {
                return nil
            }
            defer { free(demangled) }
            return String(cString: demangled)
        }
    }
}
