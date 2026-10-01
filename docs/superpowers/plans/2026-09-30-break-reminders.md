---
title: Break Reminders implementation plan
created: 2026-09-30T00:00:00-04:00
tags: [plan, break-reminders]
---

# Break Reminders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Always-on eye and movement break reminders that defer during calls and fullscreen, reset after real absences, and deliver via notch, notification, escalating, or overlay.

**Architecture:** Pure, AppKit-free core (`BreakReminderModels`, `BusyPolicy`, `BreakSchedule`, `BreakCoordinator`, `ActivityRotation`, `AwayTracker`, `NotchBreakWatch`) driven by a thin `BreakReminderService` that samples signals and executes coordinator outputs against three delivery sinks. The notch sink reuses `NotchService.presentCapture` with a new route.

**Tech Stack:** Swift 5.9, AppKit, SwiftUI, CoreAudio, CoreMediaIO, UserNotifications. Tests: custom harness via `./build.sh --test`.

**Spec:** `docs/superpowers/specs/2026-09-30-break-reminders-design.md`

## Global Constraints

- Package targets macOS 14 (`Package.swift:9`).
- Pure files import `Foundation` only and are listed in `build.sh`'s `TEST_SOURCES` (the `if (( TEST ))` block); the test build fails to link otherwise.
- New test suites are `enum XxxTests { static func run(_ suite: TestSuite) }` using `suite.expect(cond, "message")`, and only run once appended to the registry array in `Tests/MetricsTests.swift`.
- Every new `DefaultsKey` is registered in `Defaults.registeredDefaults` (`Core/Defaults.swift`, the dictionary around line 1428), so settings backup includes it.
- A literal `%` in any localized format string is `%%` in every locale (`e21313f6`).
- Every language in `AppLanguage` (15: enUS, ptBR, tr, ru, es, sk, de, fr, it, ja, ko, zhHans, zhTW, zhHK, uk) gets every new string; strings live in a `Core/BreakReminderStrings.swift` struct with one `static let` per language, the same shape as `Core/KeepAwakeStrings.swift`.
- New source files carry the two-line SPDX header used throughout: `// SPDX-License-Identifier: GPL-3.0-or-later` / `// Copyright (C) 2026 Vorssaint`.
- Commit subjects: conventional style, `feat(break-reminders): …`. No AI attribution trailers.
- Run the harness bounded: `timeout 600 ./build.sh --test`. A single suite: `timeout 600 ./build.sh --test-suite=break-reminders`.

## Review Focus

1. A Mac without a notch with the Notch feature off and delivery style `notch`: the prompt must still appear (notification, then overlay), never vanish. Pinned by Task 6 test "notch failure falls through to notification then overlay".
2. Clock jumps (sleep without notification, manual time change backward): `dt` must never be negative or huge. Pinned by Task 5 test "negative and huge gaps".
3. Activity list edited to empty while a prompt is live: no crash, generic text. Pinned by Task 2 test "empty list returns nil" and Task 6 test "prompt with empty activity list".
4. Working hours where start equals end or days mask is 0: verdict must not be permanently `off` silently; settings clamp. Pinned by Task 3 test "degenerate working hours treated as disabled".
5. Both kinds disabled while a prompt is live: prompt dismissed, nothing re-fires. Pinned by Task 6 test "disabling both kinds dismisses".

---

### Task 1: Verify the recalled macOS APIs

The spec marks three API details as recalled. Confirm them before code depends on them. This task produces a throwaway probe and a note; the probe is not committed.

**Files:**
- Create (scratch, not committed): `$SCRATCH/api-probe.swift`
- Modify: `docs/superpowers/specs/2026-09-30-break-reminders-design.md` (only if a check fails)

**Interfaces:** Produces: confirmed names for `kAudioHardwarePropertyProcessObjectList`, `kAudioProcessPropertyIsRunningInput`, `kAudioProcessPropertyPID`, `kCMIODevicePropertyDeviceIsRunningSomewhere`, and the idle call.

- [ ] **Step 1: Write the probe**

```swift
import CoreAudio
import CoreMediaIO
import CoreGraphics
import Foundation

func procs() -> [AudioObjectID] {
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                          mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
    return ids
}
func u32(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector) -> UInt32 {
    var addr = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    var v: UInt32 = 0; var s = UInt32(MemoryLayout<UInt32>.size)
    AudioObjectGetPropertyData(id, &addr, 0, nil, &s, &v); return v
}
func pid(_ id: AudioObjectID) -> pid_t {
    var addr = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID, mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    var v: pid_t = 0; var s = UInt32(MemoryLayout<pid_t>.size)
    AudioObjectGetPropertyData(id, &addr, 0, nil, &s, &v); return v
}
for p in procs() where u32(p, kAudioProcessPropertyIsRunningInput) != 0 { print("input pid", pid(p)) }

var cam = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                    mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                    mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
var size: UInt32 = 0
CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &cam, 0, nil, &size)
var devs = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
var used: UInt32 = 0
CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &cam, 0, nil, size, &used, &devs)
for d in devs {
    var a = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                      mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                                      mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
    var v: UInt32 = 0; var u: UInt32 = 0
    CMIOObjectGetPropertyData(d, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &u, &v)
    print("camera", d, "running", v)
}
print("idle", CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: CGEventType(rawValue: ~0)!))
```

- [ ] **Step 2: Run it idle, then while recording in Voice Memos, then with Photo Booth open**

Run: `swiftc -O $SCRATCH/api-probe.swift -o $SCRATCH/api-probe && $SCRATCH/api-probe`
Expected: no `input pid` lines idle; one `input pid <VoiceMemos pid>` while recording; `camera … running 1` with Photo Booth; `idle` grows while hands are off the keyboard. Play music through headphones and confirm no `input pid` line.

- [ ] **Step 3: Record the result**

If all four behave as expected, change nothing. If any fails, edit the Signals section of the spec with the working call and note the change in the commit body of Task 8.

---

### Task 2: Models and ActivityRotation

**Files:**
- Create: `Sources/Vorssaint/Services/BreakReminders/BreakReminderModels.swift`
- Create: `Sources/Vorssaint/Services/BreakReminders/ActivityRotation.swift`
- Create: `Tests/BreakReminderTests.swift`
- Modify: `build.sh` (append both sources to `TEST_SOURCES`, before `build/generated-tests/*.swift`)
- Modify: `Tests/MetricsTests.swift` (append registry entry)

**Interfaces:**
- Produces: `BreakKind`, `DeliveryStyle`, `BreakActivity`, `WorkingHours`, `KindSettings`, `BreakSettings`, `BreakSignals`, `BusyVerdict`, `BreakAction`, `BreakPrompt`, `ActivityRotation` exactly as below.

- [ ] **Step 1: Write the models file**

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum BreakKind: String, CaseIterable, Codable { case eyes, movement }

enum DeliveryStyle: String, CaseIterable, Codable { case notch, notification, escalating, overlay }

struct BreakActivity: Codable, Equatable {
    var id: UUID
    var text: String
    var seconds: Int
}

/// `days` bit n = Calendar weekday n+1 (bit 0 = Sunday). Start inclusive, end exclusive.
struct WorkingHours: Equatable {
    var enabled: Bool
    var days: Int
    var startMinutes: Int
    var endMinutes: Int

    /// Degenerate hours (no day selected, or start >= end) behave as disabled.
    var isEffective: Bool { enabled && days & 0x7F != 0 && startMinutes < endMinutes }

    func contains(_ date: Date, calendar: Calendar) -> Bool {
        guard isEffective else { return true }
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = parts.weekday, days & (1 << (weekday - 1)) != 0 else { return false }
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return minute >= startMinutes && minute < endMinutes
    }
}

struct KindSettings: Equatable {
    var enabled: Bool
    var interval: TimeInterval
    var breakLength: TimeInterval
    var style: DeliveryStyle
    var activities: [BreakActivity]

    var resetThreshold: TimeInterval { max(breakLength, 120) }
}

struct BreakSettings: Equatable {
    var eyes: KindSettings
    var movement: KindSettings
    var escalateAfter: TimeInterval
    var hours: WorkingHours
    var pausedUntil: Date?

    subscript(kind: BreakKind) -> KindSettings {
        get { kind == .eyes ? eyes : movement }
        set { if kind == .eyes { eyes = newValue } else { movement = newValue } }
    }
}

struct BreakSignals: Equatable {
    var micInUse = false
    var cameraInUse = false
    var fullscreenFrontmost = false
    var idleSeconds: TimeInterval = 0
}

enum BusyVerdict: Equatable { case off, idle, busy, active }

enum BreakAction: Equatable { case done, skip, snooze }

struct BreakPrompt: Equatable {
    let id: UUID
    let kind: BreakKind
    /// nil when the kind's list is empty; the sink shows the generic message.
    let activity: BreakActivity?
    /// The activity's own seconds, or the kind's break length.
    let seconds: Int
}
```

- [ ] **Step 2: Write ActivityRotation**

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// In-order rotation per kind. The index advances only when a prompt ends
/// as taken (done, skip, timeout after being seen, absence while seen).
struct ActivityRotation: Equatable {
    var indices: [BreakKind: Int] = [:]

    func current(_ kind: BreakKind, in list: [BreakActivity]) -> BreakActivity? {
        guard !list.isEmpty else { return nil }
        return list[min(max(indices[kind] ?? 0, 0), list.count - 1)]
    }

    mutating func advance(_ kind: BreakKind, count: Int) {
        guard count > 0 else { indices[kind] = 0; return }
        let clamped = min(max(indices[kind] ?? 0, 0), count - 1)
        indices[kind] = (clamped + 1) % count
    }
}
```

