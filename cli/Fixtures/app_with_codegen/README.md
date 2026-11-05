# Fixture: custom code generators

Acceptance fixture for `codeGenerators:` and code generation targets. It exercises both in a multi-project workspace, and `generate.sh` makes the environment contract executable.

It declares three generators:

| | Declared with | Exercised by |
|---|---|---|
| **Per-target** | `codeGenerators:` on a target | `assets` on `AccountUI` in `Projects/DesignSystem`, reproducing the built-in `.assets()` synthesizer with an external tool |
| **Per-target, declared environment** | the same, plus `environment:` | `strings` on `AccountUI`, a second generator on one target whose output depends on a declared variable |
| **Code generation target** | `.codegen` | `GQLCodegen` in `Projects/Core`, one Apollo-shaped run feeding both `GQLSchema` and `GQLTypes` |

`Projects/App` depends on `GQLTypes` and `AccountUI` in the other two projects and declares nothing about code generation.

## Running it

```sh
tuist generate --no-open
tuist build App --platform ios
tuist test AccountUITests --platform ios
```

Running `tuist generate` writes the projects and then runs all three generators. The generators read only the environment Tuist supplies. The `generate.sh` script runs them without Tuist and sets exactly that environment, so it doubles as an executable specification of the contract.

`**/Derived/` is gitignored and generated output lives under `Derived/CodeGen/`, so a fresh clone has no generated files.

## Layout

The fixture is a multi-project repo, `Projects/{Name}/Project.swift`, with shared inputs at the root, so manifest-relative and root-relative paths differ.

```
Tuist.swift                                  config
Workspace.swift                              projects: ["Projects/**"]
templates/Assets.stencil                     SHARED input at the root, needs `//` to reach
Codegen/swiftgen-assets.sh                   stands in for SwiftGen
Codegen/strings.sh                           typed accessors from a string catalog
Codegen/apollo.sh                            stands in for Apollo: 1 run → N output dirs
Codegen/schema.graphqls                      shared schema at the root
generate.sh                                  runs all three with the environment Tuist supplies

Projects/Core/Project.swift                  GQLCodegen → GQLSchema, GQLTypes
Projects/Core/Sources/GQLTypes/GraphQL/      .graphql operations (inputs, not sources)
Projects/DesignSystem/Project.swift          AccountUI's two per-target generators
Projects/DesignSystem/…/Resources/           Colors.xcassets, Icons.xcassets
Projects/DesignSystem/Strings/en.json        string catalog, OUTSIDE the buildable folder
Projects/DesignSystem/Tests/AccountUITests/  unit tests compiled against generated accessors
Projects/App/Project.swift                   cross-project consumer, declares no code generation

Projects/{P}/Derived/CodeGen/Targets/{target}/{generator}/Sources/     per-target output
Projects/{P}/Derived/CodeGen/Producers/{producer}/{consumer}/Sources/  code generation target output
Projects/{P}/Derived/CodeGen/State/                                    action hashes, never attached
```

The code generation target that produces a consumer's output is its producer. `Derived/` is per **project**, not per repo, following the convention `DeleteDerivedDirectoryProjectMapper` uses. A per-target generator's directory is keyed by `(consuming target, generator name)`, and a producer's by `(producer, consumer)`. The two subtrees are separate so those keys can't collide.

No output path appears in any manifest. Tuist derives every one of them and attaches the result as a buildable folder.

## Input paths

| Form | Resolves against |
|---|---|
| `"Sources/AccountUI/Resources"` | the directory containing `Project.swift`, **the default** |
| `"//templates/Assets.stencil"` | the repo root |

The fixture exercises both forms, and the two mistakes fail differently. Without `//`, the template resolves under `Projects/DesignSystem/`, where nothing exists, and Tuist fails because a declared `.file` input is missing. A mis-scoped **glob** only warns and hashes fewer files than intended. The unexpanded pattern is part of the action hash, so the hash still moves once a file matches.

## Environment contract

Common to every generator:

| Variable | Value |
|---|---|
| `TUIST_INPUTS_FILE` | path to a JSON array of `{type, path}` with absolute paths: one `file` entry per `.file` input, one `folder` entry per `.folder` input, and one `file` entry per `.glob` match. `.script` inputs contribute stdout to the hash and are absent |
| `TUIST_TARGET_NAME` | the target declaring the generator, or the code generation target itself |
| `TUIST_ROOT_DIR` | the repo root |
| `TUIST_PROJECT_DIR` | the **project** directory, not the repo root |

