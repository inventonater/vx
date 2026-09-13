import AppKit

/// Owns the temporary clipboard contents used to paste a transcription.
/// Preparation and restoration run on TextInserter's main queue.
final class TranscriptionPasteboard {
    private typealias Item = [(type: NSPasteboard.PasteboardType, data: Data)]

    private struct PendingRestore {
        let id = UUID()
        let items: [Item]
        let changeCount: Int
    }

    private let pasteboard: NSPasteboard
    private var pendingRestore: PendingRestore?

    init(pasteboard: NSPasteboard) {
        self.pasteboard = pasteboard
    }

    func prepare(_ text: String) throws -> () -> Void {
        let previousChangeCount = pasteboard.changeCount
        let original: [Item]
        if let pendingRestore, pendingRestore.changeCount == previousChangeCount {
            // A second dictation may arrive before the first restore callback.
            // Carry forward the original clipboard, rather than the earlier transcript.
            original = pendingRestore.items
        } else {
            original = try snapshot()
        }

        // Reading promised data may call another app and take time.
        guard pasteboard.changeCount == previousChangeCount else {
            throw TextInsertionError.clipboardChanged
        }

        let clearedChangeCount = pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            pendingRestore = nil
            restore(original, ifUnchangedSince: clearedChangeCount)
            throw TextInsertionError.clipboardUnavailable
        }

        // Keep the generation returned by our own write; a fresh read could observe
        // a newer external copy and incorrectly claim it as VX's clipboard contents.
        let pending = PendingRestore(items: original, changeCount: clearedChangeCount)
        pendingRestore = pending

        return { [self] in
            // An older callback must not restore over a newer insertion or clear its state.
            guard pendingRestore?.id == pending.id else { return }
            pendingRestore = nil
            restore(pending.items, ifUnchangedSince: pending.changeCount)
        }
    }

    private func snapshot() throws -> [Item] {
        let items = pasteboard.pasteboardItems ?? []
        guard !items.isEmpty || (pasteboard.types ?? []).isEmpty else {
            throw TextInsertionError.clipboardUnavailable
        }
        return try items.map { item in
            try item.types.map { type in
                guard let data = item.data(forType: type) else {
                    // Leave unreadable or unfulfilled promised contents in place.
                    throw TextInsertionError.clipboardUnavailable
                }
                return (type, data)
            }
        }
    }

    private func restore(_ snapshot: [Item], ifUnchangedSince changeCount: Int) {
        // Pasteboard items are bound to their original owner. Rebuild them from bytes
        // instead of retaining items that become invalid when the clipboard is cleared.
        let items = snapshot.map { representations in
            let item = NSPasteboardItem()
            for representation in representations {
                item.setData(representation.data, forType: representation.type)
            }
            return item
        }

        // A copy made after VX's write belongs to the user, even if its text is identical.
        guard pasteboard.changeCount == changeCount else { return }
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }
}
