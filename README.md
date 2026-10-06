# F Renamer

🇬🇧 English · [🇷🇺 Русский](README.ru.md)

A simple, fast and native macOS utility for batch renaming files.

F Renamer was originally created as a small tool for speeding up repetitive file organization in a music production workflow. It has since evolved into a general-purpose file renaming utility for macOS.

The goal is simple: **make repetitive renaming tasks fast, predictable and painless.**

## Features

- Batch rename multiple files
- Rename files directly from a selected folder
- Drag & drop files and folders
- Preview changes before applying them
- Undo the last rename operation
- Clear the current selection
- Convert filenames to title case
- Work with WAV files and folders
- Native macOS interface built with SwiftUI
- Lightweight and focused on one job

## Screenshots

<!-- Add screenshots here -->

## Why F Renamer?

Renaming a large number of files is one of those small tasks that can waste a surprising amount of time.

F Renamer was built around a practical workflow: select a group of files, apply the required naming operation, preview the result, and rename everything in one action.

It is designed to stay out of the way rather than turn a simple task into a complicated file-management suite.

## Requirements

- macOS 12.0 or later
- Apple Silicon or Intel Mac

## Installation

Download the latest release from the [Releases](../../releases) page and move **F Renamer.app** to your Applications folder.

## Usage

### Select a folder

Choose **Folder...** to select a directory.

F Renamer scans the selected folder and displays the files available for renaming.

### Select files

Choose **WAV Files...** or drag files directly into the application.

### Rename

Apply the desired naming operation, review the preview and rename the selected files.

### Undo

If you need to revert the most recent rename operation, use **Undo Last Rename**.

## Development

F Renamer is built natively for macOS using:

- Swift
- SwiftUI
- AppKit
- Xcode

The project is intentionally lightweight and does not depend on Electron or other cross-platform frameworks.

## Project Status

F Renamer is currently under active development.

The core renaming workflow is functional, while the interface and additional file-management features are still being refined.

Finder Quick Action integration is currently experimental and may change in future versions.

## Roadmap

Planned improvements include:

- [ ] Support for additional file types
- [ ] More filename transformation operations
- [ ] Prefix and suffix operations
- [ ] Find & replace
- [ ] Numbering and sequence generation
- [ ] Better rename preview
- [ ] Additional Finder integration
- [ ] Improved undo/history
- [ ] Localization
- [ ] Additional workflow automation

The roadmap is intentionally flexible and will evolve with the project.

## Localization

F Renamer is being designed with localization in mind.

The application currently supports English and Russian interfaces.

## Privacy

F Renamer is designed to work locally on your Mac.

The application does not upload your files or filenames to a remote server.

## Author

**Maxim**

Music producer and sound engineer.

Telegram: [@producermaxim](https://t.me/producermaxim)

## License

F Renamer is released under the MIT License.

See [LICENSE](LICENSE) for details.