A per-target generator gets its output directory, created by Tuist before it runs:

| Variable | Value |
|---|---|
| `TUIST_OUTPUT_SOURCES_DIR` | where to write generated sources |

A code generation target has one directory per consumer, so instead:

| Variable | Value |
|---|---|
| `TUIST_OUTPUTS_FILE` | path to a JSON array of `{project, target, path}`, one entry per declared output |

Tuist also sets the values declared in a generator's `environment:`, and they're part of the action hash. Every output directory is a **staging** directory that Tuist moves into place after a zero exit. A generator writes files into the directory it's given but must not hard-code that directory's path inside them, because the files end up somewhere else.

`.script` inputs don't get this contract. They run from the repo root with only `TUIST_ROOT_DIR` and the declared `environment:` added to the inherited environment, so identical script inputs run once per command and share their output. A script input that needs per-target context takes it as an argument, such as a path relative to the root.

Inputs and outputs travel in JSON files, so each input keeps its type and no path needs quoting. The outputs file is an array because target names aren't unique across projects.

### No script derives its own paths

Each script reads its inputs from `$TUIST_INPUTS_FILE` and its output directories from `$TUIST_OUTPUT_SOURCES_DIR` or `$TUIST_OUTPUTS_FILE`. **A script reading only `$TUIST_INPUTS_FILE` reads only the inputs Tuist hashed.**

The `apollo.sh` script consumes the pre-expanded `.glob("//Projects/**/*.graphql")` instead of running its own `find`, so the operations it reads are exactly the ones in the cache key. The `swiftgen-assets.sh` script scans for catalogs only inside its declared `.folder` input, whose whole tree is in the hash.

None of the scripts depends on the order of `inputs:`. The `swiftgen-assets.sh` and `strings.sh` scripts select inputs by declared type and extension, and `apollo.sh` by extension. On the output side, `apollo.sh` looks each entry up by target rather than by position.

## Parity with `.assets()`

The `assets` generator reproduces a case Tuist already ships, the built-in `.assets()` synthesizer.

`Codegen/swiftgen-assets.sh` matches the built-in's contract: same inputs (every `.xcassets` under the target's resources), same output filename (`TuistAssets+{Target}.swift`), same declared shape. Its output for `AccountUI` matches what `resourceSynthesizers: [.assets()]` generates over the same two catalogs:

```swift
public enum AccountUIAsset: Sendable {
  public enum Colors { public static let brandPrimary = AccountUIColors(name: "brandPrimary") }
  public enum Icons  { public static let iconWarning  = AccountUIColors(name: "iconWarning") }
}
```

The output is `public` throughout, and the colour type is `{Target}Colors`, namespaced per target so two targets in one module can't collide. The built-in `assetsTemplate` nests one enum per catalog when there is more than one catalog, so `AccountUI` has two.

The built-in also generates `.color` / `.swiftUIColor` accessors, `swiftIdentifier` sanitizing, `Bundle.module` threading, and symbol, image, data, and ARKit groups. The stand-in doesn't reproduce them; a real SwiftGen invocation would.

The custom form can pin a specific tool version or use something other than SwiftGen. It can put that version in the cache key via `.script("… --version")`, and it applies per target rather than per project. The built-in needs no tool on `PATH`, uses a Tuist-maintained template, and works on a fresh clone with no bootstrap.

## Properties to preserve when swapping in real generators

- Adding a `type` to `Codegen/schema.graphqls`, **or adding a `.graphql` file anywhere**, changes the generated file *set*.
- Adding a `.colorset`, **or a whole new `.xcassets`**, changes `AccountUIAsset`'s accessors. Like the built-in, the generator takes the resources *root* and scans it for catalogs by extension.
- Removing `templates/Assets.stencil` from the declared inputs makes the assets generator exit non-zero rather than generate without a template. That makes "the declared inputs are the only inputs" observable.
- Adding a key to `Projects/DesignSystem/Strings/en.json` changes the `strings` generator's output, from one declared input.
- Flipping `STRINGS_ACCESS_LEVEL` changes every generated declaration, and because it's declared through `environment:`, it moves the action hash.
- Unsetting `STRINGS_ACCESS_LEVEL` makes the generator exit non-zero rather than assume a default. A variable that reached the generator without reaching the cache key can't pass unnoticed.
