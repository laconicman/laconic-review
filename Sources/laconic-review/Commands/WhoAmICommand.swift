import ArgumentParser
import LaconicReviewCore

/// Verify the token and show the current GitLab identity (`GET /user`).
struct WhoAmICommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "whoami",
        abstract: "Verify the token and print the current GitLab identity."
    )

    @OptionGroup var options: ConnectionOptions

    func run() async throws {
        let me = try await options.makeConnection(requireProject: false).currentUser()
        if options.json {
            print(try JSON.string(me))
        } else {
            let suffix = me.name.map { " — \($0)" } ?? ""
            print("✓ \(me.username) (id \(me.id))\(suffix)")
        }
    }
}
