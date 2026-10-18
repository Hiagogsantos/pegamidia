"""Ações da versão para computador (Windows): listar, abrir, renomear e apagar os
arquivos baixados na pasta do usuário (Downloads\\PegaMidia).

Só funcionam para quem está no próprio computador (127.0.0.1) e exigem o cabeçalho
``X-PegaMidia: 1``: celulares na rede e outras páginas abertas no navegador não
conseguem mexer nos arquivos.
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from .downloader import _limpar_nome
from .jobs import caminho_livre

_ENDERECOS_LOCAIS = {"127.0.0.1", "::1", "localhost", "testclient"}


def eh_pedido_local(request: Request) -> bool:
    host = request.client.host if request.client else ""
    return host in _ENDERECOS_LOCAIS


def _exigir_local(request: Request) -> Path:
    if not eh_pedido_local(request) or request.headers.get("x-pegamidia") != "1":
        raise HTTPException(status_code=403, detail="Disponível só no computador onde o PegaMídia está aberto.")
    pasta = request.app.state.tarefas.pasta_usuario
    if pasta is None:
        raise HTTPException(status_code=404, detail="Este servidor não tem pasta de downloads local.")
    pasta.mkdir(parents=True, exist_ok=True)
    return pasta


def _arquivo(pasta: Path, nome: str) -> Path:
    """Só aceita arquivos que estão direto dentro da pasta (nada de ``..\\``)."""
    if not nome or Path(nome).name != nome or nome.startswith("."):
        raise HTTPException(status_code=400, detail="Nome de arquivo inválido.")
    caminho = pasta / nome
    if not caminho.is_file():
        raise HTTPException(status_code=404, detail="Arquivo não encontrado.")
    return caminho


def abrir_no_sistema(caminho: Path, selecionar: bool = False) -> None:
    """Abre o arquivo no programa padrão, ou mostra-o selecionado na pasta."""
    if sys.platform == "win32":
        if selecionar:
            subprocess.Popen(f'explorer /select,"{caminho}"')
        else:
            os.startfile(caminho)  # type: ignore[attr-defined]
    elif sys.platform == "darwin":
        subprocess.Popen(["open", "-R", str(caminho)] if selecionar else ["open", str(caminho)])
    else:
        subprocess.Popen(["xdg-open", str(caminho.parent if selecionar else caminho)])


class PedidoArquivo(BaseModel):
    nome: str


class PedidoRenomear(BaseModel):
    nome: str
    novo: str = Field(..., min_length=1, max_length=200)


router = APIRouter(prefix="/local")


@router.get("/arquivos")
def arquivos(request: Request) -> dict:
    pasta = _exigir_local(request)
    lista = []
    for p in pasta.iterdir():
        if p.is_file() and not p.name.startswith("."):
            info = p.stat()
            lista.append({"nome": p.name, "tamanho": info.st_size, "modificado": info.st_mtime})
    lista.sort(key=lambda a: a["modificado"], reverse=True)
    return {"pasta": str(pasta), "arquivos": lista}


@router.post("/abrir")
def abrir(pedido: PedidoArquivo, request: Request) -> dict:
    request.app.state.abrir_no_sistema(_arquivo(_exigir_local(request), pedido.nome))
    return {"ok": True}


@router.post("/mostrar")
def mostrar(pedido: PedidoArquivo, request: Request) -> dict:
    request.app.state.abrir_no_sistema(_arquivo(_exigir_local(request), pedido.nome), selecionar=True)
    return {"ok": True}


@router.post("/abrir-pasta")
def abrir_pasta(request: Request) -> dict:
    request.app.state.abrir_no_sistema(_exigir_local(request))
    return {"ok": True}


@router.post("/renomear")
def renomear(pedido: PedidoRenomear, request: Request) -> dict:
    pasta = _exigir_local(request)
    atual = _arquivo(pasta, pedido.nome)
    novo_nome = f"{_limpar_nome(pedido.novo)}{atual.suffix}"
    destino = caminho_livre(pasta, novo_nome, ignorar=atual)
    if destino != atual:
        atual.rename(destino)
    return {"nome": destino.name}


@router.post("/apagar")
def apagar(pedido: PedidoArquivo, request: Request) -> dict:
    _arquivo(_exigir_local(request), pedido.nome).unlink()
    return {"ok": True}
