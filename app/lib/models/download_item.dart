enum TipoMidia { video, audio }

enum EstadoDownload { fila, servidor, transferindo, concluido, erro }

/// De onde o arquivo vem: do servidor (yt-dlp) ou direto da página (captura pelo WebView).
enum OrigemDownload { servidor, pagina }

/// Um item da tela "Downloads". É salvo no aparelho (shared_preferences) como JSON.
class DownloadItem {
  DownloadItem({
    required this.id,
    required this.titulo,
    required this.urlOrigem,
    required this.tipo,
    required this.origem,
    required this.criadoEm,
    this.estado = EstadoDownload.fila,
    this.progresso = 0,
    this.mensagem = 'Na fila…',
    this.caminho,
    this.tamanho,
    this.jobId,
  });

  factory DownloadItem.fromJson(Map<String, dynamic> json) => DownloadItem(
        id: json['id'] as String,
        titulo: json['titulo'] as String? ?? 'Sem título',
        urlOrigem: json['urlOrigem'] as String? ?? '',
        tipo: TipoMidia.values.asNameMap()[json['tipo']] ?? TipoMidia.video,
        origem: OrigemDownload.values.asNameMap()[json['origem']] ?? OrigemDownload.servidor,
        criadoEm: DateTime.tryParse(json['criadoEm'] as String? ?? '') ?? DateTime.now(),
        estado: EstadoDownload.values.asNameMap()[json['estado']] ?? EstadoDownload.erro,
        progresso: (json['progresso'] as num?)?.toDouble() ?? 0,
        mensagem: json['mensagem'] as String? ?? '',
        caminho: json['caminho'] as String?,
        tamanho: (json['tamanho'] as num?)?.toInt(),
        jobId: json['jobId'] as String?,
      );

  final String id;
  String titulo;
  final String urlOrigem;
  final TipoMidia tipo;
  final OrigemDownload origem;
  final DateTime criadoEm;
  EstadoDownload estado;

  /// 0.0 a 1.0 da etapa atual.
  double progresso;
  String mensagem;
  String? caminho;
  int? tamanho;
  String? jobId;

  bool get emAndamento =>
      estado == EstadoDownload.fila || estado == EstadoDownload.servidor || estado == EstadoDownload.transferindo;

  Map<String, dynamic> toJson() => {
        'id': id,
        'titulo': titulo,
        'urlOrigem': urlOrigem,
        'tipo': tipo.name,
        'origem': origem.name,
        'criadoEm': criadoEm.toIso8601String(),
        'estado': estado.name,
        'progresso': progresso,
        'mensagem': mensagem,
        'caminho': caminho,
        'tamanho': tamanho,
        'jobId': jobId,
      };
}