- [ ] **Step 3: Write the failing tests**

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum BreakReminderTests {
    static func run(_ suite: TestSuite) {
        rotation(suite)
    }

    static func activity(_ text: String, _ seconds: Int = 20) -> BreakActivity {
        BreakActivity(id: UUID(), text: text, seconds: seconds)
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
}
```

- [ ] **Step 4: Register sources and suite**

In `build.sh`, add inside `TEST_SOURCES=(` just above `build/generated-tests/*.swift`:

```bash
        Sources/Vorssaint/Services/BreakReminders/BreakReminderModels.swift
        Sources/Vorssaint/Services/BreakReminders/ActivityRotation.swift
```

In `Tests/MetricsTests.swift`, append to the `groups` array:

```swift
            ("break-reminders", { BreakReminderTests.run(suite) }),
```

- [ ] **Step 5: Run the suite**

Run: `timeout 600 ./build.sh --test-suite=break-reminders`
Expected: PASS, 10 checks in `break-reminders`. (Write the tests first and run once before Step 1–2 exist if you want the red step: it fails to compile with `cannot find 'ActivityRotation' in scope`.)

- [ ] **Step 6: Commit**

```bash
git add Sources/Vorssaint/Services/BreakReminders/BreakReminderModels.swift Sources/Vorssaint/Services/BreakReminders/ActivityRotation.swift Tests/BreakReminderTests.swift Tests/MetricsTests.swift build.sh
git commit -m "feat(break-reminders): add the break models and activity rotation"
```

---

### Task 3: BusyPolicy and pause times

**Files:**
- Create: `Sources/Vorssaint/Services/BreakReminders/BusyPolicy.swift`
- Modify: `Tests/BreakReminderTests.swift`, `build.sh` (append source)

**Interfaces:**
- Consumes: `BreakSignals`, `BreakSettings`, `WorkingHours`, `BusyVerdict` (Task 2).
- Produces: `BusyPolicy.verdict(_:settings:now:calendar:) -> BusyVerdict`, `BusyPolicy.pauseUntilTomorrow(now:hours:calendar:) -> Date`, `BusyPolicy.idleThreshold: TimeInterval = 60`.

- [ ] **Step 1: Write the failing tests** (add `policy(suite)` to `run`)

```swift
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
```

- [ ] **Step 2: Run to verify failure**

Run: `timeout 600 ./build.sh --test-suite=break-reminders`
Expected: compile error `cannot find 'BusyPolicy' in scope`.

- [ ] **Step 3: Implement**

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum BusyPolicy {
    static let idleThreshold: TimeInterval = 60

    /// First match wins: off, idle, busy, active.
    static func verdict(_ s: BreakSignals, settings: BreakSettings, now: Date, calendar: Calendar) -> BusyVerdict {
        if let until = settings.pausedUntil, until > now { return .off }
        if !settings.hours.contains(now, calendar: calendar) { return .off }
        if s.idleSeconds >= idleThreshold { return .idle }
        if s.micInUse || s.cameraInUse || s.fullscreenFrontmost { return .busy }
        return .active
    }

    /// Working start on the first calendar day after today whose bit is set;
    /// next local midnight when working hours are not in effect.
    static func pauseUntilTomorrow(now: Date, hours: WorkingHours, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        let midnight = calendar.date(byAdding: .day, value: 1, to: today)!
        guard hours.isEffective else { return midnight }
        for offset in 1...7 {
            let day = calendar.date(byAdding: .day, value: offset, to: today)!
            let weekday = calendar.component(.weekday, from: day)
            if hours.days & (1 << (weekday - 1)) != 0 {
                return calendar.date(byAdding: .minute, value: hours.startMinutes, to: day)!
            }
        }
        return midnight
    }
}
```

Append `Sources/Vorssaint/Services/BreakReminders/BusyPolicy.swift` to `TEST_SOURCES`.

- [ ] **Step 4: Run to verify pass**

Run: `timeout 600 ./build.sh --test-suite=break-reminders`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Vorssaint/Services/BreakReminders/BusyPolicy.swift Tests/BreakReminderTests.swift build.sh
git commit -m "feat(break-reminders): add the busy verdict and pause times"
```

---

### Task 4: BreakSchedule state machine

**Files:**
- Create: `Sources/Vorssaint/Services/BreakReminders/BreakSchedule.swift`
- Modify: `Tests/BreakReminderTests.swift`, `build.sh`

**Interfaces:**
- Consumes: `KindSettings`, `BusyVerdict`, `BreakAction` (Task 2).
- Produces:

```swift
struct BreakSchedule {
    enum State: Equatable {
        case counting(TimeInterval), due, deferred(TimeInterval)
        case prompting(id: UUID, seen: Bool, deadline: Date?)
        case snoozed(until: Date)
    }
    enum Event: Equatable { case prompt(UUID), ended(UUID, advance: Bool) }
    private(set) var state: State
    mutating func tick(dt: TimeInterval, verdict: BusyVerdict, idleSeconds: TimeInterval,
                       awayFor: TimeInterval?, settings: KindSettings, now: Date,
                       newID: () -> UUID) -> [Event]
    mutating func presented(id: UUID, deadline: Date?)
    mutating func respond(id: UUID, action: BreakAction, now: Date) -> [Event]
    mutating func reset() -> [Event]   // ended(advance: false) if prompting
}
```

- [ ] **Step 1: Write the failing tests** (add `schedule(suite)` to `run`)

```swift
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
```

- [ ] **Step 2: Run to verify failure**

Run: `timeout 600 ./build.sh --test-suite=break-reminders`
Expected: compile error `cannot find 'BreakSchedule' in scope`.

- [ ] **Step 3: Implement**

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One kind's countdown. At most one transition per tick; the crossing tick
/// emits nothing, so the next tick decides on freshly sampled busy signals.
struct BreakSchedule {
    enum State: Equatable {
        case counting(TimeInterval)
        case due
        case deferred(TimeInterval)
        /// `seen` turns true when a sink actually showed it; `deadline` is
        /// the no-response timeout measured from that moment.
        case prompting(id: UUID, seen: Bool, deadline: Date?)
        case snoozed(until: Date)
    }

    enum Event: Equatable {
        case prompt(UUID)
        case ended(UUID, advance: Bool)
    }

    static let grace: TimeInterval = 30
    static let snoozeLength: TimeInterval = 300

    private(set) var state: State

    init(state: State = .counting(0)) { self.state = state }

    mutating func tick(dt: TimeInterval, verdict: BusyVerdict, idleSeconds: TimeInterval,
                       awayFor: TimeInterval?, settings: KindSettings, now: Date,
                       newID: () -> UUID) -> [Event] {
        let dt = max(0, dt)
        guard settings.enabled else { return reset() }

        let threshold = settings.resetThreshold
        if (awayFor ?? 0) >= threshold || idleSeconds >= threshold {
            if case let .prompting(id, seen, _) = state {
                state = .counting(0)
                return [.ended(id, advance: seen)]
            }
            state = .counting(0)
            return []
        }

        switch state {
        case let .counting(elapsed):
            if elapsed >= settings.interval { state = .due; return [] }
            let next = verdict == .off ? elapsed : elapsed + dt
            state = next >= settings.interval ? .due : .counting(next)
            return []
        case .due:
            switch verdict {
            case .active: return startPrompt(newID())
            case .busy, .idle: state = .deferred(0)
            case .off: break
            }
            return []
        case let .deferred(activeFor):
            guard verdict == .active else { state = .deferred(0); return [] }
            let next = activeFor + dt
            if next >= Self.grace { return startPrompt(newID()) }
            state = .deferred(next)
            return []
        case let .prompting(id, seen, deadline):
            switch verdict {
            case .busy:
                state = .deferred(0)
                return [.ended(id, advance: false)]
            case .off:
                state = .counting(0)
                return [.ended(id, advance: false)]
            case .active, .idle:
                if let deadline, now >= deadline {
                    state = .counting(0)
                    return [.ended(id, advance: seen)]
                }
                return []
            }
        case let .snoozed(until):
            if verdict == .off { state = .counting(0) }
            else if now >= until { state = .due }
            return []
        }
    }

    mutating func presented(id: UUID, deadline: Date?) {
        guard case let .prompting(current, _, _) = state, current == id else { return }
        state = .prompting(id: id, seen: true, deadline: deadline)
    }

    mutating func respond(id: UUID, action: BreakAction, now: Date) -> [Event] {
        guard case let .prompting(current, _, _) = state, current == id else { return [] }
        switch action {
        case .done, .skip:
            state = .counting(0)
            return [.ended(id, advance: true)]
        case .snooze:
            state = .snoozed(until: now.addingTimeInterval(Self.snoozeLength))
            return [.ended(id, advance: false)]
        }
    }

    mutating func reset() -> [Event] {
        defer { state = .counting(0) }
        if case let .prompting(id, _, _) = state { return [.ended(id, advance: false)] }
        return []
    }

    private mutating func startPrompt(_ id: UUID) -> [Event] {
        state = .prompting(id: id, seen: false, deadline: nil)
        return [.prompt(id)]
    }
}
```

Note the `counting` branch: entering with `elapsed >= interval` (a shortened interval) goes due without adding time; otherwise it adds time and may go due in the same tick, emitting nothing either way. Append the source to `TEST_SOURCES`.

- [ ] **Step 4: Run to verify pass**

Run: `timeout 600 ./build.sh --test-suite=break-reminders`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Vorssaint/Services/BreakReminders/BreakSchedule.swift Tests/BreakReminderTests.swift build.sh
git commit -m "feat(break-reminders): add the per-kind break schedule"
```

---

### Task 5: AwayTracker, TickClock, NotchBreakWatch

**Files:**
- Create: `Sources/Vorssaint/Services/BreakReminders/BreakPresence.swift`
- Modify: `Tests/BreakReminderTests.swift`, `build.sh`

**Interfaces:**
- Produces:

```swift
struct AwayTracker {
    enum Condition: Hashable { case locked, sessionInactive, asleep, screensAsleep }
    private(set) var conditions: Set<Condition>
    var isAway: Bool { get }
    mutating func begin(_ c: Condition, now: Date)
    mutating func end(_ c: Condition, now: Date) -> TimeInterval?
    mutating func watchdog(now: Date, screenLocked: Bool, idleSeconds: TimeInterval) -> TimeInterval?
}
struct TickClock {
    mutating func step(now: Date, interval: TimeInterval) -> (dt: TimeInterval, gap: TimeInterval?)
    mutating func reset(now: Date)
}
struct NotchBreakWatch {
    mutating func displaced(id: UUID, currentCaptureID: UUID?, visible: Bool, expanded: Bool, now: Date) -> Bool
}
```

- [ ] **Step 1: Write the failing tests** (add `presence(suite)` to `run`)

```swift
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
```

- [ ] **Step 2: Run to verify failure**

Run: `timeout 600 ./build.sh --test-suite=break-reminders`
Expected: compile error `cannot find 'AwayTracker' in scope`.

- [ ] **Step 3: Implement**

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Away lasts while any condition holds; it ends once, when the last clears.
struct AwayTracker {
    enum Condition: Hashable { case locked, sessionInactive, asleep, screensAsleep }

    private(set) var conditions: Set<Condition> = []
    private var start: Date?

    var isAway: Bool { !conditions.isEmpty }

    mutating func begin(_ c: Condition, now: Date) {
        if conditions.isEmpty { start = now }
        conditions.insert(c)
    }

    mutating func end(_ c: Condition, now: Date) -> TimeInterval? {
        guard conditions.remove(c) != nil, conditions.isEmpty else { return nil }
        return finish(now)
    }

    /// Recovers from a missed wake or unlock notification.
    mutating func watchdog(now: Date, screenLocked: Bool, idleSeconds: TimeInterval) -> TimeInterval? {
        guard isAway, !screenLocked, idleSeconds < BusyPolicy.idleThreshold else { return nil }
        conditions.removeAll()
        return finish(now)
    }

    private mutating func finish(_ now: Date) -> TimeInterval? {
        defer { start = nil }
        return start.map { max(0, now.timeIntervalSince($0)) }
    }
}

struct TickClock {
    private var last: Date?

    mutating func reset(now: Date) { last = now }

    /// A gap over twice the tick is an absence (dt 0); a backwards jump counts nothing.
    mutating func step(now: Date, interval: TimeInterval) -> (dt: TimeInterval, gap: TimeInterval?) {
        defer { last = now }
        guard let last else { return (0, nil) }
        let delta = now.timeIntervalSince(last)
        if delta < 0 { return (0, nil) }
        if delta > interval * 2 { return (0, delta) }
        return (delta, nil)
    }
}

/// Backstop for paths that hide a notch break without collapsing the island.
struct NotchBreakWatch {
    static let limit: TimeInterval = 10
    private var invisibleSince: Date?

    mutating func displaced(id: UUID, currentCaptureID: UUID?, visible: Bool, expanded: Bool, now: Date) -> Bool {
        if currentCaptureID != id { return true }
        guard expanded, !visible else { invisibleSince = nil; return false }
        let since = invisibleSince ?? now
        invisibleSince = since
        return now.timeIntervalSince(since) >= Self.limit
    }
}
```

Append the source to `TEST_SOURCES` (it references `BusyPolicy`, already listed).

- [ ] **Step 4: Run to verify pass**

Run: `timeout 600 ./build.sh --test-suite=break-reminders`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Vorssaint/Services/BreakReminders/BreakPresence.swift Tests/BreakReminderTests.swift build.sh
git commit -m "feat(break-reminders): track absences, tick gaps and notch displacement"
```

---

### Task 6: BreakCoordinator

**Files:**
- Create: `Sources/Vorssaint/Services/BreakReminders/BreakCoordinator.swift`
- Modify: `Tests/BreakReminderTests.swift`, `build.sh`

**Interfaces:**
- Consumes: Tasks 2–4.
- Produces:

```swift
struct BreakCoordinator {
    enum Output: Equatable {
        case present(BreakPrompt, via: DeliveryStyle)
        case dismiss(UUID, via: DeliveryStyle)
    }
    private(set) var schedules: [BreakKind: BreakSchedule]
    private(set) var rotation: ActivityRotation
    init(rotation: ActivityRotation)
    var livePromptID: UUID? { get }
    var needsBusySignals: Bool { get }      // any kind due, deferred or prompting
    mutating func tick(now: Date, dt: TimeInterval, verdict: BusyVerdict, idleSeconds: TimeInterval,
                       awayFor: TimeInterval?, settings: BreakSettings, newID: () -> UUID) -> [Output]
    mutating func presented(id: UUID, via: DeliveryStyle, now: Date, settings: BreakSettings)
    mutating func deliveryFailed(id: UUID, via: DeliveryStyle, now: Date, settings: BreakSettings) -> [Output]
    mutating func displaced(id: UUID, via: DeliveryStyle, now: Date, settings: BreakSettings) -> [Output]
    mutating func respond(id: UUID, action: BreakAction, now: Date, settings: BreakSettings) -> [Output]
    mutating func settingsChanged(from old: BreakSettings, to new: BreakSettings) -> [Output]
    mutating func stop() -> [Output]
}
```

Delivery chain rules (from the spec):
- Order for a requested style: `[requested] + [.notch, .notification, .overlay]` minus the requested one, each at most once. For `.escalating` the chain is `[.notch, .notification, .overlay]` and `.overlay` is the escalation stage.
- `deliveryFailed` (present returned false or a sink failed before showing): next style in the chain; nothing left → the prompt ends unseen (`reset`, no advance).
- `displaced` after a successful present: escalating → overlay directly; otherwise next in chain.
- Timeout deadlines, set in `presented`: overlay → `now + seconds + 60`; notch/notification as a final style → `now + 600`; notch/notification as the first stage of escalating → no deadline, and `escalateAt = now + escalateAfter`.
- At `escalateAt`: `dismiss(current)` then `present(overlay)`.

- [ ] **Step 1: Write the failing tests** (add `coordinator(suite)` to `run`)

```swift
    static func coordinator(_ suite: TestSuite) {
        let t0 = date(30, 10)
        var ids: [UUID] = (0..<20).map { _ in UUID() }
        func next() -> UUID { ids.removeFirst() }
        func base(eyes: DeliveryStyle = .overlay, movement: DeliveryStyle = .overlay) -> BreakSettings {
            var s = settings()
            s.eyes = KindSettings(enabled: true, interval: 100, breakLength: 20, style: eyes,
                                  activities: [activity("look", 20), activity("close", 10)])
            s.movement = KindSettings(enabled: true, interval: 300, breakLength: 120, style: movement,
                                      activities: [activity("stretch", 60)])
            return s
        }
        func run(_ c: inout BreakCoordinator, _ s: BreakSettings, seconds: Int, verdict: BusyVerdict = .active,
                 from start: Date = t0) -> [BreakCoordinator.Output] {
            var out: [BreakCoordinator.Output] = []
            for i in 0..<(seconds / 5) {
                out += c.tick(now: start.addingTimeInterval(Double(i + 1) * 5), dt: 5, verdict: verdict,
                              idleSeconds: 0, awayFor: nil, settings: s, newID: next)
            }
            return out
        }
        func presents(_ o: [BreakCoordinator.Output]) -> [(BreakKind, DeliveryStyle)] {
            o.compactMap { if case let .present(p, via) = $0 { return (p.kind, via) }; return nil }
        }

        // Eyes prompts after its interval plus one decision tick.
        var c = BreakCoordinator(rotation: ActivityRotation())
        let s = base()
        let first = run(&c, s, seconds: 105)
        suite.expect(presents(first).count == 1 && presents(first)[0] == (.eyes, .overlay),
                     "eyes presents via its style after its interval")
        guard let live = c.livePromptID else { suite.expect(false, "a live prompt exists"); return }
        if case let .present(p, _) = first.last! {
            suite.expect(p.activity?.text == "look" && p.seconds == 20, "the prompt carries the current activity")
        }
        c.presented(id: live, via: .overlay, now: t0.addingTimeInterval(105), settings: s)
        let ended = c.respond(id: live, action: .done, now: t0.addingTimeInterval(110), settings: s)
        suite.expect(ended == [.dismiss(live, via: .overlay)], "done dismisses the current sink")
        suite.expect(c.rotation.current(.eyes, in: s.eyes.activities)?.text == "close", "done advances the rotation")
        suite.expect(c.respond(id: live, action: .done, now: t0, settings: s).isEmpty, "a stale id is ignored")

        // Coalescing: movement prompting resets eyes in every state.
        for eyesState in [BreakSchedule.State.due, .deferred(10), .snoozed(until: t0.addingTimeInterval(60)),
                          .counting(45), .prompting(id: UUID(), seen: true, deadline: nil)] {
            var k = BreakCoordinator(rotation: ActivityRotation())
            k.forceState(.eyes, eyesState)
            k.forceState(.movement, .due)
            let out = k.tick(now: t0, dt: 5, verdict: .active, idleSeconds: 0, awayFor: nil, settings: base(),
                             newID: next)
            let kinds = presents(out).map { $0.0 }
            suite.expect(kinds == [.movement], "movement prompting absorbs eyes in state \(eyesState)")
            suite.expect(k.schedules[.eyes]?.state == .counting(0), "eyes resets when movement prompts (\(eyesState))")
        }
        // Eyes may not prompt near or during a movement break.
        for moveState in [BreakSchedule.State.due, .deferred(5), .snoozed(until: t0.addingTimeInterval(60)),
                          .counting(250)] {
            var k = BreakCoordinator(rotation: ActivityRotation())
            k.forceState(.eyes, .due)
            k.forceState(.movement, moveState)
            let out = k.tick(now: t0, dt: 5, verdict: .active, idleSeconds: 0, awayFor: nil, settings: base(),
                             newID: next)
            suite.expect(presents(out).allSatisfy { $0.0 != .eyes }, "eyes holds off while movement is \(moveState)")
        }
        var tie = BreakCoordinator(rotation: ActivityRotation())
        tie.forceState(.eyes, .due); tie.forceState(.movement, .due)
        let both = tie.tick(now: t0, dt: 5, verdict: .active, idleSeconds: 0, awayFor: nil, settings: base(), newID: next)
        suite.expect(presents(both).map { $0.0 } == [.movement], "a same-tick tie goes to movement")

        // Fallback chain.
        var f = BreakCoordinator(rotation: ActivityRotation())
        f.forceState(.eyes, .due)
        let notchFirst = base(eyes: .notch)
        let p0 = f.tick(now: t0, dt: 5, verdict: .active, idleSeconds: 0, awayFor: nil, settings: notchFirst, newID: next)
        suite.expect(presents(p0).map { $0.1 } == [.notch], "requested style first")
        let pid = f.livePromptID!
        suite.expect(presents(f.deliveryFailed(id: pid, via: .notch, now: t0, settings: notchFirst)).map { $0.1 } == [.notification],
                     "notch failure falls through to notification")
        suite.expect(presents(f.deliveryFailed(id: pid, via: .notification, now: t0, settings: notchFirst)).map { $0.1 } == [.overlay],
                     "notch failure falls through to notification then overlay")
        var n = BreakCoordinator(rotation: ActivityRotation())
        n.forceState(.eyes, .due)
        let notifFirst = base(eyes: .notification)
        _ = n.tick(now: t0, dt: 5, verdict: .active, idleSeconds: 0, awayFor: nil, settings: notifFirst, newID: next)
        suite.expect(presents(n.deliveryFailed(id: n.livePromptID!, via: .notification, now: t0, settings: notifFirst)).map { $0.1 }
                        == [.notch], "a failed notification tries the notch next")

        // Escalation.
        var e = BreakCoordinator(rotation: ActivityRotation())
        e.forceState(.movement, .due)
        let esc = base(movement: .escalating)
        let e0 = e.tick(now: t0, dt: 5, verdict: .active, idleSeconds: 0, awayFor: nil, settings: esc, newID: next)
        suite.expect(presents(e0).map { $0.1 } == [.notch], "escalating starts at the notch")
        let eid = e.livePromptID!
        e.presented(id: eid, via: .notch, now: t0, settings: esc)
        let early = e.tick(now: t0.addingTimeInterval(119), dt: 5, verdict: .active, idleSeconds: 0, awayFor: nil,
                           settings: esc, newID: next)
        suite.expect(early.isEmpty, "no escalation before escalateAfter")
        let up = e.tick(now: t0.addingTimeInterval(120), dt: 5, verdict: .active, idleSeconds: 0, awayFor: nil,
                        settings: esc, newID: next)
        suite.expect(up == [.dismiss(eid, via: .notch), .present(e.prompt(eid)!, via: .overlay)],
                     "escalation dismisses the current sink and presents the overlay")
        var dsp = BreakCoordinator(rotation: ActivityRotation())
        dsp.forceState(.movement, .due)
        _ = dsp.tick(now: t0, dt: 5, verdict: .active, idleSeconds: 0, awayFor: nil, settings: esc, newID: next)
        let did = dsp.livePromptID!
        dsp.presented(id: did, via: .notch, now: t0, settings: esc)
        suite.expect(presents(dsp.displaced(id: did, via: .notch, now: t0, settings: esc)).map { $0.1 } == [.overlay],
                     "displacement during escalating goes straight to the overlay")

        // Unseen prompts never advance; seen timeouts do.
        var u = BreakCoordinator(rotation: ActivityRotation())
        u.forceState(.eyes, .due)
        _ = u.tick(now: t0, dt: 5, verdict: .active, idleSeconds: 0, awayFor: nil, settings: s, newID: next)
        let uid = u.livePromptID!
        _ = u.tick(now: t0.addingTimeInterval(5), dt: 5, verdict: .busy, idleSeconds: 0, awayFor: nil, settings: s, newID: next)
        suite.expect(u.rotation.current(.eyes, in: s.eyes.activities)?.text == "look", "an unseen prompt does not advance")
        _ = uid

        var to = BreakCoordinator(rotation: ActivityRotation())
        to.forceState(.eyes, .due)
        _ = to.tick(now: t0, dt: 5, verdict: .active, idleSeconds: 0, awayFor: nil, settings: s, newID: next)
        let tid = to.livePromptID!
        to.presented(id: tid, via: .overlay, now: t0, settings: s)
        let timeout = to.tick(now: t0.addingTimeInterval(80), dt: 5, verdict: .active, idleSeconds: 0, awayFor: nil,
                              settings: s, newID: next)
        suite.expect(timeout == [.dismiss(tid, via: .overlay)], "overlay times out at seconds + 60 from present")
        suite.expect(to.rotation.current(.eyes, in: s.eyes.activities)?.text == "close", "a seen timeout advances")

        // Settings changes.
        var sc = BreakCoordinator(rotation: ActivityRotation())
        sc.forceState(.eyes, .due)
        _ = sc.tick(now: t0, dt: 5, verdict: .active, idleSeconds: 0, awayFor: nil, settings: s, newID: next)
        let sid = sc.livePromptID!
        sc.presented(id: sid, via: .overlay, now: t0, settings: s)
        let restyled = sc.settingsChanged(from: s, to: base(eyes: .notification))
        suite.expect(restyled.first == .dismiss(sid, via: .overlay) &&
                     presents(restyled).map { $0.1 } == [.notification] && sc.livePromptID == sid,
                     "a style change re-presents the same prompt id with the new style")
        var bothOff = base(); bothOff.eyes.enabled = false; bothOff.movement.enabled = false
        let killed = sc.tick(now: t0.addingTimeInterval(5), dt: 5, verdict: .active, idleSeconds: 0, awayFor: nil,
                             settings: bothOff, newID: next)
        suite.expect(killed == [.dismiss(sid, via: .notification)] && sc.livePromptID == nil,
                     "disabling both kinds dismisses")
        _ = run(&sc, bothOff, seconds: 1000, from: t0.addingTimeInterval(10))
        suite.expect(sc.livePromptID == nil, "nothing re-fires with both kinds disabled")

        var empty = BreakCoordinator(rotation: ActivityRotation())
        var noActivities = base(); noActivities.eyes.activities = []
        empty.forceState(.eyes, .due)
        let generic = empty.tick(now: t0, dt: 5, verdict: .active, idleSeconds: 0, awayFor: nil,
                                 settings: noActivities, newID: next)
        if case let .present(p, _)? = generic.first {
            suite.expect(p.activity == nil && p.seconds == 20, "prompt with empty activity list uses the break length")
        } else { suite.expect(false, "prompt with empty activity list still presents") }

        var stopping = BreakCoordinator(rotation: ActivityRotation())
        stopping.forceState(.eyes, .due)
        _ = stopping.tick(now: t0, dt: 5, verdict: .active, idleSeconds: 0, awayFor: nil, settings: s, newID: next)
        let sid2 = stopping.livePromptID!
        suite.expect(stopping.stop() == [.dismiss(sid2, via: .overlay)] && stopping.livePromptID == nil,
                     "stop dismisses the live prompt")
        suite.expect(stopping.deliveryFailed(id: sid2, via: .overlay, now: t0, settings: s).isEmpty,
                     "a fallback after stop presents nothing")

        // A long call: deferral fires 30 s after it ends.
        var call = BreakCoordinator(rotation: ActivityRotation())
        call.forceState(.eyes, .counting(0))
        var single = base(); single.movement.enabled = false
        let during = run(&call, single, seconds: 5400, verdict: .busy)
        suite.expect(presents(during).isEmpty, "nothing presents during a 90-minute call")
        let after = run(&call, single, seconds: 35, from: t0.addingTimeInterval(5400))
        suite.expect(presents(after).count == 1, "the deferred break fires 30 s after the call ends")
    }
```

`forceState(_:_:)` and `prompt(_:)` are test helpers on the coordinator; implement them in the source, marked as such.

- [ ] **Step 2: Run to verify failure**

Run: `timeout 600 ./build.sh --test-suite=break-reminders`
Expected: compile error `cannot find 'BreakCoordinator' in scope`.

- [ ] **Step 3: Implement**

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Owns both schedules, coalesces them, and drives one prompt at a time
/// through its delivery chain.
struct BreakCoordinator {
    enum Output: Equatable {
        case present(BreakPrompt, via: DeliveryStyle)
        case dismiss(UUID, via: DeliveryStyle)
    }

    private struct Live {
        var prompt: BreakPrompt
        var chain: [DeliveryStyle]
        var via: DeliveryStyle
        var escalating: Bool
        var escalateAt: Date?
    }

    static let finalTimeout: TimeInterval = 600
    static let overlayGrace: TimeInterval = 60
    static let nearDue: TimeInterval = 60

    private(set) var schedules: [BreakKind: BreakSchedule] = [.eyes: BreakSchedule(), .movement: BreakSchedule()]
    private(set) var rotation: ActivityRotation
    private var live: Live?
    private var stopped = false

    init(rotation: ActivityRotation) { self.rotation = rotation }

    var livePromptID: UUID? { live?.prompt.id }

    var needsBusySignals: Bool {
        schedules.values.contains {
            switch $0.state {
            case .due, .deferred, .prompting: return true
            case .counting, .snoozed: return false
            }
        }
    }

    // MARK: Tick

    mutating func tick(now: Date, dt: TimeInterval, verdict: BusyVerdict, idleSeconds: TimeInterval,
                       awayFor: TimeInterval?, settings: BreakSettings, newID: () -> UUID) -> [Output] {
        guard !stopped else { return [] }
        var out: [Output] = []
        var events: [BreakKind: [BreakSchedule.Event]] = [:]
        for kind in [BreakKind.movement, .eyes] {
            events[kind] = schedules[kind]!.tick(dt: dt, verdict: verdict, idleSeconds: idleSeconds, awayFor: awayFor,
                                                 settings: settings[kind], now: now, newID: newID)
        }
        for kind in [BreakKind.movement, .eyes] {
            for event in events[kind] ?? [] { if case let .ended(id, advance) = event {
                out += end(id: id, kind: kind, advance: advance, settings: settings)
            } }
        }

        let movementPrompted = events[.movement]!.contains { if case .prompt = $0 { return true }; return false }
        if movementPrompted {
            out += resetEyes(settings: settings)
            events[.eyes] = []
        } else if eyesWouldPrompt(events[.eyes]!), movementBlocksEyes(settings: settings) {
            _ = schedules[.eyes]!.reset()
            events[.eyes] = []
        }

        for kind in [BreakKind.movement, .eyes] {
            for event in events[kind] ?? [] { if case let .prompt(id) = event {
                out += start(id: id, kind: kind, settings: settings)
            } }
        }

        if var current = live, let at = current.escalateAt, now >= at {
            out.append(.dismiss(current.prompt.id, via: current.via))
            current.via = .overlay
            current.escalateAt = nil
            current.chain = []
            live = current
            out.append(.present(current.prompt, via: .overlay))
        }
        return out
    }

    // MARK: Sink callbacks

    mutating func presented(id: UUID, via: DeliveryStyle, now: Date, settings: BreakSettings) {
        guard var current = live, current.prompt.id == id, current.via == via else { return }
        let kind = current.prompt.kind
        let firstStage = current.escalating && via != .overlay
        let deadline: Date?
        if via == .overlay {
            deadline = now.addingTimeInterval(TimeInterval(current.prompt.seconds) + Self.overlayGrace)
        } else if firstStage {
            deadline = nil
            current.escalateAt = now.addingTimeInterval(settings.escalateAfter)
        } else {
            deadline = now.addingTimeInterval(Self.finalTimeout)
        }
        live = current
        schedules[kind]!.presented(id: id, deadline: deadline)
    }

    mutating func deliveryFailed(id: UUID, via: DeliveryStyle, now: Date, settings: BreakSettings) -> [Output] {
        guard !stopped, var current = live, current.prompt.id == id, current.via == via else { return [] }
        guard !current.chain.isEmpty else {
            live = nil
            _ = schedules[current.prompt.kind]!.reset()
            return []
        }
        current.via = current.chain.removeFirst()
        current.escalateAt = nil
        live = current
        return [.present(current.prompt, via: current.via)]
    }

    mutating func displaced(id: UUID, via: DeliveryStyle, now: Date, settings: BreakSettings) -> [Output] {
        guard !stopped, var current = live, current.prompt.id == id, current.via == via else { return [] }
        if current.escalating && via != .overlay {
            current.chain = []
            current.via = .overlay
            current.escalateAt = nil
            live = current
            return [.present(current.prompt, via: .overlay)]
        }
        return deliveryFailed(id: id, via: via, now: now, settings: settings)
    }

    mutating func respond(id: UUID, action: BreakAction, now: Date, settings: BreakSettings) -> [Output] {
        guard !stopped, let current = live, current.prompt.id == id else { return [] }
        let kind = current.prompt.kind
        var out: [Output] = []
        for event in schedules[kind]!.respond(id: id, action: action, now: now) {
            if case let .ended(endedID, advance) = event {
                out += end(id: endedID, kind: kind, advance: advance, settings: settings)
            }
        }
        return out
    }

    mutating func settingsChanged(from old: BreakSettings, to new: BreakSettings) -> [Output] {
        guard !stopped, var current = live else { return [] }
        let kind = current.prompt.kind
        guard old[kind].style != new[kind].style, new[kind].enabled else { return [] }
        let previous = current.via
        let chain = Self.chain(for: new[kind].style)
        current.via = chain.first!
        current.chain = Array(chain.dropFirst())
        current.escalating = new[kind].style == .escalating
        current.escalateAt = nil
        live = current
        return [.dismiss(current.prompt.id, via: previous), .present(current.prompt, via: current.via)]
    }

    mutating func stop() -> [Output] {
        stopped = true
        defer { live = nil }
        guard let current = live else { return [] }
        _ = schedules[current.prompt.kind]!.reset()
        return [.dismiss(current.prompt.id, via: current.via)]
    }

    // MARK: Helpers

    static func chain(for style: DeliveryStyle) -> [DeliveryStyle] {
        let order: [DeliveryStyle] = [.notch, .notification, .overlay]
        if style == .escalating { return order }
        return [style] + order.filter { $0 != style }
    }

    private mutating func start(id: UUID, kind: BreakKind, settings: BreakSettings) -> [Output] {
        let k = settings[kind]
        let activity = rotation.current(kind, in: k.activities)
        let prompt = BreakPrompt(id: id, kind: kind, activity: activity,
                                 seconds: activity?.seconds ?? Int(k.breakLength))
        let chain = Self.chain(for: k.style)
        live = Live(prompt: prompt, chain: Array(chain.dropFirst()), via: chain[0],
                    escalating: k.style == .escalating, escalateAt: nil)
        return [.present(prompt, via: chain[0])]
    }

    private mutating func end(id: UUID, kind: BreakKind, advance: Bool, settings: BreakSettings) -> [Output] {
        if advance { rotation.advance(kind, count: settings[kind].activities.count) }
        guard let current = live, current.prompt.id == id else { return [] }
        live = nil
        return [.dismiss(id, via: current.via)]
    }

    private mutating func resetEyes(settings: BreakSettings) -> [Output] {
        let near: Bool
        switch schedules[.eyes]!.state {
        case let .counting(e): near = e >= settings.eyes.interval - Self.nearDue
        case .due, .deferred, .snoozed, .prompting: near = true
        }
        guard near else { return [] }
        var out: [Output] = []
        for event in schedules[.eyes]!.reset() {
            if case let .ended(id, _) = event { out += end(id: id, kind: .eyes, advance: false, settings: settings) }
        }
        return out
    }

    private func eyesWouldPrompt(_ events: [BreakSchedule.Event]) -> Bool {
        events.contains { if case .prompt = $0 { return true }; return false }
    }

    private func movementBlocksEyes(settings: BreakSettings) -> Bool {
        guard settings.movement.enabled else { return false }
        switch schedules[.movement]!.state {
        case .due, .deferred, .prompting, .snoozed: return true
        case let .counting(e): return e >= settings.movement.interval - Self.nearDue
        }
    }

    // MARK: Test support (used only by Tests/BreakReminderTests.swift)

    mutating func forceState(_ kind: BreakKind, _ state: BreakSchedule.State) {
        schedules[kind] = BreakSchedule(state: state)
    }

    func prompt(_ id: UUID) -> BreakPrompt? { live?.prompt.id == id ? live?.prompt : nil }
}
```

Two details the tests pin and the code must keep: (a) the `escalating` first-stage deadline is nil, so the schedule never times out a notch stage; the overlay's `presented` sets the real deadline; (b) `end` advances the rotation even when the live prompt is already gone (a timeout racing a response), but only emits `dismiss` for the current one.

If the "eyes prompting while movement prompts" coalescing test fails because `resetEyes` sees `prompting` only after `tick` already ran, note that movement and eyes tick in that order (movement first), so eyes' `prompting` is from a previous tick and `resetEyes` dismisses it; eyes' own new prompt the same tick is dropped by `events[.eyes] = []`.

Append the source to `TEST_SOURCES`.

- [ ] **Step 4: Run to verify pass**

Run: `timeout 600 ./build.sh --test-suite=break-reminders`
Expected: PASS. If a coalescing or chain expectation fails, fix the coordinator, not the test: each test line quotes a spec rule.

- [ ] **Step 5: Commit**

```bash
git add Sources/Vorssaint/Services/BreakReminders/BreakCoordinator.swift Tests/BreakReminderTests.swift build.sh
git commit -m "feat(break-reminders): coordinate both kinds and the delivery chain"
```

---

### Task 7: Defaults keys, settings store, strings

**Files:**
- Modify: `Sources/Vorssaint/Core/Defaults.swift` (keys in `enum DefaultsKey`; values in `registeredDefaults` near line 1428)
- Create: `Sources/Vorssaint/Services/BreakReminders/BreakSettingsStore.swift`
- Create: `Sources/Vorssaint/Core/BreakReminderStrings.swift`
- Modify: `Tests/BreakReminderTests.swift`, `build.sh`

**Interfaces:**
- Produces: `DefaultsKey.breakReminders*` (below), `DefaultsKey.notchBreakReminders`, `BreakSettingsStore.load(_ defaults: UserDefaults, language: AppLanguage) -> BreakSettings`, `BreakSettingsStore.save(_ settings: BreakSettings, to: UserDefaults)`, `BreakSettingsStore.loadRotation(_:) -> ActivityRotation`, `BreakSettingsStore.saveRotation(_:to:)`, `BreakReminderStrings` with `FeatureStrings.breakReminders(_ language: AppLanguage) -> BreakReminderStrings`.

- [ ] **Step 1: Add the keys**

In `enum DefaultsKey` (after the keep-awake keys):

```swift
    static let breakRemindersEyesEnabled = "breakRemindersEyesEnabled"
    static let breakRemindersEyesIntervalMinutes = "breakRemindersEyesIntervalMinutes"
    static let breakRemindersEyesBreakSeconds = "breakRemindersEyesBreakSeconds"
    static let breakRemindersEyesDeliveryStyle = "breakRemindersEyesDeliveryStyle"   // DeliveryStyle.rawValue
    static let breakRemindersEyesActivities = "breakRemindersEyesActivities"         // JSON [BreakActivity]; "" = seed defaults
    static let breakRemindersEyesRotationIndex = "breakRemindersEyesRotationIndex"
    static let breakRemindersMovementEnabled = "breakRemindersMovementEnabled"
    static let breakRemindersMovementIntervalMinutes = "breakRemindersMovementIntervalMinutes"
    static let breakRemindersMovementBreakSeconds = "breakRemindersMovementBreakSeconds"
    static let breakRemindersMovementDeliveryStyle = "breakRemindersMovementDeliveryStyle"
    static let breakRemindersMovementActivities = "breakRemindersMovementActivities"
    static let breakRemindersMovementRotationIndex = "breakRemindersMovementRotationIndex"
    static let breakRemindersEscalateAfterSeconds = "breakRemindersEscalateAfterSeconds"
    static let breakRemindersWorkingHoursEnabled = "breakRemindersWorkingHoursEnabled"
    static let breakRemindersWorkingDays = "breakRemindersWorkingDays"               // bit n = weekday n+1
    static let breakRemindersWorkingStartMinutes = "breakRemindersWorkingStartMinutes"
    static let breakRemindersWorkingEndMinutes = "breakRemindersWorkingEndMinutes"
    static let breakRemindersPausedUntil = "breakRemindersPausedUntil"               // timeIntervalSince1970; 0 = none
    static let notchBreakReminders = "notchBreakReminders"
```

In `registeredDefaults`:

```swift
        DefaultsKey.breakRemindersEyesEnabled: true,
        DefaultsKey.breakRemindersEyesIntervalMinutes: 20,
        DefaultsKey.breakRemindersEyesBreakSeconds: 20,
        DefaultsKey.breakRemindersEyesDeliveryStyle: "notification",
        DefaultsKey.breakRemindersEyesActivities: "",
        DefaultsKey.breakRemindersEyesRotationIndex: 0,
        DefaultsKey.breakRemindersMovementEnabled: true,
        DefaultsKey.breakRemindersMovementIntervalMinutes: 50,
        DefaultsKey.breakRemindersMovementBreakSeconds: 120,
        DefaultsKey.breakRemindersMovementDeliveryStyle: "escalating",
        DefaultsKey.breakRemindersMovementActivities: "",
        DefaultsKey.breakRemindersMovementRotationIndex: 0,
        DefaultsKey.breakRemindersEscalateAfterSeconds: 120,
        DefaultsKey.breakRemindersWorkingHoursEnabled: false,
        DefaultsKey.breakRemindersWorkingDays: 0b0111110,
        DefaultsKey.breakRemindersWorkingStartMinutes: 540,
        DefaultsKey.breakRemindersWorkingEndMinutes: 1080,
        DefaultsKey.breakRemindersPausedUntil: 0.0,
        DefaultsKey.notchBreakReminders: true,
```

- [ ] **Step 2: Write the strings file**

`Core/BreakReminderStrings.swift`, shaped like `Core/KeepAwakeStrings.swift`: a struct, `extension FeatureStrings { static func breakReminders(_ language: AppLanguage) -> BreakReminderStrings }` switching over all 15 cases, and one `static let` per language in an `extension BreakReminderStrings`.

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct BreakReminderStrings {
    let featureTitle: String
    let featureCaption: String
    let eyesSection: String
    let movementSection: String
    let scheduleSection: String
    let enabled: String
    let interval: String          // e.g. "Every"
    let breakLength: String
    let deliveryStyle: String
    let styleNotch: String
    let styleNotification: String
    let styleEscalating: String
    let styleOverlay: String
    let escalateAfter: String
    let workingHours: String
    let workingHoursCaption: String
    let activities: String
    let addActivity: String
    let done: String
    let snooze: String
    let skip: String
    let pauseMenu: String
    let pauseHour: String
    let pauseTomorrow: String
    let resume: String
    let eyesGeneric: String
    let movementGeneric: String
    let notchToggle: String
    let defaultEyes: [String]       // texts for the seeded eyes list, in order
    let defaultMovement: [String]   // texts for the seeded movement list, in order
}
```

English values (all other languages translate these; keep counts equal; no `%` anywhere):

```swift
    static let enUS = BreakReminderStrings(
        featureTitle: "Break Reminders",
        featureCaption: "Reminds you to rest your eyes and move, and waits while you're in a call.",
        eyesSection: "Eye breaks", movementSection: "Movement breaks", scheduleSection: "Schedule",
        enabled: "Enabled", interval: "Every", breakLength: "Break length", deliveryStyle: "Remind with",
        styleNotch: "Notch", styleNotification: "Notification", styleEscalating: "Notch, then full screen",
        styleOverlay: "Full screen", escalateAfter: "Go full screen after",
        workingHours: "Only during working hours", workingHoursCaption: "Reminders pause outside these days and hours.",
        activities: "Activities", addActivity: "Add activity",
        done: "Done", snooze: "Snooze 5 min", skip: "Skip",
        pauseMenu: "Pause breaks", pauseHour: "For 1 hour", pauseTomorrow: "Until tomorrow", resume: "Resume breaks",
        eyesGeneric: "Look away from the screen", movementGeneric: "Get up and move",
        notchToggle: "Break reminders",
        defaultEyes: ["Look at something 20 feet away", "Close your eyes", "Blink slowly ten times"],
        defaultMovement: ["Stand up and stretch", "10 pushups", "Walk around for two minutes", "Shoulder rolls"])
```

Seeded seconds, by position: eyes `[20, 10, 10]`, movement `[60, 60, 120, 30]`.

- [ ] **Step 3: Write the store**

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum BreakSettingsStore {
    static let eyesSeedSeconds = [20, 10, 10]
    static let movementSeedSeconds = [60, 60, 120, 30]

    static func load(_ d: UserDefaults, language: AppLanguage) -> BreakSettings {
        let text = FeatureStrings.breakReminders(language)
        func kind(_ enabled: String, _ interval: String, _ length: String, _ style: String, _ list: String,
                  seed: [String], seconds: [Int], fallback: DeliveryStyle) -> KindSettings {
            KindSettings(enabled: d.bool(forKey: enabled),
                         interval: TimeInterval(max(1, d.integer(forKey: interval))) * 60,
                         breakLength: TimeInterval(max(5, d.integer(forKey: length))),
                         style: DeliveryStyle(rawValue: d.string(forKey: style) ?? "") ?? fallback,
                         activities: activities(d.string(forKey: list) ?? "", seed: seed, seconds: seconds))
        }
        let paused = d.double(forKey: DefaultsKey.breakRemindersPausedUntil)
        return BreakSettings(
            eyes: kind(DefaultsKey.breakRemindersEyesEnabled, DefaultsKey.breakRemindersEyesIntervalMinutes,
                       DefaultsKey.breakRemindersEyesBreakSeconds, DefaultsKey.breakRemindersEyesDeliveryStyle,
                       DefaultsKey.breakRemindersEyesActivities, seed: text.defaultEyes,
                       seconds: eyesSeedSeconds, fallback: .notification),
            movement: kind(DefaultsKey.breakRemindersMovementEnabled, DefaultsKey.breakRemindersMovementIntervalMinutes,
                           DefaultsKey.breakRemindersMovementBreakSeconds, DefaultsKey.breakRemindersMovementDeliveryStyle,
                           DefaultsKey.breakRemindersMovementActivities, seed: text.defaultMovement,
                           seconds: movementSeedSeconds, fallback: .escalating),
            escalateAfter: TimeInterval(max(30, d.integer(forKey: DefaultsKey.breakRemindersEscalateAfterSeconds))),
            hours: WorkingHours(enabled: d.bool(forKey: DefaultsKey.breakRemindersWorkingHoursEnabled),
                                days: d.integer(forKey: DefaultsKey.breakRemindersWorkingDays),
                                startMinutes: d.integer(forKey: DefaultsKey.breakRemindersWorkingStartMinutes),
                                endMinutes: d.integer(forKey: DefaultsKey.breakRemindersWorkingEndMinutes)),
            pausedUntil: paused > 0 ? Date(timeIntervalSince1970: paused) : nil)
    }

    /// "" means the user never edited the list: seed from the current language.
    static func activities(_ json: String, seed: [String], seconds: [Int]) -> [BreakActivity] {
        if !json.isEmpty, let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([BreakActivity].self, from: data) { return decoded }
        return zip(seed, seconds).map { BreakActivity(id: UUID(), text: $0, seconds: $1) }
    }

    static func encode(_ list: [BreakActivity]) -> String {
        (try? JSONEncoder().encode(list)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    static func loadRotation(_ d: UserDefaults) -> ActivityRotation {
        ActivityRotation(indices: [.eyes: d.integer(forKey: DefaultsKey.breakRemindersEyesRotationIndex),
                                   .movement: d.integer(forKey: DefaultsKey.breakRemindersMovementRotationIndex)])
    }

    static func saveRotation(_ r: ActivityRotation, to d: UserDefaults) {
        d.set(r.indices[.eyes] ?? 0, forKey: DefaultsKey.breakRemindersEyesRotationIndex)
        d.set(r.indices[.movement] ?? 0, forKey: DefaultsKey.breakRemindersMovementRotationIndex)
    }

    static func savePause(_ until: Date?, to d: UserDefaults) {
        d.set(until?.timeIntervalSince1970 ?? 0, forKey: DefaultsKey.breakRemindersPausedUntil)
    }
}
```

Seed activities get fresh UUIDs on every load while unedited; that is harmless because rotation is by index. The settings pane writes the JSON on first edit.

- [ ] **Step 4: Write the failing tests** (add `store(suite)` and `strings(suite)` to `run`)

```swift
    static func store(_ suite: TestSuite) {
        let d = UserDefaults(suiteName: "break-reminders-tests-\(UUID().uuidString)")!
        d.register(defaults: Defaults.registeredDefaults)
        let s = BreakSettingsStore.load(d, language: .enUS)
        suite.expect(s.eyes.interval == 1200 && s.eyes.breakLength == 20 && s.eyes.style == .notification,
                     "eyes defaults: 20 min, 20 s, notification")
        suite.expect(s.movement.interval == 3000 && s.movement.breakLength == 120 && s.movement.style == .escalating,
                     "movement defaults: 50 min, 2 min, escalating")
        suite.expect(s.eyes.activities.map(\.seconds) == [20, 10, 10] && s.movement.activities.count == 4,
                     "seeded activities")
        suite.expect(s.pausedUntil == nil && !s.hours.enabled, "no pause and no working hours by default")
        let edited = [BreakActivity(id: UUID(), text: "x", seconds: 7)]
        d.set(BreakSettingsStore.encode(edited), forKey: DefaultsKey.breakRemindersEyesActivities)
        suite.expect(BreakSettingsStore.load(d, language: .enUS).eyes.activities == edited, "edited lists round-trip")
        for key in [DefaultsKey.breakRemindersEyesActivities, DefaultsKey.breakRemindersPausedUntil,
                    DefaultsKey.breakRemindersWorkingDays, DefaultsKey.notchBreakReminders] {
            suite.expect(Defaults.registeredDefaults[key] != nil, "\(key) is registered so backup includes it")
        }
    }

    static func strings(_ suite: TestSuite) {
        for language in AppLanguage.allCases {
            let s = FeatureStrings.breakReminders(language)
            suite.expect(s.defaultEyes.count == 3 && s.defaultMovement.count == 4,
                         "\(language) seeds the same number of activities")
            let all = Mirror(reflecting: s).children.compactMap { $0.value as? String }
                + s.defaultEyes + s.defaultMovement
            suite.expect(all.allSatisfy { !$0.isEmpty }, "\(language) has no empty break string")
            suite.expect(all.allSatisfy { !$0.contains("%") }, "\(language) break strings contain no raw percent")
        }
    }
```

Check that `Defaults.registeredDefaults` is the actual name of the dictionary in `Core/Defaults.swift` (search `registeredDefaults`); if the dictionary is spelled differently, use the real name in both the test and Step 1. Check that `AppLanguage` is `CaseIterable` (search `enum AppLanguage`); if not, list the 15 cases explicitly.

- [ ] **Step 5: Register sources, run, verify pass**

Append `Sources/Vorssaint/Core/BreakReminderStrings.swift` and `Sources/Vorssaint/Services/BreakReminders/BreakSettingsStore.swift` to `TEST_SOURCES`.
Run: `timeout 600 ./build.sh --test-suite=break-reminders`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/Vorssaint/Core/Defaults.swift Sources/Vorssaint/Core/BreakReminderStrings.swift Sources/Vorssaint/Services/BreakReminders/BreakSettingsStore.swift Tests/BreakReminderTests.swift build.sh
git commit -m "feat(break-reminders): add settings keys, store and strings"
```

---

### Task 8: Feature catalog, signal sampler, service

**Files:**
- Modify: `Sources/Vorssaint/Core/FeatureCatalog.swift` (add `breakReminders` to `case quickLauncher, … cleaningMode, …` on line 29 and to every switch that lists `.cleaningMode`: lines ~83, 113, 171, 279, 340, 457; plus `enabledKeys`/`initialEnableKeys` and the availability defaults)
- Modify: `Sources/Vorssaint/App/FeatureRuntime.swift` (binding next to `.micMute` at ~309)
- Modify: feature title/caption lookups (find with `grep -rn "case .cleaningMode" Sources/Vorssaint/Core`)
- Create: `Sources/Vorssaint/Services/Audio/AudioInputActivity.swift`
- Create: `Sources/Vorssaint/Services/BreakReminders/BreakSignalSampler.swift`
- Create: `Sources/Vorssaint/Services/BreakReminders/BreakReminderService.swift`
- Create: `Sources/Vorssaint/Services/BreakReminders/Delivery/BreakDelivery.swift`
- Modify: `Tests/FeatureCatalogTests.swift` only if it enumerates expected features

**Interfaces:**
- Consumes: Tasks 2–7.
- Produces: `AppFeature.breakReminders`; `BreakDelivery` protocol; `BreakReminderService.shared` with `syncWithPreferences()`, `start()`, `stop()`, `pause(for:)`, `pauseUntilTomorrow()`, `resume()`, `respond(promptID:action:)`, `isPaused: Bool`; `AudioInputActivity.anyOtherProcessCapturing() -> Bool`; `BreakSignalSampler.sample(includeBusy: Bool) -> BreakSignals`, `BreakSignalSampler.screenLocked() -> Bool`.

- [ ] **Step 1: Catalog entry**

Per switch, mirror `.cleaningMode`, with these values: group `.tools`; `symbolName` `"figure.walk"`; permissions `[]` (notifications are requested by the service, not gated by the hub); `installedByDefault` false; `enabledKeys` `[DefaultsKey.breakRemindersEyesEnabled, DefaultsKey.breakRemindersMovementEnabled]`. Title and caption come from `FeatureStrings.breakReminders(language).featureTitle` / `.featureCaption`. The compiler's exhaustive-switch errors list every remaining site; resolve each by analogy to `.cleaningMode`.

- [ ] **Step 2: AudioInputActivity**

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreAudio
import Foundation

/// Whether another process is recording from any input. Per process, so a
/// headset that is only playing audio does not count.
enum AudioInputActivity {
    static func anyOtherProcessCapturing(excluding ownPID: pid_t = getpid()) -> Bool {
        processObjects().contains { process in
            readUInt32(process, kAudioProcessPropertyIsRunningInput) != 0 && pid(of: process) != ownPID
        }
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func processObjects() -> [AudioObjectID] {
        var addr = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func readUInt32(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32 {
        var addr = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr ? value : 0
    }

    private static func pid(of id: AudioObjectID) -> pid_t {
        var addr = address(kAudioProcessPropertyPID)
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr ? value : 0
    }
}
```

- [ ] **Step 3: BreakSignalSampler**

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import CoreMediaIO

enum BreakSignalSampler {
    static func sample(includeBusy: Bool) -> BreakSignals {
        var s = BreakSignals()
        s.idleSeconds = CGEventSource.secondsSinceLastEventType(.hidSystemState,
                                                                eventType: CGEventType(rawValue: ~0)!)
        guard includeBusy else { return s }
        s.micInUse = AudioInputActivity.anyOtherProcessCapturing()
        s.cameraInUse = cameraInUse()
        s.fullscreenFrontmost = fullscreenFrontmost()
        return s
    }

    static func screenLocked() -> Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    static func cameraInUse() -> Bool {
        var addr = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                             mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                             mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        guard CMIOObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == 0, size > 0 else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &addr, 0, nil, size, &used, &devices) == 0 else { return false }
        return devices.contains { device in
            var running = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
            var value: UInt32 = 0
            var out: UInt32 = 0
            return CMIOObjectGetPropertyData(device, &running, 0, nil, UInt32(MemoryLayout<UInt32>.size),
                                             &out, &value) == 0 && value != 0
        }
    }

    /// Frontmost app owns a layer-0 window exactly covering a display.
    /// Our own windows (the overlay) never count.
    static func fullscreenFrontmost() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != getpid(),
              let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return false }
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let screens = NSScreen.screens.map { s -> CGRect in
            CGRect(x: s.frame.minX, y: mainHeight - s.frame.maxY, width: s.frame.width, height: s.frame.height)
        }
        return info.contains { w in
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == front.processIdentifier,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let raw = w[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: raw) else { return false }
            return screens.contains { $0 == bounds }
        }
    }
}
```

- [ ] **Step 4: BreakDelivery protocol**

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

protocol BreakDelivery: AnyObject {
    /// False when the surface cannot show it now; the coordinator moves down the chain.
    func present(_ prompt: BreakPrompt, respond: @escaping (BreakAction) -> Void) -> Bool
    func dismiss(id: UUID)
}
```

- [ ] **Step 5: BreakReminderService**

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Main thread only. Built lazily by FeatureRuntime; nothing runs while the
/// feature is uninstalled.
final class BreakReminderService {
    static let shared = BreakReminderService()

    static let tickInterval: TimeInterval = 5
    static let watchdogInterval: TimeInterval = 60

    private let defaults = UserDefaults.standard
    private var coordinator = BreakCoordinator(rotation: ActivityRotation())
    private var settings: BreakSettings
    private var away = AwayTracker()
    private var clock = TickClock()
    private var pendingAway: TimeInterval?
    private var timer: Timer?
    private var watchdog: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private(set) var running = false
    var sinks: [DeliveryStyle: BreakDelivery] = [:]   // filled in Tasks 9–11
    var notchWatch = NotchBreakWatch()
    var onPresentedChange: (() -> Void)?

    private init() {
        settings = BreakSettingsStore.load(defaults, language: AppLanguage.current)
    }

    var isPaused: Bool { (settings.pausedUntil ?? .distantPast) > Date() }

    func syncWithPreferences() {
        let wanted = AppFeature.breakReminders.isAvailable
        if wanted && !running { start() } else if !wanted && running { stop() } else if running { reloadSettings() }
    }

    func start() {
        guard !running else { return }
        running = true
        settings = BreakSettingsStore.load(defaults, language: AppLanguage.current)
        coordinator = BreakCoordinator(rotation: BreakSettingsStore.loadRotation(defaults))
        clock.reset(now: Date())
        observeSystem()
        timer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in self?.tick() }
        watchdog = Timer.scheduledTimer(withTimeInterval: Self.watchdogInterval, repeats: true) { [weak self] _ in
            self?.runWatchdog()
        }
    }

    func stop() {
        guard running else { return }
        running = false
        timer?.invalidate(); timer = nil
        watchdog?.invalidate(); watchdog = nil
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        execute(coordinator.stop())
    }

    func reloadSettings() {
        let old = settings
        settings = BreakSettingsStore.load(defaults, language: AppLanguage.current)
        execute(coordinator.settingsChanged(from: old, to: settings))
    }

    func pause(for interval: TimeInterval) { setPause(Date().addingTimeInterval(interval)) }
    func pauseUntilTomorrow() {
        setPause(BusyPolicy.pauseUntilTomorrow(now: Date(), hours: settings.hours, calendar: .current))
    }
    func resume() { setPause(nil) }

    private func setPause(_ until: Date?) {
        BreakSettingsStore.savePause(until, to: defaults)
        settings.pausedUntil = until
        tick()
    }

    // MARK: Tick

    private func tick() {
        guard running, !away.isAway else { return }
        let now = Date()
        let step = clock.step(now: now, interval: Self.tickInterval)
        let awayFor = [pendingAway, step.gap].compactMap { $0 }.max()
        pendingAway = nil
        let signals = BreakSignalSampler.sample(includeBusy: coordinator.needsBusySignals)
        let verdict = BusyPolicy.verdict(signals, settings: settings, now: now, calendar: .current)
        execute(coordinator.tick(now: now, dt: step.dt, verdict: verdict, idleSeconds: signals.idleSeconds,
                                 awayFor: awayFor, settings: settings, newID: UUID.init))
        checkNotchDisplacement(now: now)
        BreakSettingsStore.saveRotation(coordinator.rotation, to: defaults)
    }

    private func execute(_ outputs: [BreakCoordinator.Output]) {
        for output in outputs {
            switch output {
            case let .dismiss(id, via):
                sinks[via]?.dismiss(id: id)
            case let .present(prompt, via):
                present(prompt, via: via)
            }
        }
    }

    private func present(_ prompt: BreakPrompt, via: DeliveryStyle) {
        notchWatch = NotchBreakWatch()
        let shown = sinks[via]?.present(prompt) { [weak self] action in
            guard let self, self.running else { return }
            self.execute(self.coordinator.respond(id: prompt.id, action: action, now: Date(), settings: self.settings))
        } ?? false
        if shown {
            coordinator.presented(id: prompt.id, via: via, now: Date(), settings: settings)
        } else {
            execute(coordinator.deliveryFailed(id: prompt.id, via: via, now: Date(), settings: settings))
        }
    }

    /// Sinks call these when a shown prompt is lost (Tasks 9–11).
    func sinkFailed(id: UUID, via: DeliveryStyle) {
        guard running else { return }
        execute(coordinator.deliveryFailed(id: id, via: via, now: Date(), settings: settings))
    }

    func sinkDisplaced(id: UUID, via: DeliveryStyle) {
        guard running else { return }
        execute(coordinator.displaced(id: id, via: via, now: Date(), settings: settings))
    }

    /// A notch session close resets the prompt quietly: no fallback, no advance.
    func sinkClosed(id: UUID) {
        guard running, coordinator.livePromptID == id else { return }
        execute(coordinator.stopPromptQuietly(id: id))
    }

    private func checkNotchDisplacement(now: Date) { /* filled in Task 11 */ }

    // MARK: Away

    private func observeSystem() {
        let ws = NSWorkspace.shared.notificationCenter
        let dist = DistributedNotificationCenter.default()
        func on(_ c: NotificationCenter, _ name: Notification.Name, _ body: @escaping () -> Void) {
            observers.append((c, c.addObserver(forName: name, object: nil, queue: .main) { _ in body() }))
        }
        on(ws, NSWorkspace.sessionDidResignActiveNotification) { [weak self] in self?.beginAway(.sessionInactive) }
        on(ws, NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in self?.endAway(.sessionInactive) }
        on(ws, NSWorkspace.willSleepNotification) { [weak self] in self?.beginAway(.asleep) }
        on(ws, NSWorkspace.didWakeNotification) { [weak self] in self?.endAway(.asleep) }
        on(ws, NSWorkspace.screensDidSleepNotification) { [weak self] in self?.beginAway(.screensAsleep) }
        on(ws, NSWorkspace.screensDidWakeNotification) { [weak self] in self?.endAway(.screensAsleep) }
        on(dist, Notification.Name("com.apple.screenIsLocked")) { [weak self] in self?.beginAway(.locked) }
        on(dist, Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in self?.endAway(.locked) }
    }

    private func beginAway(_ c: AwayTracker.Condition) { away.begin(c, now: Date()) }

    private func endAway(_ c: AwayTracker.Condition) {
        if let duration = away.end(c, now: Date()) { returned(after: duration) }
    }

    private func runWatchdog() {
        let idle = BreakSignalSampler.sample(includeBusy: false).idleSeconds
        if let duration = away.watchdog(now: Date(), screenLocked: BreakSignalSampler.screenLocked(),
                                        idleSeconds: idle) {
            returned(after: duration)
        }
    }

    private func returned(after duration: TimeInterval) {
        pendingAway = duration
        clock.reset(now: Date())
        tick()
    }
}
```

This needs one more coordinator method used by `sinkClosed`. Add to `BreakCoordinator` (Task 6 file) with a test line in `coordinator(suite)`:

```swift
    /// The surface went away with the session: reset with no fallback and no advance.
    mutating func stopPromptQuietly(id: UUID) -> [Output] {
        guard let current = live, current.prompt.id == id else { return [] }
        live = nil
        _ = schedules[current.prompt.kind]!.reset()
        return [.dismiss(id, via: current.via)]
    }
