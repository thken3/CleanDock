import Foundation
import Testing
@testable import CleanDockCore

private func item(_ name: String, added: Double? = nil, modified: Double? = nil, created: Double? = nil) -> StackItem {
    StackItem(url: URL(fileURLWithPath: "/tmp/stack/\(name)"),
              added: added.map(Date.init(timeIntervalSince1970:)),
              modified: modified.map(Date.init(timeIntervalSince1970:)),
              created: created.map(Date.init(timeIntervalSince1970:)))
}

private func names(_ items: [StackItem]) -> [String] { items.map(\.url.lastPathComponent) }

@Test func byNameUsesFinderOrdering() {
    let items = [item("b.txt"), item("File 10"), item("File 2"), item("a.txt")]
    #expect(names(StackOrder.front(items, arrangement: .name)) == ["a.txt", "b.txt", "File 2"])
}

@Test func kindFallsBackToName() {
    #expect(names(StackOrder.front([item("b"), item("a")], arrangement: .kind)) == ["a", "b"])
}

@Test func byDateNewestFirst() {
    let items = [item("old", added: 1, modified: 30, created: 2), item("new", added: 3, modified: 10, created: 1), item("mid", added: 2, modified: 20, created: 3)]
    #expect(names(StackOrder.front(items, arrangement: .dateAdded)) == ["new", "mid", "old"])
    #expect(names(StackOrder.front(items, arrangement: .dateModified)) == ["old", "mid", "new"])
    #expect(names(StackOrder.front(items, arrangement: .dateCreated)) == ["mid", "old", "new"])
}

@Test func missingDatesSortLastThenByName() {
    let items = [item("z"), item("a"), item("dated", added: 5)]
    #expect(names(StackOrder.front(items, arrangement: .dateAdded)) == ["dated", "a", "z"])
}

@Test func hiddenFilesAreSkipped() {
    #expect(names(StackOrder.front([item(".DS_Store"), item(".localized"), item("a")], arrangement: .name)) == ["a"])
}

@Test func atMostCountItems() {
    let items = (1...5).map { item("f\($0)") }
    #expect(StackOrder.front(items, arrangement: .name).count == 3)
    #expect(StackOrder.front(items, arrangement: .name, count: 1).count == 1)
    #expect(StackOrder.front([], arrangement: .name).isEmpty)
}
