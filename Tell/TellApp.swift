//
//  TellApp.swift — Tell entrypoint: regular macOS app + menu bar status icon
//

import SwiftUI
import AppKit

final class TellAppDelegate: NSObject, NSApplicationDelegate {
    weak var daemon: DaemonController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        TellSettings.shared.ensureDataDirs()
    }

    func applicationWillTerminate(_ notification: Notification) {
        daemon?.stop()
    }

    /// Don't quit when the last window closes — keep menu bar icon alive.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    /// Re-open the main window when the user clicks the Dock icon
    /// while no windows are open.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // openWindow isn't directly accessible from delegate — use AppleScript-style relaunch
            // by raising the existing window scene
            for w in sender.windows where w.title == "Tell" {
                w.makeKeyAndOrderFront(nil)
                sender.activate(ignoringOtherApps: true)
                return true
            }
        }
        return true
    }
}

@main
struct TellApp: App {
    @StateObject private var daemon = DaemonController()
    @NSApplicationDelegateAdaptor(TellAppDelegate.self) private var appDelegate

    init() {
        TellSettings.registerDefaults()
        // Regular: shows in Dock, ⌘Tab, has normal app menu.
        // Combined with menu bar status icon below for ambient access.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        // ─── Main window (opens automatically at launch) ───
        WindowGroup("Tell", id: "main") {
            MainWindow()
                .environmentObject(daemon)
                .onAppear {
                    appDelegate.daemon = daemon
                    if TellSettings.shared.daemonAutoStart {
                        daemon.startIfNeeded()
                    }
                }
        }
        .defaultSize(width: 1000, height: 720)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)  // hide macOS title bar, keep traffic lights
        .commands {
            CommandGroup(replacing: .newItem) {}  // hide File > New (we're not document-based)
        }

        // ─── Menu bar status icon (ambient access) ───
        MenuBarExtra {
            PopoverView()
                .environmentObject(daemon)
        } label: {
            Image(systemName: daemon.running ? "eye.circle.fill" : "eye.circle")
                .foregroundStyle(daemon.running ? .green : .secondary)
        }
        .menuBarExtraStyle(.window)

        // ─── Settings window (⌘,) ───
        Settings { SettingsView() }
    }
}
