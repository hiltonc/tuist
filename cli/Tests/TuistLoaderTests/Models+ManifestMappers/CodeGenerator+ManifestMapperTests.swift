import Foundation
import Path
import ProjectDescription
import Testing
import TuistSupport
import XcodeGraph
@testable import TuistLoader

struct CodeGeneratorManifestMapperTests {
    private let generatorPaths = GeneratorPaths(
        manifestDirectory: try! AbsolutePath(validating: "/Repository/Projects/DesignSystem"), // swiftlint:disable:this force_try
        rootDirectory: try! AbsolutePath(validating: "/Repository") // swiftlint:disable:this force_try
    )

    @Test
    func from_keeps_inputs_relative_to_their_declared_root() throws {
        let manifest = ProjectDescription.CodeGenerator.script(
            name: "assets",
            script: "exit 0",
            inputs: [
                .folder("Sources/AccountUI/Resources"),
                .file("//templates/Assets.stencil"),
                .glob("//Projects/**/*.graphql"),
                .script("swiftgen --version"),
            ],
            environment: ["LEVEL": "public"]
        )

        let generator = try XcodeGraph.CodeGenerator.from(manifest: manifest, generatorPaths: generatorPaths)

        #expect(generator.name == "assets")
        #expect(generator.environment == ["LEVEL": "public"])
        #expect(generator.rootDirectory == "/Repository")
        #expect(generator.outputs.isEmpty)
        #expect(generator.inputs == [
            .folder(.init(
                anchor: .project,
                anchorDirectory: "/Repository/Projects/DesignSystem",
                relativePath: "Sources/AccountUI/Resources"
            )),
            .file(.init(anchor: .repository, anchorDirectory: "/Repository", relativePath: "templates/Assets.stencil")),
            .glob(.init(anchor: .repository, anchorDirectory: "/Repository", relativePath: "Projects/**/*.graphql")),
            .script("swiftgen --version"),
        ])
        let logicalPaths: [String] = generator.inputs.compactMap {
            switch $0 {
            case let .file(path), let .folder(path), let .glob(path): path.logicalPath
            case .script: nil
            }
        }
        #expect(logicalPaths == ["Sources/AccountUI/Resources", "//templates/Assets.stencil", "//Projects/**/*.graphql"])
    }

    @Test
    func from_resolves_codegen_outputs_against_the_declaring_project() throws {
        let manifest = ProjectDescription.Target.codegen(
            name: "GQLCodegen",
            script: "exit 0",
            outputs: [
                .output(target: "GQLSchema"),
                .output(project: "//Projects/Networking", target: "GQLTransport"),
            ]
        )

        let target = try #require(manifest.codegen)
        let generator = try XcodeGraph.CodeGenerator.from(manifest: target, name: manifest.name, generatorPaths: generatorPaths)

        #expect(generator.name == "GQLCodegen")
        #expect(generator.outputs == [
            .init(projectPath: "/Repository/Projects/DesignSystem", target: "GQLSchema"),
            .init(projectPath: "/Repository/Projects/Networking", target: "GQLTransport"),
        ])
    }
}
