import FileSystem
import Foundation
import Path
import TuistCore
import TuistLoader
import TuistServer
import TuistSupport

protocol AccountUpdateServicing {
    func run(
        accountHandle: String?,
        handle: String?,
        directory: String?,
        onEvent: (AccountUpdateServiceEvent) -> Void
    ) async throws
}

enum AccountUpdateServiceEvent: CustomStringConvertible {
    case completed(handle: String)

    var description: String {
        switch self {
        case let .completed(handle): "The account \(handle) was successfully updated."
        }
    }
}

struct AccountUpdateService: AccountUpdateServicing {
    private let configLoader: ConfigLoading
    private let fileSystem: FileSysteming
    private let serverURLService: ServerURLServicing
    private let updateAccountService: UpdateAccountServicing
    private let authTokenRefreshService: AuthTokenRefreshServicing
    private let serverSessionController: ServerSessionControlling

    // MARK: - Init

    init(
        configLoader: ConfigLoading = ConfigLoader(),
        fileSystem: FileSysteming = FileSystem(),
        serverURLService: ServerURLServicing = ServerURLService(),
        updateAccountService: UpdateAccountServicing = UpdateAccountService(),
        authTokenRefreshService: AuthTokenRefreshServicing = AuthTokenRefreshService(),
        serverSessionController: ServerSessionControlling = ServerSessionController()
    ) {
        self.configLoader = configLoader
        self.fileSystem = fileSystem
        self.serverURLService = serverURLService
        self.updateAccountService = updateAccountService
        self.authTokenRefreshService = authTokenRefreshService
        self.serverSessionController = serverSessionController
    }

    func run(
        accountHandle: String?,
        handle: String?,
        directory: String?,
        onEvent: (AccountUpdateServiceEvent) -> Void
    ) async throws {
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(directory)
        let config = try await configLoader.loadConfig(path: directoryPath)
        let serverURL = try serverURLService.url(configServerURL: config.url)

        let passedAccountHandle = accountHandle
        let accountHandle: String
        if let passedAccountHandle {
            accountHandle = passedAccountHandle
        } else {
            accountHandle = try await serverSessionController.authenticatedHandle(serverURL: serverURL)
        }

        let account = try await updateAccountService.updateAccount(
            serverURL: serverURL,
            accountHandle: accountHandle,
            handle: handle
        )
        try await authTokenRefreshService.refreshTokens(serverURL: serverURL)

        onEvent(.completed(handle: account.handle))
    }
}

extension AccountUpdateServicing {
    func run(
        accountHandle: String?,
        handle: String?,
        directory: String?,
        onEvent: ((AccountUpdateServiceEvent) -> Void) = { AlertController.current.success(.alert("\($0.description)")) }
    ) async throws {
        try await run(
            accountHandle: accountHandle,
            handle: handle,
            directory: directory,
            onEvent: onEvent
        )
    }
}
