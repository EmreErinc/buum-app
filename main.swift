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
            NSWorkspace.shared.open(updater.logURL)
        }
        Divider()
        Button("Preferences…") {
            openWindow(id: "preferences")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")
        if let v = updater.updateAvailable {
            Divider()
            Button(updater.isUpdating ? "⬇️ Installing update…" : "⬆️ Update to v\(v)") {
                updater.performUpdate(version: v)
                openWindow(id: "output")
            }
            .disabled(updater.isRunning || updater.isUpdating)
        }
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

// MARK: - Preferences

class Prefs: ObservableObject {
    static let shared = Prefs()
    @AppStorage("runMas")               var runMas               = true
    @AppStorage("runCleanup")           var runCleanup           = true
    @AppStorage("runBrokenCaskCheck")   var runBrokenCaskCheck   = true
    @AppStorage("notifyOnSuccess")      var notifyOnSuccess      = true
    @AppStorage("preScript")            var preScript            = ""
    @AppStorage("postScript")           var postScript           = ""
    @AppStorage("runOnWake")            var runOnWake            = false
    @AppStorage("greedyUpgrade")        var greedyUpgrade        = true
    @AppStorage("dryRun")               var dryRun               = false
    @AppStorage("backupBeforeUpgrade")  var backupBeforeUpgrade  = false
    @AppStorage("scheduleEnabled")      var scheduleEnabled      = false
    @AppStorage("scheduleHours")        var scheduleHours        = 24
}

struct PrefsView: View {
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        Form {
            Section("Update Steps") {
                Toggle("Update Mac App Store apps (mas)", isOn: $prefs.runMas)
                Toggle("Clean Homebrew cache after upgrade", isOn: $prefs.runCleanup)
                Toggle("Check for broken casks", isOn: $prefs.runBrokenCaskCheck)
                Toggle("Upgrade casks with auto-updates or latest version (--greedy)", isOn: $prefs.greedyUpgrade)
                Toggle("Dry run (preview only, no changes)", isOn: $prefs.dryRun)
                Toggle("Backup package list before upgrading (brew bundle dump)", isOn: $prefs.backupBeforeUpgrade)
            }
            Section("Notifications") {
                Toggle("Notify on success", isOn: $prefs.notifyOnSuccess)
            }
            Section(header: Text("Automation"),
                    footer: Text("Schedule takes effect on next app launch.").foregroundStyle(.secondary)) {
                Toggle("Run updates on wake from sleep", isOn: $prefs.runOnWake)
                Toggle("Run updates on a schedule", isOn: $prefs.scheduleEnabled)
                if prefs.scheduleEnabled {
                    Picker("Interval", selection: $prefs.scheduleHours) {
                        Text("Every 6 hours").tag(6)
                        Text("Daily").tag(24)
                        Text("Weekly").tag(168)
                    }
                    .pickerStyle(.segmented)
                }
            }
            Section(header: Text("Pre-update Script"),
                    footer: Text("Runs before brew update. Leave empty to skip.").foregroundStyle(.secondary)) {
                TextEditor(text: $prefs.preScript)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 70)
            }
            Section(header: Text("Post-update Script"),
                    footer: Text("Runs after all steps complete. Leave empty to skip.").foregroundStyle(.secondary)) {
                TextEditor(text: $prefs.postScript)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 70)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding(.bottom)
    }
}

struct OutdatedPackage: Identifiable {
    let id = UUID()
    let name: String
    let current: String
    let latest: String
}

struct BrewService: Identifiable {
    let id = UUID()
    let name: String
    let status: String  // "started", "stopped", "error", "none"

    var statusIcon: String {
        switch status {
        case "started": return "🟢"
        case "error":   return "🔴"
        case "stopped": return "⚫"
        default:        return "⚪"
        }
    }
}