```

```swift
        var quiet = BreakCoordinator(rotation: ActivityRotation())
        quiet.forceState(.eyes, .due)
        _ = quiet.tick(now: t0, dt: 5, verdict: .active, idleSeconds: 0, awayFor: nil, settings: s, newID: next)
        let qid = quiet.livePromptID!
        suite.expect(quiet.stopPromptQuietly(id: qid) == [.dismiss(qid, via: .overlay)] &&
                     quiet.schedules[.eyes]?.state == .counting(0) &&
                     quiet.rotation.current(.eyes, in: s.eyes.activities)?.text == "look",
                     "a session close resets without fallback or advance")
```

`AppLanguage.current`: use whatever the codebase uses to read the active language (search `static var current` in `Core/Localization.swift`; if the app reads it through an `L10n`/`Localization` object, call that instead).

- [ ] **Step 6: Runtime binding**

In `FeatureRuntime.swift` next to `.micMute`:

```swift
        .breakReminders: { BreakReminderService.shared.syncWithPreferences() },
```

- [ ] **Step 7: Build and run all tests**

Run: `timeout 600 ./build.sh && timeout 600 ./build.sh --test`
Expected: build succeeds; the full harness passes (previous total plus the new suite).

- [ ] **Step 8: Commit**

```bash
git add Sources/Vorssaint/Core/FeatureCatalog.swift Sources/Vorssaint/App/FeatureRuntime.swift Sources/Vorssaint/Services/Audio/AudioInputActivity.swift Sources/Vorssaint/Services/BreakReminders/BreakSignalSampler.swift Sources/Vorssaint/Services/BreakReminders/BreakReminderService.swift Sources/Vorssaint/Services/BreakReminders/Delivery/BreakDelivery.swift Sources/Vorssaint/Services/BreakReminders/BreakCoordinator.swift Tests/BreakReminderTests.swift
# plus any title/caption files the compiler pointed at, by explicit path
git commit -m "feat(break-reminders): add the feature, signal sampler and service"
```

---

### Task 9: Notification delivery

**Files:**
- Modify: `Sources/Vorssaint/Services/Notifier.swift`
- Modify: `Sources/Vorssaint/App/AppDelegate.swift` (launch guard at `:56-60`, `didReceive` at `:2388`, new `willPresent`)
- Create: `Sources/Vorssaint/Services/BreakReminders/Delivery/NotificationBreakDelivery.swift`
- Create: `Tests/BreakReminderNotifierContract.swift`
- Modify: `Tests/MetricsTests.swift` (add the contract to the `break-reminders` group)

**Interfaces:**
- Consumes: `BreakDelivery`, `BreakReminderService.shared.respond…` via the closure passed to `present`.
- Produces: `Notifier.registerCategories()`, `Notifier.post(title:body:categoryIdentifier:userInfo:identifier:)`, `Notifier.breakCategoryIdentifier`, `Notifier.breakPromptKey`, `Notifier.breakDoneAction`, `Notifier.breakSnoozeAction`, `NotificationBreakDelivery`.

- [ ] **Step 1: Write the failing source contract**

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// setNotificationCategories replaces every category, so it may be called
/// from exactly one place, which registers WhatsApp and break categories together.
enum BreakReminderNotifierContract {
    static func run(_ suite: TestSuite) {
        let source = (try? String(contentsOfFile: "Sources/Vorssaint/Services/Notifier.swift", encoding: .utf8)) ?? ""
        suite.expect(!source.isEmpty, "Notifier.swift is readable from the repo root")
        let calls = source.components(separatedBy: "setNotificationCategories(").count - 1
        suite.expect(calls == 1, "setNotificationCategories is called exactly once")
        guard let range = source.range(of: "static func registerCategories(") else {
            suite.expect(false, "registerCategories exists"); return
        }
        let body = source[range.lowerBound...].prefix(1500)
        suite.expect(body.contains("setNotificationCategories(") && body.contains("whatsAppOrganizerCategoryIdentifier")
                     && body.contains("breakCategoryIdentifier"),
                     "registerCategories registers both categories")
        suite.expect(body.contains(".customDismissAction"), "the break category reports swipe-away dismissals")
    }
}
```

