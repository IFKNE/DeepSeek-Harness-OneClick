@echo off
rem Uninstall DeepSeek Harness (optional: keep your data)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\uninstall.ps1"
pause
