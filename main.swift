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
            Text(updater.isRunning ? updater.status : "Buum")
                .font(.headline)
                .padding(.bottom, 4)
            Divider()
            Button("Run Updates (buum)") {
                updater.run()
            }
            .disabled(updater.isRunning)
            .keyboardShortcut("u")
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            if updater.isRunning {
                Image(systemName: "arrow.triangle.2.circlepath")
            } else {
                Image(systemName: "shippingbox.fill")
            }
        }
    }
}

class Updater: ObservableObject {
    @Published var isRunning = false
    @Published var status = "Idle"

    func run() {
        guard !isRunning else { return }
        isRunning = true

        DispatchQueue.global(qos: .userInitiated).async {
            let brewPath = "/opt/homebrew/bin/brew"
            let masPath = "/opt/homebrew/bin/mas"
            let env: [String: String] = {
                var e = ProcessInfo.processInfo.environment
                e["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                return e
            }()

            if !FileManager.default.fileExists(atPath: brewPath) {
                self.setStatus("Installing Homebrew...")
                self.shell("/bin/bash", ["-c", #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#], env: env)
            }

            if !FileManager.default.fileExists(atPath: masPath) {
                self.setStatus("Installing mas...")
                self.shell("/opt/homebrew/bin/brew", ["install", "mas"], env: env)
            }

            self.setStatus("Updating Homebrew...")
            self.shell(brewPath, ["update"], env: env)

            self.setStatus("Upgrading packages...")
            self.shell(brewPath, ["upgrade"], env: env)

            self.setStatus("Checking App Store updates...")
            self.shell(masPath, ["outdated"], env: env)

            self.setStatus("Upgrading App Store apps...")
            let result = self.shell(masPath, ["upgrade"], env: env)

            DispatchQueue.main.async {
                self.isRunning = false
                self.status = "Idle"
                self.notify(success: result == 0)
            }
        }
    }

    @discardableResult
    func shell(_ path: String, _ args: [String], env: [String: String]) -> Int32 {
        let task = Process()
        task.launchPath = path
        task.arguments = args
        task.environment = env
        task.launch()
        task.waitUntilExit()
        return task.terminationStatus
    }

    func setStatus(_ message: String) {
        DispatchQueue.main.async { self.status = message }
    }

    func notify(success: Bool) {
        let content = UNMutableNotificationContent()
        content.title = "Buum"
        content.body = success ? "All updates completed!" : "Updates finished with errors."
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
