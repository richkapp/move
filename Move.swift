// Move: a minimalist menu bar stand-up timer.
import SwiftUI
import AppKit
import UserNotifications
import ServiceManagement

// MARK: - Sounds

enum AlarmSound: String, CaseIterable, Identifiable {
    case glass = "Glass", ping = "Ping", tink = "Tink", hero = "Hero", submarine = "Submarine"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .glass: return "Ding"
        case .ping: return "Beep"
        case .tink: return "Tink"
        case .hero: return "Chime"
        case .submarine: return "Sonar"
        }
    }
}

// MARK: - Timer model

@MainActor
final class MoveTimer: ObservableObject {
    private let d = UserDefaults.standard

    @Published var intervalMin: Int { didSet { d.set(intervalMin, forKey: "interval"); restart() } }
    @Published var warnMin: Int { didSet { d.set(warnMin, forKey: "warn"); warned = remaining <= Double(warnMin * 60) } }
    @Published var sound: AlarmSound { didSet { d.set(sound.rawValue, forKey: "sound"); play(sound, times: 1) } }
    @Published var repeats: Int { didSet { d.set(repeats, forKey: "repeats") } }
    @Published var volume: Double { didSet { d.set(volume, forKey: "volume") } }
    @Published var showCountdown: Bool { didSet { d.set(showCountdown, forKey: "showCountdown") } }
    @Published var warnSound: Bool { didSet { d.set(warnSound, forKey: "warnSound") } }
    @Published private(set) var notificationsAllowed = true
    @Published var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled {
        didSet {
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch { NSLog("Move: launch at login failed: \(error)") }
        }
    }

    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var paused = false

    private var target = Date()
    private var warned = false
    private var lastTick = Date()
    private var ticker: Timer?
    private var player: NSSound?

    init() {
        d.register(defaults: ["interval": 90, "warn": 10, "sound": AlarmSound.glass.rawValue,
                              "repeats": 2, "volume": 0.8, "showCountdown": true, "warnSound": true])
        intervalMin = d.integer(forKey: "interval")
        warnMin = d.integer(forKey: "warn")
        sound = AlarmSound(rawValue: d.string(forKey: "sound") ?? "") ?? .glass
        repeats = d.integer(forKey: "repeats")
        volume = d.double(forKey: "volume")
        showCountdown = d.bool(forKey: "showCountdown")
        warnSound = d.bool(forKey: "warnSound")

        restart()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t

        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            await refreshPermission()
        }
    }

    // MARK: Display

    var bigTime: String {
        let s = Int(remaining.rounded(.up))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    var shortTime: String {
        if paused { return "II" }
        return remaining >= 60 ? "\(Int((remaining / 60).rounded(.up)))m" : "\(Int(remaining.rounded(.up)))s"
    }

    // MARK: Actions

    func restart() {
        let len = Double(intervalMin * 60)
        target = Date().addingTimeInterval(len)
        remaining = len
        warned = warnMin == 0 || warnMin >= intervalMin
        lastTick = Date()
    }

    /// Set the time left until the next move, e.g. 19 min. Next cycles go back to the normal interval.
    func setRemaining(_ secs: TimeInterval) {
        let s = max(1, secs)
        remaining = s
        target = Date().addingTimeInterval(s)
        lastTick = Date()
        warned = warnMin == 0 || s <= Double(warnMin * 60)
    }

    /// Current remaining time as h:mm, used to prefill the editor.
    var editTime: String {
        let m = Int((remaining / 60).rounded(.up))
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    func togglePause() {
        if paused {
            target = Date().addingTimeInterval(remaining)
            lastTick = Date()
            paused = false
        } else {
            paused = true
        }
    }

    func moveNow() { fire() }

    /// Re-reads whether macOS lets Move show notifications, so the panel can flag it.
    func refreshPermission() async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        notificationsAllowed = s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
    }

    func openNotificationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=com.richkapp.move")!
        NSWorkspace.shared.open(url)
    }

    func previewSound() { play(sound, times: 1) }

    // MARK: Engine

    private func tick() {
        let now = Date()
        defer { lastTick = now }
        guard !paused else { return }

        // Big gap since last tick = Mac was asleep. You were away, so start fresh instead of ringing.
        if now.timeIntervalSince(lastTick) > 60 { restart(); return }

        remaining = max(0, target.timeIntervalSince(now))

        // Re-check notification permission every 30s so the panel warning stays accurate.
        if Int(now.timeIntervalSince1970) % 30 == 0 { Task { await refreshPermission() } }

        if !warned && remaining > 0 && remaining <= Double(warnMin * 60) {
            warned = true
            if warnSound { play(sound, times: 1, scale: 0.5) }
            notify("Move in \(warnMin) min", "Start wrapping up what you're doing.")
        }
        if remaining <= 0 { fire() }
    }

    private func fire() {
        play(sound, times: repeats)
        notify("Time to move", "Stand up, stretch, take a short walk.")
        restart()
    }

    private func play(_ s: AlarmSound, times: Int, scale: Double = 1) {
        guard times > 0 else { return }
        for i in 0..<times {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 1.2) { [weak self] in
                guard let self else { return }
                let snd = NSSound(named: NSSound.Name(s.rawValue))?.copy() as? NSSound
                snd?.volume = Float(self.volume * scale)
                snd?.play()
                self.player = snd
            }
        }
    }

    private func notify(_ title: String, _ body: String) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}

