abstract class AudioProcessor {
  const AudioProcessor();

  List<int> process(List<int> buffer);

  Map<String, dynamic> toMap() => {'type': runtimeType.toString()};
}