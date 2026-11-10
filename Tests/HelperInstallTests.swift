import Foundation
import Testing

/// The plist install that keeps launchd away from the user-writable copy of the helper, and the
/// checks that let an update replace the root-owned copy.
@Suite struct HelperInstallTests {
    @Test func launchdRunsTheRootOwnedCopy() {
        let plist = HelperInstall.plist(app: "/Applications/Chargectl.app")
        #expect(plist["Program"] == nil)
        #expect(
            plist["ProgramArguments"] as? [String]
                == [
                    "/Library/PrivilegedHelperTools/Chargectl Service", "--app",
                    "/Applications/Chargectl.app",
                ])
    }

    /// Login Items names the job after this file. A name with a dot, like the label, reads as a
    /// file type: Login Items showed "com.tyldra.chargectl.daemon" with a blank document icon.
    @Test func loginItemsShowsTheHelperAsChargectlService() {
        let program = URL(fileURLWithPath: HelperInstall.programPath)
        #expect(program.lastPathComponent == "Chargectl Service")
        #expect(program.pathExtension.isEmpty)
        #expect(HelperInstall.programPath != HelperInstall.legacyProgramPath)
    }

    @Test func installingAndRemovingDeleteTheLabelNamedCopy() {
        let legacy = HelperInstall.quote(HelperInstall.legacyProgramPath)
        #expect(HelperInstall.installCommand(app: "/Applications/Chargectl.app").contains("/bin/rm -f \(legacy) "))
        for file in HelperInstall.programFiles {
            #expect(HelperInstall.removeCommand.contains(HelperInstall.quote(file)))
        }
    }

    @Test func theInstallCommandIsValidShell() throws {
        let command = HelperInstall.installCommand(app: "/Applications/Chargectl's copy.app")
        #expect(try shell(["-n", "-c", command]).status == 0)
        #expect(
            command.contains("/usr/bin/ditto '/Applications/Chargectl'\\''s copy.app/Contents/MacOS/Chargectl Service'")
        )
        #expect(try shell(["-n", "-c", HelperInstall.removeCommand]).status == 0)
    }

    @Test func quotingKeepsAnyPathIntact() throws {
        for path in ["/Applications/Chargectl.app", "/Volumes/My Disk/It's here; rm -rf $HOME $(id)"] {
            #expect(try shell(["-c", "printf %s " + HelperInstall.quote(path)]).output == path)
        }
    }

    @Test func theBundledHelperBelongsToItsApp() {
        let program = HelperInstall.bundledProgram(app: "/Applications/Chargectl.app")
        #expect(program == "/Applications/Chargectl.app/Contents/MacOS/Chargectl Service")
        #expect(HelperInstall.app(containing: program) == "/Applications/Chargectl.app")
    }

    @Test func requirementsPinTheReleaseCertificate() {
        let hash = "9dbaf96294b53fd3bce51929a4ffcc3acbf92f07"
        #expect(
            DaemonIdentity.requirement(identifier: "com.tyldra.chargectl", certificate: hash)
                == #"identifier "com.tyldra.chargectl" and certificate leaf = H"9DBAF96294B53FD3BCE51929A4FFCC3ACBF92F07""#
        )
        let clients = #"(identifier "com.tyldra.chargectl" or identifier "com.tyldra.chargectl.widgets")"#
        #expect(
            DaemonIdentity.clientRequirement(team: nil, certificate: hash)
                == clients + #" and certificate leaf = H"9DBAF96294B53FD3BCE51929A4FFCC3ACBF92F07""#)
        #expect(DaemonIdentity.clientRequirement(team: nil, certificate: nil) == clients)
        #expect(DaemonIdentity.clientRequirement(team: "ABCDE12345", certificate: hash).contains("ABCDE12345"))
    }

    /// Nothing but 40 hex digits reaches a code requirement.
    @Test func malformedCertificatesAreIgnored() {
        for text in [
            "", "1234", #"9DBAF96294B53FD3BCE51929A4FFCC3ACBF92F0" or anchor apple"#, String(repeating: "G", count: 40),
        ] {
            #expect(DaemonIdentity.requirement(identifier: "com.tyldra.chargectl", certificate: text) == nil)
        }
    }

    // MARK: Program updates

    @Test func aSignedProgramReplacesTheInstalledOne() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let destination = folder.appendingPathComponent("helper").path
        try Data("old".utf8).write(to: URL(fileURLWithPath: destination))
        try ProgramUpdate.install(from: "/usr/bin/true", to: destination, requirement: "anchor apple")
        #expect(
            try Data(contentsOf: URL(fileURLWithPath: destination))
                == Data(contentsOf: URL(fileURLWithPath: "/usr/bin/true")))
        #expect(!FileManager.default.fileExists(atPath: destination + ".new"))
    }

    @Test func aProgramSignedByAnyoneElseIsRefused() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let destination = folder.appendingPathComponent("helper").path
        try Data("old".utf8).write(to: URL(fileURLWithPath: destination))
        let requirement =
            #"identifier "com.tyldra.chargectl.daemon" and certificate leaf = H"9DBAF96294B53FD3BCE51929A4FFCC3ACBF92F07""#
        #expect(throws: ProgramUpdate.Failure.self) {
            try ProgramUpdate.install(from: "/usr/bin/true", to: destination, requirement: requirement)
        }
        #expect(try Data(contentsOf: URL(fileURLWithPath: destination)) == Data("old".utf8))
        #expect(!FileManager.default.fileExists(atPath: destination + ".new"))
    }

    @Test func anUnsignedFileIsRefused() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("script").path
        try Data("#!/bin/sh\nid\n".utf8).write(to: URL(fileURLWithPath: source))
        #expect(throws: ProgramUpdate.Failure.self) {
            try ProgramUpdate.install(
                from: source, to: folder.appendingPathComponent("helper").path, requirement: "anchor apple")
        }
    }

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "HelperInstallTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func shell(_ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return (process.terminationStatus, output)
    }
}
