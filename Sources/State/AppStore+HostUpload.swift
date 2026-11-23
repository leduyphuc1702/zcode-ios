import Foundation
import CryptoKit

/// Collects PTY output delivered on the RPC client's event queue.
private final class HostUploadOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""

    func append(_ chunk: String) {
        lock.lock()
        text += chunk
        if text.count > 64_000 { text = String(text.suffix(32_000)) }
        lock.unlock()
    }

    /// The remainder of the first line that starts with `marker`, once that line is complete.
    func line(after marker: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let start = text.range(of: marker) else { return nil }
        let rest = text[start.upperBound...]
        guard let end = rest.firstIndex(where: \.isNewline) else { return nil }
        return String(rest[..<end])
    }
}

extension AppStore {
    private static let hostUploadWriteBytes = 256 * 1024
    nonisolated private static let hostUploadTextLimit = 65_536

    /// The host turns uploaded non-media files into UTF-8 text and keeps only metadata above 64 KB,
    /// so binary or large files are copied to the Mac and sent by path instead.
    nonisolated static func needsHostFileCopy(kind: String, data: Data) -> Bool {
        guard kind == "file" else { return false }
        return data.count > hostUploadTextLimit || String(data: data, encoding: .utf8) == nil
    }

    nonisolated static func hostUploadFileName(_ name: String) -> String {
        var cleaned = name.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        return cleaned.isEmpty ? "attachment" : cleaned
    }

    /// Shell line that writes `byteCount` base64 characters read from the PTY into the upload folder,
    /// checks the SHA-256 and prints `__ZCM_DONE<path>` or `__ZCM_FAIL`. Markers are split in the
    /// source so the echoed command line never matches them.
    nonisolated static func hostUploadCommand(fileName: String, base64Length: Int, sha256: String) -> String {
        let nameB64 = Data(hostUploadFileName(fileName).utf8).base64EncodedString()
        let script = [
            "stty raw -echo",
            "if base64 -D </dev/null >/dev/null 2>&1; then b=-D; else b=-d; fi",
            "d=\"$HOME/Downloads/ZCode Uploads\"",
            "mkdir -p \"$d\" || { stty sane; printf \"%s%s\\n\" __ZCM_ FAIL; exit 1; }",
            "n=$(printf %s \(nameB64) | base64 $b)",
            "f=\"$d/$n\"",
            "[ -e \"$f\" ] && f=\"$d/$(date +%Y%m%d-%H%M%S)-$n\"",
            "printf \"%s%s\\r\\n\" __ZCM_ READY",
            "head -c \(base64Length) | base64 $b > \"$f.zcmpart\"",
            "stty sane",
            "h=$(shasum -a 256 \"$f.zcmpart\" 2>/dev/null || sha256sum \"$f.zcmpart\")",
            "if [ \"${h%% *}\" = \(sha256) ]; then mv -f \"$f.zcmpart\" \"$f\" && printf \"%s%s%s\\n\" __ZCM_ DONE \"$f\"; else rm -f \"$f.zcmpart\"; printf \"%s%s\\n\" __ZCM_ FAIL; fi",
        ].joined(separator: "; ")
        return "exec /bin/sh -c '\(script)'\r"
    }

    /// Copies `data` into `~/Downloads/ZCode Uploads/` on the host through a terminal session and
    /// returns the absolute path. The host has no file-write RPC; this is the same PTY the terminal tab uses.
    func copyFileToHost(name: String, data: Data) async throws -> String {
        let created = try await rpcClient.call(
            channel: "terminal",
            method: "create",
            args: [.fromJSONObject(["cols": 200, "rows": 24])],
            timeoutSec: 10
        )
        guard let ptyId = created.decodeJSONDictionary()?["id"] as? String, !ptyId.isEmpty else {
            throw V4CommandError(status: "failed", reasonCode: nil, message: "The Mac didn't open a terminal for the upload.")
        }
        let output = HostUploadOutput()
        var subId: Int32?
        do {
            subId = try await rpcClient.listen(channel: "terminal", event: "onDynamicData", arg: .string(ptyId)) { value in
                if case .string(let raw) = value { output.append(raw) }
            }
            let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let base64 = data.base64EncodedString()
            try await terminalWrite(ptyId, Self.hostUploadCommand(fileName: name, base64Length: base64.utf8.count, sha256: sha))
            guard await waitForMarker(output, "__ZCM_READY", timeout: 25) != nil else {
                throw V4CommandError(status: "failed", reasonCode: nil, message: "The Mac's shell didn't start the upload.")
            }
            let utf8 = Array(base64.utf8)
            var offset = 0
            while offset < utf8.count {
                let end = min(utf8.count, offset + Self.hostUploadWriteBytes)
                try await terminalWrite(ptyId, String(decoding: utf8[offset..<end], as: UTF8.self))
                offset = end
            }
            let path = await waitForMarker(output, "__ZCM_DONE", timeout: 30 + Double(data.count) / 200_000)
            guard let path, path.hasPrefix("/") else {
                throw V4CommandError(status: "failed", reasonCode: nil, message: "\(name) didn't arrive intact on the Mac.")
            }
            await closeHostUploadTerminal(ptyId, subId: subId)
            return path
        } catch {
            await closeHostUploadTerminal(ptyId, subId: subId)
            throw error
        }
    }

    private func terminalWrite(_ ptyId: String, _ data: String) async throws {
        _ = try await rpcClient.call(
            channel: "terminal",
            method: "write",
            args: [.fromJSONObject(["id": ptyId, "data": data])],
            timeoutSec: 30
        )
    }

    /// Resolves with the text after `marker`, or nil on timeout or when the upload reported failure.
    private func waitForMarker(_ output: HostUploadOutput, _ marker: String, timeout: Double) async -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let line = output.line(after: marker) { return line }
            if output.line(after: "__ZCM_FAIL") != nil { return nil }
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
        return nil
    }

    private func closeHostUploadTerminal(_ ptyId: String, subId: Int32?) async {
        if let subId { await rpcClient.unlisten(subId) }
        _ = try? await rpcClient.call(
            channel: "terminal",
            method: "dispose",
            args: [.fromJSONObject(["id": ptyId])],
            timeoutSec: 3
        )
    }
}
