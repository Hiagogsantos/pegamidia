import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../config.dart';
import '../models/download_item.dart';
import '../services/link_utils.dart';

/// Abre o menu "Compartilhar" do sistema (e-mail, WhatsApp, Drive…).
/// Se o arquivo passar de ~25 MB, avisa antes: e-mails costumam recusar anexos grandes.
Future<void> compartilharDownload(BuildContext context, DownloadItem item) async {
  final caminho = item.caminho;
  if (caminho == null || !File(caminho).existsSync()) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Arquivo não encontrado no aparelho.')),
    );
    return;
  }
  final tamanho = item.tamanho ?? File(caminho).lengthSync();
  if (tamanho > limiteAnexoEmailBytes) {
    final seguir = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.mail_outline),
        title: const Text('Arquivo grande para e-mail'),
        content: Text(
          'Este arquivo tem ${formatarTamanho(tamanho)}. Gmail e similares só aceitam anexos de '
          'até cerca de 25 MB.\n\n'
          'Sugestões:\n'
          '• Envie pelo WhatsApp ou salve no Google Drive e mande o link.\n'
          '• Ou baixe de novo em qualidade menor (360p ou 480p).',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Compartilhar assim mesmo')),
        ],
      ),
    );
    if (seguir != true) return;
  }
  await SharePlus.instance.share(
    ShareParams(files: [XFile(caminho)], subject: item.titulo, text: item.titulo),
  );
}
