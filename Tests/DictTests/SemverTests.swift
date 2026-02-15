import Testing
@testable import DictCore

@Suite("Semver comparison")
struct SemverTests {
    @Test func equalVersions() {
        #expect(!isNewerVersion("1.2.3", than: "1.2.3"))
    }

    @Test func higherMajor() {
        #expect(isNewerVersion("2.0.0", than: "1.9.9"))
    }

    @Test func higherMinor() {
        #expect(isNewerVersion("1.3.0", than: "1.2.9"))
    }

    @Test func higherPatch() {
        #expect(isNewerVersion("1.2.4", than: "1.2.3"))
    }

    @Test func lowerVersion() {
        #expect(!isNewerVersion("1.0.0", than: "1.2.3"))
    }

    @Test func missingComponents() {
        // "1.0" treated as "1.0.0"
        #expect(!isNewerVersion("1.0", than: "1.0.0"))
        #expect(isNewerVersion("1.1", than: "1.0.0"))
    }

    @Test func emptyStrings() {
        #expect(!isNewerVersion("", than: ""))
        #expect(!isNewerVersion("", than: "1.0.0"))
        // Empty remote has no numeric components → all zeros → not newer
        #expect(!isNewerVersion("", than: "0.0.0"))
    }

    @Test func nonNumericComponents() {
        // Non-numeric parts are dropped by compactMap
        #expect(!isNewerVersion("abc", than: "1.0.0"))
        // "1.abc.3" → [1, 3] vs [1, 0, 2]: at index 1, 3 > 0 → true
        #expect(isNewerVersion("1.abc.3", than: "1.0.2"))
    }

    @Test func extraComponents() {
        #expect(isNewerVersion("1.2.3.4.5", than: "1.2.3.4.4"))
        #expect(!isNewerVersion("1.2.3.4.5", than: "1.2.3.4.5"))
    }
}
