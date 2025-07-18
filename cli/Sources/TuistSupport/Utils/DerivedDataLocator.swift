import CryptoKit
import Foundation
import Mockable
import Path

@Mockable
public protocol DerivedDataLocating {
    func locate(
        for projectPath: AbsolutePath
    ) async throws -> AbsolutePath
}

public final class DerivedDataLocator: DerivedDataLocating {
    public init() {}

    public func locate(
        for projectPath: AbsolutePath
    ) async throws -> AbsolutePath {
        let hash = try XcodeProjectPathHasher.hashString(for: projectPath.pathString)
        return try await Environment.current.derivedDataDirectory()
            .appending(component: "\(projectPath.basenameWithoutExt)-\(hash)")
    }
}

// Thanks to https://pewpewthespells.com/blog/xcode_deriveddata_hashes.html for
// the initial Objective-C implementation.
// This is taken from XCLogParser, from Spotify, at:
// https://github.com/spotify/XCLogParser/blob/master/Sources/XcodeHasher/XcodeHasher.swift

enum XcodeProjectPathHasher {
    enum HashingError: Error {
        case invalidPartitioning
    }

    static func hashString(for path: String) throws -> String {
        // Initialize a 28 `String` array since we can't initialize empty `Character`s.
        var result = Array(repeating: "", count: 28)

        let md5 = Insecure.MD5.hash(data: path.data(using: .utf8) ?? Data())
        let digest = Array(md5)

        // Split 16 bytes into two chunks of 8 bytes each.
        let partitions = stride(from: 0, to: digest.count, by: 8).map {
            Array(digest[$0 ..< Swift.min($0 + 8, digest.count)])
        }

        guard let firstHalf = partitions.first,
              let secondHalf = partitions.last
        else {
            throw HashingError.invalidPartitioning
        }

        // We would need to reverse the bytes, so we just read them in big endian.
        var startValue = UInt64(bigEndian: Data(firstHalf).withUnsafeBytes { $0.load(as: UInt64.self) })

        for index in stride(from: 13, through: 0, by: -1) {
            // Take the startValue % 26 to restrict to alphabetic characters and add 'a' scalar value (97).
            let char = String(UnicodeScalar(Int(startValue % 26) + 97)!)
            result[index] = char
            startValue /= 26
        }

        // We would need to reverse the bytes, so we just read them in big endian.
        startValue = UInt64(bigEndian: Data(secondHalf).withUnsafeBytes { $0.load(as: UInt64.self) })

        for index in stride(from: 27, through: 14, by: -1) {
            // Take the startValue % 26 to restrict to alphabetic characters and add 'a' scalar value (97).
            let char = String(UnicodeScalar(Int(startValue % 26) + 97)!)
            result[index] = char
            startValue /= 26
        }

        return result.joined()
    }
}
