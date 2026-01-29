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
        let url: String?
        let versionRequirement: VersionRequirement?

        /// Version requirement for a dependency
        enum VersionRequirement {
            case range(from: String, to: String?)
            case exact(String)
            case branch(String)
            case revision(String)

            /// Convert to swift-bins URL dependency declaration
            func swiftDeclaration(url: String) -> String {
                switch self {
                case .range(let from, _):
                    return ".package(url: \"\(url)\", from: \"\(from)\")"
                case .exact(let version):
                    return ".package(url: \"\(url)\", exact: \"\(version)\")"
                case .branch(let branch):
                    return ".package(url: \"\(url)\", branch: \"\(branch)\")"
                case .revision(let rev):
                    return ".package(url: \"\(url)\", revision: \"\(rev)\")"
                }
            }
        }

        /// Derive swift-bins URL from original GitHub URL
        /// e.g., https://github.com/onevcat/Kingfisher -> https://github.com/swift-bins/onevcat_Kingfisher
        var swiftBinsURL: String? {
            guard let url = url else { return nil }

            // Parse owner/repo from GitHub URL
            // Handles: https://github.com/owner/repo.git or https://github.com/owner/repo
            let pattern = #"github\.com[/:]([^/]+)/([^/.]+)"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
                  let ownerRange = Range(match.range(at: 1), in: url),
                  let repoRange = Range(match.range(at: 2), in: url) else {
                return nil
            }

            let owner = String(url[ownerRange])
            let repo = String(url[repoRange])

            return "https://github.com/swift-bins/\(owner)_\(repo)"
        }
    }

    /// A target that should be built (has an available scheme)
    struct BuildTarget {
        let name: String        // The scheme/target name to build
        let productName: String // The product name for the output xcframework
    }
}
