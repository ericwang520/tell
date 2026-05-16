//
//  Settings.swift — Tell preferences, redesigned per Style D
//  (tell-setup-prefs.jsx + tokens-surfaces.css)
//

import SwiftUI
import AppKit

// MARK: - Settings model (UserDefaults wrapper, unchanged)

struct TellSettings {
    static let shared = TellSettings()

    static let kOpenaiApiKey      = "openaiApiKey"
    static let kTellApiBase       = "tellApiBase"
    static let kTellApiKey        = "tellApiKey"
    static let kTellApiModel      = "tellApiModel"
    static let kOllamaUrl         = "ollamaUrl"
    static let kOllamaNarrModel   = "ollamaNarrModel"
    static let kProjectRoot       = "projectRoot"
    static let kDataDir           = "dataDir"
    static let kDaemonAutoStart   = "daemonAutoStart"
    static let kDaemonIdleSeconds = "daemonIdleSeconds"
    static let kDaemonPollSeconds = "daemonPollSeconds"
    static let kGbrainSyncEvery   = "gbrainSyncEvery"
    static let kGbrainBinPath     = "gbrainBinPath"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            kTellApiBase:       "https://hnd1.aihub.zeabur.ai/v1",
            kTellApiModel:      "claude-haiku-4-5",
            kOllamaUrl:         "http://localhost:11434",
            kOllamaNarrModel:   "qwen2.5:7b",
            kProjectRoot:       "~/Desktop/yc_gbrain",
            kDataDir:           "~/Desktop/yc_gbrain/data",
            kDaemonAutoStart:   true,
            kDaemonIdleSeconds: 180,
            kDaemonPollSeconds: 1,
            kGbrainSyncEvery:   3,
            kGbrainBinPath:     "/Users/wanghuangruei/.bun/bin/gbrain",
        ])
    }

    private let d = UserDefaults.standard
    var openaiApiKey: String      { d.string(forKey: Self.kOpenaiApiKey) ?? "" }
    var tellApiBase: String       { d.string(forKey: Self.kTellApiBase) ?? "" }
    var tellApiKey: String        { d.string(forKey: Self.kTellApiKey) ?? "" }
    var tellApiModel: String      { d.string(forKey: Self.kTellApiModel) ?? "claude-haiku-4-5" }
    var ollamaUrl: String         { d.string(forKey: Self.kOllamaUrl) ?? "http://localhost:11434" }
    var ollamaNarrModel: String   { d.string(forKey: Self.kOllamaNarrModel) ?? "qwen2.5:7b" }
    var projectRoot: String       { d.string(forKey: Self.kProjectRoot) ?? "~/Desktop/yc_gbrain" }
    var dataDir: String           { d.string(forKey: Self.kDataDir) ?? "" }
    var daemonAutoStart: Bool     { d.object(forKey: Self.kDaemonAutoStart) as? Bool ?? true }
    var daemonIdleSeconds: Int    { d.object(forKey: Self.kDaemonIdleSeconds) as? Int ?? 180 }
    var daemonPollSeconds: Int    { d.object(forKey: Self.kDaemonPollSeconds) as? Int ?? 1 }
    var gbrainSyncEvery: Int      { d.object(forKey: Self.kGbrainSyncEvery) as? Int ?? 3 }
    var gbrainBinPath: String     { d.string(forKey: Self.kGbrainBinPath) ?? "/Users/wanghuangruei/.bun/bin/gbrain" }

    var resolvedDataDir: URL {
        if !dataDir.isEmpty {
            return URL(fileURLWithPath: (dataDir as NSString).expandingTildeInPath)
        }
        let appSup = FileManager.default.urls(for: .applicationSupportDirectory,
                                              in: .userDomainMask).first!
        return appSup.appendingPathComponent("Tell").appendingPathComponent("data")
    }
    var resolvedProjectRoot: URL {
        URL(fileURLWithPath: (projectRoot as NSString).expandingTildeInPath)
    }

    var subprocessEnv: [String: String] {
        var env = ProcessInfo.processInfo.environment
        if !openaiApiKey.isEmpty { env["OPENAI_API_KEY"] = openaiApiKey }
        if !tellApiBase.isEmpty  { env["TELL_API_BASE"]  = tellApiBase }
        if !tellApiKey.isEmpty   { env["TELL_API_KEY"]   = tellApiKey }
        if !tellApiModel.isEmpty { env["TELL_API_MODEL"] = tellApiModel }
        env["TELL_DATA_DIR"]        = resolvedDataDir.path
        env["TELL_PROJECT_ROOT"]    = resolvedProjectRoot.path
        env["TELL_OLLAMA_URL"]      = ollamaUrl
        env["TELL_NARRATIVE_MODEL"] = ollamaNarrModel
        return env
    }

    func ensureDataDirs() {
        let fm = FileManager.default
        let base = resolvedDataDir
        for sub in ["screen", "intentions", "retros", "captures"] {
            let d = base.appendingPathComponent(sub)
            try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        }
    }
}

// MARK: - Style D primitives

