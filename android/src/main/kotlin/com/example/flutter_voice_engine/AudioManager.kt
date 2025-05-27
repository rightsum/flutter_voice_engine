package com.example.flutter_voice_engine

import android.content.Context
import android.media.*
import android.util.Base64
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel

class AudioManager(
    private val context: Context,
    private val channels: Int,
    private val sampleRate: Int,
    private val bitDepth: Int,
    private val bufferSize: Int,
    private val amplitudeThreshold: Float,
    private val enableAEC: Boolean
) {
    private var audioRecord: AudioRecord? = null
    private var audioTrack: AudioTrack? = null
    private var isRecording = AtomicBoolean(false)
    private val audioChunkChannel = Channel<String>(Channel.UNLIMITED)
    private val errorChannel = Channel<String>(Channel.UNLIMITED)
    private var recordingJob: Job? = null
    private val scope = CoroutineScope(Dispatchers.IO)

    fun setupAudioSession(
        usage: Int,
        contentType: Int,
        flags: Int
    ) {
        val audioAttributes = AudioAttributes.Builder()
            .setUsage(usage)
            .setContentType(contentType)
            .setFlags(flags)
            .build()
        val audioFocusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(audioAttributes)
            .build()
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioManager.requestAudioFocus(audioFocusRequest)
    }

    fun setupEngine() {
        val channelConfig = if (channels == 1) AudioFormat.CHANNEL_IN_MONO else AudioFormat.CHANNEL_IN_STEREO
        val audioFormat = if (bitDepth == 16) AudioFormat.ENCODING_PCM_16BIT else AudioFormat.ENCODING_PCM_FLOAT
        val minBufferSize = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)

        audioRecord = AudioRecord(
            MediaRecorder.AudioSource.MIC,
            sampleRate,
            channelConfig,
            audioFormat,
            bufferSize.coerceAtLeast(minBufferSize)
        )

        val trackChannelConfig = if (channels == 1) AudioFormat.CHANNEL_OUT_MONO else AudioFormat.CHANNEL_OUT_STEREO
        audioTrack = AudioTrack(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build(),
            AudioFormat.Builder()
                .setSampleRate(sampleRate)
                .setChannelMask(trackChannelConfig)
                .setEncoding(audioFormat)
                .build(),
            Math.max(bufferSize, minBufferSize),
            AudioTrack.MODE_STREAM,
            AudioManager.AUDIO_SESSION_ID_GENERATE
        )

        if (enableAEC && AcousticEchoCanceler.isAvailable()) {
            AcousticEchoCanceler.create(audioRecord?.audioSessionId)?.apply { enabled = true }
        }
    }

    fun startRecording(): Channel<String> {
        if (isRecording.getAndSet(true)) return audioChunkChannel
        audioRecord?.startRecording()
        recordingJob = scope.launch {
            val buffer = ByteArray(bufferSize)
            try {
                while (isRecording.get()) {
                    val read = audioRecord?.read(buffer, 0, buffer.size) ?: 0
                    if (read > 0) {
                        val amplitude = calculateAmplitude(buffer, read)
                        if (audioTrack?.playState == AudioTrack.PLAYSTATE_PLAYING && amplitude < amplitudeThreshold) {
                            continue
                        }
                        val base64String = Base64.encodeToString(buffer, 0, read, Base64.NO_WRAP)
                        audioChunkChannel.send(base64String)
                    } else if (read < 0) {
                        errorChannel.send("Recording error: $read")
                    }
                }
            } catch (e: Exception) {
                errorChannel.send("Recording failed: ${e.message}")
            }
        }
        return audioChunkChannel
    }

    fun stopRecording() {
        if (isRecording.getAndSet(false)) {
            recordingJob?.cancel()
            audioRecord?.stop()
            audioChunkChannel.close()
        }
    }

    fun playAudioChunk(base64String: String) {
        try {
            val data = Base64.decode(base64String, Base64.NO_WRAP)
            audioTrack?.write(data, 0, data.size)
            if (audioTrack?.playState != AudioTrack.PLAYSTATE_PLAYING) {
                audioTrack?.play()
            }
        } catch (e: Exception) {
            errorChannel.send("Playback failed: ${e.message}")
        }
    }

    fun stopPlayback() {
        audioTrack?.pause()
        audioTrack?.flush()
    }

    fun shutdown() {
        stopRecording()
        stopPlayback()
        audioRecord?.release()
        audioTrack?.release()
        audioRecord = null
        audioTrack = null
        scope.cancel()
    }

    private fun calculateAmplitude(buffer: ByteArray, read: Int): Float {
        val shorts = ShortArray(read / 2)
        ByteBuffer.wrap(buffer).asShortBuffer().get(shorts)
        return shorts.maxOfOrNull { Math.abs(it.toFloat()) } ?: 0f
    }

    fun getErrorChannel(): Channel<String> = errorChannel
}