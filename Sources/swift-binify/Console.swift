import Foundation

/// Console output helpers for consistent formatting
enum Console {

    // MARK: - Headers & Steps

    static func header(_ title: String) {
        print("📦 \(title)")
    }

    static func step(_ message: String) {
        print("🔍 \(message)...")
    }

    static func buildStep(_ message: String) {
        print("🔨 \(message)...")
    }

    static func generateStep(_ message: String) {
        print("📝 \(message)...")
    }

    // MARK: - Status Messages

    static func success(_ item: String, detail: String) {
        print("   ✓ \(item) -> \(detail)")
    }

    static func success(_ message: String) {
        print("   ✓ \(message)")
    }

    static func failure(_ item: String, reason: String) {
        print("   ✗ \(item) - \(reason)")
    }

    static func warning(_ message: String) {
        print("⚠️  \(message)")
    }

    static func done(_ message: String) {
        print("✅ \(message)")
    }

    static func error(_ message: String) {
        print("❌ \(message)")
    }

    // MARK: - Info Display

    static func info(_ key: String, _ value: String) {
        print("   \(key): \(value)")
    }

    static func blank() {
        print("")
    }

    // MARK: - Usage Instructions

    static func usageInstructions(outputPath: String) {
        print("   To use in your project, change:")
        print("      .package(url: \"...\", ...)")
        print("   To:")
        print("      .package(path: \"\(outputPath)\")")
    }
}
