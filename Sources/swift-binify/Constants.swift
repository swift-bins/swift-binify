import Foundation

enum Constants {
    /// Base path for output xcframeworks and generated packages
    static let outputBasePath = "/tmp/swift-binify-dylibs"

    /// Swift versions to generate versioned manifests for (when library evolution is off).
    /// Update this list when new Swift toolchains need support.
    static let supportedSwiftVersions = ["6.0", "6.1", "6.2"] // Also update SWIFT_VERSIONS in build-binary.yml

    /// Returns the output directory URL for a given package name
    static func outputDirectory(for packageName: String) -> URL {
        URL(fileURLWithPath: outputBasePath).appendingPathComponent(packageName)
    }

    /// Returns a versioned subdirectory (e.g. `swift-6.2/`) inside the package output dir
    static func versionedOutputDirectory(for packageName: String, swiftVersion: String) -> URL {
        outputDirectory(for: packageName).appendingPathComponent("swift-\(swiftVersion)")
    }
}
