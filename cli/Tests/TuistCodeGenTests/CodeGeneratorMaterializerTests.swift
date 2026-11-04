import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistAlert
import TuistCore
import TuistHasher
import TuistLoggerTesting
import TuistLogging
import TuistTesting
import XcodeGraph
@testable import TuistCodeGen

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
        #expect(!Logger.testingLogHandler.collected[.notice, ==].contains("up to date"))
        try await subject.materialize(graph: graph)
        #expect(try await runs(counter) == 1)
        #expect(Logger.testingLogHandler.collected[.notice, ==].contains("1 code generator up to date"))

        try await fileSystem.writeText(
            #"{"key": "changed"}"#,
            at: project.appending(components: "Strings", "en.json"),
            options: Set([.overwrite])
        )
        try await subject.materialize(graph: graph)
        #expect(try await runs(counter) == 2)
    }

    @Test(.inTemporaryDirectory, .withMockedLogger())
    func materialize_summarizes_skipped_generators_in_one_notice() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let project = try await makeProject(root: root)
        let generators = ["first", "second"].map { name in
            CodeGenerator(name: name, script: #"touch "$TUIST_OUTPUT_SOURCES_DIR/A.swift""#, inputs: [], rootDirectory: root)
        }
        let graph = graph(project: project, codeGenerators: generators)
        try await subject.materialize(graph: graph)

        try await subject.materialize(graph: graph)

        let notices = Logger.testingLogHandler.collected[.notice, ==]
        #expect(notices.contains("2 code generators up to date"))
        #expect(!notices.contains("Skipping"))
    }

    @Test(.inTemporaryDirectory, .withMockedLogger())
    func materialize_leaves_no_recorded_hash_when_the_swap_fails_partway() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let project = try await makeProject(root: root)
        let counter = root.appending(component: "runs")
        let graph = codeGenerationTargetGraph(project: project, root: root, script: """
        echo run >> "\(counter.pathString)"
        /usr/bin/python3 -c '
        import json, os
        for output in json.load(open(os.environ["TUIST_OUTPUTS_FILE"])):
            open(os.path.join(output["path"], "Generated.swift"), "w").write("")
        '
        """)
        try await subject.materialize(graph: graph)
        try await fileSystem.writeText(
            #"{"key": "changed"}"#,
            at: project.appending(components: "Strings", "en.json"),
            options: Set([.overwrite])
        )
        let secondOutputParent = producerOutputDirectory(project: project, consumer: "GQLTypes").parentDirectory
        try await fileSystem.remove(secondOutputParent)
        try await fileSystem.writeText("", at: secondOutputParent)

        await #expect(throws: (any Error).self) { try await subject.materialize(graph: graph) }

        #expect(try await fileSystem.exists(producerOutputDirectory(project: project, consumer: "GQLSchema")))
        #expect(try await !fileSystem.exists(CodeGeneratorLayout.producerStatePath(projectPath: project, producer: "GQLCodegen")))
        try await fileSystem.remove(secondOutputParent)
        try await subject.materialize(graph: graph)
        #expect(try await runs(counter) == 3)
        #expect(try await fileSystem.exists(CodeGeneratorLayout.producerStatePath(projectPath: project, producer: "GQLCodegen")))
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
            standardOutput: "",
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

    @Test(.inTemporaryDirectory, .withMockedLogger())
    func materialize_runs_a_code_generation_target_when_some_of_its_consumers_were_pruned() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let project = try await makeProject(root: root)
        let marker = root.appending(component: "ran")
        var graph = codeGenerationTargetGraph(project: project, root: root, script: "touch \"\(marker.pathString)\"")
        graph.projects[project]?.targets["GQLTypes"] = nil

        try await subject.materialize(graph: graph)

        #expect(try await fileSystem.exists(marker))
    }

    @Test(.inTemporaryDirectory, .withMockedLogger(), .withScopedAlertController())
    func materialize_warns_about_empty_globs_empty_output_and_standard_error() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let project = try await makeProject(root: root)
        let generator = CodeGenerator(
            name: "strings",
            script: "echo careful >&2",
            inputs: [.glob(CodeGenerator.Path(anchor: .project, anchorDirectory: project, relativePath: "Strings/*.yml"))],
            rootDirectory: root
        )

        try await subject.materialize(graph: graph(project: project, codeGenerators: [generator]))

        let warnings = AlertController.current.warnings().map(\.message).map { $0.plain() }
        #expect(warnings == [
            "The glob input 'Strings/*.yml' of the code generator 'strings' of target 'AccountUI' matched no files.",
            "The code generator 'strings' of target 'AccountUI' wrote to standard error:\ncareful",
            "The code generator 'strings' of target 'AccountUI' produced no files for target 'AccountUI'.",
        ])
    }

    @Test(.inTemporaryDirectory, .withMockedLogger())
    func materialize_reports_standard_output_and_error_when_the_generator_fails() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let project = try await makeProject(root: root)
        let generator = perTargetGenerator(root: root, script: """
        echo "schema.graphqls:3: unknown type"
        echo "boom" >&2
        exit 1
        """)

        await #expect(throws: CodeGeneratorMaterializerError.generatorFailed(
            generator: "strings",
            target: "AccountUI",
            exitCode: 1,
            standardOutput: "schema.graphqls:3: unknown type\n",
            standardError: "boom\n"
        )) {
            try await subject.materialize(graph: graph(project: project, codeGenerators: [generator]))
        }
    }

    @Test(.inTemporaryDirectory, .withMockedLogger())
    func materialize_leaves_every_file_in_place_when_a_rerun_produces_identical_output() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let project = try await makeProject(root: root)
        let counter = root.appending(component: "runs")
        let generator = perTargetGenerator(root: root, script: """
        echo run >> "\(counter.pathString)"
        mkdir -p "$TUIST_OUTPUT_SOURCES_DIR/Nested"
        echo "let a = 1" > "$TUIST_OUTPUT_SOURCES_DIR/A.swift"
        echo "let b = 1" > "$TUIST_OUTPUT_SOURCES_DIR/Nested/B.swift"
        """)
        let graph = graph(project: project, codeGenerators: [generator])
        try await subject.materialize(graph: graph)
        let output = outputDirectory(project: project, generator: generator)
        let files = [output.appending(component: "A.swift"), output.appending(components: "Nested", "B.swift")]
        let before = try files.map(identity)

        try await fileSystem.writeText(
            #"{"key": "changed"}"#,
            at: project.appending(components: "Strings", "en.json"),
            options: Set([.overwrite])
        )
        try await subject.materialize(graph: graph)

        #expect(try await runs(counter) == 2)
        #expect(try files.map(identity) == before)
    }

    @Test(.inTemporaryDirectory, .withMockedLogger())
    func materialize_replaces_changed_files_adds_new_ones_and_removes_stale_ones_without_touching_unchanged_ones(
    ) async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let project = try await makeProject(root: root)
        let strings = project.appending(components: "Strings", "en.json")
        let generator = perTargetGenerator(root: root, script: """
        echo "let same = 1" > "$TUIST_OUTPUT_SOURCES_DIR/Same.swift"
        cp Strings/en.json "$TUIST_OUTPUT_SOURCES_DIR/Changed.swift"
        if grep -q value Strings/en.json; then
            touch "$TUIST_OUTPUT_SOURCES_DIR/Stale.swift"
            mkdir -p "$TUIST_OUTPUT_SOURCES_DIR/StaleFolder"
            touch "$TUIST_OUTPUT_SOURCES_DIR/StaleFolder/Inner.swift"
        else
            touch "$TUIST_OUTPUT_SOURCES_DIR/New.swift"
        fi
        """)
        let graph = graph(project: project, codeGenerators: [generator])
        try await subject.materialize(graph: graph)
        let output = outputDirectory(project: project, generator: generator)
        let same = try identity(output.appending(component: "Same.swift"))
        let changed = try identity(output.appending(component: "Changed.swift"))

        try await fileSystem.writeText(#"{"key": "edited"}"#, at: strings, options: Set([.overwrite]))
        try await subject.materialize(graph: graph)

        #expect(try await fileSystem.contentsOfDirectory(output).map(\.basename).sorted() == [
            "Changed.swift", "New.swift", "Same.swift",
        ])
        #expect(try identity(output.appending(component: "Same.swift")) == same)
        #expect(try identity(output.appending(component: "Changed.swift")).inode != changed.inode)
        #expect(try await fileSystem.readTextFile(at: output.appending(component: "Changed.swift")) == #"{"key": "edited"}"#)
        let staging = CodeGeneratorLayout.codeGenDirectory(projectPath: project)
            .appending(component: CodeGeneratorMaterializer.stagingDirectoryName)
        #expect(try await fileSystem.contentsOfDirectory(staging).isEmpty)
    }

    @Test(.inTemporaryDirectory, .withMockedLogger())
    func materialize_replaces_a_file_whose_permissions_changed() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let project = try await makeProject(root: root)
        let generator = perTargetGenerator(root: root, script: """
        echo "#!/bin/sh" > "$TUIST_OUTPUT_SOURCES_DIR/tool.sh"
        if grep -q edited Strings/en.json; then chmod +x "$TUIST_OUTPUT_SOURCES_DIR/tool.sh"; fi
        """)
        let graph = graph(project: project, codeGenerators: [generator])
        try await subject.materialize(graph: graph)
        let tool = outputDirectory(project: project, generator: generator).appending(component: "tool.sh")

        try await fileSystem.writeText(
            #"{"key": "edited"}"#,
            at: project.appending(components: "Strings", "en.json"),
            options: Set([.overwrite])
        )
        try await subject.materialize(graph: graph)

        #expect(FileManager.default.isExecutableFile(atPath: tool.pathString))
    }

    @Test(.inTemporaryDirectory, .withMockedLogger())
    func materialize_leaves_an_unchanged_consumer_share_of_a_code_generation_target_in_place() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let project = try await makeProject(root: root)
        let graph = codeGenerationTargetGraph(project: project, root: root, script: """
        /usr/bin/python3 -c '
        import json, os
        strings = open("Strings/en.json").read()
        for output in json.load(open(os.environ["TUIST_OUTPUTS_FILE"])):
            contents = strings if output["target"] == "GQLTypes" else "let schema = 1"
            open(os.path.join(output["path"], "Generated.swift"), "w").write(contents)
        '
        """)
        try await subject.materialize(graph: graph)
        let schema = producerOutputDirectory(project: project, consumer: "GQLSchema").appending(component: "Generated.swift")
        let types = producerOutputDirectory(project: project, consumer: "GQLTypes").appending(component: "Generated.swift")
        let schemaBefore = try identity(schema)
        let typesBefore = try identity(types)

        try await fileSystem.writeText(
            #"{"key": "edited"}"#,
            at: project.appending(components: "Strings", "en.json"),
            options: Set([.overwrite])
        )
        try await subject.materialize(graph: graph)

        #expect(try identity(schema) == schemaBefore)
        #expect(try identity(types).inode != typesBefore.inode)
        #expect(try await fileSystem.readTextFile(at: types) == #"{"key": "edited"}"#)
    }

    // MARK: - Helpers

    private struct FileIdentity: Equatable {
        let inode: Int
        let modificationDate: Date
    }

    private func identity(_ path: AbsolutePath) throws -> FileIdentity {
        let attributes = try FileManager.default.attributesOfItem(atPath: path.pathString)
        return FileIdentity(
            inode: try #require(attributes[.systemFileNumber] as? Int),
            modificationDate: try #require(attributes[.modificationDate] as? Date)
        )
    }

    private func codeGenerationTargetGraph(project: AbsolutePath, root: AbsolutePath, script: String) -> Graph {
        let codegen = CodeGenerator(
            name: "GQLCodegen",
            script: script,
            inputs: [.file(CodeGenerator.Path(anchor: .project, anchorDirectory: project, relativePath: "Strings/en.json"))],
            outputs: [
                CodeGenerator.Output(projectPath: project, target: "GQLSchema"),
                CodeGenerator.Output(projectPath: project, target: "GQLTypes"),
            ],
            rootDirectory: root
        )
        return .test(projects: [
            project: .test(path: project, targets: [
                .test(name: "GQLCodegen", product: .staticLibrary, codegen: codegen),
                .test(name: "GQLSchema", product: .staticFramework),
                .test(name: "GQLTypes", product: .staticFramework),
            ]),
        ])
    }

    private func producerOutputDirectory(project: AbsolutePath, consumer: String) -> AbsolutePath {
        CodeGeneratorLayout.producerOutputDirectory(consumerProjectPath: project, producer: "GQLCodegen", consumer: consumer)
    }

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
