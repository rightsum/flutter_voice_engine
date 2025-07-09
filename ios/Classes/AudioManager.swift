import AVFoundation
import Combine
import CommonCrypto
import Flutter

public class AudioManager {
    // Voice Bot Related
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var inputNode: AVAudioInputNode { audioEngine.inputNode }
    private var inputFormat: AVAudioFormat
    private var audioFormat: AVAudioFormat
    private var webSocketFormat: AVAudioFormat
    private var isRecording = false
    private let audioChunkPublisher = PassthroughSubject<Data, Never>()
    public let errorPublisher = PassthroughSubject<String, Never>()
    private var recordingConverter: AVAudioConverter?
    private var playbackConverter: AVAudioConverter?
    private let amplitudeThreshold: Float
    private let enableAEC: Bool
    private var cancellables = Set<AnyCancellable>()
    private let targetSampleRate: Float64 = 24000

    // Background Music Related
    
    private var queuePlayer: AVQueuePlayer = AVQueuePlayer()
    private var playerLooper: AVPlayerLooper?
    private var playlistItems: [AVPlayerItem] = []
    private var musicPositionTimer: Timer?
    public var musicIsPlaying = false

    public var eventSink: FlutterEventSink?

    public init(
        channels: UInt32 = 1,
        sampleRate: Double = 48000,
        bitDepth: Int = 16,
        bufferSize: Int = 4096,
        amplitudeThreshold: Float = 0.05,
        enableAEC: Bool = true,
        category: AVAudioSession.Category = .playAndRecord,
        mode: AVAudioSession.Mode = .spokenAudio,
        options: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .mixWithOthers, .allowBluetoothA2DP],
        preferredSampleRate: Double = 48000,
        preferredBufferDuration: Double = 0.005
    ) {
        self.amplitudeThreshold = amplitudeThreshold
        self.enableAEC = enableAEC
        
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(category, mode: mode, options: options)
            try session.setPreferredSampleRate(preferredSampleRate)
            try session.setPreferredIOBufferDuration(preferredBufferDuration)
            try session.setInputGain(1.0)
            try session.setActive(true, options: [.notifyOthersOnDeactivation])
            let appliedOptions = session.categoryOptions.rawValue
            print("Audio session configured: sampleRate=\(session.sampleRate), channels=\(session.outputNumberOfChannels), inputGain=\(session.inputGain), options=\(appliedOptions), bufferDuration=\(session.ioBufferDuration)")
            print("Expected options: defaultToSpeaker=8, mixWithOthers=32, allowBluetoothA2DP=4, Total=44")
            if appliedOptions != 44 {
                print("Warning: Options mismatch, expected 44, got \(appliedOptions)")
                try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .mixWithOthers, .allowBluetoothA2DP])
                print("Fallback applied: options=\(session.categoryOptions.rawValue)")
            }
        } catch {
            print("Failed to configure audio session: \(error)")
            errorPublisher.send("Audio session error: \(error.localizedDescription)")
        }

        self.inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: session.sampleRate,
            channels: channels,
            interleaved: true
        )!
        self.audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: session.sampleRate,
            channels: 2,
            interleaved: false
        )!
        self.webSocketFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: channels,
            interleaved: true
        )!
        setupConverters()
    }

    private func setupConverters() {
        recordingConverter = AVAudioConverter(from: inputFormat, to: webSocketFormat)
        playbackConverter = AVAudioConverter(from: webSocketFormat, to: audioFormat)
        if recordingConverter == nil || playbackConverter == nil {
            errorPublisher.send("Failed to initialize audio converters")
            DispatchQueue.main.async { [weak self] in
                self?.eventSink?(["type": "error", "message": "Failed to initialize audio converters"])
            }
        } else {
            print("Converters initialized: recording=\(inputFormat)->\(webSocketFormat), playback=\(webSocketFormat)->\(audioFormat)")
        }
    }

    public func setupEngine() {
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: audioFormat)
        audioEngine.connect(audioEngine.mainMixerNode, to: audioEngine.outputNode, format: audioFormat)
        audioEngine.mainMixerNode.outputVolume = 1.0

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(true)
            if enableAEC {
                try inputNode.setVoiceProcessingEnabled(true)
                print("Voice processing enabled for AEC")
            }
            try audioEngine.start()
            print("Audio engine started with outputFormat=\(audioFormat)")
        } catch {
            print("Failed to start audio engine or enable AEC: \(error)")
            errorPublisher.send("Engine error: \(error.localizedDescription)")
            DispatchQueue.main.async { [weak self] in
                self?.eventSink?(["type": "error", "message": "Engine error: \(error.localizedDescription)"])
            }
        }
    }

    public func emitMusicIsPlaying() {
        DispatchQueue.main.async { [weak self] in
            guard let sink = self?.eventSink else {
                print("eventSink is nil, cannot send music state")
                return
            }
            print("Emitting music state: \(self?.musicIsPlaying ?? false)")
            sink(["type": "music_state", "state": self?.musicIsPlaying ?? false])
        }
    }

    public func setBackgroundMusicVolume(_ volume: Float) {
        queuePlayer.volume = volume
    }

    public func getBackgroundMusicVolume() -> Float {
        return queuePlayer.volume
    }

    
    public func startEmittingMusicPosition() {
      stopEmittingMusicPosition()

      musicPositionTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
        guard let self = self,
              let currentItem = self.queuePlayer.currentItem,
              currentItem.status == .readyToPlay
        else { return }

        let rawPos  = CMTimeGetSeconds(self.queuePlayer.currentTime())
        let duration = CMTimeGetSeconds(currentItem.duration)
        // clamp between 0 and duration:
        let position = max(0, min(rawPos, duration))

        DispatchQueue.main.async {
          self.eventSink?([
            "type":     "music_position",
            "position": position,
            "duration": duration
          ])
        }
      }

      RunLoop.main.add(musicPositionTimer!, forMode: .common)
    }


    public func stopEmittingMusicPosition() {
        print("Stopping music position timer")
        musicPositionTimer?.invalidate()
        musicPositionTimer = nil
    }

    private func isRemoteURL(_ source: String) -> Bool {
        return source.lowercased().hasPrefix("http://") || source.lowercased().hasPrefix("https://")
    }

    private func downloadToTemp(_ urlStr: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: urlStr) else { completion(nil); return }
        let tempDir = FileManager.default.temporaryDirectory
        let filename = md5(urlStr) + (url.pathExtension.isEmpty ? ".mp3" : ".\(url.pathExtension)")
        let localPath = tempDir.appendingPathComponent(filename).path
        if FileManager.default.fileExists(atPath: localPath) {
            completion(localPath)
            return
        }
        let task = URLSession.shared.downloadTask(with: url) { (tempURL, _, error) in
            if let tempURL = tempURL, error == nil {
                do {
                    try FileManager.default.moveItem(at: tempURL, to: URL(fileURLWithPath: localPath))
                    completion(localPath)
                    print("Downloaded track: \(urlStr) to \(localPath)")
                } catch {
                    print("Failed to move downloaded file: \(error)")
                    completion(nil)
                }
            } else {
                print("Failed to download music from \(urlStr): \(error?.localizedDescription ?? "Unknown error")")
                DispatchQueue.main.async { [weak self] in
                    self?.eventSink?(["type": "error", "message": "Failed to download music from \(urlStr)"])
                }
                completion(nil)
            }
        }
        task.resume()
    }

    private func md5(_ string: String) -> String {
        let data = Data(string.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_MD5($0.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    private func installRecordingTap() {
        let bus = 0
        inputNode.removeTap(onBus: bus)
        inputNode.installTap(onBus: bus, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self, let converter = self.recordingConverter else {
                self?.errorPublisher.send("Recording converter unavailable")
                DispatchQueue.main.async { [weak self] in
                    self?.eventSink?(["type": "error", "message": "Recording converter unavailable"])
                }
                return
            }
            let amplitude = buffer.floatChannelData?.pointee.withMemoryRebound(to: Float.self, capacity: Int(buffer.frameLength)) { ptr in
                (0..<Int(buffer.frameLength)).reduce(0.0) { max($0, abs(ptr[$1])) }
            } ?? 0
            let frameCapacity = UInt32(round(Double(buffer.frameLength) * converter.outputFormat.sampleRate / buffer.format.sampleRate))
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: converter.outputFormat,
                frameCapacity: frameCapacity
            ) else {
                self.errorPublisher.send("Failed to create output buffer")
                DispatchQueue.main.async { [weak self] in
                    self?.eventSink?(["type": "error", "message": "Failed to create output buffer"])
                }
                return
            }
            var error: NSError?
            let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            if let error = error {
                self.errorPublisher.send("Recording conversion error: \(error.localizedDescription)")
                DispatchQueue.main.async { [weak self] in
                    self?.eventSink?(["type": "error", "message": "Recording conversion error: \(error.localizedDescription)"])
                }
                return
            }
            if status == .error {
                self.errorPublisher.send("Recording conversion failed")
                DispatchQueue.main.async { [weak self] in
                    self?.eventSink?(["type": "error", "message": "Recording conversion failed"])
                }
                return
            }
            if let data = outputBuffer.int16ChannelData?.pointee {
                let byteCount = Int(outputBuffer.frameLength) * MemoryLayout<Int16>.size * Int(outputBuffer.format.channelCount)
                let audioData = Data(bytes: data, count: byteCount)
                self.audioChunkPublisher.send(audioData)
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.eventSink?(["type": "error", "message": "No audio data in output buffer"])
                }
            }
        }
    }

    public func startRecording() -> AnyPublisher<Data, Never> {
        guard !isRecording else {
            print("Already recording")
            return audioChunkPublisher.eraseToAnyPublisher()
        }
        isRecording = true
        print("Starting recording with format=\(webSocketFormat)")
        installRecordingTap()
        return audioChunkPublisher.eraseToAnyPublisher()
    }

    public func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        inputNode.removeTap(onBus: 0)
        print("Recording stopped")
    }

    public func playAudioChunk(audioData: Data) throws {
        guard audioEngine.isRunning, let converter = playbackConverter else {
            throw NSError(domain: "AudioManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Engine or converter unavailable"])
        }
        print("Received playback chunk, size: \(audioData.count) bytes")
        let frameCount = AVAudioFrameCount(audioData.count / (MemoryLayout<Int16>.size * Int(self.webSocketFormat.channelCount)))
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: webSocketFormat, frameCapacity: frameCount) else {
            throw NSError(domain: "AudioManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to create input buffer"])
        }
        inputBuffer.frameLength = frameCount
        audioData.withUnsafeBytes { rawBuffer in
            inputBuffer.int16ChannelData?.pointee.update(from: rawBuffer.baseAddress!.assumingMemoryBound(to: Int16.self), count: Int(frameCount * webSocketFormat.channelCount))
        }
        let outputFrameCapacity = UInt32(round(Double(frameCount) * audioFormat.sampleRate / webSocketFormat.sampleRate))
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: AVAudioFrameCount(outputFrameCapacity)) else {
            throw NSError(domain: "AudioManager", code: -4, userInfo: [NSLocalizedDescriptionKey: "Failed to create output buffer"])
        }
        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }
        if let error = error {
            throw error
        }
        if status == .error {
            throw NSError(domain: "AudioManager", code: -5, userInfo: [NSLocalizedDescriptionKey: "Playback conversion failed"])
        }
        playerNode.scheduleBuffer(outputBuffer, completionHandler: nil)
        if !playerNode.isPlaying {
            playerNode.play()
            print("Started playback")
        }
    }

    public func stopPlayback() {
        playerNode.stop()
        playerNode.reset()
        print("Playback stopped")
    }

    

    public func shutdownBot() {
        stopRecording()
        stopPlayback()
        print("Bot stopped, music continues if playing.")
    }

    public func shutdownAll() {
        stopRecording()
        stopPlayback()

        // stop and clear background music
        queuePlayer.pause()
        playerLooper?.disableLooping()
        playlistItems.removeAll()
        stopEmittingMusicPosition()

        // tear down audio engine
        audioEngine.stop()
        cancellables.removeAll()
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("Failed to deactivate audio session: \(error)")
            DispatchQueue.main.async { [weak self] in
                self?.eventSink?(["type": "error", "message": "Failed to deactivate audio session: \(error.localizedDescription)"])
            }
        }
        print("AudioManager shutdown (bot + music)")
    }

    public func handleConfigurationChange() {
        print("Audio engine configuration changed")
        if !audioEngine.isRunning {
            print("Engine stopped, attempting to restart")
            do {
                try audioEngine.start()
                if isRecording {
                    print("Reinstalling recording tap")
                    installRecordingTap()
                }
            } catch {
                print("Failed to restart audio engine: \(error)")
                errorPublisher.send("Engine restart failed: \(error.localizedDescription)")
                DispatchQueue.main.async { [weak self] in
                    self?.eventSink?(["type": "error", "message": "Engine restart failed: \(error.localizedDescription)"])
                }
            }
        }
    }

    public func isRecordingActive() -> Bool {
        return isRecording
    }

    
    
    
    
    // ----------------- Background Music Work ---------------------
    
    /// Replace your existing `setMusicPlaylist(_:)` with this:
    // 1) setMusicPlaylist: just builds your array of AVPlayerItems (remote or local). We no longer enqueue them here.
    public func setMusicPlaylist(_ urls: [String]) {
        // 1) Tear down any existing queue/looper
        playerLooper?.disableLooping()
        queuePlayer.removeAllItems()
        
        // 2) Build AVPlayerItems from AVURLAssets, kick off an async preload of the 'playable' & 'duration' keys
        playlistItems = urls.compactMap { urlStr in
            let assetURL: URL
            if isRemoteURL(urlStr), let u = URL(string: urlStr) {
                assetURL = u
            } else {
                assetURL = URL(fileURLWithPath: urlStr)
            }
            
            let asset = AVURLAsset(url: assetURL)
            // prime the asset so metadata & first frames are ready
            asset.loadValuesAsynchronously(forKeys: ["playable", "duration"]) {
                // you could inspect statusOfValue here if you need to error-handle
            }
            
            let item = AVPlayerItem(asset: asset)
            // buffer at least a few seconds before playback
            item.preferredForwardBufferDuration = 5.0
            return item
        }
    }



    
    /// Play a single file, optionally looping
    public func playBackgroundMusic(source: String, loop: Bool = true) {
        // Create the item
        let url = URL(fileURLWithPath: source)
        let item = AVPlayerItem(url: url)
        queuePlayer.removeAllItems()
        queuePlayer.insert(item, after: nil)

        if loop {
          // Attach an AVPlayerLooper to keep it seamlessly looping
          playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        } else {
          playerLooper?.disableLooping()
        }

        queuePlayer.play()
        musicIsPlaying = true
        emitMusicIsPlaying()
        startEmittingMusicPosition()
    }
    
    /// Replace your existing `playTrackAtIndex(_:)` with this:
    public func playTrackAtIndex(_ index: Int) {
        guard index >= 0 && index < playlistItems.count else {
            eventSink?(["type":"error","message":"Invalid track index"])
            return
        }

        playerLooper?.disableLooping()
        queuePlayer.pause()
        queuePlayer.removeAllItems()

        let template = playlistItems[index]
        queuePlayer.insert(template, after: nil)
        playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: template)

        queuePlayer.play()
        musicIsPlaying = true
        emitMusicIsPlaying()
        startEmittingMusicPosition()
    }

    
    public func stopBackgroundMusic() {
        queuePlayer.pause()
        musicIsPlaying = false
        stopEmittingMusicPosition()
        emitMusicIsPlaying()         // → sends {"type":"music_state","state": false}
        playerLooper?.disableLooping()
    }
    
    // 3) seekBackgroundMusic: seeks the queuePlayer and resumes if needed
    public func seekBackgroundMusic(to position: Double) {
        let cm = CMTime(seconds: position, preferredTimescale: 1_000)
        queuePlayer.seek(to: cm) { [weak self] _ in
            guard let self = self else { return }
            // resume only if it was already playing
            if self.musicIsPlaying {
                self.queuePlayer.play()
            }
        }
    }

}
