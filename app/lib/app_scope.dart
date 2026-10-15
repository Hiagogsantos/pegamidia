import 'package:flutter/widgets.dart';

import 'services/download_manager.dart';
import 'services/server_api.dart';
import 'services/settings_service.dart';

/// Dá acesso aos serviços do app em qualquer tela: `AppScope.of(context)`.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.settings,
    required this.api,
    required this.downloads,
    required super.child,
  });

  final SettingsService settings;
  final ServerApi api;
  final DownloadManager downloads;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope não encontrado');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      settings != oldWidget.settings || api != oldWidget.api || downloads != oldWidget.downloads;
}
