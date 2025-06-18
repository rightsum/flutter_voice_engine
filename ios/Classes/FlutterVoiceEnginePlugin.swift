import Flutter
import AVFoundation
import Combine

public class FlutterVoiceEnginePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_voice_engine", binaryMessenger: registrar.messenger())
        let audioChunkChannel = FlutterEventChannel(name: "flutter_voice_engine/audio_chunk", binaryMessenger: registrar.messenger())
        let instance = FlutterVoiceEnginePlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        audioChunkChannel.setStreamHandler(instance)
    }
    
    private var audioManager: AudioManager
    private var audioChunkSink: FlutterEventSink?
    private var cancellables = Set<AnyCancellable>()
    private var interruptionHandler: (() -> Void)?
    private var isInitialized: Bool = false


    override init() {
        audioManager = AudioManager()
        super.init()
        setupInterruptionObserver()
        setupConfigurationChangeObserver()
    }

    private func setupInterruptionObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    private func setupConfigurationChangeObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioEngineConfigurationChange),
            name: NSNotification.Name.AVAudioEngineConfigurationChange,
            object: nil
        )
    }

    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        if type == .began {
            audioManager.stopPlayback()
            interruptionHandler?()
        }
    }

    @objc private func handleAudioEngineConfigurationChange(notification: Notification) {
        audioManager.handleConfigurationChange()
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            guard let args = call.arguments as? [String: Any],
                  let audioConfig = args["audioConfig"] as? [String: Any],
                  let sessionConfig = args["sessionConfig"] as? [String: Any],
                  let processors = args["processors"] as? [[String: Any]] else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing or invalid arguments", details: nil))
                return
            }
            initialize(audioConfig: audioConfig, sessionConfig: sessionConfig, processors: processors, result: result)
        case "startRecording":
            startRecording(result: result)
        case "stopRecording":
            stopRecording(result: result)
        case "playAudioChunk":
            guard let args = call.arguments as? [String: Any],
                  let audioData = args["audioData"] as? FlutterStandardTypedData else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing or invalid audioData", details: nil))
                return
            }
            playAudioChunk(audioData: audioData, result: result)
        case "stopPlayback":
            stopPlayback(result: result)
        case "playBackgroundMusic":
            guard let args = call.arguments as? [String: Any],
                  let source = args["source"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing music file source", details: nil))
                return
            }
            let loop = (args["loop"] as? Bool) ?? true
            audioManager.playBackgroundMusic(source: source, loop: loop)
            result(nil)
        case "stopBackgroundMusic":
            stopBackgroundMusic(result: result)
        case "playBackgroundMusicPlaylist":
            guard let args = call.arguments as? [String: Any],
                  let sources = args["sources"] as? [String],
                  let loopMode = args["loopMode"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing playlist arguments", details: nil))
                return
            }
            audioManager.playBackgroundMusicPlaylist(sources: sources, loopMode: loopMode)
            result(nil)
        case "shutdownBot":
            shutdownBot(result: result)
        case "shutdownAll":
            shutdownAll(result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func stopBackgroundMusic(result: @escaping FlutterResult) {
        audioManager.stopBackgroundMusic()
        result(nil)
    }

    private func initialize(audioConfig: [String: Any], sessionConfig: [String: Any], processors: [[String: Any]], result: @escaping FlutterResult) {
        // Already initialized? No-op (or optionally reset).
        if isInitialized {
            print("AudioManager already initialized. Skipping re-init.");
            result(nil)
            return
        }

        let channels = audioConfig["channels"] as? UInt32 ?? 1
        let sampleRate = audioConfig["sampleRate"] as? Double ?? 48000.0
        let bitDepth = audioConfig["bitDepth"] as? Int ?? 16
        let bufferSize = audioConfig["bufferSize"] as? Int ?? 4096
        let amplitudeThreshold = audioConfig["amplitudeThreshold"] as? Float ?? 0.05
        let enableAEC = audioConfig["enableAEC"] as? Bool ?? true
        let category = mapCategory(sessionConfig["category"] as? String ?? "playAndRecord")
        let mode = mapMode(sessionConfig["mode"] as? String ?? "spokenAudio")
        let options = (sessionConfig["options"] as? [String] ?? []).compactMap { mapOption($0) }
        let preferredBufferDuration = sessionConfig["preferredBufferDuration"] as? Double ?? 0.005

        audioManager = AudioManager(
            channels: channels,
            sampleRate: sampleRate,
            bitDepth: bitDepth,
            bufferSize: bufferSize,
            amplitudeThreshold: amplitudeThreshold,
            enableAEC: enableAEC,
            category: category,
            mode: mode,
            options: AVAudioSession.CategoryOptions(options),
            preferredSampleRate: sampleRate,
            preferredBufferDuration: preferredBufferDuration
        )
        
        audioManager.setupEngine()
        isInitialized = true
        print("Plugin: Initialization complete")
        result(nil)
    }

    private func startRecording(result: @escaping FlutterResult) {
        audioManager.startRecording().sink { [weak self] audioData in
            DispatchQueue.main.async {
                print("Plugin: Sending audio chunk to Flutter, size: \(audioData.count) bytes")
                self?.audioChunkSink?(FlutterStandardTypedData(bytes: audioData))
            }
        }.store(in: &cancellables)
        result(nil)
    }

    private func stopRecording(result: @escaping FlutterResult) {
        audioManager.stopRecording()
        cancellables.removeAll()
        result(nil)
    }

    private func playAudioChunk(audioData: FlutterStandardTypedData, result: @escaping FlutterResult) {
        do {
            try audioManager.playAudioChunk(audioData: audioData.data)
            result(nil)
        } catch {
            result(FlutterError(code: "PLAYBACK_FAILED", message: error.localizedDescription, details: nil))
        }
    }

    private func stopPlayback(result: @escaping FlutterResult) {
        audioManager.stopPlayback()
        result(nil)
    }

    private func shutdownBot(result: @escaping FlutterResult) {
        audioManager.shutdownBot()
        cancellables.removeAll()
        result(nil)
    }

    private func shutdownAll(result: @escaping FlutterResult) {
        audioManager.shutdownAll()
        cancellables.removeAll()
        NotificationCenter.default.removeObserver(self)
        result(nil)
    }


    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        print("Plugin: Setting up audio chunk stream")
        audioChunkSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        print("Plugin: Cancelling audio chunk stream")
        audioChunkSink = nil
        return nil
    }

    private func mapCategory(_ category: String) -> AVAudioSession.Category {
        switch category {
        case "ambient": return .ambient
        case "soloAmbient": return .soloAmbient
        case "playback": return .playback
        case "record": return .record
        case "playAndRecord": return .playAndRecord
        case "multiRoute": return .multiRoute
        default: return .playAndRecord
        }
    }

    private func mapMode(_ mode: String) -> AVAudioSession.Mode {
        switch mode {
        case "defaultMode": return .default
        case "spokenAudio": return .spokenAudio
        case "voiceChat": return .voiceChat
        case "videoChat": return .videoChat
        case "videoRecording": return .videoRecording
        case "measurement": return .measurement
        case "moviePlayback": return .moviePlayback
        case "gameChat": return .gameChat
        default: return .spokenAudio
        }
    }

    private func mapOption(_ option: String) -> AVAudioSession.CategoryOptions? {
        switch option {
        case "mixWithOthers": return .mixWithOthers
        case "duckOthers": return .duckOthers
        case "allowBluetooth": return .allowBluetooth
        case "allowBluetoothA2DP": return .allowBluetoothA2DP
        case "allowAirPlay": return .allowAirPlay
        case "defaultToSpeaker": return .defaultToSpeaker
        default: return nil
        }
    }
}
