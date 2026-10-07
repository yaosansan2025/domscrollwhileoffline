import SwiftUI

struct ProfessionalSettingsView: View {
    @EnvironmentObject private var auth: InstagramAuth
    @EnvironmentObject private var instagram: InstagramStore

    var body: some View {
        NavigationStack {
            Form {
                Section("Instagram professional account") {
                    if auth.isSignedIn {
                        Text(instagram.profile.map { "Connected as @\($0.username)" } ?? "Connected")
                        Button("Log out", role: .destructive) {
                            auth.signOut()
                            instagram.clear()
                        }
                    } else {
                        Button(auth.isSigningIn ? "Signing in…" : "Sign in with Instagram") {
                            Task { await auth.signIn() }
                        }
                        .disabled(auth.isSigningIn)
                    }
                    if let error = auth.errorMessage {
                        Text(error).foregroundStyle(.red)
                    }
                } footer: {
                    Text("Meta's official API supports Business and Creator accounts. This app shows your own media; it has no personalized recommendation feed.")
                }
                Section("Authentication service") {
                    TextField("https://your-service.example", text: $auth.serviceURLString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } footer: {
                    Text("Configure an HTTPS token-exchange service before signing in. The Instagram app secret stays on that service; the access token is stored in this device's Keychain.")
                }
            }
            .navigationTitle("Settings")
        }
    }
}
