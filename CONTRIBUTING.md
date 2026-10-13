# Contributing to KeyFlip

Bug reports and pull requests are welcome. For compatibility reports, include
the KeyFlip version, macOS version, application/version, field type, whether
you used a selection or the word before the cursor, and the status message
shown in Settings. Use invented text instead of private drafts or clipboard
contents. See [the testing guide](docs/TESTING.md).

## Development

You need macOS 13 or later and Swift 5.9 or later. There are no external
packages to install.

```sh
bash scripts/test.sh
bash scripts/build-app.sh
```

Use `scripts/test.sh` rather than `swift test`: the test suite is a standalone
executable. Keep platform-independent logic in `KeyFlipCore` and macOS
integration in `KeyFlip`. Add regression coverage for behavioral fixes and
describe which editors you checked when changing text replacement.

Desktop checks are available through `scripts/check-platform.sh`; add
`--with-layouts` when English and Russian layouts are enabled. These checks
do not replace the manual editor checks in the testing guide.

## Pull requests

Explain the problem, the resulting behavior, and how you tested the change.
Keep generated bundles, build caches, signing material, and personal data
out of commits. Contributions intended for inclusion in this project are
provided under its [MIT license](LICENSE).