Register: change the registry entry to `("break-reminders", { BreakReminderTests.run(suite); BreakReminderNotifierContract.run(suite) }),`.

- [ ] **Step 2: Run to verify failure**

Run: `timeout 600 ./build.sh --test-suite=break-reminders`
Expected: FAIL on "registerCategories exists".

- [ ] **Step 3: Refactor Notifier**

Replace the inline `center.setNotificationCategories([...])` in `postWhatsAppOrganization` with a stored title plus a call to `registerCategories()`:

```swift
    static let breakCategoryIdentifier = "breakReminder"
    static let breakPromptKey = "breakPromptID"
    static let breakDoneAction = "breakReminder.done"
    static let breakSnoozeAction = "breakReminder.snooze"

    /// Latest localized titles; registerCategories rebuilds both categories from them.
    static var whatsAppUndoTitle = "Undo"
    static var breakDoneTitle = "Done"
    static var breakSnoozeTitle = "Snooze 5 min"

    /// The one place categories are registered: the call replaces every category.
    static func registerCategories() {
        let undo = UNNotificationAction(identifier: whatsAppOrganizerUndoActionIdentifier,
                                        title: whatsAppUndoTitle, options: [.foreground])
        let done = UNNotificationAction(identifier: breakDoneAction, title: breakDoneTitle, options: [])
        let snooze = UNNotificationAction(identifier: breakSnoozeAction, title: breakSnoozeTitle, options: [])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: whatsAppOrganizerCategoryIdentifier,
                                   actions: [undo], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: breakCategoryIdentifier,
                                   actions: [done, snooze], intentIdentifiers: [], options: [.customDismissAction]),
        ])
    }
```

