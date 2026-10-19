"""Fallback para páginas sem extrator no yt-dlp (Shopee, Kwai e afins).

Estratégia:
1. Seguir os redirecionamentos do link curto e ler a meta tag ``og:video`` do HTML.
2. Se não houver, abrir a página no Chromium headless (Playwright), escutar as
   requisições de rede e procurar vídeos ``.mp4`` / ``.m3u8`` — é o mesmo "truque do F12"
   (aba Network) feito à mão no navegador.
"""

from __future__ import annotations

import base64
import json
import logging
import os
import re
import threading
import time
from dataclasses import dataclass
from html.parser import HTMLParser
from urllib.parse import parse_qs, urljoin, urlsplit

import httpx

log = logging.getLogger(__name__)

USER_AGENT = (
    "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/129.0.0.0 Mobile Safari/537.36"
)

MENSAGEM_SEM_VIDEO = "Não consegui achar vídeo nesta página."

_EXTENSOES = re.compile(r"\.(mp4|m3u8|webm|mov|mpd)(?:$|[?#&])", re.IGNORECASE)
_SEGMENTOS = re.compile(r"\.(ts|m4s|aac|m4a)(?:$|[?#&])", re.IGNORECASE)
_TIPOS_CONTEUDO = {
    "video/mp4": "mp4",
    "video/webm": "webm",
    "video/quicktime": "mov",
    "application/vnd.apple.mpegurl": "m3u8",
    "application/x-mpegurl": "m3u8",
    "audio/mpegurl": "m3u8",
    "application/dash+xml": "mpd",
}
# Ordem de preferência: MP4 direto é o mais fácil de baixar e de abrir no celular.
_PREFERENCIA = {"mp4": 0, "mov": 1, "m3u8": 2, "webm": 3, "mpd": 4}

# JavaScript executado na página: lê os <video> e a meta og:video, e tenta dar play
# (alguns sites só carregam o vídeo depois do play).
_JS_VIDEOS = """
() => {
  const urls = [];
  for (const v of document.querySelectorAll('video')) {
    for (const u of [v.currentSrc, v.src]) if (u) urls.push(u);
    for (const s of v.querySelectorAll('source')) if (s.src) urls.push(s.src);
    try { v.muted = true; const p = v.play(); if (p && p.catch) p.catch(() => {}); } catch (e) {}
  }
  for (const sel of ['meta[property="og:video"]', 'meta[property="og:video:url"]',
                     'meta[property="og:video:secure_url"]', 'meta[name="twitter:player:stream"]']) {
    const m = document.querySelector(sel);
    if (m && m.content) urls.push(m.content);
  }
  return urls;
}
"""


class VideoNaoEncontrado(Exception):
    def __init__(self, mensagem: str = MENSAGEM_SEM_VIDEO):
        super().__init__(mensagem)


@dataclass
class VideoEncontrado:
    url: str
    tipo: str  # mp4, m3u8, webm, mov ou mpd
    pagina: str  # URL final da página; vai no cabeçalho Referer do download
    titulo: str | None = None
    miniatura: str | None = None
    tamanho: int | None = None
    # Instagram/Facebook: "video" = só imagem, "audio" = só som (arquivos DASH separados)
    trilha: str | None = None
    # quando a imagem e o som vêm separados, o som fica aqui e os dois são juntados
    url_audio: str | None = None

    @property
    def cabecalhos(self) -> dict[str, str]:
        return {"User-Agent": USER_AGENT, "Referer": self.pagina}


def classificar(url: str, content_type: str | None = None) -> str | None:
    """Diz se uma URL de rede é um vídeo (e de que tipo) ou ``None``."""
    if not url or url.startswith(("blob:", "data:")):
        return None
    if content_type:
        tipo = _TIPOS_CONTEUDO.get(content_type.split(";")[0].strip().lower())
        if tipo:
            return tipo
    if _SEGMENTOS.search(url):
        return None
    achado = _EXTENSOES.search(url)
    return achado.group(1).lower() if achado else None


_PARAMETROS_DE_PEDACO = ("bytestart", "byteend")


def normalizar_url(url: str) -> str:
    """Instagram e Facebook pedem o mesmo arquivo em pedaços (``bytestart``/``byteend``
    na URL). Sem esses parâmetros a CDN entrega o arquivo inteiro."""
    inicio = url.find("?")
    if inicio < 0:
        return url
    fim = url.find("#", inicio)
    fim = len(url) if fim < 0 else fim
    partes = url[inicio + 1:fim].split("&")
    mantidas = [p for p in partes if p and p.split("=", 1)[0] not in _PARAMETROS_DE_PEDACO]
    if len(mantidas) == len([p for p in partes if p]):
        return url
    consulta = "&".join(mantidas)
    return url[:inicio] + (f"?{consulta}" if consulta else "") + url[fim:]


