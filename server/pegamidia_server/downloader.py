"""Integração com o yt-dlp: informações do link e download com progresso."""

from __future__ import annotations

import logging
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any, Callable

import yt_dlp
from yt_dlp.utils import DownloadError

from . import fallback
from .sites import NOMES, SITES_SEM_EXTRATOR, detectar_site

log = logging.getLogger(__name__)

QUALIDADE_PADRAO = "720p"
# Limite de segurança para não lotar o disco do PC da escola (padrão: 2 GB).
TAMANHO_MAXIMO = int(os.environ.get("PEGAMIDIA_TAMANHO_MAXIMO", str(2 * 1024**3)))

_EXTENSOES_TEMPORARIAS = (".part", ".ytdl", ".temp", ".tmp")


class ErroDownload(Exception):
    """Erro com mensagem já pronta para mostrar ao usuário."""


def altura_da_qualidade(qualidade: str) -> int | None:
    """``"720p"`` → 720; ``"melhor"`` → None (sem limite)."""
    achado = re.fullmatch(r"(\d{3,4})p", qualidade or "")
    return int(achado.group(1)) if achado else None


def montar_opcoes(
    tipo: str,
    qualidade: str,
    pasta: Path,
    formato_audio: str = "mp3",
    nome_arquivo: str | None = None,
    cabecalhos: dict[str, str] | None = None,
    progresso: Callable[[dict], None] | None = None,
    pos_processamento: Callable[[dict], None] | None = None,
) -> dict[str, Any]:
    """Opções do ``yt_dlp.YoutubeDL`` para vídeo (MP4) ou áudio (MP3/M4A)."""
    nome = _limpar_nome(nome_arquivo) if nome_arquivo else "%(title).80B"
    opcoes: dict[str, Any] = {
        "outtmpl": str(pasta / f"{nome}.%(ext)s"),
        "noplaylist": True,
        "quiet": True,
        "no_warnings": True,
        "noprogress": True,
        "restrictfilenames": False,
        "windowsfilenames": True,  # nomes que funcionam em qualquer sistema
        "max_filesize": TAMANHO_MAXIMO,
        "socket_timeout": 30,
        "retries": 3,
        "fragment_retries": 5,
        "concurrent_fragment_downloads": 4,
        # Sem login e sem cookies: só conteúdo público.
        "cookiefile": None,
    }
    if cabecalhos:
        opcoes["http_headers"] = dict(cabecalhos)
    if progresso:
        opcoes["progress_hooks"] = [progresso]
    if pos_processamento:
        opcoes["postprocessor_hooks"] = [pos_processamento]

    if tipo == "audio":
        if formato_audio == "m4a":
            # M4A: pega direto a faixa AAC quando existe (sem reconverter).
            opcoes["format"] = "ba[ext=m4a]/ba/b"
            opcoes["postprocessors"] = [
                {"key": "FFmpegExtractAudio", "preferredcodec": "m4a", "preferredquality": "192"}
            ]
        else:
            opcoes["format"] = "ba/b"
            opcoes["postprocessors"] = [
                {"key": "FFmpegExtractAudio", "preferredcodec": "mp3", "preferredquality": "192"}
            ]
    else:
        altura = altura_da_qualidade(qualidade)
        # Prefere H.264/AAC em MP4 (abre em qualquer celular e no e-mail).
        ordem = [f"res:{altura}"] if altura else ["res"]
        ordem += ["vcodec:h264", "acodec:aac", "ext:mp4:m4a"]
        opcoes["format"] = "bv*+ba/b"
        opcoes["format_sort"] = ordem
        opcoes["merge_output_format"] = "mp4"
        opcoes["postprocessors"] = [{"key": "FFmpegVideoRemuxer", "preferedformat": "mp4"}]
    return opcoes


def _limpar_nome(nome: str) -> str:
    nome = re.sub(r'[\\/:*?"<>|\x00-\x1f%]+', " ", nome)
    nome = re.sub(r"\s+", " ", nome).strip(" .")
    return (nome[:80].strip() or "video")


