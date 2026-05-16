//
//  PopoverView.swift — slim menu bar status popover (view-only)
//  Configuration / setup / dashboard all live in the main window.
//

import SwiftUI
import AppKit
import Combine

struct PopoverView: View {
    @StateObject var store = ActivityStore()
    @EnvironmentObject var daemon: DaemonController
    @Environment(\.openWindow) private var openWindow

    @State private var pulse = false
    @State private var tick: Date = Date()
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(T.borderSoft)
            statusBody
            Divider().background(T.borderSoft)
            footer
        }
        .frame(width: 280)
        .background(T.bg)
        .preferredColorScheme(.dark)
        .onAppear {
            store.reload(range: .pastHour)
            store.refreshGbrainStats()
            withAnimation(.easeInOut(duration: 2.2).repeatForever()) { pulse.toggle() }
        }
        .onReceive(timer) { _ in
            tick = Date()
            store.reload(range: .pastHour)
            store.refreshGbrainStats()
        }
    }

    // MARK: - header (wordmark + live dot)

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(daemon.running ? T.accent : T.fgQuat)
                .frame(width: 7, height: 7)
                .shadow(color: T.accent.opacity(0.55), radius: 5)
                .opacity(pulse ? 0.6 : 1)
            Text("tell.")
                .font(T.serif(15))
                .foregroundColor(T.fgPri)
            Spacer()
            Text(daemon.running ? "watching" : "paused")
                .font(T.mono(10))
                .foregroundColor(daemon.running ? T.accent.opacity(0.85) : T.fgTer)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    // MARK: - status body

    private var statusBody: some View {
        VStack(spacing: 0) {
            statusRow(
                icon: "waveform.path.ecg",
                label: "daemon",
                value: daemon.running ? "pid \(daemon.pid)" : "stopped",
                color: daemon.running ? T.fgPri : T.fgTer
            )
            divider
            statusRow(
                icon: "clock",
                label: "tracked",
                value: store.totalActive.isEmpty ? "—" : "\(store.totalActive) · \(store.apps.count) apps",
                color: T.fgPri
            )
            divider
            statusRow(
                icon: "brain.head.profile",
                label: "gbrain",
                value: "\(store.gbrainPages)p · \(store.gbrainChunks)c · \(store.gbrainEmbedded)e",
                color: T.fgPri
            )
            divider
            // last tell observation (one short line)
            if !store.overall.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LAST OBSERVATION")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.4)
                        .foregroundColor(T.warn.opacity(0.85))
                    Text(store.overall)
                        .font(T.serif(12))
                        .foregroundColor(T.fgPri)
                        .lineSpacing(2)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(T.borderSoft).frame(height: 0.5)
    }

    private func statusRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(T.fgTer)
                .frame(width: 14)
            Text(label)
                .font(T.mono(10.5))
                .foregroundColor(T.fgTer)
            Spacer()
            Text(value)
                .font(T.mono(10.5, weight: .semibold))
                .foregroundColor(color)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    // MARK: - footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            } label: {
                HStack(spacing: 5) {
                    Text("Open Tell")
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryGreenButtonStyle(fill: true))
            Button {
                daemon.running ? daemon.stop() : daemon.startIfNeeded()
            } label: {
                Image(systemName: daemon.running ? "pause" : "play.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(T.fgSec)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 6).fill(T.bgElev))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(T.borderSoft, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .help(daemon.running ? "Pause daemon" : "Start daemon")
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(T.fgTer)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 6).fill(T.bgElev))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(T.borderSoft, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .help("Quit Tell")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

// MARK: - Shared button styles (used by popover + setup sheet + settings)

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

