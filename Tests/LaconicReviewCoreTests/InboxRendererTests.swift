import Foundation
import Testing
@testable import LaconicReviewCore

@Suite("InboxRenderer")
struct InboxRendererTests {

    let inbox = Inbox(
        iid: 1263,
        title: "FPM-1856: swift-pjsip 0.6.0",
        webURL: "http://git.flat.lab/FP/partner-ios/-/merge_requests/1263",
        branch: "imp/swift-pjsip-0-6-0/FPM-1856",
        fetchedAt: Date(timeIntervalSince1970: 1_761_847_200), // fixed instant — stable output
        threads: [
            DiscussionThread(
                id: "6a9c1750b37d513a43987b574953fceb50b03ce7",
                individualNote: false,
                resolvable: true,
                resolved: false,
                notes: [
                    ThreadNote(
                        id: 101,
                        author: "Лавров",
                        username: "s.lavrov",
                        createdAt: Date(timeIntervalSince1970: 1_761_840_000),
                        body: "Раньше был try-catch. Хорошо бы добавить логирование.",
                        position: Position(file: "flat-ios/SIP/SipService.swift", line: 329, lineType: .new)
                    ),
                    ThreadNote(
                        id: 102,
                        author: "Павел Бухштаб",
                        username: "p.bukhshtab",
                        createdAt: nil,
                        body: "Сделано.",
                        position: nil
                    ),
                ]
            ),
            DiscussionThread(
                id: "deadbeef",
                individualNote: true,
                resolvable: false,
                resolved: false,
                notes: [
                    ThreadNote(
                        id: 103,
                        author: "Лавров",
                        username: "s.lavrov",
                        createdAt: nil,
                        body: "approved",
                        position: nil
                    ),
                ]
            ),
        ]
    )

    @Test("emits one inbox anchor with counts")
    func inboxAnchor() {
        let md = InboxRenderer.render(inbox)
        #expect(md.contains("<!-- inbox iid=1263 branch=imp/swift-pjsip-0-6-0/FPM-1856"))
        #expect(md.contains("open=1 resolved=0 -->"))
    }

    @Test("thread anchors carry id, number, state and diff position")
    func threadAnchor() {
        let md = InboxRenderer.render(inbox)
        #expect(md.contains(
            "<!-- thread id=6a9c1750b37d513a43987b574953fceb50b03ce7 no=1 state=open resolvable=true "
            + "file=flat-ios/SIP/SipService.swift line=329 line_type=new -->"
        ))
        #expect(md.contains("<!-- thread id=deadbeef no=2 state=note resolvable=false -->"))
    }

    @Test("notes render verbatim in order under T-headings")
    func notes() {
        let md = InboxRenderer.render(inbox)
        #expect(md.contains("### T1 · SipService.swift:329 — ⏳ open"))
        #expect(md.contains("**Лавров** (@s.lavrov), 2025-10-30 16:00 UTC:"))
        #expect(md.contains("Раньше был try-catch. Хорошо бы добавить логирование."))
        #expect(md.contains("### T2 · general — 💬 note"))
        // First note before second within the thread.
        let t1 = md.range(of: "try-catch")
        let t2 = md.range(of: "Сделано.")
        #expect(t1 != nil && t2 != nil && t1!.lowerBound < t2!.lowerBound)
    }

    @Test("counts: open counts resolvable-and-unresolved only")
    func counts() {
        #expect(inbox.openCount == 1)
        #expect(inbox.resolvedCount == 0)
        #expect(inbox.threads[0].position?.file == "flat-ios/SIP/SipService.swift")
    }
}
