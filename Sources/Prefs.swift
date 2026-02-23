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

class Prefs: ObservableObject {
    static let shared = Prefs()
    @AppStorage("runMas")               var runMas               = true
    @AppStorage("runCleanup")           var runCleanup           = true
    @AppStorage("runBrokenCaskCheck")   var runBrokenCaskCheck   = true
    @AppStorage("notifyOnSuccess")      var notifyOnSuccess      = true
    @AppStorage("preScript")            var preScript            = ""
    @AppStorage("postScript")           var postScript           = ""
    @AppStorage("runOnWake")            var runOnWake            = false
    @AppStorage("dryRun")               var dryRun               = false
    @AppStorage("backupBeforeUpgrade")  var backupBeforeUpgrade  = false
    @AppStorage("scheduleEnabled")      var scheduleEnabled      = false
    @AppStorage("scheduleHours")        var scheduleHours        = 24
}
