//
//  MainWindow.swift — full Tell dashboard window (sidebar + detail)
//

import SwiftUI
import AppKit

enum WindowSection: String, CaseIterable, Identifiable {
    case dashboard, logs, brain, settings
    var id: String { rawValue }
    var label: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .logs:      return "Daemon logs"
        case .brain:     return "gbrain"
        case .settings:  return "Settings"
        }
    }
    var symbol: String {
        switch self {
        case .dashboard: return "rectangle.grid.2x2"
        case .logs:      return "terminal"
        case .brain:     return "brain.head.profile"
        case .settings:  return "gearshape"
        }
    }
}

struct MainWindow: View {
    @EnvironmentObject var daemon: DaemonController
    @State private var section: WindowSection = .dashboard
    @State private var pulse: Bool = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            detail
                .background(T.bg)
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 920, minHeight: 640)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever()) { pulse.toggle() }
        }
    }

    // ── Sidebar (per tell-main-window.jsx + tokens-surfaces.css) ──

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Brand: pulsing dot + serif italic 'tell' + orange period
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Circle()
                    .fill(daemon.running ? T.accent : T.fgQuat)
                    .frame(width: 7, height: 7)
                    .shadow(color: T.accent.opacity(0.55), radius: 5)
                    .opacity(pulse ? 0.6 : 1)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                ( Text("tell").font(T.serif(18)).foregroundColor(T.fgPri)
                + Text(".").font(T.serif(19)).foregroundColor(T.period) )
                Spacer()
            }
            .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 18)

            // Nav rows
            VStack(spacing: 1) {
                ForEach(WindowSection.allCases) { item in
                    sidebarRow(item)
                }
            }
            .padding(.horizontal, 8)

            Spacer()

            // Footer: live dot + daemon line + last log
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(daemon.running ? T.accent : T.fgQuat)
                        .frame(width: 6, height: 6)
                        .shadow(color: T.accent.opacity(0.5), radius: 3)
                        .opacity(pulse ? 0.6 : 1)
                    Text(daemon.running ? "daemon · pid \(daemon.pid)" : "daemon stopped")
                        .font(T.mono(10))
                        .foregroundColor(T.fgTer)
                }
                if !daemon.lastLog.isEmpty {
                    Text(daemon.lastLog.prefix(80))
                        .font(T.mono(9.5))
                        .foregroundColor(T.fgQuat)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) {
                Rectangle().fill(T.borderSoft).frame(height: 0.5)
            }
        }
        .background(T.bgDeep)
    }

    private func sidebarRow(_ item: WindowSection) -> some View {
        Button {
            section = item
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.symbol)
                    .font(.system(size: 12))
                    .opacity(0.85)
                    .frame(width: 16)
                Text(item.label)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .foregroundColor(section == item ? T.fgPri : T.fgSec)
            .background(
                RoundedRectangle(cornerRadius: T.rBtn)
                    .fill(section == item ? T.bgElev2 : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(SidebarRowHoverStyle())
    }

    @ViewBuilder
    private var detail: some View {
        Group {
            switch section {
            case .dashboard: DashboardView().environmentObject(daemon)
            case .logs:      LogsView().environmentObject(daemon)
            case .brain:     GbrainView().environmentObject(daemon)
            case .settings:  SettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(T.bg)
    }
}

// MARK: - Hover styles

struct SidebarRowHoverStyle: ButtonStyle {
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: T.rBtn)
                    .fill(hover && !configuration.isPressed ? T.bgElev : Color.clear)
            )
            .onHover { hover = $0 }
    }
}

// MARK: - Logs view

