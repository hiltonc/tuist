---
{
  "title": "Code generators",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to declare commands that generate a target's sources from declared inputs."
}
---
# Code generators {#code-generators}

A code generator is a command that produces some of a target's sources from a declared set of inputs. SwiftGen accessors, typed localized strings, and Apollo GraphQL types are typical examples. Tuist runs it during `tuist generate`, `tuist build`, and `tuist test` and attaches its output to the target. Its declaration and inputs contribute to the target's [content hash](/guides/features/projects/hashing).

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

Tuist never hashes generated output. It hashes the generator's declaration instead, so `tuist hash` and `tuist graph` don't run any generator and give the same answer whether output exists or not. The hash covers:

- the command, the generator's name, and the target that declares it
- the values declared in `environment`
- for `.file`, the path and contents
- for `.folder`, the path, and the relative path and contents of every file in its tree
- for `.glob`, the pattern, and the path and contents of every match
- for `.script`, its standard output

Paths contribute as the manifest writes them: relative to the manifest's directory, or to the repository root when prefixed with `//`. Renaming an input therefore invalidates the output, since generators often derive type names from file names. Two checkouts at different locations still share cache hits. Inputs never resolve inside a `Derived` directory, so a pattern such as `//Projects/**/*.graphql` doesn't reach generated output.

Tuist warns, rather than failing, when a glob matches nothing. The pattern still contributes to the hash, so it changes once the first match appears.

The `environment` parameter names the variables the output depends on. Its values are added to the inherited environment and contribute to the hash; the rest of the environment, `PATH` included, doesn't. To capture which build of a tool ran, declare a `.script` input such as `.script("mise x -- swiftgen --version")`. Script inputs run from the repository root with `TUIST_ROOT_DIR` and the declared environment set. Nothing identifies the target or project, so the script and the declared environment determine the output, and within one `tuist generate`, `tuist build`, or `tuist test` Tuist runs each distinct pair once and reuses its output for every generator that declares it. Nothing is reused across invocations, so a script input still sees changes made since the last one.

> [!IMPORTANT]
> **Declare everything the output depends on**
>
> Tuist assumes a generator's output is a deterministic function of its command, declared inputs, and declared environment. A file or variable the generator reads without declaring it can produce an incorrect cache hit. Editing generated files by hand is invisible to the cache, and the next run overwrites them.

An input can't overlap an output directory in either direction.

## When generators run {#when-generators-run}

Tuist runs generators during `tuist generate`, `tuist build`, and `tuist test`, after focus, tree-shaking, and binary cache substitution. A target that's excluded or replaced by a cached binary doesn't run its generators. Tuist writes the project first and attaches output folders by path, so Xcode picks up their contents once the generators finish.

Tuist records each generator's hash under `Derived/CodeGen/State`. A generator is skipped when the recorded hash matches and its output directories exist, and Tuist reports how many it skipped, as in "16 code generators up to date". Otherwise it writes into fresh staging directories, and once it exits zero, Tuist updates the previous output to match them and records the new hash. As a result:

- a file whose contents and permissions are unchanged is left in place, keeping its modification date, so Xcode recompiles only what changed
- a changed file is replaced atomically, and a new one is added
- files a generator no longer produces disappear
- a failed run keeps the previous output, and a non-zero exit fails the command
- a run interrupted while output is being updated runs again next time

Tuist warns when a generator produces no files. On the next `tuist generate`, Tuist deletes output and state for generators or targets that no longer exist.

Generators run concurrently, including several instances of the same script for different targets. A script must therefore be safe to run alongside other instances of itself. One that builds its own tool on first use, for example, must hold a lock while it builds, or the tool must be built before Tuist runs.

Like `tuist hash`, `tuist inspect dependencies` doesn't run generators. It scans the output the last run left as part of each target's sources, so an import that appears only in generated code counts. When a target's output doesn't exist yet, it warns that the output wasn't inspected; run `tuist generate` first.

## Code generation targets {#code-generation-targets}

Some generators emit into several modules from one invocation, such as an Apollo configuration that splits schema types and operation types. A code generation target, created with `.codegen`, is a product-less target whose generator runs once and feeds several targets:

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

The consumers declare nothing about code generation. The code generation target that produces a consumer's output is its producer. For each output, Tuist writes to `Derived/CodeGen/Producers/{producer}/{consumer}/Sources` in the consumer's project and attaches that directory to the consumer. Tuist also adds a dependency from the consumer on its producer. A change to the generator's inputs therefore changes the hash of every consumer and of everything that depends on them. Use `.output(target:)` for a target in the same project and `.output(project:target:)` for one elsewhere. A target can have only one producer.

A code generation target's script receives the same environment as a per-target generator, with `TUIST_OUTPUTS_FILE` in place of `TUIST_OUTPUT_SOURCES_DIR`. It points at a JSON array with one entry per output:

```json
[
  { "project": "//Projects/Core", "target": "GQLSchema", "path": "/…/Sources" },
  { "project": "//Projects/Networking", "target": "GQLTransport", "path": "/…/Sources" }
]
```

Look outputs up by `project` and `target` rather than by position. Tuist generates a code generation target as an aggregate target that builds nothing, and produces or skips all its outputs together.

## One input split across targets {#one-input-split-across-targets}

Sometimes one input is split across many targets by per-target configuration. For example, a single `en.json` might be divided among feature modules by key globs in each module's configuration file, with one module's `**` catching the rest. Every target's output then depends on every target's configuration, since changing one module's globs can move keys into or out of any other. This can be declared in two forms:

- A per-target generator on each consumer that declares the shared input and all the configuration files, ideally through one `.glob` such as `.glob("//Projects/*/strings.yml")`, so a new module is picked up without editing the others.
- One code generation target whose `outputs` list every consumer, and whose script reads the input and configuration once and writes each target's share.

Prefer the code generation target. Per-target generators keep the consumers independent of each other, but because each one declares every configuration file, any edit reruns all of them. A code generation target runs once per change, but every consumer depends on it.

## Limitations {#limitations}

- A generator's output contributes sources only.
- One generator can't consume another's output; the order in which generators run is unspecified, and they can run at the same time.
- Targets resolved by a package manager can't declare or consume generators.
- Nothing sandboxes a generator, so it can read and write outside its declared inputs and output.

## Relationship to synthesized files {#relationship-to-synthesized-files}

[Synthesized files](/guides/features/projects/synthesized-files) such as resource accessors need no external tool, and Tuist maintains their templates. Prefer them where they fit, and use a code generator for file types or tools they don't cover.