def trilha_pela_url(url: str) -> str | None:
    """Lê o ``vencode_tag`` do parâmetro ``efg`` (JSON em base64) das URLs do
    Instagram/Facebook: ``..._audio`` é só som; ``dash_...`` é só imagem."""
    efg = parse_qs(urlsplit(url).query).get("efg", [None])[0]
    if not efg:
        return None
    try:
        dados = json.loads(base64.urlsafe_b64decode(efg + "=" * (-len(efg) % 4)))
        tag = str(dados.get("vencode_tag", "")).lower()
    except Exception:
        return None
    if "audio" in tag:
        return "audio"
    if "dash" in tag:
        return "video"
    return None


def escolher_melhor(candidatos: list[VideoEncontrado]) -> VideoEncontrado | None:
    """Prefere MP4; entre vários MP4 fica com o maior (normalmente a melhor qualidade).

    Se a imagem e o som vierem separados (Instagram/Facebook), devolve a imagem com
    o melhor som em ``url_audio``, para o download juntar os dois."""
    audios = [c for c in candidatos if c.trilha == "audio"]
    candidatos = [c for c in candidatos if c.trilha != "audio"]
    if not candidatos:
        return None
    ordem = {id(c): i for i, c in enumerate(candidatos)}
    melhor = min(
        candidatos,
        key=lambda c: (_PREFERENCIA.get(c.tipo, 9), -(c.tamanho or 0), ordem[id(c)]),
    )
    if melhor.trilha == "video" and audios:
        melhor.url_audio = max(audios, key=lambda c: c.tamanho or 0).url
    return melhor


