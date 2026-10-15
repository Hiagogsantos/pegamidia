import 'package:flutter/material.dart';
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
}
