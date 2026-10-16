/// Vídeos do Instagram e do Facebook (CDN `fbcdn.net` / `cdninstagram.com`).
///
/// O player dessas redes não usa um MP4 único: ele baixa a imagem e o som em
/// arquivos separados (DASH) e pede cada arquivo em pedaços, com `bytestart` e
/// `byteend` na URL. Por isso a captura via várias "MP4" que não são o vídeo inteiro.
/// Aqui: tirar os pedaços da URL (vira o arquivo inteiro), descobrir se cada
/// arquivo é só imagem ou só som, e depois juntar os dois (ver `juntar_midia.dart`).
library;

import 'dart:convert';

/// O que um arquivo MP4 contém.
enum TrilhaMidia { videoEAudio, soVideo, soAudio }

bool ehCdnMeta(String url) {
  final host = (Uri.tryParse(url)?.host ?? '').toLowerCase();
  return host.endsWith('fbcdn.net') || host.endsWith('cdninstagram.com');
}

/// Remove `bytestart`/`byteend` das URLs do Instagram/Facebook: sem eles, a CDN
/// entrega o arquivo inteiro em vez de um pedaço.
String normalizarUrlVideo(String url) {
  if (!ehCdnMeta(url)) return url;
  final inicioQuery = url.indexOf('?');
  if (inicioQuery < 0) return url;
  final inicioFragmento = url.indexOf('#', inicioQuery);
  final fim = inicioFragmento < 0 ? url.length : inicioFragmento;
  final parametros = url.substring(inicioQuery + 1, fim).split('&').where((p) {
    final chave = p.split('=').first;
    return p.isNotEmpty && chave != 'bytestart' && chave != 'byteend';
  }).toList();
  final base = url.substring(0, inicioQuery);
  final fragmento = inicioFragmento < 0 ? '' : url.substring(inicioFragmento);
  return parametros.isEmpty ? '$base$fragmento' : '$base?${parametros.join('&')}$fragmento';
}

/// Palpite rápido pelo parâmetro `efg` da URL (JSON em base64 com o `vencode_tag`,
/// ex.: `...dash_baseline_1_v1` para imagem e `...dash_ln_heaac_vbr3_audio` para som).
TrilhaMidia? trilhaPelaUrl(String url) {
  if (!ehCdnMeta(url)) return null;
  final efg = Uri.tryParse(url)?.queryParameters['efg'];
  if (efg == null || efg.isEmpty) return null;
  try {
    final json = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(efg))));
    final tag = (json is Map ? json['vencode_tag'] : null)?.toString().toLowerCase() ?? '';
    if (tag.contains('audio')) return TrilhaMidia.soAudio;
    if (tag.contains('dash')) return TrilhaMidia.soVideo;
  } catch (_) {
    // efg em outro formato: decide pelo conteúdo do arquivo
  }
  return null;
}

/// Resultado da leitura do começo de um MP4.
class InfoMp4 {
  const InfoMp4({required this.temVideo, required this.temAudio, this.largura, this.altura});

  final bool temVideo;
  final bool temAudio;
  final int? largura;
  final int? altura;

  TrilhaMidia get trilha => temVideo && temAudio
      ? TrilhaMidia.videoEAudio
      : temVideo
          ? TrilhaMidia.soVideo
          : TrilhaMidia.soAudio;

  String? get resolucao => (largura != null && altura != null) ? '$largura×$altura' : null;
}

bool _caixa(List<int> b, int i, String nome) =>
    b[i] == nome.codeUnitAt(0) &&
    b[i + 1] == nome.codeUnitAt(1) &&
    b[i + 2] == nome.codeUnitAt(2) &&
    b[i + 3] == nome.codeUnitAt(3);

int _u32(List<int> b, int i) => (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];

/// Lê os primeiros bytes de um MP4 (o cabeçalho `moov`) e diz se há trilha de
/// imagem (`hdlr` = `vide`), de som (`soun`) e o tamanho da imagem (`tkhd`).
/// Retorna `null` se o cabeçalho não estiver nesses bytes.
InfoMp4? analisarInicioMp4(List<int> b) {
  var video = false;
  var audio = false;
  int? largura;
  int? altura;
  for (var i = 4; i + 16 <= b.length; i++) {
    if (_caixa(b, i, 'hdlr')) {
      // hdlr: tipo(4) versão/flags(4) pre_defined(4) handler_type(4)
      final tipo = String.fromCharCodes(b.sublist(i + 12, i + 16));
      if (tipo == 'vide') video = true;
      if (tipo == 'soun') audio = true;
    } else if (_caixa(b, i, 'tkhd')) {
      // largura/altura em ponto fixo 16.16 no fim da caixa (posição depende da versão)
      final inicioCaixa = i - 4;
      final posicao = inicioCaixa + (b[i + 4] == 1 ? 96 : 84);
      if (posicao + 8 <= b.length) {
        final w = _u32(b, posicao) >> 16;
        final h = _u32(b, posicao + 4) >> 16;
        if (w > 0 && h > 0) {
          largura = w;
          altura = h;
        }
      }
    }
  }
  if (!video && !audio) return null;
  return InfoMp4(temVideo: video, temAudio: audio, largura: largura, altura: altura);
}
