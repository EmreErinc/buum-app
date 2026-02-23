// Buum - macOS menu bar app for Homebrew & Mac App Store updates
// Copyright (C) 2026 Emre Erinç
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

import SwiftUI

struct MenuContent: View {
    @ObservedObject var updater: Updater
    @Environment(\.openWindow) var openWindow

    var body: some View {
        Text(updater.isRunning ? updater.status : "Buum")
            .font(.headline)
            .padding(.bottom, 4)
        Divider()

        // Outdated packages submenu
        if updater.isCheckingOutdated {
            Text("Checking for outdated packages…")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
        } else if !updater.outdatedPackages.isEmpty {
            Menu("📦 \(updater.outdatedPackages.count) Outdated Package\(updater.outdatedPackages.count == 1 ? "" : "s")") {
                ForEach(updater.outdatedPackages) { pkg in
                    Text("\(pkg.name)  \(pkg.current) → \(pkg.latest)")
                        .font(.system(size: 12, design: .monospaced))
                }
            }
        } else {
            Text("✅ All packages up to date")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
        }
        Button(updater.isCheckingOutdated ? "Checking…" : "Refresh Outdated List") {
            updater.fetchOutdated()
        }
        .disabled(updater.isRunning || updater.isCheckingOutdated)
        .keyboardShortcut("c")
        if updater.lastDiskFreed > 0 {
            Text("🧹 Last cleanup freed \(updater.lastDiskFreed / 1_000_000) MB")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        Divider()
        Button("Run Updates (buum)") {
            updater.run()
            openWindow(id: "output")
        }
        .disabled(updater.isRunning)
        .keyboardShortcut("u")
        Button("Run Brew Doctor") {
            updater.runDoctor()
            openWindow(id: "output")
        }
        .disabled(updater.isRunning)
        .keyboardShortcut("d")
        Button("Find Missing Dependencies") {
            updater.runMissing()
            openWindow(id: "output")
        }
        .disabled(updater.isRunning)
        .keyboardShortcut("m")

        // System updates
        Divider()
        Button("macOS Software Update") {
            updater.runSoftwareUpdate()
            openWindow(id: "output")
        }
        .disabled(updater.isRunning)
        .keyboardShortcut("s", modifiers: [.command, .shift])
        Button("Update npm & pip Globals") {
            updater.runDevUpdate()
            openWindow(id: "output")
        }
        .disabled(updater.isRunning)

        // Brew Services submenu
        Divider()
        Menu("🔧 Brew Services") {
            Button(updater.isLoadingServices ? "Refreshing…" : "Refresh") {
                updater.fetchServices()
            }
            .disabled(updater.isLoadingServices)
            if !updater.services.isEmpty {
                Divider()
                ForEach(updater.services) { svc in
                    Menu("\(svc.statusIcon) \(svc.name)") {
                        Button("Start")   { updater.serviceAction("start",   service: svc.name); openWindow(id: "output") }
                        Button("Stop")    { updater.serviceAction("stop",    service: svc.name); openWindow(id: "output") }
                        Button("Restart") { updater.serviceAction("restart", service: svc.name); openWindow(id: "output") }
                    }
                }
            }
        }
        Divider()
        Button(updater.isRunning ? "Show Live Output" : "Show Last Output") {
            openWindow(id: "output")
        }
        .disabled(updater.output.isEmpty)
        Button("Show Log") {
            NSWorkspace.shared.open(Logger.logURL)
        }
        Divider()
        Button("Preferences…") {
            openWindow(id: "preferences")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")
        if let v = updater.updateAvailable {
            Divider()
            Button("⬆️ Update available: v\(v)") {
                NSWorkspace.shared.open(URL(string: Environment.releasesURL)!)
            }
        }
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