class _LeitorMeta(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.meta: dict[str, str] = {}
        self.titulo: str | None = None
        self.fontes_video: list[str] = []
        self._no_title = False

    def handle_starttag(self, tag, attrs):
        a = {k.lower(): (v or "") for k, v in attrs}
        if tag == "meta":
            chave = (a.get("property") or a.get("name") or "").lower()
            if chave and a.get("content") and chave not in self.meta:
                self.meta[chave] = a["content"].strip()
        elif tag == "title":
            self._no_title = True
        elif tag in ("video", "source") and a.get("src"):
            self.fontes_video.append(a["src"])

    def handle_endtag(self, tag):
        if tag == "title":
            self._no_title = False

    def handle_data(self, data):
        if self._no_title and data.strip() and not self.titulo:
            self.titulo = data.strip()


def ler_html(html: str, pagina: str) -> tuple[VideoEncontrado | None, str | None, str | None]:
    """Procura vídeo no HTML puro. Retorna (vídeo ou None, título, miniatura)."""
    leitor = _LeitorMeta()
    try:
        leitor.feed(html)
    except Exception:  # HTML quebrado: aproveita o que já foi lido
        pass
    m = leitor.meta
    titulo = m.get("og:title") or m.get("twitter:title") or leitor.titulo
    miniatura = m.get("og:image") or m.get("twitter:image")
    if miniatura:
        miniatura = urljoin(pagina, miniatura)

    candidatos = []
    for chave in ("og:video:secure_url", "og:video:url", "og:video", "twitter:player:stream"):
        if m.get(chave):
            candidatos.append(m[chave])
    candidatos += leitor.fontes_video
    for bruto in candidatos:
        url = urljoin(pagina, bruto)
        tipo = classificar(url) or ("mp4" if _og_video_mp4(m) else None)
        if tipo:
            return VideoEncontrado(url, tipo, pagina, titulo, miniatura), titulo, miniatura
    return None, titulo, miniatura


def _og_video_mp4(meta: dict[str, str]) -> bool:
    return meta.get("og:video:type", "").lower() == "video/mp4"


def baixar_pagina(url: str, timeout: float = 20.0) -> tuple[str, str]:
    """Segue redirecionamentos (ex.: ``br.shp.ee/...``) e devolve (URL final, HTML)."""
    with httpx.Client(
        follow_redirects=True,
        timeout=timeout,
        headers={"User-Agent": USER_AGENT, "Accept-Language": "pt-BR,pt;q=0.9"},
    ) as cliente:
        resposta = cliente.get(url)
        resposta.raise_for_status()
        return str(resposta.url), resposta.text


def playwright_disponivel() -> bool:
    try:
        import playwright.sync_api  # noqa: F401
    except ImportError:
        return False
    return True


def procurar_com_navegador(url: str, espera: float = 25.0) -> tuple[list[VideoEncontrado], str, str | None, str | None]:
    """Abre a página no Chromium headless e captura os vídeos que ela carrega."""
    from playwright.sync_api import sync_playwright

    candidatos: list[VideoEncontrado] = []
    vistos: set[str] = set()
    estado = {"pagina": url}

    def anotar(u: str, tipo: str | None, tamanho: int | None = None) -> None:
        if not tipo:
            return
        inteira = normalizar_url(u)
        if inteira != u:
            tamanho = None  # o tamanho era só do pedaço
        if inteira in vistos:
            return
        vistos.add(inteira)
        candidatos.append(VideoEncontrado(inteira, tipo, estado["pagina"], tamanho=tamanho,
                                          trilha=trilha_pela_url(inteira)))

    def na_resposta(resp) -> None:
        try:
            cabecalhos = resp.headers
            tamanho = cabecalhos.get("content-length")
            anotar(resp.url, classificar(resp.url, cabecalhos.get("content-type")),
                   int(tamanho) if tamanho and tamanho.isdigit() else None)
        except Exception:
            pass

    with sync_playwright() as p:
        navegador = p.chromium.launch(
            headless=True,
            executable_path=os.environ.get("PEGAMIDIA_CHROMIUM") or None,
            # Versão Windows: usa o Microsoft Edge que já vem no sistema.
            channel=os.environ.get("PEGAMIDIA_NAVEGADOR_CANAL") or None,
            args=["--autoplay-policy=no-user-gesture-required"],
        )
        try:
            contexto = navegador.new_context(
                user_agent=USER_AGENT,
                viewport={"width": 412, "height": 915},
                is_mobile=True,
                has_touch=True,
                locale="pt-BR",
            )
            pagina = contexto.new_page()
            pagina.on("request", lambda req: anotar(req.url, classificar(req.url)))
            pagina.on("response", na_resposta)
            try:
                pagina.goto(url, wait_until="domcontentloaded", timeout=30_000)
            except Exception as erro:  # a página pode demorar, mas já ter carregado o vídeo
                log.info("goto não terminou: %s", erro)
            estado["pagina"] = pagina.url
            limite = time.monotonic() + espera
            achou_em = None
            while time.monotonic() < limite:
                try:
                    for u in pagina.evaluate(_JS_VIDEOS):
                        anotar(urljoin(pagina.url, u), classificar(u) or "mp4")
                except Exception:
                    pass
                if candidatos and achou_em is None:
                    achou_em = time.monotonic()
                # depois do primeiro vídeo, espera mais um pouco por uma versão melhor
                if achou_em is not None and time.monotonic() - achou_em > 3:
                    break
                pagina.wait_for_timeout(1000)
            titulo = None
            miniatura = None
            try:
                titulo = pagina.evaluate(
                    "() => document.querySelector('meta[property=\"og:title\"]')?.content || document.title"
                ) or None
                miniatura = pagina.evaluate(
                    "() => document.querySelector('meta[property=\"og:image\"]')?.content || null"
                )
            except Exception:
                pass
            cabecalhos = {"User-Agent": USER_AGENT, "Referer": pagina.url}
            for c in candidatos:
                if c.trilha and c.tamanho is None:
                    c.tamanho = medir_tamanho(c.url, cabecalhos)
            return candidatos, pagina.url, titulo, miniatura
        finally:
            navegador.close()


def medir_tamanho(url: str, cabecalhos: dict[str, str]) -> int | None:
    """Tamanho total do arquivo sem baixá-lo (Content-Range de um pedido de 1 byte)."""
    try:
        with httpx.Client(follow_redirects=True, timeout=10, headers=cabecalhos) as cliente:
            r = cliente.get(url, headers={"Range": "bytes=0-0"})
            faixa = r.headers.get("content-range", "")
            if "/" in faixa and faixa.rsplit("/", 1)[1].isdigit():
                return int(faixa.rsplit("/", 1)[1])
            tamanho = r.headers.get("content-length")
            return int(tamanho) if r.status_code == 200 and tamanho and tamanho.isdigit() else None
    except httpx.HTTPError:
        return None


# Cache curto: o /info descobre o vídeo e o /download reaproveita sem abrir o navegador de novo.
_cache: dict[str, tuple[float, VideoEncontrado]] = {}
_cache_lock = threading.Lock()
_CACHE_SEGUNDOS = 30 * 60


def descobrir_video(url: str, usar_navegador: bool = True) -> VideoEncontrado:
    with _cache_lock:
        item = _cache.get(url)
        if item and time.time() - item[0] < _CACHE_SEGUNDOS:
            return item[1]

    titulo = miniatura = None
    pagina = url
    try:
        pagina, html = baixar_pagina(url)
        video, titulo, miniatura = ler_html(html, pagina)
    except httpx.HTTPError as erro:
        log.info("Falha ao baixar HTML de %s: %s", url, erro)
        video = None

    if video is None and usar_navegador and playwright_disponivel():
        try:
            candidatos, pagina, titulo_nav, mini_nav = procurar_com_navegador(pagina)
        except Exception as erro:
            log.warning("Playwright falhou em %s: %s", pagina, erro)
            candidatos, titulo_nav, mini_nav = [], None, None
        video = escolher_melhor(candidatos)
        titulo = titulo or titulo_nav
        miniatura = miniatura or mini_nav

    if video is None:
        raise VideoNaoEncontrado()
    video.titulo = video.titulo or titulo
    video.miniatura = video.miniatura or miniatura
    with _cache_lock:
        _cache[url] = (time.time(), video)
    return video
