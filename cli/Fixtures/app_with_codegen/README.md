# Fixture: custom code generators

Acceptance fixture for `codeGenerators:` and `.codegen` targets, from the RFC *Custom code
generators*. It exercises both primitives in a multi-project workspace and makes the
environment contract executable.

Three generators across the RFC's two primitives:

| | declared with | exercised by |
|---|---|---|
| **Per-target** | `codeGenerators:` on a target | `assets` on `AccountUI` in `Projects/DesignSystem`, reproducing the built-in `.assets()` synthesizer with an external tool |
| **Per-target, declared environment** | the same, plus `environment:` | `strings` on `AccountUI`, a second generator on one target whose output depends on a declared variable |
| **Multi-target** | a product-less `.codegen` target | `GQLCodegen` in `Projects/Core`, one Apollo-shaped run feeding both `GQLSchema` and `GQLTypes` |

`Projects/App` consumes generated output from both projects while declaring nothing about
codegen, which is the case that constrains where the derived dependency edge can be
injected.

## Running it

```sh
tuist generate --no-open
tuist build App --platform ios
tuist test AccountUITests --platform ios
```

`tuist generate` runs all three generators after writing the projects. `./generate.sh` runs
them without Tuist: they take no arguments and read only the environment Tuist supplies.
`generate.sh` sets exactly that environment, so it doubles as the executable specification of the contract: if a value in it
had to be hand-computed in a way Tuist could not, the contract would be wrong.

It also exists out of necessity. `**/Derived/` is gitignored and codegen output lives under
`Derived/CodeGen/`, so generated files cannot be committed and a fresh clone has none. That
is the correct state to reason from, and why the action hash must come from the
declaration rather than from output bytes, and why read-only commands have to work without
generating.

## Layout

Deliberately mirrors a multi-project repo, `Projects/{Name}/Project.swift` with shared
inputs at the root, because that makes the path semantics observable. With a
single root-level `Project.swift`, manifest-relative and root-relative paths would coincide
and the distinction below would be invisible.

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
Projects/App/Project.swift                   cross-project consumer, declares no codegen

Projects/{P}/Derived/CodeGen/Targets/{target}/{generator}/Sources/     per-target output
Projects/{P}/Derived/CodeGen/Producers/{producer}/{consumer}/Sources/  multi-target output
Projects/{P}/Derived/CodeGen/State/                            action hashes, never attached

The trailing `Sources/` names what the directory holds, so another kind of output can be
added later without moving what is already there. `State/` sits outside every attached
directory.
```

`Derived/` is per **project**, not per repo, following Tuist's existing convention
(`DeleteDerivedDirectoryProjectMapper.swift:33`). The two subtrees are separate so the
namespaces cannot collide: a per-target generator's path is keyed by
`(consuming target, generator name)` and a multi-target one's by
`(producing target, consuming target)`. Merged under one `{target}/{name}/` prefix, a
generator named `foo` on `AccountUI` and a `.codegen` target named `foo` that lists
`AccountUI` as an output would resolve to the same directory, and since the folder is
attached exactly once, whichever ran second would silently win.

No output path appears in any manifest. Tuist derives every one of them and attaches the
result as a buildable folder.

## Input paths

Inputs borrow `ForeignBuild.Input`'s four cases and its resolution, though not the type
itself, which discards the path identity a code generator depends on:

| form | resolves against |
|---|---|
| `"Sources/AccountUI/Resources"` | the directory containing `Project.swift`, **the default** |
| `"//templates/Assets.stencil"` | the repo root |

Both directions are exercised on purpose, because the two mistakes fail very differently.
Omitting `//` on the template resolves it under `Projects/DesignSystem/`, where nothing
exists, and the generator exits non-zero. A mis-scoped **glob** only warns and proceeds
with a hash over fewer files than intended. For codegen the pattern is retained unexpanded
and contributes itself to the action hash, so the hash still moves once a file matches.

## Environment contract

Common to every generator:

| variable | value |
|---|---|
| `TUIST_INPUTS_FILE` | path to a JSON array of `{type, path}`, one entry per declared path input, resolved absolute, globs already expanded. `.script` inputs contribute stdout to the hash and are absent |
| `TUIST_TARGET_NAME` | the owning target, or the `.codegen` target's own name |
| `TUIST_ROOT_DIR` | the repo root |
| `TUIST_PROJECT_DIR` | the **project** directory, not the repo root |

A per-target generator gets its output directory, created by Tuist before invoking:

| variable | value |
|---|---|
| `TUIST_OUTPUT_SOURCES_DIR` | where to write generated sources |

A multi-target generator has one directory per consumer, so instead:

