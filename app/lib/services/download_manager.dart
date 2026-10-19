import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/download_item.dart';
import 'juntar_midia.dart';
import 'link_utils.dart';
import 'server_api.dart';

/// Guarda a lista de downloads e executa cada um (pelo servidor ou direto da página).
class DownloadManager extends ChangeNotifier {
  DownloadManager(this._api, this._prefs,
      {Dio? dio, Future<Directory> Function()? pasta, JuntarVideoEAudio? juntar})
      : _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 20))),
        _pastaBase = pasta ?? getApplicationDocumentsDirectory,
        _juntar = juntar ?? juntarNoAparelho;

  static const _chave = 'downloads';
  static const _intervaloStatus = Duration(seconds: 1);

  final ServerApi _api;
  final SharedPreferences _prefs;
  final Dio _dio;
  final Future<Directory> Function() _pastaBase;
  final JuntarVideoEAudio _juntar;
  final List<DownloadItem> _itens = [];
  final Map<String, CancelToken> _cancelar = {};

  /// Mais recentes primeiro.
  List<DownloadItem> get itens => List.unmodifiable(_itens);

  int get emAndamento => _itens.where((i) => i.emAndamento).length;

  Future<void> carregar() async {
    final bruto = _prefs.getString(_chave);
    if (bruto == null) return;
    try {
      final lista = jsonDecode(bruto) as List;
      _itens
        ..clear()
        ..addAll(lista.map((e) => DownloadItem.fromJson(Map<String, dynamic>.from(e as Map))));
    } catch (_) {
      _itens.clear();
    }
    for (final item in _itens) {
      if (item.emAndamento) {
        // O app foi fechado no meio do download.
        item
          ..estado = EstadoDownload.erro
          ..mensagem = 'Interrompido. Baixe de novo.';
      } else if (item.estado == EstadoDownload.concluido &&
          (item.caminho == null || !File(item.caminho!).existsSync())) {
        item
          ..estado = EstadoDownload.erro
          ..mensagem = 'Arquivo não encontrado no aparelho.';
      }
    }
    notifyListeners();
  }

  Future<void> _salvar() => _prefs.setString(_chave, jsonEncode(_itens.map((i) => i.toJson()).toList()));

  void _mudou(DownloadItem item, {bool salvar = false}) {
    notifyListeners();
    if (salvar || !item.emAndamento) unawaited(_salvar());
  }

  DownloadItem _novo(String titulo, String url, TipoMidia tipo, OrigemDownload origem) {
    final item = DownloadItem(
      id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      titulo: titulo,
      urlOrigem: url,
      tipo: tipo,
      origem: origem,
      criadoEm: DateTime.now(),
    );
    _itens.insert(0, item);
    _mudou(item, salvar: true);
    return item;
  }

  /// Baixa pelo servidor (yt-dlp). Também usado para `.m3u8` achado pelo WebView,
  /// passando a página em [referer]. [titulo] vira o nome do arquivo no servidor;
  /// [tituloExibicao] só aparece na lista até o servidor informar o título real.
  DownloadItem baixarPeloServidor({
    required String url,
    required TipoMidia tipo,
    String qualidade = '720p',
    String? titulo,
    String? tituloExibicao,
    String? referer,
  }) {
    final item = _novo(titulo ?? tituloExibicao ?? 'Preparando…', referer ?? url, tipo, OrigemDownload.servidor);
    unawaited(_executarServidor(item, url, qualidade, titulo, referer));
    return item;
  }

  Future<void> _executarServidor(
      DownloadItem item, String url, String qualidade, String? titulo, String? referer) async {
    final cancelar = _cancelar[item.id] = CancelToken();
    try {
      item
        ..estado = EstadoDownload.servidor
        ..mensagem = 'Enviando para o servidor…';
      _mudou(item);
      final jobId = await _api.iniciarDownload(
        url: url,
        tipo: item.tipo.name,
        qualidade: qualidade,
        referer: referer,
        titulo: titulo,
      );
      item.jobId = jobId;
      _mudou(item, salvar: true);

      while (true) {
        if (cancelar.isCancelled) throw const ApiException('Cancelado.');
        final st = await _api.status(jobId);
        if (st.titulo != null && st.titulo!.isNotEmpty) item.titulo = st.titulo!;
        if (st.estado == 'erro') throw ApiException(st.mensagem);
        if (st.estado == 'concluido') break;
        item
          ..progresso = st.progresso / 100
          ..mensagem = 'No servidor: ${st.mensagem}';
        _mudou(item);
        await Future<void>.delayed(_intervaloStatus);
      }

      final st = await _api.status(jobId);
      final nome = st.nomeArquivo ?? '${limparNomeArquivo(item.titulo)}.${item.tipo == TipoMidia.audio ? 'mp3' : 'mp4'}';
      final destino = await _caminhoLivre(nome);
      item
        ..estado = EstadoDownload.transferindo
        ..progresso = 0
        ..mensagem = 'Transferindo para o celular…';
      _mudou(item);
      await _api.baixarArquivo(jobId, destino.path, cancelar: cancelar, progresso: (recebido, total) {
        if (total > 0) _progresso(item, recebido / total);
      });
      _concluir(item, destino);
    } on ApiException catch (e) {
      _falhar(item, e.mensagem);
    } catch (e) {
      _falhar(item, 'Erro inesperado: $e');
    } finally {
      _cancelar.remove(item.id);
    }
  }

  /// Baixa direto no celular um vídeo achado na página (MP4/WebM/MOV), enviando os
  /// mesmos cabeçalhos do WebView (algumas CDNs recusam sem eles).
  DownloadItem baixarDireto({
    required String videoUrl,
    required String pagina,
    required String titulo,
    Map<String, String> cabecalhos = const {},
    String extensao = 'mp4',
  }) {
    final item = _novo(titulo, pagina, TipoMidia.video, OrigemDownload.pagina);
    unawaited(_executarDireto(item, videoUrl, cabecalhos, extensao));
    return item;
  }

  Future<void> _executarDireto(
      DownloadItem item, String videoUrl, Map<String, String> cabecalhos, String extensao) async {
    final cancelar = _cancelar[item.id] = CancelToken();
    try {
      final destino = await _caminhoLivre('${limparNomeArquivo(item.titulo)}.$extensao');
      item
        ..estado = EstadoDownload.transferindo
        ..mensagem = 'Baixando…';
      _mudou(item);
      await _baixarArquivo(videoUrl, destino, cabecalhos, cancelar, (fracao) => _progresso(item, fracao));
      _concluir(item, destino);
    } on DioException catch (e) {
      _falhar(item, _mensagemDio(e));
    } catch (e) {
      _falhar(item, 'Erro inesperado: $e');
    } finally {
      _cancelar.remove(item.id);
    }
  }

  /// Atualiza a barra só a cada 1% para não redesenhar a tela a cada pedacinho recebido.
  void _progresso(DownloadItem item, double valor) {
    if ((valor - item.progresso).abs() < 0.01 && valor < 1) return;
    item.progresso = valor;
    _mudou(item);
  }

  /// Instagram/Facebook: a imagem e o som vêm em arquivos separados. Baixa os dois
  /// (com os cabeçalhos do WebView) e junta num MP4 normal no próprio celular.
  DownloadItem baixarDiretoComAudio({
    required String videoUrl,
    required String audioUrl,
    required String pagina,
    required String titulo,
    Map<String, String> cabecalhos = const {},
    int? tamanhoVideo,
    int? tamanhoAudio,
  }) {
    final item = _novo(titulo, pagina, TipoMidia.video, OrigemDownload.pagina);
    unawaited(_executarComAudio(item, videoUrl, audioUrl, cabecalhos, tamanhoVideo, tamanhoAudio));
    return item;
  }

  Future<void> _executarComAudio(DownloadItem item, String videoUrl, String audioUrl,
      Map<String, String> cabecalhos, int? tamanhoVideo, int? tamanhoAudio) async {
    final cancelar = _cancelar[item.id] = CancelToken();
    final temporaria = Directory('${(await _pastaBase()).path}/PegaMidia/.temporario/${item.id}');
    try {
      await temporaria.create(recursive: true);
      final arquivoVideo = File('${temporaria.path}/video.mp4');
      final arquivoAudio = File('${temporaria.path}/audio.mp4');
      // A barra anda proporcional ao tamanho de cada parte (imagem costuma ser bem maior).
      final pesoVideo = (tamanhoVideo != null && tamanhoAudio != null && tamanhoVideo + tamanhoAudio > 0)
          ? tamanhoVideo / (tamanhoVideo + tamanhoAudio)
          : 0.85;
      item
        ..estado = EstadoDownload.transferindo
        ..mensagem = 'Baixando a imagem…';
      _mudou(item);
      await _baixarArquivo(videoUrl, arquivoVideo, cabecalhos, cancelar,
          (fracao) => _progresso(item, fracao * pesoVideo));
      item.mensagem = 'Baixando o som…';
      _mudou(item);
      await _baixarArquivo(audioUrl, arquivoAudio, cabecalhos, cancelar,
          (fracao) => _progresso(item, pesoVideo + fracao * (1 - pesoVideo)));

      item.mensagem = 'Juntando imagem e som…';
      _mudou(item);
      final destino = await _caminhoLivre('${limparNomeArquivo(item.titulo)}.mp4');
      try {
        await _juntar(arquivoVideo.path, arquivoAudio.path, destino.path);
      } on PlatformException catch (e) {
        _semSom(item, arquivoVideo, destino, 'não foi possível juntar o som: ${e.message}');
        return;
      } on MissingPluginException {
        _semSom(item, arquivoVideo, destino, 'este aparelho não junta imagem e som');
        return;
      }
      _concluir(item, destino);
    } on DioException catch (e) {
      _falhar(item, _mensagemDio(e));
    } catch (e) {
      _falhar(item, 'Erro inesperado: $e');
    } finally {
      _cancelar.remove(item.id);
      if (await temporaria.exists()) await temporaria.delete(recursive: true);
    }
  }

  /// Se não der para juntar, ao menos entrega a imagem (sem som) e avisa.
  void _semSom(DownloadItem item, File video, File destino, String motivo) {
    video.copySync(destino.path);
    debugPrint('PegaMídia: salvo sem som ($motivo)');
    item.titulo = '${item.titulo} (sem som)';
    _concluir(item, destino);
  }

  Future<void> _baixarArquivo(String url, File destino, Map<String, String> cabecalhos, CancelToken cancelar,
      void Function(double fracao) progresso) {
    return _dio.download(
      url,
      destino.path,
      cancelToken: cancelar,
      options: Options(headers: cabecalhos, receiveTimeout: const Duration(minutes: 2)),
      onReceiveProgress: (recebido, total) {
        if (total > 0) progresso(recebido / total);
      },
    );
  }

  String _mensagemDio(DioException e) {
    final codigo = e.response?.statusCode;
    if (e.type == DioExceptionType.cancel) return 'Cancelado.';
    if (codigo != null) return 'O site recusou o download (erro $codigo).';
    return 'Falha de conexão ao baixar o vídeo.';
  }

  void _concluir(DownloadItem item, File arquivo) {
    item
      ..estado = EstadoDownload.concluido
      ..progresso = 1
      ..caminho = arquivo.path
      ..tamanho = arquivo.lengthSync()
      ..mensagem = 'Pronto';
    _mudou(item, salvar: true);
  }

  void _falhar(DownloadItem item, String mensagem) {
    item
      ..estado = EstadoDownload.erro
      ..mensagem = mensagem;
    _mudou(item, salvar: true);
  }

  void cancelar(DownloadItem item) => _cancelar[item.id]?.cancel();

  Future<void> apagar(DownloadItem item) async {
    cancelar(item);
    final caminho = item.caminho;
    if (caminho != null) {
      try {
        final arquivo = File(caminho);
        if (await arquivo.exists()) await arquivo.delete();
      } on FileSystemException {
        // já não existe: ok
      }
    }
    _itens.remove(item);
    notifyListeners();
    await _salvar();
  }

  /// Muda o nome que aparece na lista e o nome do arquivo no aparelho (é o nome que
  /// chega no e-mail/WhatsApp ao compartilhar). A extensão (.mp4/.mp3) é mantida.
  /// Se já existir outro arquivo com esse nome, acrescenta " (2)", " (3)"…
  Future<void> renomear(DownloadItem item, String novoNome) async {
    final titulo = novoNome.trim();
    if (titulo.isEmpty || item.emAndamento) return;
    final caminho = item.caminho;
    if (caminho != null && await File(caminho).exists()) {
      final atual = File(caminho);
      final nomeAtual = atual.uri.pathSegments.last;
      final ponto = nomeAtual.lastIndexOf('.');
      final extensao = ponto > 0 ? nomeAtual.substring(ponto) : '';
      final novoArquivo = '${limparNomeArquivo(titulo)}$extensao';
      if (novoArquivo != nomeAtual) {
        final destino = await _caminhoLivre(novoArquivo);
        item.caminho = (await atual.rename(destino.path)).path;
      }
    }
    item.titulo = titulo;
    notifyListeners();
    await _salvar();
  }

  /// Pasta `PegaMidia` dentro dos documentos do app; evita sobrescrever arquivos.
  Future<File> _caminhoLivre(String nome) async {
    final base = Directory('${(await _pastaBase()).path}/PegaMidia');
    await base.create(recursive: true);
    final ponto = nome.lastIndexOf('.');
    final raiz = ponto > 0 ? nome.substring(0, ponto) : nome;
    final ext = ponto > 0 ? nome.substring(ponto) : '';
    var arquivo = File('${base.path}/$nome');
    var n = 2;
    while (await arquivo.exists()) {
      arquivo = File('${base.path}/$raiz ($n)$ext');
      n++;
    }
    return arquivo;
  }
}
