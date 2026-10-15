/// Funções puras sobre links: achar o link num texto, detectar o site e
/// reconhecer URLs de vídeo capturadas pelo WebView.
library;

enum Site {
  youtubeMusic('YouTube Music'),
  youtube('YouTube'),
  facebook('Facebook'),
  twitter('X / Twitter'),
  tiktok('TikTok'),
  instagram('Instagram'),
  kwai('Kwai'),
  shopee('Shopee'),
  outro('Outro site');

  const Site(this.nome);
  final String nome;

  /// Sites sem extrator no yt-dlp: o app procura o vídeo direto na página (WebView).
  bool get usaCapturaNaPagina => this == Site.kwai || this == Site.shopee;
}

const Map<Site, List<String>> _dominios = {
  Site.youtubeMusic: ['music.youtube.com'],
  Site.youtube: ['youtube.com', 'youtu.be', 'youtube-nocookie.com'],
  Site.facebook: ['facebook.com', 'fb.watch', 'fb.com'],
  Site.twitter: ['twitter.com', 'x.com', 't.co'],
  Site.tiktok: ['tiktok.com'],
  Site.instagram: ['instagram.com', 'instagr.am'],
  Site.kwai: ['kwai.com', 'kw.ai', 'kwai-video.com', 'kwai.net'],
  Site.shopee: ['shopee.com.br', 'shp.ee', 'shopee.com', 'shopee.sg'],
};

final RegExp _urlNoTexto = RegExp(r'''https?://[^\s<>"']+''', caseSensitive: false);

/// Acha o primeiro link num texto (ex.: "Olha esse produto! https://br.shp.ee/abc").
String? extrairUrl(String? texto) {
  if (texto == null) return null;
  final achado = _urlNoTexto.firstMatch(texto);
  if (achado == null) return null;
  var url = achado.group(0)!;
  while (url.isNotEmpty && '.,;:!?)]}'.contains(url[url.length - 1])) {
    url = url.substring(0, url.length - 1);
  }
  return Uri.tryParse(url)?.hasAuthority == true ? url : null;
}

Site detectarSite(String url) {
  final host = (Uri.tryParse(url)?.host ?? '').toLowerCase();
  for (final entrada in _dominios.entries) {
    for (final dominio in entrada.value) {
      if (host == dominio || host.endsWith('.$dominio')) return entrada.key;
    }
  }
  return Site.outro;
}

/// Tipos de vídeo que a captura reconhece.
enum TipoVideo {
  mp4,
  mov,
  m3u8,
  webm,
  mpd;

  /// MP4/MOV/WebM: arquivo inteiro, dá para baixar direto no celular.
  /// M3U8/MPD: vídeo em pedaços; precisa do servidor (ffmpeg) para virar MP4.
  bool get emPedacos => this == TipoVideo.m3u8 || this == TipoVideo.mpd;

  int get preferencia => switch (this) {
        TipoVideo.mp4 => 0,
        TipoVideo.mov => 1,
        TipoVideo.m3u8 => 2,
        TipoVideo.webm => 3,
        TipoVideo.mpd => 4,
      };
}

final RegExp _extensaoVideo = RegExp(r'\.(mp4|m3u8|webm|mov|mpd)(?:$|[?#&])', caseSensitive: false);
final RegExp _segmento = RegExp(r'\.(ts|m4s|aac|m4a)(?:$|[?#&])', caseSensitive: false);

const Map<String, TipoVideo> _tiposConteudo = {
  'video/mp4': TipoVideo.mp4,
  'video/webm': TipoVideo.webm,
  'video/quicktime': TipoVideo.mov,
  'application/vnd.apple.mpegurl': TipoVideo.m3u8,
  'application/x-mpegurl': TipoVideo.m3u8,
  'audio/mpegurl': TipoVideo.m3u8,
  'application/dash+xml': TipoVideo.mpd,
};

/// Equivalente a filtrar "mp4" na aba Network do F12: diz se a URL é um vídeo.
/// Ignora `blob:` (players MSE) e pedaços soltos (.ts/.m4s).
TipoVideo? classificarUrlVideo(String url, {String? contentType}) {
  if (url.isEmpty || url.startsWith('blob:') || url.startsWith('data:')) return null;
  if (contentType != null) {
    final tipo = _tiposConteudo[contentType.split(';').first.trim().toLowerCase()];
    if (tipo != null) return tipo;
  }
  if (_segmento.hasMatch(url)) return null;
  final achado = _extensaoVideo.firstMatch(url);
  if (achado == null) return null;
  return TipoVideo.values.byName(achado.group(1)!.toLowerCase());
}

/// Nome de arquivo seguro para qualquer sistema.
String limparNomeArquivo(String nome, {int maximo = 80}) {
  var limpo = nome.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f%]+'), ' ');
  limpo = limpo.replaceAll(RegExp(r'\s+'), ' ').trim();
  while (limpo.endsWith('.')) {
    limpo = limpo.substring(0, limpo.length - 1).trim();
  }
  if (limpo.length > maximo) limpo = limpo.substring(0, maximo).trim();
  return limpo.isEmpty ? 'video' : limpo;
}

/// Normaliza o endereço digitado em Configurações ("192.168.0.10:8000" → "http://192.168.0.10:8000").
String? normalizarEnderecoServidor(String texto) {
  var t = texto.trim();
  if (t.isEmpty) return null;
  if (!t.contains('://')) t = 'http://$t';
  final uri = Uri.tryParse(t);
  if (uri == null || uri.host.isEmpty || !(uri.scheme == 'http' || uri.scheme == 'https')) {
    return null;
  }
  final porta = uri.hasPort ? ':${uri.port}' : '';
  final caminho = uri.path.endsWith('/') ? uri.path.substring(0, uri.path.length - 1) : uri.path;
  return '${uri.scheme}://${uri.host}$porta$caminho';
}

String formatarTamanho(int? bytes) {
  if (bytes == null || bytes <= 0) return '';
  const unidades = ['B', 'KB', 'MB', 'GB'];
  var valor = bytes.toDouble();
  var i = 0;
  while (valor >= 1024 && i < unidades.length - 1) {
    valor /= 1024;
    i++;
  }
  final casas = i >= 2 ? 1 : 0;
  return '${valor.toStringAsFixed(casas).replaceAll('.', ',')} ${unidades[i]}';
}

String formatarDuracao(num? segundos) {
  if (segundos == null || segundos <= 0) return '';
  final total = segundos.round();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}