In `postWhatsAppOrganization`: set `whatsAppUndoTitle = undoTitle`, call `registerCategories()`, keep the `post(...)`.

Add an `identifier: String? = nil` parameter to the private `post(title:body:categoryIdentifier:userInfo:)` and use `identifier ?? UUID().uuidString` where it currently writes `UUID().uuidString` (`Notifier.swift:76`). Expose:

```swift
    static func postBreak(title: String, body: String, promptID: UUID) {
        post(title: title, body: body, categoryIdentifier: breakCategoryIdentifier,
             userInfo: [breakPromptKey: promptID.uuidString], identifier: promptID.uuidString)
    }

    static func removeBreak(promptID: UUID) {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [promptID.uuidString])
        center.removePendingNotificationRequests(withIdentifiers: [promptID.uuidString])
    }
```

- [ ] **Step 4: AppDelegate wiring**

Inside the existing `Bundle.main.bundleIdentifier != nil` block (`AppDelegate.swift:56-60`), after the delegate is set, add `Notifier.registerCategories()`.

At the top of `userNotificationCenter(_:didReceive:withCompletionHandler:)` (`:2388`):

```swift
        if let raw = response.notification.request.content.userInfo[Notifier.breakPromptKey] as? String,
           let id = UUID(uuidString: raw) {
            NotificationBreakDelivery.shared.handle(id: id, actionIdentifier: response.actionIdentifier)
            completionHandler()
            return
        }
```

