import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../app_scope.dart';
import '../models/download_item.dart';
import '../services/link_utils.dart';

/// Vídeo encontrado na página (equivale a uma linha da aba Network do F12).
class VideoCapturado {
  VideoCapturado(this.url, this.tipo);

  final String url;
  final TipoVideo tipo;
  int? tamanho;
}

/// Abre o link num WebView e captura os vídeos que a página carrega —
/// o "truque do F12" (Network → filtrar mp4) feito automaticamente.
/// Funciona sem servidor para MP4; vídeos em pedaços (.m3u8) vão para o servidor.
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key, required this.url});

  final String url;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  /// Lê os <video> da página e a meta og:video; tenta dar play (alguns sites só
  /// carregam o vídeo depois do play).
  static const _jsVideos = '''
(function() {
  var urls = [];
  document.querySelectorAll('video').forEach(function(v) {
    [v.currentSrc, v.src].forEach(function(u) { if (u) urls.push(u); });
    v.querySelectorAll('source').forEach(function(s) { if (s.src) urls.push(s.src); });
    try { v.muted = true; var p = v.play(); if (p && p.catch) p.catch(function() {}); } catch (e) {}
  });
  ['meta[property="og:video"]', 'meta[property="og:video:url"]',
   'meta[property="og:video:secure_url"]', 'meta[name="twitter:player:stream"]'].forEach(function(sel) {
    var m = document.querySelector(sel);
    if (m && m.content) urls.push(m.content);
  });
  return urls;
})();
''';

  static const _jsTitulo = '''
(function() {
  var m = document.querySelector('meta[property="og:title"]');
  return (m && m.content) || document.title || '';
})();
''';

  InAppWebViewController? _controlador;
  Timer? _varredura;
  final Map<String, VideoCapturado> _videos = {};
  final Dio _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));
  double _carregamento = 0;
  String _pagina = '';
  String? _titulo;
  String? _userAgent;
  late final DateTime _inicio = DateTime.now();

  @override
  void initState() {
    super.initState();
    _pagina = widget.url;
    _varredura = Timer.periodic(const Duration(milliseconds: 1500), (_) => _varrerPagina());
  }

  @override
  void dispose() {
    _varredura?.cancel();
    _dio.close(force: true);
    super.dispose();
  }

  void _anotar(String? url, {String? contentType}) {
    if (url == null || _videos.containsKey(url)) return;
    final tipo = classificarUrlVideo(url, contentType: contentType);
    if (tipo == null) return;
    final video = VideoCapturado(url, tipo);
    if (!mounted) return;
    setState(() => _videos[url] = video);
    if (!tipo.emPedacos) unawaited(_medir(video));
  }

  Future<void> _varrerPagina() async {
    final c = _controlador;
    if (c == null || !mounted) return;
    try {
      final resultado = await c.evaluateJavascript(source: _jsVideos);
      final atual = (await c.getUrl())?.toString();
      if (atual != null && atual.startsWith('http')) _pagina = atual;
      if (resultado is List) {
        for (final u in resultado) {
          if (u is String) {
            final absoluta = Uri.parse(_pagina).resolve(u).toString();
            // <video src> sem extensão conhecida: provavelmente MP4.
            if (classificarUrlVideo(absoluta) == null && !absoluta.startsWith('blob:') && absoluta.startsWith('http')) {
              _anotar(absoluta, contentType: 'video/mp4');
            } else {
              _anotar(absoluta);
            }
          }
        }
      }
    } catch (_) {
      // página ainda carregando
    }
    if (mounted) setState(() {}); // atualiza o aviso de "ainda procurando"
  }

  Map<String, String> _cabecalhosBasicos() => {
        'User-Agent': ?_userAgent,
        'Referer': _pagina,
      };

  /// Tamanho estimado: lê o Content-Length (ou Content-Range) sem baixar o vídeo todo.
  Future<void> _medir(VideoCapturado video) async {
    try {
      final r = await _dio.get<ResponseBody>(
        video.url,
        options: Options(
          headers: {..._cabecalhosBasicos(), 'Range': 'bytes=0-0'},
          responseType: ResponseType.stream,
          receiveTimeout: const Duration(seconds: 10),
          validateStatus: (s) => s != null && s < 400,
        ),
      );
      final faixa = r.headers.value('content-range');
      final tamanho = faixa != null
          ? int.tryParse(faixa.split('/').last)
          : int.tryParse(r.headers.value('content-length') ?? '');
      unawaited(r.data?.stream.listen((_) {}).cancel());
      if (mounted && tamanho != null && tamanho > 1) setState(() => video.tamanho = tamanho);
    } catch (_) {
      // sem tamanho: tudo bem
    }
  }

  Future<Map<String, String>> _cabecalhosCompletos(String videoUrl) async {
    final cabecalhos = _cabecalhosBasicos();
    try {
      final cookies = await CookieManager.instance().getCookies(url: WebUri(videoUrl));
      if (cookies.isNotEmpty) {
        cabecalhos['Cookie'] = cookies.map((c) => '${c.name}=${c.value}').join('; ');
      }
    } catch (_) {}
    return cabecalhos;
  }

  Future<String> _tituloDaPagina() async {
    try {
      final t = await _controlador?.evaluateJavascript(source: _jsTitulo);
      if (t is String && t.trim().isNotEmpty) return t.trim();
    } catch (_) {}
    return _titulo ?? 'Vídeo da página';
  }

  Future<void> _baixar(VideoCapturado video, {bool soAudio = false}) async {
    final scope = AppScope.of(context);
    final titulo = await _tituloDaPagina();
    if (!mounted) return;

    if (video.tipo.emPedacos || soAudio) {
      if (!scope.settings.temServidor) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Precisa do servidor'),
            content: Text(soAudio
                ? 'Para tirar só o áudio é preciso o servidor ligado. Configure o endereço em Configurações.'
                : 'Este vídeo vem em pedaços (${video.tipo.name.toUpperCase()}). Para juntar tudo num MP4 '
                    'é preciso o servidor ligado. Configure o endereço em Configurações.'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Ok'))],
          ),
        );
        return;
      }
      scope.downloads.baixarPeloServidor(
        url: video.url,
        tipo: soAudio ? TipoMidia.audio : TipoMidia.video,
        qualidade: 'melhor',
        titulo: titulo,
        referer: _pagina,
      );
    } else {
      final cabecalhos = await _cabecalhosCompletos(video.url);
      scope.downloads.baixarDireto(
        videoUrl: video.url,
        pagina: _pagina,
        titulo: titulo,
        cabecalhos: cabecalhos,
        extensao: video.tipo == TipoVideo.mov ? 'mov' : video.tipo.name,
      );
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  List<VideoCapturado> get _ordenados => _videos.values.toList()
    ..sort((a, b) {
      final p = a.tipo.preferencia.compareTo(b.tipo.preferencia);
      return p != 0 ? p : (b.tamanho ?? 0).compareTo(a.tamanho ?? 0);
    });

  @override
  Widget build(BuildContext context) {
    final temServidor = AppScope.of(context).settings.temServidor;
    return Scaffold(
      appBar: AppBar(
        title: Text(_videos.isEmpty ? 'Procurando vídeo…' : 'Vídeos encontrados: ${_videos.length}'),
        bottom: _carregamento < 1
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(value: _carregamento == 0 ? null : _carregamento),
              )
            : null,
        actions: [
          IconButton(
            tooltip: 'Recarregar',
            icon: const Icon(Icons.refresh),
            onPressed: () => _controlador?.reload(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(widget.url)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                mediaPlaybackRequiresUserGesture: false,
                allowsInlineMediaPlayback: true,
                useOnLoadResource: true,
                useShouldInterceptRequest: true,
                useShouldOverrideUrlLoading: true,
              ),
              onWebViewCreated: (c) async {
                _controlador = c;
                try {
                  final ua = await c.evaluateJavascript(source: 'navigator.userAgent');
                  if (ua is String) _userAgent = ua;
                } catch (_) {}
              },
              // Não deixa a página abrir o app da loja (shopee://, intent://…).
              shouldOverrideUrlLoading: (c, acao) async {
                final esquema = acao.request.url?.scheme ?? '';
                return (esquema == 'http' || esquema == 'https' || esquema == 'about' || esquema == 'data')
                    ? NavigationActionPolicy.ALLOW
                    : NavigationActionPolicy.CANCEL;
              },
              onLoadResource: (c, recurso) => _anotar(recurso.url?.toString()),
              shouldInterceptRequest: (c, pedido) async {
                _anotar(pedido.url.toString());
                return null; // não altera a requisição; só observa
              },
              onProgressChanged: (c, p) => setState(() => _carregamento = p / 100),
              onTitleChanged: (c, t) => _titulo = t,
              onLoadStop: (c, url) async {
                if (url != null) _pagina = url.toString();
                _userAgent ??= await c.evaluateJavascript(source: 'navigator.userAgent') as String?;
                await _varrerPagina();
              },
            ),
          ),
          _painel(temServidor),
        ],
      ),
    );
  }

  Widget _painel(bool temServidor) {
    final tema = Theme.of(context);
    final segundos = DateTime.now().difference(_inicio).inSeconds;
    return Material(
      elevation: 8,
      color: tema.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: _videos.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(segundos < 20
                            ? 'Procurando vídeo na página… Se aparecer um vídeo, toque no play.'
                            : 'Ainda não achei. Toque no play do vídeo ou role a página. '
                                'Se não houver vídeo, volte e tente outro link.'),
                      ),
                    ],
                  ),
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final v in _ordenados)
                      ListTile(
                        leading: Icon(v.tipo.emPedacos ? Icons.view_module : Icons.movie),
                        title: Text([
                          v.tipo.name.toUpperCase(),
                          if (v.tamanho != null) formatarTamanho(v.tamanho),
                          if (v.tipo.emPedacos) '(via servidor)',
                        ].join(' • ')),
                        subtitle: Text(Uri.tryParse(v.url)?.host ?? v.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (temServidor)
                              IconButton(
                                tooltip: 'Só o áudio (pelo servidor)',
                                icon: const Icon(Icons.music_note),
                                onPressed: () => _baixar(v, soAudio: true),
                              ),
                            FilledButton(onPressed: () => _baixar(v), child: const Text('Baixar')),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
