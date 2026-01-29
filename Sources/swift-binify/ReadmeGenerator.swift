import Foundation

/// Generates README.md files for binary repos
struct ReadmeGenerator {

    /// Configuration for README generation
    struct Config {
        let sourceRepoURL: String    // Original source repo URL
        let binaryRepoURL: String    // swift-bins binary repo URL
        let packageName: String      // Package name
        let sourceOwner: String      // Original repo owner (e.g., "onevcat")
        let tag: String              // Version tag
    }

    /// Generate README content
    func generate(config: Config) -> String {
        // Clean URLs (remove .git suffix)
        let cleanSourceURL = config.sourceRepoURL.replacingOccurrences(of: ".git", with: "")
        let binaryPackageIdentity = "\(config.sourceOwner)_\(config.packageName)"

        return """
        # \(config.packageName) (Binary)

        Pre-built binary xcframeworks for [\(config.packageName)](\(cleanSourceURL)).

        > ![TIP]
        > swift-bins is currently a proof of concept, but you're welcome to use this prebuilt package. It's easy to get started with and easy to detach from later.

        ## Usage

        **1. Update your package dependency:**

        ```swift
        // Before (builds from source)
        .package(url: "\(cleanSourceURL)", from: "\(config.tag)")

        // After (uses pre-built binaries)
        .package(url: "\(config.binaryRepoURL)", from: "\(config.tag)")
        ```

        **2. Update your target dependency** (package name changes):

        ```swift
        // Before
        .product(name: "\(config.packageName)", package: "\(config.packageName)")

        // After
        .product(name: "\(config.packageName)", package: "\(binaryPackageIdentity)")
        ```

        ## License

        See [LICENSE](LICENSE) - sourced from the original repository.

        ## Original Repository

        For documentation and source code, visit the original repo:
        - README: \(cleanSourceURL)#readme
        - Source: \(cleanSourceURL)

        ## More Information

        For more information, see the [swift-binify](https://github.com/swift-bins/swift-binify) repository.
        """
    }

    /// Write README to output directory
    func write(config: Config, to outputDir: URL) throws {
        let content = generate(config: config)
        let readmeURL = outputDir.appendingPathComponent("README.md")
        try content.write(to: readmeURL, atomically: true, encoding: .utf8)
    }
}
