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

The helper, `Chargectl Service` (built from the `chargectld` target), ships inside
`Chargectl.app`. For builds without an Apple team, Install Helper copies it to
`/Library/PrivilegedHelperTools/Chargectl Service`, owned by root, and
installs a launchd daemon that runs that copy, with your administrator password.
launchd never runs the copy inside the app, because the app belongs to the user
who installed it and anything running as that user could replace it. Builds
signed with a team register the helper with SMAppService instead. Either way
launchd runs it as root. It can:

- switch wall power on and off and set the MagSafe LED through SMC keys;
- set macOS's charge limit, including writing PowerUIAgent's preferences;
- keep the Mac awake with a power assertion;
- read and write its own files in `/Library/Application Support/Chargectl`.

The app checks `api.github.com` for new releases every few hours. Before
installing one, it checks the zip against the release's SHA-256 file, verifies
its code signature, and requires the bundle identifier `com.tyldra.chargectl`
and the expected version. Releases signed with Chargectl's release certificate
(a self-signed code-signing certificate whose SHA-1 is built into the app and the
helper) must be signed with that certificate. Releases signed ad hoc prove only
that the app is intact, not who built it; their checksum comes from the same
GitHub release over HTTPS.

When the app is updated, the helper copies the new helper over its root-owned
copy only if the new one is signed with the release certificate; the copy is
checked after it is made, in the root-owned folder. Otherwise the old helper keeps
running and the app asks to install the new one with the administrator password.

While its launchd plist is installed, the helper keeps a sudoers rule in
`/private/etc/sudoers.d/chargectl`, checked with `visudo` before it is moved in
place. It lets members of `admin` run exactly `launchctl enable` for the
helper's label and `launchctl bootstrap` for its root-owned plist without a
password, so the app can start the helper after a macOS update has moved it
aside. Removing the helper or uninstalling deletes the rule.

It accepts XPC connections only from the Chargectl app. When the build is signed
with a team, the app must carry the same team identifier; with the release
certificate, that certificate. Ad-hoc builds can only require the identifier
`com.tyldra.chargectl`, so any local process signed ad hoc with that identifier
can change charging behavior. Release builds carry no `get-task-allow`
entitlement, so other processes cannot attach to the app and speak as it. Clients cannot make the service run
commands or read other files. Reports that widen this boundary are in scope.
