import SwiftUI

/// 「地图」Tab —— 在地图上查看路线库里的轨迹。离线底图将在下一里程碑接入。
struct MapTabView: View {
    @EnvironmentObject var library: RouteLibraryStore
    @State private var selectedID: UUID?

    private var selected: RouteRecord? {
        library.records.first { $0.id == selectedID } ?? library.records.first
    }

    var body: some View {
        ZStack {
            WDColor.inkPine.ignoresSafeArea()
            if let record = selected {
                RouteMapView(points: record.document.points)
                    .ignoresSafeArea(edges: .top)
                VStack {
                    routePicker
                    Spacer()
                    infoBar(record)
                }
            } else {
                emptyState
            }
        }
    }

    private var routePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(library.records) { record in
                    let active = (selected?.id == record.id)
                    Button { selectedID = record.id } label: {
                        Text(record.name)
                            .font(WDFont.body(13).weight(.medium))
                            .foregroundStyle(active ? WDColor.onDark : WDColor.ricePaper)
                            .lineLimit(1)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Capsule().fill(active ? WDColor.ink : WDColor.deepMoss.opacity(0.95))
                                .overlay(Capsule().stroke(WDColor.line, lineWidth: active ? 0 : 1)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 8)
    }

    private func infoBar(_ record: RouteRecord) -> some View {
        InkCard {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.name).font(WDFont.heading(15)).foregroundStyle(WDColor.ricePaper).lineLimit(1)
                    Text("by \(record.provenance.displayAuthor)").font(WDFont.caption(11)).foregroundStyle(WDColor.mist)
                }
                Spacer()
                Text(String(format: "%.1f km", record.distanceKm)).font(WDFont.mono(14)).foregroundStyle(WDColor.bamboo)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 96)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "map").font(.system(size: 40, weight: .ultraLight)).foregroundStyle(WDColor.mist.opacity(0.5))
            Text("导入路线后可在此查看").font(WDFont.body(15)).foregroundStyle(WDColor.mist)
        }
    }
}
