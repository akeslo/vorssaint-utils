---
title: Break Reminders design
created: 2026-09-30T00:00:00-04:00
tags: [design, spec, break-reminders]
---

# Break Reminders

## Intent

Kes wants an always-on reminder to step away from the screen: short eye breaks
("look 20ft away for 20s") and longer movement breaks ("stretch", "10 pushups").
It runs without being started, never interrupts a meeting, and does not nag
after the user already took a break by walking away.

Stated by Kes: standalone feature (not a Pomodoro add-on); both eye and movement
types; every delivery style offered (notch, notification, escalating, overlay);
defer while mic/camera in use or fullscreen; manual pause; idle reset; working
hours; in-order rotation through an editable activity list per type.

Assumed: "es" in the conversation meant "yes, both" for idle reset and working
hours.

Success: reminders fire at the configured cadence during working hours, never
while the mic or camera is live or a fullscreen app is frontmost, reset after a
real absence (idle, locked, asleep), and cost nothing when the feature is
switched off in the hub.

## Non-goals

- Detecting screen sharing directly (no public API). Covered indirectly: a call
  that shares the screen almost always holds the mic.
- Calendar-based meeting detection.
- Statistics, streaks, or history.
- Pomodoro integration.

## Architecture

New `AppFeature.breakReminders` in the `tools` group of `FeatureCatalog.swift`,
with hub icon `figure.walk` and title/description strings. `FeatureRuntime`
binds it with a closure like the other features: becoming available calls
`BreakReminderService.shared.start()`; becoming unavailable mid-session calls
`stop()`, which invalidates the timer, removes observers, and dismisses any
live prompt. Nothing is built while the feature is off.

Units. Only `BreakReminderService`, the signal sampler, and the sinks touch the
system; everything else is pure and AppKit-free.

| Unit | File | Responsibility |
|---|---|---|
| Models | `Services/BreakReminders/BreakReminderModels.swift` | `BreakKind` (`eyes`, `movement`), `BreakSettings`, `BreakSignals`, `BusyVerdict`, `BreakEvent`, `BreakAction`, `BreakActivity`, `BreakPrompt`, `DeliveryStyle`, `WorkingHours`. Foundation only. |
| `BusyPolicy` | `Services/BreakReminders/BusyPolicy.swift` | `static func verdict(_ s: BreakSignals, settings: BreakSettings, now: Date, calendar: Calendar) -> BusyVerdict`. |
| `BreakSchedule` | `Services/BreakReminders/BreakSchedule.swift` | Per-kind state machine (below). |
| `BreakCoordinator` | `Services/BreakReminders/BreakCoordinator.swift` | Owns both schedules and both rotations, applies coalescing, owns current prompt ids, escalation deadlines, and the delivery fallback chain. `mutating func tick(now:, verdict:, awayFor:) -> [CoordinatorOutput]`, `mutating func respond(promptID:, action:, now:)`, `mutating func deliveryFailed(promptID:, style:)`. |
| `ActivityRotation` | `Services/BreakReminders/ActivityRotation.swift` | Stored index per kind; `current(from:)` and `advance(count:)`. |
| `BreakSignalSampler` | `Services/BreakReminders/BreakSignalSampler.swift` | Reads the live signals. |
| `BreakReminderService` | `Services/BreakReminders/BreakReminderService.swift` | Singleton. Timer, NSWorkspace observers, feeds the coordinator, executes its outputs against sinks, persists settings/rotation/pause. |
| Sinks | `Services/BreakReminders/Delivery/{Notch,Notification,Overlay}BreakDelivery.swift` | `protocol BreakDelivery { func present(_ p: BreakPrompt, respond: @escaping (BreakAction) -> Void) -> Bool; func update(_ p: BreakPrompt); func dismiss(id: UUID) }`. `present` returns false when the surface is unavailable (feature off, unauthorized). |

Escalating is not a sink: the coordinator implements it by emitting
`dismiss` to whichever sink currently holds the prompt, then
`present(overlay)` at the deadline. Displacement or failure of the first sink
during escalating: a first-stage `present` returning false moves to
notification; displacement after a successful present moves to the overlay.

## Signals

`BreakSignals` (sampled by `BreakSignalSampler`):

