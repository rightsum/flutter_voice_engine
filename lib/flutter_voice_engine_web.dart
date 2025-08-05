import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:js_util' as js_util;
import 'dart:typed_data';

import 'src/core/audio_config.dart';
import 'src/core/audio_session_config.dart';
import 'src/core/audio_processor.dart';
import 'src/platform/flutter_voice_engine_platform_interface.dart';

/// A web implementation of the FlutterVoiceEnginePlatform of the FlutterVoiceEngine plugin.
class FlutterVoiceEngineWebPlugin extends FlutterVoiceEnginePlatform {
  /// Constructs a FlutterVoiceEngineWebPlugin
  FlutterVoiceEngineWebPlugin();

  static void registerWith(dynamic registrar) {
    // Register this plugin as the web implementation
    FlutterVoiceEnginePlatform.instance = FlutterVoiceEngineWebPlugin();
  }

  /// Check if the current platform supports Web Audio API
  static bool get isSupported {
    try {
      final audioContextConstructor = js.context['AudioContext'] ?? js.context['webkitAudioContext'];
      return audioContextConstructor != null;
    } catch (e) {
      return false;
    }
  }

  // Audio context and related objects using js interop
  js.JsObject? _audioContext;
  dynamic _mediaStream; // Using dynamic to handle JS MediaStream
  js.JsObject? _sourceNode;
  js.JsObject? _gainNode;
  js.JsObject? _audioBufferSource;
  js.JsObject? _scriptProcessor;
  
  // Configuration
  bool _enablePlaybackMonitoring = false;
  
  bool _isInitialized = false;
  bool _isRecording = false;
  
  // Stream controllers
  final _audioChunkController = StreamController<Uint8List>.broadcast();
  final _musicPositionController = StreamController<Duration>.broadcast();
  final _musicDurationController = StreamController<Duration>.broadcast();
  final _musicIsPlayingController = StreamController<bool>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  // Audio configuration
  AudioConfig? _audioConfig;
  List<AudioProcessor>? _processors;

  @override
  Stream<Uint8List> get audioChunkStream => _audioChunkController.stream;

  @override
  Stream<Duration> get backgroundMusicPositionStream => _musicPositionController.stream;

  @override
  Stream<Duration> get backgroundMusicDurationStream => _musicDurationController.stream;

  @override
  Stream<bool> get backgroundMusicIsPlayingStream => _musicIsPlayingController.stream;

  @override
  Stream<String> get errorStream => _errorController.stream;

  @override
  Future<void> initialize(
    AudioConfig config,
    AudioSessionConfig sessionConfig,
    List<AudioProcessor> processors,
  ) async {
    try {
      if (_isInitialized) {
        return;
      }

      _audioConfig = config;
      _processors = processors;

      // Initialize Web Audio API using JS interop
      final audioContextConstructor = js.context['AudioContext'] ?? js.context['webkitAudioContext'];
      if (audioContextConstructor == null) {
        throw Exception('Web Audio API not supported in this browser');
      }
      
      _audioContext = js.JsObject(audioContextConstructor);
      
      // Check if audio context is allowed to start
      if (_audioContext!['state'] == 'suspended') {
        print('FlutterVoiceEngineWeb: AudioContext is suspended, waiting for user interaction');
      }

      _isInitialized = true;
      print('FlutterVoiceEngineWeb: Initialized successfully');
    } catch (e) {
      _errorController.add('Initialization failed: $e');
      rethrow;
    }
  }