struct LogsView: View {
    @EnvironmentObject var daemon: DaemonController
    @State private var autoScroll: Bool = true
    @State private var filter: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(T.borderSoft)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filtered.indices, id: \.self) { i in
                            row(filtered[i])
                                .id(i)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: filtered.count) {
                    if autoScroll, filtered.count > 0 {
                        proxy.scrollTo(filtered.count - 1, anchor: .bottom)
                    }
                }
                .onAppear {
                    if filtered.count > 0 {
                        proxy.scrollTo(filtered.count - 1, anchor: .bottom)
                    }
                }
            }
        }
        .background(T.bg)
    }

    private var filtered: [String] {
        if filter.isEmpty { return daemon.logs }
        let f = filter.lowercased()
        return daemon.logs.filter { $0.lowercased().contains(f) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Daemon logs")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(T.fgPri)
            Text("\(filtered.count)/\(daemon.logs.count) lines")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundColor(T.fgTer)
            Spacer()
            TextField("Filter", text: $filter)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundColor(T.fgPri)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .frame(width: 200)
                .background(T.bgDeep)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(T.borderSoft, lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Toggle("Auto-scroll", isOn: $autoScroll)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundColor(T.fgSec)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(daemon.logs.joined(separator: "\n"),
                                                forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(SoftButtonStyle())
            .help("Copy all logs")
            Button {
                daemon.logs.removeAll()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(SoftButtonStyle(secondary: true))
            .help("Clear log buffer (in-memory only)")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func row(_ line: String) -> some View {
        let isErr = line.contains("error") || line.contains("ERROR") || line.contains("❌")
        let isWarn = line.contains("WARN") || line.contains("⚠")
        let isInfo = line.hasPrefix("[tell-daemon]")
        let color: Color = isErr ? T.warn
                         : isWarn ? T.warn.opacity(0.7)
                         : isInfo ? T.fgSec
                         : T.fgTer
        return Text(line)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(color)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 1)
    }
}

// MARK: - gbrain view

struct GbrainView: View {
    @EnvironmentObject var daemon: DaemonController
    @StateObject private var store = ActivityStore()
    @State private var query: String = ""
    @State private var results: [(score: String, slug: String, snippet: String)] = []
    @State private var searching: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(T.borderSoft)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    statsCard
                    searchCard
                }
                .padding(20)
            }
        }
        .background(T.bg)
        .onAppear { store.refreshGbrainStats() }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile").foregroundColor(T.fgSec)
                Text("gbrain")
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(T.fgPri)
            }
            Spacer()
            Button(store.gbrainSyncing ? "Syncing…" : "Sync now") {
                store.gbrainSyncManually()
            }
            .buttonStyle(SoftButtonStyle(primary: true))
            .disabled(store.gbrainSyncing)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BRAIN STATE").font(.system(size: 10, weight: .semibold)).tracking(1.5)
                .foregroundColor(T.fgTer)
            HStack(spacing: 30) {
                statTile(label: "Pages",    value: "\(store.gbrainPages)")
                statTile(label: "Chunks",   value: "\(store.gbrainChunks)")
                statTile(label: "Embedded", value: "\(store.gbrainEmbedded)")
                statTile(label: "Last sync",
                         value: store.gbrainLastSync.isEmpty ? "—" : store.gbrainLastSync)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(T.bgElev))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(T.borderSoft, lineWidth: 0.5))
    }

    private func statTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(T.fgTer)
            Text(value).font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundColor(T.fgPri)
        }
    }

    private var searchCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SEARCH BRAIN").font(.system(size: 10, weight: .semibold)).tracking(1.5)
                .foregroundColor(T.fgTer)
            HStack {
                TextField("e.g. Twitter, OCR, PickTrip…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(T.fgPri)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(T.bgDeep)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(T.borderSoft, lineWidth: 0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onSubmit { Task { await runSearch() } }
                Button(searching ? "…" : "Search") {
                    Task { await runSearch() }
                }
                .buttonStyle(SoftButtonStyle())
                .disabled(searching || query.isEmpty)
            }
            if results.isEmpty && !query.isEmpty && !searching {
                Text("No results.")
                    .font(.system(size: 11.5)).foregroundColor(T.fgTer)
                    .padding(.top, 6)
            }
            ForEach(results.indices, id: \.self) { i in
                let r = results[i]
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(r.slug)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(T.fgPri)
                        Spacer()
                        Text(r.score)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(T.fgTer)
                    }
                    Text(r.snippet)
                        .font(.system(size: 11.5))
                        .foregroundColor(T.fgSec)
                        .lineLimit(3)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(T.bgDeep))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(T.bgElev))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(T.borderSoft, lineWidth: 0.5))
    }

    private func runSearch() async {
        searching = true; defer { searching = false }
        results = []
        let bin = TellSettings.shared.gbrainBinPath
        let env = TellSettings.shared.subprocessEnv
        let q = query
        let raw: String = await Task.detached(priority: .userInitiated) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: bin)
            p.arguments = ["search", q]
            p.environment = env
            let outPipe = Pipe(); p.standardOutput = outPipe
            p.standardError = Pipe()
            do { try p.run() } catch { return "" }
            p.waitUntilExit()
            let d = outPipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: d, encoding: .utf8) ?? ""
        }.value
        // parse lines like: [0.3744] screen/2026-05-16 -- snippet text...
        let pattern = #"^\[([\d\.]+)\]\s+(\S+)\s+--\s+(.+)$"#
        let regex = try? NSRegularExpression(pattern: pattern)
        var parsed: [(String, String, String)] = []
        for line in raw.split(separator: "\n") {
            let s = String(line)
            if let r = regex?.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) {
                func grp(_ i: Int) -> String {
                    guard let rr = Range(r.range(at: i), in: s) else { return "" }
                    return String(s[rr])
                }
                parsed.append((grp(1), grp(2), grp(3)))
            }
        }
        results = parsed
    }
}
