@echo off
rem Gera o painel.html com o que ja foi coletado (use depois das coletas por GPO)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Gerar-Painel.ps1"
if exist "%~dp0painel.html" start "" "%~dp0painel.html"
pause
