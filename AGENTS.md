# Agent instructions

Read `README.md` for behavior and architecture and `CONTRIBUTING.md` for development rules. Pure logic belongs in `KeyFlipCore` with regression tests; macOS integration belongs in `KeyFlip`.

## Changelog and version: required for every change

The changelog and the app version must stay current. Do not commit a user-visible change without them.

1. **Every user-visible change** (behavior, UI text, permissions, privacy, compatibility, fixes) gets a line in `CHANGELOG.md` under `## [Unreleased]`, in the same commit as the change. Use the subsections `### Added`, `### Changed`, `### Fixed`, `### Removed`, and `### Privacy`. Write for users, not about code. Internal refactors and test-only changes need no entry.
2. **Releasing a version** (when asked to release, or when committing a finished user-visible change for the user to install):
   - Bump `CFBundleShortVersionString` in `Resources/Info.plist` using semantic versioning: patch for fixes, minor for new features or behavior changes. Always increase `CFBundleVersion` by 1.
   - Rename `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD` and add a new empty `## [Unreleased]` above it.
   - Update the comparison links at the bottom of `CHANGELOG.md`.
   - Commit, then create an annotated tag `vX.Y.Z` on that commit and push it with the branch: `git push origin main --follow-tags`.
3. If a change affects what KeyFlip reads, keeps in memory, or puts on the clipboard, update the Privacy section of `README.md` and the permission text in `SettingsView.swift` as well.

## Before committing

Run all of these and make sure they pass:

```sh
bash scripts/test.sh
bash scripts/build-app.sh
bash scripts/check-platform.sh --with-layouts
```

Update `docs/TESTING.md` when you add test scenarios or manual checks. Report which real editors were or were not checked by hand.

## Git

- `main` is the only branch, locally and on GitHub. Commit to `main` and push to `origin main`; do not leave other branches behind.
- Commit messages are in English.

## Installing a build

The build is signed ad hoc, so every reinstall invalidates macOS permission grants. To install: quit KeyFlip, replace `~/Applications/KeyFlip.app` with `dist/KeyFlip.app`, reset stale grants with `tccutil reset Accessibility local.keyflip.mac` and `tccutil reset ListenEvent local.keyflip.mac`, and relaunch. Only the user can grant Accessibility and Input Monitoring again in System Settings; tell them to.
