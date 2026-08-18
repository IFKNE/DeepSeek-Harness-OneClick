@echo off
rem Start the DeepSeek Harness web UI (http://127.0.0.1:3080)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\start-web.ps1"
pause
