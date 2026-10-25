// TalkType — hold a key, talk, release, cleaned text pastes at the cursor.
// Hold right option (or fn) = push to talk. Quick double-tap = hands-free until next tap.

import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement

enum Hotkey: String, CaseIterable {
    case rightOption, fn
    var label: String { self == .rightOption ? "Right Option" : "fn" }
    var keyCode: UInt16 { self == .rightOption ? 61 : 63 }
    var flag: NSEvent.ModifierFlags { self == .rightOption ? .option : .function }
}

enum State { case idle, recording, thinking }

final class HUD {
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    private let dot = NSView()

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 160, height: 34),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let bg = NSVisualEffectView(frame: panel.contentView!.bounds)
        bg.material = .hudWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 17
        bg.layer?.masksToBounds = true
        bg.autoresizingMask = [.width, .height]
        panel.contentView!.addSubview(bg)
        dot.frame = NSRect(x: 14, y: 12, width: 10, height: 10)
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 5
        bg.addSubview(dot)
        label.frame = NSRect(x: 32, y: 8, width: 120, height: 18)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        bg.addSubview(label)
    }

    func show(_ text: String, color: NSColor) {
        label.stringValue = text
        dot.layer?.backgroundColor = color.cgColor
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - 80, y: f.minY + 24))
        }
        panel.orderFrontRegardless()
    }

    func hide() { panel.orderOut(nil) }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    let hud = HUD()
    var recorder: AVAudioRecorder?
    var fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("talktype.m4a")
    var state: State = .idle { didSet { refreshIcon() } }
    var targetApp: NSRunningApplication?
    var keyDownAt: Date?
    var lastTapAt: Date?
    var handsFree = false
    var lastText = ""
    var statusLine = NSMenuItem(title: "ready", action: nil, keyEquivalent: "")

    var hotkey: Hotkey {
        get { Hotkey(rawValue: UserDefaults.standard.string(forKey: "hotkey") ?? "") ?? .rightOption }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "hotkey"); buildMenu() }
    }
    var rawMode: Bool {
        get { UserDefaults.standard.bool(forKey: "rawMode") }
        set { UserDefaults.standard.set(newValue, forKey: "rawMode"); buildMenu() }
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        refreshIcon()
        buildMenu()
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        if !UserDefaults.standard.bool(forKey: "loginItemSet") {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: "loginItemSet")
        }
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] e in self?.flags(e) }
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] e in self?.flags(e); return e }
    }

    // MARK: hotkey

    func flags(_ e: NSEvent) {
        guard e.keyCode == hotkey.keyCode else {
            // another key combined with the hotkey (e.g. option-click, option-arrow) cancels push-to-talk
            return
        }
        let down = e.modifierFlags.contains(hotkey.flag)
        if down {
            keyDownAt = Date()
            if handsFree { return }          // release handles stopping hands-free
            if state == .idle { start() }
        } else {
            let held = Date().timeIntervalSince(keyDownAt ?? Date())
            if handsFree {
                handsFree = false
                stop()
                return
            }
            guard state == .recording else { return }
            if held < 0.3 {
                // quick tap: second quick tap within 0.5s → hands-free; lone tap → cancel
                if let t = lastTapAt, Date().timeIntervalSince(t) < 0.5 {
                    handsFree = true
                    lastTapAt = nil
                    hud.show("hands-free", color: .systemRed)
                    return
                }
                lastTapAt = Date()
                cancel()
                return
            }
            stop()
        }
    }

    // MARK: record

    func start() {
        targetApp = NSWorkspace.shared.frontmostApplication
        try? FileManager.default.removeItem(at: fileURL)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        do {
            recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder?.record()
            state = .recording
            hud.show("listening", color: .systemRed)
        } catch {
            fail("mic error: \(error.localizedDescription)")
        }
    }

    func cancel() {
        recorder?.stop()
        recorder = nil
        state = .idle
        hud.hide()
    }

    func stop() {
        guard let r = recorder else { return }
        let dur = r.currentTime
        r.stop()
        recorder = nil
        if dur < 0.4 { state = .idle; hud.hide(); return }
        state = .thinking
        hud.show("thinking", color: .systemYellow)
        upload()
    }

    // MARK: network

    func upload() {
        guard let audio = try? Data(contentsOf: fileURL) else { return fail("no audio") }
        let app = targetApp?.localizedName ?? ""
        var comps = URLComponents(string: Config.endpoint)!
        comps.queryItems = [URLQueryItem(name: "app", value: app),
                            URLQueryItem(name: "mode", value: rawMode ? "raw" : "clean")]
        var req = URLRequest(url: comps.url!, timeoutInterval: 45)
        req.httpMethod = "POST"
        req.setValue("Bearer \(Config.token)", forHTTPHeaderField: "Authorization")
        req.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")
        req.httpBody = audio
        URLSession.shared.dataTask(with: req) { [weak self] data, resp, err in
            DispatchQueue.main.async {
                guard let self else { return }
                if let err { return self.fail(err.localizedDescription) }
                guard let data,
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return self.fail("bad response")
                }
                if let e = obj["error"] as? String { return self.fail(e) }
                let text = (obj["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                self.state = .idle
                self.hud.hide()
                guard !text.isEmpty else { return }
                self.lastText = text
                self.statusLine.title = "last: " + String(text.prefix(40))
                self.paste(text)
            }
        }.resume()
    }

    func fail(_ msg: String) {
        state = .idle
        statusLine.title = "error: \(msg)"
        hud.show("failed", color: .systemGray)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.hud.hide() }
    }

    // MARK: paste

    func paste(_ text: String) {
        let pb = NSPasteboard.general
        let saved = pb.pasteboardItems?.compactMap { item -> NSPasteboardItem? in
            let copy = NSPasteboardItem()
            for t in item.types { if let d = item.data(forType: t) { copy.setData(d, forType: t) } }
            return copy
        } ?? []
        pb.clearContents()
        pb.setString(text, forType: .string)

        guard AXIsProcessTrusted() else {
            // no accessibility permission: leave it on the clipboard
            statusLine.title = "copied (grant Accessibility to auto-paste)"
            return
        }
        targetApp?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let src = CGEventSource(stateID: .combinedSessionState)
            let v: CGKeyCode = 9
            let down = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true)
            let up = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false)
            down?.flags = .maskCommand
            up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                pb.clearContents()
                if !saved.isEmpty { pb.writeObjects(saved) }
            }
        }
    }

    // MARK: menu

    func refreshIcon() {
        let name: String
        switch state {
        case .idle: name = "mic"
        case .recording: name = "mic.fill"
        case .thinking: name = "ellipsis.circle"
        }
        statusItem?.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "TalkType")
    }

    func buildMenu() {
        let m = NSMenu()
        m.addItem(statusLine)
        m.addItem(.separator())
        m.addItem(withTitle: "Copy last transcript", action: #selector(copyLast), keyEquivalent: "").target = self
        m.addItem(.separator())
        let hk = NSMenuItem(title: "Hotkey", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for h in Hotkey.allCases {
            let i = NSMenuItem(title: "Hold \(h.label)", action: #selector(pickHotkey(_:)), keyEquivalent: "")
            i.representedObject = h.rawValue
            i.state = h == hotkey ? .on : .off
            i.target = self
            sub.addItem(i)
        }
        hk.submenu = sub
        m.addItem(hk)
        let raw = NSMenuItem(title: "Raw transcript (skip cleanup)", action: #selector(toggleRaw), keyEquivalent: "")
        raw.state = rawMode ? .on : .off
        raw.target = self
        m.addItem(raw)
        let login = NSMenuItem(title: "Open at login", action: #selector(toggleLogin), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        login.target = self
        m.addItem(login)
        m.addItem(withTitle: "Accessibility settings…", action: #selector(openAX), keyEquivalent: "").target = self
        m.addItem(.separator())
        m.addItem(withTitle: "hold key = talk · double-tap = hands-free", action: nil, keyEquivalent: "")
        m.addItem(withTitle: "Quit TalkType", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = m
    }

    @objc func copyLast() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastText, forType: .string)
    }
    @objc func pickHotkey(_ s: NSMenuItem) { hotkey = Hotkey(rawValue: s.representedObject as! String)! }
    @objc func toggleRaw() { rawMode.toggle() }
    @objc func toggleLogin() {
        if SMAppService.mainApp.status == .enabled { try? SMAppService.mainApp.unregister() }
        else { try? SMAppService.mainApp.register() }
        buildMenu()
    }
    @objc func openAX() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
