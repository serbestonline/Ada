import AppKit
import SwiftUI

// Ada: Claude Code çalışırken ekranın tepesinde, çentiğin altında duran küçük siyah ada.
// Aynı ikili iki iş görür: "Ada hook" Claude Code kancasından gelen olayı yayınlar,
// argümansız açılınca da olayları dinleyip adayı çizer.

enum Ada {
    static let bundleID = "com.serbest.ada"
    static let event = Notification.Name("com.serbest.ada.event")
    static let flashAfter: TimeInterval = 20     // bundan kısa turlarda ekran yanmaz, yalnız çan çalar
    static let claude = "com.anthropic.claudefordesktop"
    static let announceFor: TimeInterval = 8      // biten oturum adanın en üstünde bu kadar duyurulur
    static let listedFor: TimeInterval = 12 * 3600    // açılan listede bundan eski oturumlar görünmez
    /// Etiket dili: ADA_LANG ya da sistem dili; Türkçe dışında İngilizce.
    static var turkish = (ProcessInfo.processInfo.environment["ADA_LANG"] ?? Locale.preferredLanguages.first ?? "en").hasPrefix("tr")
    static let staleAfter: TimeInterval = 600    // shortcut: Esc ile kesilen turda Stop gelmez, ada 10 dk sonra son "Bitti"ye döner
}

func T(_ tr: String, _ en: String) -> String { Ada.turkish ? tr : en }

switch CommandLine.arguments.dropFirst().first {
case "hook": Hook.run(); exit(0)
case "selftest": Hook.selftest(); exit(0)
case "title": print(Desktop.info(CommandLine.arguments[2]) as Any); exit(0)
case "record": MainActor.assumeIsolated { Media.record(CommandLine.arguments[2], CommandLine.arguments[3]) }; exit(0)
case "snapshot": MainActor.assumeIsolated { Snapshot.write(CommandLine.arguments[2]) }; exit(0)
default: break
}

// MARK: - Kanca modu

enum Hook {
    static func run() {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let event = j["hook_event_name"] as? String,
              let session = j["session_id"] as? String else { return }
        if NSRunningApplication.runningApplications(withBundleIdentifier: Ada.bundleID).isEmpty {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = ["-g", Bundle.main.bundlePath]
            try? p.run(); p.waitUntilExit()
            usleep(800_000)                          // ada dinlemeye başlamadan yayınlanan olay kaybolmasın
        }
        let project = URL(fileURLWithPath: j["cwd"] as? String ?? "").lastPathComponent
        DistributedNotificationCenter.default().postNotificationName(
            Ada.event, object: nil,
            userInfo: ["event": event, "session": session, "label": label(event, j), "project": project],
            deliverImmediately: true)
    }

    static func label(_ event: String, _ j: [String: Any]) -> String {
        switch event {
        case "PreToolUse": break
        case "Notification": return T("Onayını bekliyor", "Waiting for your approval")
        default: return T("Düşünüyor", "Thinking")
        }
        let input = j["tool_input"] as? [String: Any] ?? [:]
        let file = (input["file_path"] ?? input["notebook_path"]) as? String
        let name = file.map { URL(fileURLWithPath: $0).lastPathComponent }
        let desc = input["description"] as? String
        switch j["tool_name"] as? String ?? "" {
        case "Edit", "MultiEdit", "Write", "NotebookEdit": return join(T("Düzenliyor", "Editing"), name)
        case "Read": return join(T("Okuyor", "Reading"), name)
        case "Bash": return join(T("Çalıştırıyor", "Running"), desc)
        case "Grep", "Glob": return T("Arıyor", "Searching")
        case "WebFetch", "WebSearch": return T("Web'de arıyor", "Browsing the web")
        case "Agent", "Task": return join(T("Ajan çalışıyor", "Running an agent"), desc)
        case "AskUserQuestion": return T("Sana soruyor", "Asking you")
        case "Skill": return join("Skill", input["skill"] as? String)
        default: return T("Çalışıyor", "Working")
        }
    }

    static func join(_ verb: String, _ detail: String?) -> String {
        guard let d = detail, !d.isEmpty else { return verb }
        return "\(verb) · \(d)"
    }

    static func selftest() {
        Ada.turkish = true
        func pre(_ tool: String, _ input: [String: Any]) -> String { label("PreToolUse", ["tool_name": tool, "tool_input": input]) }
        precondition(pre("Edit", ["file_path": "/a/b/main.swift"]) == "Düzenliyor · main.swift")
        precondition(pre("Bash", ["command": "ls", "description": "List files"]) == "Çalıştırıyor · List files")
        precondition(pre("Bash", ["command": "ls"]) == "Çalıştırıyor")
        precondition(pre("mcp__x__y", [:]) == "Çalışıyor")
        precondition(label("PostToolUse", [:]) == "Düşünüyor")
        precondition(label("Notification", [:]) == "Onayını bekliyor")
        print("selftest ok")
    }
}

