// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

enum FileOptimizerTests {
    typealias Support = FileOptimizerSupport

    static func run(_ suite: TestSuite) {
        kinds(suite)
        destinations(suite)
        names(suite)
        reasons(suite)
        placing(suite)
        strings(suite)
        catalog(suite)
    }

    static func kinds(_ suite: TestSuite) {
        func url(_ name: String) -> URL { URL(fileURLWithPath: "/Users/me/\(name)") }
        suite.expect(Support.kind(for: url("a.PNG")) == .image(uti: "public.png"), "PNG is an image")
        suite.expect(Support.kind(for: url("a.jpeg")) == .image(uti: "public.jpeg"), "JPEG is an image")
        suite.expect(Support.kind(for: url("a.tif")) == .image(uti: "public.tiff"), "TIFF is an image")
        suite.expect(Support.kind(for: url("a.HEIC")) == .convertedImage(uti: "public.heic"), "HEIC converts")
        suite.expect(Support.kind(for: url("a.webp")) == .convertedImage(uti: "org.webmproject.webp"),
                     "WebP converts")
        suite.expect(Support.kind(for: url("a.MOV")) == .video, "MOV is a video")
        suite.expect(Support.kind(for: url("a.m4v")) == .video, "M4V is a video")
        suite.expect(Support.kind(for: url("a.pdf")) == .pdf, "PDF is a PDF")
        for ext in ["mkv", "gif", "txt", "zip", ""] {
            suite.expect(Support.kind(for: url("a.\(ext)")) == .unsupported, "\(ext) is not taken")
        }
        let png = url("shot.png")
        suite.expect(Support.imageExtension(outputType: "public.png", source: png) == "png", "PNG stays png")
        suite.expect(Support.imageExtension(outputType: "public.jpeg", source: png) == "jpg", "PNG as JPEG is jpg")
        suite.expect(Support.imageExtension(outputType: "public.jpeg", source: url("a.JPEG")) == "JPEG",
                     "a JPEG keeps its own extension")
        suite.expect(Support.imageExtension(outputType: "public.png", source: url("a.tiff")) == "png",
                     "TIFF written as PNG is png")
    }

    static func destinations(_ suite: TestSuite) {
        let source = URL(fileURLWithPath: "/Users/me/Pictures/a.png")
        suite.expect(Support.destinationDirectory(source: source, mode: .besideOriginal, folder: "/x",
                                                  isDirectory: { _ in true })?.path == "/Users/me/Pictures",
                     "beside the original is the original's folder")
        suite.expect(Support.destinationDirectory(source: source, mode: .folder, folder: "/Out",
                                                  isDirectory: { _ in true })?.path == "/Out",
                     "folder mode writes to the chosen folder")
        suite.expect(Support.destinationDirectory(source: source, mode: .folder, folder: "",
                                                  isDirectory: { _ in true }) == nil,
                     "folder mode without a folder has no destination")
        suite.expect(Support.destinationDirectory(source: source, mode: .folder, folder: "/Gone",
                                                  isDirectory: { _ in false }) == nil,
                     "a missing folder is never replaced by another place")
        suite.expect(Support.OutputMode.sanitized(nil) == .besideOriginal, "no mode is beside the original")
        suite.expect(Support.OutputMode.sanitized("junk") == .besideOriginal, "a bad mode is beside the original")
        suite.expect(Support.OutputMode.sanitized("folder") == .folder, "folder mode round-trips")
    }

    static func names(_ suite: TestSuite) {
        suite.expect(Support.outputName(base: "Clip", ext: "mov", attempt: 0) == "Clip (optimized).mov",
                     "first name")
        suite.expect(Support.outputName(base: "Clip", ext: "mov", attempt: 1) == "Clip (optimized 2).mov",
                     "second name")
        suite.expect(Support.outputName(base: ".hidden", ext: "png", attempt: 0) == "hidden (optimized).png",
                     "a result is never hidden")
        suite.expect(Support.outputName(base: "", ext: "pdf", attempt: 0) == "Optimized (optimized).pdf",
                     "an empty base gets a name")
        let long = String(repeating: "é", count: 300)
        for attempt in [0, 998] {
            let name = Support.outputName(base: long, ext: "jpeg", attempt: attempt)
            suite.expect(name.utf8.count <= 255, "a long name fits: \(name.utf8.count)")
            suite.expect(name.hasSuffix(attempt == 0 ? " (optimized).jpeg" : " (optimized 999).jpeg"),
                         "a shortened name keeps its tag")
        }
        suite.expect(Support.isAlreadyOptimized(URL(fileURLWithPath: "/a/x (optimized).png")), "own result")
        suite.expect(Support.isAlreadyOptimized(URL(fileURLWithPath: "/a/x (optimized 12).png")), "numbered result")
        suite.expect(!Support.isAlreadyOptimized(URL(fileURLWithPath: "/a/x (optimized draft).png")),
                     "other words in parentheses are not ours")
        suite.expect(!Support.isAlreadyOptimized(URL(fileURLWithPath: "/a/optimized.png")), "a plain name")
    }

