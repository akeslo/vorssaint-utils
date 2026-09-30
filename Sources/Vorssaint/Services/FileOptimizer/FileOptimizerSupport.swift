// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// The rules of the File optimizer that need no AppKit: which files it takes,
/// where a result goes, what it is called, and how it is put there without
/// ever replacing an existing file. The encoding itself is the clipboard
/// optimizer's, so both entry points shrink a file the same way.
enum FileOptimizerSupport {
    typealias Files = ClipboardOptimizerFileSupport

    // MARK: Kinds

    enum Kind: Equatable {
        /// PNG, JPEG or TIFF, re-encoded like a copied image file.
        case image(uti: String)
        /// HEIC, WebP, AVIF or BMP, turned into JPEG or PNG.
        case convertedImage(uti: String)
        case video
        case pdf
        case unsupported
    }

    static let imageUTIs: [String: String] = [
        "png": "public.png", "jpg": "public.jpeg", "jpeg": "public.jpeg",
        "tif": "public.tiff", "tiff": "public.tiff",
    ]

    static func kind(for url: URL) -> Kind {
        let ext = url.pathExtension.lowercased()
        if let uti = imageUTIs[ext] { return .image(uti: uti) }
        if let uti = Files.convertibleImageUTI(for: url) { return .convertedImage(uti: uti) }
        if Files.isVideo(url) { return .video }
        if Files.isPDF(url) { return .pdf }
        return .unsupported
    }

    /// The extension an optimized image is written with.
    static func imageExtension(outputType: String, source: URL) -> String {
        switch outputType {
        case "public.jpeg":
            let ext = source.pathExtension.lowercased()
            return ext == "jpeg" || ext == "jpg" ? source.pathExtension : "jpg"
        case "public.png":
            return source.pathExtension.lowercased() == "png" ? source.pathExtension : "png"
        default:
            return source.pathExtension
        }
    }

    // MARK: Where results go

    enum OutputMode: String, CaseIterable {
        case besideOriginal, folder

        static func sanitized(_ value: String?) -> OutputMode {
            value.flatMap(OutputMode.init(rawValue:)) ?? .besideOriginal
        }
    }

    /// Nil when folder mode has no usable folder: the file is then skipped,
    /// never quietly written somewhere else.
    static func destinationDirectory(source: URL, mode: OutputMode, folder: String?,
                                     isDirectory: (String) -> Bool = defaultIsDirectory) -> URL? {
        switch mode {
        case .besideOriginal:
            return source.deletingLastPathComponent()
        case .folder:
            guard let folder, !folder.isEmpty, isDirectory(folder) else { return nil }
            return URL(fileURLWithPath: folder, isDirectory: true)
        }
    }

    static func defaultIsDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    // MARK: Names

    /// Stable, not localized, so a result is recognized in any language.
    static let marker = "optimized"
    static let maxNameBytes = 255
    static let maxAttempts = 999

    /// `<base> (optimized).<ext>`, then `<base> (optimized 2).<ext>` and on.
    /// The base is shortened so the longest name still fits the file system.
    static func outputName(base: String, ext: String, attempt: Int) -> String {
        let tag = attempt == 0 ? " (\(marker))" : " (\(marker) \(attempt + 1))"
        let tail = tag + (ext.isEmpty ? "" : "." + ext)
        let reserve = " (\(marker) \(maxAttempts))".utf8.count + (ext.isEmpty ? 0 : ext.utf8.count + 1)
        var clean = base.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        clean = String(clean.drop { $0 == "." })
        if clean.trimmingCharacters(in: .whitespaces).isEmpty { clean = "Optimized" }
        while clean.utf8.count > maxNameBytes - reserve { clean.removeLast() }
        return clean + tail
    }

    /// A file this feature already wrote, dropped again.
    static func isAlreadyOptimized(_ url: URL) -> Bool {
        let base = url.deletingPathExtension().lastPathComponent
        if base.hasSuffix(" (\(marker))") { return true }
        guard base.hasSuffix(")"), let open = base.range(of: " (\(marker) ", options: .backwards) else {
            return false
        }
        let number = base[open.upperBound..<base.index(before: base.endIndex)]
        return !number.isEmpty && number.allSatisfy(\.isNumber)
    }

    // MARK: Outcomes

    enum SkipReason: String, CaseIterable {
        case notSmaller, tooLarge, tooLong, notDownloaded, notAFile, protected, leftAlone,
             unsupported, conversionOff, alreadyOptimized, diskSpace, cannotWrite, folderUnavailable,
             unreadable, noVideo
    }

