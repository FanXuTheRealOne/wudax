import SwiftUI

/// 「地图」Tab —— 聚焦一条历史路线，或以实时定位与朝向浏览当前位置。
struct MapTabView: View {
    @EnvironmentObject var library: RouteLibraryStore
    @EnvironmentObject var session: TripSession
    @EnvironmentObject var navigation: AppNavigation
    @State private var isRoutePickerExpanded = false
    @State private var cameraMode: RouteMapCameraMode = .route
    @State private var cameraRequestID = 0
    @State private var locationRevision = 0
    @State private var mapLayer: RouteMapLayer = .standard

    private var selected: RouteRecord? {
        if let id = navigation.selectedMapRouteID,
           let selected = library.record(id: id) {
            return selected
        }
        return library.records.first
    }

    var body: some View {
        // `LocationService` 是 `TripSession` 的嵌套 ObservableObject；显式订阅后，
        // 地图即使未处于行中阶段也会随位置和罗盘 heading 重绘。
        let _ = locationRevision
        ZStack {
            WDColor.inkPine.ignoresSafeArea()

            if let record = selected {
                RouteMapView(
                    points: record.document.points,
                    currentCoordinate: session.location.latestLocation?.coordinate,
                    tracksUserLocation: true,
                    userHeadingDegrees: session.location.headingDegrees,
                    cameraMode: cameraMode,
                    cameraRequestID: cameraRequestID,
                    mapLayer: mapLayer
                )
                .ignoresSafeArea(edges: .top)

                VStack(spacing: 12) {
                    HStack(alignment: .top, spacing: 8) {
                        routePicker(record)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        mapLayerMenu
                    }
                    .padding(.horizontal, 16)
                    Spacer()
                    mapFocusControls
                    infoBar(record)
                }
                .padding(.top, 8)
                .padding(.bottom, 96)
            } else {
                emptyState
            }
        }
        .onAppear {
            if navigation.selectedMapRouteID == nil {
                navigation.selectedMapRouteID = library.records.first?.id
            }
            if session.location.authorizationState == .whenInUse || session.location.authorizationState == .always {
                session.location.startMonitoring()
            }
            focusRoute()
        }
        .onChange(of: navigation.selectedMapRouteID) { _ in
            focusRoute()
        }
        .onReceive(session.location.objectWillChange) { _ in
            locationRevision &+= 1
        }
    }

    // MARK: 历史路线折叠选择

    private func routePicker(_ selectedRecord: RouteRecord) -> some View {
        DisclosureGroup(isExpanded: $isRoutePickerExpanded) {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(library.records) { record in
                        Button {
                            navigation.selectedMapRouteID = record.id
                            isRoutePickerExpanded = false
                            focusRoute()
                            Haptics.tap()
                        } label: {
                            HStack(spacing: 10) {
                                RouteShapeThumbnail(coordinates: record.coordinates, stroke: record.riskLevel.color)
                                    .frame(width: 34, height: 30)
                                    .padding(4)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(WDColor.mossSurface))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(record.name)
                                        .font(WDFont.body(13).weight(.medium))
                                        .foregroundStyle(WDColor.ricePaper)
                                        .lineLimit(1)
                                    Text(String(format: "%.1f km · %@", record.distanceKm, record.provenance.displayAuthor))
                                        .font(WDFont.caption(10)).foregroundStyle(WDColor.mist)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if record.id == selectedRecord.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(WDColor.bamboo)
                                }
                            }
                            .padding(.horizontal, 10).padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(record.id == selectedRecord.id ? WDColor.mossSurface.opacity(0.9) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 10)
            }
            .frame(maxHeight: 228)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(WDColor.bamboo)
                VStack(alignment: .leading, spacing: 2) {
                    Text("历史路线")
                        .font(WDFont.caption(10)).foregroundStyle(WDColor.mist)
                    Text(selectedRecord.name)
                        .font(WDFont.heading(14)).foregroundStyle(WDColor.ricePaper)
                        .lineLimit(1)
                }
                Spacer()
                Text(String(format: "%.1f km", selectedRecord.distanceKm))
                    .font(WDFont.mono(11)).foregroundStyle(WDColor.bamboo)
            }
            .contentShape(Rectangle())
        }
        .tint(WDColor.ricePaper)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(WDColor.deepMoss.opacity(0.96))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(WDColor.line.opacity(0.65), lineWidth: 1))
        )
    }

    // MARK: 地图相机控制

    private var mapLayerMenu: some View {
        Menu {
            ForEach(RouteMapLayer.allCases) { layer in
                Button {
                    mapLayer = layer
                    Haptics.tap()
                } label: {
                    Label(layer.title, systemImage: layer.symbolName)
                }
            }
        } label: {
            Image(systemName: "square.3.layers.3d.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(WDColor.ricePaper)
                .frame(width: 48, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(WDColor.deepMoss.opacity(0.96))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(WDColor.line.opacity(0.65), lineWidth: 1))
                )
        }
        .accessibilityLabel("切换地图图层")
    }

    private var mapFocusControls: some View {
        HStack(spacing: 10) {
            Spacer()
            Button(action: focusRoute) {
                Label("路线聚焦", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(MapFocusButtonStyle(isSelected: cameraMode == .route))

            Button(action: focusUserLocation) {
                Label("自身定位", systemImage: "location.fill")
            }
            .buttonStyle(MapFocusButtonStyle(isSelected: cameraMode == .user))
        }
        .padding(.horizontal, 16)
    }

    private func focusRoute() {
        cameraMode = .route
        cameraRequestID += 1
        Haptics.tap()
    }

    private func focusUserLocation() {
        session.location.startMonitoring()
        cameraMode = .user
        cameraRequestID += 1
        Haptics.tap()
    }

    private func infoBar(_ record: RouteRecord) -> some View {
        InkCard {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.name).font(WDFont.heading(15)).foregroundStyle(WDColor.ricePaper).lineLimit(1)
                    if let heading = session.location.headingDegrees {
                        Label("朝向 \(Int(heading.rounded()))°", systemImage: "location.north.fill")
                            .font(WDFont.caption(10)).foregroundStyle(WDColor.bamboo)
                    } else {
                        Text("点击“自身定位”显示实时位置与朝向")
                            .font(WDFont.caption(10)).foregroundStyle(WDColor.mist)
                    }
                }
                Spacer()
                Text(String(format: "%.1f km", record.distanceKm)).font(WDFont.mono(14)).foregroundStyle(WDColor.bamboo)
            }
        }
        .padding(.horizontal, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "map").font(.system(size: 40, weight: .ultraLight)).foregroundStyle(WDColor.mist.opacity(0.5))
            Text("导入路线后可在此查看").font(WDFont.body(15)).foregroundStyle(WDColor.mist)
        }
    }
}

private struct MapFocusButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(WDFont.caption(11).weight(.semibold))
            .foregroundStyle(isSelected ? WDColor.ink : WDColor.ricePaper)
            .padding(.horizontal, 13).padding(.vertical, 10)
            .background(
                Capsule().fill(isSelected ? WDColor.bamboo : WDColor.deepMoss.opacity(configuration.isPressed ? 0.78 : 0.96))
            )
            .overlay(Capsule().stroke(WDColor.line.opacity(isSelected ? 0 : 0.72), lineWidth: 1))
    }
}
