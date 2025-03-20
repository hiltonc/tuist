import Foundation

public enum TuistAcceptanceFixtures {
    case appWithAirshipSDK
    case appWithAlamofire
    case appWithBuildRules
    case appWithComposableArchitecture
    case appWithCustomDefaultConfiguration
    case appWithCustomScheme
    case appWithExponeaSDK
    case appWithFrameworkAndTests
    case appWithGlobs
    case appWithGoogleMaps
    case appWithMetalOptions
    case appWithPlugins
    case appWithPocketSVG
    case appWithPreviews
    case appWithRealm
    case appWithRegistryAndAlamofire
    case appWithRegistryAndAlamofireAsXcodePackage
    case appWithRevenueCat
    case appWithSBTUITestTunnel
    case appWithSpmDependencies
    case appWithSpmModuleAliases

    case appWithSpmXcframeworkDependency
    case appWithSwiftCMark
    case appWithLocalSPMModuleWithRemoteDependencies
    case appWithTestPlan
    case appWithTests
    case appWithMacBundle
    case commandLineToolBasic
    case commandLineToolWithDynamicFramework
    case commandLineToolWithDynamicLibrary
    case commandLineToolWithStaticLibrary
    case frameworkWithEnvironmentVariables
    case frameworkWithMacroAndPluginPackages
    case frameworkWithNativeSwiftMacro
    case frameworkWithSwiftMacro
    case frameworkWithSPMBundle
    case generatediOSAppWithoutConfigManifest
    case invalidManifest
    case invalidWorkspaceManifestName
    case iosAppLarge
    case iosAppWithAppClip
    case iosAppWithBuildVariables
    case iosAppWithCoreData
    case iosAppWithCustomConfiguration
    case iosAppWithCustomDevelopmentRegion
    case iosWppWithCustomResourceParserOptions
    case iosAppWithCustomScheme
    case iosAppWithExtensions
    case iosAppWithDynamicFrameworksLinkingStaticFrameworks
    case iosAppWithFrameworkAndResources
    case iosAppWithFrameworkAndDisabledResources
    case iosAppWithFrameworkLinkingStaticFramework
    case iosAppWithFrameworks
    case iosAppWithHeaders
    case iosAppWithHelpers
    case iosAppWithImplicitDependencies
    case iosAppWithIncompatibleXcode
    case iosAppWithLocalBinarySwiftPackage
    case iosAppWithLocalSwiftPackage
    case iosAppWithMultiConfigs
    case iosAppWithNoneLinkingStatusFramework
    case iosAppWithOnDemandResources
    case iosAppWithPluginsAndTemplates
    case iosAppWithPrivacyManifest
    case iosAppWithSpmDependencies
    case iosAppWithSpmDependenciesForceResolvedVersions
    case iosAppWithRemoteBinarySwiftPackage
    case iosAppWithRemoteSwiftPackage
    case iosAppWithStaticFrameworks
    case iosAppWithStaticLibraries
    case iosAppWithStaticLibraryAndPackage
    case iosAppWithTemplates
    case iosAppWithTests
    case iosAppWithTransitiveFramework
    case iosAppWithWatchapp2
    case iosAppWithWeaklyLinkedFramework
    case iosAppWithXcframeworks
    case iosWorkspaceWithDependencyCycle
    case iosWorkspaceWithMicrofeatureArchitecture
    case iosAppWithCatalyst
    case macosAppWithCopyFiles
    case macosAppWithExtensions
    case manifestWithLogs
    case multiplatformApp
    case multiplatformAppWithExtension
    case multiplatformAppWithMacrosAndEmbeddedWatchOSApp
    case multiplatformAppWithSdk
    case multiplatformµFeatureUnitTestsWithExplicitDependencies
    case packageWithRegistryAndAlamofire
    case plugin
    case projectWithClassPrefix
    case projectWithFileHeaderTemplate
    case projectWithInlineFileHeaderTemplate
    case spmPackage
    case tuistPlugin
    case visionosApp
    case workspaceWithFileHeaderTemplate
    case workspaceWithInlineFileHeaderTemplate
    case xcodeApp
    case xcodeProjectWithInspectBuild
    case xcodeProjectiOSApp
    case xcodeProjectWithRegistryAndAlamofire
    case xcodeProjectWithTests
    case xcodeProjectWithPackagesAndTests
    case appWithExecutableNonLocalDependencies
    case appWithGeneratedSources
    case custom(String)

