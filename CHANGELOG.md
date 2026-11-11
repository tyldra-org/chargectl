# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.2.6] - 2026-11-11

Plugging in inside the sailing range no longer charges the battery to the
limit and past it.

### Fixed

- **Changing macOS's limit below 80% no longer starts a charge.** Chargectl
  set such a limit by asking macOS for 80% first, and on the charger that
  started a charge toward 80% that macOS finished after the lower limit was
  set. Limits below 80% are now changed directly.
- **Plugging in inside the sailing range no longer charges to the limit.**
  macOS started charging toward the limit the moment the charger was
  connected and kept going after Chargectl lowered its limit, while the
  status said "Sailing on the charger". On battery inside the range, macOS's
  limit now follows the charge, and a charge that starts anyway stops at the
  level Chargectl is holding.
- **A charge that runs past the limit is no longer held there.** A moment
  without current in such a charge made Chargectl hold at whatever level it
  had reached, and the hold then rose with the charge. A hold now follows a
  rising charge only after the battery has rested for two minutes; until
  then, charging past the limit cuts wall power.

## [0.2.5] - 2026-11-10

Login Items lists the helper as "Chargectl Service" again.

### Fixed

- **Login Items lists the helper as "Chargectl Service" again**, instead of
  "com.tyldra.chargectl.daemon" with a blank icon. Since 0.2.0 the helper's
  root-owned copy was named after its launchd label, and Login Items shows that
  file's name. The copy is now `/Library/PrivilegedHelperTools/Chargectl Service`.
  Installing the helper again moves it right away; otherwise the helper moves
  itself, which takes effect when the Mac next restarts.

## [0.2.4] - 2026-11-09

The Full By widget comes in every size, and a skipped full charge no longer
shows as the next one.

### Added

- **The Full By widget comes in every size.** Large, extra large and extra
  large portrait join small and medium. They show the time left or the next
  full charge, a track of the hours until then (held at your limit, then
  charging), the week, the next few full charges with when each starts, and
  Skip or Stop.

### Fixed

- **A skipped full charge no longer shows as the next one.** After Skip or Stop,
  the widgets, the Control Center control and the Control page kept showing the
  skipped time; they now show the one after it, and the widget marks the
  skipped day.
- **The Health widget and History's battery health chart work with an older
  helper.** They stayed empty until the helper was updated to the app's
  version; every helper from 0.2.0 on has the daily record they need.
- **No history entry is lost after a crash.** An entry written right after a
  line that a crash cut short was skipped together with it.
- **macOS's own limit is only reported as draining the battery when it is in
  force.** A policy left from before the last restart could count.
- **The Time Left widget no longer says "Until you unplug" on battery** when
  there is no estimate yet.
- **The menu bar preview in setup and Settings keeps its clock current**, and
  shows "—" instead of 0% before the battery is read.

## [0.2.3] - 2026-11-08

Uninstalling, or dragging Chargectl to the Trash, leaves nothing behind.

### Fixed

- **Uninstall leaves nothing behind.** It now also removes the widgets'
  Application Scripts folder, stops the widget extension before deleting its
  data, and makes a second pass after the app quits, because quitting wrote the
  preferences and caches again. If macOS protects the widgets' data, Chargectl
  shows those folders in Finder so you can drag them to the Trash.
- **Dragging the app to the Trash cleans up too.** The helper already handed
  charging back and removed itself when the app was deleted; it now also
  removes the app's preferences, caches, widget data, crash reports and Dock
  tile for each user.
- **`brew uninstall --zap` removes the widgets' Application Scripts folder and
  the WebKit data too.**

## [0.2.2] - 2026-11-08

Full by is set on a day track, and cards no longer stretch into empty space.

### Changed

- **Full by is set on a day track.** Drag the time along a 24-hour track, the
  same ruler and knob as the charge limit, or use the arrow keys (15 minutes,
  Shift for an hour). The green stretch before the knob shows when charging
  starts, and the time sits above it in large digits. All seven days are always
  shown, with Weekdays, Every day and Once as shortcuts; this replaces the Days
  option, which jumped back to Weekdays or Every day when the chosen days
  matched one of them. The card's caption shows the next one, such as "Next:
  Tomorrow, 8:00 AM".

### Fixed

- **Cards no longer stretch to match their neighbour.** Control and Settings
  stack their cards in two columns, each card as tall as its content, so cards
  like Helper, Updates, Charge control and Heat no longer end in empty space.
  Settings' menu bar card now spans the page.
- **The menu bar preview in Settings fits.** It drops menus before it cuts off
  the percentage.
- **Overview fits the default window width.** The Top Up, Discharge and
  Calibrate buttons no longer shorten their names, and the summary strip drops
  its last facts instead of wrapping.

## [0.2.1] - 2026-11-08

A new app icon, and the setup window loses its grey strip.

### Changed

