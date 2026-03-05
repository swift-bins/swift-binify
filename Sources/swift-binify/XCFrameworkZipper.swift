import Foundation
import CryptoKit

/// Result of zipping an xcframework
struct ZippedFramework {
    let name: String
    let zipPath: URL
    let checksum: String
}

/// Zips xcframeworks and calculates SHA256 checksums
struct XCFrameworkZipper {

    /// Zip all xcframeworks in the output directory
    /// - Parameters:
    ///   - frameworkDir: Directory containing .xcframework folders
    ///   - targetNames: Names of targets to zip
    ///   - zipOutputDir: Where to write the zip files (defaults to frameworkDir)
    ///   - swiftVersionTag: Optional Swift version tag for versioned zip names (e.g. "6.2")
    /// - Returns: Array of zipped framework info with checksums
    func zipAll(
        in frameworkDir: URL,
        targetNames: [String],
        zipOutputDir: URL? = nil,
        swiftVersionTag: String? = nil
    ) throws -> [ZippedFramework] {
        let fileManager = FileManager.default
        let destDir = zipOutputDir ?? frameworkDir
        var results: [ZippedFramework] = []

        for targetName in targetNames {
            let xcframeworkPath = frameworkDir.appendingPathComponent("\(targetName).xcframework")
            let zipName = swiftVersionTag != nil
                ? "\(targetName)-swift-\(swiftVersionTag!).xcframework.zip"
                : "\(targetName).xcframework.zip"
            let zipPath = destDir.appendingPathComponent(zipName)

            guard fileManager.fileExists(atPath: xcframeworkPath.path) else {
                Console.warning("XCFramework not found: \(targetName).xcframework")
                continue
            }

            // Remove existing zip if present
            try? fileManager.removeItem(at: zipPath)

            // Create zip archive
            try createZipArchive(source: xcframeworkPath, destination: zipPath)

            // Calculate SHA256 checksum
            let checksum = try calculateSHA256(of: zipPath)

            results.append(ZippedFramework(
                name: targetName,
                zipPath: zipPath,
                checksum: checksum
            ))

            Console.success("Zipped \(zipName)", detail: "checksum: \(checksum.prefix(16))...")
        }

        return results
    }

    // MARK: - Private Helpers

    private func createZipArchive(source: URL, destination: URL) throws {
        let fileManager = FileManager.default
        let sourceDir = source.deletingLastPathComponent()
        let sourceName = source.lastPathComponent

        // Use ditto for deterministic zip creation (better than zip command)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", sourceName, destination.path]
        process.currentDirectoryURL = sourceDir

        let pipe = Pipe()
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw ZipperError.zipFailed("Failed to create zip: \(errorMessage)")
        }

        // Verify zip was created
        guard fileManager.fileExists(atPath: destination.path) else {
            throw ZipperError.zipFailed("Zip file was not created")
        }
    }

    private func calculateSHA256(of url: URL) throws -> String {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        var hasher = SHA256()

        // Read in chunks to handle large files efficiently
        let chunkSize = 1024 * 1024 // 1MB chunks
        while autoreleasepool(invoking: {
            let data = fileHandle.readData(ofLength: chunkSize)
            if data.isEmpty {
                return false
            }
            hasher.update(data: data)
            return true
        }) {}

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Errors

enum ZipperError: LocalizedError {
    case zipFailed(String)

    var errorDescription: String? {
        switch self {
        case .zipFailed(let message):
            return message
        }
    }
}