  @override
  Future<void> startRecording() async {
    try {
      if (!_isInitialized) {
        throw Exception('FlutterVoiceEngine not initialized');
      }

      if (_isRecording) {
        return;
      }

      // Resume audio context if suspended
      if (_audioContext!['state'] == 'suspended') {
        await _audioContext!.callMethod('resume');
      }

      // Request microphone access
      final constraints = js.JsObject.jsify({
        'audio': {
          'sampleRate': _audioConfig?.sampleRate ?? 44100,
          'channelCount': _audioConfig?.channels ?? 1,
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        }
      });

      final mediaDevices = js.context['navigator']['mediaDevices'];
      final streamPromise = mediaDevices.callMethod('getUserMedia', [constraints]);
      
      // Convert JS Promise to Dart Future
      final completer = Completer<js.JsObject>();
      streamPromise.callMethod('then', [
        js.allowInterop((stream) {
          completer.complete(stream);
        })
      ]);
      streamPromise.callMethod('catch', [
        js.allowInterop((error) {
          completer.completeError(error);
        })
      ]);
      
      final streamJsObject = await completer.future;
      _mediaStream = streamJsObject; // Store as JsObject instead

      // Create audio source node
      _sourceNode = _audioContext!.callMethod('createMediaStreamSource', [streamJsObject]);
      
      // Create gain node for volume control
      _gainNode = _audioContext!.callMethod('createGain');
      _gainNode!['gain']['value'] = 1.0;

      // Create script processor for audio processing
      final bufferSize = _audioConfig?.bufferSize ?? 4096;
      _scriptProcessor = _audioContext!.callMethod('createScriptProcessor', [bufferSize, 1, 1]);
      
      // Set up audio processing callback using js_util for better type safety
      _scriptProcessor!['onaudioprocess'] = js.allowInterop((event) {
        try {
          // Use js_util for safer property access
          final inputBuffer = js_util.getProperty(event, 'inputBuffer');
          final outputBuffer = js_util.getProperty(event, 'outputBuffer');
          
          // Get audio data from input channel 0
          final inputData = js_util.callMethod(inputBuffer, 'getChannelData', [0]);
          
          // Get the length using js_util
          final bufferLength = js_util.getProperty(inputData, 'length') as int;
          
          // Convert to Float32List
          final List<double> audioList = [];
          for (int i = 0; i < bufferLength; i++) {
            final sample = js_util.getProperty(inputData, i) as double;
            audioList.add(sample);
          }
          Float32List processedData = Float32List.fromList(audioList);
          
          // Apply audio processors if any
          if (_processors != null) {
            for (final processor in _processors!) {
              processedData = _applyAudioProcessor(processor, processedData);
            }
          }
          
          // Convert to Uint8List for streaming
          final audioChunk = _float32ToUint8(processedData);
          _audioChunkController.add(audioChunk);
          
          // Copy processed data to output channel
          final outputData = js_util.callMethod(outputBuffer, 'getChannelData', [0]);
          final outputLength = js_util.getProperty(outputData, 'length') as int;
          for (int i = 0; i < processedData.length && i < outputLength; i++) {
            js_util.setProperty(outputData, i, processedData[i]);
          }
        } catch (e) {
          _errorController.add('Audio processing error: $e');
        }
      });

      // Connect the audio processing chain
      _sourceNode!.callMethod('connect', [_gainNode]);
      _gainNode!.callMethod('connect', [_scriptProcessor]);
      
      // Only connect to speakers if playback monitoring is enabled
      if (_enablePlaybackMonitoring) {
        _scriptProcessor!.callMethod('connect', [_audioContext!['destination']]);
      }

      _isRecording = true;
      print('FlutterVoiceEngineWeb: Recording started');
    } catch (e) {
      _errorController.add('Failed to start recording: $e');
      rethrow;
    }
  }

  @override
  Future<void> stopRecording() async {
    try {
      if (!_isRecording) {
        return;
      }

      // Disconnect and clean up audio nodes
      try {
        _scriptProcessor?.callMethod('disconnect');
        _gainNode?.callMethod('disconnect');
        _sourceNode?.callMethod('disconnect');
      } catch (e) {
        print('Error disconnecting audio nodes: $e');
      }
      
      // Stop media stream tracks
      if (_mediaStream != null) {
        try {
          final tracks = _mediaStream.callMethod('getTracks');
          for (int i = 0; i < tracks['length']; i++) {
            final track = tracks[i];
            track.callMethod('stop');
          }
        } catch (e) {
          print('Error stopping media stream tracks: $e');
        }
      }
      
      // Clean up references
      _scriptProcessor = null;
      _gainNode = null;
      _sourceNode = null;
      _mediaStream = null;

      _isRecording = false;
      print('FlutterVoiceEngineWeb: Recording stopped');
    } catch (e) {
      _errorController.add('Failed to stop recording: $e');
      rethrow;
    }
  }

  @override
  Future<void> playAudioChunk(Uint8List audioData) async {
    try {
      if (!_isInitialized) {
        throw Exception('FlutterVoiceEngine not initialized');
      }

      // Resume audio context if suspended
      if (_audioContext!['state'] == 'suspended') {
        await _audioContext!.callMethod('resume');
      }

      // Create audio buffer from the data
      final audioBuffer = await _createAudioBufferFromData(audioData);
      
      // Stop any currently playing audio
      try {
        _audioBufferSource?.callMethod('stop');
      } catch (e) {
        // Ignore errors when stopping
      }
      
      // Create new audio buffer source
      _audioBufferSource = _audioContext!.callMethod('createBufferSource');
      _audioBufferSource!['buffer'] = audioBuffer;
      _audioBufferSource!.callMethod('connect', [_audioContext!['destination']]);
      
      // Set up completion handler
      _audioBufferSource!['onended'] = js.allowInterop((_) {
        _musicIsPlayingController.add(false);
      });
      
      // Play the audio
      _audioBufferSource!.callMethod('start');
      _musicIsPlayingController.add(true);
      
    } catch (e) {
      _errorController.add('Failed to play audio chunk: $e');
      rethrow;
    }
  }

  @override
  Future<void> stopPlayback() async {
    try {
      _audioBufferSource?.callMethod('stop');
      _audioBufferSource = null;
      _musicIsPlayingController.add(false);
    } catch (e) {
      _errorController.add('Failed to stop playback: $e');
      rethrow;
    }
  }

