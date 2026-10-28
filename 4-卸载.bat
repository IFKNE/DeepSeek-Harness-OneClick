@echo off
rem Uninstall DeepSeek Harness (keeps data unless explicitly selected)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\uninstall.ps1"
pause
