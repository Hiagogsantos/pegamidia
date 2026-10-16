import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pegamidia/models/download_item.dart';
import 'package:pegamidia/models/media_info.dart';
import 'package:pegamidia/services/download_manager.dart';
import 'package:pegamidia/services/server_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Simula o servidor PegaMídia (e um site com MP4) sem rede.
class ServidorFalso implements HttpClientAdapter {
  ServidorFalso({this.statusAntesDePronto = 2, this.erro});

  final int statusAntesDePronto;
  final String? erro;
  int consultas = 0;
  final pedidos = <RequestOptions>[];

  ResponseBody _json(Object corpo, [int codigo = 200]) => ResponseBody.fromString(
        jsonEncode(corpo),
        codigo,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    pedidos.add(options);
    final caminho = options.uri.path;
    if (caminho == '/download') return _json({'job_id': 'abc123'});
    if (caminho == '/status/abc123') {
      consultas++;
      if (erro != null) return _json({'estado': 'erro', 'progresso': 0, 'mensagem': erro});
      final pronto = consultas > statusAntesDePronto;
      return _json({
        'estado': pronto ? 'concluido' : 'baixando',
        'progresso': pronto ? 100 : 50,
        'mensagem': pronto ? 'Pronto!' : 'Baixando…',
        'titulo': 'Aula de ciências',
        'nome_arquivo': pronto ? 'Aula de ciências.mp4' : null,
        'tamanho': pronto ? 4 : null,
      });
    }
    if (caminho == '/imagem.mp4') return ResponseBody.fromBytes(List.filled(30, 1), 200);
    if (caminho == '/som.mp4') return ResponseBody.fromBytes(List.filled(10, 2), 200);
    if (caminho == '/arquivo/abc123' || caminho == '/video.mp4') {
      return ResponseBody.fromBytes([1, 2, 3, 4], 200, headers: {
        Headers.contentLengthHeader: ['4'],
      });
    }
    if (caminho == '/info') return _json({'detail': 'Não consegui achar vídeo nesta página.'}, 422);
    return _json({'detail': 'Não encontrado'}, 404);
  }

  @override
  void close({bool force = false}) {}
}

typedef JuntarFalso = Future<void> Function(String video, String audio, String saida);

