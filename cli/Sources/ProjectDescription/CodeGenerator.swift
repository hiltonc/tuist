/// A command that produces some of a target's sources from a declared set of inputs.
///
/// Tuist runs the command during `tuist generate`, `tuist build`, and `tuist test`, and attaches its output
/// directory to the target as a buildable folder. No output path appears in the manifest: it's derived from the
/// target's name and the generator's `name`.
///
/// ```swift
/// .target(
///     name: "AccountUI",
///     destinations: .iOS,
///     product: .staticFramework,
///     bundleId: "dev.tuist.accountui",
///     buildableFolders: ["Sources/AccountUI"],
///     codeGenerators: [
///         .script(
///             name: "assets",
///             script: #"exec "$TUIST_ROOT_DIR/scripts/assets.sh""#,
///             inputs: [
///                 .folder("Sources/AccountUI/Resources"),
///                 .file("//templates/Assets.stencil"),
///                 .script("mise x -- swiftgen --version"),
///             ]
///         ),
///     ]
/// )
/// ```
///
/// The generator's output never contributes to the target's content hash. Its declaration does instead: the
/// command, the name, the declared `environment`, and the logical path and contents of every input. Tuist assumes
/// the output is a deterministic function of those, so an input the generator reads but doesn't declare can produce
/// an incorrect cache hit.
///
/// The script runs from the project directory, inheriting the environment, with these variables set:
///
/// - `TUIST_OUTPUT_SOURCES_DIR`: an empty directory to write sources into. Tuist moves it into place after the
///   script exits zero, so generated files mustn't embed its path.
/// - `TUIST_INPUTS_FILE`: a JSON array of `{"type", "path"}` entries, one per file, folder, and glob match, with
///   absolute paths. Script inputs are absent.
/// - `TUIST_TARGET_NAME`, `TUIST_PROJECT_DIR`, and `TUIST_ROOT_DIR`.
///
/// ``Input/script(_:)`` inputs run differently: from the repository root, with only `TUIST_ROOT_DIR` and the declared
/// `environment` added.
public struct CodeGenerator: Codable, Equatable, Sendable {
    /// The generator's name, unique within the target. It's a component of the output directory, so it can't
    /// contain a path separator or be `.` or `..`.
    public var name: String

    /// The shell script that runs the generator.
    public var script: String

    /// The inputs the generator's output depends on.
    public var inputs: [Input]

    /// Variables the generator's output depends on. They're added to the inherited environment and contribute to
    /// the content hash. The rest of the environment, `PATH` included, doesn't.
    public var environment: [String: String]

    /// Creates a generator that runs a shell script.
    ///
    /// - Parameters:
    ///   - name: The generator's name, unique within the target.
    ///   - script: The shell script that runs the generator.
    ///   - inputs: The inputs the generator's output depends on.
    ///   - environment: Variables the generator's output depends on.
    public static func script(
        name: String,
        script: String,
        inputs: [Input] = [],
        environment: [String: String] = [:]
    ) -> Self {
        Self(name: name, script: script, inputs: inputs, environment: environment)
    }

    /// An input that affects a generator's output.
    ///
    /// Paths are relative to the manifest's directory, or to the repository root when prefixed with `//`. They
    /// contribute to the hash as written, alongside their contents, so renaming an input invalidates the output
    /// while moving the checkout doesn't. Inputs never resolve inside a `Derived` directory.
    public enum Input: Codable, Hashable, Sendable {
        /// A file whose contents affect the output.
        case file(Path)

        /// A folder whose whole tree affects the output.
        case folder(Path)

        /// A glob pattern whose matches affect the output. A pattern that matches nothing warns rather than failing,
        /// and still contributes itself, so the hash moves when the first match appears.
        case glob(Path)

        /// A shell script whose standard output affects the output, such as a tool's `--version`.
        ///
        /// It runs from the repository root, inheriting the environment, with only `TUIST_ROOT_DIR` and the declared
        /// `environment` added. Nothing identifies the target or project, so identical script inputs with the same
        /// declared environment run once per command and share their output. A script that needs per-target context
        /// takes it as an argument, such as a path relative to the root:
        ///
        /// ```swift
        /// .script(#""$TUIST_ROOT_DIR/scripts/schema-version.sh" Projects/AccountUI"#)
        /// ```
        case script(String)
    }

    /// A target a code generation target produces sources for. See
    /// ``Target/codegen(name:script:inputs:environment:outputs:metadata:)``.
    public struct Output: Codable, Hashable, Sendable {
        /// The project containing the consumer. `nil` for the generator's own project.
        public var project: Path?

        /// The consumer's name.
        public var target: String

        /// A consumer in the generator's own project.
        public static func output(target: String) -> Self {
            Self(project: nil, target: target)
        }

        /// A consumer in another project.
        ///
        /// - Parameters:
        ///   - project: The path to the directory containing the consumer's project.
        ///   - target: The consumer's name.
        public static func output(project: Path, target: String) -> Self {
            Self(project: project, target: target)
        }
    }
}
