import AVFAudio
import Foundation
import UIKit

/// Exact 1:1 port of `J2me.iOS.Platform.BackgroundAudio` using bundled `background-loop.wav`.
@MainActor
final class BackgroundAudio {
    static let shared = BackgroundAudio()

    private var observers: [NSObjectProtocol] = []
    private var player: AVAudioPlayer?
    private var monitorTimer: Timer?
    private var wanted = false
    private var interrupted = false

    private(set) var status: String = "stopped"

    var isRunning: Bool {
        wanted && (player?.isPlaying == true || interrupted)
    }

    var isEnabled: Bool {
        wanted
    }

    private init() {
        observeAudioSession()
    }

    func start() {
        wanted = true
        interrupted = false
        ensurePlaying()
        startMonitor()
    }

    func stop() {
        wanted = false
        interrupted = false
        monitorTimer?.invalidate()
        monitorTimer = nil
        player?.stop()
        player = nil
        status = "stopped"
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    func foreground() {
        guard wanted else { return }
        interrupted = false
        ensurePlaying()
    }

    private func startMonitor() {
        monitorTimer?.invalidate()
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.wanted, !self.interrupted else { return }
                if self.player?.isPlaying != true {
                    self.ensurePlaying()
                }
            }
        }
    }

    private func ensurePlaying() {
        guard wanted else { return }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            status = "SetCategory: \(error.localizedDescription)"
            return
        }

        if player == nil {
            guard let url = Bundle.main.url(forResource: "background-loop", withExtension: "wav") else {
                status = "error: missing background-loop.wav"
                return
            }
            do {
                let p = try AVAudioPlayer(contentsOf: url)
                p.numberOfLoops = -1
                p.volume = 0.01
                p.prepareToPlay()
                self.player = p
            } catch {
                status = "AVAudioPlayer: \(error.localizedDescription)"
                return
            }
        }

        if let p = player {
            if !p.isPlaying {
                let ok = p.play()
                status = ok ? "playing" : "Play() trả false"
            } else {
                status = "playing"
            }
        }
    }

    private func observeAudioSession() {
        let nc = NotificationCenter.default

        observers.append(nc.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let typeRaw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor [weak self] in
                guard let self, self.wanted else { return }
                if let raw = typeRaw, let type = AVAudioSession.InterruptionType(rawValue: raw) {
                    switch type {
                    case .began:
                        self.interrupted = true
                        self.status = "interrupted"
                    case .ended:
                        self.interrupted = false
                        self.ensurePlaying()
                    @unknown default:
                        break
                    }
                }
            }
        })

        observers.append(nc.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.wanted, !self.interrupted else { return }
                self.ensurePlaying()
            }
        })

        observers.append(nc.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.wanted else { return }
                self.player = nil
                self.interrupted = false
                self.status = "media-services-lost"
                self.ensurePlaying()
            }
        })
    }
}
