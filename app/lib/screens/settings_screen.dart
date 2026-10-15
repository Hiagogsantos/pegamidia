import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../config.dart';
import '../services/link_utils.dart';
import '../services/server_api.dart';
import 'about_screen.dart';

/// Endereço do servidor e botão "Testar conexão".
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _campo = TextEditingController();
  bool _testando = false;
  String? _resultado;
  bool _ok = false;
  bool _iniciado = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_iniciado) {
      _iniciado = true;
      _campo.text = AppScope.of(context).settings.servidor ?? '';
    }
  }

  @override
  void dispose() {
    _campo.dispose();
    super.dispose();
  }

  Future<String?> _salvar() async {
    final settings = AppScope.of(context).settings;
    final texto = _campo.text.trim();
    if (texto.isEmpty) {
      await settings.salvarServidor(null);
      setState(() {
        _resultado = 'Servidor removido. O app vai procurar vídeos direto nas páginas.';
        _ok = true;
      });
      return null;
    }
    final endereco = normalizarEnderecoServidor(texto);
    if (endereco == null) {
      setState(() {
        _resultado = 'Endereço inválido. Exemplo: $exemploServidor';
        _ok = false;
      });
      return null;
    }
    _campo.text = endereco;
    await settings.salvarServidor(endereco);
    return endereco;
  }

  Future<void> _testar() async {
    FocusScope.of(context).unfocus();
    final api = AppScope.of(context).api;
    final endereco = await _salvar();
    if (endereco == null) return;
    setState(() {
      _testando = true;
      _resultado = null;
    });
    try {
      final s = await api.saude(endereco: endereco);
      setState(() {
        _ok = s.ffmpeg;
        _resultado = 'Conectado! Servidor ${s.versao}, yt-dlp ${s.ytDlp}.'
            '${s.ffmpeg ? '' : '\nAtenção: o ffmpeg não está instalado no servidor.'}'
            '${s.playwright ? '' : '\nPlaywright não instalado: o servidor não procura vídeo em páginas como Shopee/Kwai (o app ainda procura pelo WebView).'}';
      });
    } on ApiException catch (e) {
      setState(() {
        _ok = false;
        _resultado = e is ServidorIndisponivel ? 'Servidor não encontrado.\n${e.mensagem}' : e.mensagem;
      });
    } finally {
      if (mounted) setState(() => _testando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Servidor', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'Endereço do PC da escola que roda o servidor (mesma rede Wi-Fi). '
            'Ele aparece na tela quando o servidor é iniciado.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _campo,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Endereço do servidor',
              hintText: exemploServidor,
              prefixIcon: Icon(Icons.dns_outlined),
            ),
            onSubmitted: (_) => _testar(),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _testando ? null : _testar,
            icon: _testando
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.wifi_tethering),
            label: const Text('Salvar e testar conexão'),
          ),
          if (_resultado != null) ...[
            const SizedBox(height: 12),
            Card(
              color: _ok ? cores.primaryContainer : cores.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_resultado!,
                    style: TextStyle(color: _ok ? cores.onPrimaryContainer : cores.onErrorContainer)),
              ),
            ),
          ],
          const SizedBox(height: 24),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.info_outline),
            title: const Text('Sobre e regras de uso'),
            subtitle: const Text('$appName $appVersion'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutScreen())),
          ),
        ],
      ),
    );
  }
}
