import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pegamidia/services/midia_dash.dart';

/// URL no formato das que o player do Instagram pede (vencode_tag dentro do efg).
String urlInstagram(String vencodeTag, {String pedaco = '&bytestart=0&byteend=1023'}) {
  final efg = base64Url.encode(utf8.encode(jsonEncode({'vencode_tag': vencodeTag, 'video_id': null})));
  return 'https://instagram.frec52-1.fna.fbcdn.net/o1/v/t16/f2/m86/AQabc.mp4'
      '?efg=${Uri.encodeQueryComponent(efg)}&_nc_ht=instagram.frec52-1.fna.fbcdn.net&oh=00_x&oe=6720$pedaco';
}

void main() {
  group('normalizarUrlVideo', () {
    test('tira bytestart/byteend do Instagram: os pedaços viram um arquivo só', () {
      final a = normalizarUrlVideo(urlInstagram('dash_baseline_1_v1', pedaco: '&bytestart=0&byteend=1023'));
      final b = normalizarUrlVideo(urlInstagram('dash_baseline_1_v1', pedaco: '&bytestart=1024&byteend=99999'));
      expect(a, b);
      expect(a, isNot(contains('bytestart')));
      expect(a, isNot(contains('byteend')));
      expect(a, contains('oh=00_x&oe=6720'));
    });

    test('mantém a ordem e a codificação dos outros parâmetros', () {
      expect(
        normalizarUrlVideo('https://video.xx.fbcdn.net/v/a.mp4?bytestart=5&_nc_cat=1&efg=ab%3D%3D&byteend=9#x'),
        'https://video.xx.fbcdn.net/v/a.mp4?_nc_cat=1&efg=ab%3D%3D#x',
      );
      expect(normalizarUrlVideo('https://scontent.cdninstagram.com/v.mp4?bytestart=0&byteend=1'),
          'https://scontent.cdninstagram.com/v.mp4');
    });

    test('não mexe em URLs de outros sites', () {
      const shopee = 'https://down-bs-sg.vod.susercontent.com/a.mp4?bytestart=0&byteend=10';
      expect(normalizarUrlVideo(shopee), shopee);
    });
  });

  test('trilhaPelaUrl lê o vencode_tag do efg', () {
    expect(trilhaPelaUrl(urlInstagram('ig-xpvds.clips.c2-C3.dash_baseline_1_v1')), TrilhaMidia.soVideo);
    expect(trilhaPelaUrl(urlInstagram('ig-xpvds.clips.c2-C3.dash_ln_heaac_vbr3_audio')), TrilhaMidia.soAudio);
    expect(trilhaPelaUrl(urlInstagram('xpv_progressive.INSTAGRAM.CLIPS')), isNull);
    expect(trilhaPelaUrl('https://video.xx.fbcdn.net/a.mp4?efg=nao-e-base64!'), isNull);
    expect(trilhaPelaUrl('https://exemplo.com/a.mp4'), isNull);
  });

  group('analisarInicioMp4 (arquivos gerados com ffmpeg)', () {
    List<int> inicio(String nome) {
      final bytes = File('test/fixtures/$nome').readAsBytesSync();
      return bytes.length > 65536 ? bytes.sublist(0, 65536) : bytes;
    }

    test('MP4 em pedaços só com imagem (como o Instagram)', () {
      final info = analisarInicioMp4(inicio('so_video_dash.mp4'))!;
      expect(info.trilha, TrilhaMidia.soVideo);
      expect(info.resolucao, '64×112');
    });

    test('MP4 em pedaços só com som', () {
      final info = analisarInicioMp4(inicio('so_audio_dash.mp4'))!;
      expect(info.trilha, TrilhaMidia.soAudio);
      expect(info.resolucao, isNull);
    });

    test('MP4 normal com imagem e som', () {
      final info = analisarInicioMp4(inicio('video_e_audio.mp4'))!;
      expect(info.trilha, TrilhaMidia.videoEAudio);
      expect(info.resolucao, '96×64');
    });

    test('bytes que não são MP4', () {
      expect(analisarInicioMp4(utf8.encode('<html>não é vídeo</html>')), isNull);
      expect(analisarInicioMp4(const []), isNull);
    });
  });
}
