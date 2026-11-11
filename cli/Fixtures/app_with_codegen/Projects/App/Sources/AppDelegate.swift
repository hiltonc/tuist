import AccountUI
import GQLTypes
import UIKit

/// Consumes generated code from both primitives, across project boundaries, while
/// declaring nothing about codegen:
///   - Account / AccountQuery  ← Projects/Core, multi-target GQLCodegen aggregate
///   - AccountUIAsset          ← Projects/DesignSystem, per-target codeGenerator
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        _ = Account()
        _ = AccountQuery.operationName
        // AccountUI has two catalogs (Colors, Icons), so the assets template namespaces accessors per catalog.
        _ = AccountUIAsset.Colors.brandPrimary
        return true
    }
}
