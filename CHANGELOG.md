# Changelog

## 0.0.1 (Unreleased)

- **iOS**:
    - Supports real-time audio recording and playback with hardware-based acoustic echo cancellation (AEC).
    - Provides `initialize`, `startRecording`, `stopRecording`, `playAudioChunk`, `stopPlayback`, `shutdown` methods.
    - Streams Base64-encoded audio chunks (`audioChunkStream`) and errors (`errorStream`).
    - Handles audio interruptions via `onInterruption` callback.
    - Configurable audio settings (`sampleRate`, `channels`, `bitDepth`, `bufferSize`, `amplitudeThreshold`, `enableAEC`).
- **Android**:
    - Not supported in this version.