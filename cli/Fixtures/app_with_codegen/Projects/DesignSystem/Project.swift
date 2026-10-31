import ProjectDescription

/// PER-TARGET generators, declared with `codeGenerators:`. The first does the built-in
/// `.assets()` synthesizer's job with an external tool; the second declares the environment
/// variable its output depends on, which the built-ins have no way to express.
///
/// Both input path forms are exercised, and this manifest lives at Projects/DesignSystem/
/// so the difference is observable:
///   - `.folder("Sources/AccountUI/Resources")` is manifest-relative, the target's own
///     input, which per-target scoping exists for.
///   - `.file("//templates/Assets.stencil")` is a repo-ROOT shared input. Written without
///     `//` it would resolve under Projects/DesignSystem/ and Tuist would reject it as a
///     missing input.
///
/// The template is also the case the built-in cannot hash: `.assets()` compiles its
/// template into the CLI, so a template edit ships with a CLI upgrade and never moves a
/// target hash. Declared as an input here, editing it invalidates exactly the targets that
/// use it.
let project = Project(
    name: "DesignSystem",
    targets: [
        .target(
            name: "AccountUI",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "dev.tuist.appwithcodegen.accountui",
            // No `resources:`. The catalogs are already inside the buildable folder, and
            // declaring them twice makes them members of both, which the built-in
            // synthesizer dedupes by basename only, so two catalogs named Colors.xcassets
            // in different subdirectories would silently collapse to one.
            buildableFolders: ["Sources/AccountUI"],
            codeGenerators: [
                .script(
                    name: "assets",
                    // No output path appears in this manifest: it is derived as
                    // Derived/CodeGen/Targets/AccountUI/assets/Sources/ and attached as a
                    // buildable folder by Tuist, so there is nothing to keep in sync.
                    //
                    // `exec` because this body's only job is to hand off: it replaces the
                    // shell rather than forking, so the generator's exit status and stderr
                    // surface directly. Contrast the `.script(…)` INPUT below, which must
                    // NOT use `exec`: Tuist captures its stdout for the cache key, and
                    // nothing after an `exec` runs.
                    script: #"exec "$TUIST_ROOT_DIR/Codegen/swiftgen-assets.sh""#,
                    inputs: [
                        // The resources ROOT, not one named catalog: the built-in matches
                        // every `.xcassets` by extension, and AccountUI has two (Colors,
                        // Icons) to prove the scan. Naming one path would silently ignore
                        // the second.
                        .folder("Sources/AccountUI/Resources"),
                        .file("//templates/Assets.stencil"),
                        // The tool's own version in the cache key, not expressible with
                        // the built-in, whose template ships inside the CLI.
                        .script(#""$TUIST_ROOT_DIR/Codegen/swiftgen-assets.sh" --version"#),
                    ]
                ),

                // A second generator on the same target. Its output directory is keyed by
                // `name:`, so the two cannot collide.
                .script(
                    name: "strings",
                    script: #"exec "$TUIST_ROOT_DIR/Codegen/strings.sh""#,
                    inputs: [
                        // Outside `Sources/AccountUI` deliberately: inside the buildable
                        // folder the catalog would ship as a resource of the target, which
                        // is not the point of generating accessors from it.
                        .file("Strings/en.json"),
                        .script(#""$TUIST_ROOT_DIR/Codegen/strings.sh" --version"#),
                    ],
                    // A variable the generator's output depends on. Ambient it would be
                    // invisible to the cache key, so flipping it would leave every hash
                    // unmoved while changing every generated declaration.
                    environment: ["STRINGS_ACCESS_LEVEL": "public"]
                ),
            ]
        ),

        // Compiles against generated accessors, so `tuist test` exercises generated code.
        .target(
            name: "AccountUITests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.appwithcodegen.accountuitests",
            buildableFolders: ["Tests/AccountUITests"],
            dependencies: [
                .target(name: "AccountUI"),
            ]
        ),
    ],
    // The `assets` generator takes the place of the built-in `.assets()` synthesizer and writes the same
    // `TuistAssets+AccountUI.swift`, so the built-ins are turned off for this project.
    resourceSynthesizers: []
)
