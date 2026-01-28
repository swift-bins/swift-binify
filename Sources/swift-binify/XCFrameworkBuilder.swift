import Foundation
import Cockle

/// Builds xcframeworks using xcodebuild
struct XCFrameworkBuilder {
    let packagePath: URL
    let packageName: String
    let configuration: String
    let platforms: Set<Platform>
    let dependencies: [PackageInfo.Dependency]
    
    private let dylibsPath = "/tmp/swift-binify-dylibs"
    
    /// Build a scheme as a dynamic xcframework
    /// - Parameters:
    ///   - scheme: The xcodebuild scheme name to build
    ///   - outputName: The name for the output xcframework
    func build(scheme: String, outputName: String) async throws -> String {
        let fileManager = FileManager.default
        
        let outputDir = URL(fileURLWithPath: dylibsPath).appendingPathComponent(packageName)
        
        // Create output directory
        try fileManager.createDirectory(at: outputDir, withIntermediateDirectories: true)
        
        // Build directory for intermediate artifacts
        let buildDir = packagePath.appendingPathComponent(".build/xcframework-build")
        try? fileManager.removeItem(at: buildDir)
        try fileManager.createDirectory(at: buildDir, withIntermediateDirectories: true)
        
        // Rewrite Package.swift to use local dependencies and force dynamic libraries
        let packageSwiftURL = packagePath.appendingPathComponent("Package.swift")
        let originalContent = try String(contentsOf: packageSwiftURL, encoding: .utf8)
        
        do {
            // Modify Package.swift
            var modifiedContent = rewriteDependencies(in: originalContent)
            modifiedContent = rewriteLibrariesToDynamic(in: modifiedContent)
            
            if modifiedContent != originalContent {
                try modifiedContent.write(to: packageSwiftURL, atomically: true, encoding: .utf8)
            }
            
            // Build for each supported platform
            var frameworkPaths: [String] = []
            
            for platform in platforms.sorted(by: { $0.rawValue < $1.rawValue }) {
                let slices = platform.buildSlices
                for slice in slices {
                    print("      \(slice.displayName)...")
                    let frameworkPath = try await buildForPlatform(
                        scheme: scheme,
                        sdk: slice.sdk,
                        destination: slice.destination,
                        buildDir: buildDir
                    )
                    frameworkPaths.append(frameworkPath)
                }
            }
            
            // Restore original Package.swift
            try originalContent.write(to: packageSwiftURL, atomically: true, encoding: .utf8)
            
            // Create xcframework
            let xcframeworkPath = outputDir.appendingPathComponent("\(outputName).xcframework")
            
            // Remove existing xcframework
            try? fileManager.removeItem(at: xcframeworkPath)
            
            // Build create-xcframework command
            var createArgs = ["-create-xcframework"]
            for path in frameworkPaths {
                createArgs += ["-framework", path]
            }
            createArgs += ["-output", xcframeworkPath.path]
            
            let shell = try Shell()
            _ = try await shell.execute(path: "/usr/bin/xcodebuild", args: createArgs)
            
            // Cleanup build directory
            try? fileManager.removeItem(at: buildDir)
            
            return xcframeworkPath.path
            
        } catch {
            // Always restore original Package.swift on error
            try? originalContent.write(to: packageSwiftURL, atomically: true, encoding: .utf8)
            throw error
        }
    }
    
