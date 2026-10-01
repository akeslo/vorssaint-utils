// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum BreakReminderNotchContract {
    static func run(_ suite: TestSuite) {
        let name = "com.vorssaint.tests.break-notch"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        defer { d.removePersistentDomain(forName: name) }
        d.register(defaults: Defaults.registeredDefaults)
        d.set(true, forKey: AppFeature.notch.availabilityKey)
        d.set(true, forKey: DefaultsKey.notchEnabled)
        d.set(true, forKey: AppFeature.breakReminders.availabilityKey)
        d.set(false, forKey: AppFeature.screenshot.availabilityKey)
        suite.expect(NotchSupport.routes(.breakReminder, in: d),
                     "breaks route with the Screenshot feature off and Captures not in the modules")
        d.set(false, forKey: DefaultsKey.notchBreakReminders)
        suite.expect(!NotchSupport.routes(.breakReminder, in: d), "the notch toggle turns break routing off")

        let source = (try? String(contentsOfFile: "Sources/Vorssaint/Services/Notch/NotchService.swift",
                                  encoding: .utf8)) ?? ""
        suite.expect(source.contains("NotchSupport.routes(route)"), "presentCapture guards on its own route")
        suite.expect(source.contains("routes(captureRoute)"), "syncWithPreferences keeps a capture on its stored route")
        suite.expect(source.contains("captureRoute == .capture") && source.contains("captureID != nil"),
                     "a break never presents over a live screenshot capture")
        let userCollapses = source.components(separatedBy: "collapse(user: true)").count - 1
        suite.expect(userCollapses >= 1 && userCollapses <= 4,
                     "only the Esc, hide pad and toggle sites collapse as the user")
    }
}
