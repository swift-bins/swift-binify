import Foundation
import Cockle
import ScipioKit

/// Builds xcframeworks using Scipio
struct XCFrameworkBuilder {
    let packagePath: URL
    let packageName: String
    let configuration: String
    let platforms: Set<Platform>
    let dependencies: [PackageInfo.Dependency]

    /// Build all targets using Scipio, then copy only the ones we need
    func buildAll(targets: [String]) async throws -> [String: String] {
        let fileManager = FileManager.default
        let outputDir = Constants.outputDirectory(for: packageName)

        // Create output directory
        try fileManager.createDirectory(at: outputDir, withIntermediateDirectories: true)

        // Rewrite Package.swift to use local dependencies and force dynamic libraries
        let packageSwiftURL = packagePath.appendingPathComponent("Package.swift")
        let originalContent = try String(contentsOf: packageSwiftURL, encoding: .utf8)

        // Scipio output directory
        let scipioOutputDir = packagePath.appendingPathComponent("XCFrameworks")

        do {
            // Modify Package.swift
            var modifiedContent = rewriteDependencies(in: originalContent)
            modifiedContent = rewriteLibrariesToDynamic(in: modifiedContent)

            if modifiedContent != originalContent {
                try modifiedContent.write(to: packageSwiftURL, atomically: true, encoding: .utf8)
            }

            // Clean previous Scipio output
            try? fileManager.removeItem(at: scipioOutputDir)

            // Convert our platforms to Scipio platforms
            let scipioPlatforms: Set<Runner.Options.Platform> = Set(platforms.compactMap { $0.scipioPlatform })

            let runner = Runner(
                mode: .createPackage,
                options: .init(
                    baseBuildOptions: .init(
                        buildConfiguration: configuration == "debug" ? .debug : .release,
                        platforms: .specific(scipioPlatforms),
                        isSimulatorSupported: true,
                        isDebugSymbolsEmbedded: false,
                        frameworkType: .dynamic,
                        enableLibraryEvolution: true
                    ),
                    shouldOnlyUseVersionsFromResolvedFile: false,
                    frameworkCachePolicies: [],
                    resolvedPackagesCachePolicies: [],
                    overwrite: true,
                    verbose: false
                )
            )

            try await runner.run(packageDirectory: packagePath, frameworkOutputDir: .custom(scipioOutputDir))

            // Restore original Package.swift
            try originalContent.write(to: packageSwiftURL, atomically: true, encoding: .utf8)

            // Copy only the xcframeworks for the targets we want (not dependencies)
            let results = try copyBuiltFrameworks(
                targets: targets,
                from: scipioOutputDir,
                to: outputDir,
                fileManager: fileManager
            )

            // Cleanup Scipio output
            try? fileManager.removeItem(at: scipioOutputDir)

            return results

        } catch {
            // Always restore original Package.swift on error
            try? originalContent.write(to: packageSwiftURL, atomically: true, encoding: .utf8)
            throw error
        }
    }

    // MARK: - Private Helpers

    private func copyBuiltFrameworks(
        targets: [String],
        from scipioOutputDir: URL,
        to outputDir: URL,
        fileManager: FileManager
    ) throws -> [String: String] {
        var results: [String: String] = [:]

        for target in targets {
            let sourceXCFramework = scipioOutputDir.appendingPathComponent("\(target).xcframework")
            let destXCFramework = outputDir.appendingPathComponent("\(target).xcframework")

            if fileManager.fileExists(atPath: sourceXCFramework.path) {
                // Remove existing
                try? fileManager.removeItem(at: destXCFramework)
                // Copy
                try fileManager.copyItem(at: sourceXCFramework, to: destXCFramework)
                results[target] = destXCFramework.path
            }
        }

        return results
    }

    /// Rewrite .package(url:...) dependencies to use local paths
    private func rewriteDependencies(in content: String) -> String {
        var result = content

        for dep in dependencies {
            // Check if prebuilt version exists
            let prebuiltPath = "\(Constants.outputBasePath)/\(dep.identity)"
            guard FileManager.default.fileExists(atPath: prebuiltPath) else { continue }

            // Match .package(url: ".../<identity>" or .package(url: ".../<identity>.git"
            // with any version requirement after it
            let patterns = [
                // Match: .package(url: "...<identity>.git", ...)
                #"\.package\s*\(\s*url:\s*"[^"]*[/:]"# + NSRegularExpression.escapedPattern(for: dep.identity) + #"(?:\.git)?"[^)]*\)"#,
                // Match: .package(url: "...<identity>", ...)
                #"\.package\s*\(\s*url:\s*"[^"]*[/:]"# + NSRegularExpression.escapedPattern(for: dep.identity) + #""[^)]*\)"#,
            ]

            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                    let range = NSRange(result.startIndex..., in: result)
                    result = regex.stringByReplacingMatches(
                        in: result,
                        range: range,
                        withTemplate: ".package(path: \"\(prebuiltPath)\")"
                    )
                }
            }
        }

        return result
    }

    /// Rewrite .library products to be dynamic
    private func rewriteLibrariesToDynamic(in content: String) -> String {
        var result = content

        // Pattern to match .library(name: "...", targets: [...]) without an explicit type
        let pattern = #"\.library\s*\(\s*name:\s*("[^"]+")\s*,\s*targets:"#

        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: ".library(name: $1, type: .dynamic, targets:"
            )
        }

        // Also convert any explicit .static to .dynamic
        result = result.replacingOccurrences(of: "type: .static", with: "type: .dynamic")

        return result
    }
}

// MARK: - Platform Configuration

extension Platform {
    var scipioPlatform: Runner.Options.Platform? {
        switch self {
        case .ios: return .iOS
        case .macos: return .macOS
        case .tvos: return .tvOS
        case .watchos: return .watchOS
        case .visionos: return .visionOS
        }
    }
}
