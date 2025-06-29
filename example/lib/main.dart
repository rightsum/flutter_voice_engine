import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_voice_engine_example/session/gemini_test/cubit/test_session_cubit.dart';
import 'package:flutter_voice_engine_example/session/gemini_test/cubit/test_session_state.dart';
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
      home: MultiBlocProvider(
        providers: [
          BlocProvider<SessionCubit>(
            create: (context) => SessionCubit(),
          ),
          BlocProvider<TestSessionCubit>(
            create: (context) => TestSessionCubit(),
          ),
        ],
        child: const HomePageOld(),
      ),
    );
  }
}

class HomePageOld extends StatefulWidget {
  const HomePageOld({super.key});

  @override
  State<HomePageOld> createState() => _HomePageOldState();
}

class _HomePageOldState extends State<HomePageOld>   {

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gemini Live Bot (Multimodal)')),
      body: BlocConsumer<TestSessionCubit, TestSessionState>(
        listener: (context, state) {
          if (state.isError && state.error != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.error!)),
            );
          }
        },
        builder: (context, state) {
          final cubit = context.read<TestSessionCubit>();
          final cameraController = cubit.cameraController; // Get the controller from the cubit
          return Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    // Camera Preview
                    if (state.showCameraPreview && cameraController != null && cameraController.value.isInitialized)
                      Center(
                        child: AspectRatio(
                          aspectRatio: cameraController.value.aspectRatio,
                          child: CameraPreview(cameraController),
                        ),
                      )
                    else if (state.isInitializingCamera)
                      const Center(child: CircularProgressIndicator())
                    else if (!state.isSessionStarted)
                        const Center(child: Text("Tap 'Start Session' to begin."))
                      else
                        const Center(child: Text("Camera not active. Session started."))
                    ,

                    // Overlay for status messages and controls
                    Positioned.fill(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Status Messages
                              if (state.isInitializingCamera)
                                const Text("Initializing Camera...")
                              else if (state.isStreamingImages && state.isRecording)
                                const Text("Observing & Listening...")
                              else if (state.promptUserToSpeak)
                                  const Text("Now, ask your question about what you see!")
                                else if (state.isBotSpeaking)
                                    const Text("Bot is speaking...")
                                  else if (state.isRecording)
                                      const Text("Listening...")
                                    else if (state.isSessionStarted && !state.isCameraActive)
                                        const Text("Session active. Open camera to observe.")
                                      else if (state.isSessionStarted)
                                          const Text("Session active.") // Generic if no specific state
                              ,

                              const SizedBox(height: 20),

                              // Control Buttons
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  // Start/Stop Session
                                  ElevatedButton(
                                    onPressed: state.isSessionStarted
                                        ? cubit.stopSession
                                        : cubit.startSession,
                                    child: Text(state.isSessionStarted ? 'End Session' : 'Start Session'),
                                  ),

                                  // Manual Start/Stop Recording - kept as per request
                                  // but will largely be managed automatically by startSession/stopSession
                                  ElevatedButton(
                                    onPressed: state.isSessionStarted && !state.isRecording
                                        ? () => cubit.startRecording()
                                        : state.isRecording
                                        ? () => cubit.stopRecording()
                                        : null,
                                    child: Text(state.isRecording ? 'Stop Voice' : 'Start Voice'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}


class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Voice Engine Test')),
      body: BlocBuilder<TestSessionCubit, TestSessionState>(
        builder: (context, state) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Session: ${state.isSessionStarted ? 'Started' : 'Stopped'}'),
                Text('Recording: ${state.isRecording ? 'On' : 'Off'}'),
                Text('Playing: ${state.isPlaying ? 'On' : 'Off'}'),
                if (state.error != null)
                  Text(
                    'Error: ${state.error}',
                    style: const TextStyle(color: Colors.red),
                  ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: state.isSessionStarted ? null : () => context.read<TestSessionCubit>().startSession(),
                  child: const Text('Start Session'),
                ),
                ElevatedButton(
                  onPressed: state.isSessionStarted ? () => context.read<TestSessionCubit>().stopSession() : null,
                  child: const Text('Stop Session'),
                ),
                ElevatedButton(
                  onPressed: state.isSessionStarted && !state.isRecording ? () => context.read<TestSessionCubit>().startRecording() : null,
                  child: const Text('Start Recording'),
                ),
                ElevatedButton(
                  onPressed: state.isRecording ? () => context.read<TestSessionCubit>().stopRecording() : null,
                  child: const Text('Stop Recording'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class TestCameraHomePage extends StatefulWidget {
  const TestCameraHomePage({super.key});

  @override
  State<TestCameraHomePage> createState() => _TestCameraHomePageState();
}

class _TestCameraHomePageState extends State<TestCameraHomePage> {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isNotEmpty) {
        _cameraController = CameraController(
          cameras.first,
          ResolutionPreset.medium,
        );
        await _cameraController!.initialize();
        setState(() {
          _isCameraInitialized = true;
        });
      } else {
        print('No cameras available');
      }
    } catch (e) {
      print('Error initializing camera: $e');
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    print("Building TestCameraHomePage, isCameraInitialized: $_isCameraInitialized, cameraController: $_cameraController");
    return Scaffold(
      appBar: AppBar(title: const Text('Camera Preview')),
      body: _isCameraInitialized && _cameraController != null
          ? CameraPreview(_cameraController!)
          : const Center(child: CircularProgressIndicator()),
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
          prev.isMusicPlaying != curr.isMusicPlaying ||
          prev.currentMusicUrl != curr.currentMusicUrl,
      builder: (context, state) {
        final isPlaying = state.isMusicPlaying;
        final position = _dragging ? _dragValue : state.musicPosition ?? Duration.zero;
        final duration = state.musicDuration ?? Duration.zero;
        final posText = _format(position);
        final durText = _format(duration);
        final trackName = state.currentMusicUrl.isNotEmpty
            ? Uri.decodeComponent(Uri.parse(state.currentMusicUrl).pathSegments.last.replaceFirst('music/', ''))
            : 'No Music Playing';

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
                    Expanded(
                      child: Text(
                        trackName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
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
                        print("Music button pressed, isPlaying: $isPlaying, url: ${state.currentMusicUrl}");
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
                    onChanged: (v) => setState(() => _dragValue = Duration(milliseconds: v.round())),
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
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$m:$s";
  }
}