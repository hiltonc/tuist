import FileSystem
import Foundation
import Path
import Testing
import TuistAlert
import TuistCore
import TuistSupport
import TuistTesting
import XcodeGraph
@testable import TuistInspectCommand
@testable import TuistKit

struct TargetImportsScannerTests {
    private let fileSystem = FileSystem()

    @Test func imports() async throws {
        // Given
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            let targetPath = temporaryDirectory.appending(components: "FirstTarget", "Sources")

            let targetFirstFile = targetPath.appending(component: "FirstFile.swift")
            let targetSecondFile = targetPath.appending(component: "SecondFile.swift")

            try await fileSystem.makeDirectory(at: targetPath)

            try await fileSystem.writeText(
                """
                import SecondTarget
                import A

                let a = 5
                """,
                at: targetFirstFile
            )

            try await fileSystem.writeText(
                """
                @testable import ThirdTarget

                func main() { }
                """,
                at: targetSecondFile
            )

            let target = Target.test(
                name: "FirstTarget",
                sources: [
                    SourceFile(path: targetFirstFile),
                    SourceFile(path: targetSecondFile),
                ]
            )

            // When
            let result = try await TargetImportsScanner()
                .imports(for: target)

            // Then
            #expect(result == ["SecondTarget", "ThirdTarget", "A"])
        }
    }

    @Test func imports_in_buildable_folder_sources() async throws {
        // Given
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            let targetPath = temporaryDirectory.appending(components: "FirstTarget", "Sources")

            let targetFirstFile = targetPath.appending(component: "FirstFile.swift")
            let targetSecondFile = targetPath.appending(component: "SecondFile.swift")

            try await fileSystem.makeDirectory(at: targetPath)

            try await fileSystem.writeText(
                """
                import SecondTarget
                import A

                let a = 5
                """,
                at: targetFirstFile
            )

            try await fileSystem.writeText(
                """
                @testable import ThirdTarget

                func main() { }
                """,
                at: targetSecondFile
            )

            let target = Target.test(
                name: "FirstTarget",
                buildableFolders: [
                    BuildableFolder(
                        path: "/Sources",
                        exceptions: [],
                        resolvedFiles: [
                            BuildableFolderFile(path: targetFirstFile, compilerFlags: nil),
                            BuildableFolderFile(path: targetSecondFile, compilerFlags: nil),
                        ]
                    ),
                ]
            )

            // When
            let result = try await TargetImportsScanner()
                .imports(for: target)

            // Then
            #expect(result == ["SecondTarget", "ThirdTarget", "A"])
        }
    }

    @Test func imports_in_code_generator_output() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given
            let output = temporaryDirectory.appending(
                components: "Derived",
                "CodeGen",
                "Targets",
                "Strings",
                "strings",
                "Sources"
            )
            try await fileSystem.makeDirectory(at: output.appending(component: "Nested"))
            try await fileSystem.writeText("import StringKeys", at: output.appending(component: "Strings.swift"))
            try await fileSystem.writeText("import Nested", at: output.appending(components: "Nested", "Nested.swift"))
            try await fileSystem.writeText("import NotSource", at: output.appending(component: "notes.txt"))
            let target = Target.test(name: "Strings", buildableFolders: [generatedFolder(output)])

            // When
            let result = try await TargetImportsScanner().imports(for: target)

            // Then
            #expect(result == ["StringKeys", "Nested"])
        }
    }

    @Test(.withScopedAlertController()) func imports_warns_when_code_generator_output_is_missing() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given
            let output = temporaryDirectory.appending(
                components: "Derived",
                "CodeGen",
                "Targets",
                "Strings",
                "strings",
                "Sources"
            )
            let target = Target.test(name: "Strings", buildableFolders: [generatedFolder(output)])

            // When
            let result = try await TargetImportsScanner().imports(for: target)

            // Then
            #expect(result == [])
            #expect(AlertController.current.warnings().map(\.message).map { $0.plain() } == [
                "The code generator output of target 'Strings' at \(output.pathString) doesn't exist, so its imports weren't inspected. Run 'tuist generate' to produce it.",
            ])
        }
    }

    @Test func lint_counts_an_import_only_in_code_generator_output() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given
            let project = temporaryDirectory.appending(component: "Project")
            let declaringOutput = project.appending(components: "Derived", "CodeGen", "Targets", "Strings", "strings", "Sources")
            let undeclaringOutput = project.appending(components: "Derived", "CodeGen", "Targets", "Other", "strings", "Sources")
            for output in [declaringOutput, undeclaringOutput] {
                try await fileSystem.makeDirectory(at: output)
                try await fileSystem.writeText("import StringKeys", at: output.appending(component: "Strings.swift"))
            }
            let strings = Target.test(
                name: "Strings",
                product: .staticFramework,
                dependencies: [.target(name: "StringKeys")],
                buildableFolders: [generatedFolder(declaringOutput)]
            )
            let other = Target.test(
                name: "Other",
                product: .staticFramework,
                buildableFolders: [generatedFolder(undeclaringOutput)]
            )
            let stringKeys = Target.test(name: "StringKeys", product: .staticFramework)
            let graph = Graph.test(
                path: project,
                projects: [project: .test(path: project, targets: [strings, other, stringKeys])],
                dependencies: [
                    .target(name: "Strings", path: project): [.target(name: "StringKeys", path: project)],
                ]
            )
            let subject = GraphImportsLinter(targetScanner: TargetImportsScanner())

            // When
            let redundant = try await subject.lint(
                graphTraverser: GraphTraverser(graph: graph),
                inspectType: .redundant,
                ignoreTagsMatching: []
            )
            let implicit = try await subject.lint(
                graphTraverser: GraphTraverser(graph: graph),
                inspectType: .implicit,
                ignoreTagsMatching: []
            )

            // Then
            #expect(redundant == [])
            #expect(implicit == [InspectImportsIssue(target: "Other", dependencies: ["StringKeys"])])
        }
    }

    @Test func imports_when_filesAreAbsent() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given
            let sourcesPath = temporaryDirectory.appending(components: "Target", "Sources")
            let sourcePath = sourcesPath.appending(component: "Source.swift")
            let target = Target.test(
                name: "Target",
                sources: [
                    SourceFile(path: sourcePath),
                ]
            )

            // When
            let result = try await TargetImportsScanner()
                .imports(for: target)

            // Then
            #expect(result == [])
        }
    }

    @Test func imports_limitsConcurrentFileScans() async throws {
        // Given
        let sourceCodeReader = ConcurrentSourceCodeReader()
        let sources = try (0 ..< 20).map { index -> SourceFile in
            let path = try AbsolutePath(validating: "/Target/Sources/File\(index).swift")
            return SourceFile(path: path)
        }
        let target = Target.test(
            name: "FirstTarget",
            sources: sources
        )

        // When
        let result = try await TargetImportsScanner(
            maxConcurrentFileScans: 3,
            sourceCodeReader: sourceCodeReader.read(at:)
        )
        .imports(for: target)

        // Then
        #expect(result == ["SecondTarget"])
        #expect(await sourceCodeReader.maxConcurrentReads <= 3)
    }
}

private func generatedFolder(_ path: AbsolutePath) -> BuildableFolder {
    BuildableFolder(path: path, exceptions: BuildableFolderExceptions(exceptions: []), resolvedFiles: [], isGenerated: true)
}

private actor ConcurrentSourceCodeReader {
    private var activeReads = 0
    private(set) var maxConcurrentReads = 0

    func read(at _: AbsolutePath) async throws -> String? {
        activeReads += 1
        maxConcurrentReads = max(maxConcurrentReads, activeReads)
        defer { activeReads -= 1 }

        try await Task.sleep(nanoseconds: 10_000_000)
        return "import SecondTarget"
    }
}
