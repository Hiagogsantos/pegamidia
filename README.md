# PegaMídia

```
⚠️ Projeto escolar, sem fins comerciais

Este app foi criado para uso educacional e interno de uma escola
(ex.: salvar vídeos de produtos para o bingo, materiais de aula,
gravações próprias). Não é vendido, não tem anúncios e não deve
ser usado comercialmente.

Use apenas com conteúdo seu, com permissão do autor ou de licença
livre. Respeite os direitos autorais e os termos de uso de cada site.
Os autores não se responsabilizam pelo uso indevido.

Este app não é afiliado ao YouTube, Google, Meta, X, TikTok, Kwai
ou Shopee.
```

App Flutter para colar um link (YouTube, YouTube Music, Facebook, X/Twitter, TikTok, Instagram, Kwai, Shopee…) e baixar o **vídeo (MP4)** ou só o **áudio (MP3)**, e depois compartilhar o arquivo por e-mail, WhatsApp etc.

> O projeto nasceu para baixar o vídeo de um produto da Shopee e mandar por e-mail, mostrando um possível presente para o bingo da escola.

## Como funciona

```
[App Flutter]  --(link)-->  [Servidor Python (FastAPI + yt-dlp + ffmpeg)]
     ^                                   |
     +-------(arquivo MP4/MP3)-----------+
```

