import ApplicationServices

enum AX {
    static func value<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    /// Several attributes in one round trip. Missing attributes come back as error placeholders, never as a shorter array.
    static func values(_ element: AXUIElement, _ names: [String]) -> [Any]? {
        var out: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, names as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &out) == .success,
              let list = out as? [Any], list.count == names.count else { return nil }
        return list
    }

    static func point(_ value: Any) -> CGPoint? {
        guard CFGetTypeID(value as CFTypeRef) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    static func size(_ value: Any) -> CGSize? {
        guard CFGetTypeID(value as CFTypeRef) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }
}