// MARK: - Durum

final class Model: ObservableObject {
    struct Session {
        var label: String; var project: String; var start: Date; var updated: Date; var done: Date?
        var id = "", title: String? = nil, localID: String? = nil
        /// Masaüstündeki sohbetin adı; terminal oturumunda klasörün adı.
        var name: String { title ?? (project.isEmpty ? "Claude" : project) }
    }

    @Published var sessions: [String: Session] = [:]
    @Published var now = Date()
    @Published var topInset: CGFloat = 0
    @Published var expanded = false
    var recording = false                            // README kaydı: yıldız gerçek saatle değil, kaydın saatiyle döner

    var announced: String?                           // az önce biten oturum
    var announcedAt = Date.distantPast

    /// Adada hep görünen satırlar: az önce biten oturum, sonra çalışan bütün oturumlar turlarının başladığı sırayla;
    /// hiçbiri yoksa en son biten, Claude yeniden başlayana kadar "Bitti" olarak kalır.
    var shown: [Session] {
        var rows = sessions.values.filter { $0.done == nil && now.timeIntervalSince($0.updated) < Ada.staleAfter }
            .sorted { $0.start < $1.start }
        if let id = announced, now.timeIntervalSince(announcedAt) < Ada.announceFor, let s = sessions[id], s.done != nil {
            rows.insert(s, at: 0)
        }
        if rows.isEmpty, let last = sessions.values.filter({ $0.done != nil }).max(by: { $0.done! < $1.done! }) { rows = [last] }
        return Array(rows.prefix(6))
    }

    /// Üzerine gelince eklenen satırlar: son 12 saatte biten öteki oturumlar, en yeni üstte.
    var extra: [Session] {
        let ids = Set(shown.map(\.id))
        let done = sessions.values.filter { $0.done != nil && !ids.contains($0.id) && now.timeIntervalSince($0.updated) < Ada.listedFor }
        return Array(done.sorted { $0.done! > $1.done! }.prefix(5))
    }

    func handle(_ info: [AnyHashable: Any]) {
        guard let event = info["event"] as? String, let id = info["session"] as? String else { return }
        let label = info["label"] as? String ?? "", project = info["project"] as? String ?? ""
        let t = Date()
        switch event {
        case "Stop":
            guard var s = sessions[id], s.done == nil else { return }
            s.done = t; s.updated = t; s.label = T("Bitti", "Done")
            sessions[id] = s
            announced = id; announcedAt = t
            fill(id)                                 // sohbetin adı ilk turdan sonra konur
            Chime.play()
            if t.timeIntervalSince(s.start) >= Ada.flashAfter { ScreenPulse.flash() }
        case "SessionEnd":
            sessions[id] = nil
        default:
            if event == "UserPromptSubmit" || sessions[id]?.done != nil || sessions[id] == nil {
                let old = sessions[id]
                sessions[id] = Session(label: label, project: project, start: t, updated: t, done: nil,
                                       id: id, title: old?.title, localID: old?.localID)
            } else {
                sessions[id]!.label = label; sessions[id]!.updated = t
            }
            if sessions[id]?.title == nil { fill(id) }
        }
        now = t
    }

    func islandSize(notch: CGFloat, inset: CGFloat) -> CGSize {
        let rows = CGFloat(shown.count), more = expanded ? CGFloat(extra.count) : 0
        let h = inset + 32 + (rows > 1 ? (rows - 1) * 28 + 4 : 0) + (more > 0 ? 5 + more * 26 + 6 : 0)
        return CGSize(width: max(rows > 1 || more > 0 ? 400 : 340, notch + 60), height: h)
    }

    func fill(_ id: String) {
        guard let i = Desktop.info(id) else { return }
        sessions[id]?.title = i.title; sessions[id]?.localID = i.localID
    }
}

/// Claude masaüstü uygulamasının oturum kayıtları: sohbetin adı ve onu açan bağlantı.
enum Desktop {
    static let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
    private static var paths: [String: URL] = [:]
    private static var missedAt: [String: Date] = [:] // kaydı bulunamayan oturum en çok 30 sn'de bir yeniden aranır

