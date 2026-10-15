#!/usr/bin/env sh
# Instala o servidor do PegaMídia no Linux/macOS (rodar uma vez). Requer Python 3.11+ e ffmpeg
# (Ubuntu/Debian: sudo apt install python3-venv ffmpeg   |   macOS: brew install ffmpeg).
set -e
cd "$(dirname "$0")"
python3 -m venv .venv
.venv/bin/python -m pip install --upgrade pip
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python -m playwright install chromium
echo "Pronto! Agora rode ./iniciar.sh"
