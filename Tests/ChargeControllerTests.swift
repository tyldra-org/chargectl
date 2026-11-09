import Foundation
import Testing

/// The daemon's control loop against stand-ins for the battery, the wall-power switch and
/// macOS's charge limit, with its files in a temporary folder.
@Suite struct ChargeControllerTests {
    @Test func firstRunStartsFromTheMacOSLimit() {
        let rig = Rig(macOSLimit: .init(isEnabled: true, limit: 75))
        defer { rig.remove() }
        rig.start()
        #expect(rig.controller.status().settings.limit == 75)
        #expect(rig.store.load(ChargeSettings.self, from: .settings)?.limit == 75)
    }

    @Test func firstRunWithTheMacOSLimitOffStartsAt100() {
        let rig = Rig(macOSLimit: .init(isEnabled: false, limit: 80))
        defer { rig.remove() }
        rig.start()
        #expect(rig.controller.status().settings.limit == 100)
    }

    @Test func aLimitChosenInSystemSettingsBecomesTheLimit() {
        let rig = Rig(settings: .limit(80, sailing: 5))
        defer { rig.remove() }
        rig.battery.percent = 60
        rig.start()
        rig.macOSLimit.setting = .init(isEnabled: true, limit: 85)
        rig.controller.tick()
        #expect(rig.controller.status().settings.limit == 85)
        #expect(rig.store.load(ChargeSettings.self, from: .settings)?.limit == 85)
    }

    /// PowerUIAgent may refuse limits below 80%; the limit is then held by cutting wall power.
    @Test func aRefusedLowLimitIsHeldByCuttingWallPower() {
        let rig = Rig(settings: .limit(60, sailing: 5))
        defer { rig.remove() }
        rig.macOSLimit.lowest = 80
        rig.battery.percent = 60
        rig.start()
        #expect(!rig.wallPower.connected)
        #expect(rig.controller.logEntries().contains { $0.message.contains("held by switching wall power") })
    }

    @Test func sleepReconnectsWallPower() {
        let rig = Rig(settings: .limit(60, sailing: 5))
        defer { rig.remove() }
        rig.battery.percent = 70
        rig.start()
        #expect(!rig.wallPower.connected)
        rig.controller.prepareForSleep()
        #expect(rig.wallPower.connected)
    }

    @Test func sleepKeepsWallPowerCutWhenDischargingAsleep() {
        var settings = ChargeSettings.limit(60, sailing: 5)
        settings.holdAsleep = true
        let rig = Rig(settings: settings)
        defer { rig.remove() }
        rig.battery.percent = 70
        rig.start()
        rig.controller.prepareForSleep()
        #expect(!rig.wallPower.connected)
    }

    @Test func stoppingTheHelperReconnectsWallPower() {
        let rig = Rig(settings: .limit(60, sailing: 5))
        defer { rig.remove() }
        rig.battery.percent = 70
        rig.start()
        rig.controller.shutdown()
        #expect(rig.wallPower.connected)
    }

    /// Without a reading nothing can be decided; the Mac must not keep running on its battery.
    @Test func wallPowerComesBackWhenTheBatteryCannotBeRead() {
        let rig = Rig(settings: .limit(60, sailing: 5))
        defer { rig.remove() }
        rig.battery.percent = 70
        rig.start()
        #expect(!rig.wallPower.connected)
        rig.battery.isReadable = false
        rig.controller.tick()
        rig.controller.tick()
        #expect(!rig.wallPower.connected)
        rig.controller.tick()
        #expect(rig.wallPower.connected)
    }

    /// PowerUIAgent can be slow; each tick asks it for the limit once.
    @Test func macOSLimitIsReadOncePerTick() {
        let rig = Rig(settings: .limit(80, sailing: 5))
        defer { rig.remove() }
        rig.battery.percent = 60
        rig.start()
        rig.macOSLimit.reads = 0
        rig.controller.tick()
        #expect(rig.macOSLimit.reads == 1)
    }

    /// The XPC service answers from the board, without waiting for the main actor.
    @Test func theBoardFollowsEveryChange() {
        let rig = Rig(settings: .limit(80, sailing: 5))
        defer { rig.remove() }
        rig.battery.percent = 64
        rig.start()
        var changed = rig.controller.status().settings
        changed.limit = 70
        rig.controller.update(changed)
        #expect(rig.controller.board.status?.settings.limit == 70)
        #expect(rig.controller.board.history.last?.percent == 64)
        #expect(rig.controller.board.logs.last?.message == rig.controller.logEntries().last?.message)
    }

