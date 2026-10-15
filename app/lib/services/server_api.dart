import 'package:dio/dio.dart';

import '../models/media_info.dart';

/// Erro com mensagem pronta para mostrar ao usuário.
class ApiException implements Exception {
  const ApiException(this.mensagem);
  final String mensagem;

  @override
  String toString() => mensagem;
}

/// O servidor não respondeu (desligado, IP errado ou outra rede Wi-Fi).
class ServidorIndisponivel extends ApiException {
  const ServidorIndisponivel()
      : super('Servidor não encontrado. Confira se o PC do servidor está ligado, '
            'na mesma rede Wi-Fi, e o endereço em Configurações.');
}

class ServidorNaoConfigurado extends ApiException {
  const ServidorNaoConfigurado() : super('Configure o endereço do servidor em Configurações.');
}

/// Cliente HTTP do servidor PegaMídia (FastAPI + yt-dlp).
class ServerApi {
  ServerApi(this._enderecoAtual, {Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 8)));

  final String? Function() _enderecoAtual;
  final Dio _dio;

  String get _base {
    final base = _enderecoAtual();
    if (base == null) throw const ServidorNaoConfigurado();
    return base;
  }

  Options _opcoes(Duration espera) => Options(
        sendTimeout: const Duration(seconds: 15),
        receiveTimeout: espera,
        contentType: Headers.jsonContentType,
      );

  Future<T> _chamar<T>(Future<T> Function() chamada) async {
    try {
      return await chamada();
    } on DioException catch (e) {
      throw traduzirErro(e);
    }
  }

  static ApiException traduzirErro(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
        return const ServidorIndisponivel();
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const ApiException('O servidor demorou demais para responder. Tente de novo.');
      case DioExceptionType.cancel:
        return const ApiException('Cancelado.');
      default:
        final dados = e.response?.data;
        if (dados is Map && dados['detail'] is String) return ApiException(dados['detail'] as String);
        if (dados is Map && dados['detail'] is List) {
          return const ApiException('Pedido inválido para o servidor.');
        }
        if (e.response == null) return const ServidorIndisponivel();
        return ApiException('Erro do servidor (${e.response?.statusCode}).');
    }
  }

  /// `GET /saude` — usado pelo botão "Testar conexão".
  Future<ServidorSaude> saude({String? endereco}) => _chamar(() async {
        final r = await _dio.get<Map<String, dynamic>>(
          '${endereco ?? _base}/saude',
          options: _opcoes(const Duration(seconds: 8)),
        );
        return ServidorSaude.fromJson(r.data ?? const {});
      });

  /// `POST /info` — título, miniatura, duração e qualidades.
  /// Pode demorar (até ~40 s) quando o servidor precisa abrir a página no navegador.
  Future<MediaInfo> info(String url) => _chamar(() async {
        final r = await _dio.post<Map<String, dynamic>>(
          '$_base/info',
          data: {'url': url},
          options: _opcoes(const Duration(seconds: 90)),
        );
        return MediaInfo.fromJson(r.data ?? const {});
      });

  /// `POST /download` — cria a tarefa no servidor e devolve o `job_id`.
  Future<String> iniciarDownload({
    required String url,
    required String tipo,
    String qualidade = '720p',
    String formatoAudio = 'mp3',
    String? referer,
    String? titulo,
  }) =>
      _chamar(() async {
        final r = await _dio.post<Map<String, dynamic>>(
          '$_base/download',
          data: {
            'url': url,
            'tipo': tipo,
            'qualidade': qualidade,
            'formato_audio': formatoAudio,
            'referer': ?referer,
            'titulo': ?titulo,
          },
          options: _opcoes(const Duration(seconds: 30)),
        );
        return r.data!['job_id'] as String;
      });

  /// `GET /status/{job_id}`.
  Future<JobStatus> status(String jobId) => _chamar(() async {
        final r = await _dio.get<Map<String, dynamic>>(
          '$_base/status/$jobId',
          options: _opcoes(const Duration(seconds: 15)),
        );
        return JobStatus.fromJson(r.data ?? const {});
      });

  /// `GET /arquivo/{job_id}` — transfere o arquivo pronto para o celular.
  Future<void> baixarArquivo(
    String jobId,
    String destino, {
    void Function(int recebido, int total)? progresso,
    CancelToken? cancelar,
  }) =>
      _chamar(() async {
        await _dio.download(
          '$_base/arquivo/$jobId',
          destino,
          onReceiveProgress: progresso,
          cancelToken: cancelar,
          options: Options(receiveTimeout: const Duration(minutes: 2)),
        );
      });
}