- `micInUse`: some process other than Vorssaint is capturing audio input,
  read per process: `kAudioHardwarePropertyProcessObjectList`, then
  `kAudioProcessPropertyIsRunningInput` and `kAudioProcessPropertyPID` for
  each (the package targets macOS 14, `Package.swift:9`; property names
  recalled, verified in implementation task 1). The device-level
  `kAudioDevicePropertyDeviceIsRunningSomewhere` is not used, because it is
  true for a headset that is only playing audio, and the app's own mixer and
  level taps drive output devices. Lives in `Services/Audio/AudioInputActivity.swift` as
  a static function, never through `MicMuteService.shared`.
- `cameraInUse`: any CoreMediaIO device with
  `kCMIODevicePropertyDeviceIsRunningSomewhere != 0`. Recalled as needing no
  permission; verify in implementation task 1 before relying on it.
- `fullscreenFrontmost`: the frontmost app's PID owns a layer-0 on-screen
  window (`CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)`)
  whose `kCGWindowBounds` equals some `NSScreen.frame` converted to CG
  (top-left) coordinates. Bounds, owner PID and layer need no Screen Recording
  permission.
- `idleSeconds`: `CGEventSource.secondsSinceLastEventType(.hidSystemState,
  eventType: CGEventType(rawValue: ~0)!)` (any HID input). Verify the sentinel
  in implementation task 1.

Lock, session, and sleep are not polled. The service observes
`NSWorkspace.sessionDidResignActive/DidBecomeActive`, `screensDidSleep/Wake`,
`willSleep/didWake`, and the distributed `com.apple.screenIsLocked/Unlocked`
notifications. It keeps a set of active away conditions (locked, session
inactive, system asleep, screens asleep). `awayStart` is recorded when the set
becomes non-empty; away ends only when the set is empty again, and then
`awayFor = now - awayStart` is passed to the coordinator once. While away, the
regular tick is suspended; a 60 s watchdog re-derives the lock state from
`CGSessionCopyCurrentDictionary()` (`CGSSessionScreenIsLocked`) and clears the
away set when the screen is unlocked and `idleSeconds < 60`, so a missed wake
or unlock notification cannot stop reminders for the session.

Tick gaps: a gap between ticks larger than 2 x the tick interval (App Nap,
missed sleep notification) is passed as `awayFor = gap` with `dt = 0` for that
tick. `lastTick` is reset to `now` when an away period ends, so the absence is
counted once, as `awayFor`, never also as a gap.

Sampling cost: the timer ticks every 5 s. `idleSeconds` is read every tick
(cheap). Mic, camera, and the window list are read only when some kind is
`due`, `deferred`, or `prompting`; otherwise they are reported as false. The
busy verdict therefore never affects `counting`, which is consistent with the
table below (busy time counts as screen time). The fullscreen check ignores
windows owned by Vorssaint's own PID, so the overlay never counts as a
fullscreen app.

## Busy verdict

`BusyVerdict` precedence (first match wins):

1. `off`: `pausedUntil > now`, or working hours enabled and `now` outside them.
2. `idle`: `idleSeconds >= 60`.
3. `busy`: `micInUse || cameraInUse || fullscreenFrontmost`.
4. `active`.

Lock/sleep are not verdicts; they are the `awayFor` input (above).

