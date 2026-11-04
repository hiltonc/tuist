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

/// Hashes paths by their logical form, so two checkouts at different paths agree.
///
/// Inside ``CodeGeneratorScriptInputCache/scoped(_:)``, each distinct `.script` input runs once.
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
                let output = try await scriptInputOutput(script, generator: generator)
                components.append("script:\(try contentHasher.hash(output))")
            case .file, .folder, .glob:
                guard let resolved = resolvedInputs.next() else { continue }
                components.append("\(resolved.kind.rawValue):\(resolved.declared.logicalPath)")
                components += try await resolved.files.concurrentMap { file in
                    "entry:\(file.logicalPath):\(try await contentHasher.hash(path: file.path))"
                }
            }
        }

        return try contentHasher.hash(components)
    }

    private func scriptInputOutput(_ script: String, generator: CodeGenerator) async throws -> String {
        let environment = CodeGeneratorEnvironment.scriptInputEnvironment(for: generator)
        let rootDirectory = generator.rootDirectory
        let run = { @Sendable [commandRunner] in
            try await commandRunner.runAndCollectOutput(
                arguments: ["/bin/sh", "-c", script],
                environment: environment,
                workingDirectory: rootDirectory
            ).standardOutput
        }
        guard let cache = CodeGeneratorScriptInputCache.current else { return try await run() }
        return try await cache.output(
            for: .init(script: script, environment: generator.environment, rootDirectory: rootDirectory),
            run: run
        )
    }
}
