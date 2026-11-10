import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistCore
import XcodeGraph
@testable import TuistHasher

struct TargetContentHasherCodeGeneratorTests {
    private let fileSystem = FileSystem()
    private let subject = TargetContentHasher(contentHasher: ContentHasher())

    @Test(.inTemporaryDirectory)
    func hash_does_not_depend_on_whether_generated_output_exists() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let project = try await makeProject(root: root)
        let target = target(project: project, generator: generator(root: root, project: project))
        let missing = try await hash(target, project: project)

        let output = CodeGeneratorLayout.targetOutputDirectory(projectPath: project, target: "AccountUI", generator: "strings")
        try await fileSystem.makeDirectory(at: output)
        try await fileSystem.writeText("let generated = 1", at: output.appending(component: "Strings.swift"))
        var withResolvedOutput = target
        withResolvedOutput.buildableFolders[0].resolvedFiles = [
            BuildableFolderFile(path: output.appending(component: "Strings.swift"), compilerFlags: nil),
        ]
        let present = try await hash(withResolvedOutput, project: project)

        try await fileSystem.writeText(
            "let generated = 2",
            at: output.appending(component: "Strings.swift"),
            options: Set([.overwrite])
        )
        let edited = try await hash(withResolvedOutput, project: project)

        #expect(missing == present)
        #expect(present == edited)
    }

    @Test(.inTemporaryDirectory)
    func hash_changes_when_a_generator_declaration_or_input_changes() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let project = try await makeProject(root: root)
        let base = try await hash(target(project: project, generator: generator(root: root, project: project)), project: project)
        let withoutGenerator = try await hash(target(project: project, generator: nil), project: project)
        let otherScript = try await hash(
            target(project: project, generator: generator(root: root, project: project, script: "exit 1")),
            project: project
        )
        let otherEnvironment = try await hash(
            target(project: project, generator: generator(root: root, project: project, environment: ["LEVEL": "internal"])),
            project: project
        )

        try await fileSystem.writeText(
            #"{"key": "changed"}"#,
            at: project.appending(components: "Strings", "en.json"),
            options: Set([.overwrite])
        )
        let editedInput = try await hash(
            target(project: project, generator: generator(root: root, project: project)),
            project: project
        )

        #expect(Set([base, withoutGenerator, otherScript, otherEnvironment, editedInput]).count == 5)
    }

    @Test(.inTemporaryDirectory)
    func hashing_never_runs_a_generator() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let project = try await makeProject(root: root)
        let marker = root.appending(component: "generator-ran")
        let generator = generator(root: root, project: project, script: "touch \"\(marker.pathString)\"")

        _ = try await hash(target(project: project, generator: generator), project: project)

        #expect(try await !fileSystem.exists(marker))
    }

    @Test(.inTemporaryDirectory)
    func a_consumers_hash_moves_with_its_producers_inputs() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let project = try await makeProject(root: root)
        let codegen = Target.test(
            name: "GQLCodegen",
            product: .staticLibrary,
            codegen: CodeGenerator(
                name: "GQLCodegen",
                script: "exit 0",
                inputs: [.file(.init(anchor: .project, anchorDirectory: project, relativePath: "Strings/en.json"))],
                outputs: [.init(projectPath: project, target: "GQLSchema")],
                rootDirectory: root
            )
        )
        let consumer = Target.test(name: "GQLSchema", product: .staticFramework, dependencies: [.target(name: "GQLCodegen")])
        let graphProject = Project.test(path: project, sourceRootPath: project, targets: [codegen, consumer])
        let graph = Graph.test(
            path: project,
            projects: [project: graphProject],
            dependencies: [.target(name: "GQLSchema", path: project): [.target(name: "GQLCodegen", path: project)]]
        )
        let hasher = GraphContentHasher(contentHasher: ContentHasher())
        let before = try await hasher.contentHashes(
            for: graph,
            include: { _ in true },
            destination: nil,
            additionalStrings: { _ in [] }
        )

        try await fileSystem.writeText(
            #"{"key": "changed"}"#,
            at: project.appending(components: "Strings", "en.json"),
            options: Set([.overwrite])
        )
        let after = try await hasher.contentHashes(
            for: graph,
            include: { _ in true },
            destination: nil,
            additionalStrings: { _ in [] }
        )

        let consumerTarget = try #require(before.keys.first { $0.target.name == "GQLSchema" })
        #expect(before[consumerTarget]?.hash != after[consumerTarget]?.hash)
    }

    // MARK: - Helpers

    private func makeProject(root: AbsolutePath) async throws -> AbsolutePath {
        let project = root.appending(components: "Projects", "DesignSystem")
        try await fileSystem.makeDirectory(at: project.appending(component: "Strings"))
        try await fileSystem.writeText(#"{"key": "value"}"#, at: project.appending(components: "Strings", "en.json"))
        return project
    }

    private func generator(
        root: AbsolutePath,
        project: AbsolutePath,
        script: String = "exit 0",
        environment: [String: String] = ["LEVEL": "public"]
    ) -> CodeGenerator {
        CodeGenerator(
            name: "strings",
            script: script,
            inputs: [.file(.init(anchor: .project, anchorDirectory: project, relativePath: "Strings/en.json"))],
            environment: environment,
            rootDirectory: root
        )
    }

    private func target(project: AbsolutePath, generator: CodeGenerator?) -> Target {
        let output = CodeGeneratorLayout.targetOutputDirectory(projectPath: project, target: "AccountUI", generator: "strings")
        return .test(
            name: "AccountUI",
            product: .staticFramework,
            buildableFolders: generator == nil ? [] : [
                BuildableFolder(path: output, exceptions: .init(exceptions: []), resolvedFiles: [], isGenerated: true),
            ],
            codeGenerators: generator.map { [$0] } ?? []
        )
    }

    private func hash(_ target: Target, project: AbsolutePath) async throws -> String {
        let graphTarget = GraphTarget(
            path: project,
            target: target,
            project: .test(path: project, sourceRootPath: project, targets: [target])
        )
        return try await subject.contentHash(
            for: graphTarget,
            hashedTargets: [:],
            hashedPaths: [:],
            destination: nil
        ).hash
    }
}
