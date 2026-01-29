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
    let location: LocationDump?
    let requirement: RequirementDump?
}

struct LocationDump: Codable {
    let remote: [RemoteDump]?
}

struct RemoteDump: Codable {
    let urlString: String?
}

struct RequirementDump: Codable {
    let range: [RangeDump]?
    let exact: [String]?
    let branch: [String]?
    let revision: [String]?
}

struct RangeDump: Codable {
    let lowerBound: String?
    let upperBound: String?
}

struct ToolsVersionDump: Codable {
    let _version: String?
}
