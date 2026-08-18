@echo off
rem Set your DeepSeek API key into DSH_HOME\.credentials.yaml
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\set-api-key.ps1"
pause
