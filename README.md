# Flutt- 🔇 **Echo Cancellation**: Hardware-based Acoustic Echo Cancellation (AEC) with platform-specific optimizations.
- 🎵 **Background Music:** Play, seek, pause, loop, and manage playlists with live position and state updates.
- 🔗 **Flutter Streams:** Audio chunks, music position, playback state, and errors via Dart Streams.
- 🎚️ **Configurable Audio**: Customize `sampleRate`, `channels`, `bitDepth`, `bufferSize`, and more.
- 🚨 **Error Handling**: Stream errors to handle issues gracefully.
- 🛠️ **Extensible**: Fine-grained audio session control and WebSocket integration for bots.
- 🌐 **Web Support**: Full Web Audio API support for browser-based applications.

## Platform Support

| Platform | Audio Recording | Audio Playback | Echo Cancellation | Background Music |
|----------|----------------|----------------|-------------------|------------------|
| iOS      | ✅             | ✅             | ✅ (Hardware AEC) | ✅               |
| Android  | ✅             | ✅             | ✅               | ✅               |
| Web      | ✅             | ✅             | ✅ (Browser AEC)  | ✅               |eEngine 🎙️

A powerful cross-platform audio plugin for Android, iOS, and Web to build real-time conversational voice bots, background music playback, and advanced audio session management.

## Features

- 🎵 **Real-Time Audio**: Record and stream audio chunks as raw PCM Int16 data.
- 🔇 **Echo Cancellation**: Hardware-based Acoustic Echo Cancellation (AEC) with Apple’s Voice Processing.
- 🎵 **Background Music:** Play, seek, pause, loop, and manage playlists with live position and state updates.
- 🔗 **Flutter Streams:** Audio chunks, music position, playback state, and errors via Dart Streams.
- 🎚️ **Configurable Audio**: Customize `sampleRate`, `channels`, `bitDepth`, `bufferSize`, and more.
- 🚨 **Error Handling**: Stream errors to handle issues gracefully.
- 🛠️ **Extensible**: Fine-grained AVAudioSession control and WebSocket integration for bots.

## Getting Started

### Prerequisites

- Flutter 3.0.0 or higher
- iOS 13.0 or higher (for iOS)
- Xcode 14 or higher (for iOS development)
- Modern web browser with Web Audio API support (for web)

### Installation

Add the plugin to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_voice_engine:
    path: ./flutter_voice_engine # Or specify your package source
```

Run:

```bash
flutter pub get
```

### Android Setup

Add microphone permission to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
```

### iOS Setup

1. Update `ios/Runner/Info.plist` to include microphone permission:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>We need microphone access for voice interactions.</string>
```

2. Ensure `ios/Podfile` targets iOS 13.0:

```ruby
platform :ios, '13.0'
```

3. Run:

```bash
cd ios
pod install
cd ..
```

### Web Setup

The web platform uses the Web Audio API and requires no additional setup. However, note the following:

1. **Browser Compatibility**: Requires a modern browser with Web Audio API support (Chrome 66+, Firefox 60+, Safari 14.1+, Edge 79+).

2. **HTTPS Requirement**: Due to browser security policies, microphone access requires HTTPS in production. During development, `localhost` is allowed.

3. **User Interaction**: Audio context may be suspended until user interaction (click, tap, etc.) due to browser autoplay policies.

4. **Permissions**: The browser will prompt users for microphone permission when `startRecording()` is called.

**Running on Web:**

```bash
flutter run -d chrome --web-renderer html
```

**Note**: Use the `html` renderer for better Web Audio API compatibility.

### Example Usage

```dart
import 'package:flutter_voice_engine/flutter_voice_engine.dart';
import 'package:flutter_voice_engine/core/audio_config.dart';
import 'package:flutter_voice_engine/core/audio_session_config.dart';

