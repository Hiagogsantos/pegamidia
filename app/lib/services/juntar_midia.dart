import 'package:flutter/services.dart';

/// Junta um MP4 só com imagem e outro só com som num MP4 normal.
typedef JuntarVideoEAudio = Future<void> Function(String video, String audio, String saida);

/// Implementação Android (MediaMuxer, sem bibliotecas extras): ver `MainActivity.kt`.
/// Em outras plataformas lança [MissingPluginException].
Future<void> juntarNoAparelho(String video, String audio, String saida) async {
  const canal = MethodChannel('pegamidia/midia');
  await canal.invokeMethod<void>('juntarVideoEAudio', {
    'video': video,
    'audio': audio,
    'saida': saida,
  });
}
