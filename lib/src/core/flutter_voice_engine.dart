import 'dart:async';
import 'dart:typed_data';
import 'audio_config.dart';
import 'audio_session_config.dart';
import 'audio_processor.dart';
import '../platform/flutter_voice_engine_platform_interface.dart';

class FlutterVoiceEngine {
  AudioConfig audioConfig = AudioConfig();
  AudioSessionConfig sessionConfig = AudioSessionConfig();
  bool isInitialized = false;
  bool isRecording = false;

  final _platform = FlutterVoiceEnginePlatform.instance;

  FlutterVoiceEngine() {
    // Set up stream listeners from platform
    _platform.audioChunkStream.listen(_audioChunkController.add);
    _platform.backgroundMusicPositionStream.listen((duration) {
      _musicPositionController.add({
        'position': duration.inMilliseconds / 1000.0,
        'duration': duration.inMilliseconds / 1000.0, // Simplified for now
      });
    });
    _platform.backgroundMusicIsPlayingStream.listen(_musicStateController.add);
    _platform.errorStream.listen(_errorController.add);
  }

  final _audioChunkController = StreamController<Uint8List>.broadcast();
  final _musicPositionController = StreamController<Map<String, double>>.broadcast();
  final _musicStateController = StreamController<bool>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  /// Streams
  Stream<Uint8List> get audioChunkStream => _audioChunkController.stream;

  Stream<Map<String, double>> get musicPositionStream =>
      _musicPositionController.stream;

  Stream<bool> get musicStateStream => _musicStateController.stream;

  Stream<String> get errorStream => _errorController.stream;

  /// Converters for nicer Dart-level streams:
  Stream<Duration> get backgroundMusicPositionStream =>
      musicPositionStream.map((m) => Duration(
          milliseconds: (m['position']! * 1000).round()));

  Stream<Duration> get backgroundMusicDurationStream => musicPositionStream.map((event) {
    final d = event['duration'] as double;
    final ms = d.isFinite ? (d * 1000).round() : 0;
    return Duration(milliseconds: ms);
  });


  Stream<bool> get backgroundMusicIsPlayingStream =>
      musicStateStream;

  /// Initialization
  Future<void> initialize([
    AudioConfig? config,
    AudioSessionConfig? sessionConfig,
    List<AudioProcessor>? processors,
  ]) async {
    if (config != null) audioConfig = config;
    if (sessionConfig != null) this.sessionConfig = sessionConfig;
    
    await _platform.initialize(
      audioConfig,
      this.sessionConfig,
      processors ?? [],
    );
    isInitialized = true;
  }

  /// Recording
  Future<void> startRecording() async {
    if (!isInitialized) throw Exception('VoiceEngine not initialized');
    await _platform.startRecording();
    isRecording = true;
  }

  Future<void> stopRecording() async {
    if (!isInitialized || !isRecording) return;
    await _platform.stopRecording();
    isRecording = false;
  }

  Future<void> playAudioChunk(Uint8List data) async {
    if (!isInitialized) throw Exception('VoiceEngine not initialized');
    // Pass Uint8List directly to platform interface
    await _platform.playAudioChunk(data);
  }

  Future<void> stopPlayback() async {
    if (!isInitialized) return;
    await _platform.stopPlayback();
  }

  /// Background Music (Platform-specific - may not be available on all platforms)
  Future<void> playBackgroundMusic(String source, {bool loop = true}) async {
    if (!isInitialized) throw Exception('VoiceEngine not initialized');
    // This feature may not be available on all platforms (e.g., web)
    throw UnimplementedError('Background music not supported on this platform');
  }

  Future<void> stopBackgroundMusic() async {
    if (!isInitialized) throw Exception('VoiceEngine not initialized');
    throw UnimplementedError('Background music not supported on this platform');
  }

  Future<void> seekBackgroundMusic(Duration position) async {
    if (!isInitialized) throw Exception('VoiceEngine not initialized');
    throw UnimplementedError('Background music not supported on this platform');
  }

  Future<void> setBackgroundMusicVolume(double volume) async {
    if (!isInitialized) throw Exception('VoiceEngine not initialized');
    throw UnimplementedError('Background music not supported on this platform');
  }

  Future<double> getBackgroundMusicVolume() async {
    if (!isInitialized) return 1.0;
    throw UnimplementedError('Background music not supported on this platform');
  }

  /// Playlist support (Platform-specific)
  Future<void> setMusicPlaylist(List<String> urls) async {
    if (!isInitialized) throw Exception('VoiceEngine not initialized');
    throw UnimplementedError('Playlist not supported on this platform');
  }

  Future<void> playTrackAtIndex(int index) async {
    if (!isInitialized) throw Exception('VoiceEngine not initialized');
    throw UnimplementedError('Playlist not supported on this platform');
  }

  /// Shutdown
  Future<void> shutdown() async {
    await shutdownAll();
  }

  Future<void> shutdownBot() async {
    if (!isInitialized) return;
    // Bot-specific shutdown - may not be applicable on all platforms
    await shutdown();
  }

  Future<void> shutdownAll() async {
    if (!isInitialized) return;
    await _platform.shutdown();
    isInitialized = false;
    isRecording = false;
    await _audioChunkController.close();
    await _musicPositionController.close();
    await _musicStateController.close();
    await _errorController.close();
  }
}