Add:

```swift
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let isBreak = notification.request.content.userInfo[Notifier.breakPromptKey] != nil
        completionHandler(isBreak ? [.banner, .sound] : [])
    }
```

- [ ] **Step 5: NotificationBreakDelivery**

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import UserNotifications

final class NotificationBreakDelivery: BreakDelivery {
    static let shared = NotificationBreakDelivery()

    private(set) var authorized = false
    private var handlers: [UUID: (BreakAction) -> Void] = [:]

    /// Cached because present must answer synchronously. A stale cache can
    /// drop one prompt until its timeout; accepted in the spec.
    func refreshAuthorization(requestIfUndetermined: Bool) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.authorized = settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional
                if requestIfUndetermined, settings.authorizationStatus == .notDetermined {
                    Notifier.requestPermission()
                }
            }
        }
    }

    func present(_ prompt: BreakPrompt, respond: @escaping (BreakAction) -> Void) -> Bool {
        guard authorized else { return false }
        let text = FeatureStrings.breakReminders(AppLanguage.current)
        Notifier.breakDoneTitle = text.done
        Notifier.breakSnoozeTitle = text.snooze
        Notifier.registerCategories()
        handlers[prompt.id] = respond
        let generic = prompt.kind == .eyes ? text.eyesGeneric : text.movementGeneric
        Notifier.postBreak(title: prompt.activity?.text ?? generic,
                           body: "\(prompt.seconds) s", promptID: prompt.id)
        return true
    }

    func dismiss(id: UUID) {
        handlers[id] = nil
        Notifier.removeBreak(promptID: id)
    }

    func handle(id: UUID, actionIdentifier: String) {
        guard let respond = handlers[id] else { return }
        switch actionIdentifier {
        case Notifier.breakSnoozeAction: respond(.snooze)
        case UNNotificationDismissActionIdentifier: respond(.skip)
        default: respond(.done)   // Done button or a tap on the banner
        }
    }
}
```

Check `Notifier.requestPermission()` exists with that name (search `requestPermission` in `Notifier.swift`); use the real name.

In `BreakReminderService.start()`, register the sink and refresh authorization:

```swift
        sinks[.notification] = NotificationBreakDelivery.shared
        let wantsNotifications = [settings.eyes, settings.movement].contains {
            $0.enabled && ($0.style == .notification || $0.style == .escalating)
        }
        NotificationBreakDelivery.shared.refreshAuthorization(requestIfUndetermined: wantsNotifications)
