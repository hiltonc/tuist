import ProjectDescription

/// Code generators whose output holds resources. Each output folder declares what it holds, so the targets are
/// generated the same way before and after the generators first run.
let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .macOS,
            product: .app,
            bundleId: "dev.tuist.app-with-codegen-resources",
            infoPlist: .default,
            buildableFolders: ["App/Sources"],
            dependencies: [
                .target(name: "DynamicKit"),
                .target(name: "StaticKit"),
                .target(name: "MixedKit"),
            ]
        ),
        // A dynamic framework copies its resources through the synchronized folder.
        .target(
            name: "DynamicKit",
            destinations: .macOS,
            product: .framework,
            bundleId: "dev.tuist.dynamickit",
            buildableFolders: ["DynamicKit/Sources"],
            codeGenerators: [
                .script(
                    name: "resources",
                    script: #"printf Dynamic > "$TUIST_OUTPUT_SOURCES_DIR/dynamic.txt""#,
                    contents: [.resources]
                ),
            ]
        ),
        // A static framework moves its resources to the companion bundle.
        .target(
            name: "StaticKit",
            destinations: .macOS,
            product: .staticFramework,
            bundleId: "dev.tuist.statickit",
            buildableFolders: ["StaticKit/Sources"]
        ),
        .codegen(
            name: "ResourcesCodegen",
            script: #"exec "$TUIST_PROJECT_DIR/static.sh""#,
            inputs: [.file("static.sh")],
            outputs: [.output(target: "StaticKit", contents: [.resources])]
        ),
        // A static framework whose generated sources and resources share one folder, routed by file type.
        .target(
            name: "MixedKit",
            destinations: .macOS,
            product: .staticFramework,
            bundleId: "dev.tuist.mixedkit",
            codeGenerators: [
                .script(
                    name: "mixed",
                    script: #"exec "$TUIST_PROJECT_DIR/mixed.sh""#,
                    inputs: [.file("mixed.sh")],
                    contents: [.sources, .resources]
                ),
            ]
        ),
    ]
)
