import Foundation

enum Constants {
    /// Base path for output xcframeworks and generated packages
    static let outputBasePath = "/tmp/swift-binify-dylibs"

    /// Returns the output directory URL for a given package name
    static func outputDirectory(for packageName: String) -> URL {
        URL(fileURLWithPath: outputBasePath).appendingPathComponent(packageName)
    }
}
