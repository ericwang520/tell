//
//  ContentView.swift
//  Tell — Activity Dashboard (menu bar)
//

import SwiftUI
import AppKit
import Combine

// MARK: - Theme (mirrors tokens-d.css)

enum T {
    static let bg          = Color(hex: 0x1F1C19)
    static let bgElev      = Color(hex: 0x2A2620)
    static let bgElev2     = Color(hex: 0x322D26)
    static let bgHover     = Color(hex: 0x36302A)
    static let bgHero      = Color(hex: 0x2D2620)
    static let bgDeep      = Color(hex: 0x181613)

    static let border      = Color(hex: 0x3B3429)
    static let borderSoft  = Color(hex: 0x2E281F)
    static let borderStrong = Color(hex: 0x4A4234)

    static let fgPri       = Color(hex: 0xFAF3E6)
    static let fgSec       = Color(hex: 0xC7B59C)
    static let fgTer       = Color(hex: 0x8A7866)
    static let fgQuat      = Color(hex: 0x5D4F3E)

    static let accent      = Color(hex: 0x4ADE80)
    static let warn        = Color(hex: 0xFBBF24)
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >>  8) & 0xFF) / 255
        let b = Double( hex        & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

// MARK: - App catalog (real macOS icons)

final class AppCatalog {
    static let shared = AppCatalog()
    private var nameToURL: [String: URL] = [:]

    init() { rescan() }

    func rescan() {
        let fm = FileManager.default
        let roots: [String] = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            (NSHomeDirectory() as NSString).appendingPathComponent("Applications"),
        ]
        var map: [String: URL] = [:]
        for root in roots {
            guard let urls = try? fm.contentsOfDirectory(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for url in urls where url.pathExtension == "app" {
                let name = url.deletingPathExtension().lastPathComponent
                map[name] = url
            }
        }
        nameToURL = map
    }

    func url(for appName: String) -> URL? {
        if let u = nameToURL[appName] { return u }
        for running in NSWorkspace.shared.runningApplications {
            if let name = running.localizedName, name == appName, let u = running.bundleURL {
                return u
            }
        }
        return nil
    }

    func icon(for appName: String) -> NSImage? {
        if let u = url(for: appName) {
            return NSWorkspace.shared.icon(forFile: u.path)
        }
        return nil
    }

    /// Every installed app (deduped by name).
    func allApps() -> [(name: String, url: URL)] {
        nameToURL.map { (name: $0.key, url: $0.value) }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
}

// MARK: - Activity data

struct Session: Identifiable {
    let id = UUID()
    let app: String
    let title: String
    let start: Date
    let end: Date
    var seconds: Int { max(0, Int(end.timeIntervalSince(start))) }
}

struct AppActivity: Identifiable {
    let id = UUID()
    let name: String
    let totalSeconds: Int
    let sessions: [Session]
    let spark: [SparkLevel]
    let drift: Bool
    let summary: String
    let lastSeen: Date
}

enum SparkLevel { case off, on, peak }

enum RangeKey: String, CaseIterable {
    case pastHour, today, yesterday
    var label: String {
        switch self {
        case .pastHour:  return "Past hour"
        case .today:     return "Today"
        case .yesterday: return "Yesterday"
        }
    }
    /// CLI value passed to `tell-rich --window <value>`.
    var richArg: String {
        switch self {
        case .pastHour:  return "1h"     // tell-rich parses "1h" as last hour
        case .today:     return "today"
        case .yesterday: return "yesterday"
        }
    }
}

// MARK: - Daemon controller (auto-starts tell-daemon, stops on app quit)

@MainActor
final class DaemonController: ObservableObject {
    @Published var running: Bool = false
    @Published var pid: Int32 = 0
    @Published var lastLog: String = ""
    /// Rolling log buffer, capped at logCap lines. Tail of daemon stderr/stdout.
    @Published var logs: [String] = []
    let logCap = 500

    private var process: Process?
    private var logTask: Task<Void, Never>?

    fileprivate func appendLog(_ line: String) {
        logs.append(line)
        if logs.count > logCap {
            logs.removeFirst(logs.count - logCap)
        }
        lastLog = line
    }

    /// Project root + daemon script come from settings.
    var projectRoot: URL { TellSettings.shared.resolvedProjectRoot }
    var daemonScript: URL { projectRoot.appendingPathComponent("daemon/tell-daemon.py") }
    var pythonBin: String { "/usr/bin/python3" }

    /// Start daemon if not already running (also reaps any orphan from a previous run).
    func startIfNeeded() {
        reapOrphans()
        if running { return }
        let settings = TellSettings.shared
        settings.ensureDataDirs()

        guard FileManager.default.fileExists(atPath: daemonScript.path) else {
            lastLog = "❌ daemon script not found: \(daemonScript.path)"
            return
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: pythonBin)
        p.arguments = [
            daemonScript.path,
            "--interval", String(settings.daemonPollSeconds),
            "--ocr",
            "--rescan", "30",
            "--idle", String(settings.daemonIdleSeconds),
            "--gbrain-sync-every", String(settings.gbrainSyncEvery),
        ]
        p.currentDirectoryURL = projectRoot
        p.environment = settings.subprocessEnv

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe

        do {
            try p.run()
            process = p
            pid = p.processIdentifier
            running = true
            lastLog = "▶ started pid=\(pid)"

            logTask = Task.detached(priority: .background) { [weak self] in
                let handle = pipe.fileHandleForReading
                while let line = try? handle.readLine(strippingNewline: true), !Task.isCancelled {
                    await MainActor.run { [weak self] in
                        self?.appendLog(line)
                    }
                }
                await MainActor.run { [weak self] in
                    self?.running = false
                    self?.pid = 0
                    self?.appendLog("◼ daemon exited")
                }
            }
        } catch {
            lastLog = "❌ failed to start: \(error.localizedDescription)"
        }
    }

    /// Restart with current settings (useful after Settings change).
    func restart() {
        stop()
        startIfNeeded()
    }

    /// Stop the daemon if we started it.
    func stop() {
        logTask?.cancel(); logTask = nil
        if let p = process, p.isRunning {
            p.terminate()
            _ = p.waitForExit(timeoutSeconds: 5)
        }
        process = nil
        running = false
        pid = 0
    }

    /// Kill any stale tell-daemon.py from a previous app session (best-effort).
    private func reapOrphans() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        task.arguments = ["-f", "tell-daemon.py"]
        task.standardOutput = Pipe(); task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
    }
}

private extension Process {
    /// Wait at most `timeoutSeconds` for the process to exit. Returns true if it did.
    func waitForExit(timeoutSeconds: Double) -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while isRunning {
            if Date() >= deadline { return false }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return true
    }
}

private extension FileHandle {
    /// Read one line (until \n) as UTF-8. Returns nil on EOF.
    func readLine(strippingNewline: Bool) throws -> String? {
        var buf = Data()
        while true {
            let chunk = availableData
            if chunk.isEmpty {
                return buf.isEmpty ? nil :
                    String(data: buf, encoding: .utf8)
            }
            buf.append(chunk)
            if let nl = buf.firstIndex(of: 0x0A) {
                let lineData = buf.prefix(strippingNewline ? nl : nl + 1)
                return String(data: lineData, encoding: .utf8)
            }
        }
    }
}

// MARK: - tell-rich JSON payload

struct RichPayload: Decodable {
    let overall: String?
    let intent: String?
    let generated_at: String?
    let model: String?
    let apps: [RichApp]?
    struct RichApp: Decodable {
        let name: String
        let summary: String?
    }
}

@MainActor
final class ActivityStore: ObservableObject {
    @Published var apps: [AppActivity] = []
    @Published var rangeText: String = ""
    @Published var totalActive: String = ""
    @Published var refreshedAt: String = ""
    @Published var intent: String = ""
    /// LLM-generated overall narrative from tell-rich. Empty until refresh runs.
    @Published var overall: String = ""
    /// LLM-generated per-app one-liners, keyed by app name (case-insensitive lookup).
    @Published var aiSummaries: [String: String] = [:]
    /// Model + provenance for the hero footer.
    @Published var richModel: String = ""
    @Published var richGeneratedAt: String = ""
    /// True while the refresh button is running tell-rich in the background.
    @Published var refreshing: Bool = false

    var dataDir: URL { TellSettings.shared.resolvedDataDir }
    var richPath: URL { dataDir.appendingPathComponent("latest.json") }
    var richBin: URL {
        TellSettings.shared.resolvedProjectRoot
            .appendingPathComponent("cli/tell-rich")
    }

    private let driftApps: Set<String> = [
        "Twitter", "X", "Discord", "Slack", "LINE", "Messages",
        "TikTok", "Instagram", "Facebook", "Reddit", "YouTube",
    ]

    func reload(range: RangeKey) {
        let cal = Calendar.current
        let now = Date()
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        let targetDate: Date = (range == .yesterday)
            ? cal.date(byAdding: .day, value: -1, to: now)!
            : now
        let dateStr = df.string(from: targetDate)
        let path = dataDir.appendingPathComponent("screen").appendingPathComponent("\(dateStr).md")

        // Refresh tell-rich JSON BEFORE parsing — so summaries / overall reflect
        // the same window we're rendering. Falls back silently if file missing.
        loadRichPayload()

        let raw = (try? String(contentsOf: path, encoding: .utf8)) ?? ""
        var sessions = parseSessions(raw, day: targetDate)

        let windowStart: Date
        let windowEnd: Date
        switch range {
        case .pastHour:
            windowEnd = now
            windowStart = now.addingTimeInterval(-3600)
        case .today:
            windowStart = cal.startOfDay(for: now)
            windowEnd = now
        case .yesterday:
            windowStart = cal.startOfDay(for: targetDate)
            windowEnd = cal.date(byAdding: .day, value: 1, to: windowStart)!
        }

        sessions = sessions.filter { $0.end >= windowStart && $0.start <= windowEnd }

        let grouped = Dictionary(grouping: sessions, by: { $0.app })
        var built: [AppActivity] = []
        for (app, ss) in grouped {
            let total = ss.reduce(0) { $0 + $1.seconds }
            if total < 5 { continue }
            let sorted = ss.sorted { $0.start > $1.start }
            let last = sorted.first!.end
            let spark = buildSpark(sessions: ss, start: windowStart, end: windowEnd)
            let drift = driftApps.contains(app)
            let summary = makeSummary(app: app, sessions: sorted)
            built.append(AppActivity(
                name: app, totalSeconds: total, sessions: sorted,
                spark: spark, drift: drift, summary: summary, lastSeen: last
            ))
        }

        apps = built.sorted { $0.totalSeconds > $1.totalSeconds }

        let tf = DateFormatter(); tf.dateFormat = "HH:mm"
        rangeText = "\(tf.string(from: windowStart)) – \(tf.string(from: min(windowEnd, now)))"
        totalActive = humanDuration(apps.reduce(0) { $0 + $1.totalSeconds })
        let tf2 = DateFormatter(); tf2.dateFormat = "HH:mm:ss"
        refreshedAt = tf2.string(from: Date())
        intent = loadIntent(date: dateStr)
    }

    private func loadIntent(date: String) -> String {
        let url = dataDir.appendingPathComponent("intentions").appendingPathComponent("\(date).md")
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        let parts = raw.components(separatedBy: "## Today's focus")
        guard parts.count >= 2 else { return "" }
        return parts[1]
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty && !$0.hasPrefix("_") }) ?? ""
    }

    private func parseSessions(_ raw: String, day: Date) -> [Session] {
        let lines = raw.components(separatedBy: "\n")
        let pattern = #"^## (\d{2}):(\d{2}):(\d{2})[–-](\d{2}):(\d{2}):(\d{2}) \((\d+)s\) — (.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)
        var out: [Session] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if let m = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                func n(_ idx: Int) -> Int {
                    guard let r = Range(m.range(at: idx), in: line) else { return 0 }
                    return Int(line[r]) ?? 0
                }
                func s(_ idx: Int) -> String {
                    guard let r = Range(m.range(at: idx), in: line) else { return "" }
                    return String(line[r])
                }
                let sh = n(1), sm = n(2), ss = n(3)
                let eh = n(4), em = n(5), es = n(6)
                let app = s(8)
                let start = cal.date(byAdding: .second, value: sh * 3600 + sm * 60 + ss, to: dayStart)!
                let end = cal.date(byAdding: .second, value: eh * 3600 + em * 60 + es, to: dayStart)!
                var title = ""
                if i + 1 < lines.count {
                    let t = lines[i + 1]
                    if let tr = t.range(of: "title: `") {
                        let after = t[tr.upperBound...]
                        if let endTick = after.firstIndex(of: "`") {
                            title = String(after[..<endTick])
                        }
                    }
                }
                out.append(Session(app: app, title: title, start: start, end: end))
            }
            i += 1
        }
        return out
    }

    private func buildSpark(sessions: [Session], start: Date, end: Date) -> [SparkLevel] {
        let bucketCount = 5
        let span = max(end.timeIntervalSince(start), 1)
        var totals = Array(repeating: 0.0, count: bucketCount)
        let bucketSpan = span / Double(bucketCount)
        for s in sessions {
            let a = max(s.start.timeIntervalSince(start), 0)
            let b = min(s.end.timeIntervalSince(start), span)
            if b <= a { continue }
            for i in 0..<bucketCount {
                let bs = Double(i) * bucketSpan
                let be = bs + bucketSpan
                let overlap = max(0, min(b, be) - max(a, bs))
                totals[i] += overlap
            }
        }
        let maxV = totals.max() ?? 0
        if maxV < 1 { return Array(repeating: .off, count: bucketCount) }
        return totals.map { v in
            if v < maxV * 0.15 { return .off }
            if v < maxV * 0.60 { return .on }
            return .peak
        }
    }

    private func makeSummary(app: String, sessions: [Session]) -> String {
        // 1. Prefer LLM-generated summary from tell-rich (case-insensitive match)
        let aiKey = app.lowercased()
        if let ai = aiSummaries[aiKey], !ai.isEmpty {
            return ai
        }
        // 2. Fallback: heuristic from window titles
        if sessions.isEmpty { return "—" }
        let first = sessions.first!
        let n = sessions.count
        if n == 1 {
            return first.title.isEmpty ? "One short session." : first.title
        }
        let tf = DateFormatter(); tf.dateFormat = "HH:mm"
        let title = first.title.isEmpty ? "" : "“\(truncate(first.title, 40))”. "
        return "\(title)\(n) sessions, last at \(tf.string(from: first.end))."
    }

    // MARK: - tell-rich JSON integration

    /// Parse `latest.json` produced by `tell-rich`. Idempotent.
    private func loadRichPayload() {
        guard
            let data = try? Data(contentsOf: richPath),
            let payload = try? JSONDecoder().decode(RichPayload.self, from: data)
        else {
            overall = ""
            aiSummaries = [:]
            richModel = ""
            richGeneratedAt = ""
            return
        }
        overall = (payload.overall ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var map: [String: String] = [:]
        for a in (payload.apps ?? []) {
            let s = (a.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { map[a.name.lowercased()] = s }
        }
        aiSummaries = map
        richModel = payload.model ?? ""
        richGeneratedAt = payload.generated_at ?? ""
    }

    /// Run `tell-rich --window <range> --save data/latest.json`, then reload.
    /// Settings env vars are injected (no .env.tell dependency).
    func refreshFromCLI(range: RangeKey) {
        refreshing = true
        let bin = richBin
        let saveTo = richPath
        let arg = range.richArg
        let cwd = TellSettings.shared.resolvedProjectRoot
        let env = TellSettings.shared.subprocessEnv
        Task.detached { [weak self] in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: bin.path)
            p.arguments = ["--window", arg, "--save", saveTo.path]
            p.currentDirectoryURL = cwd
            p.environment = env
            p.standardOutput = Pipe()
            p.standardError = Pipe()
            do {
                try p.run()
                p.waitUntilExit()
            } catch {
                // swallow — UI shows whatever's currently in latest.json
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.refreshing = false
                self.reload(range: range)
            }
        }
    }

    // MARK: - gbrain stats

    @Published var gbrainPages: Int = 0
    @Published var gbrainChunks: Int = 0
    @Published var gbrainEmbedded: Int = 0
    @Published var gbrainLastSync: String = ""
    @Published var gbrainSyncing: Bool = false

    /// Run `gbrain import <dataDir> --no-embed` to push fresh data, then refresh stats.
    func gbrainSyncManually() {
        gbrainSyncing = true
        let gbrainBin = TellSettings.shared.gbrainBinPath
        let dataPath = TellSettings.shared.resolvedDataDir.path
        let env = TellSettings.shared.subprocessEnv
        Task.detached { [weak self] in
            // 1. gbrain import
            let imp = Process()
            imp.executableURL = URL(fileURLWithPath: gbrainBin)
            imp.arguments = ["import", dataPath, "--no-embed"]
            imp.environment = env
            imp.standardOutput = Pipe(); imp.standardError = Pipe()
            try? imp.run()
            imp.waitUntilExit()

            // 2. gbrain stats → parse Pages/Chunks/Embedded
            let stats = Process()
            stats.executableURL = URL(fileURLWithPath: gbrainBin)
            stats.arguments = ["stats"]
            stats.environment = env
            let outPipe = Pipe(); stats.standardOutput = outPipe
            stats.standardError = Pipe()
            try? stats.run(); stats.waitUntilExit()
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let outText = String(data: outData, encoding: .utf8) ?? ""
            let p = Self.extractInt(after: "Pages:", in: outText)
            let c = Self.extractInt(after: "Chunks:", in: outText)
            let e = Self.extractInt(after: "Embedded:", in: outText)

            let now = DateFormatter()
            now.dateFormat = "HH:mm:ss"
            let stamp = now.string(from: Date())

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.gbrainPages = p
                self.gbrainChunks = c
                self.gbrainEmbedded = e
                self.gbrainLastSync = stamp
                self.gbrainSyncing = false
            }
        }
    }

    /// Quietly refresh stats only (no import).
    func refreshGbrainStats() {
        let gbrainBin = TellSettings.shared.gbrainBinPath
        let env = TellSettings.shared.subprocessEnv
        Task.detached { [weak self] in
            let stats = Process()
            stats.executableURL = URL(fileURLWithPath: gbrainBin)
            stats.arguments = ["stats"]
            stats.environment = env
            let outPipe = Pipe(); stats.standardOutput = outPipe
            stats.standardError = Pipe()
            do { try stats.run() } catch { return }
            stats.waitUntilExit()
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let outText = String(data: outData, encoding: .utf8) ?? ""
            let p = Self.extractInt(after: "Pages:", in: outText)
            let c = Self.extractInt(after: "Chunks:", in: outText)
            let e = Self.extractInt(after: "Embedded:", in: outText)
            await MainActor.run { [weak self] in
                self?.gbrainPages = p
                self?.gbrainChunks = c
                self?.gbrainEmbedded = e
            }
        }
    }

    nonisolated private static func extractInt(after marker: String, in text: String) -> Int {
        guard let range = text.range(of: marker) else { return 0 }
        let tail = text[range.upperBound...]
        let digits = tail.prefix(20).filter { $0.isNumber || $0 == " " }
            .trimmingCharacters(in: .whitespaces)
        let firstNum = digits.split(separator: " ").first ?? ""
        return Int(firstNum) ?? 0
    }

    private func truncate(_ s: String, _ max: Int) -> String {
        s.count <= max ? s : String(s.prefix(max)) + "…"
    }

    func humanDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let m = seconds / 60
        if m < 60 { return "\(m)m" }
        return String(format: "%dh %02dm", m / 60, m % 60)
    }

    func launch(_ appName: String) {
        guard let url = AppCatalog.shared.url(for: appName) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }
}

