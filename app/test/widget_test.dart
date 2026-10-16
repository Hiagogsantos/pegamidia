import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pegamidia/main.dart';
import 'package:pegamidia/services/download_manager.dart';
import 'package:pegamidia/services/server_api.dart';
import 'package:pegamidia/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> abrirApp(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsService(prefs);
    final api = ServerApi(() => settings.servidor);
    await tester.pumpWidget(PegaMidiaApp(settings: settings, api: api, downloads: DownloadManager(api, prefs)));
  }

  testWidgets('mostra o nome do app e as abas', (tester) async {
    await abrirApp(tester);
    expect(find.text('PegaMídia'), findsOneWidget);
    expect(find.text('Início'), findsOneWidget);
    expect(find.text('Downloads'), findsWidgets);
    expect(find.text('Configurações'), findsWidgets);
  });

  testWidgets('link inválido mostra mensagem clara', (tester) async {
    await abrirApp(tester);
    await tester.enterText(find.byType(TextField).first, 'isso não é link');
    await tester.tap(find.text('Buscar'));
    await tester.pump();
    expect(find.textContaining('Link inválido'), findsOneWidget);
  });

  testWidgets('tela Sobre mostra as regras de uso', (tester) async {
    await abrirApp(tester);
    await tester.tap(find.byTooltip('Sobre e regras de uso'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Projeto escolar, sem fins comerciais'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('não é afiliado'), 200);
    expect(find.textContaining('não é afiliado'), findsOneWidget);
  });

  testWidgets('configurações recusa endereço inválido', (tester) async {
    await abrirApp(tester);
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'ftp://x');
    await tester.tap(find.text('Salvar e testar conexão'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Endereço inválido'), findsOneWidget);
  });

  testWidgets('renomear pelo menu dos 3 pontinhos em Downloads', (tester) async {
    final pasta = Directory.systemTemp.createTempSync('pegamidia_widget');
    addTearDown(() => pasta.deleteSync(recursive: true));
    final arquivo = File('${pasta.path}/PegaMidia/Achados casa.mp4')..createSync(recursive: true);
    SharedPreferences.setMockInitialValues({
      'downloads': jsonEncode([
        {
          'id': 'a1',
          'titulo': 'Achados casa',
          'urlOrigem': 'https://www.instagram.com/reel/x/',
          'tipo': 'video',
          'origem': 'pagina',
          'criadoEm': DateTime.now().toIso8601String(),
          'estado': 'concluido',
          'progresso': 1,
          'caminho': arquivo.path,
          'tamanho': 0,
        },
      ]),
    });
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsService(prefs);
    final api = ServerApi(() => settings.servidor);
    final downloads = DownloadManager(api, prefs, pasta: () async => pasta);
    // o plugin de "Compartilhar" não existe nos testes; com E/S real ele reclamaria
    final mensageiro = tester.binding.defaultBinaryMessenger;
    for (final canal in ['receive_sharing_intent/events-media', 'receive_sharing_intent/messages']) {
      mensageiro.setMockMethodCallHandler(MethodChannel(canal), (_) async => canal.endsWith('messages') ? '[]' : null);
      addTearDown(() => mensageiro.setMockMethodCallHandler(MethodChannel(canal), null));
    }
    await tester.runAsync(downloads.carregar);
    await tester.pumpWidget(PegaMidiaApp(settings: settings, api: api, downloads: downloads));

    await tester.tap(find.byIcon(Icons.download));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Renomear'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Tesoura para o bingo');
    await tester.tap(find.widgetWithText(FilledButton, 'Renomear'));
    await tester.pumpAndSettle();
    // renomear o arquivo é E/S de verdade: deixa terminar fora do relógio falso do teste
    for (var i = 0; i < 20 && downloads.itens.single.titulo != 'Tesoura para o bingo'; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.text('Tesoura para o bingo'), findsOneWidget);
    expect(File('${pasta.path}/PegaMidia/Tesoura para o bingo.mp4').existsSync(), isTrue);
    expect(arquivo.existsSync(), isFalse);
  });
}
