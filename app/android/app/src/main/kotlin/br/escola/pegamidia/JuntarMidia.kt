package br.escola.pegamidia

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import java.nio.ByteBuffer

/**
 * Junta um MP4 só com imagem e outro só com som (como o Instagram e o Facebook
 * entregam os vídeos) num MP4 normal, sem reconverter nada: só copia as amostras.
 * Usa o MediaMuxer do próprio Android, então não aumenta o tamanho do app.
 */
object JuntarMidia {
    private const val CHAVE_ROTACAO = "rotation-degrees" // MediaFormat.KEY_ROTATION (API 23+)

    fun juntar(caminhoVideo: String, caminhoAudio: String, caminhoSaida: String) {
        val video = MediaExtractor()
        val audio = MediaExtractor()
        var muxer: MediaMuxer? = null
        try {
            video.setDataSource(caminhoVideo)
            audio.setDataSource(caminhoAudio)
            val trilhaVideo = acharTrilha(video, "video/")
                ?: throw IllegalArgumentException("O arquivo de vídeo não tem imagem.")
            val trilhaAudio = acharTrilha(audio, "audio/")
                ?: throw IllegalArgumentException("O arquivo de áudio não tem som.")
            video.selectTrack(trilhaVideo)
            audio.selectTrack(trilhaAudio)
            val formatoVideo = video.getTrackFormat(trilhaVideo)
            val formatoAudio = audio.getTrackFormat(trilhaAudio)

            val m = MediaMuxer(caminhoSaida, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            muxer = m
            if (formatoVideo.containsKey(CHAVE_ROTACAO)) {
                m.setOrientationHint(formatoVideo.getInteger(CHAVE_ROTACAO))
            }
            val saidaVideo = m.addTrack(formatoVideo)
            val saidaAudio = m.addTrack(formatoAudio)
            m.start()
            copiar(video, m, saidaVideo, formatoVideo)
            copiar(audio, m, saidaAudio, formatoAudio)
            m.stop()
        } finally {
            try {
                muxer?.release()
            } catch (_: Exception) {
            }
            video.release()
            audio.release()
        }
    }

    private fun acharTrilha(extrator: MediaExtractor, prefixo: String): Int? {
        for (i in 0 until extrator.trackCount) {
            val mime = extrator.getTrackFormat(i).getString(MediaFormat.KEY_MIME) ?: continue
            if (mime.startsWith(prefixo)) return i
        }
        return null
    }

    private fun copiar(extrator: MediaExtractor, muxer: MediaMuxer, trilha: Int, formato: MediaFormat) {
        val capacidade = if (formato.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
            maxOf(formato.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE), 1 shl 20)
        } else {
            4 shl 20
        }
        val buffer = ByteBuffer.allocate(capacidade)
        val info = MediaCodec.BufferInfo()
        while (true) {
            buffer.clear()
            val lidos = extrator.readSampleData(buffer, 0)
            if (lidos < 0) break
            val chave = (extrator.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC) != 0
            info.set(0, lidos, extrator.sampleTime, if (chave) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0)
            muxer.writeSampleData(trilha, buffer, info)
            extrator.advance()
        }
    }
}
