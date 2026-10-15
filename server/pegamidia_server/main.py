"""API HTTP do servidor PegaMídia (FastAPI)."""

from __future__ import annotations

import asyncio
import contextlib
import logging
import os
import shutil
from pathlib import Path
from typing import Literal

import yt_dlp
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field
from starlette.concurrency import run_in_threadpool

from . import APP_NAME, __version__, fallback
from .downloader import QUALIDADE_PADRAO, ErroDownload, extrair_info
from .jobs import GerenciadorTarefas
from .sites import UrlInvalida, validar_url

log = logging.getLogger("pegamidia")

PASTA_DOWNLOADS = Path(os.environ.get("PEGAMIDIA_PASTA", Path(__file__).resolve().parent.parent / "downloads"))
INTERVALO_LIMPEZA = 60 * 60  # 1 h


class PedidoInfo(BaseModel):
    url: str = Field(..., description="Link da página do vídeo")


class PedidoDownload(BaseModel):
    url: str
    tipo: Literal["video", "audio"] = "video"
    qualidade: str = Field(QUALIDADE_PADRAO, pattern=r"^(melhor|\d{3,4}p)$")
    formato_audio: Literal["mp3", "m4a"] = "mp3"
    # Usados quando o app já achou o vídeo pelo WebView (ex.: .m3u8 da Shopee):
    referer: str | None = Field(None, description="Página de onde o vídeo veio (cabeçalho Referer)")
    titulo: str | None = Field(None, max_length=200)


def criar_app(gerenciador: GerenciadorTarefas | None = None) -> FastAPI:
    tarefas = gerenciador or GerenciadorTarefas(PASTA_DOWNLOADS)

    @contextlib.asynccontextmanager
    async def ciclo_de_vida(_app: FastAPI):
        async def limpar_periodicamente():
            while True:
                try:
                    apagados = await run_in_threadpool(tarefas.limpar_antigos)
                    if apagados:
                        log.info("Limpeza: %d item(ns) antigo(s) apagado(s)", apagados)
                except Exception:
                    log.exception("Falha na limpeza de downloads")
                await asyncio.sleep(INTERVALO_LIMPEZA)

        tarefa_limpeza = asyncio.create_task(limpar_periodicamente())
        try:
            yield
        finally:
            tarefa_limpeza.cancel()
            tarefas.encerrar()

    app = FastAPI(title=f"{APP_NAME} — servidor", version=__version__, lifespan=ciclo_de_vida)
    app.state.tarefas = tarefas

    def _validar(url: str) -> str:
        try:
            return validar_url(url)
        except UrlInvalida as erro:
            raise HTTPException(status_code=400, detail=str(erro)) from erro

    @app.get("/")
    @app.get("/saude")
    def saude() -> dict:
        """Usado pelo botão "Testar conexão" do app."""
        return {
            "app": APP_NAME,
            "versao": __version__,
            "yt_dlp": yt_dlp.version.__version__,
            "ffmpeg": shutil.which("ffmpeg") is not None,
            "playwright": fallback.playwright_disponivel(),
        }

    @app.post("/info")
    def info(pedido: PedidoInfo) -> dict:
        url = _validar(pedido.url)
        try:
            return extrair_info(url)
        except ErroDownload as erro:
            raise HTTPException(status_code=422, detail=str(erro)) from erro

    @app.post("/download")
    def download(pedido: PedidoDownload) -> dict:
        url = _validar(pedido.url)
        referer = _validar(pedido.referer) if pedido.referer else None
        tarefa = tarefas.criar(url, pedido.tipo, pedido.qualidade, pedido.formato_audio,
                               referer=referer, titulo=pedido.titulo)
        return {"job_id": tarefa.id}

    @app.get("/status/{job_id}")
    def status(job_id: str) -> dict:
        tarefa = tarefas.obter(job_id)
        if tarefa is None:
            raise HTTPException(status_code=404, detail="Tarefa não encontrada (talvez já tenha sido apagada).")
        return tarefa.publico()

    @app.get("/arquivo/{job_id}")
    def arquivo(job_id: str) -> FileResponse:
        tarefa = tarefas.obter(job_id)
        if tarefa is None:
            raise HTTPException(status_code=404, detail="Tarefa não encontrada (talvez já tenha sido apagada).")
        if tarefa.estado != "concluido" or tarefa.arquivo is None or not tarefa.arquivo.exists():
            raise HTTPException(status_code=409, detail="O arquivo ainda não está pronto.")
        return FileResponse(tarefa.arquivo, filename=tarefa.arquivo.name)

    return app


app = criar_app()
