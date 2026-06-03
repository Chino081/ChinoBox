@echo off
chcp 65001 >nul 2>&1
title ChinoBox Build

:: Use Git Bash to run build.sh
set "GIT_BASH=C:\Program Files\Git\bin\bash.exe"
if not exist "%GIT_BASH%" (
    echo [error] Git Bash not found at "%GIT_BASH%"
    pause
    exit /b 1
)

echo Starting build...
"%GIT_BASH%" --login -i "%~dp0build.sh" %*

echo.
if %ERRORLEVEL% equ 0 (
    echo Build succeeded!
) else (
    echo Build failed with error code %ERRORLEVEL%
)
pause
