import ArgumentParser
import Foundation

struct BuildCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
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
            """
    )

    @Argument(help: "Path to the Swift package directory")
    var packagePath: String

    @Option(name: .long, help: "Build configuration (debug/release)")
    var configuration: String = "release"

    @Option(name: .long, help: "Output mode: 'local' for path-based targets, 'release' for URL-based")
    var outputMode: OutputMode = .local

    @Option(name: .long, help: "Base URL for release assets (required for release mode)")
    var releaseUrlBase: String?

    @Option(name: .long, help: "Version tag for release URLs (required for release mode)")
    var tag: String?

    @Option(name: .long, help: "Source repo URL for README generation (required for release mode)")
    var sourceRepo: String?

    @Option(name: .long, help: "Binary repo URL for README generation (required for release mode)")
    var binaryRepo: String?

    @Flag(name: .long, help: "Whether binary repo uses owner_name format (affects README)")
    var requiresOwnerPrefix: Bool = false

    @Flag(name: .long, help: "Disable library evolution (builds are tied to a specific Swift version)")
    var noLibraryEvolution: Bool = false

    @Option(name: .long, help: "Swift version tag (e.g. '6.2') — required when --no-library-evolution is set")
    var swiftVersionTag: String?

    func run() async throws {
        if outputMode == .release {
            guard let _ = releaseUrlBase else {
                Console.error("--release-url-base is required for release mode")
                throw ExitCode.failure
            }
            guard let _ = tag else {
                Console.error("--tag is required for release mode")
                throw ExitCode.failure
            }
            guard let _ = sourceRepo else {
                Console.error("--source-repo is required for release mode")
                throw ExitCode.failure
            }
            guard let _ = binaryRepo else {
                Console.error("--binary-repo is required for release mode")
                throw ExitCode.failure
            }
        }

        if noLibraryEvolution {
            guard let _ = swiftVersionTag else {
                Console.error("--swift-version-tag is required when --no-library-evolution is set")
                throw ExitCode.failure
            }
        }

        let packageURL = resolvePackageURL()
        let packageIdentity = packageURL.lastPathComponent

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
        let enableEvolution = !noLibraryEvolution
        let builder = XCFrameworkBuilder(
            packagePath: packageURL,
            packageName: packageIdentity,
            configuration: configuration,
            platforms: packageInfo.platforms,
            dependencies: packageInfo.dependencies,
            enableLibraryEvolution: enableEvolution,
            swiftVersionTag: swiftVersionTag
        )

        if noLibraryEvolution {
            Console.buildStep("Building xcframeworks with Scipio (no library evolution, swift-\(swiftVersionTag!))")
        } else {
            Console.buildStep("Building xcframeworks with Scipio")
        }
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

        var zippedFrameworks: [ZippedFramework] = []
        if outputMode == .release && !succeeded.isEmpty {
            Console.step("Zipping xcframeworks")
            let zipper = XCFrameworkZipper()
            if let versionTag = swiftVersionTag {
                let versionedDir = Constants.versionedOutputDirectory(
                    for: outputDir.lastPathComponent,
                    swiftVersion: versionTag
                )
                zippedFrameworks = try zipper.zipAll(
                    in: versionedDir,
                    targetNames: succeeded,
                    zipOutputDir: outputDir,
                    swiftVersionTag: versionTag
                )
            } else {
                zippedFrameworks = try zipper.zipAll(in: outputDir, targetNames: succeeded)
            }
            Console.blank()
        }

        if !succeeded.isEmpty {
            try generatePackageWrapper(
                packageInfo: packageInfo,
                succeeded: succeeded,
                outputDir: outputDir,
                zippedFrameworks: zippedFrameworks
            )
        }

        if outputMode == .release, !succeeded.isEmpty {
            try generateReadme(packageInfo: packageInfo, outputDir: outputDir)
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
        outputDir: URL,
        zippedFrameworks: [ZippedFramework]
    ) throws {
        let generator = PackageGenerator()

        let releaseConfig: PackageGenerator.ReleaseConfig?
        if outputMode == .release, let urlBase = releaseUrlBase, let version = tag {
            releaseConfig = PackageGenerator.ReleaseConfig(
                urlBase: urlBase,
                tag: version,
                zippedFrameworks: zippedFrameworks,
                swiftVersionTag: swiftVersionTag
            )
        } else {
            releaseConfig = nil
        }

        if noLibraryEvolution, let versionTag = swiftVersionTag {
            Console.generateStep("Generating versioned Package manifests")
            try generator.generateVersionedManifest(
                packageInfo: packageInfo,
                builtProducts: succeeded,
                outputDir: outputDir,
                swiftVersionTag: versionTag,
                releaseConfig: releaseConfig
            )
        } else {
            Console.generateStep("Generating Package.swift")
            try generator.generate(
                packageInfo: packageInfo,
                builtProducts: succeeded,
                outputDir: outputDir,
                releaseConfig: releaseConfig
            )
            Console.success("\(outputDir.path)/Package.swift")
        }
        Console.blank()
    }

    private func generateReadme(packageInfo: PackageInfo, outputDir: URL) throws {
        guard let sourceRepoURL = sourceRepo,
              let binaryRepoURL = binaryRepo,
              let version = tag else {
            return
        }

        let sourceOwner = parseOwner(from: sourceRepoURL) ?? "unknown"

        Console.generateStep("Generating README.md")
        let generator = ReadmeGenerator()
        let config = ReadmeGenerator.Config(
            sourceRepoURL: sourceRepoURL,
            binaryRepoURL: binaryRepoURL,
            packageName: packageInfo.name,
            sourceOwner: sourceOwner,
            tag: version,
            requiresOwnerPrefix: requiresOwnerPrefix,
            noLibraryEvolution: noLibraryEvolution
        )

        try generator.write(config: config, to: outputDir)
        Console.success("\(outputDir.path)/README.md")
        Console.blank()
    }

    private func parseOwner(from url: String) -> String? {
        let pattern = #"github\.com[/:]([^/]+)/"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
              let ownerRange = Range(match.range(at: 1), in: url) else {
            return nil
        }
        return String(url[ownerRange])
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
