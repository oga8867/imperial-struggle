@echo off
REM Imperial Struggle - direct play with console window for log output

set "GODOT_DIR=X:\SteamLibrary\steamapps\common\Godot Engine"
set "GODOT_EXE=%GODOT_DIR%\godot.windows.opt.tools.64.exe"
set "PROJECT_DIR=%~dp0godot_project"

if not exist "%GODOT_EXE%" (
    echo [ERROR] Godot not found at: %GODOT_EXE%
    pause
    exit /b 1
)

if not exist "%PROJECT_DIR%\project.godot" (
    echo [ERROR] Project not found at: %PROJECT_DIR%
    pause
    exit /b 1
)

echo Starting Imperial Struggle (with console)...
echo Logs will also be saved to: %APPDATA%\Godot\app_userdata\Imperial Struggle\imperial_struggle.log
echo.
REM --verbose makes Godot keep its console window open and pipe output here
"%GODOT_EXE%" --path "%PROJECT_DIR%" --verbose
echo.
echo Game closed. Press any key to exit.
pause
exit /b 0