def traduzir_erro(mensagem: str) -> str:
    """Converte erros do yt-dlp em mensagens claras em português."""
    m = (mensagem or "").lower()
    if "unsupported url" in m or "no video formats found" in m or "no video could be found" in m:
        return fallback.MENSAGEM_SEM_VIDEO
    if "sign in to confirm" in m or "not a bot" in m:
        return ("O YouTube bloqueou temporariamente este computador. Atualize o extrator "
                "(pip install -U yt-dlp) e tente de novo mais tarde.")
    if "private" in m or "login" in m or "log in" in m or "cookies" in m or "sign in" in m:
        return "Este vídeo é privado ou exige login. O PegaMídia só baixa vídeos públicos."
    if "file is larger than max-filesize" in m or "max-filesize" in m:
        return "O arquivo é grande demais. Tente uma qualidade menor."
    if "video unavailable" in m or "has been removed" in m or "http error 404" in m or "http error 410" in m:
        return "Vídeo indisponível ou removido."
    if "ffmpeg" in m and ("not found" in m or "not installed" in m):
        return "O ffmpeg não está instalado no servidor."
    if any(t in m for t in ("unable to download webpage", "name or service not known",
                            "timed out", "getaddrinfo failed", "connection refused",
                            "temporary failure in name resolution")):
        return "Não consegui abrir o link. Verifique o endereço e a internet do servidor."
    primeira = (mensagem or "").strip().splitlines()[0] if mensagem and mensagem.strip() else ""
    primeira = re.sub(r"^ERROR:\s*", "", primeira)
    return f"Não foi possível baixar: {primeira[:200]}" if primeira else "Não foi possível baixar."


def precisa_fallback(mensagem: str, site: str) -> bool:
    """Quando o yt-dlp não reconhece a página, tentamos achar o vídeo nela (og:video/Playwright)."""
    m = (mensagem or "").lower()
    if "unsupported url" in m or "no video formats found" in m or "no video could be found" in m:
        return True
    # Instagram e Facebook costumam pedir login ao yt-dlp; a página pública ainda mostra o vídeo.
    return site in SITES_SEM_EXTRATOR or site in ("outro", "instagram", "facebook")


_SO_AUDIO = ("mp3", "m4a", "opus", "ogg", "oga", "wav", "aac", "flac")


def _tem_imagem(formato: dict[str, Any]) -> bool:
    vcodec = formato.get("vcodec")
    if vcodec is None:
        return formato.get("ext") not in _SO_AUDIO
    return vcodec != "none"


def resumir_info(info: dict[str, Any], url: str) -> dict[str, Any]:
    """Resumo das informações do yt-dlp no formato do endpoint ``/info``."""
    site = detectar_site(url)
    formatos = info.get("formats") or []
    # Codec ausente (None) = desconhecido, comum em links diretos de .mp4: não dá para
    # dizer que não há imagem/som. Só "none" significa que a trilha não existe.
    tem_video = any(_tem_imagem(f) for f in formatos) or (not formatos and info.get("ext") not in _SO_AUDIO)
    tem_audio = any(f.get("acodec") != "none" for f in formatos) or not formatos

    por_altura: dict[int, dict[str, Any]] = {}
    for f in formatos:
        altura = f.get("height")
        if not altura or (f.get("vcodec") or "none") == "none":
            continue
        tamanho = f.get("filesize") or f.get("filesize_approx")
        atual = por_altura.get(altura)
        if atual is None or (tamanho or 0) > (atual["tamanho_aprox"] or 0):
            por_altura[altura] = {"altura": altura, "ext": f.get("ext"), "tamanho_aprox": tamanho}

    return {
        "titulo": info.get("title") or "Sem título",
        "miniatura": info.get("thumbnail"),
        "duracao": info.get("duration"),
        "autor": info.get("uploader") or info.get("channel"),
        "site": site,
        "site_nome": NOMES.get(site, "Outro site"),
        "extrator": info.get("extractor_key") or info.get("extractor"),
        "tem_video": bool(tem_video),
        "tem_audio": bool(tem_audio),
        "qualidades": [f"{a}p" for a in sorted(por_altura)],
        "formatos": [por_altura[a] for a in sorted(por_altura)],
        "fonte": "yt-dlp",
    }


