# Security policy

## Supported versions

Chargectl has no releases yet. Security fixes land on `main`; build from the
newest commit to receive them.

## Reporting a vulnerability

Do not report security vulnerabilities through public issues, discussions or
pull requests.

Report privately through
[GitHub private vulnerability reporting](https://github.com/tyldra-org/chargectl/security/advisories/new).
If you cannot use GitHub, email yogeshprasad098@gmail.com.

Include as much of the following as you can:

- The affected commit.
- The type of issue and its impact.
- Step-by-step reproduction, proof of concept, or exploit code.
- Any known workaround.

## What to expect

- Acknowledgement within 7 days.
- An initial assessment, including severity, within 14 days.
- Progress updates until resolution.
- A fix and a GitHub Security Advisory. You are credited in the advisory
  unless you ask not to be.

This is a volunteer-maintained project; these are targets, not guarantees.

## Disclosure policy

The project follows coordinated disclosure. Please give maintainers a
reasonable time to release a fix, normally up to 90 days, before public
disclosure. Maintainers will agree a disclosure date with you.

## What the helper can do

The helper, `Chargectl Service` (built from the `chargectld` target), lives inside
`Chargectl.app`. Install Helper installs it as a launchd daemon with your
administrator password, or registers it with SMAppService for builds signed with
a team; either way launchd runs it as root. It can:

- switch wall power on and off and set the MagSafe LED through SMC keys;
- set macOS's charge limit, including writing PowerUIAgent's preferences;
- keep the Mac awake with a power assertion;
- read and write its own files in `/Library/Application Support/Chargectl`.

The app checks `api.github.com` for new releases every few hours. Before
installing one, it checks the zip against the release's SHA-256 file, verifies
its code signature, and requires the bundle identifier `com.tyldra.chargectl`
and the expected version. Releases are signed ad hoc, so the signature proves the
app is intact, not who built it; the checksum comes from the same GitHub
release over HTTPS.

While its launchd plist is installed, the helper keeps a sudoers rule in
`/private/etc/sudoers.d/chargectl`, checked with `visudo` before it is moved in
place. It lets members of `admin` run exactly `launchctl enable` for the
helper's label and `launchctl bootstrap` for its root-owned plist without a
password, so the app can start the helper after a macOS update has moved it
aside. Removing the helper or uninstalling deletes the rule.

It accepts XPC connections only from the Chargectl app. When the build is signed
with a team, the app must carry the same team identifier. Ad-hoc builds can only
require the identifier `com.tyldra.chargectl`, so any local process signed ad hoc
with that identifier can change charging behavior. Clients cannot make the service run
commands or read other files. Reports that widen this boundary are in scope.
