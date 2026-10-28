# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.10] - 2026-10-27

The helper comes back by itself after a macOS update, and holding above the
limit no longer discharges the battery.

### Fixed

- **"Install the helper" after a macOS update.** A macOS update moves
  third-party files aside and puts them back after launchd has started the
  system's daemons, so the helper's job was missing until the next restart. The
  helper now keeps a narrow sudoers rule that lets the app start it again
  without a password, and the app does so as soon as it sees the job missing.
  Installs from 0.1.9 get the rule when the helper first runs 0.1.10. (#15)
- **Discharging while holding above the limit.** After a restart the battery
  gauge can read a percent higher than before. The hold stayed at the old
  reading, so macOS's limit sat below the charge and discharged the battery at
  over 20 W. With macOS's limit available, the hold now follows the reading
  while the battery is not charging, and a starting helper forgets the old
  hold. (#15)

## [0.1.9] - 2026-10-27

Updates reopen Chargectl at once.

### Fixed

- **Slow reopen after an automatic update.** The updated app now starts right
  away instead of after 30 seconds, and the helper no longer stops a copy that
  started after the update. (#14)

## [0.1.8] - 2026-10-27

Chargectl keeps itself up to date.

### Added

- **Automatic updates.** Chargectl checks GitHub for a new release a minute
  after it starts and every six hours, and installs it while its windows are
  closed. The helper restarts into the new version and reopens the app. Each
  download is checked against its published SHA-256 and code signature. On by
  default; turn it off, check now or install a waiting version in Settings ›
  Updates. The Homebrew cask is marked as updating itself. (#13)

## [0.1.7] - 2026-10-27

Top Up and Calibrate charge to 100% again and leave your limit alone.

### Fixed

- **Top Up stopped at 80% and changed the limit.** macOS has no 100% charge
  limit: asking for 100% switches its limit off. Chargectl saw the limit off,
  switched it back on, macOS restored its 80% default, and Chargectl took that
  as a limit you had chosen in System Settings. Charging to 100% (Top Up,
  Calibrate, or a 100% limit) now switches macOS's limit off, and changes made
  while a job runs are no longer taken as yours. (#12)

## [0.1.6] - 2026-10-21

Uninstall leaves nothing of Chargectl behind.

### Fixed

- **Dock tile.** Uninstall removes Chargectl from the Dock, whether pinned or
  under recent apps, instead of leaving a question-mark icon. (#11)
- **Homebrew leftovers.** Uninstall also removes the cached download and the
  `tyldra-org/tools` tap when nothing else from it is installed, along with
  Homebrew's record of the cask. (#11)
- **Crash reports.** Uninstall, `scripts/uninstall.sh` and `brew uninstall
  --zap` remove the crash reports macOS wrote for the helper. (#11)
- **Homebrew commands.** Homebrew now loads casks from other taps only when they
  are named in full, so the docs and the cask use `tyldra-org/tools/chargectl`.
  (#11)

## [0.1.5] - 2026-10-21

The helper keeps working across updates and restarts, and holds the charge
above the limit as it should.

### Changed

- **Helper installed with your password.** Install Helper now adds the helper as
  a launchd daemon after asking for your administrator password, instead of
  through Login Items. macOS ties a Login Items approval to the exact build when
  an app has no Team ID, so after every update it refused to start the helper
  ("Launch Constraint Violation") and the app said the helper had stopped. Builds
  signed with a team still use Login Items. (#10)
- **macOS's limit stays during restarts.** Shutting down, restarting or updating
  reconnects wall power but leaves macOS's charge limit at yours, so it holds
  until the helper runs again. Turning charge control off, removing the helper
  and uninstalling still restore your own limit. (#10)

### Fixed

- **"The helper stopped" after a restart.** Right after the Mac starts,
  PowerUI can take a minute to answer, and the helper did not accept the app's
  connection until it had. It now answers at once and finishes starting in the
  background. (#10)
- **Discharging above the limit with automatic discharge off.** After a
  restart, or when macOS stopped charging a percent past the limit, Chargectl
  cut wall power and discharged to the limit. It now holds the charge on the
  charger; only charging past the limit cuts wall power. (#10)
- **Misleading macOS limit notice.** "macOS's own charge limit is running the Mac
  on battery" appeared while the helper was starting. It now appears only when
  no helper is installed. (#10)
- **Deleting the app removes the helper.** The helper now hands charging back to
  macOS and deletes its launchd job and data once Chargectl.app has been gone
  for 30 seconds, and `brew uninstall --zap` also removes the launchd job. (#10)

## [0.1.4] - 2026-10-21

Updates now restart the helper and reopen Chargectl by themselves.

### Added

- **Reopen after an update.** When Chargectl was running, the helper stops any
  copy still running old code and reopens the new version once an update
  replaces the app, whether through Homebrew, `scripts/install.sh` or by hand.
  (#9)
- **Old helper notice.** If the helper keeps running an older version, the app
  says so and opens Login Items, where turning Chargectl off and on restarts
  it. (#9)

### Fixed

- **The helper follows the app again.** It never restarted into a new version
  and did not remove itself when the app was deleted, because it looked for its
  own executable at a relative path. Updating from 0.1.3 or earlier needs one
  restart of the helper; the app shows how. (#9)
- **Version in Settings.** It always showed 0.1.0. (#9)
- **Homebrew stops the app before an upgrade.** Chargectl turns Quit into
  closing its window, so the cask now stops it with a signal. (#9)

## [0.1.3] - 2026-10-20

The Estimate shows time to your limit, and a new card lists the apps using
significant energy.

### Added

- **Using Significant Energy.** A card on the Overview lists the apps using the
  most power, averaged over the last minute. A browser's helpers count for the
  browser, and commands count for the terminal that started them. (#8)

### Changed

- **Time to where the charge is going.** The Estimate counts to your limit while
  charging to it ("until 70%"), to the lower bound while sailing, to the target
  while discharging, and to empty on battery, instead of always to full. While
  holding, it says so. (#8)

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

[Unreleased]: https://github.com/tyldra-org/chargectl/compare/v0.1.10...HEAD
[0.1.10]: https://github.com/tyldra-org/chargectl/compare/v0.1.9...v0.1.10
[0.1.9]: https://github.com/tyldra-org/chargectl/compare/v0.1.8...v0.1.9
[0.1.8]: https://github.com/tyldra-org/chargectl/compare/v0.1.7...v0.1.8
[0.1.7]: https://github.com/tyldra-org/chargectl/compare/v0.1.6...v0.1.7
[0.1.6]: https://github.com/tyldra-org/chargectl/compare/v0.1.5...v0.1.6
[0.1.5]: https://github.com/tyldra-org/chargectl/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/tyldra-org/chargectl/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/tyldra-org/chargectl/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/tyldra-org/chargectl/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/tyldra-org/chargectl/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/tyldra-org/chargectl/releases/tag/v0.1.0
