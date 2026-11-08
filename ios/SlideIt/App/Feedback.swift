import AVFoundation
import UIKit

/// Sound effects (synthesised on the fly: no audio files needed) and haptics.
@MainActor
final class Feedback {
    static let shared = Feedback()

    enum Sound: CaseIterable {
        case slide, match, unmatch, beep, go, win, lose, pop, bump, join
    }

    static let soundKey = "soundOn"
    var soundOn: Bool { UserDefaults.standard.object(forKey: Self.soundKey) as? Bool ?? true }

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var buffers: [Sound: AVAudioPCMBuffer] = [:]
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let notify = UINotificationFeedbackGenerator()

    private init() {
        // .ambient: respects the silent switch and mixes with the player's music.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        for _ in 0..<6 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
        }
        engine.mainMixerNode.outputVolume = 0.9
        for s in Sound.allCases { buffers[s] = render(s) }
        light.prepare()
    }

    // MARK: Haptics

    func tap() { light.impactOccurred(intensity: 0.75) }
    func bump() { rigid.impactOccurred(intensity: 0.6) }
    func success() { notify.notificationOccurred(.success) }
    func warning() { notify.notificationOccurred(.warning) }

    // MARK: Sound

    func play(_ sound: Sound) {
        guard soundOn, let buffer = buffers[sound] else { return }
        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }
        let p = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        p.stop()
        p.scheduleBuffer(buffer, at: nil, options: [])
        p.play()
    }

    private struct Note {
        var freq: Double
        var start: Double
        var duration: Double
        var volume: Double
        var wave: Wave = .sine
        var slideTo: Double? = nil
    }

    private enum Wave { case sine, triangle, square, saw }

    private func notes(for sound: Sound) -> [Note] {
        switch sound {
        case .slide: [Note(freq: 500, start: 0, duration: 0.05, volume: 0.22, wave: .triangle, slideTo: 340)]
        case .match: [Note(freq: 880, start: 0, duration: 0.09, volume: 0.25), Note(freq: 1320, start: 0.06, duration: 0.14, volume: 0.2)]
        case .unmatch: [Note(freq: 300, start: 0, duration: 0.08, volume: 0.15, slideTo: 220)]
        case .beep: [Note(freq: 620, start: 0, duration: 0.12, volume: 0.12, wave: .square)]
        case .go: [Note(freq: 990, start: 0, duration: 0.3, volume: 0.14, wave: .square)]
        case .win: [523.0, 659, 784, 1047, 1319].enumerated().map { Note(freq: $1, start: Double($0) * 0.09, duration: 0.2, volume: 0.25, wave: .triangle) }
        case .lose: [392.0, 330, 262].enumerated().map { Note(freq: $1, start: Double($0) * 0.13, duration: 0.22, volume: 0.1, wave: .saw) }
        case .pop: [Note(freq: 650, start: 0, duration: 0.07, volume: 0.2, slideTo: 1200)]
        case .bump: [Note(freq: 130, start: 0, duration: 0.06, volume: 0.12, wave: .square)]
        case .join: [Note(freq: 660, start: 0, duration: 0.08, volume: 0.2), Note(freq: 990, start: 0.07, duration: 0.1, volume: 0.2)]
        }
    }

    private func render(_ sound: Sound) -> AVAudioPCMBuffer? {
        let notes = notes(for: sound)
        let rate = format.sampleRate
        let length = (notes.map { $0.start + $0.duration }.max() ?? 0) + 0.02
        let frames = AVAudioFrameCount(length * rate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let data = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for i in 0..<Int(frames) { data[i] = 0 }
        for n in notes {
            let startFrame = Int(n.start * rate)
            let count = Int(n.duration * rate)
            var phase = 0.0
            for k in 0..<count where startFrame + k < Int(frames) {
                let t = Double(k) / Double(count)
                let f = n.slideTo.map { n.freq * pow($0 / n.freq, t) } ?? n.freq
                phase += f / rate
                let x = phase - floor(phase)
                let s: Double = switch n.wave {
                case .sine: sin(2 * .pi * x)
                case .triangle: 4 * abs(x - 0.5) - 1
                case .square: x < 0.5 ? 1 : -1
                case .saw: 2 * x - 1
                }
                // Quick attack, exponential-ish decay: a soft "pluck".
                let env = min(1, Double(k) / (0.004 * rate)) * pow(1 - t, 2)
                data[startFrame + k] += Float(s * env * n.volume)
            }
        }
        return buffer
    }
}