private struct SectionCard<Content: View>: View {
    var title: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let t = title {
                Text(t)
                    .font(T.ui(13, weight: .semibold))
                    .foregroundColor(T.fgPri)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18).padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: T.rCard).fill(T.bgElev))
        .overlay(RoundedRectangle(cornerRadius: T.rCard).stroke(T.borderSoft, lineWidth: 0.5))
    }
}

private struct FieldLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(T.ui(10, weight: .semibold))
            .tracking(1.4)
            .foregroundColor(T.fgTer)
    }
}

private struct TDInputModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(T.mono(12))
            .foregroundColor(T.fgPri)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(T.bgDeep)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(T.border, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
private extension View { func tdInput() -> some View { modifier(TDInputModifier()) } }

private struct TDSwitch: View {
    @Binding var isOn: Bool
    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 9)
                    .fill(isOn ? T.accent.opacity(0.20) : T.bgElev)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(isOn ? T.accent.opacity(0.4) : T.border, lineWidth: 0.5)
                    )
                    .frame(width: 28, height: 16)
                Circle()
                    .fill(isOn ? T.accent : T.fgSec)
                    .frame(width: 11, height: 11)
                    .padding(.horizontal, 1.5)
            }
            .animation(.easeOut(duration: 0.18), value: isOn)
        }
        .buttonStyle(.plain)
    }
}

