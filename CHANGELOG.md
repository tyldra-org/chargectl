# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.2] - 2026-10-20

Reinstalling with Homebrew works after uninstalling from Settings.

### Fixed

- **Uninstall clears Homebrew's record.** Settings › Uninstall Chargectl and
  `scripts/uninstall.sh` now also remove Homebrew's record of the cask. Before,
  the next `brew install` failed with "It seems the App source
  '/Applications/Chargectl.app' is not there". (#6)

## [0.1.1] - 2026-10-20

Lowering the limit while plugged in no longer discharges the battery.

### Fixed

- **Holding above the limit after a change.** With automatic discharge off,
  lowering the limit below the charge or turning automatic discharge off while
  plugged in cut wall power and discharged to the limit. Chargectl now holds the
  current charge on the charger, as it does when you plug in above the limit. (#5)

## [0.1.0] - 2026-10-20

The first release of Chargectl: battery charge limits for Apple silicon
MacBooks, from the menu bar.

### Added

- **Charge limit from 20% to 100%.** Charging stops at the limit and the Mac
  runs on the charger. macOS's own charge limit holds it, also while Chargectl
  is closed, and stays in sync with System Settings › Battery.
- **Sailing.** After reaching the limit, the charge may drift down a few
  percent before charging resumes, so the battery is not topped up all day.
- **Above the limit.** Plugged in above the limit, hold the current charge or
  discharge down to the limit.
- **Overcharge guard.** When macOS charges to 100% anyway, or after "Charge to
  Full Now", wall power is cut until the charge is back at the limit.
- **Jobs.** Top up to 100% once, discharge to the limit, or calibrate the
  battery gauge.
- **Heat, sleep and MagSafe.** Pause charging while the battery is warm, choose
  whether discharging continues during sleep, and turn the MagSafe light off.
- **Live readings.** Charger, Mac and battery power every second, battery
  health, cycles and temperature, time to full or empty, 24 hours of history
  and a log of what the battery and Chargectl did.
- **Menu bar panel and dashboard.** A welcome window installs the helper and
  sets your first limit, and opens again until setup is done.
- **Clean uninstall.** Settings › Uninstall Chargectl or `scripts/uninstall.sh`
  hands charging back to macOS and removes every file Chargectl added.
- **Homebrew.** `brew install --cask tyldra-org/tools/chargectl`.

[Unreleased]: https://github.com/tyldra-org/chargectl/compare/v0.1.2...HEAD
[0.1.2]: https://github.com/tyldra-org/chargectl/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/tyldra-org/chargectl/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/tyldra-org/chargectl/releases/tag/v0.1.0
