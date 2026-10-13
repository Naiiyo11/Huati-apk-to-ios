import SwiftUI

struct CampusMapView: View {
    @EnvironmentObject private var model: AppModel
    let route: [JSON]
    let points: [JSON]
    let showCatalog: Bool
    @State private var scale = 1.0
    @State private var savedScale = 1.0
    @State private var offset = CGSize.zero
    @State private var savedOffset = CGSize.zero
    @State private var selected: String?

    var body: some View {
        GeometryReader { geo in
            let map = model.core?.map ?? [:]
            let boundary = map["boundary"] as? [[Double]] ?? []
            let allPoints = showCatalog ? model.catalog.objects("points") + points : points
            let mappedPoints = ((try? model.core?.call("mapPoints", [allPoints])) as? [JSON]) ?? []
            let mappedRoute = ((try? model.core?.call("mapPoints", [route])) as? [JSON]) ?? []
            let projection = Projection(boundary: boundary, size: geo.size, scale: scale, offset: offset)
            ZStack(alignment: .topTrailing) {
                Canvas { context, size in
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.94, green: 0.97, blue: 0.98)))
                    context.fill(polygon(boundary, projection), with: .color(Color(red: 0.90, green: 0.94, blue: 0.90)))
                    for area in map.objects("areas") {
                        let color: Color
                        switch area.text("kind") {
                        case "water": color = Color(red: 0.72, green: 0.86, blue: 0.95)
                        case "building": color = Color(red: 0.81, green: 0.85, blue: 0.89)
                        case "pitch": color = Color(red: 0.74, green: 0.88, blue: 0.79)
                        default: color = Color(red: 0.80, green: 0.91, blue: 0.83)
                        }
                        for ring in area["rings"] as? [[[Double]]] ?? [] {
                            let path = polygon(ring, projection)
                            context.fill(path, with: .color(color))
                            context.stroke(path, with: .color(.white.opacity(0.6)), lineWidth: 0.8)
                        }
                    }
                    for road in map.objects("roads") {
                        let line = polyline(road["points"] as? [[Double]] ?? [], projection)
                        context.stroke(line, with: .color(Color(red: 0.75, green: 0.81, blue: 0.85)), style: StrokeStyle(lineWidth: min(10, max(2, road.number("width", 2) * scale + 1.5)), lineCap: .round, lineJoin: .round))
                        context.stroke(line, with: .color(.white.opacity(0.88)), style: StrokeStyle(lineWidth: min(8, max(1, road.number("width", 2) * scale)), lineCap: .round, lineJoin: .round))
                    }
                    context.stroke(polygon(boundary, projection), with: .color(Theme.blue.opacity(0.5)), style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                    for label in map.objects("labels") {
                        if scale < 1.8 && label.number("priority") < 50 { continue }
                        let point = label["point"] as? [Double] ?? []
                        if point.count == 2 { context.draw(Text(label.text("name")).font(.system(size: min(14, 9 + scale), weight: .medium)).foregroundColor(Theme.muted), at: projection.point(point)) }
                    }
                    if mappedRoute.count > 1 {
                        let line = polyline(mappedRoute.map { [$0.number("lat"), $0.number("lng")] }, projection)
                        context.stroke(line, with: .color(.white), style: StrokeStyle(lineWidth: 5.5, lineCap: .round, lineJoin: .round))
                        context.stroke(line, with: .color(Theme.blue), style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round))
                    }
                    for (index, item) in mappedPoints.enumerated() {
                        let p = projection.point([item.number("lat"), item.number("lng")]), isCurrent = index >= mappedPoints.count - points.count
                        let rect = CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)
                        context.fill(Path(ellipseIn: rect), with: .color(isCurrent ? Color(red: 0.18, green: 0.61, blue: 0.48) : Theme.ink))
                        context.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 2)
                    }
                    let metres = 100.0, pixelWidth = metres * projection.factor * scale
                    let x = 15.0, y = size.height - 17
                    var bar = Path(); bar.move(to: CGPoint(x: x, y: y)); bar.addLine(to: CGPoint(x: x + pixelWidth, y: y))
                    context.stroke(bar, with: .color(Theme.ink), lineWidth: 2)
                    context.draw(Text("100 m").font(.system(size: 10)).foregroundColor(Theme.ink), at: CGPoint(x: x + pixelWidth / 2, y: y - 10))
                }
                .contentShape(Rectangle())
                .gesture(MagnificationGesture().onChanged { value in scale = min(6, max(1, savedScale * value)); clamp(size: geo.size) }.onEnded { _ in savedScale = scale; savedOffset = offset })
                .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { value in offset = CGSize(width: savedOffset.width + value.translation.width, height: savedOffset.height + value.translation.height); clamp(size: geo.size) }.onEnded { _ in savedOffset = offset })
                .simultaneousGesture(SpatialTapGesture().onEnded { value in
                    if let item = mappedPoints.min(by: { a, b in
                        let p = projection.point([a.number("lat"), a.number("lng")]), q = projection.point([b.number("lat"), b.number("lng")])
                        return hypot(p.x - value.location.x, p.y - value.location.y) < hypot(q.x - value.location.x, q.y - value.location.y)
                    }) {
                        let p = projection.point([item.number("lat"), item.number("lng")])
                        if hypot(p.x - value.location.x, p.y - value.location.y) < 25 { selected = item.text("point_name", item.text("name", "考核点")) }
                    }
                })
                .onTapGesture(count: 2) { changeScale(scale < 3 ? scale * 1.5 : 1, size: geo.size) }
                VStack(spacing: 8) {
                    Button { changeScale(scale * 1.35, size: geo.size) } label: { Image(systemName: "plus").frame(width: 38, height: 38) }.accessibilityLabel("放大地图")
                    Button { changeScale(scale / 1.35, size: geo.size) } label: { Image(systemName: "minus").frame(width: 38, height: 38) }.accessibilityLabel("缩小地图")
                    Button { changeScale(1, size: geo.size) } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 38, height: 38) }.accessibilityLabel("校园全图")
                }.font(.body.weight(.semibold)).buttonStyle(.plain).foregroundStyle(Theme.blue).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13)).padding(10)
            }.clipShape(RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.blue.opacity(0.16)))
        }
        .alert("校园点位", isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) { Button("关闭") { selected = nil } } message: { Text(selected ?? "") }
    }
    private func changeScale(_ value: Double, size: CGSize) { scale = min(6, max(1, value)); if scale == 1 { offset = .zero }; clamp(size: size); savedScale = scale; savedOffset = offset }
    private func clamp(size: CGSize) {
        let x = size.width * (scale - 1) / 2, y = size.height * (scale - 1) / 2
        offset = CGSize(width: min(x, max(-x, offset.width)), height: min(y, max(-y, offset.height)))
    }
    private func polyline(_ points: [[Double]], _ projection: Projection) -> Path {
        var path = Path()
        for (index, point) in points.enumerated() where point.count == 2 {
            if index == 0 { path.move(to: projection.point(point)) } else { path.addLine(to: projection.point(point)) }
        }; return path
    }
    private func polygon(_ points: [[Double]], _ projection: Projection) -> Path { var path = polyline(points, projection); path.closeSubpath(); return path }
}

