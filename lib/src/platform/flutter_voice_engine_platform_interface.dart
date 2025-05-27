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

  Future<void> initialize(
      AudioConfig config,
      AudioSessionConfig sessionConfig,
      List<AudioProcessor> processors,
      ) {
    throw UnimplementedError('initialize() has not been implemented.');
  }

  Future<void> startRecording() {
    throw UnimplementedError('startRecording() has not been implemented.');
  }

  Future<void> stopRecording() {
    throw UnimplementedError('stopRecording() has not been implemented.');
  }

  Future<void> playAudioChunk(String base64String) {
    throw UnimplementedError('playAudioChunk() has not been implemented.');
  }

  Future<void> stopPlayback() {
    throw UnimplementedError('stopPlayback() has not been implemented.');
  }

  Future<void> shutdown() {
    throw UnimplementedError('shutdown() has not been implemented.');
  }

  Future<void> setAudioChunkHandler(void Function(Uint8List) handler) {
    throw UnimplementedError('setAudioChunkHandler() has not been implemented.');
  }

  Future<void> setInterruptionHandler(void Function() handler) {
    throw UnimplementedError('setInterruptionHandler() has not been implemented.');
  }
}