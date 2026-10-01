// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum BreakReminderTests {
    static func run(_ suite: TestSuite) {
        rotation(suite)
        policy(suite)
        schedule(suite)
        presence(suite)
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

    static func schedule(_ suite: TestSuite) {
        let k = KindSettings(enabled: true, interval: 100, breakLength: 20, style: .overlay, activities: [])
        let t0 = date(30, 10)
        let id = UUID()
        func tick(_ s: inout BreakSchedule, _ v: BusyVerdict, dt: TimeInterval = 5, idle: TimeInterval = 0,
                  away: TimeInterval? = nil, kind: KindSettings = k, now: Date = t0) -> [BreakSchedule.Event] {
            s.tick(dt: dt, verdict: v, idleSeconds: idle, awayFor: away, settings: kind, now: now, newID: { id })
        }

        var s = BreakSchedule()
        _ = tick(&s, .active, dt: 50)
        suite.expect(s.state == .counting(50), "active time counts")
        _ = tick(&s, .busy, dt: 10); _ = tick(&s, .idle, dt: 10, idle: 60)
        suite.expect(s.state == .counting(70), "busy and short idle count as screen time")
        _ = tick(&s, .off, dt: 10)
        suite.expect(s.state == .counting(70), "off freezes the countdown")
        let crossing = tick(&s, .active, dt: 30)
        suite.expect(s.state == .due && crossing.isEmpty, "crossing the interval goes due and emits nothing")
        _ = tick(&s, .off)
        suite.expect(s.state == .due, "due holds while off")
        _ = tick(&s, .busy)
        suite.expect(s.state == .deferred(0), "due while busy defers")
        _ = tick(&s, .active, dt: 25)
        suite.expect(s.state == .deferred(25), "deferred counts active grace")
        _ = tick(&s, .busy)
        suite.expect(s.state == .deferred(0), "busy restarts the grace")
        _ = tick(&s, .active, dt: 25)
        let fired = tick(&s, .active, dt: 5)
        suite.expect(fired == [.prompt(id)], "30 s of active grace prompts")
        suite.expect(s.state == .prompting(id: id, seen: false, deadline: nil), "prompting starts unseen")

        // The tick that crosses the interval while the mic is live does not prompt.
        var m = BreakSchedule(state: .counting(99))
        let crossBusy = tick(&m, .active, dt: 5)
        suite.expect(crossBusy.isEmpty && m.state == .due, "the crossing tick never prompts on unsampled signals")
        _ = tick(&m, .busy)
        suite.expect(m.state == .deferred(0), "the next tick sees the mic and defers")

        // Due while active prompts on the next tick.
        var d = BreakSchedule(state: .due)
        suite.expect(tick(&d, .active) == [.prompt(id)], "due while active prompts")

        // Deadlines start at present time.
        var p = BreakSchedule(state: .prompting(id: id, seen: false, deadline: nil))
        _ = tick(&p, .active, now: t0.addingTimeInterval(10_000))
        suite.expect(p.state == .prompting(id: id, seen: false, deadline: nil), "no deadline before present")
        p.presented(id: id, deadline: t0.addingTimeInterval(80))
        suite.expect(tick(&p, .active, now: t0.addingTimeInterval(79)).isEmpty, "before the deadline nothing ends")
        suite.expect(tick(&p, .active, now: t0.addingTimeInterval(80)) == [.ended(id, advance: true)],
                     "the deadline ends a seen prompt and advances")
        suite.expect(p.state == .counting(0), "timeout returns to counting")

        // Busy and off while prompting.
        var b = BreakSchedule(state: .prompting(id: id, seen: true, deadline: nil))
        suite.expect(tick(&b, .busy) == [.ended(id, advance: false)] && b.state == .deferred(0),
                     "a call starting mid-prompt dismisses and defers")
        var o = BreakSchedule(state: .prompting(id: id, seen: true, deadline: nil))
        suite.expect(tick(&o, .off) == [.ended(id, advance: false)] && o.state == .counting(0),
                     "pause mid-prompt dismisses and resets")

        // Responses.
        var r = BreakSchedule(state: .prompting(id: id, seen: true, deadline: nil))
        suite.expect(r.respond(id: UUID(), action: .done, now: t0).isEmpty, "a stale id is ignored")
        suite.expect(r.respond(id: id, action: .snooze, now: t0) == [.ended(id, advance: false)],
                     "snooze dismisses without advancing")
        suite.expect(r.state == .snoozed(until: t0.addingTimeInterval(300)), "snooze lasts 5 minutes")
        _ = tick(&r, .busy, now: t0.addingTimeInterval(100))
        suite.expect(r.state == .snoozed(until: t0.addingTimeInterval(300)), "snoozed ignores busy before it ends")
        _ = tick(&r, .active, now: t0.addingTimeInterval(300))
        suite.expect(r.state == .due, "snooze end goes due")
        var sOff = BreakSchedule(state: .snoozed(until: t0.addingTimeInterval(300)))
        _ = tick(&sOff, .off)
        suite.expect(sOff.state == .counting(0), "off while snoozed resets")
        var done = BreakSchedule(state: .prompting(id: id, seen: true, deadline: nil))
        suite.expect(done.respond(id: id, action: .done, now: t0) == [.ended(id, advance: true)]
                        && done.state == .counting(0), "done advances and resets")

        // Absence.
        var a = BreakSchedule(state: .counting(90))
        _ = tick(&a, .idle, idle: 119)
        suite.expect(a.state == .counting(95), "an idle stretch under the threshold still counts")
        _ = tick(&a, .idle, idle: 120)
        suite.expect(a.state == .counting(0), "idle at max(breakLength, 2 min) resets")
        for i in 0..<300 { _ = tick(&a, .idle, idle: 125 + Double(i) * 5) }
        suite.expect(a.state == .counting(0), "25 minutes idle holds the countdown at zero")
        var aw = BreakSchedule(state: .prompting(id: id, seen: true, deadline: nil))
        suite.expect(tick(&aw, .active, away: 180) == [.ended(id, advance: true)] && aw.state == .counting(0),
                     "an absence while a seen prompt is up counts as taken")
        var aw2 = BreakSchedule(state: .prompting(id: id, seen: false, deadline: nil))
        suite.expect(tick(&aw2, .active, away: 180) == [.ended(id, advance: false)],
                     "an absence over an unseen prompt does not advance")
        var shortAway = BreakSchedule(state: .counting(50))
        _ = tick(&shortAway, .active, away: 60)
        suite.expect(shortAway.state == .counting(55), "a short absence does not reset")

        // Disable and settings change.
        var off = BreakSchedule(state: .prompting(id: id, seen: true, deadline: nil))
        var disabled = k; disabled.enabled = false
        suite.expect(tick(&off, .active, kind: disabled) == [.ended(id, advance: false)] && off.state == .counting(0),
                     "disabling mid-prompt dismisses and resets")
        var longer = k; longer.interval = 200
        var keep = BreakSchedule(state: .counting(150))
        _ = tick(&keep, .active, kind: longer)
        suite.expect(keep.state == .counting(155), "a longer interval keeps elapsed time")
        var shorter = k; shorter.interval = 50
        var cut = BreakSchedule(state: .counting(60))
        _ = tick(&cut, .active, kind: shorter)
        suite.expect(cut.state == .due, "a shorter interval re-checks due")
    }

    static func presence(_ suite: TestSuite) {
        let t0 = date(30, 10)
        var away = AwayTracker()
        away.begin(.locked, now: t0)
        away.begin(.screensAsleep, now: t0.addingTimeInterval(10))
        suite.expect(away.end(.screensAsleep, now: t0.addingTimeInterval(60)) == nil,
                     "waking the screen while still locked is still away")
        suite.expect(away.end(.locked, now: t0.addingTimeInterval(200)) == 200,
                     "unlock ends the absence once, measured from its first condition")
        suite.expect(!away.isAway && away.end(.locked, now: t0.addingTimeInterval(300)) == nil,
                     "a second unlock reports nothing")

        var lost = AwayTracker()
        lost.begin(.asleep, now: t0)
        suite.expect(lost.watchdog(now: t0.addingTimeInterval(60), screenLocked: false, idleSeconds: 120) == nil,
                     "the watchdog waits for real input")
        suite.expect(lost.watchdog(now: t0.addingTimeInterval(120), screenLocked: true, idleSeconds: 1) == nil,
                     "the watchdog waits for unlock")
        suite.expect(lost.watchdog(now: t0.addingTimeInterval(180), screenLocked: false, idleSeconds: 1) == 180,
                     "a missed wake notification is recovered by the watchdog")

        var clock = TickClock()
        clock.reset(now: t0)
        let normal = clock.step(now: t0.addingTimeInterval(5), interval: 5)
        suite.expect(normal.dt == 5 && normal.gap == nil, "a normal tick counts its time")
        let gap = clock.step(now: t0.addingTimeInterval(605), interval: 5)
        suite.expect(gap.dt == 0 && gap.gap == 600, "a gap over 2x the tick becomes an absence")
        let back = clock.step(now: t0.addingTimeInterval(500), interval: 5)
        suite.expect(back.dt == 0 && back.gap == nil, "negative and huge gaps never count backwards")

        var watch = NotchBreakWatch()
        let id = UUID()
        suite.expect(watch.displaced(id: id, currentCaptureID: UUID(), visible: false, expanded: true, now: t0),
                     "a replaced capture is displaced at once")
        suite.expect(!watch.displaced(id: id, currentCaptureID: id, visible: false, expanded: true, now: t0),
                     "invisibility starts a timer")
        suite.expect(!watch.displaced(id: id, currentCaptureID: id, visible: false, expanded: true,
                                      now: t0.addingTimeInterval(9)), "under 10 s is not displaced")
        suite.expect(watch.displaced(id: id, currentCaptureID: id, visible: false, expanded: true,
                                     now: t0.addingTimeInterval(10)), "10 s invisible while expanded is displaced")
        var collapsed = NotchBreakWatch()
        _ = collapsed.displaced(id: id, currentCaptureID: id, visible: false, expanded: false, now: t0)
        suite.expect(!collapsed.displaced(id: id, currentCaptureID: id, visible: false, expanded: false,
                                          now: t0.addingTimeInterval(60)), "a collapsed island is never the watch's call")
        var seen = NotchBreakWatch()
        _ = seen.displaced(id: id, currentCaptureID: id, visible: false, expanded: true, now: t0)
        _ = seen.displaced(id: id, currentCaptureID: id, visible: true, expanded: true, now: t0.addingTimeInterval(5))
        suite.expect(!seen.displaced(id: id, currentCaptureID: id, visible: false, expanded: true,
                                     now: t0.addingTimeInterval(12)), "becoming visible restarts the timer")
    }
}
