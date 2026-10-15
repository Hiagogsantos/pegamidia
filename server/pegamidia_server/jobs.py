"""Fila de tarefas de download (em memória) e limpeza de arquivos antigos."""

from __future__ import annotations

import logging
import shutil
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

from .downloader import ErroDownload, baixar

log = logging.getLogger(__name__)

IDADE_MAXIMA = 24 * 60 * 60  # arquivos com mais de 24 h são apagados


@dataclass
class Tarefa:
    id: str
    url: str
    tipo: str
    qualidade: str
    formato_audio: str = "mp3"
    referer: str | None = None
    titulo: str | None = None
    estado: str = "na_fila"  # na_fila | baixando | processando | concluido | erro
    progresso: float = 0.0
    mensagem: str = "Na fila…"
    bytes_baixados: int | None = None
    arquivo: Path | None = None
    criado_em: float = field(default_factory=time.time)

    def publico(self) -> dict:
        tamanho = None
        if self.arquivo is not None and self.arquivo.exists():
            tamanho = self.arquivo.stat().st_size
        return {
            "job_id": self.id,
            "url": self.url,
            "tipo": self.tipo,
            "qualidade": self.qualidade,
            "estado": self.estado,
            "progresso": self.progresso,
            "mensagem": self.mensagem,
            "titulo": self.titulo,
            "nome_arquivo": self.arquivo.name if self.arquivo else None,
            "tamanho": tamanho,
            "bytes_baixados": self.bytes_baixados,
        }


Baixador = Callable[..., Path]


class GerenciadorTarefas:
    def __init__(self, pasta: Path, max_paralelo: int = 2, baixador: Baixador = baixar):
        self.pasta = pasta
        self.pasta.mkdir(parents=True, exist_ok=True)
        self._baixador = baixador
        self._tarefas: dict[str, Tarefa] = {}
        self._lock = threading.Lock()
        self._executor = ThreadPoolExecutor(max_workers=max_paralelo, thread_name_prefix="download")

    def criar(self, url: str, tipo: str, qualidade: str, formato_audio: str = "mp3",
              referer: str | None = None, titulo: str | None = None) -> Tarefa:
        tarefa = Tarefa(id=uuid.uuid4().hex[:12], url=url, tipo=tipo, qualidade=qualidade,
                        formato_audio=formato_audio, referer=referer, titulo=titulo)
        with self._lock:
            self._tarefas[tarefa.id] = tarefa
        self._executor.submit(self._executar, tarefa)
        return tarefa

    def obter(self, job_id: str) -> Tarefa | None:
        with self._lock:
            return self._tarefas.get(job_id)

    def _atualizar(self, tarefa: Tarefa, **campos) -> None:
        with self._lock:
            for chave, valor in campos.items():
                setattr(tarefa, chave, valor)

    def _executar(self, tarefa: Tarefa) -> None:
        pasta = self.pasta / tarefa.id
        try:
            arquivo = self._baixador(
                tarefa.url, tarefa.tipo, tarefa.qualidade, pasta,
                lambda **c: self._atualizar(tarefa, **c),
                formato_audio=tarefa.formato_audio, referer=tarefa.referer, titulo=tarefa.titulo,
            )
            self._atualizar(tarefa, arquivo=arquivo, estado="concluido", progresso=100.0,
                            mensagem="Pronto!")
        except ErroDownload as erro:
            self._atualizar(tarefa, estado="erro", mensagem=str(erro))
        except Exception as erro:  # erro inesperado: registra e avisa o usuário
            log.exception("Falha na tarefa %s", tarefa.id)
            self._atualizar(tarefa, estado="erro", mensagem=f"Erro inesperado: {erro}")

    def limpar_antigos(self, idade_maxima: float = IDADE_MAXIMA, agora: float | None = None) -> int:
        """Apaga pastas/arquivos de ``downloads/`` com mais de 24 h. Retorna quantos apagou."""
        agora = agora or time.time()
        apagados = 0
        with self._lock:
            for job_id, tarefa in list(self._tarefas.items()):
                if agora - tarefa.criado_em > idade_maxima and tarefa.estado in ("concluido", "erro"):
                    del self._tarefas[job_id]
            ativos = {t.id for t in self._tarefas.values()}
        for item in self.pasta.iterdir():
            if item.name in ativos or item.name.startswith("."):
                continue
            try:
                if agora - item.stat().st_mtime <= idade_maxima:
                    continue
                if item.is_dir():
                    shutil.rmtree(item, ignore_errors=True)
                else:
                    item.unlink(missing_ok=True)
                apagados += 1
            except OSError as erro:
                log.warning("Não consegui apagar %s: %s", item, erro)
        return apagados

    def encerrar(self) -> None:
        self._executor.shutdown(wait=False, cancel_futures=True)
