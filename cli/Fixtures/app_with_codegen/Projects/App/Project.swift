import ProjectDescription

/// A dependent of both generating projects, declaring nothing about code generation, yet its hash must
/// move when the schema, an operation, the string catalog, or the shared template changes,
/// propagating through the `.project` dependencies below.
///
/// This is also the case that pins where a code generation target's derived edge can be
/// injected. A code generation target may name a consumer in another project, so injection has
/// to happen after every project exists as a model and before the graph is built: a
/// workspace mapper, not a per-project one.
let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.appwithcodegen",
            infoPlist: .default,
            sources: ["Sources/**"],
            dependencies: [
                .project(target: "GQLTypes", path: "//Projects/Core"),
                .project(target: "AccountUI", path: "//Projects/DesignSystem"),
            ]
        ),
    ]
)
