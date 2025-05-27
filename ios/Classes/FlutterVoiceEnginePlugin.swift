import Flutter
import AVFoundation
import Combine

public class FlutterVoiceEnginePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    
    public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "flutter_voice_engine", binaryMessenger: registrar.messenger())
    let audioChunkChannel = FlutterEventChannel(name: "flutter_voice_engine/audio_chunk", binaryMessenger: registrar.messenger())
    let errorChannel = FlutterEventChannel(name: "flutter_voice_engine/error", binaryMessenger: registrar.messenger())
    let instance = FlutterVoiceEnginePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    audioChunkChannel.setStreamHandler(instance)
    errorChannel.setStreamHandler(instance)
}
    
private var audioManager: AudioManager
private var audioChunkSink: FlutterEventSink?
private var errorSink: FlutterEventSink?
private var cancellables = Set<AnyCancellable>()
private var interruptionHandler: (() -> Void)?

override init() {
    audioManager = AudioManager() // Default initialization
    super.init()
    setupInterruptionObserver()
}

private func setupInterruptionObserver() {
    NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleInterruption),
        name: AVAudioSession.interruptionNotification,
        object: AVAudioSession.sharedInstance()
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
              let base64String = args["base64String"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing base64String", details: nil))
            return
        }
        playAudioChunk(base64String: base64String, result: result)
    case "stopPlayback":
        stopPlayback(result: result)
    case "shutdown":
        shutdown(result: result)
    default:
        result(FlutterMethodNotImplemented)
    }
}

private func initialize(audioConfig: [String: Any], sessionConfig: [String: Any], processors: [[String: Any]], result: @escaping FlutterResult) {
    do {
        let channels = audioConfig["channels"] as? UInt32 ?? 1
        let sampleRate = audioConfig["sampleRate"] as? Double ?? 48000.0
        let bitDepth = audioConfig["bitDepth"] as? Int ?? 16
        let bufferSize = audioConfig["bufferSize"] as? Int ?? 4096
        let amplitudeThreshold = audioConfig["amplitudeThreshold"] as? Float ?? 0.05
        let enableAEC = audioConfig["enableAEC"] as? Bool ?? true

        audioManager = AudioManager(
            channels: channels,
            sampleRate: sampleRate,
            bitDepth: bitDepth,
            bufferSize: bufferSize,
            amplitudeThreshold: amplitudeThreshold,
            enableAEC: enableAEC
        )

        let category = sessionConfig["category"] as? String ?? "playAndRecord"
        let mode = sessionConfig["mode"] as? String ?? "spokenAudio"
        let options = (sessionConfig["options"] as? [String] ?? []).compactMap { mapOption($0) }
        let bufferDuration = sessionConfig["preferredBufferDuration"] as? Double ?? 0.005

        try audioManager.setupAudioSession(
            category: mapCategory(category),
            mode: mapMode(mode),
            options: AVAudioSession.CategoryOptions(options),
            sampleRate: sampleRate,
            bufferDuration: bufferDuration
        )
        try audioManager.setupEngine()
        // Processors will be implemented later
        result(nil)
    } catch {
        result(FlutterError(code: "INITIALIZATION_FAILED", message: error.localizedDescription, details: nil))
    }
}

private func startRecording(result: @escaping FlutterResult) {
    audioManager.startRecording().sink { [weak self] base64String in
        self?.audioChunkSink?(base64String)
    }.store(in: &cancellables)
    result(nil)
}

private func stopRecording(result: @escaping FlutterResult) {
    audioManager.stopRecording()
    cancellables.removeAll()
    result(nil)
}

private func playAudioChunk(base64String: String, result: @escaping FlutterResult) {
    do {
        try audioManager.playAudioChunk(base64String: base64String)
        result(nil)
    } catch {
        result(FlutterError(code: "PLAYBACK_FAILED", message: error.localizedDescription, details: nil))
    }
}

private func stopPlayback(result: @escaping FlutterResult) {
    audioManager.stopPlayback()
    result(nil)
}

private func shutdown(result: @escaping FlutterResult) {
    audioManager.shutdown()
    cancellables.removeAll()
    NotificationCenter.default.removeObserver(self)
    result(nil)
}

// MARK: - FlutterStreamHandler
public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    if arguments as? String == "error" {
        errorSink = events
    } else {
        audioChunkSink = events
    }
    return nil
}

public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    if arguments as? String == "error" {
        errorSink = nil
    } else {
        audioChunkSink = nil
    }
    return nil
}

// MARK: - Helpers
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
    case "interruptSpokenAudioAndMixWithOthers": return .interruptSpokenAudioAndMixWithOthers
    case "allowBluetooth": return .allowBluetooth
    case "allowBluetoothA2DP": return .allowBluetoothA2DP
    case "allowAirPlay": return .allowAirPlay
    case "defaultToSpeaker": return .defaultToSpeaker
    default: return nil
    }
}

}
