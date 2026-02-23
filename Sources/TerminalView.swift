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

struct TerminalView: View {
    @ObservedObject var updater: Updater
    @State private var autoScroll = true
    @State private var password = ""
    @State private var searchText = ""
    @FocusState private var passwordFocused: Bool

    private var displayedLines: [OutputLine] {
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
