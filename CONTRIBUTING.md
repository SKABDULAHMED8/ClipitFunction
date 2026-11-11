# Contributing

Thanks for helping to improve Clipit!

## Reporting a problem

Open an issue and include:

- Windows version (`winver`) and shell (CMD, Windows PowerShell 5.1 or PowerShell 7)
- The exact command you ran and what you expected
- The output of `clipit --version`

## Code guidelines

- `src/clipit.ps1` and `install.ps1` must stay **ASCII-only** - Windows PowerShell 5.1 reads BOM-less files as ANSI.
- Everything must work in both **Windows PowerShell 5.1** and **PowerShell 7**, so avoid 7-only syntax (`?:`, `&&`, `??`).
- Keep `.cmd` and `.ps1` files with Windows (CRLF) line endings; `.gitattributes` protects this.
- The installer must stay **idempotent**: running it twice must never create duplicate folders, PATH entries or profile blocks.
- The CI workflow parses all scripts and runs an install / repair / uninstall round trip on Windows. Please make sure it passes.

## Pull requests

1. Fork the repository and create a branch.
2. Make a focused change and update `CHANGELOG.md`.
3. Open a pull request describing what changed and how you tested it.
