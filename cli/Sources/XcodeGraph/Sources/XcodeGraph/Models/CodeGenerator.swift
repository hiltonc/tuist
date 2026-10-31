import Path

/// A command that produces source files for one or more targets from a declared set of inputs.
///
/// A generator declared in a target's `codeGenerators` produces sources for that target. A generator held by a
/// code generation target (``Target/codegen``) produces sources for every target in ``outputs``.
///
/// Tuist never hashes generated output. The declaration itself, with the logical paths and contents of its
/// inputs, contributes to the owning target's content hash, so a hash can be computed without running the command.
public struct CodeGenerator: Equatable, Hashable, Codable, Sendable {
    /// The generator's name. Unique within its target, and a component of its output directory.
    public let name: String

    /// The shell script that runs the generator.
    public let script: String

    /// The inputs the generator's output depends on.
    public let inputs: [Input]

    /// Environment variables the generator's output depends on. They're added to the inherited environment and
    /// contribute to the action hash.
    public let environment: [String: String]

    /// The targets a code generation target produces sources for. Empty for a per-target generator.
    public let outputs: [Output]

    /// The repository root, which `//` input paths and logical identities are relative to.
    public let rootDirectory: AbsolutePath

    public init(
        name: String,
        script: String,
        inputs: [Input],
        environment: [String: String] = [:],
        outputs: [Output] = [],
        rootDirectory: AbsolutePath
    ) {
        self.name = name
        self.script = script
        self.inputs = inputs
        self.environment = environment
        self.outputs = outputs
        self.rootDirectory = rootDirectory
    }

    /// An input that affects a generator's output.
    public enum Input: Equatable, Hashable, Codable, Sendable {
        /// A file, hashed by its logical path and contents.
        case file(Path)

        /// A folder, hashed by its logical path and the relative paths and contents of its whole tree.
        case folder(Path)

        /// A glob pattern, kept unexpanded. Hashed by the pattern and the logical path and contents of each match.
        case glob(Path)

        /// A shell script whose standard output contributes to the hash.
        case script(String)
    }

    /// A path as the manifest declared it, kept relative to the directory it's anchored to.
    public struct Path: Equatable, Hashable, Codable, Sendable {
        /// The directory a declared path is relative to.
        public enum Anchor: String, Equatable, Hashable, Codable, Sendable {
            /// The directory containing the manifest that declares the generator.
            case project
            /// The repository root, written with a `//` prefix.
            case repository
            /// The file system root, for a path outside the repository.
            case absolute
        }

        public let anchor: Anchor

        /// The absolute path of the anchor directory.
        public let anchorDirectory: AbsolutePath

        /// The path relative to ``anchorDirectory``. For a glob, the unexpanded pattern.
        public let relativePath: String

        public init(anchor: Anchor, anchorDirectory: AbsolutePath, relativePath: String) {
            self.anchor = anchor
            self.anchorDirectory = anchorDirectory
            self.relativePath = relativePath
        }

        /// The resolved absolute path. For a glob, the absolute pattern.
        public var absolutePath: AbsolutePath {
            get throws {
                try AbsolutePath(validating: relativePath, relativeTo: anchorDirectory)
            }
        }

        /// The path as the manifest names it, which is machine-independent: `//` and the path relative to the
        /// repository root, the path relative to the manifest's directory, or an absolute path outside the repository.
        public var logicalPath: String {
            logicalPath(of: relativePath)
        }

        /// The logical path of `path`, such as a glob match, under the same anchor.
        public func logicalPath(of path: AbsolutePath) -> String {
            logicalPath(of: path.relative(to: anchorDirectory).pathString)
        }

        private func logicalPath(of relativePath: String) -> String {
            switch anchor {
            case .project: relativePath
            case .repository: "//\(relativePath)"
            case .absolute: "/\(relativePath)"
            }
        }
    }

    /// A target a code generation target produces sources for.
    public struct Output: Equatable, Hashable, Codable, Sendable {
        /// The directory of the project containing the consumer.
        public let projectPath: AbsolutePath

        /// The consumer's name.
        public let target: String

        public init(projectPath: AbsolutePath, target: String) {
            self.projectPath = projectPath
            self.target = target
        }
    }

    #if DEBUG
        public static func test(
            name: String = "generator",
            script: String = "exit 0",
            inputs: [Input] = [],
            environment: [String: String] = [:],
            outputs: [Output] = [],
            // swiftlint:disable:next force_try
            rootDirectory: AbsolutePath = try! AbsolutePath(validating: "/Repository")
        ) -> CodeGenerator {
            CodeGenerator(
                name: name,
                script: script,
                inputs: inputs,
                environment: environment,
                outputs: outputs,
                rootDirectory: rootDirectory
            )
        }
    #endif
}
