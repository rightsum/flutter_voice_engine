# Changelog

## 0.0.1 (Unreleased)

### Added Web Support 🌐
- **Web Platform**: Full Web Audio API implementation
  - Real-time audio recording and playback using Web Audio API
  - Browser-based echo cancellation, noise suppression, and auto gain control
  - Cross-browser compatibility (Chrome, Firefox, Safari, Edge)
  - Automatic microphone permission handling
  - Audio context state management (suspended/running)
  - User interaction requirement handling for autoplay policies

### Platform Features
- **iOS**:
    - Supports real-time audio recording and playback with hardware-based acoustic echo cancellation (AEC).
    - Provides `initialize`, `startRecording`, `stopRecording`, `playAudioChunk`, `stopPlayback`, `shutdown` methods.
    - Streams Base64-encoded audio chunks (`audioChunkStream`) and errors (`errorStream`).
    - Handles audio interruptions via `onInterruption` callback.
    - Configurable audio settings (`sampleRate`, `channels`, `bitDepth`, `bufferSize`, `amplitudeThreshold`, `enableAEC`).
- **Android**:
    - Similar functionality as iOS with platform-specific optimizations.
- **Web**:
    - Real-time audio processing using ScriptProcessorNode and Web Audio API
    - Browser-native audio constraints (echo cancellation, noise suppression)
    - Cross-platform audio streaming compatibility
    - Automatic audio format conversion (Float32 to PCM16)
    - Web-specific error handling and platform detection