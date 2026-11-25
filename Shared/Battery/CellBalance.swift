import Foundation

/// How far apart the battery's cells are. Cells in series should sit within a few millivolts of
/// each other at rest; a gap that stays wide often comes before a cell fails, well before the
/// capacity shows it.
nonisolated enum CellBalance {
    /// mV apart, at rest, worth a warning.
    static let warningSpread = 60
    /// A; below this the battery counts as at rest. Under load the cells read further apart.
    static let restCurrent = 0.2
    /// Readings at rest in a row, one a second, before the warning shows.
    static let warningReadings = 60

    /// mV between the highest and lowest cell; nil with fewer than two cells.
    static func spread(_ cells: [Int]?) -> Int? {
        guard let cells, cells.count >= 2, let high = cells.max(), let low = cells.min() else { return nil }
        return high - low
    }

    /// The count of wide readings at rest so far, after this reading. Readings under load leave it
    /// as it is; a narrow reading at rest starts it again.
    static func wideReadings(after count: Int, cells: [Int]?, current: Double) -> Int {
        guard let spread = spread(cells), abs(current) < restCurrent else { return count }
        return spread >= warningSpread ? count + 1 : 0
    }
}
