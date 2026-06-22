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
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#else
#error("Unsupported Platform")
#endif

public extension FilePath {
    func createSubPath(_ subPath: FilePath) {
        var creationPath = self

        subPath.components.forEach { c in
            creationPath.append(c)

            do {
                let fd = try FileDescriptor.open(
                    creationPath,
                    .readOnly,
                    options: [.directory],
                    permissions: .ownerReadWrite
                )

                do {
                    try fd.close()
                } catch { print("failed close directory") }
            } catch {
                switch errno {
                case ENOENT: // doesn't exist, let's create it
                    if mkdir(creationPath.string, S_IRWXU | S_IRWXG | S_IRWXO) == -1 {
                        if errno == EPERM {
                            print("Lacking permissions to write to \(creationPath)")
                            print("Give benchmark plugin permissions by running with e.g.:")
                            print("")
                            print("swift package --allow-writing-to-package-directory benchmark baseline update")
                            print("")
                        }
                        print("Failed to create directory at [\(creationPath)], errno = [\(errno)]")
                        return
                    }

                default:
                    print("Failed to handle file \(creationPath), errno = [\(errno)]")
                }
            }
        }
    }
}
