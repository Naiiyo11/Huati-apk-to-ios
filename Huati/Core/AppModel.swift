import Foundation
import SwiftUI
import UIKit

@MainActor final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published var config: JSON = [:]
    @Published var run: JSON = [:]
    @Published var preview: JSON = [:]
    @Published var route: JSON = [:]
    @Published var schedule: JSON = ["hour": 6, "minute": 15, "enabled": false]
    @Published var results: JSON = [:]
    @Published var catalog: JSON = [:]
    @Published var preferences: JSON = [:]
    @Published var busy = false
    @Published var message: String?
    @Published var loginHandlesMessages = false
    @Published var selectedTab = 0
    @Published var now = Clock.now
    @Published var startupError: String?
    private(set) var core: CoreBridge?
    private var store: SecureStore?
    private let location = PhoneLocation()
    private var timer: Timer?
    private var diagnosticEvents: [JSON] = []
    private var operation: Task<Void, Never>?
    private let processID = UUID().uuidString

    var signedIn: Bool { !config.text("student_id").isEmpty }
    var unresolved: Bool { !run.isEmpty && !["finished", "discarded"].contains(run.text("status")) }
    var activeRecord: Bool { run.text("status") == "created" && run.flag("auto_submit") }
    var running: Bool { activeRecord && ((try? core?.number("remaining", [run, Clock.now])) ?? 0) > 0 }
    var remaining: Double { (try? core?.number("remaining", [run, now])) ?? 0 }
    var report: String {
        let header = "华理跑步姬 iOS 2.0.4\niOS \(UIDevice.current.systemVersion)\n后台刷新：\(UIApplication.shared.backgroundRefreshStatus == .available ? "允许" : "不可用或受限")\n低电量模式：\(ProcessInfo.processInfo.isLowPowerModeEnabled ? "开启" : "关闭")\n\n背景任务由 iOS 决定唤醒时机，通知不会执行网络请求。\n报告不含账号、会话、手机号、坐标和请求正文。\n\n"
        return header + diagnosticEvents.map { "\(Clock.label($0.number("at"))) · \($0.text("event")) · \($0.text("state"))" }.joined(separator: "\n")
    }

    private init() {
        do {
            let disk = try SecureStore(); store = disk; core = try CoreBridge()
            config = try disk.read("config") ?? [:]; run = try disk.read("run") ?? [:]
            preview = try disk.read("points") ?? [:]; route = try disk.read("route") ?? [:]
            results = try disk.read("results") ?? [:]; preferences = try disk.read("preferences") ?? [:]
            schedule = try disk.read("schedule") ?? schedule
            catalog = try disk.read("catalog") ?? ["complete": false, "source": "公开参考与历次服务器点位", "points": Self.referencePoints]
            if catalog.objects("points").isEmpty { catalog = ["complete": false, "points": Self.referencePoints, "source": "公开参考的三个点位"] }
            diagnosticEvents = try disk.read("diagnostics")?.objects("events") ?? []
            try recover()
        } catch { startupError = "本地数据暂不可用，已保留原文件。\n" + error.localizedDescription }
    }

    static let referencePoints: [JSON] = [
        ["point_name": "单双杠练习场", "lat": 30.832999, "lng": 121.509337],
        ["point_name": "考核点 38", "lat": 30.827536, "lng": 121.503933],
        ["point_name": "体育馆主馆", "lat": 30.829844, "lng": 121.507996]
    ]
    private func disk() throws -> SecureStore {
        guard startupError == nil, let store else { throw AppError("请先解决本地存储问题，避免覆盖原记录") }
        return store
    }
    private func rules() throws -> CoreBridge { guard let core else { throw AppError("本地规则不可用") }; return core }
    private func api() throws -> HuatiAPI { try HuatiAPI(config: config) }
    private func saveRun(_ value: JSON) throws { try disk().write("run", value); run = value }
    private func saveSchedule(_ value: JSON) throws { try disk().write("schedule", value); schedule = value }
    private func event(_ value: String) {
        diagnosticEvents.append(["at": Clock.now, "event": value, "state": UIApplication.shared.applicationState == .active ? "前台" : "后台"])
        diagnosticEvents = Array(diagnosticEvents.suffix(100))
        try? store?.write("diagnostics", ["events": diagnosticEvents])
    }
    private func recover() throws {
        var state = run
        switch state.text("status") {
        case "checking": state["status"] = "created"; state = try rules().object("pause", [state, Clock.now])
        case "create_pending": state["status"] = "create_unknown"
        case "finish_pending", "record_updated": state["status"] = "finish_unknown"
        default: state = [:]
        }
        if !state.isEmpty { state["auto_submit"] = false; state["error"] = "上次操作被中断，请在官方小程序核实，不会重复创建或提交。"; try saveRun(state) }
        if ["locating", "fetching"].contains(schedule.text("prep_status")) {
            var value = schedule; value["prep_status"] = "waiting_points"; value["retry_ms"] = 0
            value.removeValue(forKey: "prepared_preview"); value.removeValue(forKey: "prepared_refresh_ms"); try saveSchedule(value)
        }
        if schedule.text("last_status") == "creating" {
            var value = schedule; value["last_status"] = "interrupted"; value["last_message"] = "自动创建被中断，请核实原记录。本次时间不会重复创建。"; try saveSchedule(value)
        }
    }

    func activate() {
        guard startupError == nil else { return }
        event("打开应用")
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
        guard let self else { return }

        Task { @MainActor [self] in
            let time = Clock.now
            if self.activeRecord || floor(time / 1000) != floor(self.now / 1000) {
                self.now = time
            }
            if !self.busy {
                self.operation = Task { await self.service() }
            }
        }
    }
        UIApplication.shared.isIdleTimerDisabled = preferences.flag("keep_awake")
        operation = Task { await service() }
        BackgroundCoordinator.shared.schedule(self)
    }
    func deactivate() {
        timer?.invalidate(); timer = nil; UIApplication.shared.isIdleTimerDisabled = false
        event("进入后台")
        BackgroundCoordinator.shared.schedule(self)
    }
    func cancelCurrentWork() { operation?.cancel() }
    func perform(_ work: @escaping () async throws -> Void) {
        guard !busy, startupError == nil else { return }; busy = true
        operation = Task {
            defer { busy = false; now = Clock.now; BackgroundCoordinator.shared.schedule(self) }
            do { try await work() } catch { message = error.localizedDescription }
        }
    }
    func setPreference(_ key: String, value: Bool) {
        do { var next = preferences; next[key] = value; try disk().write("preferences", next); preferences = next
            if key == "road_mode" { route = [:]; try disk().remove("route") }
            if key == "keep_awake", UIApplication.shared.applicationState == .active { UIApplication.shared.isIdleTimerDisabled = value }
        } catch { message = error.localizedDescription }
    }
    func saveTime(hour: Int, minute: Int) throws {
        guard try rules().flag("validTime", [hour, minute]) else { throw AppError("自动时间需在北京时间 06:00–21:00，最晚 21:00") }
        var next = schedule
        if next.number("hour") != Double(hour) || next.number("minute") != Double(minute) { clearPreparation(&next) }
        next["hour"] = hour; next["minute"] = minute; try saveSchedule(next)
        BackgroundCoordinator.shared.schedule(self)
    }
    func enableDaily(_ enabled: Bool) async throws {
        if enabled && !signedIn { throw AppError("请先登录并验证账号") }
        var next = schedule; next["enabled"] = enabled
        next["student_id"] = config.text("student_id"); clearPreparation(&next); try saveSchedule(next)
        if enabled { await BackgroundCoordinator.shared.requestNotifications() }
        BackgroundCoordinator.shared.schedule(self)
    }
    private func clearPreparation(_ value: inout JSON) {
        ["prep_target_ms", "prep_status", "prep_message", "prepared_origin", "prepared_preview", "prepared_refresh_ms", "retry_ms", "origin_source"].forEach { value.removeValue(forKey: $0) }
    }

    func sendSMS(_ phone: String) async throws {
        try validatePhone(phone)
        let next = try disk().read("login_meta")?.number("sms_next_allowed") ?? 0
        guard next <= Clock.now else { throw AppError("请等待 \(Int(ceil((next - Clock.now) / 1000))) 秒后再获取验证码") }
        try disk().write("login_meta", ["sms_next_allowed": Clock.now + 60000])
        _ = try HuatiAPI.success(await HuatiAPI.login("/xcxapi/sendSMS/", body: ["iphone": phone]))
        message = "验证码已发送"
    }
    private func validatePhone(_ phone: String) throws {
        guard phone.range(of: "^1[3-9][0-9]{9}$", options: .regularExpression) != nil else { throw AppError("请输入绑定的 11 位手机号") }
    }
    func phoneLogin(phone: String, secret: String, byCode: Bool) async throws {
        try validatePhone(phone)
        if byCode { guard secret.range(of: "^[0-9]{4,8}$", options: .regularExpression) != nil else { throw AppError("请输入短信数字验证码") } }
        else { guard !secret.isEmpty && secret.count <= 256 else { throw AppError("请输入账号密码") } }
        let response = try await HuatiAPI.login(byCode ? "/xcxapi/login/" : "/xcxapi/userLogin/", body: ["iphone": phone, byCode ? "code" : "password": secret])
        guard let data = try HuatiAPI.success(response) as? JSON, let session = data["session_keys"] as? String else { throw AppError("服务器未返回会话，请使用文件导入") }
        var candidate: JSON = ["format": "huati-mobile-session", "version": 1, "host": HuatiAPI.host, "headers": ["X-Session-ID": session], "login_source": "phone"]
        if !data.text("id").isEmpty { candidate["student_id"] = data.text("id") }
        try await acceptConfig(candidate)
    }
    func importSession(_ data: Data) async throws {
        guard data.count <= 256 * 1024, let value = try JSONSerialization.jsonObject(with: data) as? JSON else { throw AppError("会话文件无效或超过 256 KB") }
        try await acceptConfig(value)
    }
    private func acceptConfig(_ candidate: JSON) async throws {
        let client = try HuatiAPI(config: candidate)
        guard let user = try await client.value("/xcxapi/getUserInfo/") as? JSON, !user.text("id").isEmpty else { throw AppError("未取得账号信息") }
        let id = user.text("id")
        guard candidate.text("student_id").isEmpty || candidate.text("student_id") == id else { throw AppError("登录响应与账号不一致") }
        guard !unresolved || run.text("student_id") == id else { throw AppError("还有另一账号的待处理记录，请先处理") }
        var value: JSON = ["format": "huati-mobile-session", "version": 1, "host": HuatiAPI.host, "headers": client.headers, "student_id": id]
        let oldLocation = candidate.object("location").isEmpty ? config.object("location") : candidate.object("location")
        if !oldLocation.isEmpty { _ = try rules().call("coordinate", [oldLocation.number("lat", .nan), oldLocation.number("lng", .nan)]); value["location"] = oldLocation }
        if candidate.number("recent_record_id") > 0 { value["recent_record_id"] = candidate.number("recent_record_id") }
        else if config.text("student_id") == id && config.number("recent_record_id") > 0 { value["recent_record_id"] = config.number("recent_record_id") }
        if config.text("student_id") != id {
            var daily = schedule; daily["enabled"] = false; clearPreparation(&daily); try saveSchedule(daily)
            try disk().remove("catalog"); catalog = ["complete": false, "points": Self.referencePoints, "source": "公开参考的三个点位"]
        }
        try disk().write("config", value); config = value
        try disk().remove("points"); preview = [:]; try disk().remove("route"); route = [:]
        if !unresolved { try disk().remove("run"); run = [:]; try disk().remove("results"); results = [:] }
        message = "登录会话已保存"; event("登录完成")
    }
    func exportedSession() throws -> Data {
        guard signedIn else { throw AppError("请先登录") }
        var value = config; value["exported_at"] = try rules().call("date", [Clock.now])
        if run.text("status") == "finished" { value["recent_record_id"] = run.number("record_id") }
        return try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    }
    func clearSession() throws {
        guard !unresolved else { throw AppError("请先处理未完成或待核实记录") }
        var daily = schedule; daily["enabled"] = false; clearPreparation(&daily); try saveSchedule(daily)
        for name in ["config", "points", "route", "run", "results", "catalog", "discarded"] { try disk().remove(name) }
        config = [:]; preview = [:]; route = [:]; run = [:]; results = [:]
        catalog = ["complete": false, "points": Self.referencePoints, "source": "公开参考的三个点位"]
    }
    func readLocation() async throws {
        let fix = try await location.read(allowPrompt: true)
        let value = try rules().object("gcj", [fix]); var next = config; next["location"] = value
        try disk().write("config", next); config = next; message = "已读取当前位置（GCJ-02）"
    }
    func fetchPoints(lat: Double, lng: Double) async throws -> JSON {
        guard !unresolved else { throw AppError("请先处理当前记录") }
        _ = try rules().call("coordinate", [lat, lng])
        let client = try api()
        guard let user = try await client.value("/xcxapi/getUserInfo/") as? JSON else { throw AppError("账号响应无效") }
        let response = try await client.request("/xcxtapi/activity/randrunInfo?lat=\(lat)&lng=\(lng)")
        guard let points = try HuatiAPI.success(response) as? [JSON] else { throw AppError("服务器点位格式无效") }
        _ = try rules().call("points", [points])
        guard user.text("id") == response.text("student_id"), user.text("id") == config.text("student_id") else { throw AppError("点位所属账号与登录会话不一致") }
        let value: JSON = ["points": points, "lat": response.number("lat", lat), "lng": response.number("lng", lng), "student_id": user.text("id"), "captured_at": Clock.now]
        _ = try rules().call("coordinate", [value.number("lat"), value.number("lng")])
        let merged = try rules().object("catalogMerge", [catalog, points, try rules().boundary, Clock.now])
        try disk().write("catalog", merged); catalog = merged; event("已获取三点")
        return value
    }
    func loadPoints(lat: Double, lng: Double) async throws {
        let value = try await fetchPoints(lat: lat, lng: lng)
        try disk().write("points", value); preview = value; try disk().remove("route"); route = [:]
    }
    func previewRoute(metres: Int, duration: Int, steps: Int) throws {
        _ = try rules().call("parameters", [metres, duration, steps]); try requirePreview()
        let value = try rules().plan(preview, metres: metres, scheduled: false, roads: preferences.flag("road_mode"))
        try disk().write("route", value); route = value
    }
    private func requirePreview() throws {
        let age = Clock.now - preview.number("captured_at")
        guard !preview.isEmpty, age >= 0, age <= 1800000 else { throw AppError("三点已过期，请重新获取") }
    }
    func create(metres: Int, duration: Int, steps: Int, scheduled: Bool = false) async throws {
        guard !unresolved else { throw AppError("还有未处理的记录") }; try requirePreview()
        _ = try rules().call("parameters", [metres, duration, steps])
        var plan = route
        if scheduled || plan.number("requested_distance") != Double(metres) || plan.flag("road_mode") != preferences.flag("road_mode") || plan.isEmpty {
            plan = try rules().plan(preview, metres: metres, scheduled: scheduled, roads: preferences.flag("road_mode"))
        }
        let client = try api()
        guard let user = try await client.value("/xcxapi/getUserInfo/") as? JSON,
              user.text("id") == preview.text("student_id"), user.text("id") == config.text("student_id") else { throw AppError("账号已变化，请重新获取三点") }
        let actual = plan.number("distance"), seconds = Double(duration) / 1000
        let pace = seconds / (actual / 1000), frequency = Double(steps) / (seconds / 60)
        let warning = actual < max(2000, user.number("shortest_distance", 2000)) || pace < user.number("min_pace", 180) || pace > user.number("max_pace", 1000)
        if warning && !scheduled { throw AppError("里程或配速不在服务器允许范围内") }
        guard frequency >= user.number("min_step_frequency", 30), frequency <= user.number("max_step_frequency", 400) else { throw AppError("步数与时长不符合步频范围") }
        try Task.checkCancellation()
        let start = scheduled ? Clock.now : floor(Clock.now / 1000) * 1000
        let uptime = ProcessInfo.processInfo.systemUptime
        var state: JSON = ["status": "create_pending", "mode": "simulated", "student_id": user.text("id"), "points": preview.objects("points"), "lat": preview.number("lat"), "lng": preview.number("lng"), "start_ms": start, "uptime_start": uptime, "process_id": processID, "distance": actual, "requested_distance": metres, "duration_ms": duration, "duration": Int(ceil(seconds)), "steps": steps, "auto_submit": true, "pauses": [JSON](), "road_mode": plan.flag("road_mode"), "scheduled_route": scheduled, "route_samples": plan.objects("route_samples")]
        if warning { state["preflight_warning"] = "本次路线配速或里程可能无效，结束后仍提交。" }
        try saveRun(state)
        do {
            event("创建请求")
            guard let created = try await client.value("/xcxapi/createLine/", body: ["student_id": user["id"] ?? user.text("id"), "pass_point": preview.objects("points")]) as? JSON, created.number("record_id") > 0 else { throw AppError("服务器未返回记录编号") }
            state["record_id"] = created.number("record_id"); state["status"] = "created"; try saveRun(state)
            selectedTab = 2; event("创建完成")
            await BackgroundCoordinator.shared.requestNotifications()
            BackgroundCoordinator.shared.schedule(self)
        } catch {
            state["status"] = "create_unknown"; state["auto_submit"] = false; state["error"] = "创建结果待核实，请查看官方小程序；不会重复创建。"
            try saveRun(state); throw AppError(state.text("error"))
        }
    }
    func pause() throws { try saveRun(rules().object("pause", [run, Clock.now])); event("已暂停") }
    func resume() throws { try saveRun(rules().object("resume", [run, Clock.now])); event("已继续") }
    func discard() throws {
        let value = try rules().object("discard", [run, Clock.now]); try saveRun(value)
        var previous = try disk().read("discarded")?.objects("runs") ?? []; previous.append(value)
        try disk().write("discarded", ["runs": Array(previous.suffix(50))]); preview = [:]; route = [:]
        try disk().remove("points"); try disk().remove("route"); event("已舍弃本地记录")
    }
    func finish() async throws {
        guard ["created", "check_failed"].contains(run.text("status")), try rules().number("remaining", [run, Clock.now]) == 0 else { throw AppError("记录尚未计满时长，或当前状态不允许提交") }
        let end = Clock.now, start = run.number("start_ms"), seconds = Int((end - start) / 1000)
        guard seconds > 0 && seconds <= 86400 else { throw AppError("记录时长异常，请在小程序核实") }
        let currentUptime = ProcessInfo.processInfo.systemUptime, elapsedStart = run.number("uptime_start", currentUptime)
        // Monotonic comparison is valid within this process, including lock-screen suspension.
        if run.text("process_id") == processID && abs((currentUptime - elapsedStart) - (end - start) / 1000) > 60 { throw AppError("手机时间发生变化，请核实系统时间") }
        guard let path = try rules().call("path", [run, end]) as? [JSON] else { throw AppError("轨迹计算失败") }
        let payload: JSON = ["record_id": run.number("record_id"), "pace": Double(seconds) / 60 / (run.number("distance") / 1000), "running_time": seconds, "mileage": run.number("distance"), "start_time": try rules().call("date", [start]), "end_time": try rules().call("date", [end]), "pass_point": 3, "step_count": run.number("steps")]
        let encrypted: JSON = ["a": try HuatiAPI.encrypt(payload)], client = try api()
        var state = run; state["status"] = "checking"; state["auto_submit"] = false; try saveRun(state)
        do {
            guard let user = try await client.value("/xcxapi/getUserInfo/") as? JSON, user.text("id") == state.text("student_id") else { throw AppError("当前登录账号与记录不同") }
            try Task.checkCancellation(); event("校验请求")
            let checked = try await client.request("/xcxapi/checkRecord/", body: encrypted)
            guard let detail = try HuatiAPI.success(checked) as? JSON, [0, 1].contains(Int(detail.number("status", -1))) else { throw AppError("校验状态未知，请先查询记录") }
            state["check"] = checked; state["accepted_invalid"] = detail.number("status") == 0
            if state.flag("accepted_invalid") { state["invalid_reason"] = detail.text("warning", detail.text("message", checked.text("message", "服务器判定无效"))) }
        } catch {
            state["status"] = "created"; state = try rules().object("pause", [state, end]); state["error"] = error.localizedDescription; try saveRun(state); throw error
        }
        state["status"] = "finish_pending"; state["finish_payload"] = payload; try saveRun(state)
        do {
            try Task.checkCancellation(); event("提交请求")
            _ = try await client.value("/xcxapi/updateRecordNew/", body: encrypted)
            state["status"] = "record_updated"; try saveRun(state)
            for i in stride(from: 0, to: path.count, by: 50) {
                try Task.checkCancellation(); event("上传轨迹")
                let body: JSON = ["record_id": state.number("record_id"), "path_point": Array(path[i..<min(i + 50, path.count)]), "path_image": ""]
                _ = try await client.value("/xcxapi/uploadPathPointV3/", body: ["img_url": try HuatiAPI.encrypt(body)])
                state["uploaded_points"] = min(i + 50, path.count); try saveRun(state)
            }
            state["status"] = "finished"; state["end_ms"] = end; state["actual_duration"] = seconds
            state["active_duration_ms"] = try rules().number("moving", [state, end]); state.removeValue(forKey: "error"); try saveRun(state); event("提交完成")
        } catch {
            state["status"] = "finish_unknown"; state["error"] = "提交或轨迹上传结果待核实，请查询服务器；不会重复提交。"; try saveRun(state); throw AppError(state.text("error"))
        }
        do { try await refresh() } catch { message = "本次已提交，成绩查询暂未成功，可稍后刷新。" }
    }
    func refresh() async throws {
        let client = try api(); let statistics = try await client.value("/xcxapi/recordListcont/")
        var value: JSON = ["statistics": statistics, "checked_at": Clock.now]
        let id = run.number("record_id", config.number("recent_record_id"))
        if id > 0 { value["record"] = try await client.value("/xcxapi/recordInfo/?id=\(Int64(id))") }
        try disk().write("results", value); results = value
    }
    func importCatalog(_ data: Data) throws {
        guard data.count <= 256 * 1024, let value = try JSONSerialization.jsonObject(with: data) as? JSON else { throw AppError("点位文件无效或超过 256 KB") }
        let normalized = try rules().object("catalogImport", [value, try rules().boundary, Clock.now]); try disk().write("catalog", normalized); catalog = normalized
    }

    func service() async {
        guard !busy, startupError == nil, let core else { return }
        let current = Clock.now
        let finishDue = activeRecord && ((try? core.number("remaining", [run, current])) ?? 1) <= 0
        var dailyDue = false
        if schedule.flag("enabled"), let target = try? core.number("target", [schedule, current]) {
            let ready = (try? core.flag("ready", [schedule, current, target])) ?? false
            dailyDue = current >= target - 120000 && current >= schedule.number("retry_ms")
                && current >= schedule.number("last_attempt_ms") && ((try? core.flag("reserved", [schedule, target])) == false)
                && (schedule.number("prep_target_ms") == target || current < target + 300000)
                && (!ready || current >= target) && (!unresolved || current >= target)
        }
        guard finishDue || dailyDue else { return }
        busy = true; now = current
        defer { busy = false; now = Clock.now; BackgroundCoordinator.shared.schedule(self) }
        do {
            try Task.checkCancellation()
            if finishDue { try await finish(); return }
            if schedule.flag("enabled") { try await dailyStep() }
        } catch {
            if activeRecord { do { var state = try rules().object("pause", [run, Clock.now]); state["error"] = error.localizedDescription; try saveRun(state) } catch { startupError = "无法保存记录状态，请核实服务器记录。" } }
            message = error.localizedDescription; event("任务停止或中断")
        }
    }
    private func dailyStep() async throws {
        let core = try rules(), now = Clock.now, target = try core.number("target", [schedule, Clock.now])
        guard now >= target - 120000, try !core.flag("reserved", [schedule, target]), now >= schedule.number("last_attempt_ms") else { return }
        guard core.callDay(target) == core.callDay(now) else { return }
        if unresolved {
            if now >= target && (now < target + 300000 || schedule.number("prep_target_ms") == target) {
                var s = try core.object("reserve", [schedule, target, now]); s["last_status"] = "skipped"
                s["last_message"] = "本次时间已跳过：还有未完成、暂停或待核实记录。可处理原记录后另设后续时间。"; try saveSchedule(s)
            }
            return
        }
        guard schedule.text("student_id") == config.text("student_id") else { var s = schedule; s["enabled"] = false; s["last_message"] = "账号已变化，请重新开启自动运行"; try saveSchedule(s); return }
        if schedule.number("prep_target_ms") != target {
            guard now < target + 300000 else { return }
            var s = schedule; clearPreparation(&s); s["prep_target_ms"] = target; s["prep_status"] = "waiting_points"; try saveSchedule(s)
        }
        guard now >= schedule.number("retry_ms") else { return }
        if try !core.flag("ready", [schedule, now, target]) {
            var s = schedule; s["prep_status"] = "locating"; s["prep_message"] = "读取位置并刷新今日随机三点"; try saveSchedule(s)
            do {
                var origin = s.object("prepared_origin")
                if origin.isEmpty || now - origin.number("captured_at") > 300000 || now < origin.number("captured_at") {
                    let fix: Any
                    do { fix = try await location.read(allowPrompt: false) } catch is CancellationError { throw CancellationError() } catch { fix = NSNull() }
                    try Task.checkCancellation()
                    origin = try core.object("origin", [fix, core.boundary, Int.random(in: 0..<3)])
                    origin["captured_at"] = Clock.now; s["prepared_origin"] = origin; s["origin_source"] = origin.text("source")
                }
                let opening = try core.number("opening", [target])
                if Clock.now < opening { s["prep_status"] = "waiting_open"; s["retry_ms"] = opening; s["prep_message"] = "起点已准备，等待北京时间 06:00 后刷新三点"; try saveSchedule(s); return }
                s["prep_status"] = "fetching"; try saveSchedule(s)
                let client = try api()
                guard let user = try await client.value("/xcxapi/getUserInfo/") as? JSON, user.text("id") == config.text("student_id") else { throw AppError("账号不一致，请重新登录") }
                _ = try await client.value("/xcxapi/RunningData/")
                s["prepared_refresh_ms"] = Clock.now
                let p = try await fetchPoints(lat: origin.number("lat"), lng: origin.number("lng"))
                try Task.checkCancellation()
                s["prepared_preview"] = p; s["prep_status"] = "ready"; s["prep_message"] = "今日三点已刷新，等待计划时间"; s["retry_ms"] = 0; try saveSchedule(s)
            } catch {
                s["prep_status"] = "waiting_points"; s["retry_ms"] = Clock.now + 30000; s["prep_message"] = "准备未完成，应用有执行机会时继续尝试"; try saveSchedule(s)
                if error is CancellationError { throw error }; return
            }
        }
        guard Clock.now >= target, try core.flag("ready", [schedule, Clock.now, target]) else { return }
        let duration = Int(try core.number("randomDuration", [Double.random(in: 0..<1)]))
        var s = try core.object("reserve", [schedule, target, Clock.now]); s["last_duration_ms"] = duration; s["last_status"] = "creating"; try saveSchedule(s)
        let p = s.object("prepared_preview"); try disk().write("points", p); preview = p
        do {
            try await create(metres: 2200, duration: duration, steps: 2600, scheduled: true)
            s["last_status"] = "started"; s["last_message"] = "已自动开始，计满本次随机时长后提交"; s["last_record_id"] = run.number("record_id")
        } catch { s["last_status"] = "failed"; s["last_message"] = error.localizedDescription }
        s["prep_status"] = "consumed"; s.removeValue(forKey: "prepared_preview"); try saveSchedule(s)
    }
    func backgroundTask() async {
        event("iOS 后台唤醒")
        await service()
        BackgroundCoordinator.shared.schedule(self)
    }
    func startProbe() async {
        await BackgroundCoordinator.shared.requestNotifications()
        event("安排一分钟后台自检")
        BackgroundCoordinator.shared.probe(after: 60)
    }
    func probe() async {
        event("后台自检已唤醒")
        var request = URLRequest(url: URL(string: "https://run.ecust.edu.cn/")!)
        request.httpMethod = "HEAD"; request.timeoutInterval = 15
        do { _ = try await URLSession.shared.data(for: request); event("匿名网络自检完成") }
        catch { event("匿名网络自检失败") }
    }
}

extension CoreBridge {
    func callDay(_ time: Double) -> String { (try? call("day", [time]) as? String) ?? "" }
}
