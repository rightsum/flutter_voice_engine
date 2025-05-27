import AVFoundation
import Combine

public class AudioManager {
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var inputNode: AVAudioInputNode { audioEngine.inputNode }
    private var inputFormat: AVAudioFormat
    private var outputFormat: AVAudioFormat
    private var targetFormat: AVAudioFormat
    private var isRecording = false
    private let audioChunkPublisher = PassthroughSubject<String, Never>()
    private let errorPublisher = PassthroughSubject<String, Never>()
    private var recordingConverter: AVAudioConverter?
    private var playbackConverter: AVAudioConverter?
    private let amplitudeThreshold: Float
    private let enableAEC: Bool
    private var cancellables = Set<AnyCancellable>()

public init(
    channels: UInt32 = 1,
    sampleRate: Double = 48000,
    bitDepth: Int = 16,
    bufferSize: Int = 4096,
    amplitudeThreshold: Float = 0.05,
    enableAEC: Bool = true
) {
    self.inputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: channels,
        interleaved: true
    )!
    self.outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 2,
        interleaved: false
    )!
    self.targetFormat = AVAudioFormat(
        commonFormat: bitDepth == 16 ? .pcmFormatInt16 : .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: channels,
        interleaved: true
    )!
    self.amplitudeThreshold = amplitudeThreshold
    self.enableAEC = enableAEC
}

public func setupAudioSession(
    category: AVAudioSession.Category,
    mode: AVAudioSession.Mode,
    options: AVAudioSession.CategoryOptions,
    sampleRate: Double,
    bufferDuration: Double
) throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(category, mode: mode, options: options)
    try session.setPreferredSampleRate(sampleRate)
    try session.setPreferredIOBufferDuration(bufferDuration)
    try session.setActive(true, options: .notifyOthersOnDeactivation)
    if session.sampleRate != sampleRate {
        self.inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: session.sampleRate,
            channels: inputFormat.channelCount,
            interleaved: true
        )!
        self.outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: session.sampleRate,
            channels: 2,
            interleaved: false
        )!
        self.targetFormat = AVAudioFormat(
            commonFormat: targetFormat.commonFormat,
            sampleRate: session.sampleRate,
            channels: inputFormat.channelCount,
            interleaved: true
        )!
        setupConverters()
    }
}

private func setupConverters() {
    recordingConverter = AVAudioConverter(from: inputFormat, to: targetFormat)
    playbackConverter = AVAudioConverter(from: targetFormat, to: outputFormat)
    if recordingConverter == nil || playbackConverter == nil {
        errorPublisher.send("Failed to initialize audio converters")
    }
}

public func setupEngine() throws {
    audioEngine.attach(playerNode)
    let engineOutputFormat = audioEngine.outputNode.inputFormat(forBus: 0)
    audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: engineOutputFormat)
    audioEngine.connect(audioEngine.mainMixerNode, to: audioEngine.outputNode, format: engineOutputFormat)
    if enableAEC {
        try inputNode.setVoiceProcessingEnabled(true)
    }
    try audioEngine.start()
    setupConverters()
}

public func startRecording() -> AnyPublisher<String, Never> {
    guard !isRecording else { return audioChunkPublisher.eraseToAnyPublisher() }
    isRecording = true
    let bus = 0
    inputNode.installTap(onBus: bus, bufferSize: AVAudioFrameCount(4096), format: inputFormat) { [weak self] buffer, _ in
        guard let self = self, let converter = self.recordingConverter else {
            self?.errorPublisher.send("Recording converter unavailable")
            return
        }
        let amplitude = buffer.floatChannelData?.pointee.withMemoryRebound(to: Float.self, capacity: Int(buffer.frameLength)) { ptr in
            (0..<Int(buffer.frameLength)).reduce(0.0) { max($0, abs(ptr[$1])) }
        } ?? 0
        if amplitude < self.amplitudeThreshold && self.playerNode.isPlaying {
            return
        }
        let frameCapacity = UInt32(round(Double(buffer.frameLength) * converter.outputFormat.sampleRate / buffer.format.sampleRate))
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: converter.outputFormat,
            frameCapacity: AVAudioFrameCount(frameCapacity)
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
        let base64String = self.bufferToBase64(buffer: outputBuffer)
        self.audioChunkPublisher.send(base64String)
    }
    return audioChunkPublisher.eraseToAnyPublisher()
}

public func stopRecording() {
    isRecording = false
    inputNode.removeTap(onBus: 0)
    audioChunkPublisher.send(completion: .finished)
}

public func playAudioChunk(base64String: String) throws {
    guard audioEngine.isRunning, let converter = playbackConverter else {
        throw NSError(domain: "AudioManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Audio engine not running or playback converter unavailable"])
    }
    guard let data = Data(base64Encoded: base64String) else {
        throw NSError(domain: "AudioManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to decode Base64 audio chunk"])
    }
    let frameCount = AVAudioFrameCount(data.count / (targetFormat.commonFormat == .pcmFormatInt16 ? MemoryLayout<Int16>.size : MemoryLayout<Float>.size))
    guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: converter.inputFormat, frameCapacity: frameCount) else {
        throw NSError(domain: "AudioManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to create input buffer"])
    }
    inputBuffer.frameLength = frameCount
    data.withUnsafeBytes { rawBuffer in
        if targetFormat.commonFormat == .pcmFormatInt16 {
            inputBuffer.int16ChannelData?.pointee.assign(from: rawBuffer.baseAddress!.assumingMemoryBound(to: Int16.self), count: Int(frameCount))
        } else {
            inputBuffer.floatChannelData?.pointee.assign(from: rawBuffer.baseAddress!.assumingMemoryBound(to: Float.self), count: Int(frameCount))
        }
    }
    let outputFrameCapacity = UInt32(round(Double(frameCount) * converter.outputFormat.sampleRate / converter.inputFormat.sampleRate))
    guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: AVAudioFrameCount(outputFrameCapacity)) else {
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
    }
}

public func stopPlayback() {
    playerNode.stop()
    playerNode.reset()
}

public func shutdown() {
    stopRecording()
    stopPlayback()
    audioEngine.stop()
    try? AVAudioSession.sharedInstance().setActive(false)
}

private func bufferToBase64(buffer: AVAudioPCMBuffer) -> String {
    if targetFormat.commonFormat == .pcmFormatInt16 {
        guard let data = buffer.int16ChannelData?.pointee else { return "" }
        let byteCount = Int(buffer.frameLength) * MemoryLayout<Int16>.size * Int(buffer.format.channelCount)
        return Data(bytes: data, count: byteCount).base64EncodedString()
    } else {
        guard let data = buffer.floatChannelData?.pointee else { return "" }
        let byteCount = Int(buffer.frameLength) * MemoryLayout<Float>.size * Int(buffer.format.channelCount)
        return Data(bytes: data, count: byteCount).base64EncodedString()
    }
}

}
