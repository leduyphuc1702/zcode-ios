import Foundation
import AuthenticationServices
import CryptoKit
import Security
import UIKit

public enum ZaiAuthError: LocalizedError {
    case cancelled
    case invalidToken(String)
    case oauthFailed(String)
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Sign-in was cancelled."
        case .invalidToken(let detail):
            return detail
        case .oauthFailed(let detail):
            return detail
        case .networkError(let detail):
            return detail
        }
    }
}

public struct ZaiAuthResult: Equatable {
    public let account: ZaiUserAccount
    public let zcodeJwtToken: String
    public let providerAccessToken: String
}

/// 100% Native iOS Z.AI Authentication & Remote Relay Service.
/// Uses Apple's system `ASWebAuthenticationSession` (`AuthenticationServices`) + `URLSession` + `CryptoKit`
/// — strictly zero `WKWebView`, `UIWebView`, `SFSafariViewController`, or `WebKit`.
@MainActor
public final class ZaiAuthAndRemoteService: NSObject, ASWebAuthenticationPresentationContextProviding {
    public static let shared = ZaiAuthAndRemoteService()

    private let urlSession: URLSession
    private var activeWebAuthSession: ASWebAuthenticationSession?
    private var activePollTask: Task<Void, Never>?

    private static let zaiClientId = "client_P8X5CMWmlaRO9gyO-KSqtg"
    private static let nativeRedirectURI = "zcode://oauth/callback"