    static func info(_ cli: String) -> (title: String?, localID: String)? {
        // Yeni açılan sohbetin kaydına oturum kimliği biraz sonra yazılır; terminal oturumlarının hiç kaydı yoktur.
        if paths[cli] == nil && Date().timeIntervalSince(missedAt[cli] ?? .distantPast) > 30 {
            // shortcut: yeni oturumda bütün kayıtlar bir kez taranır (~30 MB); klasör çok büyürse dosya tarihine göre daraltılmalı
            let key = Data("\"cliSessionId\":\"\(cli)\"".utf8)
            let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }.filter { $0.pathExtension == "json" } ?? []
            paths[cli] = files.first { (try? Data(contentsOf: $0, options: .alwaysMapped))?.range(of: key) != nil }
            if paths[cli] == nil { missedAt[cli] = Date() }
        }
        guard let url = paths[cli], let d = try? Data(contentsOf: url),
              let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let local = j["sessionId"] as? String else { return nil }
        return (j["title"] as? String, local)
    }

    /// Masaüstü sohbetini açar; terminal oturumunda yalnız Claude'u öne getirir.
    static func open(_ s: Model.Session?) {
        if let id = s?.localID, let url = URL(string: "claude://code/continue?session=\(id)") {
            NSWorkspace.shared.open(url)
        } else if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Ada.claude) {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

// MARK: - Görünüm

struct IslandView: View {
    @ObservedObject var model: Model
    private let spinner = ["·", "✢", "✳", "✶", "✻", "✽", "✻", "✶", "✳", "✢"]
    private let orange = Color(red: 0.85, green: 0.47, blue: 0.34)

    var body: some View {
        let shown = model.shown, extra = model.expanded ? model.extra : []
        VStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.offset) { i, s in
                line(s, highlight: s.id == model.announced && s.done != nil && shown.count > 1)
                    .frame(height: i == 0 ? 32 : 28).contentShape(Rectangle()).onTapGesture { Desktop.open(s) }
            }
            if !extra.isEmpty {
                Rectangle().fill(.white.opacity(0.12)).frame(height: 1).padding(.top, shown.count > 1 ? 4 : 0).padding(.bottom, 4)
                ForEach(Array(extra.enumerated()), id: \.offset) { _, s in
                    line(s).frame(height: 26).contentShape(Rectangle()).onTapGesture { Desktop.open(s) }
                }
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 13, weight: .semibold))
        .padding(.horizontal, 18)
        .padding(.top, model.topInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16).fill(.black))
    }

    /// Bir oturumun satırı: yıldız ya da onay, sohbetin adı, gri olarak o anki iş, süre. Duyuruda "Bitti" yeşil yazılır.
    private func line(_ s: Model.Session, highlight: Bool = false) -> some View {
        HStack(spacing: 10) {
            if s.done != nil {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            } else {
                TimelineView(.periodic(from: .now, by: 0.12)) { ctx in
                    let t = (model.recording ? model.now : ctx.date).timeIntervalSinceReferenceDate
                    Text(spinner[Int(t / 0.12) % spinner.count]).foregroundColor(orange).frame(width: 16)
                }
            }
            Text(s.name).foregroundColor(.white).lineLimit(1).truncationMode(.tail).layoutPriority(1)
            Text(s.label).foregroundColor(highlight ? .green : .white.opacity(0.55)).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 8)
            Text(elapsed(s)).foregroundColor(.white.opacity(0.55)).monospacedDigit().lineLimit(1).fixedSize().layoutPriority(2)
        }
    }

    private func elapsed(_ s: Model.Session) -> String {
        let sec = Int((s.done ?? model.now).timeIntervalSince(s.start))
        return String(format: "%d:%02d", sec / 60, sec % 60)
    }
}

// MARK: - Pencere

/// Ada hiç öne gelmediği için ilk tıklama da satıra ulaşsın.
final class FirstClickHost<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class Island {
    let model = Model()
    let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)

    init() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = FirstClickHost(rootView: IslandView(model: model))
        DistributedNotificationCenter.default().addObserver(forName: Ada.event, object: nil, queue: .main) { [weak self] n in
            self?.model.handle(n.userInfo ?? [:]); self?.refresh()
        }
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.model.now = Date(); self?.refresh()
        }
        // Fare adanın üstündeyse liste açılır; ayrılınca kapanır.
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let over = self.panel.isVisible && NSMouseInRect(NSEvent.mouseLocation, self.panel.frame, false)
            guard over != self.model.expanded else { return }
            if over { (self.model.shown + self.model.extra).forEach { self.model.fill($0.id) } }
            self.model.expanded = over; self.refresh()
        }
    }

    /// Fare hangi ekrandaysa ada onun tepesine geçer; çentikli ekranda çentiğin altına uzar.
    func refresh() {
        guard !model.shown.isEmpty else { panel.orderOut(nil); return }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else { return }
        let inset = screen.safeAreaInsets.top
        var notch: CGFloat = 0
        if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea { notch = screen.frame.width - l.width - r.width }
        let size = model.islandSize(notch: notch, inset: inset)
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                           width: size.width, height: size.height)
        if model.topInset != inset { model.topInset = inset }
        if panel.frame != frame { panel.setFrame(frame, display: true, animate: panel.isVisible) }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }
}

