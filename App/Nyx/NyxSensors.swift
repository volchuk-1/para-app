import Foundation
import AVFoundation
import CoreMotion

/// «Під музику» and «Нахил»: a number 0…1 from the phone itself, read only while the app is open.
/// The microphone: how loud the room is right now, against the loudest of the last few seconds (so a quiet song and a
/// loud one both move the toy). Nothing is recorded or kept: only the loudness of each moment.
final class NyxSensors {
    private(set) var env: Double = 0
    private var engine: AVAudioEngine?
    private let motion = CMMotionManager()
    private var peak: Float = 0.02
    private var smooth: Float = 0

    // MARK: the microphone

    func startMic(_ done: @escaping (Bool) -> Void) {
        guard engine == nil else { done(true); return }
        AVAudioApplication.requestRecordPermission { [weak self] ok in
            DispatchQueue.main.async {
                guard ok, let self else { done(false); return }
                done(self.runMic())
            }
        }
    }

    private func runMic() -> Bool {
        let s = AVAudioSession.sharedInstance()
        do {
            // music on this phone keeps playing
            try s.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP])
            try s.setActive(true)
        } catch { return false }
        let e = AVAudioEngine()
        let input = e.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0 else { return false }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buf, _ in
            guard let self, let ch = buf.floatChannelData?[0] else { return }
            let n = Int(buf.frameLength)
            guard n > 0 else { return }
            var sum: Float = 0
            for i in 0..<n { sum += ch[i] * ch[i] }
            let rms = (sum / Float(n)).squareRoot()
            // the loudest lately falls slowly, so the scale follows the song
            self.peak = max(rms, self.peak * 0.995, 0.01)
            let v = min(1, rms / self.peak)
            self.smooth = self.smooth * 0.6 + v * 0.4
            let out = Double(self.smooth)
            DispatchQueue.main.async { self.env = out }
        }
        do { try e.start() } catch { input.removeTap(onBus: 0); return false }
        engine = e
        return true
    }

    func stopMic() {
        guard let e = engine else { return }
        e.inputNode.removeTap(onBus: 0)
        e.stop()
        engine = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: the tilt: lying flat — 0, standing up — 1

    func startTilt() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 20.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let g = m?.gravity else { return }
            self?.env = max(0, min(1, 1 - abs(g.z)))
        }
    }

    func stopTilt() { motion.stopDeviceMotionUpdates() }

    func stopAll() { stopMic(); stopTilt() }
}
