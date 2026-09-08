@echo off
REM Imperial Struggle - launcher
REM Set GODOT_EXE in your environment when Godot is installed elsewhere.

if not defined GODOT_EXE set "GODOT_EXE=X:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
set "PROJECT_DIR=%~dp0godot_project"

if not exist "%GODOT_EXE%" (
    echo.
    echo [ERROR] Godot executable not found at:
    echo   %GODOT_EXE%
    echo.
    echo Please edit RUN.BAT and update the GODOT_EXE path.
    pause
    exit /b 1
)

if not exist "%PROJECT_DIR%\project.godot" (
    echo.
    echo [ERROR] Godot project not found at:
    echo   %PROJECT_DIR%
    echo.
    pause
    exit /b 1
)

echo Launching Imperial Struggle...
start "" "%GODOT_EXE%" --path "%PROJECT_DIR%"
exit /b 0
