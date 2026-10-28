/// What macOS's own charge limit must be for Chargectl to hold a given limit. macOS has no 100%
/// limit: asking PowerUIAgent for 100% switches the limit off ("Charge limit was disabled"), and
/// switching it back on restores its 80% default. So 100% means off.
nonisolated enum MacOSLimitTarget {
    static func isMet(by isEnabled: Bool, at current: Int, for limit: Int) -> Bool {
        limit >= ChargePolicy.macOSLimitRange.upperBound ? !isEnabled : isEnabled && current == limit
    }
}
