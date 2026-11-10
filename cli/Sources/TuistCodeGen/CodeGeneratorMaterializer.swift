import FileSystem
import Foundation
import Mockable
import Path
import TuistAlert
import TuistCore
import TuistHasher
import TuistLogging
import TuistProcess
import TuistSupport
import XcodeGraph

enum CodeGeneratorMaterializerError: FatalError, Equatable {
    case generatorFailed(generator: String, target: String, exitCode: Int32, standardOutput: String, standardError: String)

    var type: ErrorType { .abort }

    var description: String {
        switch self {
        case let .generatorFailed(generator, target, exitCode, standardOutput, standardError):
            (["The code generator '\(generator)' of target '\(target)' exited with status \(exitCode)."]
                + [standardOutput, standardError].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty })
                .joined(separator: "\n")
        }
    }
}

@Mockable
public protocol CodeGeneratorMaterializing {
    /// Runs the code generators of every target in the graph whose recorded action hash is out of date.
    func materialize(graph: Graph) async throws
}

/// Runs code generators and moves their output into place.
///
/// `generate`, `build`, and `test` run it on the graph left after focus, tree-shaking, and cache substitution, so a
/// pruned or cache-hit target never runs its generator; commands that only hash or inspect the graph never run it.
///
/// The recorded action hash is deleted before the output update and written after it, so a crash mid-update makes the
/// next run regenerate.
public struct CodeGeneratorMaterializer: CodeGeneratorMaterializing {
    static let stagingDirectoryName = ".staging"

    private let fileSystem: FileSysteming
    private let actionHasher: CodeGeneratorActionHashing
    private let inputResolver: CodeGeneratorInputResolving
    private let commandRunner: CommandRunning

    public init(
        fileSystem: FileSysteming = FileSystem(),
        actionHasher: CodeGeneratorActionHashing = CodeGeneratorActionHasher(contentHasher: ContentHasher()),
        inputResolver: CodeGeneratorInputResolving = CodeGeneratorInputResolver(),
        commandRunner: CommandRunning = CommandRunner()
    ) {
        self.fileSystem = fileSystem
        self.actionHasher = actionHasher
        self.inputResolver = inputResolver
        self.commandRunner = commandRunner
    }

    public func materialize(graph: Graph) async throws {
        let actions = graph.projects.sorted(by: { $0.key < $1.key }).flatMap { projectPath, project in
            project.targets.values.sorted().flatMap { CodeGeneratorAction.actions(for: $0, projectPath: projectPath) }
        }
        .filter { action in
            !action.isMultiTarget || action.outputs.contains { graph.projects[$0.projectPath]?.targets[$0.target] != nil }
        }
        guard !actions.isEmpty else { return }

        let projectPaths = Set(actions.flatMap { [$0.projectPath] + $0.outputs.map(\.projectPath) })
        for projectPath in projectPaths {
            try unlinkSymbolicLinks(through: stagingRoot(projectPath: projectPath), projectPath: projectPath)
        }
        try await remove(Set(projectPaths.map(stagingRoot)))
        for action in actions {
            try unlinkSymbolicLinks(through: action.statePath.parentDirectory, projectPath: action.projectPath)
            for output in action.outputs {
                try unlinkSymbolicLinks(through: output.directory, projectPath: output.projectPath)
            }
        }

        Logger.current.notice("Running code generators", metadata: .section)
        let skipped = try await actions.concurrentMap { action in
            try await materialize(action: action)
        }
        .filter { $0 == .upToDate }
        .count
        if skipped > 0 {
            Logger.current.notice("\(skipped) code generator\(skipped == 1 ? "" : "s") up to date")
        }
    }

    private enum CodeGeneratorRun {
        case ran, upToDate
    }

    private func materialize(action: CodeGeneratorAction) async throws -> CodeGeneratorRun {
        let hash = try await actionHasher.hash(action: action)
        if try await isUpToDate(action: action, hash: hash) {
            Logger.current.debug(
                "Skipping the code generator '\(action.generator.name)' of target '\(action.targetName)': its action hash is unchanged"
            )
            return .upToDate
        }

        let identifier = UUID().uuidString
        let workDirectory = stagingRoot(projectPath: action.projectPath).appending(component: identifier)
        let stagingDirectories = action.outputs.enumerated().map { index, output in
            stagingRoot(projectPath: output.projectPath).appending(components: identifier, "outputs", String(index))
        }
        let temporaryDirectories = Set(
            [workDirectory] + action.outputs.map { stagingRoot(projectPath: $0.projectPath).appending(component: identifier) }
        )
        do {
            try await run(
                action: action,
                hash: hash,
                workDirectory: workDirectory,
                stagingDirectories: stagingDirectories
            )
        } catch {
            try? await remove(temporaryDirectories)
            throw error
        }
        try await remove(temporaryDirectories)
        return .ran
    }

