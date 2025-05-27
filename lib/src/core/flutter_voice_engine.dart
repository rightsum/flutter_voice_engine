import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'audio_config.dart';
import 'audio_session_config.dart';

class FlutterVoiceEngine {
  static const MethodChannel _channel = MethodChannel('flutter_voice_engine');
  static const EventChannel _audioChunkChannel = EventChannel('flutter_voice_engine/audio_chunk');

  AudioConfig audioConfig = AudioConfig();
  AudioSessionConfig sessionConfig = AudioSessionConfig();
  bool isInitialized = false;
  bool isRecording = false;

  final _audioChunkController = StreamController<Uint8List>.broadcast();

  FlutterVoiceEngine() {
    _audioChunkChannel.receiveBroadcastStream().listen(
          (dynamic data) {
        if (data is Uint8List) {
          print('Flutter: Received audio chunk, size: ${data.length} bytes');
          _audioChunkController.add(data);
        } else {
          print('Flutter: Invalid audio chunk data type: ${data.runtimeType}');
        }
      },
      onError: (error) {
        print('Flutter: Audio chunk stream error: $error');
      },
      onDone: () {
        print('Flutter: Audio chunk stream closed');
      },
    );
  }

  Stream<Uint8List> get audioChunkStream => _audioChunkController.stream;

  Future<void> initialize() async {
    try {
      print('Flutter: Initializing VoiceEngine');
      await _channel.invokeMethod('initialize', {
        'audioConfig': audioConfig.toMap(),
        'sessionConfig': sessionConfig.toMap(),
        'processors': [],
      });
      isInitialized = true;
      print('Flutter: VoiceEngine initialized');
    } catch (e) {
      isInitialized = false;
      print('Flutter: Initialization failed: $e');
      rethrow;
    }
  }

  Future<void> startRecording() async {
    if (!isInitialized) {
      throw Exception('VoiceEngine not initialized');
    }
    print('Flutter: Starting recording');
    await _channel.invokeMethod('startRecording');
    isRecording = true;
  }

  Future<void> stopRecording() async {
    if (!isInitialized || !isRecording) {
      print('Flutter: Not recording or not initialized');
      return;
    }
    print('Flutter: Stopping recording');
    await _channel.invokeMethod('stopRecording');
    isRecording = false;
  }

  Future<void> playAudioChunk(Uint8List audioData) async {
    if (!isInitialized) {
      throw Exception('VoiceEngine not initialized');
    }
    try {
      print('Flutter: Playing audio chunk, size: ${audioData.length} bytes');
      await _channel.invokeMethod('playAudioChunk', {
        'audioData': audioData,
      });
    } catch (e) {
      print('Flutter: Playback failed: $e');
      rethrow;
    }
  }

  Future<void> stopPlayback() async {
    if (!isInitialized) {
      print('Flutter: Not initialized');
      return;
    }
    print('Flutter: Stopping playback');
    await _channel.invokeMethod('stopPlayback');
  }

  Future<void> shutdown() async {
    if (!isInitialized) {
      print('Flutter: Not initialized');
      return;
    }
    print('Flutter: Shutting down VoiceEngine');
    await _channel.invokeMethod('shutdown');
    isInitialized = false;
    isRecording = false;
    await _audioChunkController.close();
  }
}