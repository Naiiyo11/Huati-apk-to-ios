import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var opening = true
    @State private var wallpaper = Int.random(in: 1...19)
    @State private var tip = Int.random(in: 0..<20)
    @State private var artSeed = Int.random(in: 0..<18)
    private let labels = ["模拟", "自动", "记录", "地图", "账号"]

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                ArtView(path: String(format: "backgrounds/geometry_%02d.jpg", model.selectedTab % 3 + 1), mode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
            }.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("华理跑步姬").font(.system(.title2, design: .rounded).weight(.bold))
                        Text("\(labels[model.selectedTab])  /  iOS 2.0.4").font(.caption).tracking(1).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    if model.busy { ProgressView().tint(Theme.blue) }
                    else { Text(model.signedIn ? "会话已保存" : "待登录").font(.caption.weight(.medium)).padding(10).background(.white.opacity(0.85), in: Capsule()) }
                }.foregroundStyle(Theme.ink).padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 16)
                if let error = model.startupError {
                    ScrollView { Note(title: "本地数据需要检查", text: error).padding(20) }
                } else {
                    ScrollView {
                        VStack(spacing: 18) {
                            switch model.selectedTab {
                            case 0: SimulationPage(seed: artSeed)
                            case 1: AutomaticPage(seed: artSeed)
                            case 2: RecordPage(seed: artSeed)
                            case 3: MapPage(seed: artSeed)
                            default: AccountPage(seed: artSeed)
                            }
                        }.padding(.horizontal, 16).padding(.bottom, 26).frame(maxWidth: .infinity)
                    }.scrollDismissesKeyboard(.interactively)
                }
            }
            if opening { SplashView(wallpaper: wallpaper, tip: tip).transition(.opacity).zIndex(2) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { if !opening { bottomBar } }
        .task {
            do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { return }
            withAnimation(.easeOut(duration: 0.3)) { opening = false }
            model.activate()
        }
        .alert("华理跑步姬", isPresented: Binding(get: { model.message != nil && !model.loginHandlesMessages }, set: { if !$0 && !model.loginHandlesMessages { model.message = nil } })) {
            Button("知道了", role: .cancel) { model.message = nil }
        } message: { Text(model.message ?? "") }
        .tint(Theme.blue)
    }
    private var bottomBar: some View {
        HStack(spacing: 0) {
            ForEach(0..<5) { index in
                Button {
                    model.selectedTab = index; artSeed = Int.random(in: 0..<18)
                } label: {
                    VStack(spacing: 5) {
                        ZStack {
                            if index == 0 { ArtView(path: "icons/nav_running.png").frame(width: 48, height: 54) }
                            else if index == 4 { ArtView(path: "icons/nav_account.png").frame(width: 38.4, height: 38.4) }
                            else { Image(systemName: ["", "clock.badge.checkmark", "list.clipboard", "map", ""][index]).font(.system(size: 26, weight: .regular)) }
                        }.frame(height: 56)
                        Text(labels[index]).font(.caption.weight(model.selectedTab == index ? .semibold : .regular))
                    }.frame(maxWidth: .infinity).frame(minHeight: 88)
                        .foregroundStyle(model.selectedTab == index ? Theme.blue : Theme.muted)
                        .background(model.selectedTab == index ? Theme.light.opacity(0.7) : .clear, in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain).accessibilityLabel(labels[index])
            }
        }.padding(.horizontal, 8).padding(.vertical, 6).background(.ultraThinMaterial)
    }
}

struct SplashView: View {
    let wallpaper: Int
    let tip: Int
    private let tips = ["先热身，再出发，让身体慢慢进入节奏。", "肩膀放松，保持自然呼吸。", "天气炎热时避开暴晒，及时补水。", "跑完慢走几分钟再休息。", "校园路口留意行人，跑步也要看路。", "穿合脚的运动鞋，舒适更重要。", "循序渐进，给身体留出恢复时间。", "下雨路滑时放慢脚步。", "规律作息，好的休息也是训练的一部分。", "身体不舒服时，及时停下休息。", "把目光放远一点，找到自己的节奏。", "跑前检查鞋带。", "夜跑选择明亮路段。", "运动后温和拉伸。", "每一次实际运动都值得记录。", "模拟路线仅供演示，真实运动让身体更健康。", "先看天气再出门。", "脚步轻一些，保持稳定。", "留意身体感受，不必追赶别人的配速。", "带着好心情出发，也记得休息。"]
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                ArtView(path: String(format: "wallpapers/scene_%02d.jpg", wallpaper), mode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                LinearGradient(colors: [Color(red: 0.79, green: 0.89, blue: 0.99).opacity(0.95), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: geometry.size.width * 0.65).frame(maxWidth: .infinity, alignment: .leading)
                HStack(alignment: .top, spacing: 18) {
                    vertical("华理跑步姬—")
                    vertical("跑步记录模拟")
                    Spacer()
                }.padding(.leading, 30).padding(.top, geometry.safeAreaInsets.top + 65).frame(maxHeight: .infinity, alignment: .top)
                VStack(alignment: .leading, spacing: 12) {
                    Text("华理跑步姬").font(.title.bold())
                    Text("tips：" + tips[tip % tips.count]).font(.subheadline).lineSpacing(5)
                    Capsule().fill(Theme.blue.opacity(0.5)).frame(height: 3)
                }.foregroundStyle(Theme.ink).padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22)).padding(22).padding(.bottom, geometry.safeAreaInsets.bottom + 16)
            }
        }.ignoresSafeArea()
    }
    private func vertical(_ text: String) -> some View {
        VStack(spacing: 5) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, character in
                Text(String(character)).font(.system(size: 23, weight: .semibold, design: .serif)).rotationEffect(character == "—" ? .degrees(90) : .zero)
            }
        }.foregroundStyle(Theme.ink)
    }
}
