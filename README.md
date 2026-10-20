# Chargectl

Keep a MacBook's battery at a charge limit, from the menu bar.

[![CI](https://github.com/tyldra-org/chargectl/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/tyldra-org/chargectl/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/tyldra-org/chargectl)](LICENSE)

Lithium-ion batteries wear faster when they sit at 100%. Chargectl stops charging
at the limit you pick, anywhere from 20% to 100%, and keeps the Mac running on
the charger while the battery stays where it is. It shows live power, battery
health and a 24-hour history, and a small root service keeps the limit while
the app is closed.

## Quick start

Requirements: an Apple silicon MacBook on macOS 27, Xcode 27 and
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
git clone https://github.com/tyldra-org/chargectl.git
cd chargectl
./scripts/install.sh
```

The script asks for your password once, builds the app, copies it to
`/Applications`, starts the control service and opens Chargectl. Click the ring
in the menu bar and drag the bar to set a limit.

Quit any other charge limiter first. Two of them fight over the same settings.

## Features

- Charge limit from 20% to 100%, held on the charger without using the battery.
- Sailing: once at the limit, the charge may drift down a few percent before
  charging resumes, so the battery is not topped up all day.
- Automatic discharge, off by default: when plugged in above the limit, either
  hold the current charge or discharge down to the limit.
- Top up to 100%, discharge to the limit, and calibration jobs.
- Heat protection, clamshell support, sleep handling and MagSafe LED control.
- Live charger, Mac and battery power, battery health, a 24-hour history and a
  log of what the battery and Chargectl did.

## How it works

On current Apple silicon firmware, the SMC keys that pause charging (`CH0B`,
`CH0C`, `CHTE`, `bfF0`) are gated behind a private Apple entitlement, so no
third-party process can pause charging directly. Chargectl uses two other tools:

- **macOS's own charge limit.** PowerUIAgent holds the entitlement. At its limit
  the battery hardware holds the charge while the Mac runs on the charger, and
  above it the battery discharges to the limit. Limits of 80% to 100% are set
  through `PowerUISmartChargeClient`. Lower limits are written to PowerUIAgent's
  preferences (`com.apple.smartcharging.topoffprotection`, `mclLimitValue`)
  after an allowed 80% request, then the `com.apple.smartcharging.defaultschanged`
  notification makes PowerUIAgent reload them. Chargectl reads the limit back and
  falls back to switching wall power if macOS did not take it.
- **Switching wall power** with the `CHIE` SMC key, which runs the Mac on its
  battery while the charger stays plugged in. It is used to discharge to a limit
  below 80%, for heat protection and calibration, and as the fallback.

| Feature | How |
| --- | --- |
| Limit | macOS's limit set to the limit; the Mac holds on the charger |
| Sailing | After reaching the limit, macOS's limit follows the charge down until limit minus sailing, then charging resumes |
| Automatic discharge | Off: macOS's limit is set to the current charge. On: macOS discharges to limits of 80% or more; below that, wall power is cut until the limit |
| Top up, discharge | Temporary jobs that override the limit |
| Calibrate | Drain to 15%, charge to 100%, rest an hour, return to the limit |
| Heat protection | Cut wall power at the threshold, reconnect 2 °C below it |
| Clamshell | Prevent-sleep assertion while wall power is cut |
| Sleep | Wall power is reconnected before sleep unless "hold limit asleep" is on |
| MagSafe LED | `ACLC`: macOS-driven or off |

Your own macOS charge limit is saved the first time Chargectl changes it and
restored when Chargectl stops, is turned off or is uninstalled.

Readings come from the `AppleSmartBattery` registry entry and live SMC keys
(`B0AC`, `B0AV`, `PDTR`, `PSTR`, `VD0R`, `ID0R`, `TB0T`) and need no
privileges.

## Install and uninstall

```sh
./scripts/install.sh           # build, install the app and service, open it
./scripts/install.sh --logs    # same, then follow the service log
./scripts/uninstall.sh         # remove everything Chargectl added
```

Run `install.sh` again after pulling changes; it replaces both the app and the
service. **Settings > Uninstall Chargectl** in the app does the same as
`uninstall.sh`: it reconnects wall power, restores your macOS charge limit and
removes the service, its data, preferences and caches.

## Limitations

- Chargectl relies on private macOS interfaces (PowerUI, SMC keys and
  PowerUIAgent preferences). A macOS or firmware update can change them.
- The control service runs as root. Read [SECURITY.md](SECURITY.md) for what it
  can do and who can talk to it.
- Builds are signed ad hoc, not with a Developer ID, and are not notarized.
- Only Apple silicon MacBooks on macOS 27 are supported and tested.

## Development

Built with Swift and SwiftUI, using XcodeGen for the project file.

```sh
./scripts/check.sh          # format, build, test, shell and workflow checks
./scripts/test.sh           # unit tests only
./scripts/run.sh            # install a Debug build with its service
```

`./scripts/check.sh` is the same entry point CI runs. See
[CONTRIBUTING.md](CONTRIBUTING.md) for the workflow and [AGENTS.md](AGENTS.md)
for the project layout.

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) and follow
the [Code of Conduct](CODE_OF_CONDUCT.md).

## Security

Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).
Do not open public issues for security problems.

## License

Licensed under Apache-2.0; see [LICENSE](LICENSE).
Copyright 2026 Yogesh Prasad.
