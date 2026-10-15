/// Constantes do app. O nome aparece em um único lugar: [appName].
library;

const String appName = 'PegaMídia';
const String appVersion = '1.0.0';

/// Gmail, Outlook e similares limitam anexos a ~25 MB.
const int limiteAnexoEmailBytes = 25 * 1024 * 1024;

/// Exemplo mostrado na tela de configurações.
const String exemploServidor = 'http://192.168.0.10:8000';

const List<String> qualidadesVideo = ['720p', '480p', '360p', 'melhor'];
const String qualidadePadrao = '720p';
