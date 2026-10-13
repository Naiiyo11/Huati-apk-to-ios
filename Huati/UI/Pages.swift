import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct SimulationPage: View {
    @EnvironmentObject private var model: AppModel
    let seed: Int
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var distance = "2.20"
    @State private var minutes = "15"
    @State private var steps = "2600"
    @State private var confirmation = false
    private func parameters() throws -> (Int, Int, Int) {
        guard let km = Double(distance), km.isFinite, km >= 2, km <= 30,
              let min = Double(minutes), min.isFinite, min >= 1, min <= 120, let step = Int(steps) else { throw AppError("请检查里程、时长和步数") }
        return (Int((km * 1000).rounded()), Int((min * 60000).rounded()), step)
    }
    var body: some View {
        ModuleCard("起点与三点", subtitle: "使用手机定位，或填写 GCJ-02 起点坐标", index: seed) {
            Note(title: "模拟数据", text: "本应用生成的路线、步数与计时不代表实际运动。成绩以服务器判定为准。")
            HStack {
                TextField("纬度", text: $latitude).keyboardType(.numbersAndPunctuation).entryStyle()
                TextField("经度", text: $longitude).keyboardType(.numbersAndPunctuation).entryStyle()
            }
            ActionButton(title: "读取手机当前位置", secondary: true) {
                model.perform { try await model.readLocation(); latitude = model.config.object("location").text("lat"); longitude = model.config.object("location").text("lng") }
            }
            ActionButton(title: "获取随机三点") {
                model.perform {
                    guard let lat = Double(latitude), let lng = Double(longitude) else { throw AppError("请先读取或填写起点") }
                    try await model.loadPoints(lat: lat, lng: lng)
                }
            }
            ForEach(Array(model.preview.objects("points").enumerated()), id: \.offset) { index, point in
                HStack { Text("\(index + 1)").font(.caption.bold()).padding(8).background(Theme.light, in: Circle()); Text(point.text("point_name", point.text("name", "考核点"))).font(.subheadline); Spacer() }
            }
        }.disabled(model.busy)
        ModuleCard("本次模拟", subtitle: "先查看路线，再创建本次记录", index: seed + 2) {
            VStack(alignment: .leading, spacing: 8) {
                Text("目标里程 · 公里").font(.caption).foregroundStyle(Theme.muted)
                TextField("2.20", text: $distance).keyboardType(.decimalPad).entryStyle()
                Text("时长 · 分钟").font(.caption).foregroundStyle(Theme.muted)
                TextField("15", text: $minutes).keyboardType(.decimalPad).entryStyle()
                Text("步数").font(.caption).foregroundStyle(Theme.muted)
                TextField("2600", text: $steps).keyboardType(.numberPad).entryStyle()
            }
            Toggle("沿校园道路规划", isOn: Binding(get: { model.preferences.flag("road_mode") }, set: { model.setPreference("road_mode", value: $0) }))
            Note(title: "道路路线规则", text: "手动路线经过三点，目标里程允许 ±0.5 公里，至少 2.1 公里。自动路线经过三点且至少 2.1 公里，以实际路线里程提交。")
            ActionButton(title: "预览本次路线", secondary: true) {
                model.perform { let (m, t, s) = try parameters(); try model.previewRoute(metres: m, duration: t, steps: s) }
            }
            if !model.route.isEmpty {
                CampusMapView(route: model.route.objects("route_samples"), points: model.preview.objects("points"), showCatalog: false).frame(height: 300)
                Text(String(format: "预计实际里程 %.3f 公里", model.route.number("distance") / 1000)).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
            }
            ActionButton(title: "开始模拟记录") {
                model.perform { let (m, t, s) = try parameters(); try model.previewRoute(metres: m, duration: t, steps: s); confirmation = true }
            }
        }.disabled(model.busy)
        .onAppear { latitude = model.config.object("location").text("lat"); longitude = model.config.object("location").text("lng") }
        .sheet(isPresented: $confirmation) {
            CompanionSheet("创建模拟记录", subtitle: "请核对本次参数，确认后创建服务器记录") {
                metric("里程", String(format: "%.3f 公里", model.route.number("distance") / 1000))
                metric("时长", "\(minutes) 分钟")
                metric("步数", "\(steps) 步")
                Note(title: "结束后提交", text: "计时结束后直接校验并提交，包括服务器明确判为无效的结果。网络或提交结果不确定时停止并保留核实状态。")
                Note(title: "iPhone 后台", text: "建议保持应用在前台。锁屏或切到其他应用后，iOS 可能暂停执行；回到应用会恢复原记录，不会重复创建。")
            } actions: {
                ActionButton(title: "确认创建") {
                    confirmation = false
                    model.perform { let (m, t, s) = try parameters(); try await model.create(metres: m, duration: t, steps: s) }
                }
                ActionButton(title: "返回修改", secondary: true) { confirmation = false }
            }
        }
    }
    private func metric(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(Theme.muted); Spacer(); Text(value).fontWeight(.semibold).foregroundStyle(Theme.ink) }.padding(14).background(Theme.light, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct AutomaticPage: View {
    @EnvironmentObject private var model: AppModel
    let seed: Int
    @State private var hour = 6
    @State private var minute = 15
    private var latestMessage: String {
        if model.schedule.number("last_record_id") > 0, model.schedule.number("last_record_id") == model.run.number("record_id") {
            switch model.run.text("status") {
            case "finished": return model.run.flag("accepted_invalid") ? "自动记录已提交，服务器判为无效。" : "自动记录已提交，请查看服务器成绩。"
            case "paused": return "自动记录已暂停，可继续或舍弃。"
            case "discarded": return "自动记录已舍弃，可另设后续时间。"
            case "create_unknown", "finish_unknown": return "自动记录结果待核实，请查看官方小程序。"
            default: break
            }
        }
        return model.schedule.text("last_message")
    }
    var body: some View {
        ModuleCard("每日计划", subtitle: "北京时间 06:00–21:00，自选开始时间", index: seed + 3) {
            HStack {
                Picker("小时", selection: $hour) { ForEach(6...21, id: \.self) { Text(String(format: "%02d 时", $0)).tag($0) } }.pickerStyle(.menu)
                Spacer()
                Picker("分钟", selection: $minute) { ForEach(0..<60, id: \.self) { Text(String(format: "%02d 分", $0)).tag($0) } }.pickerStyle(.menu)
            }.entryStyle()
            ActionButton(title: "保存启动时间") { model.perform { try model.saveTime(hour: hour, minute: minute); model.message = "已保存每日启动时间" } }
            Toggle("开启每日自动模拟", isOn: Binding(get: { model.schedule.flag("enabled") }, set: { value in model.perform { try await model.enableDaily(value) } }))
            Note(title: "准备与时长", text: "提前 2 分钟读取位置，06:00 开放后刷新今日随机三点。定位失败或校外时选校内模拟起点。运行时长每次随机大于 12 分钟、小于 16 分钟，精确保存到毫秒，至少 2.1 公里，计满后直接提交。")
            if model.schedule.number("last_duration_ms") > 0 { Text("最近随机时长：" + Clock.duration(model.schedule.number("last_duration_ms"))).font(.subheadline.monospacedDigit()) }
            if !model.schedule.text("prep_message").isEmpty { Note(title: "准备状态", text: model.schedule.text("prep_message")) }
            if !latestMessage.isEmpty { Note(title: "最近任务", text: latestMessage) }
            if model.schedule.flag("enabled"), let target = try? model.core?.number("next", [model.schedule, model.now]) {
                Note(title: "下一次计划", text: Clock.label(target) + "（北京时间）\n后台执行机会由 iOS 决定，请以实际记录为准。")
            }
        }.disabled(model.busy)
        ModuleCard("锁屏与后台", subtitle: "iOS 由系统安排后台执行机会", index: seed + 4) {
            Note(title: "执行条件", text: "iPhone 没有精确后台闹钟。系统后台任务可能提前准备不足、延迟或不运行，开启后台刷新也不能保证准点执行。若需按计划执行，请让应用保持在前台并保持联网。通知只用于提醒。")
            Toggle("前台使用时保持屏幕常亮", isOn: Binding(get: { model.preferences.flag("keep_awake") }, set: { model.setPreference("keep_awake", value: $0) }))
            DisclosureGroup("苹果手机设置与排查") {
                Text("1. 设置 → 通用 → 后台 App 刷新，启用本应用与网络刷新。\n2. 设置 → 电池，关闭低电量模式。\n3. 允许应用通知，手机保持联网。\n4. 读取真实位置时允许使用期间定位与精确位置。苹果版不持续采集后台位置。\n5. 不要从最近应用中强制划掉本应用；重启后先解锁并打开一次。\n6. 在账号页查看后台排查报告，以实际唤醒事件判断，通知出现不等于任务执行。")
                    .font(.subheadline).lineSpacing(6).padding(.top, 10).foregroundStyle(Theme.muted)
            }
            ActionButton(title: "打开系统设置", secondary: true) { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
        }
        .onAppear { hour = Int(model.schedule.number("hour", 6)); minute = Int(model.schedule.number("minute", 15)) }
    }
}

struct RecordPage: View {
    @EnvironmentObject private var model: AppModel
    let seed: Int
    @State private var discardConfirmation = false
    private var status: String {
        ["created": "模拟中", "paused": "已暂停", "finished": "已完成提交", "discarded": "已舍弃本地模拟", "create_pending": "创建中", "create_unknown": "创建结果待核实", "checking": "校验中", "finish_pending": "提交中", "record_updated": "上传轨迹中", "finish_unknown": "提交结果待核实", "check_failed": "校验待处理"][model.run.text("status")] ?? "暂无当前记录"
    }
    var body: some View {
        ModuleCard("当前记录", subtitle: status, index: seed + 5) {
            if !model.run.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(String(format: "%.3f km", model.run.number("distance") / 1000)).font(.title2.bold())
                        Text("计划时长 " + Clock.duration(model.run.number("duration_ms", model.run.number("duration") * 1000))).font(.caption).monospacedDigit()
                    }
                    Spacer()
                    Text(Clock.duration(model.remaining)).font(.title3.weight(.medium)).monospacedDigit()
                }.foregroundStyle(Theme.ink)
                if ["created", "paused"].contains(model.run.text("status")) {
                    let duration = model.run.number("duration_ms", model.run.number("duration") * 1000)
                    ProgressView(value: duration > 0 ? min(1, max(0, 1 - model.remaining / duration)) : 0)
                    if model.running { Text("预计开始提交：" + Clock.label(model.now + model.remaining, precise: true)).font(.caption).foregroundStyle(Theme.muted) }
                }
                CampusMapView(route: model.run.objects("route_samples"), points: model.run.objects("points"), showCatalog: false).frame(height: 310)
                if model.run.flag("accepted_invalid") { Note(title: model.run.text("status") == "finished" ? "已提交无效记录" : "校验判为无效", text: model.run.text("invalid_reason", "服务器判为无效，详情以官方小程序为准。")) }
                if !model.run.text("error").isEmpty { Note(title: "需要处理", text: model.run.text("error")) }
                if !model.run.text("preflight_warning").isEmpty { Note(title: "成绩提示", text: model.run.text("preflight_warning")) }
                if model.run.text("status") == "created" { ActionButton(title: "暂停本次模拟", secondary: true) { model.perform { try model.pause() } } }
                if model.run.text("status") == "paused" { ActionButton(title: "继续本次模拟") { model.perform { try model.resume() } } }
                if ["created", "paused", "check_failed", "create_unknown", "finish_unknown"].contains(model.run.text("status")) {
                    ActionButton(title: "舍弃本次记录", secondary: true) { discardConfirmation = true }
                }
                if model.run.text("status") == "check_failed" || (model.run.text("status") == "created" && model.remaining == 0) {
                    ActionButton(title: "提交已计满的记录") { model.perform { try await model.finish() } }
                }
            } else { Note(title: "开始记录", text: "在模拟页获取三点并开始，或在自动页保存每日计划。") }
        }.disabled(model.busy)
        ModuleCard("服务器成绩", subtitle: "最终结果以官方小程序显示为准", index: seed + 6) {
            ActionButton(title: "查询服务器记录状态") { model.perform { try await model.refresh() } }
            if !model.results.isEmpty {
                let stats = model.results.object("statistics"), detail = model.results.object("record")
                VStack(alignment: .leading, spacing: 12) {
                    grade("累计有效", String(format: "%.2f 公里", stats.number("valid_grades")))
                    grade("累计无效", String(format: "%.2f 公里", stats.number("invalid_grades")))
                    grade("累计次数", "\(Int(stats.number("run_num"))) 次")
                    if !detail.isEmpty {
                        let verdict = detail.number("running_time") > 1 ? (detail.number("status") == 1 ? "有效" : "无效") : "尚未结束"
                        Note(title: String(format: "本次 %.2f 公里 · %@", detail.number("mileage") / 1000, verdict), text: detail.text("start_time") + (detail.text("warning").isEmpty ? "" : "\n原因：" + detail.text("warning")))
                    }
                    Text("查询于 " + Clock.label(model.results.number("checked_at"))).font(.caption).foregroundStyle(Theme.muted)
                }
            }
        }.disabled(model.busy)
        .sheet(isPresented: $discardConfirmation) {
            CompanionSheet("舍弃本次记录", subtitle: "舍弃后停止本地计时，无法继续本次模拟") {
                Note(title: "服务器记录保留", text: "这会停止本地自动提交。已创建的服务器占位记录不会被删除，仍可查询；结果待核实时请到官方小程序确认。")
            } actions: {
                ActionButton(title: "确认舍弃") { discardConfirmation = false; model.perform { try model.discard() } }
                ActionButton(title: "保留本次", secondary: true) { discardConfirmation = false }
            }
        }
    }
    private func grade(_ name: String, _ value: String) -> some View {
        HStack { Text(name).foregroundStyle(Theme.muted); Spacer(); Text(value).fontWeight(.semibold).foregroundStyle(Theme.ink) }.font(.subheadline)
    }
}