```

Also refresh (without requesting) on `NSApplication.didBecomeActiveNotification`, added to `observeSystem()`. In the hub install path, `enableOnFirstInstall` for `.breakReminders` triggers `Notifier.requestPermission()` the same way other notification features do (search `requestPermission` call sites in `FeatureHubSettings.swift:952` and mirror it for this feature).

- [ ] **Step 6: Run tests and build**

Run: `timeout 600 ./build.sh --test && timeout 600 ./build.sh`
Expected: PASS; build succeeds.

- [ ] **Step 7: Commit**

```bash
git add Sources/Vorssaint/Services/Notifier.swift Sources/Vorssaint/App/AppDelegate.swift Sources/Vorssaint/Services/BreakReminders/Delivery/NotificationBreakDelivery.swift Sources/Vorssaint/Services/BreakReminders/BreakReminderService.swift Tests/BreakReminderNotifierContract.swift Tests/MetricsTests.swift
# plus FeatureHubSettings.swift if Step 5 touched it
git commit -m "feat(break-reminders): deliver breaks as notifications"
```

---

### Task 10: Overlay delivery

**Files:**
- Create: `Sources/Vorssaint/Services/BreakReminders/Delivery/OverlayBreakDelivery.swift`
- Create: `Sources/Vorssaint/UI/BreakReminders/BreakOverlayView.swift`
- Modify: `Sources/Vorssaint/Services/BreakReminders/BreakReminderService.swift` (register sink)

**Interfaces:**
- Consumes: `BreakDelivery`, `BreakPrompt`, `BreakReminderStrings`, `IsSecureEventInputEnabled` (see `Core/SecureInputSupport.swift`).
- Produces: `OverlayBreakDelivery`.

- [ ] **Step 1: The view**

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct BreakOverlayView: View {
    let title: String
    let seconds: Int
    let shownAt: Date
    let text: BreakReminderStrings
    let respond: (BreakAction) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 24) {
                Text(title).font(.system(size: 34, weight: .semibold)).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                TimelineView(.periodic(from: shownAt, by: 1)) { context in
                    let left = max(0, seconds - Int(context.date.timeIntervalSince(shownAt)))
                    Text(left > 0 ? "\(left)" : text.done)
                        .font(.system(size: 64, weight: .light).monospacedDigit()).foregroundStyle(.white)
                }
                HStack(spacing: 12) {
                    Button(text.done) { respond(.done) }.keyboardShortcut(.none)
                    Button(text.snooze) { respond(.snooze) }
                    Button(text.skip) { respond(.skip) }
                }
                .controlSize(.large)
            }
            .padding(40)
        }
    }
}
```

- [ ] **Step 2: The sink**

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// One non-activating panel per screen. Never key, so typing in the
/// frontmost app is never interrupted; buttons take the first click.
final class OverlayBreakDelivery: BreakDelivery {
    static let shared = OverlayBreakDelivery()
    static let secureInputWait: TimeInterval = 120

    private final class Host: NSHostingView<BreakOverlayView> {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private var panels: [UUID: [NSPanel]] = [:]
    private var waiting: [UUID: Timer] = [:]

    func present(_ prompt: BreakPrompt, respond: @escaping (BreakAction) -> Void) -> Bool {
        if IsSecureEventInputEnabled() {
            // Wait for a password field to clear, up to 2 minutes, then show anyway.
            let started = Date()
            waiting[prompt.id] = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
                guard !IsSecureEventInputEnabled() || Date().timeIntervalSince(started) >= Self.secureInputWait else { return }
                timer.invalidate()
                self?.waiting[prompt.id] = nil
                self?.show(prompt, respond: respond)
                BreakReminderService.shared.overlayShownLate(id: prompt.id)
            }
            return true
        }
        show(prompt, respond: respond)
        return true
    }

    func dismiss(id: UUID) {
        waiting.removeValue(forKey: id)?.invalidate()
        panels.removeValue(forKey: id)?.forEach { $0.orderOut(nil) }
    }

    private func show(_ prompt: BreakPrompt, respond: @escaping (BreakAction) -> Void) {
        let text = FeatureStrings.breakReminders(AppLanguage.current)
        let generic = prompt.kind == .eyes ? text.eyesGeneric : text.movementGeneric
        let shownAt = Date()
        panels[prompt.id] = NSScreen.screens.map { screen in
            let panel = Panel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.contentView = Host(rootView: BreakOverlayView(
                title: prompt.activity?.text ?? generic, seconds: prompt.seconds, shownAt: shownAt,
                text: text, respond: respond))
            panel.setFrame(screen.frame, display: true)
            panel.orderFrontRegardless()
            return panel
        }
    }
}
```

The overlay reports success immediately even while waiting on secure input, so the coordinator would start its deadline too early. Add to `BreakReminderService`:

```swift
    /// The overlay waited on secure input; restart its timers from now.
    func overlayShownLate(id: UUID) {
        guard running else { return }
        coordinator.presented(id: id, via: .overlay, now: Date(), settings: settings)
    }
```

and in `present(_:via:)` skip `coordinator.presented` for `.overlay` while `IsSecureEventInputEnabled()` is true (the late call sets it). This keeps the spec rule "timers start at the sink's present time".

Register in `start()`: `sinks[.overlay] = OverlayBreakDelivery.shared`.

- [ ] **Step 3: Build and manual check**

Run: `timeout 600 ./build.sh --install`
Then in Settings set eyes to 1 minute, style Full screen. Expected: after ~1 min plus one tick, a dim overlay on every display; the frontmost app keeps keyboard focus (type in it while the overlay is up); one click on Done closes it; Snooze brings it back 5 minutes later.

- [ ] **Step 4: Commit**

```bash
git add Sources/Vorssaint/Services/BreakReminders/Delivery/OverlayBreakDelivery.swift Sources/Vorssaint/UI/BreakReminders/BreakOverlayView.swift Sources/Vorssaint/Services/BreakReminders/BreakReminderService.swift
git commit -m "feat(break-reminders): deliver breaks as a full-screen overlay"
```

---

### Task 11: Notch delivery

**Files:**
- Modify: `Sources/Vorssaint/Services/Notch/NotchService.swift` (`presentCapture` `:1890`, `syncWithPreferences` guard `:782-786`, `open` `~:944`, `collapse` `:991`, `removeCapture`/`clearCapture` `:1920-1935`, session close `:2771`, `withdrawFromMissingScreen` `:2525-2538`, the Esc/`.hidePad`/toggle collapse call sites)
- Modify: `Sources/Vorssaint/Services/Notch/NotchSupport.swift` (`NotchEvent` case, `preferenceKey` `:1226`, `routes` `:1473`, durations `:1253`, priority `:1244`)
- Modify: `Sources/Vorssaint/UI/Settings/NotchSettings.swift` only if it enumerates `NotchEvent.allCases`
- Create: `Sources/Vorssaint/UI/Notch/NotchBreakView.swift`
- Create: `Sources/Vorssaint/Services/BreakReminders/Delivery/NotchBreakDelivery.swift`
- Create: `Tests/BreakReminderNotchContract.swift`
- Modify: `Tests/MetricsTests.swift`, `BreakReminderService.swift`

**Interfaces:**
- Consumes: `NotchService.shared`, `NotchSupport.routes`, `NotchBreakWatch`, `BreakReminderService.sinkDisplaced/sinkFailed/sinkClosed`.
- Produces: `NotchEvent.breakReminder`; `presentCapture(id:content:actions:height:route:takeFocus:pinIsland:fallback:close:hover:collapsed:displaced:) -> Bool`; `collapse(user: Bool = false)`; `NotchService.currentCaptureID: UUID?`; `NotchService.isExpanded: Bool`; `NotchBreakDelivery`.

- [ ] **Step 1: Write the failing contracts**

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum BreakReminderNotchContract {
    static func run(_ suite: TestSuite) {
        let d = UserDefaults(suiteName: "break-notch-\(UUID().uuidString)")!
        d.register(defaults: Defaults.registeredDefaults)
        d.set(true, forKey: AppFeature.breakReminders.availabilityKey)
        d.set(false, forKey: AppFeature.screenshot.availabilityKey)
        suite.expect(NotchSupport.routes(.breakReminder, defaults: d),
                     "breaks route with the Screenshot feature off and Captures not in the modules")
        d.set(false, forKey: DefaultsKey.notchBreakReminders)
        suite.expect(!NotchSupport.routes(.breakReminder, defaults: d), "the notch toggle turns break routing off")

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
```

Adjust the `routes` call to the real signature: read `NotchSupport.routes` at `NotchSupport.swift:1473`. If it reads `UserDefaults.standard` with no parameter, add a `defaults: UserDefaults = .standard` parameter as part of this task, threading it to the `preferenceKey` read and `isAvailable(in:)`.

Register: append `BreakReminderNotchContract.run(suite)` inside the `break-reminders` group.

- [ ] **Step 2: Run to verify failure**

Run: `timeout 600 ./build.sh --test-suite=break-reminders`
Expected: compile error `type 'NotchEvent' has no member 'breakReminder'`.

- [ ] **Step 3: NotchSupport changes**

- Add `case breakReminder` to `NotchEvent`.
- `preferenceKey`: `case .breakReminder: return DefaultsKey.notchBreakReminders`.
- `routes`: `case .breakReminder: return AppFeature.breakReminders.isAvailable(in: defaults)` (after the shared preference-key gate the function already applies).
- Duration and priority switches: give `.breakReminder` the same values as `.capture` (it never goes through `show()`; these only satisfy exhaustiveness).
- Add `NotchNoticeView`/notch settings cases the compiler asks for; if notch settings list `allCases`, the row title is `FeatureStrings.breakReminders(language).notchToggle`.
- `NotchSupport.swift` is in `TEST_SOURCES` already; if `FeatureCatalog.swift` is not, the contract cannot call `AppFeature`: check the list and add it if missing.

- [ ] **Step 4: NotchService changes**

Add stored state next to `captureID` (`:137`):

```swift
    private var captureRoute: NotchEvent = .capture
    private var captureOwnsPin = false
    private var captureCollapsed: (() -> Void)?
    private var captureDisplaced: (() -> Void)?
    var currentCaptureID: UUID? { captureID }
    var isExpanded: Bool { expanded }
```

Replace `presentCapture` (`:1890-1905`):

```swift
    func presentCapture(id: UUID, content: AnyView, actions: AnyView? = nil, height: CGFloat,
                        route: NotchEvent = .capture, takeFocus: Bool? = nil, pinIsland: Bool = false,
                        fallback: @escaping () -> Void, close: @escaping () -> Void,
                        hover: @escaping (Bool) -> Void,
                        collapsed: (() -> Void)? = nil, displaced: (() -> Void)? = nil) -> Bool {
        guard acceptsSystemFeedback, NotchSupport.routes(route) else { return false }
        // Never take the slot from a live screenshot.
        if route != .capture, captureID != nil, captureRoute == .capture { return false }
        let wasExpanded = expanded
        let keepOpen = expanded && self.pinned && !captureOwnsPin
        let inheritedPin = captureOwnsPin
        captureID = id
        captureRoute = route
        captureContentHeight = height
        captureContent = content
        captureActions = actions
        captureFallback = fallback
        captureClose = close
        captureHover = hover
        captureCollapsed = collapsed
        captureDisplaced = displaced
        captureOwnsPin = (!keepOpen && pinIsland) || inheritedPin
        open(.captures, pinned: keepOpen || pinIsland,
             takeFocus: takeFocus ?? UserDefaults.standard.bool(forKey: DefaultsKey.screenshotPreviewTakesFocus),
             feedback: false, allowUnlisted: route != .capture)
        captureHover?(inside)
        guard isCaptureVisible(id: id) else {
            let tookPin = captureOwnsPin && !inheritedPin
            clearCapture()
            if tookPin { pinned = false }
            if !wasExpanded { collapse() }
            return false
        }
        return true
    }
```

`open(_:pinned:takeFocus:feedback:)` gains `allowUnlisted: Bool = false`; where it filters with `modules.contains($0) ? $0 : nil` (around `:944`), keep `.captures` when `allowUnlisted` is true:

```swift
        let destination = module.flatMap { (modules.contains($0) || (allowUnlisted && $0 == .captures)) ? $0 : nil }
            ?? reopening.module
```

`clearCapture()` also resets `captureRoute = .capture`, `captureCollapsed = nil`, `captureDisplaced = nil`, and `captureOwnsPin = false`.

`removeCapture(id:)`:

```swift
    func removeCapture(id: UUID) {
        guard captureID == id else { return }
        let ownedPin = captureOwnsPin
        clearCapture()
        if ownedPin { pinned = false }
        if expanded, selected == .captures, !showingSections {
            if pinned { refreshPresentation() } else { collapse() }
        }
    }
```

`syncWithPreferences` guard (`:782-786`): replace `!NotchSupport.routes(.capture)` with `!NotchSupport.routes(captureRoute)`.

