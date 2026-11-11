<#
.SYNOPSIS
    Clipit - run a command, show its output, and copy the COMPLETE output to the clipboard.

.DESCRIPTION
    Dot-sourced from the PowerShell profile (PowerShell 5.1 and 7) so that the
    Clipit function is available in every session. clipit.cmd calls this same
    file for its management commands, so the behaviour is identical everywhere.

    Project: https://github.com/SKABDULAHMED8/ClipitFunction
    License: MIT

    NOTE: keep this file ASCII-only. Windows PowerShell 5.1 reads BOM-less
    files as ANSI and would garble other characters.
#>
param(
    # Internal parameters, only used when clipit.cmd launches this file.
    [string]$CmdAction = '',
    [string]$CmdArg = '',
    [string]$CmdOutFile = ''
)

# Folder that holds this script (and the log folders). Captured at load time
# because $PSScriptRoot is empty inside functions that run later.
$script:ClipitRoot = $PSScriptRoot
if (-not $script:ClipitRoot) {
    $script:ClipitRoot = Join-Path $env:LOCALAPPDATA 'ClipitFunction'
}
$script:ClipitMaxBytes = 100KB

function Get-ClipitVersion {
    $file = Join-Path $script:ClipitRoot 'VERSION'
    if (Test-Path -LiteralPath $file) {
        return (Get-Content -LiteralPath $file -TotalCount 1).Trim()
    }
    return 'unknown'
}

function Get-ClipitShellInfo {
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        return @{ Name = 'PowerShell 7'; Folder = 'Powershell7CLTFS' }
    }
    return @{ Name = 'Windows PowerShell 5.1'; Folder = 'Powershell5CLTFS' }
}

function Clear-ClipitClipboard {
    try {
        Set-Clipboard -Value $null
    }
    catch {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.Clipboard]::Clear()
    }
}

