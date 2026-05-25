import Foundation

func currentBlockTab(from titles: [String]) -> String? {
    let regex = /^Block\s*-?\s*(\d+)$/
    var best: (number: Int, title: String)?
    for title in titles {
        guard let m = title.wholeMatch(of: regex), let n = Int(m.1) else { continue }
        if best == nil || n > best!.number { best = (n, title) }
    }
    return best?.title
}
