import SwiftUI
import UniformTypeIdentifiers

struct AuthorizedOfflineView: View {
    @EnvironmentObject private var offline: AuthorizedOfflineStore
    var accountID: String? = nil
    @State private var importing = false
    @State private var managing = false
    @State private var confirmClear = false

    private var account: OfflineAccount? { offline.accounts.first { $0.id == accountID } }
    private var visibleReels: [OfflineReel] {
        guard let accountID else { return offline.reels }
        return offline.reels.filter { $0.accountID == accountID }
    }

    var body: some View {
        NavigationStack {
            Group {
                if visibleReels.isEmpty {
                    ContentUnavailableView {
                        Label(account == nil ? "Your offline feed is empty" : "No videos for this account",
                              systemImage: "play.rectangle")
                    } description: {
                        Text("Import video files you have permission to keep. Adding an account name does not download its posts.")
                    } actions: {
                        Button("Import videos") { importing = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ReelFeedView(reels: visibleReels.map { reel in
                        PlayableReel(id: reel.id, videoURL: offline.fileURL(for: reel),
                                     creator: reel.creator, caption: reel.caption,
                                     likes: nil, comments: nil)
                    }, loops: true)
                }
            }
            .navigationTitle(account.map { "@\($0.username)" } ?? "Offline Feed")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Import videos", systemImage: "square.and.arrow.down") {
                            importing = true
                        }
                        Button("Manage saved videos", systemImage: "list.bullet") {
                            managing = true
                        }
                        .disabled(visibleReels.isEmpty)
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .overlay {
                if offline.isSaving {
                    ProgressView("Saving video…")
                        .padding().background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.movie],
                          allowsMultipleSelection: true) { result in
                do {
                    let urls = try result.get()
                    Task {
                        for url in urls { await offline.importFile(url, accountID: accountID) }
                    }
                } catch { offline.errorMessage = error.localizedDescription }
            }
            .sheet(isPresented: $managing) {
                NavigationStack {
                    List {
                        Section {
                            Text(ByteCountFormatter.string(fromByteCount: visibleReels.reduce(0) { $0 + $1.byteCount },
                                                          countStyle: .file))
                        } header: { Text("Storage used") }
                        Section("Saved videos") {
                            ForEach(visibleReels) { reel in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(reel.creator).font(.headline)
                                        Text(reel.caption).lineLimit(1).font(.caption)
                                    }
                                    Spacer()
                                    Text(ByteCountFormatter.string(fromByteCount: reel.byteCount,
                                                                  countStyle: .file))
                                        .font(.caption)
                                }
                                .swipeActions {
                                    Button("Delete", role: .destructive) {
                                        do { try offline.delete(reel) }
                                        catch { offline.errorMessage = error.localizedDescription }
                                    }
                                    .disabled(offline.isSaving)
                                }
                            }
                        }
                    }
                    .navigationTitle("Offline library")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") { managing = false }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Clear all", role: .destructive) { confirmClear = true }
                                .disabled(offline.isSaving || visibleReels.isEmpty)
                        }
                    }
                    .confirmationDialog("Delete all offline videos?", isPresented: $confirmClear) {
                        Button("Delete all", role: .destructive) {
                            do {
                                if accountID == nil { try offline.clearAll() }
                                else { for reel in visibleReels { try offline.delete(reel) } }
                            }
                            catch { offline.errorMessage = error.localizedDescription }
                        }
                    }
                }
            }
            .alert("Offline video error", isPresented: Binding(
                get: { offline.errorMessage != nil },
                set: { if !$0 { offline.errorMessage = nil } }
            )) { Button("OK") { offline.errorMessage = nil } } message: {
                Text(offline.errorMessage ?? "")
            }
        }
    }
}