| variable | value |
|---|---|
| `TUIST_OUTPUTS_FILE` | path to a JSON array of `{project, target, path}`, one entry per declared output |

Values declared in a generator's `environment:` are set too, and are part of the action
hash. Every output directory is a **staging** directory, moved into place only after a zero
exit. A generator writes files into the directory it is given, but must not hard-code that
directory's path inside them: the path it sees is not where those files end up.

Inputs and outputs travel in files rather than variables. A variable holding hundreds of
newline-separated paths competes with the argument and environment size limit and forces a
quoting convention on paths containing spaces; a file also lets each entry keep its type,
which matters because `.script` inputs are not paths at all. The outputs list is an array
rather than an object keyed by target because target names are not unique across projects: a
producer can legitimately feed a `Models` target in two of them.

### No script recomputes a path

This is a correctness property rather than tidiness. A generator that derives its own input set
performs a second, independent path computation that can disagree with what the manifest
declared and Tuist hashed, so the set of files hashed and the set actually read can
diverge. **A script reading only `$TUIST_INPUTS_FILE` cannot read an undeclared input.**

`apollo.sh` demonstrates the strong form: it consumes the pre-expanded
`.glob("//Projects/**/*.graphql")` instead of running its own `find`, so the operations it
reads are exactly the ones in the cache key. A generator that scanned for itself would have
to exclude `Derived/` by hand, and the moment any generator emitted a `.graphql` a scan that
forgot to would consume its own output.

All three select inputs by their declared **type**, not by position, so reordering `inputs:`
in a manifest cannot silently break them. `apollo.sh` does the same on the output side,
looking each entry up by target rather than taking them in order.

## Parity with `.assets()`

The per-target primitive is demonstrated against a case Tuist **already ships**, because if
`codeGenerators:` cannot reproduce `.assets()` it is not general enough to be worth adding.

`Codegen/swiftgen-assets.sh` matches the built-in's contract deliberately: same inputs
(every `.xcassets` under the target's resources), same output filename
(`TuistAssets+{Target}.swift`), same declared shape. This was **verified by diff**, not
inferred from the template: a throwaway project with only
`resourceSynthesizers: [.assets()]` over the same two catalogs was generated with
`tuist 4.204.0-canary.2` and its output compared:

```swift
public enum AccountUIAsset: Sendable {
  public enum Colors { public static let brandPrimary = AccountUIColors(name: "brandPrimary") }
  public enum Icons  { public static let iconWarning  = AccountUIColors(name: "iconWarning") }
}
```

Reading the template alone had produced two wrong conclusions, both of which the diff
caught: real output is `public` throughout, not `internal`, and the colour type is
`{Target}Colors` rather than a shared `ColorAsset`, namespaced per target, so two targets
in one module cannot collide. Per-catalog nesting once there is more than one catalog is
real (`AssetsTemplate.swift:114-119`), which is why `AccountUI` has two.

Remaining differences are all additive on the built-in's side and not worth reproducing in
a stand-in: `.color` / `.swiftUIColor` accessors, `swiftIdentifier` sanitizing, `Bundle.module`
threading, and symbol/image/data/ARKit groups. A real SwiftGen invocation would match them.

Three things the custom form does that `.assets()` cannot: pin a specific tool version (or
use something that is not SwiftGen), put that version in the cache key via
`.script("… --version")`, and apply per target rather than per project. What the built-in
still does better matters too: no tool on `PATH`, a Tuist-maintained template, works on a
fresh clone with no bootstrap. **The primitive is an escape hatch for what the built-ins do
not cover, not a replacement for them.**

## Properties to preserve when swapping in real generators

- Adding a `type` to `Codegen/schema.graphqls`, **or adding a `.graphql` file anywhere**,
  changes the generated file *set*. That makes manifest enumeration impossible and
  forces the buildable-folder approach.
- Adding a `.colorset`, **or a whole new `.xcassets`**, changes `AccountUIAsset`'s
  accessors. The built-in matches catalogs by extension rather than by a named path, so the
  generator takes the resources *root* and scans; declaring one catalog path would silently
  ignore the second.
- Removing `templates/Assets.stencil` from the declared inputs makes the assets generator
  exit non-zero rather than silently generating without a template. That makes
  "the declared inputs are the only inputs" observable.
- Adding a key to `Projects/DesignSystem/Strings/en.json` changes the `strings` generator's
  output, from one declared input.
- Flipping `STRINGS_ACCESS_LEVEL` changes every generated declaration. Declared through
  `environment:` it moves the action hash; left ambient it would not, which is the whole
  reason the parameter exists.
- Unsetting `STRINGS_ACCESS_LEVEL` makes the generator exit non-zero rather than assume a
  default, so a variable that reached the generator without reaching the cache key cannot
  pass unnoticed.