- **A new app icon.** It's the menu bar ring at Dock size: a green charge on a
  glass track that ends at your limit, with no lightning bolt. It's built in
  Icon Composer, so it follows System Settings › Appearance › Icon & widget
  style: Default, Dark, Clear and Tinted. (#23)

### Fixed

- **The setup window no longer has a grey strip along its bottom.** The window
  was a title bar taller than its content. (#22)

## [0.2.0] - 2026-11-08

A redesigned app with widgets, Control Center controls and Full by. The root
helper now runs from a copy only root can change, and four charging bugs are
fixed.

### Added

- **Widgets.** Charge comes in every size macOS offers, from Small to Extra
  Large Portrait. Power, Health, Today, Full by, Controls and Time left come in
  Small and Medium, and Ring in Small. Each kind answers one question; Controls,
  Full by and the larger Charge sizes have buttons that change the limit, Top Up,
  Discharge or skip a full charge without opening the app. (#20)
- **Control Center controls** for charge control (showing your limit), Top Up,
  Discharge and Full by, which can also sit in the menu bar. (#20)
- **Full by.** Control › Full by charges to 100% just in time for a time you
  set, once, on weekdays, every day or on chosen days, then goes back to your
  limit. Charging starts only as early as the charge needs, so the battery isn't
  kept full for hours. Stopping it skips that time. (#20)
- **Battery health over time.** History keeps one summary a day for years:
  health, cycles, hours at 90% or more and the warmest moment. A new card shows
  them over a month, three months, a year or everything. (#20)
- **Shortcuts actions.** Set the limit, turn charge control on or off, Top Up,
  Discharge, stop a job, charge to full by a time, turn Full by off, and get the
  battery's charge. (#20)
- **Notifications** for problems (on), finished jobs (on) and the limit being
  reached (off); Settings › Notifications. (#20)
- **A warning when the charger is too weak.** Plugged in, yet the battery runs
  down for a minute: Chargectl says the charger can't keep up. (#20)
- **A check that charge control works.** If the helper cuts wall power and the
  battery keeps charging for 30 seconds, Chargectl warns that a macOS or firmware
  update may have changed how charging is controlled. (#20)

### Changed

- **A redesigned dashboard and menu bar.** Every page now uses the same calm
  cards, one green accent and a black status pill at the top that confirms each
  change. Overview shows power flowing from the charger to the Mac and the
  battery, and the charge over the last hour, 6 or 24 hours. Control puts the
  limit first, on a slider with a ruler and the sailing range drawn in, and reads
  the rules back as one sentence; turning charge control off asks first.
  History adds four totals for the range, the charger connection under the
  chart and one crosshair across all charts. Logs groups lines from the same
  second, splits them by day, marks helper restarts and adds search (⌘F) and
  Copy. Settings shows a menu bar preview and appearance as small windows, and
  asks before removing the helper. (#20)
- **The menu bar ring shows your limit.** Its track ends at the charge limit, so
  a closed ring means the battery is held there, and a small symbol shows
  charging, holding, discharging or a missing helper. (#20)
- **A calmer setup window.** Each of the four steps shows one picture, a title,
  a sentence and only that step's controls. A diagram shows what the helper
  connects, the install checklist ticks off as it goes, the limit uses the same
  slider as Control, and the last step shows where Chargectl sits in the menu
  bar. (#20)
- **The helper writes much less to disk and keeps more log.** History and log
  entries are appended one line at a time instead of rewriting the whole file
  every minute (about 280 MB a day at a full day of history), and the log keeps
  the last 2,000 lines instead of 300. Files from older versions are moved over
  on the first start. (#20)
- **The app keeps hearing from the helper while macOS's battery service is
  slow.** Status, history and logs are answered without waiting for it, and the
  helper asks it for the charge limit once per check instead of up to four
  times plus once for every status request. (#20)

### Security

- **Other programs can no longer replace the root helper.** launchd ran the
  helper from inside Chargectl.app, which belongs to your user account, so any
  program running as you could replace that file and have it run as root
  without a password. Install Helper now copies the helper to
  `/Library/PrivilegedHelperTools`, owned by root, and launchd runs that copy.
  A helper installed by an earlier version moves itself there; this takes
  effect when the Mac next restarts. (#20)
- **Releases can be signed with Chargectl's own certificate.** Once they are,
  the updater accepts only that signature, the helper takes commands only from
  an app signed with it, and updates replace the helper without a password.
  Until then, each update asks for the administrator password to update the
  helper. (#20)
- **Release builds no longer let other processes attach to them** (no
  `get-task-allow` entitlement), so nothing can speak to the helper as the app.
  (#20)

### Fixed

- **Limits macOS can't hold stay held while the Mac sleeps.** Where macOS's own
  limit can't go as low as yours, or isn't available, the helper used to
  reconnect wall power before sleep, and the Mac could charge to macOS's limit
  or to full overnight. Now wall power stays cut while asleep when the charge is
  at least at the lower bound and 30%, so it only drifts down a little. (#20)
- **Wall power comes back when the battery cannot be read.** After three failed
  readings in a row the helper reconnects the charger instead of leaving the Mac
  running down its battery. (#20)
- **A limit below 80% no longer flickers wall power the first time macOS
  refuses it.** The helper now decides again at once, instead of applying the
  old decision after switching to holding the limit with wall power. (#20)
- **Plugging in inside the sailing range no longer charges.** With a 55% limit
  and 7% sailing, plugging in at 52% started charging to 55%. The charge is now
  held where it is, and charging starts only once it drifts down to 48%, the
  same as after reaching the limit. (#20)

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

[Unreleased]: https://github.com/tyldra-org/chargectl/compare/v0.2.6...HEAD
[0.2.6]: https://github.com/tyldra-org/chargectl/compare/v0.2.5...v0.2.6
[0.2.5]: https://github.com/tyldra-org/chargectl/compare/v0.2.4...v0.2.5
[0.2.4]: https://github.com/tyldra-org/chargectl/compare/v0.2.3...v0.2.4
[0.2.3]: https://github.com/tyldra-org/chargectl/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/tyldra-org/chargectl/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/tyldra-org/chargectl/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/tyldra-org/chargectl/compare/v0.1.10...v0.2.0
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
