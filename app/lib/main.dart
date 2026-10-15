import 'dart:async';

import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_scope.dart';
import 'config.dart';
import 'screens/downloads_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'services/download_manager.dart';
import 'services/link_utils.dart';
import 'services/server_api.dart';
import 'services/settings_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final settings = SettingsService(prefs);
  final api = ServerApi(() => settings.servidor);
  final downloads = DownloadManager(api, prefs);
  await downloads.carregar();
  runApp(PegaMidiaApp(settings: settings, api: api, downloads: downloads));
}

class PegaMidiaApp extends StatelessWidget {
  const PegaMidiaApp({super.key, required this.settings, required this.api, required this.downloads});

  final SettingsService settings;
  final ServerApi api;
  final DownloadManager downloads;

  @override
  Widget build(BuildContext context) {
    const semente = Color(0xFF00897B);
    return AppScope(
      settings: settings,
      api: api,
      downloads: downloads,
      child: MaterialApp(
        title: appName,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: semente, useMaterial3: true),
        darkTheme: ThemeData(colorSchemeSeed: semente, brightness: Brightness.dark, useMaterial3: true),
        home: const TelaPrincipal(),
      ),
    );
  }
}

/// Barra inferior com Início, Downloads e Configurações.
class TelaPrincipal extends StatefulWidget {
  const TelaPrincipal({super.key});

  @override
  State<TelaPrincipal> createState() => _TelaPrincipalState();
}

class _TelaPrincipalState extends State<TelaPrincipal> {
  int _aba = 0;
  final _inicio = GlobalKey<HomeScreenState>();
  StreamSubscription<List<SharedMediaFile>>? _compartilhamentos;

  @override
  void initState() {
    super.initState();
    _ouvirCompartilhamentos();
  }

  /// Recebe links enviados pelo botão "Compartilhar" de outros apps (Shopee, YouTube…).
  void _ouvirCompartilhamentos() {
    try {
      _compartilhamentos = ReceiveSharingIntent.instance.getMediaStream().listen(_recebeu, onError: (_) {});
      ReceiveSharingIntent.instance.getInitialMedia().then((itens) {
        _recebeu(itens);
        ReceiveSharingIntent.instance.reset();
      }).catchError((_) {});
    } catch (_) {
      // plataforma sem suporte (ex.: testes)
    }
  }

  void _recebeu(List<SharedMediaFile> itens) {
    for (final item in itens) {
      final url = extrairUrl(item.path) ?? extrairUrl(item.message);
      if (url != null) {
        setState(() => _aba = 0);
        WidgetsBinding.instance.addPostFrameCallback((_) => _inicio.currentState?.receberLink(url));
        return;
      }
    }
  }

  void irParaDownloads() => setState(() => _aba = 1);

  @override
  void dispose() {
    _compartilhamentos?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final downloads = AppScope.of(context).downloads;
    return Scaffold(
      body: IndexedStack(
        index: _aba,
        children: [
          HomeScreen(key: _inicio, aoIniciarDownload: irParaDownloads),
          const DownloadsScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: downloads,
        builder: (context, _) => NavigationBar(
          selectedIndex: _aba,
          onDestinationSelected: (i) => setState(() => _aba = i),
          destinations: [
            const NavigationDestination(icon: Icon(Icons.link), label: 'Início'),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: downloads.emAndamento > 0,
                label: Text('${downloads.emAndamento}'),
                child: const Icon(Icons.download),
              ),
              label: 'Downloads',
            ),
            const NavigationDestination(icon: Icon(Icons.settings), label: 'Configurações'),
          ],
        ),
      ),
    );
  }
}
