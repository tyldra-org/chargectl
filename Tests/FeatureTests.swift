import Foundation
import Testing

/// Full by, the long-term record, and the checks that notice when charging is not going as it
/// should.
@Suite struct FeatureTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    /// Sunday 8 November 2026, 6:00 in Berlin.
    var sunday6am: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 6))! }

    // MARK: Full by schedule

    @Test func weekdaysSkipTheWeekend() {
        let schedule = FullBySchedule(hour: 8, minute: 0, weekdays: FullBySchedule.weekdaysOnly)
        let next = schedule.nextDeadline(after: sunday6am, calendar: calendar)
        #expect(next == calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 8)))
    }

    @Test func everyDayIsLaterToday() {
        let schedule = FullBySchedule(hour: 8, minute: 30, weekdays: FullBySchedule.everyDay)
        #expect(
            schedule.nextDeadline(after: sunday6am, calendar: calendar)
                == calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 8, minute: 30)))
    }

    @Test func aOneOffEndsOnceItPasses() throws {
        let schedule = try #require(FullBySchedule.once(hour: 7, minute: 0, after: sunday6am, calendar: calendar))
        #expect(schedule.nextDeadline(after: sunday6am, calendar: calendar) == schedule.once)
        #expect(schedule.nextDeadline(after: schedule.once!.addingTimeInterval(1), calendar: calendar) == nil)
    }

    @Test func aSkippedTimeGivesWayToTheNextOne() throws {
        let schedule = FullBySchedule(hour: 8, minute: 0, weekdays: FullBySchedule.weekdaysOnly)
        let monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 8)))
        let tuesday = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 8)))
        #expect(schedule.nextDeadline(after: sunday6am, skipping: monday, calendar: calendar) == tuesday)
        #expect(schedule.nextDeadline(after: sunday6am, skipping: nil, calendar: calendar) == monday)
        // A skip that is not the next time changes nothing.
        #expect(schedule.nextDeadline(after: sunday6am, skipping: tuesday, calendar: calendar) == monday)
    }

    /// Days outside 1...7 only come from a damaged settings file; they must not crash the helper.
    @Test func aDamagedScheduleStillDescribesItself() {
        let schedule = FullBySchedule(hour: 8, minute: 0, weekdays: [0, 2, 8])
        #expect(schedule.summary.hasSuffix("at 8:00"))
        #expect(schedule.summary.split(separator: ",").count == 1)
    }

    @Test func onlyHelpersWithTheDailyRecordAreAskedForIt() {
        #expect(DaemonIdentity.hasDailyHistory("0.2.0"))
        #expect(DaemonIdentity.hasDailyHistory("0.2.3"))
        #expect(DaemonIdentity.hasDailyHistory("1.0.0"))
        #expect(!DaemonIdentity.hasDailyHistory("0.1.11"))
        #expect(!DaemonIdentity.hasDailyHistory("unknown"))
    }

    @Test func leadTimeGrowsAsTheChargeFalls() {
        #expect(FullBySchedule.leadTime(from: 100) == FullBySchedule.margin)
        #expect(FullBySchedule.leadTime(from: 80) == 50 * 60 + FullBySchedule.margin)
        #expect(FullBySchedule.leadTime(from: 50) > FullBySchedule.leadTime(from: 80))
    }

    @Test func settingsWithoutADayDropTheSchedule() {
        var settings = ChargeSettings()
        settings.fullBy = FullBySchedule(hour: 8, minute: 0)
        #expect(settings.normalized().fullBy == nil)
        settings.fullBy = FullBySchedule(hour: 25, minute: 75, weekdays: [0, 2, 9])
        #expect(settings.normalized().fullBy == FullBySchedule(hour: 23, minute: 59, weekdays: [2]))
    }

    // MARK: Full by in the policy

    func decide(_ percent: Int, at now: Date, fullBy: Date?, state: ControlState = ControlState()) -> ChargeDecision {
        ChargePolicy.decide(
            PolicyInput(percent: percent, isPluggedIn: true, temperature: 30, canSetMacOSLimit: true, fullBy: fullBy),
            settings: .limit(80, sailing: 5), state: state, now: now)
    }

    @Test func fullByWaitsUntilItIsTimeToStart() {
        let deadline = sunday6am.addingTimeInterval(3 * 3600)
        let early = decide(80, at: sunday6am, fullBy: deadline)
        #expect(early.state.mode == .automatic)
        #expect(early.macOSLimit == 80)
    }

    @Test func fullByChargesToFullBeforeItsTime() {
        let deadline = sunday6am.addingTimeInterval(3600)
        let started = decide(80, at: sunday6am, fullBy: deadline)
        #expect(started.state.mode == .fullBy(deadline))
        #expect(started.activity == .chargingFull(by: deadline))
        #expect(started.macOSLimit == 100)
        #expect(started.state.adapterEnabled)
        let full = decide(100, at: deadline.addingTimeInterval(-60), fullBy: deadline, state: started.state)
        #expect(full.activity == .full)
        #expect(full.state.mode == .fullBy(deadline))
    }

    @Test func fullByEndsAtItsTime() {
        let deadline = sunday6am.addingTimeInterval(3600)
        let started = decide(80, at: sunday6am, fullBy: deadline)
        #expect(started.state.mode == .fullBy(deadline))
        let after = decide(100, at: deadline, fullBy: nil, state: started.state)
        #expect(after.state.mode == .automatic)
        #expect(after.event?.contains("full charge time reached") == true)
    }

    // MARK: Long-term record

    @Test func aDaySumsUpItsMinutes() throws {
        let day = calendar.startOfDay(for: sunday6am)
        var samples: [HistorySample] = []
        for minute in 0..<120 {
            let date = day.addingTimeInterval(Double(minute) * 60)
            let percent = minute < 30 ? 95 : 70
            let temperature: Double = minute < 60 ? 30 : 34
            let wall: Double = minute < 90 ? 30 : 0
            samples.append(
                HistorySample(
                    date: date, percent: percent, temperature: temperature, systemPower: 8, wallPower: wall,
                    batteryPower: 0))
        }
        samples.append(
            HistorySample(
                date: day.addingTimeInterval(-60), percent: 100, temperature: 50, systemPower: 8, wallPower: 30,
                batteryPower: 0))
        let sample = try #require(
            DailySample.summarize(day: day, samples: samples, battery: battery(), calendar: calendar))
        #expect(sample.minutesRecorded == 120)
        #expect(sample.minutesPlugged == 90)
        #expect(sample.minutesHighCharge == 30)
        #expect(sample.averageTemperature == 32)
        #expect(sample.maxTemperature == 34)
        #expect(sample.health == 5000.0 / 5760)
    }

    @Test func aDayWithoutReadingsIsSkipped() {
        #expect(DailySample.summarize(day: sunday6am, samples: [], battery: battery(), calendar: calendar) == nil)
    }

    // MARK: Checks

    @Test func cuttingPowerThatDoesNothingIsNoticed() {
        var check = ControlCheck()
        for _ in 1..<ControlCheck.readings { check.observe(wallPowerCut: true, pluggedIn: true, current: 2) }
        #expect(check.problem == nil)
        check.observe(wallPowerCut: true, pluggedIn: true, current: 2)
        #expect(check.problem != nil)
        check.observe(wallPowerCut: true, pluggedIn: true, current: -1)
        #expect(check.problem == nil)
    }

    @Test func connectedPowerIsNotAControlProblem() {
        var check = ControlCheck()
        for _ in 0..<20 { check.observe(wallPowerCut: false, pluggedIn: true, current: 2) }
        #expect(check.problem == nil)
    }

    @Test func aWeakChargerShowsAfterAMinute() {
        var check = ChargerCheck()
        let start = sunday6am
        check.observe(battery(current: -0.8), wallPowerCut: false, drainsOnPurpose: false, now: start)
        #expect(!check.isWeak)
        check.observe(battery(current: -0.8), wallPowerCut: false, drainsOnPurpose: false, now: start + 61)
        #expect(check.isWeak)
        check.observe(battery(current: 0.5), wallPowerCut: false, drainsOnPurpose: false, now: start + 62)
        #expect(!check.isWeak)
    }

    @Test func drainingOnPurposeIsNotAWeakCharger() {
        var check = ChargerCheck()
        check.observe(battery(current: -0.8), wallPowerCut: false, drainsOnPurpose: true, now: sunday6am)
        check.observe(battery(current: -0.8), wallPowerCut: false, drainsOnPurpose: true, now: sunday6am + 120)
        #expect(!check.isWeak)
        check.observe(battery(current: -0.8), wallPowerCut: true, drainsOnPurpose: false, now: sunday6am + 240)
        #expect(!check.isWeak)
    }

    // MARK: Events

    @Test func eventsComeFromChanges() {
        var old = StatusSnapshot(activity: .charging(to: 80), mode: .topUp)
        var new = StatusSnapshot(activity: .holding(80), mode: .automatic)
        #expect(StatusSnapshot.events(from: old, to: new) == [.limitReached(80), .jobFinished("top up")])
        old = new
        new.activity = .heatPaused
        new.weakCharger = true
        new.adapterWatts = 30
        new.helperProblem = "The helper stopped."
        new.controlProblem = true
        #expect(
            StatusSnapshot.events(from: old, to: new) == [
                .tooWarm, .helperStopped("The helper stopped."), .weakCharger(30), .controlNotWorking,
            ])
        #expect(StatusSnapshot.events(from: new, to: new).isEmpty)
    }

    private func battery(current: Double = 0) -> BatterySnapshot {
        BatterySnapshot(
            date: sunday6am, percent: 70, isPluggedIn: true, isCharging: current > 0, cycleCount: 120,
            designCycleCount: 1000, designCapacity: 5760, fullChargeCapacity: 5000, voltage: 12, current: current,
            temperature: 30, adapterWatts: 30, adapterName: nil, wallPower: 20, systemPower: 8, chargerVoltage: nil,
            chargerCurrent: nil, adapterVoltage: nil, minutesToFull: nil, minutesToEmpty: nil)
    }
}
