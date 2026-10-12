import SwiftUI

struct FeatureChatsListView: View {
    @ObservedObject var store: FeatureChatStore
    let profile: String
    @Environment(\.dismiss) private var dismiss

    @State private var pickerCompany: CVCompany
    @State private var showNewChatPicker = false
    @State private var openChatId: UUID?

    init(store: FeatureChatStore, profile: String) {
        self.store = store
        self.profile = profile
        _pickerCompany = State(initialValue: CVCompany.cases(for: profile).first ?? .nHabit)
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.chats.isEmpty {
                    ContentUnavailableView(
                        "No Features Yet",
                        systemImage: "text.bubble",
                        description: Text("Tap + to start a new feature chat")
                    )
                } else {
                    List {
                        ForEach(store.chats) { chat in
                            Button { openChatId = chat.id } label: {
                                HStack(alignment: .center, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(chat.title)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        HStack(spacing: 5) {
                                            Text(chat.company.displayName(for: profile))
                                                .font(.caption)
                                                .foregroundColor(.indigo)
                                            if !chat.messages.isEmpty {
                                                Text("·").font(.caption).foregroundColor(.secondary)
                                                let replies = chat.messages.filter { $0.role == .assistant }.count
                                                Text("\(replies) \(replies == 1 ? "reply" : "replies")")
                                                    .font(.caption).foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                    Spacer()
                                    Text(relativeDate(chat.updatedAt))
                                        .font(.caption2).foregroundColor(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .onDelete { store.delete(at: $0) }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Features")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showNewChatPicker = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showNewChatPicker) {
                newChatSheet
            }
            .sheet(item: openChatBinding) { (chat: FeatureChat) in
                FeatureChatView(store: store, chatId: chat.id, profile: profile)
            }
        }
    }

    // Wraps UUID? into an Identifiable so .sheet(item:) works
    private var openChatBinding: Binding<FeatureChat?> {
        Binding(
            get: { openChatId.flatMap { id in store.chats.first { $0.id == id } } },
            set: { if $0 == nil { openChatId = nil } }
        )
    }

    private var newChatSheet: some View {
        NavigationStack {
            Form {
                Section("Experience") {
                    Picker("Company", selection: $pickerCompany) {
                        ForEach(CVCompany.cases(for: profile), id: \.self) { co in
                            Text(co.displayName(for: profile)).tag(co)
                        }
                    }
                    .pickerStyle(.wheel)
                }
            }
            .navigationTitle("New Feature Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { showNewChatPicker = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        showNewChatPicker = false
                        let chat = store.create(company: pickerCompany)
                        openChatId = chat.id
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private func relativeDate(_ date: Date) -> String {
    let diff = Date().timeIntervalSince(date)
    if diff < 60 { return "now" }
    if diff < 3600 { return "\(Int(diff / 60))m" }
    if diff < 86400 { return "\(Int(diff / 3600))h" }
    return "\(Int(diff / 86400))d"
}
