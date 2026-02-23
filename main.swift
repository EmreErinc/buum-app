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

            // Install Homebrew if missing
            if !FileManager.default.fileExists(atPath: brewPath) {
                self.setStatus("Installing Homebrew...")
                self.shell("/bin/bash", ["-c", #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#], env: env)
            }

            // Install mas if missing
            if !FileManager.default.fileExists(atPath: masPath) {
                self.setStatus("Installing mas...")
                self.shell(brewPath, ["install", "mas"], env: env)
            }

            // Update & upgrade Homebrew
            self.setStatus("Updating Homebrew...")
            self.shell(brewPath, ["update"], env: env)

            self.setStatus("Upgrading packages...")
            self.shell(brewPath, ["upgrade"], env: env)

            // Update Mac App Store apps
            self.setStatus("Checking App Store updates...")
            self.shell(masPath, ["outdated"], env: env)

            self.setStatus("Upgrading App Store apps...")
            self.shell(masPath, ["upgrade"], env: env)

            // Clean up old versions and cache
            self.setStatus("Cleaning up Homebrew cache...")
            self.shell(brewPath, ["cleanup", "--prune=all"], env: env)

            // Detect and auto-ignore broken casks
            self.setStatus("Checking for broken casks...")
            let brokenCasks = self.findBrokenCasks(brewPath: brewPath, env: env)

            if !brokenCasks.isEmpty {
                self.setStatus("Disabling \(brokenCasks.count) broken cask(s)...")
                self.ignoreBrokenCasks(brokenCasks)
            }

            DispatchQueue.main.async {
                self.isRunning = false
                self.status = "Idle"
                self.notify(success: true, brokenCasks: brokenCasks)
            }
        }
    }

    // Returns list of installed casks that fail `brew info --cask`
    private func findBrokenCasks(brewPath: String, env: [String: String]) -> [String] {
        let task = Process()
        task.launchPath = brewPath
        task.arguments = ["list", "--cask"]
        task.environment = env
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        task.launch()
        task.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let casks = output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }

        return casks.filter { cask in
            let check = Process()
            check.launchPath = brewPath
            check.arguments = ["info", "--cask", cask]
            check.environment = env
            check.standardOutput = Pipe()
            check.standardError = Pipe()
            check.launch()
            check.waitUntilExit()
            return check.terminationStatus != 0
        }
    }

    // Writes broken casks to ~/.config/homebrew/ignored-casks.rb
    private func ignoreBrokenCasks(_ casks: [String]) {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/homebrew")
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        let ignoredFile = configDir.appendingPathComponent("ignored-casks.rb")
        let lines = casks.map { "cask '\($0)' do\n  disable!\nend" }.joined(separator: "\n")
        let data = (lines + "\n").data(using: .utf8)

        if FileManager.default.fileExists(atPath: ignoredFile.path) {
            if let handle = try? FileHandle(forWritingTo: ignoredFile) {
                handle.seekToEndOfFile()
                handle.write(data ?? Data())
                handle.closeFile()
            }
        } else {
            try? data?.write(to: ignoredFile)
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

    func notify(success: Bool, brokenCasks: [String] = []) {
        let content = UNMutableNotificationContent()
        content.title = "Buum"
        if !brokenCasks.isEmpty {
            content.body = "✅ Done! Disabled \(brokenCasks.count) broken cask(s): \(brokenCasks.joined(separator: ", "))"
        } else {
            content.body = success ? "✅ All updates completed & cache cleaned!" : "⚠️ Updates finished with errors."
        }
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
