import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../config.dart';
import '../models/download_item.dart';
import '../models/media_info.dart';
import '../services/link_utils.dart';
import '../services/server_api.dart';
import 'about_screen.dart';
import 'capture_screen.dart';

/// Tela inicial: colar o link, ver a prévia, escolher vídeo/áudio e baixar.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.aoIniciarDownload});

  /// Chamado depois que um download começa (a tela principal vai para "Downloads").
  final VoidCallback aoIniciarDownload;

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final _campo = TextEditingController();
  bool _carregando = false;
  String? _erro;
  String? _url;
  MediaInfo? _info;
  TipoMidia _tipo = TipoMidia.video;
  String _qualidade = qualidadePadrao;

  @override
  void dispose() {
    _campo.dispose();
    super.dispose();
  }

  /// Link recebido pelo "Compartilhar" de outro app.
  void receberLink(String url) {
    _campo.text = url;
    _buscar();
  }

  Future<void> _colar() async {
    final dados = await Clipboard.getData(Clipboard.kTextPlain);
    final texto = dados?.text?.trim();
    if (texto == null || texto.isEmpty) {
      _mostrar('A área de transferência está vazia.');
      return;
    }
    _campo.text = extrairUrl(texto) ?? texto;
    await _buscar();
  }

  void _mostrar(String mensagem) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensagem)));
  }

  Future<void> _buscar() async {
    FocusScope.of(context).unfocus();
    final url = extrairUrl(_campo.text);
    setState(() {
      _info = null;
      _erro = null;
      _url = url;
    });
    if (url == null) {
      setState(() => _erro = 'Link inválido. Cole um endereço que comece com http:// ou https://.');
      return;
    }

    final scope = AppScope.of(context);
    final site = detectarSite(url);
    // Shopee e Kwai não têm extrator no yt-dlp: procura o vídeo direto na página.
    if (site.usaCapturaNaPagina) {
      await _abrirCaptura(url);
      return;
    }
    if (!scope.settings.temServidor) {
      _mostrar('Sem servidor configurado: procurando o vídeo na própria página.');
      await _abrirCaptura(url);
      return;
    }

    setState(() => _carregando = true);
    try {
      final info = await scope.api.info(url);
      if (!mounted) return;
      setState(() {
        _info = info;
        if (!info.temVideo) _tipo = TipoMidia.audio;
      });
    } on ServidorIndisponivel {
      _mostrar('Servidor não encontrado. Procurando o vídeo na própria página…');
      await _abrirCaptura(url);
    } on ApiException catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _abrirCaptura(String url) async {
    final iniciou = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CaptureScreen(url: url)),
    );
    if (iniciou == true) widget.aoIniciarDownload();
  }

  void _baixar() {
    final url = _url;
    final info = _info;
    if (url == null || info == null) return;
    AppScope.of(context).downloads.baixarPeloServidor(
          url: url,
          tipo: _tipo,
          qualidade: _qualidade,
          tituloExibicao: info.titulo,
        );
    _mostrar('Download iniciado.');
    widget.aoIniciarDownload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(appName),
        actions: [
          IconButton(
            tooltip: 'Sobre e regras de uso',
            icon: const Icon(Icons.info_outline),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutScreen())),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Cole o link do vídeo (YouTube, Facebook, X, TikTok, Instagram, Kwai, Shopee…)',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _campo,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _buscar(),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: 'https://…',
              prefixIcon: const Icon(Icons.link),
              suffixIcon: _campo.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpar',
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() {
                        _campo.clear();
                        _info = null;
                        _erro = null;
                        _url = null;
                      }),
                    ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _carregando ? null : _colar,
                  icon: const Icon(Icons.content_paste),
                  label: const Text('Colar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _carregando ? null : _buscar,
                  icon: const Icon(Icons.search),
                  label: const Text('Buscar'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_carregando)
            const Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Buscando informações do vídeo…'),
              ],
            ),
          if (_erro != null) _CartaoErro(mensagem: _erro!, aoProcurarNaPagina: _url == null ? null : () => _abrirCaptura(_url!)),
          if (_info != null) _previa(_info!),
        ],
      ),
    );
  }

  Widget _previa(MediaInfo info) {
    final tema = Theme.of(context);
    final estimado = _tipo == TipoMidia.video ? info.tamanhoEstimado(_qualidade) : null;
    final detalhes = [
      info.siteNome,
      if (info.autor != null) info.autor!,
      if (formatarDuracao(info.duracao).isNotEmpty) formatarDuracao(info.duracao),
    ].join(' • ');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (info.miniatura != null)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(
                info.miniatura!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(
                  color: Colors.black12,
                  child: Icon(Icons.movie_outlined, size: 48),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(info.titulo, style: tema.textTheme.titleMedium, maxLines: 3, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(detalhes, style: tema.textTheme.bodySmall),
                const SizedBox(height: 16),
                SegmentedButton<TipoMidia>(
                  segments: [
                    ButtonSegment(
                      value: TipoMidia.video,
                      label: const Text('Vídeo (MP4)'),
                      icon: const Icon(Icons.movie),
                      enabled: info.temVideo,
                    ),
                    ButtonSegment(
                      value: TipoMidia.audio,
                      label: const Text('Áudio (MP3)'),
                      icon: const Icon(Icons.music_note),
                      enabled: info.temAudio,
                    ),
                  ],
                  selected: {_tipo},
                  onSelectionChanged: (s) => setState(() => _tipo = s.first),
                ),
                if (_tipo == TipoMidia.video && info.fonte != 'pagina') ...[
                  const SizedBox(height: 16),
                  DropdownMenu<String>(
                    initialSelection: _qualidade,
                    label: const Text('Qualidade'),
                    expandedInsets: EdgeInsets.zero,
                    onSelected: (q) => setState(() => _qualidade = q ?? qualidadePadrao),
                    dropdownMenuEntries: [
                      for (final q in qualidadesVideo)
                        DropdownMenuEntry(
                          value: q,
                          label: q == 'melhor' ? 'Melhor disponível' : (q == '720p' ? '720p (recomendado)' : q),
                        ),
                    ],
                  ),
                ],
                if (estimado != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        estimado > limiteAnexoEmailBytes ? Icons.warning_amber : Icons.sd_storage_outlined,
                        size: 18,
                        color: estimado > limiteAnexoEmailBytes ? tema.colorScheme.error : null,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          estimado > limiteAnexoEmailBytes
                              ? 'Cerca de ${formatarTamanho(estimado)}: grande demais para anexar em e-mail.'
                              : 'Cerca de ${formatarTamanho(estimado)}',
                          style: tema.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _baixar,
                  icon: const Icon(Icons.download),
                  label: const Text('Baixar'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CartaoErro extends StatelessWidget {
  const _CartaoErro({required this.mensagem, this.aoProcurarNaPagina});

  final String mensagem;
  final VoidCallback? aoProcurarNaPagina;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Card(
      color: cores.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, color: cores.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(child: Text(mensagem, style: TextStyle(color: cores.onErrorContainer))),
              ],
            ),
            if (aoProcurarNaPagina != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: aoProcurarNaPagina,
                icon: const Icon(Icons.travel_explore),
                label: const Text('Procurar o vídeo na página'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
