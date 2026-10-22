import AVFoundation

/// The ball's roll and its clicks, made from filtered white noise as the Node version's WebAudio graph did.
/// Main queue only. The engine starts on the first spin with sound on, so a silent table never opens the device.
final class RouletteSound {
    var isMuted = false {
        didSet { if isMuted { stopRoll() } }
    }

    private let engine = AVAudioEngine()
    private let rollPlayer = AVAudioPlayerNode()
    private let rollFilter = AVAudioUnitEQ(numberOfBands: 1)
    private var clickPlayers: [AVAudioPlayerNode] = []
    private var nextClickPlayer = 0
    private var clickBuffers: [Float: AVAudioPCMBuffer] = [:]
    private var isRolling = false
    private var rollRamp: Timer?
    private lazy var format = AVAudioFormat(standardFormatWithSampleRate: engine.outputNode.outputFormat(forBus: 0).sampleRate,
                                            channels: 1)

    private static let clickPlayerCount = 4
    private static let rollPeakVolume: Float = 0.05
    private static let rollRampIn: TimeInterval = 0.3
    private static let rollRampOut: TimeInterval = 0.25

    func prepare() {
        guard !isMuted, !engine.isRunning else { return }
        if clickPlayers.isEmpty { wire() }
        do {
            try engine.start()
        } catch {
            Log.write("roulette sound could not start: \(error.localizedDescription)")
        }
    }

    func click(volume: Float, frequency: Float) {
        guard !isMuted, engine.isRunning, let buffer = clickBuffer(at: frequency) else { return }
        let player = clickPlayers[nextClickPlayer]
        nextClickPlayer = (nextClickPlayer + 1) % clickPlayers.count
        player.volume = volume
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
    }

    func startRoll() {
        guard !isMuted, engine.isRunning, !isRolling, let noise = noiseBuffer(seconds: 1) else { return }
        isRolling = true
        rollFilter.bands[0].frequency = 1100
        rollPlayer.volume = 0.0001
        rollPlayer.scheduleBuffer(noise, at: nil, options: .loops)
        rollPlayer.play()
        ramp(to: Self.rollPeakVolume, over: Self.rollRampIn) {}
    }

    /// 1 while the ball still flies, falling to 0 as it settles.
    func rollPitch(_ speed: Double) {
        guard isRolling else { return }
        rollFilter.bands[0].frequency = Float(450 + 750 * speed)
    }

    func stopRoll() {
        guard isRolling else { return }
        isRolling = false
        ramp(to: 0.0001, over: Self.rollRampOut) { [rollPlayer] in rollPlayer.stop() }
    }

    private func wire() {
        let band = rollFilter.bands[0]
        band.filterType = .bandPass
        band.frequency = 1100
        band.bandwidth = Self.octaves(forQ: 1.1)
        band.bypass = false
        engine.attach(rollPlayer)
        engine.attach(rollFilter)
        engine.connect(rollPlayer, to: rollFilter, format: format)
        engine.connect(rollFilter, to: engine.mainMixerNode, format: format)
        for _ in 0..<Self.clickPlayerCount {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            clickPlayers.append(player)
        }
    }

    /// Exponential, like the WebAudio ramps it replaces.
    private func ramp(to target: Float, over duration: TimeInterval, then finish: @escaping () -> Void) {
        rollRamp?.invalidate()
        let from = max(rollPlayer.volume, 0.0001)
        let started = Date()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            let progress = min(1, Date().timeIntervalSince(started) / duration)
            rollPlayer.volume = from * powf(target / from, Float(progress))
            guard progress >= 1 else { return }
            timer.invalidate()
            finish()
        }
        RunLoop.main.add(timer, forMode: .common)
        rollRamp = timer
    }

    /// A 60 ms burst of noise through a narrow band-pass, fading out over 45 ms.
    private func clickBuffer(at frequency: Float) -> AVAudioPCMBuffer? {
        if let cached = clickBuffers[frequency] { return cached }
        guard let format, let buffer = noiseBuffer(seconds: 0.06), let samples = buffer.floatChannelData?[0] else { return nil }
        var filter = BandPass(frequency: Double(frequency), q: 6, sampleRate: format.sampleRate)
        let fadeFrames = 0.045 * format.sampleRate
        for frame in 0..<Int(buffer.frameLength) {
            let envelope = Float(pow(0.0001, min(1, Double(frame) / fadeFrames)))
            samples[frame] = Float(filter.process(Double(samples[frame]))) * envelope
        }
        clickBuffers[frequency] = buffer
        return buffer
    }

    private func noiseBuffer(seconds: Double) -> AVAudioPCMBuffer? {
        guard let format else { return nil }
        let frames = AVAudioFrameCount(max(1, seconds * format.sampleRate))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for frame in 0..<Int(frames) {
            samples[frame] = Float.random(in: -1...1)
        }
        return buffer
    }

    private static func octaves(forQ q: Double) -> Float {
        Float(2 / log(2) * asinh(1 / (2 * q)))
    }
}

/// The RBJ cookbook band-pass, constant 0 dB peak gain, matching WebAudio's BiquadFilterNode "bandpass".
private struct BandPass {
    private let b0, b2, a1, a2: Double
    private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    init(frequency: Double, q: Double, sampleRate: Double) {
        let omega = 2 * Double.pi * frequency / sampleRate
        let alpha = sin(omega) / (2 * q)
        let a0 = 1 + alpha
        b0 = alpha / a0
        b2 = -alpha / a0
        a1 = -2 * cos(omega) / a0
        a2 = (1 - alpha) / a0
    }

    mutating func process(_ input: Double) -> Double {
        let output = b0 * input + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = input
        y2 = y1
        y1 = output
        return output
    }
}
