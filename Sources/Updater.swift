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

import AppKit
import UserNotifications

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
    @Published var lastDiskFreed: Int64 = 0

    private var scheduleTimer: Timer?
    private var stdinHandle: FileHandle?
    private let inputSemaphore = DispatchSemaphore(value: 0)
    private let commandSemaphore = DispatchSemaphore(value: 0)
    private var pendingInput: String = ""
    private var promptActive = false

    init() {
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

    // MARK: - Outdated Packages

    func fetchOutdated() {
        guard !isRunning && !isCheckingOutdated else { return }
        isCheckingOutdated = true
        DispatchQueue.global(qos: .utility).async {
            let env = Environment.makeEnvironment()
            guard FileManager.default.fileExists(atPath: Environment.brewPath) else {
                DispatchQueue.main.async { self.isCheckingOutdated = false }
                return
            }
            let task = Process()
            task.launchPath = Environment.brewPath
            task.arguments = ["outdated", "--verbose"]
            task.environment = env
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()
            task.launch()
            task.waitUntilExit()

            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
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

    // MARK: - Brew Services

    func fetchServices() {
        guard !isLoadingServices else { return }
        isLoadingServices = true
        DispatchQueue.global(qos: .utility).async {
            let env = Environment.makeEnvironment()
            guard FileManager.default.fileExists(atPath: Environment.brewPath) else {
                DispatchQueue.main.async { self.isLoadingServices = false }
                return
            }
            let task = Process()
            task.launchPath = Environment.brewPath
            task.arguments = ["services", "list"]
            task.environment = env
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()
            task.launch()
            task.waitUntilExit()

            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let svcs: [BrewService] = out.components(separatedBy: "\n")
                .dropFirst()
                .compactMap { line in
                    let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                    guard parts.count >= 2 else { return nil }
                    return BrewService(name: parts[0], status: parts[1])
                }
                .filter { $0.status != "none" }
            DispatchQueue.main.async {
                self.services = svcs
                self.isLoadingServices = false
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
            let env = Environment.makeEnvironment()
            var failed = false
            self.setStatus("\(action.capitalized)ing \(service)…")
            Logger.log("--- brew services \(action) \(service) ---")
            self.shell(Environment.brewPath, ["services", action, service], env: env, &failed)
            Logger.log("--- done ---\n")
            DispatchQueue.main.async {
                self.isRunning = false
                self.status = "Idle"
                self.fetchServices()
            }
        }
    }

    // MARK: - System Updates

    func runSoftwareUpdate() {
        guard !isRunning else { return }
        isRunning = true
        output = []
        DispatchQueue.global(qos: .userInitiated).async {
            let env = Environment.makeEnvironment()
            var failed = false
            self.setStatus("Running macOS Software Update…")
            Logger.log("--- softwareupdate started ---")
            self.shell("/usr/sbin/softwareupdate", ["--install", "--all"], env: env, &failed)
            Logger.log("--- softwareupdate finished ---\n")
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
            let env = Environment.makeEnvironment()
            var failed = false
            Logger.log("--- dev tools update started ---")

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

            Logger.log("--- dev tools update finished ---\n")
            DispatchQueue.main.async {
                self.isRunning = false
                self.status = "Idle"
                self.notify(success: !failed)
            }
        }
    }

    // MARK: - Input Handling

    func submitInput(_ value: String) {
        pendingInput = value
        promptActive = false
        DispatchQueue.main.async { self.waitingForInput = false }
        inputSemaphore.signal()
        commandSemaphore.signal()
    }

    private func waitIfPromptActive() {
        guard promptActive else { return }
        commandSemaphore.wait()
    }

    // MARK: - Output Handling

    func appendOutput(_ text: String, isError: Bool = false, isPrompt: Bool = false) {
        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        DispatchQueue.main.async {
            for line in lines {
                self.output.append(OutputLine(text: line, isError: isError, isPrompt: isPrompt))
            }
        }
    }

    private func setStatus(_ message: String) {
        DispatchQueue.main.async { self.status = message }
    }

    // MARK: - Main Update Flow

    func run() {
        guard !isRunning else { return }
        isRunning = true
        output = []

        DispatchQueue.global(qos: .userInitiated).async {
            let env = Environment.makeEnvironment()

            Logger.log("--- Buum run started ---")
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
            if !FileManager.default.fileExists(atPath: Environment.brewPath) {
                self.setStatus("Installing Homebrew...")
                self.shell("/bin/bash", ["-c", #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#], env: env, &failed)
                self.waitIfPromptActive()
            }

            // Install mas if missing
            if !FileManager.default.fileExists(atPath: Environment.masPath) {
                self.setStatus("Installing mas...")
                self.shell(Environment.brewPath, ["install", "mas"], env: env, &failed)
                self.waitIfPromptActive()
            }

            self.setStatus("Updating Homebrew...")
            self.shell(Environment.brewPath, ["update"], env: env, &failed)
            self.waitIfPromptActive()

            self.setStatus("Upgrading packages...")
            if Prefs.shared.backupBeforeUpgrade {
                self.setStatus("Backing up package list...")
                let backupPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/homebrew/Brewfile.bak").path
                self.shell(Environment.brewPath, ["bundle", "dump", "--force", "--file=\(backupPath)"], env: env, &failed)
                self.waitIfPromptActive()
            }
            let upgradeArgs = Prefs.shared.dryRun ? ["upgrade", "--dry-run"] : ["upgrade"]
            self.shell(Environment.brewPath, upgradeArgs, env: env, &failed)
            self.waitIfPromptActive()

            self.setStatus("Checking App Store updates...")
            if Prefs.shared.runMas {
                self.shell(Environment.masPath, ["outdated"], env: env, &failed)
                self.waitIfPromptActive()

                self.setStatus("Upgrading App Store apps...")
                self.shell(Environment.masPath, ["upgrade"], env: env, &failed)
                self.waitIfPromptActive()
            }

            self.setStatus("Cleaning up Homebrew cache...")
            if Prefs.shared.runCleanup {
                let beforeCleanup = self.diskFreeBytes()
                self.shell(Environment.brewPath, ["cleanup", "--prune=all"], env: env, &failed)
                self.waitIfPromptActive()
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
                brokenCasks = self.findBrokenCasks(env: env)
            } else {
                brokenCasks = []
            }

            if !brokenCasks.isEmpty {
                self.setStatus("Disabling \(brokenCasks.count) broken cask(s)...")
                self.ignoreBrokenCasks(brokenCasks)
                Logger.log("Disabled broken casks: \(brokenCasks.joined(separator: ", "))")
            }

            // Post-update script
            let postScript = Prefs.shared.postScript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !postScript.isEmpty {
                self.setStatus("Running post-update script...")
                self.shell("/bin/bash", ["-c", postScript], env: env, &failed)
                self.waitIfPromptActive()
            }

            Logger.log("--- Buum run finished (success: \(!failed)) ---\n")

            DispatchQueue.main.async {
                self.isRunning = false
                self.status = "Idle"
                self.notify(success: !failed, brokenCasks: brokenCasks)
                self.fetchOutdated()
            }
        }
    }

    // MARK: - Diagnostics

    func runDoctor() {
        guard !isRunning else { return }
        isRunning = true
        hasIssues = false
        output = []

        DispatchQueue.global(qos: .userInitiated).async {
            let env = Environment.makeEnvironment()

            self.setStatus("Running brew doctor...")
            Logger.log("--- brew doctor started ---")

            let task = Process()
            task.launchPath = Environment.brewPath
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

            if !out.isEmpty { Logger.log("stdout: \(out.trimmingCharacters(in: .whitespacesAndNewlines))") }
            if !err.isEmpty { Logger.log("stderr: \(err.trimmingCharacters(in: .whitespacesAndNewlines))") }
            Logger.log("--- brew doctor finished (healthy: \(healthy)) ---\n")

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
            let env = Environment.makeEnvironment()

            self.setStatus("Finding missing dependencies...")
            Logger.log("--- brew missing started ---")

            let task = Process()
            task.launchPath = Environment.brewPath
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
                Logger.log("stdout: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                self.appendOutput(text, isError: true)
                Logger.log("stderr: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
            }

            task.launch()
            task.waitUntilExit()

            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil

            let missing = self.output
                .filter { !$0.isError && !$0.text.hasPrefix("$") }
                .flatMap { $0.text.components(separatedBy: "\n") }
                .filter { $0.contains(":") }

            Logger.log("--- brew missing finished ---\n")

            DispatchQueue.main.async {
                self.isRunning = false
                self.status = "Idle"

                let content = UNMutableNotificationContent()
                content.title = "Buum — Missing Dependencies"
                content.sound = .default

                if missing.isEmpty {
                    content.body = "✅ No missing dependencies found!"
                } else {
                    content.body = "⚠️ \(missing.count) formula(e) have missing deps. Check output window."
                    content.categoryIdentifier = "MISSING_DEPS"
                }

                let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                UNUserNotificationCenter.current().add(req)

                if !missing.isEmpty {
                    self.offerReinstall(missing: missing, env: env)
                }
            }
        }
    }

    // MARK: - Shell Execution

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
        Logger.log("$ \(([path] + args).joined(separator: " "))")

        let passwordPatterns = ["password", "Password", "sudo:"]

        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Logger.log("stdout: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
            let isPrompt = passwordPatterns.contains(where: { text.contains($0) })
            self.appendOutput(text, isError: false, isPrompt: isPrompt)
            if isPrompt { self.promptForInput(text) }
        }

        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Logger.log("stderr: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
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
        Logger.log("exit: \(exitCode)")
        if exitCode != 0 { failed = true }
        return exitCode
    }

    func shellWithAuth(_ command: String, label: String, env: [String: String], failed: inout Bool) {
        appendOutput("$ \(label)", isError: false)
        Logger.log("$ \(command) [via osascript]")

        let path = env["PATH"] ?? Environment.defaultPath
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
            Logger.log("stdout: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            let cancelled = text.contains("User canceled") || text.contains("-128")
            self.appendOutput(text, isError: !cancelled)
            Logger.log("stderr: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        task.launch()
        task.waitUntilExit()

        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil

        let exitCode = task.terminationStatus
        Logger.log("exit: \(exitCode)")
        if exitCode != 0 { failed = true }
    }

    // MARK: - Private Helpers

    private func promptForInput(_ prompt: String) {
        promptActive = true
        DispatchQueue.main.async {
            self.inputPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            self.waitingForInput = true
        }
        inputSemaphore.wait()
        if let data = (pendingInput + "\n").data(using: .utf8) {
            stdinHandle?.write(data)
        }
        pendingInput = ""
    }

    private func isConnected() -> Bool {
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

    private func offerReinstall(missing: [String], env: [String: String]) {
        let alert = NSAlert()
        alert.messageText = "Missing Dependencies Found"
        alert.informativeText = "\(missing.count) formula(e) have missing dependencies.\n\nWould you like to reinstall them now?"
        alert.addButton(withTitle: "Reinstall")
        alert.addButton(withTitle: "Ignore")
        alert.alertStyle = .warning

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
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
                self.shell(Environment.brewPath, ["reinstall"] + formulae, env: env, &failed)
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.status = "Idle"
                    self.notify(success: !failed)
                }
            }
        }
    }

    private func findBrokenCasks(env: [String: String]) -> [String] {
        let task = Process()
        task.launchPath = Environment.brewPath
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
            check.launchPath = Environment.brewPath
            check.arguments = ["info", "--cask", cask]
            check.environment = env
            check.standardOutput = Pipe()
            check.standardError = Pipe()
            check.launch()
            check.waitUntilExit()
            return check.terminationStatus != 0
        }
    }

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

    // MARK: - Update Check

    private func checkForUpdates() {
        guard let url = URL(string: Environment.latestReleaseAPI) else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else { return }
            let latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            if latest > Environment.currentVersion {
                DispatchQueue.main.async { self.updateAvailable = latest }
            }
        }.resume()
    }

    private func setupSchedule() {
        scheduleTimer?.invalidate()
        scheduleTimer = nil
        guard Prefs.shared.scheduleEnabled, Prefs.shared.scheduleHours > 0 else { return }
        let interval = TimeInterval(Prefs.shared.scheduleHours * 3600)
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.run()
        }
    }

    // MARK: - Notifications

    private func notify(success: Bool, brokenCasks: [String] = []) {
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
