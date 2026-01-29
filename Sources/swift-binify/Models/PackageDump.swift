import Foundation

// MARK: - JSON Models for `swift package dump-package`

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
