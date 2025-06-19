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
  final _musicPositionChannel = EventChannel('flutter_voice_engine/music_position');
  final _musicStateChannel = EventChannel('flutter_voice_engine/music_state');

  late final Stream<dynamic> _musicPositionRawStream;

  MethodChannelFlutterVoiceEngine() {
    _musicPositionRawStream = _musicPositionChannel
        .receiveBroadcastStream()
        .map((event) {
      if (event is Map) return event;
      print('music_position channel received unexpected type: ${event.runtimeType} ($event)');
      return <dynamic, dynamic>{}; // Empty map as fallback.
    }).cast<Map<dynamic, dynamic>>();
  }

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

  @override
  Stream<Duration> get backgroundMusicPositionStream =>
      _musicPositionRawStream.map((event) {
        final position = (event['position'] as num?)?.toDouble() ?? 0.0;
        return Duration(milliseconds: (position * 1000).round());
      });

  @override
  Stream<Duration> get backgroundMusicDurationStream =>
      _musicPositionRawStream.map((event) {
        final duration = (event['duration'] as num?)?.toDouble() ?? 0.0;
        return Duration(milliseconds: (duration * 1000).round());
      });

  @override
  Stream<bool> get backgroundMusicIsPlayingStream =>
      _musicStateChannel.receiveBroadcastStream().map((event) => event == true);
}