    /// Without macOS's limit, charging during sleep would run past the limit.
    @Test func sleepKeepsALimitMacOSCannotHold() {
        let rig = Rig(settings: .limit(60, sailing: 5))
        defer { rig.remove() }
        rig.battery.percent = 60
        rig.controller.finishStarting(macOSLimit: nil)
        rig.wallPower.connected = true
        rig.controller.prepareForSleep()
        #expect(!rig.wallPower.connected)
    }

    @Test func sleepChargesALowBatteryAnyway() {
        let rig = Rig(settings: .limit(60, sailing: 5))
        defer { rig.remove() }
        rig.battery.percent = 25
        rig.controller.finishStarting(macOSLimit: nil)
        #expect(rig.wallPower.connected)
        rig.controller.prepareForSleep()
        #expect(rig.wallPower.connected)
    }

    @Test func aSwitchThatDoesNothingIsReported() {
        let rig = Rig(settings: .limit(60, sailing: 5))
        defer { rig.remove() }
        rig.battery.percent = 70
        rig.battery.current = 2
        rig.start()
        #expect(!rig.wallPower.connected)
        for _ in 0..<ControlCheck.readings { rig.controller.tick() }
        #expect(rig.controller.status().controlProblem != nil)
    }

    @Test func aStoppedFullByDoesNotStartAgain() throws {
        var settings = ChargeSettings.limit(80, sailing: 5)
        settings.fullBy = try #require(
            FullBySchedule.once(hour: 0, minute: 0, after: .now, calendar: .current).map {
                var schedule = $0
                schedule.once = Date.now.addingTimeInterval(1800)
                return schedule
            })
        let rig = Rig(settings: settings)
        defer { rig.remove() }
        rig.battery.percent = 85
        rig.start()
        guard case .fullBy = rig.controller.status().mode else {
            Issue.record("Full by did not start")
            return
        }
        _ = rig.controller.perform(.stop)
        rig.controller.tick()
        #expect(rig.controller.status().mode == .automatic)
    }

    @Test func eachDayIsSummedUpOnce() {
        let rig = Rig(settings: .limit(80, sailing: 5))
        defer { rig.remove() }
        let today = Calendar.current.startOfDay(for: .now)
        let lateYesterday = HistorySample(
            date: today.addingTimeInterval(-60), percent: 92, temperature: 31, systemPower: 8, wallPower: 30,
            batteryPower: 0)
        rig.store.replaceLines([lateYesterday], in: .history)
        let controller = ChargeController(store: rig.store, smc: nil, battery: rig.battery, wallPower: rig.wallPower)
        controller.finishStarting(macOSLimit: rig.macOSLimit)
        controller.tick(now: .now.addingTimeInterval(120))
        controller.tick(now: .now.addingTimeInterval(240))
        #expect(controller.board.daily.map(\.minutesHighCharge) == [1])
        #expect(rig.store.loadLines(DailySample.self, from: .daily).count == 1)
    }

    @Test func turningChargeControlOffRestoresTheUsersMacOSLimit() {
        let rig = Rig(settings: .limit(80, sailing: 5), macOSLimit: .init(isEnabled: true, limit: 90))
        defer { rig.remove() }
        rig.battery.percent = 60
        rig.start()
        #expect(rig.macOSLimit.setting == .init(isEnabled: true, limit: 80))
        var off = rig.controller.status().settings
        off.isEnabled = false
        rig.controller.update(off)
        #expect(rig.macOSLimit.setting == .init(isEnabled: true, limit: 90))
        #expect(rig.store.load(MacOSChargeLimit.Setting.self, from: .macOSLimit) == nil)
    }

    @Test func historyAndLogsSurviveARestart() {
        let rig = Rig(settings: .limit(80, sailing: 5))
        defer { rig.remove() }
        rig.battery.percent = 64
        rig.start()
        var changed = rig.controller.status().settings
        changed.limit = 70
        rig.controller.update(changed)

        let restarted = ChargeController(store: rig.store, smc: nil, battery: rig.battery, wallPower: rig.wallPower)
        #expect(restarted.historySamples().last?.percent == 64)
        #expect(restarted.logEntries().contains { $0.message == "settings: limit 80% → 70%" })
    }

    /// Recording appends a line; the files are rewritten only to drop old entries.
    @Test func historyIsAppendedOneLineAtATime() throws {
        let rig = Rig(settings: .limit(80, sailing: 5))
        defer { rig.remove() }
        rig.start()
        let file = rig.store.directory.appendingPathComponent("history.jsonl")
        let start = Date.now
        for minute in 1...5 {
            rig.controller.tick(now: start.addingTimeInterval(Double(minute) * 61))
        }
        let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 6)
        #expect(rig.controller.historySamples().count == 6)
    }

    @Test func historyFromOlderVersionsMovesToLines() {
        let rig = Rig(settings: .limit(80, sailing: 5))
        defer { rig.remove() }
        let old = (1...3).map { minute in
            HistorySample(
                date: .now.addingTimeInterval(Double(-minute) * 60 - 600), percent: 50 + minute, temperature: 30,
                systemPower: 8, wallPower: 30, batteryPower: 10)
        }
        rig.store.save(Array(old.reversed()), to: .history)
        let controller = ChargeController(store: rig.store, smc: nil, battery: rig.battery, wallPower: rig.wallPower)
        controller.finishStarting(macOSLimit: rig.macOSLimit)
        let files = FileManager.default
        #expect(!files.fileExists(atPath: rig.store.directory.appendingPathComponent("history.json").path))
        #expect(rig.store.loadLines(HistorySample.self, from: .history).prefix(3).map(\.percent) == [53, 52, 51])
        #expect(controller.historySamples().count == 4)
    }
}