// MARK: - UI

/// Edit state for the countdown. A plain ObservableObject (not @State) so it builds with Command Line Tools only.
final class EditState: ObservableObject {
    @Published var editing = false
    @Published var draft = ""
    @Published var invalid = false
}

struct PanelView: View {
    @ObservedObject var t: MoveTimer
    @StateObject private var e = EditState()
    @FocusState private var focused: Bool

    private let timeFont = Font.system(size: 44, weight: .light, design: .rounded)

    /// Accepts "h:mm", "h:mm:ss", "19" (minutes), "1h", "19m", "1h19m".
    private func parse(_ raw: String) -> TimeInterval? {
        let s = raw.lowercased().replacingOccurrences(of: " ", with: "")
        if s.contains("h") || s.contains("m") {
            var h = 0.0, m = 0.0, num = ""
            for ch in s {
                if ch.isNumber || ch == "." { num.append(ch) }
                else if ch == "h", let v = Double(num) { h = v; num = "" }
                else if ch == "m", let v = Double(num) { m = v; num = "" }
                else { return nil }
            }
            if !num.isEmpty { guard let v = Double(num) else { return nil }; m = v }
            let total = h * 3600 + m * 60
            return total > 0 ? total : nil
        }
        let parts = s.split(separator: ":", omittingEmptySubsequences: false).map { Double($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        let v = parts.map { $0! }
        let total: Double
        switch v.count {
        case 1: total = v[0] * 60
        case 2: total = v[0] * 3600 + v[1] * 60
        case 3: total = v[0] * 3600 + v[1] * 60 + v[2]
        default: return nil
        }
        return total > 0 ? total : nil
    }

    private func apply() {
        if let secs = parse(e.draft) { t.setRemaining(secs); e.editing = false; e.invalid = false }
        else { e.invalid = true }
    }

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 2) {
                if e.editing {
                    TextField("h:mm", text: $e.draft)
                        .font(timeFont).monospacedDigit()
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.plain)
                        .focused($focused)
                        .onAppear { DispatchQueue.main.async { focused = true } }
                        .onSubmit { apply() }
                        .onExitCommand { e.editing = false; e.invalid = false }
                        .onChange(of: e.draft) { _, _ in e.invalid = false }
                    Text(e.invalid ? "try 0:19 or 19m" : "h:mm, Return to set, Esc to cancel")
                        .font(.caption).foregroundStyle(e.invalid ? .red : .secondary)
                } else {
                    Text(t.bigTime)
                        .font(timeFont).monospacedDigit()
                        .contentShape(Rectangle())
                        .onTapGesture { e.draft = t.editTime; e.editing = true }
                        .help("Click to change time left")
                    Text(t.paused ? "paused" : "until you move · click to edit")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)

            HStack(spacing: 8) {
                Button(t.paused ? "Resume" : "Pause") { t.togglePause() }
                Button("Reset") { t.restart() }
                Button("Move now") { t.moveNow() }
            }
            .controlSize(.small)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Stepper("Every \(t.intervalMin) min", value: $t.intervalMin, in: 5...240, step: 5)
                Stepper(t.warnMin == 0 ? "No warning" : "Warn \(t.warnMin) min before",
                        value: $t.warnMin, in: 0...30)

                HStack {
                    Picker("Sound", selection: $t.sound) {
                        ForEach(AlarmSound.allCases) { Text($0.label).tag($0) }
                    }
                    Button { t.previewSound() } label: { Image(systemName: "play.fill") }
                        .buttonStyle(.borderless)
                        .help("Preview")
                }

                HStack {
                    Text("Rings")
                    Picker("", selection: $t.repeats) {
                        Text("1×").tag(1); Text("2×").tag(2); Text("3×").tag(3)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                HStack {
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                    Slider(value: $t.volume, in: 0.1...1)
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                }

                Toggle("Countdown in menu bar", isOn: $t.showCountdown)
                Toggle("Soft sound on warning", isOn: $t.warnSound)
                Toggle("Launch at login", isOn: $t.launchAtLogin)
            }
            .font(.callout)

            if !t.notificationsAllowed {
                HStack(spacing: 6) {
                    Image(systemName: "bell.slash.fill").foregroundStyle(.orange)
                    Text("Notifications are off").font(.caption)
                    Spacer()
                    Button("Fix") { t.openNotificationSettings() }.controlSize(.small)
                }
            }

            Divider()

            Button("Quit Move") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 270)
        .task { await t.refreshPermission() }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }
    // Show banners even though Move is technically the "active" app.
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .list])
    }
}

@main
struct MoveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var timer = MoveTimer()

    var body: some Scene {
        MenuBarExtra {
            PanelView(t: timer)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "figure.walk")
                if timer.showCountdown { Text(timer.shortTime).monospacedDigit() }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
