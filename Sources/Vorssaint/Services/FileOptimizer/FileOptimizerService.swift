// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

/// Optimizes files the user picks or drops, one at a time, with the
/// clipboard optimizer's engines and options. Originals are only read; each
/// result is written beside the original (or into a chosen folder) under a
/// new name that never replaces an existing file. Work files live in a
/// private folder of their own, apart from the clipboard optimizer's, so
/// neither feature's cleanup touches the other's jobs.
final class FileOptimizerService: ObservableObject {
    static let shared = FileOptimizerService()

    typealias Support = FileOptimizerSupport

    enum State: Equatable {
        case queued
        case running(progress: Double?)
        case done(output: URL, before: Int64, after: Int64)
        case skipped(Support.SkipReason)
        case failed(String)
        case cancelled

        var isFinished: Bool {
            switch self {
            case .queued, .running: return false
            default: return true
            }
        }
    }

    struct Item: Identifiable, Equatable {
        let id = UUID()
        let source: URL
        let kind: Support.Kind
        var state: State
    }

    /// One running item. Cancelling stops its avconvert; `immediately` is
    /// for quitting, when there is no time to wait for it to exit.
    private final class Token {
        private let lock = NSLock()
        private var cancelled = false
        private var process: Process?

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }

        func cancel(immediately: Bool = false) {
            lock.lock()
            cancelled = true
            let process = self.process
            lock.unlock()
            if immediately, let process, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }

