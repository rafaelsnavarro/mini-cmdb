@echo off
if not exist "%~dp0Coletar-Inventario.ps1" (
  echo.
  echo  ERRO: Coletar-Inventario.ps1 nao foi encontrado nesta pasta.
  echo.
  echo  Provavelmente voce abriu o Coletar.bat DE DENTRO do arquivo .zip.
  echo  Clique com o botao direito no MiniCMDB.zip, escolha "Extrair Tudo..."
  echo  e execute o Coletar.bat a partir da pasta extraida.
  echo.
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Coletar-Inventario.ps1" %*
echo.
if exist "%~dp0painel.html" start "" "%~dp0painel.html"
pause
