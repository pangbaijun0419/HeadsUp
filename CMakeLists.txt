cmake_minimum_required(VERSION 3.29)

set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_OSX_DEPLOYMENT_TARGET 26.0)
project(HeadsUp LANGUAGES Swift)

set(HEADSUP_BUNDLE_IDENTIFIER "com.example.headsup" CACHE STRING "Bundle identifier for local builds")

set(HEADSUP_SOURCES
    HeadsUp/App/HeadsUpApp.swift
    HeadsUp/Core/Models.swift
    HeadsUp/Core/TrackerReducer.swift
    HeadsUp/Core/UsageDataExport.swift
    HeadsUp/Infrastructure/UsageStore.swift
    HeadsUp/Infrastructure/NotificationService.swift
    HeadsUp/Intents/XiaohongshuIntents.swift
    HeadsUp/UI/RootView.swift
    HeadsUp/UI/InterfaceVersion.swift
    HeadsUp/UI/FutureTheme.swift
    HeadsUp/UI/FutureRootView.swift
    HeadsUp/UI/FutureStatisticsView.swift
    HeadsUp/UI/FutureReminderView.swift
    HeadsUp/UI/DataManagementView.swift
    HeadsUp/Assets.xcassets
)

add_executable(HeadsUp MACOSX_BUNDLE ${HEADSUP_SOURCES})
set_source_files_properties(HeadsUp/Assets.xcassets PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
set_target_properties(HeadsUp PROPERTIES
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/HeadsUp/Info.plist"
    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "${HEADSUP_BUNDLE_IDENTIFIER}"
    XCODE_ATTRIBUTE_CODE_SIGN_STYLE "Automatic"
    XCODE_ATTRIBUTE_SWIFT_VERSION "6.0"
    XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1"
    XCODE_ATTRIBUTE_GENERATE_INFOPLIST_FILE "NO"
    XCODE_ATTRIBUTE_MARKETING_VERSION "1.0"
    XCODE_ATTRIBUTE_CURRENT_PROJECT_VERSION "5"
    XCODE_ATTRIBUTE_ASSETCATALOG_COMPILER_APPICON_NAME "AppIcon"
)