private struct TDStepperRow: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    init(_ label: String, value: Binding<Int>, in range: ClosedRange<Int>, step: Int = 1) {
        self.label = label; self._value = value; self.range = range; self.step = step
    }
    var body: some View {
        HStack {
            Text(label)
                .font(T.ui(12))
                .foregroundColor(T.fgSec)
            Spacer()
            HStack(spacing: 0) {
                stepBtn("−") {
                    value = max(range.lowerBound, value - step)
                }
                Text("\(value)")
                    .font(T.mono(12)).monospacedDigit()
                    .foregroundColor(T.fgPri)
                    .frame(width: 38, height: 28)
                    .overlay(
                        HStack { Rectangle().fill(T.border).frame(width: 0.5); Spacer(); Rectangle().fill(T.border).frame(width: 0.5) }
                    )
                stepBtn("+") {
                    value = min(range.upperBound, value + step)
                }
            }
            .background(T.bgDeep)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(T.border, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .frame(height: 28)
        }
    }

    private func stepBtn(_ glyph: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(glyph)
                .font(T.ui(13, weight: .medium))
                .foregroundColor(T.fgSec)
                .frame(width: 24, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SubTabs: View {
    @Binding var selection: PrefTab
    var body: some View {
        HStack(spacing: 2) {
            ForEach(PrefTab.allCases) { t in
                Button { selection = t } label: {
                    Text(t.label)
                        .font(T.ui(12, weight: .medium))
                        .foregroundColor(selection == t ? T.fgPri : T.fgSec)
                        .padding(.horizontal, 14)
                        .frame(height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(selection == t ? T.bgElev2 : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(selection == t ? T.borderStrong : Color.clear,
                                                lineWidth: 0.5)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8).fill(T.bgDeep)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(T.borderSoft, lineWidth: 0.5))
        )
    }
}

private enum PrefTab: String, CaseIterable, Identifiable {
    case api, daemon, paths
    var id: String { rawValue }
    var label: String {
        switch self { case .api: return "API Keys"; case .daemon: return "Daemon"; case .paths: return "Paths" }
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @AppStorage(TellSettings.kOpenaiApiKey)      private var openaiApiKey: String = ""
    @AppStorage(TellSettings.kTellApiBase)       private var tellApiBase: String = "https://hnd1.aihub.zeabur.ai/v1"
    @AppStorage(TellSettings.kTellApiKey)        private var tellApiKey: String = ""
    @AppStorage(TellSettings.kTellApiModel)      private var tellApiModel: String = "claude-haiku-4-5"
    @AppStorage(TellSettings.kOllamaUrl)         private var ollamaUrl: String = "http://localhost:11434"
    @AppStorage(TellSettings.kOllamaNarrModel)   private var ollamaNarrModel: String = "qwen2.5:7b"
    @AppStorage(TellSettings.kProjectRoot)       private var projectRoot: String = "~/Desktop/yc_gbrain"
    @AppStorage(TellSettings.kDataDir)           private var dataDir: String = ""
    @AppStorage(TellSettings.kDaemonAutoStart)   private var daemonAutoStart: Bool = true
    @AppStorage(TellSettings.kDaemonIdleSeconds) private var daemonIdleSeconds: Int = 180
    @AppStorage(TellSettings.kDaemonPollSeconds) private var daemonPollSeconds: Int = 1
    @AppStorage(TellSettings.kGbrainSyncEvery)   private var gbrainSyncEvery: Int = 3
    @AppStorage(TellSettings.kGbrainBinPath)     private var gbrainBinPath: String = "/Users/wanghuangruei/.bun/bin/gbrain"

    @State private var tab: PrefTab = .api
    @State private var testResult: String = ""
    @State private var testing: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                SubTabs(selection: $tab)
                Spacer()
            }
            .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 12)
            ScrollView {
                VStack(spacing: 14) {
                    switch tab {
                    case .api:    apiTab
                    case .daemon: daemonTab
                    case .paths:  pathsTab
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 18)
            }
        }
        .frame(width: 560, height: 460)
        .background(T.bg)
        .preferredColorScheme(.dark)
    }

    // ── API ──

    private var apiTab: some View {
        VStack(spacing: 14) {
            SectionCard(title: "OpenAI (gbrain embeddings)") {
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel(text: "API key")
                    SecureField("sk-…", text: $openaiApiKey).tdInput()
                }
            }
            SectionCard(title: "Tell narrative") {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        FieldLabel(text: "Endpoint URL")
                        TextField("https://…/v1", text: $tellApiBase).tdInput()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        FieldLabel(text: "API key")
                        SecureField("sk-…", text: $tellApiKey).tdInput()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        FieldLabel(text: "Model")
                        TextField("claude-haiku-4-5", text: $tellApiModel).tdInput()
                    }
                    HStack(spacing: 12) {
                        Button(testing ? "Testing…" : "Test endpoint") {
                            Task { await testEndpoint() }
                        }
                        .buttonStyle(SecondaryGhostButtonStyle())
                        .disabled(testing || tellApiKey.isEmpty || tellApiBase.isEmpty)
                        Text(testResult)
                            .font(T.mono(11))
                            .foregroundColor(testResult.hasPrefix("✅") ? T.accent
                                             : testResult.hasPrefix("❌") ? T.warn
                                             : T.fgTer)
                            .lineLimit(2)
                    }
                }
            }
            SectionCard(title: "Local Ollama (optional)") {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        FieldLabel(text: "Ollama URL")
                        TextField("http://localhost:11434", text: $ollamaUrl).tdInput()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        FieldLabel(text: "Narrative model")
                        TextField("qwen2.5:7b", text: $ollamaNarrModel).tdInput()
                    }
                }
            }
        }
    }

    // ── Daemon ──

    private var daemonTab: some View {
        VStack(spacing: 14) {
            SectionCard {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Auto-start daemon when app launches")
                            .font(T.ui(12.5, weight: .medium))
                            .foregroundColor(T.fgPri)
                        Text("Without this you'll need to start the daemon manually.")
                            .font(T.serif(11.5))
                            .foregroundColor(T.fgTer)
                    }
                    Spacer()
                    TDSwitch(isOn: $daemonAutoStart)
                }
            }
            SectionCard(title: "Capture cadence") {
                VStack(spacing: 8) {
                    TDStepperRow("Poll interval (seconds, 1–10)",
                                 value: $daemonPollSeconds, in: 1...10)
                    TDStepperRow("Idle timeout (seconds, 30–600)",
                                 value: $daemonIdleSeconds, in: 30...600, step: 30)
                }
            }
            SectionCard(title: "gbrain integration") {
                VStack(spacing: 10) {
                    TDStepperRow("Auto-sync after every N segments",
                                 value: $gbrainSyncEvery, in: 1...20)
                    VStack(alignment: .leading, spacing: 6) {
                        FieldLabel(text: "gbrain binary path")
                        TextField("/path/to/gbrain", text: $gbrainBinPath).tdInput()
                    }
                }
            }
        }
    }

    // ── Paths ──

    private var pathsTab: some View {
        VStack(spacing: 14) {
            SectionCard(title: "Project root") {
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel(text: "Path")
                    TextField("~/code/tell", text: $projectRoot).tdInput()
                    Text("daemon/ and cli/ live under this folder")
                        .font(T.mono(10))
                        .foregroundColor(T.fgQuat)
                }
            }
            SectionCard(title: "Data directory") {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("default: ~/Library/Application Support/Tell/data",
                              text: $dataDir).tdInput()
                    Text("resolved · \(TellSettings.shared.resolvedDataDir.path)")
                        .font(T.mono(10))
                        .foregroundColor(T.fgQuat)
                        .textSelection(.enabled)
                    HStack {
                        Button("Open data folder in Finder") {
                            NSWorkspace.shared.open(TellSettings.shared.resolvedDataDir)
                        }
                        .buttonStyle(SecondaryGhostButtonStyle())
                        Spacer()
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    // ── test endpoint ──

    private func testEndpoint() async {
        testing = true; defer { testing = false }
        testResult = ""
        guard let url = URL(string: tellApiBase + "/chat/completions") else {
            testResult = "❌ invalid URL"; return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(tellApiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": tellApiModel,
            "messages": [["role": "user", "content": "say ok"]],
            "max_tokens": 8,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 15
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 200 {
                testResult = "✅ \(tellApiModel) replied"
            } else {
                let snippet = String(data: data.prefix(80), encoding: .utf8) ?? ""
                testResult = "❌ HTTP \(code): \(snippet.prefix(50))"
            }
        } catch {
            testResult = "❌ \(error.localizedDescription.prefix(60))"
        }
    }
}

#Preview { SettingsView() }
