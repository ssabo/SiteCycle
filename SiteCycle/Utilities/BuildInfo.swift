import Foundation

/// The version, build number, the git branch and commit the app was built from, and when.
///
/// The branch, commit and date come from the `SiteCycleGitBranch`, `SiteCycleGitCommit` and
/// `SiteCycleBuildDate` Info.plist keys, which `ci_scripts/ci_post_clone.sh` fills in on Xcode Cloud.
/// They're empty in a local build unless that script was run by hand.
struct BuildInfo: Equatable {
    static let branchKey = "SiteCycleGitBranch"
    static let commitKey = "SiteCycleGitCommit"
    /// An ISO 8601 UTC timestamp, such as `2026-11-22T21:55:00Z`.
    static let buildDateKey = "SiteCycleBuildDate"
    static let shortCommitLength = 7
    static let unknown = "Unknown"

    let version: String
    let build: String
    /// Nil when the build wasn't stamped.
    let branch: String?
    /// The full commit SHA; nil when the build wasn't stamped.
    let commit: String?
    /// When the build was stamped; nil when it wasn't, or the value doesn't parse.
    let buildDate: Date?

    init(infoDictionary: [String: Any]?) {
        version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        branch = Self.nonEmpty(infoDictionary?[Self.branchKey])
        commit = Self.nonEmpty(infoDictionary?[Self.commitKey])
        buildDate = Self.nonEmpty(infoDictionary?[Self.buildDateKey]).flatMap {
            try? Date($0, strategy: .iso8601)
        }
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

    /// The build date in the given time zone, such as "Nov 22, 2026 at 1:55 PM".
    func buildDateText(timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        guard let buildDate else { return Self.unknown }
        var style = Date.FormatStyle(date: .abbreviated, time: .shortened)
        style.timeZone = timeZone
        return buildDate.formatted(style.locale(locale))
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
