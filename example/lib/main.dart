import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_voice_engine_example/session/session_cubit.dart';
import 'package:flutter_voice_engine_example/session/session_state.dart';
void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: BlocProvider(
        create: (context) => SessionCubit(),
        child: const HomePage(),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Voice Engine Test')),
      body: BlocBuilder<SessionCubit, SessionState>(
        builder: (context, state) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Session: ${state.isSessionStarted ? 'Started' : 'Stopped'}'),
                Text('Recording: ${state.isRecording ? 'On' : 'Off'}'),
                Text('Playing: ${state.isPlaying ? 'On' : 'Off'}'),
                if (state.error != null)
                  Text('Error: ${state.error}', style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: state.isSessionStarted
                      ? null
                      : () => context.read<SessionCubit>().startSession(),
                  child: const Text('Start Session'),
                ),
                ElevatedButton(
                  onPressed: state.isSessionStarted
                      ? () => context.read<SessionCubit>().stopSession()
                      : null,
                  child: const Text('Stop Session'),
                ),
                ElevatedButton(
                  onPressed: state.isSessionStarted && !state.isRecording
                      ? () => context.read<SessionCubit>().startRecording()
                      : null,
                  child: const Text('Start Recording'),
                ),
                ElevatedButton(
                  onPressed: state.isRecording
                      ? () => context.read<SessionCubit>().stopRecording()
                      : null,
                  child: const Text('Stop Recording'),
                ),
                // ElevatedButton(
                //   onPressed: state.isMusicLoading ? null : () {
                //     if(!state.isMusicPlaying) {
                //       context.read<SessionCubit>().playMusic();
                //     } else {
                //       context.read<SessionCubit>().stopMusic();
                //     }
                //   },
                //   child: Text(state.isMusicPlaying ? 'Pause Background Music' : 'Play Background Music'),
                // ),
                const MusicPlayerCard(),
                if(state.isMusicLoading)
                  const CircularProgressIndicator(),
              ],
            ),
          );
        },
      ),
    );
  }
}


class MusicPlayerCard extends StatefulWidget {
  const MusicPlayerCard({super.key});

  @override
  State<MusicPlayerCard> createState() => _MusicPlayerCardState();
}

class _MusicPlayerCardState extends State<MusicPlayerCard> {
  double _volume = 1.0;
  bool _dragging = false;
  Duration _dragValue = Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final cubit = context.read<SessionCubit>();
      _volume = await cubit.getMusicVolume();
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SessionCubit, SessionState>(
      buildWhen: (prev, curr) =>
      prev.musicPosition != curr.musicPosition ||
          prev.musicDuration != curr.musicDuration ||
          prev.isMusicPlaying != curr.isMusicPlaying,
      builder: (context, state) {
        final isPlaying = state.isMusicPlaying;
        final position = _dragging ? _dragValue : state.musicPosition;
        final duration = state.musicDuration;
        final posText = _format(position!);
        final durText = _format(duration!);

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 6,
          child: Padding(
            padding: const EdgeInsets.all(18.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.teal.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.all(10),
                      child: const Icon(Icons.music_note, color: Colors.teal, size: 30),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        'Calm Ocean Waves', // Random music name
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                        color: Colors.teal,
                        size: 38,
                      ),
                      onPressed: () {
                        final cubit = context.read<SessionCubit>();

                        print("Music button pressed, isPlaying: $isPlaying");
                        if (isPlaying) {
                          cubit.stopMusic();
                        } else {
                          cubit.playMusic();
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(posText, style: const TextStyle(fontSize: 14, color: Colors.black54)),
                    const Spacer(),
                    Text(durText, style: const TextStyle(fontSize: 14, color: Colors.black54)),
                  ],
                ),
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 5,
                    thumbColor: Colors.teal,
                    activeTrackColor: Colors.teal,
                    inactiveTrackColor: Colors.teal.withOpacity(0.15),
                    overlayColor: Colors.tealAccent.withOpacity(0.3),
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
                  ),
                  child: Slider(
                    min: 0,
                    max: duration.inMilliseconds.toDouble().clamp(1, double.infinity),
                    value: position.inMilliseconds.clamp(0, duration.inMilliseconds == 0 ? 1 : duration.inMilliseconds).toDouble(),
                    onChangeStart: (_) => setState(() => _dragging = true),
                    onChanged: (v) {
                      setState(() => _dragValue = Duration(milliseconds: v.round()));
                    },
                    onChangeEnd: (v) {
                      final cubit = context.read<SessionCubit>();
                      cubit.seekMusic(Duration(milliseconds: v.round()));
                      setState(() {
                        _dragging = false;
                        _dragValue = Duration.zero;
                      });
                    },
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.volume_down, size: 22, color: Colors.teal),
                    Expanded(
                      child: Slider(
                        min: 0,
                        max: 1,
                        value: _volume,
                        activeColor: Colors.teal,
                        onChanged: (v) {
                          setState(() => _volume = v);
                          context.read<SessionCubit>().setMusicVolume(v);
                        },
                      ),
                    ),
                    const Icon(Icons.volume_up, size: 22, color: Colors.teal),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _format(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = (d.inSeconds.remainder(60)).toString().padLeft(2, '0');
    return "$m:$s";
  }
}
