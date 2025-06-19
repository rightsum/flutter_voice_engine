import 'dart:async';
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
  final eventChannel = const EventChannel('flutter_voice_engine/events');

  final _audioChunkController = StreamController<Uint8List>.broadcast();
  final _musicPositionController = StreamController<Map<String, dynamic>>.broadcast();
  final _musicStateController = StreamController<bool>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  MethodChannelFlutterVoiceEngine() {
    print('MethodChannelFlutterVoiceEngine: Constructor called');
    eventChannel.receiveBroadcastStream().listen(
          (dynamic event) {
        print('MethodChannel: Received event: $event');
        if (event is Map) {
          final type = event['type'] as String?;
          switch (type) {
            case 'audio_chunk':
              final data = event['data'];
              if (data is Uint8List) {
                print('MethodChannel: Received audio chunk, size: ${data.length} bytes');
                _audioChunkController.add(data);
              } else {
                print('MethodChannel: Invalid audio chunk data type: ${data.runtimeType}');
                _errorController.add('Invalid audio chunk data type: ${data.runtimeType}');
              }
              break;
            case 'music_position':
              final position = event['position'] as num?;
              final duration = event['duration'] as num?;
              if (position != null && duration != null) {
                print('MethodChannel: Received music position: position=$position, duration=$duration');
                _musicPositionController.add({'position': position.toDouble(), 'duration': duration.toDouble()});
              } else {
                print('MethodChannel: Invalid music position data: $event');
                _errorController.add('Invalid music position data: $event');
              }
              break;
            case 'music_state':
              final state = event['state'] as bool?;
              if (state != null) {
                print('MethodChannel: Received music state: $state');
                _musicStateController.add(state);
              } else {
                print('MethodChannel: Invalid music state data: ${event['state'].runtimeType}');
                _errorController.add('Invalid music state data: ${event['state'].runtimeType}');
              }
              break;
            case 'error':
              final message = event['message'] as String?;
              if (message != null) {
                print('MethodChannel: Received error: $message');
                _errorController.add(message);
              }
              break;
            default:
              print('MethodChannel: Unknown event type: $type');
              _errorController.add('Unknown event type: $type');
          }
        } else {
          print('MethodChannel: Invalid event data type: ${event.runtimeType}');
          _errorController.add('Invalid event data type: ${event.runtimeType}');
        }
      },
      onError: (error) {
        print('MethodChannel: Event stream error: $error');
        _errorController.add('Event stream error: $error');
      },
      onDone: () {
        print('MethodChannel: Event stream closed');
        _errorController.add('Event stream closed');
      },
    );
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
    await methodChannel.invokeMethod('shutdownAll');
  }

  @override
  Future<void> setAudioChunkHandler(void Function(Uint8List) handler) async {
    _audioChunkController.stream.listen(handler);
  }

  @override
  Stream<Duration> get backgroundMusicPositionStream =>
      _musicPositionController.stream.map((event) => Duration(milliseconds: (event['position'] * 1000).round()));

  @override
  Stream<Duration> get backgroundMusicDurationStream =>
      _musicPositionController.stream.map((event) => Duration(milliseconds: (event['duration'] * 1000).round()));

  @override
  Stream<bool> get backgroundMusicIsPlayingStream => _musicStateController.stream;

  Stream<String> get errorStream => _errorController.stream;

  @override
  // TODO: implement audioChunkStream
  Stream<Uint8List> get audioChunkStream => _audioChunkController.stream;

  @override
  Future<void> setInterruptionHandler(void Function() handler) {
    throw UnimplementedError();
  }
}