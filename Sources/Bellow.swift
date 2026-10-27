import AppKit

/// A bull's snort and bellow, synthesized once: a sawtooth that rises and sags, growling, through two formants.
enum Bellow {
    private static let sampleRate = 44_100.0
    private static let snortSeconds = 0.16
    private static let bellowStart = 0.2
    private static let bellowSeconds = 1.1
    private static let peak = 0.55

    private static let sound = NSSound(data: wav(samples()))

    static func play() {
        guard let sound else { return }
        sound.stop()
        sound.play()
    }

    private static func samples() -> [Double] {
        let frameCount = Int((bellowStart + bellowSeconds) * sampleRate)
        var snort = BandPass(frequency: 520, q: 0.7, sampleRate: sampleRate)
        var body = BandPass(frequency: 160, q: 0.8, sampleRate: sampleRate)
        var firstFormant = BandPass(frequency: 380, q: 2.5, sampleRate: sampleRate)
        var secondFormant = BandPass(frequency: 950, q: 4, sampleRate: sampleRate)
        var breath = BandPass(frequency: 1800, q: 1, sampleRate: sampleRate)
        var phase = 0.0
        var output = [Double](repeating: 0, count: frameCount)
        for frame in 0..<frameCount {
            let time = Double(frame) / sampleRate
            let noise = Double.random(in: -1...1)
            if time < snortSeconds {
                output[frame] += snort.process(noise) * pow(sin(.pi * time / snortSeconds), 2) * 1.6
            }
            let bellowTime = time - bellowStart
            guard bellowTime >= 0 else { continue }
            phase = (phase + pitch(at: bellowTime) / sampleRate).truncatingRemainder(dividingBy: 1)
            let growl = 1 + 0.35 * sin(2 * .pi * 28 * bellowTime)
            let source = (2 * phase - 1) * growl + noise * 0.25
            let voice = body.process(source) + firstFormant.process(source) * 0.9
                + secondFormant.process(source) * 0.45 + breath.process(noise) * 0.12
            output[frame] += voice * envelope(at: bellowTime)
        }
        let loudest = output.map(abs).max() ?? 0
        return loudest > 0 ? output.map { $0 / loudest * peak } : output
    }

    /// Hertz: climbs from 85 to 140 over the first quarter second, wavers, then sags toward 110.
    private static func pitch(at time: Double) -> Double {
        let rise = min(1, time / 0.25)
        let sag = max(0, (time - 0.6) / 0.5)
        return 85 + 55 * (1 - pow(1 - rise, 2)) - 30 * sag + 4 * sin(2 * .pi * 5.5 * time)
    }

    private static func envelope(at time: Double) -> Double {
        let attack = min(1, time / 0.08)
        let release = min(1, max(0, (bellowSeconds - time) / 0.35))
        return attack * release
    }

    private static func wav(_ samples: [Double]) -> Data {
        var data = Data()
        func append<Value: FixedWidthInteger>(_ value: Value) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        let byteCount = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8))
        append(36 + byteCount)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(sampleRate))
        append(UInt32(sampleRate) * 2)
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(byteCount)
        for sample in samples {
            append(Int16(max(-1, min(1, sample)) * Double(Int16.max)))
        }
        return data
    }
}
