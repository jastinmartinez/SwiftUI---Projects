/// Represents the active position within a playback queue.
struct PlaybackQueuePosition: Equatable {
    let entryIDs: [String]
    let currentEntryID: String?

    /// Reports whether the current entry has a neighbor in the requested direction.
    ///
    /// - Parameter direction: The direction requested from the active queue.
    /// - Returns: `true` only when the queue can move to a different entry.
    func canTransition(_ direction: PlaybackNavigationDirection) -> Bool {
        guard let currentEntryID,
            let currentIndex = entryIDs.firstIndex(of: currentEntryID)
        else {
            return false
        }

        switch direction {
        case .previous:
            return currentIndex > entryIDs.startIndex
        case .next:
            return entryIDs.index(after: currentIndex) < entryIDs.endIndex
        }
    }
}
