import Foundation

/// Resolves a markdown link target in an assistant message to a host file, following the desktop
/// transcript (`qz`/`Kz`): absolute system paths, `~/`, `./x` and slash-containing relative paths
/// resolve against the workspace; `path:12`, `path:12:3` and `path#L12` carry a line number.
/// Bare names (`README.md`), `../x` and URLs with a scheme are not file links.
enum ChatFileLink {
    struct Target: Equatable {
        let path: String
        let line: Int?
    }

    private static let systemRoots: Set<String> = [
        "Applications", "Library", "System", "Users", "Volumes", "bin", "boot", "dev", "etc", "home", "lib", "lib64",
        "media", "mnt", "opt", "private", "proc", "root", "run", "sbin", "srv", "sys", "tmp", "usr", "var",
    ]
    private static let wrappers: [Character: Character] = ["\"": "\"", "'": "'", "`": "`", "“": "”", "‘": "’"]

    static func resolve(_ href: String, workspacePath: String?, homePath: String?) -> Target? {
        let workspace = workspacePath.flatMap { $0.isEmpty ? nil : $0 }
        let (rawPath, line) = splitLine(unwrap(href).replacingOccurrences(of: "\\", with: "/"))
        let path = decode(rawPath)
        guard !path.isEmpty else { return nil }

        if path.range(of: "^~[^/]+/", options: .regularExpression) != nil { return nil }
        let homeRelative = path.hasPrefix("./~/") ? String(path.dropFirst(2)) : (path.hasPrefix("~/") ? path : nil)
        if let homeRelative {
            guard let home = homePath, home.hasPrefix("/") else { return nil }
            return Target(path: join(home, String(homeRelative.dropFirst(2))), line: line)
        }
        if path.range(of: "^/[A-Za-z]:/", options: .regularExpression) != nil { return nil }

        if path.hasPrefix("./") || isWorkspaceRelative(path) {
            guard let workspace else { return nil }
            let relative = path.hasPrefix("./") ? String(path.dropFirst(2)) : path
            guard !relative.isEmpty, let normalized = normalize(relative) else { return nil }
            return Target(path: join(workspace, normalized), line: line)
        }
        if let workspace, path.hasPrefix("/"), !isSystemAbsolute(path) {
            if isInside(path, workspace) { return Target(path: path, line: line) }
            guard let normalized = normalize(String(path.dropFirst())) else { return nil }
            return Target(path: join(workspace, normalized), line: line)
        }
        return path.hasPrefix("/") ? Target(path: path, line: line) : nil
    }

    /// The host user's home, taken from a `/Users/<name>` or `/home/<name>` workspace path.
    static func homePath(forWorkspace workspace: String?) -> String? {
        guard let workspace else { return nil }
        let parts = workspace.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 2, parts[0] == "Users" || parts[0] == "home" else { return nil }
        return "/\(parts[0])/\(parts[1])"
    }

    private static func unwrap(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("file://"), let url = URL(string: text), url.isFileURL {
            text = url.path
        }
        let prefix = text.hasPrefix("./") ? "./" : ""
        let body = text.dropFirst(prefix.count)
        if body.count >= 2, let first = body.first, let close = wrappers[first], body.last == close {
            return prefix + body.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
        }
        return text
    }

    private static func splitLine(_ text: String) -> (String, Int?) {
        if let match = text.range(of: "#L(\\d+)(-L?\\d+)?$", options: [.regularExpression, .caseInsensitive]) {
            let digits = text[match].dropFirst(2).prefix { $0.isNumber }
            return (String(text[..<match.lowerBound]), Int(digits))
        }
        if let match = text.range(of: ":(\\d+):(\\d+)$", options: .regularExpression) {
            let digits = text[match].dropFirst().prefix { $0.isNumber }
            return (String(text[..<match.lowerBound]), Int(digits))
        }
        if let match = text.range(of: ":(\\d+)$", options: .regularExpression) {
            return (String(text[..<match.lowerBound]), Int(text[match].dropFirst()))
        }
        return (text, nil)
    }

    private static func decode(_ path: String) -> String {
        path.contains("%") ? (path.removingPercentEncoding ?? path) : path
    }

    private static func isWorkspaceRelative(_ path: String) -> Bool {
        if path.hasPrefix("/") || path.hasPrefix("#") || path.hasPrefix("../") { return false }
        if path.range(of: "^[A-Za-z][A-Za-z0-9+.-]*:", options: .regularExpression) != nil { return false }
        return path.contains("/")
    }

    private static func isSystemAbsolute(_ path: String) -> Bool {
        guard path.hasPrefix("/"), !path.hasPrefix("//") else { return false }
        let first = path.dropFirst().split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        return systemRoots.contains(first)
    }

    private static func isInside(_ path: String, _ root: String) -> Bool {
        let p = path.hasSuffix("/") ? String(path.dropLast()) : path
        let r = root.hasSuffix("/") ? String(root.dropLast()) : root
        return p == r || p.hasPrefix(r + "/")
    }

    private static func normalize(_ relative: String) -> String? {
        var parts: [Substring] = []
        for part in relative.split(separator: "/") where part != "." {
            if part == ".." {
                guard !parts.isEmpty else { return nil }
                parts.removeLast()
            } else {
                parts.append(part)
            }
        }
        return parts.joined(separator: "/")
    }

    private static func join(_ base: String, _ relative: String) -> String {
        var trimmedBase = base
        while trimmedBase.hasSuffix("/") { trimmedBase.removeLast() }
        return relative.isEmpty ? trimmedBase : "\(trimmedBase)/\(relative)"
    }
}
