// Copyright (c) serrebidev and contributors
// This file is part of BlindRSS
// SPDX-License-Identifier: MIT

import Foundation
import Security

/// YouTube account sign-in (0.1.14), from the SmartTube source audit
/// recorded in AUDIT.md section D. SmartTube (MIT) authenticates with
/// the OAuth 2.0 device-code flow of YouTube's own TV app: no Google
/// Cloud project and no per-app credential. The TV client id and
/// secret are not constants in SmartTube's source; they are extracted
/// at runtime from the YouTube TV web app's base JavaScript, and this
/// implementation does the same, so Google rotating them does not
/// break sign-in. Written fresh in Swift from the audited flow; no
/// SmartTube code is copied.
///
/// Only the refresh token is stored (Keychain). Access tokens are
/// minted from it on demand, exactly as SmartTube's sign-in service
/// builds its "Bearer" authorization header.
enum YouTubeTVAuth {
    // MARK: TV client identity (MediaServiceCore AppClient/Constants)

    static let clientName = "TVHTML5"
    static let clientVersion = "7.20260901.15.00"
    static let userAgent = "Mozilla/5.0 (ChromiumStylePlatform) Cobalt/25.lts.30.1034943-gold (unlike Gecko), Unknown_TV_Unknown_0/Unknown (Unknown, Unknown)"
    static let referer = "https://www.youtube.com/tv"
    /// The TV Innertube API key (AppConstants.API_KEY in the audit):
    /// a public client key of the same class as the WEB key the
    /// transcript fetch already uses.
    static let apiKey = "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8"
    static let scope = "http://gdata.youtube.com https://www.googleapis.com/auth/youtube-paid-content"

    static let deviceCodeURL = URL(string: "https://www.youtube.com/o/oauth2/device/code")!
    static let tokenURL = URL(string: "https://www.youtube.com/o/oauth2/token")!
    static let tvPageURL = URL(string: "https://www.youtube.com/tv")!

    // MARK: Client credential extraction (pure, unit-tested)

    /// The TV page's base script URL: AppInfo.java's
    /// id="base-js" src="..." pattern (modern clients).
    static func baseJSURL(fromTVPageHTML html: String) -> URL? {
        guard let start = html.range(of: "id=\"base-js\" src=\"") else { return nil }
        let rest = html[start.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        let path = String(rest[..<end])
        if path.hasPrefix("http") { return URL(string: path) }
        return URL(string: "https://www.youtube.com" + path)
    }

    /// Extracts the TV client id and secret from the base script with
    /// ClientData.java's patterns. The FIRST match is the Android TV
    /// device pair; later occurrences answer HTTP 401.
    static func clientCredentials(fromBaseJS js: String) -> (id: String, secret: String)? {
        let idPattern = #"clientId:"([-\w]+\.apps\.googleusercontent\.com)",\n?[$\w]+:"\w+""#
        let secretPattern = #"clientId:"[-\w]+\.apps\.googleusercontent\.com",\n?[$\w]+:"(\w+)""#
        guard let id = firstCapture(idPattern, in: js),
              let secret = firstCapture(secretPattern, in: js) else { return nil }
        return (id, secret)
    }

    private static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let swiftRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[swiftRange])
    }

    // MARK: Device flow payloads (pure, unit-tested)

    struct UserCode: Equatable, Sendable {
        var deviceCode: String
        var userCode: String
        var verificationURL: String
        var expiresIn: Int
        var interval: Int
    }

    static func parseUserCode(_ data: Data) -> UserCode? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let deviceCode = root["device_code"] as? String,
              let userCode = root["user_code"] as? String else { return nil }
        return UserCode(deviceCode: deviceCode,
                        userCode: userCode,
                        verificationURL: root["verification_url"] as? String ?? "https://www.google.com/device",
                        expiresIn: (root["expires_in"] as? NSNumber)?.intValue ?? 1800,
                        interval: max(3, (root["interval"] as? NSNumber)?.intValue ?? 5))
    }

    enum TokenOutcome: Equatable, Sendable {
        case success(accessToken: String, refreshToken: String?, expiresIn: Int)
        case pending
        case failed(String)
    }

    /// Token endpoint responses: success carries access_token (and, on
    /// the device exchange, refresh_token); while the user has not
    /// confirmed yet the endpoint answers an error payload —
    /// authorization_pending or slow_down — which means keep polling.
    static func parseToken(_ data: Data) -> TokenOutcome {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .failed("Unreadable response from YouTube.")
        }
        if let access = root["access_token"] as? String, !access.isEmpty {
            return .success(accessToken: access,
                            refreshToken: root["refresh_token"] as? String,
                            expiresIn: (root["expires_in"] as? NSNumber)?.intValue ?? 3600)
        }
        let error = root["error"] as? String ?? "unknown_error"
        if error == "authorization_pending" || error == "slow_down" { return .pending }
        return .failed(error)
    }

    /// This installation's device id for the device-code request:
    /// generated once and kept, like MediaServiceData's device id.
    static var deviceID: String {
        if let existing = UserDefaults.standard.string(forKey: "youtube.deviceID") { return existing }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: "youtube.deviceID")
        return fresh
    }

    // MARK: Network

    private static func postJSON(url: URL, body: [String: Any]) async -> Data? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return data
    }

    /// Fetches (and caches) the current TV client credentials: TV
    /// page, base script, extraction — the AppServiceCore chain.
    static func fetchClientCredentials() async -> (id: String, secret: String)? {
        let defaults = UserDefaults.standard
        var request = URLRequest(url: tvPageURL)
        request.timeoutInterval = 30
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let (pageData, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: pageData, encoding: .utf8),
              let jsURL = baseJSURL(fromTVPageHTML: html) else { return nil }
        // Cache is keyed by the script URL, as in ClientDataCached.
        if defaults.string(forKey: "youtube.clientJSURL") == jsURL.absoluteString,
           let id = defaults.string(forKey: "youtube.clientID"),
           let secret = defaults.string(forKey: "youtube.clientSecret") {
            return (id, secret)
        }
        guard let (jsData, _) = try? await URLSession.shared.data(from: jsURL),
              let js = String(data: jsData, encoding: .utf8),
              let credentials = clientCredentials(fromBaseJS: js) else { return nil }
        defaults.set(jsURL.absoluteString, forKey: "youtube.clientJSURL")
        defaults.set(credentials.id, forKey: "youtube.clientID")
        defaults.set(credentials.secret, forKey: "youtube.clientSecret")
        return credentials
    }

    static func requestUserCode() async -> UserCode? {
        guard let credentials = await fetchClientCredentials(),
              let data = await postJSON(url: deviceCodeURL, body: [
                "client_id": credentials.id,
                "device_id": deviceID,
                "model_name": "ytlr::",
                "scope": scope,
              ]) else { return nil }
        return parseUserCode(data)
    }

    static func exchangeDeviceCode(_ deviceCode: String) async -> TokenOutcome {
        guard let credentials = await fetchClientCredentials(),
              let data = await postJSON(url: tokenURL, body: [
                "device_code": deviceCode,
                "client_id": credentials.id,
                "client_secret": credentials.secret,
                "grant_type": "http://oauth.net/grant_type/device/1.0",
              ]) else { return .failed("network") }
        return parseToken(data)
    }

    static func refreshAccessToken(refreshToken: String) async -> TokenOutcome {
        guard let credentials = await fetchClientCredentials(),
              let data = await postJSON(url: tokenURL, body: [
                "refresh_token": refreshToken,
                "client_id": credentials.id,
                "client_secret": credentials.secret,
                "grant_type": "refresh_token",
              ]) else { return .failed("network") }
        return parseToken(data)
    }

    /// Authenticated TV browse: Subscriptions ("FEsubscriptions") and
    /// Home/Recommendations ("default"), the BrowseApiHelper ids.
    static func browse(browseID: String, accessToken: String) async -> Data? {
        guard let url = URL(string: "https://www.youtube.com/youtubei/v1/browse?key=\(apiKey)&prettyPrint=false") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "context": ["client": ["clientName": clientName, "clientVersion": clientVersion,
                                   "clientScreen": "WATCH", "userAgent": userAgent, "hl": "en"]],
            "browseId": browseID,
        ])
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}

