<#
.SYNOPSIS
    Installer for Clipit - installs, repairs or removes Clipit for the current Windows user.

.DESCRIPTION
    Installs Clipit into %LOCALAPPDATA%\ClipitFunction (no administrator rights needed):
      * adds that folder to the USER Path, so "clipit" works in CMD, PowerShell 5.1,
        PowerShell 7, Windows Terminal and VS Code
      * adds a small managed block to the PowerShell profiles so the Clipit function loads
      * creates the three log folders once (they are reused, never duplicated)
      * adds a Start Menu shortcut and an Apps & features entry with the Clipit icon

    Running it again never creates duplicates:
      * healthy install       -> "already installed", nothing is changed
      * incomplete / outdated -> the missing pieces are completed
      * -Repair               -> old install is removed and a fresh one is created
      * -Uninstall            -> everything is removed (saved logs are kept unless -Purge)

.PARAMETER Repair
    Remove the existing installation, then install a fresh copy. Saved logs are kept.

.PARAMETER Uninstall
    Remove Clipit. Saved logs are kept unless -Purge is also given.

.PARAMETER Purge
    With -Uninstall or -Repair: also delete the saved log folders.

.PARAMETER NoExecutionPolicy
    Do not change the Windows PowerShell execution policy (see README, Troubleshooting).

.PARAMETER Pause
    Wait for Enter before closing (used by install.cmd and the Apps & features entry).

.PARAMETER Branch
    GitHub branch to download from when this script is not run from a local copy.

.EXAMPLE
    irm https://raw.githubusercontent.com/SKABDULAHMED8/ClipitFunction/main/install.ps1 | iex

.LINK
    https://github.com/SKABDULAHMED8/ClipitFunction

NOTE: keep this file ASCII-only (Windows PowerShell 5.1 reads BOM-less files as ANSI).
#>
[CmdletBinding()]
param(
    [switch]$Repair,
    [switch]$Uninstall,
    [switch]$Purge,
    [switch]$NoExecutionPolicy,
    [switch]$Pause,
    [string]$Branch = 'main'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # makes Invoke-WebRequest much faster in Windows PowerShell 5.1

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------
$AppName     = 'Clipit'
$Owner       = 'SKABDULAHMED8'
$RepoName    = 'ClipitFunction'
$RawBase     = "https://raw.githubusercontent.com/$Owner/$RepoName/$Branch"
$InstallDir  = Join-Path $env:LOCALAPPDATA 'ClipitFunction'
$LogFolders  = @('Powershell5CLTFS', 'Powershell7CLTFS', 'cmdCLTFS')
$UninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ClipitFunction'
$BeginMark   = '# >>> Clipit (managed block - do not edit) >>>'
$EndMark     = '# <<< Clipit (managed block) <<<'

# Name inside the install folder -> path inside the repository
$PackageFiles = @(
    @{ Name = 'clipit.ps1';  Src = 'src/clipit.ps1' },
    @{ Name = 'clipit.cmd';  Src = 'src/clipit.cmd' },
    @{ Name = 'clipit.ico';  Src = 'assets/clipit.ico' },
    @{ Name = 'clipit.png';  Src = 'assets/clipit.png' },
    @{ Name = 'setup.ps1';   Src = 'install.ps1' },
    @{ Name = 'LICENSE.txt'; Src = 'LICENSE' },
    @{ Name = 'VERSION';     Src = 'VERSION' }
)
$RequiredFiles = @($PackageFiles | ForEach-Object { $_.Name })

$script:SetupExit = 0

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
function Write-Step { param([string]$Text) Write-Host ''; Write-Host "==> $Text" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Text) Write-Host "  [OK] $Text" -ForegroundColor Green }
function Write-Warn { param([string]$Text) Write-Host "  [!]  $Text" -ForegroundColor Yellow }
function Write-Info { param([string]$Text) Write-Host "       $Text" }

# ---------------------------------------------------------------------------
# User PATH (edited in the registry so %VARIABLES% in it are never flattened)
# ---------------------------------------------------------------------------
function Get-UserPathRaw {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment')
    if (-not $key) { return '' }
    try {
        return [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    }
    finally { $key.Close() }
}

function Send-EnvironmentChange {
    try {
        if (-not ('ClipitWin.Native' -as [type])) {
            Add-Type -Namespace ClipitWin -Name Native -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true, CharSet = System.Runtime.InteropServices.CharSet.Auto)]
public static extern System.IntPtr SendMessageTimeout(System.IntPtr hWnd, uint Msg, System.UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out System.UIntPtr lpdwResult);
'@
        }
        $result = [UIntPtr]::Zero
        [void][ClipitWin.Native]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$result)
    }
    catch { }   # not critical: new terminals pick the change up anyway
}

