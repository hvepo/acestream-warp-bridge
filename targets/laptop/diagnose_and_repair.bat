@echo off
setlocal
title Laptop Diagnostic and Repair Tool - WarpAcePi
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0diagnose_laptop.ps1"
if %ERRORLEVEL% neq 0 (
    echo.
    echo [!] Diagnostics completed with warnings/errors.
)

pause
exit /b 0