/// A controller wired to fakes, with its files in a fresh temporary folder.
private struct Rig {
    let store: Store
    let battery = FakeBattery()
    let wallPower = FakeWallPower()
    let macOSLimit = FakeMacOSLimit()
    let controller: ChargeController

    init(settings: ChargeSettings? = nil, macOSLimit setting: MacOSChargeLimit.Setting = .default) {
        store = Store(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(
                "ChargeControllerTests-\(UUID().uuidString)", isDirectory: true))
        if let settings { store.save(settings, to: .settings) }
        macOSLimit.setting = setting
        controller = ChargeController(store: store, smc: nil, battery: battery, wallPower: wallPower)
    }

    func start() {
        controller.finishStarting(macOSLimit: macOSLimit)
    }

    func remove() {
        try? store.removeAll()
    }
}

extension MacOSChargeLimit.Setting {
    /// macOS's own default: on, at 80%.
    static let `default` = Self(isEnabled: true, limit: 80)
}

private final class FakeBattery: BatterySource {
    var percent = 70
    var pluggedIn = true
    var isReadable = true
    var current = 0.0

    func read(now: Date) throws -> BatterySnapshot {
        guard isReadable else { throw BatteryReadError.unreadable }
        return BatterySnapshot(
            date: now, percent: percent, isPluggedIn: pluggedIn, isCharging: current > 0, cycleCount: 100,
            designCycleCount: 1000, designCapacity: 5760, fullChargeCapacity: 5000, voltage: 12, current: current,
            temperature: 30, adapterWatts: pluggedIn ? 35 : nil, adapterName: nil, wallPower: pluggedIn ? 20 : 0,
            systemPower: 8, chargerVoltage: nil, chargerCurrent: nil, adapterVoltage: nil, minutesToFull: nil,
            minutesToEmpty: nil)
    }
}

private final class FakeWallPower: WallPowerSwitch {
    let key = "CHIE"
    var connected = true

    func isConnected() throws -> Bool { connected }

    func set(connected: Bool) throws {
        self.connected = connected
    }
}

/// PowerUIAgent's charge limit. @unchecked: tests use it only from the main actor.
private nonisolated final class FakeMacOSLimit: MacOSLimitControl, @unchecked Sendable {
    var setting = MacOSChargeLimit.Setting(isEnabled: true, limit: 80)
    /// The lowest limit it accepts.
    var lowest = ChargeSettings.limitRange.lowerBound
    /// Calls to current().
    var reads = 0

    func current() throws -> MacOSChargeLimit.Setting {
        reads += 1
        return setting
    }

    func isOptimizedChargingEnabled() -> Bool? { false }

    func apply(_ setting: MacOSChargeLimit.Setting) throws {
        if setting.isEnabled {
            try set(limit: setting.limit)
        } else {
            self.setting.isEnabled = false
        }
    }

    func set(limit: Int) throws {
        if limit >= 100 {
            setting.isEnabled = false
            return
        }
        guard limit >= lowest else {
            throw MacOSChargeLimit.LimitError.notApplied(requested: limit, actual: setting.limit)
        }
        setting = .init(isEnabled: true, limit: limit)
    }
}
