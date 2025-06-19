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
    private let musicPlayerNode = AVAudioPlayerNode()
    private var musicFile: AVAudioFile?
    public var musicIsPlaying = false
    private var playlist: [String] = []
    private var playlistLocalPaths: [String] = []
    private var currentTrackIndex: Int = 0
    private var loopMode: String = "none" // "none", "track", "playlist"

    // Stream for all events
    private var musicPositionTimer: Timer?
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
                try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
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
        audioEngine.attach(musicPlayerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: audioFormat)
        audioEngine.connect(musicPlayerNode, to: audioEngine.mainMixerNode, format: audioFormat)
        audioEngine.connect(audioEngine.mainMixerNode, to: audioEngine.outputNode, format: audioFormat)
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
        musicPlayerNode.volume = volume
    }

    public func getBackgroundMusicVolume() -> Float {
        return musicPlayerNode.volume
    }

    public func seekBackgroundMusic(to position: Double) {
        guard let musicFile = musicFile else {
            print("No music file, cannot seek")
            eventSink?(["type": "error", "message": "No music file loaded for seeking"])
            return
        }
        let sampleRate = musicFile.processingFormat.sampleRate
        let duration = Double(musicFile.length) / sampleRate
        let clampedPosition = max(0, min(position, duration)) // Clamp to valid range
        let framePosition = AVAudioFramePosition(clampedPosition * sampleRate)
        
        // Preserve playback state
        let wasPlaying = musicPlayerNode.isPlaying
        
        // Schedule segment at next render time
        let frameCount = AVAudioFrameCount(musicFile.length - framePosition)
        if frameCount > 0 {
            // Pause briefly to queue new segment
            if wasPlaying {
                musicPlayerNode.pause()
            }
            musicPlayerNode.scheduleSegment(
                musicFile,
                startingFrame: framePosition,
                frameCount: frameCount,
                at: AVAudioTime(hostTime: mach_absolute_time()), // Start immediately
                completionHandler: musicIsPlaying && loopMode == "track" ? { [weak self] in
                    guard let self = self else { return }
                    self.playBackgroundMusic(source: musicFile.url.path, loop: true)
                    print("Music looped after seek.")
                } : nil
            )
            // Resume playback
            if wasPlaying {
                if !audioEngine.isRunning {
                    do {
                        try audioEngine.start()
                        print("Started audioEngine for seek playback.")
                    } catch {
                        print("Failed to start audio engine: \(error)")
                        eventSink?(["type": "error", "message": "Failed to start audio engine: \(error.localizedDescription)"])
                    }
                }
                musicPlayerNode.play()
                musicIsPlaying = true
            }
        } else {
            // Handle edge case: seek to end
            if wasPlaying {
                musicPlayerNode.pause()
            }
            musicPlayerNode.scheduleFile(musicFile, at: nil, completionHandler: nil)
            musicIsPlaying = false
            emitMusicIsPlaying()
            print("Seeked to end, music paused.")
        }
        
        // Emit updated position
        DispatchQueue.main.async { [weak self] in
            guard let sink = self?.eventSink else {
                print("eventSink is nil, cannot send position")
                return
            }
            print("Seeked to position: \(clampedPosition), duration: \(duration)")
            sink(["type": "music_position", "position": clampedPosition, "duration": duration])
        }
    }

    public func startEmittingMusicPosition() {
        stopEmittingMusicPosition()
        print("Starting music position timer")
        musicPositionTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.emitMusicPosition()
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
                try? FileManager.default.moveItem(at: tempURL, to: URL(fileURLWithPath: localPath))
                completion(localPath)
            } else {
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

    public func playBackgroundMusic(source: String, loop: Bool = true) {
        stopBackgroundMusic()
        let play: (String) -> Void = { [weak self] localPath in
            guard let self = self else { return }
            do {
                self.musicFile = try AVAudioFile(forReading: URL(fileURLWithPath: localPath))
                guard let musicFile = self.musicFile else { return }
                let scheduleFile: () -> Void = {
                    self.musicPlayerNode.scheduleFile(musicFile, at: nil, completionHandler: loop ? { [weak self] in
                        guard let self = self, self.musicIsPlaying else { return }
                        self.musicPlayerNode.scheduleFile(musicFile, at: nil, completionHandler: loop ? { [weak self] in
                            self?.playBackgroundMusic(source: localPath, loop: loop)
                            print("Music looped, rescheduling.")
                        } : nil)
                        if self.musicPlayerNode.isPlaying {
                            self.musicPlayerNode.play()
                        }
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self, let sink = self.eventSink else { return }
                            let duration = Double(musicFile.length) / musicFile.processingFormat.sampleRate
                            print("Music looped, emitting position=0")
                            sink(["type": "music_position", "position": 0.0, "duration": duration])
                        }
                        print("Music looped, restarted playback.")
                    } : nil)
                }
                if !self.audioEngine.attachedNodes.contains(self.musicPlayerNode) {
                    self.audioEngine.attach(self.musicPlayerNode)
                    self.audioEngine.connect(self.musicPlayerNode, to: self.audioEngine.mainMixerNode, format: self.audioFormat)
                    print("Reattached musicPlayerNode for playback.")
                }
                if !self.audioEngine.isRunning {
                    try self.audioEngine.start()
                    print("Started audioEngine for playback.")
                }
                scheduleFile()
                self.musicPlayerNode.play()
                self.musicIsPlaying = true
                self.emitMusicIsPlaying()
                self.startEmittingMusicPosition()
                print("Background music started: \(localPath)")
            } catch {
                print("Failed to play music: \(error)")
                DispatchQueue.main.async { [weak self] in
                    self?.eventSink?(["type": "error", "message": "Failed to play music: \(error.localizedDescription)"])
                }
            }
        }
        if isRemoteURL(source) {
            downloadToTemp(source) { localPath in
                DispatchQueue.main.async {
                    if let path = localPath {
                        play(path)
                    }
                }
            }
        } else if FileManager.default.fileExists(atPath: source) {
            play(source)
        } else if let bundlePath = Bundle.main.path(forResource: source, ofType: nil) {
            play(bundlePath)
        } else {
            print("AudioManager: Source not found: \(source)")
            DispatchQueue.main.async { [weak self] in
                self?.eventSink?(["type": "error", "message": "Source not found: \(source)"])
            }
        }
    }

    private func emitMusicPosition() {
        guard let musicFile = musicFile else {
            print("No music file, cannot emit position")
            return
        }
        let duration = Double(musicFile.length) / musicFile.processingFormat.sampleRate
        var position: Double = 0.0
        if let nodeTime = musicPlayerNode.lastRenderTime,
           let playerTime = musicPlayerNode.playerTime(forNodeTime: nodeTime),
           playerTime.sampleRate > 0 {
            position = Double(playerTime.sampleTime) / playerTime.sampleRate
            // Normalize position to [0, duration] for looping
            if position > duration {
                position = position.truncatingRemainder(dividingBy: duration)
            }
        }
        DispatchQueue.main.async { [weak self] in
            guard let sink = self?.eventSink else {
                print("eventSink is nil, cannot send position")
                return
            }
            print("Emitting music position: position=\(position), duration=\(duration)")
            sink(["type": "music_position", "position": position, "duration": duration])
        }
    }

    public func stopBackgroundMusic() {
        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
                print("Started audioEngine for music control.")
            } catch {
                print("Failed to start audio engine: \(error)")
                eventSink?(["type": "error", "message": "Failed to start audio engine: \(error.localizedDescription)"])
            }
        }
        if !audioEngine.attachedNodes.contains(musicPlayerNode) {
            audioEngine.attach(musicPlayerNode)
            audioEngine.connect(musicPlayerNode, to: audioEngine.mainMixerNode, format: audioFormat)
            print("Reattached musicPlayerNode for pause control.")
        }
        if musicPlayerNode.isPlaying {
            musicPlayerNode.pause()
            musicIsPlaying = false
            stopEmittingMusicPosition()
            emitMusicIsPlaying()
            print("Background music paused")
        } else {
            musicIsPlaying = false
            stopEmittingMusicPosition()
            emitMusicIsPlaying()
            print("Background music already paused, updated state")
        }
        playlist = []
        playlistLocalPaths = []
        currentTrackIndex = 0
    }

    private func installRecordingTap() {
        let bus = 0
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
            // Temporarily bypass amplitude check for debugging
            // if amplitude < self.amplitudeThreshold && self.playerNode.isPlaying {
            //     print("Skipping low-amplitude chunk during playback (possible echo)")
            //     return
            // }
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
                    DispatchQueue.main.async { [weak self] in
                        self?.eventSink?(["type": "error", "message": "Download failed for \(source)"])
                    }
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
                    self.prepareNextTrack(start: true)
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
            DispatchQueue.main.async { [weak self] in
                self?.eventSink?(["type": "error", "message": "Failed to play track \(localPath): \(error.localizedDescription)"])
            }
        }
    }

    public func shutdownBot() {
        stopRecording()
        stopPlayback()
        print("Bot stopped, music continues if playing.")
        // Ensure musicPlayerNode and audioEngine remain controllable
        if !audioEngine.attachedNodes.contains(musicPlayerNode) {
            audioEngine.attach(musicPlayerNode)
            audioEngine.connect(musicPlayerNode, to: audioEngine.mainMixerNode, format: audioFormat)
            print("Reattached musicPlayerNode for continued control.")
        }
        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
                print("Restarted audioEngine for music control.")
            } catch {
                print("Failed to restart audio engine: \(error)")
                eventSink?(["type": "error", "message": "Failed to restart audio engine: \(error.localizedDescription)"])
            }
        }
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
}
