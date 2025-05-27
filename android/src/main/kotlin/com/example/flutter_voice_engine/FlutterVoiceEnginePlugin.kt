package com.example.flutter_voice_engine

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class FlutterVoiceEnginePlugin: FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
  companion object {
    const val METHOD_CHANNEL = "flutter_voice_engine"
    const val AUDIO_CHUNK_CHANNEL = "flutter_voice_engine/audio_chunk"
    const val ERROR_CHANNEL = "flutter_voice_engine/error"
  }

  private lateinit var context: Context
  private lateinit var audioManager: AudioManager
  private var audioChunkSink: EventChannel.EventSink? = null
  private var errorSink: EventChannel.EventSink? = null
  private val scope = CoroutineScope(Dispatchers.Main)

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    context = flutterPluginBinding.applicationContext
    MethodChannel(flutterPluginBinding.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler(this)
    EventChannel(flutterPluginBinding.binaryMessenger, AUDIO_CHUNK_CHANNEL).setStreamHandler(this)
    EventChannel(flutterPluginBinding.binaryMessenger, ERROR_CHANNEL).setStreamHandler(this)
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "initialize" -> {
        val audioConfig = call.argument<Map<String, Any>>("audioConfig")
        val sessionConfig = call.argument<Map<String, Any>>("sessionConfig")
        initialize(audioConfig, sessionConfig, result)
      }
      "startRecording" -> startRecording(result)
      "stopRecording" -> stopRecording(result)
      "playAudioChunk" -> playAudioChunk(call.argument<String>("base64String"), result)
      "stopPlayback" -> stopPlayback(result)
      "shutdown" -> shutdown(result)
      else -> result.notImplemented()
    }
  }

  private fun initialize(audioConfig: Map<String, Any>?, sessionConfig: Map<String, Any>?, result: MethodChannel.Result) {
    try {
      val channels = audioConfig?.get("channels") as? Int ?: 1
      val sampleRate = (audioConfig?.get("sampleRate") as? Double)?.toInt() ?: 48000
      val bitDepth = audioConfig?.get("bitDepth") as? Int ?: 16
      val bufferSize = audioConfig?.get("bufferSize") as? Int ?: 4096
      val amplitudeThreshold = audioConfig?.get("amplitudeThreshold") as? Double ?: 0.05
      val enableAEC = audioConfig?.get("enableAEC") as? Boolean ?: true

      audioManager = AudioManager(
        context, channels, sampleRate, bitDepth, bufferSize, amplitudeThreshold.toFloat(), enableAEC
      )

      val usage = when (sessionConfig?.get("category") as? String) {
        "playAndRecord" -> AudioAttributes.USAGE_VOICE_COMMUNICATION
        "playback" -> AudioAttributes.USAGE_MEDIA
        else -> AudioAttributes.USAGE_MEDIA
      }
      val contentType = when (sessionConfig?.get("mode") as? String) {
        "spokenAudio" -> AudioAttributes.CONTENT_TYPE_SPEECH
        else -> AudioAttributes.CONTENT_TYPE_MUSIC
      }
      val flags = (sessionConfig?.get("options") as? List<String>)?.mapNotNull {
        when (it) {
          "defaultToSpeaker" -> AudioAttributes.FLAG_AUDIBILITY_ENFORCED
          else -> null
        }
      }?.fold(0) { acc, flag -> acc or flag } ?: 0

      audioManager.setupAudioSession(usage, contentType, flags)
      audioManager.setupEngine()
      result.success(null)
    } catch (e: Exception) {
      result.error("INITIALIZATION_FAILED", e.message, null)
    }
  }

  private fun startRecording(result: MethodChannel.Result) {
    scope.launch {
      audioManager.startRecording().receiveAsFlow().collect { base64String ->
        audioChunkSink?.success(base64String)
      }
    }
    scope.launch {
      audioManager.getErrorChannel().receiveAsFlow().collect { error ->
        errorSink?.success(error)
      }
    }
    result.success(null)
  }

  private fun stopRecording(result: MethodChannel.Result) {
    audioManager.stopRecording()
    result.success(null)
  }

  private fun playAudioChunk(base64String: String?, result: MethodChannel.Result) {
    if (base64String == null) {
      result.error("INVALID_ARGUMENTS", "Missing base64String", null)
      return
    }
    audioManager.playAudioChunk(base64String)
    result.success(null)
  }

  private fun stopPlayback(result: MethodChannel.Result) {
    audioManager.stopPlayback()
    result.success(null)
  }

  private fun shutdown(result: MethodChannel.Result) {
    audioManager.shutdown()
    audioChunkSink = null
    errorSink = null
    result.success(null)
  }

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    if (arguments == "error") {
      errorSink = events
    } else {
      audioChunkSink = events
    }
  }

  override fun onCancel(arguments: Any?) {
    if (arguments == "error") {
      errorSink = null
    } else {
      audioChunkSink = null
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    audioManager.shutdown()
  }
}