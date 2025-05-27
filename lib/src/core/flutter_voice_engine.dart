import 'dart:async';
import 'package:flutter/foundation.dart';
import '../platform/flutter_voice_engine_platform_interface.dart';
import 'audio_config.dart';
import 'audio_session_config.dart';
import 'audio_processor.dart';

class FlutterVoiceEngine {
  FlutterVoiceEngine._(); // Private constructor for singleton
  static final FlutterVoiceEngine _instance = FlutterVoiceEngine._();
  factory FlutterVoiceEngine() => _instance;

  final _platform = FlutterVoiceEnginePlatform.instance;
  AudioConfig _audioConfig = AudioConfig();
  AudioSessionConfig _sessionConfig = AudioSessionConfig();
  bool _isInitialized = false;
  bool _isRecording = false;
  bool _isPlaying = false;
  StreamController<String>? _audioChunkController;
  StreamController<String>? _errorController;
  VoidCallback? _onInterruption;

  // Getters
  AudioConfig get audioConfig => _audioConfig;
  AudioSessionConfig get sessionConfig => _sessionConfig;
  bool get isInitialized => _isInitialized;
  bool get isRecording => _isRecording;
  bool get isPlaying => _isPlaying;
  Stream<String> get audioChunkStream => _audioChunkController?.stream ?? const Stream.empty();
  Stream<String> get errorStream => _errorController?.stream ?? const Stream.empty();

  // Setters
  set audioConfig(AudioConfig config) {
    if (_isInitialized) throw StateError('Cannot change config after initialization');
    _audioConfig = config;
  }

  set sessionConfig(AudioSessionConfig config) {
    if (_isInitialized) throw StateError('Cannot change session config after initialization');
    _sessionConfig = config;
  }

  set onInterruption(VoidCallback? callback) => _onInterruption = callback;

  Future<void> initialize({List<AudioProcessor>? processors}) async {
    if (_isInitialized) return;
    try {
      await _platform.initialize(_audioConfig, _sessionConfig, processors ?? []);
      _audioChunkController = StreamController.broadcast();
      _errorController = StreamController.broadcast();
      await _platform.setAudioChunkHandler((base64String) {
        _audioChunkController?.add(base64String);
      });
      await _platform.setErrorHandler((error) {
        _errorController?.add(error);
      });
      await _platform.setInterruptionHandler(() {
        _onInterruption?.call();
      });
      _isInitialized = true;
    } catch (e) {
      throw Exception('Failed to initialize FlutterVoiceEngine: $e');
    }
  }

  Future<void> startRecording() async {
    if (!_isInitialized) throw StateError('FlutterVoiceEngine not initialized');
    if (_isRecording) return;
    try {
      await _platform.startRecording();
      _isRecording = true;
    } catch (e) {
      throw Exception('Failed to start recording: $e');
    }
  }

  Future<void> stopRecording() async {
    if (!_isRecording) return;
    try {
      await _platform.stopRecording();
      _isRecording = false;
    } catch (e) {
      throw Exception('Failed to stop recording: $e');
    }
  }

  Future<void> playAudioChunk(String base64String) async {
    if (!_isInitialized) throw StateError('FlutterVoiceEngine not initialized');
    try {
      await _platform.playAudioChunk(base64String);
      _isPlaying = true;
    } catch (e) {
      throw Exception('Failed to play audio chunk: $e');
    }
  }

  Future<void> stopPlayback() async {
    if (!_isPlaying) return;
    try {
      await _platform.stopPlayback();
      _isPlaying = false;
    } catch (e) {
      throw Exception('Failed to stop playback: $e');
    }
  }

  Future<void> shutdown() async {
    try {
      await _platform.shutdown();
      await _audioChunkController?.close();
      await _errorController?.close();
      _isInitialized = false;
      _isRecording = false;
      _isPlaying = false;
    } catch (e) {
      throw Exception('Failed to shutdown FlutterVoiceEngine: $e');
    }
  }
}