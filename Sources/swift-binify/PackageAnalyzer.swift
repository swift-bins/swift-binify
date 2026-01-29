import Foundation
import Cockle

/// Analyzes an SPM package by running `swift package dump-package`
struct PackageAnalyzer {

    func analyze(packagePath: URL) async throws -> PackageInfo {
        let shell = try makeSilentShell()

        try await shell.cd(packagePath.path)
        let output = try await shell.swift(package: (), "dump-package")

        guard let data = output.data(using: .utf8) else {
            throw AnalyzerError.commandFailed("Failed to read dump-package output")
        }

        let decoder = JSONDecoder()
        let dump = try decoder.decode(PackageDump.self, from: data)

        // Get available schemes from xcodebuild
        let availableSchemes = try await getAvailableSchemes(at: packagePath)

        return processPackageDump(dump, availableSchemes: availableSchemes)
    }

    // MARK: - Private Helpers

    private func makeSilentShell() throws -> Shell {
        try Shell(configuration: ShellConfiguration(
            standardErrorHandler: NoOutputPrinter(),
            standardOutputHandler: NoOutputPrinter()
        ))
    }

    private func getAvailableSchemes(at packagePath: URL) async throws -> Set<String> {
        let shell = try makeSilentShell()

        try await shell.cd(packagePath.path)
        let output = try await shell.execute(path: "/usr/bin/xcodebuild", args: ["-list"])

        return parseSchemes(from: output)
    }

    private func parseSchemes(from output: String) -> Set<String> {
        var schemes: Set<String> = []
        var inSchemesSection = false

        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "Schemes:" {
                inSchemesSection = true
                continue
            }
            if inSchemesSection {
                if trimmed.isEmpty || trimmed.contains(":") {
                    break
                }
                schemes.insert(trimmed)
            }
        }

        return schemes
    }

    private func processPackageDump(_ dump: PackageDump, availableSchemes: Set<String>) -> PackageInfo {
        let products = parseProducts(from: dump)
        let platformVersions = parsePlatformVersions(from: dump)
        let dependencies = parseDependencies(from: dump)
        let toolsVersion = dump.toolsVersion?._version ?? "5.9"
        let buildTargets = determineBuildTargets(products: products, availableSchemes: availableSchemes)

        return PackageInfo(
            name: dump.name,
            toolsVersion: toolsVersion,
            products: products,
            platformVersions: platformVersions,
            dependencies: dependencies,
            buildTargets: buildTargets,
            availableSchemes: availableSchemes
        )
    }

    private func parseProducts(from dump: PackageDump) -> [PackageInfo.Product] {
        dump.products.compactMap { product -> PackageInfo.Product? in
            guard let libraryType = product.type?.library else { return nil }

            // Check if explicitly static - skip those
            let isStatic = libraryType.contains("static")
            if isStatic { return nil }

            return PackageInfo.Product(
                name: product.name,
                targets: product.targets,
                isLibrary: true
            )
        }
    }

    private func parsePlatformVersions(from dump: PackageDump) -> [PlatformVersion] {
        if let platformDumps = dump.platforms, !platformDumps.isEmpty {
            return platformDumps.compactMap { p in
                guard let platform = PlatformKind(rawValue: p.platformName.lowercased()) else {
                    return nil
                }
                return PlatformVersion(platform: platform, version: p.version)
            }
        } else {
            // No platforms specified = supports all platforms
            // Default to macOS and iOS with reasonable minimums
            return [
                PlatformVersion(platform: .ios, version: "13.0"),
                PlatformVersion(platform: .macos, version: "10.15")
            ]
        }
    }

    private func parseDependencies(from dump: PackageDump) -> [PackageInfo.Dependency] {
        (dump.dependencies ?? []).compactMap { dep -> PackageInfo.Dependency? in
            guard let identity = dep.sourceControl?.first?.identity else { return nil }
            return PackageInfo.Dependency(identity: identity)
        }
    }

    private func determineBuildTargets(
        products: [PackageInfo.Product],
        availableSchemes: Set<String>
    ) -> [PackageInfo.BuildTarget] {
        var buildTargets: [PackageInfo.BuildTarget] = []
        var seenTargets: Set<String> = []

        for product in products {
            for targetName in product.targets {
                // Skip if we've already added this target
                guard !seenTargets.contains(targetName) else { continue }

                // Check if a scheme exists for this target
                guard availableSchemes.contains(targetName) else { continue }

                seenTargets.insert(targetName)
                buildTargets.append(PackageInfo.BuildTarget(
                    name: targetName,
                    productName: product.name
                ))
            }
        }

        return buildTargets
    }
}
