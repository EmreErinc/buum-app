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
import UserNotifications

@main
struct BuumApp: App {
    @StateObject private var updater = Updater()

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(updater: updater)
        } label: {
            if updater.isRunning {
                Image(systemName: "arrow.triangle.2.circlepath")
            } else if updater.hasIssues {
                Image(systemName: "exclamationmark.triangle.fill")
            } else if updater.outdatedPackages.count > 0 {
                Label("\(updater.outdatedPackages.count)", systemImage: "shippingbox.fill")
            } else {
                Image(systemName: "shippingbox.fill")
            }
        }

        Window("Buum Output", id: "output") {
            TerminalView(updater: updater)
                .frame(minWidth: 680, minHeight: 420)
        }
        .defaultSize(width: 680, height: 420)

        Window("Buum Preferences", id: "preferences") {
            PrefsView()
                .frame(minWidth: 480, minHeight: 400)
        }
        .defaultSize(width: 480, height: 400)
    }
}