    /// The clipboard engine names its skips with short tags; the File
    /// optimizer shows them.
    static func skipReason(tag: String) -> SkipReason {
        switch tag {
        case "not smaller": return .notSmaller
        case "size": return .tooLarge
        case "duration": return .tooLong
        case "not downloaded": return .notDownloaded
        case "not a file": return .notAFile
        case "protected": return .protected
        case "image", "left alone": return .leftAlone
        case "disk space": return .diskSpace
        case "unreadable", "empty": return .unreadable
        case "no video": return .noVideo
        default: return .unsupported
        }
    }

    // MARK: Placing a result

    enum PlaceError: Error, Equatable {
        case cannotWrite, diskSpace, exhausted, failed(Int32)
    }

    static func placeError(errno code: Int32) -> PlaceError {
        switch code {
        case EACCES, EPERM, EROFS: return .cannotWrite
        case ENOSPC, EDQUOT: return .diskSpace
        default: return .failed(code)
        }
    }

    static let partialPrefix = ".vorssaint-optimizing-"

    /// Moves `file` into `directory` under the first free optimized name.
    /// Never replaces anything: a taken name moves on to the next one. When
    /// a rename cannot cross to that folder, the file is copied in under a
    /// hidden name first; `noteCopy` hears that name before it exists, so a
    /// crash in between can be cleaned up, and nil once it is gone.
    static func place(_ file: URL, in directory: URL, base: String, ext: String,
                      noteCopy: (URL?) -> Void = { _ in }) throws -> URL {
        switch renameExclusive(file, in: directory, base: base, ext: ext) {
        case .success(let url):
            return url
        case .failure(let error) where error == .cannotWrite || error == .diskSpace || error == .exhausted:
            throw error
        case .failure:
            break
        }
        let partial = directory.appendingPathComponent(partialPrefix + UUID().uuidString
                                                       + (ext.isEmpty ? "" : "." + ext))
        noteCopy(partial)
        defer {
            try? FileManager.default.removeItem(at: partial)
            noteCopy(nil)
        }
        do {
            try FileManager.default.copyItem(at: file, to: partial)
        } catch {
            throw copyError(error)
        }
        switch renameExclusive(partial, in: directory, base: base, ext: ext) {
        case .success(let url):
            try? FileManager.default.removeItem(at: file)
            return url
        case .failure(let error):
            throw error
        }
    }

    private static func renameExclusive(_ file: URL, in directory: URL, base: String,
                                        ext: String) -> Result<URL, PlaceError> {
        for attempt in 0..<maxAttempts {
            let target = directory.appendingPathComponent(outputName(base: base, ext: ext, attempt: attempt))
            if renamex_np(file.path, target.path, UInt32(RENAME_EXCL)) == 0 { return .success(target) }
            var code = errno
            if code == ENOTSUP || code == EINVAL {
                // Volumes such as exFAT or SMB lack an exclusive rename:
                // claim the name with an exclusive create, then rename over
                // that placeholder, which is ours alone.
                let fd = open(target.path, O_CREAT | O_EXCL | O_WRONLY, 0o600)
                if fd >= 0 {
                    close(fd)
                    if rename(file.path, target.path) == 0 { return .success(target) }
                    code = errno
                    unlink(target.path)
                } else {
                    code = errno
                }
            }
            if code == EEXIST { continue }
            return .failure(placeError(errno: code))
        }
        return .failure(.exhausted)
    }

    private static func copyError(_ error: Error) -> PlaceError {
        let ns = error as NSError
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError, underlying.domain == NSPOSIXErrorDomain {
            return placeError(errno: Int32(underlying.code))
        }
        switch ns.code {
        case NSFileWriteNoPermissionError, NSFileWriteVolumeReadOnlyError: return .cannotWrite
        case NSFileWriteOutOfSpaceError: return .diskSpace
        default: return .failed(Int32(ns.code))
        }
    }

    // MARK: Progress

    /// avconvert reports nothing machine readable, so video progress is an
    /// estimate from the clip length, held below done until it is done.
    static func estimatedVideoProgress(elapsed: TimeInterval, duration: Double) -> Double {
        min(0.95, max(0, elapsed / max(1, duration * 0.75)))
    }

    /// Savings shown under the queue.
    static func savedBytes(_ pairs: [(before: Int64, after: Int64)]) -> Int64 {
        pairs.reduce(0) { $0 + max(0, $1.before - $1.after) }
    }
}
