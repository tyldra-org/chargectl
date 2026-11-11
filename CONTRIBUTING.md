# Contributing to Chargectl

This guide explains how to propose a change and what makes it easy to accept.

## Before you start

- Read the [Code of Conduct](CODE_OF_CONDUCT.md). It applies everywhere the
  project operates.
- Search [existing issues](https://github.com/tyldra-org/chargectl/issues) first.
- Every pull request starts from an issue. Find one or open one; for anything
  larger than a small fix, agree on the approach there before writing code.
- Report security problems privately through [SECURITY.md](SECURITY.md), never
  in a public issue.
- Issues labelled `good first issue` and `help wanted` are ready for outside
  contributors.

## Set up

You need an Apple silicon Mac on macOS 27, Xcode 27 and XcodeGen.

```sh
brew install xcodegen
git clone https://github.com/tyldra-org/chargectl.git
cd chargectl
./scripts/check.sh
```

`./scripts/install.sh` installs your build with its root service, so you can
try it on your own Mac. `./scripts/uninstall.sh` removes it again.

### Signing

`install.sh` signs with a Developer ID or Apple Development certificate when one
is in your keychain (see [`scripts/signing.sh`](scripts/signing.sh)); otherwise
the build is signed ad hoc, as releases are.

- **Ad hoc:** Install Helper copies the helper to
  `/Library/PrivilegedHelperTools` and writes a launchd job to
  `/Library/LaunchDaemons` that runs that root-owned copy, with your
  administrator password. macOS ties a background item's approval to an ad-hoc
  build, so the Login Items route would stop the helper after every update; a
  launchd job keeps working. Login Items lists it as "Chargectl Service", the
  copy's file name, apart from Chargectl: macOS ties a launchd job to its app
  (`AssociatedBundleIdentifiers`) only when both are signed by the same Apple
  team. An update replaces the copy only when the new helper is signed with the
  release certificate; otherwise the app asks to install it again.
- **Release certificate:** `./scripts/make-release-certificate.sh <folder>`
  creates a self-signed code-signing certificate and prints the commands that
  store it as the release workflow's secrets. Releases are then signed with it,
  its SHA-1 is built into the app and the helper, and updates replace the helper
  without a password. Keep the `.p12` private and backed up.
- **With a team:** Install Helper registers the helper with SMAppService. It is
  listed under Chargectl in Login Items, you turn it on once, and the approval
  carries over to updates. The helper only accepts the Chargectl app signed by
  the same team.

## Make a change

1. Fork the repository and create a branch from `main`.
2. Keep the change focused on one purpose. Split unrelated work into separate
   pull requests.
3. Add or update tests that prove the change. Charging decisions live in
   `Shared/Control/ChargePolicy.swift` and are tested without hardware in
   `Tests/`.
4. Update documentation and `CHANGELOG.md` under `Unreleased` when behavior
   visible to users changes.
5. Run the full local check, which is the same entry point CI runs:

   ```sh
   ./scripts/check.sh
   ```

   Individual stages:

   | Stage | Command |
   | --- | --- |
   | Format | `xcrun swift-format lint --strict --recursive App Daemon Shared Tests Widgets` |
   | Build | `./scripts/build.sh Release` |
   | Test | `./scripts/test.sh` |
   | Shell | `shellcheck` on every tracked `*.sh` file |
   | Workflows | `actionlint`, `zizmor`, then `scripts/ci-scope.test.sh` |
   | Cask | `./scripts/check-cask.sh`: the Homebrew tap's `brew style` and `brew audit` on the cask |

   Fix formatting with `xcrun swift-format format --in-place --recursive App Daemon Shared Tests Widgets`.

   CI runs only what your change needs (`scripts/ci-scope.sh` decides). A
   docs-only pull request skips the macOS build. A Swift change runs only the
   test suites it reaches: the suites that name a type it declares, directly or
   through the Shared and Daemon files that use it. App and widget code isn't
   in the test target, so changing only that builds the tests without running
   them. Changes to `project.yml`, the test scripts or the CI wiring run
   everything, and so does every push to `main`. So does a file in none of the
   script's lists: when you add a new kind of file, add it to the list for what
   reads it, with a case in `scripts/ci-scope.test.sh`. To see what CI will pick
   for your branch, run `./scripts/ci-scope.sh areas origin/main` and
   `./scripts/ci-scope.sh tests origin/main`.

Changes to how charging is controlled must also be tried on a real MacBook.
Say in the pull request which Mac and macOS version you used and what you saw.

### Screenshots

The README's pictures come from a Debug build with sample data, so they need no
helper. Update them when the app's look changes:

- **Pages and setup:** `./scripts/build.sh Debug`, then
  `./scripts/screenshots.sh`. It writes every dashboard page and the first
  setup step, in dark and light, to `docs/assets/screenshots`. Windows open on
  your sharpest screen, so use a Retina display.
- **Widgets:** `"$TMPDIR/Chargectl-DerivedData/Build/Products/Debug/Chargectl.app/Contents/MacOS/Chargectl" --render-design <folder> --only readme-widgets`,
  then copy `readme-widgets-dark.png` and `readme-widgets-light.png` to
  `docs/assets/screenshots/widgets-dark.png` and `widgets-light.png`.
- **Menu bar panel:** run the Debug build with `--demo`, open the panel, press
  ⌘⇧4 then Space, and click the panel. Save it as `menu-bar.png`.
- **App icon:** after editing `App/Resources/AppIcon.icon` in Icon Composer,
  export the README's copy with Icon Composer's `ictool`, then pad it to the
  macOS icon grid:

  ```sh
  "$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool" \
    App/Resources/AppIcon.icon --export-image --output-file /tmp/icon.png \
    --platform macOS --rendition Default --width 103 --height 103 --scale 2
  magick /tmp/icon.png -background none -gravity center -extent 256x256 docs/assets/icon.png
  ```

## Commit messages and pull request titles

This project uses [Conventional Commits](https://www.conventionalcommits.org/).
Pull requests are squash merged and the pull request title becomes the commit
subject, so the title should follow the format:

```text
type(optional-scope): short imperative description
```

Allowed types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`,
`build`, `ci`, `chore`, `revert`. Mark breaking changes with `!` after the type
or scope and explain the migration in the body.

## Files only maintainers change

Pull requests from contributors without write access cannot change these; the
`protected-files` check fails if they do. Open an issue describing the change
instead.

- `.github/`: workflows, issue forms, the pull request template and Dependabot.
- `LICENSE`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, `CONTRIBUTING.md` and other
  policy files.
- `AGENTS.md`.
- `scripts/check.sh` and `scripts/ci-scope.sh`, which decide what CI checks.
- The release and signing scripts: `package.sh`, `signing.sh`, `version.sh`,
  `import-release-certificate.sh`, `make-release-certificate.sh`, `cask.sh`,
  `check-cask.sh` and `release-notes.sh` in `scripts/`.
- The `.entitlements` files, which set what the app and widgets may do.

## Pull requests

- Name the issue it resolves in the description: `Closes #<number>`. The
  `linked-issue` check fails without one. Dependabot's pull requests are the
  only exception.
- Fill in the pull request template, including how you verified the change.
- Keep pull requests small; they are reviewed faster and more thoroughly.
- All required checks must pass before merge.
- A maintainer will review, usually within a few working days. If there is no
  response after a week, a polite ping on the pull request is welcome.

## Licensing

Contributions are licensed under the project license, Apache-2.0 (see
[LICENSE](LICENSE)), without additional terms. Submit only work you have the
right to license that way.

## AI-assisted contributions

AI tools are welcome. You remain responsible for every line you submit: read
it, test it, and be able to explain it. Agents should follow
[AGENTS.md](AGENTS.md).
