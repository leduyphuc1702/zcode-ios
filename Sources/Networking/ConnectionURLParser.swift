import Foundation

public struct ParsedConnectionDescriptor: Equatable {
    public let transport: ConnectionTransportKind
    public let name: String
    public let normalizedURL: String
    public let host: String
    public let port: Int
    public let mid: String
    public let sid: String
    public let passHash: String
    public let remoteControlToken: String
    public let token: String?

    public init(
        transport: ConnectionTransportKind,
        name: String,
        normalizedURL: String,
        host: String,
        port: Int,
        mid: String,
        sid: String,
        passHash: String = "",
        remoteControlToken: String = "",
        token: String? = nil
    ) {
        self.transport = transport
        self.name = name
        self.normalizedURL = normalizedURL
        self.host = host
        self.port = port
        self.mid = mid
        self.sid = sid
        self.passHash = passHash
        self.remoteControlToken = remoteControlToken
        self.token = token
    }
}

/// Parses Z.AI / ZCode Remote Control URLs (`https://zcode.z.ai/remote/v4?sid=...&mid=...#...`),
/// bare domain inputs (`zcode.z.ai/remote/v4?...`), `remoteControlToken` window URLs,
/// `zcode://` deep links, and Direct ZCode Server `http(s)://` / `ws(s)://` endpoints.
public enum ConnectionURLParser {

    public static func isLikelyZCodeURL(_ rawText: String?) -> Bool {
        guard let rawText else { return false }
        let lower = rawText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return false }
        return lower.contains("zcode.z.ai") ||
            lower.contains("/remote/v") ||
            (lower.contains("sid=") && lower.contains("mid=")) ||
            lower.contains("remotecontroltoken=") ||
            lower.hasPrefix("zcode://") ||
            lower.hasPrefix("ws://") ||
            lower.hasPrefix("wss://")
    }

    public static func extractFirstURL(from rawText: String) -> String? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let pattern = #"(?:https?|wss?|zcode)://[^\s\n\r"'<>()]+"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let range = Range(match.range, in: trimmed) {
            return String(trimmed[range])
        }

        // Bare domain without scheme (matching my-dlq/zcode-mobile-app UrlParser.kt)
        if !trimmed.contains("://"),
           !trimmed.contains(" "),
           (trimmed.contains(".") || trimmed.hasPrefix("localhost")) {
            if trimmed.lowercased().contains("zcode") || trimmed.lowercased().contains("z.ai") || trimmed.lowercased().contains("/remote") {
                return "https://\(trimmed)"
            } else {
                return "http://\(trimmed)"
            }
        }
        return trimmed
    }

    public static func parse(_ rawInput: String) -> ParsedConnectionDescriptor? {
        guard let extracted = extractFirstURL(from: rawInput),
              let components = URLComponents(string: extracted) else {
            return nil
        }

        let scheme = (components.scheme ?? "").lowercased()
        let host = (components.host ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return nil }

        let path = components.path
        let queryItems = components.queryItems ?? []

        func query(_ key: String) -> String? {
            queryItems.first(where: { $0.name.caseInsensitiveCompare(key) == .orderedSame })?.value
        }

        let fragment = (components.fragment ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var fragmentItems: [URLQueryItem] = []
        if fragment.contains("=") {
            var fragComp = URLComponents()
            fragComp.query = fragment
            fragmentItems = fragComp.queryItems ?? []
        }

        func fragQuery(_ key: String) -> String? {
            fragmentItems.first(where: { $0.name.caseInsensitiveCompare(key) == .orderedSame })?.value
        }

        let mid = (query("mid") ?? fragQuery("mid") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let sid = (query("sid") ?? fragQuery("sid") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let customName = (query("name") ?? fragQuery("name") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let token = (query("token") ?? fragQuery("token"))?.trimmingCharacters(in: .whitespacesAndNewlines)
        let remoteControlToken = (query("remoteControlToken") ?? fragQuery("remoteControlToken") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let rawHashParam = (query("hash") ?? query("passHash") ?? query("p") ?? fragQuery("hash") ?? fragQuery("passHash") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPassHash: String
        if !rawHashParam.isEmpty {
            resolvedPassHash = rawHashParam
        } else if !fragment.isEmpty && !fragment.contains("=") {
            resolvedPassHash = fragment
        } else {
            resolvedPassHash = ""
        }

        let isZaiHost = host.lowercased().contains("zcode") || host.lowercased().contains("z.ai") || path.lowercased().contains("/remote")

        // Case 1: Z.AI Remote Control V3/V4 URL (`https://zcode.z.ai/remote/v4?sid=...&mid=...#...`)
        if !sid.isEmpty && (!mid.isEmpty || isZaiHost) {
            let resolvedName: String
            if !customName.isEmpty {
                resolvedName = customName
            } else if !mid.isEmpty {
                resolvedName = "Device \(mid.prefix(8))"
            } else {
                resolvedName = "ZCode (\(sid.prefix(6)))"
            }
            return ParsedConnectionDescriptor(
                transport: .cloudRelayV2,
                name: resolvedName,
                normalizedURL: extracted,
                host: host,
                port: components.port ?? 443,
                mid: mid,
                sid: sid,
                passHash: resolvedPassHash,
                remoteControlToken: remoteControlToken,
                token: token
            )
        }

        // Case 2: ZCode Window Remote Control Token URL (`https://zcode.z.ai/remote/v4?remoteControlToken=...`)
        if !remoteControlToken.isEmpty {
            let resolvedName = customName.isEmpty ? "ZCode Remote (\(remoteControlToken.prefix(6)))" : customName
            return ParsedConnectionDescriptor(
                transport: .cloudRelayV2,
                name: resolvedName,
                normalizedURL: extracted,
                host: host,
                port: components.port ?? 443,
                mid: mid,
                sid: sid.isEmpty ? remoteControlToken : sid,
                passHash: resolvedPassHash,
                remoteControlToken: remoteControlToken,
                token: token ?? remoteControlToken
            )
        }

        // Reject bare `https://zcode.z.ai/remote/v4` with no `sid` and no `remoteControlToken`
        if isZaiHost && path.lowercased().contains("/remote") && sid.isEmpty && remoteControlToken.isEmpty {
            return nil
        }

        // Case 3: Direct ZCode Server WebSocket or HTTP endpoint (`http://192.168.1.16:57743` or `ws://...`)
        if ["http", "https", "ws", "wss", "zcode"].contains(scheme) {
            let defaultPort = (scheme == "https" || scheme == "wss") ? 443 : 57743
            let port = components.port ?? defaultPort
            let wsScheme = (scheme == "https" || scheme == "wss") ? "wss" : "ws"
            let cleanPath = (path.isEmpty || path == "/") ? "/ws" : path
            let normalized = "\(wsScheme)://\(host):\(port)\(cleanPath)"
            let resolvedName = customName.isEmpty ? "\(host):\(port)" : customName
            return ParsedConnectionDescriptor(
                transport: .directServer,
                name: resolvedName,
                normalizedURL: normalized,
                host: host,
                port: port,
                mid: "",
                sid: "",
                passHash: "",
                remoteControlToken: "",
                token: token
            )
        }

        return nil
    }
}
