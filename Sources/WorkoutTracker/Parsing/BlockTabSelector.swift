import Foundation

func currentBlockTab(from titles: [String]) -> String? {
    var best: (number: Int, title: String)?
    for title in titles {
        guard let n = blockNumber(from: title) else { continue }
        if let currentBest = best {
            if n > currentBest.number { best = (n, title) }
        } else {
            best = (n, title)
        }
    }
    return best?.title
}

/// Block tabs other than the current one, newest first. Given a resume cursor naming a Block tab, only
/// the tabs deeper than it: everything at or newer than the cursor is already on device.
func sortedHistoricalTabs(
    from titles: [String],
    excluding currentTab: String,
    deeperThan cursorTab: String? = nil
) -> [String] {
    let cursorNumber = cursorTab.flatMap(blockNumber(from:)) ?? .max
    return titles.compactMap { title -> (number: Int, title: String)? in
        guard title != currentTab, let number = blockNumber(from: title), number < cursorNumber else { return nil }
        return (number, title)
    }
    .sorted { $0.number > $1.number }
    .map(\.title)
}

func blockNumber(from title: String) -> Int? {
    let regex = /^Block\s*-?\s*(\d+)$/
    guard let match = title.wholeMatch(of: regex) else { return nil }
    return Int(match.1)
}
