@echo off
setlocal
title Diagnostico y Reparacion - Portatil
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0diagnosticar_laptop.ps1"
echo.
pause
