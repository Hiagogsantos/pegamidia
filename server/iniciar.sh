#!/usr/bin/env sh
# Inicia o servidor do PegaMídia (porta 8000).
cd "$(dirname "$0")"
exec .venv/bin/python -m pegamidia_server "$@"
