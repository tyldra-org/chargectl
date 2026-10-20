# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.1] - 2026-10-20

### Fixed

- With automatic discharge off, lowering the limit below the charge, or turning
  automatic discharge off, while plugged in cut wall power and discharged to the
  limit. Chargectl now holds the current charge on the charger, as it does when
  you plug in above the limit.

## [0.1.0] - 2026-10-20

First release.

### Added

- Menu bar app with a dashboard: overview, control, history, logs and settings.
- Welcome window on first launch that installs the helper and sets the first
  limit; it opens again until setup is finished.
- Root control service that holds the charge limit while the app is closed.
- Charge limits from 20% to 100% through macOS's own charge limit, held on the
  charger without using the battery.
- Sailing, automatic discharge, top up, discharge and calibration.
- Protection against macOS's occasional charge to 100% and "Charge to Full
  Now": wall power is cut until the charge is back at the limit.
- Heat protection, sleep handling and MagSafe LED control.
- Live power readings from SMC keys, a 24-hour history and a log of measured
  battery changes.
- App icon. The dashboard shows a Dock icon while it is open; closing it or
  pressing ⌘Q returns Chargectl to the menu bar, where Quit Chargectl is.
  Open at Login is in Settings.
- Install Helper registers the root helper with SMAppService, listed as
  Chargectl in Login Items; it restarts into new app versions and removes itself
  when the app is deleted.
- `scripts/install.sh` and `scripts/uninstall.sh`, and an in-app uninstall
  that restores the macOS charge limit and removes every file Chargectl added.

[Unreleased]: https://github.com/tyldra-org/chargectl/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/tyldra-org/chargectl/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/tyldra-org/chargectl/releases/tag/v0.1.0
