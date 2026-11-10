import Foundation

/// Remembers where the cursor was when the panel opened, so Insert can tell whether it has moved since.
struct InsertionTarget<Element> {
    private var remembered: (processID: pid_t, element: Element)?
    private let isSame: (Element, Element) -> Bool

    init(isSame: @escaping (Element, Element) -> Bool) {
        self.isSame = isSame
    }

    /// `element` is nil when the app doesn't say what has focus. Nothing can be compared then.
    mutating func remember(_ element: Element?, processID: pid_t) {
        remembered = element.map { (processID, $0) }
    }

    /// False once, when the focus is known to have moved. The new place is then remembered,
    /// so asking again confirms it.
    mutating func confirm(_ current: Element?, processID: pid_t) -> Bool {
        guard let remembered, remembered.processID == processID, let current else { return true }
        if isSame(remembered.element, current) { return true }
        self.remembered = (processID, current)
        return false
    }
}