function Set-UserPathRaw {
    param([string]$Value)
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment')
    try { $key.SetValue('Path', $Value, [Microsoft.Win32.RegistryValueKind]::ExpandString) }
    finally { $key.Close() }
    Send-EnvironmentChange
}

function ConvertTo-PathKey {
    param([string]$Entry)
    return [Environment]::ExpandEnvironmentVariables($Entry).Trim().TrimEnd('\')
}

function Test-UserPath {
    $target = ConvertTo-PathKey $InstallDir
    foreach ($entry in (Get-UserPathRaw).Split(';')) {
        if ($entry.Trim() -and (ConvertTo-PathKey $entry) -ieq $target) { return $true }
    }
    return $false
}

function Add-UserPath {
    if (Test-UserPath) { return $false }
    $raw = (Get-UserPathRaw).TrimEnd(';')
    if ($raw) { Set-UserPathRaw "$raw;$InstallDir" } else { Set-UserPathRaw $InstallDir }
    return $true
}

function Remove-UserPath {
    $target = ConvertTo-PathKey $InstallDir
    $keep = @()
    $removed = $false
    foreach ($entry in (Get-UserPathRaw).Split(';')) {
        if (-not $entry.Trim()) { continue }
        if ((ConvertTo-PathKey $entry) -ieq $target) { $removed = $true } else { $keep += $entry }
    }
    if ($removed) { Set-UserPathRaw ($keep -join ';') }
    return $removed
}

# ---------------------------------------------------------------------------
# PowerShell profiles (one managed block, replaced in place, never duplicated)
# ---------------------------------------------------------------------------
function Get-ProfileFiles {
    $docs = [Environment]::GetFolderPath('MyDocuments')
    return [ordered]@{
        'Windows PowerShell 5.1' = (Join-Path $docs 'WindowsPowerShell\profile.ps1')
        'PowerShell 7'           = (Join-Path $docs 'PowerShell\profile.ps1')
    }
}

function Test-PowerShell7Present {
    if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) { return $true }
    if (Test-Path -LiteralPath (Join-Path $env:ProgramFiles 'PowerShell')) { return $true }
    $docs = [Environment]::GetFolderPath('MyDocuments')
    return (Test-Path -LiteralPath (Join-Path $docs 'PowerShell'))
}

function Read-TextWithEncoding {
    param([string]$Path)
    $reader = New-Object System.IO.StreamReader($Path, [System.Text.Encoding]::Default, $true)
    try {
        $text = $reader.ReadToEnd()
        return @{ Text = $text; Encoding = $reader.CurrentEncoding }
    }
    finally { $reader.Dispose() }
}

function Test-ProfileBlock {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    try { return ((Get-Content -LiteralPath $Path -Raw) -like "*$BeginMark*") }
    catch { return $false }
}

function Get-ProfileBlockText {
    return (@(
        $BeginMark,
        '$__clipit = Join-Path $env:LOCALAPPDATA ''ClipitFunction\clipit.ps1''',
        'if (Test-Path -LiteralPath $__clipit) { . $__clipit }',
        'Remove-Variable __clipit -ErrorAction SilentlyContinue',
        $EndMark
    ) -join "`r`n")
}

function Get-BlockPattern {
    return ('(?s)(\r?\n)?[ \t]*' + [regex]::Escape($BeginMark) + '.*?' + [regex]::Escape($EndMark) + '[ \t]*(\r?\n)?')
}

function Set-ProfileBlock {
    param([string]$Path)

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $block = Get-ProfileBlockText

    if (-not (Test-Path -LiteralPath $Path)) {
        [System.IO.File]::WriteAllText($Path, $block + "`r`n", (New-Object System.Text.UTF8Encoding($true)))
        return
    }

    $backup = "$Path.clipit-backup"
    if (-not (Test-Path -LiteralPath $backup)) { Copy-Item -LiteralPath $Path -Destination $backup -Force }

    $file = Read-TextWithEncoding $Path
    $text = $file.Text
    if ($text -like "*$BeginMark*") {
        # refresh the existing block in place
        # '$' is special in .NET replacement strings, so it is doubled
        $replacement = ("`r`n" + $block + "`r`n").Replace('$', '$$')
        $text = [regex]::Replace($text, (Get-BlockPattern), $replacement)
    }
    else {
        if ($text.Length -gt 0 -and -not $text.EndsWith("`n")) { $text += "`r`n" }
        $text += "`r`n$block`r`n"
    }
    [System.IO.File]::WriteAllText($Path, $text, $file.Encoding)
}

