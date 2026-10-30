import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistCore
import TuistHasher
import TuistTesting
import XcodeGraph
@testable import TuistKit

struct CodeGeneratorMaterializerTests {
    private let fileSystem = FileSystem()
    private let subject = CodeGeneratorMaterializer()

    @Test(.inTemporaryDirectory, .withMockedLogger())
    func materialize_runs_a_per_target_generator_with_the_environment_contract() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let project = try await makeProject(root: root)
        let generator = perTargetGenerator(root: root, script: """
        echo "$TUIST_TARGET_NAME $TUIST_PROJECT_DIR $TUIST_ROOT_DIR $ACCESS" > "$TUIST_OUTPUT_SOURCES_DIR/Env.swift"
        cp "$TUIST_INPUTS_FILE" "$TUIST_OUTPUT_SOURCES_DIR/inputs.json"
        """)

        try await subject.materialize(graph: graph(project: project, codeGenerators: [generator]))

        let output = outputDirectory(project: project, generator: generator)
        let environment = try await fileSystem.readTextFile(at: output.appending(component: "Env.swift"))
        #expect(environment.trimmingCharacters(in: .newlines) == "AccountUI \(project.pathString) \(root.pathString) public")
        let inputs = try JSONSerialization.jsonObject(
            with: try await fileSystem.readFile(at: output.appending(component: "inputs.json"))
        ) as? [[String: String]]
        #expect(inputs == [
            ["type": "file", "path": project.appending(components: "Strings", "en.json").pathString],
            ["type": "folder", "path": project.appending(component: "Resources").pathString],
        ])
        #expect(try await fileSystem.exists(stateFile(project: project, generator: generator)))
    }

    @Test(.inTemporaryDirectory, .withMockedLogger())
    func materialize_skips_a_generator_whose_action_hash_is_unchanged() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let project = try await makeProject(root: root)
        let counter = root.appending(component: "runs")
        let generator = perTargetGenerator(root: root, script: """
        echo run >> "\(counter.pathString)"
        echo "let a = 1" > "$TUIST_OUTPUT_SOURCES_DIR/A.swift"
        """)
        let graph = graph(project: project, codeGenerators: [generator])

        try await subject.materialize(graph: graph)
        try await subject.materialize(graph: graph)
        #expect(try await runs(counter) == 1)

        try await fileSystem.writeText(
            #"{"key": "changed"}"#,
            at: project.appending(components: "Strings", "en.json"),
            options: Set([.overwrite])
        )
        try await subject.materialize(graph: graph)
        #expect(try await runs(counter) == 2)
    }

    @Test(.inTemporaryDirectory, .withMockedLogger())
    func materialize_regenerates_when_a_crash_left_no_recorded_hash() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let project = try await makeProject(root: root)
        let counter = root.appending(component: "runs")
        let generator = perTargetGenerator(root: root, script: """
        echo run >> "\(counter.pathString)"
        echo "let a = 1" > "$TUIST_OUTPUT_SOURCES_DIR/A.swift"
        """)
        let graph = graph(project: project, codeGenerators: [generator])
        try await subject.materialize(graph: graph)

        // A crash between deleting the recorded hash and writing the new one leaves the output without a hash.
        try await fileSystem.remove(stateFile(project: project, generator: generator))
        try await subject.materialize(graph: graph)

        #expect(try await runs(counter) == 2)
    }

    @Test(.inTemporaryDirectory, .withMockedLogger())
    func materialize_regenerates_when_an_output_directory_is_missing() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let project = try await makeProject(root: root)
        let counter = root.appending(component: "runs")
        let generator = perTargetGenerator(root: root, script: """
        echo run >> "\(counter.pathString)"
        echo "let a = 1" > "$TUIST_OUTPUT_SOURCES_DIR/A.swift"
        """)
        let graph = graph(project: project, codeGenerators: [generator])
        try await subject.materialize(graph: graph)

        try await fileSystem.remove(outputDirectory(project: project, generator: generator))
        try await subject.materialize(graph: graph)

        #expect(try await runs(counter) == 2)
        #expect(try await fileSystem
            .exists(outputDirectory(project: project, generator: generator).appending(component: "A.swift")))
    }

    @Test(.inTemporaryDirectory, .withMockedLogger())
    func materialize_replaces_the_output_so_files_no_longer_produced_disappear() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let project = try await makeProject(root: root)
        let first = perTargetGenerator(root: root, script: #"touch "$TUIST_OUTPUT_SOURCES_DIR/Old.swift""#)
        try await subject.materialize(graph: graph(project: project, codeGenerators: [first]))

        let second = perTargetGenerator(root: root, script: #"touch "$TUIST_OUTPUT_SOURCES_DIR/New.swift""#)
        try await subject.materialize(graph: graph(project: project, codeGenerators: [second]))

        let output = outputDirectory(project: project, generator: second)
        #expect(try await fileSystem.contentsOfDirectory(output).map(\.basename) == ["New.swift"])
    }

    @Test(.inTemporaryDirectory, .withMockedLogger())
    func materialize_keeps_the_previous_output_when_the_generator_fails() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let project = try await makeProject(root: root)
        let succeeding = perTargetGenerator(root: root, script: #"touch "$TUIST_OUTPUT_SOURCES_DIR/Good.swift""#)
        try await subject.materialize(graph: graph(project: project, codeGenerators: [succeeding]))
        let recordedHash = try await fileSystem.readTextFile(at: stateFile(project: project, generator: succeeding))

        let failing = perTargetGenerator(root: root, script: """
        touch "$TUIST_OUTPUT_SOURCES_DIR/Partial.swift"
        echo "boom" >&2
        exit 3
        """)
        await #expect(throws: CodeGeneratorMaterializerError.generatorFailed(
            generator: "strings",
            target: "AccountUI",
            exitCode: 3,
            standardError: "boom\n"
        )) {
            try await subject.materialize(graph: graph(project: project, codeGenerators: [failing]))
        }

        let output = outputDirectory(project: project, generator: failing)
        #expect(try await fileSystem.contentsOfDirectory(output).map(\.basename) == ["Good.swift"])
        #expect(try await fileSystem.readTextFile(at: stateFile(project: project, generator: failing)) == recordedHash)
        let staging = CodeGeneratorLayout.codeGenDirectory(projectPath: project)
            .appending(component: CodeGeneratorMaterializer.stagingDirectoryName)
        #expect(try await fileSystem.contentsOfDirectory(staging).isEmpty)
    }

    @Test(.inTemporaryDirectory, .withMockedLogger())
    func materialize_writes_every_output_of_a_multi_target_generator() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let project = try await makeProject(root: root)
        let codegen = CodeGenerator(
            name: "GQLCodegen",
            script: """
            /usr/bin/python3 -c '
            import json, os, sys
            for output in json.load(open(os.environ["TUIST_OUTPUTS_FILE"])):
                open(os.path.join(output["path"], output["target"] + ".swift"), "w").write(output["project"])
            '
            """,
            inputs: [],
            outputs: [
                CodeGenerator.Output(projectPath: project, target: "GQLSchema"),
                CodeGenerator.Output(projectPath: project, target: "GQLTypes"),
            ],
            rootDirectory: root
        )
        let graph = Graph.test(projects: [
            project: .test(path: project, targets: [
                .test(name: "GQLCodegen", product: .staticLibrary, codegen: codegen),
                .test(name: "GQLSchema", product: .staticFramework),
                .test(name: "GQLTypes", product: .staticFramework),
            ]),
        ])

        try await subject.materialize(graph: graph)

        for consumer in ["GQLSchema", "GQLTypes"] {
            let file = CodeGeneratorLayout.producerOutputDirectory(
                consumerProjectPath: project,
                producer: "GQLCodegen",
                consumer: consumer
            ).appending(component: "\(consumer).swift")
            #expect(try await fileSystem.readTextFile(at: file) == "//Projects/DesignSystem")
        }
        #expect(try await fileSystem.exists(CodeGeneratorLayout.producerStatePath(projectPath: project, producer: "GQLCodegen")))
    }

    @Test(.inTemporaryDirectory, .withMockedLogger())
    func materialize_skips_a_multi_target_generator_whose_consumers_were_all_pruned() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let project = try await makeProject(root: root)
        let marker = root.appending(component: "ran")
        let codegen = CodeGenerator(
            name: "GQLCodegen",
            script: "touch \"\(marker.pathString)\"",
            inputs: [],
            outputs: [CodeGenerator.Output(projectPath: project, target: "GQLSchema")],
            rootDirectory: root
        )
        let graph = Graph.test(projects: [
            project: .test(path: project, targets: [.test(name: "GQLCodegen", product: .staticLibrary, codegen: codegen)]),
        ])

        try await subject.materialize(graph: graph)

        #expect(try await !fileSystem.exists(marker))
    }

    // MARK: - Helpers

    private func makeProject(root: AbsolutePath) async throws -> AbsolutePath {
        let project = root.appending(components: "Projects", "DesignSystem")
        try await fileSystem.makeDirectory(at: project.appending(component: "Strings"))
        try await fileSystem.makeDirectory(at: project.appending(component: "Resources"))
        try await fileSystem.writeText(#"{"key": "value"}"#, at: project.appending(components: "Strings", "en.json"))
        return project
    }

    private func perTargetGenerator(root: AbsolutePath, script: String) -> CodeGenerator {
        let project = root.appending(components: "Projects", "DesignSystem")
        return CodeGenerator(
            name: "strings",
            script: script,
            inputs: [
                .file(CodeGenerator.Path(anchor: .project, anchorDirectory: project, relativePath: "Strings/en.json")),
                .folder(CodeGenerator.Path(anchor: .project, anchorDirectory: project, relativePath: "Resources")),
                .script("echo 1.0.0"),
            ],
            environment: ["ACCESS": "public"],
            rootDirectory: root
        )
    }

    private func graph(project: AbsolutePath, codeGenerators: [CodeGenerator]) -> Graph {
        .test(projects: [
            project: .test(path: project, targets: [
                .test(name: "AccountUI", product: .staticFramework, codeGenerators: codeGenerators),
            ]),
        ])
    }

    private func outputDirectory(project: AbsolutePath, generator: CodeGenerator) -> AbsolutePath {
        CodeGeneratorLayout.targetOutputDirectory(projectPath: project, target: "AccountUI", generator: generator.name)
    }

    private func stateFile(project: AbsolutePath, generator: CodeGenerator) -> AbsolutePath {
        CodeGeneratorLayout.targetStatePath(projectPath: project, target: "AccountUI", generator: generator.name)
    }

    private func runs(_ counter: AbsolutePath) async throws -> Int {
        try await fileSystem.readTextFile(at: counter).split(separator: "\n").count
    }
}
