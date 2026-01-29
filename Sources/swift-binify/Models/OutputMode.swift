import Foundation
import ArgumentParser

/// Output mode for generated Package.swift
enum OutputMode: String, CaseIterable, ExpressibleByArgument {
    /// Local path-based binary targets (for local development)
    case local

    /// URL-based binary targets (for GitHub Releases distribution)
    case release
}
