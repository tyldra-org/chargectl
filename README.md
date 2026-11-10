<p align="center">
  <img src="docs/assets/icon.png" alt="Chargectl" width="128" height="128">
</p>

<h1 align="center">Chargectl</h1>

<p align="center">
  <strong>Stop your MacBook charging at 80%, or any limit you choose, to slow battery wear.</strong>
</p>

<p align="center">
  <a href="https://github.com/tyldra-org/chargectl/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/tyldra-org/chargectl/actions/workflows/ci.yml/badge.svg?branch=main"></a>
  <a href="LICENSE"><img alt="License: Apache-2.0" src="https://img.shields.io/badge/license-Apache--2.0-blue.svg"></a>
  <img alt="macOS 27" src="https://img.shields.io/badge/macOS-27-black.svg?logo=apple">
  <img alt="Apple silicon" src="https://img.shields.io/badge/Apple%20silicon-arm64-black.svg">
</p>

<p align="center">
  <a href="https://tyldra-org.github.io/chargectl/">Website</a> ·
  <a href="#quickstart">Quickstart</a> ·
  <a href="#features">Features</a> ·
  <a href="#screenshots">Screenshots</a> ·
  <a href="#widgets">Widgets</a> ·
  <a href="#how-it-works">How it works</a> ·
  <a href="#faq">FAQ</a> ·
  <a href="#install-and-uninstall">Install</a> ·
  <a href="CONTRIBUTING.md">Contributing</a> ·
  <a href="SECURITY.md">Security</a>
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/overview-dark.png">
    <img alt="Chargectl's Overview page: the charge against the limit, power flowing from the charger to the Mac and the battery, battery health, the charge over the last 6 hours and recent activity" src="docs/assets/screenshots/overview-light.png" width="880">
  </picture>
</p>

---

Lithium-ion batteries wear faster when they sit at 100%. Chargectl is a free,
open-source menu bar app for Apple silicon MacBook Air and MacBook Pro. It stops
charging at the limit you choose, anywhere from 20% to 100%, and keeps your Mac
running on the charger while the battery rests. It works with macOS's own charge
limit instead of around it, shows what the charger, the Mac and the battery are
doing each second, and keeps working while the app is closed.

## Quickstart

| Requirement | Version |
| --- | --- |
| Mac | Apple silicon MacBook |
| macOS | 27 or later |

```sh
brew install --cask tyldra-org/tools/chargectl
```

