import Foundation
import Path
import TuistCore
import TuistLoader
import TuistServer
import TuistSupport

protocol SessionServicing: AnyObject {
    /// It prints any existing session in the keychain to authenticate
    /// on a server identified by that URL.
    func printSession(
        directory: String?
    ) async throws
}

final class SessionService: SessionServicing {
    private let serverSessionController: ServerSessionControlling
    private let serverURLService: ServerURLServicing
    private let configLoader: ConfigLoading

    // MARK: - Init

    init(
        serverSessionController: ServerSessionControlling = ServerSessionController(),
        serverURLService: ServerURLServicing = ServerURLService(),
        configLoader: ConfigLoading = ConfigLoader(warningController: WarningController.shared)
    ) {
        self.serverSessionController = serverSessionController
        self.serverURLService = serverURLService
        self.configLoader = configLoader
    }

    // MARK: - CloudAuthServicing

    func printSession(
        directory: String?
    ) async throws {
        let directoryPath: AbsolutePath
        if let directory {
            directoryPath = try AbsolutePath(validating: directory, relativeTo: FileHandler.shared.currentPath)
        } else {
            directoryPath = FileHandler.shared.currentPath
        }
        let config = try await configLoader.loadConfig(path: directoryPath)
        let serverURL = try serverURLService.url(configServerURL: config.url)
        try await serverSessionController.printSession(serverURL: serverURL)
    }
}
