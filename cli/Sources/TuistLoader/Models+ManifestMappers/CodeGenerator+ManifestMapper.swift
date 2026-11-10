import Path
import ProjectDescription
import XcodeGraph

extension XcodeGraph.CodeGenerator {
    /// Maps a per-target generator declared in a target's `codeGenerators`.
    static func from(
        manifest: ProjectDescription.CodeGenerator,
        generatorPaths: GeneratorPaths
    ) throws -> XcodeGraph.CodeGenerator {
        XcodeGraph.CodeGenerator(
            name: manifest.name,
            script: manifest.script,
            inputs: try manifest.inputs.map { try .from(manifest: $0, generatorPaths: generatorPaths) },
            environment: manifest.environment,
            contents: Set(manifest.contents.map(XcodeGraph.BuildableFolderContent.from(manifest:))),
            rootDirectory: generatorPaths.rootDirectory
        )
    }

    /// Maps the generator of a code generation target, which takes the target's name.
    static func from(
        manifest: ProjectDescription.Target.Codegen,
        name: String,
        generatorPaths: GeneratorPaths
    ) throws -> XcodeGraph.CodeGenerator {
        XcodeGraph.CodeGenerator(
            name: name,
            script: manifest.script,
            inputs: try manifest.inputs.map { try .from(manifest: $0, generatorPaths: generatorPaths) },
            environment: manifest.environment,
            outputs: try manifest.outputs.map { output in
                XcodeGraph.CodeGenerator.Output(
                    projectPath: try generatorPaths.resolveSchemeActionProjectPath(output.project),
                    target: output.target,
                    contents: Set(output.contents.map(XcodeGraph.BuildableFolderContent.from(manifest:)))
                )
            },
            rootDirectory: generatorPaths.rootDirectory
        )
    }
}

extension XcodeGraph.CodeGenerator.Input {
    /// Globs stay unexpanded, so the pattern contributes to the hash even while it matches nothing.
    static func from(
        manifest: ProjectDescription.CodeGenerator.Input,
        generatorPaths: GeneratorPaths
    ) throws -> XcodeGraph.CodeGenerator.Input {
        switch manifest {
        case let .file(path): .file(try .from(manifest: path, generatorPaths: generatorPaths))
        case let .folder(path): .folder(try .from(manifest: path, generatorPaths: generatorPaths))
        case let .glob(path): .glob(try .from(manifest: path, generatorPaths: generatorPaths))
        case let .script(script): .script(script)
        }
    }
}

extension XcodeGraph.CodeGenerator.Path {
    static func from(
        manifest: ProjectDescription.Path,
        generatorPaths: GeneratorPaths
    ) throws -> XcodeGraph.CodeGenerator.Path {
        let resolvedPath = try generatorPaths.resolve(path: manifest)
        let anchor: Anchor = if !resolvedPath.isDescendantOfOrEqual(to: generatorPaths.rootDirectory) {
            .absolute
        } else if manifest.type == .relativeToRoot {
            .repository
        } else {
            .project
        }
        let anchorDirectory = switch anchor {
        case .absolute: AbsolutePath.root
        case .repository: generatorPaths.rootDirectory
        case .project: generatorPaths.manifestDirectory
        }
        return XcodeGraph.CodeGenerator.Path(
            anchor: anchor,
            anchorDirectory: anchorDirectory,
            relativePath: resolvedPath.relative(to: anchorDirectory).pathString
        )
    }
}
