// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The image, video and PDF options the File optimizer and the Clipboard
/// optimizer share. The File optimizer page shows them; the Clipboard page
/// shows the same views only while the File optimizer is not installed, so
/// the options stay reachable without two sets of controls.
enum OptimizerOptions {
    typealias Files = ClipboardOptimizerFileSupport

    static func caption(_ string: String) -> some View {
        Text(string)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    static func slider(_ label: String, value: Binding<Double>) -> some View {
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

    /// The caps count binary megabytes, so they are shown that way too.
    static func megabytes(_ value: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.allowedUnits = [.useMB]
        return formatter.string(fromByteCount: Int64(value) * 1024 * 1024)
    }
}

struct OptimizerImageOptions: View {
    /// Conversion only reaches the clipboard with copied image files on.
    var convertEnabled = true

    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.clipboardImageOptimizerFormat) private var format = "keep"
    @AppStorage(DefaultsKey.clipboardImageOptimizerQuality)
    private var quality = ClipboardImageOptimizerSupport.defaultQuality
    @AppStorage(DefaultsKey.clipboardImageOptimizerMaxDimension) private var maxDimension = 0
    @AppStorage(DefaultsKey.clipboardImageOptimizerHalveRetina) private var halveRetina = false
    @AppStorage(DefaultsKey.clipboardOptimizerConvertImages) private var convertImages = false

    private var text: ClipboardImageOptimizerStrings { FeatureStrings.clipboardImageOptimizer(l10n.language) }
    private var jpeg: String { ClipboardImageOptimizerSupport.FormatPolicy.jpeg.rawValue }

    var body: some View {
        Picker(text.formatLabel, selection: $format) {
            Text(text.formatKeep).tag(ClipboardImageOptimizerSupport.FormatPolicy.keep.rawValue)
            Text(text.formatJPEG).tag(jpeg)
        }
        if format == jpeg || convertImages {
            if format == jpeg {
                OptimizerOptions.caption(text.formatCaption)
            }
            OptimizerOptions.slider(text.quality, value: $quality)
        }
        Picker(text.maxDimension, selection: $maxDimension) {
            ForEach(ClipboardImageOptimizerSupport.maxDimensionChoices, id: \.self) { value in
                Text(value == 0 ? text.maxDimensionOff : "\(value) px").tag(value)
            }
        }
        Toggle(text.halveRetina, isOn: $halveRetina)
        OptimizerOptions.caption(text.halveRetinaCaption)
        Toggle(text.convertImages, isOn: $convertImages)
            .disabled(!convertEnabled)
            // Conversion decides which copied files qualify, so a running
            // clipboard job for one must hear it was turned off.
            .onChange(of: convertImages) { _, _ in ClipboardImageOptimizerService.shared.syncWithPreferences() }
        OptimizerOptions.caption(FeatureStrings.fileOptimizer(l10n.language).convertCaption)
    }
}

struct OptimizerVideoOptions: View {
    private typealias Files = ClipboardOptimizerFileSupport

    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.clipboardOptimizerVideoCodec) private var videoCodec = MediaVideoCodec.hevc.rawValue
    @AppStorage(DefaultsKey.clipboardOptimizerVideoQuality) private var videoQuality = Files.VideoOptions.defaultQuality
    @AppStorage(DefaultsKey.clipboardOptimizerVideoMaxDimension)
    private var videoMaxDimension = Files.VideoOptions.defaultMaxDimension
    @AppStorage(DefaultsKey.clipboardOptimizerVideoRemoveAudio) private var removeAudio = false
    @AppStorage(DefaultsKey.clipboardOptimizerVideoMaxMB) private var videoMaxMB = Files.VideoOptions.defaultMaxMB
    @AppStorage(DefaultsKey.clipboardOptimizerVideoMaxMinutes)
    private var videoMaxMinutes = Files.VideoOptions.defaultMaxMinutes

    private var text: ClipboardImageOptimizerStrings { FeatureStrings.clipboardImageOptimizer(l10n.language) }

    /// avconvert has no HEVC preset below 1080p.
    private var dimensionChoices: [Int] {
        Files.VideoOptions.maxDimensionChoices(codec: MediaVideoCodec(rawValue: videoCodec) ?? .hevc)
    }

    var body: some View {
        Picker(text.videoCodec, selection: $videoCodec) {
            Text(text.codecHEVC).tag(MediaVideoCodec.hevc.rawValue)
            Text(text.codecH264).tag(MediaVideoCodec.h264.rawValue)
        }
        .onChange(of: videoCodec) { _, _ in
            if !dimensionChoices.contains(videoMaxDimension) {
                videoMaxDimension = Files.VideoOptions.defaultMaxDimension
            }
        }
        OptimizerOptions.slider(text.videoQuality, value: $videoQuality)
        Picker(text.videoMaxDimension, selection: $videoMaxDimension) {
            ForEach(dimensionChoices, id: \.self) { value in
                Text(value == 0 ? text.videoMaxDimensionKeep : "\(value) px").tag(value)
            }
        }
        Toggle(text.removeAudio, isOn: $removeAudio)
        Picker(text.videoMaxSize, selection: $videoMaxMB) {
            ForEach(Files.VideoOptions.maxMBChoices, id: \.self) { Text(OptimizerOptions.megabytes($0)).tag($0) }
        }
        Picker(text.videoMaxDuration, selection: $videoMaxMinutes) {
            ForEach(Files.VideoOptions.maxMinutesChoices, id: \.self) { value in
                Text(String(format: text.minutesFormat, value)).tag(value)
            }
        }
    }
}

struct OptimizerPDFOptions: View {
    private typealias Files = ClipboardOptimizerFileSupport

    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.clipboardOptimizerPDFDPI) private var pdfDPI = Files.PDFOptions.defaultDPI
    @AppStorage(DefaultsKey.clipboardOptimizerPDFQuality) private var pdfQuality = Files.PDFOptions.defaultQuality
    @AppStorage(DefaultsKey.clipboardOptimizerPDFMaxMB) private var pdfMaxMB = Files.PDFOptions.defaultMaxMB

    private var text: ClipboardImageOptimizerStrings { FeatureStrings.clipboardImageOptimizer(l10n.language) }

    var body: some View {
        Picker(text.pdfDPI, selection: $pdfDPI) {
            ForEach(Files.PDFOptions.dpiChoices, id: \.self) { value in
                Text(String(format: text.dpiFormat, value)).tag(value)
            }
        }
        OptimizerOptions.slider(text.pdfQuality, value: $pdfQuality)
        Picker(text.pdfMaxSize, selection: $pdfMaxMB) {
            ForEach(Files.PDFOptions.maxMBChoices, id: \.self) { Text(OptimizerOptions.megabytes($0)).tag($0) }
        }
    }
}
