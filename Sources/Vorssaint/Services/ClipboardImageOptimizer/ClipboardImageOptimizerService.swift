// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

/// Re-encodes a lone copied image into a smaller one of the same kind. Polls
/// like the URL cleaner: change count, item count and type names only, and the
/// image itself is read only once those say it qualifies. Whatever is already
/// on the pasteboard when it starts is never touched.
final class ClipboardImageOptimizerService: ObservableObject {
    static let shared = ClipboardImageOptimizerService()

    @Published private(set) var isRunning = false

    private final class PollToken {
        private let lock = NSLock()
        private var cancelled = false

        func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }
    }

    private static let pollTimeout: TimeInterval = 2
    private static let readTimeout: TimeInterval = 4

    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var lastChangeCount = 0
    /// No poll acts until the starting change count is known; otherwise a
    /// timed-out baseline would let the image already copied be rewritten.
    private var hasBaseline = false
    private var lastOwnWrite: Int?
    private var pollInFlight = false
    private var pollToken: PollToken?
    private var encodeInFlight = false

    /// Read from the pasteboard lane and the encode queue, so it sits behind
    /// a lock: a result is written only if nothing turned the feature off or
    /// reconfigured it since the work started.
    private let stateLock = NSLock()
    private var generation = 0
    private var enabled = false

    private let encodeQueue = DispatchQueue(label: "Vorssaint.ClipboardImageOptimizer.encode", qos: .utility)

    private init() {}

    func syncWithPreferences() {
        if AppFeature.clipboardImageOptimizer.isAvailable,
           UserDefaults.standard.bool(forKey: DefaultsKey.clipboardImageOptimizerEnabled) {
            start()
        } else {
            stop()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        cancelPoll()
        updateState(enabled: false)
        encodeInFlight = false
        isRunning = false
    }

    /// Options are read for each new image, so a settings change while
    /// running needs nothing here and never drops the image in flight.
    private func start() {
        guard timer == nil else {
            isRunning = true
            return
        }
        updateState(enabled: true)
        encodeInFlight = false
        hasBaseline = false
        let timer = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.hasBaseline = false
                self?.baseline()
            }
        isRunning = true
        baseline()
    }

    private func updateState(enabled: Bool) {
        stateLock.lock()
        generation &+= 1
        self.enabled = enabled
        stateLock.unlock()
    }

    private func currentState() -> (generation: Int, enabled: Bool) {
        stateLock.lock()
        defer { stateLock.unlock() }
        return (generation, enabled)
    }

    /// Whatever sits on the pasteboard now is the user's, never ours to shrink.
    private func baseline() {
        cancelPoll()
        let token = PollToken()
        pollToken = token
        pollInFlight = true
        GeneralPasteboardAccess.shared.async(timeout: Self.pollTimeout, { _ in
            token.isCancelled ? nil : NSPasteboard.general.changeCount
        }, then: { [weak self] changeCount in
            guard let self, self.pollToken === token else { return }
            self.pollToken = nil
            self.pollInFlight = false
            if let changeCount {
                self.lastChangeCount = changeCount
                self.hasBaseline = true
            }
        })
    }

    private func tick() {
        guard isRunning, !pollInFlight, !encodeInFlight, !TransientPaste.shared.isBusy else { return }
        guard hasBaseline else {
            baseline()
            return
        }
        let token = PollToken()
        pollToken = token
        pollInFlight = true
        let since = lastChangeCount
        let includeFiles = UserDefaults.standard.bool(forKey: DefaultsKey.clipboardImageOptimizerIncludeFiles)
        GeneralPasteboardAccess.shared.async(timeout: Self.pollTimeout, { _ in
            token.isCancelled ? nil : Self.readSnapshot(since: since, includeFiles: includeFiles)
        }, then: { [weak self] snapshot in
            guard let self, self.pollToken === token else { return }
            self.pollToken = nil
            self.pollInFlight = false
            guard self.isRunning, let snapshot, snapshot.changeCount != self.lastChangeCount else { return }
            self.lastChangeCount = snapshot.changeCount
            self.consider(snapshot)
        })
    }

    /// Runs on the pasteboard lane. Reads counts and type names; file URLs
    /// only when files are on and the pasteboard says it carries one.
    private static func readSnapshot(since: Int, includeFiles: Bool) -> PasteboardImageSnapshot? {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != since else {
            return PasteboardImageSnapshot(changeCount: changeCount, itemCount: 0, types: [],
                                           fileURLs: [])
        }
        let types = (pasteboard.types ?? []).map(\.rawValue)
        var fileURLs: [URL] = []
        if includeFiles, types.contains(ClipboardImageOptimizerSupport.fileURLType),
           !types.contains(where: ClipboardImageOptimizerSupport.untouchableTypes.contains) {
            fileURLs = pasteboard.readObjects(forClasses: [NSURL.self],
                                              options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        }
        return PasteboardImageSnapshot(changeCount: changeCount,
                                       itemCount: pasteboard.pasteboardItems?.count ?? 0,
                                       types: types, fileURLs: fileURLs)
    }

    private func consider(_ snapshot: PasteboardImageSnapshot) {
        let options = ClipboardImageOptimizerSupport.Options.fromDefaults()
        guard case .eligible(let source) = ClipboardImageOptimizerSupport.eligibility(
            snapshot, lastOwnWrite: lastOwnWrite, includeFiles: options.includeFiles) else { return }
        let state = currentState()
        encodeInFlight = true
        switch source {
        case .bitmap(let type):
            GeneralPasteboardAccess.shared.async(timeout: Self.readTimeout, { isExpired -> Data? in
                let pasteboard = NSPasteboard.general
                guard pasteboard.changeCount == snapshot.changeCount, !isExpired() else { return nil }
                return pasteboard.data(forType: NSPasteboard.PasteboardType(type))
            }, then: { [weak self] data in
                guard let self else { return }
                guard let data else {
                    self.finishEncode(generation: state.generation)
                    return
                }
                let sourceType = ClipboardImageOptimizerSupport.pngTypes.contains(type) ? "public.png" : "public.tiff"
                self.encode(data: { data }, sourceType: sourceType, snapshot: snapshot,
                            options: options, generation: state.generation)
            })
        case .file(let url, let uti):
            encode(data: {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                guard size > 0, size <= ClipboardImageOptimizerSupport.maxBytes else { return nil }
                return try? Data(contentsOf: url)
            }, sourceType: uti, snapshot: snapshot, options: options, generation: state.generation)
        }
    }

    private func encode(data load: @escaping () -> Data?,
                        sourceType: String,
                        snapshot: PasteboardImageSnapshot,
                        options: ClipboardImageOptimizerSupport.Options,
                        generation: Int) {
        encodeQueue.async { [weak self] in
            guard let self else { return }
            let isCancelled = { self.currentState().generation != generation }
            let original = isCancelled() ? nil : autoreleasepool { load() }
            let output = original.flatMap {
                ClipboardImageOptimizerEncoding.optimize(data: $0, sourceType: sourceType,
                                                         options: options, isCancelled: isCancelled)
            }
            DispatchQueue.main.async {
                guard original != nil, let output, !isCancelled() else {
                    self.finishEncode(generation: generation)
                    return
                }
                self.commit(output, snapshot: snapshot, generation: generation)
            }
        }
    }

    private func commit(_ output: ClipboardImageOptimizerEncoding.Output,
                        snapshot: PasteboardImageSnapshot,
                        generation: Int) {
        let state = currentState()
        guard state.enabled, state.generation == generation else {
            finishEncode(generation: generation)
            return
        }
        GeneralPasteboardAccess.shared.async({ [weak self] () -> Int? in
            guard let self else { return nil }
            let pasteboard = NSPasteboard.general
            let state = self.currentState()
            guard OptimizationCommit.accepts(generation: generation, current: state.generation,
                                             enabled: state.enabled,
                                             pasteboardChangeCount: pasteboard.changeCount,
                                             snapshotChangeCount: snapshot.changeCount) else { return nil }
            pasteboard.clearContents()
            let item = NSPasteboardItem()
            item.setData(output.data, forType: NSPasteboard.PasteboardType(output.type))
            pasteboard.writeObjects([item])
            return pasteboard.changeCount
        }, then: { [weak self] newChangeCount in
            guard let self else { return }
            self.finishEncode(generation: generation)
            guard let newChangeCount else { return }
            self.lastOwnWrite = newChangeCount
            self.lastChangeCount = max(self.lastChangeCount, newChangeCount)
            // History records the smaller copy as an ordinary change; only
            // auto clear keeps timing from the original copy.
            ClipboardAutoClearService.shared.noteOwnRewrite(from: snapshot.changeCount, to: newChangeCount)
        })
    }

    /// A completion from before a stop/start must not clear the flag of the
    /// encode that the newer generation has in flight.
    private func finishEncode(generation: Int) {
        if currentState().generation == generation { encodeInFlight = false }
    }

    private func cancelPoll() {
        pollToken?.cancel()
        pollToken = nil
        pollInFlight = false
    }
}
