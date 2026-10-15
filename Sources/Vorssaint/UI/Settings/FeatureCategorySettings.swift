// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Every feature of one group, on and off alike: off rows stay in place,
/// dimmed, so a page never changes shape when something is switched.
struct FeatureCategorySettings: View {
    let group: FeatureGroup
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var router = SettingsRouter.shared
    @State private var expanded: Set<AppFeature> = []

    var body: some View {
        let members = AppFeature.features(in: group)
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(group.title(FeatureStrings.hub(l10n.language))).font(.title2.bold())
                    Spacer()
                    Text("\(members.filter(\.isAvailable).count)/\(members.count)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ForEach(members, id: \.self) { feature in
                    FeatureRow(feature: feature, expanded: Binding(
                        get: { expanded.contains(feature) },
                        set: { if $0 { expanded.insert(feature) } else { expanded.remove(feature) } }))
                        .id(feature)
                }
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(22)
        }
        .onAppear { reveal(proxy) }
        .onChange(of: router.pendingFeatureTarget) { _, _ in reveal(proxy) }
        }
    }

    /// A search result's feature: open its options and scroll to its row.
    private func reveal(_ proxy: ScrollViewProxy) {
        guard let request = router.pendingFeatureTarget,
              request.feature.group == group else { return }
        router.consumeFeatureTarget(id: request.id)
        expanded.insert(request.feature)
        DispatchQueue.main.async { proxy.scrollTo(request.feature, anchor: .top) }
    }
}

/// One feature: its single switch, where it shows (chips that never gate
/// it), what blocks it, and its existing options inline.
struct FeatureRow: View {
    let feature: AppFeature
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var permissions = Permissions.shared
    @Binding var expanded: Bool

    private var hub: FeatureHubStrings { FeatureStrings.hub(l10n.language) }

    var body: some View {
        let state = feature.state
        let on = state != .off
        SettingsCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.hubTitle(l10n.s, hub: hub)).font(.headline)
                        Text(feature.hubDescription(hub))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Toggle(feature.hubTitle(l10n.s, hub: hub), isOn: Binding(
                        get: { feature.isAvailable },
                        set: { FeatureRuntime.shared.setAvailable([feature], $0) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(!on && feature.installBlockedReason != nil)
                        .help(on ? "" : feature.installBlockedReason ?? "")
                }
                .opacity(on ? 1 : 0.5)
                if on, !chips.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                            Label(chip.text, systemImage: chip.symbol)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .foregroundStyle(chip.on ? Color.accentColor : Color.secondary)
                                .background(Capsule().fill(chip.on ? Color.accentColor.opacity(0.12) : Color.clear))
                                .overlay(Capsule().stroke(Color.secondary.opacity(0.3)))
                        }
                    }
                }
                if case .blocked(let block) = state { attention(block) }
                if on, let page = optionsPage {
                    DisclosureGroup(l10n.s.keepAwakeOptions, isExpanded: $expanded) {
                        if expanded {
                            // A page brings its own scroll view, so it gets a bounded frame.
                            options(page).frame(height: 460)
                        }
                    }
                }
            }
        }
    }

    private func attention(_ block: FeatureState.Block) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            switch block {
            case .permission(let permission):
                Text("\(permission.name(hub)): \(hub.statusMissing)")
                Spacer(minLength: 8)
                Button(hub.openSystemSettings) { permission.openSystemSettings() }
                    .controlSize(.small)
            case .hardware(let reason):
                Text(reason).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .font(.caption)
        .foregroundStyle(.orange)
        .padding(8)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    /// Nil when the feature has no page, or only the Features page itself.
    private var optionsPage: SettingsPage? {
        let page = feature.settingsDestination.page
        return feature.hasNavigableSettingsDestination && page != .features ? page : nil
    }

    @ViewBuilder
    private func options(_ page: SettingsPage) -> some View {
        let anchor = feature.settingsDestination.sectionAnchor
        if page == .general, let anchor, GeneralToolSettings.anchors.contains(anchor) {
            GeneralToolSettings(anchor: anchor)
        } else {
            SettingsPageContent(page: page, anchor: anchor)
        }
    }

    private struct Chip { let text: String; let symbol: String; let on: Bool }

    /// shortcut: no Dynamic Island chip yet; the island joins this model in its own step.
    private var chips: [Chip] {
        let defaults = UserDefaults.standard
        var result: [Chip] = []
        if let section = PanelSectionID.allCases.first(where: { $0.featureGate.contains(feature) }) {
            let shown = defaults.object(forKey: section.visibilityKey) as? Bool ?? section.shownByDefault
            result.append(Chip(text: hub.chipMenuPanel, symbol: "menubar.dock.rectangle", on: shown))
        }
        let metrics = MenuBarMetric.allCases.filter { $0.feature == feature }
        if !metrics.isEmpty {
            result.append(Chip(text: l10n.s.menuBarSection, symbol: "menubar.rectangle",
                               on: metrics.contains { defaults.bool(forKey: $0.defaultsKey) }))
        }
        for role in GlobalShortcutRole.allCases
        where role.feature == feature && role.requiredEnableKeys.allSatisfy(defaults.bool(forKey:)) {
            result.append(Chip(text: role.savedShortcut.displayString, symbol: "command", on: true))
        }
        return result
    }
}
