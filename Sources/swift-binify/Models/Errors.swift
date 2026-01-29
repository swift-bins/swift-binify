import Foundation

// MARK: - Analyzer Errors

enum AnalyzerError: Error, LocalizedError {
    case commandFailed(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message
        case .parseError(let message):
            return "Parse error: \(message)"
        }
    }
}

// MARK: - Build Errors

enum BuildError: Error, LocalizedError {
    case commandFailed(String, String)
    case frameworkNotFound(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let cmd, let output):
            return "\(cmd) failed:\n\(output.prefix(500))"
        case .frameworkNotFound(let name):
            return "Framework not found: \(name)"
        }
    }
}
