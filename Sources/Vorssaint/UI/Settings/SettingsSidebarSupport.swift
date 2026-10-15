// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One fixed row of the Settings sidebar: a page, never a tool inside one.
struct SettingsSidebarItem: Identifiable {
    let id: SettingsPage
    let title: String
    let icon: String
    /// On/total features, for category rows.
    var count: String? = nil

    var destination: FeatureSettingsDestination { FeatureSettingsDestination(id) }
}

/// A stable group of rows; its title follows the selected language.
struct SettingsSidebarSection: Identifiable {
    let id: Int
    let title: String
    let items: [SettingsSidebarItem]
}

enum SettingsSidebarSupport {
    /// The row that owns `page`: its own, or for a feature's page the
    /// category of that feature. Nil for pages no row stands for.
    static func selection(for page: SettingsPage,
                          in items: [SettingsSidebarItem]) -> SettingsPage? {
        if items.contains(where: { $0.id == page }) { return page }
        return FeatureVisibilitySupport.features(for: page).first.map { .category($0.group) }
    }
}
