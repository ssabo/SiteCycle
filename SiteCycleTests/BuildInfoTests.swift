import Testing
import Foundation
@testable import SiteCycle

struct BuildInfoTests {

    @Test func readsStampedBranchAndCommit() {
        let info = BuildInfo(infoDictionary: [
            "CFBundleShortVersionString": "1.2",
            "CFBundleVersion": "42",
            BuildInfo.branchKey: "feature/settings-build-info",
            BuildInfo.commitKey: "0123456789abcdef0123456789abcdef01234567",
            BuildInfo.buildDateKey: "2026-11-22T21:55:00Z",
        ])

        #expect(info.versionText == "1.2 (42)")
        #expect(info.branchText == "feature/settings-build-info")
        #expect(info.commit == "0123456789abcdef0123456789abcdef01234567")
        #expect(info.shortCommitText == "0123456")
        #expect(info.buildDate == Date(timeIntervalSince1970: 1_795_384_500))
    }

    @Test func buildDateIsShownInTheGivenTimeZone() throws {
        let info = BuildInfo(infoDictionary: [BuildInfo.buildDateKey: "2026-11-22T21:55:00Z"])
        let utc = try #require(TimeZone(identifier: "UTC"))
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let locale = Locale(identifier: "en_US")

        let utcText = info.buildDateText(timeZone: utc, locale: locale)
        let tokyoText = info.buildDateText(timeZone: tokyo, locale: locale)

        #expect(utcText.contains("Nov 22, 2026"))
        #expect(utcText.contains("9:55"))
        #expect(tokyoText.contains("Nov 23, 2026"))
        #expect(tokyoText.contains("6:55"))
    }

    @Test func unparseableBuildDateIsUnknown() {
        let info = BuildInfo(infoDictionary: [BuildInfo.buildDateKey: "yesterday"])

        #expect(info.buildDate == nil)
        #expect(info.buildDateText() == BuildInfo.unknown)
    }

    @Test func unstampedBuildShowsUnknown() {
        let info = BuildInfo(infoDictionary: [
            BuildInfo.branchKey: "",
            BuildInfo.commitKey: "  ",
        ])

        #expect(info.branch == nil)
        #expect(info.commit == nil)
        #expect(info.branchText == BuildInfo.unknown)
        #expect(info.shortCommitText == BuildInfo.unknown)
    }

    @Test func unexpandedBuildSettingIsTreatedAsMissing() {
        let info = BuildInfo(infoDictionary: [
            BuildInfo.branchKey: "$(SITECYCLE_GIT_BRANCH)",
            BuildInfo.commitKey: "$(SITECYCLE_GIT_COMMIT)",
            BuildInfo.buildDateKey: "$(SITECYCLE_BUILD_DATE)",
        ])

        #expect(info.branch == nil)
        #expect(info.commit == nil)
        #expect(info.buildDate == nil)
    }

    @Test func missingInfoDictionaryFallsBackToDefaults() {
        let info = BuildInfo(infoDictionary: nil)

        #expect(info.versionText == "1.0 (1)")
        #expect(info.branchText == BuildInfo.unknown)
        #expect(info.shortCommitText == BuildInfo.unknown)
        #expect(info.buildDateText() == BuildInfo.unknown)
    }

    @Test func shortCommitKeepsShortValuesWhole() {
        let info = BuildInfo(infoDictionary: [BuildInfo.commitKey: "abc12"])

        #expect(info.shortCommitText == "abc12")
    }
}
