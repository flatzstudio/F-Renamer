# Test Cases

## Unit and filesystem integration coverage
- WAV scan: top-level only, case-insensitive extension, deduplication, natural stable ordering.
- Numeric prefixes: separator and whitespace forms; preserve `808`, `909`, `303`, and `12 String`.
- Batch analyzer sets A–E: leading/trailing common segments, real-world Cyrillic fixture, and Russian normalization.
- Capitalization: opt-in behavior, lightweight wording preservation, protected uppercase technical/music tokens, numeric-only names, and manual-target preservation when toggled.
- Duplicate resolver: deterministic `Name 1.wav` allocation, filesystem-occupied slot skipping, unique meaningful numeric names left unchanged, and manual-target priority.
- Validator: duplicate outputs scoped to the same directory, external target collision, invalid names, and no-change proposals.
- Rename engine: rename, A/B swap, collision prevention, and rollback after injected failure.
- Finder selection parsing: folder, WAV, multiple WAV, mixed unsupported items, Unicode/spaces, multiple folders, and files from different parent directories.
- Finder handoff: one-time named-pasteboard request claiming, opaque custom URL validation, and preservation of scanner natural ordering.

## Commands

```bash
swift test --arch arm64

xcodebuild test \
  -project MultitrackCleaner.xcodeproj \
  -scheme MultitrackCleaner \
  -configuration Debug \
  -sdk macosx \
  -destination 'platform=macOS,arch=arm64' \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO
```

## Manual smoke procedure
1. Create a temporary folder with WAV-named files.
2. Open it in the application using **Choose Folder** or drag it into the drop zone.
3. Confirm Before → After proposals and manually edit one target.
4. Select **Rename** and verify filesystem names.

## Finder Quick Action smoke procedure
A real Finder smoke test requires a locally signed containing app and extension. Xcode Personal Team signing is sufficient for this local-only workflow; unsigned `CODE_SIGNING_ALLOWED=NO` output is intentionally not accepted as proof of Finder/security-scope behavior.

1. Sign into Xcode with the Personal Team, build the app with signing enabled, and run the containing app from Xcode or a stable Applications location.
2. Confirm **F Renamer** appears under Finder **Quick Actions**; enable it in macOS extension settings if necessary.
3. **Folder:** right-click one folder containing WAV files, choose **Quick Actions → F Renamer**, and confirm the app opens that top-level folder in the normal preview. Perform a rename and verify names in Finder.
4. **Multiple WAV:** select WAV files from one folder, run the action, and confirm only those files appear in natural order. Perform a rename and verify Finder names.
5. **Already running:** leave the app open, invoke the action again, and confirm no second app process is created and the preview updates. Add a manual edit first and confirm the replacement alert appears.
6. **Unicode:** invoke the action with `01 - Вокал Максим.wav`, `02 - Гитара левая.wav`, and `03 - Гитара правая.wav`; verify preview and resulting filenames are not damaged.
7. Verify error cases: only unsupported items, multiple folders, files from different folders, missing item, expired handoff, and denied access.
8. Inspect both signed products with `codesign -d --entitlements :-`. Confirm both include App Sandbox and user-selected read/write access, and neither contains `com.apple.security.application-groups` or `com.apple.security.files.bookmarks.app-scope`.

## Known limitation
A free Personal Team permits local Xcode deployment only. Its profiles expire after seven days, so the app and Finder extension must be rebuilt/reinstalled periodically. This workflow does not provide App Store distribution or notarization.
