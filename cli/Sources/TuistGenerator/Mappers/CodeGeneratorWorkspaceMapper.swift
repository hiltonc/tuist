import FileSystem
import Foundation
import Path
import TuistConstants
import TuistCore
import TuistLogging
import TuistSupport
import XcodeGraph

public enum CodeGeneratorWorkspaceMapperError: FatalError, Equatable {
    case invalidDeclarations([String])

    public var type: ErrorType { .abort }

    public var description: String {
        switch self {
        case let .invalidDeclarations(issues):
            (["The code generator declarations are invalid:"] + issues.map { "- \($0)" }).joined(separator: "\n")
        }
    }
}

/// Attaches code generator output to the targets that consume it.
///
/// For every generator, it attaches each output directory to its consumer as a buildable folder marked as generated.
/// For a code generation target, it also adds a dependency from each consumer on the producer to the consumer's
/// `dependencies`, so the build orders generation first and the content hasher, which walks a target's declared
/// dependencies, moves the consumer's hash with the producer's.
///
/// It runs before the graph is loaded, once every project exists as a model, because a producer can name a consumer
/// in another project. Generation itself is deferred to the materialization phase that `generate`, `build`, and
/// `test` run, so mapping never executes a generator. It also returns side effects that delete output and state no
/// declaration accounts for any longer.
public struct CodeGeneratorWorkspaceMapper: WorkspaceMapping {
    private let fileSystem: FileSysteming

    public init(fileSystem: FileSysteming = FileSystem()) {
        self.fileSystem = fileSystem
    }

    public func map(workspace: WorkspaceWithProjects) async throws -> (WorkspaceWithProjects, [SideEffectDescriptor]) {
        var workspace = workspace
        // Names become path components, so they're validated before any output path is derived from them.
        try validateNames(projects: workspace.projects)
        let declaringProjects = workspace.projects.filter { project in
            project.targets.values.contains { !$0.codeGenerators.isEmpty || $0.codegen != nil }
        }
        let sideEffects = try await staleOutputDeletions(projects: workspace.projects)
        guard !declaringProjects.isEmpty else { return (workspace, sideEffects) }

        let actions = declaringProjects.flatMap { project in
            project.targets.values.sorted().flatMap { CodeGeneratorAction.actions(for: $0, projectPath: project.path) }
        }
        try validate(actions: actions, projects: workspace.projects)

        var projectIndices = [AbsolutePath: Int]()
        for (index, project) in workspace.projects.enumerated() {
            projectIndices[project.path] = index
        }

        for action in actions {
            for output in action.outputs {
                guard let projectIndex = projectIndices[output.projectPath] else { continue }
                var consumer = workspace.projects[projectIndex].targets[output.target]!
                consumer.buildableFolders.append(BuildableFolder(
                    path: output.directory,
                    exceptions: BuildableFolderExceptions(exceptions: []),
                    resolvedFiles: [],
                    contents: [.sources],
                    isCodeGeneratorOutput: true
                ))
                if action.isMultiTarget, !consumer.declaresDependency(
                    on: action.targetName,
                    in: action.projectPath,
                    from: output.projectPath
                ) {
                    consumer.dependencies.append(
                        output.projectPath == action.projectPath
                            ? .target(name: action.targetName)
                            : .project(target: action.targetName, path: action.projectPath)
                    )
                }
                workspace.projects[projectIndex].targets[output.target] = consumer
            }

            // A code generation target builds nothing, so it supports whatever its consumers do.
            if action.isMultiTarget, let projectIndex = projectIndices[action.projectPath] {
                let consumerDestinations = action.outputs.reduce(into: Destinations()) { destinations, output in
                    guard let index = projectIndices[output.projectPath],
                          let consumer = workspace.projects[index].targets[output.target] else { return }
                    destinations.formUnion(consumer.destinations)
                }
                if !consumerDestinations.isEmpty {
                    workspace.projects[projectIndex].targets[action.targetName]?.destinations = consumerDestinations
                }
            }
        }

        return (workspace, sideEffects)
    }

    // MARK: - Validation

