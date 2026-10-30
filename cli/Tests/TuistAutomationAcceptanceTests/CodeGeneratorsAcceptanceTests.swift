import FileSystem
import FileSystemTesting
import Path
import Testing
import TuistAcceptanceTesting
import TuistBuildCommand
import TuistCore
import TuistGenerateCommand
import TuistSupport
import TuistTestCommand
import TuistTesting
import XcodeProj
@testable import TuistKit

struct CodeGeneratorsAcceptanceTests {
    private let fileSystem = FileSystem()

    @Test(
        .withFixture("app_with_codegen", fixturesDirectory: Fixtures.cliDirectory),
        .inTemporaryDirectory,
        .withMockedEnvironment()
    )
    func generate_runs_every_generator_and_build_compiles_their_output() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        let designSystem = fixtureDirectory.appending(components: "Projects", "DesignSystem")
        let core = fixtureDirectory.appending(components: "Projects", "Core")

        try await TuistTest.run(GenerateCommand.self, ["--path", fixtureDirectory.pathString, "--no-open"])

        let assets = CodeGeneratorLayout.targetOutputDirectory(
            projectPath: designSystem,
            target: "AccountUI",
            generator: "assets"
        )
        let strings = CodeGeneratorLayout.targetOutputDirectory(
            projectPath: designSystem,
            target: "AccountUI",
            generator: "strings"
        )
        let schema = CodeGeneratorLayout.producerOutputDirectory(
            consumerProjectPath: core,
            producer: "GQLCodegen",
            consumer: "GQLSchema"
        )
        let types = CodeGeneratorLayout.producerOutputDirectory(
            consumerProjectPath: core,
            producer: "GQLCodegen",
            consumer: "GQLTypes"
        )
        #expect(try await fileSystem.exists(assets.appending(component: "TuistAssets+AccountUI.swift")))
        #expect(try await fileSystem.readTextFile(at: strings.appending(component: "AccountUIStrings.swift"))
            .contains("public enum"))
        #expect(try await fileSystem.exists(schema.appending(component: "SchemaMetadata.generated.swift")))
        #expect(try await fileSystem.exists(types.appending(component: "AccountQuery.generated.swift")))

        let coreProject = try XcodeProj(pathString: core.appending(component: "Core.xcodeproj").pathString)
        #expect(coreProject.pbxproj.aggregateTargets.map(\.name) == ["GQLCodegen"])
        let gqlTypes = try #require(coreProject.pbxproj.nativeTargets.first { $0.name == "GQLTypes" })
        #expect(gqlTypes.dependencies.contains { $0.target?.name == "GQLCodegen" })

        try await TuistTest.run(
            BuildCommand.self,
            [
                "App",
                "--path", fixtureDirectory.pathString,
                "--platform", "ios",
                "--derived-data-path", derivedDataPath.pathString,
            ]
        )
        try await TuistTest.run(
            TestCommand.self,
            [
                "AccountUITests",
                "--path", fixtureDirectory.pathString,
                "--derived-data-path", derivedDataPath.pathString,
            ]
        )
    }
}
