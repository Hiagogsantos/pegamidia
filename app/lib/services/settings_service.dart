import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Configurações salvas no aparelho (endereço do servidor).
class SettingsService extends ChangeNotifier {
  SettingsService(this._prefs);

  static const _chaveServidor = 'servidor_url';

  final SharedPreferences _prefs;

  static Future<SettingsService> carregar() async =>
      SettingsService(await SharedPreferences.getInstance());

  /// Ex.: `http://192.168.0.10:8000`. `null` quando ainda não foi configurado.
  String? get servidor {
    final valor = _prefs.getString(_chaveServidor);
    return (valor == null || valor.isEmpty) ? null : valor;
  }

  bool get temServidor => servidor != null;

  Future<void> salvarServidor(String? url) async {
    if (url == null || url.isEmpty) {
      await _prefs.remove(_chaveServidor);
    } else {
      await _prefs.setString(_chaveServidor, url);
    }
    notifyListeners();
  }
}