You can also download `Chargectl-<version>.zip` from
[Releases](https://github.com/tyldra-org/chargectl/releases/latest), or
[build it from source](#build-from-source).

Then open **Chargectl** from Applications. A short welcome walks you through:

1. **Installing the helper**, the small root service that controls charging.
   macOS asks for your password once. Updates restart the helper and reopen
   Chargectl by themselves.
2. **Choosing a limit.** It starts from the limit already set in System Settings ›
   Battery, so nothing changes until you pick another one.

After that Chargectl lives in the menu bar. Click <img src="docs/assets/screenshots/menu-bar-icon.png" alt="the Chargectl ring" height="20" align="top"> to see your battery,
switch options and drag the white marker to change the limit.

> [!IMPORTANT]
> Quit any other charge limiter, such as AlDente, before you install. Two of
> them fight over the same settings.

## Features

| | |
| --- | --- |
| **Charge limit, 20% to 100%** | Charging stops at the limit and the Mac runs on the charger. The battery is not used to hold it. |
| **Sailing** | After reaching the limit, the charge may drift down a few percent before charging resumes, so the battery is not topped up all day. |
| **Above the limit** | Plugged in above the limit, either hold the current charge or discharge down to the limit. |
| **Overcharge guard** | When macOS charges past the limit anyway (its occasional charge to 100%, or "Charge to Full Now"), Chargectl brings the battery back. |
| **Two-way sync** | Chargectl's limit shows in System Settings › Battery, and a limit chosen there becomes Chargectl's limit. |
| **Jobs** | Top up to 100% once, discharge to the limit, or calibrate the battery gauge. |
| **Full by** | Charge to 100% just in time for a time you set, once or on chosen days, then back to the limit. |
| **Heat protection** | Pause charging while the battery is warm. |
| **Live readings** | Charger, Mac and battery power each second, battery health, cycles and temperature. |
| **Time to the limit** | How long until the charge reaches your limit, the end of sailing or a discharge target, or empty on battery. |
| **Energy by app** | The apps using significant energy, averaged over the last minute, with each app's helpers and commands counted for it. |
| **History and logs** | 24 hours of charge, temperature and power, and a log of what the battery and Chargectl did. |
| **Health over time** | One summary a day, kept for years: health, cycles, hours at 90% or more and the warmest moment. |
| **Widgets and controls** | Widgets in every size for the charge, power, health, today, Full by, time left and quick controls; Control Center controls for charge control, Top Up, Discharge and Full by. |
| **Shortcuts and notifications** | Shortcuts actions for the limit, jobs and Full by. Notifications for problems, finished jobs and the limit. |
| **Checks** | Warns when the charger is too weak to run the Mac, or when cutting wall power stops working after an update. |
| **Automatic updates** | New releases install themselves while Chargectl's windows are closed, checked against their checksum and code signature. On by default; Settings › Updates. |
| **Clean removal** | Uninstall restores normal charging and your macOS limit, and removes every file Chargectl added, including its caches, widget data and Dock tile. Dragging the app to the Trash does the same within a few minutes, through the helper. |

## Screenshots

Every page comes in light and dark; GitHub shows the one that matches your theme.

<table>
  <tr>
    <td align="center" valign="top">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/control-dark.png">
        <img alt="Control page: the charge limit on a slider with the sailing range, Full by, charge control, heat and the MagSafe light" src="docs/assets/screenshots/control-light.png" width="420">
      </picture><br>
      <b>Control</b><br>
      <sub>The limit on a slider with the sailing range drawn in, Full by, heat and the MagSafe light.</sub>
    </td>
    <td align="center" valign="top">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/history-dark.png">
        <img alt="History page: totals for the range, the charge chart, temperature, power and battery health over time" src="docs/assets/screenshots/history-light.png" width="420">
      </picture><br>
      <b>History</b><br>
      <sub>Totals for the range, charge, temperature and power under one crosshair, and health over months.</sub>
    </td>
  </tr>
  <tr>
    <td align="center" valign="top">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/logs-dark.png">
        <img alt="Logs page: events grouped by day, with filters for battery, Chargectl and warnings, search and Copy" src="docs/assets/screenshots/logs-light.png" width="420">
      </picture><br>
      <b>Logs</b><br>
      <sub>Every battery change and Chargectl action, by day, with filters, search (⌘F) and Copy.</sub>
    </td>
    <td align="center" valign="top">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/settings-dark.png">
        <img alt="Settings page: menu bar, appearance, notifications, the helper and updates" src="docs/assets/screenshots/settings-light.png" width="420">
      </picture><br>
      <b>Settings</b><br>
      <sub>Menu bar, appearance, notifications, the helper and automatic updates.</sub>
    </td>
  </tr>
  <tr>
    <td align="center" valign="top">
      <img alt="Menu bar panel: the charge, the limit, health and live power, quick switches and jobs" src="docs/assets/screenshots/menu-bar.png" width="300"><br>
      <b>Menu bar</b><br>
      <sub>Charge, live power, quick switches and jobs. Drag the marker to change the limit.</sub>
    </td>
    <td align="center" valign="top">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/setup-dark.png">
        <img alt="Setup window, first step: Welcome to Chargectl" src="docs/assets/screenshots/setup-light.png" width="380">
      </picture><br>
      <b>Setup</b><br>
      <sub>Four short steps: welcome, install the helper, choose a limit, done.</sub>
    </td>
  </tr>
</table>

## Widgets

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/widgets-dark.png">
    <img alt="Chargectl widgets on the desktop: Charge in large and medium, Controls, Full by, Ring, Power, Health, Time left and Today" src="docs/assets/screenshots/widgets-light.png" width="880">
  </picture>
</p>

Right-click the desktop, choose **Edit Widgets** and search for Chargectl. Each
widget answers one question, and clicking one opens the matching page.

| Widget | Sizes | Shows |
| --- | --- | --- |
| Charge | Small to Extra Large Portrait | The charge against your limit; larger sizes add the last hours, live power, and Top Up and Discharge |
| Ring | Small | The charge as a ring that closes at your limit |
| Power | Small, Medium | Watts from the charger, to the Mac and into the battery |
| Health | Small, Medium | Battery health and cycles, and how health changed over months |
| Today | Small, Medium | Time at 90% or more and on the charger, the lowest charge and the warmest moment |
| Full by | Small to Extra Large Portrait | The next full charge and its days, with Skip and Change; larger sizes add a track of the hours until then and the next few full charges |
| Controls | Small, Medium | The limit in 5% steps, Top Up and Discharge; Medium adds the charge control switch |
| Time left | Small, Medium | How long until the limit, full or empty |

Control Center has controls for charge control, Top Up, Discharge and Full by.
Add them in Control Center › Edit Controls; each can also sit in the menu bar.

## How it works

On current Apple silicon firmware, the SMC keys that pause charging (`CH0B`,
`CH0C`, `CHTE`, `bfF0`) are reserved for Apple through a private entitlement, so
no third-party process can pause charging directly. Chargectl uses the two tools
that remain:

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/architecture-dark.svg">
    <img alt="Chargectl.app talks to the root helper over XPC; the helper sets macOS's charge limit through PowerUI and switches wall power with the CHIE SMC key." src="docs/assets/architecture-light.svg" width="900">
  </picture>
</p>

- **macOS's own charge limit.** PowerUIAgent holds the entitlement. At its limit
  the battery holds its charge while the Mac runs on the charger; above it the
  battery discharges to the limit. Limits from 80% to 100% go through
  `PowerUISmartChargeClient`. Lower limits are written to PowerUIAgent's
  preferences (`com.apple.smartcharging.topoffprotection`, `mclLimitValue`)
  after an allowed 80% request, and the `com.apple.smartcharging.defaultschanged`
  notification makes PowerUIAgent reload them. Chargectl reads the limit back and
  falls back to switching wall power if macOS did not take it.
- **Switching wall power** with the `CHIE` SMC key, which runs the Mac on its
  battery while the charger stays plugged in. It is used to discharge to a limit
  below 80%, for heat protection, calibration, the overcharge guard and the
  fallback.

| Situation | What Chargectl does |
| --- | --- |
| Charging to the limit, or at it | Sets macOS's limit to the limit. The Mac holds on the charger. |
| Above the limit, holding | Sets macOS's limit to the current charge. |
| Above the limit, discharging, 80% or more | Sets macOS's limit to the limit; macOS discharges to it. |
| Above the limit, discharging, below 80% | Cuts wall power until the limit, sets macOS's limit, then reconnects. |
| Sailing | macOS's limit follows the charge down until limit minus sailing, then charging resumes. |
| Heat protection | Cuts wall power at the threshold and reconnects 2 °C below it. |
| Sleep | macOS holds the limit while asleep. A discharge in progress reconnects wall power before sleep unless "Sleep discharge" is on. |

Chargectl saves your own macOS charge limit before its first change and restores
it when it stops, when you turn charge control off and when you uninstall.
Readings come from the `AppleSmartBattery` registry entry and live SMC keys
(`B0AC`, `B0AV`, `PDTR`, `PSTR`, `VD0R`, `ID0R`, `TB0T`) and need no privileges.

## FAQ

### How do I stop my MacBook charging at 80%?

Install Chargectl, open it, and pick 80% in the setup window, or later drag the white marker in its menu bar panel. When the battery reaches 80%, charging stops and your Mac runs on the charger until you unplug it.

### macOS already has a charge limit. Why use Chargectl?

Recent macOS versions can limit charging from 80% to 100% in System Settings › Battery. Chargectl uses that same limit and adds limits down to 20%, sailing, Full by, heat protection, discharging to the limit, and a record of your battery's health over months.

### How is Chargectl different from AlDente?

Both stop a MacBook from charging to 100%. Chargectl is free and open source under the Apache-2.0 license, with no paid tier, and holds the limit through macOS's own charge limit, so it keeps working while the Mac sleeps or the app is closed. Use one or the other: two charge limiters fight over the same settings.

### Does it work on Intel Macs or older versions of macOS?

No. Chargectl needs an Apple silicon MacBook and macOS 27 or later.

### Does Chargectl collect any data?

No. It has no account and no analytics. It contacts GitHub only to check for new releases, and you can turn that off in Settings › Updates.

### How do I uninstall it?

Settings › Uninstall Chargectl restores normal charging and your macOS limit, and removes every file Chargectl added. Dragging the app to the Trash does the same within a few minutes.

## Install and uninstall

### Homebrew

```sh
brew install --cask tyldra-org/tools/chargectl                  # install
brew update && brew upgrade --cask tyldra-org/tools/chargectl   # update
brew uninstall --zap --cask tyldra-org/tools/chargectl          # remove everything
```

Chargectl updates itself, so `brew upgrade` without a name skips it. Use the
full name `tyldra-org/tools/chargectl`: Homebrew only loads casks from
other taps when you name them, or after `brew trust tyldra-org/tools`.

### Download

Each [release](https://github.com/tyldra-org/chargectl/releases) has
`Chargectl-<version>.zip`, its SHA-256 checksum and a build provenance
attestation. Unzip it and move Chargectl to Applications. Releases are not
notarized, so macOS blocks the first launch of a downloaded copy: open it once,
then choose **Open Anyway** in System Settings › Privacy & Security. To check a
download:

```sh
shasum -a 256 -c Chargectl-<version>.zip.sha256
gh attestation verify Chargectl-<version>.zip --repo tyldra-org/chargectl
```

### Build from source

Needs Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```sh
git clone https://github.com/tyldra-org/chargectl.git
cd chargectl
./scripts/install.sh           # build and install the app
./scripts/install.sh --logs    # same, then follow the helper's log
./scripts/uninstall.sh         # remove everything Chargectl added
```

Run `install.sh` again after pulling changes. The helper notices the new app and
restarts into it. If `Chargectl.app` is deleted, the helper removes itself.
How local builds are signed, and what that changes for the helper, is in
[CONTRIBUTING.md](CONTRIBUTING.md#signing).

### Uninstall

**Settings › Uninstall Chargectl** works for every install method and does the
same as `uninstall.sh`. It reconnects wall power, restores your macOS charge
limit, and removes:

- the helper, its launchd job, its sudoers rule, data, caches and crash reports;
- the Login Items entries, preferences, caches and saved state;
- Chargectl's tile in the Dock, pinned or under recent apps;
- Homebrew's record of the cask, its cached download, and the
  `tyldra-org/tools` tap when nothing else from it is installed.

If the helper is not running, it asks for your password and does the same as an
administrator.

## Limitations

- Chargectl relies on private macOS interfaces: PowerUI, PowerUIAgent's
  preferences and SMC keys. A macOS or firmware update can change them.
- The helper runs as root. [SECURITY.md](SECURITY.md) describes what it can do and
  who can talk to it.
- Releases are signed with Chargectl's own certificate, not an Apple developer
  certificate, and are not notarized. The Homebrew cask removes the quarantine
  flag after install so the app opens; a downloaded zip needs **Open Anyway**
  once.
- Only Apple silicon MacBooks on macOS 27 are supported and tested.

## Development

| Path | Contents |
| --- | --- |
| [`App/`](App) | Menu bar app: welcome, dashboard, menu bar panel, XPC client |
| [`Daemon/`](Daemon) | Chargectl Service: control loop, SMC and macOS limit adapters, XPC service |
| [`Shared/`](Shared) | Code built into both: SMC access, battery readings, `ChargePolicy`, XPC models |
| [`Tests/`](Tests) | Swift Testing suites for the charging policy and shared models |
| [`scripts/`](scripts) | Build, test, install, uninstall and the CI entry point |

```sh
./scripts/check.sh   # format, build, test, shell and workflow checks (what CI runs)
./scripts/test.sh    # unit tests only
./scripts/run.sh     # install a Debug build
```

### Releasing

1. Set `MARKETING_VERSION` in [`project.yml`](project.yml) and move the
   `Unreleased` entries in [`CHANGELOG.md`](CHANGELOG.md) under the new version.
2. Merge that to `main`, then tag it:

   ```sh
   git tag -a v0.2.0 -m "Chargectl 0.2.0" && git push origin v0.2.0
   ```

The [release workflow](.github/workflows/release.yml) checks that the tag
matches `project.yml`, runs the tests, and builds and attests
`Chargectl-<version>.zip`, while the cask check runs on another runner. Once
both are done, it publishes the release with notes from the changelog, and
opens a pull request that updates the cask in
[tyldra-org/homebrew-tools](https://github.com/tyldra-org/homebrew-tools).
Running the workflow by hand from the Actions tab is a dry run: the same checks
and signed build, with nothing published. `./scripts/package.sh` builds the same
zip locally.

Charging decisions live in [`ChargePolicy`](Shared/Control/ChargePolicy.swift),
a pure function tested without hardware. Read [CONTRIBUTING.md](CONTRIBUTING.md)
before opening a pull request, and [AGENTS.md](AGENTS.md) if you work with a
coding agent.

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) and follow the
[Code of Conduct](CODE_OF_CONDUCT.md). Changes to how charging is controlled must
be tried on a real MacBook; say which one in the pull request.

## Security

Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md). Do
not open public issues for security problems.

## License

Chargectl is licensed under the [Apache License 2.0](LICENSE).
Copyright 2026 Yogesh Prasad.
