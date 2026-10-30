import ProjectDescription

/// A MULTI-TARGET generator, declared as a product-less `.codegen` target. One Apollo run
/// whose output is source for two targets, because a per-target split would reparse the
/// whole schema and rescan every `.graphql` file once per module.
///
/// Path semantics matter more here than in DesignSystem, because both inputs live outside
/// this project. A bare string is manifest-relative, so "Codegen/schema.graphqls" would
/// resolve to Projects/Core/Codegen/schema.graphqls and match nothing, and for the glob
/// that failure only warns.
let project = Project(
    name: "Core",
    targets: [
        // Product-less aggregate: one run, two consumers, nothing linked.
        .codegen(
            name: "GQLCodegen",
            // `exec` for the same reason as in DesignSystem. The script reads
            // $TUIST_INPUTS_FILE and $TUIST_OUTPUTS_FILE; $TUIST_ROOT_DIR only locates
            // the generator itself, since $TUIST_PROJECT_DIR is the project directory
            // rather than the repo root.
            script: #"exec "$TUIST_ROOT_DIR/Codegen/apollo.sh""#,
            inputs: [
                .file("//Codegen/schema.graphqls"),
                // Repo-WIDE operation scan, matching Apollo's real behaviour. Written
                // manifest-relative as "**/*.graphql" this would silently cover only
                // Projects/Core and miss operations in other projects.
                .glob("//Projects/**/*.graphql"),
                .script(#""$TUIST_ROOT_DIR/Codegen/apollo.sh" --version"#),
            ],
            // The single source of truth for this generator's fan-out: it yields one
            // output directory per consumer, the buildable folder attached to each, and
            // the build-ordering edge. Declared on the producer because only it knows its
            // own fan-out, since with several outputs Tuist cannot infer which directory
            // belongs to which consumer.
            outputs: [
                .output(target: "GQLSchema"),
                .output(target: "GQLTypes"),
                // A bare name identifies a consumer in this project. One elsewhere is
                // named explicitly, since a target name alone is not a workspace-wide
                // identity:
                // .output(project: "//Projects/Networking", target: "GQLTransport"),
            ]
        ),

        // Consumers declare nothing about codegen: not the output path, not the
        // dependency on GQLCodegen. Tuist derives the path, attaches the buildable
        // folder, and injects the edge into `target.dependencies` so the content hasher
        // sees it.
        .target(
            name: "GQLSchema",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "dev.tuist.appwithcodegen.gqlschema",
            buildableFolders: ["Sources/GQLSchema"]
        ),

        .target(
            name: "GQLTypes",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "dev.tuist.appwithcodegen.gqltypes",
            buildableFolders: ["Sources/GQLTypes"],
            dependencies: [
                .target(name: "GQLSchema"),
            ]
        ),
    ]
)
