// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum BreakReminderTests {
    static func run(_ suite: TestSuite) {
        rotation(suite)
        policy(suite)
    }

    static func activity(_ text: String, _ seconds: Int = 20) -> BreakActivity {
        BreakActivity(id: UUID(), text: text, seconds: seconds)
    }

    static func settings(hours: WorkingHours = WorkingHours(enabled: false, days: 0, startMinutes: 540, endMinutes: 1080),
                         paused: Date? = nil) -> BreakSettings {
        BreakSettings(
            eyes: KindSettings(enabled: true, interval: 1200, breakLength: 20, style: .notification, activities: []),
            movement: KindSettings(enabled: true, interval: 3000, breakLength: 120, style: .escalating, activities: []),
            escalateAfter: 120, hours: hours, pausedUntil: paused)
    }

    static var gregorian: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }

    /// 2026-09-30 is a Wednesday (weekday 4).
    static func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        gregorian.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    static func rotation(_ suite: TestSuite) {
        let list = [activity("a"), activity("b"), activity("c")]
        var r = ActivityRotation()
        suite.expect(r.current(.eyes, in: list)?.text == "a", "rotation starts at the first activity")
        r.advance(.eyes, count: 3); r.advance(.eyes, count: 3)
        suite.expect(r.current(.eyes, in: list)?.text == "c", "rotation advances in order")
        r.advance(.eyes, count: 3)
        suite.expect(r.current(.eyes, in: list)?.text == "a", "rotation wraps")
        suite.expect(r.current(.movement, in: list)?.text == "a", "kinds rotate independently")

        r.indices[.eyes] = 2
        let shorter = Array(list.prefix(2))
        suite.expect(r.current(.eyes, in: shorter)?.text == "b", "deleting clamps to the last item")
        r.advance(.eyes, count: 2)
        suite.expect(r.current(.eyes, in: shorter)?.text == "a", "advance after a clamp wraps to the start")

        suite.expect(r.current(.eyes, in: []) == nil, "empty list returns nil")
        r.advance(.eyes, count: 0)
        suite.expect(r.indices[.eyes] == 0, "advancing an empty list resets the index")
    }

    static func policy(_ suite: TestSuite) {
        let cal = gregorian
        let now = date(30, 10)
        func v(_ s: BreakSignals, _ set: BreakSettings = settings()) -> BusyVerdict {
            BusyPolicy.verdict(s, settings: set, now: now, calendar: cal)
        }
        suite.expect(v(BreakSignals()) == .active, "no signals is active")
        suite.expect(v(BreakSignals(micInUse: true)) == .busy, "mic is busy")
        suite.expect(v(BreakSignals(cameraInUse: true)) == .busy, "camera is busy")
        suite.expect(v(BreakSignals(fullscreenFrontmost: true)) == .busy, "fullscreen is busy")
        suite.expect(v(BreakSignals(micInUse: true, idleSeconds: 60)) == .idle, "idle outranks busy")
        suite.expect(v(BreakSignals(idleSeconds: 59)) == .active, "59 s idle is still active")
        suite.expect(v(BreakSignals(idleSeconds: 60), settings(paused: now.addingTimeInterval(1))) == .off,
                     "pause outranks idle")
        suite.expect(v(BreakSignals(), settings(paused: now)) == .active, "a pause ending now has expired")

        let weekdays = 0b0111110 // Mon-Fri
        let work = WorkingHours(enabled: true, days: weekdays, startMinutes: 540, endMinutes: 1080)
        suite.expect(work.contains(date(30, 9), calendar: cal), "start is inclusive")
        suite.expect(!work.contains(date(30, 18), calendar: cal), "end is exclusive")
        suite.expect(!work.contains(date(27, 10), calendar: cal), "Sunday is bit 0 and off")
        suite.expect(BusyPolicy.verdict(BreakSignals(), settings: settings(hours: work), now: date(30, 20), calendar: cal) == .off,
                     "outside hours is off")
        let noDays = WorkingHours(enabled: true, days: 0, startMinutes: 540, endMinutes: 1080)
        let flat = WorkingHours(enabled: true, days: weekdays, startMinutes: 600, endMinutes: 600)
        suite.expect(noDays.contains(date(30, 20), calendar: cal) && flat.contains(date(30, 20), calendar: cal),
                     "degenerate working hours treated as disabled")

        suite.expect(BusyPolicy.pauseUntilTomorrow(now: date(30, 8), hours: work, calendar: cal)
                        == cal.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 9)),
                     "until tomorrow skips a pre-start morning and lands on the next working start")
        let fri = cal.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 12))!
        suite.expect(BusyPolicy.pauseUntilTomorrow(now: fri, hours: work, calendar: cal)
                        == cal.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9)),
                     "Friday pauses until Monday start")
        suite.expect(BusyPolicy.pauseUntilTomorrow(now: date(30, 15), hours: settings().hours, calendar: cal)
                        == cal.date(from: DateComponents(year: 2026, month: 10, day: 1)),
                     "without working hours, until tomorrow is midnight")
    }
}