class Updater: ObservableObject {
    @Published var isRunning = false
    @Published var status = "Idle"
    @Published var hasIssues = false
    @Published var output: [OutputLine] = []
    @Published var waitingForInput = false
    @Published var inputPrompt = ""
    @Published var outdatedPackages: [OutdatedPackage] = []
    @Published var isCheckingOutdated = false
    @Published var services: [BrewService] = []
    @Published var isLoadingServices = false
    @Published var updateAvailable: String? = nil
    @Published var isUpdating = false
    @Published var lastDiskFreed: Int64 = 0

    private var scheduleTimer: Timer?

    init() {
        // Migrate: ensure greedy is on for existing installs (was previously off by default)
        if UserDefaults.standard.object(forKey: "greedyUpgrade") == nil {
            UserDefaults.standard.set(true, forKey: "greedyUpgrade")
        }
        fetchOutdated()
        fetchServices()
        checkForUpdates()
        setupSchedule()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.fetchOutdated()
            self?.fetchServices()
            if Prefs.shared.runOnWake { self?.run() }
        }
    }

    private var stdinHandle: FileHandle?
    private let inputSemaphore = DispatchSemaphore(value: 0)   // unblocks readabilityHandler → writes to stdin
    private let commandSemaphore = DispatchSemaphore(value: 0) // unblocks run() → resumes next command
    private var pendingInput: String = ""
    private var promptActive = false  // true while waiting for user input

    func fetchOutdated() {
        guard !isRunning && !isCheckingOutdated else { return }
        isCheckingOutdated = true
        DispatchQueue.global(qos: .utility).async {
            let brewPath = "/opt/homebrew/bin/brew"
            let env: [String: String] = {
                var e = ProcessInfo.processInfo.environment
                e["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                return e
            }()
            guard FileManager.default.fileExists(atPath: brewPath) else {
                DispatchQueue.main.async { self.isCheckingOutdated = false }
                return
            }
            let task = Process()
            task.launchPath = brewPath
            task.arguments = ["outdated", "--verbose"]
            task.environment = env
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()
            task.launch()
            task.waitUntilExit()

            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            // Each line: "formula (current) < latest"
            let packages: [OutdatedPackage] = out.components(separatedBy: "\n").compactMap { line in
                let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
                guard parts.count >= 4 else { return nil }
                let name = parts[0]
                let current = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "()"))
                let latest = parts.last ?? ""
                return OutdatedPackage(name: name, current: current, latest: latest)
            }
            DispatchQueue.main.async {
                self.outdatedPackages = packages
                self.isCheckingOutdated = false
            }
        }
    }


    func fetchServices() {
        guard !isLoadingServices else { return }
        isLoadingServices = true
        DispatchQueue.global(qos: .utility).async {
            let brewPath = "/opt/homebrew/bin/brew"
            let env: [String: String] = {
                var e = ProcessInfo.processInfo.environment
                e["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                return e
            }()
            guard FileManager.default.fileExists(atPath: brewPath) else {
                DispatchQueue.main.async { self.isLoadingServices = false }
                return
            }
            let task = Process()
            task.launchPath = brewPath
            task.arguments = ["services", "list"]
            task.environment = env
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()
            task.launch()
            task.waitUntilExit()

            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let svcs: [BrewService] = out.components(separatedBy: "\n")
                .dropFirst() // skip header row
                .compactMap { line in
                    let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                    guard parts.count >= 2 else { return nil }
                    return BrewService(name: parts[0], status: parts[1])
                }
                .filter { $0.status != "none" }
            DispatchQueue.main.async {
                self.services = svcs
                self.isLoadingServices = false
                // Warn in menu bar if any service is in error state
                if svcs.contains(where: { $0.status == "error" }) {
                    self.hasIssues = true
                }
            }
        }
    }

    func serviceAction(_ action: String, service: String) {
        guard !isRunning else { return }
        isRunning = true
        output = []
        DispatchQueue.global(qos: .userInitiated).async {
            let brewPath = "/opt/homebrew/bin/brew"
            let env: [String: String] = {
                var e = ProcessInfo.processInfo.environment
                e["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                return e
            }()
            var failed = false
            self.setStatus("\(action.capitalized)ing \(service)…")
            self.log("--- brew services \(action) \(service) ---")
            self.shell(brewPath, ["services", action, service], env: env, &failed)
            self.log("--- done ---\n")
            DispatchQueue.main.async {
                self.isRunning = false
                self.status = "Idle"
                self.fetchServices()
            }
        }
    }

    func runSoftwareUpdate() {
        guard !isRunning else { return }
        isRunning = true
        output = []
        DispatchQueue.global(qos: .userInitiated).async {
            let env: [String: String] = {
                var e = ProcessInfo.processInfo.environment
                e["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                return e
            }()
            var failed = false
            self.setStatus("Running macOS Software Update…")
            self.log("--- softwareupdate started ---")
            self.shell("/usr/sbin/softwareupdate", ["--install", "--all"], env: env, &failed)
            self.log("--- softwareupdate finished ---\n")
            DispatchQueue.main.async {
                self.isRunning = false
                self.status = "Idle"
                self.notify(success: !failed)
            }
        }
    }

    func runDevUpdate() {
        guard !isRunning else { return }
        isRunning = true
        output = []
        DispatchQueue.global(qos: .userInitiated).async {
            let env: [String: String] = {
                var e = ProcessInfo.processInfo.environment
                e["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                return e
            }()
            var failed = false
            self.log("--- dev tools update started ---")

            // npm
            self.setStatus("Updating npm globals…")
            let npmCode = self.shell("/bin/bash", ["-c", "which npm && npm update -g"], env: env, &failed)
            if npmCode == 1 { self.appendOutput("npm not found, skipping.", isError: false) }
            self.waitIfPromptActive()

            // pip3
            self.setStatus("Updating pip3…")
            let pipCode = self.shell("/bin/bash", ["-c", "which pip3 && pip3 install --upgrade pip"], env: env, &failed)
            if pipCode == 1 { self.appendOutput("pip3 not found, skipping.", isError: false) }
            self.waitIfPromptActive()

            self.log("--- dev tools update finished ---\n")
            DispatchQueue.main.async {
                self.isRunning = false
                self.status = "Idle"
                self.notify(success: !failed)
            }
        }
    }

    func submitInput(_ value: String) {
        pendingInput = value
        promptActive = false
        DispatchQueue.main.async { self.waitingForInput = false }
        inputSemaphore.signal()    // let readabilityHandler write to stdin
        commandSemaphore.signal()  // let run() continue to next command
    }

    // Called between every shell() in run() — blocks if a prompt is pending
    func waitIfPromptActive() {
        guard promptActive else { return }
        commandSemaphore.wait()
    }

    struct OutputLine: Identifiable {
        let id = UUID()
        let text: String
        let isError: Bool
        let isPrompt: Bool
    }

    func appendOutput(_ text: String, isError: Bool = false, isPrompt: Bool = false) {
        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        DispatchQueue.main.async {
            for line in lines {
                self.output.append(OutputLine(text: line, isError: isError, isPrompt: isPrompt))
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

            // Connectivity check
            if !self.isConnected() {
                self.appendOutput("⚠️ No internet connection. Skipping run.", isError: false)
                DispatchQueue.main.async { self.isRunning = false }
                return
            }

            // Pre-update script
            let preScript = Prefs.shared.preScript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !preScript.isEmpty {
                self.setStatus("Running pre-update script...")
                self.shell("/bin/bash", ["-c", preScript], env: env, &failed)
                self.waitIfPromptActive()
            }

            // Install Homebrew if missing
            if !FileManager.default.fileExists(atPath: brewPath) {
                self.setStatus("Installing Homebrew...")
                self.shell("/bin/bash", ["-c", #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#], env: env, &failed)
                self.waitIfPromptActive()
            }

            // Install mas if missing
            if !FileManager.default.fileExists(atPath: masPath) {
                self.setStatus("Installing mas...")
                self.shell(brewPath, ["install", "mas"], env: env, &failed)
                self.waitIfPromptActive()
            }

            self.setStatus("Updating Homebrew...")
            self.shell(brewPath, ["update"], env: env, &failed)
            self.waitIfPromptActive()

            self.setStatus("Upgrading packages...")
            if Prefs.shared.backupBeforeUpgrade {
                self.setStatus("Backing up package list...")
                let backupPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/homebrew/Brewfile.bak").path
                self.shell(brewPath, ["bundle", "dump", "--force", "--file=\(backupPath)"], env: env, &failed)
                self.waitIfPromptActive()
            }
            var upgradeArgs = ["upgrade"]
            if Prefs.shared.greedyUpgrade { upgradeArgs.append("--greedy") }
            if Prefs.shared.dryRun        { upgradeArgs.append("--dry-run") }
            let upgradeStart = self.output.count
            self.shell(brewPath, upgradeArgs, env: env, &failed)
            self.waitIfPromptActive()

            // Force-upgrade any packages brew skipped during upgrade
            let upgradeSkipped = self.skippedPackages(since: upgradeStart)
            if !upgradeSkipped.isEmpty && !Prefs.shared.dryRun {
                self.setStatus("Force-upgrading \(upgradeSkipped.count) skipped package(s)...")
                self.appendOutput("🔁 Force-upgrading skipped: \(upgradeSkipped.joined(separator: ", "))")
                self.shell(brewPath, ["upgrade", "--force"] + upgradeSkipped, env: env, &failed)
                self.waitIfPromptActive()
            }

            self.setStatus("Checking App Store updates...")
            if Prefs.shared.runMas {
                self.shell(masPath, ["outdated"], env: env, &failed)
                self.waitIfPromptActive()

                self.setStatus("Upgrading App Store apps...")
                self.shell(masPath, ["upgrade"], env: env, &failed)
                self.waitIfPromptActive()
            }

            self.setStatus("Cleaning up Homebrew cache...")
            if Prefs.shared.runCleanup {
                let beforeCleanup = self.diskFreeBytes()
                let cleanupStart = self.output.count
                self.shell(brewPath, ["cleanup", "--prune=all"], env: env, &failed)
                self.waitIfPromptActive()

                // Force-upgrade any packages cleanup warned about, then re-clean
                let cleanupSkipped = self.skippedPackages(since: cleanupStart)
                if !cleanupSkipped.isEmpty && !Prefs.shared.dryRun {
                    self.setStatus("Force-upgrading \(cleanupSkipped.count) package(s) skipped in cleanup...")
                    self.appendOutput("🔁 Force-upgrading: \(cleanupSkipped.joined(separator: ", "))")
                    self.shell(brewPath, ["upgrade", "--force"] + cleanupSkipped, env: env, &failed)
                    self.waitIfPromptActive()
                    self.shell(brewPath, ["cleanup", "--prune=all"], env: env, &failed)
                    self.waitIfPromptActive()
                }

                let freed = self.diskFreeBytes() - beforeCleanup
                if freed > 0 {
                    let mb = freed / 1_000_000
                    self.appendOutput("🧹 Freed \(mb) MB", isError: false)
                    DispatchQueue.main.async { self.lastDiskFreed = freed }
                }
            }

            self.setStatus("Checking for broken casks...")
            let brokenCasks: [String]
            if Prefs.shared.runBrokenCaskCheck {
                brokenCasks = self.findBrokenCasks(brewPath: brewPath, env: env)
            } else {
                brokenCasks = []
            }

            if !brokenCasks.isEmpty {
                self.setStatus("Disabling \(brokenCasks.count) broken cask(s)...")
                self.ignoreBrokenCasks(brokenCasks)
                self.log("Disabled broken casks: \(brokenCasks.joined(separator: ", "))")
            }

            // Post-update script
            let postScript = Prefs.shared.postScript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !postScript.isEmpty {
                self.setStatus("Running post-update script...")
                self.shell("/bin/bash", ["-c", postScript], env: env, &failed)
                self.waitIfPromptActive()
            }

            self.log("--- Buum run finished (success: \(!failed)) ---\n")

            DispatchQueue.main.async {
                self.isRunning = false
                self.status = "Idle"
                self.notify(success: !failed, brokenCasks: brokenCasks)
                self.fetchOutdated()
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

    func runMissing() {
        guard !isRunning else { return }
        isRunning = true
        output = []

        DispatchQueue.global(qos: .userInitiated).async {
            let brewPath = "/opt/homebrew/bin/brew"
            let env: [String: String] = {
                var e = ProcessInfo.processInfo.environment
                e["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                return e
            }()

            self.setStatus("Finding missing dependencies...")
            self.log("--- brew missing started ---")

            let task = Process()
            task.launchPath = brewPath
            task.arguments = ["missing"]
            task.environment = env

            let outPipe = Pipe()
            let errPipe = Pipe()
            task.standardOutput = outPipe
            task.standardError = errPipe

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                self.appendOutput(text, isError: false)
                self.log("stdout: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                self.appendOutput(text, isError: true)
                self.log("stderr: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
            }

            task.launch()
            task.waitUntilExit()

            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil

            // Parse missing packages from output: "formula: dep1 dep2 dep3"
            let missing = self.output
                .filter { !$0.isError && !$0.text.hasPrefix("$") }
                .flatMap { $0.text.components(separatedBy: "\n") }
                .filter { $0.contains(":") }

            self.log("--- brew missing finished ---\n")

            DispatchQueue.main.async {
                self.isRunning = false
                self.status = "Idle"

                let content = UNMutableNotificationContent()
                content.title = "Buum — Missing Dependencies"
                content.sound = .default

                if missing.isEmpty {
                    content.body = "✅ No missing dependencies found!"
                } else {
                    // Offer to install them
                    content.body = "⚠️ \(missing.count) formula(e) have missing deps. Check output window."
                    content.categoryIdentifier = "MISSING_DEPS"
                }

                let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                UNUserNotificationCenter.current().add(req)

                // If missing deps found, offer to reinstall them
                if !missing.isEmpty {
                    self.offerReinstall(missing: missing, brewPath: brewPath, env: env)
                }
            }
        }
    }

    private func offerReinstall(missing: [String], brewPath: String, env: [String: String]) {
        let alert = NSAlert()
        alert.messageText = "Missing Dependencies Found"
        alert.informativeText = "\(missing.count) formula(e) have missing dependencies.\n\nWould you like to reinstall them now?"
        alert.addButton(withTitle: "Reinstall")
        alert.addButton(withTitle: "Ignore")
        alert.alertStyle = .warning

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            // Extract formula names (before the colon on each line)
            let formulae = missing.compactMap { line -> String? in
                let parts = line.components(separatedBy: ":")
                return parts.first?.trimmingCharacters(in: .whitespaces)
            }
            guard !formulae.isEmpty else { return }

            isRunning = true
            setStatus("Reinstalling missing deps...")
            output = []

            DispatchQueue.global(qos: .userInitiated).async {
                var failed = false
                self.shell(brewPath, ["reinstall"] + formulae, env: env, &failed)
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.status = "Idle"
                    self.notify(success: !failed)
                }
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
        let inPipe  = Pipe()
        task.standardOutput = outPipe
        task.standardError  = errPipe
        task.standardInput  = inPipe
        stdinHandle = inPipe.fileHandleForWriting

        let cmd = ([path.components(separatedBy: "/").last ?? path] + args).joined(separator: " ")
        appendOutput("$ \(cmd)", isError: false)
        log("$ \(([path] + args).joined(separator: " "))")

        let passwordPatterns = ["password", "Password", "sudo:"]

        // Stream stdout live
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self.log("stdout: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
            let isPrompt = passwordPatterns.contains(where: { text.contains($0) })
            self.appendOutput(text, isError: false, isPrompt: isPrompt)
            if isPrompt { self.promptForInput(text) }
        }

        // Stream stderr live — detect password prompts
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self.log("stderr: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
            let isPrompt = passwordPatterns.contains(where: { text.contains($0) })
            self.appendOutput(text, isError: !isPrompt, isPrompt: isPrompt)
            if isPrompt { self.promptForInput(text) }
        }

        task.launch()
        task.waitUntilExit()

        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil
        stdinHandle = nil

        let exitCode = task.terminationStatus
        log("exit: \(exitCode)")
        if exitCode != 0 { failed = true }
        return exitCode
    }

    private func promptForInput(_ prompt: String) {
        promptActive = true
        DispatchQueue.main.async {
            self.inputPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            self.waitingForInput = true
        }
        // Block readabilityHandler thread until user submits password
        inputSemaphore.wait()
        if let data = (pendingInput + "\n").data(using: .utf8) {
            stdinHandle?.write(data)
        }
        pendingInput = ""
    }

    func setStatus(_ message: String) {
        DispatchQueue.main.async { self.status = message }
    }

    // Runs a shell command via osascript so macOS shows its native auth dialog if needed
    func shellWithAuth(_ command: String, label: String, env: [String: String], failed: inout Bool) {
        appendOutput("$ \(label)", isError: false)
        log("$ \(command) [via osascript]")

        // Build PATH prefix so mas is found inside osascript environment
        let path = env["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        let script = "do shell script \"export PATH=\\\"\(path)\\\"; \(command)\" with administrator privileges"

        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]

        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe

        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self.appendOutput(text, isError: false)
            self.log("stdout: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            // "User canceled" means they dismissed the dialog — not a real error
            let cancelled = text.contains("User canceled") || text.contains("-128")
            self.appendOutput(text, isError: !cancelled)
            self.log("stderr: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        task.launch()
        task.waitUntilExit()

        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil

        let exitCode = task.terminationStatus
        log("exit: \(exitCode)")
        // Exit 1 with "User canceled" (-128) is not a real failure
        if exitCode != 0 { failed = true }
    }

    func isConnected() -> Bool {
        let task = Process()
        task.launchPath = "/sbin/ping"
        task.arguments = ["-c", "1", "-W", "2000", "8.8.8.8"]
        task.standardOutput = Pipe(); task.standardError = Pipe()
        task.launch(); task.waitUntilExit()
        return task.terminationStatus == 0
    }

    private func diskFreeBytes() -> Int64 {
        let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/")
        return (attrs?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
    }

    func checkForUpdates() {
        let current = "1.9.0"
        guard let url = URL(string: "https://api.github.com/repos/emreerinc/buum-app/releases/latest") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else { return }
            let latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            if latest > current {
                DispatchQueue.main.async { self.updateAvailable = latest }
            }
        }.resume()
    }

    func performUpdate(version: String) {
        guard !isUpdating && !isRunning else { return }
        isUpdating = true
        output = []

        DispatchQueue.global(qos: .userInitiated).async {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("BuumUpdate-\(version)")
            let zipPath = tempDir.appendingPathComponent("Buum-\(version).zip")
            let scriptPath = tempDir.appendingPathComponent("update.sh")

            do {
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

                // Download ZIP
                self.appendOutput("⬇️ Downloading Buum v\(version)…")
                self.setStatus("Downloading v\(version)…")
                guard let zipURL = URL(string: "https://github.com/emreerinc/buum-app/releases/download/v\(version)/Buum-\(version).zip") else { throw NSError(domain: "Buum", code: 1) }
                let data = try Data(contentsOf: zipURL)
                try data.write(to: zipPath)
                self.appendOutput("✅ Download complete (\(data.count / 1024) KB)")

                // Write update script — runs after app quits
                let script = """
                #!/bin/bash
                sleep 2
                cd "\(tempDir.path)"
                unzip -o "\(zipPath.path)" -d "\(tempDir.path)" > /dev/null 2>&1
                cp -rf "\(tempDir.path)/Buum.app" "/Applications/Buum.app"
                codesign --force --deep --sign - "/Applications/Buum.app" > /dev/null 2>&1
                open "/Applications/Buum.app"
                rm -rf "\(tempDir.path)"
                """
                try script.write(toFile: scriptPath.path, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                      ofItemAtPath: scriptPath.path)

                self.appendOutput("🔄 Installing and restarting…")
                self.setStatus("Restarting…")

                // Launch update script detached, then quit
                let task = Process()
                task.launchPath = "/bin/bash"
                task.arguments = [scriptPath.path]
                task.launch()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    NSApplication.shared.terminate(nil)
                }
            } catch {
                self.appendOutput("❌ Update failed: \(error.localizedDescription)", isError: true)
                self.log("Update error: \(error)")
                DispatchQueue.main.async {
                    self.isUpdating = false
                    self.status = "Idle"
                }
            }
        }
    }

    func setupSchedule() {
        scheduleTimer?.invalidate()
        scheduleTimer = nil
        guard Prefs.shared.scheduleEnabled, Prefs.shared.scheduleHours > 0 else { return }
        let interval = TimeInterval(Prefs.shared.scheduleHours * 3600)
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.run()
        }
    }

    // Parses output lines since `startIndex` for "Warning: Skipping X: most recent version Y not installed"
    private func skippedPackages(since startIndex: Int) -> [String] {
        output.dropFirst(startIndex)
            .filter { $0.text.contains("Warning: Skipping") && $0.text.contains("not installed") }
            .compactMap { line -> String? in
                let parts = line.text.components(separatedBy: "Skipping ")
                guard parts.count >= 2 else { return nil }
                return parts[1].components(separatedBy: ":").first?.trimmingCharacters(in: .whitespaces)
            }
    }

    func notify(success: Bool, brokenCasks: [String] = []) {
        // Skip notification on success if the user opted out
        if success && brokenCasks.isEmpty && !Prefs.shared.notifyOnSuccess { return }
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
    @State private var password = ""
    @State private var searchText = ""
    @FocusState private var passwordFocused: Bool

    private var displayedLines: [Updater.OutputLine] {
        searchText.isEmpty ? updater.output : updater.output.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Circle().fill(.red).frame(width: 12, height: 12)
                Circle().fill(.yellow).frame(width: 12, height: 12)
                Circle().fill(.green).frame(width: 12, height: 12)
                TextField("Filter…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(width: 160)
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
                        ForEach(displayedLines) { line in
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
                Button("Copy") {
                    let text = updater.output.map { $0.text }.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.black.opacity(0.85))

            // Password prompt bar — shown when a command needs sudo
            if updater.waitingForInput {
                Divider().background(.yellow.opacity(0.4))
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.yellow)
                        .font(.system(size: 12))
                    Text(updater.inputPrompt.isEmpty ? "Password required:" : updater.inputPrompt)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.yellow)
                    SecureField("Enter password…", text: $password)
                        .font(.system(size: 12, design: .monospaced))
                        .textFieldStyle(.plain)
                        .foregroundStyle(.white)
                        .focused($passwordFocused)
                        .onSubmit {
                            updater.submitInput(password)
                            password = ""
                        }
                    Button("Submit") {
                        updater.submitInput(password)
                        password = ""
                    }
                    .font(.system(size: 11))
                    .keyboardShortcut(.return)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.yellow.opacity(0.08))
                .onAppear { passwordFocused = true }
            }
        }
        .background(Color.black)
    }
}
