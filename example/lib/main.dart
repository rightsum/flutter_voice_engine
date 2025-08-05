import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_voice_engine/flutter_voice_engine.dart';
import 'package:flutter_voice_engine/src/platform/flutter_voice_engine_platform_interface.dart';
import 'package:flutter_voice_engine/flutter_voice_engine_web.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Voice Engine Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FlutterVoiceEngine _voiceEngine = FlutterVoiceEngine();
  bool _isInitialized = false;
  bool _isRecording = false;
  String _status = 'Not initialized';
  String _error = '';
  String _platform = '';
  bool _webSupported = false;
  bool _playbackMonitoring = false;

  @override
  void initState() {
    super.initState();
    _checkPlatformSupport();
  }

  void _checkPlatformSupport() {
    setState(() {
      if (kIsWeb) {
        _platform = 'Web';
        // Check if Web Audio API is supported
        try {
          _webSupported = true; // We'll assume it's supported for now
        } catch (e) {
          _webSupported = false;
        }
      } else {
        _platform = 'Mobile/Desktop';
        _webSupported = true; // Native platforms are supported
      }
    });
  }

  Future<void> _initializeEngine() async {
    try {
      setState(() {
        _status = 'Initializing...';
        _error = '';
      });

      final audioConfig = AudioConfig(
        sampleRate: 44100,
        channels: 1,
        bitDepth: 16,
        bufferSize: 4096,
        amplitudeThreshold: 0.05,
        enableAEC: true,
      );

      final sessionConfig = AudioSessionConfig(
        category: AudioCategory.playAndRecord,
        mode: AudioMode.spokenAudio,
        options: const {
          AudioOption.defaultToSpeaker,
          AudioOption.duckOthers,
        },
        preferredBufferDuration: 0.005,
      );

      await _voiceEngine.initialize(
        audioConfig,
        sessionConfig,
        [], // No processors for this example
      );

      // Set up audio chunk handler
      _voiceEngine.audioChunkStream.listen((audioChunk) {
        if (kDebugMode) {
          print('Received audio chunk: ${audioChunk.length} bytes');
        }
      });

      // Set up error handler
      _voiceEngine.errorStream.listen((String error) {
        setState(() {
          _error = error;
        });
      });

      setState(() {
        _isInitialized = true;
        _status = 'Initialized successfully';
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to initialize: $e';
        _status = 'Initialization failed';
      });
    }
  }

  Future<void> _startRecording() async {
    if (!_isInitialized) return;

    try {
      setState(() {
        _status = 'Starting recording...';
        _error = '';
      });

      await _voiceEngine.startRecording();

      setState(() {
        _isRecording = true;
        _status = 'Recording...';
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to start recording: $e';
        _status = 'Recording failed';
      });
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;

    try {
      setState(() {
        _status = 'Stopping recording...';
        _error = '';
      });

      await _voiceEngine.stopRecording();

      setState(() {
        _isRecording = false;
        _status = 'Recording stopped';
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to stop recording: $e';
        _status = 'Stop recording failed';
      });
    }
  }

  Future<void> _shutdown() async {
    if (!_isInitialized) return;

    try {
      setState(() {
        _status = 'Shutting down...';
        _error = '';
      });

      await _voiceEngine.shutdown();

      setState(() {
        _isInitialized = false;
        _isRecording = false;
        _status = 'Shutdown complete';
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to shutdown: $e';
        _status = 'Shutdown failed';
      });
    }
  }

  void _togglePlaybackMonitoring(bool enabled) {
    setState(() {
      _playbackMonitoring = enabled;
    });
    
    // Access the web plugin directly if on web platform
    if (kIsWeb) {
      try {
        // Get the web plugin instance
        final webPlugin = FlutterVoiceEnginePlatform.instance;
        if (webPlugin is FlutterVoiceEngineWebPlugin) {
          webPlugin.setPlaybackMonitoring(enabled);
        }
      } catch (e) {
        setState(() {
          _error = 'Failed to toggle playback monitoring: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    if (_isInitialized) {
      _voiceEngine.shutdown();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter Voice Engine Demo'),
        backgroundColor: Colors.blue,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Platform Information',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text('Platform: $_platform'),
                    Text('Web Audio Support: ${_webSupported ? 'Yes' : 'No'}'),
                    if (kIsWeb)
                      const Text(
                        'Note: Web version uses Web Audio API for audio processing',
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: Colors.grey,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Engine Status',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text('Status: $_status'),
                    Text('Initialized: ${_isInitialized ? 'Yes' : 'No'}'),
                    Text('Recording: ${_isRecording ? 'Yes' : 'No'}'),
                    if (_error.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          'Error: $_error',
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (!_webSupported)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: const Text(
                  'Web Audio API is not supported in this browser. Please use a modern browser with Web Audio API support.',
                  style: TextStyle(color: Colors.orange),
                ),
              )
            else ...[
              ElevatedButton(
                onPressed: _isInitialized ? null : _initializeEngine,
                child: const Text('Initialize Engine'),
              ),
              const SizedBox(height: 8),
              if (kIsWeb) ...[
                SwitchListTile(
                  title: const Text('Playback Monitoring'),
                  subtitle: const Text('Hear yourself through speakers (may cause feedback)'),
                  value: _playbackMonitoring,
                  onChanged: _isInitialized ? _togglePlaybackMonitoring : null,
                ),
                const SizedBox(height: 8),
              ],
              ElevatedButton(
                onPressed: _isInitialized && !_isRecording ? _startRecording : null,
                child: const Text('Start Recording'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _isRecording ? _stopRecording : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Stop Recording'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _isInitialized ? _shutdown : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Shutdown Engine'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}