- **Servidor** (`server/`): roda num PC da escola, na mesma rede Wi-Fi dos celulares. Usa o [yt-dlp](https://github.com/yt-dlp/yt-dlp), que é atualizado quase toda semana. Um PC com internet residencial/escolar funciona melhor que um servidor em nuvem (o YouTube costuma bloquear IPs de datacenter).
- **App** (`app/`): só faz HTTP; funciona em Android e iOS.
- **Captura pela página (WebView)**: para Shopee, Kwai ou qualquer página com vídeo, o app abre o link num navegador interno e captura os vídeos que a página carrega. É o mesmo que fazer à mão no Chrome: F12 → Network → filtrar "mp4" → abrir → salvar. Para MP4 isso funciona **sem servidor**.

Ordem que o app segue:

1. Shopee e Kwai → captura pela página (no próprio celular).
2. Outros sites → servidor (yt-dlp). Se o yt-dlp não reconhecer a página, o servidor procura a meta `og:video` e, se precisar, abre a página no Chromium (Playwright) e captura o `.mp4`/`.m3u8`.
3. Servidor desligado ou não configurado → captura pela página para qualquer link.
4. Vídeo em pedaços (`.m3u8`) achado pelo app → é enviado ao servidor para virar MP4 (com ffmpeg).

### Sites

| Site | Como baixa | Observação |
|---|---|---|
| YouTube / YouTube Music | yt-dlp | Áudio sai em MP3 192 kbps |
| Facebook (vídeos e reels) | yt-dlp | Vídeos privados não são suportados |
| X / Twitter | yt-dlp | |
| TikTok | yt-dlp | Links curtos `vm.tiktok.com` funcionam |
| Instagram | yt-dlp | Só posts públicos |
| Kwai | Captura pela página (app) / fallback do servidor | Sem extrator dedicado no yt-dlp |
| Shopee | Captura pela página (app) / fallback do servidor | Links curtos `br.shp.ee/...` funcionam |

Os sites mudam com frequência. Se um link parar de funcionar, atualize o yt-dlp (veja abaixo). A lista oficial está em [supportedsites.md](https://github.com/yt-dlp/yt-dlp/blob/master/supportedsites.md).

## 1. Servidor (PC da escola)

Requisitos: Python 3.11+ e ffmpeg.

**Windows**

1. Instale o [Python](https://www.python.org/downloads/) (marque "Add python.exe to PATH") e o ffmpeg: `winget install Gyan.FFmpeg`.
2. Na pasta `server`, dê dois cliques em **`instalar.bat`** (só na primeira vez).
3. Para usar, dê dois cliques em **`iniciar.bat`** e deixe a janela aberta. Ela mostra o endereço para colocar no app, ex.: `http://192.168.0.10:8000`.
4. Se algum site parar de funcionar: **`atualizar.bat`** (equivale a `pip install -U yt-dlp`).

Na primeira vez, o Windows pode perguntar sobre o firewall: permita o acesso em **redes privadas**.

**Linux / macOS**

```sh
sudo apt install python3-venv ffmpeg   # ou: brew install ffmpeg
cd server
./instalar.sh
./iniciar.sh          # mostra o endereço para o app
./atualizar.sh        # quando algum site parar de funcionar
```

### API

| Método | Rota | Corpo / resposta |
|---|---|---|
| `GET` | `/saude` | versão do servidor e do yt-dlp, se há ffmpeg/Playwright |
| `POST` | `/info` | `{url}` → título, miniatura, duração, site, qualidades e tamanhos |
| `POST` | `/download` | `{url, tipo: "video"\|"audio", qualidade: "720p"\|"480p"\|"360p"\|"melhor"}` → `{job_id}` |
| `GET` | `/status/{job_id}` | estado (`na_fila`, `baixando`, `processando`, `concluido`, `erro`), progresso (%), mensagem, nome do arquivo |
| `GET` | `/arquivo/{job_id}` | envia o arquivo pronto |

A documentação interativa fica em `http://<ip-do-servidor>:8000/docs`.

Detalhes:
- Vídeo: até 720p por padrão (arquivos menores, melhor para e-mail), MP4 com H.264/AAC sempre que possível.
- Áudio: MP3 192 kbps.
- Sem login e sem cookies de contas pessoais: só conteúdo público.
- Arquivos com mais de 24 h na pasta `server/downloads/` são apagados automaticamente.
- Por segurança, o servidor recusa links para endereços da rede local (`192.168.x.x`, `localhost`…).
- Variáveis opcionais: `PEGAMIDIA_PASTA` (pasta dos downloads), `PEGAMIDIA_TAMANHO_MAXIMO` (bytes, padrão 2 GB), `PEGAMIDIA_CHROMIUM` (caminho de um Chrome/Chromium para o Playwright).

Testes: `pip install -r requirements-dev.txt && python -m pytest` (baixam um vídeo gerado localmente com yt-dlp + ffmpeg de verdade).

## 2. App

Telas:
- **Início**: campo para colar o link (botão "Colar"), prévia com miniatura e título, escolha Vídeo/Áudio e qualidade, botão Baixar.
- **Downloads**: lista com progresso; abrir, compartilhar e apagar.
- **Configurações**: endereço do servidor e "Testar conexão".
- **Sobre**: regras de uso.

Também dá para mandar um link direto para o app pelo botão **Compartilhar** de outros apps (Shopee, YouTube, TikTok…) — no Android.

Ao compartilhar um arquivo com mais de ~25 MB, o app avisa que o Gmail e similares não aceitam anexos desse tamanho e sugere WhatsApp/Drive ou uma qualidade menor.

### Rodar em modo de desenvolvimento

```sh
cd app
flutter pub get
flutter run
```

### Gerar o APK

O app é distribuído como **APK interno** (não vai para a Play Store, que não aceita apps que baixam do YouTube).

**Pelo GitHub Actions (recomendado)**: crie uma tag e envie:

```sh
git tag v1.0.0
git push origin v1.0.0
```

O workflow [`build-apk.yml`](.github/workflows/build-apk.yml) gera os APKs (um por arquitetura) e anexa na página de **Releases**. Na dúvida, instale o `PegaMidia-arm64-v8a-release.apk`. Também dá para rodar o workflow manualmente (aba Actions → "Gerar APK" → Run workflow) e baixar os APKs nos artefatos.

Para assinar com uma chave própria (necessário para instalar atualizações por cima da versão anterior), gere uma keystore **uma vez** e guarde-a com segurança (fora do repositório):

```sh
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
base64 -w0 upload-keystore.jks   # copie a saída
```

Em *Settings → Secrets and variables → Actions*, crie: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` (ex.: `upload`) e `ANDROID_KEY_PASSWORD`. Sem eles, o APK sai assinado com a chave de debug.

**Local**: com Flutter SDK e Android SDK instalados:

```sh
cd app
flutter build apk --release --split-per-abi
# saída em build/app/outputs/flutter-apk/
```

Para assinar localmente, crie `app/android/key.properties` (já está no `.gitignore` — **nunca** commite a keystore nem as senhas):

```properties
storePassword=...
keyPassword=...
keyAlias=upload
storeFile=/caminho/para/upload-keystore.jks
```

### Observações

- Android: o app libera HTTP sem criptografia para conseguir falar com o servidor na rede local (`http://192.168.x.x:8000`); o Android não permite liberar só uma faixa de IPs.
- iOS: compila, mas receber links pelo "Compartilhar" exige configurar uma Share Extension no Xcode (veja a documentação do `receive_sharing_intent`).
- Vídeos com `src` do tipo `blob:` (players MSE) não podem ser baixados direto; nesses casos o app usa a URL `.m3u8` capturada da rede e envia ao servidor.
- O ícone foi gerado por [`tools/gerar_icone.py`](tools/gerar_icone.py) e não usa logos de nenhuma plataforma.

## Licença

[PolyForm Noncommercial 1.0.0](LICENSE): uso, cópia e modificação permitidos para fins **não comerciais** (escolas e instituições educacionais estão expressamente incluídas). Licenças não comerciais não são consideradas "open source" pela OSI, mas o código continua público aqui no GitHub.

O servidor usa o yt-dlp ([Unlicense](https://github.com/yt-dlp/yt-dlp/blob/master/LICENSE)) e o ffmpeg, instalados separadamente.
