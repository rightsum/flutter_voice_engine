import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../core/audio_config.dart';
import '../core/audio_session_config.dart';
import '../core/audio_processor.dart';
import 'flutter_voice_engine_platform_interface.dart';

class MethodChannelFlutterVoiceEngine extends FlutterVoiceEnginePlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_voice_engine');
  final eventChannel = const EventChannel('flutter_voice_engine/audio_chunk');

  @override
  Future<void> initialize(
      AudioConfig config,
      AudioSessionConfig sessionConfig,
      List<AudioProcessor> processors,
      ) async {
    await methodChannel.invokeMethod('initialize', {
      'audioConfig': config.toMap(),
      'sessionConfig': sessionConfig.toMap(),
      'processors': processors.map((p) => p.toMap()).toList(),
    });
  }

  @override
  Future<void> startRecording() async {
    await methodChannel.invokeMethod('startRecording');
  }

  @override
  Future<void> stopRecording() async {
    await methodChannel.invokeMethod('stopRecording');
  }

  @override
  Future<void> playAudioChunk(String base64String) async {
    await methodChannel.invokeMethod('playAudioChunk', {'base64String': base64String});
  }

  @override
  Future<void> stopPlayback() async {
    await methodChannel.invokeMethod('stopPlayback');
  }

  @override
  Future<void> shutdown() async {
    await methodChannel.invokeMethod('shutdown');
  }

  @override
  Future<void> setAudioChunkHandler(void Function(Uint8List) handler) async {
    eventChannel.receiveBroadcastStream().listen((data) {
      print('MethodChannel: Received data type: ${data.runtimeType}');
      if (data is Uint8List) {
        print('MethodChannel: Received audio chunk, size: ${data.length} bytes');
        handler(data);
      } else {
        print('MethodChannel: Invalid audio chunk data type: ${data.runtimeType}');
      }
    }, onError: (error) {
      print('MethodChannel: Audio chunk stream error: $error');
    }, onDone: () {
      print('MethodChannel: Audio chunk stream closed');
    });
  }
}