//
//  PopoverView.swift — Working menu bar popover (380 × 540) per Style D
//  Spec: tell-popover-slim.jsx + tokens-d.css + tokens-surfaces.css
//

import SwiftUI
import AppKit
import Combine

struct PopoverView: View {
    @EnvironmentObject var store: ActivityStore  // SHARED across popover + main window
    @EnvironmentObject var daemon: DaemonController
    @Environment(\.openWindow) private var openWindow

    @State private var pulse = false
    /// Hard floor between two LLM hero fetches — closing and re-opening the
    /// popover within this window will NOT trigger a new tell-rich call.
    private let aiCacheTTL: TimeInterval = 300  // 5 minutes
    /// Fast tick (every 5s): re-parse markdown + gbrain stats — cheap, no LLM.
    private let tick = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    /// Slow tick (every 5 min): re-fire tell-rich so the hero LLM stays current.
    private let aiTick = Timer.publish(every: 300, on: .main, in: .common).autoconnect()

    /// Convenience accessor — range lives on the shared store, so changing
    /// it in the dashboard also changes it here and vice versa.
    private var range: RangeKey { store.range }

    var body: some View {
        VStack(spacing: 0) {
            header  // pinned top
            ScrollView {
                VStack(spacing: 0) {
                    rangeRow
                    gbrainStrip
                    heroCard
                    sectionHead
                    topAppRows
                    Spacer(minLength: 0)
                }
            }
            .scrollIndicators(.hidden)
        }
        .frame(width: 380, height: 540)
        .background(T.bg)
        .preferredColorScheme(.dark)
        .onAppear {
            store.reload(range: range)
            store.refreshGbrainStats()
            // Shared cache — if the main window already fetched this range
            // within 5 min, the popover reuses store.overall directly.
            if !store.aiCacheFresh(for: range, ttl: aiCacheTTL) {
                store.refreshFromCLI(range: range)
                store.markAIFetched(for: range)
            }
            withAnimation(.easeInOut(duration: 2.2).repeatForever()) { pulse.toggle() }
        }
        .onReceive(tick) { _ in
            store.reload(range: range)
            store.refreshGbrainStats()
        }
        .onReceive(aiTick) { _ in
            store.refreshFromCLI(range: range)
            store.markAIFetched(for: range)
        }
    }

