import XCTest
@testable import ZCode

@MainActor
final class ProjectTreeTests: XCTestCase {
    private func rawTask(_ id: String, projectId: Any = NSNull(), title: String = "", updated: Double, extra: [String: Any] = [:]) -> [String: Any] {
        var raw: [String: Any] = [
            "taskId": id, "title": title, "workspacePath": "/Users/me/code/app",
            "createdAt": updated - 1000, "updatedAt": updated, "status": "completed",
            "pinned": false, "archived": false, "projectId": projectId, "hostId": "local"
        ]
        for (k, v) in extra { raw[k] = v }
        return raw
    }

    func testTreeTaskKeepsEmptyTitleAndProjectAssignment() throws {
        let s = try XCTUnwrap(AppStore.treeTaskSession(from: rawTask("t1", projectId: "p1", updated: 1_700_000_000_000)))
        XCTAssertEqual(s.title, "")
        XCTAssertEqual(s.displayTitle, "New task")
        XCTAssertEqual(s.treeProjectId, "p1")
        XCTAssertTrue(s.inProjectTree)
        XCTAssertEqual(s.status, .idle)
        XCTAssertEqual(s.sidebarIndicator, .none)

        let loose = try XCTUnwrap(AppStore.treeTaskSession(from: rawTask("t2", updated: 1_700_000_000_000)))
        XCTAssertNil(loose.treeProjectId)
    }

    func testErrorUnreadAndChangeSummary() throws {
        let s = try XCTUnwrap(AppStore.treeTaskSession(from: rawTask("t1", updated: 1_700_000_000_000, extra: [
            "status": "error", "unreadAt": 1_700_000_000_500,
            "changeSummary": ["fileCount": 2, "added": 12, "removed": 3, "files": [["path": "a"], ["path": "b"]]],
            "cronAutomationId": "cron-1"
        ])))
        XCTAssertEqual(s.sidebarIndicator, .error, "error wins over unread")
        XCTAssertTrue(s.unread)
        XCTAssertEqual(s.changeAdded, 12)
        XCTAssertEqual(s.changeRemoved, 3)
        XCTAssertEqual(s.cronAutomationId, "cron-1")
    }

    func testSidebarSortPutsWorkingFirstThenUpdated() throws {
        var a = try XCTUnwrap(AppStore.treeTaskSession(from: rawTask("a", updated: 1_000_000)))
        let b = try XCTUnwrap(AppStore.treeTaskSession(from: rawTask("b", updated: 3_000_000)))
        let c = try XCTUnwrap(AppStore.treeTaskSession(from: rawTask("c", updated: 2_000_000)))
        a.status = .running
        XCTAssertEqual(AppStore.sortedForSidebar([b, c, a]).map(\.id), ["a", "b", "c"])
        XCTAssertEqual(AppStore.sortedForTimeline([a, c, b]).map(\.id), ["b", "c", "a"])
    }

    func testGroupTaskKeyMatchesDesktopJSON() throws {
        let s = try XCTUnwrap(AppStore.treeTaskSession(from: rawTask("t1", updated: 1)))
        XCTAssertEqual(AppStore.groupTaskKey(s), "[\"/Users/me/code/app\",\"t1\"]")
    }

    func testPendingTag() throws {
        var s = try XCTUnwrap(AppStore.treeTaskSession(from: rawTask("t1", updated: 1)))
        XCTAssertNil(s.pendingTagText)
        s.pendingInteractionCount = 1
        XCTAssertEqual(s.pendingTagText, "Awaiting approval")
        s.pendingInteractionCount = 3
        XCTAssertEqual(s.pendingTagText, "Awaiting approval · 3")
    }

    func testRelativeAgeAndTimelineBuckets() {
        let now = Date(timeIntervalSince1970: 1_763_900_000) // Sun 2025-11-23
        XCTAssertEqual(WorkspaceSidebarView.relativeAge(from: now.addingTimeInterval(-30), now: now), "now")
        XCTAssertEqual(WorkspaceSidebarView.relativeAge(from: now.addingTimeInterval(-5 * 60), now: now), "5m")
        XCTAssertEqual(WorkspaceSidebarView.relativeAge(from: now.addingTimeInterval(-3 * 3600), now: now), "3h")
        XCTAssertEqual(WorkspaceSidebarView.relativeAge(from: now.addingTimeInterval(-50 * 3600), now: now), "2d")

        XCTAssertEqual(WorkspaceSidebarView.timelineBucket(now, now: now), "Today")
        XCTAssertEqual(WorkspaceSidebarView.timelineBucket(now.addingTimeInterval(-86_400), now: now), "Yesterday")
        XCTAssertEqual(WorkspaceSidebarView.timelineBucket(now.addingTimeInterval(-2 * 86_400), now: now), "2 days ago")
        XCTAssertEqual(WorkspaceSidebarView.timelineBucket(now.addingTimeInterval(-400 * 86_400), now: now), "Older")
    }
}
