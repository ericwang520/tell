//
//  SetupSheet.swift — first-launch onboarding (2-item checklist, Tell voice)
//

import SwiftUI
import AppKit
import CoreGraphics

struct SetupSheet: View {
    @Binding var isPresented: Bool

    @AppStorage(TellSettings.kTellApiBase)  private var tellApiBase: String = "https://hnd1.aihub.zeabur.ai/v1"
    @AppStorage(TellSettings.kTellApiKey)   private var tellApiKey: String = ""
    @AppStorage(TellSettings.kTellApiModel) private var tellApiModel: String = "claude-haiku-4-5"

    @State private var screenPermissionGranted: Bool = false
    @State private var testResult: String = ""
    @State private var testing: Bool = false

    private let knownModels = [
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
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            Divider().background(T.borderSoft)
            footer
        }
        .frame(width: 540, height: 520)
        .background(T.bg)
        .preferredColorScheme(.dark)
        .onAppear { checkScreenPermission() }
    }

    // MARK: - header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle().fill(T.accent).frame(width: 7, height: 7)
                .shadow(color: T.accent.opacity(0.55), radius: 4)
            VStack(alignment: .leading, spacing: 4) {
                Text("tell.").font(T.serif(20)).foregroundColor(T.fgPri)
                Text("Tell needs two things to watch your day.")
                    .font(T.mono(11.5))
                    .foregroundColor(T.fgTer)
            }
            Spacer()
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
    }

    // MARK: - section 1: permission

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
                            .buttonStyle(PrimaryGreenButtonStyle())
                        Button("Re-check") { checkScreenPermission() }
                            .buttonStyle(SecondaryGhostButtonStyle())
                    }
                    Text("After granting, click Re-check (or relaunch Tell).")
                        .font(.system(size: 10.5)).foregroundColor(T.fgQuat)
                }
            }
        }
    }

    // MARK: - section 2: LLM

    @ViewBuilder
    private var section2LLM: some View {
        sectionCard(
            number: "2",
            title: "An LLM to write what it sees",
            done: !tellApiKey.isEmpty && !testResult.hasPrefix("❌")
        ) {
            VStack(alignment: .leading, spacing: 10) {
                fieldRow(label: "Endpoint") {
                    plainInput($tellApiBase, placeholder: "https://…/v1")
                }
                fieldRow(label: "Key") {
                    secureInput($tellApiKey, placeholder: "sk-…")
                }
                fieldRow(label: "Model") {
                    HStack(spacing: 6) {
                        Menu {
                            ForEach(knownModels, id: \.self) { m in
                                Button(m) { tellApiModel = m }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 9))
                                Text("Presets")
                                    .font(T.ui(11, weight: .medium))
                            }
                            .foregroundColor(T.fgSec)
                            .padding(.horizontal, 8)
                            .frame(height: 26)
                            .background(T.bgElev)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(T.borderSoft, lineWidth: 0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        plainInput($tellApiModel, placeholder: "claude-haiku-4-5")
                    }
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

    // MARK: - footer

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
    }

    // MARK: - reusable bits

    @ViewBuilder
    private func sectionCard<Content: View>(
        number: String,
        title: String,
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

    private func plainInput(_ binding: Binding<String>, placeholder: String) -> some View {
        TextField(placeholder, text: binding)
            .textFieldStyle(.plain)
            .font(T.mono(12))
            .foregroundColor(T.fgPri)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(T.bgDeep)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(T.borderSoft, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func secureInput(_ binding: Binding<String>, placeholder: String) -> some View {
        SecureField(placeholder, text: binding)
            .textFieldStyle(.plain)
            .font(T.mono(12))
            .foregroundColor(T.fgPri)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(T.bgDeep)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(T.borderSoft, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - permission + test

    private func checkScreenPermission() {
        screenPermissionGranted = CGPreflightScreenCaptureAccess()
    }

    private func openScreenRecordingPrefs() {
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

#Preview {
    SetupSheet(isPresented: .constant(true))
}
