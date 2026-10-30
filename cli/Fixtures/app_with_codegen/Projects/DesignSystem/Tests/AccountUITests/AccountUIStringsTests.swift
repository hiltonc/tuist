import AccountUI
import Testing

struct AccountUIStringsTests {
    @Test func strings_are_generated_from_the_catalog() {
        #expect(AccountUIStrings.accountTitle == "Account")
        #expect(AccountUIStrings.accountSignOut == "Sign Out")
    }

    @Test func assets_are_namespaced_per_catalog() {
        #expect(AccountUIAsset.Colors.brandPrimary.name == "brandPrimary")
        #expect(AccountUIAsset.Icons.iconWarning.name == "iconWarning")
    }
}
