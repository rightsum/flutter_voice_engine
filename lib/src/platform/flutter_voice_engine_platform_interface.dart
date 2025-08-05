import 'dart:typed_data';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import '../core/audio_config.dart';
import '../core/audio_session_config.dart';
import '../core/audio_processor.dart';
import 'flutter_voice_engine_method_channel.dart';

abstract class FlutterVoiceEnginePlatform extends PlatformInterface {
  FlutterVoiceEnginePlatform() : super(token: _token);
  static final Object _token = Object();
  static FlutterVoiceEnginePlatform _instance = MethodChannelFlutterVoiceEngine();
  static FlutterVoiceEnginePlatform get instance => _instance;
  static set instance(FlutterVoiceEnginePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Stream<Duration> get backgroundMusicPositionStream;
  Stream<Duration> get backgroundMusicDurationStream;
  Stream<bool> get backgroundMusicIsPlayingStream;
  Stream<Uint8List> get audioChunkStream;
  Stream<String> get errorStream;

  Future<void> initialize(
      AudioConfig config,
      AudioSessionConfig sessionConfig,
      List<AudioProcessor> processors,
      );

  Future<void> startRecording();

  Future<void> stopRecording();

  Future<void> playAudioChunk(Uint8List audioData);

  Future<void> stopPlayback();

  Future<void> shutdown();

  Future<void> setAudioChunkHandler(void Function(Uint8List) handler);

  Future<void> setInterruptionHandler(void Function() handler);
}