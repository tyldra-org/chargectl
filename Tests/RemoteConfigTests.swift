import CryptoKit
import Foundation
import Testing

@Suite struct RemoteConfigTests {
    private func context(
        version: String = "0.3.7", taps: Set<String> = [], from: String? = nil, homebrew: Bool = true,
        now: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> RemoteConfig.Context {
        RemoteConfig.Context(version: version, taps: taps, installedFrom: from, homebrew: homebrew, now: now)
    }

    private func item(
        _ id: String, _ placement: RemoteConfig.Item.Placement = .prompt, when: RemoteConfig.Conditions? = nil,
        until: Date? = nil
    ) -> RemoteConfig.Item {
        RemoteConfig.Item(id: id, placement: placement, title: id, body: "", when: when, until: until)
    }

    @Test func showsAnItemOnlyWhereItsConditionsHold() {
        let config = RemoteConfig(items: [
            item("old-tap", when: .init(tapped: "tyldra-org/tools")),
            item("old-versions", when: .init(below: "0.4.0")),
            item("new-versions", when: .init(atLeast: "0.4.0")),
            item("downloads", when: .init(homebrew: false)),
            item("expired", until: Date(timeIntervalSince1970: 1_700_000_000)),
            item("banner", .banner),
        ])
        let shown = config.items(for: context(taps: ["tyldra-org/tools"]), placement: .prompt).map(\.id)
        #expect(shown == ["old-tap", "old-versions"])
        #expect(
            config.items(for: context(version: "0.4.0", homebrew: false), placement: .prompt).map(\.id) == [
                "new-versions", "downloads",
            ])
        #expect(config.items(for: context(), placement: .banner).map(\.id) == ["banner"])
    }

    /// Someone who already moved sees neither prompt; someone halfway sees only the last step.
    @Test func theTapMovePromptsReachOnlyThoseWhoStillNeedThem() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("feed/app.json"))
        let signature = try Data(contentsOf: root.appendingPathComponent("feed/app.json.sig"))
        let config = try #require(RemoteConfigFeed.verify(data, signature: signature))
        func shown(_ taps: Set<String>, from: String?) -> [String] {
            config.items(for: context(taps: taps, from: from), placement: .prompt).map(\.id)
        }
        let old = "tyldra-org/tools"
        let new = "tyldra/tools"
        #expect(shown([old], from: old) == ["tap-moved-2026-11"])
        #expect(shown([old, new], from: old) == ["tap-moved-2026-11"])
        #expect(shown([old, new], from: new) == ["old-tap-left-2026-11"])
        #expect(shown([new], from: new).isEmpty)
        #expect(shown([], from: nil).isEmpty)
    }

    @Test func readsTheTapFromAHomebrewReceipt() {
        let receipt = Data(#"{"source": {"tap": "tyldra-org/tools", "version": "0.3.7"}}"#.utf8)
        #expect(RemoteConfigFeed.tap(inReceipt: receipt) == "tyldra-org/tools")
        #expect(RemoteConfigFeed.tap(inReceipt: Data("{}".utf8)) == nil)
    }

    @Test func flagsAndValuesFallBackToTheBuiltInDefault() {
        let config = RemoteConfig(
            items: [],
            flags: ["smartLimit": .init(on: true, when: .init(atLeast: "0.4.0")), "off": .init(on: false)],
            values: ["refreshSeconds": .init(number: 30)])
        #expect(!config.flag("smartLimit", default: false, context: context()))
        #expect(config.flag("smartLimit", default: false, context: context(version: "0.4.1")))
        #expect(!config.flag("off", default: true, context: context()))
        #expect(config.flag("missing", default: true, context: context()))
        #expect(config.value("refreshSeconds", default: 5, context: context()) == 30)
        #expect(config.value("missing", default: 5, context: context()) == 5)
    }

    @Test func usesOnlyAFileItsKeySigned() throws {
        let key = Curve25519.Signing.PrivateKey()
        let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
        let data = Data(#"{"items": [{"id": "a", "placement": "banner", "title": "Hi", "body": "There"}]}"#.utf8)
        let signature = Data(try key.signature(for: data).base64EncodedString().utf8)
        #expect(RemoteConfigFeed.verify(data, signature: signature, key: publicKey)?.items.first?.id == "a")
        var changed = data
        changed[changed.startIndex] = UInt8(ascii: " ")
        #expect(RemoteConfigFeed.verify(changed, signature: signature, key: publicKey) == nil)
        let other = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        #expect(RemoteConfigFeed.verify(data, signature: signature, key: other) == nil)
        #expect(RemoteConfigFeed.verify(data, signature: Data("not base64".utf8), key: publicKey) == nil)
    }

    /// The file the apps download is signed with the key they carry, so a change to it can't
    /// reach main unsigned.
    @Test func theRepositorysFileIsSigned() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("feed/app.json"))
        let signature = try Data(contentsOf: root.appendingPathComponent("feed/app.json.sig"))
        #expect(RemoteConfigFeed.verify(data, signature: signature) != nil)
    }
}
