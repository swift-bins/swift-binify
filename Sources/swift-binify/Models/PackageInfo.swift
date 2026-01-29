import Foundation

// MARK: - Platform Types

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

// MARK: - Package Info

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
