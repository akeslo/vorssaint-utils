// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct BreakReminderSettings: View {
    @ObservedObject private var l10n = L10n.shared
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
                        length: $eyesLength, lengthRange: 5...300, lengthStep: 5, style: $eyesStyle,
                        listKey: DefaultsKey.breakRemindersEyesActivities, kind: .eyes)
            kindSection(text.movementSection, on: $moveOn, every: $moveEvery, everyRange: 15...240,
                        length: $moveLength, lengthRange: 30...900, lengthStep: 15, style: $moveStyle,
                        listKey: DefaultsKey.breakRemindersMovementActivities, kind: .movement)
            Section(text.scheduleSection) {
                Stepper(value: $escalateAfter, in: 60...600, step: 60) {
                    Text("\(text.escalateAfter): \(BreakDurationText.seconds(escalateAfter))")
                }
                Toggle(text.workingHours, isOn: $hoursOn)
                if hoursOn {
                    WorkingDaysPicker(days: $days)
                    HStack {
                        MinuteOfDayPicker(minutes: $start, range: 0...max(0, end - 15))
                        Text("–").foregroundStyle(.secondary)
                        MinuteOfDayPicker(minutes: $end, range: min(1439, start + 15)...1439)
                    }
                    Text(text.workingHoursCaption).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: [eyesOn, moveOn, hoursOn]) { _, _ in BreakReminderService.shared.reloadSettings() }
        .onChange(of: [eyesEvery, eyesLength, moveEvery, moveLength, escalateAfter, days, start, end]) { _, _ in
            BreakReminderService.shared.reloadSettings()
        }
        .onChange(of: [eyesStyle, moveStyle]) { _, _ in BreakReminderService.shared.reloadSettings() }
    }

    @ViewBuilder
    private func kindSection(_ title: String, on: Binding<Bool>, every: Binding<Int>, everyRange: ClosedRange<Int>,
                             length: Binding<Int>, lengthRange: ClosedRange<Int>, lengthStep: Int,
                             style: Binding<String>, listKey: String, kind: BreakKind) -> some View {
        Section(title) {
            Toggle(text.enabled, isOn: on)
            if on.wrappedValue {
                Stepper(value: every, in: everyRange, step: 5) {
                    Text("\(text.interval): \(BreakDurationText.minutes(every.wrappedValue))")
                }
                Stepper(value: length, in: lengthRange, step: lengthStep) {
                    Text("\(text.breakLength): \(BreakDurationText.seconds(length.wrappedValue))")
                }
                Picker(text.deliveryStyle, selection: style) {
                    ForEach(DeliveryStyle.allCases, id: \.rawValue) { Text(styleName($0)).tag($0.rawValue) }
                }
                ActivityListEditor(listKey: listKey, kind: kind, text: text)
            }
        }
    }

    private func styleName(_ style: DeliveryStyle) -> String {
        switch style {
        case .notch: return text.styleNotch
        case .notification: return text.styleNotification
        case .escalating: return text.styleEscalating
        case .overlay: return text.styleOverlay
        }
    }
}

/// Localized, locale-aware durations for the steppers.
enum BreakDurationText {
    static func seconds(_ value: Int) -> String {
        Duration.seconds(value).formatted(.units(allowed: [.minutes, .seconds], width: .narrow))
    }

    static func minutes(_ value: Int) -> String {
        Duration.seconds(value * 60).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }
}

/// Seven weekday toggles. `days` bit n is Calendar weekday n+1; the last
/// selected day cannot be cleared, so the mask is never 0.
struct WorkingDaysPicker: View {
    @Binding var days: Int

    private var weekdayOrder: [Int] {
        let first = Calendar.current.firstWeekday - 1
        return (0..<7).map { (first + $0) % 7 }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(weekdayOrder, id: \.self) { bit in
                Toggle(Calendar.current.shortWeekdaySymbols[bit], isOn: binding(for: bit))
                    .toggleStyle(.button)
                    .controlSize(.small)
            }
        }
    }

    private func binding(for bit: Int) -> Binding<Bool> {
        Binding(
            get: { days & (1 << bit) != 0 },
            set: { on in
                let next = on ? days | (1 << bit) : days & ~(1 << bit)
                if next & 0x7F != 0 { days = next }
            })
    }
}

/// A time of day in 15-minute steps. The caller bounds `range` so the start
/// stays before the end.
struct MinuteOfDayPicker: View {
    @Binding var minutes: Int
    let range: ClosedRange<Int>

    private var time: Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    var body: some View {
        Stepper(value: $minutes, in: range, step: 15) {
            Text(time, style: .time)
        }
    }
}

/// Edits one kind's activity list. The JSON key is written only when the user
/// changes the list, never on appearance: an unwritten key means "seed from
/// the current language", and saving unedited seeds would freeze them.
struct ActivityListEditor: View {
    let listKey: String
    let kind: BreakKind
    let text: BreakReminderStrings

    @ObservedObject private var l10n = L10n.shared
    @State private var list: [BreakActivity] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text.activities).font(.subheadline.weight(.medium))
            ForEach($list, id: \.id) { $activity in
                HStack {
                    TextField("", text: Binding(get: { activity.text },
                                                set: { newValue in update(activity.id) { $0.text = newValue } }))
                        .textFieldStyle(.roundedBorder)
                    Stepper(value: Binding(get: { activity.seconds },
                                           set: { newValue in update(activity.id) { $0.seconds = newValue } }),
                            in: 5...900, step: 5) {
                        Text(BreakDurationText.seconds(activity.seconds)).monospacedDigit()
                    }
                    .fixedSize()
                    Button(role: .destructive) {
                        let id = activity.id
                        commit(list.filter { $0.id != id })
                    } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                }
            }
            Button {
                commit(list + [BreakActivity(id: UUID(), text: "", seconds: kind == .eyes ? 20 : 60)])
            } label: { Label(text.addActivity, systemImage: "plus.circle") }
                .buttonStyle(.borderless)
        }
        .onAppear(perform: reload)
        .onChange(of: l10n.language) { _, _ in reload() }
    }

    private func reload() {
        list = BreakSettingsStore.load(.standard, language: l10n.language)[kind].activities
    }

    private func update(_ id: UUID, _ change: (inout BreakActivity) -> Void) {
        var next = list
        guard let index = next.firstIndex(where: { $0.id == id }) else { return }
        change(&next[index])
        commit(next)
    }

    private func commit(_ next: [BreakActivity]) {
        list = next
        UserDefaults.standard.set(BreakSettingsStore.encode(next), forKey: listKey)
        BreakReminderService.shared.reloadSettings()
    }
}
