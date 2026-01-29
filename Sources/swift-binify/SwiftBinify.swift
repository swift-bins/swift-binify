import ArgumentParser
import Foundation

@main
struct SwiftBinify: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Build Swift packages as dynamic xcframeworks",
        discussion: """
            Builds all products of a Swift package as dynamic library xcframeworks.

            Automatically detects supported platforms from Package.swift and builds
            for all of them. Simulators are always included for platforms that support them.

            Output goes to /tmp/swift-binify-dylibs/<package-name>/ with a generated
            Package.swift that can be used as a drop-in replacement.

            Usage in your project - just change:
                .package(url: "https://github.com/foo/bar", from: "1.0.0")
            To:
                .package(path: "/tmp/swift-binify-dylibs/bar")
            """,
        version: "1.0.0"
    )

    @Argument(help: "Path to the Swift package directory")
    var packagePath: String

    @Option(name: .long, help: "Build configuration (debug/release)")
    var configuration: String = "release"

    func run() async throws {
        let packageURL = resolvePackageURL()
        let packageIdentity = packageURL.lastPathComponent.lowercased()

        printHeader(packageURL: packageURL)

        let packageInfo = try await analyzePackage(at: packageURL)
        printAnalysisResults(packageInfo, identity: packageIdentity)

        guard !packageInfo.buildTargets.isEmpty else {
            Console.warning("No buildable targets found")
            return
        }

        let outputDir = Constants.outputDirectory(for: packageIdentity)
        let results = try await buildFrameworks(
            packageInfo: packageInfo,
            packageURL: packageURL,
            packageIdentity: packageIdentity
        )

        try generateOutputAndPrintResults(
            packageInfo: packageInfo,
            results: results,
            targetNames: packageInfo.buildTargets.map { $0.name },
            outputDir: outputDir
        )
    }

    // MARK: - Private Helpers

    private func resolvePackageURL() -> URL {
        URL(fileURLWithPath: packagePath).standardizedFileURL
    }

    private func printHeader(packageURL: URL) {
        Console.header("Swift Binify")
        Console.info("Package", packageURL.path)
        Console.blank()
    }

    private func analyzePackage(at packageURL: URL) async throws -> PackageInfo {
        Console.step("Analyzing package")
        let analyzer = PackageAnalyzer()
        return try await analyzer.analyze(packagePath: packageURL)
    }

    private func printAnalysisResults(_ packageInfo: PackageInfo, identity: String) {
        Console.info("Name", packageInfo.name)
        Console.info("Identity", identity)
        Console.info("Platforms", packageInfo.platforms.map { $0.displayName }.sorted().joined(separator: ", "))
        Console.info("Targets to build", packageInfo.buildTargets.map { $0.name }.joined(separator: ", "))

        if !packageInfo.dependencies.isEmpty {
            Console.info("Dependencies", packageInfo.dependencies.map { $0.identity }.joined(separator: ", "))
        }
        Console.blank()
    }

    private func buildFrameworks(
        packageInfo: PackageInfo,
        packageURL: URL,
        packageIdentity: String
    ) async throws -> [String: String] {
        let builder = XCFrameworkBuilder(
            packagePath: packageURL,
            packageName: packageIdentity,
            configuration: configuration,
            platforms: packageInfo.platforms,
            dependencies: packageInfo.dependencies
        )

        Console.buildStep("Building xcframeworks with Scipio")
        Console.blank()

        let targetNames = packageInfo.buildTargets.map { $0.name }
        return try await builder.buildAll(targets: targetNames)
    }

    private func generateOutputAndPrintResults(
        packageInfo: PackageInfo,
        results: [String: String],
        targetNames: [String],
        outputDir: URL
    ) throws {
        let succeeded = results.keys.sorted()
        let failed = targetNames.filter { !results.keys.contains($0) }

        printBuildResults(succeeded: succeeded, failed: failed, results: results)

        // Generate Package.swift wrapper
        if !succeeded.isEmpty {
            try generatePackageWrapper(packageInfo: packageInfo, succeeded: succeeded, outputDir: outputDir)
        }

        try printFinalStatus(succeeded: succeeded, failed: failed, outputDir: outputDir)
    }

    private func printBuildResults(succeeded: [String], failed: [String], results: [String: String]) {
        for target in succeeded {
            if let path = results[target] {
                Console.success(target, detail: path)
            }
        }

        for target in failed {
            Console.failure(target, reason: "not found in build output")
        }
        Console.blank()
    }

    private func generatePackageWrapper(
        packageInfo: PackageInfo,
        succeeded: [String],
        outputDir: URL
    ) throws {
        Console.generateStep("Generating Package.swift")
        let generator = PackageGenerator()
        try generator.generate(
            packageInfo: packageInfo,
            builtProducts: succeeded,
            outputDir: outputDir
        )
        Console.success("\(outputDir.path)/Package.swift")
        Console.blank()
    }

    private func printFinalStatus(succeeded: [String], failed: [String], outputDir: URL) throws {
        if failed.isEmpty {
            Console.done("Done! Built \(succeeded.count) framework(s)")
            Console.blank()
            Console.usageInstructions(outputPath: outputDir.path)
        } else if succeeded.isEmpty {
            Console.error("Failed! No frameworks were built")
            throw ExitCode.failure
        } else {
            Console.warning("Partial success: \(succeeded.count) succeeded, \(failed.count) not found")
            Console.info("Missing", failed.joined(separator: ", "))
            Console.blank()
            Console.usageInstructions(outputPath: outputDir.path)
        }
    }
}
