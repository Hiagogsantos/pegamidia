"""Versão para computador (Windows) do PegaMídia.

Abre uma janela com a tela do PegaMídia e, ao mesmo tempo, funciona como servidor
para os celulares da mesma rede Wi-Fi. Os arquivos baixados vão para
``Downloads\\PegaMidia``. O executável (PegaMidia.exe) já traz o ffmpeg e o Deno.

Uso:  PegaMidia.exe                abre a janela
      PegaMidia.exe --teste [URL]  autoteste (usado no GitHub Actions)
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import socket
import sys
import threading
import time
import urllib.request
from pathlib import Path

APP_NAME = "PegaMídia"
PORTA_PADRAO = 8000


def pasta_base() -> Path:
    """Onde ficam os arquivos que vêm junto com o programa."""
    if getattr(sys, "frozen", False):
        return Path(getattr(sys, "_MEIPASS", Path(sys.executable).parent))
    return Path(__file__).resolve().parent.parent


def pasta_dados() -> Path:
    """Pasta do programa no perfil do usuário (temporários e registro de erros)."""
    raiz = os.environ.get("LOCALAPPDATA") or str(Path.home() / ".local" / "share")
    pasta = Path(raiz) / "PegaMidia"
    pasta.mkdir(parents=True, exist_ok=True)
    return pasta


def pasta_downloads() -> Path:
    """Downloads\\PegaMidia do usuário (onde os vídeos prontos ficam)."""
    if sys.platform == "win32":
        try:  # pasta "Downloads" de verdade, mesmo se o usuário a moveu de lugar
            import ctypes
            from uuid import UUID

            guid = UUID("374DE290-123F-4565-9164-39C4925E467B")  # FOLDERID_Downloads
            caminho = ctypes.c_wchar_p()
            buffer = (ctypes.c_byte * 16).from_buffer_copy(guid.bytes_le)
            if ctypes.windll.shell32.SHGetKnownFolderPath(ctypes.byref(buffer), 0, None, ctypes.byref(caminho)) == 0:
                pasta = Path(caminho.value)
                ctypes.windll.ole32.CoTaskMemFree(caminho)
                return pasta / "PegaMidia"
        except Exception:
            pass
    return Path.home() / "Downloads" / "PegaMidia"


def preparar_ambiente() -> None:
    """Coloca o ffmpeg e o Deno que vêm com o programa no PATH e configura as pastas."""
    ferramentas = pasta_base() / "ferramentas"
    if ferramentas.is_dir():
        os.environ["PATH"] = str(ferramentas) + os.pathsep + os.environ.get("PATH", "")
    os.environ.setdefault("PEGAMIDIA_PASTA", str(pasta_dados() / "temporarios"))
    os.environ.setdefault("PEGAMIDIA_PASTA_USUARIO", str(pasta_downloads()))
    if sys.platform == "win32":
        # procura vídeos em páginas (Shopee, Kwai, Instagram) com o Edge que já vem no Windows
        os.environ.setdefault("PEGAMIDIA_NAVEGADOR_CANAL", "msedge")


def configurar_registro() -> Path:
    """Programa sem console (janela): stdout/stderr vão para um arquivo de registro."""
    arquivo = pasta_dados() / "pegamidia.log"
    if sys.stdout is None or sys.stderr is None:
        saida = open(arquivo, "a", encoding="utf-8", buffering=1)  # noqa: SIM115
        sys.stdout = sys.stdout or saida
        sys.stderr = sys.stderr or saida
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
        handlers=[logging.FileHandler(arquivo, encoding="utf-8"), logging.StreamHandler(sys.stderr)],
    )
    return arquivo


def ip_na_rede() -> str | None:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        try:
            s.connect(("10.255.255.255", 1))
            return s.getsockname()[0]
        except OSError:
            return None


def porta_livre(preferida: int) -> int:
    for porta in (preferida, 0):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            try:
                s.bind(("0.0.0.0", porta))
                return s.getsockname()[1]
            except OSError:
                continue
    raise RuntimeError("Nenhuma porta livre")


def ja_aberto(porta: int) -> bool:
    """Outro PegaMídia já está rodando nesta porta?"""
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{porta}/saude", timeout=2) as r:
            return json.load(r).get("app") == APP_NAME
    except Exception:
        return False


def iniciar_servidor(porta: int, host: str = "0.0.0.0"):
    """Sobe o servidor numa thread e espera ele responder."""
    import uvicorn

    from .main import app

    config = uvicorn.Config(app, host=host, port=porta, log_config=None, access_log=False)
    servidor = uvicorn.Server(config)
    threading.Thread(target=servidor.run, name="servidor", daemon=True).start()
    limite = time.monotonic() + 30
    while time.monotonic() < limite:
        if servidor.started:
            return servidor
        time.sleep(0.1)
    raise RuntimeError("O servidor não iniciou")


def abrir_janela(url: str) -> None:
    """Janela própria (WebView2/Edge). Se não der, abre no navegador padrão."""
    try:
        import webview

        webview.create_window(APP_NAME, url, width=1080, height=820, min_size=(720, 560))
        webview.start()
        return
    except Exception:
        logging.getLogger("pegamidia").exception("Janela própria indisponível; usando o navegador")
    import webbrowser

    webbrowser.open(url)
    try:  # mantém o programa aberto com uma janelinha para encerrar
        import tkinter as tk

        raiz = tk.Tk()
        raiz.title(APP_NAME)
        tk.Label(raiz, text=f"{APP_NAME} está aberto no navegador:\n{url}", padx=24, pady=16).pack()
        tk.Button(raiz, text="Encerrar o PegaMídia", command=raiz.destroy, padx=12, pady=6).pack(pady=(0, 16))
        raiz.mainloop()
    except Exception:
        while True:
            time.sleep(3600)


def autoteste(urls: list[str]) -> int:
    """Confere se o executável funciona: servidor, ffmpeg, Deno e, para cada URL, um
    download em MP3 que precisa terminar em Downloads\\PegaMidia."""
    porta = porta_livre(0)
    iniciar_servidor(porta, host="127.0.0.1")
    base = f"http://127.0.0.1:{porta}"

    def pedir(caminho: str, corpo: dict | None = None) -> dict:
        dados = json.dumps(corpo).encode() if corpo is not None else None
        req = urllib.request.Request(base + caminho, data=dados, headers={
            "Content-Type": "application/json", "X-PegaMidia": "1"})
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.load(r)

    saude = pedir("/saude")
    print("saude:", saude, flush=True)
    with urllib.request.urlopen(base + "/", timeout=10) as r:
        assert b"PegaM" in r.read(), "tela não carregou"
    problemas = [nome for nome in ("ffmpeg", "deno", "playwright") if not saude.get(nome)]
    if not saude.get("computador"):
        problemas.append("computador")
    for n, url in enumerate(urls, 1):
        nome = f"autoteste-{n}"
        job = pedir("/download", {"url": url, "tipo": "audio", "titulo": nome})["job_id"]
        for _ in range(240):
            st = pedir(f"/status/{job}")
            if st["estado"] in ("concluido", "erro"):
                break
            time.sleep(0.5)
        print(f"download {url}:", st, flush=True)
        arquivos = [a["nome"] for a in pedir("/local/arquivos")["arquivos"]]
        if st["estado"] != "concluido" or f"{nome}.mp3" not in arquivos:
            problemas.append(f"download de {url}")
    print("arquivos na pasta do usuário:", pedir("/local/arquivos")["arquivos"], flush=True)
    print("PROBLEMAS:" if problemas else "AUTOTESTE OK", ", ".join(problemas), flush=True)
    return 1 if problemas else 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="PegaMidia", description=f"{APP_NAME} para computador")
    parser.add_argument("--teste", nargs="*", metavar="URL", help="autoteste sem janela (baixa cada URL em MP3)")
    parser.add_argument("--porta", type=int, default=PORTA_PADRAO)
    args = parser.parse_args(argv)

    preparar_ambiente()
    registro = configurar_registro()
    log = logging.getLogger("pegamidia")

    if args.teste is not None:
        return autoteste(args.teste)

    if ja_aberto(args.porta):
        abrir_janela(f"http://127.0.0.1:{args.porta}/")
        return 0
    porta = porta_livre(args.porta)
    ip = ip_na_rede()
    if ip:
        os.environ["PEGAMIDIA_ENDERECO_REDE"] = f"http://{ip}:{porta}"
    try:
        iniciar_servidor(porta)
    except Exception:
        log.exception("Falha ao iniciar o servidor (registro em %s)", registro)
        raise
    log.info("PegaMídia aberto na porta %s; arquivos em %s", porta, os.environ["PEGAMIDIA_PASTA_USUARIO"])
    abrir_janela(f"http://127.0.0.1:{porta}/")
    os._exit(0)  # fechou a janela: encerra o servidor também


if __name__ == "__main__":
    sys.exit(main())
