//
//  PopoverView.swift — slim 380-wide menu bar popover
//  Spec: tell-popover-slim.jsx + tokens-d.css + tokens-surfaces.css
//

import SwiftUI
import AppKit
import CoreGraphics

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
            topbar
            rangeRow
            gbrainStrip
            heroCard
            if needsSetup {
                Spacer(minLength: 0)
            } else {
                sectionHead
                topAppRows
                Spacer(minLength: 0)
            }
            footer
        }
        .frame(width: 380, height: 540)
        .background(T.bg)
        .preferredColorScheme(.dark)
        .onAppear {
            store.reload(range: range)
            store.refreshGbrainStats()
            withAnimation(.easeInOut(duration: 2.2).repeatForever()) { pulse.toggle() }
            if needsSetup && !alreadyDismissedSetup { showSetup = true }
        }
        .onChange(of: range) { store.reload(range: range) }
        .sheet(isPresented: $showSetup) { SetupSheet(isPresented: $showSetup) }
    }

    // ── Wordmark — italic serif + orange period (live dot + sub) ──

    private var wordmark: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle()
                    .fill(daemon.running ? T.accent : T.fgQuat)
                    .frame(width: 6, height: 6)
                    .shadow(color: T.accent.opacity(0.55), radius: 5)
                    .opacity(pulse ? 0.6 : 1)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                ( Text("tell").font(T.serif(17, italic: true)).foregroundColor(T.fgPri)
                + Text(".").font(T.serif(19, italic: true)).foregroundColor(T.period) )
            }
            Text("watching · \(store.rangeText)")
                .font(T.mono(10.5))
                .foregroundColor(T.fgTer)
                .textCase(.lowercase)
        }
    }

    private var topbar: some View {
        HStack {
            wordmark
            Spacer()
            iconBtn(daemon.running ? "pause" : "play.fill") {
                daemon.running ? daemon.stop() : daemon.startIfNeeded()
            }
            iconBtn(store.refreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise") {
                store.refreshFromCLI(range: range)
            }
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(T.borderSoft).frame(height: 0.5)
        }
    }

    private func iconBtn(_ sym: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: sym)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(T.fgTer)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(HoverIconButtonStyle())
    }

    // ── Range pills row ──

    private var rangeRow: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                ForEach(RangeKey.allCases, id: \.self) { k in
                    rangePill(k)
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: T.rChip)
                    .fill(T.bgDeep)
                    .overlay(
                        RoundedRectangle(cornerRadius: T.rChip)
                            .stroke(T.borderSoft, lineWidth: 0.5)
                    )
            )
            Spacer()
            Text("upd \(store.refreshedAt)")
                .font(T.mono(9.5))
                .foregroundColor(T.fgTer)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func rangePill(_ k: RangeKey) -> some View {
        let active = (range == k)
        return Button {
            range = k
        } label: {
            HStack(spacing: 6) {
                if k == .pastHour {
                    Circle()
                        .fill(T.accent)
                        .frame(width: 5, height: 5)
                        .shadow(color: T.accent.opacity(0.5), radius: 3)
                        .opacity(active && pulse ? 0.55 : 1)
                }
                Text(k.label)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(active ? T.fgPri : T.fgSec)
            }
            .padding(.horizontal, 11)
            .frame(height: 24)
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
                    }
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // ── gbrain status strip ──

    private var gbrainStrip: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 10))
                    .foregroundColor(T.fgTer)
                Text(brainStripText)
                    .font(T.mono(9.5))
                    .foregroundColor(T.fgTer)
            }
            Spacer()
            if !store.totalActive.isEmpty {
                Text("\(store.totalActive) · \(store.apps.count) apps")
                    .font(T.mono(9.5))
                    .foregroundColor(T.fgTer)
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8).fill(T.bgDeep.opacity(0.5))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(T.borderSoft, lineWidth: 0.5))
        )
        .padding(.horizontal, 14).padding(.bottom, 12)
    }

    private var brainStripText: AttributedString {
        var s = AttributedString()
        var append: (String, Color) -> Void = { txt, c in
            var part = AttributedString(txt)
            part.foregroundColor = c
            s += part
        }
        append("\(store.gbrainPages)", T.fgPri); append("p · ", T.fgTer)
        append("\(store.gbrainChunks)", T.fgPri); append("c · ", T.fgTer)
        append("\(store.gbrainEmbedded)", T.fgPri); append("e", T.fgTer)
        if !store.gbrainLastSync.isEmpty {
            append("  ·  synced \(store.gbrainLastSync)", T.fgQuat)
        }
        return s
    }

    // ── Hero card ──

    private var heroCard: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(T.warn).frame(width: 2)
                .shadow(color: T.warn.opacity(0.3), radius: 4)
            VStack(alignment: .leading, spacing: 6) {
                if needsSetup && store.overall.isEmpty {
                    setupHeroBody
                } else {
                    Text("TELL · \(range.label.uppercased())")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.6).foregroundColor(T.warn)
                    if store.refreshing && store.overall.isEmpty {
                        heroSkeleton
                    } else if !store.overall.isEmpty {
                        heroAttributed(store.overall)
                            .font(T.serif(14.5))
                            .foregroundColor(T.fgPri)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Press ↻ to ask Tell for an honest read.")
                            .font(T.serif(13.5))
                            .foregroundColor(T.fgSec)
                    }
                    HStack {
                        Text("\(store.richGeneratedAt.isEmpty ? store.refreshedAt : store.richGeneratedAt)  ·  \(store.richModel.isEmpty ? "qwen2.5:7b" : store.richModel)")
                            .font(T.mono(9.5))
                            .foregroundColor(T.fgQuat)
                        Spacer()
                        if !store.totalActive.isEmpty {
                            Text("\(store.totalActive) · \(store.apps.count) apps")
                                .font(T.mono(9.5))
                                .foregroundColor(T.fgQuat)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
        .background(
            ZStack {
                T.bgHero
                LinearGradient(
                    colors: [T.warn.opacity(0.05), .clear],
                    startPoint: .topLeading, endPoint: .center
                )
            }
        )
        .overlay(RoundedRectangle(cornerRadius: T.rCard).stroke(T.border, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: T.rCard))
        .padding(.horizontal, 14).padding(.bottom, 12)
    }

    @ViewBuilder
    private var setupHeroBody: some View {
        Text("TELL · SETUP NEEDED")
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.6).foregroundColor(T.warn)
        Text("Tell isn't configured yet.")
            .font(T.serif(14.5))
            .foregroundColor(T.fgPri)
        Text("No LLM key or screen permission — capture is blocked.")
            .font(T.serif(12.5))
            .foregroundColor(T.fgSec)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 2)
        Button {
            showSetup = true
        } label: {
            HStack(spacing: 6) {
                Text("Set up Tell")
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .semibold))
            }
        }
        .buttonStyle(PrimaryGreenButtonStyle())
        .padding(.top, 6)
    }

    @ViewBuilder
    private var heroSkeleton: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach([0.92, 0.75, 0.50], id: \.self) { w in
                Rectangle()
                    .fill(LinearGradient(
                        colors: [T.fgPri.opacity(0.04), T.fgPri.opacity(0.10), T.fgPri.opacity(0.04)],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(height: 14)
                    .frame(maxWidth: .infinity * w, alignment: .leading)
                    .cornerRadius(4)
            }
        }
        .padding(.top, 4)
    }

    /// Build a Text with mono "chips" for ⟨...⟩ ranges (warn coloured, semibold mono).
    private func heroAttributed(_ s: String) -> Text {
        var out = Text("")
        var buf = ""
        var inMark = false
        func flushPlain() {
            if !buf.isEmpty {
                out = out + Text(buf).foregroundColor(T.fgPri)
                buf.removeAll()
            }
        }
        func flushChip() {
            if !buf.isEmpty {
                out = out + Text(buf)
                    .foregroundColor(T.warn)
                    .fontWeight(.semibold)
                    .font(T.mono(13.5, weight: .semibold))
                buf.removeAll()
            }
        }
        for ch in s {
            if ch == "⟨" { flushPlain(); inMark = true; continue }
            if ch == "⟩" { flushChip(); inMark = false; continue }
            buf.append(ch)
        }
        if inMark { flushChip() } else { flushPlain() }
        return out
    }

    // ── Section head ──

    private var sectionHead: some View {
        HStack(alignment: .lastTextBaseline) {
            Text("TOP APPS")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.5)
                .foregroundColor(T.fgTer)
            Spacer()
            Text("\(min(4, store.apps.count)) of \(store.apps.count)")
                .font(T.mono(10.5))
                .foregroundColor(T.fgQuat)
        }
        .padding(.horizontal, 14).padding(.bottom, 8)
    }

    // ── Top app rows (poprow) ──

    private var topAppRows: some View {
        let top = Array(store.apps.prefix(4))
        return VStack(spacing: 0) {
            ForEach(top) { app in
                popRow(app)
            }
            if top.isEmpty {
                Text("No activity captured yet — daemon is collecting…")
                    .font(.system(size: 11)).italic()
                    .foregroundColor(T.fgTer)
                    .padding(.horizontal, 14).padding(.vertical, 8)
            }
        }
    }

    private func popRow(_ a: AppActivity) -> some View {
        HStack(spacing: 10) {
            appIcon(name: a.name, size: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 1) {
                Text(a.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(T.fgPri)
                if !a.summary.isEmpty {
                    Text(a.summary)
                        .font(T.serif(11.5))
                        .foregroundColor(T.fgSec)
                        .lineLimit(1)
                } else if !a.sessions.isEmpty, let first = a.sessions.first?.title, !first.isEmpty {
                    Text(first)
                        .font(T.serif(11.5))
                        .foregroundColor(T.fgSec)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Text(durStr(a.totalSeconds))
                .font(T.mono(11.5, weight: .semibold))
                .foregroundColor(a.drift ? T.warn : T.fgPri)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(HoverBackgroundStyle(color: T.bgElev))
        .contentShape(Rectangle())
    }

    private func durStr(_ s: Int) -> String {
        if s < 60 { return "\(s)s" }
        let m = s / 60
        if m < 60 { return "\(m)m" }
        return String(format: "%dh %02dm", m / 60, m % 60)
    }

    // ── Footer ──

    private var footer: some View {
        HStack(spacing: 8) {
            if needsSetup {
                Button { showSetup = true } label: {
                    Text("Set up Tell")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryGreenButtonStyle(fill: true))
                iconBtn("gearshape") { openPrefs() }
            } else {
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                } label: {
                    HStack(spacing: 6) {
                        Text("Open Tell")
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                }
                .buttonStyle(PrimaryGreenButtonStyle())
                iconBtn("gearshape") { openPrefs() }
                Spacer()
                Button("Speak it") {
                    // future TTS hook — wired to gateway later
                }
                .buttonStyle(SecondaryGhostButtonStyle())
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .overlay(alignment: .top) {
            Rectangle().fill(T.borderSoft).frame(height: 0.5)
        }
    }

    private func openPrefs() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}

// MARK: - Reusable button styles (Tell-themed)

struct PrimaryGreenButtonStyle: ButtonStyle {
    var fill: Bool = false  // expand to fill width
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundColor(T.accentInk)
            .padding(.horizontal, 14)
            .frame(height: 28)
            .frame(maxWidth: fill ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed ? T.accent : T.accentDim)
            )
            .contentShape(Rectangle())
    }
}

struct SecondaryGhostButtonStyle: ButtonStyle {
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(hover ? T.fgPri : T.fgSec)
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hover ? T.bgElev : Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(T.border, lineWidth: 0.5))
            )
            .contentShape(Rectangle())
            .onHover { hover = $0 }
    }
}

struct HoverIconButtonStyle: ButtonStyle {
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hover ? T.bgElev : Color.clear)
            )
            .onHover { hover = $0 }
    }
}

struct HoverBackgroundStyle: View {
    let color: Color
    @State private var hover = false
    var body: some View {
        Rectangle().fill(hover ? color : Color.clear)
            .onHover { hover = $0 }
    }
}