function Show-ClipitHelp {
    param([string]$ShellName, [string]$LogFolder, [string]$Prefix)

    Write-Host ''
    Write-Host '================ CLIPIT HELP ================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host 'RUN A COMMAND' -ForegroundColor Yellow
    Write-Host "  $Prefix `"command`""
    Write-Host '      Runs the command, shows its output, and copies the'
    Write-Host '      COMPLETE output to the clipboard once it has finished.'
    Write-Host '      Put the whole command inside one pair of quotes.'
    Write-Host ''
    Write-Host 'CLIPBOARD' -ForegroundColor Yellow
    Write-Host "  $Prefix Clear"
    Write-Host '      Clears the current clipboard.'
    Write-Host "  $Prefix ClearW"
    Write-Host '      Clears Windows Clipboard History (pinned items are kept).'
    Write-Host ''
    Write-Host 'SAVED OUTPUT' -ForegroundColor Yellow
    Write-Host "  $Prefix --last"
    Write-Host '      Copies the most recent saved long-output file.'
    Write-Host "  $Prefix --openlogs"
    Write-Host "      Opens this shell's log folder."
    Write-Host ''
    Write-Host 'CLEANUP (asks before deleting; folders are never removed)' -ForegroundColor Yellow
    Write-Host "  $Prefix Clearp5f    TXT files in Powershell5CLTFS"
    Write-Host "  $Prefix Clearp7f    TXT files in Powershell7CLTFS"
    Write-Host "  $Prefix ClearC3     TXT files in cmdCLTFS"
    Write-Host "  $Prefix ClearAllF   TXT files in all three folders"
    Write-Host ''
    Write-Host 'OTHER' -ForegroundColor Yellow
    Write-Host "  $Prefix --version"
    Write-Host "  $Prefix --help"
    Write-Host ''
    Write-Host 'OUTPUT RULE' -ForegroundColor Yellow
    Write-Host '  100 KB or less : complete output is copied to the clipboard.'
    Write-Host '  over 100 KB    : complete output is saved to a TXT file and the'
    Write-Host '                   path of that file is copied to the clipboard.'
    Write-Host ''
    Write-Host 'THIS SHELL' -ForegroundColor Yellow
    Write-Host "  $ShellName"
    Write-Host "  Log folder: $LogFolder"
    Write-Host ''
    Write-Host '=============================================' -ForegroundColor Cyan
    Write-Host ''
}

function Clear-ClipitHistory {
    # Uses the Windows clipboard API. It must run in Windows PowerShell 5.1,
    # so it is launched in a child powershell.exe in every shell.
    $inner = @'
$null = [Windows.ApplicationModel.DataTransfer.Clipboard, Windows.ApplicationModel.DataTransfer, ContentType=WindowsRuntime]
[Windows.ApplicationModel.DataTransfer.Clipboard]::ClearHistory()
'@
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($inner))

    try {
        Clear-ClipitClipboard
        $result = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $encoded 2>$null
        $text = ($result | Out-String).Trim()

        if ($text -eq 'True') {
            Write-Host 'Successfully cleared Clipboard History.' -ForegroundColor Green
            Write-Host 'Current clipboard cleared.' -ForegroundColor Green
            Write-Host 'Pinned Clipboard History items were preserved.' -ForegroundColor Cyan
        }
        else {
            Write-Host 'Windows could not clear Clipboard History.' -ForegroundColor Red
            Write-Host 'Check that Clipboard History is turned on: Settings > System > Clipboard.' -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host 'Unable to clear Clipboard History.' -ForegroundColor Red
        Write-Host $_ -ForegroundColor Red
    }
}

function Clear-ClipitFolders {
    param([string[]]$FolderNames)

    $found = @()
    foreach ($name in $FolderNames) {
        $path = Join-Path $script:ClipitRoot $name
        if (-not (Test-Path -LiteralPath $path)) {
            Write-Host "$name : folder is not present, nothing to delete." -ForegroundColor Yellow
            continue
        }
        $files = @(Get-ChildItem -LiteralPath $path -Filter '*.txt' -File)
        if ($files.Count -eq 0) {
            Write-Host "$name : already empty." -ForegroundColor Green
            continue
        }
        Write-Host "$name : $($files.Count) TXT file(s)." -ForegroundColor Yellow
        $found += $files
    }

    if ($found.Count -eq 0) { return }

    $answer = Read-Host "Delete $($found.Count) TXT file(s)? [Y/N]"
    if ($answer -notmatch '^[Yy]') {
        Write-Host 'Cleanup cancelled.' -ForegroundColor Yellow
        return
    }

    foreach ($file in $found) {
        Remove-Item -LiteralPath $file.FullName -Force
    }
    Write-Host "$($found.Count) TXT file(s) deleted. The folders were kept." -ForegroundColor Green
}

# Handles every non-run command. Returns $true when the command was handled.
function Invoke-ClipitAdmin {
    param(
        [string]$Name,
        [string]$ShellName,
        [string]$FolderName,
        [string]$Prefix
    )

    $logFolder = Join-Path $script:ClipitRoot $FolderName
    $key = $Name.Trim().ToLowerInvariant()

    switch ($key) {
        { $_ -in '', '--help', '-h', 'help', '/?', '-?' } {
            Show-ClipitHelp -ShellName $ShellName -LogFolder $logFolder -Prefix $Prefix
            return $true
        }
        '--version' {
            Write-Host "Clipit $(Get-ClipitVersion)"
            return $true
        }
        'clear' {
            try {
                Clear-ClipitClipboard
                Write-Host 'Successfully cleared the current clipboard.' -ForegroundColor Green
            }
            catch {
                Write-Host 'Unable to clear the clipboard.' -ForegroundColor Red
                Write-Host $_ -ForegroundColor Red
            }
            return $true
        }
        'clearw' {
            Clear-ClipitHistory
            return $true
        }
        '--openlogs' {
            if (-not (Test-Path -LiteralPath $logFolder)) {
                New-Item -ItemType Directory -Path $logFolder -Force | Out-Null
            }
            Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$logFolder`""
            return $true
        }
        '--last' {
            if (-not (Test-Path -LiteralPath $logFolder)) {
                Write-Host "Log folder is not present: $logFolder" -ForegroundColor Yellow
                return $true
            }
            $last = Get-ChildItem -LiteralPath $logFolder -Filter '*.txt' -File |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
            if (-not $last) {
                Write-Host 'No saved TXT output files were found.' -ForegroundColor Yellow
                return $true
            }
            try {
                Set-Clipboard -Value (Get-Content -LiteralPath $last.FullName -Raw)
                Write-Host ''
                Write-Host 'Latest saved output copied to the clipboard.' -ForegroundColor Green
                Write-Host "File: $($last.FullName)" -ForegroundColor Cyan
                Write-Host ''
            }
            catch {
                Write-Host 'Unable to copy the saved output.' -ForegroundColor Red
                Write-Host $_ -ForegroundColor Red
            }
            return $true
        }
        'clearp5f'  { Clear-ClipitFolders -FolderNames @('Powershell5CLTFS'); return $true }
        'clearp7f'  { Clear-ClipitFolders -FolderNames @('Powershell7CLTFS'); return $true }
        'clearc3'   { Clear-ClipitFolders -FolderNames @('cmdCLTFS'); return $true }
        'clearallf' { Clear-ClipitFolders -FolderNames @('Powershell5CLTFS', 'Powershell7CLTFS', 'cmdCLTFS'); return $true }
    }

    return $false
}

