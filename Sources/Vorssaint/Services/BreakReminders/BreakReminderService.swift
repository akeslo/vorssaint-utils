// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox

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
        settings = BreakSettingsStore.load(defaults, language: L10n.shared.language)
    }

    var isPaused: Bool { (settings.pausedUntil ?? .distantPast) > Date() }

    func syncWithPreferences() {
        let wanted = AppFeature.breakReminders.isAvailable
        if wanted && !running { start() } else if !wanted && running { stop() } else if running { reloadSettings() }
    }

    func start() {
        guard !running else { return }
        running = true
        settings = BreakSettingsStore.load(defaults, language: L10n.shared.language)
        coordinator = BreakCoordinator(rotation: BreakSettingsStore.loadRotation(defaults))
        clock.reset(now: Date())
        sinks[.notification] = NotificationBreakDelivery.shared
        sinks[.overlay] = OverlayBreakDelivery.shared
        let wantsNotifications = [settings.eyes, settings.movement].contains {
            $0.enabled && ($0.style == .notification || $0.style == .escalating)
        }
        NotificationBreakDelivery.shared.refreshAuthorization(requestIfUndetermined: wantsNotifications)
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
        settings = BreakSettingsStore.load(defaults, language: L10n.shared.language)
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
            // The overlay may be waiting on secure input; overlayShownLate starts its timers.
            if via == .overlay && IsSecureEventInputEnabled() { return }
            coordinator.presented(id: prompt.id, via: via, now: Date(), settings: settings)
        } else {
            execute(coordinator.deliveryFailed(id: prompt.id, via: via, now: Date(), settings: settings))
        }
    }

    /// The overlay waited on secure input; restart its timers from now.
    func overlayShownLate(id: UUID) {
        guard running else { return }
        coordinator.presented(id: id, via: .overlay, now: Date(), settings: settings)
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
        on(NotificationCenter.default, NSApplication.didBecomeActiveNotification) {
            NotificationBreakDelivery.shared.refreshAuthorization(requestIfUndetermined: false)
        }
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
