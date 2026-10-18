# Receita do PyInstaller para o PegaMidia.exe (versão Windows).
# Uso (na pasta server):  pyinstaller --noconfirm desktop/PegaMidia.spec
# Antes, coloque ffmpeg.exe, ffprobe.exe e deno.exe em server/ferramentas (o GitHub Actions faz isso).
from pathlib import Path

from PyInstaller.utils.hooks import collect_data_files, collect_submodules

raiz = Path(SPECPATH).parent  # pasta server

datas = [
    (str(raiz / "pegamidia_server" / "web"), "pegamidia_server/web"),
    (str(raiz / "ferramentas"), "ferramentas"),
]
# driver do Playwright (node), scripts do YouTube (yt-dlp-ejs) e DLLs da janela (pywebview/pythonnet)
for pacote in ("playwright", "yt_dlp_ejs", "webview", "pythonnet", "clr_loader", "certifi"):
    datas += collect_data_files(pacote)

hiddenimports = (
    collect_submodules("pegamidia_server")
    + collect_submodules("uvicorn")
    + collect_submodules("yt_dlp_ejs")
    + ["webview.platforms.edgechromium", "webview.platforms.winforms", "clr"]
)

a = Analysis(
    [str(raiz / "PegaMidia.py")],
    pathex=[str(raiz)],
    datas=datas,
    hiddenimports=hiddenimports,
    excludes=["pytest"],
    noarchive=False,
)
pyz = PYZ(a.pure)
exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="PegaMidia",
    icon=str(raiz / "desktop" / "pegamidia.ico"),
    console=False,  # programa de janela (sem a tela preta do console)
    upx=False,
)
coll = COLLECT(exe, a.binaries, a.datas, name="PegaMidia", upx=False)
