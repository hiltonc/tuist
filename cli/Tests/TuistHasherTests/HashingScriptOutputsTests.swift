import Foundation
import Path
import Testing
import TuistProcess
import TuistTesting

@testable import TuistHasher

struct HashingScriptOutputsTests {
    private let commandRunner = MockCommandRunner()
    private let script = "git rev-parse HEAD"

    @Test
    func standardOutput_runsAScriptRequestedConcurrentlyOnce() async throws {
        let workingDirectory = try AbsolutePath(validating: "/project")
        commandRunner.succeedCommand(["/bin/sh", "-c", script], output: "abc123")
        let subject = HashingScriptOutputs()
        let commandRunner = commandRunner
        let script = script

        let outputs = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0 ..< 50 {
                group.addTask {
                    try await subject.standardOutput(
                        of: script,
                        workingDirectory: workingDirectory,
                        commandRunner: commandRunner
                    )
                }
            }
            return try await group.reduce(into: [String]()) { $0.append($1) }
        }

        #expect(outputs == Array(repeating: "abc123", count: 50))
        #expect(commandRunner.calls == ["/bin/sh -c \(script)"])
        #expect(commandRunner.workingDirectories == [workingDirectory])
    }

    @Test
    func standardOutput_runsTheSameScriptOncePerWorkingDirectory() async throws {
        let firstDirectory = try AbsolutePath(validating: "/project/App")
        let secondDirectory = try AbsolutePath(validating: "/project/Modules")
        commandRunner.succeedCommand(["/bin/sh", "-c", script], output: "abc123")
        let subject = HashingScriptOutputs()

        for directory in [firstDirectory, secondDirectory, firstDirectory, secondDirectory] {
            _ = try await subject.standardOutput(
                of: script,
                workingDirectory: directory,
                commandRunner: commandRunner
            )
        }

        #expect(commandRunner.workingDirectories == [firstDirectory, secondDirectory])
    }

    @Test
    func standardOutput_failsEveryRequestForAFailingScript() async throws {
        let workingDirectory = try AbsolutePath(validating: "/project")
        commandRunner.errorCommand(["/bin/sh", "-c", script], error: "not a git repository")
        let subject = HashingScriptOutputs()
        let expectedError = CommandError.terminated(
            1,
            stderr: "not a git repository",
            command: ["/bin/sh", "-c", script]
        )

        for _ in 0 ..< 3 {
            await #expect(throws: expectedError) {
                try await subject.standardOutput(
                    of: script,
                    workingDirectory: workingDirectory,
                    commandRunner: commandRunner
                )
            }
        }
        #expect(commandRunner.calls.count == 1)
    }
}
