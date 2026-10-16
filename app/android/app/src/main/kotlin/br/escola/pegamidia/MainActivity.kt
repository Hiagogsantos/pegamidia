package br.escola.pegamidia

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val trabalho = Executors.newSingleThreadExecutor()
    private val principal = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pegamidia/midia")
            .setMethodCallHandler { chamada, resultado ->
                if (chamada.method != "juntarVideoEAudio") {
                    resultado.notImplemented()
                    return@setMethodCallHandler
                }
                val video = chamada.argument<String>("video")
                val audio = chamada.argument<String>("audio")
                val saida = chamada.argument<String>("saida")
                if (video == null || audio == null || saida == null) {
                    resultado.error("ARGUMENTOS", "Faltam os caminhos dos arquivos.", null)
                    return@setMethodCallHandler
                }
                // Juntar pode levar alguns segundos: roda fora da thread da interface.
                trabalho.execute {
                    try {
                        JuntarMidia.juntar(video, audio, saida)
                        principal.post { resultado.success(null) }
                    } catch (e: Exception) {
                        File(saida).delete()
                        principal.post { resultado.error("FALHA", e.message ?: e.toString(), null) }
                    }
                }
            }
    }
}
