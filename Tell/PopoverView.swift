//
//  PopoverView.swift — concise menu bar popover
//  (full dashboard lives in MainWindow)
//

import SwiftUI
import AppKit

struct PopoverView: View {
    @StateObject var store = ActivityStore()
    @EnvironmentObject var daemon: DaemonController
    @Environment(\.openWindow) private var openWindow

    @State private var range: RangeKey = .pastHour
    @State private var pulse = false
    @State private var showSetup = false

    private var needsSetup: Bool {
        TellSettings.shared.tellApiKey.isEmpty
            || !CGPreflightScreenCaptureAccess()
    }
    private var alreadyDismissedSetup: Bool {
        UserDefaults.standard.bool(forKey: "didDismissFirstSetup")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(T.borderSoft).frame(height: 0.5)
            rangePicker
            statusStrip
            heroCard
            topAppsCompact
            Spacer(minLength: 0)
            footer
        }
        .frame(width: 380, height: 540)
        .background(T.bg)
        .preferredColorScheme(.dark)
        .onAppear {
            store.reload(range: range)
            store.refreshGbrainStats()
            withAnimation(.easeInOut(duration: 2.2).repeatForever()) { pulse.toggle() }
            // First-launch onboarding
            if needsSetup && !alreadyDismissedSetup {
                showSetup = true
            }
        }
        .onChange(of: range) { store.reload(range: range) }
        .sheet(isPresented: $showSetup) {
            SetupSheet(isPresented: $showSetup)
        }
    }

    // MARK: - header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(daemon.running ? T.accent : T.fgQuat)
                .frame(width: 6, height: 6)
                .shadow(color: T.accent.opacity(0.55), radius: 3)
                .opacity(pulse ? 0.6 : 1)
            Image("TellWordmark")
                .resizable()
                .scaledToFit()
                .frame(height: 18)
            Text(store.rangeText)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(T.fgTer)
            Spacer()
            iconBtn(daemon.running ? "pause.circle" : "play.circle") {
                daemon.running ? daemon.stop() : daemon.startIfNeeded()
            }
            iconBtn(store.refreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise") {
                store.refreshFromCLI(range: range)
            }
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 10)
    }

    private func iconBtn(_ s: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: s)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(T.fgTer)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
    }

    // MARK: - range picker (compact 3-pill)

    private var rangePicker: some View {
        HStack(spacing: 4) {
            ForEach(RangeKey.allCases, id: \.self) { k in
                Button {
                    range = k
                } label: {
                    Text(k.label)
                        .font(.system(size: 11.5, weight: range == k ? .semibold : .regular))
                        .foregroundColor(range == k ? T.fgPri : T.fgSec)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(range == k ? T.bgElev2 : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(range == k ? T.borderStrong : Color.clear,
                                                lineWidth: 0.5)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("upd \(store.refreshedAt)")
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundColor(T.fgQuat)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    // MARK: - status strip

    private var statusStrip: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 10)).foregroundColor(T.fgTer)
            Text("\(store.gbrainPages)p · \(store.gbrainChunks)c · \(store.gbrainEmbedded)e")
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundColor(T.fgTer)
            if !store.gbrainLastSync.isEmpty {
                Text("· \(store.gbrainLastSync)")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(T.fgQuat)
            }
            Spacer()
            if !store.totalActive.isEmpty {
                Text("\(store.totalActive) · \(store.apps.count) apps")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(T.fgQuat)
            }
        }
        .padding(.horizontal, 14).padding(.bottom, 8)
    }

    // MARK: - hero

    private var heroCard: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(T.warn).frame(width: 2)
            VStack(alignment: .leading, spacing: 6) {
                Text("TELL · \(range.label.uppercased())")
                    .font(.system(size: 9.5, weight: .semibold)).tracking(1.4)
                    .foregroundColor(T.warn)
                if needsSetup && store.overall.isEmpty {
                    emptyStateBody
                } else if !store.overall.isEmpty {
                    highlighted(store.overall)
                        .font(.system(size: 13))
                        .italic()
                        .foregroundColor(T.fgPri)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(store.refreshing ? "Generating…" : "Press ↻ to ask Tell for an honest read.")
                        .font(.system(size: 12))
                        .foregroundColor(T.fgSec)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
        .background(T.bgHero)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(T.border, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 14).padding(.bottom, 10)
    }

    @ViewBuilder
    private var emptyStateBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tell isn't configured yet.")
                .font(.system(size: 13)).foregroundColor(T.fgPri)
            Text("No LLM key or screen permission — capture is blocked.")
                .font(.system(size: 11)).foregroundColor(T.fgSec)
            Button("Set up Tell →") { showSetup = true }
                .buttonStyle(SoftButtonStyle(primary: true))
                .padding(.top, 4)
        }
    }

    /// Render text with ⟨...⟩ runs in warn color.
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
                inMark = true; continue
            }
            if ch == "⟩" {
                if !buf.isEmpty {
                    out = out + Text(buf).foregroundColor(T.warn).fontWeight(.semibold)
                    buf.removeAll()
                }
                inMark = false; continue
            }
            buf.append(ch)
        }
        if !buf.isEmpty {
            out = out + Text(buf).foregroundColor(inMark ? T.warn : T.fgPri)
        }
        return out
    }

    // MARK: - top apps compact

    private var topAppsCompact: some View {
        let top = Array(store.apps.prefix(4))
        return VStack(alignment: .leading, spacing: 6) {
            Text("TOP APPS").font(.system(size: 9.5, weight: .semibold)).tracking(1.4)
                .foregroundColor(T.fgTer)
                .padding(.horizontal, 14)
            VStack(spacing: 4) {
                ForEach(top) { a in compactAppRow(a) }
                if top.isEmpty {
                    Text("No activity yet — daemon is collecting…")
                        .font(.system(size: 11)).foregroundColor(T.fgTer)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                }
            }
        }
    }

    private func compactAppRow(_ a: AppActivity) -> some View {
        HStack(spacing: 10) {
            appIcon(name: a.name, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(a.name)
                    .font(.system(size: 12, weight: .medium)).foregroundColor(T.fgPri)
                if !a.summary.isEmpty {
                    Text(a.summary)
                        .font(.system(size: 10.5)).italic()
                        .foregroundColor(T.fgSec).lineLimit(1)
                }
            }
            Spacer()
            Text(durStr(a.totalSeconds))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(a.drift ? T.warn : T.fgPri)
        }
        .padding(.horizontal, 14).padding(.vertical, 4)
    }

    private func durStr(_ s: Int) -> String {
        if s < 60 { return "\(s)s" }
        let m = s / 60
        if m < 60 { return "\(m)m" }
        return String(format: "%dh %02dm", m / 60, m % 60)
    }

    // MARK: - footer

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(T.borderSoft).frame(height: 0.5)
            HStack(spacing: 8) {
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                } label: {
                    HStack(spacing: 4) {
                        Text("Open Dashboard")
                        Image(systemName: "arrow.up.right")
                    }
                }
                .buttonStyle(SoftButtonStyle(primary: true))
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    if #available(macOS 14.0, *) {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    } else {
                        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                    }
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(SoftButtonStyle())
                Spacer()
                Button("Quit Tell") { NSApp.terminate(nil) }
                    .buttonStyle(SoftButtonStyle(secondary: true))
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
    }
}
