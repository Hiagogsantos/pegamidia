@echo off
REM Atualiza o yt-dlp (os sites mudam com frequencia; rode se algum link parar de funcionar).
cd /d "%~dp0"
.venv\Scripts\python -m pip install -U yt-dlp
pause
