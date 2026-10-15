#!/usr/bin/env sh
# Atualiza o yt-dlp (rode se algum link parar de funcionar).
cd "$(dirname "$0")"
.venv/bin/python -m pip install -U yt-dlp
