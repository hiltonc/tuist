import Path
import TuistEnvironment
import XcodeGraph

/// The environment a code generator runs with.
///
/// Declared values are added to the inherited environment rather than replacing it, so `PATH` stays reachable while
/// only the declared variables contribute to the action hash.
public enum CodeGeneratorEnvironment {
    public static let rootDirectory = "TUIST_ROOT_DIR"
    public static let projectDirectory = "TUIST_PROJECT_DIR"
    public static let targetName = "TUIST_TARGET_NAME"
    public static let inputsFile = "TUIST_INPUTS_FILE"
    public static let outputSourcesDirectory = "TUIST_OUTPUT_SOURCES_DIR"
    public static let outputsFile = "TUIST_OUTPUTS_FILE"

    /// The environment `.script` inputs run with while hashing: the inherited environment, the declared variables, and
    /// the repository root. Nothing identifies the target, so generators that declare the same script and environment
    /// can share one run.
    public static func scriptInputEnvironment(
        for generator: CodeGenerator,
        inherited: [String: String] = Environment.current.variables
    ) -> [String: String] {
        inherited
            .merging(generator.environment) { _, declared in declared }
            .merging([rootDirectory: generator.rootDirectory.pathString]) { _, tuist in tuist }
    }

    /// The environment the generator's script runs with, given the files and staging directories Tuist prepared.
    public static func generatorEnvironment(
        for action: CodeGeneratorAction,
        inputsFile: AbsolutePath,
        outputSourcesDirectory: AbsolutePath?,
        outputsFile: AbsolutePath?,
        inherited: [String: String] = Environment.current.variables
    ) -> [String: String] {
        var environment = scriptInputEnvironment(for: action.generator, inherited: inherited)
        environment[projectDirectory] = action.projectPath.pathString
        environment[targetName] = action.targetName
        environment[self.inputsFile] = inputsFile.pathString
        environment[self.outputSourcesDirectory] = outputSourcesDirectory?.pathString
        environment[self.outputsFile] = outputsFile?.pathString
        return environment
    }
}
