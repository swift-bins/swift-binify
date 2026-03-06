import Foundation

enum Constants {
    /// Base path for output xcframeworks and generated packages
    static let outputBasePath = "/tmp/swift-binify-dylibs"

    /// Swift versions to generate versioned manifests for (when library evolution is off).
    /// Update this list when new Swift toolchains need support.
    static let supportedSwiftVersions = [
        "5.8.0",
        "5.9.0", "5.9.1", "5.9.2",
        "5.10.0", "5.10.1",
        "6.0.0", "6.0.1", "6.0.2", "6.0.3",
        "6.1.0", "6.1.1", "6.1.2",
        "6.2.0", "6.2.1", "6.2.2", "6.2.3", "6.2.4"
    ]

    /// Returns the output directory URL for a given package name
    static func outputDirectory(for packageName: String) -> URL {
        URL(fileURLWithPath: outputBasePath).appendingPathComponent(packageName)
    }

    /// Returns a versioned subdirectory (e.g. `swift-6.2/`) inside the package output dir
    static func versionedOutputDirectory(for packageName: String, swiftVersion: String) -> URL {
        outputDirectory(for: packageName).appendingPathComponent("swift-\(swiftVersion)")
    }
}
