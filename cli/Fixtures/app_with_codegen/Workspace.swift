import ProjectDescription

/// Several projects rather than one, which is what makes the `//` vs manifest-relative
/// distinction observable: a manifest at Projects/Core/ cannot reach a repo-root input
/// without `//`. With a single root-level Project.swift the two forms would coincide.
let workspace = Workspace(
    name: "AppWithCodegen",
    projects: ["Projects/**"]
)