// MARK: - Dashboard view

struct DashboardView: View {
    @StateObject var store = ActivityStore()
    @EnvironmentObject var daemon: DaemonController
    @State private var range: RangeKey = .pastHour
    @State private var openApp: String? = nil
    @State private var pulse = false
    @State private var showAllInstalled = false
    @Namespace private var rangeNs

    var body: some View {
        VStack(spacing: 0) {
            topbar
            Rectangle().fill(T.borderSoft).frame(height: 0.5)
            rangeRow
            heroCard
            gbrainRow
            sectionHead
            ScrollView { content.padding(.bottom, 20) }
        }
        .frame(width: 720, height: 760)
        .background(T.bg)
        .preferredColorScheme(.dark)
        .onAppear {
            store.reload(range: range)
            store.refreshGbrainStats()
            withAnimation(.easeInOut(duration: 2.2).repeatForever()) { pulse.toggle() }
        }
        .onChange(of: range) {
            store.reload(range: range)
            openApp = nil
        }
    }

    // MARK: gbrain status strip

    private var gbrainRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(daemon.running ? T.accent : T.fgQuat)
                    .frame(width: 6, height: 6)
                Text("daemon")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(T.fgSec)
                Text(daemon.running ? "pid \(daemon.pid)" : "stopped")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(T.fgTer)
            }
            Rectangle().fill(T.borderSoft).frame(width: 1, height: 14)
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 11))
                    .foregroundColor(T.fgSec)
                Text("gbrain")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(T.fgSec)
                Text("\(store.gbrainPages)p · \(store.gbrainChunks)c · \(store.gbrainEmbedded)e")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(T.fgTer)
                if !store.gbrainLastSync.isEmpty {
                    Text("· synced \(store.gbrainLastSync)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(T.fgQuat)
                }
            }
            Spacer()
            Button {
                store.gbrainSyncManually()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: store.gbrainSyncing ? "arrow.triangle.2.circlepath" : "arrow.up.circle")
                    Text(store.gbrainSyncing ? "syncing…" : "Sync to gbrain")
                }
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundColor(T.fgSec)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(T.bgElev))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(T.borderSoft, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .disabled(store.gbrainSyncing)
        }
        .padding(.horizontal, 20).padding(.bottom, 12)
    }

    // MARK: top bar

    private var topbar: some View {
        HStack(alignment: .center) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle()
                    .fill(T.accent).frame(width: 7, height: 7)
                    .shadow(color: T.accent.opacity(0.55), radius: 4)
                    .opacity(pulse ? 0.55 : 1)
                Text("Tell")
                    .font(.system(size: 17, weight: .medium))
                    .italic()
                    .foregroundColor(T.fgPri)
                Text("watching · \(store.rangeText)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(T.fgTer)
            }
            Spacer()
            HStack(spacing: 4) {
                iconBtn(daemon.running ? "pause.circle" : "play.circle") {
                    if daemon.running { daemon.stop() } else { daemon.startIfNeeded() }
                }
                iconBtn(showAllInstalled ? "square.grid.2x2.fill" : "square.grid.2x2") {
                    showAllInstalled.toggle()
                }
                iconBtn(store.refreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise") {
                    store.refreshFromCLI(range: range)
                }
                iconBtn("gearshape") {
                    NSApp.activate(ignoringOtherApps: true)
                    if #available(macOS 14.0, *) {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    } else {
                        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                    }
                }
                iconBtn("xmark") {
                    NSApp.keyWindow?.close()
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 12)
    }

    private func iconBtn(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color.clear)
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(T.fgTer)
            }
            .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .onHover { _ in }
    }

    // MARK: range toggle

    private var rangeRow: some View {
        HStack {
            HStack(spacing: 2) {
                ForEach(RangeKey.allCases, id: \.self) { k in rangePill(k) }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(T.bgDeep)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(T.borderSoft, lineWidth: 0.5))
            )
            Spacer()
            Text("updated \(store.refreshedAt)")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundColor(T.fgTer)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private func rangePill(_ k: RangeKey) -> some View {
        let active = (range == k)
        return Button {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                range = k
            }
        } label: {
            HStack(spacing: 6) {
                if k == .pastHour {
                    Circle()
                        .fill(T.accent).frame(width: 5, height: 5)
                        .shadow(color: T.accent.opacity(0.5), radius: 3)
                        .opacity(active && pulse ? 0.5 : 1)
                }
                Text(k.label)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(active ? T.fgPri : T.fgSec)
                    .animation(.easeOut(duration: 0.18), value: active)
            }
            .padding(.horizontal, 14).frame(height: 28)
            .background(
                ZStack {
                    if active {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(T.bgElev2)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(T.borderStrong, lineWidth: 0.5)
                            )
                            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                            .matchedGeometryEffect(id: "activeRange", in: rangeNs)
                    }
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: hero

    private var heroCard: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(T.warn).frame(width: 2)
                .shadow(color: T.warn.opacity(0.3), radius: 4)
            VStack(alignment: .leading, spacing: 8) {
                Text("TELL · \(range.label.uppercased())")
                    .font(.system(size: 10, weight: .semibold)).tracking(1.6)
                    .foregroundColor(T.warn)
                heroBody
                HStack {
                    Text(heroFooter())
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(T.fgQuat)
                    Spacer()
                    Text("\(store.totalActive) active · \(store.apps.count) apps")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(T.fgQuat)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
        }
        .background(T.bgHero)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(T.border, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 20).padding(.bottom, 16)
    }

    @ViewBuilder
    private var heroBody: some View {
        // Prefer LLM overall from tell-rich. Wrap inline ⟨...⟩ tokens in warn color.
        if !store.overall.isEmpty {
            highlighted(store.overall)
                .font(.system(size: 18))
                .italic()
                .foregroundColor(T.fgPri)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(fallbackHeroText())
                .font(.system(size: 18))
                .italic()
                .foregroundColor(T.fgPri)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Render text with ⟨...⟩ runs highlighted in warn color (as in the mockup).
    private func highlighted(_ s: String) -> Text {
        var out = Text("")
        var buf = ""
        var inMark = false
        for ch in s {
            if ch == "⟨" {
                if !buf.isEmpty {
                    out = out + Text(buf).foregroundColor(T.fgPri)
                    buf.removeAll()
                }
                inMark = true
                continue
            }
            if ch == "⟩" {
                if !buf.isEmpty {
                    out = out + Text(buf)
                        .foregroundColor(T.warn)
                        .fontWeight(.semibold)
                    buf.removeAll()
                }
                inMark = false
                continue
            }
            buf.append(ch)
        }
        if !buf.isEmpty {
            out = out + Text(buf).foregroundColor(inMark ? T.warn : T.fgPri)
        }
        return out
    }

    private func fallbackHeroText() -> String {
        if store.refreshing {
            return "Generating Tell observation…"
        }
        if store.apps.isEmpty {
            if !store.intent.isEmpty {
                return "You said: \(store.intent) — but I have no screen samples for this range."
            }
            return "No activity captured in this range. Daemon may be paused."
        }
        let parts = store.apps.prefix(3).map { "\($0.name) \(store.humanDuration($0.totalSeconds))" }
        let head = parts.joined(separator: ", ")
        return "\(head). Press ↻ to ask Tell for an honest read."
    }

    private func heroFooter() -> String {
        if store.overall.isEmpty {
            return "no LLM observation yet · press ↻ to generate"
        }
        let model = store.richModel.isEmpty ? "model" : store.richModel
        let when = store.richGeneratedAt.isEmpty ? store.refreshedAt : store.richGeneratedAt
        return "generated \(when) · via \(model) · local data"
    }

    // MARK: section head

    private var sectionHead: some View {
        HStack {
            Text(showAllInstalled
                 ? "ALL INSTALLED APPS · \(AppCatalog.shared.allApps().count)"
                 : "APPS · \(range.label.uppercased())")
                .font(.system(size: 11, weight: .semibold)).tracking(1.5)
                .foregroundColor(T.fgTer)
            Spacer()
            Text(showAllInstalled
                 ? "click to launch"
                 : "tap to expand · double-click to launch")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundColor(T.fgQuat)
        }
        .padding(.horizontal, 20).padding(.bottom, 10)
    }

    // MARK: content (activity grid OR installed apps grid)

    @ViewBuilder private var content: some View {
        if showAllInstalled {
            installedGrid
        } else {
            activityGrid
        }
    }

    private var activityGrid: some View {
        let openCard = store.apps.first { $0.name == openApp }
        let others = store.apps.filter { $0.name != openApp }
        return VStack(spacing: 8) {
            if let openCard {
                ExpandedCard(activity: openCard, store: store) { openApp = nil }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(others) { app in
                    AppCard(activity: app) { openApp = app.name } onLaunch: { store.launch(app.name) }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private var installedGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 12) {
            ForEach(AppCatalog.shared.allApps(), id: \.url) { entry in
                Button {
                    NSWorkspace.shared.openApplication(
                        at: entry.url,
                        configuration: NSWorkspace.OpenConfiguration(),
                        completionHandler: nil
                    )
                } label: {
                    VStack(spacing: 6) {
                        appIcon(name: entry.name, size: 44)
                        Text(entry.name)
                            .font(.system(size: 10.5))
                            .foregroundColor(T.fgSec)
                            .lineLimit(2).multilineTextAlignment(.center)
                            .frame(height: 26)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(T.bgElev))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(T.borderSoft, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - App card

struct AppCard: View {
    let activity: AppActivity
    let onTap: () -> Void
    let onLaunch: () -> Void
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                appIcon(name: activity.name, size: 30)
                Spacer()
                Text(durString(activity.totalSeconds))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(activity.drift ? T.warn : T.fgPri)
            }
            Text(activity.name)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(T.fgPri).lineLimit(1)
            Text(activity.summary)
                .font(.system(size: 12.5))
                .italic()
                .foregroundColor(T.fgSec)
                .lineSpacing(2).lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            spark
        }
        .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 11)
        .frame(minHeight: 124, alignment: .topLeading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(hover ? T.bgHover : T.bgElev)
                if activity.drift {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(LinearGradient(colors: [T.warn.opacity(0.05), .clear],
                                             startPoint: .top, endPoint: .center))
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(activity.drift ? T.warn.opacity(0.22) : T.borderSoft, lineWidth: 0.5)
        )
        .overlay(alignment: .topTrailing) {
            if activity.drift {
                Circle().fill(T.warn).frame(width: 5, height: 5)
                    .shadow(color: T.warn.opacity(0.5), radius: 3)
                    .padding(8)
            }
        }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(count: 2) { onLaunch() }
        .onTapGesture { onTap() }
        .contextMenu {
            Button("Expand") { onTap() }
            Button("Open \(activity.name)") { onLaunch() }
        }
    }

    private var spark: some View {
        HStack(spacing: 2) {
            ForEach(0..<activity.spark.count, id: \.self) { i in
                Rectangle()
                    .fill(colorFor(activity.spark[i]))
                    .frame(height: 12).cornerRadius(1)
            }
        }
    }

    private func colorFor(_ s: SparkLevel) -> Color {
        switch s {
        case .off:  return T.fgQuat
        case .on:   return activity.drift ? T.warn.opacity(0.65) : T.fgTer
        case .peak: return activity.drift ? T.warn : T.fgSec
        }
    }

    private func durString(_ s: Int) -> String {
        if s < 60 { return "\(s)s" }
        let m = s / 60
        if m < 60 { return "\(m)m" }
        return String(format: "%dh %02dm", m / 60, m % 60)
    }
}

// MARK: - Expanded card

struct ExpandedCard: View {
    let activity: AppActivity
    let store: ActivityStore
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                appIcon(name: activity.name, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(T.fgPri)
                    Text("\(activity.sessions.count) sessions")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(T.fgTer)
                }
                Spacer()
                Button {
                    store.launch(activity.name)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                        Text("Open")
                    }
                    .font(.system(size: 11))
                    .foregroundColor(T.fgSec)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(T.bgElev))
                }
                .buttonStyle(.plain)
                Text(durString(activity.totalSeconds))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(activity.drift ? T.warn : T.fgPri)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(T.fgTer)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(T.bgElev))
                }
                .buttonStyle(.plain)
            }
            Text(activity.summary)
                .font(.system(size: 12.5))
                .italic()
                .foregroundColor(T.fgSec)

            VStack(spacing: 0) {
                ForEach(Array(activity.sessions.enumerated()), id: \.offset) { idx, s in
                    if idx > 0 { Rectangle().fill(T.borderSoft).frame(height: 0.5) }
                    HStack(spacing: 14) {
                        Text("\(time(s.start)) – \(time(s.end))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(T.fgTer)
                            .frame(width: 96, alignment: .leading)
                        Text(s.title.isEmpty ? "(no title)" : s.title)
                            .font(.system(size: 12.5))
                            .foregroundColor(T.fgPri).lineLimit(1)
                        Spacer()
                        Text(durString(s.seconds))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(T.fgTer)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                }
            }
            .background(T.bgDeep)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(T.borderSoft, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(14)
        .background(T.bgElev2)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(T.borderStrong, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func time(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
    private func durString(_ s: Int) -> String {
        if s < 60 { return "\(s)s" }
        let m = s / 60
        if m < 60 { return "\(m)m" }
        return String(format: "%dh %02dm", m / 60, m % 60)
    }
}

// MARK: - Real macOS icon

func appIcon(name: String, size: CGFloat) -> some View {
    Group {
        if let ns = AppCatalog.shared.icon(for: name) {
            Image(nsImage: ns)
                .resizable().interpolation(.high)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(T.bgElev2)
                Text(String(name.prefix(1)))
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundColor(T.fgSec)
            }
            .frame(width: size, height: size)
        }
    }
    .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
}

#Preview {
    DashboardView()
}
