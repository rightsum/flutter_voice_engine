import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import '../platform/flutter_voice_engine_platform_interface.dart';
import 'audio_config.dart';
import 'audio_session_config.dart';

class FlutterVoiceEngine {
  static const MethodChannel _channel = MethodChannel('flutter_voice_engine');
  static const EventChannel _eventChannel = EventChannel(
    'flutter_voice_engine/events',
  );

  AudioConfig audioConfig = AudioConfig();
  AudioSessionConfig sessionConfig = AudioSessionConfig();
  bool isInitialized = false;
  bool isRecording = false;

  final _audioChunkController = StreamController.broadcast();
  final _musicPositionController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _musicStateController = StreamController.broadcast();
  final _errorController = StreamController.broadcast();

  FlutterVoiceEngine() {
    print('FlutterVoiceEngine: Constructor called');
    _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is Map) {
          final type = event['type'] as String?;
          switch (type) {
            case 'audio_chunk':
              final data = event['data'];
              if (data is Uint8List) {
                _audioChunkController.add(data);
              } else {
                _errorController.add(
                  'Invalid audio chunk data type: ${data.runtimeType}',
                );
              }
              break;
            case 'music_position':
              final position = event['position'] as double?;
              final duration = event['duration'] as double?;
              if (position != null && duration != null) {
                _musicPositionController.add({
                  'position': position,
                  'duration': duration,
                });
              } else {
                _errorController.add('Invalid music position data: $event');
              }
              break;
            case 'music_state':
              final state = event['state'] as bool?;
              if (state != null) {
                print('Flutter: Received music state: $state');
                _musicStateController.add(state);
              } else {
                print(
                  'Flutter: Invalid music state data: ${event['state'].runtimeType}',
                );
                _errorController.add(
                  'Invalid music state data: ${event['state'].runtimeType}',
                );
              }
              break;
            case 'error':
              final message = event['message'] as String?;
              if (message != null) {
                _errorController.add(message);
              }
              break;
            default:
              _errorController.add('Unknown event type: $type');
          }
        } else {
          _errorController.add('Invalid event data type: ${event.runtimeType}');
        }
      },
      onError: (error) {
        _errorController.add('Event stream error: $error');
      },
      onDone: () {
        _errorController.add('Event stream closed');
      },
    );
  }

  Stream get audioChunkStream => _audioChunkController.stream;
  Stream<Map<String, dynamic>> get musicPositionStream =>
      _musicPositionController.stream;
  Stream get musicStateStream => _musicStateController.stream;
  Stream get errorStream => _errorController.stream;

  Future initialize() async {
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

  Future startRecording() async {
    if (!isInitialized) {
      throw Exception('VoiceEngine not initialized');
    }
    print('Flutter: Starting recording');
    await _channel.invokeMethod('startRecording');
    isRecording = true;
  }

  Future stopRecording() async {
    if (!isInitialized || !isRecording) {
      print('Flutter: Not recording or not initialized');
      return;
    }
    print('Flutter: Stopping recording');
    await _channel.invokeMethod('stopRecording');
    isRecording = false;
  }

  Future playAudioChunk(Uint8List audioData) async {
    if (!isInitialized) {
      throw Exception('VoiceEngine not initialized');
    }
    try {
      print('Flutter: Playing audio chunk, size: ${audioData.length} bytes');
      await _channel.invokeMethod('playAudioChunk', {'audioData': audioData});
    } catch (e) {
      print('Flutter: Playback failed: $e');
      rethrow;
    }
  }

  Future stopPlayback() async {
    if (!isInitialized) {
      print('Flutter: Not initialized');
      return;
    }
    print('Flutter: Stopping playback');
    await _channel.invokeMethod('stopPlayback');
  }

  Future shutdownBot() async {
    if (!isInitialized) {
      print('Flutter: Not initialized');
      return;
    }
    print('Flutter: Shutting down only bot (music continues)');
    await _channel.invokeMethod('shutdownBot');
    isRecording = false;
  }

  Future shutdownAll() async {
    if (!isInitialized) {
      print('Flutter: Not initialized');
      return;
    }
    print('Flutter: Shutting down everything (bot + music)');
    await _channel.invokeMethod('shutdownAll');
    isInitialized = false;
    isRecording = false;
    await _audioChunkController.close();
    await _musicPositionController.close();
    await _musicStateController.close();
    await _errorController.close();
  }

  Future playBackgroundMusic(String source, {bool loop = true}) async {
    if (!isInitialized) throw Exception('VoiceEngine not initialized');
    await _channel.invokeMethod('playBackgroundMusic', {
      'source': source,
      'loop': loop,
    });
  }

  Future playBackgroundMusicPlaylist(
    List sources, {
    String loopMode = 'none',
  }) async {
    if (!isInitialized) throw Exception('VoiceEngine not initialized');
    await _channel.invokeMethod('playBackgroundMusicPlaylist', {
      'sources': sources,
      'loopMode': loopMode,
    });
  }

  Future stopBackgroundMusic() async {
    if (!isInitialized) {
      throw Exception('VoiceEngine not initialized');
    }
    print('Flutter: Stopping background music');
    await _channel.invokeMethod('stopBackgroundMusic');
  }

  Future setBackgroundMusicVolume(double volume) async {
    if (!isInitialized) throw Exception('VoiceEngine not initialized');
    await _channel.invokeMethod('setBackgroundMusicVolume', {'volume': volume});
  }

  Future getBackgroundMusicVolume() async {
    if (!isInitialized) throw Exception('VoiceEngine not initialized');
    final vol = await _channel.invokeMethod('getBackgroundMusicVolume');
    return (vol as num).toDouble();
  }

  Future seekBackgroundMusic(Duration position) async {
    if (!isInitialized) throw Exception('VoiceEngine not initialized');
    await _channel.invokeMethod('seekBackgroundMusic', {
      'position': position.inMilliseconds / 1000.0,
    });
  }

  Stream get backgroundMusicDurationStream => musicPositionStream.map(
    (event) => Duration(milliseconds: (event['duration'] * 1000).round()),
  );

  Stream get backgroundMusicPositionStream => musicPositionStream.map(
    (event) => Duration(milliseconds: (event['position'] * 1000).round()),
  );

  Stream get backgroundMusicIsPlayingStream => musicStateStream;
}
