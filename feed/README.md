# Remote config

Chargectl reads `app.json` from `main` with every update check: hourly, on
wake and 10 seconds after launch. It keeps the last copy whose signature
checked out, so its prompts show right after a restart or an update.

What it can change without a release:

- **items:** a `prompt` (the card in the middle of the dashboard, like the
  update prompt) or a `banner` (top of every page), with a title, body,
  optional commands to copy or a link, and `later` or `done` dismissal.
- **flags:** `{"name": {"on": true}}`, read in code with
  `RemoteContent.shared.flag("name", default: false)`.
- **values:** `{"name": {"number": 30}}`, read with
  `RemoteContent.shared.value("name", default: 5)`.

Each one can take `when`: `below` and `atLeast` (versions), `tapped` (a
Homebrew tap on the Mac), `installedFrom` (the tap Homebrew installed
Chargectl from) and `homebrew` (true or false). Items also take `until`.
Target narrowly, so people who already did the thing never see it.

Nothing in the file runs. A new kind of block or action needs a release.

After any edit, sign it and commit both files:

```sh
swift scripts/remote-config.swift sign feed/app.json
```

The test `theRepositorysFileIsSigned` fails when the two don't match. The
private key lives in the maintainer's login Keychain (service
`tyldra.remote-config`); the app carries the public key in
`Shared/Remote/RemoteConfig.swift`.
