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
            } else {
                Image(systemName: "shippingbox.fill")
            }
        }

        Window("Buum Output", id: "output") {
            TerminalView(updater: updater)
                .frame(minWidth: 680, minHeight: 420)
        }
        .defaultSize(width: 680, height: 420)
    }
}

struct MenuContent: View {
    @ObservedObject var updater: Updater
    @Environment(\.openWindow) var openWindow

    var body: some View {
        Text(updater.isRunning ? updater.status : "Buum")
            .font(.headline)
            .padding(.bottom, 4)
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
        Divider()
        Button(updater.isRunning ? "Show Live Output" : "Show Last Output") {
            openWindow(id: "output")
        }
        .disabled(updater.output.isEmpty)
        Button("Show Log") {
            NSWorkspace.shared.open(updater.logURL)
        }
        Divider()
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

class Updater: ObservableObject {
    @Published var isRunning = false
    @Published var status = "Idle"
    @Published var hasIssues = false
    @Published var output: [OutputLine] = []

    struct OutputLine: Identifiable {
        let id = UUID()
        let text: String
        let isError: Bool
    }

    func appendOutput(_ text: String, isError: Bool = false) {
        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        DispatchQueue.main.async {
            for line in lines {
                self.output.append(OutputLine(text: line, isError: isError))
            }
        }
    }

    let logURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Buum")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("buum.log")
    }()

    func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path),
               let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try? data.write(to: logURL)
            }
        }
    }

    func run() {
        guard !isRunning else { return }
        isRunning = true
        output = []

        DispatchQueue.global(qos: .userInitiated).async {
            let brewPath = "/opt/homebrew/bin/brew"
            let masPath = "/opt/homebrew/bin/mas"
            let env: [String: String] = {
                var e = ProcessInfo.processInfo.environment
                e["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                return e
            }()

            self.log("--- Buum run started ---")
            var failed = false

            // Install Homebrew if missing
            if !FileManager.default.fileExists(atPath: brewPath) {
                self.setStatus("Installing Homebrew...")
                self.shell("/bin/bash", ["-c", #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#], env: env, &failed)
            }

            // Install mas if missing
            if !FileManager.default.fileExists(atPath: masPath) {
                self.setStatus("Installing mas...")
                self.shell(brewPath, ["install", "mas"], env: env, &failed)
            }

            self.setStatus("Updating Homebrew...")
            self.shell(brewPath, ["update"], env: env, &failed)

            self.setStatus("Upgrading packages...")
            self.shell(brewPath, ["upgrade"], env: env, &failed)

            self.setStatus("Checking App Store updates...")
            self.shell(masPath, ["outdated"], env: env, &failed)

            self.setStatus("Upgrading App Store apps...")
            self.shell(masPath, ["upgrade"], env: env, &failed)

            self.setStatus("Cleaning up Homebrew cache...")
            self.shell(brewPath, ["cleanup", "--prune=all"], env: env, &failed)

            self.setStatus("Checking for broken casks...")
            let brokenCasks = self.findBrokenCasks(brewPath: brewPath, env: env)

            if !brokenCasks.isEmpty {
                self.setStatus("Disabling \(brokenCasks.count) broken cask(s)...")
                self.ignoreBrokenCasks(brokenCasks)
                self.log("Disabled broken casks: \(brokenCasks.joined(separator: ", "))")
            }

            self.log("--- Buum run finished (success: \(!failed)) ---\n")

            DispatchQueue.main.async {
                self.isRunning = false
                self.status = "Idle"
                self.notify(success: !failed, brokenCasks: brokenCasks)
            }
        }
    }

    func runDoctor() {
        guard !isRunning else { return }
        isRunning = true
        hasIssues = false
        output = []

        DispatchQueue.global(qos: .userInitiated).async {
            let brewPath = "/opt/homebrew/bin/brew"
            let env: [String: String] = {
                var e = ProcessInfo.processInfo.environment
                e["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                return e
            }()

            self.setStatus("Running brew doctor...")
            self.log("--- brew doctor started ---")

            let task = Process()
            task.launchPath = brewPath
            task.arguments = ["doctor"]
            task.environment = env
            let outPipe = Pipe()
            let errPipe = Pipe()
            task.standardOutput = outPipe
            task.standardError = errPipe
            task.launch()
            task.waitUntilExit()

            let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let healthy = task.terminationStatus == 0

            if !out.isEmpty { self.log("stdout: \(out.trimmingCharacters(in: .whitespacesAndNewlines))") }
            if !err.isEmpty { self.log("stderr: \(err.trimmingCharacters(in: .whitespacesAndNewlines))") }
            self.log("--- brew doctor finished (healthy: \(healthy)) ---\n")

            // Parse issues from output for a summary
            let issues = (out + err)
                .components(separatedBy: "\n")
                .filter { $0.hasPrefix("Warning:") || $0.hasPrefix("Error:") }

            DispatchQueue.main.async {
                self.isRunning = false
                self.status = "Idle"
                self.hasIssues = !healthy

                let content = UNMutableNotificationContent()
                content.title = "Buum — Brew Doctor"
                content.sound = .default
                if healthy {
                    content.body = "✅ Your system is ready to brew!"
                } else if issues.isEmpty {
                    content.body = "⚠️ Issues found. Open Show Log for details."
                } else {
                    content.body = "⚠️ \(issues.count) issue(s): \(issues.prefix(2).joined(separator: " | "))"
                }
                let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                UNUserNotificationCenter.current().add(req)
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
    func shell(_ path: String, _ args: [String], env: [String: String], _ failed: inout Bool) -> Int32 {
        let task = Process()
        task.launchPath = path
        task.arguments = args
        task.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe

        let cmd = ([path.components(separatedBy: "/").last ?? path] + args).joined(separator: " ")
        appendOutput("$ \(cmd)", isError: false)
        log("$ \(([path] + args).joined(separator: " "))")

        // Stream stdout live
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                self.appendOutput(text, isError: false)
                self.log("stdout: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }

        // Stream stderr live
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                self.appendOutput(text, isError: true)
                self.log("stderr: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }

        task.launch()
        task.waitUntilExit()

        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil

        let exitCode = task.terminationStatus
        log("exit: \(exitCode)")
        if exitCode != 0 { failed = true }
        return exitCode
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

struct TerminalView: View {
    @ObservedObject var updater: Updater
    @State private var autoScroll = true

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Circle().fill(.red).frame(width: 12, height: 12)
                Circle().fill(.yellow).frame(width: 12, height: 12)
                Circle().fill(.green).frame(width: 12, height: 12)
                Spacer()
                Text(updater.isRunning ? updater.status : "Done")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("Auto-scroll", isOn: $autoScroll)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.black.opacity(0.85))

            Divider().background(.gray.opacity(0.3))

            // Output lines
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(updater.output) { line in
                            Text(line.text)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(line.isError ? Color.red.opacity(0.85) : Color.green.opacity(0.9))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(12)
                }
                .onChange(of: updater.output.count) { _ in
                    if autoScroll {
                        withAnimation { proxy.scrollTo("bottom") }
                    }
                }
            }
            .background(Color.black)

            // Bottom bar
            HStack {
                Text("\(updater.output.count) lines")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                if updater.isRunning {
                    ProgressView().scaleEffect(0.6)
                }
                Button("Clear") { updater.output = [] }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(updater.isRunning)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.black.opacity(0.85))
        }
        .background(Color.black)
    }
}
