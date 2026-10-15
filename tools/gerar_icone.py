"""Gera o ícone do PegaMídia (seta de download sobre um "play"), sem logos de plataformas.

Uso: python tools/gerar_icone.py   (requer Pillow)
"""

from pathlib import Path

from PIL import Image, ImageDraw

RAIZ = Path(__file__).resolve().parent.parent / "app"
COR_FUNDO = (0, 137, 123)  # verde-azulado do tema do app
BRANCO = (255, 255, 255)


def desenhar(tamanho: int, redondo: bool = True) -> Image.Image:
    escala = 4  # desenha grande e reduz: bordas suaves
    t = tamanho * escala
    img = Image.new("RGBA", (t, t), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if redondo:
        d.ellipse((0, 0, t - 1, t - 1), fill=COR_FUNDO)
    else:
        d.rounded_rectangle((0, 0, t - 1, t - 1), radius=int(t * 0.22), fill=COR_FUNDO)
    # "tela" de vídeo com triângulo de play
    m = t * 0.24
    topo, base = t * 0.24, t * 0.58
    d.rounded_rectangle((m, topo, t - m, base), radius=int(t * 0.05), outline=BRANCO, width=int(t * 0.045))
    cx, cy, r = t / 2, (topo + base) / 2, t * 0.085
    d.polygon([(cx - r * 0.7, cy - r), (cx - r * 0.7, cy + r), (cx + r, cy)], fill=BRANCO)
    # seta de download embaixo
    largura = t * 0.07
    d.rectangle((cx - largura / 2, t * 0.60, cx + largura / 2, t * 0.71), fill=BRANCO)
    d.polygon([(cx - t * 0.11, t * 0.68), (cx + t * 0.11, t * 0.68), (cx, t * 0.79)], fill=BRANCO)
    return img.resize((tamanho, tamanho), Image.LANCZOS)


def main() -> None:
    android = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for pasta, tamanho in android.items():
        desenhar(tamanho).save(RAIZ / f"android/app/src/main/res/mipmap-{pasta}/ic_launcher.png")
    ios = RAIZ / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for arquivo in ios.glob("*.png"):
        with Image.open(arquivo) as atual:
            tamanho = atual.size[0]
        # iOS não aceita transparência no ícone
        fundo = Image.new("RGB", (tamanho, tamanho), COR_FUNDO)
        icone = desenhar(tamanho, redondo=False)
        fundo.paste(icone, mask=icone)
        fundo.save(arquivo)
    print("Ícones gerados.")


if __name__ == "__main__":
    main()
