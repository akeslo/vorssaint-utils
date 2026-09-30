// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The clipboard optimizer's section of the clipboard page: images, videos
/// and PDFs, each with its own switch and options.
struct ClipboardImageOptimizerSettings: View {
    private typealias Files = ClipboardOptimizerFileSupport

    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.clipboardImageOptimizerEnabled) private var enabled = false
    @AppStorage(DefaultsKey.clipboardOptimizerImages) private var images = true
    @AppStorage(DefaultsKey.clipboardImageOptimizerFormat) private var format = "keep"
    @AppStorage(DefaultsKey.clipboardImageOptimizerQuality)
    private var quality = ClipboardImageOptimizerSupport.defaultQuality
    @AppStorage(DefaultsKey.clipboardImageOptimizerMaxDimension) private var maxDimension = 0
    @AppStorage(DefaultsKey.clipboardImageOptimizerHalveRetina) private var halveRetina = false
    @AppStorage(DefaultsKey.clipboardImageOptimizerIncludeFiles) private var includeFiles = false
    @AppStorage(DefaultsKey.clipboardOptimizerConvertImages) private var convertImages = false
    @AppStorage(DefaultsKey.clipboardOptimizerVideos) private var videos = false
    @AppStorage(DefaultsKey.clipboardOptimizerVideoCodec) private var videoCodec = MediaVideoCodec.hevc.rawValue
    @AppStorage(DefaultsKey.clipboardOptimizerVideoQuality) private var videoQuality = Files.VideoOptions.defaultQuality
    @AppStorage(DefaultsKey.clipboardOptimizerVideoMaxDimension)
    private var videoMaxDimension = Files.VideoOptions.defaultMaxDimension
    @AppStorage(DefaultsKey.clipboardOptimizerVideoRemoveAudio) private var removeAudio = false
    @AppStorage(DefaultsKey.clipboardOptimizerVideoMaxMB) private var videoMaxMB = Files.VideoOptions.defaultMaxMB
    @AppStorage(DefaultsKey.clipboardOptimizerVideoMaxMinutes)
    private var videoMaxMinutes = Files.VideoOptions.defaultMaxMinutes
    @AppStorage(DefaultsKey.clipboardOptimizerPDFs) private var pdfs = false
    @AppStorage(DefaultsKey.clipboardOptimizerPDFDPI) private var pdfDPI = Files.PDFOptions.defaultDPI
    @AppStorage(DefaultsKey.clipboardOptimizerPDFQuality) private var pdfQuality = Files.PDFOptions.defaultQuality
    @AppStorage(DefaultsKey.clipboardOptimizerPDFMaxMB) private var pdfMaxMB = Files.PDFOptions.defaultMaxMB
    @State private var storedBytes: (total: Int64, kept: Int64) = (0, 0)

    private var text: ClipboardImageOptimizerStrings {
        FeatureStrings.clipboardImageOptimizer(l10n.language)
    }

    var body: some View {
        Section {
            Toggle(text.enable, isOn: $enabled)
                .onChange(of: enabled) { _, _ in resync() }
            if enabled {
                imageControls
                videoControls
                pdfControls
                storageControls
            }
        } header: {
            Text(text.title)
        }
        .settingsFormSectionAnchor(.clipboardImageOptimizer)
        .onAppear(perform: refreshStorage)
    }

    @ViewBuilder private var imageControls: some View {
        Toggle(text.imagesToggle, isOn: $images)
            .onChange(of: images) { _, _ in resync() }
        caption(text.caption)
        if images {
            Picker(text.formatLabel, selection: $format) {
                Text(text.formatKeep).tag(ClipboardImageOptimizerSupport.FormatPolicy.keep.rawValue)
                Text(text.formatJPEG).tag(ClipboardImageOptimizerSupport.FormatPolicy.jpeg.rawValue)
            }
            .onChange(of: format) { _, _ in resync() }
            if format == ClipboardImageOptimizerSupport.FormatPolicy.jpeg.rawValue || convertImages {
                if format == ClipboardImageOptimizerSupport.FormatPolicy.jpeg.rawValue {
                    caption(text.formatCaption)
                }
                slider(text.quality, value: $quality)
            }
            Picker(text.maxDimension, selection: $maxDimension) {
                ForEach(ClipboardImageOptimizerSupport.maxDimensionChoices, id: \.self) { value in
                    Text(value == 0 ? text.maxDimensionOff : "\(value) px").tag(value)
                }
            }
            .onChange(of: maxDimension) { _, _ in resync() }
            Toggle(text.halveRetina, isOn: $halveRetina)
                .onChange(of: halveRetina) { _, _ in resync() }
            caption(text.halveRetinaCaption)
            Toggle(text.includeFiles, isOn: $includeFiles)
                .onChange(of: includeFiles) { _, _ in resync() }
            caption(text.includeFilesCaption)
            Toggle(text.convertImages, isOn: $convertImages)
                .disabled(!includeFiles)
                .onChange(of: convertImages) { _, _ in resync() }
            caption(text.convertImagesCaption)
        }
    }

    @ViewBuilder private var videoControls: some View {
        Toggle(text.videos, isOn: $videos)
            .onChange(of: videos) { _, _ in resync() }
        caption(text.videosCaption)
        if videos {
            Picker(text.videoCodec, selection: $videoCodec) {
                Text(text.codecHEVC).tag(MediaVideoCodec.hevc.rawValue)
                Text(text.codecH264).tag(MediaVideoCodec.h264.rawValue)
            }
            slider(text.videoQuality, value: $videoQuality)
            Picker(text.videoMaxDimension, selection: $videoMaxDimension) {
                ForEach(Files.VideoOptions.maxDimensionChoices, id: \.self) { value in
                    Text(value == 0 ? text.videoMaxDimensionKeep : "\(value) px").tag(value)
                }
            }
            Toggle(text.removeAudio, isOn: $removeAudio)
            Picker(text.videoMaxSize, selection: $videoMaxMB) {
                ForEach(Files.VideoOptions.maxMBChoices, id: \.self) { Text(megabytes($0)).tag($0) }
            }
            Picker(text.videoMaxDuration, selection: $videoMaxMinutes) {
                ForEach(Files.VideoOptions.maxMinutesChoices, id: \.self) { value in
                    Text(String(format: text.minutesFormat, value)).tag(value)
                }
            }
        }
    }

    @ViewBuilder private var pdfControls: some View {
        Toggle(text.pdfs, isOn: $pdfs)
            .onChange(of: pdfs) { _, _ in resync() }
        caption(text.pdfsCaption)
        if pdfs {
            Picker(text.pdfDPI, selection: $pdfDPI) {
                ForEach(Files.PDFOptions.dpiChoices, id: \.self) { value in
                    Text(String(format: text.dpiFormat, value)).tag(value)
                }
            }
            slider(text.pdfQuality, value: $pdfQuality)
            Picker(text.pdfMaxSize, selection: $pdfMaxMB) {
                ForEach(Files.PDFOptions.maxMBChoices, id: \.self) { Text(megabytes($0)).tag($0) }
            }
        }
    }

    @ViewBuilder private var storageControls: some View {
        caption(text.storageCaption)
        Button(String(format: text.clearCopies, bytes(storedBytes.total))) {
            ClipboardImageOptimizerService.shared.clearOptimizedCopies(completion: refreshStorage)
        }
        .disabled(storedBytes.total <= storedBytes.kept)
        if storedBytes.kept > 0 {
            caption(String(format: text.keptBytes, bytes(storedBytes.kept)))
        }
    }

    private func slider(_ label: String, value: Binding<Double>) -> some View {
        LabeledContent(label) {
            HStack {
                Slider(value: value, in: 0.1...1, step: 0.05)
                    .accessibilityLabel(label)
                Text("\(Int((value.wrappedValue * 100).rounded()))%")
                    .monospacedDigit()
                    .frame(minWidth: 40, alignment: .trailing)
            }
        }
    }

    private func caption(_ string: String) -> some View {
        Text(string)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// The caps count binary megabytes, so they are shown that way too.
    private func megabytes(_ value: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.allowedUnits = [.useMB]
        return formatter.string(fromByteCount: Int64(value) * 1024 * 1024)
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