    static func reasons(_ suite: TestSuite) {
        let pairs: [(String, Support.SkipReason)] = [
            ("not smaller", .notSmaller), ("size", .tooLarge), ("duration", .tooLong),
            ("not downloaded", .notDownloaded), ("not a file", .notAFile), ("protected", .protected),
            ("image", .leftAlone), ("disk space", .diskSpace), ("unreadable", .unreadable),
            ("empty", .unreadable), ("no video", .noVideo), ("whatever", .unsupported),
        ]
        for (tag, reason) in pairs {
            suite.expect(Support.skipReason(tag: tag) == reason, "\(tag) reads as \(reason)")
        }
        suite.expect(Support.placeError(errno: EACCES) == .cannotWrite, "EACCES cannot write")
        suite.expect(Support.placeError(errno: EROFS) == .cannotWrite, "EROFS cannot write")
        suite.expect(Support.placeError(errno: ENOSPC) == .diskSpace, "ENOSPC is disk space")
        suite.expect(Support.estimatedVideoProgress(elapsed: 1000, duration: 10) == 0.95, "progress stays below done")
        suite.expect(Support.estimatedVideoProgress(elapsed: 0, duration: 10) == 0, "progress starts at zero")
        suite.expect(Support.savedBytes([(100, 40), (10, 20)]) == 60, "only real savings add up")
    }

    static func placing(_ suite: TestSuite) {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("VorssaintFileOptimizerTests-\(UUID().uuidString)")
        let work = dir.appendingPathComponent("work")
        let out = dir.appendingPathComponent("out")
        try? fm.createDirectory(at: work, withIntermediateDirectories: true)
        try? fm.createDirectory(at: out, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        func staged(_ text: String) -> URL {
            let url = work.appendingPathComponent(UUID().uuidString)
            try? Data(text.utf8).write(to: url)
            return url
        }
        let existing = out.appendingPathComponent("a (optimized).png")
        try? Data("keep".utf8).write(to: existing)
        let first = try? Support.place(staged("one"), in: out, base: "a", ext: "png")
        suite.expect(first?.lastPathComponent == "a (optimized 2).png", "a taken name moves on: \(String(describing: first))")
        suite.expect((try? String(contentsOf: existing, encoding: .utf8)) == "keep", "an existing file is never replaced")
        let second = try? Support.place(staged("two"), in: out, base: "a", ext: "png")
        suite.expect(second?.lastPathComponent == "a (optimized 3).png", "the next one takes the next name")
        let names = (try? fm.contentsOfDirectory(atPath: out.path)) ?? []
        suite.expect(!names.contains { $0.hasPrefix(Support.partialPrefix) }, "no partial file is left behind")

        let locked = dir.appendingPathComponent("locked")
        try? fm.createDirectory(at: locked, withIntermediateDirectories: true)
        chmod(locked.path, 0o555)
        defer { chmod(locked.path, 0o755) }
        let source = staged("three")
        do {
            _ = try Support.place(source, in: locked, base: "a", ext: "png")
            suite.expect(false, "a read-only folder takes nothing")
        } catch {
            suite.expect(error as? Support.PlaceError == .cannotWrite, "a read-only folder cannot be written: \(error)")
        }
        suite.expect(fm.fileExists(atPath: source.path), "a failed placement keeps the staged result for cleanup")
        suite.expect(((try? fm.contentsOfDirectory(atPath: locked.path)) ?? []).isEmpty,
                     "a failed placement writes nothing")
    }

    static func strings(_ suite: TestSuite) {
        let english = FileOptimizerStrings.localized(.enUS)
        for language in AppLanguage.allCases {
            let text = FileOptimizerStrings.localized(language)
            let mirror = Mirror(reflecting: text)
            for child in mirror.children {
                guard let value = child.value as? String else { continue }
                suite.expect(!value.trimmingCharacters(in: .whitespaces).isEmpty,
                             "\(language) \(child.label ?? "?") is filled in")
            }
            for reason in Support.SkipReason.allCases {
                suite.expect(!text.reason(reason).isEmpty, "\(language) explains \(reason)")
            }
            suite.expect(text.sizeChangeFormat.components(separatedBy: "%@").count == 3,
                         "\(language) size change keeps both placeholders")
            suite.expect(text.savedFormat.components(separatedBy: "%@").count == 2,
                         "\(language) saved total keeps its placeholder")
            if language != .enUS {
                suite.expect(text.dropPrompt != english.dropPrompt, "\(language) drop prompt is translated")
            }
        }
    }

    static func catalog(_ suite: TestSuite) {
        let feature = AppFeature.fileOptimizer
        suite.expect(feature.group == .tools, "the File optimizer is a tool")
        suite.expect(feature.enabledKeys.isEmpty, "the File optimizer runs only when asked")
        suite.expect(feature.permissions.isEmpty, "the File optimizer asks for no permission of its own")
        suite.expect(!feature.installedByDefault, "the File optimizer is opt-in")
        suite.expect(feature.settingsDestination == FeatureSettingsDestination(.fileOptimizer),
                     "the File optimizer opens its own page")
        suite.expect(FeatureVisibilitySupport.features(for: .fileOptimizer) == [.fileOptimizer],
                     "the page belongs to the File optimizer alone")
        suite.expect(!AppFeature.clipboardImageOptimizer.enabledKeys.isEmpty
                     && !feature.enabledKeys.contains(DefaultsKey.clipboardImageOptimizerEnabled),
                     "the File optimizer does not depend on the clipboard switch")
        let registered = Defaults.registeredDefaults
        suite.expect(registered[DefaultsKey.fileOptimizerOutputMode] as? String == "besideOriginal",
                     "results go beside the original by default")
        suite.expect(registered[DefaultsKey.fileOptimizerOutputFolder] as? String == "",
                     "no output folder is chosen by default")
    }
}
