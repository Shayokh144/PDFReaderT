import UIKit

/// Derives a dictionary headword from a PDF text selection string.
enum PDFWordSelection {
    /// Returns a Define term when the selection is a Word Selection; otherwise `nil`.
    static func defineTerm(from selectedText: String) -> String? {
        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = trimmed.trimmingCharacters(in: .punctuationCharacters)
        guard !stripped.isEmpty else {
            return nil
        }
        guard stripped.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            return nil
        }
        return stripped
    }
}

enum PDFSelectionMenu {
    static let defineActionIdentifier = UIAction.Identifier("pdf_reader.define")

    /// Drops system Look Up / Define items so the menu can add our Define action.
    static func removingSystemLookup(from elements: [UIMenuElement]) -> [UIMenuElement] {
        elements.compactMap(removingSystemLookup(from:))
    }

    private static func removingSystemLookup(from element: UIMenuElement) -> UIMenuElement? {
        if let menu = element as? UIMenu {
            if isSystemLookupMenu(menu) {
                return nil
            }
            let children = removingSystemLookup(from: menu.children)
            if children.isEmpty {
                return nil
            }
            if children.count == menu.children.count {
                return menu
            }
            return menu.replacingChildren(children)
        }

        if let command = element as? UICommand, isSystemLookupCommand(command) {
            return nil
        }

        if let action = element as? UIAction, isSystemLookupAction(action) {
            return nil
        }

        return element
    }

    private static func isSystemLookupMenu(_ menu: UIMenu) -> Bool {
        menu.identifier == .lookup || isLookupIdentifier(menu.identifier.rawValue)
    }

    private static func isSystemLookupCommand(_ command: UICommand) -> Bool {
        isLookupSelector(command.action) || isLookupIdentifier(command.propertyList as? String)
    }

    private static func isSystemLookupAction(_ action: UIAction) -> Bool {
        action.identifier != defineActionIdentifier && isLookupIdentifier(action.identifier.rawValue)
    }

    private static func isLookupSelector(_ selector: Selector?) -> Bool {
        guard let selector else {
            return false
        }
        switch NSStringFromSelector(selector) {
        case "_define:", "_lookup:", "define:", "lookup:":
            return true
        default:
            return false
        }
    }

    private static func isLookupIdentifier(_ rawValue: String?) -> Bool {
        guard let rawValue else {
            return false
        }
        let lowered = rawValue.lowercased()
        return lowered.contains("lookup") || lowered.contains("define")
    }
}
