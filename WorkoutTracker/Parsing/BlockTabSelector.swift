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

func sortedHistoricalTabs(from titles: [String], excluding currentTab: String) -> [String] {
    titles.compactMap { title -> (number: Int, title: String)? in
        guard title != currentTab, let number = blockNumber(from: title) else { return nil }
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
