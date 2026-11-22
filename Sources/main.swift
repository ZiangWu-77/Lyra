import AppKit
import AVFoundation
import CoreGraphics
import ServiceManagement

// The only startup path: network must be blocked before input can be observed.
guard keytone_lock_network() == 0 else {
    fputs("KeyTone: offline protection failed; refusing to start.\n", stderr)
    exit(70)
}

struct Pack: Decodable {
    let id: String
    let name: String
    let segments: [String: [[Int]]]
}

enum AssetError: Error { case invalidAudio, invalidSegment }

final class SoundBank {
    let pack: Pack
    let format: AVAudioFormat
    let sounds: [String: [AVAudioPCMBuffer]]

    init(directory: URL, id: String) throws {
        pack = try JSONDecoder().decode(Pack.self, from: Data(contentsOf: directory.appendingPathComponent(id + ".json")))
        let file = try AVAudioFile(forReading: directory.appendingPathComponent(id + ".wav"))
        format = file.processingFormat
        guard file.length > 0, file.length < 10_000_000,
              let whole = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw AssetError.invalidAudio
        }
        try file.read(into: whole)
        guard let source = whole.floatChannelData else { throw AssetError.invalidAudio }
        var loaded: [String: [AVAudioPCMBuffer]] = [:]
        for (key, parts) in pack.segments {
            var buffers: [AVAudioPCMBuffer] = []
            for part in parts {
                guard part.count == 2, part[0] >= 0, part[1] > part[0], part[1] <= Int(whole.frameLength),
                      let slice = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(part[1] - part[0])),
                      let destination = slice.floatChannelData else { throw AssetError.invalidSegment }
                slice.frameLength = slice.frameCapacity
                for channel in 0..<Int(format.channelCount) {
                    destination[channel].update(from: source[channel].advanced(by: part[0]), count: Int(slice.frameLength))
                }
                buffers.append(slice)
            }
            loaded[key] = buffers
        }
        guard loaded["KeyA"]?.isEmpty == false else { throw AssetError.invalidAudio }
        sounds = loaded
    }
}

let soundDirectory = Bundle.main.resourceURL!.appendingPathComponent("Sounds")
let packs: [Pack] = ((try? FileManager.default.contentsOfDirectory(at: soundDirectory, includingPropertiesForKeys: nil)) ?? [])
    .filter { $0.pathExtension == "json" }
    .compactMap { try? JSONDecoder().decode(Pack.self, from: Data(contentsOf: $0)) }
    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

let musicDirectory = Bundle.main.resourceURL!.appendingPathComponent("Music")
let musicPack = (try? Data(contentsOf: musicDirectory.appendingPathComponent("beethoven5.json")))
    .flatMap { try? JSONDecoder().decode(Pack.self, from: $0) }

if CommandLine.arguments.contains("--verify-assets") {
    do {
        guard packs.count == 14 else { throw AssetError.invalidAudio }
        var segments = 0
        for pack in packs {
            let bank = try SoundBank(directory: soundDirectory, id: pack.id)
            segments += bank.sounds.values.reduce(0) { $0 + $1.count }
        }
        guard let musicPack else { throw AssetError.invalidAudio }
        let musicBank = try SoundBank(directory: musicDirectory, id: musicPack.id)
        guard let clips = musicBank.sounds["KeyA"], clips.count == 1 else { throw AssetError.invalidAudio }
        print("PASS: \(packs.count) local sound packs; \(segments) valid PCM segments; one continuous orchestral recording")
        exit(0)
    } catch { fputs("FAIL: invalid bundled sound assets\n", stderr); exit(1) }
}

// Each playback channel serializes its own audio operations; keystrokes never reach storage or a logger.
final class AudioPlayer {
    private let queue = DispatchQueue(label: "local.keytone.audio", qos: .userInteractive)
    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var bank: SoundBank?
    private var next = 0
    private var gain: Float = 0.3
    private var silent = false
    private var releases = true
    var onError: ((String) -> Void)?
    private let voiceCount: Int

