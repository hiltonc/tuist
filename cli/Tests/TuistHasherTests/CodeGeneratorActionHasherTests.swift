import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistCore
import XcodeGraph
@testable import TuistHasher

struct CodeGeneratorActionHasherTests {
    private let fileSystem = FileSystem()
    private let subject = CodeGeneratorActionHasher(contentHasher: ContentHasher())

    @Test(.inTemporaryDirectory, arguments: [false, true])
    func hash_is_independent_of_the_checkout_location(isCodeGenerationTarget: Bool) async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let first = temporaryDirectory.appending(component: "first")
        let second = temporaryDirectory.appending(components: "nested", "second")
        for root in [first, second] {
            try await writeFixture(root: root)
        }
        let actionFor = { (root: AbsolutePath) in
            isCodeGenerationTarget
                ? try codeGenerationTargetAction(root: root, inputs: fixtureInputs(root: root))
                : action(root: root, inputs: fixtureInputs(root: root))
        }

        let firstHash = try await subject.hash(action: actionFor(first))
        let secondHash = try await subject.hash(action: actionFor(second))

        #expect(firstHash == secondHash)
    }

    @Test(.inTemporaryDirectory)
    func hash_changes_when_a_file_input_is_renamed_with_the_same_contents() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        try await writeFixture(root: root)
        let before = try await subject.hash(action: action(root: root, inputs: [.file(projectPath(root, "Schema/A.graphql"))]))

        try await fileSystem.move(
            from: root.appending(components: "Projects", "Core", "Schema", "A.graphql"),
            to: root.appending(components: "Projects", "Core", "Schema", "B.graphql")
        )
        let after = try await subject.hash(action: action(root: root, inputs: [.file(projectPath(root, "Schema/B.graphql"))]))

        #expect(before != after)
    }

    @Test(.inTemporaryDirectory)
    func hash_changes_when_a_file_inside_a_folder_input_is_renamed_or_edited() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        try await writeFixture(root: root)
        let inputs: [CodeGenerator.Input] = [.folder(projectPath(root, "Schema"))]
        let original = try await subject.hash(action: action(root: root, inputs: inputs))

        let schema = root.appending(components: "Projects", "Core", "Schema")
        try await fileSystem.move(from: schema.appending(component: "A.graphql"), to: schema.appending(component: "C.graphql"))
        let renamed = try await subject.hash(action: action(root: root, inputs: inputs))

        try await fileSystem.writeText("type C {}", at: schema.appending(component: "C.graphql"), options: Set([.overwrite]))
        let edited = try await subject.hash(action: action(root: root, inputs: inputs))

        #expect(Set([original, renamed, edited]).count == 3)
    }

    @Test(.inTemporaryDirectory)
    func hash_ignores_derived_directories_inside_folder_and_glob_inputs() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        try await writeFixture(root: root)
        let inputs: [CodeGenerator.Input] = [
            .folder(projectPath(root, "Schema")),
            .glob(repositoryPath(root, "Projects/**/*.graphql")),
        ]
        let before = try await subject.hash(action: action(root: root, inputs: inputs))

        for directory in [
            root.appending(components: "Projects", "Core", "Schema", "Derived"),
            root.appending(components: "Projects", "Core", "Derived", "CodeGen"),
        ] {
            try await fileSystem.makeDirectory(at: directory)
            try await fileSystem.writeText("type Generated {}", at: directory.appending(component: "Generated.graphql"))
        }
        let after = try await subject.hash(action: action(root: root, inputs: inputs))

        #expect(before == after)
    }

    @Test(.inTemporaryDirectory)
    func hash_of_a_glob_changes_when_its_first_match_appears() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        try await writeFixture(root: root)
        let inputs: [CodeGenerator.Input] = [.glob(repositoryPath(root, "Projects/**/*.proto"))]
        let empty = try await subject.hash(action: action(root: root, inputs: inputs))
        let noInputs = try await subject.hash(action: action(root: root, inputs: []))

        try await fileSystem.writeText("message A {}", at: root.appending(components: "Projects", "Core", "A.proto"))
        let matched = try await subject.hash(action: action(root: root, inputs: inputs))

        #expect(empty != noInputs)
        #expect(empty != matched)
    }

    @Test(.inTemporaryDirectory)
    func hash_of_a_glob_changes_with_the_pattern_even_when_matches_are_the_same() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        try await writeFixture(root: root)

        let narrow = try await subject.hash(action: action(root: root, inputs: [
            .glob(repositoryPath(root, "Projects/Core/**/*.graphql")),
        ]))
        let wide = try await subject.hash(action: action(root: root, inputs: [
            .glob(repositoryPath(root, "Projects/**/*.graphql")),
        ]))

        #expect(narrow != wide)
    }

    @Test(.inTemporaryDirectory)
    func hash_distinguishes_input_kinds_and_anchors() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        try await writeFixture(root: root)

        let projectRelative = try await subject.hash(action: action(
            root: root,
            inputs: [.file(projectPath(root, "Schema/A.graphql"))]
        ))
        let rootRelative = try await subject.hash(action: action(root: root, inputs: [
            .file(repositoryPath(root, "Projects/Core/Schema/A.graphql")),
        ]))
        let folder = try await subject.hash(action: action(root: root, inputs: [.folder(projectPath(root, "Schema"))]))

        #expect(Set([projectRelative, rootRelative, folder]).count == 3)
    }

    @Test(.inTemporaryDirectory)
    func hash_changes_with_the_declared_environment_command_name_and_target() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        try await writeFixture(root: root)

        let base = try await subject.hash(action: action(root: root))
        let environment = try await subject.hash(action: action(root: root, environment: ["ACCESS_LEVEL": "public"]))
        let otherValue = try await subject.hash(action: action(root: root, environment: ["ACCESS_LEVEL": "internal"]))
        let command = try await subject.hash(action: action(root: root, script: "exit 1"))
        let name = try await subject.hash(action: action(root: root, name: "other"))
        let target = try await subject.hash(action: action(root: root, targetName: "Other"))

        #expect(Set([base, environment, otherValue, command, name, target]).count == 6)
    }

    @Test(.inTemporaryDirectory)
    func hash_includes_script_input_output_run_with_the_generator_environment() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        try await writeFixture(root: root)
        let script = #"cat "$TUIST_ROOT_DIR/version.txt"; echo "$TOOL_FLAVOR""#
        let first = try await subject.hash(action: action(
            root: root,
            inputs: [.script(script)],
            environment: ["TOOL_FLAVOR": "a"]
        ))

        try await fileSystem.writeText("2.0.0", at: root.appending(component: "version.txt"), options: Set([.overwrite]))
        let second = try await subject.hash(action: action(
            root: root,
            inputs: [.script(script)],
            environment: ["TOOL_FLAVOR": "a"]
        ))

        #expect(first != second)
    }

    @Test(.inTemporaryDirectory)
    func hash_of_a_multi_target_action_covers_its_output_mapping() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        try await writeFixture(root: root)
        let core = root.appending(components: "Projects", "Core")
        let generator = { (outputs: [String]) in
            CodeGenerator(
                name: "GQLCodegen",
                script: "exit 0",
                inputs: [],
                outputs: outputs.map { CodeGenerator.Output(projectPath: core, target: $0) },
                rootDirectory: root
            )
        }
        let actionFor = { (outputs: [String]) in
            try #require(CodeGeneratorAction.actions(
                for: .test(name: "GQLCodegen", codegen: generator(outputs)),
                projectPath: core
            ).first)
        }

        let one = try await subject.hash(action: actionFor(["GQLSchema"]))
        let two = try await subject.hash(action: actionFor(["GQLSchema", "GQLTypes"]))

        #expect(one != two)
    }

    @Test(.inTemporaryDirectory)
    func hash_throws_when_a_declared_file_is_missing() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        try await writeFixture(root: root)

        await #expect(throws: CodeGeneratorInputResolverError.self) {
            try await subject.hash(action: action(root: root, inputs: [.file(projectPath(root, "Missing.json"))]))
        }
    }

    // MARK: - Helpers

    private func writeFixture(root: AbsolutePath) async throws {
        let schema = root.appending(components: "Projects", "Core", "Schema")
        try await fileSystem.makeDirectory(at: schema)
        try await fileSystem.writeText("type A {}", at: schema.appending(component: "A.graphql"))
        try await fileSystem.writeText("1.0.0", at: root.appending(component: "version.txt"))
    }

    private func fixtureInputs(root: AbsolutePath) -> [CodeGenerator.Input] {
        [
            .file(repositoryPath(root, "version.txt")),
            .folder(projectPath(root, "Schema")),
            .glob(repositoryPath(root, "Projects/**/*.graphql")),
            .script("echo fixed"),
        ]
    }

    private func projectPath(_ root: AbsolutePath, _ path: String) -> CodeGenerator.Path {
        CodeGenerator.Path(anchor: .project, anchorDirectory: root.appending(components: "Projects", "Core"), relativePath: path)
    }

    private func repositoryPath(_ root: AbsolutePath, _ path: String) -> CodeGenerator.Path {
        CodeGenerator.Path(anchor: .repository, anchorDirectory: root, relativePath: path)
    }

    private func action(
        root: AbsolutePath,
        name: String = "strings",
        script: String = "exit 0",
        targetName: String = "AccountUI",
        inputs: [CodeGenerator.Input] = [],
        environment: [String: String] = [:]
    ) -> CodeGeneratorAction {
        let generator = CodeGenerator(
            name: name,
            script: script,
            inputs: inputs,
            environment: environment,
            rootDirectory: root
        )
        return CodeGeneratorAction.actions(
            for: .test(name: targetName, codeGenerators: [generator]),
            projectPath: root.appending(components: "Projects", "Core")
        )[0]
    }

    private func codeGenerationTargetAction(root: AbsolutePath, inputs: [CodeGenerator.Input]) throws -> CodeGeneratorAction {
        let generator = CodeGenerator(
            name: "GQLCodegen",
            script: "exit 0",
            inputs: inputs,
            outputs: [
                CodeGenerator.Output(projectPath: root.appending(components: "Projects", "Core"), target: "GQLSchema"),
                CodeGenerator.Output(projectPath: root.appending(components: "Projects", "App"), target: "App"),
            ],
            rootDirectory: root
        )
        return try #require(CodeGeneratorAction.actions(
            for: .test(name: "GQLCodegen", codegen: generator),
            projectPath: root.appending(components: "Projects", "Core")
        ).first)
    }
}
