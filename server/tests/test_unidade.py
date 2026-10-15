import os
import time
from pathlib import Path

import pytest

from pegamidia_server import downloader, fallback
from pegamidia_server.jobs import GerenciadorTarefas
from pegamidia_server.sites import UrlInvalida, detectar_site, extrair_url, validar_url


@pytest.mark.parametrize(
    ("url", "site"),
    [
        ("https://www.youtube.com/watch?v=abc", "youtube"),
        ("https://youtu.be/abc", "youtube"),
        ("https://music.youtube.com/watch?v=abc", "youtube_music"),
        ("https://m.facebook.com/reel/123", "facebook"),
        ("https://fb.watch/xyz/", "facebook"),
        ("https://x.com/user/status/1", "twitter"),
        ("https://twitter.com/user/status/1", "twitter"),
        ("https://vm.tiktok.com/ZMabc/", "tiktok"),
        ("https://www.instagram.com/reel/abc/", "instagram"),
        ("https://www.kwai.com/@user/video/123", "kwai"),
        ("https://br.shp.ee/AbCd123", "shopee"),
        ("https://shopee.com.br/produto-i.1.2", "shopee"),
        ("https://exemplo.com.br/video", "outro"),
        ("https://notyoutube.com/watch", "outro"),
    ],
)
def test_detectar_site(url, site):
    assert detectar_site(url) == site


def test_extrair_url_de_texto_compartilhado():
    texto = "Olha esse produto na Shopee! https://br.shp.ee/AbCd123?x=1. Corre!"
    assert extrair_url(texto) == "https://br.shp.ee/AbCd123?x=1"
    assert extrair_url("sem link aqui") is None


def test_validar_url_recusa_rede_local(monkeypatch):
    monkeypatch.delenv("PEGAMIDIA_PERMITIR_LOCAL", raising=False)
    for ruim in ["", "ftp://a.com/x", "não é link", "http://localhost:8000/x",
                 "http://192.168.0.1/admin", "http://127.0.0.1/", "http://[::1]/", "http://impressora.local/"]:
        with pytest.raises(UrlInvalida):
            validar_url(ruim)
    assert validar_url(" https://youtu.be/abc ") == "https://youtu.be/abc"
    assert validar_url("http://8.8.8.8/v.mp4") == "http://8.8.8.8/v.mp4"


def test_opcoes_video_720p_mp4():
    o = downloader.montar_opcoes("video", "720p", Path("/tmp/x"))
    assert o["format_sort"][0] == "res:720"
    assert o["merge_output_format"] == "mp4"
    assert o["noplaylist"] is True
    assert "cookiefile" in o and o["cookiefile"] is None


def test_opcoes_video_melhor_sem_limite():
    o = downloader.montar_opcoes("video", "melhor", Path("/tmp/x"))
    assert o["format_sort"][0] == "res"


def test_opcoes_audio_mp3_192():
    o = downloader.montar_opcoes("audio", "720p", Path("/tmp/x"))
    pp = o["postprocessors"][0]
    assert pp["key"] == "FFmpegExtractAudio"
    assert pp["preferredcodec"] == "mp3"
    assert pp["preferredquality"] == "192"
    assert "format_sort" not in o


def test_opcoes_nome_e_cabecalhos():
    o = downloader.montar_opcoes("video", "720p", Path("/tmp/x"), nome_arquivo='Presente: "bingo"/2',
                                 cabecalhos={"Referer": "https://shopee.com.br/p"})
    assert o["outtmpl"] == "/tmp/x/Presente bingo 2.%(ext)s"
    assert o["http_headers"]["Referer"] == "https://shopee.com.br/p"


@pytest.mark.parametrize(
    ("erro", "trecho"),
    [
        ("ERROR: Unsupported URL: https://shopee.com.br/x", "Não consegui achar vídeo"),
        ("ERROR: [youtube] abc: Private video. Sign in if you've been granted access", "privado"),
        ("ERROR: [youtube] abc: Sign in to confirm you're not a bot", "bloqueou"),
        ("ERROR: [youtube] abc: Video unavailable", "indisponível"),
        ("ERROR: Unable to download webpage: <urlopen error [Errno -2] Name or service not known>",
         "Não consegui abrir o link"),
        ("ERROR: algo estranho", "Não foi possível baixar: algo estranho"),
    ],
)
def test_traduzir_erro(erro, trecho):
    assert trecho in downloader.traduzir_erro(erro)


