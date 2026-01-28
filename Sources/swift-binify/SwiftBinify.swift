import ArgumentParser
import Foundation

@main
struct SwiftBinify: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Build Swift packages as dynamic xcframeworks",
        discussion: """
            Builds all products of a Swift package as dynamic library xcframeworks.
            
            Automatically detects supported platforms from Package.swift and builds
            for all of them. Simulators are always included for platforms that support them.
            
            Output goes to /tmp/swift-binify-dylibs/<package-name>/ with a generated
            Package.swift that can be used as a drop-in replacement.
            
            Usage in your project - just change:
                .package(url: "https://github.com/foo/bar", from: "1.0.0")
            To:
                .package(path: "/tmp/swift-binify-dylibs/bar")
            """,
        version: "1.0.0"
    )
    
    @Argument(help: "Path to the Swift package directory")
    var packagePath: String
    
    @Option(name: .long, help: "Build configuration (debug/release)")
    var configuration: String = "release"
    
    func run() async throws {
        let packageURL = URL(fileURLWithPath: packagePath).standardizedFileURL
        
        print("📦 Swift Binify")
        print("   Package: \(packageURL.path)")
        print("")
        
        // Step 1: Analyze the package
        print("🔍 Analyzing package...")
        let analyzer = PackageAnalyzer()
        let packageInfo = try await analyzer.analyze(packagePath: packageURL)
        
        print("   Name: \(packageInfo.name)")
        print("   Platforms: \(packageInfo.platforms.map { $0.displayName }.sorted().joined(separator: ", "))")
        print("   Available schemes: \(packageInfo.availableSchemes.sorted().joined(separator: ", "))")
        print("   Targets to build: \(packageInfo.buildTargets.map { $0.name }.joined(separator: ", "))")
        if !packageInfo.dependencies.isEmpty {
            print("   Dependencies: \(packageInfo.dependencies.map { $0.identity }.joined(separator: ", "))")
        }
        print("")
        
        if packageInfo.buildTargets.isEmpty {
            print("⚠️  No buildable targets found")
            print("   (Skipped static libraries and targets without schemes)")
            return
        }
        
        // Step 2: Build each target as a dynamic xcframework
        let outputDir = URL(fileURLWithPath: "/tmp/swift-binify-dylibs/\(packageInfo.name)")
        
        let builder = XCFrameworkBuilder(
            packagePath: packageURL,
            packageName: packageInfo.name,
            configuration: configuration,
            platforms: packageInfo.platforms,
            dependencies: packageInfo.dependencies
        )
        
        print("🔨 Building xcframeworks...")
        print("")
        
        var succeeded: [String] = []
        var failed: [String] = []
        
        for target in packageInfo.buildTargets {
            print("   \(target.name):")
            do {
                let outputPath = try await builder.build(
                    scheme: target.name,
                    outputName: target.name
                )
                print("   ✓ \(outputPath)")
                succeeded.append(target.name)
            } catch {
                print("   ✗ Failed: \(error.localizedDescription)")
                failed.append(target.name)
            }
            print("")
        }
        
        // Step 3: Generate Package.swift wrapper
        if !succeeded.isEmpty {
            print("📝 Generating Package.swift...")
            let generator = PackageGenerator()
            try generator.generate(
                packageInfo: packageInfo,
                builtProducts: succeeded,
                outputDir: outputDir
            )
            print("   ✓ \(outputDir.path)/Package.swift")
            print("")
        }
        
        if failed.isEmpty {
            print("✅ Done! Built \(succeeded.count) framework(s)")
            print("")
            print("   To use in your project, change:")
            print("      .package(url: \"...\", ...)")
            print("   To:")
            print("      .package(path: \"\(outputDir.path)\")")
        } else if succeeded.isEmpty {
            print("❌ Failed! All \(failed.count) target(s) failed to build")
            throw ExitCode.failure
        } else {
            print("⚠️  Partial success: \(succeeded.count) succeeded, \(failed.count) failed")
            print("   Failed: \(failed.joined(separator: ", "))")
            print("")
            print("   To use in your project, change:")
            print("      .package(url: \"...\", ...)")
            print("   To:")
            print("      .package(path: \"\(outputDir.path)\")")
            throw ExitCode.failure
        }
    }
}
