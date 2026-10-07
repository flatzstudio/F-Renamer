# F Renamer

English · [Русский](README.ru.md)

F Renamer is a native macOS utility for cleaning and standardizing multitrack WAV filenames. It analyzes a batch, shows an editable preview, validates every destination, then renames files transactionally. It never reads or changes audio content.

## Requirements

- macOS 14 or later
- Apple Silicon (arm64)

## Features

- Add WAV files or scan the top level of a folder; `.wav` matching is case-insensitive.
- Detect track-number prefixes, shared filename segments, and supported instrument names.
- Optionally capitalize names while preserving technical/music tokens.
- Review and edit every proposed name before applying changes.
- Prevent overwrites and duplicate destinations; attempt rollback if a batch rename fails.
- Use the Finder Quick Action to send a folder or WAV selection to the app's normal preview.
- Switch the interface between English and Russian.

## Build and Test

Run the test suite:

```sh
swift test --arch arm64
```

Build the app and Finder extension in Xcode using the `MultitrackCleaner` scheme. Select a signing team in Xcode if you want to install and test the Finder Quick Action. The project intentionally does not store a developer's signing Team ID.

See [CHANGELOG.md](CHANGELOG.md) and [Documentation/TEST_CASES.md](Documentation/TEST_CASES.md) for release notes and manual Finder checks.

The 1.0.0 archive prepared for this release candidate is unsigned. It is for local evaluation only; signing the app and enabling the Finder Quick Action requires selecting your Apple Development team in Xcode.

## Privacy and Safety

F Renamer works locally. It has no account, cloud service, telemetry, or network requirement. It changes filenames only after preview and confirmation. Existing files are not overwritten.

## License

MIT. See [LICENSE](LICENSE).