`collapse()` (`:991`) becomes `collapse(user: Bool = false)`. At its top, after its existing early returns:

```swift
        if captureID != nil, captureRoute != .capture {
            let callback = user ? captureCollapsed : captureDisplaced
            let ownedPin = captureOwnsPin
            clearCapture()
            if ownedPin { pinned = false }
            callback?()
        }
```

Change only the Esc handlers (`:1426`, `:1430`), the `.hidePad` action, and the notch toggle to call `collapse(user: true)`. Leave every other call site as `collapse()`.

Session close (`:2771`) and `withdrawFromMissingScreen` (`:2525-2538`) already call `captureClose`/`captureFallback`; the break sink maps those (Step 6). No change needed there beyond `clearCapture` resetting the new fields.

- [ ] **Step 5: NotchBreakView**

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchBreakView: View {
    let title: String
    let seconds: Int
    let shownAt: Date

    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .lineLimit(2).multilineTextAlignment(.center)
            TimelineView(.periodic(from: shownAt, by: 1)) { context in
                let left = max(0, seconds - Int(context.date.timeIntervalSince(shownAt)))
                Text("\(left)").font(.system(size: 28, weight: .light).monospacedDigit()).foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct NotchBreakActions: View {
    let text: BreakReminderStrings
    let respond: (BreakAction) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(text.done) { respond(.done) }
            Button(text.snooze) { respond(.snooze) }
            Button(text.skip) { respond(.skip) }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.white)
    }
}
```

- [ ] **Step 6: NotchBreakDelivery**

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

final class NotchBreakDelivery: BreakDelivery {
    static let shared = NotchBreakDelivery()
    static let height: CGFloat = 110
    private(set) var liveID: UUID?

    func present(_ prompt: BreakPrompt, respond: @escaping (BreakAction) -> Void) -> Bool {
        let notch = NotchService.shared
        guard notch.showsSystemFeedback else { return false }
        let text = FeatureStrings.breakReminders(AppLanguage.current)
        let generic = prompt.kind == .eyes ? text.eyesGeneric : text.movementGeneric
        let id = prompt.id
        let shown = notch.presentCapture(
            id: id,
            content: AnyView(NotchBreakView(title: prompt.activity?.text ?? generic, seconds: prompt.seconds,
                                            shownAt: Date())),
            actions: AnyView(NotchBreakActions(text: text, respond: respond)),
            height: Self.height, route: .breakReminder, takeFocus: false, pinIsland: true,
            fallback: { BreakReminderService.shared.sinkFailed(id: id, via: .notch) },
            close: { BreakReminderService.shared.sinkClosed(id: id) },
            hover: { _ in },
            collapsed: { respond(.snooze) },
            displaced: { BreakReminderService.shared.sinkDisplaced(id: id, via: .notch) })
        if shown { liveID = id }
        return shown
    }

    func dismiss(id: UUID) {
        guard liveID == id else { return }
        liveID = nil
        NotchService.shared.removeCapture(id: id)
    }
}
```

Check the property name `showsSystemFeedback` (`NotchService.swift:703`); if it is private, make it `private(set)`/internal read-only.

In `BreakReminderService`: `sinks[.notch] = NotchBreakDelivery.shared` in `start()`, and fill `checkNotchDisplacement`:

```swift
    private func checkNotchDisplacement(now: Date) {
        guard let id = NotchBreakDelivery.shared.liveID else { return }
        let notch = NotchService.shared
        if notchWatch.displaced(id: id, currentCaptureID: notch.currentCaptureID,
                                visible: notch.isCaptureVisible(id: id), expanded: notch.isExpanded, now: now) {
            NotchBreakDelivery.shared.dismiss(id: id)
            sinkDisplaced(id: id, via: .notch)
        }
    }
```

`stop()` must dismiss the notch capture without its fallback firing: because `stop()` sets `running = false` before `execute(coordinator.stop())`, and every `sink*` method returns early when not running, a fallback raised during removal does nothing.

- [ ] **Step 7: Run tests, build, manual check**

Run: `timeout 600 ./build.sh --test && timeout 600 ./build.sh --install`
Expected: PASS. Manual, eyes at 1 minute, style Notch:
1. The island opens on the break card and stays open while the pointer leaves and while switching apps.
2. Done closes it and the island collapses (not left pinned and empty).
3. Esc on the island snoozes (prompt returns 5 minutes later).
4. Opening the status menu while the card is up moves the break to a notification.
5. Taking a screenshot while the card is up: the screenshot preview replaces it and the break moves to a notification.
6. With the Screenshot feature off in the hub, the card still appears.

- [ ] **Step 8: Commit**

```bash
git add Sources/Vorssaint/Services/Notch/NotchService.swift Sources/Vorssaint/Services/Notch/NotchSupport.swift Sources/Vorssaint/UI/Notch/NotchBreakView.swift Sources/Vorssaint/Services/BreakReminders/Delivery/NotchBreakDelivery.swift Sources/Vorssaint/Services/BreakReminders/BreakReminderService.swift Tests/BreakReminderNotchContract.swift Tests/MetricsTests.swift
# plus NotchSettings.swift / NotchNoticeView.swift if the compiler sent you there
git commit -m "feat(break-reminders): deliver breaks in the notch"
```

---

### Task 12: Settings pane, pause menu, Command Bar

**Files:**
- Create: `Sources/Vorssaint/UI/Settings/BreakReminderSettings.swift`
- Modify: the settings router that maps features to panes (find with `grep -rn "CleaningModeSettings\|case .cleaningMode" Sources/Vorssaint/UI/Settings`)
- Modify: the status menu builder (find with `grep -rn "keepAwake" Sources/Vorssaint/App/StatusItemController.swift Sources/Vorssaint/App/MenuBarRenderer.swift`)
- Modify: `Sources/Vorssaint/Services/CommandBar/CommandBarCatalog.swift`

**Interfaces:**
- Consumes: `DefaultsKey.breakReminders*`, `BreakSettingsStore`, `BreakReminderService.shared.pause(for:)/pauseUntilTomorrow()/resume()/reloadSettings()/isPaused`, `BreakReminderStrings`.

- [ ] **Step 1: Settings pane**

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct BreakReminderSettings: View {
    @EnvironmentObject private var l10n: Localization
    private var text: BreakReminderStrings { FeatureStrings.breakReminders(l10n.language) }

    @AppStorage(DefaultsKey.breakRemindersEyesEnabled) private var eyesOn = true
    @AppStorage(DefaultsKey.breakRemindersEyesIntervalMinutes) private var eyesEvery = 20
    @AppStorage(DefaultsKey.breakRemindersEyesBreakSeconds) private var eyesLength = 20
    @AppStorage(DefaultsKey.breakRemindersEyesDeliveryStyle) private var eyesStyle = DeliveryStyle.notification.rawValue
    @AppStorage(DefaultsKey.breakRemindersMovementEnabled) private var moveOn = true
    @AppStorage(DefaultsKey.breakRemindersMovementIntervalMinutes) private var moveEvery = 50
    @AppStorage(DefaultsKey.breakRemindersMovementBreakSeconds) private var moveLength = 120
    @AppStorage(DefaultsKey.breakRemindersMovementDeliveryStyle) private var moveStyle = DeliveryStyle.escalating.rawValue
    @AppStorage(DefaultsKey.breakRemindersEscalateAfterSeconds) private var escalateAfter = 120
    @AppStorage(DefaultsKey.breakRemindersWorkingHoursEnabled) private var hoursOn = false
    @AppStorage(DefaultsKey.breakRemindersWorkingDays) private var days = 0b0111110
    @AppStorage(DefaultsKey.breakRemindersWorkingStartMinutes) private var start = 540
    @AppStorage(DefaultsKey.breakRemindersWorkingEndMinutes) private var end = 1080

    var body: some View {
        Form {
            kindSection(text.eyesSection, on: $eyesOn, every: $eyesEvery, everyRange: 5...120,
                        length: $eyesLength, lengthRange: 5...300, style: $eyesStyle,
                        listKey: DefaultsKey.breakRemindersEyesActivities, kind: .eyes)
            kindSection(text.movementSection, on: $moveOn, every: $moveEvery, everyRange: 15...240,
                        length: $moveLength, lengthRange: 30...900, style: $moveStyle,
                        listKey: DefaultsKey.breakRemindersMovementActivities, kind: .movement)
            Section(text.scheduleSection) {
                Stepper("\(text.escalateAfter): \(escalateAfter / 60) min", value: $escalateAfter, in: 60...600, step: 60)
                Toggle(text.workingHours, isOn: $hoursOn)
                if hoursOn {
                    WorkingDaysPicker(days: $days)
                    MinuteOfDayPicker(label: "", minutes: $start, range: 0...(end - 15))
                    MinuteOfDayPicker(label: "", minutes: $end, range: (start + 15)...1439)
                    Text(text.workingHoursCaption).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: [eyesOn, moveOn, hoursOn]) { _ in BreakReminderService.shared.reloadSettings() }
        .onChange(of: [eyesEvery, eyesLength, moveEvery, moveLength, escalateAfter, days, start, end]) { _ in
            BreakReminderService.shared.reloadSettings()
        }
        .onChange(of: [eyesStyle, moveStyle]) { _ in BreakReminderService.shared.reloadSettings() }
    }
}
```

Write `kindSection(...)` (Toggle, two Steppers with the given ranges, a Picker over `DeliveryStyle.allCases` labelled with `text.styleNotch/…`, and `ActivityListEditor(listKey:kind:)`), `WorkingDaysPicker` (seven toggles; disallow clearing the last set bit, so `days` is never 0), `MinuteOfDayPicker` (hour and 15-minute stepper over the binding), and `ActivityListEditor` (rows of `TextField` + seconds `Stepper` 5...900 + delete button, an add button; on every change writes `BreakSettingsStore.encode(list)` to `listKey` and calls `reloadSettings()`; initial value from `BreakSettingsStore.load(...)[kind].activities`). Match the look of neighbouring panes (open `KeepAwakeSettings` or the pane for `.cleaningMode` and copy its section/row helpers rather than inventing new ones). If `@EnvironmentObject Localization` is not how neighbouring panes get the language, use their pattern.

Route the pane: add `case .breakReminders: BreakReminderSettings()` where the router maps features to panes.

- [ ] **Step 2: Status menu pause items**

Where the status menu adds feature items (mirror the Keep Awake block), when `AppFeature.breakReminders.isAvailable`:

```swift
        let breaks = NSMenuItem(title: text.pauseMenu, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        if BreakReminderService.shared.isPaused {
            sub.addItem(withTitle: text.resume, action: #selector(resumeBreaks), keyEquivalent: "").target = self
        } else {
            sub.addItem(withTitle: text.pauseHour, action: #selector(pauseBreaksHour), keyEquivalent: "").target = self
            sub.addItem(withTitle: text.pauseTomorrow, action: #selector(pauseBreaksTomorrow), keyEquivalent: "").target = self
        }
        breaks.submenu = sub
        menu.addItem(breaks)
```

```swift
    @objc private func pauseBreaksHour() { BreakReminderService.shared.pause(for: 3600) }
    @objc private func pauseBreaksTomorrow() { BreakReminderService.shared.pauseUntilTomorrow() }
    @objc private func resumeBreaks() { BreakReminderService.shared.resume() }
```

- [ ] **Step 3: Command Bar rows**

In `CommandBarCatalog.swift`, next to the keep-awake rows, add three rows gated on `AppFeature.breakReminders.isAvailable`: ids `action.breaks.pauseHour`, `action.breaks.pauseTomorrow`, `action.breaks.resume`, titles from `text.pauseHour`/`pauseTomorrow`/`resume` prefixed by `text.pauseMenu`, actions calling the three service methods. Copy the shape of an existing no-argument action row exactly.

- [ ] **Step 4: Build, test, manual check**

Run: `timeout 600 ./build.sh --test && timeout 600 ./build.sh --install`
Expected: PASS. Manual: the pane edits take effect without relaunch (change eyes to 1 minute, a prompt arrives about a minute later); clearing the last working day is impossible; Pause for 1 hour shows "Resume breaks" in the menu afterwards; the Command Bar finds "Pause breaks".

- [ ] **Step 5: Commit**

```bash
git add Sources/Vorssaint/UI/Settings/BreakReminderSettings.swift Sources/Vorssaint/Services/CommandBar/CommandBarCatalog.swift
# plus the settings router and status menu files by explicit path
git commit -m "feat(break-reminders): add the settings pane, pause menu and command bar rows"
```

---

### Task 13: End-to-end verification

**Files:** none changed unless a check fails.

- [ ] **Step 1: Full harness**

Run: `timeout 600 ./build.sh --test`
Expected: PASS with the previous check count plus the new `break-reminders` checks; record both numbers.

- [ ] **Step 2: Manual matrix** (`./build.sh --install`, eyes 1 min, movement 2 min)

| Check | Expected |
|---|---|
| Voice Memos recording when a break is due | No prompt; fires ~30 s after recording stops |
| Music on a USB/Bluetooth headset | Breaks still fire on time |
| Photo Booth open | Deferred |
| Fullscreen video | Deferred |
| Lock 3 min, unlock | Countdown restarted, no immediate prompt |
| Walk away 3 min without locking | Countdown restarted, no prompt on return |
| Eyes and movement due together | One movement prompt only |
| Each delivery style | Matches Tasks 9–11 manual checks |
| Notification permission denied, style Notification | Falls to notch, then overlay |
| Switch the feature off in the hub mid-prompt | Prompt disappears; nothing else appears |
| Pause until tomorrow with working hours Mon–Fri on a Friday | Menu shows Resume; no prompts until Monday start |

- [ ] **Step 3: Report**

Record failures as new tasks against the owning file; do not mark the plan done until the matrix passes.
