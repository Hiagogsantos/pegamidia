"""Detecção do site a partir do link e validação básica de URLs."""

from __future__ import annotations

import ipaddress
import os
import re
from urllib.parse import urlparse

# (nome interno, nome amigável, sufixos de domínio)
_SITES: list[tuple[str, str, tuple[str, ...]]] = [
    ("youtube_music", "YouTube Music", ("music.youtube.com",)),
    ("youtube", "YouTube", ("youtube.com", "youtu.be", "youtube-nocookie.com")),
    ("facebook", "Facebook", ("facebook.com", "fb.watch", "fb.com")),
    ("twitter", "X / Twitter", ("twitter.com", "x.com", "t.co")),
    ("tiktok", "TikTok", ("tiktok.com",)),
    ("instagram", "Instagram", ("instagram.com", "instagr.am")),
    ("kwai", "Kwai", ("kwai.com", "kw.ai", "kwai-video.com", "kwai.net")),
    ("shopee", "Shopee", ("shopee.com.br", "shp.ee", "shopee.com", "shopee.sg")),
]

# Sites sem extrator dedicado no yt-dlp: usamos o fallback (og:video / Playwright).
SITES_SEM_EXTRATOR = {"kwai", "shopee"}

NOMES = {nome: amigavel for nome, amigavel, _ in _SITES} | {"outro": "Outro site"}

_URL_NO_TEXTO = re.compile(r"https?://[^\s<>\"']+", re.IGNORECASE)


class UrlInvalida(ValueError):
    """Link vazio, malformado ou apontando para endereço não permitido."""


def _dominio_bate(host: str, sufixo: str) -> bool:
    return host == sufixo or host.endswith("." + sufixo)


def detectar_site(url: str) -> str:
    """Retorna o nome interno do site (ex.: ``youtube``) ou ``outro``."""
    host = (urlparse(url).hostname or "").lower()
    for nome, _amigavel, sufixos in _SITES:
        if any(_dominio_bate(host, s) for s in sufixos):
            return nome
    return "outro"


def extrair_url(texto: str) -> str | None:
    """Acha o primeiro link dentro de um texto (ex.: texto compartilhado pela Shopee)."""
    achado = _URL_NO_TEXTO.search(texto or "")
    if not achado:
        return None
    return achado.group(0).rstrip(".,;:!?)]}")


def permitir_enderecos_locais() -> bool:
    return os.environ.get("PEGAMIDIA_PERMITIR_LOCAL", "") == "1"


def validar_url(texto: str) -> str:
    """Normaliza o link recebido e recusa endereços que não sejam páginas públicas.

    O servidor roda dentro da rede da escola; recusar IPs locais evita que alguém use
    o PegaMídia para acessar outros aparelhos da rede.
    """
    url = extrair_url(texto.strip()) if texto else None
    if not url:
        raise UrlInvalida("Link inválido. Cole um endereço que comece com http:// ou https://.")
    partes = urlparse(url)
    host = (partes.hostname or "").lower()
    if partes.scheme not in ("http", "https") or not host:
        raise UrlInvalida("Link inválido. Cole um endereço que comece com http:// ou https://.")

    if not permitir_enderecos_locais():
        if host == "localhost" or host.endswith(".local") or host.endswith(".localhost"):
            raise UrlInvalida("Endereços da rede local não são permitidos.")
        try:
            ip = ipaddress.ip_address(host)
        except ValueError:
            ip = None
        if ip is not None and not ip.is_global:
            raise UrlInvalida("Endereços da rede local não são permitidos.")
    return url
