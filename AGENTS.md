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
| CI and release workflows, `scripts/check.sh`, `scripts/ci-scope.sh`, the cask, README, CONTRIBUTING, SECURITY | `open-source-repo` |
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
| Test | `./scripts/test.sh` (some suites: `CHARGECTL_TEST_SUITES='ChargePolicyTests' ./scripts/test.sh`) |
| The jobs and test suites CI picks for your branch | `./scripts/ci-scope.sh areas origin/main`, `./scripts/ci-scope.sh tests origin/main` |
| Format check | `xcrun swift-format lint --strict --recursive App Daemon Shared Tests Widgets` |
| Everything CI runs | `./scripts/check.sh` (`--list` shows stages; one stage: `./scripts/check.sh test`). A missing tool (`shellcheck`, `actionlint`, `zizmor`, `brew`) is skipped and named; CI runs `--all`, where a skip fails |
| Fix formatting | `xcrun swift-format format --in-place --recursive App Daemon Shared Tests Widgets` |
| Package a release zip | `./scripts/package.sh` |
| Print the Homebrew cask | `./scripts/cask.sh <version> <sha256>` |
| Check the cask as the tap's CI does | `./scripts/check.sh cask` |
| Retake the README screenshots | `./scripts/screenshots.sh` (after `./scripts/build.sh Debug`; see CONTRIBUTING.md) |
| Render the dashboard pages, menu bar panel and widgets to PNG files, light and dark, with sample data | `"${TMPDIR:-/tmp}/Chargectl-DerivedData/Build/Products/Debug/Chargectl.app/Contents/MacOS/Chargectl" --render-design <folder> --only <name prefix>` after `./scripts/build.sh Debug`. It never talks to the helper; shot names are in `App/Debug/DesignRender.swift` |
| Try a changed release workflow without publishing (only when the user asks) | `gh workflow run release.yml --ref <branch>` |

The build and test scripts regenerate the Xcode project from `project.yml`
first, so edit `project.yml`, never the generated `.xcodeproj`.

While iterating, run only the suites your change reaches, as CI does for a pull
request:

```sh
CHARGECTL_TEST_SUITES="$(./scripts/ci-scope.sh tests origin/main | cut -d= -f2)" ./scripts/test.sh
```

A new kind of file goes in a list in `scripts/ci-scope.sh` with a case in
`scripts/ci-scope.test.sh`. A path that no list names makes CI run every check.

Run `./scripts/check.sh` once before saying the work is done.

## Never run

- `./scripts/install.sh`, `./scripts/uninstall.sh` or `./scripts/run.sh`
  unless the user asks. They change how the Mac charges.
- Anything that writes SMC keys or PowerUIAgent preferences outside the app.
- Commits, pushes of a work branch, pull requests, merges through the
  required checks, and issue work for the change, unless the user asks,
  in the conversation or in standing instructions (for example an automatic
  mode in their own agent files).
- A force push, a rewrite of pushed history, a tag or a release, unless the
  user asks in this conversation. A `v*` tag publishes a release.
- Any other command that changes GitHub state (`gh repo edit`, `gh label`,
  `gh release create`, `gh secret`, `gh api -X POST|PUT|PATCH|DELETE`),
  unless the user asks in this conversation.
- Edits to the files CONTRIBUTING lists under "Files only maintainers change",
  unless you work as the maintainer: the `protected-files` check fails the
  pull request.

## Where things live

| Path | Contents |
| --- | --- |
| `App/` | Menu bar app: dashboard pages, menu bar panel, XPC client |
| `App/Resources/AppIcon.icon` | The app icon, an Icon Composer document (Xcode › Open Developer Tool › Icon Composer) with SVG layers |
| `Daemon/` | `Chargectl Service` (target `chargectld`): control loop, SMC and macOS limit adapters, XPC service |
| `Widgets/` | Widget extension: widgets for every size, Control Center controls; `Widgets/Views` is also drawn by the app for design renders |
| `Shared/` | Code built into both: SMC access, battery readings, `ChargePolicy`, XPC models |
| `Tests/` | Swift Testing suites (`ChargectlTests` target). The target builds `Shared` and `Daemon` only; `App` and `Widgets` are not in it, so testable logic belongs in `Shared` |
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
- Every pull request closes an issue: find or open it first and put
  `Closes #<n>` in the body. The required `linked-issue` check fails without
  one; only Dependabot is exempt.
- Keep changes focused; do not reformat or refactor unrelated code.
- Pin GitHub Actions to full commit SHAs with the tag in a trailing comment.
- Add a `CHANGELOG.md` entry under `Unreleased` for user-visible changes.

## Proving a change

A change is done when:

1. `./scripts/check.sh` passes locally.
2. New behavior has a test that fails without the change.
3. The PR description states what changed, why, and the exact commands used to
   verify it, including the Mac it ran on for charging changes.
