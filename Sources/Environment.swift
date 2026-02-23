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

enum Environment {
    static let brewPath = "/opt/homebrew/bin/brew"
    static let masPath = "/opt/homebrew/bin/mas"
    static let defaultPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    static let currentVersion = "1.8.0"
    static let releasesURL = "https://github.com/emreerinc/buum-app/releases/latest"
    static let latestReleaseAPI = "https://api.github.com/repos/emreerinc/buum-app/releases/latest"

    static func makeEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = defaultPath
        return env
    }
}
