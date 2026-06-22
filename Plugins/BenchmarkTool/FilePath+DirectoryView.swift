//
// Copyright (c) 2022 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

import SystemPackage

#if canImport(Darwin)
import Darwin
typealias DirectoryStreamPointer = UnsafeMutablePointer<DIR>?
#elseif canImport(Glibc)
import Glibc
typealias DirectoryStreamPointer = OpaquePointer?
#elseif canImport(Musl)
import Musl
typealias DirectoryStreamPointer = OpaquePointer?
#else
#error("Unsupported Platform")
#endif

/// Extends FilePath with basic directory iteration capabilities
public extension FilePath {
    /// `DirectoryView` provides an iteratable sequence of the contents of a directory referenced by a `FilePath`
    struct DirectoryView {
        var directoryStreamPointer: DirectoryStreamPointer = nil
        var path: FilePath

        /// Initializer
        /// - Parameter path: The file system path to provide directory entries for, should reference a directory
        init(path pathName: FilePath) {
            path = pathName
            path.withPlatformString {
                directoryStreamPointer = opendir($0)
            }
        }
    }

    var directoryEntries: DirectoryView { DirectoryView(path: self) }
}

extension FilePath.DirectoryView: IteratorProtocol, Sequence {
    public mutating func next() -> FilePath? {
        guard let streamPointer = directoryStreamPointer else {
            return nil
        }

        guard let directoryEntry = readdir(streamPointer) else {
            closedir(streamPointer)
            directoryStreamPointer = nil
            return nil
        }

        let fileName = withUnsafePointer(to: &directoryEntry.pointee.d_name) { pointer -> FilePath.Component in
            pointer.withMemoryRebound(
                to: CChar.self,
                capacity: MemoryLayout.size(ofValue: directoryEntry.pointee.d_name)
            ) {
                guard let fileName = FilePath.Component(platformString: $0) else {
                    fatalError("Could not initialize FilePath.Component from platformString \(String(cString: $0))")
                }
                return fileName
            }
        }
        return path.appending(fileName)
    }
}
