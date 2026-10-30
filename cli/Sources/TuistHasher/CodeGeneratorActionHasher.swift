import Foundation
import Mockable
import Path
import TuistCore
import TuistProcess
import TuistSupport
import XcodeGraph

@Mockable
public protocol CodeGeneratorActionHashing: Sendable {
    /// Returns the hash of an action's declaration and the contents of its inputs.
    func hash(action: CodeGeneratorAction) async throws -> String
}

/// Hashes a code generator's declaration, never its output.
///
/// The hash covers, per input, the kind plus:
///
/// - `.file`: the logical path and contents.
/// - `.folder`: the logical path, and the relative paths and contents of the whole tree.
/// - `.glob`: the unexpanded pattern, and the logical path and contents of each match.
/// - `.script`: standard output.
///
/// and per action the command, the generator's name, the declaring target's identity, the declared environment, and
/// for a multi-target generator its outputs. Logical paths are relative to the repository root or the manifest's
/// directory, so two checkouts at different paths agree.
public struct CodeGeneratorActionHasher: CodeGeneratorActionHashing {
    private static let version = "1"

    private let contentHasher: ContentHashing
    private let inputResolver: CodeGeneratorInputResolving
    private let commandRunner: CommandRunning

    public init(
        contentHasher: ContentHashing,
        inputResolver: CodeGeneratorInputResolving = CodeGeneratorInputResolver(),
        commandRunner: CommandRunning = CommandRunner()
    ) {
        self.contentHasher = contentHasher
        self.inputResolver = inputResolver
        self.commandRunner = commandRunner
    }

    public func hash(action: CodeGeneratorAction) async throws -> String {
        let generator = action.generator
        var components = [
            "codegen-v\(Self.version)",
            "kind:\(action.isMultiTarget ? "multi-target" : "per-target")",
            "target:\(action.logicalProjectPath(action.projectPath)):\(action.targetName)",
            "name:\(generator.name)",
            "command:\(try contentHasher.hash(generator.script))",
            "environment:\(try contentHasher.hash(generator.environment))",
        ]
        if action.isMultiTarget {
            components += action.outputs.map { "output:\(action.logicalProjectPath($0.projectPath)):\($0.target)" }
        }

        var resolvedInputs = try await inputResolver.resolve(action: action).makeIterator()
        for input in generator.inputs {
            switch input {
            case let .script(script):
                let output = try await commandRunner.runAndCollectOutput(
                    arguments: ["/bin/sh", "-c", script],
                    environment: CodeGeneratorEnvironment.scriptInputEnvironment(for: action),
                    workingDirectory: action.projectPath
                )
                components.append("script:\(try contentHasher.hash(output.standardOutput))")
            case .file, .folder, .glob:
                guard let resolved = resolvedInputs.next() else { continue }
                components.append("\(resolved.kind.rawValue):\(resolved.declared.logicalPath)")
                for file in resolved.files {
                    let contentHash = try await contentHasher.hash(path: file.path)
                    components.append("entry:\(file.logicalPath):\(contentHash)")
                }
            }
        }

        return try contentHasher.hash(components)
    }
}
