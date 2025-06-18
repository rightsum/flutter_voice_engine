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
          print('UI updated with state: $state');
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
                ElevatedButton(
                  onPressed: state.isMusicLoading ? null : () {
                    if(!state.isMusicPlaying) {
                      context.read<SessionCubit>().playMusic("https://firebasestorage.googleapis.com/v0/b/dr-nur-ai.firebasestorage.app/o/music%2FZen%20Journey.mp3?alt=media&token=XYZ");
                    } else {
                      context.read<SessionCubit>().stopMusic();
                    }
                  },
                  child: Text(state.isMusicPlaying ? 'Pause Background Music' : 'Play Background Music'),
                ),
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
