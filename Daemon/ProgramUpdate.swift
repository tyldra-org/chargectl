import Foundation
import Security

/// Puts a new copy of the helper where launchd runs it, for a plist install. The copy is made
/// first and checked second: the source sits in the user's app bundle and could change between a
/// check and a copy, the copy in a root-owned folder cannot.
nonisolated enum ProgramUpdate {
    enum Failure: Error, Equatable, CustomStringConvertible {
        case copy(String)
        case signature(String)

        var description: String {
            switch self {
            case .copy(let reason): "could not copy the helper: \(reason)"
            case .signature(let reason): "the new helper is not signed by Chargectl: \(reason)"
            }
        }
    }

    /// Copies source to destination through a staging file next to it.
    /// - Parameter requirement: a code requirement the copy must satisfy, or nil to take it as is.
    static func install(from source: String, to destination: String, requirement: String?) throws {
        let files = FileManager.default
        let staging = destination + ".new"
        try? files.removeItem(atPath: staging)
        do {
            try files.copyItem(atPath: source, toPath: staging)
        } catch {
            throw Failure.copy(error.localizedDescription)
        }
        do {
            var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o755]
            if getuid() == 0 {
                attributes[.ownerAccountID] = 0
                attributes[.groupOwnerAccountID] = 0
            }
            do {
                try files.setAttributes(attributes, ofItemAtPath: staging)
            } catch {
                throw Failure.copy(error.localizedDescription)
            }
            if let requirement { try check(staging, against: requirement) }
            guard rename(staging, destination) == 0 else { throw Failure.copy(String(cString: strerror(errno))) }
        } catch {
            try? files.removeItem(atPath: staging)
            throw error
        }
    }

    /// Throws unless the code at path is intact and satisfies requirement.
    static func check(_ path: String, against requirement: String) throws {
        var code: SecStaticCode?
        var compiled: SecRequirement?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess, let code
        else { throw Failure.signature("unreadable") }
        guard SecRequirementCreateWithString(requirement as CFString, [], &compiled) == errSecSuccess, let compiled
        else { throw Failure.signature("invalid requirement") }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate)
        let status = SecStaticCodeCheckValidity(code, flags, compiled)
        guard status == errSecSuccess else {
            throw Failure.signature(SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)")
        }
    }
}
