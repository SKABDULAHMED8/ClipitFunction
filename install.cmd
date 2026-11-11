@echo off
rem ============================================================================
rem  Clipit installer launcher (double-click friendly)
rem
rem    install.cmd              install (or report "already installed")
rem    install.cmd repair       remove the old install and create a fresh one
rem    install.cmd uninstall    remove Clipit (saved logs are kept)
rem    install.cmd purge        remove Clipit AND delete saved logs
rem ============================================================================
setlocal EnableExtensions

set "SETUP_ARGS="
if /i "%~1"=="repair"    set "SETUP_ARGS=-Repair"
if /i "%~1"=="uninstall" set "SETUP_ARGS=-Uninstall"
if /i "%~1"=="purge"     set "SETUP_ARGS=-Uninstall -Purge"

if not exist "%~dp0install.ps1" (
    echo install.ps1 was not found next to install.cmd.
    echo Download the whole repository, or use the one-line installer from the README.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %SETUP_ARGS% -Pause
exit /b %ERRORLEVEL%
