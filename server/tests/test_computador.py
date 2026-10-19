"""Versão Windows: pasta do usuário, ações locais (abrir/renomear/apagar) e a tela."""

import socket
import threading
import time

import pytest
from fastapi.testclient import TestClient

from pegamidia_server import fallback
from pegamidia_server.jobs import GerenciadorTarefas
from pegamidia_server.main import criar_app

LOCAL = {"X-PegaMidia": "1"}


@pytest.fixture
def computador(tmp_path):
    usuario = tmp_path / "Downloads" / "PegaMidia"
    abertos = []
    app = criar_app(GerenciadorTarefas(tmp_path / "temporarios", pasta_usuario=usuario))
    app.state.abrir_no_sistema = lambda caminho, selecionar=False: abertos.append((caminho.name, selecionar))
    with TestClient(app) as c:
        yield c, usuario, abertos


def esperar(c, job):
    for _ in range(300):
        st = c.get(f"/status/{job}").json()
        if st["estado"] in ("concluido", "erro"):
            return st
        time.sleep(0.2)
    raise AssertionError(st)


def test_pagina_inicial_e_saude(computador):
    c, _, _ = computador
    assert "PegaMídia" in c.get("/").text
    assert c.get("/saude").json()["computador"] is True


def test_download_vai_para_a_pasta_do_usuario_e_pode_ser_renomeado(computador, site_local):
    c, usuario, abertos = computador
    job = c.post("/download", json={"url": f"{site_local}/produto.mp4", "titulo": "Caneca: bingo"}).json()["job_id"]
    st = esperar(c, job)
    assert st["estado"] == "concluido", st
    assert (usuario / "Caneca bingo.mp4").is_file()
    # o temporário da tarefa foi apagado
    assert not (c.app.state.tarefas.pasta / job).exists()
    # o celular ainda consegue buscar o arquivo
    assert c.get(f"/arquivo/{job}").status_code == 200

    lista = c.get("/local/arquivos", headers=LOCAL).json()
    assert [a["nome"] for a in lista["arquivos"]] == ["Caneca bingo.mp4"]

    assert c.post("/local/renomear", json={"nome": "Caneca bingo.mp4", "novo": "Presente/mães?"},
                  headers=LOCAL).json() == {"nome": "Presente mães.mp4"}
    assert (usuario / "Presente mães.mp4").is_file()

    c.post("/local/abrir", json={"nome": "Presente mães.mp4"}, headers=LOCAL)
    c.post("/local/mostrar", json={"nome": "Presente mães.mp4"}, headers=LOCAL)
    c.post("/local/abrir-pasta", json={}, headers=LOCAL)
    assert abertos == [("Presente mães.mp4", False), ("Presente mães.mp4", True), ("PegaMidia", False)]

    assert c.post("/local/apagar", json={"nome": "Presente mães.mp4"}, headers=LOCAL).status_code == 200
    assert list(usuario.iterdir()) == []


def test_renomear_nao_sobrescreve(computador):
    c, usuario, _ = computador
    usuario.mkdir(parents=True)
    (usuario / "a.mp4").write_bytes(b"a")
    (usuario / "b.mp4").write_bytes(b"b")
    r = c.post("/local/renomear", json={"nome": "a.mp4", "novo": "b"}, headers=LOCAL).json()
    assert r == {"nome": "b (2).mp4"}
    assert (usuario / "b.mp4").read_bytes() == b"b"
    # mesmo nome: nada muda
    assert c.post("/local/renomear", json={"nome": "b.mp4", "novo": "b"}, headers=LOCAL).json() == {"nome": "b.mp4"}


def test_acoes_locais_protegidas(computador, tmp_path):
    c, usuario, _ = computador
    usuario.mkdir(parents=True)
    segredo = tmp_path / "segredo.txt"
    segredo.write_text("x")
    # sem o cabeçalho (ex.: outra página aberta no navegador): recusado
    assert c.get("/local/arquivos").status_code == 403
    # fora da pasta do usuário: recusado
    for nome in ["../segredo.txt", "..\\segredo.txt", "/etc/passwd", ""]:
        r = c.post("/local/apagar", json={"nome": nome}, headers=LOCAL)
        assert r.status_code in (400, 404), nome
    assert segredo.exists()


def test_servidor_sem_pasta_do_usuario_nao_tem_acoes_locais(tmp_path):
    with TestClient(criar_app(GerenciadorTarefas(tmp_path))) as c:
        assert c.get("/saude").json()["computador"] is False
        assert c.get("/local/arquivos", headers=LOCAL).status_code == 404


@pytest.mark.skipif(not (fallback.playwright_disponivel() and __import__("os").environ.get("PEGAMIDIA_CHROMIUM")
                         or __import__("os").environ.get("PEGAMIDIA_TESTAR_NAVEGADOR") == "1"),
                    reason="Playwright/Chromium indisponível")
def test_tela_no_navegador(tmp_path, site_local):
    """Usa a tela como uma pessoa: cola o link, escolhe o nome, baixa, renomeia e apaga."""
    import os

    import uvicorn
    from playwright.sync_api import expect, sync_playwright

    usuario = tmp_path / "PegaMidia"
    app = criar_app(GerenciadorTarefas(tmp_path / "tmp", pasta_usuario=usuario))
    app.state.abrir_no_sistema = lambda *a, **k: None
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        porta = s.getsockname()[1]
    servidor = uvicorn.Server(uvicorn.Config(app, host="127.0.0.1", port=porta, log_config=None))
    threading.Thread(target=servidor.run, daemon=True).start()
    while not servidor.started:
        time.sleep(0.05)
    try:
        with sync_playwright() as p:
            navegador = p.chromium.launch(executable_path=os.environ.get("PEGAMIDIA_CHROMIUM") or None)
            pagina = navegador.new_page()
            pagina.goto(f"http://127.0.0.1:{porta}/")
            expect(pagina.get_by_role("button", name="📁 Abrir pasta")).to_be_visible()

            pagina.get_by_placeholder("https://…", exact=False).fill(f"{site_local}/produto.mp4")
            pagina.get_by_role("button", name="Buscar").click()
            nome = pagina.get_by_label("Nome do arquivo")
            expect(nome).to_be_visible(timeout=30_000)
            nome.fill("Tesoura de cozinha")
            pagina.get_by_role("button", name="⬇ Baixar").click()
            item = pagina.locator(".item", has_text="Tesoura de cozinha.mp4")
            expect(item).to_be_visible(timeout=60_000)
            assert (usuario / "Tesoura de cozinha.mp4").is_file()

            item.get_by_role("button", name="Renomear").click()
            pagina.get_by_label("Novo nome").fill("Presente bingo")
            pagina.locator("#dlg-renomear").get_by_role("button", name="Renomear").click()
            expect(pagina.locator(".item", has_text="Presente bingo.mp4")).to_be_visible()
            assert (usuario / "Presente bingo.mp4").is_file()

            pagina.locator(".item", has_text="Presente bingo.mp4").get_by_role("button", name="Apagar").click()
            pagina.locator("#dlg-confirmar").get_by_role("button", name="Apagar").click()
            expect(pagina.get_by_text("Nenhum download ainda.")).to_be_visible()
            assert not any(usuario.iterdir())

            # link inválido mostra mensagem clara
            pagina.get_by_placeholder("https://…", exact=False).fill("isso não é link")
            pagina.get_by_role("button", name="Buscar").click()
            expect(pagina.get_by_text("Link inválido", exact=False)).to_be_visible()
            navegador.close()
    finally:
        servidor.should_exit = True
