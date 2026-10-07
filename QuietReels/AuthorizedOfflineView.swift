import SwiftUI
import UniformTypeIdentifiers

struct AuthorizedOfflineView: View {
    @EnvironmentObject private var offline: AuthorizedOfflineStore
    @State private var importing = false
    @State private var managing = false
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            Group {
                if offline.reels.isEmpty {
                    ContentUnavailableView {
                        Label("Your offline feed is empty", systemImage: "play.rectangle")
                    } description: {
                        Text("Import videos you have permission to keep, then swipe through them whenever you are offline.")
                    } actions: {
                        Button("Import videos") { importing = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ReelFeedView(reels: offline.reels.map { reel in
                        PlayableReel(id: reel.id, videoURL: offline.fileURL(for: reel),
                                     creator: reel.creator, caption: reel.caption,
                                     likes: nil, comments: nil)
                    }, loops: true)
                }
            }
            .navigationTitle("Offline Feed")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Import videos", systemImage: "square.and.arrow.down") {
                            importing = true
                        }
                        Button("Manage saved videos", systemImage: "list.bullet") {
                            managing = true
                        }
                        .disabled(offline.reels.isEmpty)
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
                        for url in urls { await offline.importFile(url) }
                    }
                } catch { offline.errorMessage = error.localizedDescription }
            }
            .sheet(isPresented: $managing) {
                NavigationStack {
                    List {
                        Section {
                            Text(ByteCountFormatter.string(fromByteCount: offline.totalBytes,
                                                          countStyle: .file))
                        } header: { Text("Storage used") }
                        Section("Saved videos") {
                            ForEach(offline.reels) { reel in
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
                                .disabled(offline.isSaving || offline.reels.isEmpty)
                        }
                    }
                    .confirmationDialog("Delete all offline videos?", isPresented: $confirmClear) {
                        Button("Delete all", role: .destructive) {
                            do { try offline.clearAll() }
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
