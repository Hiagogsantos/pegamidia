import functools
import http.server
import os
import shutil
import subprocess
import threading
from pathlib import Path

import pytest

# Os testes de ponta a ponta usam um servidor HTTP em 127.0.0.1.
os.environ["PEGAMIDIA_PERMITIR_LOCAL"] = "1"


@pytest.fixture(scope="session")
def site_local(tmp_path_factory):
    """Sobe um "site" local com um MP4 de 2 s e páginas HTML que apontam para ele."""
    if shutil.which("ffmpeg") is None:
        pytest.skip("ffmpeg não instalado")
    raiz: Path = tmp_path_factory.mktemp("site")
    subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc=size=320x240:rate=15:duration=2",
         "-f", "lavfi", "-i", "sine=frequency=440:duration=2",
         "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest",
         str(raiz / "produto.mp4")],
        check=True,
    )
    (raiz / "og.html").write_text(
        '<html><head><title>Página</title><meta property="og:title" content="Presente do bingo">'
        '<meta property="og:video" content="/produto.mp4"><meta property="og:image" content="/capa.jpg">'
        "</head><body>oi</body></html>",
        encoding="utf-8",
    )
    # Vídeo inserido só por JavaScript (como na Shopee): HTML puro não mostra nada.
    (raiz / "js.html").write_text(
        "<html><head><title>Produto legal</title></head><body><div id=p></div><script>"
        "setTimeout(() => { const v = document.createElement('video');"
        " v.src = '/' + ['produto', 'mp4'].join('.'); v.muted = true;"
        " document.getElementById('p').appendChild(v); v.play().catch(() => {}); }, 300);"
        "</script></body></html>",
        encoding="utf-8",
    )
    (raiz / "vazio.html").write_text("<html><head><title>Nada</title></head><body>sem vídeo</body></html>",
                                     encoding="utf-8")

    class Silencioso(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *args):
            pass

    servidor = http.server.ThreadingHTTPServer(("127.0.0.1", 0),
                                               functools.partial(Silencioso, directory=str(raiz)))
    threading.Thread(target=servidor.serve_forever, daemon=True).start()
    yield f"http://127.0.0.1:{servidor.server_address[1]}"
    servidor.shutdown()
