import Foundation

/// Debug-only load timing harness. Inert unless launched with `ZCM_BENCH_URL` + `ZCM_BENCH_TOKEN`;
/// release builds compile every hook to a no-op.
@MainActor
enum LoadBench {
    #if DEBUG
    static let environment = ProcessInfo.processInfo.environment
    static var enabled: Bool { environment["ZCM_BENCH_URL"] != nil }
    private static var start = Date()
    private static var lines: [String] = []
    /// Sessions whose conversation reflects host data (fresh snapshot or a confirmed resume).
    static var live: Set<String> = []

    static var logURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("zcm-bench.log")
    }

    static func reset() {
        start = Date()
        lines.removeAll()
        live.removeAll()
    }

    static func mark(_ event: String) {
        guard enabled else { return }
        let line = "\(Int(Date().timeIntervalSince(start) * 1000))\t\(event)"
        lines.append(line)
        try? (lines.joined(separator: "\n") + "\n").write(to: logURL, atomically: true, encoding: .utf8)
    }

    static func noteLive(_ sessionId: String, _ how: String) {
        guard enabled, !live.contains(sessionId) else { return }
        live.insert(sessionId)
        mark("live-\(how) \(sessionId)")
    }

    nonisolated static func markAsync(_ event: String) {
        Task { @MainActor in mark(event) }
    }
    #else
    static func mark(_ event: String) {}
    nonisolated static func markAsync(_ event: String) {}
    static func noteLive(_ sessionId: String, _ how: String) {}
    #endif
}

#if DEBUG
extension AppStore {
    func runLoadBenchIfRequested() {
        guard let url = LoadBench.environment["ZCM_BENCH_URL"],
              let token = LoadBench.environment["ZCM_BENCH_TOKEN"], !token.isEmpty else { return }
        let titles = (LoadBench.environment["ZCM_BENCH_TITLES"] ?? "").split(separator: "|").map(String.init)
        Task { @MainActor in
            LoadBench.reset()
            LoadBench.mark("start")
            // The simulator keychain may reject writes, so the relay token rides on the pairing URL instead.
            var components = URLComponents(string: url)
            let items = (components?.queryItems ?? []) + [URLQueryItem(name: "remoteControlToken", value: token)]
            components?.queryItems = items
            _ = await self.addAndConnect(rawURLOrInput: components?.string ?? url, token: token)
            LoadBench.mark("connected page=\(self.mobilePage) active=\(self.activeSessionId) phase=\(self.pairingPhase) conns=\(self.connections.count)")
            await self.benchWaitForContent(self.activeSessionId, label: "initial")
            for title in titles {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard let session = self.sessions.first(where: { $0.title.hasPrefix(title) }) else {
                    LoadBench.mark("missing \(title)")
                    continue
                }
                let sameBridge = await self.rpcClient.currentBridge()?.workspaceKey
                    == ZCodeRPCClient.resolveWorkspaceKey(workspacePath: session.workspacePath, workspaceIdentity: session.workspaceIdentity ?? self.workspaceIdentityByPath[session.workspacePath])
                LoadBench.live.remove(session.id)
                LoadBench.mark("select \(title) sameWorkspace=\(sameBridge) cachedMsgs=\(session.messages.count)")
                self.selectSession(session)
                await self.benchWaitForContent(session.id, label: title)
            }
            LoadBench.mark("done")
        }
    }

    private func benchWaitForContent(_ sessionId: String, label: String) async {
        let begin = Date()
        var shown = false
        while Date().timeIntervalSince(begin) < 30 {
            if !shown, v4Sync.conversation?.sessionId == sessionId,
               let session = sessions.first(where: { $0.id == sessionId }), !session.messages.isEmpty {
                shown = true
                LoadBench.mark("shown \(label) msgs=\(session.messages.count)")
            }
            if LoadBench.live.contains(sessionId), shown {
                LoadBench.mark("ready \(label)")
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        LoadBench.mark("timeout \(label) shown=\(shown)")
    }
}
#endif