    private override init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.urlSession = URLSession(configuration: config)
        super.init()
    }

    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let keyWindow = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
            return keyWindow
        }
        if let firstWindow = scenes.flatMap(\.windows).first {
            return firstWindow
        }
        return ASPresentationAnchor()
    }

    public func cancelPendingSignIn() {
        activePollTask?.cancel()
        activePollTask = nil
        activeWebAuthSession?.cancel()
        activeWebAuthSession = nil
    }

    // MARK: - 1. Native Z.AI System OAuth (CLI Polling + Direct Callback Hybrid)

    public func signInWithZaiOAuth(region: ZaiAuthRegion = .global) async throws -> ZaiAuthResult {
        cancelPendingSignIn()

        // Try initializing official ZCode OAuth CLI polling flow first; fall back to direct OAuth authorize URL
        if let cliFlow = try? await initOAuthPollingFlow(region: region) {
            return try await runSystemAuthWithPolling(flow: cliFlow, region: region)
        } else {
            return try await runDirectSystemOAuthCodeFlow(region: region)
        }
    }

    private struct CLIOAuthInitFlow {
        let flowId: String
        let authorizeURL: URL
        let pollURL: URL
        let pollToken: String
        let pollIntervalSec: Double
        let expiresAt: Date
        let state: String
    }

    private func initOAuthPollingFlow(region: ZaiAuthRegion) async throws -> CLIOAuthInitFlow {
        let pollToken = Self.generateSecureHex(byteCount: 32)
        guard let initURL = URL(string: "\(region.zcodeOrigin)/api/v1/oauth/cli/init") else {
            throw ZaiAuthError.oauthFailed("Invalid ZCode OAuth init endpoint.")
        }

        var req = URLRequest(url: initURL)
        req.httpMethod = "POST"
        req.setValue("Bearer \(pollToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["provider": region.rawValue])

        let (data, response) = try await urlSession.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["code"] as? Int) == 0,
              let payload = json["data"] as? [String: Any],
              let flowId = payload["flow_id"] as? String,
              let authURLStr = payload["authorize_url"] as? String,
              let authURL = URL(string: authURLStr) else {
            throw ZaiAuthError.oauthFailed("Could not initialize Z.AI OAuth polling flow.")
        }

        let expiresEpoch = (payload["expires_at"] as? Double) ?? (Date().timeIntervalSince1970 + 300)
        let intervalSec = max(1.5, (payload["poll_interval_sec"] as? Double) ?? 2.0)
        let encodedFlow = flowId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? flowId
        guard let pollURL = URL(string: "\(region.zcodeOrigin)/api/v1/oauth/cli/poll/\(encodedFlow)") else {
            throw ZaiAuthError.oauthFailed("Invalid Z.AI OAuth poll endpoint.")
        }
        let state = URLComponents(url: authURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "state" })?.value ?? ""

        return CLIOAuthInitFlow(
            flowId: flowId,
            authorizeURL: authURL,
            pollURL: pollURL,
            pollToken: pollToken,
            pollIntervalSec: intervalSec,
            expiresAt: Date(timeIntervalSince1970: expiresEpoch),
            state: state
        )
    }

    private func runSystemAuthWithPolling(flow: CLIOAuthInitFlow, region: ZaiAuthRegion) async throws -> ZaiAuthResult {
        return try await withCheckedThrowingContinuation { continuation in
            var isResolved = false

            @MainActor
            func finish(_ result: Result<ZaiAuthResult, Error>) {
                guard !isResolved else { return }
                isResolved = true
                self.cancelPendingSignIn()
                continuation.resume(with: result)
            }

            let session = ASWebAuthenticationSession(
                url: flow.authorizeURL,
                callbackURLScheme: "zcode"
            ) { callbackURL, error in
                Task { @MainActor in
                    if let callbackURL {
                        do {
                            let exchanged = try await self.exchangeCallbackURL(
                                callbackURL,
                                expectedState: flow.state,
                                redirectURI: Self.nativeRedirectURI,
                                region: region
                            )
                            finish(.success(exchanged))
                        } catch {
                            finish(.failure(error))
                        }
                        return
                    }
                    if let authErr = error as? ASWebAuthenticationSessionError,
                       authErr.code == .canceledLogin {
                        // Give one final poll check in case web flow finished right before user tapped Done
                        if let polled = try? await self.pollOnce(flow: flow, region: region) {
                            finish(.success(polled))
                        } else {
                            finish(.failure(ZaiAuthError.cancelled))
                        }
                    } else if let error {
                        finish(.failure(ZaiAuthError.oauthFailed(error.localizedDescription)))
                    }
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.activeWebAuthSession = session
            _ = session.start()

            // Concurrent poll loop for server-side callback completion
            self.activePollTask = Task { @MainActor in
                while !Task.isCancelled && Date() < flow.expiresAt {
                    try? await Task.sleep(nanoseconds: UInt64(flow.pollIntervalSec * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    do {
                        if let result = try await self.pollOnce(flow: flow, region: region) {
                            finish(.success(result))
                            return
                        }
                    } catch {
                        finish(.failure(error))
                        return
                    }
                }
            }
        }
    }

    private func pollOnce(flow: CLIOAuthInitFlow, region: ZaiAuthRegion) async throws -> ZaiAuthResult? {
        var req = URLRequest(url: flow.pollURL)
        req.httpMethod = "GET"
        req.setValue("Bearer \(flow.pollToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["code"] as? Int) == 0,
              let payload = json["data"] as? [String: Any],
              let status = payload["status"] as? String else {
            return nil
        }

        if status == "pending" {
            return nil
        }
        if status == "failed" {
            throw ZaiAuthError.oauthFailed("Z.AI authorization failed. Please try signing in again.")
        }
        guard status == "ready",
              let zcodeToken = (payload["token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !zcodeToken.isEmpty else {
            return nil
        }

        let zaiDict = payload["zai"] as? [String: Any]
        let bmDict = payload["bigmodel"] as? [String: Any]
        let providerToken = (zaiDict?["access_token"] as? String)
            ?? (bmDict?["access_token"] as? String)
            ?? (bmDict?["accessToken"] as? String)
            ?? zcodeToken

        let userDict = payload["user"] as? [String: Any]
        let userId = (userDict?["user_id"] as? String) ?? Self.extractJWTClaim(zcodeToken, keys: ["sub", "user_id"]) ?? "zai-user"
        let email = (userDict?["email"] as? String) ?? Self.extractJWTClaim(zcodeToken, keys: ["email"])
        let name = (userDict?["name"] as? String) ?? email ?? "Z.AI User"
        let avatar = userDict?["avatar"] as? String

        let account = ZaiUserAccount(
            userId: userId,
            displayName: name,
            email: email,
            avatarURL: avatar,
            region: region,
            signedInAt: Date()
        )
        return ZaiAuthResult(account: account, zcodeJwtToken: zcodeToken, providerAccessToken: providerToken)
    }

    private func runDirectSystemOAuthCodeFlow(region: ZaiAuthRegion) async throws -> ZaiAuthResult {
        let state = Self.generateSecureHex(byteCount: 16)
        var comps = URLComponents(string: "https://chat.z.ai/api/oauth/authorize")!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: Self.zaiClientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.nativeRedirectURI),
            URLQueryItem(name: "state", value: state)
        ]
        guard let authURL = comps.url else {
            throw ZaiAuthError.oauthFailed("Could not construct Z.AI authorize URL.")
        }

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "zcode"
            ) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let authErr = error as? ASWebAuthenticationSessionError,
                          authErr.code == .canceledLogin {
                    continuation.resume(throwing: ZaiAuthError.cancelled)
                } else {
                    continuation.resume(throwing: ZaiAuthError.oauthFailed(error?.localizedDescription ?? "Authorization failed."))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.activeWebAuthSession = session
            _ = session.start()
        }

        self.activeWebAuthSession = nil
        return try await exchangeCallbackURL(
            callbackURL,
            expectedState: state,
            redirectURI: Self.nativeRedirectURI,
            region: region
        )
    }

    public func exchangeCallbackURL(
        _ callbackURL: URL,
        expectedState: String?,
        redirectURI: String,
        region: ZaiAuthRegion
    ) async throws -> ZaiAuthResult {
        guard let comps = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw ZaiAuthError.oauthFailed("Invalid OAuth callback URL.")
        }
        let items = comps.queryItems ?? []
        let code = items.first(where: { $0.name == "code" || $0.name == "authCode" })?.value ?? ""
        let state = items.first(where: { $0.name == "state" })?.value ?? ""
        if let err = items.first(where: { $0.name == "error" })?.value, !err.isEmpty {
            throw ZaiAuthError.oauthFailed("Z.AI OAuth error: \(err)")
        }
        guard !code.isEmpty else {
            throw ZaiAuthError.oauthFailed("OAuth callback did not contain an authorization code.")
        }
        if let expectedState, !expectedState.isEmpty, state != expectedState {
            throw ZaiAuthError.oauthFailed("OAuth state verification mismatch.")
        }

        guard let tokenURL = URL(string: "\(region.zcodeOrigin)/api/v1/oauth/token") else {
            throw ZaiAuthError.oauthFailed("Invalid ZCode token endpoint.")
        }
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "provider": region.rawValue,
            "code": code,
            "redirect_uri": redirectURI,
            "state": state
        ])

        let (data, response) = try await urlSession.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["code"] as? Int) == 0,
              let payload = json["data"] as? [String: Any],
              let zcodeToken = (payload["token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !zcodeToken.isEmpty else {
            throw ZaiAuthError.oauthFailed("Token exchange with ZCode server failed.")
        }

        let zaiDict = payload["zai"] as? [String: Any]
        let providerToken = (zaiDict?["access_token"] as? String) ?? zcodeToken
        let userDict = payload["user"] as? [String: Any]
        let userId = (userDict?["user_id"] as? String) ?? Self.extractJWTClaim(zcodeToken, keys: ["sub", "user_id"]) ?? "zai-user"
        let email = (userDict?["email"] as? String) ?? Self.extractJWTClaim(zcodeToken, keys: ["email"])
        let name = (userDict?["name"] as? String) ?? email ?? "Z.AI User"

        let account = ZaiUserAccount(
            userId: userId,
            displayName: name,
            email: email,
            avatarURL: userDict?["avatar"] as? String,
            region: region,
            signedInAt: Date()
        )
        return ZaiAuthResult(account: account, zcodeJwtToken: zcodeToken, providerAccessToken: providerToken)
    }

    // MARK: - 2. Direct Access Token Sign-In & Verification

    public func verifyAndSignInWithToken(
        _ rawToken: String,
        region: ZaiAuthRegion = .global,
        displayNameHint: String? = nil
    ) async throws -> ZaiAuthResult {
        var cleaned = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.lowercased().hasPrefix("bearer ") {
            cleaned = String(cleaned.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard cleaned.count >= 12 else {
            throw ZaiAuthError.invalidToken("Please paste a valid Z.AI / ZCode access token.")
        }

        // Probe Z.AI userinfo or /api/v1/remote/device to validate if online
        var resolvedName = displayNameHint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var resolvedEmail = Self.extractJWTClaim(cleaned, keys: ["email"])
        var resolvedUserId = Self.extractJWTClaim(cleaned, keys: ["sub", "user_id", "uid"]) ?? "zai-\(cleaned.prefix(8))"

        if let userInfoURL = URL(string: region.oauthUserInfoURL) {
            var req = URLRequest(url: userInfoURL)
            req.timeoutInterval = 8
            req.setValue("Bearer \(cleaned)", forHTTPHeaderField: "Authorization")
            if let (data, resp) = try? await urlSession.data(for: req),
               let http = resp as? HTTPURLResponse,
               (200..<300).contains(http.statusCode),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let inner = (json["data"] as? [String: Any]) ?? json
                if let uid = (inner["id"] as? String) ?? (inner["user_id"] as? String) {
                    resolvedUserId = uid
                }
                if let em = inner["email"] as? String, !em.isEmpty {
                    resolvedEmail = em
                }
                if resolvedName.isEmpty,
                   let nm = (inner["name"] as? String) ?? (inner["username"] as? String) ?? (inner["nickname"] as? String),
                   !nm.isEmpty {
                    resolvedName = nm
                }
            }
        }

        if resolvedName.isEmpty {
            resolvedName = Self.extractJWTClaim(cleaned, keys: ["name", "username", "preferred_username"])
                ?? resolvedEmail
                ?? "Z.AI Account"
        }

        let account = ZaiUserAccount(
            userId: resolvedUserId,
            displayName: resolvedName,
            email: resolvedEmail,
            avatarURL: nil,
            region: region,
            signedInAt: Date()
        )
        return ZaiAuthResult(account: account, zcodeJwtToken: cleaned, providerAccessToken: cleaned)
    }

    // MARK: - 3. ZCode Remote Relay Token & Registered Devices API

    public func fetchRelayTerminalToken(zcodeJwt: String, origin: String = "https://zcode.z.ai") async throws -> String {
        guard let url = URL(string: "\(origin)/api/v1/remote/token") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 10
        req.setValue("Bearer \(zcodeJwt)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["role": "terminal"])

        let (data, response) = try await urlSession.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 401 {
            throw ZaiAuthError.invalidToken("Z.AI session expired. Please sign in again.")
        }
        guard (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["code"] as? Int) == 0,
              let payload = json["data"] as? [String: Any],
              let token = payload["token"] as? String,
              !token.isEmpty else {
            throw ZaiAuthError.networkError("Unable to acquire ZCode Remote Relay token.")
        }
        return token
    }

    public func fetchRegisteredDevices(zcodeJwt: String, origin: String = "https://zcode.z.ai") async throws -> [ZaiRegisteredRemoteDevice] {
        guard let url = URL(string: "\(origin)/api/v1/remote/device") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 10
        req.setValue("Bearer \(zcodeJwt)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["code"] as? Int) == 0,
              let items = json["data"] as? [[String: Any]] else {
            return []
        }

        return items.compactMap { item in
            guard let sid = item["device_sid"] as? String,
                  let mid = item["device_mid"] as? String else { return nil }
            let online = (item["online"] as? Bool) ?? false
            let ts = (item["created_at"] as? Double) ?? Date().timeIntervalSince1970
            let meta = item["meta"] as? [String: Any]
            let name = (meta?["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let platform = (meta?["platform"] as? String) ?? "desktop"
            let version = (meta?["version"] as? String) ?? "3.16.3"
            return ZaiRegisteredRemoteDevice(
                deviceSid: sid,
                deviceMid: mid,
                online: online,
                createdAt: Date(timeIntervalSince1970: ts > 9_999_999_999 ? ts / 1000.0 : ts),
                deviceName: (name?.isEmpty == false) ? name! : "Device \(mid.prefix(8))",
                platform: platform,
                version: version
            )
        }
    }

    // MARK: - 4. Exact ZCode Remote V4 `auth_challenge` HMAC-SHA256 Proof (`H2t` 1:1)

    nonisolated public static func calculateChallengeProof(
        passHash: String,
        nonce: String,
        role: String = "terminal",
        deviceSid: String
    ) -> String {
        let key = SymmetricKey(data: Data(passHash.utf8))
        let message = Data("\(nonce)|\(role)|\(deviceSid)".utf8)
        let signature = HMAC<SHA256>.authenticationCode(for: message, using: key)
        return Data(signature)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Helpers

    nonisolated private static func generateSecureHex(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func extractJWTClaim(_ token: String, keys: [String]) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var b64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let rem = b64.count % 4
        if rem > 0 {
            b64 += String(repeating: "=", count: 4 - rem)
        }
        guard let data = Data(base64Encoded: b64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        for key in keys {
            if let val = json[key] as? String, !val.isEmpty {
                return val
            }
        }
        return nil
    }
}
