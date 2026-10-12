import SwiftUI

struct FeatureChatView: View {
    @ObservedObject var store: FeatureChatStore
    let chatId: UUID
    let profile: String
    @Environment(\.dismiss) private var dismiss

    @State private var input = ""
    @State private var isSending = false
    @State private var error: String?
    @State private var selectedBulletIds: Set<UUID> = []
    @State private var isSavingBullets = false
    @State private var savedToast = false

    private var chat: FeatureChat? { store.chats.first { $0.id == chatId } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messagesView
                Divider()
                inputBar
            }
            .navigationTitle(chat?.title ?? "Feature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if let chat {
                        Text(chat.company.displayName(for: profile))
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.indigo.opacity(0.12), in: Capsule())
                            .foregroundColor(.indigo)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if savedToast {
                    Text("Added to pool")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.bottom, 80)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: savedToast)
        }
    }

    // MARK: - Messages

    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if let chat {
                        ForEach(chat.messages) { msg in
                            if msg.role == .user {
                                userBubble(msg)
                            } else {
                                assistantBubble(msg)
                            }
                        }
                    }
                    if isSending {
                        HStack {
                            ProgressView()
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                            Spacer()
                        }
                    }
                    if let error {
                        Text(error).font(.caption).foregroundColor(.red).padding(.horizontal)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal).padding(.top, 12)
            }
            .onChange(of: chat?.messages.count) { _ in
                withAnimation { proxy.scrollTo("bottom") }
            }
            .onChange(of: isSending) { _ in
                withAnimation { proxy.scrollTo("bottom") }
            }
            .onAppear { proxy.scrollTo("bottom") }
        }
    }

    private func userBubble(_ msg: ChatMessage) -> some View {
        HStack {
            Spacer(minLength: 60)
            Text(msg.content)
                .font(.system(size: 15))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color.indigo)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    @ViewBuilder
    private func assistantBubble(_ msg: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !msg.content.isEmpty {
                Text(msg.content)
                    .font(.system(size: 15))
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .frame(maxWidth: .infinity * 0.85, alignment: .leading)
            }
            if !msg.bullets.isEmpty {
                VStack(spacing: 6) {
                    ForEach(msg.bullets, id: \.id) { bullet in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: selectedBulletIds.contains(bullet.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selectedBulletIds.contains(bullet.id) ? .indigo : .secondary)
                                .font(.system(size: 20))
                                .padding(.top, 1)
                            Text(bullet.displayText)
                                .font(.system(size: 14))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(selectedBulletIds.contains(bullet.id) ? Color.indigo.opacity(0.08) : Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedBulletIds.contains(bullet.id) {
                                selectedBulletIds.remove(bullet.id)
                            } else {
                                selectedBulletIds.insert(bullet.id)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Input bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            if !selectedBulletIds.isEmpty {
                Button(action: addSelectedToPool) {
                    Group {
                        if isSavingBullets { ProgressView().tint(.white) }
                        else { Text("Add \(selectedBulletIds.count) to Pool").fontWeight(.semibold) }
                    }
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .background(Color.indigo)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .disabled(isSavingBullets)
                .padding(.horizontal).padding(.top, 8)
            }

            HStack(alignment: .bottom, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    if input.isEmpty {
                        Text("Describe a feature, or 'make it more technical'…")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                            .padding(.horizontal, 5).padding(.vertical, 9)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $input)
                        .font(.system(size: 15))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 36, maxHeight: 120)
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("Done") {
                                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                }
                            }
                        }
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 34))
                        .foregroundColor(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending ? .secondary : .indigo)
                }
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }
            .padding(.horizontal).padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Actions

    private func send() {
        guard var chat = chat else { return }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        isSending = true
        error = nil

        let userMsg = ChatMessage(role: .user, content: text)
        chat.messages.append(userMsg)
        chat.updatedAt = Date()
        if chat.title == "New Feature" { chat.title = String(text.prefix(40)) }
        store.update(chat)

        Task {
            do {
                let history = chat.messages.map { ($0.role.rawValue, $0.content) }
                let (replyText, bullets) = try await CVProfileService.chatBullets(
                    messages: history.map { (role: $0.0, content: $0.1) },
                    company: chat.company.apiKey,
                    profile: profile
                )
                let persisted = bullets.map { PersistedBullet(latex: $0.latex, skills: $0.skills) }
                var updated = store.chats.first { $0.id == chatId } ?? chat
                updated.messages.append(ChatMessage(role: .assistant, content: replyText, bullets: persisted))
                updated.updatedAt = Date()
                store.update(updated)
            } catch {
                self.error = error.localizedDescription
            }
            isSending = false
        }
    }

    private func addSelectedToPool() {
        guard let chat = chat else { return }
        isSavingBullets = true
        let toAdd = chat.messages
            .filter { $0.role == .assistant }
            .flatMap { $0.bullets }
            .filter { selectedBulletIds.contains($0.id) }

        Task {
            do {
                var prof = try await CVProfileService.fetchProfile(for: profile)
                var pool = prof.bullets.pool(for: chat.company)
                for b in toAdd {
                    let newId = "\(chat.company.apiKey)_\(UUID().uuidString.prefix(6).lowercased())"
                    pool.append(CVProfileBullet(id: newId, pinned: false, skills: b.skills, latex: b.latex))
                }
                prof.bullets.setPool(pool, for: chat.company)
                try await CVProfileService.saveBullets(prof.bullets, for: profile)
                selectedBulletIds = []
                savedToast = true
                Task { try? await Task.sleep(nanoseconds: 2_000_000_000); savedToast = false }
            } catch {
                self.error = error.localizedDescription
            }
            isSavingBullets = false
        }
    }
}