    /// Rewrite .package(url:...) dependencies to use local paths
    private func rewriteDependencies(in content: String) -> String {
        var result = content
        
        for dep in dependencies {
            // Check if prebuilt version exists
            let prebuiltPath = "\(dylibsPath)/\(dep.identity)"
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
    /// Changes: .library(name: "Foo", targets: [...])
    /// To:      .library(name: "Foo", type: .dynamic, targets: [...])
    private func rewriteLibrariesToDynamic(in content: String) -> String {
        var result = content
        
        // Pattern to match .library(name: "...", targets: [...]) without an explicit type
        // We need to add type: .dynamic after the name
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
    
    private func buildForPlatform(
        scheme: String,
        sdk: String,
        destination: String,
        buildDir: URL
    ) async throws -> String {
        let derivedDataPath = buildDir.appendingPathComponent("DerivedData-\(sdk)")
        
        // Build the xcodebuild command
        var buildArgs = ["build"]
        buildArgs += ["-scheme", scheme]
        buildArgs += ["-configuration", configuration.capitalized]
        buildArgs += ["-sdk", sdk]
        buildArgs += ["-destination", destination]
        buildArgs += ["-derivedDataPath", derivedDataPath.path]
        buildArgs += ["-skipPackagePluginValidation"]
        buildArgs += ["-skipMacroValidation"]
        // Settings for building a distributable framework with module interfaces
        buildArgs += ["BUILD_LIBRARY_FOR_DISTRIBUTION=YES"]
        buildArgs += ["SWIFT_EMIT_MODULE_INTERFACE=YES"]
        
        let shell = try Shell()
        try await shell.cd(packagePath.path)
        _ = try await shell.execute(path: "/usr/bin/xcodebuild", args: buildArgs)
        
        // Find the built framework - could be in different locations
        let productsDir = derivedDataPath
            .appendingPathComponent("Build/Products")
            .appendingPathComponent(productsDirName(for: sdk))
        
        // Try direct path first, then PackageFrameworks subdirectory
        let possiblePaths = [
            productsDir.appendingPathComponent("\(scheme).framework"),
            productsDir.appendingPathComponent("PackageFrameworks/\(scheme).framework"),
        ]
        
        for frameworkPath in possiblePaths {
            if FileManager.default.fileExists(atPath: frameworkPath.path) {
                return frameworkPath.path
            }
        }
        
        throw BuildError.frameworkNotFound(scheme, sdk)
    }
    
    private func productsDirName(for sdk: String) -> String {
        // macOS has no suffix (just "Release" or "Debug")
        // Other platforms have suffix like "Release-iphoneos"
        switch sdk {
        case "macosx":
            return configuration.capitalized
        default:
            return "\(configuration.capitalized)-\(sdk)"
        }
    }
}

// MARK: - Platform Build Configuration

struct BuildSlice {
    let sdk: String
    let destination: String
    let displayName: String
}

extension Platform {
    /// Returns all build slices for this platform (device + simulator where applicable)
    var buildSlices: [BuildSlice] {
        switch self {
        case .macos:
            return [
                BuildSlice(sdk: "macosx", destination: "generic/platform=macOS", displayName: "macOS")
            ]
        case .ios:
            return [
                BuildSlice(sdk: "iphoneos", destination: "generic/platform=iOS", displayName: "iOS"),
                BuildSlice(sdk: "iphonesimulator", destination: "generic/platform=iOS Simulator", displayName: "iOS Simulator")
            ]
        case .tvos:
            return [
                BuildSlice(sdk: "appletvos", destination: "generic/platform=tvOS", displayName: "tvOS"),
                BuildSlice(sdk: "appletvsimulator", destination: "generic/platform=tvOS Simulator", displayName: "tvOS Simulator")
            ]
        case .watchos:
            return [
                BuildSlice(sdk: "watchos", destination: "generic/platform=watchOS", displayName: "watchOS"),
                BuildSlice(sdk: "watchsimulator", destination: "generic/platform=watchOS Simulator", displayName: "watchOS Simulator")
            ]
        case .visionos:
            return [
                BuildSlice(sdk: "xros", destination: "generic/platform=visionOS", displayName: "visionOS"),
                BuildSlice(sdk: "xrsimulator", destination: "generic/platform=visionOS Simulator", displayName: "visionOS Simulator")
            ]
        }
    }
}

enum BuildError: Error, LocalizedError {
    case commandFailed(String, String)
    case frameworkNotFound(String, String)
    
    var errorDescription: String? {
        switch self {
        case .commandFailed(let cmd, let output):
            return "\(cmd) failed:\n\(output.prefix(500))"
        case .frameworkNotFound(let product, let sdk):
            return "Framework not found for \(product) (\(sdk))"
        }
    }
}