    // swiftlint:disable:next function_body_length
    private func run(
        action: CodeGeneratorAction,
        hash: String,
        workDirectory: AbsolutePath,
        stagingDirectories: [AbsolutePath]
    ) async throws {
        let label = "'\(action.generator.name)' of target '\(action.targetName)'"
        try await fileSystem.makeDirectory(at: workDirectory)
        for stagingDirectory in stagingDirectories {
            try await fileSystem.makeDirectory(at: stagingDirectory)
        }

        let resolvedInputs = try await inputResolver.resolve(action: action)
        for input in resolvedInputs where input.kind == .glob && input.files.isEmpty {
            AlertController.current.warning(.alert(
                "The glob input '\(input.declared.logicalPath)' of the code generator \(label) matched no files."
            ))
        }
        let inputsFile = workDirectory.appending(component: "inputs.json")
        try await writeJSON(
            resolvedInputs.flatMap(\.inputsFileEntries).map { ["type": $0.type, "path": $0.path.pathString] },
            at: inputsFile
        )
        var outputsFile: AbsolutePath?
        if action.isMultiTarget {
            let path = workDirectory.appending(component: "outputs.json")
            try await writeJSON(
                zip(action.outputs, stagingDirectories).map { output, stagingDirectory in
                    [
                        "project": action.logicalProjectPath(output.projectPath),
                        "target": output.target,
                        "path": stagingDirectory.pathString,
                    ]
                },
                at: path
            )
            outputsFile = path
        }

        Logger.current.notice("Running the code generator \(label)")
        let environment = CodeGeneratorEnvironment.generatorEnvironment(
            for: action,
            inputsFile: inputsFile,
            outputSourcesDirectory: action.isMultiTarget ? nil : stagingDirectories.first,
            outputsFile: outputsFile
        )
        var standardOutput = ""
        var standardError = ""
        do {
            for try await event in commandRunner.run(
                arguments: ["/bin/sh", "-c", action.generator.script],
                environment: environment,
                workingDirectory: action.projectPath
            ) {
                switch event.pipeline {
                case .standardOutput: standardOutput += event.string() ?? ""
                case .standardError: standardError += event.string() ?? ""
                }
            }
        } catch let CommandError.terminated(exitCode, _, _) {
            throw CodeGeneratorMaterializerError.generatorFailed(
                generator: action.generator.name,
                target: action.targetName,
                exitCode: exitCode,
                standardOutput: standardOutput,
                standardError: standardError
            )
        }
        if !standardOutput.isEmpty {
            Logger.current.debug("\(standardOutput)")
        }
        let trimmedStandardError = standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedStandardError.isEmpty {
            AlertController.current
                .warning(.alert("The code generator \(label) wrote to standard error:\n\(trimmedStandardError)"))
        }

        for (output, stagingDirectory) in zip(action.outputs, stagingDirectories) {
            guard try await fileSystem.contentsOfDirectory(stagingDirectory).isEmpty else { continue }
            AlertController.current.warning(.alert(
                "The code generator \(label) produced no files for target '\(output.target)'."
            ))
        }

        if try await fileSystem.exists(action.statePath) {
            try await fileSystem.remove(action.statePath)
        }
        for (output, stagingDirectory) in zip(action.outputs, stagingDirectories) {
            try await install(stagingDirectory, at: output.directory)
        }
        try await fileSystem.makeDirectory(at: action.statePath.parentDirectory)
        try await fileSystem.writeText(hash, at: action.statePath, encoding: .utf8, options: Set([.overwrite]))
    }

    private func install(_ stagingDirectory: AbsolutePath, at outputDirectory: AbsolutePath) async throws {
        if try await fileSystem.exists(outputDirectory, isDirectory: true) {
            try OutputDirectorySynchronizer().synchronize(outputDirectory, with: stagingDirectory)
            return
        }
        if try await fileSystem.exists(outputDirectory) {
            try await fileSystem.remove(outputDirectory)
        }
        try await fileSystem.makeDirectory(at: outputDirectory.parentDirectory)
        try await fileSystem.move(from: stagingDirectory, to: outputDirectory)
    }

    /// Unlinks every symbolic link from the project's code generation directory down to `directory`, so nothing is
    /// written or cleaned up through one.
    private func unlinkSymbolicLinks(through directory: AbsolutePath, projectPath: AbsolutePath) throws {
        var current = CodeGeneratorLayout.codeGenDirectory(projectPath: projectPath)
        var components = directory.relative(to: current).components.filter { $0 != "." }[...]
        while true {
            let attributes = try? FileManager.default.attributesOfItem(atPath: current.pathString)
            if attributes?[.type] as? FileAttributeType == .typeSymbolicLink {
                try FileManager.default.removeItem(atPath: current.pathString)
            }
            guard let component = components.popFirst() else { return }
            current = current.appending(component: component)
        }
    }

    private func remove(_ directories: Set<AbsolutePath>) async throws {
        for directory in directories {
            guard try await fileSystem.exists(directory) else { continue }
            try await fileSystem.remove(directory)
        }
    }

    private func isUpToDate(action: CodeGeneratorAction, hash: String) async throws -> Bool {
        guard try await fileSystem.exists(action.statePath),
              try await fileSystem.readTextFile(at: action.statePath) == hash
        else { return false }
        for output in action.outputs {
            guard try await fileSystem.exists(output.directory, isDirectory: true) else { return false }
        }
        return true
    }

    private func stagingRoot(projectPath: AbsolutePath) -> AbsolutePath {
        CodeGeneratorLayout.codeGenDirectory(projectPath: projectPath).appending(component: Self.stagingDirectoryName)
    }

    private func writeJSON(_ value: [[String: String]], at path: AbsolutePath) async throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        try await fileSystem.writeText(
            String(bytes: data, encoding: .utf8) ?? "",
            at: path,
            encoding: .utf8,
            options: Set([.overwrite])
        )
    }
}
