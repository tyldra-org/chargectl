import Foundation
import Testing

@Suite struct SharedModelTests {
    @Test func smcValuesDecodeLittleEndian() {
        #expect(abs((SMCValue(key: "TB0T", type: "flt ", bytes: [0x98, 0x99, 0xe5, 0x41]).float ?? 0) - 28.7) < 0.001)
        #expect(SMCValue(key: "B0AV", type: "ui16", bytes: [0xbe, 0x30]).integer == 12478)
        #expect(SMCValue(key: "B0AC", type: "si16", bytes: [0x86, 0xfe]).integer == -378)
        #expect(SMCValue(key: "ACLC", type: "ui8 ", bytes: [0x02]).integer == 2)
        #expect(SMCValue(key: "TB0T", type: "ui8 ", bytes: [0x02]).float == nil)
    }

    @Test func settingsDecodeMissingKeysAsDefaultsAndClamp() throws {
        let json = Data(#"{"limit": 5, "sailing": 50}"#.utf8)
        let settings = try Coding.decode(ChargeSettings.self, from: json)
        #expect(settings.limit == 20)
        #expect(settings.sailing == 20)
        #expect(settings.lowerBound == 20)
        #expect(settings.isEnabled)
        #expect(settings.magSafeLED == .system)
    }

    @Test func statusRoundTrips() throws {
        let status = DaemonStatus(
            version: "0.1.0", settings: ChargeSettings(),
            mode: .calibrate(.holding, since: Date(timeIntervalSince1970: 1_800_000_000)),
            activity: .sailing(limit: 80, lowerBound: 75), adapterEnabled: false, adapterKey: "CHIE",
            lastError: nil)
        #expect(try Coding.decode(DaemonStatus.self, from: Coding.encode(status)) == status)
    }

    @Test func batterySnapshotParsesRegistry() throws {
        let registry: [String: Any] = [
            "CurrentCapacity": 80, "ExternalConnected": true, "IsCharging": false, "CycleCount": 214,
            "DesignCycleCount9C": 1000, "Voltage": 12480, "Amperage": -390,
            "AdapterDetails": ["Watts": 35, "Name": "35W USB-C Power Adapter "],
            "BatteryData": ["DesignCapacity": 5760, "FullChargeCapacity": 5285],
        ]
        let snapshot = try #require(
            BatterySnapshot.parse(
                registry: registry, temperature: 28.7, wallPower: 0.6, systemPower: 5.3, date: .now))
        #expect(snapshot.percent == 80)
        #expect(snapshot.adapterName == "35W USB-C Power Adapter")
        #expect(snapshot.cycleCount == 214)
        #expect(abs((snapshot.health ?? 0) - 0.9175) < 0.001)
        #expect(abs(snapshot.batteryPower - -4.8672) < 0.001)
        #expect(snapshot.isPluggedIn)
    }

    /// Cutting wall power makes the registry report no charger; AC-W still sees it.
    @Test func chargerStaysAttachedWhileWallPowerIsCut() throws {
        let registry: [String: Any] = ["CurrentCapacity": 86, "ExternalConnected": false]
        let cut = try #require(
            BatterySnapshot.parse(
                registry: registry, chargerAttached: true, temperature: nil, wallPower: nil, systemPower: nil,
                date: .now))
        #expect(cut.isPluggedIn)
        let fallback = try #require(
            BatterySnapshot.parse(
                registry: registry, temperature: nil, wallPower: nil, systemPower: nil, date: .now))
        #expect(!fallback.isPluggedIn)
    }

    /// Captured from /Library/Preferences/com.apple.powerd.charging.plist on macOS 27 with an 80% limit.
    static let powerdPolicies = Data(
        base64Encoded:
            "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGoCwwSJCUpLzNVJG51bGzSDQ4PEVpOUy5vYmplY3RzViRjbGFzc6EQgAKAB9kTFBUOFhcYGRobHB0eHyAgHyNWcmVhc29uVW93bmVyWHNvY2xpbWl0VWRyYWluWnRlcm1pbmF0ZWRebm9DaGFyZ2VUb0Z1bGxdaXNFbmRPZkNoYXJnZVV0b2tlboADEVilEFCABgkICAmABF8QEW1hbnVhbENoYXJnZUxpbWl00iYOJyhcTlMudXVpZGJ5dGVzTxAQCIhcxst5QluUAjdDu12IdIAF0iorLC1aJGNsYXNzbmFtZVgkY2xhc3Nlc1ZOU1VVSUSiLC5YTlNPYmplY3TSKiswMV8QEENoYXJnZUN0cmxQb2xpY3miMi5fEBBDaGFyZ2VDdHJsUG9saWN50iorNDVeTlNNdXRhYmxlQXJyYXmjNDYuV05TQXJyYXkACAARABoAJAApADIANwBJAEwAUQBTAFwAYgBnAHIAeQB7AH0AfwCSAJkAnwCoAK4AuQDIANYA3ADeAOEA4wDlAOYA5wDoAOkA6wD/AQQBEQEkASYBKwE2AT8BRgFJAVIBVwFqAW0BgAGFAZQBmAAAAAAAAAIBAAAAAAAAADcAAAAAAAAAAAAAAAAAAAGg"
    )!

    @Test func readsMacOSChargeLimit() throws {
        #expect(NativeChargeLimit.activeLimit(inArchive: Self.powerdPolicies) == 80)
        #expect(NativeChargeLimit.drainsAboveLimit(inArchive: Self.powerdPolicies))
        let preferences = try PropertyListSerialization.data(
            fromPropertyList: ["bootSessionUUID": "A", "policies": Self.powerdPolicies], format: .binary,
            options: 0)
        #expect(NativeChargeLimit.limit(inPreferences: preferences, bootSession: "A") == 80)
        #expect(NativeChargeLimit.limit(inPreferences: preferences, bootSession: "B") == nil)
    }

    @Test func observerLogsRealChangesAndIgnoresBlips() {
        var observer = PowerObserver()
        func power(_ current: Double, wall: Bool = true, limit: Int? = 75) -> ObservedPower {
            ObservedPower(
                percent: 75, chargerAttached: true, wallPowerConnected: wall, current: current, macOSLimit: limit)
        }
        #expect(
            observer.changes(power(0)) == [
                "charger plugged in", "macOS charge limit is 75%", "battery idle; the charger runs the Mac",
            ])
        #expect(observer.changes(power(-0.03)).isEmpty)
        #expect(observer.changes(power(-0.5)).isEmpty)
        #expect(observer.changes(power(0)).isEmpty)
        #expect(
            observer.changes(power(-0.75, wall: false, limit: nil)) == [
                "wall power cut; the battery runs the Mac", "macOS charge limit is off",
            ])
        #expect(
            observer.changes(power(-0.75, wall: false, limit: nil)) == [
                "battery discharging at 0.75 A with the charger plugged in"
            ])
    }

    @Test func settingsChangesNameOnlyWhatChanged() {
        var new = ChargeSettings()
        new.limit = 75
        new.autoDischarge = true
        #expect(new.changes(from: ChargeSettings()) == ["limit 80% → 75%", "automatic discharge off → on"])
    }
}