void main() {
  late Directory pasta;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    pasta = await Directory.systemTemp.createTemp('pegamidia_teste');
  });

  tearDown(() => pasta.delete(recursive: true));

  Future<(DownloadManager, ServidorFalso)> criar({String? erro, JuntarFalso? juntar}) async {
    final falso = ServidorFalso(erro: erro);
    final dio = Dio()..httpClientAdapter = falso;
    final api = ServerApi(() => 'http://192.168.0.10:8000', dio: dio);
    final prefs = await SharedPreferences.getInstance();
    final manager = DownloadManager(api, prefs, dio: dio, pasta: () async => pasta, juntar: juntar);
    return (manager, falso);
  }

  Future<void> esperarFim(DownloadManager m) async {
    for (var i = 0; i < 100 && m.itens.any((i) => i.emAndamento); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  test('baixa pelo servidor: cria tarefa, acompanha status e transfere o arquivo', () async {
    final (m, falso) = await criar();
    m.baixarPeloServidor(url: 'https://youtu.be/abc', tipo: TipoMidia.video, tituloExibicao: 'Prévia');
    await esperarFim(m);

    final item = m.itens.single;
    expect(item.estado, EstadoDownload.concluido, reason: item.mensagem);
    expect(item.titulo, 'Aula de ciências');
    expect(item.caminho, endsWith('PegaMidia/Aula de ciências.mp4'));
    expect(File(item.caminho!).lengthSync(), 4);
    final pedido = falso.pedidos.firstWhere((p) => p.uri.path == '/download');
    expect(pedido.data, containsPair('qualidade', '720p'));
    expect((pedido.data as Map).containsKey('titulo'), isFalse);
  });

  test('mostra o erro do servidor', () async {
    final (m, _) = await criar(erro: 'Vídeo indisponível ou removido.');
    m.baixarPeloServidor(url: 'https://youtu.be/abc', tipo: TipoMidia.audio);
    await esperarFim(m);
    expect(m.itens.single.estado, EstadoDownload.erro);
    expect(m.itens.single.mensagem, 'Vídeo indisponível ou removido.');
  });

  test('baixa direto da página com Referer e não sobrescreve arquivo', () async {
    final (m, falso) = await criar();
    for (var i = 0; i < 2; i++) {
      m.baixarDireto(
        videoUrl: 'https://cdn.exemplo.com/video.mp4',
        pagina: 'https://shopee.com.br/produto',
        titulo: 'Caneca: presente',
        cabecalhos: {'Referer': 'https://shopee.com.br/produto'},
      );
      await esperarFim(m);
    }
    final nomes = m.itens.map((i) => i.caminho!.split('/').last).toSet();
    expect(nomes, {'Caneca presente.mp4', 'Caneca presente (2).mp4'});
    expect(falso.pedidos.last.headers['Referer'], 'https://shopee.com.br/produto');
  });

  test('Instagram: baixa imagem e som separados e junta num MP4', () async {
    String? juntouVideo;
    String? juntouAudio;
    final (m, falso) = await criar(juntar: (video, audio, saida) async {
      juntouVideo = video;
      juntouAudio = audio;
      expect(File(video).lengthSync(), 30);
      expect(File(audio).lengthSync(), 10);
      File(saida).writeAsBytesSync([...File(video).readAsBytesSync(), ...File(audio).readAsBytesSync()]);
    });
    m.baixarDiretoComAudio(
      videoUrl: 'https://instagram.fna.fbcdn.net/imagem.mp4',
      audioUrl: 'https://instagram.fna.fbcdn.net/som.mp4',
      pagina: 'https://www.instagram.com/reel/abc/',
      titulo: 'Tesoura de cozinha',
      cabecalhos: {'Referer': 'https://www.instagram.com/'},
    );
    await esperarFim(m);

    final item = m.itens.single;
    expect(item.estado, EstadoDownload.concluido, reason: item.mensagem);
    expect(item.caminho, endsWith('PegaMidia/Tesoura de cozinha.mp4'));
    expect(item.tamanho, 40);
    expect(juntouVideo, endsWith('video.mp4'));
    expect(juntouAudio, endsWith('audio.mp4'));
    // os arquivos temporários são apagados
    expect(Directory('${pasta.path}/PegaMidia/.temporario/${item.id}').existsSync(), isFalse);
    expect(falso.pedidos.where((p) => p.headers['Referer'] == 'https://www.instagram.com/').length, 2);
  });

  test('Instagram: se não der para juntar, salva a imagem e avisa que está sem som', () async {
    final (m, _) = await criar(juntar: (_, _, _) async => throw MissingPluginException());
    m.baixarDiretoComAudio(
      videoUrl: 'https://instagram.fna.fbcdn.net/imagem.mp4',
      audioUrl: 'https://instagram.fna.fbcdn.net/som.mp4',
      pagina: 'https://www.instagram.com/reel/abc/',
      titulo: 'Reel',
    );
    await esperarFim(m);
    final item = m.itens.single;
    expect(item.estado, EstadoDownload.concluido);
    expect(item.titulo, 'Reel (sem som)');
    expect(item.tamanho, 30);
  });

  test('salva e recarrega a lista; download interrompido vira erro', () async {
    final (m, _) = await criar();
    m.baixarPeloServidor(url: 'https://youtu.be/abc', tipo: TipoMidia.video);
    await esperarFim(m);
    final prefs = await SharedPreferences.getInstance();
    final lista = jsonDecode(prefs.getString('downloads')!) as List;
    lista.add({
      'id': 'x',
      'titulo': 'Interrompido',
      'urlOrigem': 'u',
      'tipo': 'video',
      'origem': 'servidor',
      'criadoEm': DateTime.now().toIso8601String(),
      'estado': 'servidor',
    });
    await prefs.setString('downloads', jsonEncode(lista));

    final (outro, _) = await criar();
    await outro.carregar();
    expect(outro.itens.length, 2);
    expect(outro.itens.first.estado, EstadoDownload.concluido);
    expect(outro.itens.last.estado, EstadoDownload.erro);
  });

  test('ServerApi traduz o detail do servidor', () async {
    final dio = Dio()..httpClientAdapter = ServidorFalso();
    final api = ServerApi(() => 'http://192.168.0.10:8000', dio: dio);
    expect(
      () => api.info('https://exemplo.com'),
      throwsA(isA<ApiException>().having((e) => e.mensagem, 'mensagem', 'Não consegui achar vídeo nesta página.')),
    );
    expect(() => ServerApi(() => null).info('https://x.com'), throwsA(isA<ServidorNaoConfigurado>()));
  });

  test('servidor desligado vira ServidorIndisponivel', () {
    final erro = ServerApi.traduzirErro(
        DioException.connectionError(requestOptions: RequestOptions(), reason: 'recusado'));
    expect(erro, isA<ServidorIndisponivel>());
    expect(erro.mensagem, startsWith('Servidor não encontrado'));
  });

  test('MediaInfo estima o tamanho pela qualidade', () {
    final info = MediaInfo.fromJson({
      'titulo': 'A',
      'site_nome': 'YouTube',
      'formatos': [
        {'altura': 360, 'tamanho_aprox': 10},
        {'altura': 720, 'tamanho_aprox': 30},
        {'altura': 1080, 'tamanho_aprox': 90},
      ],
    });
    expect(info.tamanhoEstimado('720p'), 30);
    expect(info.tamanhoEstimado('480p'), 10);
    expect(info.tamanhoEstimado('melhor'), 90);
  });
}
