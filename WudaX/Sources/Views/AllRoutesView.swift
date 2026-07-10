import SwiftUI

/// 「查看全部」——完整的历史 GPX 记录管理:滑动删除、重命名(增删改查中的删/改)。
struct AllRoutesView: View {
    @EnvironmentObject var session: TripSession
    @EnvironmentObject var library: RouteLibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var renaming: RouteRecord?
    @State private var newName = ""
    @State private var detailRecord: RouteRecord?

    var body: some View {
        ZStack {
            WDColor.inkPine.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                if library.records.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(library.records) { record in
                            Button { detailRecord = record } label: {
                                RouteRecordCard(record: record)
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) { library.delete(record) } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                Button { renaming = record; newName = record.name } label: {
                                    Label("重命名", systemImage: "pencil")
                                }.tint(WDColor.amber)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
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

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .medium)).foregroundStyle(WDColor.ricePaper)
            }
            Spacer()
            Text("历史 GPX 记录").font(WDFont.heading(18)).foregroundStyle(WDColor.ricePaper)
            Spacer()
            Text("\(library.records.count) 条").font(WDFont.caption()).foregroundStyle(WDColor.mist)
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "tray").font(.system(size: 40, weight: .ultraLight)).foregroundStyle(WDColor.mist.opacity(0.5))
            Text("还没有导入过路线").font(WDFont.body(15)).foregroundStyle(WDColor.mist)
            Spacer()
        }.frame(maxWidth: .infinity)
    }
}
