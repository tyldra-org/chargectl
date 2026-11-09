#if DEBUG
    import AppKit
    import SwiftUI
    import WidgetKit

    /// Debug builds only: `Chargectl --render-design <folder>` draws every page and the menu bar
    /// panel with fixed sample data, in light and dark, into PNG files, then quits. It never talks
    /// to the helper, so it is safe on a Mac whose charging Chargectl controls.
    enum DesignRender {
        static func runIfRequested() {
            let arguments = CommandLine.arguments
            guard let index = arguments.firstIndex(of: "--render-design"), index + 1 < arguments.count else { return }
            let folder = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let app = NSApplication.shared
            app.setActivationPolicy(.prohibited)
            if arguments.contains("--island-frames") {
                islandFrames(to: folder)
                exit(0)
            }
            let only = arguments.firstIndex(of: "--only").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
            for shot in shots() where only.map({ shot.name.contains($0) }) ?? true {
                for dark in [true, false] {
                    render(
                        shot, dark: dark,
                        to: folder.appendingPathComponent("\(shot.name)-\(dark ? "dark" : "light").png"))
                }
            }
            exit(0)
        }

        /// Frames of the status island opening and closing for a confirmation, to check the motion.
        private static func islandFrames(to folder: URL) {
            let model = Sample.model()
            let window = NSWindow(
                contentRect: NSRect(x: -20000, y: -20000, width: 420, height: 110), styleMask: [.borderless],
                backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = NSHostingView(
                rootView: StatusIsland(model: model).frame(width: 420, height: 110, alignment: .top).padding(.top, 10)
                    .background(Theme.window))
            window.orderFrontRegardless()
            RunLoop.main.run(until: Date.now.addingTimeInterval(0.5))
            func capture(_ index: Int) {
                guard let view = window.contentView,
                    let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
                else { return }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let file = folder.appendingPathComponent(String(format: "island-%03d.png", index))
                if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: file) }
            }
            model.update { $0.limit = 76 }
            Confirmations.shared.show("Limit set to 76%")
            for index in 0..<140 {
                capture(index)
                RunLoop.main.run(until: Date.now.addingTimeInterval(1.0 / 30))
            }
        }

        private struct Shot {
            let name: String
            let size: CGSize
            let view: () -> AnyView
        }

        private static func shots() -> [Shot] {
            let dashboard = CGSize(width: 1160, height: 860)
            let panel = CGSize(width: 340, height: 470)
            var shots: [Shot] = []
            for page in DashboardPage.allCases {
                shots.append(
                    Shot(name: page.rawValue, size: dashboard) {
                        AnyView(DashboardView(model: Sample.model(), initialPage: page))
                    })
            }
            for page in [DashboardPage.overview, .control, .history, .settings] {
                shots.append(
                    // The window's default width, so these show the layout people first see.
                    Shot(name: "\(page.rawValue)-scrolled", size: CGSize(width: 1080, height: 1560)) {
                        AnyView(DashboardView(model: Sample.model(), initialPage: page))
                    })
            }
            shots.append(
                Shot(name: "control-heat-off", size: dashboard) {
                    AnyView(DashboardView(model: Sample.model(heat: true, enabled: false), initialPage: .control))
                })
            for page in [DashboardPage.control, .history, .logs] {
                shots.append(
                    Shot(name: "\(page.rawValue)-no-helper", size: dashboard) {
                        AnyView(DashboardView(model: Sample.model(service: .notInstalled), initialPage: page))
                    })
            }
            shots.append(
                Shot(name: "logs-warning", size: dashboard) {
                    AnyView(DashboardView(model: Sample.model(warning: true), initialPage: .logs))
                })
            shots.append(
                Shot(name: "panel", size: panel) { AnyView(MenuContent(model: Sample.model(tiles: true))) })
            shots.append(
                Shot(name: "panel-discharging", size: panel) {
                    AnyView(MenuContent(model: Sample.model(percent: 88, mode: .discharge(to: 80))))
                })
            shots.append(
                Shot(name: "panel-no-helper", size: panel) {
                    AnyView(MenuContent(model: Sample.model(service: .notInstalled)))
                })
            shots.append(Shot(name: "menu-bar-icons", size: CGSize(width: 520, height: 300)) { AnyView(IconSheet()) })
            shots.append(
                Shot(name: "readme-widgets", size: WidgetSheet.collageSize) {
                    AnyView(WidgetSheet(entry: .sample(.charging), kinds: true, collage: true))
                })
            for sample in BatteryEntry.Sample.allCases {
                shots.append(
                    Shot(name: "widgets-charge-\(sample.rawValue)", size: CGSize(width: 1240, height: 860)) {
                        AnyView(WidgetSheet(entry: .sample(sample), kinds: false))
                    })
                shots.append(
                    Shot(name: "widgets-kinds-\(sample.rawValue)", size: CGSize(width: 1240, height: 860)) {
                        AnyView(WidgetSheet(entry: .sample(sample), kinds: true))
                    })
                shots.append(
                    Shot(name: "widgets-portrait-\(sample.rawValue)", size: CGSize(width: 440, height: 880)) {
                        AnyView(WidgetSheet(entry: .sample(sample), kinds: false, portrait: true))
                    })
            }
            let setup: [(String, WelcomeView.Step, ServiceState)] = [
                ("welcome-1", .welcome, .running), ("welcome-2-install", .helper, .notInstalled),
                ("welcome-2-approval", .helper, .needsApproval), ("welcome-2-running", .helper, .running),
                ("welcome-3", .limit, .running), ("welcome-3-no-helper", .limit, .notInstalled),
                ("welcome-4", .done, .running),
            ]
            for (name, step, service) in setup {
                shots.append(
                    Shot(name: name, size: CGSize(width: WelcomeView.size.width, height: WelcomeView.size.height + 32))
                    {
                        // Below the real window's 32-point title bar, as in the app.
                        AnyView(
                            WelcomeView(model: Sample.model(service: service), initialStep: step)
                                .padding(.top, 32)
                                .background(Theme.window))
                    })
            }
            return shots
        }

        private static func render(_ shot: Shot, dark: Bool, to file: URL) {
            let isPanel = shot.name.hasPrefix("panel")
            let window = NSWindow(
                contentRect: NSRect(origin: CGPoint(x: -20000, y: -20000), size: shot.size),
                // No title bar, so the content is exactly the shot's size; the welcome shots add
                // the title bar's space themselves.
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let root = shot.view()
                .frame(width: shot.size.width, height: isPanel ? nil : shot.size.height, alignment: .top)
                .fixedSize(horizontal: false, vertical: isPanel)
            let hosting = NSHostingView(rootView: root)
            if isPanel {
                let effect = NSVisualEffectView()
                effect.material = .popover
                effect.state = .active
                effect.blendingMode = .behindWindow
                hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
                effect.frame = hosting.frame
                effect.addSubview(hosting)
                window.setContentSize(hosting.fittingSize)
                window.contentView = effect
            } else {
                window.contentView = hosting
            }
            window.orderFrontRegardless()
            // Setup's first ring charges up for about two seconds.
            RunLoop.main.run(until: Date.now.addingTimeInterval(shot.name.hasPrefix("welcome") ? 2.6 : 1.6))
            guard let view = window.contentView else { return }
            let bounds = view.bounds
            // 2x whatever screen the window would be on, so the files are sharp on Retina displays.
            guard
                let bitmap = NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2), pixelsHigh: Int(bounds.height * 2),
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                    bytesPerRow: 0, bitsPerPixel: 0)
            else { return }
            bitmap.size = bounds.size
            view.cacheDisplay(in: bounds, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: file) }
            window.orderOut(nil)
        }
    }

    /// Every widget kind and size on a desktop-like background, as WidgetKit lays them out.
    private struct WidgetSheet: View {
        let entry: BatteryEntry
        let kinds: Bool
        var portrait = false
        /// The README's picture: one of each kind, in the sizes that suit it.
        var collage = false
        @Environment(\.colorScheme) private var scheme

        /// macOS's desktop grid: a medium widget is two small ones and 24 points across, a large
        /// one two small ones and 42 points down.
        private static let across: CGFloat = 24
        private static let down: CGFloat = 42
        static let collageSize = CGSize(width: 364 * 3 + across * 2 + 96, height: 382 + down + 170 + 96)

        var body: some View {
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: scheme == .dark
                        ? [Color(red: 0.17, green: 0.16, blue: 0.3), Color(red: 0.36, green: 0.22, blue: 0.24)]
                        : [Color(red: 0.75, green: 0.84, blue: 0.96), Color(red: 0.97, green: 0.85, blue: 0.8)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
                if collage {
                    collageGrid.padding(48)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if portrait {
                    tile(.charge, .systemExtraLargePortrait).padding(28)
                } else if kinds {
                    kindsGrid.padding(28)
                } else {
                    chargeSizes.padding(28)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: collage ? 28 : 0, style: .continuous))
        }

        private var chargeSizes: some View {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .top, spacing: 24) {
                        tile(.charge, .systemSmall)
                        tile(.charge, .systemMedium)
                        tile(.ring, .systemSmall)
                    }
                    tile(.charge, .systemExtraLarge)
                }
                tile(.charge, .systemLarge)
            }
        }

        private var collageGrid: some View {
            VStack(alignment: .leading, spacing: Self.down) {
                HStack(alignment: .top, spacing: Self.across) {
                    tile(.charge, .systemLarge)
                    VStack(spacing: Self.down) {
                        tile(.controls, .systemMedium)
                        tile(.fullBy, .systemMedium)
                    }
                    VStack(spacing: Self.down) {
                        HStack(spacing: Self.across) {
                            tile(.ring, .systemSmall)
                            tile(.power, .systemSmall)
                        }
                        HStack(spacing: Self.across) {
                            tile(.health, .systemSmall)
                            tile(.timeLeft, .systemSmall)
                        }
                    }
                }
                HStack(spacing: Self.across) {
                    tile(.today, .systemMedium)
                    tile(.charge, .systemMedium)
                    tile(.health, .systemMedium)
                }
            }
        }

        private var kindsGrid: some View {
            let pairs: [ChargectlWidgetKind] = [.power, .health, .today, .fullBy, .controls, .timeLeft]
            return VStack(alignment: .leading, spacing: 24) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(alignment: .top, spacing: 24) {
                        ForEach(pairs[(row * 2)..<(row * 2 + 2)], id: \.self) { kind in
                            tile(kind, .systemSmall)
                            tile(kind, .systemMedium)
                        }
                    }
                }
            }
        }

        private func tile(_ kind: ChargectlWidgetKind, _ family: WidgetFamily) -> some View {
            let size: CGSize =
                switch family {
                case .systemSmall: CGSize(width: 170, height: 170)
                case .systemMedium: CGSize(width: 364, height: 170)
                case .systemLarge: CGSize(width: 364, height: 382)
                case .systemExtraLarge: CGSize(width: 764, height: 382)
                default: CGSize(width: 364, height: 782)
                }
            let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
            return ChargectlWidgetContent(kind: kind, family: family, entry: entry)
                .padding(16)
                .frame(width: size.width, height: size.height)
                .background(WidgetPalette(scheme: scheme).background, in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(scheme == .dark ? 0.09 : 0.05)))
                .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.12), radius: 14, y: 8)
        }
    }

    /// Menu bar icons on a dark and a light strip, for each state.
    private struct IconSheet: View {
        var body: some View {
            let rows: [(String, Double, Double?, RingIcon.Glyph, Bool)] = [
                ("Charging", 0.61, 0.8, .charging, false), ("At the limit", 0.8, 0.8, .holding, false),
                ("On battery", 0.54, 0.8, .none, false), ("Discharging", 0.88, 0.8, .discharging, false),
                ("Helper off", 0.61, nil, .attention, true),
            ]
            VStack(alignment: .leading, spacing: 10) {
                ForEach(rows, id: \.0) { title, fraction, limit, glyph, dashed in
                    HStack(spacing: 16) {
                        Text(title).font(.system(size: 13)).frame(width: 110, alignment: .leading)
                        ForEach([true, false], id: \.self) { dark in
                            HStack(spacing: 5) {
                                Image(
                                    nsImage: RingIcon.image(
                                        fraction: fraction, limit: limit, glyph: glyph, dashed: dashed, size: 32)
                                )
                                .renderingMode(.template)
                                Text("\(Int(fraction * 100))%").font(.system(size: 26, weight: .medium))
                                    .monospacedDigit()
                            }
                            .foregroundStyle(dark ? .white : Color(white: 0.11))
                            .padding(.horizontal, 12)
                            .frame(height: 46)
                            .background(
                                dark
                                    ? Color(red: 0.2, green: 0.15, blue: 0.27)
                                    : Color(red: 0.9, green: 0.92, blue: 0.97), in: RoundedRectangle(cornerRadius: 10))
                        }
                        ForEach([true, false], id: \.self) { dark in
                            Image(
                                nsImage: RingIcon.image(fraction: fraction, limit: limit, glyph: glyph, dashed: dashed)
                            )
                            .renderingMode(.template)
                            .foregroundStyle(dark ? .white : Color(white: 0.11))
                            .padding(6)
                            .background(
                                dark
                                    ? Color(red: 0.2, green: 0.15, blue: 0.27)
                                    : Color(red: 0.9, green: 0.92, blue: 0.97), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.window)
        }
    }

    /// Sample data that matches the design mockups.
    enum Sample {
        static func model(
            percent: Int = 61, service: ServiceState = .running, heat: Bool = false, enabled: Bool = true,
            tiles: Bool = false, warning: Bool = false, mode: ChargeMode = .automatic, manyLogs: Bool = false
        ) -> AppModel {
            let charging = mode == .automatic && percent < 80
            let draining = mode != .automatic
            let battery = BatterySnapshot(
                date: .now, percent: percent, isPluggedIn: !draining, isCharging: charging, cycleCount: 214,
                designCycleCount: 1000, designCapacity: 5760, fullChargeCapacity: 5234, voltage: 12.05,
                current: charging ? 2.13 : draining ? -1.03 : 0, temperature: 28.5, adapterWatts: 35,
                adapterName: "35 W USB-C Power Adapter", wallPower: draining ? 0 : charging ? 35.1 : 9.6,
                systemPower: draining ? 12.4 : charging ? 8.1 : 9.4, chargerVoltage: draining ? nil : 19.8,
                chargerCurrent: draining ? nil : 1.77, adapterVoltage: 20, minutesToFull: nil, minutesToEmpty: nil)
            var settings = ChargeSettings()
            settings.fullBy = FullBySchedule(hour: 8, minute: 0, weekdays: FullBySchedule.weekdaysOnly)
            settings.heatProtection = heat || tiles
            settings.autoDischarge = tiles
            settings.isEnabled = enabled
            let activity: ChargeActivity =
                switch mode {
                case .discharge(let target): .discharging(to: target)
                default: charging ? .charging(to: 80) : .holding(80)
                }
            let status =
                service == .running
                ? DaemonStatus(
                    version: DaemonIdentity.version, settings: settings, mode: mode,
                    activity: enabled ? activity : .off,
                    adapterEnabled: !draining, adapterKey: "CHIE", lastError: nil, optimizedChargingEnabled: false)
                : nil
            return AppModel(
                preview: battery, status: status, service: service, history: history(),
                logs: manyLogs ? Self.manyLogs() : logs(warning: warning),
                macOSLimit: 80, daily: daily())
        }

        /// Four months of the daily record: health easing from 92.4% to 90.9%, a few days held at
        /// 100% for travel.
        static func daily() -> [DailySample] {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: .now)
            return (1...120).reversed().compactMap { back -> DailySample? in
                guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
                let age = Double(120 - back) / 120
                let travel = back % 23 == 0 || back % 37 == 0
                return DailySample(
                    day: day, fullChargeCapacity: Int(5322 - 88 * age + 6 * sin(Double(back) * 0.7)),
                    designCapacity: 5760, cycleCount: 186 + Int(28 * age), minutesRecorded: 1440,
                    minutesPlugged: 900 + (back % 5) * 60,
                    minutesHighCharge: travel ? 160 + (back % 3) * 30 : (back % 4 == 0 ? 25 : 0),
                    averageTemperature: 29 + 2 * sin(Double(back) * 0.3),
                    maxTemperature: 32 + 3 * sin(Double(back) * 0.21) + (travel ? 2 : 0))
            }
        }

        /// One day, a point a minute: resting at 80%, a day on battery, charged back, unplugged
        /// overnight, plugged in again a few minutes ago.
        static func history() -> [HistorySample] {
            let now = Date.now
            func noise(_ m: Double, _ a: Double) -> Double {
                a * (sin(m * 0.045) + 0.5 * sin(m * 0.017 + 1)) / 1.5
            }
            return stride(from: -1440, through: 0, by: 1).map { minute in
                let m = Double(minute)
                var percent = 80.0
                var mac = 9.4
                var battery = 0.0
                var wall = 9.7
                var temperature = 27.6
                if m < -1180 {
                    mac += noise(m, 0.5)
                    temperature += noise(m, 0.3)
                } else if m < -850 {
                    let f = (m + 1180) / 330
                    percent = 80 - 38 * f
                    mac = 11 + 2.5 * sin(.pi * f) + noise(m, 1.4)
                    battery = -mac
                    wall = 0
                    temperature = 27.6 + 0.4 * f + 2.4 * sin(.pi * f)
                } else if m < -760 {
                    let f = (m + 850) / 90
                    percent = 42 + 38 * (1 - pow(1 - f, 1.35))
                    mac = 9.8 + noise(m, 0.4)
                    battery = 27 * (1 - 0.55 * f)
                    wall = mac + battery
                    temperature = 28 + 4.4 * sin(.pi * f * 0.9)
                } else if m < -274 {
                    let f = (m + 760) / 486
                    percent = 80 - 1.2 * f
                    mac = 8.6 + noise(m, 0.5)
                    wall = mac + 0.3
                    temperature = 27 + 2.36 * exp(-f * 5)
                } else if m < -8 {
                    let f = (m + 274) / 266
                    percent = 79 - 22 * f
                    mac = 7.2 + noise(m, 0.7)
                    battery = -mac
                    wall = 0
                    temperature = 26.7 + noise(m, 0.2)
                } else {
                    let f = (m + 8) / 8
                    percent = 57 + 4 * f
                    mac = 8.1
                    battery = 26.1 * min(1, 0.3 + f)
                    wall = mac + battery
                    temperature = 26.8 + 1.7 * f
                }
                return HistorySample(
                    date: now.addingTimeInterval(m * 60), percent: Int(percent.rounded()), temperature: temperature,
                    systemPower: mac, wallPower: wall, batteryPower: battery)
            }
        }

        /// Three days of a typical log, the last 300 entries like the helper keeps: plugging in and
        /// out, charging and holding, settings changes, a heat pause, a warning, two helper restarts.
        static func manyLogs() -> [LogEntry] {
            var entries: [LogEntry] = []
            var percent = 80
            var minute = -3 * 24 * 60
            var day = 0
            func add(_ message: String, _ source: LogEntry.Source?, level: LogEntry.Level = .info, offset: Double = 0) {
                entries.append(
                    LogEntry(
                        date: Date.now.addingTimeInterval(Double(minute) * 60 + offset), level: level, message: message,
                        percent: source == nil ? nil : percent, source: source))
            }
            func boot() {
                add("Chargectl was updated; restarting the helper", .chargectl, offset: -4)
                add("stopped; wall power reconnected", .chargectl, offset: -3)
                add("chargectld 0.1.10 started", nil)
                add("switching wall power with SMC key CHIE", nil)
                add(
                    "PowerUIAgent preferences: any host: MCLFeatureState=1 (__NSCFNumber), mclLimitValue=80 (__NSCFNumber)",
                    nil)
                add("starting with the macOS charge limit, 80%", .chargectl)
                add("macOS charge limit is 80%", .observed)
            }
            while minute < -10 {
                // A day: unplugged in the morning, battery in the afternoon, charged in the evening.
                add("charger unplugged", .observed)
                add("on battery", .chargectl)
                for _ in 0..<6 {
                    minute += 35
                    percent -= 4
                    add(String(format: "battery discharging at %.2f A", 0.5 + Double(percent % 7) / 10), .observed)
                }
                if day == 1 {
                    add("settings: limit 80% → 75%", .chargectl)
                    add("limits below 80% will be held by switching wall power", nil, level: .warning)
                    minute += 90
                    add("settings: limit 75% → 80%", .chargectl)
                }
                minute += 20
                add("charger plugged in", .observed)
                add("charging to 80%", .chargectl)
                for step in 0..<7 {
                    minute += 9
                    percent = min(80, percent + 3)
                    add(String(format: "battery charging at %.2f A", 2.4 - Double(step) * 0.12), .observed)
                    if day == 0, step == 3 {
                        add("too warm, charging paused", .chargectl)
                        minute += 12
                        add("charging to 80%", .chargectl)
                    }
                }
                minute += 6
                percent = 80
                add("battery idle; the charger runs the Mac", .observed)
                add("holding at 80%, running on the charger", .chargectl)
                if day == 0 { add("settings: sailing 3% → 5%", .chargectl) }
                if day == 0 || day == 2 {
                    minute += 30
                    boot()
                }
                minute += 300
                add("macOS kept charging past 80%; running on battery back to it", .chargectl)
                add("wall power cut; the battery runs the Mac", .observed)
                minute += 14
                add("wall power reconnected", .observed)
                add("holding at 80%, running on the charger", .chargectl)
                minute += 240
                day += 1
            }
            return Array(entries.filter { $0.date <= Date.now }.suffix(300))
        }

        static func logs(warning: Bool) -> [LogEntry] {
            let now = Date.now
            func at(_ seconds: Double) -> Date { now.addingTimeInterval(-seconds) }
            var entries: [LogEntry] = [
                LogEntry(date: at(86_100), level: .info, message: "charger unplugged", percent: 80, source: .observed),
                LogEntry(date: at(86_100), level: .info, message: "on battery", percent: 80, source: .chargectl),
                LogEntry(
                    date: at(86_095), level: .info, message: "battery discharging at 1.12 A", percent: 80,
                    source: .observed),
                LogEntry(
                    date: at(63_000), level: .info, message: "settings: sailing 3% → 5%", percent: 63,
                    source: .chargectl),
                LogEntry(date: at(51_000), level: .info, message: "charger plugged in", percent: 42, source: .observed),
                LogEntry(date: at(51_000), level: .info, message: "charging to 80%", percent: 42, source: .chargectl),
                LogEntry(
                    date: at(50_995), level: .info, message: "battery charging at 2.42 A", percent: 42,
                    source: .observed),
                LogEntry(
                    date: at(45_600), level: .info, message: "battery idle; the charger runs the Mac", percent: 80,
                    source: .observed),
                LogEntry(
                    date: at(45_600), level: .info, message: "holding at 80%, running on the charger", percent: 80,
                    source: .chargectl),
                LogEntry(date: at(16_440), level: .info, message: "charger unplugged", percent: 79, source: .observed),
                LogEntry(date: at(16_440), level: .info, message: "on battery", percent: 79, source: .chargectl),
                LogEntry(
                    date: at(16_435), level: .info, message: "battery discharging at 0.61 A", percent: 79,
                    source: .observed),
                LogEntry(
                    date: at(560), level: .info, message: "Chargectl was updated; restarting the helper", percent: 57,
                    source: .chargectl),
                LogEntry(
                    date: at(559), level: .info, message: "stopped; wall power reconnected", percent: 57,
                    source: .chargectl),
                LogEntry(date: at(556), level: .info, message: "chargectld 0.1.10 started", percent: nil, source: nil),
                LogEntry(
                    date: at(556), level: .info, message: "switching wall power with SMC key CHIE", percent: nil,
                    source: nil),
                LogEntry(
                    date: at(556), level: .info,
                    message:
                        "PowerUIAgent preferences: any host: MCLFeatureState=1 (__NSCFNumber), mclLimitValue=80 (__NSCFNumber)",
                    percent: nil, source: nil),
                LogEntry(
                    date: at(556), level: .info, message: "starting with the macOS charge limit, 80%", percent: nil,
                    source: .chargectl),
                LogEntry(
                    date: at(556), level: .info, message: "on battery, no charger", percent: 57, source: .observed),
                LogEntry(
                    date: at(556), level: .info, message: "macOS charge limit is 80%", percent: 57, source: .observed),
                LogEntry(
                    date: at(556), level: .info, message: "battery discharging at 0.52 A", percent: 57,
                    source: .observed),
                LogEntry(date: at(556), level: .info, message: "on battery", percent: 57, source: .chargectl),
                LogEntry(date: at(493), level: .info, message: "charger plugged in", percent: 57, source: .observed),
                LogEntry(date: at(493), level: .info, message: "charging to 80%", percent: 57, source: .chargectl),
                LogEntry(
                    date: at(483), level: .info, message: "battery charging at 2.14 A", percent: 57, source: .observed),
                LogEntry(date: at(453), level: .info, message: "charger unplugged", percent: 57, source: .observed),
                LogEntry(date: at(453), level: .info, message: "on battery", percent: 57, source: .chargectl),
                LogEntry(
                    date: at(448), level: .info, message: "battery discharging at 0.53 A", percent: 57,
                    source: .observed),
                LogEntry(date: at(443), level: .info, message: "charger plugged in", percent: 57, source: .observed),
                LogEntry(date: at(443), level: .info, message: "charging to 80%", percent: 57, source: .chargectl),
                LogEntry(
                    date: at(438), level: .info, message: "battery charging at 2.13 A", percent: 57, source: .observed),
                LogEntry(
                    date: at(203), level: .info, message: "battery charging at 2.11 A", percent: 59, source: .observed),
                LogEntry(
                    date: at(8), level: .info, message: "battery charging at 2.08 A", percent: 61, source: .observed),
            ]
            if warning {
                entries.append(contentsOf: [
                    LogEntry(
                        date: at(110), level: .info, message: "settings: limit 80% → 75%", percent: 60,
                        source: .chargectl),
                    LogEntry(
                        date: at(110), level: .warning,
                        message: "limits below 80% will be held by switching wall power", percent: 60, source: nil),
                    LogEntry(date: at(110), level: .info, message: "charging to 75%", percent: 60, source: .chargectl),
                ])
                entries.sort { $0.date < $1.date }
            }
            return entries
        }
    }
#endif
