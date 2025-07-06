package com.example.flutter_voice_engine

import android.content.Context
import android.media.*
import android.util.Log
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import java.util.concurrent.atomic.AtomicBoolean
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.AutomaticGainControl
import android.media.audiofx.NoiseSuppressor
import android.media.AudioManager as AndroidAudioManager


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
    private var aec: AcousticEchoCanceler? = null
    private var ns: NoiseSuppressor? = null

    private var isRecording = AtomicBoolean(false)
    private val audioChunkChannel = Channel<ByteArray>(Channel.UNLIMITED)
    private val errorChannel = Channel<String>(Channel.UNLIMITED)
    private var recordingJob: Job? = null
    private val scope = CoroutineScope(Dispatchers.IO)

    fun setupEngine() {
        val channelConfig = if (channels == 1) AudioFormat.CHANNEL_IN_MONO else AudioFormat.CHANNEL_IN_STEREO
        val audioFormat = AudioFormat.ENCODING_PCM_16BIT
        val minBufferSize = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)

        audioRecord = AudioRecord(
            MediaRecorder.AudioSource.VOICE_COMMUNICATION,
            sampleRate,
            channelConfig,
            audioFormat,
            bufferSize.coerceAtLeast(minBufferSize)
        )

        if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
            errorChannel.trySend("AudioRecord initialization failed")
            return
        }

        if (enableAEC && AcousticEchoCanceler.isAvailable()) {
            aec = AcousticEchoCanceler.create(audioRecord!!.audioSessionId)
            aec?.enabled = true
        }

        if (NoiseSuppressor.isAvailable()) {
            ns = NoiseSuppressor.create(audioRecord!!.audioSessionId)
            ns?.enabled = true
        }

        if (AutomaticGainControl.isAvailable()) {
            val agc = AutomaticGainControl.create(audioRecord!!.audioSessionId)
            agc.enabled = true
        }

        val playbackSampleRate = 24000

        val trackChannelConfig = if (channels == 1) AudioFormat.CHANNEL_OUT_MONO else AudioFormat.CHANNEL_OUT_STEREO
        audioTrack = AudioTrack(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build(),
            AudioFormat.Builder()
                .setSampleRate(playbackSampleRate)
                .setChannelMask(trackChannelConfig)
                .setEncoding(audioFormat)
                .build(),
            bufferSize.coerceAtLeast(minBufferSize),
            AudioTrack.MODE_STREAM,
            AndroidAudioManager.AUDIO_SESSION_ID_GENERATE
        )

        if (audioTrack?.state != AudioTrack.STATE_INITIALIZED) {
            errorChannel.trySend("AudioTrack initialization failed")
            return
        }

        audioTrack?.setVolume(1.0f)
    }

    fun startRecording(): Channel<ByteArray> {
        if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
            errorChannel.trySend("Cannot start recording, AudioRecord not initialized")
            return audioChunkChannel
        }

        if (isRecording.getAndSet(true)) return audioChunkChannel
        audioRecord?.startRecording()
        recordingJob = scope.launch {
            val buffer = ByteArray(bufferSize)
            try {
                while (isRecording.get()) {
                    val read = audioRecord?.read(buffer, 0, buffer.size) ?: 0
                    if (read > 0) {
                        val audioData = buffer.copyOf(read)
                        audioChunkChannel.send(audioData)
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
        }
    }

    fun playAudioChunk(audioData: ByteArray) {
        try {
            audioTrack?.write(audioData, 0, audioData.size)
            if (audioTrack?.playState != AudioTrack.PLAYSTATE_PLAYING) {
                audioTrack?.play()
            }
        } catch (e: Exception) {
            errorChannel.trySend("Playback failed: ${e.message}")
        }
    }

    fun stopPlayback() {
        audioTrack?.pause()
        audioTrack?.flush()
    }

    fun shutdown() {
        stopRecording()
        stopPlayback()
        aec?.release()
        ns?.release()
        audioRecord?.release()
        audioTrack?.release()
        audioRecord = null
        audioTrack = null
        scope.cancel()
    }

    fun getErrorChannel(): Channel<String> = errorChannel
}
