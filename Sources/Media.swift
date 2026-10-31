import AppKit
import SwiftUI

// README görselleri: ada, sahte bir masaüstünün tepesinde kare kare çizilir; ekran kaydı izni gerekmez.
//   Ada record <work|done|hover|displays|icon> <klasör>   → klasör/f00000.png ... (ya da tek bir PNG)

@MainActor enum Media {
    static let fps = 12.0
    static let size = CGSize(width: 600, height: 330)

    struct Frame {
        var model: Model
        var cursor: CGPoint? = nil
        var click = 0.0                               // 0...1, tıklama halkasının ilerleyişi
        var pulse = 0.0                               // 0...1, ekran nabzının parlaklığı
    }

    static func record(_ scenario: String, _ dir: String) {
        Ada.turkish = false
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        switch scenario {
        case "work": frames(9, work).enumerated().forEach { write(Scene(frame: $1), "\(dir)/f\(String(format: "%05d", $0)).png") }
        case "done": frames(7.5, done).enumerated().forEach { write(Scene(frame: $1), "\(dir)/f\(String(format: "%05d", $0)).png") }
        case "hover": frames(7.5, hover).enumerated().forEach { write(Scene(frame: $1), "\(dir)/f\(String(format: "%05d", $0)).png") }
        case "displays": write(displays(), "\(dir)/displays.png")
        default: fatalError("bilinmeyen sahne: \(scenario)")
        }
    }

    private static func frames(_ seconds: Double, _ make: (Double) -> Frame) -> [Frame] {
        (0..<Int(seconds * fps)).map { make(Double($0) / fps) }
    }

    private static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private static func model(at t: Double, _ sessions: [Model.Session]) -> Model {
        let m = Model()
        m.recording = true
        m.now = t0 + t
        for s in sessions { m.sessions[s.id] = s }
        return m
    }

    private static func session(_ id: String, _ title: String, _ label: String, started: Double, done: Double? = nil, updated: Double = 0) -> Model.Session {
        Model.Session(label: label, project: "", start: t0 + started, updated: t0 + (done ?? updated),
                      done: done.map { t0 + $0 }, id: id, title: title)
    }

    private static func pre(_ tool: String, _ input: [String: Any]) -> String {
        Hook.label("PreToolUse", ["tool_name": tool, "tool_input": input])
    }

    // MARK: Sahneler

    /// Bir tur boyunca ada: düşünür, okur, arar, düzenler, derler.
    private static func work(_ t: Double) -> Frame {
        let steps: [(Double, String)] = [
            (0, Hook.label("PostToolUse", [:])),
            (1.4, pre("Read", ["file_path": "/app/Sources/LoginView.swift"])),
            (2.8, pre("Grep", [:])),
            (3.8, pre("Edit", ["file_path": "/app/Sources/LoginView.swift"])),
            (5.6, pre("Bash", ["description": "Build the app"])),
            (7.6, Hook.label("PostToolUse", [:])),
        ]
        let label = steps.last { $0.0 <= t }!.1
        return Frame(model: model(at: t, [session("a", "Fix the login bug", label, started: -72, updated: t)]))
    }

    /// İki sohbet çalışırken ada yalnız sayısını yazar; biri bitince adını "Done" ile duyurur ve ekranlar üç kez
    /// yanıp söner (gerçekte bir de çan çalar).
    private static func done(_ t: Double) -> Frame {
        let end = 1.5
        let a = t < end
            ? session("a", "Fix the login bug", pre("Bash", ["description": "Run the tests"]), started: -151, updated: t)
            : session("a", "Fix the login bug", T("Bitti", "Done"), started: -151, done: end)
        let b = session("b", "Write the README", pre("Edit", ["file_path": "/app/README.md"]), started: -40, updated: t)
        let m = model(at: t, [a, b])
        if t >= end { m.announced = "a"; m.announcedAt = t0 + end }
        let dt = t - end
        let pulse = dt >= 0 && dt < 1.8 ? abs(sin(.pi * dt / 0.6)) : 0     // Houra'daki gibi: 0,3 sn aç, 0,3 sn kapa, üç kez
        return Frame(model: m, pulse: pulse)
    }

    /// İki sohbet çalışıyor, ada yalnız sayısını yazar; fare gelince sohbetler adlarıyla açılır, birine tıklanır.
    private static func hover(_ t: Double) -> Frame {
        let m = model(at: t, [
            session("a", "Write the README", pre("Edit", ["file_path": "/app/README.md"]), started: -95, updated: t),
            session("b", "Fix the login bug", pre("Bash", ["description": "Run the tests"]), started: -310, updated: t - 2),
            session("c", "Plan the week", T("Bitti", "Done"), started: -900, done: -240),
        ])
        let start = CGPoint(x: size.width * 0.72, y: size.height * 0.8)
        let island = CGPoint(x: size.width / 2 + 60, y: 16)
        let row = CGPoint(x: size.width / 2 - 40, y: 32 + 5 + 2 * 26 + 13)       // iki çalışan sohbetin altındaki biten sohbet
        let cursor: CGPoint
        switch t {
        case ..<0.6: cursor = start
        case ..<2.0: cursor = mix(start, island, ease((t - 0.6) / 1.4))
        case ..<3.4: cursor = island
        case ..<4.4: cursor = mix(island, row, ease((t - 3.4) / 1.0))
        default: cursor = row
        }
        m.expanded = t >= 2.0
        let click = t >= 4.9 && t < 5.4 ? (t - 4.9) / 0.5 : 0
        return Frame(model: m, cursor: cursor, click: click)
    }

