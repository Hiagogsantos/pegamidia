# PegaMídia — app Flutter

Veja o [README principal](../README.md) para instruções de uso, do servidor e de como gerar o APK.

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```

Estrutura:

- `lib/config.dart` — nome do app (`appName`) e constantes.
- `lib/screens/` — Início, Downloads, Configurações, Sobre e a captura pela página (WebView).
- `lib/services/` — cliente do servidor (`dio`), fila de downloads, configurações e utilitários de links.
