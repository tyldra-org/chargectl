import Foundation
import Testing

/// The Library items Uninstall removes, the shell scripts that remove them, and the cask's zap,
/// which must all name the same things.
@Suite struct UninstallCleanupTests {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    /// An item as the scripts write it: "$lib/Containers/$widgets".
    private func scripted(_ item: String) -> String {
        "$lib/"
            + item.replacingOccurrences(of: UninstallCleanup.widgetsIdentifier, with: "$widgets")
            .replacingOccurrences(of: UninstallCleanup.bundleIdentifier, with: "$id")
    }

    @Test func filesScriptRemovesEveryLibraryItem() {
        for item in UninstallCleanup.libraryItems {
            #expect(UninstallCleanup.files.contains(scripted(item)), "\(item) is not in UninstallCleanup.files")
        }
    }

    @Test func caskZapListsEveryLibraryItem() throws {
        let cask = try String(contentsOf: Self.root.appendingPathComponent("scripts/cask.sh"), encoding: .utf8)
        for item in UninstallCleanup.libraryItems {
            #expect(cask.contains("\"~/Library/\(item)\""), "\(item) is not in the cask's zap")
        }
    }

    @Test func widgetIdentifiersMatch() {
        #expect(UninstallCleanup.widgetsIdentifier == DaemonIdentity.widgetsIdentifier)
        #expect(UninstallCleanup.bundleIdentifier == DaemonIdentity.appIdentifier)
    }

    @Test func uninstallAndAppDeletionRemoveTheFiles() {
        #expect(UninstallCleanup.script.contains(UninstallCleanup.files))
        #expect(UninstallCleanup.script.contains(UninstallCleanup.trash))
        #expect(UninstallCleanup.afterAppDeleted.contains(UninstallCleanup.files))
        // A copy in the Trash after a drag to the Trash is the user's to put back.
        #expect(!UninstallCleanup.afterAppDeleted.contains(UninstallCleanup.trash))
    }

    @Test(arguments: ["script", "afterAppDeleted"])
    func scriptsAreValidShell(_ name: String) throws {
        let script = name == "script" ? UninstallCleanup.script : UninstallCleanup.afterAppDeleted
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-n", "-c", script]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    /// scripts/uninstall.sh reads its cleanup out of this file by section name.
    @Test func uninstallScriptReadsThisFile() throws {
        let script = try String(
            contentsOf: Self.root.appendingPathComponent("scripts/uninstall.sh"), encoding: .utf8)
        #expect(script.contains("Shared/UninstallCleanup.swift"))
        for section in ["files", "trash", "dock", "homebrew"] {
            #expect(script.contains("$(section \(section))"))
        }
    }
}
