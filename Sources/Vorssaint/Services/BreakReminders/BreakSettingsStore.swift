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

    /// The brief's `save(_:to:)`: persists every field of the settings.
    static func save(_ s: BreakSettings, to d: UserDefaults) {
        func kind(_ k: KindSettings, _ enabled: String, _ interval: String, _ length: String, _ style: String, _ list: String) {
            d.set(k.enabled, forKey: enabled)
            d.set(Int(k.interval / 60), forKey: interval)
            d.set(Int(k.breakLength), forKey: length)
            d.set(k.style.rawValue, forKey: style)
            d.set(encode(k.activities), forKey: list)
        }
        kind(s.eyes, DefaultsKey.breakRemindersEyesEnabled, DefaultsKey.breakRemindersEyesIntervalMinutes,
             DefaultsKey.breakRemindersEyesBreakSeconds, DefaultsKey.breakRemindersEyesDeliveryStyle,
             DefaultsKey.breakRemindersEyesActivities)
        kind(s.movement, DefaultsKey.breakRemindersMovementEnabled, DefaultsKey.breakRemindersMovementIntervalMinutes,
             DefaultsKey.breakRemindersMovementBreakSeconds, DefaultsKey.breakRemindersMovementDeliveryStyle,
             DefaultsKey.breakRemindersMovementActivities)
        d.set(Int(s.escalateAfter), forKey: DefaultsKey.breakRemindersEscalateAfterSeconds)
        d.set(s.hours.enabled, forKey: DefaultsKey.breakRemindersWorkingHoursEnabled)
        d.set(s.hours.days, forKey: DefaultsKey.breakRemindersWorkingDays)
        d.set(s.hours.startMinutes, forKey: DefaultsKey.breakRemindersWorkingStartMinutes)
        d.set(s.hours.endMinutes, forKey: DefaultsKey.breakRemindersWorkingEndMinutes)
        savePause(s.pausedUntil, to: d)
    }
}
