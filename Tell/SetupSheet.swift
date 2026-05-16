//
//  SetupSheet.swift — first-launch onboarding (3-item checklist, Tell voice)
//

import SwiftUI
import AppKit
import CoreGraphics

struct SetupSheet: View {
    @Binding var isPresented: Bool

    @AppStorage(TellSettings.kTellApiBase)  private var tellApiBase: String = "https://hnd1.aihub.zeabur.ai/v1"
    @AppStorage(TellSettings.kTellApiKey)   private var tellApiKey: String = ""
    @AppStorage(TellSettings.kTellApiModel) private var tellApiModel: String = "claude-haiku-4-5"
    @AppStorage(TellSettings.kOpenaiApiKey) private var openaiApiKey: String = ""

    @State private var screenPermissionGranted: Bool = false
    @State private var testResult: String = ""
    @State private var testing: Bool = false
    @State private var permPollTask: Task<Void, Never>?

    private let modelChoices = [
        "claude-haiku-4-5",
        "claude-sonnet-4-6",
        "claude-opus-4-7",
        "gpt-4o-mini",
        "gpt-4o",
    ]

    private var canFinish: Bool {
        screenPermissionGranted && !tellApiKey.isEmpty && !tellApiBase.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(T.borderSoft)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section1Permission
                    section2LLM
                    section3OpenAI
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            Divider().background(T.borderSoft)
            footer
        }
        .frame(width: 540, height: 580)
        .background(T.bg)
        .preferredColorScheme(.dark)
        .onAppear {
            checkScreenPermission()
            startPolling()
        }
        .onDisappear { permPollTask?.cancel() }
    }

    // MARK: - parts

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle().fill(T.accent).frame(width: 7, height: 7)
                .shadow(color: T.accent.opacity(0.55), radius: 4)
            VStack(alignment: .leading, spacing: 4) {
                Image("TellWordmark")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 26)
                Text("Tell needs three things to watch your day.")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundColor(T.fgTer)
            }
            Spacer()
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
    }

    @ViewBuilder
    private var section1Permission: some View {
        sectionCard(
            number: "1",
            title: "Permission to see your screen",
            done: screenPermissionGranted
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if screenPermissionGranted {
                    Text("Granted. Tell can capture screen content via Apple Vision OCR.")
                        .font(.system(size: 12)).foregroundColor(T.fgSec)
                } else {
                    Text("Tell uses Apple's Screen Recording API and runs OCR locally. Nothing leaves your machine.")
                        .font(.system(size: 12)).foregroundColor(T.fgSec)
                    HStack(spacing: 8) {
                        Button("Open System Settings") { openScreenRecordingPrefs() }
                            .buttonStyle(SoftButtonStyle())
                        Button("Re-check") { checkScreenPermission() }
                            .buttonStyle(SoftButtonStyle(secondary: true))
                    }
                    Text("After granting, Tell may need to relaunch — quit and reopen if status doesn't update.")
                        .font(.system(size: 10.5)).foregroundColor(T.fgQuat)
                }
            }
        }
    }

    @ViewBuilder
    private var section2LLM: some View {
        sectionCard(
            number: "2",
            title: "An LLM to write what it sees",
            done: !tellApiKey.isEmpty && !testResult.hasPrefix("❌")
        ) {
            VStack(alignment: .leading, spacing: 10) {
                fieldRow(label: "Endpoint") {
                    TextField("https://…/v1", text: $tellApiBase)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(T.fgPri)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(T.bgDeep)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(T.borderSoft, lineWidth: 0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                fieldRow(label: "Key") {
                    SecureField("sk-…", text: $tellApiKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(T.fgPri)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(T.bgDeep)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(T.borderSoft, lineWidth: 0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                fieldRow(label: "Model") {
                    Picker("", selection: $tellApiModel) {
                        ForEach(modelChoices, id: \.self) { Text($0).tag($0) }
                        Text("Other (\(tellApiModel))").tag("__custom")
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .tint(T.fgPri)
                }
                HStack(spacing: 10) {
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
    }

    @ViewBuilder
    private var section3OpenAI: some View {
        sectionCard(
            number: "3",
            title: "OpenAI key for gbrain embeddings",
            optional: true,
            done: !openaiApiKey.isEmpty
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Without this, gbrain stores your data but can't do vector search (keyword search still works).")
                    .font(.system(size: 12)).foregroundColor(T.fgSec)
                fieldRow(label: "Key") {
                    SecureField("sk-…", text: $openaiApiKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(T.fgPri)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(T.bgDeep)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(T.borderSoft, lineWidth: 0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Skip for now") {
                UserDefaults.standard.set(true, forKey: "didDismissFirstSetup")
                isPresented = false
            }
            .buttonStyle(SecondaryGhostButtonStyle())

            Spacer()

            Button(canFinish ? "I'm ready" : "Finish required items above") {
                UserDefaults.standard.set(true, forKey: "didDismissFirstSetup")
                isPresented = false
            }
            .buttonStyle(PrimaryGreenButtonStyle())
            .disabled(!canFinish)
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
        .overlay(alignment: .top) {
            Rectangle().fill(T.borderSoft).frame(height: 0.5)
        }
    }

    // MARK: - sub-bits

    @ViewBuilder
    private func sectionCard<Content: View>(
        number: String,
        title: String,
        optional: Bool = false,
        done: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(done ? T.accent : T.borderStrong, lineWidth: 1)
                        .background(Circle().fill(done ? T.accent.opacity(0.15) : T.bgElev))
                        .frame(width: 22, height: 22)
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(T.accent)
                    } else {
                        Text(number)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(T.fgSec)
                    }
                }
                Text(title)
                    .font(T.ui(13.5, weight: .semibold))
                    .foregroundColor(T.fgPri)
                if optional {
                    Text("optional")
                        .font(T.mono(9.5, weight: .medium))
                        .foregroundColor(T.fgTer)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(T.bgElev))
                }
                Spacer()
            }
            content()
                .padding(.leading, 32)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: T.rCard).fill(T.bgElev))
        .overlay(RoundedRectangle(cornerRadius: T.rCard).stroke(T.borderSoft, lineWidth: 0.5))
    }

    @ViewBuilder
    private func fieldRow<Content: View>(label: String,
                                          @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(label.uppercased())
                .font(T.ui(10, weight: .semibold))
                .tracking(1.4)
                .foregroundColor(T.fgTer)
                .frame(width: 70, alignment: .trailing)
            content()
        }
    }

    // MARK: - permission + test

    private func checkScreenPermission() {
        screenPermissionGranted = CGPreflightScreenCaptureAccess()
    }

    private func startPolling() {
        permPollTask?.cancel()
        permPollTask = Task { @MainActor in
            // poll every 2s for permission flips while sheet is open
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                let now = CGPreflightScreenCaptureAccess()
                if now != screenPermissionGranted {
                    screenPermissionGranted = now
                }
            }
        }
    }

    private func openScreenRecordingPrefs() {
        // Trigger the permission prompt (one-shot) so the app appears in the list
        _ = CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
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
                let snippet = String(data: data.prefix(100), encoding: .utf8) ?? ""
                testResult = "❌ HTTP \(code): \(snippet.prefix(60))"
            }
        } catch {
            testResult = "❌ \(error.localizedDescription.prefix(60))"
        }
    }
}

// MARK: - shared button style (matches Tell theme)

struct SoftButtonStyle: ButtonStyle {
    var primary: Bool = false
    var secondary: Bool = false
    @State private var hover = false

    func makeBody(configuration: Configuration) -> some View {
        let bg: Color = primary ? T.accent.opacity(configuration.isPressed ? 0.7 : 1)
                      : hover ? T.bgHover
                      : T.bgElev
        let fg: Color = primary ? .black
                      : secondary ? T.fgSec
                      : T.fgPri
        return configuration.label
            .font(.system(size: 12, weight: primary ? .semibold : .medium))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(bg))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(T.borderSoft, lineWidth: 0.5))
            .foregroundColor(fg)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onHover { hover = $0 }
    }
}

#Preview {
    SetupSheet(isPresented: .constant(true))
}
