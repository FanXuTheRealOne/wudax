import SwiftUI

// MARK: - 「行程」Tab：开始规划 + 历史 GPX 记录 + WUDAX 助手

struct HomeView: View {
    @EnvironmentObject var session: TripSession
    @EnvironmentObject var library: RouteLibraryStore
    @EnvironmentObject var navigation: AppNavigation
    @State private var showChat = false
    @State private var showAllRoutes = false
    @State private var detailRecord: RouteRecord?
    @State private var renaming: RouteRecord?
    @State private var newName = ""
    @State private var appeared = false

    private var recentRecords: [RouteRecord] { Array(library.records.prefix(4)) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                header
                startPlanningRow
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)
                historySection
                aiSection
                Spacer(minLength: 96)
            }
            .padding(.horizontal, 22)
        }
        .background(alignment: .top) { mountainHeader }
        .onAppear { withAnimation(.spring(duration: 0.9).delay(0.1)) { appeared = true } }
        .sheet(isPresented: $showChat) { ChatView() }
        .sheet(isPresented: $showAllRoutes) { AllRoutesView() }
        .sheet(item: $detailRecord) { record in
            RouteDetailView(record: record) {
                detailRecord = nil
                session.planRecord(record)
            }
        }
        .alert("重命名路线", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("路线名称", text: $newName)
            Button("取消", role: .cancel) { renaming = nil }
            Button("保存") {
                if let record = renaming, !newName.trimmingCharacters(in: .whitespaces).isEmpty {
                    library.rename(record, to: newName)
                }
                renaming = nil
            }
        }
    }

    // MARK: 顶部山景 + Logo

    private var mountainHeader: some View {
        Group {
            if let ui = UIImage(named: "hero_morning") ?? UIImage(named: "ink_mountains") {
                Image(uiImage: ui)
                    .resizable().scaledToFill()
                    .frame(height: 340).frame(maxWidth: .infinity).clipped()
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0),
                                                 .init(color: .black, location: 0.62),
                                                 .init(color: .clear, location: 1)],
                                         startPoint: .top, endPoint: .bottom))
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    private var header: some View {
        HStack {
            if let logo = UIImage(named: "logo_white") {
                Image(uiImage: logo).resizable().scaledToFit().frame(height: 26)
            } else {
                Text("wudaX").font(WDFont.title(24)).foregroundStyle(WDColor.ricePaper)
            }
            Spacer()
            Image(systemName: "person.circle")
                .font(.system(size: 24, weight: .light)).foregroundStyle(WDColor.ricePaper.opacity(0.8))
        }
        .padding(.top, 6)
    }

    // MARK: 行程标题 + 开始规划

    private var startPlanningRow: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("行 程").font(WDFont.title(34)).foregroundStyle(WDColor.onDark)
                Rectangle().fill(WDColor.amber).frame(width: 44, height: 2.5)
            }
            Spacer()
            Button { session.startPlanning() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "figure.climbing").font(.system(size: 18, weight: .medium))
                    Text("开始规划").font(WDFont.heading(16))
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(WDColor.onDark)
                .padding(.horizontal, 18).padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 16).fill(WDColor.ink)
                    .shadow(color: WDColor.ink.opacity(0.22), radius: 10, y: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 74)
    }

    // MARK: 历史 GPX 记录

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("历史 GPX 记录", systemImage: "clock").font(WDFont.heading(17)).foregroundStyle(WDColor.ricePaper)
                Spacer()
                Button { showAllRoutes = true } label: {
                    HStack(spacing: 3) {
                        Text("查看全部").font(WDFont.caption())
                        Image(systemName: "chevron.right").font(.system(size: 10))
                    }.foregroundStyle(WDColor.mist)
                }.buttonStyle(.plain)
            }
            if recentRecords.isEmpty {
                emptyHistory
            } else {
                ForEach(recentRecords) { record in
                    RouteRecordCard(record: record) {
                        navigation.showRouteOnMap(record)
                        Haptics.tap()
                    }
                        .contentShape(Rectangle())
                        .onTapGesture { detailRecord = record }
                        .contextMenu {
                            Button { detailRecord = record } label: { Label("查看详情", systemImage: "eye") }
                            Button { renaming = record; newName = record.name } label: { Label("重命名", systemImage: "pencil") }
                            Button(role: .destructive) { library.delete(record) } label: { Label("删除", systemImage: "trash") }
                        }
                }
            }
        }
    }

    private var emptyHistory: some View {
        InkCard {
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down").font(.system(size: 22, weight: .light)).foregroundStyle(WDColor.mist)
                VStack(alignment: .leading, spacing: 3) {
                    Text("还没有路线").font(WDFont.body(15)).foregroundStyle(WDColor.ricePaper)
                    Text("点「开始规划」导入一段 GPX 轨迹").font(WDFont.caption()).foregroundStyle(WDColor.mist)
                }
                Spacer()
            }
        }
    }

    // MARK: WUDAX 助手

    private var aiSection: some View {
        Button { showChat = true } label: {
            InkCard {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: "bubble.left.fill")
                                .font(.system(size: 20)).foregroundStyle(WDColor.amber)
                                .frame(width: 44, height: 44)
                                .background(RoundedRectangle(cornerRadius: 12).fill(WDColor.mossSurface))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("WUDAX 助手").font(WDFont.heading(16)).foregroundStyle(WDColor.ricePaper)
                                Text("端侧离线小模型 · 随时问徒步的事").font(WDFont.caption()).foregroundStyle(WDColor.mist)
                            }
                            Spacer()
                            Image(systemName: "waveform").font(.system(size: 20)).foregroundStyle(WDColor.amber)
                        }
                        HStack(spacing: 8) {
                            chip("如何降低膝盖压力？")
                            chip("高原徒步注意事项")
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(WDFont.caption(11)).foregroundStyle(WDColor.ricePaper.opacity(0.85))
            .lineLimit(1)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Capsule().fill(WDColor.mossSurface))
    }
}
