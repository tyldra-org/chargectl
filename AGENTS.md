# AGENTS.md

Instructions for AI coding agents working in Chargectl. Humans should read
[CONTRIBUTING.md](CONTRIBUTING.md); this file is the agent-facing summary.
The user's instructions in the conversation override this file.

## Project

A macOS menu bar app and root service that keep a MacBook's battery at a
charge limit.

Stack: Swift 5 language mode, SwiftUI and AppKit, XcodeGen, Swift Testing.
Default actor isolation is `MainActor` with complete strict concurrency.
macOS 27 and Xcode 27 only (`scripts/env.sh` refuses any other Xcode).

## Skill routing

Before the first action of any task, find the rows below that match the work
and load those skills first, from the global `~/.agents/skills/` installation.
Do not start reading code, editing or running commands until they are loaded.
When several rows match, load each; when the work changes mid-task, load the
newly matching skills before continuing. Human contributors do not need them.

| Work | Skill |
| --- | --- |
| Any non-trivial code change: design, implementation, debugging | `engineering-judgment` |
| Swift, SwiftUI, AppKit, XPC, concurrency, Xcode and XcodeGen | `swift-development` |
| Dashboard and menu bar panel look, layout, color | `design` |
| Reviewing a diff, branch or pull request | `code-review` plus `swift-development` |
| Only when the user asks to simplify code or for a strict review | `code-quality` |
| Any Git command: status, diff, staging, commits, branches, history | `git` |
| GitHub work: issues, pull requests, Actions and CI logs, releases | `github` |
| This file or other agent instruction files | `agents-md` |
| Commit messages, PR text, release notes, docs | `unslop` |

## Commands

| Purpose | Command |
| --- | --- |
| Generate the Xcode project | `./scripts/generate.sh` |
| Build | `./scripts/build.sh Release` |
| Test | `./scripts/test.sh` |
| Format check | `xcrun swift-format lint --strict --recursive App Daemon Shared Tests Widgets` |
| Everything CI runs | `./scripts/check.sh` (`--list` shows stages; one stage: `./scripts/check.sh test`) |
| Fix formatting | `xcrun swift-format format --in-place --recursive App Daemon Shared Tests Widgets` |
| Package a release zip | `./scripts/package.sh` |
| Print the Homebrew cask | `./scripts/cask.sh <version> <sha256>` |
| Check the cask as the tap's CI does | `./scripts/check.sh cask` |

The build and test scripts regenerate the Xcode project from `project.yml`
first, so edit `project.yml`, never the generated `.xcodeproj`.

While iterating, run one suite instead of the whole test run:

```sh
./scripts/generate.sh
xcodebuild -quiet -project Chargectl.xcodeproj -scheme Chargectl \
  -destination 'platform=macOS' \
  -derivedDataPath "${TMPDIR:-/tmp}/Chargectl-DerivedData" \
  test -only-testing:ChargectlTests/ChargePolicyTests
```

Run `./scripts/check.sh` once before saying the work is done.

## Never run

- `./scripts/install.sh`, `./scripts/uninstall.sh` or `./scripts/run.sh`
  unless the user asks. They change how the Mac charges.
- Anything that writes SMC keys or PowerUIAgent preferences outside the app.
- `git push --force` to `main`, or any push to a remote, unless the user asks.
- Any command that changes GitHub state (`gh repo edit`, `gh label`,
  `gh release create`, `gh secret`, `gh api -X POST|PUT|PATCH|DELETE`),
  unless the user asks.
- Commands that publish packages or create tags.

## Where things live

| Path | Contents |
| --- | --- |
| `App/` | Menu bar app: dashboard pages, menu bar panel, XPC client |
| `Daemon/` | `Chargectl Service` (target `chargectld`): control loop, SMC and macOS limit adapters, XPC service |
| `Widgets/` | Widget extension: widgets for every size, Control Center controls; `Widgets/Views` is also drawn by the app for design renders |
| `Shared/` | Code built into both: SMC access, battery readings, `ChargePolicy`, XPC models |
| `Tests/` | Swift Testing suites (`ChargectlTests` target) for the policy, charge estimate, release and shared models |
| `scripts/` | Build, test, install, uninstall and `check.sh` |
| `project.yml` | XcodeGen spec; the `.xcodeproj` is generated and not committed |
| `.github/` | Workflows (CI and tag-triggered release) and templates |

## Conventions

- Charging decisions belong in `ChargePolicy`, which is pure and tested. The
  daemon only reads hardware and applies decisions.
- Log what the hardware did (`PowerObserver`) separately from what Chargectl
  decided.
- Conventional commits: `type(scope?): description`. Pull requests are squash
  merged with the PR title as the commit subject.
- Keep changes focused; do not reformat or refactor unrelated code.
- Pin GitHub Actions to full commit SHAs with the tag in a trailing comment.
- Add a `CHANGELOG.md` entry under `Unreleased` for user-visible changes.

## Proving a change

A change is done when:

1. `./scripts/check.sh` passes locally.
2. New behavior has a test that fails without the change.
3. The PR description states what changed, why, and the exact commands used to
   verify it, including the Mac it ran on for charging changes.