def resumir_video_encontrado(video: fallback.VideoEncontrado, url: str) -> dict[str, Any]:
    site = detectar_site(url)
    return {
        "titulo": video.titulo or "Vídeo da página",
        "miniatura": video.miniatura,
        "duracao": None,
        "autor": None,
        "site": site,
        "site_nome": NOMES.get(site, "Outro site"),
        "extrator": "pagina",
        "tem_video": True,
        "tem_audio": True,
        "qualidades": [],
        "formatos": [{"altura": None, "ext": video.tipo, "tamanho_aprox": video.tamanho}],
        "fonte": "pagina",
        "url_video": video.url,
    }


def extrair_info(url: str) -> dict[str, Any]:
    """``/info``: usa o yt-dlp e, se ele não reconhecer o site, procura o vídeo na página."""
    site = detectar_site(url)
    opcoes = {"quiet": True, "no_warnings": True, "noplaylist": True,
              "extract_flat": "in_playlist", "socket_timeout": 30}
    try:
        with yt_dlp.YoutubeDL(opcoes) as ydl:
            info = ydl.extract_info(url, download=False)
    except DownloadError as erro:
        if not precisa_fallback(str(erro), site):
            raise ErroDownload(traduzir_erro(str(erro))) from erro
        try:
            return resumir_video_encontrado(fallback.descobrir_video(url), url)
        except fallback.VideoNaoEncontrado as nao:
            raise ErroDownload(str(nao)) from erro

    if info.get("_type") in ("playlist", "multi_video") and not info.get("formats"):
        raise ErroDownload("Este link é uma playlist. Abra um vídeo específico e copie o link dele.")
    return resumir_info(info, url)


def arquivo_final(pasta: Path) -> Path | None:
    """O maior arquivo pronto da pasta da tarefa (ignora temporários do yt-dlp)."""
    arquivos = [
        p for p in pasta.iterdir()
        if p.is_file() and not p.name.endswith(_EXTENSOES_TEMPORARIAS) and ".part-" not in p.name
    ] if pasta.exists() else []
    return max(arquivos, key=lambda p: p.stat().st_size, default=None)


class AcompanharProgresso:
    """Converte os ganchos do yt-dlp em porcentagem única (vídeo + áudio contam juntos)."""

    def __init__(self, atualizar: Callable[..., None], titulo_fixo: bool = False):
        self.atualizar = atualizar
        self.partes_concluidas = 0
        self.titulo_enviado = titulo_fixo

    def progresso(self, d: dict) -> None:
        info = d.get("info_dict") or {}
        if not self.titulo_enviado and info.get("title"):
            self.titulo_enviado = True
            self.atualizar(titulo=info["title"])
        partes = len(info.get("requested_formats") or []) or 1
        if d.get("status") == "finished":
            self.partes_concluidas += 1
            feito = min(self.partes_concluidas / partes, 1.0)
            self.atualizar(estado="baixando", progresso=round(feito * 99, 1), mensagem="Baixando…")
            return
        if d.get("status") != "downloading":
            return
        total = d.get("total_bytes") or d.get("total_bytes_estimate")
        baixado = d.get("downloaded_bytes") or 0
        if total:
            fracao = baixado / total
        elif d.get("fragment_count"):
            fracao = (d.get("fragment_index") or 0) / d["fragment_count"]
        else:
            fracao = 0.0
        geral = (min(self.partes_concluidas, partes - 1) + min(fracao, 1.0)) / partes
        self.atualizar(estado="baixando", progresso=round(min(geral, 0.99) * 100, 1),
                       mensagem="Baixando…", bytes_baixados=baixado)

    def pos_processamento(self, d: dict) -> None:
        if d.get("status") == "started":
            nomes = {"FFmpegExtractAudio": "Convertendo o áudio…",
                     "FFmpegMerger": "Juntando vídeo e áudio…",
                     "FFmpegVideoRemuxer": "Gerando o MP4…"}
            self.atualizar(estado="processando",
                           mensagem=nomes.get(d.get("postprocessor"), "Processando…"))


