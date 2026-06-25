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
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Writes a diagnostic line to standard error.
///
/// Benchmark diagnostics must never go to stdout: a benchmark child process shares the parent's
/// stdout (fd 1) with machine-readable `--path stdout` output (JMH / histogram / influx encoders),
/// so a stray stdout line corrupts that output. Uses an unbuffered `write(2)` to match the command
/// plugin's stderr idiom and to interleave correctly with other diagnostics.
func writeToStandardError(_ message: String) {
    let line = message + "\n"
    line.withCString { cString in
        _ = write(STDERR_FILENO, cString, strlen(cString))
    }
}
