import Foundation

/// Generates README.md files for binary repos
struct ReadmeGenerator {

    /// Configuration for README generation
    struct Config {
        let sourceRepoURL: String       // Original source repo URL
        let binaryRepoURL: String       // swift-bins binary repo URL
        let packageName: String         // Package name
        let sourceOwner: String         // Original repo owner (e.g., "onevcat")
        let tag: String                 // Version tag
        let requiresOwnerPrefix: Bool   // Whether binary repo uses owner_name format
    }

    /// Generate README content
    func generate(config: Config) -> String {
        // Clean URLs (remove .git suffix)
        let cleanSourceURL = config.sourceRepoURL.replacingOccurrences(of: ".git", with: "")

        var readme = """
        # \(config.packageName) (Binary)

        Pre-built binary xcframeworks for [\(config.packageName)](\(cleanSourceURL)).

        > [!TIP]
        > swift-bins is currently a proof of concept, but you're welcome to use this prebuilt package. It's easy to get started with and easy to detach from later.

        ## Usage

        Update your package dependency in `Package.swift`:

        ```swift
        // Before (builds from source)
        .package(url: "\(cleanSourceURL)", from: "\(config.tag)")

        // After (uses pre-built binaries)
        .package(url: "\(config.binaryRepoURL)", from: "\(config.tag)")
        ```
        """

        // Only add package name change section if owner prefix is required
        if config.requiresOwnerPrefix {
            let binaryPackageIdentity = "\(config.sourceOwner)_\(config.packageName)"
            readme += """


            **Note:** You also need to update your target dependency (package name changes):

            ```swift
            // Before
            .product(name: "\(config.packageName)", package: "\(config.packageName)")

            // After
            .product(name: "\(config.packageName)", package: "\(binaryPackageIdentity)")
            ```
            """
        }

        readme += """


        ## License

        See [LICENSE](LICENSE) - sourced from the original repository.

        ## Original Repository

        For documentation and source code, visit the original repo:
        - README: \(cleanSourceURL)#readme
        - Source: \(cleanSourceURL)

        ## More Information

        For more information, see the [swift-binify](https://github.com/swift-bins/swift-binify) repository.
        """

        return readme
    }

    /// Write README to output directory
    func write(config: Config, to outputDir: URL) throws {
        let content = generate(config: config)
        let readmeURL = outputDir.appendingPathComponent("README.md")
        try content.write(to: readmeURL, atomically: true, encoding: .utf8)
    }
}