    // MARK: - header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(daemon.running ? T.accent : T.fgQuat)
                .frame(width: 7, height: 7)
                .shadow(color: T.accent.opacity(0.55), radius: 5)
                .opacity(pulse ? 0.6 : 1)
            Image("TellWordmark")
                .resizable()
                .scaledToFit()
                .frame(height: 17)
            Spacer()
            Text(daemon.running ? "watching" : "paused")
                .font(T.mono(10.5))
                .foregroundColor(daemon.running ? T.accent.opacity(0.85) : T.fgTer)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(T.borderSoft).frame(height: 0.5)
        }
    }

    // MARK: - range pills row

    private var rangeRow: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                ForEach(RangeKey.allCases, id: \.self) { k in rangePill(k) }
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
        return Button { store.setRange(k, aiCacheTTL: aiCacheTTL) } label: {
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
                    }
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - gbrain status strip

    private var gbrainStrip: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 11))
                .foregroundColor(T.fgTer)
            HStack(spacing: 0) {
                Text("\(store.gbrainPages)").foregroundColor(T.fgPri)
                Text("p · ").foregroundColor(T.fgTer)
                Text("\(store.gbrainChunks)").foregroundColor(T.fgPri)
                Text("c · ").foregroundColor(T.fgTer)
                Text("\(store.gbrainEmbedded)").foregroundColor(T.fgPri)
                Text("e").foregroundColor(T.fgTer)
                if !store.gbrainLastSync.isEmpty {
                    Text("  ·  synced \(store.gbrainLastSync)").foregroundColor(T.fgQuat)
                }
            }
            .font(T.mono(9.5))
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

    // MARK: - hero card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TELL · \(range.label.uppercased())")
                .font(.system(size: 10, weight: .semibold)).tracking(1.6)
                .foregroundColor(T.warn)
            if store.refreshing {
                // Shimmering placeholder text — reads as "AI is thinking"
                // (mock content shaped like a real Tell observation).
                TellHeroPlaceholder()
                    .shimmering(bandSize: 0.4)
            } else if !store.overall.isEmpty {
                heroChips(store.overall)
                    .font(T.serif(14.5))
                    .foregroundColor(T.fgPri)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Press ↻ to ask Tell for an honest read.")
                    .font(T.serif(13))
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
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            ZStack {
                T.bgHero
                LinearGradient(
                    colors: [T.warn.opacity(0.05), .clear],
                    startPoint: .topLeading, endPoint: .center
                )
            }
        )
        .overlay(alignment: .leading) {
            Rectangle().fill(T.warn).frame(width: 2)
                .shadow(color: T.warn.opacity(0.3), radius: 4)
        }
        .overlay(RoundedRectangle(cornerRadius: T.rCard).stroke(T.border, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: T.rCard))
        .padding(.horizontal, 14).padding(.bottom, 12)
    }

    @ViewBuilder
    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach([0.92, 0.75, 0.50], id: \.self) { w in
                Rectangle()
                    .fill(LinearGradient(
                        colors: [T.fgPri.opacity(0.05), T.fgPri.opacity(0.12), T.fgPri.opacity(0.05)],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(height: 12)
                    .frame(maxWidth: .infinity * w, alignment: .leading)
                    .cornerRadius(4)
            }
        }
        .padding(.top, 4)
    }

    private func heroChips(_ s: String) -> Text {
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
                    .font(T.mono(13, weight: .semibold))
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

    // MARK: - section head + top apps

    private var sectionHead: some View {
        HStack(alignment: .lastTextBaseline) {
            Text("TOP APPS")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.5)
                .foregroundColor(T.fgTer)
            Spacer()
            Text("\(min(4, store.apps.count)) of \(store.apps.count)")
                .font(T.mono(10))
                .foregroundColor(T.fgQuat)
        }
        .padding(.horizontal, 14).padding(.bottom, 6)
    }

    private var topAppRows: some View {
        let top = Array(store.apps.prefix(4))
        return VStack(spacing: 0) {
            ForEach(top) { app in popRow(app) }
            if top.isEmpty {
                Text("No activity yet — daemon is collecting…")
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
                HStack(spacing: 6) {
                    Text(a.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(T.fgPri)
                    if a.drift {
                        Circle().fill(T.warn).frame(width: 4, height: 4)
                            .shadow(color: T.warn.opacity(0.5), radius: 2)
                    }
                }
                if !a.summary.isEmpty {
                    Text(a.summary)
                        .font(T.serif(11.5))
                        .foregroundColor(T.fgSec)
                        .lineLimit(1)
                } else if let title = a.sessions.first?.title, !title.isEmpty {
                    Text(title)
                        .font(T.serif(11.5))
                        .foregroundColor(T.fgSec)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Text(durStr(a.totalSeconds))
                .font(T.mono(11, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(a.drift ? T.warn : T.fgPri)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func durStr(_ s: Int) -> String {
        if s < 60 { return "\(s)s" }
        let m = s / 60
        if m < 60 { return "\(m)m" }
        return String(format: "%dh %02dm", m / 60, m % 60)
    }

    // MARK: - footer

    // (footer removed — Open Tell / settings / pause / Speak it live elsewhere)
    @available(*, unavailable)
    private var footer: some View {
        HStack(spacing: 8) {
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
            iconBtn(daemon.running ? "pause" : "play.fill") {
                daemon.running ? daemon.stop() : daemon.startIfNeeded()
            }
            Button("Speak it") { speakLatest() }
                .buttonStyle(SecondaryGhostButtonStyle())
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .overlay(alignment: .top) {
            Rectangle().fill(T.borderSoft).frame(height: 0.5)
        }
    }

    private func iconBtn(_ sym: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: sym)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(T.fgSec)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(T.bgElev))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(T.borderSoft, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func openPrefs() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    /// Speak the latest Tell observation via macOS `say` (offline, no key needed).
    private func speakLatest() {
        let text = store.overall.replacingOccurrences(of: "⟨", with: "")
            .replacingOccurrences(of: "⟩", with: "")
        guard !text.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            p.arguments = ["-v", "Samantha", text]
            try? p.run()
        }
    }
}

// MARK: - Shared button styles (used app-wide)

struct PrimaryGreenButtonStyle: ButtonStyle {
    var fill: Bool = false
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