def baixar(
    url: str,
    tipo: str,
    qualidade: str,
    pasta: Path,
    atualizar: Callable[..., None],
    formato_audio: str = "mp3",
    referer: str | None = None,
    titulo: str | None = None,
) -> Path:
    """Baixa o link para ``pasta`` e retorna o caminho do arquivo final.

    ``atualizar(**campos)`` recebe estado/progresso/mensagem/titulo durante o download.
    """
    if shutil.which("ffmpeg") is None:
        raise ErroDownload("O ffmpeg não está instalado no servidor.")
    pasta.mkdir(parents=True, exist_ok=True)
    site = detectar_site(url)
    acompanhar = AcompanharProgresso(atualizar, titulo_fixo=bool(titulo))

    def tentar(link: str, cabecalhos: dict[str, str] | None, nome: str | None) -> None:
        opcoes = montar_opcoes(
            tipo, qualidade, pasta, formato_audio=formato_audio, nome_arquivo=nome,
            cabecalhos=cabecalhos, progresso=acompanhar.progresso,
            pos_processamento=acompanhar.pos_processamento,
        )
        with yt_dlp.YoutubeDL(opcoes) as ydl:
            ydl.extract_info(link, download=True)

    cabecalhos = {"Referer": referer, "User-Agent": fallback.USER_AGENT} if referer else None
    atualizar(estado="baixando", mensagem="Abrindo o link…")
    try:
        tentar(url, cabecalhos, titulo)
    except DownloadError as erro:
        if referer or not precisa_fallback(str(erro), site):
            raise ErroDownload(traduzir_erro(str(erro))) from erro
        atualizar(mensagem="Procurando o vídeo na página…")
        try:
            video = fallback.descobrir_video(url)
        except fallback.VideoNaoEncontrado as nao:
            raise ErroDownload(str(nao)) from erro
        nome = titulo or video.titulo or "video"
        atualizar(titulo=nome)
        _limpar_pasta(pasta)
        acompanhar.partes_concluidas = 0
        acompanhar.titulo_enviado = True
        if video.url_audio:
            return juntar_imagem_e_som(video, tipo, pasta, nome, atualizar)
        try:
            tentar(video.url, video.cabecalhos, nome)
        except DownloadError as erro2:
            raise ErroDownload(traduzir_erro(str(erro2))) from erro2

    final = arquivo_final(pasta)
    if final is None:
        raise ErroDownload("O download terminou, mas o arquivo não foi encontrado.")
    return final


def juntar_imagem_e_som(video: fallback.VideoEncontrado, tipo: str, pasta: Path, nome: str,
                        atualizar: Callable[..., None]) -> Path:
    """Instagram/Facebook entregam imagem e som em arquivos separados: o ffmpeg baixa
    os dois (com os mesmos cabeçalhos da página) e junta num MP4, sem reconverter.
    Para "só áudio", converte o som em MP3."""
    cabecalhos = "".join(f"{k}: {v}\r\n" for k, v in video.cabecalhos.items())
    if tipo == "audio":
        saida = pasta / f"{_limpar_nome(nome)}.mp3"
        entradas = ["-headers", cabecalhos, "-i", video.url_audio]
        resto = ["-vn", "-c:a", "libmp3lame", "-b:a", "192k"]
        atualizar(estado="baixando", mensagem="Baixando o som…")
    else:
        saida = pasta / f"{_limpar_nome(nome)}.mp4"
        entradas = ["-headers", cabecalhos, "-i", video.url, "-headers", cabecalhos, "-i", video.url_audio]
        resto = ["-map", "0:v:0", "-map", "1:a:0", "-c", "copy", "-movflags", "+faststart"]
        atualizar(estado="baixando", mensagem="Baixando e juntando imagem e som…")
    comando = [shutil.which("ffmpeg") or "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
               *entradas, *resto, str(saida)]
    extras = {"creationflags": subprocess.CREATE_NO_WINDOW} if sys.platform == "win32" else {}
    try:
        resultado = subprocess.run(comando, capture_output=True, text=True, timeout=1800, **extras)
    except subprocess.TimeoutExpired as erro:
        raise ErroDownload("O download demorou demais.") from erro
    if resultado.returncode != 0 or not saida.exists():
        detalhe = (resultado.stderr or "").strip().splitlines()[-1:] or ["erro desconhecido"]
        raise ErroDownload(f"Não consegui juntar imagem e som: {detalhe[0][:200]}")
    return saida


def _limpar_pasta(pasta: Path) -> None:
    for p in pasta.iterdir():
        if p.is_file():
            p.unlink(missing_ok=True)
