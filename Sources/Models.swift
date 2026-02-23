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

import Foundation

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

struct OutputLine: Identifiable {
    let id = UUID()
    let text: String
    let isError: Bool
    let isPrompt: Bool
}