# Saves a complete output to a uniquely named TXT file and returns its path.
function Save-ClipitOutput {
    param(
        [string]$Command,
        [string]$Text,
        [string]$ShellName,
        [string]$FolderName,
        [string]$ExitCode,
        [int]$Bytes,
        [string]$Started,
        [string]$Finished
    )

    # Only the required folder is created, and an existing folder is reused.
    $folder = Join-Path $script:ClipitRoot $FolderName
    if (-not (Test-Path -LiteralPath $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }

    $safe = ($Command -replace '[^A-Za-z0-9]', '')
    if ([string]::IsNullOrWhiteSpace($safe)) { $safe = 'output' }
    if ($safe.Length -gt 10) { $safe = $safe.Substring(0, 10) }

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $path = Join-Path $folder "${safe}_${stamp}.txt"
    $counter = 1
    while (Test-Path -LiteralPath $path) {
        $path = Join-Path $folder ("{0}_{1}_{2:D2}.txt" -f $safe, $stamp, $counter)
        $counter++
    }

    $header = @"
CLIPIT OUTPUT
=============
Shell: $ShellName
Command: $Command
Started: $Started
Finished: $Finished
Exit Code: $ExitCode
Output Size: $Bytes bytes
=============

"@

    [System.IO.File]::WriteAllText($path, $header + $Text, (New-Object System.Text.UTF8Encoding($false)))
    return $path
}

function Clipit {
    # No [CmdletBinding()] on purpose: that lets "--help", "--last" and
    # unquoted words reach us as plain text instead of being parsed as
    # PowerShell parameters.
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$CommandParts
    )

    $Command = (@($CommandParts) -join ' ').Trim()
    $shell = Get-ClipitShellInfo

    if (Invoke-ClipitAdmin -Name $Command -ShellName $shell.Name -FolderName $shell.Folder -Prefix 'Clipit') {
        return
    }

    $started = Get-Date

    try {
        $block = [scriptblock]::Create($Command)
        $global:LASTEXITCODE = $null

        # Run the command with every stream merged into one pipeline. Show it
        # live (Out-Host) while Tee-Object keeps a complete copy in memory.
        & { & $block } *>&1 |
            ForEach-Object {
                if ($_ -is [System.Management.Automation.ErrorRecord] -and
                    ($_.Exception -is [System.Management.Automation.RemoteException] -or
                     $_.FullyQualifiedErrorId -eq 'NativeCommandError')) {
                    # stderr line from a native program: keep just the text
                    $_.ToString()
                }
                elseif ($_ -is [System.Management.Automation.WarningRecord]) { 'WARNING: ' + $_.Message }
                elseif ($_ -is [System.Management.Automation.VerboseRecord]) { 'VERBOSE: ' + $_.Message }
                elseif ($_ -is [System.Management.Automation.DebugRecord]) { 'DEBUG: ' + $_.Message }
                elseif ($_ -is [System.Management.Automation.InformationRecord]) { $_.MessageData.ToString() }
                else { $_ }
            } |
            Tee-Object -Variable ClipitCaptured |
            Out-Host

        $finished = Get-Date
        $duration = $finished - $started
        $exitCode = if ($null -ne $global:LASTEXITCODE) { [string]$global:LASTEXITCODE } else { 'n/a' }

        $text = ($ClipitCaptured | Out-String)
        if ($null -eq $text) { $text = '' }
        $bytes = [System.Text.Encoding]::UTF8.GetByteCount($text)

        Write-Host ''
        Write-Host '---------------------------------------------' -ForegroundColor DarkGray
        Write-Host '[CLIPIT]' -ForegroundColor Cyan
        Write-Host "Shell    : $($shell.Name)"
        Write-Host "Exit Code: $exitCode"
        Write-Host "Duration : $($duration.ToString('hh\:mm\:ss\.fff'))"
        Write-Host "Output   : $bytes bytes"
        Write-Host '---------------------------------------------' -ForegroundColor DarkGray

        if ([string]::IsNullOrWhiteSpace($text)) {
            Write-Host 'Clipboard: the command produced no output, clipboard left unchanged.' -ForegroundColor Yellow
        }
        elseif ($bytes -le $script:ClipitMaxBytes) {
            Set-Clipboard -Value $text
            Write-Host 'Clipboard: complete output copied.' -ForegroundColor Green
        }
        else {
            $file = Save-ClipitOutput -Command $Command -Text $text -ShellName $shell.Name `
                -FolderName $shell.Folder -ExitCode $exitCode -Bytes $bytes `
                -Started $started.ToString('yyyy-MM-dd HH:mm:ss') `
                -Finished $finished.ToString('yyyy-MM-dd HH:mm:ss')
            Set-Clipboard -Value $file
            Write-Host 'Clipboard: output is larger than 100 KB.' -ForegroundColor Yellow
            Write-Host 'Complete output saved to:' -ForegroundColor Green
            Write-Host $file -ForegroundColor Cyan
            Write-Host 'The path of the TXT file was copied to the clipboard.' -ForegroundColor Green
        }
        Write-Host ''
    }
    catch {
        Write-Host ''
        Write-Host '[CLIPIT ERROR]' -ForegroundColor Red
        Write-Host $_ -ForegroundColor Red
        Write-Host ''
    }
}

# ---------------------------------------------------------------------------
# Entry point used by clipit.cmd (never runs when dot-sourced by a profile).
# ---------------------------------------------------------------------------
if ($CmdAction) {
    $cmdShell = 'CMD.exe'
    $cmdFolder = 'cmdCLTFS'
    $code = 0

    switch ($CmdAction) {
        'admin' {
            $name = $CmdArg
            if ($name -in 'last', 'openlogs', 'version') { $name = "--$name" }
            [void](Invoke-ClipitAdmin -Name $name -ShellName $cmdShell -FolderName $cmdFolder -Prefix 'clipit')
        }
        'large' {
            try {
                $encoding = [Console]::OutputEncoding
                $text = [System.IO.File]::ReadAllText($CmdOutFile, $encoding)
                $bytes = [System.Text.Encoding]::UTF8.GetByteCount($text)
                $now = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                $rc = if ($env:CLIPIT_RC) { $env:CLIPIT_RC } else { 'n/a' }
                $file = Save-ClipitOutput -Command $env:CLIPIT_CMD -Text $text -ShellName $cmdShell `
                    -FolderName $cmdFolder -ExitCode $rc -Bytes $bytes -Started $now -Finished $now
                Set-Clipboard -Value $file
                Write-Host 'Clipboard: output is larger than 100 KB.' -ForegroundColor Yellow
                Write-Host 'Complete output saved to:' -ForegroundColor Green
                Write-Host $file -ForegroundColor Cyan
                Write-Host 'The path of the TXT file was copied to the clipboard.' -ForegroundColor Green
            }
            catch {
                Write-Host 'Unable to save the output.' -ForegroundColor Red
                Write-Host $_ -ForegroundColor Red
                $code = 1
            }
        }
    }
    exit $code
}
