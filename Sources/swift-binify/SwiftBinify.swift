import ArgumentParser

@main
struct SwiftBinify: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Build Swift packages as dynamic xcframeworks",
        version: "1.0.0",
        subcommands: [BuildCommand.self, SwiftVersionsCommand.self],
        defaultSubcommand: BuildCommand.self
    )
}
