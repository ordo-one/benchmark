//
// Copyright (c) 2022 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

// Getting running machine configuration information

import Benchmark

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#else
#error("Unsupported Platform")
#endif

extension BenchmarkTool {
    func benchmarkMachine() -> BenchmarkMachine {
        let processors = sysconf(Int32(_SC_NPROCESSORS_ONLN))
        let memory = sysconf(Int32(_SC_PHYS_PAGES)) / 1_024 * sysconf(Int32(_SC_PAGESIZE)) / (1_024 * 1_024) // avoid overflow

        var uuname = utsname()
        _ = uname(&uuname)

        let sizeNodename = MemoryLayout.size(ofValue: uuname.nodename)
        let nodeName = withUnsafePointer(to: &uuname.nodename) {
            $0.withMemoryRebound(to: UInt8.self, capacity: sizeNodename) {
                String(cString: $0)
            }
        }

        let sizeMachine = MemoryLayout.size(ofValue: uuname.machine)
        let machine = withUnsafePointer(to: &uuname.machine) {
            $0.withMemoryRebound(to: UInt8.self, capacity: sizeMachine) {
                String(cString: $0)
            }
        }
        /* // We don't use these currently
         let sysnameSize = MemoryLayout.size(ofValue: uuname.sysname)
         let sysname = withUnsafePointer(to: &uuname.sysname) {
             $0.withMemoryRebound(to: UInt8.self, capacity: sysnameSize) {
                 String(cString: $0)
             }
         }
        
         let releaseSize = MemoryLayout.size(ofValue: uuname.release)
         let release = withUnsafePointer(to: &uuname.release) {
             $0.withMemoryRebound(to: UInt8.self, capacity: releaseSize) {
                 String(cString: $0)
             }
         }
         */
        // This is the full kernel version string
        let versionSize = MemoryLayout.size(ofValue: uuname.version)
        let version = withUnsafePointer(to: &uuname.version) {
            $0.withMemoryRebound(to: UInt8.self, capacity: versionSize) {
                String(cString: $0)
            }
        }

        return BenchmarkMachine(
            hostname: nodeName,
            processors: processors,
            processorType: machine,
            memory: memory,
            kernelVersion: version
        )
    }
}
