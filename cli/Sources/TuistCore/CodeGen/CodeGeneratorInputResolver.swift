import FileSystem
import Foundation
import Mockable
import Path
import TuistConstants
import TuistLogging
import TuistSupport
import XcodeGraph

/// A declared path input resolved against the file system.
public struct ResolvedCodeGeneratorInput: Equatable, Hashable, Sendable {
    public enum Kind: String, Equatable, Hashable, Sendable {
        case file, folder, glob
    }

    /// A file the input covers, with its machine-independent logical path.
    public struct File: Equatable, Hashable, Sendable {
        public let path: AbsolutePath
        public let logicalPath: String

        public init(path: AbsolutePath, logicalPath: String) {
            self.path = path
            self.logicalPath = logicalPath
        }
    }

    public let kind: Kind

    /// The path as declared. For a glob, the unexpanded pattern.
    public let declared: CodeGenerator.Path

    /// The file a `.file` input names, every file in a `.folder` input's tree, or every glob match, sorted by
    /// logical path.
    public let files: [File]

    public init(kind: Kind, declared: CodeGenerator.Path, files: [File]) {
        self.kind = kind
        self.declared = declared
        self.files = files
    }

    /// The entries a generator receives in `TUIST_INPUTS_FILE`: the folder itself for a `.folder` input, one entry
    /// per match for a `.glob` input.
    public var inputsFileEntries: [(type: String, path: AbsolutePath)] {
        switch kind {
        case .file: files.map { (type: "file", path: $0.path) }
        case .folder: [(type: "folder", path: (try? declared.absolutePath) ?? declared.anchorDirectory)]
        case .glob: files.map { (type: "file", path: $0.path) }
        }
    }
}

public enum CodeGeneratorInputResolverError: FatalError, Equatable {
    case inputNotFound(generator: String, target: String, path: AbsolutePath)

    public var type: ErrorType { .abort }

    public var description: String {
        switch self {
        case let .inputNotFound(generator, target, path):
            "The code generator '\(generator)' of target '\(target)' declares the input \(path.pathString), which doesn't exist."
        }
    }
}

@Mockable
public protocol CodeGeneratorInputResolving: Sendable {
    /// Resolves an action's path inputs in declaration order. `.script` inputs are skipped.
    func resolve(action: CodeGeneratorAction) async throws -> [ResolvedCodeGeneratorInput]
}

/// Resolves code generator inputs, expanding folders and globs.
///
/// Resolution never descends into a `Derived` directory, which is where generated output lives, so a wide pattern
/// such as `//Projects/**/*.graphql` can't feed a generator's output back into its own hash.
public struct CodeGeneratorInputResolver: CodeGeneratorInputResolving {
    private let fileSystem: FileSysteming
    private let filesFilter = HashingFilesFilter()

    public init(fileSystem: FileSysteming = FileSystem()) {
        self.fileSystem = fileSystem
    }

    // swiftlint:disable:next function_body_length
    public func resolve(action: CodeGeneratorAction) async throws -> [ResolvedCodeGeneratorInput] {
        var resolved: [ResolvedCodeGeneratorInput] = []
        for input in action.generator.inputs {
            switch input {
            case let .file(declared):
                let path = try declared.absolutePath
                guard try await fileSystem.exists(path, isDirectory: false) else {
                    throw CodeGeneratorInputResolverError.inputNotFound(
                        generator: action.generator.name,
                        target: action.targetName,
                        path: path
                    )
                }
                resolved.append(ResolvedCodeGeneratorInput(
                    kind: .file,
                    declared: declared,
                    files: [.init(path: path, logicalPath: declared.logicalPath)]
                ))
            case let .folder(declared):
                let path = try declared.absolutePath
                guard try await fileSystem.exists(path, isDirectory: true) else {
                    throw CodeGeneratorInputResolverError.inputNotFound(
                        generator: action.generator.name,
                        target: action.targetName,
                        path: path
                    )
                }
                resolved.append(ResolvedCodeGeneratorInput(
                    kind: .folder,
                    declared: declared,
                    files: try await files(in: path, include: "**/*", declared: declared)
                ))
            case let .glob(declared):
                let pattern = try declared.absolutePath
                let directory = pattern.upToLastNonGlob
                let files: [ResolvedCodeGeneratorInput.File]
                if directory == pattern {
                    files = try await fileSystem.exists(pattern, isDirectory: false)
                        ? [.init(path: pattern, logicalPath: declared.logicalPath(of: pattern))]
                        : []
                } else if try await fileSystem.exists(directory, isDirectory: true) {
                    files = try await self.files(
                        in: directory,
                        include: pattern.relative(to: directory).pathString,
                        declared: declared
                    )
                } else {
                    files = []
                }
                resolved.append(ResolvedCodeGeneratorInput(kind: .glob, declared: declared, files: files))
            case .script:
                continue
            }
        }
        return resolved
    }

    private func files(
        in directory: AbsolutePath,
        include: String,
        declared: CodeGenerator.Path
    ) async throws -> [ResolvedCodeGeneratorInput.File] {
        try await fileSystem
            .glob(directory: directory, include: [include], exclude: ["**/\(Constants.DerivedDirectory.name)"])
            .collect()
            .filter { filesFilter($0) && !$0.relative(to: directory).components.contains(Constants.DerivedDirectory.name) }
            .concurrentFilter { try await fileSystem.exists($0, isDirectory: false) }
            .map { ResolvedCodeGeneratorInput.File(path: $0, logicalPath: declared.logicalPath(of: $0)) }
            .sorted { $0.logicalPath < $1.logicalPath }
    }
}
