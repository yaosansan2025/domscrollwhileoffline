import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ProfileView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var name = ""
    @State private var pickingFile = false
    @State private var errorMessage = ""
    @State private var showingError = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Your name", text: $name)
                        .textInputAutocapitalization(.words)
                    Button("Save name") {
                        do {
                            try library.setProfileName(name)
                        } catch {
                            show(error)
                        }
                    }
                    .disabled(name == library.profileName)
                } footer: {
                    Text("Local profile only. Instagram does not provide personal profile and post sync for this app.")
                }

                Section("My posts") {
                    if library.profilePosts.isEmpty {
                        Text("No local posts yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(library.profilePosts) { post in
                            NavigationLink {
                                ProfilePostView(post: post,
                                                fileURL: library.fileURL(named: post.fileName))
                            } label: {
                                Label(post.title, systemImage: post.kind == .image
                                      ? "photo" : "play.rectangle")
                            }
                        }
                    }
                    Button("Import my photo or video from Files") { pickingFile = true }
                }
            }
            .navigationTitle("My Profile")
            .onAppear { name = library.profileName }
            .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.image, .movie]) { result in
                do {
                    let url = try result.get()
                    try library.importProfilePost(from: url)
                } catch {
                    show(error)
                }
            }
            .alert("Could not save", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func show(_ error: Error) {
        errorMessage = error.localizedDescription
        showingError = true
    }
}

private struct ProfilePostView: View {
    let post: ProfilePost
    let fileURL: URL

    var body: some View {
        Group {
            if post.kind == .video {
                LocalVideoView(videoURL: fileURL, title: post.title,
                               subtitle: "Local profile post", backTitle: "Back to My Profile")
            } else if let image = UIImage(contentsOfFile: fileURL.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black)
            } else {
                ContentUnavailableView("Image unavailable", systemImage: "photo")
            }
        }
        .navigationTitle(post.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