private struct Projection {
    let size: CGSize
    let scale: Double
    let offset: CGSize
    let centerLat: Double
    let centerLng: Double
    let factor: Double
    let longitudeFactor: Double
    init(boundary: [[Double]], size: CGSize, scale: Double, offset: CGSize) {
        self.size = size; self.scale = scale; self.offset = offset
        let lat = boundary.map { $0[0] }, lng = boundary.map { $0[1] }
        let minLat = lat.min() ?? 30.827, maxLat = lat.max() ?? 30.840, minLng = lng.min() ?? 121.491, maxLng = lng.max() ?? 121.508
        centerLat = (minLat + maxLat) / 2; centerLng = (minLng + maxLng) / 2
        longitudeFactor = cos(centerLat * .pi / 180)
        factor = min(max(1, size.width - 32) / max(1, (maxLng - minLng) * 111320 * longitudeFactor), max(1, size.height - 45) / max(1, (maxLat - minLat) * 111320))
    }
    func point(_ coordinate: [Double]) -> CGPoint {
        CGPoint(x: size.width / 2 + (coordinate[1] - centerLng) * 111320 * longitudeFactor * factor * scale + offset.width, y: size.height / 2 - (coordinate[0] - centerLat) * 111320 * factor * scale + offset.height)
    }
}