// MARK: - Bitiş: Houra'nın ekran nabzı ve çanı

/// Bütün ekranlar üç kez beyaz yanıp söner; tıklamaları engellemez.
enum ScreenPulse {
    static func flash() {
        for screen in NSScreen.screens {
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.ignoresMouseEvents = true
            w.level = .screenSaver
            w.isReleasedWhenClosed = false
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            let v = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            v.wantsLayer = true
            v.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.22).cgColor
            v.layer?.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
            v.layer?.borderWidth = 8
            v.layer?.opacity = 0
            w.contentView = v
            w.orderFrontRegardless()
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 0; a.toValue = 1; a.duration = 0.3; a.autoreverses = true; a.repeatCount = 3
            v.layer?.add(a, forKey: "pulse")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { w.orderOut(nil) }
        }
    }
}

/// Dosyasız ses: açılışta sentezlenen kısa WAV. Houra'dan ayırt edilsin diye notalar farklı (Sol ve Do).
enum Chime {
    private static let rate = 44_100.0
    private static let length = 2.5
    private static let attack = 0.02
    private static let decay = 0.5
    private static let tones: [(freq: Double, amp: Double, delay: Double)] = [(784, 0.14, 0), (1047, 0.11, 0.18)]
    private static var sound: NSSound?

    static func play() {
        sound = NSSound(data: wav())
        sound?.volume = 0.5
        sound?.play()
    }

    static func wav() -> Data {
        let n = Int(length * rate)
        var pcm = Data(capacity: n * 2)
        for i in 0..<n {
            let t = Double(i) / rate
            var v = 0.0
            for tone in tones where t >= tone.delay {
                let u = t - tone.delay
                v += tone.amp * min(1, u / attack) * exp(-u / decay) * sin(2 * .pi * tone.freq * u)
            }
            v *= min(1, (length - t) / 0.3)
            var s = Int16(max(-1, min(1, v)) * 32_767).littleEndian
            withUnsafeBytes(of: &s) { pcm.append(contentsOf: $0) }
        }
        var d = Data()
        func put<T: FixedWidthInteger>(_ x: T) { var le = x.littleEndian; withUnsafeBytes(of: &le) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); put(UInt32(36 + pcm.count)); d.append(contentsOf: Array("WAVEfmt ".utf8))
        put(UInt32(16)); put(UInt16(1)); put(UInt16(1)); put(UInt32(rate)); put(UInt32(rate * 2)); put(UInt16(2)); put(UInt16(16))
        d.append(contentsOf: Array("data".utf8)); put(UInt32(pcm.count))
        return d + pcm
    }
}

/// Önizleme: çalışan, biten ve çentikli ekrandaki hali tek PNG'de.
@MainActor enum Snapshot {
    static func write(_ path: String) {
        let t = Date()
        func model(_ label: String, done: Bool, inset: CGFloat) -> Model {
            let m = Model()
            m.sessions = ["a": .init(label: label, project: "Ada", start: t - 83, updated: t, done: done ? t : nil, id: "a")]
            m.now = t; m.topInset = inset
            return m
        }
        let view = VStack(spacing: 24) {
            IslandView(model: model("Düzenliyor · main.swift", done: false, inset: 0)).frame(width: 340, height: 32)
            IslandView(model: model("Bitti", done: true, inset: 0)).frame(width: 340, height: 32)
            IslandView(model: model("Çalıştırıyor · Build the app", done: false, inset: 32)).frame(width: 340, height: 64)
            IslandView(model: {
                let m = model("Düzenliyor · main.swift", done: false, inset: 0)
                m.sessions["a"]!.title = "Houra break screen ve session editing"
                m.sessions["b"] = .init(label: "Bitti", project: "Sebo Mind Base", start: t - 400, updated: t - 60, done: t - 60,
                                        id: "b", title: "Behavioral Lab tetik senkronizasyonu")
                m.expanded = true
                return m
            }()).frame(width: 400, height: 32 + 5 + 26 + 6)
        }.padding(24).background(Color(red: 0.02, green: 0.05, blue: 0.3))
        let r = ImageRenderer(content: view); r.scale = 2
        let rep = NSBitmapImageRep(cgImage: r.cgImage!)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    }
}

// MARK: - Açılış

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let island = Island()
app.run()
