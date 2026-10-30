---
{
  "title": "Code generators",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to declare commands that generate a target's sources from declared inputs."
}
---
# Code generators {#code-generators}

A code generator is a command that produces some of a target's sources from a declared set of inputs, such as SwiftGen accessors, typed localized strings, or Apollo GraphQL types. Declaring it in the manifest lets Tuist run it during `tuist generate`, `tuist build`, and `tuist test`, attach its output to the target, and fold its inputs into the target's [content hash](/guides/features/projects/hashing), so the generator needs no wrapper command and no caching of its own.

## Per-target generators {#per-target-generators}

A target lists the generators that produce its own sources in `codeGenerators`:

```swift
.target(
    name: "AccountUI",
    destinations: .iOS,
    product: .staticFramework,
    bundleId: "dev.tuist.accountui",
    buildableFolders: ["Sources/AccountUI"],
    codeGenerators: [
        .script(
            name: "assets",
            script: #"exec "$TUIST_ROOT_DIR/scripts/swiftgen-assets.sh""#,
            inputs: [
                .folder("Sources/AccountUI/Resources"),
                .file("//templates/Assets.stencil"),
                .script("mise x -- swiftgen --version"),
            ]
        ),
        .script(
            name: "strings",
            script: #"exec "$TUIST_ROOT_DIR/scripts/strings.sh""#,
            inputs: [.file("Strings/en.json")],
            environment: ["STRINGS_ACCESS_LEVEL": "public"]
        ),
    ]
)
```

No output path appears in the manifest. Tuist writes each generator's output to `Derived/CodeGen/Targets/{target}/{generator}/Sources` in the project's directory and attaches it to the target as a buildable folder. A generator's `name` is therefore a path component: it must be unique within the target, can't contain `/` or be `.` or `..`, and can't differ from another generator's name only by case or Unicode normalization. Target names that own or consume generated output follow the same rules within their project.

The script runs with `/bin/sh` from the project's directory. It inherits the environment, plus:

| Variable | Value |
| --- | --- |
| `TUIST_OUTPUT_SOURCES_DIR` | An empty directory to write sources into. Tuist moves it into place after the script exits zero, so generated files mustn't embed its path. |
| `TUIST_INPUTS_FILE` | A JSON array of `{"type", "path"}` entries with absolute paths: one per `.file`, one per `.folder`, and one per `.glob` match. `.script` inputs are absent. |
| `TUIST_TARGET_NAME` | The target that declares the generator. |
| `TUIST_PROJECT_DIR` | The directory containing the project's manifest. |
| `TUIST_ROOT_DIR` | The repository root. |

A generator reading only the files listed in `TUIST_INPUTS_FILE` guarantees that the files it reads are the files Tuist hashed.

## Inputs and hashing {#inputs-and-hashing}

Tuist never hashes generated output. It hashes the generator's declaration instead, so `tuist hash`, `tuist graph`, and `tuist inspect` don't run any generator and give the same answer whether output exists or not. The hash covers:

- the command, the generator's name, and the target that declares it
- the values declared in `environment`
- for `.file`, the path and contents
- for `.folder`, the path, and the relative path and contents of every file in its tree
- for `.glob`, the pattern, and the path and contents of every match
- for `.script`, its standard output

Paths contribute as the manifest writes them: relative to the manifest's directory, or to the repository root when prefixed with `//`. Renaming an input therefore invalidates the output, since generators often derive type names from file names, while two checkouts at different locations still share cache hits. Inputs never resolve inside a `Derived` directory, so a pattern such as `//Projects/**/*.graphql` doesn't reach generated output.

A glob that matches nothing is a warning, not an error. The pattern still contributes to the hash, so it changes once the first match appears.

`environment` names the variables the output depends on. Its values are added to the inherited environment and contribute to the hash; the rest of the environment, `PATH` included, doesn't. To capture which build of a tool ran, declare a `.script` input such as `.script("mise x -- swiftgen --version")`. Script inputs run from the project's directory with `TUIST_ROOT_DIR`, `TUIST_PROJECT_DIR`, `TUIST_TARGET_NAME`, and the declared environment set.

> [!IMPORTANT]
> **Declare everything the output depends on**
>
> Tuist assumes a generator's output is a deterministic function of its command, declared inputs, and declared environment. A file or variable the generator reads without declaring it can produce an incorrect cache hit. Editing generated files by hand is invisible to the cache, and the next run overwrites them.

An input can't overlap an output directory in either direction.

## When generators run {#when-generators-run}

`tuist generate`, `tuist build`, and `tuist test` run generators after focus, tree-shaking, and binary cache substitution, so a target that's excluded or replaced by a cached binary doesn't run its generators. The project is written first; output folders are attached by path, so Xcode picks up their contents once the generators finish.

Tuist records each generator's hash under `Derived/CodeGen/State`. A generator is skipped when the recorded hash matches and its output directories exist. Otherwise it writes into fresh staging directories, and once it exits zero, Tuist replaces the previous output and records the new hash. As a result:

- files a generator no longer produces disappear
- a failed run keeps the previous output, and a non-zero exit fails the command
- a run interrupted while output is being replaced runs again next time

A generator that produces no files is a warning. Output and state for generators or targets that no longer exist are deleted on the next `tuist generate`.

## Multi-target generators {#multi-target-generators}

Some generators emit into several modules from one invocation, such as an Apollo configuration that splits schema types and operation types. A product-less `.codegen` target runs once and feeds several targets:

```swift
.codegen(
    name: "GQLCodegen",
    script: #"exec "$TUIST_ROOT_DIR/Codegen/apollo.sh""#,
    inputs: [
        .file("//Codegen/schema.graphqls"),
        .glob("//Projects/**/*.graphql"),
        .script("mise x -- apollo-ios-cli --version"),
    ],
    outputs: [
        .output(target: "GQLSchema"),
        .output(project: "//Projects/Networking", target: "GQLTransport"),
    ]
)
```

The consumers declare nothing about code generation. For each output, Tuist writes to `Derived/CodeGen/Producers/{producer}/{consumer}/Sources` in the consumer's project, attaches it to the consumer, and adds a dependency from the consumer on the `.codegen` target, so a change to the generator's inputs changes the hash of every consumer and of everything that depends on them. `.output(target:)` names a target in the same project; `.output(project:target:)` names one elsewhere. A target can have only one producer.

A multi-target generator receives the same environment as a per-target one, with `TUIST_OUTPUTS_FILE` in place of `TUIST_OUTPUT_SOURCES_DIR`. It points at a JSON array with one entry per output:

```json
[
  { "project": "//Projects/Core", "target": "GQLSchema", "path": "/…/Sources" },
  { "project": "//Projects/Networking", "target": "GQLTransport", "path": "/…/Sources" }
]
```

Look outputs up by `project` and `target` rather than by position. The `.codegen` target generates as an aggregate target that builds nothing; all its outputs are produced, or skipped, together.

## Limitations {#limitations}

- A generator's output contributes sources only.
- One generator can't consume another's output; the order in which generators run is unspecified.
- Targets resolved by a package manager can't declare or consume generators.
- Nothing sandboxes a generator, so it can read and write outside its declared inputs and output.

## Relationship to synthesized files {#relationship-to-synthesized-files}

[Synthesized files](/guides/features/projects/synthesized-files) such as resource accessors stay as they are: they need no external tool, and their templates are maintained by Tuist. Prefer them where they fit, and use a code generator for file types or tools they don't cover.
