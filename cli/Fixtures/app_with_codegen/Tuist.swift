import ProjectDescription

/// Enough on its own to anchor the repo root: RootDirectoryLocator accepts the first of
/// Tuist/, Tuist.swift, tuist.toml, Plugin.swift, or .git/. That anchor is what `//` input
/// paths resolve against.
let tuist = Tuist()
