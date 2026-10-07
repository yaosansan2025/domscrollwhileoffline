import SwiftUI

struct AccountSourcesView: View {
    @EnvironmentObject private var offline: AuthorizedOfflineStore
    @State private var selectedAccount: OfflineAccount?
    @State private var adding = false
    @State private var username = ""
    @State private var addError: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if offline.accounts.isEmpty {
                    ContentUnavailableView {
                        Label("No accounts added", systemImage: "person.crop.circle.badge.plus")
                    } description: {
                        Text("Add a username later to organize videos from that creator. This does not connect to Instagram or download posts.")
                    } actions: {
                        Button("Add account") { addError = nil; adding = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        Section {
                            ForEach(offline.accounts) { account in
                                Button {
                                    selectedAccount = account
                                } label: {
                                    HStack {
                                        Label("@\(account.username)", systemImage: "person.crop.circle")
                                        Spacer()
                                        Text("\(offline.reels.filter { $0.accountID == account.id }.count)")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .swipeActions {
                                    Button("Remove", role: .destructive) {
                                        do { try offline.removeAccount(account) }
                                        catch { errorMessage = error.localizedDescription }
                                    }
                                    .disabled(offline.isSaving)
                                }
                            }
                        } footer: {
                            Text("Tap an account to import its video files and watch them offline. Removing an account keeps its videos in the main feed.")
                        }
                    }
                }
            }
            .navigationTitle("Accounts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add account", systemImage: "plus") { addError = nil; adding = true }
                }
            }
            .sheet(isPresented: $adding) {
                NavigationStack {
                    Form {
                        TextField("Instagram username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Text("A username labels a local collection. It does not sign in or fetch videos.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let addError {
                            Text(addError).foregroundStyle(.red)
                        }
                    }
                    .navigationTitle("Add account")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") { adding = false }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Add") {
                                do {
                                    try offline.addAccount(username: username)
                                    username = ""
                                    adding = false
                                } catch { addError = error.localizedDescription }
                            }
                        }
                    }
                }
            }
            .sheet(item: $selectedAccount) { account in
                AuthorizedOfflineView(accountID: account.id)
                    .environmentObject(offline)
                    .presentationDragIndicator(.visible)
            }
            .alert("Account error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) { Button("OK") { errorMessage = nil } } message: {
                Text(errorMessage ?? "")
            }
        }
    }
}