    /// Harici monitör ve çentikli MacBook ekranı yan yana.
    private static func displays() -> some View {
        let s = session("a", "Fix the login bug", pre("Edit", ["file_path": "/app/Sources/LoginView.swift"]), started: -72)
        let m = model(at: 0, [s]), notched = model(at: 0, [s])
        notched.topInset = 32                           // çentikli ekranda yazı çentiğin altına iner
        return HStack(spacing: 24) {
            VStack(spacing: 10) {
                Scene(frame: Frame(model: m))
                Text("External display").foregroundColor(.white).font(.system(size: 15, weight: .semibold))
            }
            VStack(spacing: 10) {
                Scene(frame: Frame(model: notched), notch: true)
                Text("MacBook with a notch").foregroundColor(.white).font(.system(size: 15, weight: .semibold))
            }
        }
        .padding(24).background(Color(white: 0.12))
    }

    private static func ease(_ x: Double) -> Double { let x = min(1, max(0, x)); return x * x * (3 - 2 * x) }
    private static func mix(_ a: CGPoint, _ b: CGPoint, _ k: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k)
    }

    private static func write<V: View>(_ view: V, _ path: String) {
        let r = ImageRenderer(content: view); r.scale = 2
        try! NSBitmapImageRep(cgImage: r.cgImage!).representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: path))
    }

    // MARK: Sahte masaüstü

    struct Scene: View {
        let frame: Frame
        var notch = false

        var body: some View {
            let inset: CGFloat = notch ? 32 : 0
            let island = frame.model.islandSize(notch: notch ? 190 : 0, inset: inset)
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.12, green: 0.20, blue: 0.58), Color(red: 0.02, green: 0.04, blue: 0.22)],
                               startPoint: .top, endPoint: .bottom)
                window.padding(.top, 70)
                menuBar(height: notch ? 32 : 24)
                IslandView(model: frame.model).frame(width: island.width, height: island.height)
                Rectangle().fill(.white.opacity(0.22))
                    .overlay(Rectangle().strokeBorder(.white.opacity(0.9), lineWidth: 8))
                    .opacity(frame.pulse)
                if let c = frame.cursor { cursor.offset(x: c.x - Media.size.width / 2, y: c.y) }
                if let c = frame.cursor, frame.click > 0 {
                    Circle().stroke(.white.opacity(1 - frame.click), lineWidth: 2)
                        .frame(width: 10 + 30 * frame.click, height: 10 + 30 * frame.click)
                        .offset(x: c.x - Media.size.width / 2, y: c.y - 5 - 15 * frame.click)
                }
            }
            .frame(width: Media.size.width, height: Media.size.height)
            .clipped()
        }

        private var window: some View {
            RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.12))
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 7) {
                        Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 11, height: 11)
                        Circle().fill(Color(red: 1, green: 0.74, blue: 0.18)).frame(width: 11, height: 11)
                        Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25)).frame(width: 11, height: 11)
                    }.padding(12)
                }
                .overlay {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach([0.55, 0.8, 0.4, 0.7, 0.62], id: \.self) { w in
                            RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.08)).frame(width: 380 * w, height: 9)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 28).padding(.top, 20)
                }
                .frame(width: 440, height: 240)
        }

        private func menuBar(height: CGFloat) -> some View {
            HStack(spacing: 18) {
                Image(systemName: "apple.logo")
                Text("Claude").fontWeight(.bold)
                Text("File"); Text("Edit"); Text("View")
                Spacer()
                Text("Thu 14:32")
            }
            .font(.system(size: 12.5, weight: .medium)).foregroundColor(.white)
            .padding(.horizontal, 16)
            .frame(height: height).frame(maxWidth: .infinity)
            .background(.black.opacity(0.25))
        }

        /// macOS ok imleci: siyah, beyaz kenarlı.
        private var cursor: some View {
            let arrow = Path { p in
                p.move(to: .zero); p.addLine(to: CGPoint(x: 0, y: 17)); p.addLine(to: CGPoint(x: 4.2, y: 13))
                p.addLine(to: CGPoint(x: 7, y: 19.5)); p.addLine(to: CGPoint(x: 9.8, y: 18.3)); p.addLine(to: CGPoint(x: 7.1, y: 12))
                p.addLine(to: CGPoint(x: 12.5, y: 12)); p.closeSubpath()
            }
            return ZStack(alignment: .topLeading) {
                arrow.fill(.black)
                arrow.stroke(.white, style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
            }
            .frame(width: 14, height: 21, alignment: .topLeading)
            .scaleEffect(1.25, anchor: .topLeading)
            .offset(x: 7)                               // ZStack ortası yerine okun ucu noktaya gelsin
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        }
    }
}
