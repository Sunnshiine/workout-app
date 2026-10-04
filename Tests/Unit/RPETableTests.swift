import Testing

@testable import WorkoutTracker

private let chartColumns: [RPE] = [
    .ten, .ninePointFive, .nine, .eightPointFive, .eight, .sevenPointFive, .seven, .sixPointFive, .six
]

private let publishedRTSChart: [(reps: Int, percents: [Double])] = [
    (1, [100, 97.8, 95.5, 93.9, 92.2, 90.7, 89.2, 87.8, 86.3]),
    (2, [95.5, 93.9, 92.2, 90.7, 89.2, 87.8, 86.3, 85.0, 83.7]),
    (3, [92.2, 90.7, 89.2, 87.8, 86.3, 85.0, 83.7, 82.4, 81.1]),
    (4, [89.2, 87.8, 86.3, 85.0, 83.7, 82.4, 81.1, 79.9, 78.6]),
    (5, [86.3, 85.0, 83.7, 82.4, 81.1, 79.9, 78.6, 77.4, 76.2]),
    (6, [83.7, 82.4, 81.1, 79.9, 78.6, 77.4, 76.2, 75.1, 73.9]),
    (7, [81.1, 79.9, 78.6, 77.4, 76.2, 75.1, 73.9, 72.3, 70.7]),
    (8, [78.6, 77.4, 76.2, 75.1, 73.9, 72.3, 70.7, 69.4, 68.0]),
    (9, [76.2, 75.1, 73.9, 72.3, 70.7, 69.4, 68.0, 66.7, 65.3]),
    (10, [73.9, 72.3, 70.7, 69.4, 68.0, 66.7, 65.3, 64.0, 62.6]),
    (11, [70.7, 69.4, 68.0, 66.7, 65.3, 64.0, 62.6, 61.3, 59.9]),
    (12, [68.0, 66.7, 65.3, 64.0, 62.6, 61.3, 59.9, 58.6, 57.4])
]

@Test("Every cell of the RPE Table matches the published RTS chart", arguments: publishedRTSChart)
func rpeTableMatchesThePublishedRTSChart(row: (reps: Int, percents: [Double])) throws {
    #expect(row.percents.count == chartColumns.count)
    for (rpe, percent) in zip(chartColumns, row.percents) {
        let point = try #require(RPETablePoint(reps: row.reps, rpe: rpe))
        #expect(point.share == percent / 100, "\(row.reps) reps at RPE \(rpe.rawValue)")
    }
}
