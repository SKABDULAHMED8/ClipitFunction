# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-11-11

### Added
- `clipit "command"` for CMD, Windows PowerShell 5.1 and PowerShell 7: shows the output and copies the complete output to the clipboard once.
- Outputs over 100 KB are saved to a collision-safe TXT file; the file path is copied.
- `Clear`, `ClearW` (Windows Clipboard History, pinned items kept), `--last`, `--openlogs`, `--version`, `--help`.
- Cleanup commands `Clearp5f`, `Clearp7f`, `ClearC3`, `ClearAllF` (ask before deleting, never remove the folders).
- Per-user installer (`install.ps1` / `install.cmd`) with install, repair and uninstall; no administrator rights; no duplicate folders or profile entries; "already installed" detection; setup lock against double starts.
- Start Menu shortcut and *Apps & features* entry using the Clipit icon.
