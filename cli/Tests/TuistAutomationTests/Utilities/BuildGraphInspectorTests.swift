import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import XcodeGraph
import XCTest

@testable import TuistAutomation
@testable import TuistTesting

final class BuildGraphInspectorTests: TuistUnitTestCase {
    var subject: BuildGraphInspector!

    override func setUp() {
        super.setUp()
        subject = BuildGraphInspector()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_allTestPlans() throws {
        // Given
        let path = try temporaryPath()
        let projectPath = path.appending(component: "Project.xcodeproj")
        let target1 = Target.test(name: "Test1")
        let targetReference1 = TargetReference(projectPath: projectPath, name: target1.name)
        let target2 = Target.test(name: "Test2")
        let targetReference2 = TargetReference(projectPath: projectPath, name: target2.name)

        let testPlan1 = TestPlan(
            path: path.appending(component: "Test1.testplan"),
            testTargets: [
                TestableTarget(target: targetReference1, skipped: true),
            ],
            isDefault: true
        )
        let testPlan2 = TestPlan(
            path: path.appending(component: "Test2.testplan"),
            testTargets: [
                TestableTarget(target: targetReference2, skipped: false),
            ],
            isDefault: false
        )
        let scheme1 = Scheme.test(
            testAction: .test(
                testPlans: [testPlan1]
            )
        )
        let scheme2 = Scheme.test(
            testAction: .test(
                testPlans: [testPlan2]
            )
        )

        let project = Project.test(
            path: projectPath,
            targets: [
                target1,
                target2,
            ],
            schemes: [scheme1, scheme2]
        )
        let graph = Graph.test(
            projects: [projectPath: project]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let testPlans = graphTraverser.allTestPlans()

        // Then
        XCTAssertEqual(testPlans, Set([testPlan1, testPlan2]))
    }

    func test_buildArguments_when_skipSigning() throws {
        // Given
        let target = Target.test(platform: .iOS)

        // When
        let got = subject.buildArguments(project: .test(), target: target, configuration: nil, skipSigning: true)

        // Then
        XCTAssertEqual(got, [
            .xcarg("CODE_SIGN_IDENTITY", ""),
            .xcarg("CODE_SIGNING_REQUIRED", "NO"),
            .xcarg("CODE_SIGN_ENTITLEMENTS", ""),
            .xcarg("CODE_SIGNING_ALLOWED", "NO"),
        ])
    }

    func test_buildArguments_when_theGivenConfigurationExists() throws {
        // Given
        let settings = Settings.test(base: [:], debug: .test(), release: .test())
        let target = Target.test(settings: settings)

        // When
        let got = subject.buildArguments(project: .test(), target: target, configuration: "Release", skipSigning: false)

        // Then
        XCTAssertTrue(got.contains(.configuration("Release")))
    }

    func test_buildArguments_when_theGivenConfigurationExistsInTheProject() throws {
        // Given
        let settings = Settings.test(base: [:], debug: .test(), release: .test())
        let target = Target.test(settings: nil)

        // When
        let got = subject.buildArguments(
            project: .test(settings: settings),
            target: target,
            configuration: "Release",
            skipSigning: false
        )

        // Then
        XCTAssertTrue(got.contains(.configuration("Release")))
    }

    func test_buildArguments_when_theGivenConfigurationDoesntExist() throws {
        // Given
        let settings = Settings.test(base: [:], configurations: [:])
        let target = Target.test(settings: settings)

        // When
        let got = subject.buildArguments(project: .test(), target: target, configuration: "Release", skipSigning: false)

        // Then
        XCTAssertFalse(got.contains(.configuration("Release")))
    }

    func test_buildableTarget() throws {
        // Given
        let path = try temporaryPath()
        let projectPath = path.appending(component: "Project.xcodeproj")
        let scheme = Scheme.test(buildAction: .test(targets: [.init(projectPath: projectPath, name: "Core")]))
        let target = Target.test(name: "Core")
        let project = Project.test(
            path: projectPath,
            targets: [
                target,
            ]
        )
        let graph = Graph.test(
            projects: [projectPath: project]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.buildableTarget(scheme: scheme, graphTraverser: graphTraverser)

        // Then
        XCTAssertEqual(got?.project, project)
        XCTAssertEqual(got?.target, target)
    }

    func test_testableTarget_whenNoTestActions_returnsNil() throws {
        // Given
        let path = try temporaryPath()
        let projectPath = path.appending(component: "Project.xcodeproj")

        let scheme = Scheme.test()
        let project = Project.test(path: projectPath)
        let graph = Graph.test(projects: [projectPath: project])
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.testableTarget(
            scheme: scheme,
            testPlan: nil,
            testTargets: [],
            skipTestTargets: [],
            graphTraverser: graphTraverser,
            action: .test
        )

        // Then
        XCTAssertNil(got)
    }

    func test_testableTarget_whenNoTestPlan_returnsFirstTarget() throws {
        // Given
        let path = try temporaryPath()
        let projectPath = path.appending(component: "Project.xcodeproj")
        let target = Target.test(name: "Test")
        let targetReference = TargetReference(projectPath: projectPath, name: target.name)

        let scheme = Scheme.test(
            testAction: .test(
                targets: [TestableTarget(target: targetReference)]
            )
        )
        let project = Project.test(
            path: projectPath,
            targets: [target]
        )
        let graph = Graph.test(
            projects: [projectPath: project]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.testableTarget(
            scheme: scheme,
            testPlan: nil,
            testTargets: [],
            skipTestTargets: [],
            graphTraverser: graphTraverser,
            action: .test
        )

        // Then
        XCTAssertEqual(got?.project, project)
        XCTAssertEqual(got?.target, target)
    }

    func test_testableTarget_withTestPlan_noFilters_returnsFirstEnabledTarget() throws {
        // Given
        let path = try temporaryPath()
        let projectPath = path.appending(component: "Project.xcodeproj")
        let target1 = Target.test(name: "Test1")
        let targetReference1 = TargetReference(projectPath: projectPath, name: target1.name)
        let target2 = Target.test(name: "Test2")
        let targetReference2 = TargetReference(projectPath: projectPath, name: target2.name)

        let testPlan = TestPlan(
            path: path.appending(component: "Test.testplan"),
            testTargets: [
                TestableTarget(target: targetReference1, skipped: true),
                TestableTarget(target: targetReference2, skipped: false),
            ],
            isDefault: true
        )
        let scheme = Scheme.test(
            testAction: .test(
                testPlans: [testPlan]
            )
        )
        let project = Project.test(
            path: projectPath,
            targets: [
                target1,
                target2,
            ]
        )
        let graph = Graph.test(
            projects: [projectPath: project]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.testableTarget(
            scheme: scheme,
            testPlan: testPlan.name,
            testTargets: [],
            skipTestTargets: [],
            graphTraverser: graphTraverser,
            action: .test
        )

        // Then
        XCTAssertEqual(got?.project, project)
        XCTAssertEqual(got?.target, target2)
    }

    func test_testableTarget_withTestPlan_filtersIncluded_returnsMachingTarget() throws {
        // Given
        let path = try temporaryPath()
        let projectPath = path.appending(component: "Project.xcodeproj")
        let target1 = Target.test(name: "Test1")
        let targetReference1 = TargetReference(projectPath: projectPath, name: target1.name)
        let target2 = Target.test(name: "Test2")
        let targetReference2 = TargetReference(projectPath: projectPath, name: target2.name)

        let testPlan = TestPlan(
            path: path.appending(component: "Test.testplan"),
            testTargets: [
                TestableTarget(target: targetReference1, skipped: false),
                TestableTarget(target: targetReference2, skipped: false),
            ],
            isDefault: true
        )
        let scheme = Scheme.test(
            testAction: .test(
                testPlans: [testPlan]
            )
        )
        let project = Project.test(
            path: projectPath,
            targets: [
                target1,
                target2,
            ]
        )
        let graph = Graph.test(
            projects: [projectPath: project]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = try subject.testableTarget(
            scheme: scheme,
            testPlan: testPlan.name,
            testTargets: [TestIdentifier(target: targetReference2.name)],
            skipTestTargets: [],
            graphTraverser: graphTraverser,
            action: .test
        )

        // Then
        XCTAssertEqual(got?.project, project)
        XCTAssertEqual(got?.target, target2)
    }

    func test_testableTarget_withTestPlan_filtersExcluded_returnsMachingTarget() throws {
        // Given
        let path = try temporaryPath()
        let projectPath = path.appending(component: "Project.xcodeproj")
        let target1 = Target.test(name: "Test1")
        let targetReference1 = TargetReference(projectPath: projectPath, name: target1.name)
        let target2 = Target.test(name: "Test2")
        let targetReference2 = TargetReference(projectPath: projectPath, name: target2.name)

        let testPlan = TestPlan(
            path: path.appending(component: "Test.testplan"),
            testTargets: [
                TestableTarget(target: targetReference1, skipped: false),
                TestableTarget(target: targetReference2, skipped: false),
            ],
            isDefault: true
        )
        let scheme = Scheme.test(
            testAction: .test(
                testPlans: [testPlan]
            )
        )
        let project = Project.test(
            path: projectPath,
            targets: [
                target1,
                target2,
            ]
        )
        let graph = Graph.test(
            projects: [projectPath: project]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = try subject.testableTarget(
            scheme: scheme,
            testPlan: testPlan.name,
            testTargets: [],
            skipTestTargets: [TestIdentifier(target: targetReference1.name)],
            graphTraverser: graphTraverser,
            action: .test
        )

        // Then
        XCTAssertEqual(got?.project, project)
        XCTAssertEqual(got?.target, target2)
    }

    func test_testableTarget_withTestPlan_filtersIncludedDisabledTarget_returnsNil() throws {
        // Given
        let path = try temporaryPath()
        let projectPath = path.appending(component: "Project.xcodeproj")
        let target1 = Target.test(name: "Test1")
        let targetReference1 = TargetReference(projectPath: projectPath, name: target1.name)
        let target2 = Target.test(name: "Test2")
        let targetReference2 = TargetReference(projectPath: projectPath, name: target2.name)

        let testPlan = TestPlan(
            path: path.appending(component: "Test.testplan"),
            testTargets: [
                TestableTarget(target: targetReference1, skipped: true),
                TestableTarget(target: targetReference2, skipped: false),
            ],
            isDefault: true
        )
        let scheme = Scheme.test(
            testAction: .test(
                testPlans: [testPlan]
            )
        )
        let project = Project.test(
            path: projectPath,
            targets: [
                target1,
                target2,
            ]
        )
        let graph = Graph.test(
            projects: [projectPath: project]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = try subject.testableTarget(
            scheme: scheme,
            testPlan: testPlan.name,
            testTargets: [TestIdentifier(target: targetReference1.name)],
            skipTestTargets: [],
            graphTraverser: graphTraverser,
            action: .test
        )

        // Then
        XCTAssertNil(got)
    }

    func test_buildableSchemes() throws {
        // Given
        let path = try temporaryPath()
        let projectPath = path.appending(component: "Project.xcodeproj")
        let coreProjectPath = path.appending(component: "CoreProject.xcodeproj")
        let coreScheme = Scheme.test(
            name: "Core",
            buildAction: .test(targets: [.init(projectPath: coreProjectPath, name: "Core")])
        )
        let kitScheme = Scheme.test(name: "Kit", buildAction: .test(targets: [.init(projectPath: projectPath, name: "Kit")]))
        let coreProject = Project.test(path: coreProjectPath, schemes: [coreScheme])
        let kitProject = Project.test(path: projectPath, schemes: [kitScheme])
        let workspaceScheme = Scheme.test(
            name: "Workspace-Scheme",
            buildAction: .test(
                targets: [
                    .init(projectPath: coreProjectPath, name: "Core"),
                    .init(projectPath: projectPath, name: "Kit"),
                ]
            )
        )
        let workspace = Workspace.test(schemes: [workspaceScheme])
        let graph = Graph.test(
            workspace: workspace,
            projects: [
                coreProject.path: coreProject,
                kitProject.path: kitProject,
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.buildableSchemes(graphTraverser: graphTraverser)

        // Then
        XCTAssertEqual(
            got,
            [
                coreScheme,
                kitScheme,
                workspaceScheme,
            ]
        )
    }

    func test_testSchemes() throws {
        // Given
        let path = try temporaryPath()
        let projectPath = path.appending(component: "Project.xcodeproj")
        let coreProjectPath = path.appending(component: "CoreProject.xcodeproj")
        let coreScheme = Scheme.test(
            name: "Core",
            testAction: .test(
                targets: [.init(target: .init(projectPath: projectPath, name: "CoreTests"))]
            )
        )
        let coreTestsScheme = Scheme(
            name: "CoreTests",
            testAction: .test(
                targets: [.init(target: .init(projectPath: projectPath, name: "CoreTests"))]
            )
        )
        let kitScheme = Scheme.test(
            name: "Kit",
            testAction: .test(
                targets: [.init(target: .init(projectPath: projectPath, name: "KitTests"))]
            )
        )
        let kitTestsScheme = Scheme(
            name: "KitTests",
            testAction: .test(
                targets: [.init(target: .init(projectPath: projectPath, name: "KitTests"))]
            )
        )
        let coreTarget = Target.test(name: "Core")
        let coreTestsTarget = Target.test(
            name: "CoreTests",
            product: .unitTests,
            dependencies: [.target(name: "Core")]
        )
        let coreProject = Project.test(
            path: coreProjectPath,
            targets: [
                coreTarget,
                coreTestsTarget,
            ],
            schemes: [coreScheme, coreTestsScheme]
        )
        let kitTarget = Target.test(name: "Kit", dependencies: [.target(name: "Core")])
        let kitTestsTarget = Target.test(
            name: "KitTests",
            product: .unitTests,
            dependencies: [.target(name: "Kit")]
        )
        let kitProject = Project.test(
            path: projectPath,
            targets: [
                kitTarget,
                kitTestsTarget,
            ],
            schemes: [kitScheme, kitTestsScheme]
        )
        let graph = Graph.test(
            projects: [
                kitProject.path: kitProject,
                coreProject.path: coreProject,
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.testSchemes(graphTraverser: graphTraverser)

        // Then
        XCTAssertEqual(
            got,
            [
                coreTestsScheme,
                kitTestsScheme,
            ]
        )
    }

    func test_testableSchemes() throws {
        // Given
        let path = try temporaryPath()
        let projectPath = path.appending(component: "Project.xcodeproj")
        let coreProjectPath = path.appending(component: "CoreProject.xcodeproj")
        let coreScheme = Scheme.test(
            name: "Core",
            testAction: .test(
                targets: [.init(target: .init(projectPath: projectPath, name: "CoreTests"))]
            )
        )
        let coreTestsScheme = Scheme(
            name: "CoreTests",
            testAction: .test(
                targets: [.init(target: .init(projectPath: projectPath, name: "CoreTests"))]
            )
        )
        let coreTarget = Target.test(name: "Core")
        let coreTestPlan = TestPlan(
            path: projectPath,
            testTargets: [TestableTarget(
                target: TargetReference(projectPath: projectPath, name: coreTarget.name),
                skipped: false
            )],
            isDefault: true
        )
        let coreTestPlanScheme = Scheme.test(
            name: "TestPlan",
            testAction: .test(
                testPlans: [coreTestPlan]
            )
        )
        let coreTestPlanTestsScheme = Scheme(
            name: "TestPlanTests",
            testAction: .test(
                testPlans: [coreTestPlan]
            )
        )
        let coreProject = Project.test(
            path: coreProjectPath,
            targets: [
                coreTarget,
            ],
            schemes: [coreScheme, coreTestsScheme, coreTestPlanScheme, coreTestPlanTestsScheme]
        )
        let graph = Graph.test(
            projects: [
                coreProject.path: coreProject,
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.testableSchemes(graphTraverser: graphTraverser)

        // Then
        XCTAssertEqual(
            got,
            [
                coreScheme,
                coreTestsScheme,
                coreTestPlanScheme,
                coreTestPlanTestsScheme,
            ]
        )
    }

    func test_buildableEntrySchemes_only_includes_entryTargets() throws {
        // Given
        let path = try temporaryPath()

        let projectAPath = path.appending(component: "ProjectA.xcodeproj")
        let schemeA = Scheme.test(buildAction: .test(targets: [.init(projectPath: projectAPath, name: "A")]))
        let targetA = Target.test(name: "A")
        let projectA = Project.test(
            path: projectAPath,
            targets: [targetA],
            schemes: [schemeA]
        )

        let projectBPath = path.appending(component: "ProjectB.xcodeproj")
        let schemeB = Scheme.test(buildAction: .test(targets: [.init(projectPath: projectBPath, name: "B")]))
        let targetB = Target.test(name: "B")
        let projectB = Project.test(
            path: projectBPath,
            targets: [targetB],
            schemes: [schemeB]
        )

        let graph = Graph.test(
            workspace: Workspace.test(projects: [projectA.path]),
            projects: [
                projectA.path: projectA,
                projectB.path: projectB,
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.buildableEntrySchemes(graphTraverser: graphTraverser)

        // Then
        XCTAssertEqual(got, [schemeA])
    }

    func test_workspacePath() async throws {
        // Given
        let path = try temporaryPath()
        let workspacePath = path.appending(component: "App.xcworkspace")
        try FileHandler.shared.createFolder(workspacePath)
        try FileHandler.shared.touch(workspacePath.appending(component: Constants.tuistGeneratedFileName))

        // When
        let got = try await subject.workspacePath(directory: path)

        // Then
        XCTAssertEqual(got, workspacePath)
    }

    func test_workspacePath_when_no_tuist_workspace_is_present() async throws {
        // Given
        let path = try temporaryPath()
        let workspacePath = path.appending(component: "App.xcworkspace")
        try FileHandler.shared.createFolder(workspacePath)

        // When
        let got = try await subject.workspacePath(directory: path)

        // Then
        XCTAssertNil(got)
    }

    func test_workspacePath_when_multiple_workspaces_are_present() async throws {
        // Given
        let path = try temporaryPath()
        let nonTuistWorkspacePath = path.appending(components: "SPM.xcworkspace")
        try FileHandler.shared.createFolder(nonTuistWorkspacePath)
        let workspacePath = path.appending(component: "TuistServer.xcworkspace")
        try FileHandler.shared.createFolder(workspacePath)
        try FileHandler.shared.touch(workspacePath.appending(component: Constants.tuistGeneratedFileName))

        // When
        let got = try await subject.workspacePath(directory: path)

        // Then
        XCTAssertEqual(got, workspacePath)
    }

    func test_projectSchemes_when_multiple_platforms() {
        // Given
        let graph: Graph = .test(
            workspace: .test(
                name: "WorkspaceName",
                schemes: [
                    .test(name: "WorkspaceName"),
                    .test(name: "WorkspaceName-Workspace"),
                ]
            )
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.workspaceSchemes(graphTraverser: graphTraverser)

        // Then
        XCTAssertEqual(
            got,
            [
                .test(name: "WorkspaceName-Workspace"),
            ]
        )
    }

    func test_projectSchemes_when_single_platform() {
        // Given
        let graph: Graph = .test(
            workspace: .test(
                name: "WorkspaceName",
                schemes: [
                    .test(name: "WorkspaceName"),
                    .test(name: "WorkspaceName-Workspace"),
                ]
            )
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.workspaceSchemes(graphTraverser: graphTraverser)

        // Then
        XCTAssertEqual(
            got,
            [
                .test(name: "WorkspaceName-Workspace"),
            ]
        )
    }

    func test_testableTarget_withMultipleTestPlans_noneSpecified_usesDefaultTetPlan() throws {
        // Given
        let path = try temporaryPath()
        let projectPath = path.appending(component: "Project.xcodeproj")
        let target1 = Target.test(name: "Test1")
        let targetReference1 = TargetReference(projectPath: projectPath, name: target1.name)
        let target2 = Target.test(name: "Test2")
        let targetReference2 = TargetReference(projectPath: projectPath, name: target2.name)

        let testPlan = TestPlan(
            path: path.appending(component: "Test.testplan"),
            testTargets: [
                TestableTarget(target: targetReference1, skipped: false),
            ],
            isDefault: false
        )

        let testPlan2 = TestPlan(
            path: path.appending(component: "Test2.testplan"),
            testTargets: [
                TestableTarget(target: targetReference2, skipped: false),
            ],
            isDefault: true
        )
        let scheme = Scheme.test(
            testAction: .test(
                testPlans: [testPlan, testPlan2]
            )
        )
        let project = Project.test(
            path: projectPath,
            targets: [
                target1,
                target2,
            ]
        )
        let graph = Graph.test(
            projects: [projectPath: project]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.testableTarget(
            scheme: scheme,
            testPlan: nil,
            testTargets: [],
            skipTestTargets: [],
            graphTraverser: graphTraverser,
            action: .test
        )

        // Then
        XCTAssertEqual(got?.project, project)
        XCTAssertEqual(got?.target, target2)
    }

    func test_testableTarget_withMultipleTestPlans_noneSpecified_findsTargetInNonDefaultPlan_when_action_is_build() throws {
        // Given
        let path = try temporaryPath()
        let projectPath = path.appending(component: "Project.xcodeproj")
        let target1 = Target.test(name: "Test1")
        let targetReference1 = TargetReference(projectPath: projectPath, name: target1.name)
        let target2 = Target.test(name: "Test2")
        let targetReference2 = TargetReference(projectPath: projectPath, name: target2.name)

        let testPlan = TestPlan(
            path: path.appending(component: "Test.testplan"),
            testTargets: [
                TestableTarget(target: targetReference1, skipped: false),
            ],
            isDefault: true
        )

        let testPlan2 = TestPlan(
            path: path.appending(component: "Test2.testplan"),
            testTargets: [
                TestableTarget(target: targetReference2, skipped: false),
            ],
            isDefault: false
        )
        let scheme = Scheme.test(
            testAction: .test(
                testPlans: [testPlan, testPlan2]
            )
        )
        let project = Project.test(
            path: projectPath,
            targets: [
                target1,
                target2,
            ]
        )
        let graph = Graph.test(
            projects: [projectPath: project]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.testableTarget(
            scheme: scheme,
            testPlan: nil,
            testTargets: [],
            skipTestTargets: [try TestIdentifier(target: "Test1")],
            graphTraverser: graphTraverser,
            action: .build
        )

        // Then
        XCTAssertEqual(got?.project, project)
        XCTAssertEqual(got?.target, target2)
    }
}
