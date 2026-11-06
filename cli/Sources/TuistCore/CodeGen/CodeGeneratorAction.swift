import Path
import TuistConstants
import XcodeGraph

/// One run of a code generator: the declaration, the target that owns it, and the output directories it writes.
///
/// A per-target generator writes one directory, attached to its own target. A code generation target writes one
/// directory per consumer, each inside the consumer's project. One action hash covers every output, so an action is
/// either skipped or run as a whole.
public struct CodeGeneratorAction: Equatable, Hashable, Sendable {
    /// A directory the action writes and the target it's attached to.
    public struct Output: Equatable, Hashable, Sendable {
        public let projectPath: AbsolutePath
        public let target: String
        public let directory: AbsolutePath

        public init(projectPath: AbsolutePath, target: String, directory: AbsolutePath) {
            self.projectPath = projectPath
            self.target = target
            self.directory = directory
        }
    }

    public let generator: CodeGenerator

    /// The directory of the project declaring the generator.
    public let projectPath: AbsolutePath

    /// The target declaring the generator: its owner, or the code generation target itself.
    public let targetName: String

    /// Whether the generator belongs to a code generation target.
    public let isMultiTarget: Bool

    public let outputs: [Output]

    /// Where the action hash of the last successful run is recorded, outside every output directory.
    public let statePath: AbsolutePath

    public init(
        generator: CodeGenerator,
        projectPath: AbsolutePath,
        targetName: String,
        isMultiTarget: Bool,
        outputs: [Output],
        statePath: AbsolutePath
    ) {
        self.generator = generator
        self.projectPath = projectPath
        self.targetName = targetName
        self.isMultiTarget = isMultiTarget
        self.outputs = outputs
        self.statePath = statePath
    }

    /// The actions a target declares: one per entry in `codeGenerators`, plus its own when it's a code generation
    /// target.
    public static func actions(for target: Target, projectPath: AbsolutePath) -> [CodeGeneratorAction] {
        var actions = target.codeGenerators.map { generator in
            CodeGeneratorAction(
                generator: generator,
                projectPath: projectPath,
                targetName: target.name,
                isMultiTarget: false,
                outputs: [
                    Output(
                        projectPath: projectPath,
                        target: target.name,
                        directory: CodeGeneratorLayout.targetOutputDirectory(
                            projectPath: projectPath,
                            target: target.name,
                            generator: generator.name
                        )
                    ),
                ],
                statePath: CodeGeneratorLayout.targetStatePath(
                    projectPath: projectPath,
                    target: target.name,
                    generator: generator.name
                )
            )
        }
        if let codegen = target.codegen {
            actions.append(CodeGeneratorAction(
                generator: codegen,
                projectPath: projectPath,
                targetName: target.name,
                isMultiTarget: true,
                outputs: codegen.outputs.map { output in
                    Output(
                        projectPath: output.projectPath,
                        target: output.target,
                        directory: CodeGeneratorLayout.producerOutputDirectory(
                            consumerProjectPath: output.projectPath,
                            producer: target.name,
                            consumer: output.target
                        )
                    )
                },
                statePath: CodeGeneratorLayout.producerStatePath(projectPath: projectPath, producer: target.name)
            ))
        }
        return actions
    }

    /// The machine-independent identity of a project: its directory relative to the repository root, `//`-prefixed.
    public func logicalProjectPath(_ projectPath: AbsolutePath) -> String {
        "//\(projectPath.relative(to: generator.rootDirectory).pathString)"
    }
}

/// Where code generators write, under each project's `Derived/CodeGen`.
///
/// No path here appears in a manifest. Each is a function of target and generator names, which are validated as
/// path components.
public enum CodeGeneratorLayout {
    public static let directoryName = Constants.DerivedDirectory.codeGen
    public static let targetsDirectoryName = "Targets"
    public static let producersDirectoryName = "Producers"
    public static let stateDirectoryName = "State"
    public static let sourcesDirectoryName = "Sources"

    public static func codeGenDirectory(projectPath: AbsolutePath) -> AbsolutePath {
        projectPath.appending(components: Constants.DerivedDirectory.name, directoryName)
    }

    /// `Derived/CodeGen/Targets/{target}/{generator}/Sources` in the owning project.
    public static func targetOutputDirectory(projectPath: AbsolutePath, target: String, generator: String) -> AbsolutePath {
        codeGenDirectory(projectPath: projectPath)
            .appending(components: targetsDirectoryName, target, generator, sourcesDirectoryName)
    }

    /// `Derived/CodeGen/Producers/{producer}/{consumer}/Sources` in the consumer's project.
    public static func producerOutputDirectory(
        consumerProjectPath: AbsolutePath,
        producer: String,
        consumer: String
    ) -> AbsolutePath {
        codeGenDirectory(projectPath: consumerProjectPath)
            .appending(components: producersDirectoryName, producer, consumer, sourcesDirectoryName)
    }

    /// `Derived/CodeGen/State/Targets/{target}/{generator}` in the owning project.
    public static func targetStatePath(projectPath: AbsolutePath, target: String, generator: String) -> AbsolutePath {
        codeGenDirectory(projectPath: projectPath)
            .appending(components: stateDirectoryName, targetsDirectoryName, target, generator)
    }

    /// `Derived/CodeGen/State/Producers/{producer}` in the producer's project.
    public static func producerStatePath(projectPath: AbsolutePath, producer: String) -> AbsolutePath {
        codeGenDirectory(projectPath: projectPath)
            .appending(components: stateDirectoryName, producersDirectoryName, producer)
    }
}
