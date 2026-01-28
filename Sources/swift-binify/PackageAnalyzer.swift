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
        
        // Parse platforms - if none specified, default to macOS + iOS
        var platforms: Set<Platform> = []
        if let platformDumps = dump.platforms, !platformDumps.isEmpty {
            for p in platformDumps {
                if let platform = Platform(rawValue: p.platformName.lowercased()) {
                    platforms.insert(platform)
                }
            }
        } else {
            // No platforms specified = supports all platforms
            // Default to macOS and iOS for xcframework builds
            platforms = [.macos, .ios]
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
            platforms: platforms,
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

enum Platform: String, CaseIterable {
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
    
    var swiftPlatformDeclaration: String {
        switch self {
        case .ios: return ".iOS(.v13)"
        case .macos: return ".macOS(.v10_15)"
        case .tvos: return ".tvOS(.v13)"
        case .watchos: return ".watchOS(.v6)"
        case .visionos: return ".visionOS(.v1)"
        }
    }
}

struct PackageInfo {
    let name: String
    let toolsVersion: String
    let products: [Product]
    let platforms: Set<Platform>
    let dependencies: [Dependency]
    let buildTargets: [BuildTarget]
    let availableSchemes: Set<String>
    
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
