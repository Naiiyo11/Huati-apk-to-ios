import Foundation
import CoreLocation

@MainActor final class PhoneLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var pending: CheckedContinuation<JSON, Error>?
    private var timeout: Task<Void, Never>?

    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyBest }
    func read(allowPrompt: Bool) async throws -> JSON {
        guard pending == nil else { throw AppError("正在读取位置，请稍候") }
        guard CLLocationManager.locationServicesEnabled() else { throw AppError("手机定位开关已关闭") }
        if [.denied, .restricted].contains(manager.authorizationStatus) { throw AppError("位置权限未允许") }
        if manager.authorizationStatus == .notDetermined && !allowPrompt { throw AppError("未授予位置权限") }
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                pending = continuation
                timeout = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 60_000_000_000) } catch { return }
                    self?.finish(.failure(AppError("60 秒内未取得精度 100 米内的新位置")))
                }
                if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
                else { manager.startUpdatingLocation() }
            }
        }, onCancel: { Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())) } })
    }
    private func finish(_ result: Result<JSON, Error>) {
        manager.stopUpdatingLocation(); timeout?.cancel(); timeout = nil
        let continuation = pending; pending = nil; continuation?.resume(with: result)
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard pending != nil else { return }
        if [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus) { manager.startUpdatingLocation() }
        else if [.denied, .restricted].contains(manager.authorizationStatus) { finish(.failure(AppError("位置权限未允许"))) }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last(where: { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 100 && Date().timeIntervalSince($0.timestamp) >= 0 && Date().timeIntervalSince($0.timestamp) <= 60 }) else { return }
        finish(.success(["lat": fix.coordinate.latitude, "lng": fix.coordinate.longitude]))
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code == .locationUnknown { return }
        finish(.failure(AppError("定位失败，将使用随机校内模拟起点")))
    }
}
