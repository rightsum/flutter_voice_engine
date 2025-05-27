import 'package:flutter/material.dart';
import 'package:flutter_voice_engine/flutter_voice_engine.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FlutterVoiceEngine Example',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const VoiceEnginePage(),
    );
  }
}

class VoiceEnginePage extends StatefulWidget {
  const VoiceEnginePage({super.key});
  @override
  State<VoiceEnginePage> createState() => _VoiceEnginePageState();
}

class _VoiceEnginePageState extends State<VoiceEnginePage> {
  final _voiceEngine = FlutterVoiceEngine();
  String _status = 'Not initialized';
  String _lastAudioChunk = 'No audio chunk';
  String _lastError = 'No error';
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _voiceEngine.onInterruption = () {
      setState(() => _status = 'Interrupted');
    };
    _voiceEngine.audioChunkStream.listen((chunk) {
      setState(() => _lastAudioChunk = 'Chunk: ${chunk.substring(0, 20)}...');
    });
    _voiceEngine.errorStream.listen((error) {
      setState(() => _lastError = error);
    });
  }

  Future<void> _initialize() async {
    try {
      await _voiceEngine.initialize();
      setState(() {
        _status = 'Initialized';
        _isInitialized = true;
      });
    } catch (e) {
      setState(() => _status = 'Init failed: $e');
    }
  }

  Future<void> _startRecording() async {
    try {
      await _voiceEngine.startRecording();
      setState(() => _status = 'Recording');
    } catch (e) {
      setState(() => _status = 'Start recording failed: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      await _voiceEngine.stopRecording();
      setState(() => _status = 'Recording stopped');
    } catch (e) {
      setState(() => _status = 'Stop recording failed: $e');
    }
  }

  Future<void> _playAudioChunk() async {
    try {
      // Use a sample Base64-encoded PCM16 audio chunk for testing
      const sampleChunk = "AAAA"; // Replace with actual Base64 audio data
      await _voiceEngine.playAudioChunk(sampleChunk);
      setState(() => _status = 'Playing');
    } catch (e) {
      setState(() => _status = 'Playback failed: $e');
    }
  }

  Future<void> _stopPlayback() async {
    try {
      await _voiceEngine.stopPlayback();
      setState(() => _status = 'Playback stopped');
    } catch (e) {
      setState(() => _status = 'Stop playback failed: $e');
    }
  }

  Future<void> _shutdown() async {
    try {
      await _voiceEngine.shutdown();
      setState(() {
        _status = 'Not initialized';
        _isInitialized = false;
      });
    } catch (e) {
      setState(() => _status = 'Shutdown failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FlutterVoiceEngine Example')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status: $_status', style: const TextStyle(fontSize: 18)),
            Text('Last Audio Chunk: $_lastAudioChunk', style: const TextStyle(fontSize: 16)),
            Text('Last Error: $_lastError', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              children: [
                ElevatedButton(
                  onPressed: _isInitialized ? null : _initialize,
                  child: const Text('Initialize'),
                ),
                ElevatedButton(
                  onPressed: _isInitialized && !_voiceEngine.isRecording ? _startRecording : null,
                  child: const Text('Start Recording'),
                ),
                ElevatedButton(
                  onPressed: _voiceEngine.isRecording ? _stopRecording : null,
                  child: const Text('Stop Recording'),
                ),
                ElevatedButton(
                  onPressed: _isInitialized && !_voiceEngine.isPlaying ? _playAudioChunk : null,
                  child: const Text('Play Audio Chunk'),
                ),
                ElevatedButton(
                  onPressed: _voiceEngine.isPlaying ? _stopPlayback : null,
                  child: const Text('Stop Playback'),
                ),
                ElevatedButton(
                  onPressed: _isInitialized ? _shutdown : null,
                  child: const Text('Shutdown'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}