import Foundation
import Cockle

/// Analyzes an SPM package by running `swift package dump-package`
struct PackageAnalyzer {
    
    func analyze(packagePath: URL) async throws -> PackageInfo {
        let shell = try Shell(configuration: ShellConfiguration(
            standardErrorHandler: NoOutputPrinter(),
            standardOutputHandler: NoOutputPrinter()
        ))
        
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
    
    private func getAvailableSchemes(at packagePath: URL) async throws -> Set<String> {
        let shell = try Shell(configuration: ShellConfiguration(
            standardErrorHandler: NoOutputPrinter(),
            standardOutputHandler: NoOutputPrinter()
        ))
        
        try await shell.cd(packagePath.path)
        let output = try await shell.execute(path: "/usr/bin/xcodebuild", args: ["-list"])
        
        // Parse schemes from output
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
        // Parse products, detecting static vs dynamic
        let products = dump.products.compactMap { product -> PackageInfo.Product? in
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
        
        // Parse platforms with their versions
        var platformVersions: [PlatformVersion] = []
        if let platformDumps = dump.platforms, !platformDumps.isEmpty {
            for p in platformDumps {
                if let platform = PlatformKind(rawValue: p.platformName.lowercased()) {
                    platformVersions.append(PlatformVersion(platform: platform, version: p.version))
                }
            }
        } else {
            // No platforms specified = supports all platforms
            // Default to macOS and iOS with reasonable minimums
            platformVersions = [
                PlatformVersion(platform: .ios, version: "13.0"),
                PlatformVersion(platform: .macos, version: "10.15")
            ]
        }
        
        // Parse external dependencies
        let dependencies = (dump.dependencies ?? []).compactMap { dep -> PackageInfo.Dependency? in
            guard let identity = dep.sourceControl?.first?.identity else { return nil }
            return PackageInfo.Dependency(identity: identity)
        }
        
        // Parse tools version
        let toolsVersion = dump.toolsVersion?._version ?? "5.9"
        
        // Determine what to build: unique targets that have available schemes
        // and are referenced by non-static library products
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
}

enum AnalyzerError: Error, LocalizedError {
    case commandFailed(String)
    case parseError(String)
    
    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message
        case .parseError(let message):
            return "Parse error: \(message)"
        }
    }
}

// MARK: - JSON Models

struct PackageDump: Codable {
    let name: String
    let products: [ProductDump]
    let platforms: [PlatformDump]?
    let dependencies: [DependencyDump]?
    let toolsVersion: ToolsVersionDump?
}

struct ProductDump: Codable {
    let name: String
    let targets: [String]
    let type: ProductTypeDump?
}

struct ProductTypeDump: Codable {
    let library: [String]?
    
    var isLibrary: Bool {
        library != nil
    }
}

struct PlatformDump: Codable {
    let platformName: String
    let version: String
}

struct DependencyDump: Codable {
    let sourceControl: [SourceControlDump]?
}

struct SourceControlDump: Codable {
    let identity: String
}

struct ToolsVersionDump: Codable {
    let _version: String?
}

// MARK: - Package Info

enum PlatformKind: String, CaseIterable {
    case ios
    case macos
    case tvos
    case watchos
    case visionos
    
    var displayName: String {
        switch self {
        case .ios: return "iOS"
        case .macos: return "macOS"
        case .tvos: return "tvOS"
        case .watchos: return "watchOS"
        case .visionos: return "visionOS"
        }
    }
    
    var swiftPlatformName: String {
        switch self {
        case .ios: return ".iOS"
        case .macos: return ".macOS"
        case .tvos: return ".tvOS"
        case .watchos: return ".watchOS"
        case .visionos: return ".visionOS"
        }
    }
}

struct PlatformVersion {
    let platform: PlatformKind
    let version: String
    
    /// Converts version like "12.0" to Swift declaration like ".iOS(.v12)"
    var swiftDeclaration: String {
        let versionEnum = versionToEnum(version)
        return "\(platform.swiftPlatformName)(\(versionEnum))"
    }
    
    private func versionToEnum(_ version: String) -> String {
        // Convert "12.0" -> ".v12", "13.4" -> ".v13_4", "10.15" -> ".v10_15"
        let parts = version.split(separator: ".").map(String.init)
        
        if parts.count >= 2 {
            let major = parts[0]
            let minor = parts[1]
            
            if minor == "0" {
                return ".v\(major)"
            } else {
                return ".v\(major)_\(minor)"
            }
        } else if parts.count == 1 {
            return ".v\(parts[0])"
        }
        
        return ".v\(version.replacingOccurrences(of: ".", with: "_"))"
    }
}

// Keep Platform as an alias for compatibility with XCFrameworkBuilder
typealias Platform = PlatformKind

struct PackageInfo {
    let name: String
    let toolsVersion: String
    let products: [Product]
    let platformVersions: [PlatformVersion]
    let dependencies: [Dependency]
    let buildTargets: [BuildTarget]
    let availableSchemes: Set<String>
    
    /// Convenience to get just the platform kinds (for Scipio)
    var platforms: Set<PlatformKind> {
        Set(platformVersions.map { $0.platform })
    }
    
    struct Product {
        let name: String
        let targets: [String]
        let isLibrary: Bool
    }
    
    struct Dependency {
        let identity: String
    }
    
    /// A target that should be built (has an available scheme)
    struct BuildTarget {
        let name: String        // The scheme/target name to build
        let productName: String // The product name for the output xcframework
    }
}