    init(voiceCount: Int = 32) {
        self.voiceCount = voiceCount
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            self?.queue.async { [weak self] in self?.restart() }
        }
    }
    private func restart() {
        guard bank != nil else { return }
        do {
            if !engine.isRunning { try engine.start() }
            for player in players where !player.isPlaying { player.play() }
        } catch { reportError() }
    }
    private func reportError() {
        DispatchQueue.main.async { [weak self] in self?.onError?("音频设备不可用，请检查系统输出后重新试听。") }
    }
    func load(_ pack: Pack, directory: URL = soundDirectory) {
        queue.async { [self] in
            do {
                let newBank = try SoundBank(directory: directory, id: pack.id)
                engine.stop()
                for node in players { node.stop(); engine.detach(node) }
                players = []
                bank = newBank
                next = 0
                for _ in 0..<voiceCount {
                    let node = AVAudioPlayerNode()
                    engine.attach(node)
                    engine.connect(node, to: engine.mainMixerNode, format: newBank.format)
                    players.append(node)
                }
                engine.mainMixerNode.outputVolume = silent ? 0 : gain
                engine.prepare()
                try engine.start()
                players.forEach { $0.play() }
            } catch { reportError() }
        }
    }
    func configure(volume: Float, muted: Bool, keyUp: Bool) {
        queue.async { [self] in
            gain = min(1, max(0, volume)); silent = muted; releases = keyUp
            engine.mainMixerNode.outputVolume = silent ? 0 : gain
        }
    }
    func stop() {
        queue.async { [self] in players.forEach { $0.stop() } }
    }
    func play(_ key: String, down: Bool) {
        queue.async { [self] in
            guard !silent, down || releases,
                  let parts = bank?.sounds[key] ?? bank?.sounds["KeyA"], !parts.isEmpty else { return }
            let index = down ? 0 : 1
            guard index < parts.count, !players.isEmpty else { return }
            restart()
            let node = players[next % players.count]; next = (next + 1) % players.count
            node.scheduleBuffer(parts[index], at: nil, options: .interrupts)
        }
    }
}

// Physical key positions only. Never call keyboardGetUnicodeString or read the clipboard.
let keyNames: [Int64: String] = [
    0:"KeyA",1:"KeyS",2:"KeyD",3:"KeyF",4:"KeyH",5:"KeyG",6:"KeyZ",7:"KeyX",8:"KeyC",9:"KeyV",11:"KeyB",
    12:"KeyQ",13:"KeyW",14:"KeyE",15:"KeyR",16:"KeyY",17:"KeyT",18:"Digit1",19:"Digit2",20:"Digit3",21:"Digit4",
    22:"Digit6",23:"Digit5",24:"Equal",25:"Digit9",26:"Digit7",27:"Minus",28:"Digit8",29:"Digit0",30:"BracketRight",
    31:"KeyO",32:"KeyU",33:"BracketLeft",34:"KeyI",35:"KeyP",36:"Enter",37:"KeyL",38:"KeyJ",39:"Quote",40:"KeyK",
    41:"Semicolon",42:"Backslash",43:"Comma",44:"Slash",45:"KeyN",46:"KeyM",47:"Period",48:"Tab",49:"Space",
    50:"Backquote",51:"Backspace",53:"Escape",65:"NumpadDecimal",67:"NumpadMultiply",69:"NumpadAdd",75:"NumpadDivide",
    76:"NumpadEnter",78:"NumpadSubtract",82:"Numpad0",83:"Numpad1",84:"Numpad2",85:"Numpad3",86:"Numpad4",
    87:"Numpad5",88:"Numpad6",89:"Numpad7",91:"Numpad8",92:"Numpad9",96:"F5",97:"F6",98:"F7",99:"F3",
    100:"F8",101:"F9",103:"F11",109:"F10",111:"F12",115:"Home",116:"PageUp",117:"Delete",118:"F4",
    119:"End",120:"F2",121:"PageDown",122:"F1",123:"ArrowLeft",124:"ArrowRight",125:"ArrowDown",126:"ArrowUp"
]

