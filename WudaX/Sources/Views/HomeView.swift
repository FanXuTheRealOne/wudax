import SwiftUI
import UniformTypeIdentifiers

// MARK: - 首页「行程」

struct HomeView: View {
    @EnvironmentObject var session: TripSession
    @State private var showExo = ProcessInfo.processInfo.environment["WUDAX_PHASE"] == "exo"
    @State private var showChat = false
    @State private var showGPXImporter = false
    @State private var appeared = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                header
                routeCard
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 24)
                GhostButton(title: "导入 GPX 路线", color: WDColor.ricePaper.opacity(0.8)) {
                    showGPXImporter = true
                }
                fatigueSection
                aiSection
                gearSection
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 22)
        }
        .background(alignment: .top) { mountainHeader }
        .onAppear {
            withAnimation(.spring(duration: 0.9).delay(0.15)) { appeared = true }
        }
        .sheet(isPresented: $showExo) { ExoShowcaseView() }
        .sheet(isPresented: $showChat) { ChatView() }
        .fileImporter(
            isPresented: $showGPXImporter,
            allowedContentTypes: [.xml, .data],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            session.importGPX(from: url)
        }
        .alert("GPX 导入", isPresented: Binding(
            get: { session.routeImportMessage != nil },
            set: { if !$0 { session.routeImportMessage = nil } }
        )) {
            Button("确定", role: .cancel) { session.routeImportMessage = nil }
        } message: {
            Text(session.routeImportMessage ?? "")
        }
    }

    private var mountainHeader: some View {
        Group {
            if let ui = UIImage(named: "ink_mountains") {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 300)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .mask(
                        LinearGradient(
                            stops: [.init(color: .black, location: 0),
                                    .init(color: .black, location: 0.6),
                                    .init(color: .clear, location: 1)],
                            startPoint: .top, endPoint: .bottom)
                    )
                    .opacity(0.85)
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 90) {
            HStack {
                if let logo = UIImage(named: "logo_white") {
                    Image(uiImage: logo)
                        .resizable().scaledToFit().frame(height: 26)
                } else {
                    Text("wudaX").font(WDFont.title(24)).foregroundStyle(WDColor.ricePaper)
                }
                Spacer()
                Image(systemName: "person.circle")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(WDColor.ricePaper.opacity(0.8))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("行 程")
                    .font(WDFont.title(34))
                    .foregroundStyle(WDColor.ricePaper)
                Rectangle()
                    .fill(WDColor.amber)
                    .frame(width: 44, height: 2.5)
            }
        }
        .padding(.top, 6)
    }

    private var routeCard: some View {
        Button { session.startPlanning() } label: {
            InkCard(light: true) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(session.plan.route.name)
                        .font(WDFont.title(25))
                        .foregroundStyle(WDColor.ink)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)

                    HStack(spacing: 0) {
                        metric("location", "距离", String(format: "%.1f", session.plan.route.distanceKm), "km")
                        divider
                        metric("mountain.2", "累计爬升", "\(Int(session.plan.route.ascentM))", "m")
                        divider
                        metric("clock", "预计耗时", String(format: "%.1f", session.plan.route.estimatedHours), "h")
                    }

                    HStack {
                        Label("中高风险", systemImage: "exclamationmark.triangle.fill")
                            .font(WDFont.body(13).weight(.medium))
                            .foregroundStyle(WDColor.amber)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(WDColor.amber.opacity(0.6), lineWidth: 1)
                            )
                        Spacer()
                        Text("开始规划")
                            .font(WDFont.body(13).weight(.semibold))
                            .foregroundStyle(WDColor.ricePaper)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Capsule().fill(WDColor.ink))
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle().fill(WDColor.ink.opacity(0.12)).frame(width: 1, height: 40)
            .padding(.horizontal, 10)
    }

    private func metric(_ icon: String, _ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: icon)
                .font(WDFont.caption(11))
                .foregroundStyle(WDColor.ink.opacity(0.55))
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 24, weight: .semibold, design: .serif))
                Text(unit).font(WDFont.caption(11))
            }
            .foregroundStyle(WDColor.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fatigueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("疲劳档案", systemImage: "doc.text")
                    .font(WDFont.heading(17))
                    .foregroundStyle(WDColor.ricePaper)
                Spacer()
                Text("已记录 \(session.profile.tripsRecorded) 次行程")
                    .font(WDFont.caption()).foregroundStyle(WDColor.mist)
            }
            HStack(spacing: 12) {
                profileTile(icon: "figure.hiking",
                            title: "下坡耐受",
                            value: String(format: "%.1f km", session.profile.descentToleranceKm),
                            note: "累计下降后膝痛出现")
                profileTile(icon: "drop",
                            title: "补给习惯",
                            value: String(format: "%.2f L/h", session.profile.waterRatePerHour),
                            note: "平均耗水速率")
            }
        }
    }

    private func profileTile(icon: String, title: String, value: String, note: String) -> some View {
        InkCard {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(WDColor.bamboo)
                Text(title).font(WDFont.caption()).foregroundStyle(WDColor.mist)
                Text(value).font(WDFont.mono(17)).foregroundStyle(WDColor.ricePaper)
                Text(note).font(WDFont.caption(10)).foregroundStyle(WDColor.mist.opacity(0.7))
            }
        }
    }

    private var aiSection: some View {
        Button { showChat = true } label: {
            InkCard {
                HStack(spacing: 14) {
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(WDColor.amber)
                        .frame(width: 54, height: 54)
                        .background(RoundedRectangle(cornerRadius: 12).fill(WDColor.mossSurface))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("WUDAX 助手")
                            .font(WDFont.heading(16)).foregroundStyle(WDColor.ricePaper)
                        Text("端侧离线小模型 · 随时问徒步的事")
                            .font(WDFont.caption()).foregroundStyle(WDColor.mist)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13)).foregroundStyle(WDColor.mist)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var gearSection: some View {
        Button { showExo = true } label: {
            InkCard {
                HStack(spacing: 14) {
                    Group {
                        if let ui = UIImage(named: "exo_thumb") {
                            Image(uiImage: ui).resizable().scaledToFit()
                        } else {
                            Image(systemName: "figure.walk.motion")
                                .font(.system(size: 26, weight: .light))
                                .foregroundStyle(WDColor.amber)
                        }
                    }
                    .frame(width: 54, height: 54)
                    .background(RoundedRectangle(cornerRadius: 12).fill(WDColor.mossSurface))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("WUDAX 膝关节外骨骼")
                            .font(WDFont.heading(16)).foregroundStyle(WDColor.ricePaper)
                        Text("v2.0 数据接入预留 · 查看 3D 模型")
                            .font(WDFont.caption()).foregroundStyle(WDColor.mist)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13)).foregroundStyle(WDColor.mist)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
