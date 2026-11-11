import Path
import TuistProcess
import TuistSupport

/// Shares the standard output of script hashing inputs across one hashing pass, so a script that many targets
/// declare runs once per working directory. Concurrent requests await the same run, and a failed run fails every
/// request with its error. Create one per pass so scripts run again on the next command:
///
/// ```swift
/// let scriptOutputs = HashingScriptOutputs()
/// for target in targets {
///     _ = try await additionalHashingInputsHasher.hash(
///         inputs: target.target.additionalHashingInputs, hashedPaths: [:],
///         sourceRootPath: target.project.sourceRootPath, scriptOutputs: scriptOutputs
///     )
/// }
/// ```
public actor HashingScriptOutputs {
    private struct Key: Hashable {
        let script: String
        let workingDirectory: AbsolutePath
    }

    private var runs: [Key: Task<String, Error>] = [:]

    public init() {}

    func standardOutput(
        of script: String,
        workingDirectory: AbsolutePath,
        commandRunner: CommandRunning
    ) async throws -> String {
        let key = Key(script: script, workingDirectory: workingDirectory)
        if let run = runs[key] {
            return try await run.value
        }
        let run = Task {
            try await commandRunner.runAndCollectOutput(
                arguments: ["/bin/sh", "-c", script],
                workingDirectory: workingDirectory
            ).standardOutput
        }
        runs[key] = run
        return try await run.value
    }
}
