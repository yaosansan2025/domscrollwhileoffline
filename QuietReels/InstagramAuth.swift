import AuthenticationServices
import Combine
import Foundation
import Security
import UIKit

struct InstagramCredential: Codable {
    let accessToken: String
    let expiresAt: Date
}

enum InstagramAuthError: LocalizedError {
    case configuration
    case callback
    case expired
    case server(String)

    var errorDescription: String? {
        switch self {
        case .configuration: return "Set the HTTPS authentication service URL in Settings."
        case .callback: return "Instagram sign-in did not return a valid authorization ticket."
        case .expired: return "Your Instagram session expired. Sign in again."
        case .server(let message): return message
        }
    }
}

@MainActor
final class InstagramAuth: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published private(set) var credential: InstagramCredential?
    @Published private(set) var isSigningIn = false
    @Published var errorMessage: String?
    @Published var serviceURLString: String {
        didSet { UserDefaults.standard.set(serviceURLString, forKey: "instagramAuthServiceURL") }
    }

    private var browserSession: ASWebAuthenticationSession?
    private let keychainService = "org.example.QuietReels.instagramCredential"

    override init() {
        serviceURLString = UserDefaults.standard.string(forKey: "instagramAuthServiceURL") ?? ""
        super.init()
        credential = readCredential()
    }

    var isSignedIn: Bool { credential != nil }

    func signIn() async {
        guard !isSigningIn else { return }
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false; browserSession = nil }
        do {
            let base = try serviceURL()
            let nonce = UUID().uuidString
            var startParts = URLComponents(url: base.appendingPathComponent("auth/start"),
                                           resolvingAgainstBaseURL: false)!
            startParts.queryItems = [URLQueryItem(name: "nonce", value: nonce)]
            let start = startParts.url!
            let callback = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                let session = ASWebAuthenticationSession(url: start, callbackURLScheme: "quietreels") { url, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let url { continuation.resume(returning: url) }
                    else { continuation.resume(throwing: InstagramAuthError.callback) }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                browserSession = session
                if !session.start() { continuation.resume(throwing: InstagramAuthError.callback) }
            }
            guard callback.scheme == "quietreels", callback.host == "oauth",
                  let callbackItems = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems,
                  let ticket = callbackItems.first(where: { $0.name == "ticket" })?.value,
                  callbackItems.first(where: { $0.name == "nonce" })?.value == nonce,
                  !ticket.isEmpty else { throw InstagramAuthError.callback }
            var request = URLRequest(url: base.appendingPathComponent("auth/redeem"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["ticket": ticket])
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw InstagramAuthError.server(Self.serverMessage(data))
            }
            let result = try JSONDecoder().decode(TokenResponse.self, from: data)
            guard !result.accessToken.isEmpty, result.expiresIn > 0 else {
                throw InstagramAuthError.callback
            }
            let newCredential = InstagramCredential(accessToken: result.accessToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(result.expiresIn)))
            try saveCredential(newCredential)
            credential = newCredential
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func validToken() async throws -> String {
        guard let credential else { throw InstagramAuthError.expired }
        if credential.expiresAt <= Date() {
            signOut()
            throw InstagramAuthError.expired
        }
        if credential.expiresAt.timeIntervalSinceNow < 14 * 86_400 {
            do { try await refresh(credential) }
            catch {
                if credential.expiresAt.timeIntervalSinceNow < 60 { throw error }
            }
        }
        return self.credential?.accessToken ?? credential.accessToken
    }

    func signOut() {
        SecItemDelete(keychainQuery() as CFDictionary)
        credential = nil
        errorMessage = nil
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    private func serviceURL() throws -> URL {
        guard let url = URL(string: serviceURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", url.host != nil, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { throw InstagramAuthError.configuration }
        return url
    }

    private func refresh(_ existing: InstagramCredential) async throws {
        var parts = URLComponents(string: "https://graph.instagram.com/refresh_access_token")!
        parts.queryItems = [URLQueryItem(name: "grant_type", value: "ig_refresh_token"),
                            URLQueryItem(name: "access_token", value: existing.accessToken)]
        let request = URLRequest(url: parts.url!)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw InstagramAuthError.server(Self.serverMessage(data))
        }
        let result = try JSONDecoder().decode(TokenResponse.self, from: data)
        let renewed = InstagramCredential(accessToken: result.accessToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(result.expiresIn)))
        try saveCredential(renewed)
        credential = renewed
    }

    private func keychainQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: keychainService,
         kSecAttrAccount as String: "professional-account"]
    }

    private func readCredential() -> InstagramCredential? {
        var query = keychainQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(InstagramCredential.self, from: data)
    }

    private func saveCredential(_ value: InstagramCredential) throws {
        let data = try JSONEncoder().encode(value)
        SecItemDelete(keychainQuery() as CFDictionary)
        var query = keychainQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw InstagramAuthError.server("Could not save the Instagram session in Keychain (\(status)).")
        }
    }

    private static func serverMessage(_ data: Data) -> String {
        (try? JSONDecoder().decode(ServerError.self, from: data).error) ??
            "The authentication service returned an error."
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let expiresIn: Int
        enum CodingKeys: String, CodingKey { case accessToken = "access_token", expiresIn = "expires_in" }
    }
    private struct ServerError: Decodable { let error: String }
}