    private func validateNames(projects: [Project]) throws {
        let outputs = projects.flatMap { project in
            project.targets.values.compactMap(\.codegen).flatMap(\.outputs)
        }
        var issues: [String] = []
        let projectPaths = Set(projects.map(\.path))
        issues += pathComponentIssues(
            names: Set(outputs.filter { !projectPaths.contains($0.projectPath) }.map(\.target)).sorted(),
            kind: "target name",
            scope: "a code generation output"
        ).filter { $0.contains("path component") }
        for project in projects {
            let consumers = Set(outputs.filter { $0.projectPath == project.path }.map(\.target))
            let participatingNames = Set(
                project.targets.values
                    .filter { !$0.codeGenerators.isEmpty || $0.codegen != nil }
                    .map(\.name)
            ).union(consumers)
            issues += pathComponentIssues(
                names: participatingNames.sorted(),
                kind: "target name",
                scope: "project at \(project.path.pathString)"
            )
            for target in project.targets.values.sorted() {
                issues += pathComponentIssues(
                    names: target.codeGenerators.map(\.name),
                    kind: "code generator name",
                    scope: "target '\(target.name)'"
                )
            }
        }
        guard issues.isEmpty else { throw CodeGeneratorWorkspaceMapperError.invalidDeclarations(issues) }
    }

    // swiftlint:disable:next function_body_length
    private func validate(actions: [CodeGeneratorAction], projects: [Project]) throws {
        var issues: [String] = []
        let projectsByPath = Dictionary(projects.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })

        for project in projects {
            for target in project.targets.values.sorted()
                where (target.type == .remote || project.type != .local)
                && (!target.codeGenerators.isEmpty || target.codegen != nil)
            {
                issues.append("The target '\(target.name)' is resolved by a package manager and can't declare code generators.")
            }
        }

        var producersByConsumer = [String: [String]]()
        for action in actions where action.isMultiTarget {
            for output in action.outputs {
                guard let project = projectsByPath[output.projectPath] else {
                    issues.append(
                        "The code generation target '\(action.targetName)' declares an output for '\(output.target)' in a project at \(output.projectPath.pathString) that isn't part of the workspace."
                    )
                    continue
                }
                guard let consumer = project.targets[output.target] else {
                    issues.append(
                        "The code generation target '\(action.targetName)' declares an output for '\(output.target)', which isn't a target of the project at \(output.projectPath.pathString)."
                    )
                    continue
                }
                if consumer.type == .remote || project.type != .local {
                    issues.append(
                        "The code generation target '\(action.targetName)' declares an output for '\(output.target)', which is resolved by a package manager."
                    )
                }
                if consumer.codegen != nil {
                    issues.append(
                        "The code generation target '\(action.targetName)' declares an output for '\(output.target)', which is itself a code generation target."
                    )
                }
                producersByConsumer["\(output.projectPath.pathString)/\(output.target)", default: []]
                    .append("'\(action.targetName)' (\(action.projectPath.pathString))")
            }
        }
        for (consumer, producers) in producersByConsumer.sorted(by: { $0.key < $1.key }) where producers.count > 1 {
            issues
                .append(
                    "The target at \(consumer) is claimed by more than one code generation output: \(producers.joined(separator: ", "))."
                )
        }

        issues += overlapIssues(actions: actions)

