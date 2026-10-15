import 'package:flutter_test/flutter_test.dart';
import 'package:pegamidia/services/link_utils.dart';

void main() {
  group('extrairUrl', () {
    test('acha o link dentro do texto compartilhado', () {
      expect(extrairUrl('Olha esse produto! https://br.shp.ee/AbCd123?x=1. Corre!'),
          'https://br.shp.ee/AbCd123?x=1');
      expect(extrairUrl('https://youtu.be/abc'), 'https://youtu.be/abc');
    });

    test('retorna null sem link', () {
      expect(extrairUrl('sem link'), isNull);
      expect(extrairUrl(null), isNull);
      expect(extrairUrl('ftp://a.com'), isNull);
    });
  });

  test('detectarSite', () {
    expect(detectarSite('https://www.youtube.com/watch?v=1'), Site.youtube);
    expect(detectarSite('https://music.youtube.com/watch?v=1'), Site.youtubeMusic);
    expect(detectarSite('https://vm.tiktok.com/ZMabc/'), Site.tiktok);
    expect(detectarSite('https://x.com/a/status/1'), Site.twitter);
    expect(detectarSite('https://fb.watch/abc'), Site.facebook);
    expect(detectarSite('https://www.instagram.com/reel/abc'), Site.instagram);
    expect(detectarSite('https://br.shp.ee/abc'), Site.shopee);
    expect(detectarSite('https://shopee.com.br/x-i.1.2'), Site.shopee);
    expect(detectarSite('https://www.kwai.com/@a/video/1'), Site.kwai);
    expect(detectarSite('https://notyoutube.com/'), Site.outro);
    expect(Site.shopee.usaCapturaNaPagina, isTrue);
    expect(Site.youtube.usaCapturaNaPagina, isFalse);
  });

  group('classificarUrlVideo', () {
    test('reconhece vídeos como na aba Network', () {
      expect(classificarUrlVideo('https://down-bs-sg.vod.susercontent.com/api/v4/a/mms/b.16000081.mp4'),
          TipoVideo.mp4);
      expect(classificarUrlVideo('https://cdn.x/master.m3u8?token=1'), TipoVideo.m3u8);
      expect(classificarUrlVideo('https://cdn.x/a.webm'), TipoVideo.webm);
      expect(classificarUrlVideo('https://cdn.x/api', contentType: 'video/mp4; charset=x'), TipoVideo.mp4);
    });

    test('ignora blob, pedaços e imagens', () {
      expect(classificarUrlVideo('blob:https://shopee.com.br/1'), isNull);
      expect(classificarUrlVideo('https://cdn.x/seg-1.ts'), isNull);
      expect(classificarUrlVideo('https://cdn.x/a.jpg'), isNull);
    });

    test('m3u8 precisa do servidor; mp4 não', () {
      expect(TipoVideo.m3u8.emPedacos, isTrue);
      expect(TipoVideo.mp4.emPedacos, isFalse);
    });
  });

  test('limparNomeArquivo', () {
    expect(limparNomeArquivo('Presente: "bingo"/2 '), 'Presente bingo 2');
    expect(limparNomeArquivo('...'), 'video');
    expect(limparNomeArquivo('a' * 200).length, 80);
  });

  test('normalizarEnderecoServidor', () {
    expect(normalizarEnderecoServidor('192.168.0.10:8000'), 'http://192.168.0.10:8000');
    expect(normalizarEnderecoServidor(' http://192.168.0.10:8000/ '), 'http://192.168.0.10:8000');
    expect(normalizarEnderecoServidor('https://pega.escola.br'), 'https://pega.escola.br');
    expect(normalizarEnderecoServidor(''), isNull);
    expect(normalizarEnderecoServidor('ftp://x'), isNull);
  });

  test('formatarTamanho e formatarDuracao', () {
    expect(formatarTamanho(26 * 1024 * 1024), '26,0 MB');
    expect(formatarTamanho(null), '');
    expect(formatarDuracao(75), '1:15');
    expect(formatarDuracao(3725), '1:02:05');
  });
}
