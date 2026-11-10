import Foundation
import Path

/// Runs each distinct `.script` input once per command invocation and shares its output with every code generator that
/// declares it.
///
/// A script input runs from the repository root with only `TUIST_ROOT_DIR` and the generator's declared environment
/// added to the inherited one, so the script, the declared environment, and the root identify its output. Nothing is
/// kept across invocations; a cache exists only inside ``scoped(_:)``.
public actor CodeGeneratorScriptInputCache {
    @TaskLocal public static var current: CodeGeneratorScriptInputCache?

    struct Key: Hashable {
        let script: String
        let environment: [String: String]
        let rootDirectory: AbsolutePath
    }

    private var runs: [Key: Task<String, Error>] = [:]

    public init() {}

    /// Runs `body` with a cache in scope, reusing the enclosing cache when there is one.
    ///
    /// ```swift
    /// try await CodeGeneratorScriptInputCache.scoped {
    ///     let graph = try await generator.load(path: path, options: options)
    ///     try await codeGeneratorMaterializer.materialize(graph: graph)
    /// }
    /// ```
    public static func scoped<Result>(_ body: () async throws -> Result) async throws -> Result {
        if current != nil { return try await body() }
        return try await $current.withValue(CodeGeneratorScriptInputCache()) { try await body() }
    }

    /// Returns the output of the run for `key`, starting it when no caller has. Concurrent callers wait for the same run.
    func output(for key: Key, run: @escaping @Sendable () async throws -> String) async throws -> String {
        if let existing = runs[key] {
            return try await existing.value
        }
        let task = Task { try await run() }
        runs[key] = task
        return try await task.value
    }
}