        func attach(_ process: Process) {
            lock.lock()
            self.process = process
            let cancelled = self.cancelled
            lock.unlock()
            if cancelled { process.terminate() }
        }
    }

    @Published private(set) var items: [Item] = []

    private let queue = DispatchQueue(label: "Vorssaint.FileOptimizer", qos: .utility)
    private var runningID: UUID?
    private var token: Token?
    private var preparedStore = false
    private var lastProgress = Date.distantPast

    static var rootURL: URL? {
        PrivateFileStore.containerURL?.appendingPathComponent("FileOptimizer", isDirectory: true)
    }

    /// Lists a cross-volume copy in progress, so a crash mid-copy can be
    /// cleaned up next time. Lives in the root, outside any job folder.
    private static var placingURL: URL? { rootURL?.appendingPathComponent(".placing") }

    private init() {}

    var isBusy: Bool { items.contains { !$0.state.isFinished } }

    var savedBytes: Int64 {
        Support.savedBytes(items.compactMap {
            if case .done(_, let before, let after) = $0.state { return (before, after) }
            return nil
        })
    }

    // MARK: Queue

    /// Folders are not searched: only files the user picked are touched.
    func add(_ urls: [URL]) {
        guard AppFeature.fileOptimizer.isAvailable else { return }
        prepareStore()
        let known = Set(items.filter { !$0.state.isFinished }.map { $0.source.standardizedFileURL.path })
        var seen = known
        for url in urls where url.isFileURL {
            let path = url.standardizedFileURL.path
            guard seen.insert(path).inserted else { continue }
            let kind = Support.kind(for: url)
            var item = Item(source: url, kind: kind, state: .queued)
            if Support.isAlreadyOptimized(url) {
                item.state = .skipped(.alreadyOptimized)
            } else if kind == .unsupported {
                item.state = .skipped(Support.defaultIsDirectory(url.path) ? .notAFile : .unsupported)
            }
            items.append(item)
        }
        pump()
    }

    func cancel(_ id: UUID) {
        if id == runningID {
            token?.cancel()
        } else if let index = items.firstIndex(where: { $0.id == id }), items[index].state == .queued {
            items[index].state = .cancelled
        }
    }

    func cancelAll() {
        token?.cancel()
        for index in items.indices where items[index].state == .queued {
            items[index].state = .cancelled
        }
    }

    func clearFinished() {
        items.removeAll { $0.state.isFinished }
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Quitting or uninstalling: stop the encoder now and drop the work.
    func stop() {
        token?.cancel(immediately: true)
        for index in items.indices where !items[index].state.isFinished {
            items[index].state = .cancelled
        }
        if let root = Self.rootURL {
            Self.removeLeftovers(root: root)
        }
    }

    /// Runs at launch too, so an encoder or partial copy left by a crash is
    /// cleaned up even if no file is ever dropped again.
    func syncWithAvailability() {
        if AppFeature.fileOptimizer.isAvailable {
            prepareStore()
        } else {
            stop()
        }
    }

    // MARK: Running

    /// Kills an avconvert left by a crash and removes every leftover work
    /// folder, before the first job of this launch. Runs on the job queue,
    /// so no job can start ahead of it.
    private func prepareStore() {
        guard !preparedStore, let root = Self.rootURL else { return }
        preparedStore = true
        queue.async { Self.removeLeftovers(root: root) }
    }

    private static func removeLeftovers(root: URL) {
        ClipboardOptimizerStore.killOrphanedEncoders(in: root)
        if let placing = placingURL, let path = try? String(contentsOf: placing, encoding: .utf8) {
            let url = URL(fileURLWithPath: path.trimmingCharacters(in: .whitespacesAndNewlines))
            if url.lastPathComponent.hasPrefix(Support.partialPrefix) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        let children = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil,
                                                                      options: [])) ?? []
        for child in children { try? FileManager.default.removeItem(at: child) }
    }

    private func pump() {
        guard runningID == nil, let index = items.firstIndex(where: { $0.state == .queued }) else { return }
        guard AppFeature.fileOptimizer.isAvailable else {
            cancelAll()
            return
        }
        let item = items[index]
        items[index].state = .running(progress: item.kind == .video ? 0 : nil)
        runningID = item.id
        let token = Token()
        self.token = token
        let defaults = UserDefaults.standard
        let imageOptions = ClipboardImageOptimizerSupport.Options.fromDefaults(defaults)
        let convert = defaults.bool(forKey: DefaultsKey.clipboardOptimizerConvertImages)
        let video = ClipboardOptimizerFileSupport.VideoOptions.fromDefaults(defaults)
        let pdf = ClipboardOptimizerFileSupport.PDFOptions.fromDefaults(defaults)
        let destination = Support.destinationDirectory(
            source: item.source,
            mode: Support.OutputMode.sanitized(defaults.string(forKey: DefaultsKey.fileOptimizerOutputMode)),
            folder: defaults.string(forKey: DefaultsKey.fileOptimizerOutputFolder))
        let id = item.id
        queue.async { [weak self] in
            let state = Self.process(item, destination: destination, token: token,
                                     imageOptions: imageOptions, convert: convert, video: video, pdf: pdf,
                                     progress: { value in
                                         DispatchQueue.main.async { self?.report(value, for: id) }
                                     })
            DispatchQueue.main.async { self?.finish(id, state: state) }
        }
    }

    private func report(_ progress: Double, for id: UUID) {
        guard Date().timeIntervalSince(lastProgress) >= 0.5,
              let index = items.firstIndex(where: { $0.id == id }),
              case .running = items[index].state else { return }
        lastProgress = Date()
        items[index].state = .running(progress: progress)
    }

    private func finish(_ id: UUID, state: State) {
        if runningID == id {
            runningID = nil
            token = nil
        }
        if let index = items.firstIndex(where: { $0.id == id }), !items[index].state.isFinished {
            items[index].state = state
        }
        pump()
    }

    /// One file, start to finish, on the job queue.
    private static func process(_ item: Item, destination: URL?, token: Token,
                                imageOptions: ClipboardImageOptimizerSupport.Options, convert: Bool,
                                video: ClipboardOptimizerFileSupport.VideoOptions,
                                pdf: ClipboardOptimizerFileSupport.PDFOptions,
                                progress: @escaping (Double) -> Void) -> State {
        guard let destination else { return .skipped(.folderUnavailable) }
        guard let root = rootURL else { return .failed("storage") }
        let job = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        guard PrivateFileStore.createDirectory(at: job) else { return .failed("storage") }
        defer { try? FileManager.default.removeItem(at: job) }
        let isCancelled = { token.isCancelled }
        let source = item.source
        do {
            let result: ClipboardFileOptimizer.Result
            switch item.kind {
            case .image(let uti):
                result = try ClipboardFileOptimizer.optimizeImageFile(source, sourceType: uti, options: imageOptions,
                                                                      job: job, isCancelled: isCancelled)
            case .convertedImage:
                guard convert else { return .skipped(.conversionOff) }
                result = try ClipboardFileOptimizer.convertImage(source, options: imageOptions, job: job,
                                                                 isCancelled: isCancelled)
            case .video:
                result = try ClipboardFileOptimizer.optimizeVideo(
                    source, options: video, job: job, isCancelled: isCancelled,
                    launched: { token.attach($0) }, progress: progress)
            case .pdf:
                result = try ClipboardFileOptimizer.optimizePDF(source, options: pdf, job: job,
                                                                isCancelled: isCancelled)
            case .unsupported:
                return .skipped(.unsupported)
            }
            // The clipboard keeps any conversion; here every result has to
            // earn its place.
            guard ClipboardFileOptimizer.worthKeeping(original: result.originalBytes, output: result.outputBytes)
            else { return .skipped(.notSmaller) }
            guard !token.isCancelled else { return .cancelled }
            let placed = try Support.place(
                result.url, in: destination,
                base: source.deletingPathExtension().lastPathComponent,
                ext: result.url.pathExtension,
                noteCopy: { partial in
                    guard let placing = placingURL else { return }
                    if let partial {
                        _ = PrivateFileStore.write(Data(partial.path.utf8), to: placing)
                    } else {
                        try? FileManager.default.removeItem(at: placing)
                    }
                })
            return .done(output: placed, before: result.originalBytes, after: result.outputBytes)
        } catch ClipboardFileOptimizer.Failure.cancelled {
            return .cancelled
        } catch ClipboardFileOptimizer.Failure.skipped(let tag) {
            return token.isCancelled ? .cancelled : .skipped(Support.skipReason(tag: tag))
        } catch ClipboardFileOptimizer.Failure.failed(let message) {
            return token.isCancelled ? .cancelled : .failed(message)
        } catch let error as Support.PlaceError {
            switch error {
            case .cannotWrite: return .skipped(.cannotWrite)
            case .diskSpace: return .skipped(.diskSpace)
            case .exhausted: return .failed("name")
            case .failed(let code): return .failed(String(cString: strerror(code)))
            }
        } catch {
            return token.isCancelled ? .cancelled : .failed(error.localizedDescription)
        }
    }
}
