# Architecture

## Layers
`SwiftUI views → RenamePreviewViewModel → domain services → Foundation`.

The executable target is both a native SwiftUI app and a testable Swift package. All logic lives outside views.

## Core
- `FileScanner`: reads selected URLs, expands only top-level folders, filters WAV files, deduplicates and naturally sorts.
- `FilenameAnalyzer`: batch pipeline. It removes only confirmed numeric prefixes, uses common segment evidence, normalizes instruments, optionally applies lightweight capitalization, scores confidence, and produces proposals.
- `NameCapitalizer`: applies the user-controlled capitalization option without lowercasing existing content; technical/music tokens such as `MIDI`, `FX`, `OH`, `L`, `R`, `LR`, `VCA`, `DI`, and `AMBIENCE` remain uppercase.
- `ProposedNameResolver`: after analysis and before preview validation, detects equal generated targets in the same directory and assigns deterministic numbered names. It reserves manual and unchanged targets, checks filesystem slots, and skips occupied numbers. It never changes manual edits.
- `RenameValidator` / `RenamePlanner`: revalidates proposals against the live filesystem immediately before mutation. Duplicate comparison includes the parent directory, so separate folders do not conflict.
- `RenameEngine`: moves every source to a UUID temporary sibling, then to its target. On failure it restores all available files to their original names.

## Proposal order
`FileScanner` natural order is preserved through analysis and duplicate allocation. The generated proposal sequence is: parse → confirmed numeric-prefix removal → supported common-segment removal → known-term normalization → optional capitalization → filesystem-aware duplicate numbering → validation → editable preview → manual approval → transactional rename. Toggling capitalization regenerates automatic proposals but preserves each manual target.

## Common segments
`CommonSegmentDetector` only reports leading and trailing matching segments. `FilenameAnalyzer` decides removability. It removes a common side only when every resulting candidate remains non-empty and at least one of numeric-prefix, opposite common side, or a recognized instrument makes the operation sufficiently supported. This prevents a set such as `Bass - Live` from being stripped to `Bass` merely because `Live` repeats.

## File access
The development build can be unsigned for SwiftPM and XCTest. The Finder workflow uses the standard `com.apple.security.app-sandbox` and `com.apple.security.files.user-selected.read-write` entitlements in both targets. It does not use App Groups or persistent security-scoped bookmark entitlements. `SecurityScopeLease` balances each successful `startAccessingSecurityScopedResource()` when a Finder selection is cleared or replaced, retaining write access through preview, transactional rename, and rollback. Full Disk Access is not required for ordinary accessible folders, although macOS permissions or privacy controls can still deny a location.

## Finder Quick Action
`MultitrackCleanerFinderAction` is a native Action Extension (`com.apple.ui-services`), embedded in `MultitrackCleaner.app/Contents/PlugIns`. It remains deliberately thin:

1. Finder supplies `public.file-url` attachments through `NSExtensionContext`.
2. The extension accepts one folder or regular WAV files from one directory, filtering unsupported items and rejecting multiple folders or file selections across directories.
3. While provider access is active, it creates ordinary, non-persistent URL bookmarks (`bookmarkData(options: [])`) and places a versioned request on a uniquely named `NSPasteboard`.
4. It opens `multitrackcleaner://import/<UUID>` with `NSExtensionContext.open`. The UUID is opaque; filesystem paths and bookmark data are never placed in the deep link.
5. `ApplicationInputRouter` validates the URL, claims and clears the named pasteboard request, resolves the ordinary bookmarks without authorization UI, and creates the security-scope lease.
6. `MainWindow` sends the resolved selection to the existing `RenamePreviewViewModel → FileScanner → analyzer → resolver → validator → RenameEngine` pipeline. It displays `Source: Finder` and prompts before replacing a preview with manual edits.

The custom URL scheme is only a launch/notification channel, not trusted IPC. The pasteboard payload is versioned, keyed by an unpredictable UUID, expires after 60 seconds, and is cleared after reading. If a bookmark cannot resolve or security scope cannot be acquired, the app surfaces an actionable error rather than falling back to raw paths.

Apple documents ordinary URL bookmarks as a way to share temporary file access between processes. The method keeps the containing app sandboxed and avoids an App Group container, so it is suitable for local Xcode deployment with a free Personal Team. It does not persist access across relaunches.

### Finder installation and debugging
Build and run the signed containing app from Xcode or a stable Applications location, then enable **F Renamer** in macOS extension settings if Finder does not list it immediately. Inspect signed entitlements with `codesign -d --entitlements :-` for the app and its embedded `.appex`; neither must contain `com.apple.security.application-groups` or a bookmark-scope entitlement. Test Finder from a directory outside the app container. Do not use Finder Sync, Automator, AppleScript, a launch agent, or shell `open` as a substitute.

## Platform
`Package.swift` declares macOS 14. Builds and tests are invoked with `--arch arm64`; the Xcode project build settings set `ARCHS = arm64` and exclude x86_64.
