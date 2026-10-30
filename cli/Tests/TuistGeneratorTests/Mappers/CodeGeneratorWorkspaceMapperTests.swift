import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import XcodeGraph
@testable import TuistCore
@testable import TuistGenerator
@testable import TuistTesting

struct CodeGeneratorWorkspaceMapperTests {
    private let subject = CodeGeneratorWorkspaceMapper()
    private let root = try! AbsolutePath(validating: "/Repository") // swiftlint:disable:this force_try
    private var core: AbsolutePath { root.appending(components: "Projects", "Core") }
    private var app: AbsolutePath { root.appending(components: "Projects", "App") }

    @Test
    func map_attaches_a_generated_folder_for_each_per_target_generator() async throws {
        let target = Target.test(
            name: "AccountUI",
            product: .staticFramework,
            codeGenerators: [generator(name: "assets"), generator(name: "strings")]
        )

        let (mapped, _) = try await subject.map(workspace: workspace([.test(path: core, targets: [target])]))

        let folders = try #require(mapped.projects.first?.targets["AccountUI"]?.buildableFolders)
        #expect(folders.map(\.path) == ["assets", "strings"].map {
            CodeGeneratorLayout.targetOutputDirectory(projectPath: core, target: "AccountUI", generator: $0)
        })
        #expect(folders.allSatisfy { $0.isCodeGeneratorOutput && $0.resolvedFiles.isEmpty })
    }

    @Test
    func map_injects_the_producer_into_each_consumers_model_dependencies() async throws {
        let codegen = Target.test(
            name: "GQLCodegen",
            destinations: [.iPhone],
            product: .staticLibrary,
            codegen: generator(name: "GQLCodegen", outputs: [
                .init(projectPath: core, target: "GQLSchema"),
                .init(projectPath: app, target: "App"),
            ])
        )
        let schema = Target.test(name: "GQLSchema", destinations: [.iPhone, .iPad], product: .staticFramework)
        let appTarget = Target.test(name: "App", destinations: [.mac], product: .app)

        let (mapped, _) = try await subject.map(workspace: workspace([
            .test(path: core, targets: [codegen, schema]),
            .test(path: app, name: "App", targets: [appTarget]),
        ]))

        let mappedCore = try #require(mapped.projects.first { $0.path == core })
        let mappedApp = try #require(mapped.projects.first { $0.path == app })
        #expect(mappedCore.targets["GQLSchema"]?.dependencies == [.target(name: "GQLCodegen")])
        #expect(mappedApp.targets["App"]?.dependencies == [.project(target: "GQLCodegen", path: core)])
        #expect(mappedApp.targets["App"]?.buildableFolders.map(\.path) == [
            CodeGeneratorLayout.producerOutputDirectory(consumerProjectPath: app, producer: "GQLCodegen", consumer: "App"),
        ])
        #expect(mappedApp.targets["App"]?.buildableFolders.first?.isCodeGeneratorOutput == true)
        #expect(mappedCore.targets["GQLCodegen"]?.destinations == [.iPhone, .iPad, .mac])
    }

    @Test
    func map_does_not_duplicate_a_dependency_the_consumer_already_declares() async throws {
        let codegen = Target.test(
            name: "GQLCodegen",
            product: .staticLibrary,
            codegen: generator(name: "GQLCodegen", outputs: [.init(projectPath: core, target: "GQLSchema")])
        )
        let schema = Target.test(name: "GQLSchema", product: .staticFramework, dependencies: [.target(name: "GQLCodegen")])

        let (mapped, _) = try await subject.map(workspace: workspace([.test(path: core, targets: [codegen, schema])]))

        #expect(mapped.projects.first?.targets["GQLSchema"]?.dependencies == [.target(name: "GQLCodegen")])
    }

    @Test
    func map_rejects_names_unusable_as_path_components() async throws {
        let target = Target.test(
            name: "AccountUI",
            product: .staticFramework,
            codeGenerators: [generator(name: "Strings"), generator(name: "strings"), generator(name: "../escape")]
        )
        let codegen = Target.test(
            name: "GQLCodegen",
            product: .staticLibrary,
            codegen: generator(name: "GQLCodegen", outputs: [.init(projectPath: core, target: "a/b")])
        )

        await #expect {
            try await subject.map(workspace: workspace([.test(path: core, targets: [target, codegen])]))
        } throws: { error in
            guard case let CodeGeneratorWorkspaceMapperError.invalidDeclarations(issues) = error else { return false }
            return issues.contains { $0.contains("'../escape'") && $0.contains("path component") }
                && issues.contains { $0.contains("'a/b'") && $0.contains("path component") }
                && issues.contains { $0.contains("'Strings', 'strings'") && $0.contains("differ only by case") }
        }
    }

    @Test
    func map_rejects_unknown_and_contested_outputs() async throws {
        let target = Target.test(name: "AccountUI", product: .staticFramework)
        let codegen = Target.test(
            name: "GQLCodegen",
            product: .staticLibrary,
            codegen: generator(name: "GQLCodegen", outputs: [
                .init(projectPath: core, target: "Missing"),
                .init(projectPath: core, target: "AccountUI"),
            ])
        )
        let otherCodegen = Target.test(
            name: "OtherCodegen",
            product: .staticLibrary,
            codegen: generator(name: "OtherCodegen", outputs: [.init(projectPath: core, target: "AccountUI")])
        )

        await #expect {
            try await subject.map(workspace: workspace([.test(path: core, targets: [target, codegen, otherCodegen])]))
        } throws: { error in
            guard case let CodeGeneratorWorkspaceMapperError.invalidDeclarations(issues) = error else { return false }
            return issues.contains { $0.contains("'Missing', which isn't a target") }
                && issues.contains { $0.contains("claimed by more than one code generation output") }
        }
    }

    @Test
    func map_rejects_generators_on_package_targets() async throws {
        let target = Target.test(name: "Package", product: .staticFramework, codeGenerators: [generator(name: "a")])

        await #expect(throws: CodeGeneratorWorkspaceMapperError.self) {
            try await subject.map(workspace: workspace([.test(path: core, targets: [target], type: .external(hash: nil))]))
        }
    }

    @Test
    func map_rejects_inputs_that_overlap_an_output_directory() async throws {
        let output = CodeGeneratorLayout.targetOutputDirectory(projectPath: core, target: "AccountUI", generator: "a")
        let target = Target.test(
            name: "AccountUI",
            product: .staticFramework,
            codeGenerators: [
                generator(name: "a"),
                generator(name: "b", inputs: [
                    .folder(.init(anchor: .project, anchorDirectory: core, relativePath: output.relative(to: core).pathString)),
                ]),
                generator(name: "c", inputs: [
                    .folder(.init(anchor: .project, anchorDirectory: core, relativePath: "Derived/CodeGen")),
                ]),
            ]
        )

        await #expect {
            try await subject.map(workspace: workspace([.test(path: core, targets: [target])]))
        } throws: { error in
            guard case let CodeGeneratorWorkspaceMapperError.invalidDeclarations(issues) = error else { return false }
            return issues.filter { $0.contains("overlaps") }.count == 2
        }
    }

    @Test
    func map_accepts_a_wide_input_containing_derived_directories() async throws {
        let target = Target.test(
            name: "AccountUI",
            product: .staticFramework,
            codeGenerators: [
                generator(name: "a", inputs: [
                    .glob(.init(anchor: .repository, anchorDirectory: root, relativePath: "Projects/**/*.graphql")),
                    .folder(.init(anchor: .repository, anchorDirectory: root, relativePath: "Projects")),
                ]),
            ]
        )

        _ = try await subject.map(workspace: workspace([.test(path: core, targets: [target])]))
    }

    @Test(.inTemporaryDirectory)
    func map_deletes_output_and_state_no_declaration_accounts_for() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()
        let project = temporaryDirectory.appending(component: "Core")
        let kept = CodeGeneratorLayout.targetOutputDirectory(projectPath: project, target: "AccountUI", generator: "assets")
        let staleGenerator = CodeGeneratorLayout.targetOutputDirectory(
            projectPath: project,
            target: "AccountUI",
            generator: "old"
        )
        let staleTarget = CodeGeneratorLayout.targetOutputDirectory(projectPath: project, target: "Removed", generator: "assets")
        let staleProducer = CodeGeneratorLayout.producerOutputDirectory(
            consumerProjectPath: project,
            producer: "Gone",
            consumer: "AccountUI"
        )
        for directory in [kept, staleGenerator, staleTarget, staleProducer] {
            try await fileSystem.makeDirectory(at: directory)
        }
        let keptState = CodeGeneratorLayout.targetStatePath(projectPath: project, target: "AccountUI", generator: "assets")
        let staleState = CodeGeneratorLayout.targetStatePath(projectPath: project, target: "AccountUI", generator: "old")
        for state in [keptState, staleState] {
            try await fileSystem.makeDirectory(at: state.parentDirectory)
            try await fileSystem.writeText("hash", at: state)
        }
        let target = Target.test(
            name: "AccountUI",
            product: .staticFramework,
            codeGenerators: [generator(name: "assets", rootDirectory: temporaryDirectory)]
        )

        let (_, sideEffects) = try await subject.map(workspace: workspace([.test(path: project, targets: [target])]))

        #expect(sideEffects == [
            .directory(DirectoryDescriptor(path: staleGenerator.parentDirectory, state: .absent)),
            .directory(DirectoryDescriptor(path: staleTarget.parentDirectory.parentDirectory, state: .absent)),
            .directory(DirectoryDescriptor(path: staleProducer.parentDirectory.parentDirectory, state: .absent)),
            .file(FileDescriptor(path: staleState, state: .absent)),
        ])
    }

    // MARK: - Helpers

    private func workspace(_ projects: [Project]) -> WorkspaceWithProjects {
        WorkspaceWithProjects(workspace: .test(path: root), projects: projects)
    }

    private func generator(
        name: String,
        inputs: [CodeGenerator.Input] = [],
        outputs: [CodeGenerator.Output] = [],
        rootDirectory: AbsolutePath? = nil
    ) -> CodeGenerator {
        CodeGenerator(
            name: name,
            script: "exit 0",
            inputs: inputs,
            outputs: outputs,
            rootDirectory: rootDirectory ?? root
        )
    }
}
