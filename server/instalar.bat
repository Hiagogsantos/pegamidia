@echo off
REM Instala o servidor do PegaMidia no Windows (rodar uma vez).
REM Antes: instale o Python 3.11+ (python.org, marque "Add to PATH") e o ffmpeg:
REM     winget install Gyan.FFmpeg
cd /d "%~dp0"
python -m venv .venv || goto erro
.venv\Scripts\python -m pip install --upgrade pip
.venv\Scripts\python -m pip install -r requirements.txt || goto erro
.venv\Scripts\python -m playwright install chromium
echo.
echo Pronto! Agora rode iniciar.bat
pause
exit /b 0
:erro
echo Falhou. Confira se o Python esta instalado e no PATH.
pause
exit /b 1