        guard issues.isEmpty else { throw CodeGeneratorWorkspaceMapperError.invalidDeclarations(issues) }
    }

    /// Rejects names that can't be a single path component, and names that would share a directory on a
    /// case-insensitive, normalization-insensitive file system such as APFS.
    private func pathComponentIssues(names: [String], kind: String, scope: String) -> [String] {
        var issues: [String] = []
        var namesByKey = [String: [String]]()
        for name in names {
            if name.isEmpty || name == "." || name == ".." || name.contains("/") || name.contains("\0") {
                issues.append("The \(kind) '\(name)' in \(scope) can't be used as a path component.")
            }
            namesByKey[name.precomposedStringWithCanonicalMapping.lowercased(), default: []].append(name)
        }
        for (_, collisions) in namesByKey.sorted(by: { $0.key < $1.key }) where collisions.count > 1 {
            issues.append(
                "The \(kind)s \(collisions.sorted().map { "'\($0)'" }.joined(separator: ", ")) in \(scope) differ only by case or Unicode normalization, so their output would share a directory."
            )
        }
        return issues
    }

    /// Rejects inputs and outputs that overlap in either direction. Input resolution never descends into `Derived`,
    /// so only a path that names generated output, or a directory inside `Derived`, can overlap.
    private func overlapIssues(actions: [CodeGeneratorAction]) -> [String] {
        let outputs = actions.flatMap(\.outputs).map(\.directory).map(canonical)
        var issues: [String] = []
        for action in actions {
            for input in action.generator.inputs {
                let declared: CodeGenerator.Path
                let isDirectory: Bool
                switch input {
                case let .file(path): (declared, isDirectory) = (path, false)
                case let .folder(path): (declared, isDirectory) = (path, true)
                case let .glob(path): (declared, isDirectory) = (path, true)
                case .script: continue
                }
                guard let absolutePath = try? declared.absolutePath else { continue }
                let inputPath = canonical(absolutePath.upToLastNonGlob)
                let overlaps = outputs.contains { output in
                    inputPath.isDescendantOfOrEqual(to: output)
                        || (isDirectory && output.isDescendantOfOrEqual(to: inputPath)
                            && !output.relative(to: inputPath).components.contains(Constants.DerivedDirectory.name))
                }
                if overlaps {
                    issues.append(
                        "The input '\(declared.logicalPath)' of the code generator '\(action.generator.name)' in target '\(action.targetName)' overlaps a code generator's output directory."
                    )
                }
            }
        }
        return issues
    }

    private func canonical(_ path: AbsolutePath) -> AbsolutePath {
        (try? AbsolutePath(validating: path.url.resolvingSymlinksInPath().path)) ?? path
    }

    // MARK: - Pruning

    /// Output and state directories under `Derived/CodeGen` are preserved across generations, so ones no longer
    /// matching a declaration are deleted. Otherwise a deleted generator's output would be attached and compiled
    /// again if its name were reused.
    private func staleOutputDeletions(projects: [Project]) async throws -> [SideEffectDescriptor] {
        let actions = projects.flatMap { project in
            project.targets.values.flatMap { CodeGeneratorAction.actions(for: $0, projectPath: project.path) }
        }
        var expected = Set<AbsolutePath>()
        for action in actions {
            for output in action.outputs {
                expected.formUnion(output.directory.parentDirectory.ancestorsAndSelf)
            }
            expected.formUnion(action.statePath.ancestorsAndSelf)
        }

        var sideEffects: [SideEffectDescriptor] = []
        for project in projects where project.type == .local {
            let codeGenDirectory = CodeGeneratorLayout.codeGenDirectory(projectPath: project.path)
            guard try await fileSystem.exists(codeGenDirectory, isDirectory: true) else { continue }
            let layout: [(components: [String], depth: Int)] = [
                ([CodeGeneratorLayout.targetsDirectoryName], 2),
                ([CodeGeneratorLayout.producersDirectoryName], 2),
                ([CodeGeneratorLayout.stateDirectoryName, CodeGeneratorLayout.targetsDirectoryName], 2),
                ([CodeGeneratorLayout.stateDirectoryName, CodeGeneratorLayout.producersDirectoryName], 1),
            ]
            for (components, depth) in layout {
                sideEffects += try await staleEntries(
                    in: codeGenDirectory.appending(components: components),
                    depth: depth,
                    expected: expected
                )
            }
        }
        return sideEffects
    }

    private func staleEntries(in directory: AbsolutePath, depth: Int, expected: Set<AbsolutePath>) async throws
        -> [SideEffectDescriptor]
    {
        guard depth > 0, try await fileSystem.exists(directory, isDirectory: true) else { return [] }
        var sideEffects: [SideEffectDescriptor] = []
        for entry in try await fileSystem.contentsOfDirectory(directory).sorted() where !entry.basename.hasPrefix(".") {
            if !expected.contains(entry) {
                sideEffects.append(
                    try await fileSystem.exists(entry, isDirectory: true)
                        ? .directory(DirectoryDescriptor(path: entry, state: .absent))
                        : .file(FileDescriptor(path: entry, state: .absent))
                )
            } else {
                sideEffects += try await staleEntries(in: entry, depth: depth - 1, expected: expected)
            }
        }
        return sideEffects
    }
}

extension Target {
    fileprivate func declaresDependency(
        on producer: String,
        in producerProjectPath: AbsolutePath,
        from projectPath: AbsolutePath
    ) -> Bool {
        dependencies.contains { dependency in
            switch dependency {
            case let .target(name, _, _):
                name == producer && projectPath == producerProjectPath
            case let .project(target, path, _, _):
                target == producer && path == producerProjectPath
            default:
                false
            }
        }
    }
}

extension AbsolutePath {
    fileprivate var ancestorsAndSelf: [AbsolutePath] {
        var paths = [self]
        var current = self
        while !current.isRoot {
            current = current.parentDirectory
            paths.append(current)
        }
        return paths
    }
}