struct MapPage: View {
    @EnvironmentObject private var model: AppModel
    let seed: Int
    @State private var importing = false
    var body: some View {
        ModuleCard("奉贤校园地图", subtitle: "双指缩放、拖动与点位查看", index: seed + 7) {
            Toggle(model.catalog.flag("complete") ? "显示全部跑步点位（导入表）" : "显示已收集跑步点位", isOn: Binding(get: { model.preferences.flag("map_points") }, set: { model.setPreference("map_points", value: $0) }))
            CampusMapView(route: [], points: model.preview.objects("points"), showCatalog: model.preferences.flag("map_points")).frame(height: 470)
            Note(title: "点位目录", text: model.catalog.flag("complete") ? "完整性由导入文件声明；导入目录不会更改本次随机三点。" : "默认目录包含已知三个点及历次返回点位，尚无法确认是否齐全。可以导入完整点位表。")
            ActionButton(title: "导入校园点位表", secondary: true) { importing = true }
            Text("地图 © OpenStreetMap contributors · ODbL 1.0").font(.caption).foregroundStyle(Theme.muted)
        }.disabled(model.busy)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            model.perform { let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }; try model.importCatalog(Data(contentsOf: url)) }
        }
    }
}

struct SessionDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data = Data()
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct AccountPage: View {
    @EnvironmentObject private var model: AppModel
    let seed: Int
    @State private var login = false
    @State private var importing = false
    @State private var exporting = false
    @State private var document = SessionDocument()
    @State private var probe = false
    @State private var report = false
    @State private var clearing = false
    var body: some View {
        ModuleCard("登录与会话", subtitle: model.signedIn ? "已保存会话 · 账号尾号 " + String(model.config.text("student_id").suffix(4)) : "登录后使用本机加密会话", index: seed + 8) {
            ActionButton(title: "手机登录并获取会话") { login = true }
            ActionButton(title: "选择会话文件", secondary: true) { importing = true }
            ActionButton(title: "导出会话文件到手机", secondary: true) {
                model.perform { document = SessionDocument(data: try model.exportedSession()); exporting = true }
            }
            Note(title: "会话保存", text: "会话与记录在本机加密保存，密码和验证码不保存。导出的文件含登录会话，请只保存在自己的设备。")
            if model.signedIn { Button("清除本机会话", role: .destructive) { clearing = true }.font(.subheadline) }
        }.disabled(model.busy)
        ModuleCard("后台与排查", subtitle: "查看系统唤醒及任务阶段", index: seed + 10) {
            ActionButton(title: "一分钟后台自检", secondary: true) { model.perform { await model.startProbe(); probe = true } }
            ActionButton(title: "后台排查报告", secondary: true) { report = true }
            Note(title: "自检范围", text: "只请求服务器根路径进行匿名联网检查，不创建记录。iOS 自检的最早时间为一分钟后，系统可能延迟或不唤醒。")
        }
        ModuleCard("关于华理跑步姬", subtitle: "iOS 2.0.4 · 原生界面", index: seed + 12) {
            Text("本应用为个人使用的非官方工具。模拟轨迹不代表实际运动；服务器有效性规则仍然适用。").font(.subheadline).lineSpacing(5).foregroundStyle(Theme.muted)
            Link("地图来源与许可", destination: URL(string: "https://www.openstreetmap.org/copyright")!).font(.subheadline)
        }
        .sheet(isPresented: $login) { LoginView(seed: seed + 1) }
        .sheet(isPresented: $probe) {
            CompanionSheet("已安排后台自检", subtitle: "最早一分钟后，由 iOS 决定唤醒") {
                Note(title: "观察方式", text: "可以锁屏等待，然后打开后台排查报告。只有报告中的“后台自检已唤醒”才能说明后台实际执行。提醒通知本身不能证明执行。")
                Note(title: "无跑步操作", text: "本次仅做匿名网络自检，不读取账号、不请求登录或跑步接口。")
            } actions: { ActionButton(title: "知道了") { probe = false } }
        }
        .sheet(isPresented: $report) {
            CompanionSheet("后台排查报告", subtitle: "仅含设备状态与任务阶段，不含登录信息") {
                Text(model.report).font(.system(.subheadline, design: .monospaced)).lineSpacing(5).textSelection(.enabled).foregroundStyle(Theme.ink)
            } actions: {
                ActionButton(title: "复制报告") { UIPasteboard.general.string = model.report }
                ActionButton(title: "关闭", secondary: true) { report = false }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            model.perform { let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }; try await model.importSession(Data(contentsOf: url)) }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "huati-session") { result in
            if case .failure(let error) = result { model.message = error.localizedDescription }
        }
        .confirmationDialog("清除本机会话？", isPresented: $clearing, titleVisibility: .visible) {
            Button("确认清除", role: .destructive) { model.perform { try model.clearSession() } }
        }
    }
}

