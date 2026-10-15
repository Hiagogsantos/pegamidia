@echo off
REM Inicia o servidor do PegaMidia. Deixe esta janela aberta enquanto usar o app.
cd /d "%~dp0"
.venv\Scripts\python -m pegamidia_server
pause
