import ArgumentParser

struct SwiftVersionsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swift-versions",
        abstract: "Print the list of supported Swift versions"
    )

    func run() {
        print(Constants.supportedSwiftVersions.joined(separator: " "))
    }
}
