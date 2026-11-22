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
        ])

        #expect(info.versionText == "1.2 (42)")
        #expect(info.branchText == "feature/settings-build-info")
        #expect(info.commit == "0123456789abcdef0123456789abcdef01234567")
        #expect(info.shortCommitText == "0123456")
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
        ])

        #expect(info.branch == nil)
        #expect(info.commit == nil)
    }

    @Test func missingInfoDictionaryFallsBackToDefaults() {
        let info = BuildInfo(infoDictionary: nil)

        #expect(info.versionText == "1.0 (1)")
        #expect(info.branchText == BuildInfo.unknown)
        #expect(info.shortCommitText == BuildInfo.unknown)
    }

    @Test func shortCommitKeepsShortValuesWhole() {
        let info = BuildInfo(infoDictionary: [BuildInfo.commitKey: "abc12"])

        #expect(info.shortCommitText == "abc12")
    }
}
