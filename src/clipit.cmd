@echo off
rem ============================================================================
rem  Clipit for CMD - run a command, show its output, copy the complete output.
rem  Project: https://github.com/SKABDULAHMED8/ClipitFunction   License: MIT
rem
rem  Usage:   clipit "command"      (put the whole command inside quotes)
rem           clipit --help
rem
rem  Management commands (clear, clearw, --last, ...) are handled by clipit.ps1
rem  so that CMD, PowerShell 5.1 and PowerShell 7 all behave the same way.
rem ============================================================================
setlocal EnableExtensions DisableDelayedExpansion

set "CLIPIT_DIR=%~dp0"
set "CLIPIT_PS=%~dp0clipit.ps1"
set "MAX_BYTES=102400"

if "%~1"=="" (
    set "ACTION=help"
    goto :admin
)

set "ACTION="
if "%~2"=="" (
    if /i "%~1"=="--help"      set "ACTION=help"
    if /i "%~1"=="-h"          set "ACTION=help"
    if /i "%~1"=="help"        set "ACTION=help"
    if /i "%~1"=="/?"          set "ACTION=help"
    if /i "%~1"=="--version"   set "ACTION=version"
    if /i "%~1"=="clear"       set "ACTION=clear"
    if /i "%~1"=="clearw"      set "ACTION=clearw"
    if /i "%~1"=="--last"      set "ACTION=last"
    if /i "%~1"=="--openlogs"  set "ACTION=openlogs"
    if /i "%~1"=="clearp5f"    set "ACTION=clearp5f"
    if /i "%~1"=="clearp7f"    set "ACTION=clearp7f"
    if /i "%~1"=="clearc3"     set "ACTION=clearc3"
    if /i "%~1"=="clearallf"   set "ACTION=clearallf"
)
if defined ACTION goto :admin

if not exist "%CLIPIT_PS%" (
    echo [CLIPIT] clipit.ps1 was not found next to clipit.cmd.
    echo Run the installer again with the "repair" option.
    exit /b 1
)

rem ---------------------------------------------------------------------------
rem  Run the command and capture stdout + stderr in a temporary file
rem ---------------------------------------------------------------------------
set "OUT=%TEMP%\clipit_%RANDOM%%RANDOM%.txt"

cmd /d /c %* >"%OUT%" 2>&1
set "RC=%ERRORLEVEL%"

type "%OUT%"

set "SIZE=0"
for %%A in ("%OUT%") do set "SIZE=%%~zA"

echo.
echo ---------------------------------------------
echo [CLIPIT]
echo Shell    : CMD.exe
echo Exit Code: %RC%
echo Output   : %SIZE% bytes
echo ---------------------------------------------

if "%SIZE%"=="0" (
    echo Clipboard: the command produced no output, clipboard left unchanged.
    goto :done
)

if %SIZE% LEQ %MAX_BYTES% (
    clip.exe < "%OUT%"
    echo Clipboard: complete output copied.
    goto :done
)

rem  Larger than 100 KB: save a TXT file and copy its path (handled in clipit.ps1)
rem  (unquoted on purpose: a quoted SET would let "a & b" run the second part)
set CLIPIT_CMD=%*
set "CLIPIT_RC=%RC%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%CLIPIT_PS%" -CmdAction large -CmdOutFile "%OUT%"

:done
echo.
del "%OUT%" >nul 2>&1
endlocal & exit /b %RC%

:admin
if not exist "%CLIPIT_PS%" (
    echo [CLIPIT] clipit.ps1 was not found next to clipit.cmd.
    echo Run the installer again with the "repair" option.
    exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%CLIPIT_PS%" -CmdAction admin -CmdArg %ACTION%
endlocal & exit /b %ERRORLEVEL%
