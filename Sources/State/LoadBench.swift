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

    /// Forced `project.readTree` failures, to exercise the slow-link fallbacks.
    static var failTreeLoads = 0
    static func consumeTreeFailure() -> Bool {
        guard failTreeLoads > 0 else { return false }
        failTreeLoads -= 1
        mark("readTree forced failure")
        return true
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
            for path in (LoadBench.environment["ZCM_BENCH_PREVIEW"] ?? "").split(separator: "|").map(String.init) {
                for attempt in 0..<2 {
                    let tab = self.openPreviewTab(path: path)
                    if var existing = self.previewTabs.tab(id: tab.id) {
                        existing.binaryData = nil
                        self.previewTabs.replace(existing)
                    }
                    LoadBench.mark("preview \(attempt) begin \(path)")
                    let begin = Date()
                    let poll = Task { @MainActor in
                        while !Task.isCancelled {
                            if self.previewTabs.tab(id: tab.id)?.binaryData != nil {
                                LoadBench.mark("preview \(attempt) visible after \(Int(Date().timeIntervalSince(begin) * 1000))ms")
                                return
                            }
                            try? await Task.sleep(nanoseconds: 10_000_000)
                        }
                    }
                    await self.loadPreviewTabContentIfNeeded(id: tab.id)
                    poll.cancel()
                    let loaded = self.previewTabs.tab(id: tab.id)
                    LoadBench.mark("preview \(attempt) end bytes=\(loaded?.binaryData?.count ?? -1) error=\(loaded?.errorMessage ?? "-")")
                }
            }
            let refreshes = Int(LoadBench.environment["ZCM_BENCH_REFRESH"] ?? "") ?? 0
            for round in 0..<refreshes {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                LoadBench.failTreeLoads = 1
                let kind = round % 2 == 0 ? "pull-to-refresh" : "resume-resync"
                LoadBench.mark("refresh \(round) \(kind) begin tasks=\(self.sidebarVisibleTasks.count) tree=\(self.sidebarTreeLoaded)")
                var lowest = self.sidebarVisibleTasks.count
                let watch = Task { @MainActor in
                    while !Task.isCancelled {
                        lowest = min(lowest, self.sidebarVisibleTasks.count)
                        try? await Task.sleep(nanoseconds: 20_000_000)
                    }
                }
                if round % 2 == 0 {
                    await self.refreshWorkspaceAndSessions()
                } else {
                    await self.loadAllWorkspaceTasks(preferredActiveTaskId: nil)
                }
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                watch.cancel()
                LoadBench.mark("refresh \(round) end tasks=\(self.sidebarVisibleTasks.count) lowest=\(lowest) tree=\(self.sidebarTreeLoaded)")
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                LoadBench.mark("refresh \(round) +3s tasks=\(self.sidebarVisibleTasks.count) tree=\(self.sidebarTreeLoaded) active=\(self.activeSessionId)")
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
