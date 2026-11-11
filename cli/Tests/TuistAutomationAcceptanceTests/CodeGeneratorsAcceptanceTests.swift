import FileSystem
import FileSystemTesting
import Path
import Testing
import TuistAcceptanceTesting
import TuistBuildCommand
import TuistCore
import TuistGenerateCommand
import TuistProcess
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

    @Test(
        .withFixture("app_with_codegen_resources", fixturesDirectory: Fixtures.cliDirectory),
        .inTemporaryDirectory,
        .withMockedEnvironment(),
        .withMockedLogger()
    )
    func generated_resources_follow_their_targets_product() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        let pbxprojPath = fixtureDirectory.appending(components: "App.xcodeproj", "project.pbxproj")

        try await TuistTest.run(GenerateCommand.self, ["--path", fixtureDirectory.pathString, "--no-open"])
        let projectBeforeFirstRun = try await fileSystem.readFile(at: pbxprojPath)
        let mixed = CodeGeneratorLayout.targetOutputDirectory(
            projectPath: fixtureDirectory,
            target: "MixedKit",
            generator: "mixed"
        )
        #expect(try await fileSystem.exists(mixed.appending(component: "mixed.txt")))

        try await TuistTest.run(GenerateCommand.self, ["--path", fixtureDirectory.pathString, "--no-open"])
        TuistTest.expectLogs("3 code generators up to date", at: .notice)
        #expect(try await fileSystem.readFile(at: pbxprojPath) == projectBeforeFirstRun)

        try await TuistTest.run(
            BuildCommand.self,
            ["App", "--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )

        let products = derivedDataPath.appending(components: "Build", "Products", "Debug")
        let app = products.appending(component: "App.app")
        let appResources = app.appending(components: "Contents", "Resources")
        #expect(try await fileSystem.exists(
            app.appending(components: "Contents", "Frameworks", "DynamicKit.framework", "Resources", "dynamic.txt")
        ))
        #expect(try await fileSystem.exists(
            appResources.appending(components: "App_StaticKit.bundle", "Contents", "Resources", "static.txt")
        ))
        #expect(try await fileSystem.exists(
            appResources.appending(components: "App_MixedKit.bundle", "Contents", "Resources", "mixed.txt")
        ))
        #expect(try await !fileSystem.exists(
            appResources.appending(components: "App_MixedKit.bundle", "Contents", "Resources", "MixedMessage.swift")
        ))
        let output = try await CommandRunner()
            .capture(arguments: [app.appending(components: "Contents", "MacOS", "App").pathString])
        #expect(output.trimmingCharacters(in: .whitespacesAndNewlines) == "Dynamic Static Mixed")
    }
}
