# swift-binify

A tool that builds Swift packages as pre-compiled binary xcframeworks for faster build times.

> ![IMPORTANT]
> This is still a proof of concept, but you’re welcome to use the prebuilt packages. They’re easy to get started with and easy to detach from later.

## What it does

swift-binify takes a Swift package and produces:
- Pre-built `.xcframework` binaries (zipped for distribution)
- A generated `Package.swift` that references the binaries
- Preserved LICENSE from the original repo

## Why use binaries?

Building large Swift packages from source can significantly slow down your development cycle. Pre-built binaries eliminate this compilation time entirely.

## Transparency

The entire build process is open and auditable:

1. **This tool is open source** - You can inspect exactly how binaries are built
2. **GitHub Actions logs are public** - Every build is traceable
3. **Source tags are preserved** - Binary repo tags match the original source tags
4. **Checksums are verified** - Each binary target includes a SHA256 checksum

You can always verify that a binary was built from the original source by checking the GitHub Actions run for that tag.

## Using a binary package

Replace your source dependency with the binary equivalent:

```swift
// Before (builds from source)
.package(url: "https://github.com/onevcat/Kingfisher", from: "7.12.0")

// After (uses pre-built binaries)
.package(url: "https://github.com/swift-bins/onevcat_Kingfisher", from: "7.12.0")
```

## Setting up a new binary repo

See the [example directory](example/) for setup instructions and template files.

## Local usage

```bash
# Build a package locally (for development/testing)
swift-binify /path/to/package

# Build for release (generates URL-based Package.swift)
swift-binify /path/to/package \
    --output-mode release \
    --release-url-base "https://github.com/swift-bins/owner_repo/releases/download" \
    --tag "1.0.0"
```

## License

MIT

## Vibe Check

Yes, this is still a POC
