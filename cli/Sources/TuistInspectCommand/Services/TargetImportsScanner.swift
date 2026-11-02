#if os(macOS)
    import FileSystem
    import Mockable
    import Path
    import TuistAlert
    import XcodeGraph

    @Mockable
    protocol TargetImportsScanning {
        func imports(
            for target: XcodeGraph.Target,
            reachableModules: Set<String>?
        ) async throws -> Set<String>
    }

    extension TargetImportsScanning {
        /// Convenience that scans without `canImport` awareness.
        func imports(for target: XcodeGraph.Target) async throws -> Set<String> {
            try await imports(for: target, reachableModules: nil)
        }
    }

    struct TargetImportsScanner: TargetImportsScanning {
        private let importSourceCodeScanner: ImportSourceCodeScanner
        private let fileSystem: FileSysteming
        private let maxConcurrentFileScans: Int
        private let sourceCodeReader: (AbsolutePath) async throws -> String?

        init(
            importSourceCodeScanner: ImportSourceCodeScanner = ImportSourceCodeScanner(),
            fileSystem: FileSysteming = FileSystem(),
            maxConcurrentFileScans: Int = 100
        ) {
            self.init(
                importSourceCodeScanner: importSourceCodeScanner,
                fileSystem: fileSystem,
                maxConcurrentFileScans: maxConcurrentFileScans
            ) { path in
                guard try await fileSystem.exists(path) else { return nil }
                return try await fileSystem.readTextFile(at: path)
            }
        }

        init(
            importSourceCodeScanner: ImportSourceCodeScanner = ImportSourceCodeScanner(),
            fileSystem: FileSysteming = FileSystem(),
            maxConcurrentFileScans: Int = 100,
            sourceCodeReader: @escaping (AbsolutePath) async throws -> String?
        ) {
            self.importSourceCodeScanner = importSourceCodeScanner
            self.fileSystem = fileSystem
            self.maxConcurrentFileScans = max(1, maxConcurrentFileScans)
            self.sourceCodeReader = sourceCodeReader
        }

        func imports(
            for target: XcodeGraph.Target,
            reachableModules: Set<String>?
        ) async throws -> Set<String> {
            var filesToScan = target.sources.map(\.path) + target.buildableFolders.flatMap(\.resolvedFiles).map(\.path)
                .filter { Target.validSourceExtensions.contains($0.extension ?? "") }
            for folder in target.buildableFolders where folder.isGenerated {
                filesToScan.append(contentsOf: try await generatedSourceFiles(in: folder, of: target))
            }
            if let headers = target.headers {
                filesToScan.append(contentsOf: headers.private)
                filesToScan.append(contentsOf: headers.public)
                filesToScan.append(contentsOf: headers.project)
            }
            var imports = Set(
                try await filesToScan.concurrentMap(maxConcurrentTasks: maxConcurrentFileScans) { file in
                    try await matchPattern(at: file, reachableModules: reachableModules)
                }
                .flatMap { $0 }
            )
            imports.remove(target.productName)
            return imports
        }

        /// The graph attaches generator output with no resolved files, and inspecting never runs generators, so this
        /// reads whatever output the last generate, build, or test left.
        private func generatedSourceFiles(in folder: BuildableFolder, of target: XcodeGraph.Target) async throws
            -> [AbsolutePath]
        {
            guard try await fileSystem.exists(folder.path, isDirectory: true) else {
                AlertController.current.warning(.alert(
                    "The code generator output of target '\(target.name)' at \(folder.path.pathString) doesn't exist, so its imports weren't inspected. Run 'tuist generate' to produce it."
                ))
                return []
            }
            return try await fileSystem.glob(directory: folder.path, include: ["**/*"]).collect()
                .filter { Target.validSourceExtensions.contains($0.extension ?? "") }
                .sorted()
        }

        private func matchPattern(
            at path: AbsolutePath,
            reachableModules: Set<String>?
        ) async throws -> Set<String> {
            let language: ProgrammingLanguage
            switch path.extension {
            case "swift":
                language = .swift
            case "h", "m", "cpp", "mm":
                language = .objc
            default:
                return []
            }

            guard let sourceCode = try await sourceCodeReader(path) else {
                return Set()
            }

            return try importSourceCodeScanner.extractImports(
                from: sourceCode,
                language: language,
                reachableModules: reachableModules
            )
        }
    }
#endif
