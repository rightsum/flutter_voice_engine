import AVFoundation
import Combine

public class AudioManager {
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var inputNode: AVAudioInputNode { audioEngine.inputNode }
    private var inputFormat: AVAudioFormat // 48kHz, mono, Float32
    private var audioFormat: AVAudioFormat // 48kHz, stereo, Float32
    private var webSocketFormat: AVAudioFormat // 24kHz, mono, PCM16
    private var isRecording = false
    private let audioChunkPublisher = PassthroughSubject<Data, Never>()
    public let errorPublisher = PassthroughSubject<String, Never>()
    private var recordingConverter: AVAudioConverter?
    private var playbackConverter: AVAudioConverter?
    private let amplitudeThreshold: Float = 0.05 // Match native
    private let enableAEC: Bool = true // Match native
    private var cancellables = Set<AnyCancellable>()
    private let targetSampleRate: Float64 = 24000 // WebSocket expects 24kHz

    public init(
        channels: UInt32 = 1,
        sampleRate: Double = 48000,
        bitDepth: Int = 16,
        bufferSize: Int = 4096,
        amplitudeThreshold: Float = 0.05,
        enableAEC: Bool = true
    ) {
        let hardwareSampleRate: Float64 = 48000
        self.inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: hardwareSampleRate,
            channels: channels,
            interleaved: true
        )!
        self.audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: hardwareSampleRate,
            channels: 2,
            interleaved: false
        )!
        self.webSocketFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: channels,
            interleaved: true
        )!
        setupAudioSession()
        let session = AVAudioSession.sharedInstance()
        if session.sampleRate != hardwareSampleRate {
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
        }
        setupConverters()
    }

    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            let options: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .duckOthers, .allowBluetoothA2DP]
            try session.setCategory(
                .playAndRecord,
                mode: .spokenAudio,
                options: options
            )
            try session.setPreferredSampleRate(48000)
            try session.setPreferredIOBufferDuration(0.005) // Match native
            try session.setInputGain(1.0) // Ensure loud input
            try session.setActive(true, options: [.notifyOthersOnDeactivation])
            let appliedOptions = session.categoryOptions.rawValue
            print("Audio session configured: sampleRate=\(session.sampleRate), channels=\(session.outputNumberOfChannels), inputGain=\(session.inputGain), options=\(appliedOptions), bufferDuration=\(session.ioBufferDuration)")
            print("Expected options: defaultToSpeaker=8, duckOthers=32, allowBluetoothA2DP=4, Total=44")
            if appliedOptions != 44 {
                print("Warning: Options mismatch, expected 44, got \(appliedOptions)")
                try session.setCategory(
                    .playAndRecord,
                    mode: .spokenAudio,
                    options: [.defaultToSpeaker]
                )
                print("Fallback applied: options=\(session.categoryOptions.rawValue)")
            }
        } catch {
            print("Failed to configure audio session: \(error)")
            errorPublisher.send("Audio session error: \(error.localizedDescription)")
        }
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
        audioEngine.attach(playerNode)
        // Ensure audio session is active
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(true)
        } catch {
            errorPublisher.send("Failed to activate audio session: \(error.localizedDescription)")
            return
        }
        // Use predefined audioFormat for output (2 ch, 48kHz, Float32)
        guard audioFormat.sampleRate > 0, audioFormat.channelCount == 2 else {
            errorPublisher.send("Invalid output format: \(audioFormat)")
            return
        }
        // Use inputFormat for input node (1 ch, 48kHz, Float32)
        var inputNodeFormat = inputNode.outputFormat(forBus: 0)
        if inputNodeFormat.sampleRate == 0 || inputNodeFormat.channelCount != 1 {
            print("Invalid input node format: \(inputNodeFormat), using fallback: \(inputFormat)")
            inputNodeFormat = inputFormat
        }
        do {
            // Connect nodes using validated formats
            audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: audioFormat)
            audioEngine.connect(audioEngine.mainMixerNode, to: audioEngine.outputNode, format: audioFormat)
            audioEngine.mainMixerNode.outputVolume = 1.0
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

    public func setupAudioSession(
        category: AVAudioSession.Category,
        mode: AVAudioSession.Mode,
        options: AVAudioSession.CategoryOptions,
        sampleRate: Double,
        bufferDuration: Double
    ) throws {
        // Override with native settings
        setupAudioSession()
    }

    public func startRecording() -> AnyPublisher<Data, Never> {
        guard !isRecording else {
            print("Already recording")
            return audioChunkPublisher.eraseToAnyPublisher()
        }
        isRecording = true
        print("Starting recording with format=\(webSocketFormat)")
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
            inputBuffer.int16ChannelData?.pointee.assign(from: rawBuffer.baseAddress!.assumingMemoryBound(to: Int16.self), count: Int(frameCount * webSocketFormat.channelCount))
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

    public func shutdown() {
        stopRecording()
        stopPlayback()
        audioEngine.stop()
        cancellables.removeAll()
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
        print("AudioManager shutdown")
    }
}
