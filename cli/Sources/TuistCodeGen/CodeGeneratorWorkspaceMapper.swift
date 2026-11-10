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

/// Attaches code generator output to its consumers as generated buildable folders, and makes each consumer of a code
/// generation target depend on it so the content hasher, which walks declared dependencies, moves the consumer's hash
/// with the producer's.
public struct CodeGeneratorWorkspaceMapper: WorkspaceMapping {
    public init() {}

    public func map(workspace: WorkspaceWithProjects) async throws -> (WorkspaceWithProjects, [SideEffectDescriptor]) {
        var workspace = workspace
        try validatePathComponents(projects: workspace.projects)
        let declaringProjects = workspace.projects.filter { project in
            project.targets.values.contains(where: \.declaresCodeGeneration)
        }
        let sideEffects = staleOutputCleanups(projects: workspace.projects)
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
                    isGenerated: true
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

    private func validatePathComponents(projects: [Project]) throws {
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
        let consumersByProject = Dictionary(grouping: outputs, by: \.projectPath)
        for project in projects {
            let consumers = Set((consumersByProject[project.path] ?? []).map(\.target))
            let participatingNames = Set(
                project.targets.values.filter(\.declaresCodeGeneration).map(\.name)
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

    private func validate(actions: [CodeGeneratorAction], projects: [Project]) throws {
        var issues: [String] = []
        let projectsByPath = Dictionary(projects.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })

        for project in projects {
            for target in project.targets.values.sorted()
                where (target.type == .remote || project.type != .local)
                && target.declaresCodeGeneration
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

    /// Rejects names that can't be one path component, or that would share a directory on a case- and
    /// normalization-insensitive file system such as APFS.
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

    /// Rejects inputs and outputs that overlap in either direction.
    ///
    /// Outputs and the directories that contain them are indexed once, so checking an input costs its depth rather than
    /// a comparison against every output.
    private func overlapIssues(actions: [CodeGeneratorAction]) -> [String] {
        var canonicalPaths = [AbsolutePath: AbsolutePath]()
        func canonicalPath(_ path: AbsolutePath) -> AbsolutePath {
            if let cached = canonicalPaths[path] { return cached }
            let resolved = canonical(path)
            canonicalPaths[path] = resolved
            return resolved
        }

        var outputs = Set<AbsolutePath>()
        // Directories an output is at or under with no `Derived` component in between: a directory input at one of
        // these would read that output.
        var outputContainers = Set<AbsolutePath>()
        for directory in actions.flatMap(\.outputs).map(\.directory) {
            var container = canonicalPath(directory)
            outputs.insert(container)
            // Whether to keep climbing depends only on the directory reached, so one already indexed has had its
            // ancestors indexed too.
            while outputContainers.insert(container).inserted,
                  container.basename != Constants.DerivedDirectory.name,
                  !container.isRoot
            {
                container = container.parentDirectory
            }
        }

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
                let inputPath = canonicalPath(absolutePath.upToLastNonGlob)
                let overlaps = inputPath.ancestorsAndSelf.contains(where: outputs.contains)
                    || (isDirectory && outputContainers.contains(inputPath))
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

    /// Describes the removal of output and state no declaration owns.
    private func staleOutputCleanups(projects: [Project]) -> [SideEffectDescriptor] {
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

        return projects.filter { $0.type == .local }.flatMap { project in
            let codeGenDirectory = CodeGeneratorLayout.codeGenDirectory(projectPath: project.path)
            let layout: [(components: [String], include: [String])] = [
                ([CodeGeneratorLayout.targetsDirectoryName], ["*", "*/*"]),
                ([CodeGeneratorLayout.producersDirectoryName], ["*", "*/*"]),
                ([CodeGeneratorLayout.stateDirectoryName, CodeGeneratorLayout.targetsDirectoryName], ["*", "*/*"]),
                ([CodeGeneratorLayout.stateDirectoryName, CodeGeneratorLayout.producersDirectoryName], ["*"]),
            ]
            return layout.map { components, include in
                let directory = codeGenDirectory.appending(components: components)
                return SideEffectDescriptor.generatedFilesCleanup(GeneratedFilesCleanupDescriptor(
                    directories: [directory],
                    activeFilesByDirectory: [directory: expected.filter { $0.isDescendant(of: directory) }],
                    include: include
                ))
            }
        }
    }
}

extension Target {
    fileprivate var declaresCodeGeneration: Bool {
        !codeGenerators.isEmpty || codegen != nil
    }

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