final class KeyboardListener {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    var onKey: ((String, Bool, Bool) -> Void)?
    var onMouse: ((String, Bool) -> Void)?
    var onMute: (() -> Void)?
    var running: Bool { tap != nil }
    private var mouseEnabled = false
    func configureMouse(_ enabled: Bool) {
        guard mouseEnabled != enabled else { return }
        mouseEnabled = enabled
        stop()
        _ = start()
    }
    func start() -> Bool {
        if tap != nil { return true }
        guard CGPreflightListenEventAccess() else { return false }
        let mask = inputEventMask(mouseEnabled: mouseEnabled)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: CGEventMask(mask), callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let listener = Unmanaged<KeyboardListener>.fromOpaque(context).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = listener.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passUnretained(event)
                }
                if listener.mouseEnabled,
                   let sound = mouseSound(for: type, button: event.getIntegerValueField(.mouseEventButtonNumber)) {
                    listener.onMouse?(sound.key, sound.down)
                    return Unmanaged.passUnretained(event)
                }
                guard type == .keyDown || type == .keyUp else { return Unmanaged.passUnretained(event) }
                let repeated = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                let code = event.getIntegerValueField(.keyboardEventKeycode)
                if code == 46 && event.flags.contains([.maskControl, .maskAlternate]) {
                    if type == .keyDown && !repeated { listener.onMute?() }
                } else if let name = keyNames[code] { listener.onKey?(name, type == .keyDown, repeated) }
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return false }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }
    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil; tap = nil
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let audio = AudioPlayer()
    private let mouseAudio = AudioPlayer(voiceCount: 8)
    private let musicAudio = TypingMusicPlayer()
    private let listener = KeyboardListener()
    private let prefs = UserDefaults.standard
    private var window: NSWindow!
    private var statusItem: NSStatusItem!
    private var statusLabel = NSTextField(labelWithString: "")
    private var volumeLabel = NSTextField(labelWithString: "")
    private var musicButton = NSButton(checkboxWithTitle: "打字伴奏模式", target: nil, action: nil)
    private var musicMode = false
    private var previewGeneration = 0
    private var selector = NSPopUpButton(frame: .zero, pullsDown: false)
    private var slider = NSSlider(value: 30, minValue: 0, maxValue: 100, target: nil, action: nil)
    private var muteButton = NSButton(checkboxWithTitle: "静音", target: nil, action: nil)
    private var releaseButton = NSButton(checkboxWithTitle: "播放松键声音", target: nil, action: nil)
    private var mouseSelector = NSPopUpButton(frame: .zero, pullsDown: false)
    private var mouseSlider = NSSlider(value: 30, minValue: 0, maxValue: 100, target: nil, action: nil)
    private var mouseVolumeLabel = NSTextField(labelWithString: "")
    private var mouseVolume: Float = 0.3
    private var mouseButton = NSButton(checkboxWithTitle: "鼠标点击音效", target: nil, action: nil)
    private var loginButton = NSButton(checkboxWithTitle: "登录时自动启动", target: nil, action: nil)
    private var loginStatus = NSTextField(labelWithString: "")
    private var muteMenu: NSMenuItem!
    private var volume: Float = 0.3
    private var muted = false
    private var keyUp = true
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !packs.isEmpty else { NSApp.terminate(nil); return }
        // Avoid a second listener if the app is opened from another copy.
        let peers = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier!)
        if let other = peers.first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            other.activate(options: [.activateAllWindows]); NSApp.terminate(nil); return
        }
        prefs.register(defaults: ["volume": 0.3, "muted": false, "keyUp": true, "pack": "cherrymx-brown-abs", "mouseClicks": false, "musicMode": false])
        volume = min(1, max(0, prefs.float(forKey: "volume")))
        // Migrate once from the previously shared settings without changing the keyboard.
        if prefs.object(forKey: "mouseVolume") == nil { prefs.set(volume, forKey: "mouseVolume") }
        if prefs.object(forKey: "mousePack") == nil { prefs.set(prefs.string(forKey: "pack"), forKey: "mousePack") }
        mouseVolume = min(1, max(0, prefs.float(forKey: "mouseVolume")))
        muted = prefs.bool(forKey: "muted"); keyUp = prefs.bool(forKey: "keyUp")
        musicMode = prefs.bool(forKey: "musicMode") && musicPack != nil
        createMenu(); createWindow()
        audio.onError = { [weak self] message in self?.statusLabel.stringValue = message }
        mouseAudio.onError = { [weak self] message in self?.statusLabel.stringValue = message }
        listener.onMouse = { [weak self] key, down in self?.mouseAudio.play(key, down: down) }
        musicAudio.onError = { [weak self] message in self?.statusLabel.stringValue = message }
        if musicPack != nil { musicAudio.load(musicDirectory.appendingPathComponent("beethoven5.wav")) }
        let codesByName = Dictionary(uniqueKeysWithValues: keyNames.map { ($0.value, $0.key) })
        musicAudio.isKeyHeld = { name in
            guard let code = codesByName[name] else { return false }
            return CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(code))
        }
        listener.onKey = { [weak self] key, down, repeated in self?.playKeyboard(key, down: down, repeated: repeated) }
        listener.onMute = { [weak self] in self?.toggleMute() }
        let selected = packs.firstIndex(where: { $0.id == prefs.string(forKey: "pack") }) ?? 0
        selector.selectItem(at: selected)
        let mouseSelected = packs.firstIndex(where: { $0.id == prefs.string(forKey: "mousePack") }) ?? selected
        mouseSelector.selectItem(at: mouseSelected)
        mouseAudio.load(packs[mouseSelected])
        syncControls(); audio.load(packs[selected]); listener.configureMouse(prefs.bool(forKey: "mouseClicks")); updatePermission()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.updatePermission() }
        let launchEvent = NSAppleEventManager.shared().currentAppleEvent
        let loginLaunch = launchEvent?.eventID == kAEOpenApplication &&
            launchEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if !loginLaunch { showWindow() }
    }
    func applicationWillTerminate(_ notification: Notification) { musicAudio.pause(); listener.stop(); permissionTimer?.invalidate() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func windowShouldClose(_ sender: NSWindow) -> Bool { sender.orderOut(nil); return false }

    private func createMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "KeyTone 离线键音")
        let menu = NSMenu()
        let settings = NSMenuItem(title: "打开 KeyTone…", action: #selector(showWindow), keyEquivalent: "")
        settings.target = self; menu.addItem(settings)
        muteMenu = NSMenuItem(title: "静音", action: #selector(toggleMute), keyEquivalent: "")
        muteMenu.target = self; menu.addItem(muteMenu)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 KeyTone", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp; menu.addItem(quit)
        statusItem.menu = menu
        let mainMenu = NSMenu(); let appMenu = NSMenu(); let root = NSMenuItem(); root.submenu = appMenu
        appMenu.addItem(withTitle: "退出 KeyTone", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        mainMenu.addItem(root); NSApp.mainMenu = mainMenu
    }
    private func text(_ value: String, size: CGFloat = 13, secondary: Bool = false) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: value)
        label.font = .systemFont(ofSize: size)
        label.textColor = secondary ? .secondaryLabelColor : .labelColor
        return label
    }
    private func button(_ title: String, _ action: Selector) -> NSButton {
        NSButton(title: title, target: self, action: action)
    }
    private func createWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 740),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "KeyTone · 离线键音"; window.delegate = self; window.center()
        let content = window.contentView!
        let title = text("让每次敲击都有回响", size: 24); title.font = .systemFont(ofSize: 24, weight: .semibold)
        selector.addItems(withTitles: packs.map(\.name)); selector.target = self; selector.action = #selector(selectPack)
        selector.setAccessibilityLabel("键盘音色")
        musicButton.target = self; musicButton.action = #selector(changeMusicMode)
        musicButton.isEnabled = musicPack != nil
        let musicRow = NSStackView(views: [musicButton, button("从头开始", #selector(resetMusic))]); musicRow.spacing = 20
        slider.target = self; slider.action = #selector(changeVolume); slider.isContinuous = true
        slider.setAccessibilityLabel("键盘音量")
        mouseSelector.addItems(withTitles: packs.map(\.name))
        mouseSelector.target = self; mouseSelector.action = #selector(selectMousePack)
        mouseSelector.setAccessibilityLabel("鼠标音色")
        mouseSlider.target = self; mouseSlider.action = #selector(changeMouseVolume); mouseSlider.isContinuous = true
        mouseSlider.setAccessibilityLabel("鼠标音量")
        muteButton.target = self; muteButton.action = #selector(toggleMute)
        releaseButton.target = self; releaseButton.action = #selector(changeRelease)
        mouseButton.target = self; mouseButton.action = #selector(changeMouse)
        loginButton.target = self; loginButton.action = #selector(changeLogin)
        loginStatus.font = .systemFont(ofSize: 12); loginStatus.textColor = .secondaryLabelColor
        let loginRow = NSStackView(views: [loginButton, loginStatus]); loginRow.spacing = 12
        let volumeRow = NSStackView(views: [slider, volumeLabel]); volumeRow.spacing = 12
        slider.widthAnchor.constraint(equalToConstant: 320).isActive = true
        let mouseVolumeRow = NSStackView(views: [mouseSlider, mouseVolumeLabel]); mouseVolumeRow.spacing = 12
        mouseSlider.widthAnchor.constraint(equalToConstant: 320).isActive = true
        let mouseHeader = NSStackView(views: [mouseButton, button("试听鼠标", #selector(previewMouse))]); mouseHeader.spacing = 20
        let toggles = NSStackView(views: [releaseButton, muteButton]); toggles.spacing = 30
        let buttons = NSStackView(views: [button("试听键盘", #selector(preview)), button("开启输入监控…", #selector(requestPermission))])
        buttons.spacing = 12
        statusLabel.font = .systemFont(ofSize: 12); statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 2; statusLabel.lineBreakMode = .byWordWrapping
        let divider = NSBox(); divider.boxType = .separator
        let stack = NSStackView(views: [title, text("\(packs.count) 套本地音色 · 不联网 · 不记录输入", secondary: true),
            musicRow, text("贝多芬《第五交响曲》开篇 · 松开按键 2 秒后暂停，长按持续播放", size: 12, secondary: true),
            text("键盘音色"), selector, text("键盘音量"), volumeRow, toggles,
            mouseHeader, text("鼠标音色"), mouseSelector, text("鼠标音量"), mouseVolumeRow,
            text("左键、右键和中键使用鼠标音色，移动和滚轮无声。", size: 12, secondary: true),
            loginRow, buttons, statusLabel, divider,
            text("⌃⌥M 随时静音。关闭窗口后，可从菜单栏键盘图标打开。", size: 12, secondary: true),
            button("隐私与来源", #selector(showPrivacy))])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            selector.widthAnchor.constraint(equalTo: stack.widthAnchor),
            mouseSelector.widthAnchor.constraint(equalTo: stack.widthAnchor),
            divider.widthAnchor.constraint(equalTo: stack.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }
    @objc func showWindow() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    private func updatePermission() {
        syncLoginStatus()
        if CGPreflightListenEventAccess() {
            statusLabel.stringValue = listener.start() ? "已就绪：在任意应用中打字即可发声。" : "权限已开启，但监听未启动；请退出并重新打开 KeyTone。"
        } else {
            listener.stop(); statusLabel.stringValue = "尚未开启输入监控。可以先点击“试听键盘”。"
        }
    }
    private func syncControls() {
        slider.doubleValue = Double(volume * 100); volumeLabel.stringValue = "\(Int(volume * 100))%"
        mouseSlider.doubleValue = Double(mouseVolume * 100); mouseVolumeLabel.stringValue = "\(Int(mouseVolume * 100))%"
        musicButton.state = musicMode ? .on : .off; selector.isEnabled = !musicMode
        muteButton.state = muted ? .on : .off; releaseButton.state = keyUp ? .on : .off
        mouseButton.state = prefs.bool(forKey: "mouseClicks") ? .on : .off
        muteMenu.state = muted ? .on : .off
        audio.configure(volume: volume, muted: muted, keyUp: keyUp)
        mouseAudio.configure(volume: mouseVolume, muted: muted, keyUp: keyUp)
        musicAudio.configure(volume: volume, muted: muted)
    }
    private func playKeyboard(_ key: String, down: Bool, repeated: Bool = false) {
        if musicMode { musicAudio.keyPressed(key: key, down: down) }
        else if !repeated { audio.play(key, down: down) }
    }
    @objc private func changeMusicMode() {
        musicMode = musicButton.state == .on && musicPack != nil
        prefs.set(musicMode, forKey: "musicMode")
        previewGeneration += 1
        audio.stop(); musicAudio.pause(); syncControls()
    }
    @objc private func resetMusic() {
        previewGeneration += 1
        musicAudio.reset()
    }
    @objc private func selectPack() {
        let pack = packs[selector.indexOfSelectedItem]; prefs.set(pack.id, forKey: "pack"); audio.load(pack)
    }
    @objc private func selectMousePack() {
        let pack = packs[mouseSelector.indexOfSelectedItem]
        prefs.set(pack.id, forKey: "mousePack"); mouseAudio.load(pack)
    }
    @objc private func changeMouseVolume() {
        mouseVolume = Float(mouseSlider.doubleValue / 100)
        prefs.set(mouseVolume, forKey: "mouseVolume"); syncControls()
    }
    @objc private func previewMouse() {
        // Preview remains available when global mouse listening is disabled.
        for (index, key) in ["KeyA", "KeyS", "Space"].enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.35) { [weak self] in self?.mouseAudio.play(key, down: true) }
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.35 + 0.1) { [weak self] in self?.mouseAudio.play(key, down: false) }
        }
    }
    @objc private func changeVolume() { volume = Float(slider.doubleValue / 100); prefs.set(volume, forKey: "volume"); syncControls() }
    @objc private func toggleMute() { muted.toggle(); prefs.set(muted, forKey: "muted"); syncControls() }
    @objc private func changeRelease() { keyUp = releaseButton.state == .on; prefs.set(keyUp, forKey: "keyUp"); syncControls() }
    @objc private func changeMouse() {
        let enabled = mouseButton.state == .on
        prefs.set(enabled, forKey: "mouseClicks")
        listener.configureMouse(enabled)
        updatePermission()
    }
    private func syncLoginStatus() {
        switch SMAppService.mainApp.status {
        case .enabled: loginButton.state = .on; loginStatus.stringValue = "已开启"
        case .requiresApproval: loginButton.state = .mixed; loginStatus.stringValue = "待系统允许"
        case .notRegistered: loginButton.state = .off; loginStatus.stringValue = "未开启"
        case .notFound: loginButton.state = .off; loginStatus.stringValue = "未注册"
        @unknown default: loginButton.state = .off; loginStatus.stringValue = "状态未知"
        }
    }
    @objc private func changeLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled || (service.status == .requiresApproval && loginButton.state == .off) {
                try service.unregister()
            } else if service.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            } else {
                try service.register()
                if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            }
        } catch {
            let alert = NSAlert(); alert.messageText = "无法更改自动启动"
            alert.informativeText = "系统未完成设置：\(error.localizedDescription)\n可在系统设置的“登录项与扩展”中查看 KeyTone。"
            alert.addButton(withTitle: "知道了"); alert.runModal()
        }
        syncLoginStatus()
    }
    @objc private func preview() {
        previewGeneration += 1
        let generation = previewGeneration
        if musicMode { musicAudio.preview(); return }
        let notes = ["KeyA", "KeyS", "KeyD", "Space", "Enter"]
        let spacing = 0.16
        for (index, key) in notes.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * spacing) { [weak self] in
                guard let self, self.previewGeneration == generation else { return }
                self.playKeyboard(key, down: true)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * spacing + 0.08) { [weak self] in
                guard let self, self.previewGeneration == generation else { return }
                self.playKeyboard(key, down: false)
            }
        }
    }
    @objc private func requestPermission() {
        _ = CGRequestListenEventAccess()
        // A single hard-coded local settings URL; never open arbitrary links.
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }
    @objc private func showPrivacy() {
        let alert = NSAlert(); alert.messageText = "只做本地键鼠声音"
        alert.informativeText = "程序在启动时禁止网络连接，失败则退出。\n没有统计、更新、账号、下载、网页或按键日志。\n只在本机保存键盘/鼠标各自的音色、音量，以及静音、松键音、交响乐模式和鼠标音效偏好。自动启动由 macOS 登录项管理。\n\n输入监控用于读取物理按键编号，以及启用后的鼠标按下/松开状态，即时播放后丢弃。不读取鼠标位置、移动轨迹或点击内容。\n\n10 套机械键音：Mechvibes 3.5.7（MIT，Hải Nguyễn），已保留许可证。3 套趣味合成键音：本项目原创。猫猫喵：qubodup / Jofae 的真实猫叫录音（CC0，Freesound），已保留来源说明。交响乐录音：Skidmore College Orchestra 演奏贝多芬第五交响曲，经 Musopen / Wikimedia Commons 提供，来源页标注录音公有领域；本地保存连续开篇录音，保留来源与署名。原生界面与播放程序为本项目重写。"
        alert.addButton(withTitle: "知道了"); alert.runModal()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