function Remove-ProfileBlock {
    param([string]$Path)
    if (-not (Test-ProfileBlock $Path)) { return $false }

    $file = Read-TextWithEncoding $Path
    $text = [regex]::Replace($file.Text, (Get-BlockPattern), "`r`n")
    if ([string]::IsNullOrWhiteSpace($text)) {
        Remove-Item -LiteralPath $Path -Force
    }
    else {
        [System.IO.File]::WriteAllText($Path, $text.TrimStart("`r", "`n"), $file.Encoding)
    }
    return $true
}

# ---------------------------------------------------------------------------
# Windows PowerShell execution policy (profiles are scripts, so Restricted blocks them)
# ---------------------------------------------------------------------------
function Invoke-WindowsPowerShell {
    param([string]$Script)
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($Script))
    return @(& powershell.exe -NoProfile -NonInteractive -EncodedCommand $encoded 2>$null)
}

function Get-WindowsPolicyList {
    $list = @{}
    $listScript = @'
Get-ExecutionPolicy -List | ForEach-Object { '{0}={1}' -f $_.Scope, $_.ExecutionPolicy }
'@
    try {
        foreach ($line in (Invoke-WindowsPowerShell $listScript)) {
            if ("$line" -match '^(\w+)=(\w+)$') { $list[$Matches[1]] = $Matches[2] }
        }
    }
    catch { }
    return $list
}

function Initialize-ExecutionPolicy {
    if ($NoExecutionPolicy) {
        Write-Info 'Execution policy left unchanged (-NoExecutionPolicy).'
        return
    }

    $list = Get-WindowsPolicyList
    if ($list.Count -eq 0) {
        Write-Warn 'Could not read the Windows PowerShell execution policy; skipped.'
        return
    }

    $effective = $null
    $decidedBy = $null
    foreach ($scope in 'MachinePolicy', 'UserPolicy', 'Process', 'CurrentUser', 'LocalMachine') {
        if ($list.ContainsKey($scope) -and $list[$scope] -ne 'Undefined') {
            $effective = $list[$scope]
            $decidedBy = $scope
            break
        }
    }
    if (-not $effective) { $effective = 'Restricted'; $decidedBy = 'default' }

    if ($effective -notin 'Restricted', 'AllSigned') {
        Write-Ok "PowerShell execution policy is $effective - profiles can load."
        return
    }

    if ($decidedBy -in 'MachinePolicy', 'UserPolicy') {
        Write-Warn "A Group Policy sets the execution policy to $effective, so the PowerShell profile cannot load."
        Write-Info 'The "clipit" command still works in PowerShell through clipit.cmd.'
        return
    }

    if ($effective -eq 'AllSigned') {
        Write-Warn 'Execution policy is AllSigned, which blocks unsigned profile scripts. Left unchanged.'
        Write-Info 'The "clipit" command still works in PowerShell through clipit.cmd.'
        return
    }

    [void](Invoke-WindowsPowerShell 'Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force')
    $after = Get-WindowsPolicyList
    if ($after.ContainsKey('CurrentUser') -and $after['CurrentUser'] -eq 'RemoteSigned') {
        Write-Ok 'Windows PowerShell execution policy set to RemoteSigned for your user (it was Restricted).'
    }
    else {
        Write-Warn 'Could not change the execution policy. Run in PowerShell: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned'
    }
}

