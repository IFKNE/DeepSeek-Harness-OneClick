@echo off
rem DeepSeek Harness one-click installer (Windows 10/11)
rem Runs scripts\install.ps1 with bypass of execution policy.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install.ps1"
pause
