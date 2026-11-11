<p align="center">
  <img src="assets/clipit.png" alt="Clipit logo" width="220">
</p>

<h1 align="center">Clipit</h1>

<p align="center">
  <b>Run any command in CMD, PowerShell 5.1 or PowerShell 7 and copy its complete output to the clipboard - in one step.</b><br>
  Big outputs are saved to a log file automatically. One-command installer for Windows 10 / 11.
</p>

<p align="center">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-blue.svg">
  <img alt="Platform" src="https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-0078D6.svg">
  <img alt="Shells" src="https://img.shields.io/badge/shells-CMD%20%7C%20PowerShell%205.1%20%7C%207-5391FE.svg">
  <img alt="No admin" src="https://img.shields.io/badge/admin%20rights-not%20needed-success.svg">
</p>

---

## Why Clipit?

Copying terminal output by hand (select, scroll, copy, fix the wrapping) is slow and error-prone - especially when you want to paste the result into a chat, a bug report or an AI assistant. With Clipit you type one command and the **complete** output is already on your clipboard.

```text
C:\> clipit "ipconfig /all"
...normal output is shown...
---------------------------------------------
[CLIPIT]
Shell    : CMD.exe
Exit Code: 0
Output   : 3412 bytes
---------------------------------------------
Clipboard: complete output copied.
```

## Install

Open **CMD** or **PowerShell** (no administrator needed) and paste **one** line:

```bat
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/SKABDULAHMED8/ClipitFunction/main/install.ps1 | iex"
```

Then open a **new** terminal window and run `clipit --help`.

<details>
<summary><b>Other ways to install</b> (Git, ZIP)</summary>

**With Git**

```bat
git clone https://github.com/SKABDULAHMED8/ClipitFunction.git
cd ClipitFunction
install.cmd
```

**From a ZIP** - click *Code > Download ZIP*, extract it, and double-click `install.cmd`.

</details>

Running the installer again is always safe:

| Situation | What happens |
|---|---|
| Already installed and healthy | Says **"already installed"** and changes nothing |
| Partly installed or older version | Completes / updates only what is needed |
| You want a clean start | **Repair** removes the old install and creates a fresh one |
| Two installers started at once | The second one stops (setup is guarded by a lock) |

### Repair and uninstall

```bat
:: Repair (remove old, install fresh - your saved logs are kept)
powershell -NoProfile -ExecutionPolicy Bypass -Command "& ([scriptblock]::Create((irm https://raw.githubusercontent.com/SKABDULAHMED8/ClipitFunction/main/install.ps1))) -Repair"

:: Uninstall (saved logs are kept; add -Purge to delete them too)
powershell -NoProfile -ExecutionPolicy Bypass -Command "& ([scriptblock]::Create((irm https://raw.githubusercontent.com/SKABDULAHMED8/ClipitFunction/main/install.ps1))) -Uninstall"
```

If you cloned the repo you can use `install.cmd repair`, `install.cmd uninstall` or `install.cmd purge` instead. You can also remove Clipit from **Settings > Apps > Installed apps > Clipit**.

## Usage

| Command | What it does |
|---|---|
| `clipit "command"` | Runs the command, shows the output, copies the **complete** output once it has finished |
| `clipit Clear` | Clears the current clipboard |
| `clipit ClearW` | Clears Windows Clipboard History (pinned items are kept) |
| `clipit --last` | Copies the most recent saved long-output file |
| `clipit --openlogs` | Opens the log folder of the current shell |
| `clipit Clearp5f` | Deletes the TXT files in `Powershell5CLTFS` (asks first) |
| `clipit Clearp7f` | Deletes the TXT files in `Powershell7CLTFS` (asks first) |
| `clipit ClearC3` | Deletes the TXT files in `cmdCLTFS` (asks first) |
| `clipit ClearAllF` | Deletes the TXT files in all three folders (asks first) |
| `clipit --version` / `--help` | Version / help |

Put the **whole command inside one pair of quotes**:

```powershell
clipit "Get-Process | Sort-Object CPU -Descending | Select-Object -First 10"
clipit "winget list"
```

### The 100 KB rule

| Output size | Result |
|---|---|
| 100 KB or less | The complete output is copied to the clipboard |
| More than 100 KB | The complete output is saved as a TXT file and the **path of that file** is copied. Use `clipit --last` to put the file's contents on the clipboard |

Log files are named from the first 10 letters/digits of the command plus a timestamp (for example `ipconfigall_20261111_085200.txt`) and never overwrite each other. Nothing is ever deleted automatically - only the cleanup commands above delete files, and only after you confirm.

## Where things are installed

Everything lives in your own profile, so it works for any Windows user without admin rights:

```text
%LOCALAPPDATA%\ClipitFunction
|-- clipit.ps1            PowerShell function (PowerShell 5.1 and 7)
|-- clipit.cmd            CMD command
|-- setup.ps1             installer copy (used by repair / uninstall)
|-- clipit.ico / .png     icon
|-- Powershell5CLTFS\     logs from Windows PowerShell 5.1
|-- Powershell7CLTFS\     logs from PowerShell 7
`-- cmdCLTFS\             logs from CMD
```

The installer also:

- adds that folder to your **user** `Path`, so `clipit` works in CMD, PowerShell, Windows Terminal and VS Code;
- adds one clearly marked block to your PowerShell profile(s) (`Documents\WindowsPowerShell\profile.ps1` and, if PowerShell 7 is present, `Documents\PowerShell\profile.ps1`). A `.clipit-backup` copy of an existing profile is made first, and uninstall removes only that block;
- creates a Start Menu shortcut and an *Apps & features* entry that use the Clipit icon.

## Differences between the shells

- **PowerShell 5.1 / 7:** output is shown live while the command runs. All output streams (including errors, warnings and `Write-Host`) are captured.
- **CMD:** output is shown as soon as the command finishes (it is captured to a temporary file first). Quote commands that contain `&`, `|` or `>`, for example `clipit "dir | findstr txt"`.
- The exit code of your command is shown, and CMD returns it to the caller.

## Troubleshooting

<details>
<summary><b><code>clipit</code> is not recognized</b></summary>

Open a **new** terminal window - PATH changes only apply to windows opened after installation. If it still fails, run the Repair command above.
</details>

<details>
<summary><b>PowerShell says "running scripts is disabled on this system"</b></summary>

The default Windows PowerShell 5.1 policy (`Restricted`) blocks profile scripts. The installer changes it to `RemoteSigned` **for your user only** (the same default PowerShell 7 uses). If you prefer not to change it, install with `-NoExecutionPolicy`; `clipit` then still works in PowerShell through `clipit.cmd`, you just do not get the PowerShell-native version. If a Group Policy controls the setting, the installer leaves it alone and tells you.
</details>

<details>
<summary><b><code>clipit ClearW</code> says Windows could not clear Clipboard History</b></summary>

Turn Clipboard History on under *Settings > System > Clipboard*, then try again.
</details>

<details>
<summary><b>PowerShell 7 was installed after Clipit</b></summary>

Run the installer once more - it will notice the missing PowerShell 7 profile block and add it, without touching anything else.
</details>

## Security

The installer is a single readable script ([`install.ps1`](install.ps1)): it downloads only the files listed at the top of it from this repository, never needs administrator rights, and changes only your own user profile. Reviewing a script before running it from the internet is always a good habit.

## Contributing

Issues and pull requests are welcome - see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE) (c) 2026 SKABDULAHMED8
