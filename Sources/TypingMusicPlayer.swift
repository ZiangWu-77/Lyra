import AVFoundation
import Foundation

// Main-run-loop playback. Only current held keys are retained, never input history.
final class TypingMusicPlayer {
    private var player: AVAudioPlayer?
    private var idleTimer: Timer?
    private var idleDeadline: TimeInterval?
    private var heldKeys = Set<String>()
    private var muted = false
    let idleDelay: TimeInterval = 2
    // Reconcile missed key-up events using physical key state, without reading text.
    var isKeyHeld: ((String) -> Bool)?
    var onError: ((String) -> Void)?
    var currentTime: TimeInterval { player?.currentTime ?? 0 }
    var isPlaying: Bool { player?.isPlaying ?? false }

    func load(_ url: URL) {
        pause()
        do {
            let audio = try AVAudioPlayer(contentsOf: url)
            audio.numberOfLoops = -1
            audio.prepareToPlay()
            player = audio
        } catch {
            player = nil
            onError?("交响乐录音无法加载，请检查本地音频文件。")
        }
    }

    func configure(volume: Float, muted: Bool) {
        self.muted = muted
        player?.volume = min(1, max(0, volume))
        if muted { pause() }
    }

    func keyPressed(key: String, down: Bool) {
        guard !muted else { return }
        if down {
            heldKeys.insert(key)
            idleDeadline = nil
            resume()
        } else if heldKeys.remove(key) != nil && heldKeys.isEmpty {
            idleDeadline = ProcessInfo.processInfo.systemUptime + idleDelay
        }
    }

    func preview() {
        guard !muted else { return }
        if heldKeys.isEmpty { idleDeadline = ProcessInfo.processInfo.systemUptime + 2.4 }
        resume()
    }

    private func resume() {
        guard !muted, let player else { return }
        if !player.isPlaying && !player.play() {
            pause()
            onError?("交响乐播放失败，请检查系统音频输出。")
            return
        }
        guard idleTimer == nil else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.checkIdle() }
        idleTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func checkIdle() {
        let now = ProcessInfo.processInfo.systemUptime
        if let isKeyHeld, !heldKeys.isEmpty {
            heldKeys = heldKeys.filter(isKeyHeld)
            if heldKeys.isEmpty { idleDeadline = now + idleDelay }
        }
        if heldKeys.isEmpty, let idleDeadline, now >= idleDeadline { pause() }
    }

    func pause() {
        idleTimer?.invalidate()
        idleTimer = nil
        idleDeadline = nil
        heldKeys.removeAll()
        player?.pause()
    }

    func reset() {
        pause()
        player?.currentTime = 0
    }

    deinit { idleTimer?.invalidate() }
}