// MARK: - Refresh token storage (Keychain)

enum YouTubeTokenStore {
    private static let service = "org.serrebidev.BlindRSS.youtube"
    private static let account = "refreshToken"

    static var refreshToken: String? {
        get {
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                         kSecAttrService as String: service,
                                         kSecAttrAccount as String: account,
                                         kSecReturnData as String: true]
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                         kSecAttrService as String: service,
                                         kSecAttrAccount as String: account]
            SecItemDelete(query as CFDictionary)
            guard let value = newValue, let data = value.data(using: .utf8) else { return }
            var attributes = query
            attributes[kSecValueData as String] = data
            SecItemAdd(attributes as CFDictionary, nil)
        }
    }
}

// MARK: - Account state and feeds

@MainActor
@Observable
final class YouTubeAccount {
    static let shared = YouTubeAccount()

    private(set) var isSignedIn = YouTubeTokenStore.refreshToken != nil
    private var accessToken: String?
    private var accessTokenExpiry = Date.distantPast

    private init() {}

    /// A valid access token, refreshed from the stored refresh token
    /// when the cached one is missing or near expiry — the
    /// YouTubeSignInService refresh-token -> Bearer header flow.
    func validAccessToken() async -> String? {
        if let accessToken, accessTokenExpiry > Date().addingTimeInterval(60) { return accessToken }
        guard let refresh = YouTubeTokenStore.refreshToken else { return nil }
        switch await YouTubeTVAuth.refreshAccessToken(refreshToken: refresh) {
        case .success(let token, _, let expiresIn):
            accessToken = token
            accessTokenExpiry = Date().addingTimeInterval(TimeInterval(expiresIn))
            return token
        case .pending, .failed:
            return nil
        }
    }

    /// Stores a completed sign-in's refresh token.
    func completeSignIn(refreshToken: String) {
        YouTubeTokenStore.refreshToken = refreshToken
        accessToken = nil
        accessTokenExpiry = .distantPast
        isSignedIn = true
    }

    func signOut() {
        YouTubeTokenStore.refreshToken = nil
        accessToken = nil
        accessTokenExpiry = .distantPast
        isSignedIn = false
        Announcer.announce("Signed out of YouTube.")
    }

    /// The signed-in Subscriptions feed (latest uploads across the
    /// account's subscriptions), as video results.
    func subscriptions() async -> [YouTubeService.VideoResult] {
        guard let token = await validAccessToken(),
              let data = await YouTubeTVAuth.browse(browseID: "FEsubscriptions", accessToken: token) else { return [] }
        return YouTubeService.parseSearchResults(data)
    }

    /// The signed-in Home feed: YouTube's recommendations for the
    /// account (TV browse id "default").
    func recommendations() async -> [YouTubeService.VideoResult] {
        guard let token = await validAccessToken(),
              let data = await YouTubeTVAuth.browse(browseID: "default", accessToken: token) else { return [] }
        return YouTubeService.parseSearchResults(data)
    }
}
