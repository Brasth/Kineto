import CryptoKit
import Darwin
import Foundation

public enum ModelStoreError: Error, Equatable {
    case missing
    case wrongSize(expected: Int64, actual: Int64)
    case checksumMismatch
    case invalidPointer
}

public actor ModelStore {
    private let rootURL: URL
    private let fileManager: FileManager

    public init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
    }

    public func verify(_ fileURL: URL, against descriptor: ModelDescriptor) throws {
        guard fileManager.isReadableFile(atPath: fileURL.path) else {
            throw ModelStoreError.missing
        }
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        let actualSize = Int64(values.fileSize ?? -1)
        guard actualSize == descriptor.byteCount else {
            throw ModelStoreError.wrongSize(expected: descriptor.byteCount, actual: actualSize)
        }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var digest = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1_048_576) ?? Data()
            guard !chunk.isEmpty else { break }
            digest.update(data: chunk)
        }
        let actualDigest = digest.finalize().map { String(format: "%02x", $0) }.joined()
        guard actualDigest == descriptor.sha256 else {
            throw ModelStoreError.checksumMismatch
        }
    }

    public func activate(_ stagedURL: URL, descriptor: ModelDescriptor) throws -> URL {
        try verify(stagedURL, against: descriptor)
        let pointerDirectory = rootURL.appending(path: descriptor.id, directoryHint: .isDirectory)
        let versionURL = pointerDirectory.appending(path: descriptor.revision, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: versionURL, withIntermediateDirectories: true)
        let destination = versionURL.appending(path: descriptor.fileName)

        var needsInstallation = true
        if fileManager.fileExists(atPath: destination.path) {
            needsInstallation = (try? verify(destination, against: descriptor)) == nil
        }
        if needsInstallation {
            let temporaryModelURL = versionURL.appending(path: ".staged-\(UUID().uuidString)")
            do {
                try fileManager.copyItem(at: stagedURL, to: temporaryModelURL)
                try verify(temporaryModelURL, against: descriptor)
                try synchronizeFile(temporaryModelURL)
                if fileManager.fileExists(atPath: destination.path) {
                    _ = try fileManager.replaceItemAt(destination, withItemAt: temporaryModelURL)
                } else {
                    try fileManager.moveItem(at: temporaryModelURL, to: destination)
                }
                try synchronizeDirectory(versionURL)
            } catch {
                try? fileManager.removeItem(at: temporaryModelURL)
                throw error
            }
        }

        let currentURL = pointerDirectory.appending(path: "current")
        let temporaryPointerURL = pointerDirectory.appending(path: ".current-\(UUID().uuidString)")
        do {
            try Data(descriptor.revision.utf8).write(to: temporaryPointerURL, options: .withoutOverwriting)
            try synchronizeFile(temporaryPointerURL)
            if fileManager.fileExists(atPath: currentURL.path) {
                _ = try fileManager.replaceItemAt(currentURL, withItemAt: temporaryPointerURL)
            } else {
                try fileManager.moveItem(at: temporaryPointerURL, to: currentURL)
            }
            try synchronizeDirectory(pointerDirectory)
            try? fileManager.removeItem(at: stagedURL)
            return destination
        } catch {
            try? fileManager.removeItem(at: temporaryPointerURL)
            throw error
        }
    }

    public func activeModel(for descriptor: ModelDescriptor) throws -> URL {
        let directory = rootURL.appending(path: descriptor.id, directoryHint: .isDirectory)
        let currentURL = directory.appending(path: "current")
        guard let revision = try? String(contentsOf: currentURL, encoding: .utf8),
              revision == descriptor.revision else {
            throw ModelStoreError.invalidPointer
        }
        let modelURL = directory
            .appending(path: revision, directoryHint: .isDirectory)
            .appending(path: descriptor.fileName)
        try verify(modelURL, against: descriptor)
        return modelURL
    }

    public func remove(_ descriptor: ModelDescriptor) throws {
        let directory = rootURL.appending(path: descriptor.id, directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: directory.path) else {
            throw ModelStoreError.missing
        }
        try fileManager.removeItem(at: directory)
    }
    private func synchronizeFile(_ url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.synchronize()
        try handle.close()
    }

    private func synchronizeDirectory(_ url: URL) throws {
        let descriptor = Darwin.open(url.path, O_RDONLY)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
