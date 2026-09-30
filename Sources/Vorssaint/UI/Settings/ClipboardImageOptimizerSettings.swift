// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The image optimizer's section of the clipboard page.
struct ClipboardImageOptimizerSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.clipboardImageOptimizerEnabled) private var enabled = false
    @AppStorage(DefaultsKey.clipboardImageOptimizerFormat) private var format = "keep"
    @AppStorage(DefaultsKey.clipboardImageOptimizerQuality)
    private var quality = ClipboardImageOptimizerSupport.defaultQuality
    @AppStorage(DefaultsKey.clipboardImageOptimizerMaxDimension) private var maxDimension = 0
    @AppStorage(DefaultsKey.clipboardImageOptimizerHalveRetina) private var halveRetina = false
    @AppStorage(DefaultsKey.clipboardImageOptimizerIncludeFiles) private var includeFiles = false

    private var text: ClipboardImageOptimizerStrings {
        FeatureStrings.clipboardImageOptimizer(l10n.language)
    }

    var body: some View {
        Section {
            Toggle(text.enable, isOn: $enabled)
                .onChange(of: enabled) { _, _ in resync() }
            Text(text.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
            if enabled {
                Picker(text.formatLabel, selection: $format) {
                    Text(text.formatKeep).tag(ClipboardImageOptimizerSupport.FormatPolicy.keep.rawValue)
                    Text(text.formatJPEG).tag(ClipboardImageOptimizerSupport.FormatPolicy.jpeg.rawValue)
                }
                .onChange(of: format) { _, _ in resync() }
                if format == ClipboardImageOptimizerSupport.FormatPolicy.jpeg.rawValue {
                    Text(text.formatCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LabeledContent(text.quality) {
                        HStack {
                            Slider(value: $quality, in: 0.1...1, step: 0.05)
                                .accessibilityLabel(text.quality)
                            Text("\(Int((quality * 100).rounded()))%")
                                .monospacedDigit()
                                .frame(minWidth: 40, alignment: .trailing)
                        }
                    }
                    .onChange(of: quality) { _, _ in resync() }
                }
                Picker(text.maxDimension, selection: $maxDimension) {
                    ForEach(ClipboardImageOptimizerSupport.maxDimensionChoices, id: \.self) { value in
                        Text(value == 0 ? text.maxDimensionOff : "\(value) px").tag(value)
                    }
                }
                .onChange(of: maxDimension) { _, _ in resync() }
                Toggle(text.halveRetina, isOn: $halveRetina)
                    .onChange(of: halveRetina) { _, _ in resync() }
                Text(text.halveRetinaCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(text.includeFiles, isOn: $includeFiles)
                    .onChange(of: includeFiles) { _, _ in resync() }
                Text(text.includeFilesCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(text.title)
        }
        .settingsFormSectionAnchor(.clipboardImageOptimizer)
    }

    private func resync() {
        ClipboardImageOptimizerService.shared.syncWithPreferences()
    }
}