void main() async {
  final voiceEngine = FlutterVoiceEngine();

  // Initialize with custom config
  voiceEngine.audioConfig = AudioConfig(
    sampleRate: 24000,
    channels: 1,
    bitDepth: 16,
    bufferSize: 4096,
    amplitudeThreshold: 0.05,
    enableAEC: true,
  );

  voiceEngine.sessionConfig = AudioSessionConfig(
    category: AudioCategory.playAndRecord,
    mode: AudioMode.spokenAudio,
    options: {AudioOption.defaultToSpeaker},
    preferredBufferDuration: 0.005,
  );

  try {
    // Initialize plugin
    await voiceEngine.initialize();

    // Listen for audio chunks
    voiceEngine.audioChunkStream.listen((audioBytes) {
      print('Audio chunk: ${audioBytes.sublist(0, 20)}...');
      // Send Uint8List (raw PCM Int16, 24kHz) to backend via WebSocket
    });

    // Listen for errors
    voiceEngine.errorStream.listen((error) {
      print('Error: $error');
    });

    // Listen for background music updates
    voiceEngine.backgroundMusicPositionStream.listen((pos) {
      print('Music position: $pos');
    });

    voiceEngine.backgroundMusicDurationStream.listen((dur) {
      print('Music duration: $dur');
    });

    voiceEngine.backgroundMusicIsPlayingStream.listen((isPlaying) {
      print('Is music playing? $isPlaying');
    });

    // Start recording
    await voiceEngine.startRecording();

    // Stop recording
    await voiceEngine.stopRecording();

    // Play a sample audio chunk (replace with valid PCM Int16 24kHz)
    await voiceEngine.playAudioChunk(responseBytes);

    // Play background music
    await voiceEngine.playBackgroundMusic('/path/to/track.mp3', loop: true);

    // Set volume
    await voiceEngine.setBackgroundMusicVolume(0.3);

    // Seek to position
    await voiceEngine.seekBackgroundMusic(Duration(seconds: 60));

    // Stop playback and music
    await voiceEngine.stopPlayback();
    await voiceEngine.stopBackgroundMusic();

    // Cleanup
    await voiceEngine.shutdownAll();
  } catch (e) {
    print('Error: $e');
  }
}
```

Check the real world usage in [Project Astra Clone](https://github.com/AdnanKhan45/project-astra-flutter) app in Flutter.

## API Overview

### Methods
- `initialize`: Set up the audio engine with `AudioConfig` and `AudioSessionConfig`.
- `startRecording`: Begin capturing audio and streaming chunks.
- `stopRecording`: Stop recording.
- `playAudioChunk`: Play a Base64-encoded audio chunk.
- `stopPlayback`: Stop playback.
- `playBackgroundMusic`: Play a single track with optional looping.
- `setMusicPlaylist`: Set a playlist of local or remote tracks.
- `playTrackAtIndex`: Play a specific track from the playlist.
- `stopBackgroundMusic`: Seek to a specific position in the track.
- `setBackgroundMusicVolume`: Adjust music volume (0.0 to 1.0).
- `getBackgroundMusicVolume`: Get current music volume.
- `shutdownBot`: Stop voice bot activity (music continues).
- `shutdownAll`: Stop all activities and release resources.

### Streams
- `audioChunkStream`: Emits raw PCM Int16 audio chunks (Uint8List).
- `errorStream`: Emits error messages.
- `backgroundMusicPositionStream`: Emits current music position.
- `backgroundMusicDurationStream`: Emits music duration.
- `backgroundMusicIsPlayingStream`: Emits playback state (true/false).

## Limitations

- Background music feature on Android is coming soon!

## Contributing

This plugin is in early development. Feel free to open issues or submit pull requests on [GitHub](https://github.com/your-repo/flutter_voice_engine)!

## License

MIT License. See [LICENSE](LICENSE) for details.

## Author

Muhammad Adnan ([ak187429@gmail.com](mailto:ak187429@gmail.com))

---

Built with ❤️ for voice-driven Flutter apps!