# ---------------------------------------------------------------------------
# Start Menu shortcut and Apps & features entry
# ---------------------------------------------------------------------------
function Get-ShortcutPath {
    return (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Clipit.lnk')
}

function New-ClipitShortcut {
    $path = Get-ShortcutPath
    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($path)
    $link.TargetPath = Join-Path $env:SystemRoot 'System32\cmd.exe'
    $link.Arguments = '/k ""' + (Join-Path $InstallDir 'clipit.cmd') + '" --help"'
    $link.WorkingDirectory = $env:USERPROFILE
    $link.IconLocation = (Join-Path $InstallDir 'clipit.ico') + ',0'
    $link.Description = 'Clipit - run a command and copy its complete output to the clipboard'
    $link.Save()
}

function Set-UninstallEntry {
    param([string]$Version)
    if (-not (Test-Path -LiteralPath $UninstallKey)) { New-Item -Path $UninstallKey -Force | Out-Null }
    $setup = Join-Path $InstallDir 'setup.ps1'
    $values = [ordered]@{
        DisplayName     = 'Clipit'
        DisplayVersion  = $Version
        Publisher       = $Owner
        InstallLocation = $InstallDir
        DisplayIcon     = (Join-Path $InstallDir 'clipit.ico')
        URLInfoAbout    = "https://github.com/$Owner/$RepoName"
        UninstallString = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$setup`" -Uninstall -Pause"
    }
    foreach ($name in $values.Keys) {
        Set-ItemProperty -Path $UninstallKey -Name $name -Value $values[$name]
    }
    Set-ItemProperty -Path $UninstallKey -Name 'NoModify' -Value 1 -Type DWord
    Set-ItemProperty -Path $UninstallKey -Name 'NoRepair' -Value 1 -Type DWord
}

# ---------------------------------------------------------------------------
# State detection
# ---------------------------------------------------------------------------
function Get-InstalledVersion {
    $file = Join-Path $InstallDir 'VERSION'
    if (Test-Path -LiteralPath $file) { return (Get-Content -LiteralPath $file -TotalCount 1).Trim() }
    return $null
}

function Get-ClipitState {
    $profiles = Get-ProfileFiles
    $missing = @($RequiredFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $InstallDir $_)) })
    $needs7 = Test-PowerShell7Present

    $state = [ordered]@{
        Missing    = $missing
        FilesOk    = ($missing.Count -eq 0)
        Version    = (Get-InstalledVersion)
        PathOk     = (Test-UserPath)
        Profile5Ok = (Test-ProfileBlock $profiles['Windows PowerShell 5.1'])
        Profile7Ok = ((-not $needs7) -or (Test-ProfileBlock $profiles['PowerShell 7']))
        FoldersOk  = (@($LogFolders | Where-Object { -not (Test-Path -LiteralPath (Join-Path $InstallDir $_)) }).Count -eq 0)
        RegistryOk = (Test-Path -LiteralPath $UninstallKey)
        ShortcutOk = (Test-Path -LiteralPath (Get-ShortcutPath))
    }
    $state.Healthy = ($state.FilesOk -and $state.PathOk -and $state.Profile5Ok -and $state.Profile7Ok -and
                      $state.FoldersOk -and $state.RegistryOk -and $state.ShortcutOk)
    $state.AnyPresent = ((Test-Path -LiteralPath $InstallDir) -or $state.PathOk -or $state.RegistryOk -or $state.ShortcutOk -or
                         (Test-ProfileBlock $profiles['Windows PowerShell 5.1']) -or
                         (Test-ProfileBlock $profiles['PowerShell 7']))
    return $state
}

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------
function Get-LocalSourceRoot {
    if ($PSScriptRoot -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'src\clipit.ps1'))) {
        return $PSScriptRoot
    }
    return $null
}

function Copy-PackageToStage {
    param([string]$Stage)

    $local = Get-LocalSourceRoot
    if ($local) { Write-Info "Using files from $local" }
    else {
        Write-Info "Downloading files from github.com/$Owner/$RepoName ($Branch)"
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
    }

    foreach ($file in $PackageFiles) {
        $dest = Join-Path $Stage $file.Name
        if ($local) {
            Copy-Item -LiteralPath (Join-Path $local ($file.Src -replace '/', '\')) -Destination $dest -Force
        }
        else {
            Invoke-WebRequest -UseBasicParsing -Uri "$RawBase/$($file.Src)" -OutFile $dest
        }
        if (-not (Test-Path -LiteralPath $dest) -or (Get-Item -LiteralPath $dest).Length -eq 0) {
            throw "Could not get $($file.Src)."
        }
    }
}

function Test-ClipitWorks {
    $ok = $true

    try {
        $cmdFile = Join-Path $InstallDir 'clipit.cmd'
        $out = (& $cmdFile --version 2>$null | Out-String)
        if ($out -match 'Clipit\s+\S+') { Write-Ok "CMD test passed:  $($out.Trim())" }
        else { Write-Warn 'CMD test failed.'; $ok = $false }
    }
    catch { Write-Warn "CMD test failed: $($_.Exception.Message)"; $ok = $false }

    try {
        $ps1 = Join-Path $InstallDir 'clipit.ps1'
        $probe = ". '" + $ps1.Replace("'", "''") + "'; Clipit --version"
        $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($probe))
        $out = (& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $encoded 2>$null | Out-String)
        if ($out -match 'Clipit\s+\S+') { Write-Ok "PowerShell test passed:  $($out.Trim())" }
        else { Write-Warn 'PowerShell test failed.'; $ok = $false }
    }
    catch { Write-Warn "PowerShell test failed: $($_.Exception.Message)"; $ok = $false }

    return $ok
}

function Install-Clipit {
    $stage = Join-Path ([System.IO.Path]::GetTempPath()) ('ClipitSetup_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage -Force | Out-Null

    try {
        Write-Step 'Getting the files'
        Copy-PackageToStage -Stage $stage
        $version = (Get-Content -LiteralPath (Join-Path $stage 'VERSION') -TotalCount 1).Trim()

        Write-Step "Installing Clipit $version"
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
        foreach ($file in $PackageFiles) {
            $target = Join-Path $InstallDir $file.Name
            Copy-Item -LiteralPath (Join-Path $stage $file.Name) -Destination $target -Force
            Unblock-File -LiteralPath $target -ErrorAction SilentlyContinue
        }
        Write-Ok "Files copied to $InstallDir"

        foreach ($folder in $LogFolders) {
            $path = Join-Path $InstallDir $folder
            if (-not (Test-Path -LiteralPath $path)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
        }
        Write-Ok 'Log folders ready (existing folders are reused)'

        if (Add-UserPath) { Write-Ok 'Added the install folder to your user PATH' }
        else { Write-Ok 'User PATH already contains the install folder' }
        if (@(($env:Path -split ';') | Where-Object { $_ -and (ConvertTo-PathKey $_) -ieq (ConvertTo-PathKey $InstallDir) }).Count -eq 0) {
            $env:Path = "$InstallDir;$env:Path"
        }

        $profiles = Get-ProfileFiles
        Set-ProfileBlock $profiles['Windows PowerShell 5.1']
        Write-Ok 'Windows PowerShell 5.1 profile updated'
        if (Test-PowerShell7Present) {
            Set-ProfileBlock $profiles['PowerShell 7']
            Write-Ok 'PowerShell 7 profile updated'
        }
        else {
            Write-Info 'PowerShell 7 not found. If you install it later, run this installer again.'
        }

        Initialize-ExecutionPolicy

        New-ClipitShortcut
        Set-UninstallEntry -Version $version
        Write-Ok 'Start Menu shortcut and Apps & features entry created'

        Write-Step 'Checking the installation'
        if (-not (Test-ClipitWorks)) { $script:SetupExit = 1 }
    }
    finally {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# Remove
# ---------------------------------------------------------------------------
function Remove-Clipit {
    param([bool]$KeepLogs = $true)

    Push-Location -LiteralPath ([System.IO.Path]::GetTempPath())
    try {
        $shortcut = Get-ShortcutPath
        if (Test-Path -LiteralPath $shortcut) { Remove-Item -LiteralPath $shortcut -Force; Write-Ok 'Start Menu shortcut removed' }

        if (Test-Path -LiteralPath $UninstallKey) { Remove-Item -LiteralPath $UninstallKey -Recurse -Force; Write-Ok 'Apps & features entry removed' }

        foreach ($path in (Get-ProfileFiles).Values) {
            if (Remove-ProfileBlock $path) { Write-Ok "Profile cleaned: $path" }
        }

        if (Remove-UserPath) { Write-Ok 'Removed the install folder from your user PATH' }
        $key = ConvertTo-PathKey $InstallDir
        $env:Path = (($env:Path -split ';') | Where-Object { $_ -and (ConvertTo-PathKey $_) -ine $key }) -join ';'

        foreach ($name in $RequiredFiles) {
            $file = Join-Path $InstallDir $name
            if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
        }
        Write-Ok 'Program files removed'

        if (-not $KeepLogs) {
            foreach ($folder in $LogFolders) {
                $path = Join-Path $InstallDir $folder
                if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue }
            }
            Write-Ok 'Saved logs deleted (-Purge)'
        }

        if ((Test-Path -LiteralPath $InstallDir) -and -not (Get-ChildItem -LiteralPath $InstallDir -Force)) {
            Remove-Item -LiteralPath $InstallDir -Force -ErrorAction SilentlyContinue
        }
        elseif (Test-Path -LiteralPath $InstallDir) {
            Write-Info "Your saved logs were kept in $InstallDir"
        }
    }
    finally { Pop-Location }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
function Show-Finished {
    Write-Host ''
    Write-Host '  Open a NEW CMD / PowerShell window, then try:' -ForegroundColor White
    Write-Host '      clipit --help' -ForegroundColor Cyan
    Write-Host '      clipit "ipconfig /all"' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  Repair : run this installer again with -Repair (or "install.cmd repair")'
    Write-Host '  Remove : Settings > Apps > Clipit, or run it with -Uninstall'
    Write-Host ''
}

function Invoke-ClipitSetup {
    if ($env:OS -ne 'Windows_NT') { throw 'Clipit is for Windows 10 / 11.' }
    if ($Repair -and $Uninstall) { throw 'Use either -Repair or -Uninstall, not both.' }

    $mutex = New-Object System.Threading.Mutex($false, 'Local\ClipitFunctionSetup')
    $locked = $false
    try {
        try { $locked = $mutex.WaitOne(0) }
        catch [System.Threading.AbandonedMutexException] { $locked = $true }

        if (-not $locked) {
            Write-Warn 'Another Clipit setup is already running. Nothing was changed.'
            return
        }

        Write-Host ''
        Write-Host '  Clipit setup' -ForegroundColor Cyan
        Write-Host "  https://github.com/$Owner/$RepoName" -ForegroundColor DarkGray

        $state = Get-ClipitState

        if ($Uninstall) {
            if (-not $state.AnyPresent) {
                Write-Host ''
                Write-Ok 'Clipit is not installed. Nothing to remove.'
                return
            }
            Write-Step 'Removing Clipit'
            Remove-Clipit -KeepLogs (-not $Purge)
            Write-Host ''
            Write-Ok 'Clipit was removed. Close and reopen your terminals.'
            return
        }

        if ($Repair) {
            Write-Step 'Repair: removing the old installation'
            Remove-Clipit -KeepLogs (-not $Purge)
            Install-Clipit
            Write-Host ''
            if ($script:SetupExit -eq 0) { Write-Ok 'Repair complete: a fresh copy of Clipit is installed.' }
            else { Write-Warn 'Repair finished, but a self-check failed. See the messages above.' }
            Show-Finished
            return
        }

        $sourceVersion = $null
        $local = Get-LocalSourceRoot
        if ($local -and (Test-Path -LiteralPath (Join-Path $local 'VERSION'))) {
            $sourceVersion = (Get-Content -LiteralPath (Join-Path $local 'VERSION') -TotalCount 1).Trim()
        }

        if ($state.Healthy -and ((-not $sourceVersion) -or $sourceVersion -eq $state.Version)) {
            Write-Host ''
            Write-Ok "Clipit $($state.Version) is already installed. Nothing was changed."
            Write-Info "Location: $InstallDir"
            Write-Info 'To update to the newest version or reinstall from scratch, run the installer with -Repair.'
            Write-Host ''
            return
        }

        if ($state.AnyPresent) {
            if ($state.Healthy) { Write-Step "Updating Clipit $($state.Version) to $sourceVersion" }
            else { Write-Step 'Clipit is only partly installed - completing the installation' }
        }
        Install-Clipit
        Write-Host ''
        if ($script:SetupExit -eq 0) { Write-Ok 'Clipit installed successfully.' }
        else { Write-Warn 'Clipit was installed, but a self-check failed. See the messages above.' }
        Show-Finished
    }
    finally {
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

try { Invoke-ClipitSetup }
catch {
    Write-Host ''
    Write-Host "  [X] $($_.Exception.Message)" -ForegroundColor Red
    $script:SetupExit = 1
}

if ($Pause) {
    Write-Host ''
    [void](Read-Host 'Press Enter to close')
}

# Only set a process exit code when run as a file (not when piped into iex,
# where "exit" would close the user's own terminal).
if ($PSCommandPath) { exit $script:SetupExit }
