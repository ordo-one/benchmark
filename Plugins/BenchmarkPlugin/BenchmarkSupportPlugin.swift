#if swift(>=6.0)
import Foundation
#endif
import PackagePlugin

@main
struct PluginFactory: BuildToolPlugin {
    func createBuildCommands(
        context: PackagePlugin.PluginContext, target: PackagePlugin.Target
    ) async throws
        -> [PackagePlugin.Command]
    {
        guard let target = target as? SwiftSourceModuleTarget else { return [] }
        guard target.kind == .executable else { return [] }

        let tool = try context.tool(named: "BenchmarkBoilerplateGenerator")

        #if swift(>=6.0)
        guard target.directoryURL.deletingLastPathComponent().lastPathComponent == "Benchmarks" else { return [] }

        let swiftFile = context.pluginWorkDirectoryURL.appending(path: "__BenchmarkBoilerplate.swift")
        let inputFiles = target.sourceFiles.filter { $0.url.pathExtension == "swift" }.map(\.url)
        let outputFiles: [URL] = [swiftFile]
        let outputPath = swiftFile.path(percentEncoded: false)
        let executable = tool.url
        #else
        guard target.directory.removingLastComponent().lastComponent == "Benchmarks" else { return [] }

        let swiftFile = context.pluginWorkDirectory.appending("__BenchmarkBoilerplate.swift")
        let inputFiles = target.sourceFiles.filter { $0.path.extension == "swift" }.map(\.path)
        let outputFiles: [Path] = [swiftFile]
        let outputPath = swiftFile.string
        let executable = tool.path
        #endif

        let commandArgs: [String] = [
            "--target", target.name,
            "--output", outputPath,
        ]

        let command: Command = .buildCommand(
            displayName: "Generating plugin support files",
            executable: executable,
            arguments: commandArgs,
            inputFiles: inputFiles,
            outputFiles: outputFiles
        )

        return [command]
    }
}
