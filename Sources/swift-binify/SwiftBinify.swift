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
        print("   Targets to build: \(packageInfo.buildTargets.map { $0.name }.joined(separator: ", "))")
        if !packageInfo.dependencies.isEmpty {
            print("   Dependencies: \(packageInfo.dependencies.map { $0.identity }.joined(separator: ", "))")
        }
        print("")
        
        if packageInfo.buildTargets.isEmpty {
            print("⚠️  No buildable targets found")
            return
        }
        
        // Step 2: Build all targets with Scipio
        let outputDir = URL(fileURLWithPath: "/tmp/swift-binify-dylibs/\(packageInfo.name)")
        
        let builder = XCFrameworkBuilder(
            packagePath: packageURL,
            packageName: packageInfo.name,
            configuration: configuration,
            platforms: packageInfo.platforms,
            dependencies: packageInfo.dependencies
        )
        
        print("🔨 Building xcframeworks with Scipio...")
        print("")
        
        let targetNames = packageInfo.buildTargets.map { $0.name }
        
        do {
            let results = try await builder.buildAll(targets: targetNames)
            
            let succeeded = results.keys.sorted()
            let failed = targetNames.filter { !results.keys.contains($0) }
            
            for target in succeeded {
                if let path = results[target] {
                    print("   ✓ \(target) -> \(path)")
                }
            }
            
            for target in failed {
                print("   ✗ \(target) - not found in build output")
            }
            print("")
            
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
                print("❌ Failed! No frameworks were built")
                throw ExitCode.failure
            } else {
                print("⚠️  Partial success: \(succeeded.count) succeeded, \(failed.count) not found")
                print("   Missing: \(failed.joined(separator: ", "))")
                print("")
                print("   To use in your project, change:")
                print("      .package(url: \"...\", ...)")
                print("   To:")
                print("      .package(path: \"\(outputDir.path)\")")
            }
            
        } catch {
            print("   ✗ Build failed: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
}
