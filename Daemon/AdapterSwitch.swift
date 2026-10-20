/// Connects and disconnects wall power through the first adapter key this Mac has.
struct AdapterSwitch {
    let key: String
    private let disconnected: UInt8
    private let smc: SMC

    init?(smc: SMC) {
        guard let candidate = AdapterKey.candidates.first(where: { smc.hasKey($0.key) }) else { return nil }
        key = candidate.key
        disconnected = candidate.disconnected
        self.smc = smc
    }

    func isConnected() throws -> Bool {
        try smc.read(key).bytes.allSatisfy { $0 == 0 }
    }

    func set(connected: Bool) throws {
        try smc.write(key, bytes: [connected ? 0 : disconnected])
    }
}
