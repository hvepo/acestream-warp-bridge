@echo off
setlocal
title Diagnostic and Repair Tool - WarpAcePi
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0diagnose_laptop.ps1"
echo.
pause
