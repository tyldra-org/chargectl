import Foundation
import Testing

@Suite struct AppReleaseTests {
    func payload(tag: String = "v0.2.0", draft: Bool = false, prerelease: Bool = false, assets: [String]? = nil)
        -> Data
    {
        let names = assets ?? ["Chargectl-0.2.0.zip", "Chargectl-0.2.0.zip.sha256", "chargectl.rb"]
        let list = names.map {
            #"{"name":"\#($0)","browser_download_url":"https://github.com/tyldra-org/chargectl/releases/download/\#(tag)/\#($0)"}"#
        }
        return Data(
            #"{"tag_name":"\#(tag)","draft":\#(draft),"prerelease":\#(prerelease),"assets":[\#(list.joined(separator: ","))]}"#
                .utf8)
    }

    @Test func parsesTheZipAndChecksum() throws {
        let release = try #require(AppRelease.parse(payload()))
        #expect(release.version == "0.2.0")
        #expect(release.archive.lastPathComponent == "Chargectl-0.2.0.zip")
        #expect(release.checksum.lastPathComponent == "Chargectl-0.2.0.zip.sha256")
    }

    @Test func skipsDraftsPrereleasesAndIncompleteReleases() {
        #expect(AppRelease.parse(payload(draft: true)) == nil)
        #expect(AppRelease.parse(payload(prerelease: true)) == nil)
        #expect(AppRelease.parse(payload(assets: ["Chargectl-0.2.0.zip"])) == nil)
        #expect(AppRelease.parse(payload(tag: "nightly")) == nil)
        #expect(AppRelease.parse(Data("not json".utf8)) == nil)
    }

    @Test func comparesVersionsNumerically() {
        #expect(AppRelease.isNewer("0.1.10", than: "0.1.9"))
        #expect(AppRelease.isNewer("1.0.0", than: "0.9.9"))
        #expect(!AppRelease.isNewer("0.1.7", than: "0.1.7"))
        #expect(!AppRelease.isNewer("0.1.6", than: "0.1.7"))
        #expect(!AppRelease.isNewer("0.2", than: "0.1.7"))
        #expect(!AppRelease.isNewer("0.2.0", than: "unknown"))
    }
}
