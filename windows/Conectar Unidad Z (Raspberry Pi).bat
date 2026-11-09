@echo off
setlocal
title Conectar Unidad Z a Raspberry Pi
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0conectar_rpi_z.ps1"
echo.
pause
