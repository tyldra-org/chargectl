import SwiftUI

struct ControlPage: View {
    let model: AppModel
    @AppStorage(PreferenceKey.temperatureUnit) private var unit = TemperatureUnit.systemDefault
    @State private var draftLimit: Double?

    var body: some View {
        if let settings = model.settings, model.isControllable {
            form(settings)
        } else {
            ServiceRequired(
                model: model,
                description:
                    "Install the helper to set a charge limit. It runs in the background and keeps the limit while Chargectl is closed."
            )
        }
    }

    private func form(_ settings: ChargeSettings) -> some View {
        Form {
            Section {
                LabeledContent("Charge limit") {
                    Text("\(Int(draftLimit ?? Double(settings.limit)))%").monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { draftLimit ?? Double(settings.limit) },
                        set: { draftLimit = $0 }),
                    in: Double(ChargeSettings.limitRange.lowerBound)...Double(ChargeSettings.limitRange.upperBound),
                    step: 1
                ) {
                    Text("Charge limit")
                } minimumValueLabel: {
                    Text("20%")
                } maximumValueLabel: {
                    Text("100%")
                } onEditingChanged: { editing in
                    guard !editing, let draftLimit else { return }
                    model.update { $0.limit = Int(draftLimit) }
                    self.draftLimit = nil
                }
                .labelsHidden()
                Stepper(value: binding(\.sailing), in: ChargeSettings.sailingRange) {
                    LabeledContent("Sailing range", value: "\(settings.sailing)%")
                }
                Toggle("Discharge to the limit when plugged in", isOn: binding(\.autoDischarge))
            } header: {
                Text("Charging")
            } footer: {
                Text(chargingFooter(settings))
            }

            Section {
                Toggle("Pause charging when warm", isOn: binding(\.heatProtection))
                if settings.heatProtection {
                    Stepper(
                        value: binding(\.heatThreshold), in: ChargeSettings.heatThresholdRange, step: 1
                    ) {
                        LabeledContent("Above", value: unit.format(settings.heatThreshold, decimals: 0))
                    }
                }
            } header: {
                Text("Heat")
            } footer: {
                Text("Charging resumes once the battery cools by 2 °C.")
            }

            Section {
                Toggle("Keep discharging while asleep", isOn: binding(\.holdAsleep))
            } header: {
                Text("Sleep")
            } footer: {
                Text(
                    "Before the Mac sleeps, Chargectl reconnects wall power if it had cut it to discharge. Turn this on to keep discharging while asleep. The limit itself is held by macOS, also during sleep."
                )
            }

            Section {
                Picker("MagSafe light", selection: binding(\.magSafeLED)) {
                    Text("Automatic").tag(MagSafeLEDMode.system)
                    Text("Off").tag(MagSafeLEDMode.off)
                }
                .pickerStyle(.segmented)
                Toggle("Charge control", isOn: binding(\.isEnabled))
            } footer: {
                Text("Turning charge control off hands charging back to macOS.")
            }
        }
        .formStyle(.grouped)
    }

    private func chargingFooter(_ settings: ChargeSettings) -> String {
        if settings.limit >= 100 { return "The battery charges fully." }
        let above =
            settings.autoDischarge
            ? " Plugged in above the limit, the battery discharges down to \(settings.limit)%."
            : " Plugged in above the limit, the Mac runs on the charger and the battery stays where it is."
        return holdingSentence(settings) + above
    }

    private func holdingSentence(_ settings: ChargeSettings) -> String {
        let stop = "Charging stops at \(settings.limit)% and the Mac keeps running on the charger."
        if settings.sailing == 0 { return stop }
        return stop + " If the charge drifts down, it is not topped up until it reaches \(settings.lowerBound)%."
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<ChargeSettings, Value>) -> Binding<Value> {
        Binding(
            get: { (model.settings ?? ChargeSettings())[keyPath: keyPath] },
            set: { value in model.update { $0[keyPath: keyPath] = value } })
    }
}
