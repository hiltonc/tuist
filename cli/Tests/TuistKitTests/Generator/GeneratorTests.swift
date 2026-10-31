import FileSystem
import FileSystemTesting
import Mockable
import Path
import Testing
import TuistCodeGen
import TuistCore
import XcodeGraph

@testable import TuistKit
@testable import TuistTesting

struct GeneratorTests {
    private let manifestGraphLoader = MockManifestGraphLoading()
    private let codeGeneratorMaterializer = MockCodeGeneratorMaterializing()
    private let subject: Generator

    init() {
        given(codeGeneratorMaterializer).materialize(graph: .any).willReturn()
        subject = Generator(manifestGraphLoader: manifestGraphLoader, codeGeneratorMaterializer: codeGeneratorMaterializer)
    }

    @Test(.inTemporaryDirectory)
    func load_never_runs_code_generators() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)
        given(manifestGraphLoader).load(path: .any, disableSandbox: .any).willReturn((
            graph(path: path),
            [],
            MapperEnvironment(),
            []
        ))

        let _: Graph = try await subject.load(path: path, options: nil)
        _ = try await subject.loadWithEnvironment(path: path, options: nil)

        verify(codeGeneratorMaterializer).materialize(graph: .any).called(0)
    }

    @Test(.inTemporaryDirectory, .withMockedLogger())
    func generateWithGraph_runs_code_generators_on_the_loaded_graph() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)
        let graph = graph(path: path)
        given(manifestGraphLoader).load(path: .any, disableSandbox: .any).willReturn((graph, [], MapperEnvironment(), []))

        _ = try await subject.generateWithGraph(path: path, options: nil)

        verify(codeGeneratorMaterializer).materialize(graph: .value(graph)).called(1)
    }

    private func graph(path: AbsolutePath) -> Graph {
        .test(
            path: path,
            workspace: .test(path: path, xcWorkspacePath: path.appending(component: "App.xcworkspace"), name: "App")
        )
    }
}
