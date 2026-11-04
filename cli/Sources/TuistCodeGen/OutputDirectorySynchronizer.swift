#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif
import Foundation
import Path

/// Makes an existing output directory match a freshly generated staging directory, consuming the staging directory.
///
/// Entries the staging directory no longer has are removed first, so a rename that only changes case also works on a
/// case-insensitive volume. A regular file whose bytes and permissions are unchanged is left in place. Any other file
/// is moved over its predecessor with `rename(2)`, which replaces it atomically because staging and output share the
/// project's `Derived/CodeGen` directory.
struct OutputDirectorySynchronizer {
    private let fileManager = FileManager.default

    func synchronize(_ outputDirectory: AbsolutePath, with stagingDirectory: AbsolutePath) throws {
        let staged = try entries(in: stagingDirectory)
        for name in try entries(in: outputDirectory).subtracting(staged) {
            try fileManager.removeItem(atPath: outputDirectory.appending(component: name).pathString)
        }
        for name in staged.sorted() {
            let source = stagingDirectory.appending(component: name)
            let destination = outputDirectory.appending(component: name)
            let sourceType = entryType(at: source)
            let destinationType = entryType(at: destination)
            if sourceType == .typeDirectory, destinationType == .typeDirectory {
                try synchronize(destination, with: source)
                continue
            }
            if sourceType == .typeRegular, destinationType == .typeRegular, try isUnchanged(destination, comparedTo: source) {
                continue
            }
            if destinationType != nil, sourceType == .typeDirectory || destinationType == .typeDirectory {
                try fileManager.removeItem(atPath: destination.pathString)
            }
            try move(source, to: destination)
        }
    }

    private func entries(in directory: AbsolutePath) throws -> Set<String> {
        Set(try fileManager.contentsOfDirectory(atPath: directory.pathString))
    }

    private func entryType(at path: AbsolutePath) -> FileAttributeType? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: path.pathString) else { return nil }
        return attributes[.type] as? FileAttributeType
    }

    private func isUnchanged(_ destination: AbsolutePath, comparedTo source: AbsolutePath) throws -> Bool {
        let sourceAttributes = try fileManager.attributesOfItem(atPath: source.pathString)
        let destinationAttributes = try fileManager.attributesOfItem(atPath: destination.pathString)
        guard (sourceAttributes[.size] as? NSNumber) == (destinationAttributes[.size] as? NSNumber),
              (sourceAttributes[.posixPermissions] as? NSNumber) == (destinationAttributes[.posixPermissions] as? NSNumber)
        else { return false }
        return fileManager.contentsEqual(atPath: source.pathString, andPath: destination.pathString)
    }

    private func move(_ source: AbsolutePath, to destination: AbsolutePath) throws {
        guard rename(source.pathString, destination.pathString) == 0 else {
            let code = errno
            throw CocoaError(.fileWriteUnknown, userInfo: [
                NSFilePathErrorKey: destination.pathString,
                NSUnderlyingErrorKey: POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO),
            ])
        }
    }
}
