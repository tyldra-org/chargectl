# Contributing to Chargectl

This guide explains how to propose a change and what makes it easy to accept.

## Before you start

- Read the [Code of Conduct](CODE_OF_CONDUCT.md). It applies everywhere the
  project operates.
- Search [existing issues](https://github.com/tyldra-org/chargectl/issues) first.
- For anything larger than a small fix, open an issue to agree on the approach
  before writing code.
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
  launchd job keeps working. Login Items lists it as "Chargectl Service". An
  update replaces the copy only when the new helper is signed with the release
  certificate; otherwise the app asks to install it again.
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
   | Workflows | `actionlint` |

   Fix formatting with `xcrun swift-format format --in-place --recursive App Daemon Shared Tests Widgets`.

Changes to how charging is controlled must also be tried on a real MacBook.
Say in the pull request which Mac and macOS version you used and what you saw.

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

## Pull requests

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
