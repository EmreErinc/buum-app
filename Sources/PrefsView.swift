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

struct PrefsView: View {
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        Form {
            Section("Update Steps") {
                Toggle("Update Mac App Store apps (mas)", isOn: $prefs.runMas)
                Toggle("Clean Homebrew cache after upgrade", isOn: $prefs.runCleanup)
                Toggle("Check for broken casks", isOn: $prefs.runBrokenCaskCheck)
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
