import CryptoKit
import Foundation

/// On-device copies of host data that only the host can change: conversation snapshots (re-validated on every
/// subscribe through `base`) and user-row attachment bytes (immutable per `ref`). Lives in Caches, so iOS may purge it.
enum V4LocalCache {
    static let conversationRowLimit = 300
    private static let conversationFileLimit = 40
    private static let conversationMaxBytes = 12 * 1024 * 1024
    private static let attachmentBudgetBytes = 200 * 1024 * 1024
    private static let maxAge: TimeInterval = 30 * 24 * 3600

    private static let queue = DispatchQueue(label: "ai.zcode.mobile.v4-cache", qos: .utility)

    /// Carries JSON dictionaries across the IO queue; they are never mutated after being handed over.
    private final class Box: @unchecked Sendable {
        let value: [String: Any]
        init(_ value: [String: Any]) { self.value = value }
    }

    static func key(_ parts: String...) -> String {
        SHA256.hash(data: Data(parts.joined(separator: "\u{1F}").utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func directory(_ name: String) -> URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let url = base.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static var conversationsDir: URL? { directory("ZCodeConversations") }
    private static var attachmentsDir: URL? { directory("ZCodeAttachments") }

    // MARK: Conversations

    static func saveConversation(_ payload: [String: Any], key: String) {
        let box = Box(payload)
        queue.async {
            guard let dir = conversationsDir, JSONSerialization.isValidJSONObject(box.value),
                  let data = try? JSONSerialization.data(withJSONObject: box.value) else { return }
            let url = dir.appendingPathComponent(key + ".json")
            guard data.count <= conversationMaxBytes else {
                try? FileManager.default.removeItem(at: url)
                return
            }
            try? data.write(to: url, options: .atomic)
            prune(dir, keepNewest: conversationFileLimit, budgetBytes: nil)
        }
    }

    static func loadConversation(key: String) async -> [String: Any]? {
        let box: Box? = await withCheckedContinuation { continuation in
            queue.async {
                guard let url = conversationsDir?.appendingPathComponent(key + ".json"),
                      let data = try? Data(contentsOf: url),
                      let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    continuation.resume(returning: nil)
                    return
                }
                try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
                continuation.resume(returning: Box(object))
            }
        }
        return box?.value
    }

    static func removeConversation(key: String) {
        queue.async {
            guard let url = conversationsDir?.appendingPathComponent(key + ".json") else { return }
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: Attachments

    static func saveAttachment(_ data: Data, mimeType: String, key: String) {
        queue.async {
            guard let dir = attachmentsDir else { return }
            try? data.write(to: dir.appendingPathComponent(key + ".bin"), options: .atomic)
            try? Data(mimeType.utf8).write(to: dir.appendingPathComponent(key + ".mime"), options: .atomic)
            prune(dir, keepNewest: nil, budgetBytes: attachmentBudgetBytes)
        }
    }

    static func loadAttachment(key: String) async -> (data: Data, mimeType: String)? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard let dir = attachmentsDir,
                      let data = try? Data(contentsOf: dir.appendingPathComponent(key + ".bin")), !data.isEmpty,
                      let mime = try? String(contentsOf: dir.appendingPathComponent(key + ".mime"), encoding: .utf8) else {
                    continuation.resume(returning: nil)
                    return
                }
                try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: dir.appendingPathComponent(key + ".bin").path)
                continuation.resume(returning: (data, mime))
            }
        }
    }

    // MARK: Housekeeping

    /// Drops entries older than `maxAge`, then the least recently used ones beyond the count or byte budget.
    private static func prune(_ dir: URL, keepNewest: Int?, budgetBytes: Int?) {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys) else { return }
        let entries = files.compactMap { url -> (url: URL, date: Date, size: Int)? in
            guard url.pathExtension != "mime", let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return (url, values.contentModificationDate ?? .distantPast, values.fileSize ?? 0)
        }.sorted { $0.date > $1.date }
        var total = 0
        for (index, entry) in entries.enumerated() {
            total += entry.size
            let expired = Date().timeIntervalSince(entry.date) > maxAge
            let overCount = keepNewest.map { index >= $0 } ?? false
            let overBudget = budgetBytes.map { total > $0 } ?? false
            guard expired || overCount || overBudget else { continue }
            try? FileManager.default.removeItem(at: entry.url)
            if entry.url.pathExtension == "bin" {
                try? FileManager.default.removeItem(at: entry.url.deletingPathExtension().appendingPathExtension("mime"))
            }
        }
    }
}
