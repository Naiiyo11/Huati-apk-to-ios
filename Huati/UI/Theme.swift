import SwiftUI
import UIKit

enum Theme {
    static let ink = Color(red: 0.12, green: 0.21, blue: 0.32)
    static let muted = Color(red: 0.30, green: 0.36, blue: 0.45)
    static let blue = Color(red: 0.29, green: 0.48, blue: 0.67)
    static let light = Color(red: 0.90, green: 0.95, blue: 0.99)
}

@MainActor enum Art {
    private static let cache: NSCache<NSString, UIImage> = {
        let value = NSCache<NSString, UIImage>(); value.totalCostLimit = 32 * 1024 * 1024; return value
    }()
    static func image(_ path: String) -> UIImage? {
        if let image = cache.object(forKey: path as NSString) { return image }
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Resources/Art/" + path),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(image, forKey: path as NSString, cost: Int(image.size.width * image.size.height * image.scale * image.scale * 4))
        return image
    }
    static func mascot(_ index: Int, running: Bool) -> String {
        let value = abs(index) % 18
        return String(format: "mascots/%02d_%02d_%@.png", value / 3 + 1, value % 3 + 1, running ? "running" : "normal")
    }
}

struct ArtView: View {
    let path: String
    var mode: ContentMode = .fit
    var body: some View {
        if let image = Art.image(path) { Image(uiImage: image).resizable().aspectRatio(contentMode: mode).accessibilityHidden(true) }
    }
}

struct ModuleCard<Content: View>: View {
    @EnvironmentObject private var model: AppModel
    let title: String
    let subtitle: String
    let index: Int
    @ViewBuilder var content: Content
    init(_ title: String, subtitle: String = "", index: Int, @ViewBuilder content: () -> Content) {
        self.title = title; self.subtitle = subtitle; self.index = index; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(title).font(.system(.title3, design: .rounded).weight(.semibold)).foregroundStyle(Theme.ink)
                    if !subtitle.isEmpty { Text(subtitle).font(.subheadline).lineSpacing(4).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                ArtView(path: Art.mascot(index, running: model.running)).frame(width: 74.4, height: 81.6)
            }
            content
        }
        .padding(20).frame(maxWidth: 540, alignment: .leading)
        .background(.white.opacity(210.0 / 255), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.8), lineWidth: 1))
        .shadow(color: Theme.blue.opacity(0.07), radius: 14, y: 5)
    }
}

struct Note: View {
    let title: String
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
            Text(text).font(.subheadline).lineSpacing(5).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(Theme.light.opacity(0.8), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct ActionButton: View {
    let title: String
    var secondary = false
    let action: () -> Void
    var body: some View {
        Button(action: action) { Text(title).font(.body.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 14) }
            .foregroundStyle(secondary ? Theme.ink : .white)
            .background(secondary ? Theme.light : Theme.blue, in: RoundedRectangle(cornerRadius: 14))
            .buttonStyle(.plain)
    }
}

struct CompanionSheet<Content: View, Actions: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content
    @ViewBuilder let actions: Actions
    init(_ title: String, subtitle: String, @ViewBuilder content: () -> Content, @ViewBuilder actions: () -> Actions) {
        self.title = title; self.subtitle = subtitle; self.content = content(); self.actions = actions()
    }
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                ArtView(path: "icons/brand_head.png").frame(width: 88, height: 80)
                Text(title).font(.title2.bold()).foregroundStyle(Theme.ink)
                Text(subtitle).font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity).padding(24).background(Theme.light)
            ScrollView { VStack(alignment: .leading, spacing: 14) { content }.padding(22).frame(maxWidth: .infinity, alignment: .leading) }
            VStack(spacing: 10) { actions }.padding(20).background(.white)
        }.presentationDragIndicator(.visible).presentationCornerRadius(28)
    }
}

extension View {
    func entryStyle() -> some View {
        self.padding(13).background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.blue.opacity(0.2)))
    }
}