def test_precisa_fallback():
    assert downloader.precisa_fallback("ERROR: Unsupported URL: x", "youtube")
    assert downloader.precisa_fallback("ERROR: qualquer", "shopee")
    assert not downloader.precisa_fallback("ERROR: Private video", "youtube")


def test_classificar_urls_de_video():
    c = fallback.classificar
    assert c("https://down-bs-sg.vod.susercontent.com/api/v4/1/mms/abc.16000081.mp4") == "mp4"
    assert c("https://cdn.x/video.m3u8?token=1") == "m3u8"
    assert c("https://cdn.x/seg-1.ts") is None
    assert c("https://cdn.x/api/stream", "video/mp4; charset=binary") == "mp4"
    assert c("https://cdn.x/api/playlist", "application/vnd.apple.mpegurl") == "m3u8"
    assert c("blob:https://shopee.com.br/123") is None
    assert c("https://cdn.x/imagem.jpg") is None


def test_escolher_melhor_prefere_mp4_maior():
    V = fallback.VideoEncontrado
    escolhido = fallback.escolher_melhor([
        V("https://a/x.m3u8", "m3u8", "p"),
        V("https://a/pequeno.mp4", "mp4", "p", tamanho=1000),
        V("https://a/grande.mp4", "mp4", "p", tamanho=9000),
    ])
    assert escolhido.url == "https://a/grande.mp4"
    assert fallback.escolher_melhor([]) is None


def test_ler_html_og_video():
    html = ('<html><head><meta property="og:title" content="Caneca &amp; Copo">'
            '<meta property="og:video" content="//cdn.exemplo.com/v.mp4">'
            '<meta property="og:image" content="/capa.jpg"></head></html>')
    video, titulo, mini = fallback.ler_html(html, "https://loja.exemplo.com/p/1")
    assert video.url == "https://cdn.exemplo.com/v.mp4"
    assert video.pagina == "https://loja.exemplo.com/p/1"
    assert titulo == "Caneca & Copo"
    assert mini == "https://loja.exemplo.com/capa.jpg"


def test_ler_html_sem_video():
    video, titulo, _ = fallback.ler_html("<title>Só texto</title>", "https://x.com/")
    assert video is None and titulo == "Só texto"


def test_resumir_info_qualidades():
    info = {
        "title": "Aula", "thumbnail": "t.jpg", "duration": 60, "extractor_key": "Youtube",
        "formats": [
            {"height": 360, "vcodec": "avc1", "acodec": "none", "ext": "mp4", "filesize": 100},
            {"height": 720, "vcodec": "avc1", "acodec": "none", "ext": "mp4", "filesize": 500},
            {"height": 720, "vcodec": "vp9", "acodec": "none", "ext": "webm", "filesize": 400},
            {"vcodec": "none", "acodec": "mp4a", "ext": "m4a"},
        ],
    }
    r = downloader.resumir_info(info, "https://youtu.be/abc")
    assert r["qualidades"] == ["360p", "720p"]
    assert r["formatos"][1]["tamanho_aprox"] == 500
    assert r["site"] == "youtube" and r["tem_audio"] and r["tem_video"]


def test_progresso_soma_video_e_audio():
    registros = []
    a = downloader.AcompanharProgresso(lambda **c: registros.append(c))
    info = {"title": "X", "requested_formats": [{}, {}]}
    a.progresso({"status": "downloading", "downloaded_bytes": 50, "total_bytes": 100, "info_dict": info})
    assert registros[0] == {"titulo": "X"}
    assert registros[-1]["progresso"] == 25.0
    a.progresso({"status": "finished", "info_dict": info})
    a.progresso({"status": "downloading", "downloaded_bytes": 50, "total_bytes": 100, "info_dict": info})
    assert registros[-1]["progresso"] == 75.0


def test_arquivo_final_ignora_temporarios(tmp_path):
    (tmp_path / "video.mp4.part").write_bytes(b"x" * 100)
    (tmp_path / "video.mp4").write_bytes(b"x" * 10)
    assert downloader.arquivo_final(tmp_path).name == "video.mp4"


def test_limpeza_apaga_mais_de_24h(tmp_path):
    g = GerenciadorTarefas(tmp_path, baixador=lambda *a, **k: None)
    velho = tmp_path / "velho"
    velho.mkdir()
    (velho / "a.mp4").write_bytes(b"1")
    novo = tmp_path / "novo"
    novo.mkdir()
    duas_dias = time.time() - 2 * 24 * 3600
    os.utime(velho, (duas_dias, duas_dias))
    assert g.limpar_antigos() == 1
    assert not velho.exists() and novo.exists()
    g.encerrar()
