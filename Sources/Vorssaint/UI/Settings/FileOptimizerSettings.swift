// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The File optimizer page: drop or pick files, watch the queue, choose where
/// results go, and set the options it shares with the Clipboard optimizer.
struct FileOptimizerSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = FileOptimizerService.shared
    @AppStorage(DefaultsKey.fileOptimizerOutputMode) private var outputMode = FileOptimizerSupport.OutputMode
        .besideOriginal.rawValue
    @AppStorage(DefaultsKey.fileOptimizerOutputFolder) private var outputFolder = ""
    @State private var isTargeted = false

    private var text: FileOptimizerStrings { FeatureStrings.fileOptimizer(l10n.language) }

    var body: some View {
        Form {
            Section {
                OptimizerOptions.caption(text.pageCaption)
                dropZone
            } header: {
                Text(text.title)
            }
            if !service.items.isEmpty {
                Section {
                    ForEach(service.items) { item in
                        row(item)
                    }
                    HStack {
                        if service.savedBytes > 0 {
                            OptimizerOptions.caption(String(format: text.savedFormat, bytes(service.savedBytes)))
                        }
                        Spacer()
                        Button(text.cancelAll) { service.cancelAll() }
                            .disabled(!service.isBusy)
                        Button(text.clearFinished) { service.clearFinished() }
                            .disabled(!service.items.contains { $0.state.isFinished })
                    }
                } header: {
                    Text(text.queueHeader)
                }
            }
            Section {
                Picker(text.outputMode, selection: $outputMode) {
                    Text(text.outputBeside).tag(FileOptimizerSupport.OutputMode.besideOriginal.rawValue)
                    Text(text.outputFolder).tag(FileOptimizerSupport.OutputMode.folder.rawValue)
                }
                if outputMode == FileOptimizerSupport.OutputMode.folder.rawValue {
                    LabeledContent(outputFolder.isEmpty ? text.noFolder
                                   : FileManager.default.displayName(atPath: outputFolder)) {
                        Button(text.chooseFolder, action: chooseFolder)
                    }
                    .help(outputFolder)
                }
                OptimizerOptions.caption(text.outputCaption)
            } header: {
                Text(text.outputHeader)
            }
            Section {
                OptimizerImageOptions()
            } header: {
                Text(text.imagesHeader)
            } footer: {
                OptimizerOptions.caption(text.optionsShared)
            }
            Section {
                OptimizerVideoOptions()
            } header: {
                Text(text.videosHeader)
            }
            Section {
                OptimizerPDFOptions()
            } header: {
                Text(text.pdfsHeader)
            }
        }
        .formStyle(.grouped)
    }

    private var dropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.secondary)
            Text(text.dropPrompt)
                .foregroundStyle(.secondary)
            Button(text.chooseFiles, action: chooseFiles)
        }
        .frame(maxWidth: .infinity, minHeight: 110)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
        )
        .contentShape(Rectangle())
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            service.add(files)
            return true
        } isTargeted: { isTargeted = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(text.dropPrompt)
    }

    @ViewBuilder private func row(_ item: FileOptimizerService.Item) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.source.path))
                .resizable()
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.source.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                status(item.state)
            }
            Spacer(minLength: 8)
            switch item.state {
            case .queued, .running:
                Button {
                    service.cancel(item.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .help(text.cancel)
                .accessibilityLabel(text.cancel)
            case .done(let output, _, _):
                Button(text.reveal) { service.reveal(output) }
            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder private func status(_ state: FileOptimizerService.State) -> some View {
        switch state {
        case .queued:
            OptimizerOptions.caption(text.queued)
        case .running(let progress):
            if let progress {
                ProgressView(value: progress)
                    .controlSize(.small)
            } else {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    OptimizerOptions.caption(text.working)
                }
            }
        case .done(_, let before, let after):
            Text(String(format: text.sizeChangeFormat, bytes(before), bytes(after)))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        case .skipped(let reason):
            OptimizerOptions.caption(text.reason(reason))
        case .failed(let message):
            Text(String(format: text.failedFormat, message))
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
        case .cancelled:
            OptimizerOptions.caption(text.cancelled)
        }
    }

    private func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic, .heif, .webP, .bmp, .quickTimeMovie, .mpeg4Movie,
                                     .appleProtectedMPEG4Video, .pdf]
            + [UTType("public.avif"), UTType("com.apple.m4v-video")].compactMap { $0 }
        panel.prompt = text.chooseFiles.replacingOccurrences(of: "…", with: "")
        guard panel.runModal() == .OK else { return }
        service.add(panel.urls)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if !outputFolder.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: outputFolder, isDirectory: true)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputFolder = url.path
    }
}
