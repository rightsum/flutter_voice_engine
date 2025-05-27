# FlutterVoiceEngine 🎙️

A powerful Flutter plugin for real-time audio processing, designed for voice bots and conversational AI. Capture crystal-clear audio, play responses, and eliminate echo with hardware-based acoustic echo cancellation (AEC) on iOS. Perfect for building seamless voice-driven experiences!

> **Note**: Currently supports iOS only. Android support is in development.

## Features

- 🎵 **Real-Time Audio**: Record and stream audio chunks as Base64-encoded data.
- 🔇 **Echo Cancellation**: Hardware-based AEC for clear voice interactions.
- 🎚️ **Configurable Audio**: Customize `sampleRate`, `channels`, `bitDepth`, `bufferSize`, and more.
- 🚨 **Error Handling**: Stream errors to handle issues gracefully.
- 📴 **Interruption Support**: Respond to audio interruptions (e.g., incoming calls).
- 🛠️ **Extensible**: Ready for custom audio processors (coming soon).

## Getting Started

### Prerequisites

- Flutter 3.0.0 or higher
- iOS 13.0 or higher
- Xcode 14 or higher

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

### Example Usage

```dart
import 'package:flutter_voice_engine/flutter_voice_engine.dart';
import 'package:flutter_voice_engine/core/audio_config.dart';
import 'package:flutter_voice_engine/core/audio_session_config.dart';

void main() async {
  final voiceEngine = FlutterVoiceEngine();

  // Initialize with custom config
  voiceEngine.audioConfig = AudioConfig(
    sampleRate: 48000,
    channels: 1,
    bitDepth: 16,
    enableAEC: true,
  );

  try {
    // Initialize plugin
    await voiceEngine.initialize();

    // Listen for audio chunks
    voiceEngine.audioChunkStream.listen((chunk) {
      print('Audio chunk: ${chunk.substring(0, 20)}...');
    });

    // Listen for errors
    voiceEngine.errorStream.listen((error) {
      print('Error: $error');
    });

    // Handle interruptions
    voiceEngine.onInterruption = () {
      print('Audio interrupted');
    };

    // Start recording
    await voiceEngine.startRecording();

    // Stop after 5 seconds
    await Future.delayed(Duration(seconds: 5));
    await voiceEngine.stopRecording();

    // Play a sample audio chunk (replace with valid Base64 audio)
    await voiceEngine.playAudioChunk("AAAA");
    await voiceEngine.stopPlayback();

    // Cleanup
    await voiceEngine.shutdown();
  } catch (e) {
    print('Error: $e');
  }
}
```

Check the `example/` directory for a complete demo app.

## API Overview

### Methods
- `initialize`: Set up the audio engine with `AudioConfig` and `AudioSessionConfig`.
- `startRecording`: Begin capturing audio and streaming chunks.
- `stopRecording`: Stop recording.
- `playAudioChunk`: Play a Base64-encoded audio chunk.
- `stopPlayback`: Stop playback.
- `shutdown`: Release resources.

### Streams
- `audioChunkStream`: Emits Base64-encoded audio chunks.
- `errorStream`: Emits error messages.

### Callbacks
- `onInterruption`: Triggered on audio interruptions.

## Limitations

- iOS-only for now (Android support planned).
- `AudioProcessor` support not yet implemented.
- Playback requires valid Base64-encoded audio chunks.

## Contributing

This plugin is in early development. Feel free to open issues or submit pull requests on [GitHub](https://github.com/your-repo/flutter_voice_engine)!

## License

MIT License. See [LICENSE](LICENSE) for details.

## Author

Muhammad Adnan ([ak187429@gmail.com](mailto:ak187429@gmail.com))

---

Built with ❤️ for voice-driven Flutter apps!