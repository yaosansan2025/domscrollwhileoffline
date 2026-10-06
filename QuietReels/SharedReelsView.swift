import SwiftUI
import UniformTypeIdentifiers

struct SharedReelsView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var cache: OfflineCacheStore
    @State private var adding = false

    var body: some View {
        NavigationStack {
            Group {
                if library.sharedClips.isEmpty {
                    ContentUnavailableView {
                        Label("No shared Reels yet", systemImage: "play.rectangle")
                    } description: {
                        Text("Choose a Reel in a friend's DM, then add its link and a saved video here.")
                    } actions: {
                        Button("Add shared Reel") { adding = true }
                    }
                } else {
                    List(library.sharedClips) { clip in
                        if let url = playbackURL(for: clip) {
                            NavigationLink {
                                LocalVideoView(videoURL: url, title: "Shared by \(clip.sender)",
                                               subtitle: clip.conversation,
                                               backTitle: "Back to Shared Reels", cacheClip: clip,
                                               cacheSourceURL: library.playbackURL(for: clip))
                            } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(clip.sender).font(.headline)
                                        Text(clip.conversation).font(.subheadline).foregroundStyle(.secondary)
                                        if cache.cachedVideo(for: clip) != nil {
                                            Text("Cached offline").font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                } icon: {
                                    Image(systemName: "play.rectangle.fill")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Shared Reels")
            .toolbar {
                Button { adding = true } label: { Label("Add", systemImage: "plus") }
            }
            .sheet(isPresented: $adding) {
                AddSharedClipView()
            }
        }
    }

    private func playbackURL(for clip: SharedClip) -> URL? {
        if let cached = cache.cachedVideo(for: clip) { return cache.fileURL(for: cached) }
        return library.playbackURL(for: clip)
    }
}

private struct AddSharedClipView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var sender = ""
    @State private var conversation = ""
    @State private var reelURL = ""
    @State private var directVideoURL = ""
    @State private var sourceIsURL = false
    @State private var pickingFile = false
    @State private var errorMessage = ""
    @State private var showingError = false

    var body: some View {
        NavigationStack {
            Form {
                Section("From the shared message") {
                    TextField("Friend's name", text: $sender)
                    TextField("Chat or group name", text: $conversation)
                    TextField("Reel link", text: $reelURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                Section {
                    Picker("Source", selection: $sourceIsURL) {
                        Text("Saved file").tag(false)
                        Text("Direct URL").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if sourceIsURL {
                        TextField("Direct .mp4, .mov, or .m4v URL", text: $directVideoURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }
                } header: {
                    Text("Video source")
                } footer: {
                    Text("A Reel page URL is not a video URL. Direct video URLs are an optional prototype source and may expire or require authorization.")
                }
                Section {
                    if sourceIsURL {
                        Button("Add shared Reel") {
                            do {
                                try library.addRemoteSharedClip(sender: sender,
                                    conversation: conversation, reelURL: reelURL,
                                    directVideoURL: directVideoURL)
                                dismiss()
                            } catch {
                                show(error)
                            }
                        }
                        .disabled(missingDetails || directVideoURL.isEmpty)
                    } else {
                        Button("Choose saved video from Files") { pickingFile = true }
                            .disabled(missingDetails)
                    }
                } footer: {
                    Text("Open the message in Instagram yourself. This app cannot read DMs or download a Reel from its link. Import only a video you are allowed to save.")
                }
            }
            .navigationTitle("Add shared Reel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.movie]) { result in
                do {
                    let url = try result.get()
                    try library.importSharedClip(from: url, sender: sender,
                                                 conversation: conversation, reelURL: reelURL)
                    dismiss()
                } catch {
                    show(error)
                }
            }
            .alert("Could not add Reel", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private var missingDetails: Bool {
        sender.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        conversation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        reelURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func show(_ error: Error) {
        errorMessage = error.localizedDescription
        showingError = true
    }
}
