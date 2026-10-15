import 'package:flutter/material.dart';

import '../config.dart';

/// Tela "Sobre": aviso de projeto escolar e regras de uso.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Sobre')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(appName, style: tema.textTheme.headlineSmall),
          Text('Versão $appVersion', style: tema.textTheme.bodySmall),
          const SizedBox(height: 16),
          Card(
            color: tema.colorScheme.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '⚠️ Projeto escolar, sem fins comerciais.\n\n'
                'Este app foi criado para uso educacional e interno de uma escola '
                '(ex.: salvar vídeos de produtos para o bingo, materiais de aula, gravações próprias). '
                'Não é vendido, não tem anúncios e não deve ser usado comercialmente.',
                style: TextStyle(color: tema.colorScheme.onTertiaryContainer),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Regras de uso', style: tema.textTheme.titleMedium),
          const SizedBox(height: 8),
          const _Regra('Baixe só conteúdo seu, com permissão do autor ou de licença livre.'),
          const _Regra('Não redistribua músicas e vídeos de terceiros. Respeite os direitos autorais.'),
          const _Regra(
            'Os termos do YouTube não permitem baixar vídeos fora dos recursos oficiais. Por isso o app é '
            'só para uso interno da escola e não é publicado na Play Store (é distribuído como APK interno).',
          ),
          const _Regra('Respeite os termos de uso de cada site. Os autores não se responsabilizam pelo uso indevido.'),
          const _Regra('Vídeos privados ou que exigem login não são suportados.'),
          const SizedBox(height: 16),
          Text(
            'Este app não é afiliado ao YouTube, Google, Meta, X, TikTok, Kwai ou Shopee.',
            style: tema.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Licença: PolyForm Noncommercial 1.0.0. O servidor usa o yt-dlp (Unlicense) e o ffmpeg.',
            style: tema.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => showLicensePage(context: context, applicationName: appName, applicationVersion: appVersion),
            icon: const Icon(Icons.description_outlined),
            label: const Text('Licenças de terceiros'),
          ),
        ],
      ),
    );
  }
}

class _Regra extends StatelessWidget {
  const _Regra(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.check_circle_outline, size: 18)),
          const SizedBox(width: 8),
          Expanded(child: Text(texto)),
        ],
      ),
    );
  }
}