struct LoginView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let seed: Int
    @State private var phone = ""
    @State private var secret = ""
    @State private var byCode = true
    var body: some View {
        NavigationStack {
            ZStack {
                GeometryReader { geo in ArtView(path: "backgrounds/geometry_02.jpg", mode: .fill).frame(width: geo.size.width, height: geo.size.height).clipped() }.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        ModuleCard("手机登录", subtitle: "使用小程序绑定的手机号", index: seed) {
                            Picker("登录方式", selection: $byCode) { Text("短信验证码").tag(true); Text("账号密码").tag(false) }.pickerStyle(.segmented)
                            TextField("手机号", text: $phone).keyboardType(.phonePad).textContentType(.username).entryStyle()
                            if byCode {
                                TextField("短信验证码", text: $secret).keyboardType(.numberPad).textContentType(.oneTimeCode).entryStyle()
                                ActionButton(title: "获取验证码", secondary: true) { model.perform { try await model.sendSMS(phone.trimmingCharacters(in: .whitespaces)) } }
                            } else { SecureField("华体账号密码", text: $secret).textContentType(.password).entryStyle() }
                            ActionButton(title: model.busy ? "正在处理…" : "登录并获取会话") {
                                model.perform { try await model.phoneLogin(phone: phone.trimmingCharacters(in: .whitespaces), secret: secret, byCode: byCode); secret = ""; dismiss() }
                            }
                            Note(title: "本机保存", text: "登录完成后仅保存会话，密码与验证码不会写入本机文件。")
                        }.disabled(model.busy)
                    }.padding(18)
                }.scrollDismissesKeyboard(.interactively)
            }.navigationTitle("登录与会话").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { secret = ""; dismiss() }.disabled(model.busy) } }
        }.onChange(of: byCode) { _, _ in secret = "" }
        .onAppear { model.loginHandlesMessages = true }
        .onDisappear { model.loginHandlesMessages = false }
        .alert("登录与会话", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("知道了", role: .cancel) { model.message = nil }
        } message: { Text(model.message ?? "") }
    }
}
