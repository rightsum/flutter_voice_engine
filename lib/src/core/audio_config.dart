class AudioConfig {
  final int sampleRate;
  final int channels;
  final int bitDepth;
  final int bufferSize;
  final double amplitudeThreshold;
  final bool enableAEC;

  AudioConfig({
    this.sampleRate = 24000,
    this.channels = 1,
    this.bitDepth = 16,
    this.bufferSize = 4096,
    this.amplitudeThreshold = 0.05,
    this.enableAEC = true,
  });

  Map<String, dynamic> toMap() => {
    'sampleRate': sampleRate,
    'channels': channels,
    'bitDepth': bitDepth,
    'bufferSize': bufferSize,
    'amplitudeThreshold': amplitudeThreshold,
    'enableAEC': enableAEC,
  };
}