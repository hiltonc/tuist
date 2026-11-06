import Path
import TuistTestSupport

public enum Fixtures {
    public static var directory: AbsolutePath {
        TestPaths.examplesDirectory
    }

    /// Fixtures under `cli/Fixtures`, which exercise CLI features without doubling as examples.
    public static var cliDirectory: AbsolutePath {
        TestPaths.repositoryRoot.appending(components: "cli", "Fixtures")
    }
}
