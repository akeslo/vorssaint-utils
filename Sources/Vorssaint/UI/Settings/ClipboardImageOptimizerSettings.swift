// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The clipboard optimizer's section of the clipboard page: one switch per
/// kind. Their options are shared with the File optimizer and live on its
/// page; only while that page is not installed are they shown here.
struct ClipboardImageOptimizerSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @AppStorage(DefaultsKey.clipboardImageOptimizerEnabled) private var enabled = false
    @AppStorage(DefaultsKey.clipboardOptimizerImages) private var images = true
    @AppStorage(DefaultsKey.clipboardImageOptimizerIncludeFiles) private var includeFiles = false
    @AppStorage(DefaultsKey.clipboardOptimizerVideos) private var videos = false
    @AppStorage(DefaultsKey.clipboardOptimizerPDFs) private var pdfs = false
    @State private var storedBytes: (total: Int64, kept: Int64) = (0, 0)

    private var text: ClipboardImageOptimizerStrings {
        FeatureStrings.clipboardImageOptimizer(l10n.language)
    }

    private var fileText: FileOptimizerStrings {
        FeatureStrings.fileOptimizer(l10n.language)
    }

    /// The same predicate that lists the File optimizer page, so the link
    /// never points at a page that is not there.
    private var optionsOnFilePage: Bool {
        FeatureVisibilitySupport.isPageVisible(.fileOptimizer) { $0.isAvailable }
    }

    var body: some View {
        // One switch per kind. The feature switch the hub and backup use is
        // on exactly when some kind is, so there is no separate master row.
        Section {
            imageControls
        } header: {
            Text(text.title)
        }
        .settingsFormSectionAnchor(.clipboardImageOptimizer)
        .onAppear(perform: refreshStorage)
        Section { videoControls }
        Section { pdfControls }
        if optionsOnFilePage {
            Section {
                OptimizerOptions.caption(fileText.clipboardLink)
                Button(fileText.openPage) {
                    SettingsRouter.shared.request(AppFeature.fileOptimizer.settingsDestination)
                }
            }
        }
        if enabled {
            Section { storageControls }
        }
    }

    /// A kind reads as on only while the feature is on, so turning the
    /// feature off in the hub never leaves a kind showing on here.
    private func kind(_ value: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { enabled && value.wrappedValue },
            set: { isOn in
                value.wrappedValue = isOn
                if isOn {
                    // Turning the feature back on from here must not revive
                    // kinds the hub left on underneath.
                    if !enabled {
                        images = false
                        videos = false
                        pdfs = false
                        value.wrappedValue = true
                    }
                    enabled = true
                } else {
                    enabled = images || videos || pdfs
                }
                resync()
            }
        )
    }

    @ViewBuilder private var imageControls: some View {
        Toggle(text.imagesToggle, isOn: kind($images))
        OptimizerOptions.caption(text.caption)
        if enabled && images {
            Toggle(text.includeFiles, isOn: $includeFiles)
                .onChange(of: includeFiles) { _, _ in resync() }
            OptimizerOptions.caption(text.includeFilesCaption)
            if !optionsOnFilePage {
                OptimizerImageOptions(convertEnabled: includeFiles)
            }
        }
    }

    @ViewBuilder private var videoControls: some View {
        Toggle(text.videos, isOn: kind($videos))
        OptimizerOptions.caption(text.videosCaption)
        if enabled && videos && !optionsOnFilePage {
            OptimizerVideoOptions()
        }
    }

    @ViewBuilder private var pdfControls: some View {
        Toggle(text.pdfs, isOn: kind($pdfs))
        OptimizerOptions.caption(text.pdfsCaption)
        if enabled && pdfs && !optionsOnFilePage {
            OptimizerPDFOptions()
        }
    }

    @ViewBuilder private var storageControls: some View {
        OptimizerOptions.caption(text.storageCaption)
        Button(String(format: text.clearCopies, bytes(storedBytes.total))) {
            ClipboardImageOptimizerService.shared.clearOptimizedCopies(completion: refreshStorage)
        }
        .disabled(storedBytes.total <= storedBytes.kept)
        if storedBytes.kept > 0 {
            OptimizerOptions.caption(String(format: text.keptBytes, bytes(storedBytes.kept)))
        }
    }

    private func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private func refreshStorage() {
        ClipboardImageOptimizerService.shared.storedBytes { total, kept in
            storedBytes = (total, kept)
        }
    }

    /// Options are read for each new copy, so only switches need a resync:
    /// it cancels a file job whose kind was just turned off.
    private func resync() {
        ClipboardImageOptimizerService.shared.syncWithPreferences()
    }
}
