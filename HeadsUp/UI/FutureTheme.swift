import SwiftUI

enum FutureTheme {
    static let actionBackground = Color(red: 0.32, green: 0.20, blue: 0.43)
    static let accent = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.77, green: 0.65, blue: 0.90, alpha: 1)
            : UIColor(red: 0.32, green: 0.20, blue: 0.43, alpha: 1)
    })
    static let background = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.07, green: 0.06, blue: 0.08, alpha: 1)
            : UIColor(red: 0.98, green: 0.975, blue: 0.973, alpha: 1)
    })
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let secondary = Color.secondary
}

struct FutureCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FutureTheme.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.7)
            }
    }
}

struct FutureSectionTitle: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title).font(.subheadline).foregroundStyle(FutureTheme.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FutureSettingsRow: View {
    let title: String
    var value: String
    var chevron: Bool

    init(_ title: String, value: String = "", chevron: Bool = true) {
        self.title = title
        self.value = value
        self.chevron = chevron
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title).foregroundStyle(.primary)
            Spacer(minLength: 8)
            if !value.isEmpty {
                Text(value).font(.subheadline).foregroundStyle(FutureTheme.secondary)
                    .multilineTextAlignment(.trailing)
            }
            if chevron {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    .foregroundStyle(FutureTheme.secondary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 18)
        .contentShape(Rectangle())
    }
}

struct FutureApp: Identifiable, Hashable {
    let id: String
    let name: String
    let minutes: Int

    static let samples: [FutureApp] = [
        .init(id: "xiaohongshu", name: "小红书", minutes: 52),
        .init(id: "wechat", name: "微信", minutes: 31),
        .init(id: "taobao", name: "淘宝", minutes: 17)
    ]
    static let available = samples + [
        FutureApp(id: "douyin", name: "抖音", minutes: 0),
        FutureApp(id: "bilibili", name: "哔哩哔哩", minutes: 0),
        FutureApp(id: "safari", name: "Safari", minutes: 0)
    ]
}

/// In-memory design data, intentionally separate from real usage and preferences.
@MainActor
final class FuturePreviewState: ObservableObject {
    @Published var apps = FutureApp.samples
}

struct FutureAppIcon: View {
    let app: FutureApp
    var size: CGFloat = 44

    private var color: Color {
        switch app.id {
        case "xiaohongshu": Color(red: 1, green: 0.05, blue: 0.22)
        case "wechat": Color(red: 0.02, green: 0.76, blue: 0.34)
        case "taobao": Color(red: 1, green: 0.35, blue: 0.04)
        case "douyin": .black
        case "bilibili": .pink
        default: .blue
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24).fill(color.gradient)
            switch app.id {
            case "xiaohongshu":
                Text("小红书").font(.system(size: size * 0.27, weight: .heavy))
            case "wechat":
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: size * 0.61, weight: .medium))
            case "taobao":
                Text("淘").font(.system(size: size * 0.7, weight: .semibold))
            case "douyin":
                Image(systemName: "music.note").font(.system(size: size * 0.6, weight: .bold))
            case "bilibili":
                Image(systemName: "tv").font(.system(size: size * 0.58, weight: .medium))
            default:
                Image(systemName: "safari").font(.system(size: size * 0.75, weight: .light))
            }
        }
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct FutureBrandIcon: View {
    var size: CGFloat = 40
    var body: some View {
        Image("HeadsUpBrand")
            .resizable().scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24))
            .accessibilityHidden(true)
    }
}
