import Benchmark
import Foundation

struct BenchmarkJSON: Codable {
    var name: String
    var unit: String
    var value: Double
    var range: String?
    var extra: String?
}

extension BenchmarkTool {
    func convertToJSON(_ baseline: BenchmarkBaseline, polarity: BenchmarkMetric.Polarity = .prefersSmaller) throws -> String {
        var allBenchmarks: [BenchmarkJSON] = []

        baseline.targets.forEach { target in
            var keys = baseline.results.keys.sorted(by: { $0.name < $1.name })
            keys.removeAll(where: { $0.target != target })

            keys.forEach { test in
                if let results = baseline.results[test] {
                    results.forEach { result in
                        if polarity != result.metric.polarity {
                            return
                        }

                        let testName = test.name
                        let metricName = result.metric.description
                        let fullName = "\(testName) - \(metricName)"

                        let percentiles = result.statistics.percentiles(for: [80.0, 95.0, 99.0]).map { result.scale($0) }
                        let (p80, p95, p99) = (percentiles[0], percentiles[1], percentiles[2])

                        var range: String?
                        var extra: String?

                        let stdDeviation = result.statistics.histogram.stdDeviation
                        if stdDeviation > 0 {
                            //range = String(format: "± %.3f", stdDeviation)
                            if p80 != p95 {
                                extra = "80th percentile: \(p80)\n95th percentile: \(p95)"
                            }
                        }

                        let unit = result.metric.countable
                            ? Statistics.Units(result.timeUnits).description
                            : result.timeUnits.description

                        allBenchmarks.append(BenchmarkJSON(
                            name: fullName,
                            unit: unit,
                            value: Double(p99),
                            range: range,
                            extra: extra
                        ))
                    }
                }
            }
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(allBenchmarks)
        return String(data: jsonData, encoding: .utf8) ?? "[]"
    }

}
