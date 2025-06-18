import AVFoundation
import Combine
import CommonCrypto


public class AudioManager {
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
    
    private let musicPlayerNode = AVAudioPlayerNode()
    private var musicFile: AVAudioFile?
    private var musicIsPlaying = false
    
    private var playlist: [String] = []
    private var playlistLocalPaths: [String] = []
    private var currentTrackIndex: Int = 0
    private var loopMode: String = "none" // "none", "track", "playlist"


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
            print("Expected options: defaultToSpeaker=8, duckOthers=32, allowBluetoothA2DP=4, Total=44")
            if appliedOptions != 44 {
                print("Warning: Options mismatch, expected 44, got \(appliedOptions)")
                try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
                print("Fallback applied: options=\(session.categoryOptions.rawValue)")
            }
        } catch {
            print("Failed to configure audio session: \(error)")
            errorPublisher.send("Audio session error: \(error.localizedDescription)")
        }

        let actualSampleRate = session.sampleRate
        self.inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: actualSampleRate,
            channels: channels,
            interleaved: true
        )!
        self.audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: actualSampleRate,
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
        } else {
            print("Converters initialized: recording=\(inputFormat)->\(webSocketFormat), playback=\(webSocketFormat)->\(audioFormat)")
        }
    }

    public func setupEngine() {
        // Attach audio nodes
        audioEngine.attach(playerNode)        // Bot playback
        audioEngine.attach(musicPlayerNode)   // Background music playback

        // Connect nodes to main mixer
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: audioFormat)
        audioEngine.connect(musicPlayerNode, to: audioEngine.mainMixerNode, format: audioFormat)
        audioEngine.connect(audioEngine.mainMixerNode, to: audioEngine.outputNode, format: audioFormat)
        
        // Set mixer output volume if needed
        audioEngine.mainMixerNode.outputVolume = 1.0

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(true)
            if enableAEC {
                try inputNode.setVoiceProcessingEnabled(true)
                print("Voice processing enabled for AEC")
            } else {
                print("AEC disabled by configuration")
            }
            try audioEngine.start()
            print("Audio engine started with outputFormat=\(audioFormat)")
        } catch {
            print("Failed to start audio engine or enable AEC: \(error)")
            errorPublisher.send("Engine error: \(error.localizedDescription)")
        }
    }
    
    private func isRemoteURL(_ source: String) -> Bool {
        return source.lowercased().hasPrefix("http://") || source.lowercased().hasPrefix("https://")
    }

    /// Downloads a file from a URL to a unique temp file, returns the local path.
    /// Uses MD5 hash of URL for unique file caching.
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
                try? FileManager.default.moveItem(at: tempURL, to: URL(fileURLWithPath: localPath))
                completion(localPath)
            } else {
                completion(nil)
            }
        }
        task.resume()
    }
    
    /// Simple md5 hash for filename uniqueness
    private func md5(_ string: String) -> String {
        let data = Data(string.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_MD5($0.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    /// Plays music from a local file path, asset, or remote URL. Handles looping.
    public func playBackgroundMusic(source: String, loop: Bool = true) {
        stopBackgroundMusic()
        let play: (String) -> Void = { [weak self] localPath in
            guard let self = self else { return }
            do {
                self.musicFile = try AVAudioFile(forReading: URL(fileURLWithPath: localPath))
                guard let musicFile = self.musicFile else { return }
                self.musicPlayerNode.scheduleFile(musicFile, at: nil, completionHandler: loop ? { [weak self] in
                    guard let self = self else { return }
                    self.playBackgroundMusic(source: localPath, loop: loop)
                } : nil)
                if !self.audioEngine.isRunning {
                    try self.audioEngine.start()
                }
                self.musicPlayerNode.play()
                self.musicIsPlaying = true
                print("Background music started: \(localPath)")
            } catch {
                print("Failed to play music: \(error)")
            }
        }
        if isRemoteURL(source) {
            // Download, then play
            downloadToTemp(source) { localPath in
                DispatchQueue.main.async {
                    if let path = localPath {
                        play(path)
                    } else {
                        print("Failed to download music from \(source)")
                    }
                }
            }
        } else if FileManager.default.fileExists(atPath: source) {
            // Local file, play directly
            play(source)
        } else if let bundlePath = Bundle.main.path(forResource: source, ofType: nil) {
            // Asset in bundle (if you copied it to bundle at build time)
            play(bundlePath)
        } else {
            print("AudioManager: Source not found: \(source)")
        }
    }

    
    public func stopBackgroundMusic() {
        // Is the engine running and node attached?
        guard audioEngine.isRunning, audioEngine.attachedNodes.contains(musicPlayerNode) else {
            musicIsPlaying = false
            playlist = []
            playlistLocalPaths = []
            currentTrackIndex = 0
            print("Background music stopped (engine not running or node detached)")
            return
        }
        // Check if the node is actually playing before stopping
        if musicPlayerNode.isPlaying {
            musicPlayerNode.pause()
        } else {
            print("Background music node was not playing, skipping stop()")
        }
        musicIsPlaying = false
        playlist = []
        playlistLocalPaths = []
        currentTrackIndex = 0
        print("Background music stopped")
    }



    private func installRecordingTap() {
        let bus = 0
        inputNode.installTap(onBus: bus, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self, let converter = self.recordingConverter else {
                self?.errorPublisher.send("Recording converter unavailable")
                return
            }
            let amplitude = buffer.floatChannelData?.pointee.withMemoryRebound(to: Float.self, capacity: Int(buffer.frameLength)) { ptr in
                (0..<Int(buffer.frameLength)).reduce(0.0) { max($0, abs(ptr[$1])) }
            } ?? 0
            print("Input amplitude: \(amplitude)")
            if amplitude < self.amplitudeThreshold && self.playerNode.isPlaying {
                print("Skipping low-amplitude chunk during playback (possible echo)")
                return
            }
            let frameCapacity = UInt32(round(Double(buffer.frameLength) * converter.outputFormat.sampleRate / buffer.format.sampleRate))
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: converter.outputFormat,
                frameCapacity: frameCapacity
            ) else {
                self.errorPublisher.send("Failed to create output buffer")
                return
            }
            var error: NSError?
            let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            if let error = error {
                self.errorPublisher.send("Recording conversion error: \(error.localizedDescription)")
                return
            }
            if status == .error {
                self.errorPublisher.send("Recording conversion failed")
                return
            }
            if let data = outputBuffer.int16ChannelData?.pointee {
                let byteCount = Int(outputBuffer.frameLength) * MemoryLayout<Int16>.size * Int(outputBuffer.format.channelCount)
                let audioData = Data(bytes: data, count: byteCount)
                print("Sending audio chunk, size: \(audioData.count) bytes")
                self.audioChunkPublisher.send(audioData)
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
    
    public func playBackgroundMusicPlaylist(sources: [String], loopMode: String = "none") {
        stopBackgroundMusic()
        playlist = sources
        playlistLocalPaths = Array(repeating: "", count: sources.count)
        currentTrackIndex = 0
        self.loopMode = loopMode
        prepareNextTrack(start: true)
    }
    
    private func prepareNextTrack(start: Bool = false) {
        guard currentTrackIndex < playlist.count else {
            if loopMode == "playlist" && !playlist.isEmpty {
                currentTrackIndex = 0
                prepareNextTrack(start: true)
            }
            return
        }
        let source = playlist[currentTrackIndex]
        if isRemoteURL(source) {
            downloadToTemp(source) { [weak self] localPath in
                guard let self = self, let path = localPath else {
                    print("Download failed for \(source)")
                    return
                }
                DispatchQueue.main.async {
                    self.playSingleTrack(localPath: path, start: start)
                }
            }
        } else {
            playSingleTrack(localPath: source, start: start)
        }
    }
    
    private func playSingleTrack(localPath: String, start: Bool = false) {
        do {
            musicFile = try AVAudioFile(forReading: URL(fileURLWithPath: localPath))
            musicPlayerNode.stop()
            musicPlayerNode.scheduleFile(musicFile!, at: nil, completionHandler: { [weak self] in
                guard let self = self else { return }
                if self.loopMode == "track" {
                    self.prepareNextTrack(start: true) // replays same track
                } else {
                    self.currentTrackIndex += 1
                    self.prepareNextTrack(start: true)
                }
            })
            if !audioEngine.isRunning {
                try audioEngine.start()
            }
            musicPlayerNode.play()
            musicIsPlaying = true
            print("Playing music track: \(localPath)")
        } catch {
            print("Failed to play track \(localPath): \(error)")
        }
    }

    public func shutdownBot() {
        stopRecording()
        stopPlayback()
        // Do NOT stop audioEngine or session, do NOT stop music
        print("Bot stopped, music (if playing) continues.")
    }

    public func shutdownAll() {
        stopRecording()
        stopPlayback()
        musicPlayerNode.stop()
        audioEngine.stop()
        cancellables.removeAll()
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("Failed to deactivate audio session: \(error)")
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
            }
        }
    }

    public func isRecordingActive() -> Bool {
        return isRecording
    }
}
