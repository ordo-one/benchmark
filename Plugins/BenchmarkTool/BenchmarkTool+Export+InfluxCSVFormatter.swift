//
// Copyright (c) 2023 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

import Benchmark
import Foundation

struct ExportableBenchmark: Codable {
    var benchmarkMachine: BenchmarkMachine
    var target: String
    var benchmarks: [TestData]
}

struct TestData: Codable {
    var test: String
    var iterations: Int
    var warmupIterations: Int
    var data: [TestMetricData]
}

struct TestMetricData: Codable {
    var metric: String
    var units: String
    var average: Double
    var metricsdata: [Int]
}

class InfluxCSVFormatter {
    let exportableBenchmark: ExportableBenchmark
    var finalFileFormat: String

    init(exportableBenchmark: ExportableBenchmark) {
        self.exportableBenchmark = exportableBenchmark
        finalFileFormat = ""
    }

    /// Takes in benchmark data and returns a csv formatted for influxDB
    /// - Returns: CSV string representation
    func influxCSVFormat(header: Bool) -> String {
        let machine = exportableBenchmark.benchmarkMachine
        let hostName = machine.hostname
            .replacingOccurrences(of: " ", with: "-")
        let processorType = machine.processorType
            .replacingOccurrences(of: " ", with: "-")
        let kernelVersion = machine.kernelVersion
            .replacingOccurrences(of: " ", with: "-")
        let processors = machine.processors
        let memory = machine.memory

        if header {
            let dataTypeHeader =
                "#datatype tag,tag,tag,tag,tag,tag,tag,tag,tag,double,double,double,long,long,dateTime\n"
            finalFileFormat.append(dataTypeHeader)
            let headers =
                "measurement,hostName,processoryType,processors,memory,kernelVersion,metric,unit,test,percentile,value,test_average,iterations,warmup_iterations,time\n"
            finalFileFormat.append(headers)
        }

        for testData in exportableBenchmark.benchmarks {
            let testName = testData.test
            let iterations = testData.iterations
            let warmup_iterations = testData.warmupIterations
            let percentiles = Statistics.defaultPercentilesToCalculate
            for granularData in testData.data {
                let metric = granularData.metric
                    .replacingOccurrences(of: " ", with: "")
                let units = granularData.units
                let average = granularData.average
                for (percentile, dataTableValue) in zip(percentiles, granularData.metricsdata) {
                    let time = ISO8601DateFormatter().string(from: Date())
                    let dataLine =
                        "\(exportableBenchmark.target),\(hostName),\(processorType),\(processors),\(memory),\(kernelVersion),\(metric),\(units),\(testName),\(percentile),\(dataTableValue),\(average),\(iterations),\(warmup_iterations),\(time)\n"
                    finalFileFormat.append(dataLine)
                }
            }
        }

        return finalFileFormat
    }

    func appendMachineInfo() {
        let machine = exportableBenchmark.benchmarkMachine

        let hostName = machine.hostname
            .replacingOccurrences(of: " ", with: "-")
        let processorType = machine.processorType
            .replacingOccurrences(of: " ", with: "-")
        let kernelVersion = machine.kernelVersion
            .replacingOccurrences(of: " ", with: "-")

        let hostNameConstant = "#constant tag,hostName,\(hostName)\n"
        let processorConstant = "#constant tag,processors,\(machine.processors)\n"
        let processorTypeConstant = "#constant tag,processorType,\(processorType)\n"
        let memoryConstant = "#constant tag,memory,\(machine.memory)\n"
        let kernelVersionConstant = "#constant tag,kernelVersion,\(kernelVersion)\n"

        finalFileFormat.append(hostNameConstant)
        finalFileFormat.append(processorConstant)
        finalFileFormat.append(processorTypeConstant)
        finalFileFormat.append(memoryConstant)
        finalFileFormat.append(kernelVersionConstant)
    }
}

extension BenchmarkTool {
    func convertToInflux(_ baseline: BenchmarkBaseline) throws -> String {
        var outputString = ""
        var printHeader = true

        baseline.targets.forEach { key in
            let exportStruct = saveExportableResults(
                BenchmarkBaseline(
                    baselineName: baseline.baselineName,
                    machine: benchmarkMachine(),
                    results: baseline.results
                ),
                target: key
            )

            let formatter = InfluxCSVFormatter(exportableBenchmark: exportStruct)
            outputString += formatter.influxCSVFormat(header: printHeader)
            if printHeader {
                printHeader = false
            }
        }

        return outputString
    }

    func saveExportableResults(_ benchmarks: BenchmarkBaseline, target: String) -> ExportableBenchmark {
        var keys = benchmarks.results.keys.sorted(by: { $0.name < $1.name })
        var testList: [TestData] = []
        keys.removeAll(where: { $0.target != target })

        keys.forEach { test in
            if let value = benchmarks.results[test] {
                var allResults: [BenchmarkResult] = []
                value.forEach { result in
                    allResults.append(result)
                }

                allResults.sort(by: { $0.metric.description < $1.metric.description })

                var benchmarkResultData: [TestMetricData] = []
                var iterations = 0
                var warmupIterations = 0
                var cleanedTestName = test.name

                // adds quotes around test names that contain a comma.
                // This helps avoid parsing issues on the exported CSV file
                if cleanedTestName.contains(",") {
                    cleanedTestName = "\"\(cleanedTestName)\""
                }
                allResults.forEach { results in

                    benchmarkResultData.append(
                        processBenchmarkResult(
                            test: results,
                            testName: cleanedTestName
                        )
                    )

                    iterations = results.statistics.measurementCount
                    warmupIterations = results.warmupIterations
                }

                testList.append(
                    TestData(
                        test: cleanedTestName,
                        iterations: iterations,
                        warmupIterations: warmupIterations,
                        data: benchmarkResultData
                    )
                )
            }
        }

        return ExportableBenchmark(
            benchmarkMachine: benchmarks.machine,
            target: target,
            benchmarks: testList
        )
    }

    func processBenchmarkResult(
        test: BenchmarkResult,
        testName _: String
    ) -> TestMetricData {
        var testData: [Int] = []

        let percentiles = test.statistics

        percentiles.percentiles()
            .forEach { result in
                testData.append(result)
            }

        let totalValue = Double(testData.reduce(0, +))
        let totalCount = Double(testData.count)
        let averageValue = (totalValue / totalCount)

        return TestMetricData(
            metric: test.metric.description,
            units: test.unitDescription,
            average: averageValue,
            metricsdata: testData
        )
    }
}
