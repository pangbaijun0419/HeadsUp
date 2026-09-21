import SwiftUI

/// Presentation only. Never used by the tracker, intents, or notification service.
enum InterfaceVersion: String, CaseIterable, Identifiable {
    case current
    case future

    static let storageKey = "headsup.interfaceVersion"
    var id: String { rawValue }
    var title: String { self == .current ? "当前版本" : "未来版本" }
}

struct InterfaceVersionPicker: View {
    @AppStorage(InterfaceVersion.storageKey) private var version = InterfaceVersion.current.rawValue

    var body: some View {
        Picker("界面版本", selection: $version) {
            ForEach(InterfaceVersion.allCases) { item in
                Text(item.title).tag(item.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("interfaceVersionPicker")
    }
}
