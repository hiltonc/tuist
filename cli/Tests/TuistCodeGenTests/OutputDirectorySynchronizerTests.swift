import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
@testable import TuistCodeGen

struct OutputDirectorySynchronizerTests {
    private let fileSystem = FileSystem()
    private let subject = OutputDirectorySynchronizer()

    @Test(.inTemporaryDirectory)
    func synchronize_applies_a_rename_that_only_changes_case() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let output = root.appending(component: "Output")
        let staging = root.appending(component: "Staging")
        try await write(["Foo.swift", "Models/A.swift"], in: output)
        try await write(["foo.swift", "models/A.swift"], in: staging)

        try subject.synchronize(output, with: staging)

        #expect(try entries(in: output) == ["foo.swift", "models"])
        #expect(try entries(in: output.appending(component: "models")) == ["A.swift"])
    }

    private func write(_ files: [String], in directory: AbsolutePath) async throws {
        for file in files {
            let path = directory.appending(try RelativePath(validating: file))
            try await fileSystem.makeDirectory(at: path.parentDirectory)
            try await fileSystem.writeText(file, at: path)
        }
    }

    private func entries(in directory: AbsolutePath) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.pathString).sorted()
    }
}
