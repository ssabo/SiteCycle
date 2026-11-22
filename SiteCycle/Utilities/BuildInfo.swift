import Foundation

/// The version, build number, and the git branch and commit the app was built from.
///
/// The branch and commit come from the `SiteCycleGitBranch` / `SiteCycleGitCommit`
/// Info.plist keys, which `ci_scripts/ci_post_clone.sh` fills in on Xcode Cloud.
/// They're empty in a local build unless that script was run by hand.
struct BuildInfo: Equatable {
    static let branchKey = "SiteCycleGitBranch"
    static let commitKey = "SiteCycleGitCommit"
    static let shortCommitLength = 7
    static let unknown = "Unknown"

    let version: String
    let build: String
    /// Nil when the build wasn't stamped.
    let branch: String?
    /// The full commit SHA; nil when the build wasn't stamped.
    let commit: String?

    init(infoDictionary: [String: Any]?) {
        version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        branch = Self.nonEmpty(infoDictionary?[Self.branchKey])
        commit = Self.nonEmpty(infoDictionary?[Self.commitKey])
    }

    static var main: BuildInfo {
        BuildInfo(infoDictionary: Bundle.main.infoDictionary)
    }

    /// "1.0 (42)"
    var versionText: String {
        "\(version) (\(build))"
    }

    var branchText: String {
        branch ?? Self.unknown
    }

    /// The first seven characters of the commit SHA.
    var shortCommitText: String {
        commit.map { String($0.prefix(Self.shortCommitLength)) } ?? Self.unknown
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              !text.hasPrefix("$(") else {
            return nil
        }
        return text
    }
}
