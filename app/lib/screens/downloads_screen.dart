import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../app_scope.dart';
import '../models/download_item.dart';
import '../services/link_utils.dart';
import '../widgets/compartilhar.dart';

/// Lista de downloads com progresso e as ações abrir, compartilhar e apagar.
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final downloads = AppScope.of(context).downloads;
    return Scaffold(
      appBar: AppBar(title: const Text('Downloads')),
      body: ListenableBuilder(
        listenable: downloads,
        builder: (context, _) {
          final itens = downloads.itens;
          if (itens.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('Nenhum download ainda.\nCole um link na aba Início.', textAlign: TextAlign.center),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: itens.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) => _ItemDownload(item: itens[i]),
          );
        },
      ),
    );
  }
}

class _ItemDownload extends StatelessWidget {
  const _ItemDownload({required this.item});

  final DownloadItem item;

  Future<void> _abrir(BuildContext context) async {
    final caminho = item.caminho;
    if (caminho == null) return;
    final resultado = await OpenFilex.open(caminho);
    if (resultado.type != ResultType.done && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não consegui abrir: ${resultado.message}')),
      );
    }
  }

  Future<void> _apagar(BuildContext context) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apagar?'),
        content: Text('"${item.titulo}" será removido do aparelho.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Apagar')),
        ],
      ),
    );
    if (confirmou == true && context.mounted) await AppScope.of(context).downloads.apagar(item);
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final icone = item.tipo == TipoMidia.audio ? Icons.music_note : Icons.movie;
    final subtitulo = switch (item.estado) {
      EstadoDownload.concluido => [
          formatarTamanho(item.tamanho),
          item.origem == OrigemDownload.pagina ? 'da página' : 'pelo servidor',
        ].where((s) => s.isNotEmpty).join(' • '),
      _ => item.mensagem,
    };

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: item.estado == EstadoDownload.erro ? tema.colorScheme.errorContainer : null,
        child: Icon(item.estado == EstadoDownload.erro ? Icons.error_outline : icone),
      ),
      title: Text(item.titulo, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            subtitulo,
            style: item.estado == EstadoDownload.erro ? TextStyle(color: tema.colorScheme.error) : null,
          ),
          if (item.emAndamento) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(value: item.progresso > 0 ? item.progresso : null),
          ],
        ],
      ),
      onTap: item.estado == EstadoDownload.concluido ? () => _abrir(context) : null,
      trailing: item.emAndamento
          ? IconButton(
              tooltip: 'Cancelar',
              icon: const Icon(Icons.close),
              onPressed: () => AppScope.of(context).downloads.cancelar(item),
            )
          : PopupMenuButton<String>(
              onSelected: (acao) {
                switch (acao) {
                  case 'abrir':
                    _abrir(context);
                  case 'compartilhar':
                    compartilharDownload(context, item);
                  case 'apagar':
                    _apagar(context);
                }
              },
              itemBuilder: (_) => [
                if (item.estado == EstadoDownload.concluido) ...[
                  const PopupMenuItem(value: 'abrir', child: ListTile(leading: Icon(Icons.play_arrow), title: Text('Abrir'))),
                  const PopupMenuItem(
                      value: 'compartilhar', child: ListTile(leading: Icon(Icons.share), title: Text('Compartilhar'))),
                ],
                const PopupMenuItem(value: 'apagar', child: ListTile(leading: Icon(Icons.delete), title: Text('Apagar'))),
              ],
            ),
    );
  }
}