Working hours: `workingDays` bit `n` = `Calendar` weekday `n+1` (bit 0 =
Sunday, Gregorian, user's current time zone). Start inclusive, end exclusive,
start < end enforced by the settings UI (no overnight ranges).

## BreakSchedule state machine (one per kind)

Settings per kind: `enabled`, `interval` (eyes 20 min, movement 50 min),
`breakLength` (eyes 20 s, movement 2 min).

States: `counting(elapsed)`, `due`, `deferred(activeFor)`, `prompting(id,
since)`, `snoozed(until)`.

Inputs per tick: `dt`, `verdict`, `idleSeconds`, and once after an absence,
`awayFor`.

Each schedule makes at most one transition per tick. The tick that moves
`counting` to `due` emits nothing; the next tick, which samples the busy
signals because a kind is now `due`, decides between `prompting` and
`deferred`. A prompt therefore never fires on unsampled busy signals.

Absence reset (checked first, every tick, any state), with
`resetThreshold = max(breakLength, 2 min)`:

- `awayFor >= resetThreshold`: reset to `counting(0)`, emitting `dismiss` if
  prompting.
- `idleSeconds >= resetThreshold`: reset to `counting(0)` (emitting `dismiss`
  if prompting) and hold there every tick while the condition lasts. Ongoing
  idle is treated like away, so a 25-minute walk-away without locking returns
  to a fresh countdown, not a pending prompt.

Measuring from `idleSeconds` directly, not from when the verdict flipped, makes
the threshold exact. Idle reset ignores the busy signals: a call listened to
hands-off for 2 minutes counts as a break. Accepted.

| From | Verdict / input | To |
|---|---|---|
| counting(e) | active, busy, idle | counting(e + dt); idle below the reset threshold still counts as screen time |
| counting(e) | off | counting(e) frozen |
| counting(e) | e >= interval | due |
| due | active | prompting(new id, now); emits `prompt` |
| due | busy, idle | deferred(0) |
| due | off | due (held) |
| deferred(a) | active | deferred(a + dt); at a >= 30 s → prompting, emits `prompt` |
| deferred(a) | busy, idle | deferred(0) (grace restarts) |
| deferred(a) | off | deferred(0) held |
| prompting | `done`, `skip` | counting(0) |
| prompting | no response for breakLength + 60 s after the overlay actually presented (overlay, and escalating once it reaches the overlay), or 10 min after the notch/notification presented | counting(0); emits `dismiss`. Timers start at the sink's present time, not at entry to `prompting`; a prompt that never reached a screen ends with no rotation advance |
| prompting | `snooze` | snoozed(now + 5 min); emits `dismiss` |
| prompting | busy | deferred(0); emits `dismiss` (a call started) |
| prompting | off | counting(0); emits `dismiss` (paused or hours ended) |
| prompting | active, idle | unchanged |
| snoozed(u) | now >= u | due |
| snoozed(u) | active, busy, idle before u | unchanged |
| snoozed(u) | off | counting(0) |
| any | kind disabled | counting(0); emits `dismiss` if prompting |

Settings edits: changing `interval` keeps `elapsed` and re-checks `due` on the
next tick. Nothing in the schedule is persisted; launch starts at
`counting(0)`.

## Coordinator rules

- Coalescing, one rule each way:
  - Whenever movement emits `prompt`: if eyes is `prompting`, dismiss it; if
    eyes is `prompting`, `due`, `deferred`, `snoozed`, or `counting(e)` with
    `e >= interval - 60 s`, reset eyes to `counting(0)`. Rotation does not
    advance for eyes. Same-tick ties are the same case.
  - Eyes may not enter `prompting` while movement is `counting(e)` with
    `e >= interval - 60 s`; eyes resets to `counting(0)` instead.
  - Eyes may not leave `due`/`deferred` for `prompting` while movement is
    `due`, `deferred`, `prompting`, or `snoozed`; instead eyes resets to
    `counting(0)` (movement covers it).
- One prompt on screen at a time; responses whose `promptID` is not current are
  ignored.
- Rotation: a prompt shows `rotation.current`. The index advances only when the
  prompt ends with `done`, `skip`, no-response timeout, or an absence reset
  while prompting (walking away counts as taking it). Snooze re-prompts the
  same activity; coalesced resets do not advance. Deleting activities clamps the
  index to `count - 1`, wrapping to 0 on the next advance. An empty list uses a
  generic localized message.
- The activity's `seconds` replaces `breakLength` for that prompt's countdown
  and timeouts only; the absence-reset threshold always uses the kind's
  `breakLength`.

## Delivery

`DeliveryStyle` per kind: `notch`, `notification`, `escalating`, `overlay`.
Defaults: eyes `notification`, movement `escalating`.

Fallback chain: the requested style, then the remaining styles in the fixed
order notch → notification → overlay, each tried at most once. A sink whose `present` returns false is skipped
immediately; there is no retry. The
overlay always presents, so the chain terminates. Escalating starts at notch
(skipping to notification if notch fails) and goes to overlay at
`escalateAfter` (default 2 min).

### Notch

The plain `NotchNotice` path is not used: notices have fixed durations, no
actions, priority-based replacement, and no expanded form for non-banner
notices. Instead the sink reuses the existing expanded custom-panel mechanism,
`NotchService.presentCapture(id:content:actions:height:fallback:close:hover:)`
(`NotchService.swift:1890`), which already takes arbitrary SwiftUI content and
an actions view, stays until `removeCapture(id:)`, and reports visibility via
`isCaptureVisible(id:)`.

Changes, part of this work:

1. Route stored with the capture: `presentCapture` gains `route: NotchEvent =
   .capture`, `takeFocus: Bool? = nil` (nil keeps today's
   `screenshotPreviewTakesFocus` read), `pinIsland: Bool = false`,
   `collapsed: (() -> Void)? = nil`, and `displaced: (() -> Void)? = nil`. It stores `captureRoute`. The entry guard
   at `NotchService.swift:1892` becomes `guard acceptsSystemFeedback,
   NotchSupport.routes(route)`, so a break presents with the Screenshot
   feature or the Captures module off. When the route goes off in
   `syncWithPreferences`, the stored `captureFallback` runs; for a break it is
   delivery failure (the chain advances). The guard in
   `syncWithPreferences` (`NotchService.swift:782-786`) checks
   `routes(captureRoute)` instead of `routes(.capture)`, so screenshots being
   off never wipes a break prompt.
2. Page access: `open()` only selects enabled modules (around
   `NotchService.swift:944`). `presentCapture` passes a flag that lets
   `.captures` be selected when `captureRoute != .capture`, regardless of the
   module list. After `open`, `presentCapture` returns
   `isCaptureVisible(id:)`, so a prompt that did not land on screen is a
   delivery failure, not a silent success. On that false return
   `presentCapture` calls `clearCapture()` and undoes a pin it took, so no
   stale break capture remains.
3. `NotchEvent.breakReminder`: added to every exhaustive switch, including
   `preferenceKey` (`NotchSupport.swift:1226`) with new
   `DefaultsKey.notchBreakReminders` registered default true. `routes` returns
   that key `&& AppFeature.breakReminders.isAvailable(in: defaults)`. Register
   `DefaultsKey.notchBreakReminders: true` in `registeredDefaults`
   (`Defaults.swift`) and the new feature's entry in
   `AppFeature.availabilityDefaults`. If the notch settings enumerate
   `NotchEvent.allCases`, the new row gets strings in every locale. The sink
   checks `NotchService.shared.showsSystemFeedback` (which also excludes
   hidden-until-hover) before calling; when false, `present` returns false.
   The shared `acceptsSystemFeedback` guard in `presentCapture` is unchanged.
4. The break sink calls `presentCapture(route: .breakReminder, takeFocus:
   false, pinIsland: true, collapsed: …, displaced: …)`. Pinned keeps the island open through
   pointer exit and app switches (`closesOnPointerExit`,
   `NotchService.swift:2735`). `collapse()` (`:991`) has many call sites; only
   user-gesture collapses (Esc at `:1426`/`:1430`, `.hidePad`, the toggle)
   call the stored `collapsed` callback, which for breaks maps to `snooze`.
   Every other collapse with a break capture set (`collapse()` clears `pinned`,
   and `menuPanelWillShow` `:2664`, `bringIsland(to:)` `:2314`, the Space
   change `:2618`, `openSettings` `:1648`, `perform` `:1660`, `showUpdate`
   `:2955` all call it) calls the stored `displaced` callback immediately and
   clears the capture; the sink reports failure and the chain advances. `close` (session change at `:2771`, `stop`) resets the schedule to
   `counting(0)` with no rotation advance and no fallback, whether or not the
   away tracker has recorded the change yet.
5. Content: new `UI/Notch/NotchBreakView.swift` showing activity text and a
   countdown (`TimelineView`, no per-second service calls); actions view with
   Done / Snooze / Skip calling `respond`.
6. Displacement: the pure `NotchBreakWatch` (models file; inputs
   `captureID`, `visible`, `expanded`, `now`) is fed each tick by the
   service as a backstop for paths that hide the capture without collapsing; when `captureID != id`, or
   `!isCaptureVisible(id:)` while the island is not collapsed (another module
   selected, capture controls took the island, hidden in fullscreen) lasts
   10 s, the sink reports failure and the chain advances. A user collapse is
   handled by item 4 (snooze) and is never displacement. A displaced prompt
   never reaches the no-response timeout, so rotation never advances for a
   break that was not seen.
7. Never displace a screenshot: if `captureID != nil` and
   `captureRoute == .capture` when a break would present, the sink's
   `present` returns false and the chain moves on.
8. Pin ownership: `keepOpen = expanded && self.pinned && !captureOwnsPin`
   (a pin a previous capture took does not count as the user's), and
   `presentCapture` records `captureOwnsPin = !keepOpen && pinIsland`
   (`NotchService.swift:1893`); a capture replacing a pin-owning one inherits
   the ownership.
   `removeCapture(id:)` (`:1920-1927`) clears the capture first, including the
   stored `collapsed` callback in `clearCapture`, then, if `captureOwnsPin`,
   unpins and collapses. A dismiss therefore never leaves an empty pinned
   island and is never also reported as a snooze.
9. `dismiss(id:)` calls `removeCapture(id:)`.
10. `collapse()` gains `user: Bool = false`; only the Esc, `.hidePad`, and
    toggle sites pass `true` (source contract test). Early returns in
    `collapse()` (`captureControls`, `heldDrag`) fire neither callback; the
    `NotchBreakWatch` backstop covers them.
11. `withdrawFromMissingScreen` (`:2525-2538`) runs `captureFallback`; for a
    break that is delivery failure.
12. On a false return, `presentCapture` also collapses the island if it was
    not expanded before the call.
13. After `stop()`, sink callbacks (`respond`, fallback, displaced,
    collapsed) do nothing; `stop()` removes the notch capture without running
    its fallback.

### Notification

Category `breakReminder` with actions Done / Snooze, both with empty options
(no `.foreground`), and category option `.customDismissAction`;
`UNNotificationDismissActionIdentifier` maps to `skip`. Category registration today happens only inside
`Notifier.postWhatsAppOrganization` (`Notifier.swift:44`) and replaces all
categories. It moves into one `Notifier.registerCategories()` that registers
both the WhatsApp and break categories; it is called at launch inside the
existing `Bundle.main.bundleIdentifier != nil` guard (`AppDelegate.swift:56-60`) and the
WhatsApp path calls it instead of its own `setNotificationCategories`. `userNotificationCenter(_:didReceive:)`
in `AppDelegate.swift:2388` routes responses whose `userInfo["breakPromptID"]`
is set to the service; the default tap counts as `done`. A new
`userNotificationCenter(_:willPresent:)` returns `[.banner, .sound]` only for
requests carrying `breakPromptID`, and `[]` for everything else (identical to
today's behavior with no `willPresent`). On `dismiss` or timeout the sink calls
`removeDeliveredNotifications(withIdentifiers:)` and
`removePendingNotificationRequests(withIdentifiers:)` for the prompt id.
`Notifier.post` today uses `UUID().uuidString` as the request id
(`Notifier.swift:76`); it gains an `identifier:` parameter and the sink passes
`promptID.uuidString`. Authorization status is cached at
`start()` and on `didBecomeActive`; `present` returns false when not
authorized. Authorization is requested via `Notifier.requestPermission()` when
the feature is installed from the hub, and at `start()` whenever an enabled
kind resolves to `notification` or `escalating` while the status is
`.notDetermined` (the eyes default is notification, so this fires on a fresh
install). A stale cache (permission revoked since the last read) can drop
one prompt silently until the 10-minute timeout; accepted.

### Overlay

Borderless `NSPanel` per screen at `.screenSaver` level,
`[.canJoinAllSpaces, .fullScreenAuxiliary]`, translucent dim, activity text,
countdown, Done / Snooze / Skip buttons. Style `.nonactivatingPanel`; the
buttons' hosting view returns true from `acceptsFirstMouse` so the first
click acts. When the countdown reaches zero the overlay shows a "Done" state;
it does not close itself. The schedule's timeout (breakLength + 60 s from
present) ends it, with the same effect as `done`. Changing a kind's
delivery style mid-prompt goes through `BreakCoordinator.settingsChanged(_:)`:
it dismisses and re-presents with the new style on the next tick, keeping the
prompt id and activity and restarting the timers at the new present. It never becomes key and takes no
keyboard focus; there is no Esc shortcut. If `IsSecureEventInputEnabled()`
(see `Core/SecureInputSupport.swift`) is true when the overlay would present,
it waits up to 2 min for it to clear, then presents anyway.

## Activities

`BreakActivity { id: UUID, text: String, seconds: Int }`. Two editable lists
seeded with localized defaults:

- Eyes: "Look at something 20 feet away" (20 s), "Close your eyes" (10 s),
  "Blink slowly ten times" (10 s).
- Movement: "Stand up and stretch" (60 s), "10 pushups" (60 s),
  "Walk around for two minutes" (120 s), "Shoulder rolls" (30 s).

## Settings and storage

New `DefaultsKey` entries, each registered in `Defaults.registeredDefaults`
so `SettingsBackupSupport` (`SettingsBackupSupport.swift:19`) backs them up,
all prefixed `breakReminders`: per kind `enabled`,
`intervalMinutes`, `breakSeconds`, `deliveryStyle`, `activities` (JSON),
`rotationIndex`; shared `escalateAfterSeconds`, `workingHoursEnabled`,
`workingDays`, `workingStartMinutes`, `workingEndMinutes`, `pausedUntil`. Only
these persist.

Pause: "1 hour" sets `pausedUntil = now + 1 h`. "Until tomorrow" sets it to
`workingStartMinutes` on the first day after today (calendar day, so a
pre-start morning still skips today) whose `workingDays` bit is set, when
working hours are on (the settings UI requires at least one day); otherwise to
the next local midnight. "Resume" clears it. Available from the status menu and as Command
Bar rows.

Settings pane `UI/Settings/BreakReminderSettings.swift`: Eyes and Movement
sections (enable, interval, break length, delivery style, activity editor) and
a Schedule section (working hours, escalate-after). Strings in
`Core/BreakReminderStrings.swift` plus a block in each
`Core/Localizations/Strings+*.swift`; any literal `%` in a format string is
`%%` in every locale.

## Testing

`Tests/BreakReminderTests.swift` is compiled by the `Tests/*.swift` glob
(`build.sh:536`) and follows the `enum …Contract { static func run(_ suite:
TestSuite) }` shape with `suite.expect`. It only runs once registered in the
suite registry in `Tests/MetricsTests.swift` (appended to the registry array) as
`("break-reminders", { BreakReminderTests.run(suite) })`. The pure sources must be added to the explicit `TEST_SOURCES`
list: `BreakReminderModels.swift`, `BusyPolicy.swift`, `BreakSchedule.swift`,
`BreakCoordinator.swift`, `ActivityRotation.swift`,
`Core/BreakReminderStrings.swift`, and the locale files if not already listed.

Cases:

- `BusyPolicy`: precedence, working-days bit mapping, hour edges, pause expiry.
- `BreakSchedule`: every row in the table; absence reset via `awayFor` (lock,
  sleep) and via `idleSeconds`, once per stretch; reading pause of 80 s does
  not reset; grace restart; snooze; each timeout; disable mid-prompt; interval
  change mid-count.
- `BreakCoordinator`, tested through its `[CoordinatorOutput]` and
  `deliveryFailed` (no sink in the test build; `BreakDelivery` lives with the
  sinks): both coalescing rules over
  every eyes state, and same-tick ties; stale prompt ids ignored; escalation at the
  deadline dismisses the current sink; displacement during escalating goes to
  overlay; fallback chain order; rotation
  advances only on done/skip/timeout; a deferral during a 90-minute call (inputs keep
  `idleSeconds < 60`) fires 30 s after the call ends; 25 minutes idle then
  active yields no prompt for a full `interval`.
- `ActivityRotation`: wrap, clamp after deletion, empty list.
- Localization: every new key in every locale; no unescaped `%`.
- Signals/away (pure helper `AwayTracker` in the models file): lock, wake
  while still locked, unlock yields one `awayFor`; tick-gap clamp converts a
  large gap to `awayFor`; a call starting mid-prompt yields busy and dismisses.
- Notifier: `registerCategories()` registers both categories; the WhatsApp
  path no longer calls `setNotificationCategories` directly (source contract
  test like `KeepAwakeCatalogContract`).
- Notch: `routes(.breakReminder)` is true with the Screenshot feature
  unavailable and `.captures` absent from the modules; `NotchBreakWatch`
  reports displacement when the capture is replaced or invisible for 10 s
  while expanded, and never for a user collapse; the source contract that a
  break never presents over a live screenshot capture.
- Schedule: the tick that crosses `interval` while the mic is live does not
  prompt.

Manual check: `./build.sh --install`, 1-minute intervals, each delivery style,
mic-busy deferral (Voice Memos recording), music on a USB headset does not
defer, lock 3 min then unlock resets, and
switching the feature off in the hub mid-prompt dismisses it.

## Risks

- `fullscreenFrontmost` by bounds also matches a borderless window that exactly
  covers a display. Accepted: it only defers.
- A notification nobody looks at times out after 10 minutes and advances the
  rotation. Accepted: the activity list is a rotation, not a curriculum.
- Long calls defer indefinitely by design. Eyes stays reset while movement is
  deferred, so after a long call both collapse into one movement prompt.
  Accepted.
- Fullscreen detection uses CGWindowList rather than the notch's
  `hiddenInFullscreen` because the notch feature may be off. A fullscreen app
  on a display whose reported bounds exclude the menu-bar band may be missed;
  that only means a prompt is not deferred.
- `cameraInUse` also sees Vorssaint's own camera preview; that defers
  breaks while the preview is open. Accepted.
- `cameraInUse` uses CoreMediaIO; `import CoreMediaIO` autolinks for the app
  build. The sampler is not in the test build, so no test link change.
- `cameraInUse` and the idle sentinel are recalled API details; implementation
  task 1 verifies both before anything depends on them.
