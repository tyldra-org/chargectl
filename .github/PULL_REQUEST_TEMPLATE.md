<!--
Title must be a conventional commit: type(scope): description
It becomes the squash-merge commit subject.
-->

## What and why

<!-- What does this change and what problem does it solve? -->

Closes #

## How it was verified

<!-- Exact commands run and their results; screenshots for UI changes.
For changes to how charging is controlled, name the Mac and macOS version
and describe what the battery did. -->

```sh
./scripts/check.sh
```

## Checklist

- [ ] The title follows Conventional Commits.
- [ ] Tests cover the change, or the reason they do not is stated above.
- [ ] Documentation and `CHANGELOG.md` are updated for user-visible changes.
- [ ] Breaking changes are marked with `!` and the migration is described.
