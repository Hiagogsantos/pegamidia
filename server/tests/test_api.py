"""Testes de ponta a ponta da API (yt-dlp + ffmpeg de verdade, num site local)."""

import os
import subprocess
import time

import pytest
from fastapi.testclient import TestClient

from pegamidia_server import fallback
from pegamidia_server.jobs import GerenciadorTarefas
from pegamidia_server.main import criar_app


@pytest.fixture
def cliente(tmp_path):
    with TestClient(criar_app(GerenciadorTarefas(tmp_path / "downloads"))) as c:
        yield c


def esperar(cliente, job_id, limite=60):
    fim = time.time() + limite
    while time.time() < fim:
        st = cliente.get(f"/status/{job_id}").json()
        if st["estado"] in ("concluido", "erro"):
            return st
        time.sleep(0.2)
    raise AssertionError(f"tarefa não terminou: {st}")


def duracao(caminho):
    saida = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration,format_name",
         "-of", "default=nw=1", caminho], capture_output=True, text=True, check=True).stdout
    return saida


def test_saude(cliente):
    r = cliente.get("/saude").json()
    assert r["app"] == "PegaMídia"
    assert r["ffmpeg"] is True


def test_link_invalido(cliente):
    r = cliente.post("/info", json={"url": "isso não é link"})
    assert r.status_code == 400
    assert "Link inválido" in r.json()["detail"]


def test_qualidade_invalida(cliente):
    r = cliente.post("/download", json={"url": "https://youtu.be/x", "qualidade": "enorme"})
    assert r.status_code == 422


def test_tarefa_inexistente(cliente):
    assert cliente.get("/status/naoexiste").status_code == 404
    assert cliente.get("/arquivo/naoexiste").status_code == 404


def test_info_de_mp4_direto(cliente, site_local):
    r = cliente.post("/info", json={"url": f"{site_local}/produto.mp4"})
    assert r.status_code == 200, r.text
    assert r.json()["site"] == "outro"


def test_download_video_mp4(cliente, site_local):
    job = cliente.post("/download", json={"url": f"{site_local}/produto.mp4", "tipo": "video"}).json()["job_id"]
    st = esperar(cliente, job)
    assert st["estado"] == "concluido", st
    assert st["nome_arquivo"].endswith(".mp4")
    r = cliente.get(f"/arquivo/{job}")
    assert r.status_code == 200
    assert len(r.content) == st["tamanho"] > 1000


def test_download_audio_mp3(cliente, site_local, tmp_path):
    job = cliente.post("/download", json={"url": f"{site_local}/produto.mp4", "tipo": "audio"}).json()["job_id"]
    st = esperar(cliente, job)
    assert st["estado"] == "concluido", st
    assert st["nome_arquivo"].endswith(".mp3")
    destino = tmp_path / "a.mp3"
    destino.write_bytes(cliente.get(f"/arquivo/{job}").content)
    assert "format_name=mp3" in duracao(str(destino))


def test_pagina_com_og_video(cliente, site_local):
    r = cliente.post("/info", json={"url": f"{site_local}/og.html"})
    assert r.status_code == 200, r.text
    job = cliente.post("/download", json={"url": f"{site_local}/og.html"}).json()["job_id"]
    st = esperar(cliente, job)
    assert st["estado"] == "concluido", st
    assert st["nome_arquivo"].endswith(".mp4")


def test_pagina_sem_video(cliente, site_local, monkeypatch):
    monkeypatch.setattr(fallback, "playwright_disponivel", lambda: False)
    r = cliente.post("/info", json={"url": f"{site_local}/vazio.html"})
    assert r.status_code == 422
    assert r.json()["detail"] == "Não consegui achar vídeo nesta página."
    job = cliente.post("/download", json={"url": f"{site_local}/vazio.html"}).json()["job_id"]
    st = esperar(cliente, job)
    assert st["estado"] == "erro"
    assert st["mensagem"] == "Não consegui achar vídeo nesta página."


# Roda quando há um Chromium para o Playwright: PEGAMIDIA_CHROMIUM=/caminho/chrome ou, depois de
# "python -m playwright install chromium", PEGAMIDIA_TESTAR_NAVEGADOR=1.
navegador_ok = fallback.playwright_disponivel() and (
    os.environ.get("PEGAMIDIA_CHROMIUM") or os.environ.get("PEGAMIDIA_TESTAR_NAVEGADOR") == "1")


@pytest.mark.skipif(not navegador_ok, reason="Playwright/Chromium indisponível")
def test_pagina_so_com_javascript_usa_playwright(cliente, site_local):
    r = cliente.post("/info", json={"url": f"{site_local}/js.html"})
    assert r.status_code == 200, r.text
    corpo = r.json()
    assert corpo["fonte"] == "pagina"
    assert corpo["url_video"].endswith("/produto.mp4")
    assert corpo["titulo"] == "Produto legal"

    job = cliente.post("/download", json={"url": f"{site_local}/js.html"}).json()["job_id"]
    st = esperar(cliente, job)
    assert st["estado"] == "concluido", st
    assert st["nome_arquivo"] == "Produto legal.mp4"


@pytest.mark.skipif(not navegador_ok, reason="Playwright/Chromium indisponível")
def test_instagram_imagem_e_som_separados_sao_juntados(cliente, site_local):
    r = cliente.post("/info", json={"url": f"{site_local}/dash.html"})
    assert r.status_code == 200, r.text
    assert r.json()["fonte"] == "pagina"
    job = cliente.post("/download", json={"url": f"{site_local}/dash.html"}).json()["job_id"]
    st = esperar(cliente, job)
    assert st["estado"] == "concluido", st
    assert st["nome_arquivo"] == "Reel de teste.mp4"
    destino = cliente.app.state.tarefas.obter(job).arquivo
    tipos = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=codec_type", "-of", "csv=p=0",
                            str(destino)], capture_output=True, text=True, check=True).stdout.split()
    assert sorted(tipos) == ["audio", "video"]


def test_info_de_mp4_direto_oferece_video(cliente, site_local):
    corpo = cliente.post("/info", json={"url": f"{site_local}/produto.mp4"}).json()
    assert corpo["tem_video"] is True
    assert corpo["tem_audio"] is True
