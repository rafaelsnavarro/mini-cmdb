@echo off
title Mini CMDB - Coletar uma maquina
if not exist "%~dp0Coletar-Inventario.ps1" (
  echo.
  echo  ERRO: Coletar-Inventario.ps1 nao foi encontrado nesta pasta.
  echo  Extraia o MiniCMDB.zip ^(botao direito ^> Extrair Tudo^) e rode a partir da pasta extraida.
  echo.
  pause
  exit /b 1
)

set "MAQUINA=%~1"
if "%MAQUINA%"=="" (
  echo.
  echo  ===============================================
  echo   Mini CMDB - Coletar uma maquina
  echo  ===============================================
  echo.
  echo  Digite o nome da maquina ^(ex.: PC-001^)
  echo  ou deixe em branco e tecle ENTER para coletar ESTA maquina ^(%COMPUTERNAME%^).
  echo  Para varias, separe por virgula: PC-001,PC-002
  echo.
  set /p "MAQUINA=Maquina: "
)

echo.
if "%MAQUINA%"=="" (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Coletar-Inventario.ps1" -Local
) else if /i "%MAQUINA%"=="%COMPUTERNAME%" (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Coletar-Inventario.ps1" -Local
) else (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0Coletar-Inventario.ps1' -ComputerName ('%MAQUINA%' -split '[,; ]+' | Where-Object { $_ })"
)

echo.
if exist "%~dp0painel.html" start "" "%~dp0painel.html"
pause