  /// Enable or disable playback monitoring (hearing yourself through speakers)
  /// By default, this is disabled to prevent audio feedback
  void setPlaybackMonitoring(bool enabled) {
    if (_enablePlaybackMonitoring == enabled) return;
    
    _enablePlaybackMonitoring = enabled;
    
    // Update connection if recording is active
    if (_isRecording && _scriptProcessor != null && _audioContext != null) {
      try {
        if (enabled) {
          _scriptProcessor!.callMethod('connect', [_audioContext!['destination']]);
        } else {
          _scriptProcessor!.callMethod('disconnect', [_audioContext!['destination']]);
        }
      } catch (e) {
        print('Failed to update playback monitoring: $e');
      }
    }
  }

  @override
  Future<void> shutdown() async {
    try {
      await stopRecording();
      await stopPlayback();
      
      try {
        _audioContext?.callMethod('close');
      } catch (e) {
        print('Error closing audio context: $e');
      }
      _audioContext = null;
      
      // Close all stream controllers
      await _audioChunkController.close();
      await _musicPositionController.close();
      await _musicDurationController.close();
      await _musicIsPlayingController.close();
      await _errorController.close();
      
      _isInitialized = false;
      print('FlutterVoiceEngineWeb: Shutdown completed');
    } catch (e) {
      _errorController.add('Failed to shutdown: $e');
      rethrow;
    }
  }

  @override
  Future<void> setAudioChunkHandler(void Function(Uint8List) handler) async {
    audioChunkStream.listen(handler);
  }

  @override
  Future<void> setInterruptionHandler(void Function() handler) async {
    // Handle audio interruptions in web environment
    html.document.addEventListener('visibilitychange', (event) {
      if (html.document.hidden! && _isRecording) {
        handler();
      }
    });
  }

  // Helper methods

  Float32List _applyAudioProcessor(AudioProcessor processor, Float32List data) {
    // Since AudioProcessor is abstract, we'll apply processing based on the processor's runtime type
    final processorType = processor.runtimeType.toString().toLowerCase();
    
    if (processorType.contains('noise')) {
      return _applyNoiseSuppressionWeb(data);
    } else if (processorType.contains('echo')) {
      return _applyEchoCancellationWeb(data);
    } else if (processorType.contains('gain')) {
      return _applyGainControlWeb(data);
    } else {
      return data;
    }
  }

  Float32List _applyNoiseSuppressionWeb(Float32List data) {
    // Simplified noise suppression using basic high-pass filter
    final filtered = Float32List(data.length);
    double previousSample = 0.0;
    const double alpha = 0.95; // High-pass filter coefficient
    
    for (int i = 0; i < data.length; i++) {
      filtered[i] = alpha * (filtered[i] + data[i] - previousSample);
      previousSample = data[i];
    }
    
    return filtered;
  }

  Float32List _applyEchoCancellationWeb(Float32List data) {
    // Basic echo cancellation - in production you'd need more sophisticated algorithms
    return data;
  }

  Float32List _applyGainControlWeb(Float32List data) {
    const double gain = 1.0;
    final result = Float32List(data.length);
    
    for (int i = 0; i < data.length; i++) {
      result[i] = data[i] * gain;
      // Clamp to prevent clipping
      if (result[i] > 1.0) result[i] = 1.0;
      if (result[i] < -1.0) result[i] = -1.0;
    }
    
    return result;
  }

  Uint8List _float32ToUint8(Float32List float32Data) {
    final uint8Data = Uint8List(float32Data.length * 2); // 16-bit samples
    
    for (int i = 0; i < float32Data.length; i++) {
      // Convert from float32 (-1.0 to 1.0) to int16
      final sample = (float32Data[i] * 32767).round().clamp(-32768, 32767);
      uint8Data[i * 2] = sample & 0xFF;
      uint8Data[i * 2 + 1] = (sample >> 8) & 0xFF;
    }
    
    return uint8Data;
  }

  Future<js.JsObject> _createAudioBufferFromData(Uint8List audioData) async {
    // This is a simplified implementation for creating AudioBuffer from raw audio data
    final sampleRate = _audioConfig?.sampleRate ?? 44100;
    final channels = _audioConfig?.channels ?? 1;
    final frameCount = audioData.length ~/ (2 * channels); // Assuming 16-bit samples
    
    final audioBuffer = _audioContext!.callMethod('createBuffer', [channels, frameCount, sampleRate]);
    
    // Convert Uint8List to Float32List and copy to AudioBuffer
    for (int channel = 0; channel < channels; channel++) {
      final channelData = audioBuffer.callMethod('getChannelData', [channel]);
      
      for (int i = 0; i < frameCount; i++) {
        final byteIndex = (i * channels + channel) * 2;
        if (byteIndex + 1 < audioData.length) {
          // Convert from 16-bit signed integer to float32
          final sample = (audioData[byteIndex] | (audioData[byteIndex + 1] << 8));
          final signedSample = sample > 32767 ? sample - 65536 : sample;
          channelData[i] = signedSample / 32768.0;
        }
      }
    }
    
    return audioBuffer;
  }
}
