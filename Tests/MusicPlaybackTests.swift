import Foundation

@main struct MusicPlaybackTests {
    static func main() {
        precondition(keytone_lock_network() == 0)
        let music = TypingMusicPlayer()
        music.onError = { message in fatalError(message) }
        music.load(URL(fileURLWithPath: CommandLine.arguments[1]))
        music.configure(volume: 0, muted: false)
        func wait(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        music.keyPressed(key: "A", down: false)
        precondition(!music.isPlaying)
        music.keyPressed(key: "A", down: true)
        wait(2.2) // No autorepeat events: even non-repeating held keys must continue.
        precondition(music.isPlaying && music.currentTime > 2)
        let first = music.currentTime
        music.keyPressed(key: "A", down: true) // Repeated keydown cannot duplicate hold count.
        music.keyPressed(key: "S", down: true)
        music.keyPressed(key: "A", down: false)
        wait(2.2)
        precondition(music.isPlaying && music.currentTime > first + 2)
        music.keyPressed(key: "S", down: false)
        wait(1.2)
        precondition(music.isPlaying) // Thinking pause below two seconds.
        music.keyPressed(key: "unrelated", down: false) // Must not reset deadline.
        wait(1)
        precondition(!music.isPlaying)
        let paused = music.currentTime
        wait(0.1)
        precondition(abs(music.currentTime - paused) < 0.01)
        music.keyPressed(key: "A", down: true)
        precondition(music.isPlaying && abs(music.currentTime - paused) < 0.06)
        music.configure(volume: 0, muted: true)
        music.keyPressed(key: "A", down: true)
        precondition(!music.isPlaying)
        music.configure(volume: 0, muted: false)
        precondition(!music.isPlaying)
        music.keyPressed(key: "A", down: true)
        music.pause()
        precondition(!music.isPlaying)
        // Reconcile a lost key-up without leaving background music running forever.
        music.isKeyHeld = { _ in false }
        music.keyPressed(key: "A", down: true)
        wait(2.3)
        precondition(!music.isPlaying)
        music.reset()
        precondition(music.currentTime == 0)
        music.preview()
        precondition(music.isPlaying)
        music.reset()
        print("PASS: held keys without repeats, overlapping keys, repeat deduplication, two-second release grace, resume, mute, missed-release recovery, reset and preview")
    }
}
