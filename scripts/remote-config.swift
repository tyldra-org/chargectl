// Signs the remote config file the apps read (feed/app.json), with an Ed25519 key kept in the
// maintainer's login Keychain. The apps carry the public key and ignore a file whose signature
// doesn't check out.
//
//   swift scripts/remote-config.swift keygen          make the key once; prints the public key
//   swift scripts/remote-config.swift public-key      print the public key again
//   swift scripts/remote-config.swift sign <file>     write <file>.sig
//   swift scripts/remote-config.swift verify <file> <public-key>
//
// The private key never leaves the Keychain except into this process, and is never printed.
import CryptoKit
import Foundation

let service = "tyldra.remote-config"
let account = "ed25519"

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("remote-config: \(message)\n".utf8))
  exit(1)
}

/// Runs /usr/bin/security with `input` on stdin; returns stdout.
@discardableResult
func security(_ arguments: [String], input: String? = nil) -> (status: Int32, output: String) {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
  process.arguments = arguments
  let output = Pipe()
  process.standardOutput = output
  process.standardError = FileHandle.nullDevice
  let stdin = Pipe()
  if input != nil { process.standardInput = stdin }
  do { try process.run() } catch { fail("couldn't run security: \(error)") }
  if let input {
    stdin.fileHandleForWriting.write(Data(input.utf8))
    try? stdin.fileHandleForWriting.close()
  }
  let data = (try? output.fileHandleForReading.readToEnd()) ?? Data()
  process.waitUntilExit()
  return (process.terminationStatus, String(decoding: data, as: UTF8.self))
}

func storedKey() -> Curve25519.Signing.PrivateKey? {
  let result = security(["find-generic-password", "-s", service, "-a", account, "-w"])
  guard result.status == 0,
    let raw = Data(base64Encoded: result.output.trimmingCharacters(in: .whitespacesAndNewlines))
  else { return nil }
  return try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
}

func publicKey(_ key: Curve25519.Signing.PrivateKey) -> String {
  key.publicKey.rawRepresentation.base64EncodedString()
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "keygen":
  if storedKey() != nil { fail("a key already exists; print it with public-key") }
  let key = Curve25519.Signing.PrivateKey()
  // On stdin, through security -i, so the key never appears in a process list.
  let line = "add-generic-password -a \(account) -s \(service) -l \"tyldra remote config signing key\" -w \"\(key.rawRepresentation.base64EncodedString())\"\n"
  let result = security(["-i"], input: line)
  guard result.status == 0, storedKey() != nil else { fail("couldn't save the key in the login Keychain") }
  print(publicKey(key))
case "public-key":
  guard let key = storedKey() else { fail("no key in the login Keychain; run keygen") }
  print(publicKey(key))
case "sign":
  guard arguments.count == 2 else { fail("usage: sign <file>") }
  guard let key = storedKey() else { fail("no key in the login Keychain; run keygen") }
  let url = URL(fileURLWithPath: arguments[1])
  guard let data = try? Data(contentsOf: url) else { fail("can't read \(arguments[1])") }
  guard (try? JSONSerialization.jsonObject(with: data)) != nil else { fail("\(arguments[1]) isn't valid JSON") }
  let signature = try key.signature(for: data).base64EncodedString()
  try Data((signature + "\n").utf8).write(to: url.appendingPathExtension("sig"))
  print("Signed \(arguments[1]) with \(publicKey(key))")
case "verify":
  guard arguments.count == 3 else { fail("usage: verify <file> <public-key>") }
  let url = URL(fileURLWithPath: arguments[1])
  guard let data = try? Data(contentsOf: url),
    let signatureText = try? String(contentsOf: url.appendingPathExtension("sig"), encoding: .utf8),
    let signature = Data(base64Encoded: signatureText.trimmingCharacters(in: .whitespacesAndNewlines)),
    let keyData = Data(base64Encoded: arguments[2]),
    let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
    key.isValidSignature(signature, for: data)
  else { fail("\(arguments[1]) doesn't match its signature") }
  print("\(arguments[1]) is signed by \(arguments[2])")
default:
  fail("usage: keygen | public-key | sign <file> | verify <file> <public-key>")
}
