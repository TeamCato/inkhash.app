import Foundation
import KennelKit
import XCTest
@testable import InkhashCore

/// „Übernehmen“ after connecting, the storages and the status line (ADR 0077, teamCato ADR 0009).
final class TakeOverTests: XCTestCase {
    private let account = "acc"
    private let storages = KennelStorages.summaries([
        KennelStorage(id: "nas", name: "NAS", driver: "smb", scope: .household, kinds: ["blobs"], modules: ["inkhash"]),
    ])

    func testPrivatGoesToTheStandardStorageAndTheRestStaysHere() {
        let privat = TakeOverLocal(id: UUID(), name: "Privat", isEmpty: false)
        let einkauf = TakeOverLocal(id: UUID(), name: "Einkauf", isEmpty: false)
        let arbeit = RemoteWorkspace(id: "w1", name: "Arbeit", sealed: false)
        let plan = TakeOverPlanner.plan(local: [privat, einkauf], remotes: [arbeit], storages: storages, accountID: account)

        XCTAssertEqual(plan.onDevice.map(\.title), ["Privat", "Einkauf"])
        XCTAssertEqual(plan.proposals["local:" + privat.id.uuidString.lowercased()], "kennel:standard")
        XCTAssertEqual(plan.proposals["local:" + einkauf.id.uuidString.lowercased()], "keep")
        XCTAssertEqual(plan.onDevice[0].choices.map(\.label), ["Nur hier lassen", "In Kennel · Standard", "In Kennel · NAS"])
        XCTAssertEqual(plan.inKennel.map(\.title), ["Arbeit"])
        XCTAssertEqual(plan.proposals["remote:w1"], "add")
        XCTAssertNil(plan.notice)
    }

    func testANamesakeOrTheFormerPartnerIsProposedToLink() {
        let formerID = UUID()
        let former = TakeOverLocal(id: formerID, name: "Notizen", isEmpty: false, boundKey: "acc/w2#1")
        let namesake = TakeOverLocal(id: UUID(), name: "privat", isEmpty: true)
        let remotes = [RemoteWorkspace(id: "main", name: "Privat"), RemoteWorkspace(id: "w2", name: "Alt", sealed: false)]
        let plan = TakeOverPlanner.plan(local: [former, namesake], remotes: remotes, storages: storages, accountID: account)

        XCTAssertEqual(plan.proposals["local:" + formerID.uuidString.lowercased()], "link:w2")
        XCTAssertEqual(plan.proposals["local:" + namesake.id.uuidString.lowercased()], "link:main")
        XCTAssertTrue(plan.onDevice[1].choices.contains { $0.label == "Mit „Privat“ abgleichen" })
        XCTAssertEqual(plan.inKennel.first?.subtitle, "Verschlüsselt, wird umgewandelt")
        XCTAssertNotNil(plan.notice, "says what happens with encrypted workspaces")
    }

    func testAnswersBecomeActionsWithoutDoubles() {
        let a = TakeOverLocal(id: UUID(), name: "A", isEmpty: false)
        let b = TakeOverLocal(id: UUID(), name: "B", isEmpty: false)
        let c = TakeOverLocal(id: UUID(), name: "C", isEmpty: false)
        let d = TakeOverLocal(id: UUID(), name: "D", isEmpty: false)
        let x = RemoteWorkspace(id: "x", name: "X", sealed: false)
        let y = RemoteWorkspace(id: "y", name: "Y", sealed: false)
        let z = RemoteWorkspace(id: "z", name: "Z", sealed: false)
        func key(_ local: TakeOverLocal) -> String { "local:" + local.id.uuidString.lowercased() }
        let chosen = [
            key(a): "kennel:nas", key(b): "kennel:standard", key(c): "link:x", key(d): "link:x",
            "remote:x": "add", "remote:y": "add", "remote:z": "later",
        ]
        let actions = TakeOverPlanner.actions(chosen: chosen, local: [a, b, c, d], remotes: [x, y, z])
        XCTAssertEqual(actions, [
            .place(a.id, storageID: "nas"),
            .place(b.id, storageID: nil),
            .link(c.id, remote: x),
            .add([y]),
        ])
    }

    func testLaterTakesNothing() {
        let a = TakeOverLocal(id: UUID(), name: "A", isEmpty: false)
        let actions = TakeOverPlanner.actions(
            chosen: ["local:" + a.id.uuidString.lowercased(): "keep", "remote:x": "later"], local: [a],
            remotes: [RemoteWorkspace(id: "x", name: "X")])
        XCTAssertEqual(actions, [])
    }

    func testStoragesCountTheirWorkspaces() {
        let remotes = [
            RemoteWorkspace(id: "1", name: "A", storageId: nil), RemoteWorkspace(id: "2", name: "B", storageId: "nas"),
            RemoteWorkspace(id: "3", name: "C", storageId: "nas"),
        ]
        let summaries = KennelStorages.summaries(
            [KennelStorage(id: "nas", name: "NAS", driver: "smb", scope: .private, kinds: ["blobs"], modules: ["inkhash"])],
            remotes: remotes)
        XCTAssertEqual(summaries.map(\.detail), ["Nur ich · 1 Workspace", "Nur ich · 2 Workspaces"])
        XCTAssertNil(KennelStorages.storageID("standard"))
        XCTAssertEqual(KennelStorages.storageID("nas"), "nas")
        XCTAssertEqual(KennelStorages.summaryID(of: remotes[0]), "standard")
    }

    // MARK: Status

    func testTheStatusLineSaysWhatMattersMost() {
        let date = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(KennelSyncState(phase: .synced(date)).status, .synced(date))
        XCTAssertEqual(KennelSyncState(phase: .idle).status, .checking)
        XCTAssertEqual(KennelSyncState(phase: .syncing).status, .syncing)
        XCTAssertEqual(KennelSyncState(phase: .unreachable).status, .unreachable)
        XCTAssertEqual(KennelSyncState(phase: .moduleOff).status, .moduleOff)
        XCTAssertEqual(KennelSyncState(phase: .failed("x")).status, .failed(detail: "x"))
        XCTAssertEqual(KennelSyncState(phase: .synced(date), sessionExpired: true).status, .signInAgain)
        XCTAssertEqual(KennelSyncState(phase: .moduleOff, sessionExpired: true).status, .signInAgain)
    }

    func testWaitingWorkspacesAskForAttention() {
        let date = Date(timeIntervalSince1970: 1_000)
        let waiting = KennelSyncState(phase: .synced(date), waitingForKey: ["Arbeit"])
        XCTAssertEqual(waiting.status, .attention(title: "Umwandeln", action: "Tresor öffnen …"))
        XCTAssertTrue(waiting.conversionText?.contains("„Arbeit“ ist noch verschlüsselt") == true)
        let kennel = KennelSyncState(phase: .synced(date), waitingForKennel: ["A", "B"])
        XCTAssertEqual(kennel.status, .attention(title: "Umwandeln", action: nil))
        XCTAssertTrue(kennel.conversionText?.hasPrefix("„A“ und „B“ warten auf Kennel") == true)
        XCTAssertEqual(KennelSyncState(phase: .unreachable, waitingForKey: ["A"]).status, .unreachable)
        XCTAssertNil(KennelSyncState(phase: .synced(date)).conversionText)
    }
}
