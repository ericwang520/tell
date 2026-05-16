//
//  Settings.swift — Tell preferences (API keys, paths, daemon control)
//

import SwiftUI
import AppKit

// MARK: - Settings (UserDefaults-backed, no @AppStorage here)

/// Plain wrapper around UserDefaults so the non-UI layer (DaemonController, etc.)
/// can read settings without being a SwiftUI View. SwiftUI views use @AppStorage
/// with the same keys defined below.
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

    /// Register defaults once at app launch.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            kTellApiBase:       "https://hnd1.aihub.zeabur.ai/v1",
            kTellApiModel:      "claude-haiku-4-5",
            kOllamaUrl:         "http://localhost:11434",
            kOllamaNarrModel:   "qwen2.5:7b",
            kProjectRoot:       "~/Desktop/yc_gbrain",
            kDataDir:           "~/Desktop/yc_gbrain/data",  // existing data wins
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

    // ─── derived ───

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

// MARK: - Settings window

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

    @State private var testResult: String = ""
    @State private var testing: Bool = false

    var body: some View {
        TabView {
            apiTab.tabItem { Label("API Keys", systemImage: "key.fill") }
            daemonTab.tabItem { Label("Daemon", systemImage: "waveform.path.ecg") }
            pathsTab.tabItem { Label("Paths", systemImage: "folder") }
        }
        .frame(width: 540, height: 400)
        .padding()
    }

    private var apiTab: some View {
        Form {
            Section(header: Text("OpenAI (gbrain embeddings)").font(.caption)) {
                SecureField("OPENAI_API_KEY", text: $openaiApiKey)
            }
            Section(header: Text("Tell narrative (OpenAI-compatible endpoint)").font(.caption)) {
                TextField("Endpoint URL", text: $tellApiBase)
                SecureField("API key", text: $tellApiKey)
                TextField("Model", text: $tellApiModel)
                HStack {
                    Button(testing ? "Testing…" : "Test endpoint") {
                        Task { await testEndpoint() }
                    }
                    .disabled(testing || tellApiBase.isEmpty || tellApiKey.isEmpty)
                    Text(testResult).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section(header: Text("Local Ollama (real-time distill — optional)").font(.caption)) {
                TextField("Ollama URL", text: $ollamaUrl)
                TextField("Narrative model", text: $ollamaNarrModel)
            }
        }
        .formStyle(.grouped)
    }

    private var daemonTab: some View {
        Form {
            Section {
                Toggle("Auto-start daemon when app launches", isOn: $daemonAutoStart)
            }
            Section(header: Text("Capture cadence").font(.caption)) {
                Stepper("Poll interval: \(daemonPollSeconds)s",
                        value: $daemonPollSeconds, in: 1...10)
                Stepper("Treat user idle after: \(daemonIdleSeconds)s",
                        value: $daemonIdleSeconds, in: 30...600, step: 30)
            }
            Section(header: Text("gbrain integration").font(.caption)) {
                Stepper("Auto-sync after every \(gbrainSyncEvery) segment(s)",
                        value: $gbrainSyncEvery, in: 1...20)
                TextField("Path to gbrain binary", text: $gbrainBinPath)
                    .font(.system(.caption, design: .monospaced))
            }
        }
        .formStyle(.grouped)
    }

    private var pathsTab: some View {
        Form {
            Section(header: Text("Project root (daemon/ + cli/)").font(.caption)) {
                TextField("Path", text: $projectRoot)
                    .font(.system(.caption, design: .monospaced))
            }
            Section(header: Text("Data directory").font(.caption)) {
                TextField("Leave empty for ~/Library/Application Support/Tell/data", text: $dataDir)
                    .font(.system(.caption, design: .monospaced))
                Text("Resolved: \(TellSettings.shared.resolvedDataDir.path)")
                    .font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                Button("Open data folder in Finder") {
                    NSWorkspace.shared.open(TellSettings.shared.resolvedDataDir)
                }
            }
        }
        .formStyle(.grouped)
    }

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
                let snippet = String(data: data.prefix(120), encoding: .utf8) ?? ""
                testResult = "❌ HTTP \(code): \(snippet)"
            }
        } catch {
            testResult = "❌ \(error.localizedDescription)"
        }
    }
}

#Preview { SettingsView() }