    public var path: String {
        switch self {
        case .appWithAirshipSDK:
            return "app_with_airship_sdk"
        case .appWithAlamofire:
            return "app_with_alamofire"
        case .appWithBuildRules:
            return "app_with_build_rules"
        case .appWithComposableArchitecture:
            return "app_with_composable_architecture"
        case .appWithCustomDefaultConfiguration:
            return "app_with_custom_default_configuration"
        case .appWithCustomScheme:
            return "app_with_custom_scheme"
        case .appWithExponeaSDK:
            return "app_with_exponea_sdk"
        case .appWithFrameworkAndTests:
            return "app_with_framework_and_tests"
        case .appWithGlobs:
            return "app_with_globs"
        case .appWithGoogleMaps:
            return "app_with_google_maps"
        case .appWithMetalOptions:
            return "app_with_metal_options"
        case .appWithPlugins:
            return "app_with_plugins"
        case .appWithPocketSVG:
            return "app_with_pocket_svg"
        case .appWithPreviews:
            return "app_with_previews"
        case .appWithRealm:
            return "app_with_realm"
        case .appWithRegistryAndAlamofire:
            return "app_with_registry_and_alamofire"
        case .appWithRegistryAndAlamofireAsXcodePackage:
            return "app_with_registry_and_alamofire_as_xcode_package"
        case .appWithRevenueCat:
            return "app_with_revenue_cat"
        case .appWithSBTUITestTunnel:
            return "app_with_sbtuitesttunnel"
        case .appWithSpmDependencies:
            return "app_with_spm_dependencies"
        case .appWithSpmModuleAliases:
            return "app_with_spm_module_aliases"
        case .appWithSpmXcframeworkDependency:
            return "app_with_spm_xcframework_dependency"
        case .appWithSwiftCMark:
            return "app_with_swift_cmark"
        case .appWithLocalSPMModuleWithRemoteDependencies:
            return "app_with_local_spm_module_with_remote_dependencies"
        case .appWithTestPlan:
            return "app_with_test_plan"
        case .appWithTests:
            return "app_with_tests"
        case .appWithMacBundle:
            return "app_with_mac_bundle"
        case .commandLineToolBasic:
            return "command_line_tool_basic"
        case .commandLineToolWithDynamicFramework:
            return "command_line_tool_with_dynamic_framework"
        case .commandLineToolWithDynamicLibrary:
            return "command_line_tool_with_dynamic_library"
        case .commandLineToolWithStaticLibrary:
            return "command_line_tool_with_static_library"
        case .frameworkWithEnvironmentVariables:
            return "framework_with_environment_variables"
        case .frameworkWithMacroAndPluginPackages:
            return "framework_with_macro_and_plugin_packages"
        case .frameworkWithNativeSwiftMacro:
            return "framework_with_native_swift_macro"
        case .frameworkWithSwiftMacro:
            return "framework_with_swift_macro"
        case .frameworkWithSPMBundle:
            return "framework_with_spm_bundle"
        case .generatediOSAppWithoutConfigManifest:
            return "generated_ios_app_without_config_manifest"
        case .invalidManifest:
            return "invalid_manifest"
        case .invalidWorkspaceManifestName:
            return "invalid_workspace_manifest_name"
        case .iosAppLarge:
            return "ios_app_large"
        case .iosAppWithAppClip:
            return "ios_app_with_appclip"
        case .iosAppWithBuildVariables:
            return "ios_app_with_build_variables"
        case .iosAppWithCoreData:
            return "ios_app_with_coredata"
        case .iosAppWithCustomConfiguration:
            return "ios_app_with_custom_configuration"
        case .iosAppWithCustomDevelopmentRegion:
            return "ios_app_with_custom_development_region"
        case .iosAppWithDynamicFrameworksLinkingStaticFrameworks:
            return "ios_app_with_dynamic_frameworks_linking_static_frameworks"
        case .iosWppWithCustomResourceParserOptions:
            return "ios_app_with_custom_resource_parser_options"
        case .iosAppWithCustomScheme:
            return "ios_app_with_custom_scheme"
        case .iosAppWithExtensions:
            return "ios_app_with_extensions"
        case .iosAppWithFrameworkAndResources:
            return "ios_app_with_framework_and_resources"
        case .iosAppWithFrameworkAndDisabledResources:
            return "ios_app_with_framework_and_disabled_resources"
        case .iosAppWithFrameworkLinkingStaticFramework:
            return "ios_app_with_framework_linking_static_framework"
        case .iosAppWithFrameworks:
            return "ios_app_with_frameworks"
        case .iosAppWithHeaders:
            return "ios_app_with_headers"
        case .iosAppWithHelpers:
            return "ios_app_with_helpers"
        case .iosAppWithImplicitDependencies:
            return "ios_app_with_implicit_dependencies"
        case .iosAppWithIncompatibleXcode:
            return "ios_app_with_incompatible_xcode"
        case .iosAppWithLocalBinarySwiftPackage:
            return "ios_app_with_local_binary_swift_package"
        case .iosAppWithLocalSwiftPackage:
            return "ios_app_with_local_swift_package"
        case .iosAppWithMultiConfigs:
            return "ios_app_with_multi_configs"
        case .iosAppWithNoneLinkingStatusFramework:
            return "ios_app_with_none_linking_status_framework"
        case .iosAppWithOnDemandResources:
            return "ios_app_with_on_demand_resources"
        case .iosAppWithSpmDependencies:
            return "ios_app_with_spm_dependencies"
        case .iosAppWithSpmDependenciesForceResolvedVersions:
            return "ios_app_with_spm_dependencies_forced_resolved_versions"
        case .iosAppWithPluginsAndTemplates:
            return "ios_app_with_plugins_and_templates"
        case .iosAppWithPrivacyManifest:
            return "ios_app_with_privacy_manifest"
        case .iosAppWithRemoteBinarySwiftPackage:
            return "ios_app_with_remote_binary_swift_package"
        case .iosAppWithRemoteSwiftPackage:
            return "ios_app_with_remote_swift_package"
        case .iosAppWithStaticFrameworks:
            return "ios_app_with_static_frameworks"
        case .iosAppWithStaticLibraries:
            return "ios_app_with_static_libraries"
        case .iosAppWithStaticLibraryAndPackage:
            return "ios_app_with_static_library_and_package"
        case .iosAppWithTemplates:
            return "ios_app_with_templates"
        case .iosAppWithTests:
            return "ios_app_with_tests"
        case .iosAppWithTransitiveFramework:
            return "ios_app_with_transitive_framework"
        case .iosAppWithWatchapp2:
            return "ios_app_with_watchapp2"
        case .iosAppWithWeaklyLinkedFramework:
            return "ios_app_with_weakly_linked_framework"
        case .iosAppWithXcframeworks:
            return "ios_app_with_xcframeworks"
        case .iosWorkspaceWithDependencyCycle:
            return "ios_workspace_with_dependency_cycle"
        case .iosWorkspaceWithMicrofeatureArchitecture:
            return "ios_workspace_with_microfeature_architecture"
        case .iosAppWithCatalyst:
            return "ios_app_with_catalyst"
        case .macosAppWithCopyFiles:
            return "macos_app_with_copy_files"
        case .macosAppWithExtensions:
            return "macos_app_with_extensions"
        case .manifestWithLogs:
            return "manifest_with_logs"
        case .multiplatformApp:
            return "multiplatform_app"
        case .multiplatformAppWithExtension:
            return "multiplatform_app_with_extension"
        case .multiplatformAppWithMacrosAndEmbeddedWatchOSApp:
            return "multiplatform_app_with_macros_and_embedded_watchos_app"
        case .multiplatformAppWithSdk:
            return "multiplatform_app_with_sdk"
        case .multiplatformµFeatureUnitTestsWithExplicitDependencies:
            return "multiplatform_µFeature_unit_tests_with_explicit_dependencies"
        case .packageWithRegistryAndAlamofire:
            return "package_with_registry_and_alamofire"
        case .plugin:
            return "plugin"
        case .projectWithClassPrefix:
            return "project_with_class_prefix"
        case .projectWithFileHeaderTemplate:
            return "project_with_file_header_template"
        case .projectWithInlineFileHeaderTemplate:
            return "project_with_inline_file_header_template"
        case .spmPackage:
            return "spm_package"
        case .tuistPlugin:
            return "tuist_plugin"
        case .visionosApp:
            return "visionos_app"
        case .workspaceWithFileHeaderTemplate:
            return "workspace_with_file_header_template"
        case .workspaceWithInlineFileHeaderTemplate:
            return "workspace_with_inline_file_header_template"
        case .xcodeApp:
            return "xcode_app"
        case .xcodeProjectWithInspectBuild:
            return "xcode_project_with_inspect_build"
        case .xcodeProjectiOSApp:
            return "xcode_project_ios_app"
        case .xcodeProjectWithRegistryAndAlamofire:
            return "xcode_project_with_registry_and_alamofire"
        case .xcodeProjectWithTests:
            return "xcode_project_with_tests"
        case .xcodeProjectWithPackagesAndTests:
            return "xcode_project_with_packages_and_tests"
        case .appWithExecutableNonLocalDependencies:
            return "app_with_executable_non_local_dependencies"
        case .appWithGeneratedSources:
            return "app_with_generated_sources"
        case let .custom(path):
            return path
        }
    }
}
