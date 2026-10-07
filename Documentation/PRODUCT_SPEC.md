# F Renamer - Product Spec

## Purpose
A local native macOS utility that prepares WAV multitracks for DAW import by proposing safe filename cleanup and requiring preview before a rename.

## Current scope
- macOS 14+, Apple Silicon (`arm64`) only.
- Inputs: a folder, WAV files, or a mixed selection. Folder scanning is top-level only.
- WAV filtering is case-insensitive (`.wav` / `.WAV`).
- Batch filename analysis: track-number removal, common left/right segment evidence, Russian instrument normalization, optional lightweight capitalization, confidence, and conflict detection.
- Duplicate generated target names are deterministically numbered (`Name 1.wav`, `Name 2.wav`) before preview, while occupied filesystem slots are skipped.
- Editable preview and transactional two-phase rename with rollback on failure.
- Finder Quick Action: **F Renamer** accepts one folder or WAV files from one location and opens the existing main-app preview.

## Safety rules
- No write occurs during scan or analysis.
- Preview and confirmation are mandatory.
- Existing files are never overwritten.
- Manual edits always take priority over generated formatting; collisions created by a manual edit still block Rename.
- Duplicate output names, invalid names, unavailable sources, and existing targets block Rename.
- Audio bytes and metadata are never opened or modified; only filesystem names change.
- A Finder request cannot replace a preview containing manual edits without explicit confirmation.

## Non-goals
No audio inspection, DAW integration, cloud, account, database, AI/API, recursive indexing, project management, or telemetry.

## Finder Quick Action
- The native macOS Action Extension is embedded in the app and is labeled **F Renamer** in Finder.
- It supports one folder, one WAV, or multiple WAV files from the same directory. Folders are scanned by the existing top-level `FileScanner`; file selections remain file selections.
- Unsupported selected files are ignored. Multiple folders or WAV files from different folders show: `Please select one folder or WAV files from the same location.`
- The Action Extension does not analyze or rename. It transfers a short-lived ordinary URL bookmark request through a uniquely named pasteboard; the app opens its normal preview, validation, and transactional rename flow.
- The extension and app use only App Sandbox plus user-selected read/write access. App Groups and persistent bookmark capabilities are not required, so the local workflow is compatible with Xcode Personal Team signing. See `ARCHITECTURE.md` and `TEST_CASES.md`.
