/// Resposta do `POST /info` do servidor.
class MediaInfo {
  const MediaInfo({
    required this.titulo,
    required this.siteNome,
    this.miniatura,
    this.duracao,
    this.autor,
    this.temVideo = true,
    this.temAudio = true,
    this.qualidades = const [],
    this.tamanhos = const {},
    this.fonte = 'yt-dlp',
  });

  factory MediaInfo.fromJson(Map<String, dynamic> json) {
    final tamanhos = <String, int>{};
    for (final f in (json['formatos'] as List? ?? const [])) {
      if (f is Map && f['altura'] is int && f['tamanho_aprox'] is num) {
        tamanhos['${f['altura']}p'] = (f['tamanho_aprox'] as num).toInt();
      }
    }
    return MediaInfo(
      titulo: (json['titulo'] as String?) ?? 'Sem título',
      siteNome: (json['site_nome'] as String?) ?? 'Outro site',
      miniatura: json['miniatura'] as String?,
      duracao: json['duracao'] as num?,
      autor: json['autor'] as String?,
      temVideo: json['tem_video'] as bool? ?? true,
      temAudio: json['tem_audio'] as bool? ?? true,
      qualidades: [for (final q in (json['qualidades'] as List? ?? const [])) q.toString()],
      tamanhos: tamanhos,
      fonte: (json['fonte'] as String?) ?? 'yt-dlp',
    );
  }

  final String titulo;
  final String siteNome;
  final String? miniatura;
  final num? duracao;
  final String? autor;
  final bool temVideo;
  final bool temAudio;
  final List<String> qualidades;

  /// Tamanho aproximado do vídeo (sem o áudio) por qualidade, ex.: {'720p': 12345678}.
  final Map<String, int> tamanhos;

  /// `yt-dlp` ou `pagina` (achado pelo fallback do servidor).
  final String fonte;

  /// Estimativa para a qualidade escolhida (a maior que não passe do limite).
  int? tamanhoEstimado(String qualidade) {
    if (tamanhos.isEmpty) return null;
    final alturas = tamanhos.keys.map((q) => int.parse(q.replaceAll('p', ''))).toList()..sort();
    final limite = int.tryParse(qualidade.replaceAll('p', ''));
    final escolhida = limite == null
        ? alturas.last
        : alturas.lastWhere((a) => a <= limite, orElse: () => alturas.first);
    return tamanhos['${escolhida}p'];
  }
}

/// Resposta do `GET /status/{job_id}`.
class JobStatus {
  const JobStatus({
    required this.estado,
    required this.progresso,
    required this.mensagem,
    this.titulo,
    this.nomeArquivo,
    this.tamanho,
  });

  factory JobStatus.fromJson(Map<String, dynamic> json) => JobStatus(
        estado: (json['estado'] as String?) ?? 'na_fila',
        progresso: ((json['progresso'] as num?) ?? 0).toDouble(),
        mensagem: (json['mensagem'] as String?) ?? '',
        titulo: json['titulo'] as String?,
        nomeArquivo: json['nome_arquivo'] as String?,
        tamanho: (json['tamanho'] as num?)?.toInt(),
      );

  /// na_fila | baixando | processando | concluido | erro
  final String estado;

  /// 0 a 100.
  final double progresso;
  final String mensagem;
  final String? titulo;
  final String? nomeArquivo;
  final int? tamanho;

  bool get terminou => estado == 'concluido' || estado == 'erro';
}

/// Resposta do `GET /saude`.
class ServidorSaude {
  const ServidorSaude({required this.versao, required this.ytDlp, required this.ffmpeg, required this.playwright});

  factory ServidorSaude.fromJson(Map<String, dynamic> json) => ServidorSaude(
        versao: json['versao']?.toString() ?? '?',
        ytDlp: json['yt_dlp']?.toString() ?? '?',
        ffmpeg: json['ffmpeg'] == true,
        playwright: json['playwright'] == true,
      );

  final String versao;
  final String ytDlp;
  final bool ffmpeg;
  final bool playwright;
}
