import Foundation

/// Raw values match the `arrangement` value in the Dock's `persistent-others` preferences.
public enum StackArrangement: Int {
    case name = 1, dateAdded, dateModified, dateCreated, kind
}

public struct StackItem: Equatable {
    public let url: URL
    public let added: Date?
    public let modified: Date?
    public let created: Date?

    public init(url: URL, added: Date?, modified: Date?, created: Date?) {
        self.url = url
        self.added = added
        self.modified = modified
        self.created = created
    }
}

public enum StackOrder {
    /// The items a stack tile shows, front first.
    public static func front(_ items: [StackItem], arrangement: StackArrangement, count: Int = 3) -> [StackItem] {
        let visible = items.filter { !$0.url.lastPathComponent.hasPrefix(".") }
        func byName(_ a: StackItem, _ b: StackItem) -> Bool {
            a.url.lastPathComponent.localizedStandardCompare(b.url.lastPathComponent) == .orderedAscending
        }
        let date: ((StackItem) -> Date?)?
        switch arrangement {
        case .dateAdded: date = { $0.added }
        case .dateModified: date = { $0.modified }
        case .dateCreated: date = { $0.created }
        case .name, .kind: date = nil
        }
        let sorted = visible.sorted { a, b in
            guard let date else { return byName(a, b) }
            let da = date(a) ?? .distantPast, db = date(b) ?? .distantPast
            return da == db ? byName(a, b) : da > db
        }
        return Array(sorted.prefix(count))
    }
}
