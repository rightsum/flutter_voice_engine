import '../models/audio_category.dart';
import '../models/audio_mode.dart';
import '../models/audio_option.dart';

class AudioSessionConfig {
  final AudioCategory category;
  final AudioMode mode;
  final Set<AudioOption> options;
  final double preferredBufferDuration;

  AudioSessionConfig({
    this.category = AudioCategory.playAndRecord,
    this.mode = AudioMode.spokenAudio,
    this.options = const {
      AudioOption.defaultToSpeaker,
      AudioOption.duckOthers,
      AudioOption.interruptSpokenAudioAndMixWithOthers,
    },
    this.preferredBufferDuration = 0.005,
  });

  Map<String, dynamic> toMap() => {
    'category': category.toString(),
    'mode': mode.toString(),
    'options': options.map((e) => e.toString()).toList(),
    'preferredBufferDuration': preferredBufferDuration,
  };
}