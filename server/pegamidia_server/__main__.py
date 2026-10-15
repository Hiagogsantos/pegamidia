"""Inicia o servidor: ``python -m pegamidia_server`` (porta 8000 por padrão)."""

from __future__ import annotations

import argparse
import logging
import socket

import uvicorn

from . import APP_NAME


def ip_na_rede() -> str | None:
    """IP deste PC na rede Wi-Fi (é o endereço que vai no app)."""
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        try:
            s.connect(("10.255.255.255", 1))  # não envia nada; só escolhe a interface
            return s.getsockname()[0]
        except OSError:
            return None


def main() -> None:
    parser = argparse.ArgumentParser(description=f"Servidor do {APP_NAME}")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--porta", type=int, default=8000)
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    ip = ip_na_rede()
    print(f"\n  {APP_NAME} — servidor iniciado")
    if ip:
        print(f"  No app, em Configurações, use: http://{ip}:{args.porta}\n")
    uvicorn.run("pegamidia_server.main:app", host=args.host, port=args.porta)


if __name__ == "__main__":
    main()
